#!/usr/bin/env python3
"""ablation.py - the eval harness's ablation mode.

Measures what withholding one instruction section does before anyone withholds
it for real. A case (scripts/ablation/cases/*.json) names the section by the
offload baseline's rule key, the deployed check that would guard it, an audit
pool, a fixture and the koto evidence that brings a fixture session to the
case's target state. Each repetition runs three arms in their own model
sessions: `full` (the plugin as shipped), `withheld` (a scratch copy with the
section cut) and `without_skill` (no plugin). A koto wrapper first on PATH
grades the target production with the deployed check and delivers the check's
failure message once, the way a gate refusing evidence would.

Nothing here edits a shipped file. Every copy lives under a scratch directory
whose name starts with `shirabe-ablation.`, which is also how a koto session
started by an ablation run is recognised as a fixture.

Subcommands:
  validate-case <case.json> [--case-id <id>]
  resolve-span <key> <commit>
  run [--withhold <key>] [--case <file>] [--case-id <id>] [--runs N] [--jobs J]
      [--out <records.jsonl>] [<skill>]
  smoke [--case <file>] [--case-id <id>]
  summarize <records.jsonl>
  check-figures [--dir <dir>]

Method, case format, check contract and limits:
docs/measurement/offload-ablation/README.md.

Exit codes: 0 success; 1 a failed check-figures comparison; 2 usage or a
refused case, key or run; 3 a missing prerequisite.
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

ABL_DIR = os.path.dirname(os.path.realpath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(ABL_DIR))
CASES_DIR = os.path.join(ABL_DIR, "cases")
CHECKS_DIR = os.path.join(ABL_DIR, "checks")
FIXTURES_DIR = os.path.join(ABL_DIR, "fixtures")
PLUGIN_PARTS = ("skills", "references", "scripts", ".claude-plugin")
ARMS = ("full", "withheld", "without_skill")
SCRATCH_PREFIX = "shirabe-ablation."
DELIVERY_SHAPE = "harness-check-message"

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{7,40}$")
KEY_RE = re.compile(r"^(?P<path>[A-Za-z0-9._/-]+)#(?:L(?P<start>[0-9]+)-L(?P<end>[0-9]+)|(?P<heading>[^\x00-\x1f]+))$")
WORKFLOW_RE = re.compile(r"^[a-z0-9_]{1,64}$")
TEMPLATE_RE = re.compile(r"^skills/[a-z0-9-]+/koto-templates/[a-z0-9-]+\.md$")
VAR_NAME_RE = re.compile(r"^[A-Z_]{1,32}$")
VAR_VALUE_RE = re.compile(r"^[A-Za-z0-9_.-]{0,64}$")
MODEL_RE = re.compile(r"^[a-z0-9.-]{1,64}$")
STATE_RE = re.compile(r"^[a-z0-9_]{1,64}$")
REASON_RE = re.compile(r"^[a-z0-9-]{1,40}$")
LIMIT_CAPS = {"max_turns": 80, "session_seconds": 1800, "check_seconds": 120}
TEXT_CAP = 2048

# Deny rules for the session's file tools under the home directory. They don't
# bind Bash, so leak detection, not these, is the control that matters.
HOME_DIRS = (".claude", ".ssh", ".config", ".koto", ".cache")
DENY_SETTINGS = {"permissions": {"deny": [f"Read(~/{d}/**)" for d in HOME_DIRS] +
                                 ["Edit(~/**)", "Write(~/**)"]}}


class Refusal(Exception):
    """A refused case, key or run. The message names what and why."""


def die(msg, code=2):
    sys.stderr.write(f"ablation: {msg}\n")
    sys.exit(code)


def printable(text):
    return isinstance(text, str) and len(text.encode()) <= TEXT_CAP and \
        not any(ord(c) < 32 and c not in "\n\t" for c in text)


def inside(root, path):
    root = os.path.realpath(root)
    target = os.path.realpath(path)
    return target == root or target.startswith(root + os.sep)


# -- cases --------------------------------------------------------------------

def load_cases(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise Refusal(f"{path}: unreadable case file ({exc.__class__.__name__})")
    cases = data.get("cases") if isinstance(data, dict) and "cases" in data else [data]
    if not isinstance(cases, list) or not cases:
        raise Refusal(f"{path}: no cases")
    return cases


def validate_key(key, where):
    if not isinstance(key, str):
        raise Refusal(f"{where}: rule key is not a string")
    m = KEY_RE.match(key)
    if not m:
        raise Refusal(f"{key}: malformed rule key")
    path = m.group("path")
    if path.startswith("/") or ".." in path.split("/"):
        raise Refusal(f"{key}: malformed rule key (path must be repository-relative, no '..')")
    if m.group("start") is not None and int(m.group("start")) > int(m.group("end")):
        raise Refusal(f"{key}: malformed rule key (start after end)")
    return m


def validate_case(case):
    """Refuse a case unless every field matches its pattern. Returns the case."""
    if not isinstance(case, dict):
        raise Refusal("case is not an object")
    cid = case.get("id")
    where = f"case {cid!r}"
    if case.get("schema") != "ablation-case/v1":
        raise Refusal(f"{where}: schema must be ablation-case/v1")
    if not isinstance(cid, str) or not NAME_RE.match(cid):
        raise Refusal(f"{where}: id must match {NAME_RE.pattern}")
    for field in ("skill", "profile"):
        if not isinstance(case.get(field), str) or not NAME_RE.match(case[field]):
            raise Refusal(f"{where}: {field} must match {NAME_RE.pattern}")
    wh = case.get("withhold") or {}
    validate_key(wh.get("source"), where)
    if not isinstance(wh.get("source_commit"), str) or not COMMIT_RE.match(wh["source_commit"]):
        raise Refusal(f"{where}: withhold.source_commit must be 7 to 40 hex digits")
    if not isinstance(case.get("target_state"), str) or not STATE_RE.match(case["target_state"]):
        raise Refusal(f"{where}: target_state must match {STATE_RE.pattern}")
    check_path(case.get("deployed_check"), where, "deployed_check")
    audit = case.get("audit") or {}
    rate = audit.get("sample_rate", 1.0)
    if not isinstance(rate, (int, float)) or not 0 <= rate <= 1:
        raise Refusal(f"{where}: audit.sample_rate must be between 0 and 1")
    pool = audit.get("pool", [])
    if not isinstance(pool, list):
        raise Refusal(f"{where}: audit.pool must be a list")
    for rule in pool:
        if not isinstance(rule, dict):
            raise Refusal(f"{where}: audit rule is not an object")
        validate_key(rule.get("source"), where)
        if not isinstance(rule.get("source_commit"), str) or not COMMIT_RE.match(rule["source_commit"]):
            raise Refusal(f"{where}: audit source_commit must be 7 to 40 hex digits")
        check_path(rule.get("check"), where, "audit check")
    fixture_path(case.get("fixture"), where)
    setup = case.get("setup") or {}
    if not isinstance(setup.get("workflow"), str) or not WORKFLOW_RE.match(setup["workflow"]):
        raise Refusal(f"{where}: setup.workflow must match {WORKFLOW_RE.pattern}")
    if not isinstance(setup.get("template"), str) or not TEMPLATE_RE.match(setup["template"]):
        raise Refusal(f"{where}: setup.template must be a shipped koto template path")
    for name, value in (setup.get("vars") or {}).items():
        if not VAR_NAME_RE.match(name) or not isinstance(value, str) or not VAR_VALUE_RE.match(value):
            raise Refusal(f"{where}: setup.vars {name!r} is not allowed")
    if "PLUGIN_ROOT" in (setup.get("vars") or {}):
        raise Refusal(f"{where}: setup.vars must not set PLUGIN_ROOT; the harness supplies it")
    evidence = setup.get("evidence")
    if not isinstance(evidence, list) or not evidence:
        raise Refusal(f"{where}: setup.evidence must be a non-empty list")
    for ev in evidence:
        if not isinstance(ev, dict) or not printable(json.dumps(ev)):
            raise Refusal(f"{where}: setup.evidence entries must be printable objects under 2 KB")
    prompt = case.get("prompt") or {}
    for arm_key in ("with_skill", "without_skill"):
        text = prompt.get(arm_key)
        if not printable(text) or not re.match(r"^[/A-Za-z]", text):
            raise Refusal(f"{where}: prompt.{arm_key} must be printable, under 2 KB, starting with / or a letter")
    if not printable(case.get("stop_instruction")):
        raise Refusal(f"{where}: stop_instruction must be printable and under 2 KB")
    if not isinstance(case.get("model"), str) or not MODEL_RE.match(case["model"]):
        raise Refusal(f"{where}: model must match {MODEL_RE.pattern}")
    limits = case.get("limits") or {}
    for name, cap in LIMIT_CAPS.items():
        value = limits.get(name)
        if not isinstance(value, int) or not 1 <= value <= cap:
            raise Refusal(f"{where}: limits.{name} must be an integer from 1 to {cap}")
    return case


def check_path(name, where, label):
    if not isinstance(name, str) or not NAME_RE.match(name):
        raise Refusal(f"{where}: {label} must name a check under scripts/ablation/checks/")
    path = os.path.join(CHECKS_DIR, name)
    if not inside(CHECKS_DIR, path) or not os.path.isfile(path) or not os.access(path, os.X_OK):
        raise Refusal(f"{where}: {label} {name!r} is not an executable check under scripts/ablation/checks/")
    return path


def fixture_path(name, where):
    if not isinstance(name, str) or not NAME_RE.match(name):
        raise Refusal(f"{where}: fixture must name a directory under scripts/ablation/fixtures/")
    path = os.path.join(FIXTURES_DIR, name)
    if not inside(FIXTURES_DIR, path) or not os.path.isdir(os.path.join(path, "repo")) \
            or not os.path.isfile(os.path.join(path, "issue.json")):
        raise Refusal(f"{where}: fixture {name!r} needs repo/ and issue.json under scripts/ablation/fixtures/")
    for dirpath, dirnames, filenames in os.walk(path):
        if ".git" in dirnames or ".git" in filenames:
            raise Refusal(f"{where}: fixture {name!r} holds a .git entry")
        for entry in dirnames + filenames:
            if os.path.islink(os.path.join(dirpath, entry)):
                raise Refusal(f"{where}: fixture {name!r} holds a symlink")
    return path


def select_case(case_file=None, case_id=None, withhold=None, skill=None):
    """The one case a run uses. The case file is authoritative."""
    if case_file:
        cases = load_cases(case_file)
        if case_id:
            cases = [c for c in cases if isinstance(c, dict) and c.get("id") == case_id]
        if len(cases) != 1:
            raise Refusal(f"{case_file}: expected one case, found {len(cases)} (use --case-id)")
        case = validate_case(cases[0])
        if withhold and withhold != case["withhold"]["source"]:
            raise Refusal(f"{withhold}: --withhold does not match the case's withhold.source")
        if skill and skill != case["skill"]:
            raise Refusal(f"{skill}: skill does not match the case's skill")
        return case
    if not withhold:
        raise Refusal("give --case, or --withhold and a skill")
    found = []
    for name in sorted(os.listdir(CASES_DIR)) if os.path.isdir(CASES_DIR) else []:
        if not name.endswith(".json"):
            continue
        for c in load_cases(os.path.join(CASES_DIR, name)):
            if isinstance(c, dict) and (c.get("withhold") or {}).get("source") == withhold \
                    and (skill is None or c.get("skill") == skill) \
                    and (case_id is None or c.get("id") == case_id):
                found.append(c)
    if len(found) != 1:
        raise Refusal(f"{withhold}: expected one case under scripts/ablation/cases/, found {len(found)}")
    return validate_case(found[0])


# -- spans --------------------------------------------------------------------

def git(args, cwd=REPO_ROOT, check=True):
    out = subprocess.run(["git"] + args, cwd=cwd, capture_output=True)
    if check and out.returncode != 0:
        raise Refusal(f"git {' '.join(args[:2])} failed")
    return out


HEADING_RE = re.compile(rb"^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$")


def span_at_commit(key, commit):
    """The bytes the key names, read from the file at the commit."""
    m = validate_key(key, key)
    if not isinstance(commit, str) or not COMMIT_RE.match(commit):
        raise Refusal(f"{key}: commit must be 7 to 40 hex digits")
    if git(["cat-file", "-e", f"{commit}^{{commit}}"], check=False).returncode != 0:
        raise Refusal(f"{key}: unknown commit {commit}")
    path = m.group("path")
    shown = git(["show", f"{commit}:{path}"], check=False)
    if shown.returncode != 0:
        raise Refusal(f"{key}: {path} does not exist at {commit}")
    return path, span_from_bytes(key, shown.stdout, commit)


def span_from_bytes(key, content, where="the file"):
    """The span a key names within one file's bytes."""
    m = validate_key(key, key)
    lines = content.splitlines(keepends=True)
    commit = where
    if m.group("start") is not None:
        start, end = int(m.group("start")), int(m.group("end"))
        if start < 1 or end > len(lines):
            raise Refusal(f"{key}: line range outside the file at {commit}")
        return b"".join(lines[start - 1:end])
    want = m.group("heading").encode()
    fenced = False
    begin = level = None
    for i, line in enumerate(lines):
        if line.lstrip().startswith(b"```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        h = HEADING_RE.match(line.rstrip(b"\r\n"))
        if not h:
            continue
        if begin is None:
            if h.group(2) == want:
                begin, level = i, len(h.group(1))
        elif len(h.group(1)) <= level:
            return b"".join(lines[begin:i])
    if begin is None:
        raise Refusal(f"{key}: heading not found at {commit}")
    return b"".join(lines[begin:])


def locate_once(key, content, span):
    count = start = 0
    pos = -1
    while True:
        i = content.find(span, start)
        if i < 0:
            break
        count += 1
        pos = i
        start = i + len(span)
    if count == 0:
        raise Refusal(f"{key}: span not found in the tree being run")
    if count > 1:
        raise Refusal(f"{key}: span found {count} times in the tree being run")
    return pos


def resolve_span(key, commit, tree=REPO_ROOT):
    path, span = span_at_commit(key, commit)
    try:
        with open(os.path.join(tree, path), "rb") as fh:
            content = fh.read()
    except OSError:
        raise Refusal(f"{key}: {path} does not exist in the tree being run")
    locate_once(key, content, span)
    return path, span


def cut_span(key, tree, path, span):
    full = os.path.join(tree, path)
    with open(full, "rb") as fh:
        content = fh.read()
    pos = locate_once(key, content, span)
    with open(full, "wb") as fh:
        fh.write(content[:pos] + content[pos + len(span):])


# -- one run ------------------------------------------------------------------

def sampled(case_id, repetition, rule, rate):
    if rate >= 1:
        return True
    digest = hashlib.sha256(f"{case_id}\0{repetition}\0{rule}".encode()).hexdigest()
    return int(digest[:8], 16) / 2 ** 32 < rate


def harness_snapshot():
    status = git(["status", "--porcelain"], check=False).stdout
    h = hashlib.sha256(status)
    for dirpath, dirnames, filenames in sorted(os.walk(ABL_DIR)):
        dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            h.update(full.encode())
            with open(full, "rb") as fh:
                h.update(fh.read())
    return h.hexdigest()


def copy_plugin(dest):
    ignore = shutil.ignore_patterns("workspace", "__pycache__", ".git")
    os.makedirs(dest)
    for part in PLUGIN_PARTS:
        src = os.path.join(REPO_ROOT, part)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dest, part), ignore=ignore, symlinks=True)


GH_SHIM = """#!/bin/sh
# gh stand-in for an ablation run: serves one issue, refuses everything else.
case "$1 $2" in
  "issue view")
    case " $* " in
      *" --json "*) cat '{issue}' ;;
      *) python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("title:\\t"+d.get("title","")); print("state:\\t"+d.get("state","OPEN")); print("--"); print(d.get("body",""))' '{issue}' ;;
    esac
    exit 0 ;;
esac
echo "gh: disabled in this ablation fixture" >&2
exit 1
"""

FIXTURE_IDENTITY = {"GIT_AUTHOR_NAME": "Ablation Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                    "GIT_COMMITTER_NAME": "Ablation Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}


def base_env(root, bin_dir):
    env = {
        "PATH": f"{bin_dir}:/usr/local/bin:/usr/bin:/bin",
        "HOME": os.environ.get("HOME", root),
        "TMPDIR": os.path.join(root, "tmp"),
        "LANG": os.environ.get("LANG", "C.UTF-8"),
        "SHIRABE_PREFLIGHT_DISABLE": "1",
        "KOTO_BIN": os.path.join(bin_dir, "koto"),
        "KOTO_SESSIONS_BASE": os.path.join(root, "koto"),
        "GH_CONFIG_DIR": os.path.join(root, "ghconfig"),
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_SSH_COMMAND": "/bin/false",
    }
    env.update(FIXTURE_IDENTITY)
    if os.environ.get("ANTHROPIC_API_KEY"):
        env["ANTHROPIC_API_KEY"] = os.environ["ANTHROPIC_API_KEY"]
    return env


def koto_call(real_koto, args, env, cwd, home):
    e = dict(env)
    e["HOME"] = home
    return subprocess.run([real_koto] + args, cwd=cwd, env=e, capture_output=True, text=True, timeout=120)


def run_check(path, arg, seconds):
    try:
        out = subprocess.run([path, arg], capture_output=True, text=True, timeout=seconds)
    except subprocess.TimeoutExpired:
        return "not-checkable", "check-timeout"
    except OSError:
        return "not-checkable", "check-error"
    reason = (out.stdout.splitlines() or [""])[0].strip()
    outcome = {0: "complied", 1: "violated", 2: "not-checkable"}.get(out.returncode)
    if outcome is None or not REASON_RE.match(reason):
        return "not-checkable", "check-error"
    return outcome, reason


def agent_argv(case, arm, plugin):
    test_cmd = os.environ.get("ABLATION_AGENT_CMD")
    if test_cmd:
        if os.environ.get("ABLATION_TEST") != "1":
            raise Refusal("ABLATION_AGENT_CMD is honoured only with ABLATION_TEST=1")
        head = shlex.split(test_cmd)
    else:
        claude = shutil.which("claude")
        if not claude:
            die("claude CLI not found", 3)
        head = [os.path.realpath(claude)]
    prompt = case["prompt"]["without_skill" if arm == "without_skill" else "with_skill"]
    argv = head + ["-p", "--model", case["model"], "--setting-sources", "", "--strict-mcp-config",
                   "--no-session-persistence"]
    if arm != "without_skill":
        argv += ["--plugin-dir", plugin]
    argv += ["--permission-mode", "acceptEdits", "--allowedTools", "Bash",
             "--max-turns", str(case["limits"]["max_turns"]),
             "--append-system-prompt", case["stop_instruction"],
             "--settings", json.dumps(DENY_SETTINGS),
             "--output-format", "stream-json", "--verbose", "--", prompt]
    return argv


def run_agent(argv, env, cwd, seconds, transcript_path):
    """Run the agent, stamping each stdout line with the shared monotonic clock."""
    proc = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            stdin=subprocess.DEVNULL, start_new_session=True)
    lines = []

    def reader():
        for raw in proc.stdout:
            lines.append({"t": time.monotonic_ns(), "line": raw.decode("utf-8", "replace").rstrip("\n")})

    th = threading.Thread(target=reader, daemon=True)
    th.start()
    killed = False
    try:
        proc.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        killed = True
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.wait()
    th.join(timeout=10)
    proc.stdout.close()
    with open(transcript_path, "w") as fh:
        for entry in lines:
            fh.write(json.dumps(entry) + "\n")
    return {"exit": proc.returncode, "killed": killed}


def run_one(case, arm, repetition, arm_order, span, real_koto, keep_dir=None):
    """Run one arm of one repetition. Returns the run's raw outputs as a dict."""
    tmp_base = os.environ.get("ABLATION_TMPDIR") or tempfile.gettempdir()
    root = tempfile.mkdtemp(prefix=SCRATCH_PREFIX, dir=tmp_base)
    try:
        for d in ("tmp", "home", "koto", "ghconfig", "bin", "run"):
            os.makedirs(os.path.join(root, d), exist_ok=True)
        plugin = os.path.join(root, "plugin")
        copy_plugin(plugin)
        path, span_bytes = span
        if arm == "withheld":
            cut_span(case["withhold"]["source"], plugin, path, span_bytes)
        repo = os.path.join(root, "repo")
        fixture = fixture_path(case["fixture"], case["id"])
        shutil.copytree(os.path.join(fixture, "repo"), repo)
        bin_dir = os.path.join(root, "bin")
        run_dir = os.path.join(root, "run")
        home = os.path.join(root, "home")
        env = base_env(root, bin_dir)
        for args in (["init", "-q", "-b", "feature"], ["add", "-A"], ["commit", "-q", "-m", "fixture"]):
            subprocess.run(["git"] + args, cwd=repo, env=env, capture_output=True, check=True)
        os.symlink(os.path.join(ABL_DIR, "koto-intercept"), os.path.join(bin_dir, "koto"))
        gh = os.path.join(bin_dir, "gh")
        with open(gh, "w") as fh:
            fh.write(GH_SHIM.replace("{issue}", os.path.join(fixture, "issue.json")))
        os.chmod(gh, 0o755)

        setup = case["setup"]
        wf = setup["workflow"]
        init = ["init", wf, "--template", os.path.join(plugin, setup["template"])]
        for name, value in sorted((setup.get("vars") or {}).items()):
            init += ["--var", f"{name}={value}"]
        init += ["--var", f"PLUGIN_ROOT={plugin}"]
        if koto_call(real_koto, init, env, repo, home).returncode != 0:
            raise Refusal(f"{case['id']}: koto init failed in the fixture")
        for i, ev in enumerate(setup["evidence"]):
            ev_file = os.path.join(root, "tmp", f"setup-{i}.json")
            with open(ev_file, "w") as fh:
                json.dump(ev, fh)
            koto_call(real_koto, ["next", wf, "--no-cleanup", "--with-data", f"@{ev_file}"], env, repo, home)
        status = koto_call(real_koto, ["status", wf], env, repo, home)
        try:
            state = json.loads(status.stdout).get("current_state")
        except ValueError:
            state = None
        if state != case["target_state"]:
            raise Refusal(f"{case['id']}: setup reached {state!r}, not {case['target_state']!r}")

        before = harness_snapshot()
        agent_env = dict(env)
        agent_env.update({
            "ABLATION_REAL_KOTO": real_koto,
            "ABLATION_RUN_DIR": run_dir,
            "ABLATION_KOTO_HOME": home,
            "ABLATION_TARGET_STATE": case["target_state"],
            "ABLATION_DEPLOYED_CHECK": check_path(case["deployed_check"], case["id"], "deployed_check"),
            "ABLATION_CHECK_SECONDS": str(case["limits"]["check_seconds"]),
        })
        if os.environ.get("ABLATION_TEST") == "1" and os.environ.get("ABLATION_STUB_SCRIPT"):
            agent_env["ABLATION_STUB_SCRIPT"] = os.environ["ABLATION_STUB_SCRIPT"]
        argv = agent_argv(case, arm, plugin)
        agent = run_agent(argv, agent_env, repo, case["limits"]["session_seconds"],
                          os.path.join(run_dir, "transcript.jsonl"))

        state_file = os.path.join(root, "koto", wf, f"koto-{wf}.state.jsonl")
        if os.path.isfile(state_file):
            shutil.copyfile(state_file, os.path.join(run_dir, "koto-state.jsonl"))

        audits = []
        pool = (case.get("audit") or {}).get("pool", [])
        rate = (case.get("audit") or {}).get("sample_rate", 1.0)
        for rule in pool:
            if not sampled(case["id"], repetition, rule["source"], rate):
                continue
            outcome, reason = run_check(check_path(rule["check"], case["id"], "audit check"), run_dir,
                                        case["limits"]["check_seconds"])
            audits.append({"rule.source": rule["source"], "rule.source_commit": rule["source_commit"],
                           "opportunity.outcome": outcome, "reason": reason})

        tampered = harness_snapshot() != before
        raw = {"case": case, "arm": arm, "repetition": repetition, "arm_order": arm_order,
               "root": root, "plugin": plugin, "run_dir": run_dir, "span_path": path,
               "span": span_bytes, "agent": agent, "audits": audits, "tampered": tampered,
               "audit_rate": rate}
        if keep_dir:
            dest = os.path.join(keep_dir, f"r{repetition}-{arm}")
            shutil.copytree(run_dir, dest)
            with open(os.path.join(dest, "raw.json"), "w") as fh:
                json.dump({k: v for k, v in raw.items() if k not in ("case", "span")}, fh, indent=2)
        return finish_run(raw)
    finally:
        shutil.rmtree(root, ignore_errors=True)


def finish_run(raw):
    """Turn a run's raw outputs into its record. Filled in by the record layer."""
    return {"case.id": raw["case"]["id"], "arm": raw["arm"], "repetition": raw["repetition"]}


def run_case(case, runs, jobs, out_path, keep_dir=None):
    real_koto = shutil.which("koto")
    if not real_koto:
        die("koto not found", 3)
    real_koto = os.path.realpath(real_koto)
    span = resolve_span(case["withhold"]["source"], case["withhold"]["source_commit"])

    def repetition(r):
        order = list(ARMS[(r - 1) % 3:] + ARMS[:(r - 1) % 3])
        return [run_one(case, arm, r, i + 1, span, real_koto, keep_dir) for i, arm in enumerate(order)]

    records = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        for recs in pool.map(repetition, range(1, runs + 1)):
            records.extend(recs)
    records.sort(key=lambda rec: (rec["repetition"], ARMS.index(rec["arm"])))
    if out_path:
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, "a") as fh:
            for rec in records:
                fh.write(json.dumps(rec, sort_keys=True) + "\n")
    return records


def smoke(case, real_koto):
    """One session that proves the wrapper is the koto the agent's shell finds."""
    probe = dict(case)
    probe["prompt"] = {"with_skill": "Run exactly these three shell commands and print their output: "
                                     "command -v koto; type koto; echo \"$KOTO_BIN\". Then stop.",
                       "without_skill": "Run: command -v koto. Then stop."}
    probe["stop_instruction"] = "Do nothing else."
    span = resolve_span(case["withhold"]["source"], case["withhold"]["source_commit"])
    keep = tempfile.mkdtemp(prefix="ablation-smoke-")
    try:
        run_one(probe, "full", 0, 1, span, real_koto, keep)
        text = ""
        with open(os.path.join(keep, "r0-full", "transcript.jsonl")) as fh:
            for entry in fh:
                text += json.loads(entry)["line"]
        hits = text.count("/bin/koto")
        return hits >= 3, hits
    finally:
        shutil.rmtree(keep, ignore_errors=True)


# -- CLI ------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(prog="ablation")
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("validate-case")
    v.add_argument("case_file")
    v.add_argument("--case-id")
    s = sub.add_parser("resolve-span")
    s.add_argument("key")
    s.add_argument("commit")
    r = sub.add_parser("run")
    r.add_argument("skill", nargs="?")
    r.add_argument("--withhold")
    r.add_argument("--case")
    r.add_argument("--case-id")
    r.add_argument("--runs", type=int, default=2)
    r.add_argument("--jobs", type=int, default=1)
    r.add_argument("--out")
    r.add_argument("--keep-runs")
    sm = sub.add_parser("smoke")
    sm.add_argument("--case")
    sm.add_argument("--case-id")
    sm.add_argument("--withhold")
    su = sub.add_parser("summarize")
    su.add_argument("records")
    cf = sub.add_parser("check-figures")
    cf.add_argument("--dir", default=os.path.join(REPO_ROOT, "docs", "measurement", "offload-ablation"))
    args = ap.parse_args(argv)

    try:
        if args.cmd == "validate-case":
            case = select_case(args.case_file, args.case_id)
            print(f"ok {case['id']}")
        elif args.cmd == "resolve-span":
            path, span = resolve_span(args.key, args.commit)
            print(f"{path}\t{len(span)}\t{hashlib.sha256(span).hexdigest()}")
        elif args.cmd == "run":
            if not 1 <= args.runs <= 50:
                raise Refusal("--runs must be from 1 to 50")
            if args.keep_runs and os.environ.get("ABLATION_TEST") != "1":
                raise Refusal("--keep-runs is honoured only with ABLATION_TEST=1")
            case = select_case(args.case, args.case_id, args.withhold, args.skill)
            for rec in run_case(case, args.runs, args.jobs, args.out, args.keep_runs):
                if not args.out:
                    print(json.dumps(rec, sort_keys=True))
        elif args.cmd == "smoke":
            case = select_case(args.case, args.case_id, args.withhold)
            real_koto = shutil.which("koto")
            if not real_koto:
                die("koto not found", 3)
            ok, hits = smoke(case, os.path.realpath(real_koto))
            print(f"smoke: {'ok' if ok else 'FAILED'}: the wrapper was named {hits} time(s), at least 3 expected")
            return 0 if ok else 2
        elif args.cmd == "summarize":
            print(summarize_file(args.records), end="")
        elif args.cmd == "check-figures":
            return check_figures(args.dir)
    except Refusal as exc:
        die(str(exc))
    return 0


def summarize_file(path):
    raise Refusal("summarize is not available yet")


def check_figures(directory):
    raise Refusal("check-figures is not available yet")


if __name__ == "__main__":
    sys.exit(main())
