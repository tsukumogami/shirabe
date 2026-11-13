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
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/resume-probe.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }
command -v koto >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "SKIP: koto or jq not on PATH -- no case ran"; exit 0; }

T="$(mktemp -d "${TMPDIR:-/tmp}/resume-probe-test.XXXXXX")" || exit 1
T="$(cd -P "$T" && pwd -P)" || exit 1
ktg_on_exit 'case "$T" in */resume-probe-test.*) rm -rf "$T" ;; esac'
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
    printf '%s\n' "$out" >"$T/out"
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
repo;               : >"$R/wip/scope_t_handoff.md"; expect "the old handoff file no longer fires" 10 t none

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
repo; printf 'topic: t\nphase_pointer: 1\nlast_updated: %s\n' "$FRESH" >"$R/wip/scope_t_state.md"; expect "a state file in the staging folder is not read" 10 t none
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

echo "== the lookups run together =="
# A stub koto, named through KOTO_BIN, which the probe and skill-session.sh
# both honour. It answers as a store holding only the keys it is told about
# and no session: a missing name's status is koto's exact not-found reply.
# Env the stub reads, all optional:
#   STUB_LOG        file each call is appended to
#   STUB_SLEEP      seconds every call sleeps
#   STUB_PIDS       file each stub process appends its own pid to
#   STUB_DELAY      space-separated <name>:<secs> or <name>/<key>:<secs>; a
#                   status of <name>, or a context exists of <name> <key>,
#                   sleeps that long before answering (the per-name delay)
#   STUB_GET_DELAY  the same format, for context get only
#   STUB_KEYS       <session>:<key> pairs that exist, space-separated
#   STUB_VALS       a directory; <dir>/<session>/<key> holds a key's bytes,
#                   which makes the key exist and answers its context get
#   STUB_BROKEN     names koto can't tell about: exit 3 with no code from
#                   context exists, a status that isn't JSON (has-work exit 4)
#   STUB_REFUSED    names refused with v0.37.1's own-prefix-empty text: exit 3,
#                   code session_lookup_failed, from status and context exists
#                   (has-work exit 7)
#   STUB_REFUSED2   names refused with v0.37.1's other refusal (no
#                   own-prefix-empty phrase): exit 3, session_lookup_failed
#   STUB_REFUSED0   names refused the v0.37.0 way: exit 2 whose error is not the
#                   exact not-found reply
#   STUB_MSG        when set, replaces the error text of every refusal
STUB="$T/stub/koto"
mkdir -p "$T/stub"
cat >"$STUB" <<'EOF_STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
[ -z "${STUB_PIDS-}" ] || printf '%s\n' "$$" >>"$STUB_PIDS"
sleep "${STUB_SLEEP:-0}"
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
# delay_for <id> <list> -- sleep for the first <id>:<secs> entry in <list>.
delay_for() {
    local e
    for e in $2; do
        case "$e" in "$1":*) sleep "${e##*:}"; return ;; esac
    done
}
own_empty() {
    printf "session '%s' has no copy on this host and the bucket holds none under this directory's prefix ws-a, and koto can't tell whether another directory's prefix holds it: listing the bucket's workspace prefixes failed: io: no answer within 5.44s; nothing was read, so run the command again once the bucket answers" "$1"
}
other_refusal() {
    printf "session '%s' has no copy on this host, and koto can't read the bucket's name index: io: no answer within 5.02s; nothing was read, so run the command again once the bucket answers" "$1"
}
v0370_refusal() {
    printf "listing ws-b/%s/ failed: io: request timed out after 10s" "$1"
}
# refuse <cmd> <name> -- answer with the refusal STUB_REFUSED* names, if any.
refuse() {
    local msg code rc
    if in_list "$2" "${STUB_REFUSED-}"; then msg=$(own_empty "$2"); code=session_lookup_failed; rc=3
    elif in_list "$2" "${STUB_REFUSED2-}"; then msg=$(other_refusal "$2"); code=session_lookup_failed; rc=3
    elif in_list "$2" "${STUB_REFUSED0-}"; then msg=$(v0370_refusal "$2"); code=""; rc=2
    else return 1
    fi
    [ -z "${STUB_MSG-}" ] || msg="$STUB_MSG"
    if [ -n "$code" ]; then
        jq -cn --arg c "$code" --arg m "$1" --arg e "$msg" --arg s "$2" '{code:$c,command:$m,error:$e,session:$s}'
    else
        jq -cn --arg m "$1" --arg e "$msg" '{command:$m,error:$e}'
    fi
    exit "$rc"
}
case "$1" in
    context)
        case "$2" in
            exists)
                delay_for "$3/$4" "${STUB_DELAY-}"; delay_for "$3" "${STUB_DELAY-}"
                [ -n "${STUB_VALS-}" ] && [ -f "$STUB_VALS/$3/$4" ] && exit 0
                in_list "$3:$4" "${STUB_KEYS-}" && exit 0
                in_list "$3" "${STUB_BROKEN-}" && exit 3
                refuse context "$3"
                exit 1
                ;;
            get)
                delay_for "$3/$4" "${STUB_GET_DELAY-}"
                [ -n "${STUB_VALS-}" ] && [ -f "$STUB_VALS/$3/$4" ] && { cat "$STUB_VALS/$3/$4"; exit 0; }
                exit 1
                ;;
        esac
        exit 1
        ;;
    status)
        delay_for "$2" "${STUB_DELAY-}"
        in_list "$2" "${STUB_BROKEN-}" && { printf 'garbage\n'; exit 0; }
        refuse status "$2"
        printf '{"command":"status","error":"workflow '"'"'%s'"'"' not found"}\n' "$2"
        exit 2
        ;;
esac
exit 1
EOF_STUB
chmod +x "$STUB"
export STUB_LOG="$T/stub.log"
export STUB_PIDS="$T/stub.pids"
: >"$STUB_PIDS"

# stubs_gone <label> -- no recorded stub process is still running.
stubs_gone() {
    local p left=""
    [ -s "$STUB_PIDS" ] || { ok "$1: no stub process left (none started)"; return; }
    while read -r p; do
        kill -0 "$p" 2>/dev/null && left="$left $p"
    done <"$STUB_PIDS"
    if [ -z "$left" ]; then ok "$1: no stub process left"; else bad "$1: no stub process left" "still running:$left"; fi
    : >"$STUB_PIDS"
}
# The probe's TMPDIR, so each case can see that its private directory is gone.
PT="$T/probe-tmp"
mkdir -p "$PT"
# tmp_gone <label> -- the probe left nothing in its TMPDIR.
tmp_gone() {
    if [ -z "$(ls -A "$PT")" ]; then ok "$1: its temp directory is gone"; else bad "$1: its temp directory is gone" "$(ls -A "$PT")"; fi
    rm -rf "${PT:?}"/*
}

# On a fresh topic every lookup misses: context exists on scope-t's two keys,
# a koto status for each of the four children (has-work stops there on an
# absent session), and context exists on explore-t's handoff. One after
# another that is the sum of seven lookups; run together, about the slowest.
SLEEP=2
LOOKUPS=7
repo; : >"$STUB_LOG"
start=$(date +%s)
out=$(cd "$R" && STUB_SLEEP=$SLEEP KOTO_BIN="$STUB" TMPDIR="$PT" bash "$S" --topic t --intent none 2>"$T/err"); rc=$?
took=$(($(date +%s) - start))
if [ "$rc" = 10 ] && [ "$out" = "row=10 fresh-start" ]; then
    ok "a fresh topic behind slow lookups is still row 10 ($out)"
else
    bad "a fresh topic behind slow lookups is still row 10" "got $rc: $out $(cat "$T/err")"
fi
want="context exists explore-t handoff/scope.md
context exists scope-t work/prior-run.md
context exists scope-t work/state.md
status brief-t
status design-t
status plan-t
status prd-t"
got=$(sort "$STUB_LOG")
if [ "$got" = "$want" ]; then
    ok "a fresh topic asks koto the same seven lookups, once each"
else
    bad "a fresh topic asks koto the same seven lookups, once each" "$got"
fi
# The bound is half the sum: far above one lookup, far below seven.
if [ "$took" -lt "$SLEEP" ]; then
    bad "a fresh topic's lookups run together" "took ${took} s, less than one ${SLEEP} s lookup: the stub was not called"
elif [ "$took" -lt $((SLEEP * LOOKUPS / 2)) ]; then
    ok "a fresh topic's lookups run together: ${took} s for $LOOKUPS lookups of ${SLEEP} s each"
else
    bad "a fresh topic's lookups run together" "took ${took} s for $LOOKUPS lookups of ${SLEEP} s each: total near the sum, not the slowest one"
fi
tmp_gone "a fresh topic"

# Every answer is in before the ladder runs, and the ladder still reads them
# in its own order: a lookup koto can't answer wins only where the serial
# probe reached it, never past a row that matched first.
repo
STUB_KEYS="explore-t:handoff/scope.md" STUB_BROKEN=scope-t KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect "a state lookup koto cannot answer is cannot-tell, ahead of a present handoff" 2 t none
tmp_gone "a cannot-tell state lookup"
repo
STUB_KEYS="explore-t:handoff/scope.md" STUB_BROKEN=design-t KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect "a child koto cannot report (has-work exit 4) is cannot-tell, ahead of a present handoff" 2 t none
tmp_gone "a has-work exit 4"
# A child koto refuses (has-work exit 7) is unsettled: the run holds at
# resume_route instead of ending (#1792), and the handoff still can't fire
# past it, since row 12 needs every child settled.
repo; : >"$STUB_PIDS"
STUB_KEYS="explore-t:handoff/scope.md" STUB_REFUSED=design-t KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect "a child koto refuses (has-work exit 7) is unsettled, ahead of a present handoff" 3 t none
case "$(grep '^::koto-finding:: lookup=design-t outcome=refused ' "$T/out")" in
    *" koto=session_lookup_failed session 'design-t' has no copy on this host"*)
        ok "a refused child: a finding line for design-t with koto's code and message" ;;
    *) bad "a refused child: a finding line for design-t with koto's code and message" "$(cat "$T/out")" ;;
esac
if [ "$(tail -n 1 "$T/out")" = "row=3 unsettled" ]; then
    ok "a refused child ends with row=3 unsettled"
else
    bad "a refused child ends with row=3 unsettled" "$(cat "$T/out")"
fi
stubs_gone "a has-work exit 7"
tmp_gone "a has-work exit 7"
repo; doc docs/plans/PLAN-t.md Active
STUB_BROKEN="plan-t explore-t" KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect "lookups past a matched row don't count, even ones koto cannot answer" 41 t none
tmp_gone "a Slot 5 row ahead of broken lookups"
repo
STUB_BROKEN=explore-t KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect "a handoff lookup koto cannot answer is cannot-tell" 2 t none
tmp_gone "a cannot-tell handoff lookup"
repo
KOTO_BIN="$T/stub/no-such-koto" TMPDIR="$PT" expect "koto absent: no session can exist" 10 t none
tmp_gone "koto absent"

# A probe killed while it waits (the gate's timeout, say) still removes its
# directory.
repo; : >"$STUB_LOG"
(cd "$R" && STUB_SLEEP=5 KOTO_BIN="$STUB" TMPDIR="$PT" exec bash "$S" --topic t --intent none >/dev/null 2>&1) &
pid=$!
i=0
while [ -z "$(ls -A "$PT")" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
kill -TERM "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
tmp_gone "a probe killed mid-lookup"

echo "== deadline and early answer =="
# expect_within <label> <code> <max-seconds> <topic> <intent> [extra args] --
# expect, and the probe answered in under <max-seconds>.
expect_within() {
    local label="$1" want="$2" max="$3" topic="$4" intent="$5" before after out rc start took
    shift 5
    before=$(snapshot)
    start=$(date +%s)
    out=$(cd "$R" && PATH="$T/bin:$PATH" SCOPE_PROBE_NOW="$NOW" bash "$S" --topic "$topic" --intent "$intent" "$@" 2>"$T/err")
    rc=$?
    took=$(($(date +%s) - start))
    printf '%s\n' "$out" >"$T/out"
    after=$(snapshot)
    if [ "$rc" = "$want" ] && [ "$took" -lt "$max" ]; then
        ok "$label: exit $want in under $max s ($took s)"
    else
        bad "$label: exit $want in under $max s" "got $rc after $took s: $out $(cat "$T/err")"
    fi
    [ "$before" = "$after" ] || bad "$label: the probe wrote nothing" "tree changed"
}

# The five never-opened names of a fresh topic, each lookup 30 s slow.
FRESH_DELAY="explore-t:30 plan-t:30 design-t:30 prd-t:30 brief-t:30"

# #1737: a fresh topic whose lookups run long holds at the probe's own
# deadline, naming each lookup still out, instead of outlasting the gate.
L="Deadline on a fresh topic (#1737, the v0.37.0 shape)"
repo; : >"$STUB_LOG"; : >"$STUB_PIDS"
STUB_DELAY="$FRESH_DELAY" SCOPE_PROBE_DEADLINE=2 KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect_within "$L" 3 5 t none
n=$(grep -c '^::koto-finding::' "$T/out")
if [ "$n" = 5 ]; then ok "$L: five finding lines"; else bad "$L: five finding lines" "got $n: $(cat "$T/out")"; fi
for lk in "explore-t handoff/scope.md" plan-t design-t prd-t brief-t; do
    line=$(grep -F "::koto-finding:: lookup=$lk outcome=deadline next=stop-and-act " "$T/out")
    case "$line" in
        *" koto=none before the deadline") ok "$L: a deadline line for $lk" ;;
        *) bad "$L: a deadline line for $lk" "$(cat "$T/out")" ;;
    esac
done
if [ "$(tail -n 1 "$T/out")" = "row=3 unsettled" ]; then
    ok "$L: ends with row=3 unsettled"
else
    bad "$L: ends with row=3 unsettled" "$(cat "$T/out")"
fi
stubs_gone "$L"
tmp_gone "$L"

# shape <label> -- every finding line has the header's shape: lookup=,
# outcome= and next=, the remedy field on a stop-and-act line, and koto= last.
# Nothing the probe printed names --local-topic.
shape() {
    local l wrong=""
    while IFS= read -r l; do
        case "$l" in ::koto-finding::*) ;; *) continue ;; esac
        printf '%s\n' "$l" | grep -qE '^::koto-finding:: lookup=[a-z0-9-]+( [a-z0-9/._-]+)? outcome=(deadline|refused) next=(tick-again|stop-and-act)( remedy=declare-the-bucket-name-index)? koto=[^=]*$' ||
            wrong="$wrong [$l]"
        case "$l" in
            *" next=stop-and-act remedy=declare-the-bucket-name-index koto="*|*" next=tick-again koto="*) ;;
            *) wrong="$wrong [$l]" ;;
        esac
    done <"$T/out"
    if [ -z "$wrong" ]; then ok "$1: finding lines have their shape"; else bad "$1: finding lines have their shape" "$wrong"; fi
    if grep -q -e '--local-topic' "$T/out" "$T/err"; then
        bad "$1: no output names --local-topic" "$(cat "$T/out" "$T/err")"
    else
        ok "$1: no output names --local-topic"
    fi
}
# nofind <label> -- no finding line.
nofind() {
    if grep -q '::koto-finding::' "$T/out"; then bad "$1: no finding line" "$(cat "$T/out")"; else ok "$1: no finding line"; fi
}
# hasline <label> <text> -- a finding line starts with <text>.
hasline() {
    if grep -qF -- "$2" "$T/out" && [ "$(grep -F -- "$2" "$T/out" | cut -c1-${#2})" = "$2" ]; then
        ok "$1: $2"
    else
        bad "$1: $2" "$(cat "$T/out")"
    fi
}
# after <label> -- the checks every new case ends with.
after() { shape "$1"; stubs_gone "$1"; tmp_gone "$1"; }
# val <session> <key> -- stdin becomes the key's bytes in the stub's store V.
val() { mkdir -p "$(dirname "$V/$1/$2")" && cat >"$V/$1/$2"; }
STATE2=$(printf 'topic: t\nlast_updated: %s\nphase_pointer: 2' "$FRESH")
PRIOR27=$(printf 'outcome: error\nexit: full-run\nintent: continue\nstep: scope:push')

L="early answer on the topic's own keys"
repo; V="$T/vals$N"; printf '%s\n' "$STATE2" | val scope-t work/state.md
STUB_VALS="$V" STUB_DELAY="$FRESH_DELAY" SCOPE_PROBE_DEADLINE=5 KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect_within "$L" 21 3 t none
if [ "$(cat "$T/out")" = "row=21 fresh-phase-2" ]; then ok "$L: row=21 fresh-phase-2 only"; else bad "$L: row=21 fresh-phase-2 only" "$(cat "$T/out")"; fi
nofind "$L"; after "$L"

L="early answer on the artifact tree"
repo; doc docs/plans/PLAN-t.md Active
STUB_DELAY="$FRESH_DELAY" SCOPE_PROBE_DEADLINE=5 KOTO_BIN="$STUB" TMPDIR="$PT" expect_within "$L" 41 3 t none
nofind "$L"; after "$L"

L="early answer on a prior run"
repo; V="$T/vals$N"; printf '%s\n' "$PRIOR27" | val scope-t work/prior-run.md
STUB_VALS="$V" STUB_DELAY="$FRESH_DELAY" SCOPE_PROBE_DEADLINE=5 KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect_within "$L" 27 3 t continue
nofind "$L"; after "$L"

L="a refusal no remaining row needs is ignored"
repo; V="$T/vals$N"; printf '%s\n' "$STATE2" | val scope-t work/state.md
STUB_VALS="$V" STUB_REFUSED="plan-t design-t prd-t brief-t" KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 21 t none
nofind "$L"; after "$L"

# The suite's one slow case: the default deadline, with the kill and the print,
# fits inside the gate's 30 s, and an override past 20 is not honoured.
L="the bound holds without an override"
repo
STUB_DELAY="scope-t:40 explore-t:40 plan-t:40 design-t:40 prd-t:40 brief-t:40" SCOPE_PROBE_DEADLINE=600 \
    KOTO_BIN="$STUB" TMPDIR="$PT" expect_within "$L" 3 25 t none
hasline "$L" "::koto-finding:: lookup=scope-t work/state.md outcome=deadline next=stop-and-act "
after "$L"

L="a slow context get of work/state.md runs under the deadline"
repo; V="$T/vals$N"; printf '%s\n' "$STATE2" | val scope-t work/state.md
STUB_VALS="$V" STUB_GET_DELAY="scope-t/work/state.md:30" SCOPE_PROBE_DEADLINE=2 KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect_within "$L" 3 5 t none
hasline "$L" "::koto-finding:: lookup=scope-t work/state.md outcome=deadline next=stop-and-act "
after "$L"

L="a slow context get of work/prior-run.md runs under the deadline"
repo; V="$T/vals$N"; printf '%s\n' "$PRIOR27" | val scope-t work/prior-run.md
STUB_VALS="$V" STUB_GET_DELAY="scope-t/work/prior-run.md:30" SCOPE_PROBE_DEADLINE=2 KOTO_BIN="$STUB" TMPDIR="$PT" \
    expect_within "$L" 3 5 t continue
hasline "$L" "::koto-finding:: lookup=scope-t work/prior-run.md outcome=deadline next=stop-and-act "
after "$L"

L="a refused state key (v0.37.1) is unsettled"
repo; STUB_REFUSED=scope-t KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 3 t none
hasline "$L" "::koto-finding:: lookup=scope-t work/state.md outcome=refused next=stop-and-act remedy=declare-the-bucket-name-index koto=session_lookup_failed "
after "$L"

L="a refused state key (v0.37.0, exit 2) is unsettled"
repo; STUB_REFUSED0=scope-t KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 3 t none
hasline "$L" "::koto-finding:: lookup=scope-t work/state.md outcome=refused next=tick-again koto=listing ws-b/scope-t/ failed"
after "$L"

L="a child refused with the own-prefix-empty text: stop and act"
repo; STUB_REFUSED=design-t KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 3 t none
hasline "$L" "::koto-finding:: lookup=design-t outcome=refused next=stop-and-act remedy=declare-the-bucket-name-index koto=session_lookup_failed session 'design-t'"
after "$L"

L="a child refused with the other v0.37.1 text: tick again"
repo; STUB_REFUSED2=design-t KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 3 t none
hasline "$L" "::koto-finding:: lookup=design-t outcome=refused next=tick-again koto=session_lookup_failed session 'design-t'"
after "$L"

L="a child refused the v0.37.0 way (has-work exit 7): tick again"
repo; STUB_REFUSED0=design-t KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 3 t none
hasline "$L" "::koto-finding:: lookup=design-t outcome=refused next=tick-again koto=listing ws-b/design-t/ failed"
after "$L"

L="a refused state key ahead of a cannot-tell child"
repo; STUB_REFUSED=scope-t STUB_BROKEN=design-t KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 3 t none
after "$L"
L="a cannot-tell state key ahead of a refused child"
repo; STUB_BROKEN=scope-t STUB_REFUSED=design-t KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 2 t none
stubs_gone "$L"; tmp_gone "$L"

L="a refused handoff on an empty topic is never absent"
repo; STUB_REFUSED=explore-t KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 3 t none
hasline "$L" "::koto-finding:: lookup=explore-t handoff/scope.md outcome=refused "
after "$L"

L="koto's text is reduced by allowlist"
PAD=$(printf '%1000s' '' | tr ' ' p)
MSG=$(printf 'refused at https://user:secret@host.example/p/x?sig=abc $ ; = & \\ ` " < > ::koto-finding:: lookup=forged %s\nsecond line' "$PAD")
repo; STUB_REFUSED=design-t STUB_MSG="$MSG" KOTO_BIN="$STUB" TMPDIR="$PT" expect "$L" 3 t none
n=$(grep -o '::koto-finding::' "$T/out" | wc -l | tr -d ' ')
if [ "$n" = 1 ]; then ok "$L: one finding marker in stdout"; else bad "$L: one finding marker in stdout" "got $n: $(cat "$T/out")"; fi
kv=$(sed -n 's/^::koto-finding:: lookup=design-t .* koto=//p' "$T/out")
case "$kv" in
    "session_lookup_failed refused at https://host.example/p/x "*) ok "$L: the code is kept and the URL cut to scheme, host and path" ;;
    *) bad "$L: the code is kept and the URL cut to scheme, host and path" "$kv" ;;
esac
case "$kv" in
    *secret*|*sig*|*"second line"*|*forged*" "*"="*) bad "$L: no userinfo, query or second line" "$kv" ;;
    *) ok "$L: no userinfo, query or second line" ;;
esac
if [ "${#kv}" -le 300 ] && [ -n "$kv" ]; then ok "$L: koto= is at most 300 characters (${#kv})"; else bad "$L: koto= is at most 300 characters" "${#kv}"; fi
if printf '%s' "$kv" | LC_ALL=C grep -q "[^A-Za-z0-9 ._:/'()-]"; then
    bad "$L: koto= holds only allowed characters" "$kv"
else
    ok "$L: koto= holds only allowed characters"
fi
after "$L"

echo "== --local-topic =="
for v in stated unstated; do
    repo; : >"$STUB_LOG"
    a=$(cd "$R" && KOTO_BIN="$STUB" TMPDIR="$PT" bash "$S" --topic t --intent none 2>&1); ra=$?
    b=$(cd "$R" && KOTO_BIN="$STUB" TMPDIR="$PT" bash "$S" --topic t --intent none --local-topic "$v" 2>&1); rb=$?
    if [ "$ra" = 10 ] && [ "$rb" = "$ra" ] && [ "$a" = "$b" ]; then
        ok "--local-topic $v: the same exit and lines as without it"
    else
        bad "--local-topic $v: the same exit and lines as without it" "$ra [$a] / $rb [$b]"
    fi
    tmp_gone "--local-topic $v"
done
for args in "--local-topic stated --local-topic stated" "--local-topic" "--local-topic maybe" "--local-topic=stated"; do
    repo; : >"$STUB_LOG"
    # shellcheck disable=SC2086
    (cd "$R" && KOTO_BIN="$STUB" TMPDIR="$PT" bash "$S" --topic t --intent none $args >/dev/null 2>&1); rc=$?
    if [ "$rc" = 64 ] && [ ! -s "$STUB_LOG" ]; then
        ok "[$args] is a usage error before any koto call"
    else
        bad "[$args] is a usage error before any koto call" "got $rc, stub log: $(cat "$STUB_LOG")"
    fi
done
usage_line=$(bash "$S" --topic t 2>&1 >/dev/null)
case "$usage_line" in
    *"--local-topic <stated|unstated>"*) ok "the usage line names --local-topic <stated|unstated>" ;;
    *) bad "the usage line names --local-topic <stated|unstated>" "$usage_line" ;;
esac

echo "== the probe's text =="
if grep -nE 'pkill +-f|killall|pgrep +-f' "$S" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then
    bad "the kill never matches by name" "$(grep -nE 'pkill +-f|killall|pgrep +-f' "$S")"
else
    ok "the kill never matches by name"
fi
if grep -nE 'wait -n|declare -A|local -A|mapfile|readarray' "$S" >/dev/null; then
    bad "nothing past bash 3.2" "$(grep -nE 'wait -n|declare -A|local -A|mapfile|readarray' "$S")"
else
    ok "nothing past bash 3.2"
fi
if awk '/SCOPE_PROBE_NOW/ { n = NR } /SCOPE_PROBE_DEADLINE/ && n && NR - n <= 3 { f = 1 } END { exit !f }' "$S"; then
    ok "the header names SCOPE_PROBE_DEADLINE next to SCOPE_PROBE_NOW"
else
    bad "the header names SCOPE_PROBE_DEADLINE next to SCOPE_PROBE_NOW" ""
fi
if grep -n SCOPE_PROBE_DEADLINE "$HERE/../koto-templates/scope.md" >/dev/null; then
    bad "no gate passes SCOPE_PROBE_DEADLINE" "$(grep -n SCOPE_PROBE_DEADLINE "$HERE/../koto-templates/scope.md")"
else
    ok "no gate passes SCOPE_PROBE_DEADLINE"
fi
if grep -n '\[3\]' "$HERE/../references/phases/phase-resume.md" | grep -q 'resume_route'; then
    ok "phase-resume.md has the unsettled row [3], holding at resume_route"
else
    bad "phase-resume.md has the unsettled row [3], holding at resume_route" ""
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
