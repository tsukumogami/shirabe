#!/usr/bin/env bash
# skill-gate_test.sh -- scripts/skill-gate.sh, the pull request gate's
# selection of what to run.
#
# Builds a fixture repository with a copy of skill-gate.sh, a stand-in
# scripts/check-skill.sh and a stand-in scripts/lib/script-cases.py, and the
# skills alpha, beta and gamma. Each stand-in appends `check-skill <args>` or
# `script-cases <args>` to the file STUB_RECORD names and exits with the code
# STUB_FAIL gives its first argument (`alpha=1 --all=1`), 0 otherwise. Each
# case is one commit on top of a shared base, and the copied gate runs with
# SKILL_GATE_BASE set to that base.
#
# Covers: the skills a change selects, each once and in full; each shared
# path, alone and with a skill; the paths that select nothing; a deleted and
# a renamed skill; the failure list; each refused base; the empty base; and
# --list. Nothing here runs a real check, so it needs git and python3, and no
# koto, yq or network.
#
# Usage: bash scripts/skill-gate_test.sh
#        /bin/bash scripts/skill-gate_test.sh   (macOS: the bash 3.2 floor)
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
GATE="$HERE/skill-gate.sh"
# The gate runs under the bash running this harness, so a /bin/bash run
# exercises it on 3.2.
BASH_BIN=${BASH:-bash}

command -v git >/dev/null 2>&1 || { echo "skill-gate_test: git is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "skill-gate_test: python3 is required" >&2; exit 1; }

# The fixture is its own repository, whatever repository runs this.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

T=$(mktemp -d "${TMPDIR:-/tmp}/skill-gate-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
REPO="$T/repo"
RECORD="$T/record"

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n      %s\n' "$1" "${2-}"; }

g() { git -C "$REPO" -c user.name=skill-gate-test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }

# -- the fixture --------------------------------------------------------------

mkdir -p "$REPO/scripts/lib" || exit 1
git init -q "$REPO" || exit 1
cp "$GATE" "$REPO/scripts/skill-gate.sh" || exit 1

cat >"$REPO/scripts/check-skill.sh" <<'STUB'
#!/usr/bin/env bash
printf 'check-skill %s\n' "$*" >>"$STUB_RECORD"
for want in ${STUB_FAIL:-}; do
    if [ "${want%%=*}" = "${1-}" ]; then
        exit "${want#*=}"
    fi
done
exit 0
STUB

cat >"$REPO/scripts/lib/script-cases.py" <<'STUB'
import os, sys
args = sys.argv[1:]
with open(os.environ["STUB_RECORD"], "a") as fh:
    fh.write("script-cases " + " ".join(args) + "\n")
for want in os.environ.get("STUB_FAIL", "").split():
    key, _, code = want.partition("=")
    if args and key == args[0]:
        sys.exit(int(code))
sys.exit(0)
STUB

for s in alpha beta gamma; do
    mkdir -p "$REPO/skills/$s"
    printf '# %s\n' "$s" >"$REPO/skills/$s/SKILL.md"
done
mkdir -p "$REPO/skills/alpha/scripts" "$REPO/skills/beta/evals" "$REPO/docs" "$REPO/references" \
    "$REPO/koto-templates" "$REPO/.github/workflows"
printf 'echo x\n' >"$REPO/skills/alpha/scripts/x.sh"
printf '{}\n' >"$REPO/skills/beta/evals/evals.json"
printf 'echo handoff\n' >"$REPO/scripts/check-handoff.sh"
printf '# readme\n' >"$REPO/README.md"
g add -A || exit 1
g commit -q -m base || exit 1
BASE=$(g rev-parse HEAD) || exit 1

# commit_case <change>...: a fresh commit on top of the base. Each change is
# `edit:<path>` (append a line, creating the file and its directory),
# `rm:<path>` (remove a path, recursively) or `mv:<from>:<to>`.
commit_case() {
    local c p
    g checkout -q --detach "$BASE" || return 1
    g reset -q --hard "$BASE" || return 1
    g clean -qfdx || return 1
    for c in "$@"; do
        case "$c" in
            edit:*)
                p=${c#edit:}
                mkdir -p "$REPO/$(dirname "$p")"
                printf 'changed\n' >>"$REPO/$p"
                ;;
            rm:*)
                g rm -rq "${c#rm:}" || return 1
                ;;
            mv:*)
                p=${c#mv:}
                g mv "${p%%:*}" "${p#*:}" || return 1
                ;;
        esac
    done
    g add -A || return 1
    g commit -q -m case || return 1
}

# run_gate [args...]: runs the copied gate from the fixture's root with
# SKILL_GATE_BASE and STUB_FAIL as the caller set them; sets OUT and RC.
OUT=""
RC=0
run_gate() {
    : >"$RECORD"
    OUT=$(cd "$REPO" && STUB_RECORD="$RECORD" "$BASH_BIN" scripts/skill-gate.sh "$@" 2>&1)
    RC=$?
}

record() { cat "$RECORD"; }

# expect <label> <rc> <record> [<text>...]: the run exited <rc>, recorded
# exactly <record> (lines joined by `|`), and printed each <text>.
expect() {
    local label=$1 want_rc=$2 want_rec=$3 got_rec t
    shift 3
    got_rec=$(record | tr '\n' '|')
    got_rec=${got_rec%|}
    if [ "$RC" != "$want_rc" ]; then
        fail "$label" "exit $RC, want $want_rc; output: $OUT"
        return
    fi
    if [ "$got_rec" != "$want_rec" ]; then
        fail "$label" "recorded [$got_rec], want [$want_rec]; output: $OUT"
        return
    fi
    for t in "$@"; do
        case "$OUT" in
            *"$t"*) ;;
            *) fail "$label" "output lacks [$t]: $OUT"; return ;;
        esac
    done
    pass "$label"
}

# not_in <label> <text>: the last run's output does not hold <text>.
not_in() {
    case "$OUT" in
        *"$2"*) fail "$1" "output holds [$2]: $OUT" ;;
        *) pass "$1" ;;
    esac
}

export SKILL_GATE_BASE STUB_FAIL

# -- skill selection ----------------------------------------------------------

commit_case edit:skills/alpha/SKILL.md edit:skills/alpha/scripts/x.sh edit:skills/beta/evals/evals.json
SKILL_GATE_BASE=$BASE STUB_FAIL=""
run_gate
expect "each changed skill is checked once, in name order, in full; a skill's own scripts/ is not shared" \
    0 "check-skill alpha|check-skill beta" \
    "== check-skill alpha" "== check-skill beta" "skill-gate: 2 of 2 checks passed"
not_in "  ... and no check runs with --changed" "--changed"

# -- shared paths -------------------------------------------------------------

for p in scripts/check-handoff.sh scripts/lib/new.py references/x.md koto-templates/x.md; do
    commit_case "edit:$p"
    run_gate
    expect "a change to $p alone runs every script case and no skill" 0 "script-cases --all" \
        "== script-cases --all" "skill-gate: 1 of 1 checks passed"
    commit_case "edit:$p" edit:skills/beta/x.md
    run_gate
    expect "a change to $p with skills/beta/x.md checks beta, then every script case" 0 \
        "check-skill beta|script-cases --all" "skill-gate: 2 of 2 checks passed"
done

for p in docs/x.md README.md .tsuku.toml .github/workflows/other.yml; do
    commit_case "edit:$p"
    run_gate
    expect "a change to $p alone checks nothing" 0 "" "skill-gate: nothing to check"
done

# -- a skill that is gone -----------------------------------------------------

commit_case rm:skills/gamma
run_gate
expect "a deleted skill is not checked" 0 "" "skill-gate: nothing to check"

commit_case mv:skills/gamma:skills/delta
run_gate
expect "a renamed skill is checked under its new name only" 0 "check-skill delta" \
    "== check-skill delta" "skill-gate: 1 of 1 checks passed"

# -- failures -----------------------------------------------------------------

commit_case edit:skills/alpha/SKILL.md edit:skills/beta/x.md edit:scripts/check-handoff.sh
STUB_FAIL="alpha=1"
run_gate
expect "a failing check-skill doesn't stop the checks after it" 1 \
    "check-skill alpha|check-skill beta|script-cases --all"
last=$(printf '%s\n' "$OUT" | tail -n 1)
if [ "$last" = "skill-gate: failed: check-skill alpha" ]; then
    pass "  ... and the closing line names it"
else
    fail "  ... and the closing line names it" "last line [$last]; output: $OUT"
fi
not_in "  ... with no ok line" "checks passed"

STUB_FAIL="alpha=1 beta=2 --all=1"
run_gate
expect "every failure is listed, an exit other than 1 with its code" 1 \
    "check-skill alpha|check-skill beta|script-cases --all" \
    "skill-gate: failed: check-skill alpha, check-skill beta (exit 2), script-cases --all"
not_in "  ... with no ok line" "checks passed"

STUB_FAIL="beta=2"
run_gate
expect "a check-skill that exits 2 is a failure named with its code" 1 \
    "check-skill alpha|check-skill beta|script-cases --all" \
    "skill-gate: failed: check-skill beta (exit 2)"

STUB_FAIL="--all=1"
run_gate
expect "a runner that exits 1 is listed" 1 \
    "check-skill alpha|check-skill beta|script-cases --all" \
    "skill-gate: failed: script-cases --all"
STUB_FAIL=""

# -- the base -----------------------------------------------------------------

commit_case edit:skills/alpha/SKILL.md
unset SKILL_GATE_BASE
run_gate
expect "an unset base runs every script case only" 0 "script-cases --all" \
    "skill-gate: no base commit; running every skill's script cases" "skill-gate: 1 of 1 checks passed"
SKILL_GATE_BASE=""
export SKILL_GATE_BASE
run_gate
expect "an empty base runs every script case only" 0 "script-cases --all" \
    "skill-gate: no base commit; running every skill's script cases"
STUB_FAIL="--all=1"
run_gate
expect "  ... and fails when the runner fails" 1 "script-cases --all" \
    "skill-gate: failed: script-cases --all"
STUB_FAIL=""

upper=$(printf '%s' "$BASE" | tr 'abcdef' 'ABCDEF')
case "$upper" in
    *[ABCDEF]*) ;;
    # An id of digits only has no upper case; any upper-case letter will do.
    *) upper="A${BASE#?}" ;;
esac
short=${BASE%?}
for bad in "HEAD~1" "main" "--output=x" "$short" "$upper"; do
    SKILL_GATE_BASE=$bad
    run_gate
    expect "SKILL_GATE_BASE [$bad] is refused before anything runs" 2 "" \
        "skill-gate: SKILL_GATE_BASE must be a 40-character lower-case hex commit id"
done
if [ -e "$REPO/x" ] || [ -e "$REPO/scripts/x" ]; then
    fail "  ... and --output=x leaves no file named x" "$(ls -a "$REPO")"
else
    pass "  ... and --output=x leaves no file named x"
fi

SKILL_GATE_BASE=0000000000000000000000000000000000000000
run_gate
expect "a well-formed id that is no commit here is refused, naming it" 2 "" \
    "0000000000000000000000000000000000000000"
SKILL_GATE_BASE=$BASE

# -- --list -------------------------------------------------------------------

commit_case edit:skills/alpha/SKILL.md edit:skills/alpha/scripts/x.sh edit:skills/beta/evals/evals.json \
    edit:scripts/check-handoff.sh
run_gate --list
want=$(printf 'check-skill alpha\ncheck-skill beta\nscript-cases --all')
if [ "$RC" = 0 ] && [ "$OUT" = "$want" ] && [ ! -s "$RECORD" ]; then
    pass "--list prints the checks in run order and runs nothing"
else
    fail "--list prints the checks in run order and runs nothing" "rc=$RC record=$(record) output: $OUT"
fi

for args in "--bogus" "--list --list" "alpha"; do
    # Word splitting is the point: each entry is an argument list.
    # shellcheck disable=SC2086
    run_gate $args
    expect "the argument list [$args] is a usage error" 2 "" "usage: scripts/skill-gate.sh [--list]"
done

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
