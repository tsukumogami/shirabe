#!/usr/bin/env bash
# resume-probe_test.sh -- one fixture per resume-ladder row, plus the
# first-match order where two rows could fire.
#
# Usage: bash skills/scope/scripts/resume-probe_test.sh
#
# Every case builds a fresh repository under TMPDIR, puts the files the row
# keys on in place, runs resume-probe.sh from inside it, and asserts the exit
# code. A snapshot of the tree before and after each run asserts the probe
# wrote nothing, and a gh stub on PATH fails the suite if it is ever called.
# Needs bash, git and awk.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/resume-probe.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }

T="$(mktemp -d "${TMPDIR:-/tmp}/resume-probe-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/gh.log"\nexit 1\n' "$T" >"$T/bin/gh"
chmod +x "$T/bin/gh"

# A fixed clock: 2026-06-10T00:00:00Z.
NOW=1781049600
FRESH="2026-06-09T12:00:00Z"
STALE="2026-06-01T00:00:00Z"

N=0
R=""
# repo [branch] -- a fresh repository; sets R.
repo() {
    N=$((N + 1))
    R="$T/r$N"
    mkdir -p "$R/docs/plans" "$R/docs/designs/current" "$R/docs/prds" "$R/docs/briefs" "$R/wip"
    git -C "$R" init -q
    git -C "$R" checkout -q -b "${1:-work}"
}

doc() { # doc <path> <status>
    printf -- '---\nschema: x/v1\nstatus: %s\n---\n\n# Doc\n' "$2" >"$R/$1"
}

state() { # state <topic> <extra-lines>
    printf 'topic: %s\nlast_updated: %s\nphase_pointer: %s\n%s' "$1" "${LU:-$FRESH}" "${PP:-2}" "$2" >"$R/wip/scope_$1_state.md"
}

snapshot() {
    (cd "$R" && find . -path ./.git -prune -o -print | sort && git status --porcelain)
}

# expect <label> <code> <topic> <intent> [extra args]
expect() {
    local label="$1" want="$2" topic="$3" intent="$4" before after out rc
    shift 4
    before=$(snapshot)
    out=$(cd "$R" && PATH="$T/bin:$PATH" SCOPE_PROBE_NOW="$NOW" bash "$S" --topic "$topic" --intent "$intent" "$@" 2>"$T/err")
    rc=$?
    after=$(snapshot)
    if [ "$rc" = "$want" ]; then
        ok "$label: exit $want ($out)"
    else
        bad "$label: exit $want" "got $rc: $out $(cat "$T/err")"
    fi
    [ "$before" = "$after" ] || bad "$label: the probe wrote nothing" "tree changed"
}

echo "== meta-ladder tail and Slot 7 =="
repo main;          expect "nothing on disk, unrelated branch" 10 t none
repo docs/t-work;   expect "nothing on disk, topic branch" 11 t-work none
repo;               : >"$R/wip/scope_t_handoff.md"; expect "an /explore handoff" 12 t none

echo "== fresh state file, by phase pointer =="
repo; PP=1 state t ""; expect "pointer 1" 20 t none
repo; PP=0 state t ""; expect "pointer 0" 20 t none
repo; PP=2 state t ""; expect "pointer 2" 21 t none
repo; PP=3 state t ""; expect "pointer 3" 22 t continue

echo "== stale, malformed, exit set =="
repo; LU=$STALE state t "";        expect "stale state file" 24 t none
repo; LU=$STALE state t "";        expect "stale, --ignore-stale resumes at the pointer" 21 t none --ignore-stale
repo; LU="last week" state t "";   expect "an unparseable last_updated" 25 t none
repo; state t "exit: sideways
";                                 expect "an exit outside the enum" 25 t none
repo; state t "intent: maybe
";                                 expect "an intent outside the enum" 25 t none
repo; state t "intent: stop
intent: continue
";                                 expect "a duplicated field" 25 t none
repo; printf 'phase_pointer: 1\n' >"$R/wip/scope_t_state.md"; expect "no topic line" 25 t none
repo; state t "exit: re-evaluation
boundary: prd
";                                 expect "re-evaluation without its sub-shape" 25 t none
repo; state t "publish_error: scope:push
";                                 expect "publish_error without an exit" 25 t continue
repo; state t "exit: full-run
plan_execution_mode: single-pr
publish_error: scope:elsewhere
";                                 expect "publish_error outside its enum" 25 t continue
repo; state t "exit: full-run
plan_execution_mode: bogus
";                                 expect "plan_execution_mode: bogus is refused" 25 t none
repo; state t "exit: full-run
plan_execution_mode: coordinated
";                                 expect "plan_execution_mode: coordinated is accepted" 26 t none
repo; state t "exit: full-run
plan_execution_mode: single-pr
published_pr: https://evil.example/acme/w/pull/1
";                                 expect "published_pr outside the URL pattern" 25 t continue
repo; state t "exit: full-run
plan_execution_mode: single-pr
";                                 expect "exit set, no publish pending" 26 t continue
repo; state t "exit: full-run
plan_execution_mode: single-pr
publish_error: scope:pr-create
";                                 expect "exit set with publish_error but no intent" 26 t none

echo "== publish retry =="
repo; state t "exit: full-run
plan_execution_mode: coordinated
publish_error: scope:pr-create
intent: continue
";                                 expect "full-run publish retry" 27 t continue
repo; state t "exit: re-evaluation
boundary: design
decision_record_sub_shape: rejection
publish_error: scope:push
";                                 expect "re-evaluation publish retry" 28 t stop
repo; state t "exit: abandonment-forced
triggering_child: prd
publish_error: scope:push
";                                 expect "abandonment publish retry" 29 t continue
repo; LU=$STALE state t "exit: full-run
plan_execution_mode: single-pr
publish_error: scope:push
";                                 expect "a publish retry is not held back by staleness" 27 t stop

echo "== Slot 5: the PLAN =="
repo; doc docs/plans/PLAN-t.md Active; expect "Active PLAN, intent set" 40 t continue
repo; doc docs/plans/PLAN-t.md Draft;  expect "Draft PLAN, intent set" 40 t stop
repo; doc docs/plans/PLAN-t.md Active; expect "Active PLAN, no intent" 41 t none
repo; doc docs/plans/PLAN-t.md Done;   expect "Done PLAN" 42 t none
repo; doc docs/plans/PLAN-t.md Done;   expect "Done PLAN, intent set" 42 t continue
repo; doc docs/plans/PLAN-t.md Draft;  expect "Draft PLAN, no intent" 43 t none
repo; printf 'no frontmatter\n' >"$R/docs/plans/PLAN-t.md"; expect "a PLAN whose status cannot be read" 2 t none

echo "== Slot 5: executed, DESIGN, PRD, BRIEF =="
repo; doc docs/designs/current/DESIGN-t.md Current; doc docs/prds/PRD-t.md Done
expect "executed: no PLAN, DESIGN under current/, intent set" 44 t continue
repo; doc docs/designs/current/DESIGN-t.md Current; doc docs/prds/PRD-t.md Done
expect "an executed topic without intent reaches the boundary, never 44" 45 t none
repo; doc docs/designs/current/DESIGN-t.md Accepted; expect "Accepted DESIGN under current/" 45 t none
repo; doc docs/designs/DESIGN-t.md Accepted;         expect "Accepted DESIGN in docs/designs/" 45 t none
repo; doc docs/designs/DESIGN-t.md Accepted;         expect "a DESIGN outside current/ is not executed, even with intent" 45 t continue
repo; doc docs/designs/DESIGN-t.md Proposed;         expect "Proposed DESIGN" 46 t none
repo; doc docs/prds/PRD-t.md Accepted;               expect "Accepted PRD" 47 t none
repo; doc docs/prds/PRD-t.md Draft;                  expect "Draft PRD" 48 t none
repo; doc docs/briefs/BRIEF-t.md Accepted;           expect "Accepted BRIEF" 49 t none
repo; doc docs/briefs/BRIEF-t.md Done;               expect "Done BRIEF" 49 t none
repo; doc docs/briefs/BRIEF-t.md Draft;              expect "Draft BRIEF" 50 t none
repo; doc docs/designs/DESIGN-t.md Superseded;       expect "a Superseded DESIGN falls through" 10 t none

echo "== first match where two rows could fire =="
repo; doc docs/designs/DESIGN-t.md Accepted; doc docs/prds/PRD-t.md Accepted
expect "DESIGN boundary before PRD boundary" 45 t none
repo; doc docs/plans/PLAN-t.md Active; doc docs/designs/current/DESIGN-t.md Current
expect "a PLAN wins over the executed row" 40 t continue
repo; doc docs/prds/PRD-t.md Draft; : >"$R/wip/plan_t_analysis.md"
expect "a Slot 5 row wins over a Slot 6 partial" 48 t none
repo; PP=1 state t ""; doc docs/plans/PLAN-t.md Active
expect "a state file wins over the artifact tree" 20 t none
repo; : >"$R/wip/prd_t_decisions.md"; : >"$R/wip/scope_t_handoff.md"
expect "a partial wins over the handoff" 62 t none

echo "== Slot 6: child partials =="
repo; : >"$R/wip/plan_t_analysis.md";              expect "plan partial" 60 t none
repo; : >"$R/wip/design_t_coordination.json";      expect "design partial" 61 t none
repo; : >"$R/wip/design_t_summary.md";             expect "a design feeder doc is not a partial" 10 t none
repo; : >"$R/wip/prd_t_decisions.md";              expect "prd partial" 62 t none
repo; : >"$R/wip/prd_t_scope.md";                  expect "a prd feeder doc is not a partial" 10 t none
repo; : >"$R/wip/brief_t_discover.md";             expect "brief partial" 63 t none

echo "== cannot tell and usage =="
repo; expect "an invalid topic" 2 Bad-Topic none
repo; expect "an invalid intent" 2 t maybe
repo; out=$(cd "$R" && bash "$S" --topic t 2>/dev/null); rc=$?
if [ "$rc" = 64 ]; then ok "a missing --intent is a usage error"; else bad "a missing --intent is a usage error" "got $rc"; fi

if [ -s "$T/gh.log" ]; then bad "the probe never calls gh" "$(cat "$T/gh.log")"; else ok "the probe never calls gh"; fi
if grep -nE '(^|[^A-Za-z_-])(gh|curl|wget)[[:space:]]' "$S" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then
    bad "no network call appears in the probe" ""
else
    ok "no network call appears in the probe"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
