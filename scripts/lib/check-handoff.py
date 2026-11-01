#!/usr/bin/env python3
"""check-handoff.py - the template checks behind scripts/check-handoff.sh.

Usage (from check-handoff.sh, never from an eval case directly):
  scripts/lib/check-handoff.py <from> <to> <work dir>

Runs three of check-handoff.sh's four checks on the hand-off from skill
<from> to skill <to>, in this order, printing one PASS line per check that
holds and a FAIL line per problem otherwise. The fourth, the routes check,
is check-handoff.sh's own.

A hand-off is one of two kinds, read from <from>'s template,
skills/<from>/koto-templates/<from>.md:

  leg    a state carries a request-leg gate on `leg: <to>` whose `expect`
         lists outcomes; that state is the one waiting on the leg.
  child  a `default_template:` reference names a path under skills/<to>/
         (execute.md's spawn_and_await, whose children are work-on.md
         sessions); the state holding it is the one waiting on the child.

receiving-side contract
  leg: <to>'s template, skills/<to>/koto-templates/<to>.md, exists (the leg
  accepts a template by file name); every outcome word <to> assigns on an
  edge into a terminal state, and every literal `outcome:` in a terminal's
  result map, is in the gate's expect list; every outcome a transition of
  the waiting state pins (`gates.<gate>.payload.outcome: <word>`) is in it
  too; and skills/<to>/SKILL.md declares --koto-leg.

  Result keys are read per outcome. A transition that pins an outcome word
  needs each payload key it copies (`${gates.<gate>.payload.<key>}`, outcome
  aside) in the result map of every terminal state of <to> that can end
  with that word: a terminal reached by an edge assigning the word, or one
  whose result map assigns it. A transition that pins none, or pins a word
  no terminal is known to end with, needs each copied key in at least one
  terminal. Where <to> carries fewer keys for an outcome by design,
  scripts/check-handoff.results.tsv declares, per edge and outcome, the keys
  it carries, and the check holds <to> to those instead. A record must name
  an outcome the gate expects and only keys a transition for that outcome
  copies, and may not leave out a copied key that every terminal of the
  outcome carries.

  child: each reference resolves, from the referring template's directory,
  to skills/<to>/koto-templates/<to>.md, and that file exists.

rendered directive
  The waiting state's directive, with koto's {{VAR}} substitution applied
  from the compiled template: each declared variable as an init would set it
  (a required one synthesized, see below; an optional one its default, or
  empty), SESSION_NAME, and a placeholder for each value a state captures
  with capture_stdout_as. leg: it names skill `<to>` and carries
  `--koto-leg=<req>:<leg>`, where <req> is the gate's own `request:` value
  rendered the same way, so the child is pointed at the request the gate
  reads. child: it names the child template's file (`work-on.md`).

attach
  leg: <from>'s real template is opened in a temporary koto state directory
  and ticked once, so its own opener (deliver's open_request) creates a fresh
  request with its legs as it declares them. The template in
  skills/<to>/koto-templates/ whose `name:` is <to> (preferring <to>.md) is
  then opened with `koto init --koto-leg=<req>:<leg>` and that leg's inputs,
  and the leg must show the new session bound. A refusal fails the check with
  koto's own output.
  child: <from>'s real template is opened as a parent, and the reference's
  template is opened under it with `koto init --parent`.

A required variable with no default gets: PLUGIN_ROOT the repository root;
the leg's inputs as the request declares them; otherwise the first of the
topic `handoff-check`, `docs/plans/PLAN-handoff-check.md` and the repository
root that its pattern accepts, the literal its pattern spells out
(`^outside$`), or its first allowed value.

Every koto call runs with the working directory under <work dir>. The
caller (check-handoff.sh) has already cleared koto's store variables and
set a scratch HOME (scripts/lib/koto-test-guard.sh), so the sessions and
the request live in a scratch store, never the caller's.

Exit codes:
  0  every check held
  1  a check failed
  2  usage error

Standard library only.
"""

import glob
import json
import os
import re
import subprocess
import sys

TOPIC = "handoff-check"
REQ_PLACEHOLDER = "req-handoff-check"
KOTO_TIMEOUT = 120
VAR_RE = re.compile(r"\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}")
LITERAL_PATTERN = re.compile(r"\^([A-Za-z0-9._/:@+ -]*)\$")


class Check:
    """One named check: collects problems, then prints its verdict."""

    def __init__(self, frm, to, name):
        self.frm, self.to, self.name = frm, to, name
        self.problems = []

    def fail(self, message):
        self.problems.append(message)

    def report(self):
        head = "handoff %s -> %s: %s" % (self.frm, self.to, self.name)
        if not self.problems:
            print("PASS: %s" % head)
            return True
        for problem in self.problems:
            first, _, rest = problem.partition("\n")
            print("FAIL: %s: %s" % (head, first))
            for line in rest.splitlines():
                print("    %s" % line)
        return False


KOTO_ENV = dict(os.environ)


def koto(args, cwd):
    """Run koto; return (exit code, stdout, stderr without koto's warnings)."""
    try:
        proc = subprocess.run(["koto"] + args, cwd=cwd, env=KOTO_ENV, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=KOTO_TIMEOUT)
    except subprocess.TimeoutExpired:
        return 124, "", "koto %s timed out after %ds" % (args[0], KOTO_TIMEOUT)
    err = "\n".join(line for line in proc.stderr.splitlines()
                    if not line.startswith("warning: ") and not line.startswith("  remedy: "))
    return proc.returncode, proc.stdout, err


def koto_message(out, err, limit=20):
    """koto's own words for a failure: its JSON error, else its last lines."""
    text = "\n".join(part for part in (out.strip(), err.strip()) if part)
    lines = text.splitlines()
    return "\n".join(lines[-limit:]) if lines else "(koto printed nothing)"


def compile_template(path, cwd):
    """Compiled JSON of a template, or (None, koto's message)."""
    rc, out, err = koto(["template", "compile", path], cwd)
    if rc != 0:
        return None, koto_message(out, err)
    last = out.strip().splitlines()[-1] if out.strip() else ""
    try:
        if last.startswith("/"):
            with open(last, encoding="utf-8") as fh:
                return json.load(fh), ""
        return json.loads(out), ""
    except (OSError, ValueError) as exc:
        return None, "could not read koto's compiled template: %s" % exc


def literal(value):
    return isinstance(value, str) and "${" not in value and "{{" not in value


def synth_value(name, spec, repo_root, overrides):
    """The value an init passes for a variable, or None to leave it out."""
    if name in overrides:
        return overrides[name]
    if not spec.get("required") or "default" in spec:
        return None
    if name == "PLUGIN_ROOT":
        return repo_root
    values = spec.get("values")
    if values:
        return values[0]
    pattern = spec.get("pattern")
    if not pattern:
        return TOPIC
    m = LITERAL_PATTERN.fullmatch(pattern)
    if m:
        return m.group(1)
    for candidate in (TOPIC, "docs/plans/PLAN-%s.md" % TOPIC, repo_root):
        try:
            if re.search(pattern, candidate):
                return candidate
        except re.error:
            break
    return TOPIC


def init_vars(tpl, repo_root, overrides):
    """--var arguments for an init of a compiled template."""
    args = []
    names = set()
    for name, spec in sorted((tpl.get("variables") or {}).items()):
        value = synth_value(name, spec, repo_root, overrides)
        if value is not None:
            args += ["--var", "%s=%s" % (name, value)]
            names.add(name)
    for name, value in sorted(overrides.items()):
        if name not in names:
            args += ["--var", "%s=%s" % (name, value)]
    return args


def render(text, tpl, repo_root, session, captured):
    """koto's {{VAR}} substitution over text, as an init with init_vars renders it."""
    values = {}
    for name, spec in (tpl.get("variables") or {}).items():
        value = synth_value(name, spec, repo_root, {})
        if value is None:
            value = spec.get("default", "")
        values[name] = str(value)
    for state in (tpl.get("states") or {}).values():
        cap = (state.get("default_action") or {}).get("capture_stdout_as")
        if cap:
            values.setdefault(cap, captured.get(cap, "<captured %s>" % cap))
    values.setdefault("SESSION_NAME", session)
    return VAR_RE.sub(lambda m: values.get(m.group(1), m.group(0)), text or "")


def template_name(path):
    """The `name:` a template's frontmatter declares, or None."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r"name:\s*['\"]?([A-Za-z0-9._-]+)['\"]?\s*$", line)
        if m:
            return m.group(1)
    return None


def child_references(path, to):
    """(state, reference) for each default_template naming a path under skills/<to>/."""
    refs = []
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return refs
    in_states, state = False, None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if re.match(r"states:\s*$", line):
            in_states = True
            continue
        if re.match(r"\S", line):
            in_states = False
        m = re.match(r"  ([A-Za-z_][A-Za-z0-9_]*):\s*$", line)
        if in_states and m:
            state = m.group(1)
            continue
        m = re.match(r"\s+default_template:\s*['\"]?([^'\"\s]+)['\"]?\s*$", line)
        if m and to in m.group(1).split("/")[:-1]:
            refs.append((state, m.group(1)))
    return refs


def read_records(path, frm, to):
    """{outcome: [keys]} for this edge from check-handoff.results.tsv, and problems."""
    records, problems = {}, []
    if not os.path.isfile(path):
        return records, problems
    with open(path, encoding="utf-8") as fh:
        for number, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            fields = line.split("\t")
            where = "scripts/check-handoff.results.tsv line %d" % number
            if len(fields) != 4:
                problems.append("%s has %d tab-separated fields, not 4 (from, to, outcome, keys)"
                                % (where, len(fields)))
                continue
            r_from, r_to, outcome, keys = (f.strip() for f in fields)
            if (r_from, r_to) != (frm, to):
                continue
            if outcome in records:
                problems.append("%s repeats the record for %s -> %s outcome '%s'"
                                % (where, frm, to, outcome))
                continue
            records[outcome] = [] if keys == "-" else [k for k in keys.split(",") if k]
    return records, problems


def find_leg(src, to):
    """(state, gate, leg gates, expect) for the state waiting on leg <to>, or None."""
    for state_name, state in sorted((src.get("states") or {}).items()):
        gates = state.get("gates") or {}
        leg_gates = sorted(g for g, spec in gates.items()
                           if spec.get("type") == "request-leg" and spec.get("leg") == to)
        for gate in leg_gates:
            expect = (gates[gate].get("expect") or {}).get("outcome")
            if isinstance(expect, list):
                return state_name, gate, leg_gates, expect
    return None


def leg_contract(check, frm, to, src, target, leg, paths):
    """The receiving-side contract of a leg hand-off; problems go to check."""
    state_name, gate, leg_gates, expect = leg
    from_tpl, to_tpl = paths["from_tpl"], paths["to_tpl"]
    expected = set(expect)
    state = src["states"][state_name]
    copy_re = re.compile(r"\$\{gates\.(%s)\.payload\.([A-Za-z0-9_]+)\}"
                         % "|".join(re.escape(g) for g in leg_gates))
    pin_keys = ["gates.%s.payload.outcome" % g for g in leg_gates]

    # Each transition: the outcome it pins, and the keys it copies.
    arms = []
    for transition in state.get("transitions") or []:
        when = transition.get("when") or {}
        pinned = next((when[k] for k in pin_keys if isinstance(when.get(k), str)), None)
        copied = {}
        for value in (transition.get("context_assignments") or {}).values():
            if isinstance(value, str):
                for g, key in copy_re.findall(value):
                    if key != "outcome":
                        copied.setdefault(key, "gates.%s.payload.%s" % (g, key))
        arms.append((transition.get("target"), pinned, copied))
        if pinned is not None and pinned not in expected:
            check.fail("%s's %s transition to %s pins outcome '%s', which its %s gate doesn't "
                       "expect (expects: %s)" % (from_tpl, state_name, transition.get("target"),
                                                  pinned, gate, ", ".join(expect)))

    if target is None:
        return
    states = target.get("states") or {}
    terminals = sorted(n for n, s in states.items() if s.get("terminal"))
    if not terminals:
        check.fail("%s has no terminal state" % to_tpl)
        return
    result = {n: (states[n].get("result") or {}) for n in terminals}

    # Outcome words and the terminals that can end with each.
    words, ends = {}, {}
    for source in sorted(states):
        for transition in states[source].get("transitions") or []:
            dest = transition.get("target")
            if dest not in terminals:
                continue
            word = (transition.get("context_assignments") or {}).get("outcome")
            if literal(word):
                words.setdefault(word, set()).add(
                    "an edge from %s into terminal state %s" % (source, dest))
                ends.setdefault(word, set()).add(dest)
    for name in terminals:
        word = result[name].get("outcome")
        if literal(word):
            words.setdefault(word, set()).add("the result map of terminal state %s" % name)
            ends.setdefault(word, set()).add(name)
    for word in sorted(words):
        if word not in expected:
            where = sorted(words[word])
            check.fail("outcome word '%s' is assigned in %s (%s%s), but %s's %s gate in state %s "
                       "doesn't expect it (expects: %s)"
                       % (word, to_tpl, where[0],
                          "" if len(where) == 1 else ", and %d more" % (len(where) - 1),
                          from_tpl, gate, state_name, ", ".join(expect)))

    # The declared records, checked against the transitions and the terminals.
    records, problems = read_records(paths["results"], frm, to)
    for problem in problems:
        check.fail(problem)
    copied_by_word = {}
    for _, pinned, copied in arms:
        if pinned is not None:
            copied_by_word.setdefault(pinned, {}).update(copied)
    for word in sorted(records):
        where = "scripts/check-handoff.results.tsv's record for %s -> %s outcome '%s'" % (frm, to, word)
        if word not in expected:
            check.fail("%s names an outcome %s's %s gate doesn't expect (expects: %s)"
                       % (where, from_tpl, gate, ", ".join(expect)))
            continue
        copied = copied_by_word.get(word, {})
        for key in records[word]:
            if key not in copied:
                check.fail("%s names key '%s', which no %s transition for outcome '%s' copies"
                           % (where, key, state_name, word))
        carriers = sorted(ends.get(word, ()))
        for key in sorted(copied):
            if key in records[word] or not carriers:
                continue
            if all(key in result[t] for t in carriers):
                check.fail("%s leaves out key '%s', which every terminal state ending with that "
                           "outcome carries (%s)" % (where, key, ", ".join(carriers)))

    # Every copied key where the caller reads it.
    reported = set()
    for dest, pinned, copied in arms:
        carriers = sorted(ends.get(pinned, ())) if pinned is not None else []
        if carriers:
            needed = records[pinned] if pinned in records else sorted(copied)
            for key in needed:
                for t in carriers:
                    if key not in result[t] and (key, t, pinned) not in reported:
                        reported.add((key, t, pinned))
                        source = copied.get(key, "gates.%s.payload.%s" % (gate, key))
                        check.fail("key '%s', which %s's %s transition for outcome '%s' copies "
                                   "(%s), is missing from the result map of terminal state %s "
                                   "in %s, which can end with that outcome"
                                   % (key, from_tpl, state_name, pinned, source, t, to_tpl))
        else:
            for key in sorted(copied):
                if not any(key in result[t] for t in terminals) and (key, None, None) not in reported:
                    reported.add((key, None, None))
                    check.fail("key '%s', which %s's %s transitions copy (%s), is missing from the "
                               "result map of every terminal state in %s"
                               % (key, from_tpl, state_name, copied[key], to_tpl))


def target_template(repo_root, to):
    """The template under skills/<to>/koto-templates/ whose name: is <to>."""
    preferred = os.path.join(repo_root, "skills", to, "koto-templates", to + ".md")
    if template_name(preferred) == to:
        return preferred
    for path in sorted(glob.glob(os.path.join(repo_root, "skills", to, "koto-templates", "*.md"))):
        if not path.endswith(".mermaid.md") and template_name(path) == to:
            return path
    return None


def rel(path, repo_root):
    return os.path.relpath(path, repo_root)


def main(argv):
    if len(argv) != 4:
        print("usage: check-handoff.py <from> <to> <work dir>", file=sys.stderr)
        return 2
    frm, to, work = argv[1], argv[2], argv[3]
    # scripts/lib/check-handoff.py: the repository is two directories up.
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    run_dir = os.path.join(work, "run")
    os.makedirs(run_dir, exist_ok=True)
    # koto's store for this run: <work dir>/home/.koto, gone with <work dir>.
    home = os.path.join(work, "home")
    os.makedirs(home, exist_ok=True)
    KOTO_ENV["HOME"] = home
    paths = {
        "from_tpl": "skills/%s/koto-templates/%s.md" % (frm, frm),
        "to_tpl": "skills/%s/koto-templates/%s.md" % (to, to),
        "to_skill": "skills/%s/SKILL.md" % to,
        "results": os.path.join(repo_root, "scripts", "check-handoff.results.tsv"),
    }
    from_abs = os.path.join(repo_root, paths["from_tpl"])
    to_abs = os.path.join(repo_root, paths["to_tpl"])

    contract = Check(frm, to, "receiving-side contract")
    directive = Check(frm, to, "rendered directive")
    attach = Check(frm, to, "attach")

    src, src_err = compile_template(from_abs, run_dir)
    refs = child_references(from_abs, to)
    leg = find_leg(src, to) if src else None

    if src is None:
        contract.fail("koto template compile %s failed:\n%s" % (paths["from_tpl"], src_err))
        directive.fail("%s does not compile, so no directive could be rendered" % paths["from_tpl"])
        attach.fail("%s does not compile, so nothing was attached" % paths["from_tpl"])
    if leg is None and not refs:
        if src is not None:
            contract.fail("%s has no state with a request-leg gate on `leg: %s` that expects "
                          "outcomes, and no child template reference under skills/%s/"
                          % (paths["from_tpl"], to, to))
            directive.fail("no state of %s waits on %s" % (paths["from_tpl"], to))
            attach.fail("no state of %s waits on %s" % (paths["from_tpl"], to))
        ok = [c.report() for c in (contract, directive, attach)]
        return 0 if all(ok) else 1

    if leg is not None:
        run_leg(frm, to, src, leg, paths, from_abs, to_abs, repo_root, run_dir,
                contract, directive, attach)
    else:
        run_child(frm, to, src, refs, paths, from_abs, to_abs, repo_root, run_dir,
                  contract, directive, attach)
    ok = [c.report() for c in (contract, directive, attach)]
    return 0 if all(ok) else 1


def run_leg(frm, to, src, leg, paths, from_abs, to_abs, repo_root, run_dir,
            contract, directive, attach):
    state_name, gate, _, _ = leg
    session = "%s-%s" % (frm, TOPIC)

    # receiving-side contract
    target = None
    if not os.path.isfile(to_abs):
        contract.fail("the `%s` leg accepts a template by file name, %s.md, and %s does not exist"
                      % (to, to, paths["to_tpl"]))
    else:
        target, err = compile_template(to_abs, run_dir)
        if target is None:
            contract.fail("koto template compile %s failed:\n%s" % (paths["to_tpl"], err))
    leg_contract(contract, frm, to, src, target, leg, paths)
    skill = os.path.join(repo_root, paths["to_skill"])
    try:
        with open(skill, encoding="utf-8") as fh:
            declares = "--koto-leg" in fh.read()
    except OSError:
        declares = False
    if not declares:
        contract.fail("%s does not declare --koto-leg, which the %s leg is entered with"
                      % (paths["to_skill"], to))

    # rendered directive
    spec = src["states"][state_name]["gates"][gate]
    request_var = VAR_RE.fullmatch(spec.get("request") or "")
    captured = {request_var.group(1): REQ_PLACEHOLDER} if request_var else {}
    req = render(spec.get("request") or "", src, repo_root, session, captured)
    text = " ".join(render(src["states"][state_name].get("directive"), src, repo_root,
                           session, captured).split())
    if "skill `%s`" % to not in text:
        directive.fail("state %s's directive, rendered, does not name skill `%s`" % (state_name, to))
    flag = "--koto-leg=%s:%s" % (req, to)
    if flag not in text:
        directive.fail("state %s's directive, rendered, does not carry %s, the request and leg "
                       "its %s gate reads" % (state_name, flag, gate))

    # attach
    rc, out, err = koto(["init", session, "--template", from_abs]
                        + init_vars(src, repo_root, {}), run_dir)
    if rc != 0:
        attach.fail("koto init of %s, to open its request, failed:\n%s"
                    % (paths["from_tpl"], koto_message(out, err)))
        return
    rc, tick_out, tick_err = koto(["next", session, "--no-cleanup"], run_dir)
    req_id, declaration = open_leg(to, run_dir)
    if req_id is None:
        attach.fail("%s's first tick opened no request with an open `%s` leg, so there was "
                    "nothing to attach to:\n%s" % (paths["from_tpl"], to,
                                                   koto_message(tick_out, tick_err, 10)))
        return
    tpl_path = target_template(repo_root, to)
    if tpl_path is None:
        attach.fail("no template under skills/%s/koto-templates/ declares `name: %s`" % (to, to))
        return
    tpl, _ = compile_template(tpl_path, run_dir)
    inputs = {k: str(v) for k, v in ((declaration or {}).get("inputs") or {}).items()}
    child = "%s-%s" % (to, TOPIC)
    args = ["init", child, "--template", tpl_path]
    args += init_vars(tpl or {}, repo_root, inputs)
    args += ["--koto-leg", "%s:%s" % (req_id, to)]
    rc, out, err = koto(args, run_dir)
    if rc != 0:
        attach.fail("koto refused to attach %s to leg %s of a fresh request (exit %d):\n%s"
                    % (rel(tpl_path, repo_root), to, rc, koto_message(out, err)))
        return
    rc, out, _ = koto(["request", "get", req_id], run_dir)
    try:
        bound = json.loads(out)["legs"][to].get("bound_child")
    except (ValueError, KeyError, TypeError, AttributeError):
        bound = None
    if bound != child:
        attach.fail("koto init --koto-leg of %s exited 0, but leg %s of the request is bound to "
                    "[%s], not %s" % (rel(tpl_path, repo_root), to, bound, child))


def open_leg(leg, run_dir):
    """(request id, leg declaration) of an open request with leg <leg> open, or (None, None)."""
    rc, out, _ = koto(["request", "list", "--state", "open"], run_dir)
    try:
        ids = [r["request_id"] for r in json.loads(out).get("requests", [])]
    except (ValueError, KeyError, TypeError, AttributeError):
        return None, None
    for req_id in ids:
        rc, out, _ = koto(["request", "get", req_id], run_dir)
        try:
            spec = json.loads(out)["legs"][leg]
        except (ValueError, KeyError, TypeError):
            continue
        if spec.get("disposition") == "open" and not spec.get("bound_child"):
            return req_id, spec.get("declaration") or {}
    return None, None


def run_child(frm, to, src, refs, paths, from_abs, to_abs, repo_root, run_dir,
              contract, directive, attach):
    session = "%s-%s" % (frm, TOPIC)
    base = os.path.dirname(from_abs)
    resolved = []
    for state_name, ref in refs:
        path = os.path.normpath(os.path.join(base, ref))
        where = ("the child template reference `default_template: %s` in state %s of %s"
                 % (ref, state_name, paths["from_tpl"]))
        if not os.path.isfile(path):
            contract.fail("%s resolves to %s, which does not exist" % (where, rel(path, repo_root)))
        elif os.path.realpath(path) != os.path.realpath(to_abs):
            contract.fail("%s resolves to %s, not %s" % (where, rel(path, repo_root), paths["to_tpl"]))
        else:
            resolved.append((state_name, ref, path))
    if src is None:
        return

    # rendered directive: each referring state names the child template's file.
    for state_name, ref in refs:
        state = (src.get("states") or {}).get(state_name)
        if state is None:
            directive.fail("state %s, which holds the child template reference, is not in the "
                           "compiled %s" % (state_name, paths["from_tpl"]))
            continue
        text = " ".join(render(state.get("directive"), src, repo_root, session, {}).split())
        name = "`%s`" % os.path.basename(ref)
        if name not in text:
            directive.fail("state %s's directive, rendered, does not name the child template %s"
                           % (state_name, name))

    # attach: the real template as a parent, the referenced one under it.
    if not resolved:
        attach.fail("no child template reference resolves, so no child was opened")
        return
    rc, out, err = koto(["init", session, "--template", from_abs]
                        + init_vars(src, repo_root, {}), run_dir)
    if rc != 0:
        attach.fail("koto init of %s as the parent failed:\n%s"
                    % (paths["from_tpl"], koto_message(out, err)))
        return
    for state_name, ref, path in resolved:
        tpl, _ = compile_template(path, run_dir)
        child = "%s.%s" % (session, to)
        rc, out, err = koto(["init", child, "--parent", session, "--template", path]
                            + init_vars(tpl or {}, repo_root, {}), run_dir)
        if rc != 0:
            attach.fail("koto refused to open %s as a child of %s (exit %d):\n%s"
                        % (rel(path, repo_root), session, rc, koto_message(out, err)))
            continue
        rc, out, _ = koto(["workflows", "--children", session], run_dir)
        try:
            names = [c.get("name") for c in json.loads(out)]
        except (ValueError, TypeError, AttributeError):
            names = []
        if child not in names:
            attach.fail("koto init --parent of %s exited 0, but %s does not list %s as its child"
                        % (rel(path, repo_root), session, child))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
