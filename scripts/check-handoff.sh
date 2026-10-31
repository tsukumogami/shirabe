#!/usr/bin/env bash
# check-handoff.sh -- check one skill's hand-off to another, with no model.
#
# Usage: scripts/check-handoff.sh <from> <to>
#
# <from> is the skill that hands off and <to> the skill that receives it: in
# `check-handoff.sh deliver execute`, /deliver opens a koto request and runs
# /execute on its `execute` leg. The script-graded eval cases name it in their
# `run` field (scripts/lib/script-cases.py runs them), and anyone can run it
# directly.
#
# The receiving-side contract check. Both templates are compiled with
# `koto template compile` and read from koto's JSON, so the comparison sees the
# graph koto runs rather than the YAML text:
#
#   - in skills/<from>/koto-templates/<from>.md, the state with a request-leg
#     gate on `leg: <to>` whose `expect` lists outcomes;
#   - the leg attaches a template by its file name, so
#     skills/<to>/koto-templates/<to>.md must exist;
#   - every outcome word the target assigns on an edge into one of its
#     terminal states (a literal `outcome:` in the edge's context_assignments),
#     and every literal `outcome:` in a terminal state's result map, must be in
#     that gate's expect.outcome list;
#   - every payload key the from-state's transitions copy
#     (`${gates.<gate>.payload.<key>}`, outcome aside) must be in every
#     terminal state's result map in the target;
#   - skills/<to>/SKILL.md must declare `--koto-leg`.
#
# Prints one PASS line and exits 0 when every check holds; otherwise prints a
# FAIL line per problem, naming the word, key, state or file, and exits 1.
#
# Exit codes:
#   0  the hand-off holds
#   1  a check failed, or koto is missing or could not compile a template
#   2  usage error
#
# Needs koto (for `koto template compile`) and python3. koto's compile cache
# lands under HOME; the script-case runner gives every case a temporary one.
#
# bash 3.2 floor: no associative arrays, no mapfile, no ${var,,}.

set -u

usage() {
    echo "usage: check-handoff.sh <from> <to>" >&2
    exit 2
}

[ "$#" -eq 2 ] || usage
FROM=$1
TO=$2
for arg in "$FROM" "$TO"; do
    case "$arg" in
        ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*)
            echo "check-handoff: skill name [$arg] does not match [A-Za-z0-9][A-Za-z0-9._-]*" >&2
            exit 2 ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P) || exit 2
for arg in "$FROM" "$TO"; do
    [ -d "$REPO_ROOT/skills/$arg" ] || {
        echo "check-handoff: skills/$arg is not a directory" >&2
        exit 2
    }
done

if ! command -v koto >/dev/null; then
    echo "FAIL: handoff $FROM -> $TO: koto is not on PATH; the check compiles both templates with koto template compile"
    exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "FAIL: handoff $FROM -> $TO: python3 is not on PATH"
    exit 1
fi

FROM_TEMPLATE="skills/$FROM/koto-templates/$FROM.md"
TO_TEMPLATE="skills/$TO/koto-templates/$TO.md"
TO_SKILL="skills/$TO/SKILL.md"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-handoff.XXXXXX") || {
    echo "FAIL: handoff $FROM -> $TO: could not make a temporary directory"
    exit 1
}
trap 'rm -rf "$WORK"' EXIT

# compile <template path relative to the repository> <out file>: koto's
# compiled JSON in <out file>, or a FAIL line and return 1. koto prints the
# path of the compiled file on its last stdout line; an older koto that prints
# the JSON itself is read as it is.
compile() {
    local src="$1" out="$2" last
    if ! koto template compile "$REPO_ROOT/$src" > "$WORK/compile.out" 2> "$WORK/compile.err"; then
        echo "FAIL: handoff $FROM -> $TO: koto template compile $src failed:"
        # koto's warnings come first and can be many; the error is what matters.
        grep -v -e '^warning: ' -e '^  remedy: ' "$WORK/compile.err" | tail -n 20 | sed 's/^/    /'
        return 1
    fi
    last=$(tail -n 1 "$WORK/compile.out")
    case "$last" in
        /*) cp "$last" "$out" || return 1 ;;
        *) cp "$WORK/compile.out" "$out" || return 1 ;;
    esac
}

rc=0
compile "$FROM_TEMPLATE" "$WORK/from.json" || exit 1
TO_JSON=""
if [ -f "$REPO_ROOT/$TO_TEMPLATE" ]; then
    compile "$TO_TEMPLATE" "$WORK/to.json" || exit 1
    TO_JSON="$WORK/to.json"
fi

python3 - "$FROM" "$TO" "$WORK/from.json" "$TO_JSON" "$FROM_TEMPLATE" "$TO_TEMPLATE" <<'PY' || rc=1
import json
import re
import sys

frm, to, from_json, to_json, from_tpl, to_tpl = sys.argv[1:7]
problems = []
fail = problems.append


def literal(value):
    return isinstance(value, str) and "${" not in value


with open(from_json, encoding="utf-8") as fh:
    src = json.load(fh)

# The from-state: a request-leg gate on leg <to> that expects outcomes.
found = None
for state_name, state in sorted(src.get("states", {}).items()):
    gates = state.get("gates") or {}
    leg_gates = sorted(g for g, spec in gates.items()
                       if spec.get("type") == "request-leg" and spec.get("leg") == to)
    for gate in leg_gates:
        expect = (gates[gate].get("expect") or {}).get("outcome")
        if isinstance(expect, list):
            found = (state_name, state, gate, leg_gates, expect)
            break
    if found:
        break

if found is None:
    print("FAIL: handoff %s -> %s: %s has no state with a request-leg gate on `leg: %s` "
          "that expects outcomes" % (frm, to, from_tpl, to))
    sys.exit(1)

state_name, state, gate, leg_gates, expect = found
expected = set(expect)

# Payload keys the from-state's transitions copy from any gate on the leg.
copied = {}
pattern = re.compile(r"\$\{gates\.(%s)\.payload\.([A-Za-z0-9_]+)\}"
                     % "|".join(re.escape(g) for g in leg_gates))
for transition in state.get("transitions") or []:
    for value in (transition.get("context_assignments") or {}).values():
        if not isinstance(value, str):
            continue
        for g, key in pattern.findall(value):
            if key != "outcome":
                copied.setdefault(key, "gates.%s.payload.%s" % (g, key))

if not to_json:
    fail("the `%s` leg accepts a template by file name, %s.md, and %s does not exist"
         % (to, to, to_tpl))
else:
    with open(to_json, encoding="utf-8") as fh:
        target = json.load(fh)
    states = target.get("states", {})
    terminals = sorted(n for n, s in states.items() if s.get("terminal"))
    if not terminals:
        fail("%s has no terminal state" % to_tpl)

    # Outcome words on edges into terminal states, and literal result outcomes.
    words = {}
    for source in sorted(states):
        for transition in states[source].get("transitions") or []:
            dest = transition.get("target")
            if dest not in terminals:
                continue
            word = (transition.get("context_assignments") or {}).get("outcome")
            if literal(word):
                words.setdefault(word, set()).add("an edge from %s into terminal state %s"
                                                  % (source, dest))
    for name in terminals:
        word = (states[name].get("result") or {}).get("outcome")
        if literal(word):
            words.setdefault(word, set()).add("the result map of terminal state %s" % name)
    for word in sorted(words):
        if word not in expected:
            where = sorted(words[word])
            fail("outcome word '%s' is assigned in %s (%s%s), but %s's %s gate in state %s "
                 "doesn't expect it (expects: %s)"
                 % (word, to_tpl, where[0],
                    "" if len(where) == 1 else ", and %d more" % (len(where) - 1),
                    from_tpl, gate, state_name, ", ".join(expect)))

    # Every copied key in every terminal state's result map.
    for key in sorted(copied):
        missing = [n for n in terminals if key not in (states[n].get("result") or {})]
        if missing:
            fail("key '%s', which %s's %s transitions copy (%s), is missing from the result "
                 "map of terminal state%s %s in %s"
                 % (key, from_tpl, state_name, copied[key], "" if len(missing) == 1 else "s",
                    ", ".join(missing), to_tpl))

for problem in problems:
    print("FAIL: handoff %s -> %s: %s" % (frm, to, problem))
if problems:
    sys.exit(1)
PY

if ! grep -qF -- '--koto-leg' "$REPO_ROOT/$TO_SKILL"; then
    echo "FAIL: handoff $FROM -> $TO: $TO_SKILL does not declare --koto-leg, which the $TO leg is entered with"
    rc=1
fi

if [ "$rc" -eq 0 ]; then
    echo "PASS: handoff $FROM -> $TO: receiving-side contract"
fi
exit "$rc"
