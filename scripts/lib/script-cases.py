#!/usr/bin/env python3
"""script-cases.py - run a skill's script-graded eval cases.

Usage:
  scripts/lib/script-cases.py <skill> [--scenario <a,b,...>] [--summary-out <file>]
  scripts/lib/script-cases.py --all [--summary-out <file>]
  scripts/lib/script-cases.py --for <skill> [--list]

Reads skills/<skill>/evals/evals.json (or every skill's, with --all) and runs
each case that carries `"grader": "script"`. Every other case, one with no
`grader`, a grader this runner doesn't know, or a model-graded one, is listed
as refused ("graded cases don't run") and its `run` is never executed. This
runner has no code path to `claude` or any model.

--for <skill> selects by hand-off instead: <skill>'s own script cases, then
every other skill's script cases whose `handoff` is <skill>, skill by skill
in name order, each skill's under a `== <skill>` header as --all prints them,
with one closing total. scripts/check-skill.sh runs it, so a change to a
skill fails the cases other skills keep on their hand-offs to it. Graded
cases aren't listed: the eval harness reports those. A case whose own skill
is its `handoff` runs once. <skill> must be a directory under skills/; its
own evals.json may be absent (a skill that declares
disable-model-invocation: true has none), and then it has no cases of its
own. Another skill with no evals.json is skipped, but one that can't be read
or parsed is a usage error (exit 2), since its cases can't be selected.
git's index is read only when a case is about to run, so a tree with no
script case to run needs no repository. --for takes neither --scenario nor
--summary-out. With --list it prints each case it would run as
`<skill> <id> <name>` and runs none.

The repository is the directory two levels above this file, so a copied tree
runs its own cases against its own scripts.

A script case:

  {"id": 34, "name": "handoff-execute-contract", "grader": "script",
   "handoff": "execute", "run": "scripts/check-handoff.sh deliver execute"}

Before anything runs, `run` is split into words on spaces and checked:

  - the first word must resolve through realpath to a regular file, not a
    symlink, inside the repository, tracked in git's index as a regular file,
    and be scripts/check-handoff.sh or under scripts/cases/;
  - every other word must match [A-Za-z0-9][A-Za-z0-9._-]*;
  - for scripts/check-handoff.sh, there are exactly two arguments and each is a
    skill position: it must name a directory under skills/.

A case that breaks a rule is refused with the rule named and counts as a
failed case. scripts/lib/check-evals-shape.py refuses the same cases with the
same rule text, calling containment() here rather than keeping a copy.

The words are executed directly, never through a shell, from the
repository root, with this closed environment and nothing else from the
caller: PATH, LANG, TMPDIR (a fresh directory), HOME (a fresh directory) and
KOTO_HOME (a fresh koto state directory). Each case runs in its own process
group and the group is killed (SIGKILL) when its timeout runs out: 300
seconds, or a shorter `timeout` (in seconds) the case sets. A TERM or INT to
the runner kills the running case's group the same way before the runner
exits (143 or 130): a caller that keeps the runner in its own process group,
as scripts/check-skill.sh does, signals the runner, never the case's group.

A failing case's reason is a status line (exited N, timed out, refused) and
then its merged stdout and stderr with control characters and terminal escape
sequences stripped (newline and tab kept), cut to its last 200 lines.

Output, one line per case, then the total over the script cases run:

  PASS 34 handoff-execute-contract
  FAIL 35 other-case: exited 1
      <reason lines>
  REFUSED 1 some-graded-case: graded cases don't run
  script cases: P of N passed

Summary (--summary-out <file>), schema script-cases-summary/v1:

  {"schema": "script-cases-summary/v1",
   "skills": {"<name>": {"cases_run", "cases_passed", "pass_rate",
                         "assertions": {"passed", "graded"},
                         "scenario_set": "sha256:<hex>",
                         "cases": [{"id", "name", "verdict", "reason"?}],
                         "refused": [{"id", "name"}]}}}

One assertion is one script case: `graded` is the number of script cases run
and `passed` the number that passed. pass_rate is null when no script case
ran. scenario_set is the SHA-256 of the script cases' ids and run commands,
one "<id><TAB><run>" line per case in file order, joined with newlines.

Standard library only.

Exit codes:
  0 - every script case passed (0 of 0 included)
  1 - a script case failed or was refused
  2 - usage error, or a file that can't be read or written
  3 - a missing prerequisite (git)
  130, 143 - stopped by INT or TERM; the running case's group is killed
"""

import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata

SCHEMA = "script-cases-summary/v1"
DEFAULT_TIMEOUT = 300
REASON_LINES = 200
# The reader keeps at most this much of a case's output; the reason is cut
# from its tail.
OUTPUT_KEEP = 1 << 20
ARG = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
HANDOFF = "scripts/check-handoff.sh"
CASES_DIR = "scripts/cases/"
GRADED_REFUSAL = "graded cases don't run"
ESCAPES = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b.")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


class UsageError(Exception):
    pass


def strip_controls(text):
    """Drop terminal escape sequences and control characters but newline and tab."""
    text = text.replace("\r\n", "\n")
    text = ESCAPES.sub("", text)
    out = []
    for ch in text:
        if ch in "\n\t":
            out.append(ch)
            continue
        cat = unicodedata.category(ch)
        if cat in ("Cc", "Cf", "Cs"):
            continue
        out.append(ch)
    return "".join(out)


def tail_lines(text, count=REASON_LINES):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines[-count:]


def label(value):
    """A case id or name as one printable line."""
    if value is None:
        return "?"
    if not isinstance(value, str):
        value = json.dumps(value)
    return strip_controls(value).replace("\n", " ").replace("\t", " ") or "?"


def tracked_files(root=ROOT):
    """git's index for the repository at root: path -> mode."""
    try:
        proc = subprocess.run(["git", "-C", root, "ls-files", "-s", "-z"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as exc:
        raise UsageError("could not run git: %s" % exc.strerror)
    if proc.returncode != 0:
        raise UsageError("git could not list the files tracked in %s: %s"
                         % (root, proc.stderr.decode("utf-8", "replace").strip()))
    index = {}
    for entry in proc.stdout.split(b"\0"):
        if not entry:
            continue
        meta, _, path = entry.partition(b"\t")
        index[path.decode("utf-8", "surrogateescape")] = meta.split(b" ")[0].decode()
    return index


def containment(run, index, root=ROOT):
    """Return (argv, None) for a run field the rules allow, or (None, rule broken).

    root is the repository the case belongs to, and index its tracked_files().
    The runner checks its own repository; scripts/lib/check-evals-shape.py
    calls this with the repository two levels above the skill it checks, so
    the two refuse a case with the same rule text.
    """
    if not isinstance(run, str) or run.strip() == "":
        return None, "a script case needs a non-empty `run` string"
    words = [w for w in run.split(" ") if w != ""]
    script, args = words[0], words[1:]
    candidate = os.path.join(root, script)
    real_root = os.path.realpath(root)
    rel = os.path.relpath(os.path.realpath(candidate), real_root)
    if rel.startswith(".." + os.sep) or rel == ".." or os.path.isabs(script):
        return None, ("the script %r resolves outside the repository; it must be %s or under %s"
                      % (label(script), HANDOFF, CASES_DIR))
    if rel != os.path.normpath(script):
        return None, ("the script %r resolves through a symlink to %r; it must be a regular file, "
                      "not a symlink" % (label(script), label(rel)))
    if not (rel == HANDOFF or rel.startswith(CASES_DIR)):
        return None, ("the script %r is not %s or under %s, the only paths a case may run"
                      % (label(rel), HANDOFF, CASES_DIR))
    try:
        st = os.lstat(candidate)
    except OSError:
        return None, "the script %r does not exist" % label(rel)
    if stat.S_ISLNK(st.st_mode):
        return None, "the script %r is a symlink; it must be a regular file" % label(rel)
    if not stat.S_ISREG(st.st_mode):
        return None, "the script %r is not a regular file" % label(rel)
    mode = index.get(rel)
    if mode is None:
        return None, "the script %r is not tracked by git; a case runs only tracked files" % label(rel)
    if mode not in ("100644", "100755"):
        return None, "the script %r is tracked as mode %s, not as a regular file" % (label(rel), mode)
    for arg in args:
        if not ARG.fullmatch(arg):
            return None, ("the argument %r does not match [A-Za-z0-9][A-Za-z0-9._-]*"
                          % label(arg))
    if rel == HANDOFF:
        if len(args) != 2:
            return None, ("%s takes two skill arguments, <from> and <to>; got %d"
                          % (HANDOFF, len(args)))
        for arg in args:
            if not os.path.isdir(os.path.join(root, "skills", arg)):
                return None, ("the skill argument %r names no directory under skills/"
                              % label(arg))
    if not os.access(candidate, os.X_OK):
        return None, "the script %r is not executable" % label(rel)
    return [candidate] + args, None


def case_timeout(case):
    """The case's timeout in seconds, or (None, problem)."""
    if "timeout" not in case:
        return DEFAULT_TIMEOUT, None
    value = case["timeout"]
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
        return None, "`timeout` must be a positive number of seconds"
    return min(value, DEFAULT_TIMEOUT), None


def closed_environment(scratch):
    env = {
        "PATH": os.environ.get("PATH") or os.defpath,
        "LANG": os.environ.get("LANG") or "C",
        "TMPDIR": os.path.join(scratch, "tmp"),
        "HOME": os.path.join(scratch, "home"),
        "KOTO_HOME": os.path.join(scratch, "koto"),
    }
    for key in ("TMPDIR", "HOME", "KOTO_HOME"):
        os.mkdir(env[key], 0o700)
    return env


def kill_group(pgid):
    try:
        os.killpg(pgid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


# The process group of the case running now, or None between cases.
RUNNING = [None]


def stop_on_signal(signum, _frame):
    """TERM or INT: kill the running case's group, then exit 128+signal.

    SystemExit unwinds through execute()'s finally, so the case's scratch
    directory is removed too.
    """
    pgid = RUNNING[0]
    if pgid is not None:
        kill_group(pgid)
    sys.stdout.flush()
    raise SystemExit(128 + signum)


def execute(argv, timeout):
    """Run one case. Returns (passed, status line, output text)."""
    scratch = tempfile.mkdtemp(prefix="script-case.")
    try:
        env = closed_environment(scratch)
        try:
            proc = subprocess.Popen(argv, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    start_new_session=True)
        except OSError as exc:
            return False, "could not start: %s" % exc.strerror, ""
        RUNNING[0] = proc.pid
        buf = bytearray()

        def reader():
            while True:
                chunk = proc.stdout.read1(65536) if hasattr(proc.stdout, "read1") \
                    else proc.stdout.read(65536)
                if not chunk:
                    break
                buf.extend(chunk)
                if len(buf) > 2 * OUTPUT_KEEP:
                    del buf[:len(buf) - OUTPUT_KEEP]

        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        deadline = time.monotonic() + timeout
        timed_out = False
        lingering = False
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        if not timed_out:
            # The case exited; a process it left running still holds the
            # output open, and gets what is left of the timeout.
            thread.join(max(0.0, deadline - time.monotonic()))
            if thread.is_alive():
                timed_out = lingering = True
        kill_group(proc.pid)
        proc.wait()
        RUNNING[0] = None
        thread.join(5)
        proc.stdout.close()
        text = strip_controls(bytes(buf[-OUTPUT_KEEP:]).decode("utf-8", "replace"))
        if timed_out:
            status = "timed out after %ss" % _seconds(timeout)
            if lingering:
                status += " (it exited, but a process it started kept running)"
            return False, status, text
        if proc.returncode != 0:
            return False, "exited %d" % proc.returncode, text
        return True, "exited 0", text
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def _seconds(value):
    return int(value) if float(value).is_integer() else value


def scenario_set(script_cases):
    lines = ["%s\t%s" % (json.dumps(c.get("id")), c.get("run")) for c in script_cases]
    return "sha256:" + hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def load_cases(skill):
    path = os.path.join(ROOT, "skills", skill, "evals", "evals.json")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except OSError as exc:
        raise UsageError("cannot read %s: %s" % (path, exc.strerror))
    except ValueError as exc:
        raise UsageError("%s: invalid JSON: %s" % (path, exc))
    evals = data.get("evals") if isinstance(data, dict) else None
    if not isinstance(evals, list):
        raise UsageError("%s: no `evals` list" % path)
    return evals


def run_case(case, index):
    """Run one script case; print its lines; return its summary result."""
    cid, name = case.get("id"), case.get("name")
    result = {"id": cid, "name": name}
    argv, problem = containment(case.get("run"), index)
    timeout = DEFAULT_TIMEOUT
    if argv is not None:
        timeout, problem = case_timeout(case)
    if problem is not None:
        passed, status, text = False, "refused: " + problem, ""
    else:
        passed, status, text = execute(argv, timeout)
    if passed:
        result["verdict"] = "pass"
        print("PASS %s %s" % (label(cid), label(name)))
    else:
        output = tail_lines(text)
        result["verdict"] = "fail"
        result["reason"] = "\n".join([status] + output)
        print("FAIL %s %s: %s" % (label(cid), label(name), status))
        for line in output:
            print("    " + line)
    sys.stdout.flush()
    return result


def is_script_case(case):
    return isinstance(case, dict) and case.get("grader") == "script"


def select_for(skill):
    """--for <skill>: [(skill name, [script case, ...]), ...], own cases first.

    Skills without an evals.json have no cases; any other unreadable file
    raises UsageError.
    """
    skills_dir = os.path.join(ROOT, "skills")
    others = sorted(n for n in os.listdir(skills_dir)
                    if n != skill and os.path.isfile(os.path.join(skills_dir, n, "evals", "evals.json")))
    selected = []
    if os.path.isfile(os.path.join(skills_dir, skill, "evals", "evals.json")):
        own = [c for c in load_cases(skill) if is_script_case(c)]
        if own:
            selected.append((skill, own))
    for other in others:
        cases = [c for c in load_cases(other) if is_script_case(c) and c.get("handoff") == skill]
        if cases:
            selected.append((other, cases))
    return selected


def run_for(skill, listing):
    """--for <skill>, run or listed; returns the exit code."""
    try:
        if not os.path.isdir(os.path.join(ROOT, "skills", skill)):
            raise UsageError("--for %s: skills/%s is not a directory" % (skill, skill))
        selected = select_for(skill)
    except (UsageError, OSError) as exc:
        sys.stderr.write("script-cases: %s\n" % (exc.args[0] if isinstance(exc, UsageError) else exc))
        return 2
    if listing:
        for name, cases in selected:
            for case in cases:
                print("%s %s %s" % (name, label(case.get("id")), label(case.get("name"))))
        return 0
    index = {}
    if selected:
        if shutil.which("git") is None:
            sys.stderr.write("script-cases: git not found; it is needed to check that a case's "
                             "script is tracked\n")
            return 3
        try:
            index = tracked_files()
        except UsageError as exc:
            sys.stderr.write("script-cases: %s\n" % exc.args[0])
            return 2
    passed = run = 0
    for name, cases in selected:
        print("== %s" % name)
        sys.stdout.flush()
        for case in cases:
            run += 1
            if run_case(case, index)["verdict"] == "pass":
                passed += 1
    print("script cases: %d of %d passed" % (passed, run))
    return 0 if passed == run else 1


def run_skill(skill, evals, index, scenario):
    """Run one skill's cases; print their lines; return its summary entry."""
    selected = []
    for position, case in enumerate(evals):
        name = case.get("name") if isinstance(case, dict) else None
        if scenario is not None and name not in scenario:
            continue
        selected.append((position, case))
    script_cases = [c for _, c in selected if isinstance(c, dict) and c.get("grader") == "script"]
    entry = {"cases_run": 0, "cases_passed": 0, "pass_rate": None,
             "assertions": {"passed": 0, "graded": 0},
             "scenario_set": scenario_set(script_cases), "cases": [], "refused": []}
    for position, case in selected:
        if not isinstance(case, dict):
            print("REFUSED #%d ?: not a JSON object; %s" % (position + 1, GRADED_REFUSAL))
            entry["refused"].append({"id": None, "name": None})
            continue
        cid, name = case.get("id"), case.get("name")
        if case.get("grader") != "script":
            print("REFUSED %s %s: %s" % (label(cid), label(name), GRADED_REFUSAL))
            entry["refused"].append({"id": cid, "name": name})
            continue
        entry["cases_run"] += 1
        result = run_case(case, index)
        if result["verdict"] == "pass":
            entry["cases_passed"] += 1
        entry["cases"].append(result)
    run = entry["cases_run"]
    entry["assertions"] = {"passed": entry["cases_passed"], "graded": run}
    if run:
        entry["pass_rate"] = entry["cases_passed"] / run
    return entry


def parse(argv):
    """Returns (target, summary, scenario, for_skill, listing)."""
    target, summary, scenario, for_skill, listing = None, None, None, None, False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--summary-out", "--scenario", "--for"):
            if i + 1 >= len(argv) or argv[i + 1] == "":
                raise UsageError("%s needs a value" % arg)
            value = argv[i + 1]
            i += 2
        elif (arg.startswith("--summary-out=") or arg.startswith("--scenario=")
              or arg.startswith("--for=")):
            arg, _, value = arg.partition("=")
            if value == "":
                raise UsageError("%s needs a value" % arg)
            i += 1
        elif arg in ("-h", "--help"):
            raise UsageError(None)
        elif arg == "--list":
            listing = True
            i += 1
            continue
        elif arg == "--all" or not arg.startswith("-"):
            if target is not None:
                raise UsageError("name one skill, or --all")
            target = arg
            i += 1
            continue
        else:
            raise UsageError("unknown option %r" % arg)
        if arg == "--summary-out":
            summary = value
        elif arg == "--for":
            if for_skill is not None:
                raise UsageError("--for names one skill; give it once")
            for_skill = value
        else:
            scenario = {n for n in value.split(",") if n}
    if for_skill is not None:
        if target is not None:
            raise UsageError("--for selects the cases itself; it takes no skill name or --all")
        if scenario is not None:
            raise UsageError("--for runs every case it selects; it takes no --scenario")
        if summary is not None:
            raise UsageError("--for writes no summary; it takes no --summary-out")
        if not ARG.fullmatch(for_skill):
            raise UsageError("skill name %r does not match [A-Za-z0-9][A-Za-z0-9._-]*" % for_skill)
        return None, None, None, for_skill, listing
    if listing:
        raise UsageError("--list lists what --for selects; use it with --for")
    if target is None:
        raise UsageError("name one skill, or --all")
    if target == "--all" and scenario is not None:
        raise UsageError("--scenario names cases in one skill; use it with a skill name, not --all")
    if target != "--all" and not ARG.fullmatch(target):
        raise UsageError("skill name %r does not match [A-Za-z0-9][A-Za-z0-9._-]*" % target)
    return target, summary, scenario, None, False


USAGE = ("usage: script-cases.py <skill> [--scenario <a,b,...>] [--summary-out <file>]\n"
         "       script-cases.py --all [--summary-out <file>]\n"
         "       script-cases.py --for <skill> [--list]\n")


def main(argv):
    try:
        target, summary_path, scenario, for_skill, listing = parse(argv[1:])
    except UsageError as exc:
        if exc.args[0]:
            sys.stderr.write("script-cases: %s\n" % exc.args[0])
        sys.stderr.write(USAGE)
        return 2
    signal.signal(signal.SIGTERM, stop_on_signal)
    signal.signal(signal.SIGINT, stop_on_signal)
    if for_skill is not None:
        return run_for(for_skill, listing)
    if shutil.which("git") is None:
        sys.stderr.write("script-cases: git not found; it is needed to check that a case's "
                         "script is tracked\n")
        return 3
    skills_dir = os.path.join(ROOT, "skills")
    try:
        if target == "--all":
            skills = sorted(n for n in os.listdir(skills_dir)
                            if os.path.isfile(os.path.join(skills_dir, n, "evals", "evals.json")))
        else:
            if not os.path.isfile(os.path.join(skills_dir, target, "evals", "evals.json")):
                raise UsageError("skills/%s/evals/evals.json does not exist" % target)
            skills = [target]
        index = tracked_files()
        loaded = [(skill, load_cases(skill)) for skill in skills]
    except (UsageError, OSError) as exc:
        sys.stderr.write("script-cases: %s\n" % (exc.args[0] if isinstance(exc, UsageError) else exc))
        return 2
    if scenario is not None:
        names = {c.get("name") for c in loaded[0][1] if isinstance(c, dict)}
        unknown = sorted(scenario - names)
        if unknown:
            sys.stderr.write("script-cases: no case named %s in skills/%s/evals/evals.json\n"
                             % (", ".join(label(n) for n in unknown), target))
            return 2

    summary = {"schema": SCHEMA, "skills": {}}
    passed = run = 0
    for skill, evals in loaded:
        if target == "--all":
            print("== %s" % skill)
        entry = run_skill(skill, evals, index, scenario)
        summary["skills"][skill] = entry
        passed += entry["cases_passed"]
        run += entry["cases_run"]
        sys.stdout.flush()
    print("script cases: %d of %d passed" % (passed, run))
    rc = 0 if passed == run else 1
    if summary_path is not None:
        try:
            with open(summary_path, "w", encoding="utf-8") as fh:
                json.dump(summary, fh, indent=2, sort_keys=True)
                fh.write("\n")
        except OSError as exc:
            sys.stderr.write("script-cases: could not write %s: %s\n" % (summary_path, exc.strerror))
            return 2
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
