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
#
# The probe reads koto sessions: the run's own state (key work/state.md of
# scope-<topic>) and prior-run facts (work/prior-run.md), the children's
# sessions (Slot 6) and the /explore handoff (key handoff/scope.md of
# explore-<topic>). Each repository gets its own session store
# (KOTO_SESSIONS_BASE) and the suite a private HOME, so no case sees another's
# sessions or the developer's own. The suite needs koto and jq and SKIPs
# without them; the CI job asserts koto is present first.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/resume-probe.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }
command -v koto >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "SKIP: koto or jq not on PATH -- no case ran"; exit 0; }

T="$(mktemp -d "${TMPDIR:-/tmp}/resume-probe-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
export HOME="$T/home"
mkdir -p "$HOME"
SS="$HERE/../../../scripts/skill-session.sh"
HAVE_KOTO=0
command -v koto >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && HAVE_KOTO=1
# The staging folder's name, built so no line here spells a path inside it.
SF="wi""p"

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
    export KOTO_SESSIONS_BASE="$T/store$N"
    mkdir -p "$KOTO_SESSIONS_BASE"
}

# child <skill> <topic> [done|abandoned] -- open the child's session from the
# repository, give it a work/ key, and close it when a close value is given.
# Returns 1 (after reporting) when a step fails.
child() {
    local s="$1-$2"
    (cd "$R" && bash "$SS" open "$1" "$2" >/dev/null 2>"$T/child-err") &&
        printf 'partial\n' | (cd "$R" && koto context add "$s" work/summary.md 2>>"$T/child-err") &&
        { [ -z "${3-}" ] || (cd "$R" && bash "$SS" close "$s" "$3" >/dev/null 2>>"$T/child-err"); } &&
        return 0
    bad "set up the $s session" "$(cat "$T/child-err")"
    return 1
}

# sessions <label> -- true when koto is here; otherwise reports the skip.
sessions() {
    [ "$HAVE_KOTO" -eq 1 ] && return 0
    printf 'SKIP %s (koto or jq not on PATH)\n' "$1"
    return 1
}

doc() { # doc <path> <status>
    printf -- '---\nschema: x/v1\nstatus: %s\n---\n\n# Doc\n' "$2" >"$R/$1"
}

STORE_TEMPLATE="$HERE/../../../koto-templates/skill-session.md"

# putkey <session> <key> -- open the session from the store template when it
# is not there yet, then write stdin as the key.
putkey() {
    koto context exists "$1" "$2" >/dev/null 2>&1 || true
    koto status "$1" >/dev/null 2>&1 || koto init "$1" --template "$STORE_TEMPLATE" >/dev/null 2>"$T/put-err" ||
        { bad "open $1" "$(cat "$T/put-err")"; return 1; }
    koto context add "$1" "$2" >/dev/null 2>"$T/put-err" || { bad "write $2 of $1" "$(cat "$T/put-err")"; return 1; }
}

state() { # state <topic> <extra-lines> -- key work/state.md of scope-<topic>
    printf 'topic: %s\nlast_updated: %s\nphase_pointer: %s\n%s' "$1" "${LU:-$FRESH}" "${PP:-2}" "$2" | putkey "scope-$1" work/state.md
}

# prior <topic> <lines> -- key work/prior-run.md of scope-<topic>
prior() { printf '%s' "$2" | putkey "scope-$1" work/prior-run.md; }

snapshot() {
    (cd "$R" && find . -path ./.git -prune -o -print | sort && git status --porcelain)
    find "$KOTO_SESSIONS_BASE" -path '*/ctx/*' -type f ! -name '*.lock' -exec cksum {} + 2>/dev/null | sort
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
repo;               printf 'h\n' | putkey explore-t handoff/scope.md; expect "an /explore handoff: key handoff/scope.md in a live explore-t" 12 t none
repo;               printf 'h\n' | putkey explore-t handoff/scope.md && koto next explore-t --no-cleanup --with-data '{"close":"done"}' >/dev/null 2>&1
                    expect "an /explore handoff in a finished explore-t still fires" 12 t none
repo;               printf 'x\n' | putkey explore-t work/other.md; expect "a live explore-t without handoff/scope.md does not fire" 10 t none
repo;               printf 'h\n' | putkey explore-t handoff/charter.md; expect "a charter handoff is not /scope's" 10 t none
repo;               printf 'h\n' | putkey explore-other handoff/scope.md; expect "another topic's handoff does not fire" 10 t none
repo;               expect "an absent explore-t session does not fire" 10 t none
repo;               : >"$R/wip/""scope_t_handoff.md"; expect "the old handoff file no longer fires" 10 t none

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
repo; printf 'phase_pointer: 1\n' | putkey scope-t work/state.md; expect "no topic line" 25 t none
repo; printf 'topic: t\nphase_pointer: 1\nlast_updated: %s\n' "$FRESH" >"$R/wip/""scope_t_state.md"; expect "a state file in the staging folder is not read" 10 t none
repo; state t ""; (cd "$R" && koto next scope-t --no-cleanup --with-data '{"close":"done"}' >/dev/null 2>&1); expect "a finished session's work/state.md still reads" 21 t none
repo; state other ""; expect "another topic's state is not this run's" 10 t none
repo; printf 'topic: other\nlast_updated: %s\nphase_pointer: 1\n' "$FRESH" | putkey scope-t work/state.md; expect "a state naming another topic is malformed" 25 t none
repo; printf '' | putkey scope-t work/state.md; expect "an empty work/state.md is malformed" 25 t none
repo; printf '\377\376garbage: [\n' | putkey scope-t work/state.md; expect "binary garbage in work/state.md is malformed" 25 t none
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
repo; state t "exit: re-evaluation
boundary: brief
decision_record_sub_shape: rejection
publish_error: scope:push
";                                 expect "a BRIEF-boundary rejection is a valid re-evaluation exit" 28 t stop
repo; state t "exit: re-evaluation
boundary: brief
decision_record_sub_shape: re-evaluation
";                                 expect "a BRIEF boundary with the re-evaluation sub-shape is refused" 25 t none
repo; state t "exit: abandonment-forced
triggering_child: prd
publish_error: scope:push
";                                 expect "abandonment publish retry" 29 t continue
repo; LU=$STALE state t "exit: full-run
plan_execution_mode: single-pr
publish_error: scope:push
";                                 expect "a publish retry is not held back by staleness" 27 t stop

echo "== publish retry from work/prior-run.md =="
repo; prior t "outcome: error
exit: full-run
intent: continue
step: scope:push
";                                 expect "prior-run: full-run push failure" 27 t continue
repo; prior t "outcome: error
exit: re-evaluation
intent: stop
step: scope:pr-create
";                                 expect "prior-run: re-evaluation pr-create failure" 28 t stop
repo; prior t "outcome: error
exit: abandonment-forced
intent: continue
step: scope:push
";                                 expect "prior-run: abandonment failure" 29 t continue
repo; prior t "outcome: error
exit: full-run
intent: continue
step: scope:push
";                                 expect "prior-run: no intent on the run, no retry" 10 t none
repo; prior t "outcome: landed
exit: full-run
intent: continue
";                                 expect "prior-run: no failed step falls through to the artifact rows" 10 t continue
repo; prior t "outcome: error
exit: full-run
intent: continue
step: scope:elsewhere
";                                 expect "prior-run: a step outside its set is no match" 10 t continue
repo; prior t "outcome: error
exit: sideways
intent: continue
step: scope:push
";                                 expect "prior-run: an exit outside its set is no match" 10 t continue
repo; prior t "outcome: error
exit: full-run
intent: maybe
step: scope:push
";                                 expect "prior-run: an intent outside its set is no match" 10 t continue
repo; prior t "outcome: error
exit: full-run
exit: re-evaluation
intent: continue
step: scope:push
";                                 expect "prior-run: a repeated field is no match" 10 t continue
repo; prior t "outcome: error
exit: full-run
intent: continue
step: scope:push
"; doc docs/plans/PLAN-t.md Active; expect "prior-run: a publish retry comes before the artifact rows" 27 t continue
repo; prior t "outcome: landed
exit: full-run
intent: continue
"; doc docs/plans/PLAN-t.md Active; expect "prior-run: with no failed step the artifact rows decide (PLAN Active, intent: republish)" 40 t continue
repo; state t "" && prior t "outcome: error
exit: full-run
intent: continue
step: scope:push
";                                 expect "work/state.md wins over work/prior-run.md" 21 t continue

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
if sessions "a Slot 5 row wins over a Slot 6 partial"; then
    repo; doc docs/prds/PRD-t.md Draft; child plan t &&
        expect "a Slot 5 row wins over a Slot 6 partial" 48 t none
fi
repo; PP=1 state t ""; doc docs/plans/PLAN-t.md Active
expect "a state file wins over the artifact tree" 20 t none
if sessions "a partial wins over the handoff"; then
    repo; child prd t && : >"$R/$SF/scope_t_handoff.md" &&
        expect "a partial wins over the handoff" 62 t none
    repo; child plan t && child brief t &&
        expect "the most-downstream partial wins" 60 t none
fi

echo "== Slot 6: child partials, read from the children's sessions =="
if sessions "Slot 6 child sessions"; then
    repo; child plan t &&   expect "plan partial: a live plan-t with a work/ key" 60 t none
    repo; child design t && expect "design partial: a live design-t with a work/ key" 61 t none
    repo; child prd t &&    expect "prd partial: a live prd-t with a work/ key" 62 t none
    repo; child brief t &&  expect "brief partial: a live brief-t with a work/ key" 63 t none
    # The staging folder is empty in every case above; this one says so outright.
    repo; child design t &&
        if [ -z "$(ls -A "$R/$SF")" ]; then
            expect "an empty staging folder and a live design-t route back into the design hop" 61 t none
        else
            bad "the staging folder is empty" "$(ls -A "$R/$SF")"
        fi
    repo; child design t done &&
        expect "the same design-t finished routes past it" 10 t none
    repo; child design t abandoned &&
        expect "an abandoned design-t routes past it too" 10 t none
    repo; (cd "$R" && bash "$SS" open design t >/dev/null 2>&1)
        expect "a live design-t with no work/ key is not a partial" 10 t none
    repo; child design t && git -C "$R" checkout -q -b main &&
        expect "a design-t opened on another branch is not this run's partial" 10 t none
    repo; child design other-topic &&
        expect "another topic's session is not a partial" 10 t none
fi
repo; : >"$R/$SF/plan_t_analysis.md"; : >"$R/$SF/design_t_coordination.json"
expect "files in the staging folder are no partial: only sessions are read" 10 t none

echo "== the documented initial shape is the shape the probe reads =="
# Phase 0's initial state-file block, with its placeholders filled in, has to
# resume at pointer 0; the old phase-0 / UNSET spelling has to be malformed.
P0="$HERE/../references/phases/phase-0-setup.md"
# The state key, taken from the probe's own STATE= line.
STATE_REL=$(sed -n 's/^STATE="\(.*\)"$/\1/p' "$S" | sed 's/\${TOPIC}/t/')
repo
SFILE="$T/initial-state.md"
awk '/^## Initial .*Shape$/{f=1} f&&/^```yaml/{y=1;next} y&&/^```/{exit} y' "$P0" |
    grep -v '^consumed_upstream:' |
    sed -e 's/<slug>/t/; s/scope-<topic>/scope-t/; s/<continue|stop|none>.*$/none/' \
        -e "s/<ISO-8601 timestamp>/$FRESH/" >"$SFILE"
putkey scope-t work/state.md <"$SFILE"
if [ "$STATE_REL" = "work/state.md" ] && grep -q '^phase_pointer: 0$' "$SFILE" && grep -q '^exit:$' "$SFILE"; then
    ok "phase-0-setup.md writes phase_pointer: 0 and an empty exit:"
else
    bad "phase-0-setup.md writes phase_pointer: 0 and an empty exit:" "[$STATE_REL] $(cat "$SFILE" 2>&1)"
fi
expect "the documented initial state file" 20 t none
repo; PP=phase-0 state t "";            expect "a phase-0 pointer is malformed" 25 t none
repo; state t "exit: UNSET
";                                      expect "a literal UNSET exit is malformed" 25 t none
if grep -rnE '^(phase_pointer: phase-[0-9]|exit: UNSET)$' "$HERE"/*_test.sh "$HERE/testdata" >/dev/null 2>&1 ||
   grep -nE 'phase_pointer: phase-[0-9]|exit: UNSET' "$HERE/../evals/evals.json" >/dev/null 2>&1; then
    bad "no scope fixture or eval writes phase-N or UNSET" \
        "$(grep -rnE '^(phase_pointer: phase-[0-9]|exit: UNSET)$' "$HERE"/*_test.sh "$HERE/testdata"; grep -nE 'phase_pointer: phase-[0-9]|exit: UNSET' "$HERE/../evals/evals.json" | cut -c1-120)"
else
    ok "no scope fixture or eval writes phase-N or UNSET"
fi

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
