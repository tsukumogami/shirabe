#!/usr/bin/env bash
# coordinate_engine_test.sh -- the shipped coordinate.md driven through real
# koto, from sessions coordinate-open.sh opens, against the testdata/gh
# stand-in. Check states run their real scripts; agent states take evidence
# the way the coordinator submits it; write scripts (record-open.sh,
# record-write.sh, record-holding.sh) are run by the test between ticks, as
# the agent runs them.
#
# Proves, one line per case:
#   1. dispatch is unreachable without exactly one record (none stops at
#      record_open, two at record_conflict, a record that vanishes routes
#      dispatch_check back to record_find), and once the stand-in holds the
#      record the run reaches pick with no evidence naming it;
#   2. a restart with a record present takes the found arm, never record_open;
#   3. an undisposed deferral holds dispatch_check at deferral_dispose until
#      record-write.sh disposes it, then dispatch is reached;
#   4. `dispatch` holds (the dispatch path's holding_recorded gate) until the
#      Holdings row shows dispatched, so record and wait are unreachable until
#      then;
#   5. a Draft roadmap ends at done_not_active;
#   6. an unread posture reaches posture_ask;
#   7. `koto overrides record` is refused on a check gate and on the dispatch
#      gate, with and without data;
#   8. evidence that contradicts the stand-in doesn't change a check's route;
#   9. every value of wait's event enum reaches its spoke with no
#      template_error;
#  10. two silent quiet checks reach failure and no teardown;
#  11. land is unreachable until a verified head is recorded, and a moved head
#      is refused at land.
#  12. a restart takes over every decision entry before its first dispatch:
#      the unsent escalation rendered once, the proposed one taken up, the
#      unjudged one judged, a sent escalation and a held entry left alone;
#  13. an answer that reverses a supplied decision passes decision_apply as a
#      reversal, and record confirms the Reversals row;
#  14. a close with every feature done and an escalation still out reaches
#      roadmap_blocked, then wait;
#  15. escalate_send to a person, both routes: the question tool's answer comes
#      back from escalate_send, a message's from wait, each to decision_answer.
#  16. from a holding with Branch and Pull request empty, a message report
#      naming its pull request and a leg result carrying `pr` each go through
#      report_link, where holding-link.sh writes the pull request and its
#      headRefName, and on to verify_board reading that pull request with no
#      hand write; a restart's reconcile then reports it open; `done` for a
#      report naming none goes back to wait, never to verify, and the next
#      report naming one gets through; blocked and needs_fix still route with
#      no pull request. verify_board's no-pr arm is unreachable here by
#      design (the gate above keeps such a report out of verify), so its
#      sealed verdict is board-record_test.sh's and its arm the structure
#      test's.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/coordinate_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
REAL_DATE=$(command -v date)
ORIG_PATH=$PATH

# test-lib.sh gives the GitHub DB helpers, the record renderer and the
# ok/bad/eq counters. It also puts testdata/ (the koto stand-in included)
# first on PATH; this suite needs the real koto, so PATH is rebuilt with only
# the gh stand-in in front, and the stand-in koto's variables are dropped.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P)
unset KOTO_STORE KOTO_COMPILED_HASH
# The board fixtures (bt_board, H, MOVED) for the land case.
. "$HERE/testdata/board/helpers.sh"
mkdir -p "$T/bin"
export GH_BOARD_DIR="$T/ghb" COORD_TESTDATA="$HERE/testdata"
mkdir -p "$GH_BOARD_DIR"

# `gh` is testdata/gh (the DB stand-in) for everything but the board reads
# verify_board and land make, which go to testdata/gh-board when its case
# directory holds a response for them: the board's GraphQL snapshot (any
# GraphQL query but the author/editor one) and the REST reads only the board
# makes (runs, jobs, rules, branch, the ref, files, checks).
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
key=
case "${1-} ${2-}" in
    "api graphql") case "$*" in *"editor {"*) ;; *) key=snapshot ;; esac ;;
    "api --method")
        p=${4-}; p=${p%%\?*}
        case "$p" in
            repos/*/*/actions/runs) key=runs ;;
            repos/*/*/actions/runs/*/jobs) i=${p%/jobs}; key="jobs-${i##*/}" ;;
            repos/*/*/rules/branches/*) key=rules ;;
            repos/*/*/branches/*) key=branch ;;
            repos/*/*/git/ref/heads/*) key=ref ;;
            repos/*/*/pulls/*/files) key=files ;;
            repos/*/*/commits/*/check-runs) key=checkruns ;;
            repos/*/*/commits/*/status) key=statuses ;;
        esac ;;
esac
if [ -n "$key" ] && ls "$GH_BOARD_DIR/$key".* >/dev/null 2>&1; then exec "$COORD_TESTDATA/gh-board" "$@"; fi
exec "$COORD_TESTDATA/gh" "$@"
EOF
chmod +x "$T/bin/gh"

# A clock the quiet case can move forward: with $T/clock holding a number of
# seconds, `date` without -d/-r reads that much later. Every other case runs
# on the real clock.
cat > "$T/bin/date" <<EOF
#!/usr/bin/env bash
off=\$(cat "$T/clock" 2>/dev/null) || exec "$REAL_DATE" "\$@"
for a in "\$@"; do case "\$a" in -d*|--date*|-r*|--reference*) exec "$REAL_DATE" "\$@" ;; esac; done
exec "$REAL_DATE" -d "@\$(( \$("$REAL_DATE" +%s) + off ))" "\$@"
EOF
chmod +x "$T/bin/date"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"

# koto refuses a --var value outside its allowlist (a `+` in this checkout's
# path, for one), so PLUGIN_ROOT is a symlink to the repository.
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"

# Two working directories, each a clone-shaped repo whose origin is the host.
# work/ sits in a niwa instance whose settings permit every finishing step, so
# the posture reads `readable`; bare/ has no instance root, so it reads
# `unread`.
for d in work bare; do
    mkdir -p "$T/$d"
    (cd "$T/$d" && git init -q && git remote add origin https://github.com/acme/widgets.git)
done
mkdir -p "$T/work/.niwa" "$T/work/.claude"
echo '{}' > "$T/work/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$T/work/.claude/settings.json"

db_init

# ---- helpers -----------------------------------------------------------------

roadmap_text() { # roadmap_text <status>
    printf -- '---\nstatus: %s\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** Planned\n\n### Feature 2: second\n\n**Dependencies:** Feature 1\n**Status:** Planned\n' "$1"
}
seed_roadmap() { # seed_roadmap <name> [status]
    db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-\($n).md"] = $t' --arg n "$1" --arg t "$(roadmap_text "${2:-Active}")"
}
seed_record() { # seed_record <name> <number> [record-json]: an open record issue
    local j=${3-}
    [ -n "$j" ] || j=$(record_json roadmap "$1")
    db '.issues += [{repo: "acme/widgets", number: $k, title: "Coordinator record: ROADMAP-\($n)", body: $b,
        state: "open", author: "coord", editor: null}]' --arg n "$1" --argjson k "$2" --arg b "$(render "$j" issue)"
}
record_number() { # record_number <name>: the open record issues' numbers
    jq -r --arg t "Coordinator record: ROADMAP-$1" '[.issues[] | select(.title == $t and .state == "open") | .number] | map(tostring) | join(" ")' "$GH_DB"
}

# open_run <name> [workdir]: a fresh session from coordinate-open.sh; sets S
# and WD. Sessions are named to the second, so two opens of one scope wait.
open_run() {
    WD=${2:-$T/work}
    printf '["docs/roadmaps/ROADMAP-%s.md"]' "$1" > "$T/args.json"
    S=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
    [ -n "$S" ]
}
tick() { # tick [koto next args...]: one advance of $S from $WD; stdout is koto's JSON
    (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err")
}
at() { tick "$@" | jq -r '.state // empty'; }            # the state an advance lands on
now_at() { koto status "$S" 2>/dev/null | jq -r '.current_state // .state // empty'; }
logf() { printf '%s/koto-%s.state.jsonl' "$(koto session dir "$S")" "$S"; }
entered() { # entered <state>: how many times the run entered it
    jq -s --arg s "$1" '[.[] | select((.type == "transitioned" or .type == "directed_transition") and .payload.to == $s)] | length' "$(logf)"
}
from_to() { # from_to <from> <to>: the run has an edge from -> to
    jq -s -e --arg f "$1" --arg t "$2" 'any(.[]; (.type == "transitioned" or .type == "directed_transition") and .payload.from == $f and .payload.to == $t)' "$(logf)" >/dev/null
}
write_as_agent() { # write_as_agent <script> <args...>: a write script, run from $WD as the agent runs it
    local s=$1; shift
    (cd "$WD" && bash "$PS/$s" --session "$S" "$@" >"$T/w.out" 2>"$T/w.err")
}
live_body() { # live_body <n>: the stand-in's record body, parsed
    jq -r --argjson n "$1" '.issues[] | select(.number == $n) | .body' "$GH_DB" > "$T/live.md"
    bash "$PS/record-parse.sh" --container issue "$T/live.md"
}
# to_pick <name> <record-json> [number]: seed the roadmap and one record,
# open a run and drive it to pick. Returns non-zero if it doesn't get there.
to_pick() {
    seed_roadmap "$1"
    seed_record "$1" "${3:-7}" "$2"
    open_run "$1" || return 1
    [ "$(at)" = reconcile ] || return 1
    [ "$(at --with-data '{"reconciled":"reported"}')" = pick ]
}
# Captures in koto's charset: no `=` or `,` in a template value either.
unit_row() { holding "$1" "$(jq -nc --arg u "${2:-Feature 1}" '{unit: $u, pull_request: "", branch: ""}')"; }

# ---- 1. exactly one record ---------------------------------------------------
echo "== 1. dispatch needs exactly one record =="
seed_roadmap one
if open_run one; then
    eq "1: no record stops at record_open" record_open "$(at)"
    tick --with-data '{"choice":"dispatch","unit":"feat-1"}' >/dev/null
    eq "1: record_open refuses pick's evidence and stays" record_open "$(now_at)"
    eq "1: dispatch is never entered without a record" 0 "$(entered dispatch)"
    render "$(record_json roadmap one)" issue > "$T/open.md"
    write_as_agent record-open.sh --body-file "$T/open.md"; rc=$?
    eq "1: record-open.sh (agent-run) opens the record" 0 $rc
    N1=$(record_number one)
    eq "1: after record_open the run finds the one record and reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
    eq "1: the next advance reaches pick" pick "$(at --with-data '{"reconciled":"reported"}')"
    NAMED=$(jq -r --arg n "$N1" 'select(.type == "evidence_submitted") | .payload.fields | tostring
        | select(test("(^|[^0-9])" + $n + "([^0-9]|$)") or test("issues/"))' "$(logf)")
    eq "1: no evidence named the record" "" "$NAMED"
    # The record goes away between pick and dispatch_check.
    db '(.issues[] | select(.number == ($n | tonumber))).state = "closed"' --arg n "$N1"
    eq "1: a record closed under the run routes dispatch_check back to record_open" record_open \
        "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')"
    from_to dispatch_check record_find && ok "1: the route was dispatch_check -> record_find" || bad "1: the route was dispatch_check -> record_find"
    eq "1: still no dispatch" 0 "$(entered dispatch)"
else
    bad "1: open a run" "$(cat "$T/open.err")"
fi
seed_roadmap two
seed_record two 20
seed_record two 21
if open_run two; then
    eq "1: two records stop at record_conflict" record_conflict "$(at)"
    eq "1: recheck with both still open stays at record_conflict" record_conflict "$(at --with-data '{"resolution":"recheck"}')"
    eq "1: dispatch is never entered with two records" 0 "$(entered dispatch)"
else
    bad "1: open a run with two records" "$(cat "$T/open.err")"
fi

# ---- 2. restart with a record present ----------------------------------------
echo "== 2. a restart takes the found arm =="
seed_roadmap restart
if open_run restart && [ "$(at)" = record_open ]; then
    render "$(record_json roadmap restart)" issue > "$T/open.md"
    write_as_agent record-open.sh --body-file "$T/open.md"
    at --with-data '{"opened":"opened"}' >/dev/null
    FIRST=$S
    sleep 1
    reset_calls
    if open_run restart; then
        [ "$S" != "$FIRST" ] && ok "2: the restart is a new session" || bad "2: the restart is a new session" "$S"
        eq "2: the restart reaches reconcile" reconcile "$(at)"
        eq "2: the restart never enters record_open" 0 "$(entered record_open)"
        from_to record_find reconcile_pass && from_to reconcile_pass reconcile && ok "2: record_find -> reconcile_pass -> reconcile is the found arm" || bad "2: record_find -> reconcile_pass -> reconcile is the found arm"
        grep -q '^issue create' "$GH_DB.calls" && bad "2: nothing opens a second record" "$(grep '^issue create' "$GH_DB.calls")" \
            || ok "2: nothing opens a second record"
        eq "2: one record still" 1 "$(record_number restart | wc -w | tr -d ' ')"
        N7=$(record_number restart)
        case "$(cd "$T/work" && koto context get "$S" record_url 2>&1)" in
            https://github.com/*/issues/"$N7") ok "2: the found record's URL is in context for the terminal results" ;;
            *) bad "2: the found record's URL is in context for the terminal results" "$(cd "$T/work" && koto context get "$S" record_url 2>&1)" ;;
        esac
    else
        bad "2: reopen the run" "$(cat "$T/open.err")"
    fi
else
    bad "2: first run reaches record_open" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 3. an undisposed deferral ----------------------------------------------
echo "== 3. an undisposed deferral holds dispatch =="
REC3=$(record_json roadmap defer | jq -c '.deferrals = [{deferral: "retry flaky job", reason: "out of scope", raised: "2020-01-01T00:00Z", disposition: ""}]')
if to_pick defer "$REC3" 30; then
    eq "3: an undisposed deferral routes dispatch_check to deferral_dispose" deferral_dispose \
        "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')"
    eq "3: rewritten without a write returns to deferral_dispose" deferral_dispose "$(at --with-data '{"rewritten":"rewritten"}')"
    eq "3: dispatch is unreachable while it is open" 0 "$(entered dispatch)"
    # Edit the live body keeping its Written: line: record-write.sh compares it
    # with the live record's before writing.
    live_body 30 | jq -c '.deferrals[0].disposition = "closed: moot"' > "$T/rec.json"
    jq 'del(.written)' "$T/rec.json" | bash "$PS/record-render.sh" --container issue --written "$(jq -r .written "$T/rec.json")" > "$T/body.md"
    write_as_agent record-write.sh --body-file "$T/body.md"; rc=$?
    eq "3: record-write.sh (agent-run) disposes the deferral" 0 $rc
    eq "3: once disposed, dispatch_check reaches dispatch" dispatch "$(at --with-data '{"rewritten":"rewritten"}')"
else
    bad "3: reach pick" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 4. the record step holds until the Holdings row shows -------------------
echo "== 4. dispatch reaches wait only through a recorded holding =="
# dispatched_row <topic>: the row dispatch-worker.sh leaves once the worker is
# confirmed launched.
dispatched_row() { holding "$1" "$(jq -nc '{unit: "Feature 1", pull_request: "", branch: "", dispatch_status: "dispatched", return_path: "message"}')"; }
if to_pick hold "$(record_json roadmap hold)" 40 && [ "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')" = dispatch ]; then
    eq "4: dispatched without a row holds at dispatch" dispatch "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
    eq "4: another tick still holds" dispatch "$(at)"
    eq "4: record is unreachable before the row" 0 "$(entered record)"
    eq "4: wait is unreachable before the row" 0 "$(entered wait)"
    sleep 1
    dispatched_row feat-1 > "$T/row.json"
    write_as_agent record-holding.sh --topic feat-1 --row-file "$T/row.json"; rc=$?
    eq "4: record-holding.sh (agent-run) writes the row" 0 $rc
    eq "4: with the row on GitHub, dispatch leaves, record confirms and reaches pick" pick "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
    eq "4: and pick can now hold into wait" wait "$(at --with-data '{"choice":"hold"}')"
else
    bad "4: reach dispatch" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 5. a Draft roadmap ------------------------------------------------------
echo "== 5. a Draft roadmap =="
seed_roadmap drafty Draft
if open_run drafty; then
    eq "5: a Draft roadmap ends at done_not_active" done_not_active "$(at)"
    eq "5: nothing past start" 0 "$(entered start_posture)"
else
    bad "5: open a run" "$(cat "$T/open.err")"
fi

# ---- 6. an unread posture ----------------------------------------------------
echo "== 6. an unread posture =="
seed_roadmap unread
seed_record unread 60
if open_run unread "$T/bare"; then
    eq "6: the found record still reaches reconcile" reconcile "$(at)"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name POSTURE)" in
        unread*) ok "6: the posture captured is unread" ;;
        *) bad "6: the posture captured is unread" ;;
    esac
    eq "6: reconcile routes an unread posture to posture_ask" posture_ask "$(at --with-data '{"reconciled":"reported"}')"
    eq "6: pick_facts is not reached" 0 "$(entered pick_facts)"
else
    bad "6: open a run" "$(cat "$T/open.err")"
fi

# ---- 7. no override on a check gate ------------------------------------------
echo "== 7. overrides are refused on check gates =="
seed_roadmap ovr
seed_record ovr 70
if open_run ovr && [ "$(at)" = reconcile ]; then
    try_override() { # try_override <label> <gate> [data]
        local rc
        if [ -n "${3-}" ]; then
            (cd "$WD" && koto overrides record "$S" --gate "$2" --rationale "test" --with-data "$3" >"$T/ovr.out" 2>&1); rc=$?
        else
            (cd "$WD" && koto overrides record "$S" --gate "$2" --rationale "test" >"$T/ovr.out" 2>&1); rc=$?
        fi
        [ $rc -ne 0 ] && ok "7: $1 is refused" || bad "7: $1 is refused" "$(head -c 300 "$T/ovr.out")"
    }
    try_override "an override of reconcile_posture without data" reconcile_posture
    try_override "an override of reconcile_posture with data" reconcile_posture '{"exit_code":25}'
    at --with-data '{"reconciled":"reported"}' >/dev/null
    at --with-data '{"choice":"dispatch","unit":"feat-1"}' >/dev/null
    if [ "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')" = dispatch ]; then
        try_override "an override of holding_recorded without data" holding_recorded
        try_override "an override of holding_recorded with data" holding_recorded '{"exit_code":0}'
        eq "7: dispatch stays blocked after the attempts" dispatch "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
    else
        bad "7: reach a blocked dispatch" "$(cat "$T/tick.err")"
    fi
    OV=$(cd "$WD" && koto overrides list "$S" 2>/dev/null | jq -r '[.. | objects | select(has("gate"))] | length' 2>/dev/null)
    eq "7: no override is on record" 0 "${OV:-0}"
    eq "7: the log has no override event" 0 "$(jq -s '[.[] | select((.type // "") | test("override"))] | length' "$(logf)")"
else
    bad "7: reach reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 8. evidence can't change a check's route --------------------------------
echo "== 8. contradicting evidence doesn't move a check =="
seed_roadmap contra
if open_run contra && [ "$(at)" = record_open ]; then
    eq "8: 'opened' with no record on GitHub routes record_find back to record_open" record_open "$(at --with-data '{"opened":"opened"}')"
    eq "8: record_find read none twice" 2 "$(jq -s '[.[] | select(.type == "variable_captured" and .payload.key == "RECORD_FIND" and (.payload.value | startswith("none ")))] | length' "$(logf)")"
else
    bad "8: reach record_open" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
seed_roadmap contra2
seed_record contra2 80
if open_run contra2 "$T/bare" && [ "$(at)" = reconcile ]; then
    R=$(tick --with-data '{"reconciled":"reported","merge":"permitted"}')
    [ -n "$(printf '%s' "$R" | jq -r '.error.code // empty')" ] && ok "8: reconcile refuses a field it doesn't accept" || bad "8: reconcile refuses a field it doesn't accept" "$R"
    eq "8: an unread posture routes to posture_ask whatever the evidence says" posture_ask "$(at --with-data '{"reconciled":"reported"}')"
else
    bad "8: reach reconcile with an unread posture" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
if to_pick contra3 "$(record_json roadmap contra3)" 81 && [ "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')" = dispatch ] \
    && [ "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')" = dispatch ]; then
    R=$(tick --with-data '{"dispatched":"sent","topic":"feat-1","confirmed":"yes"}')
    [ -n "$(printf '%s' "$R" | jq -r '.error.code // empty')" ] && ok "8: dispatch refuses evidence claiming it is confirmed" || bad "8: dispatch refuses evidence claiming it is confirmed" "$R"
    eq "8: and stays at dispatch, the row not on GitHub" dispatch "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
else
    bad "8: reach a blocked dispatch" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 9. every wait event reaches its spoke -----------------------------------
echo "== 9. every wait event reaches its spoke =="
# Each value is submitted from a fresh wait visit: a run of its own, driven to
# wait the legitimate way (pick -> hold). No `koto next --to` is used: koto
# 0.13 only directs along a declared edge, and most spokes have none back to
# wait.
J=$(koto template compile "$TPL" 2>/dev/null)
if [ -n "$J" ] && [ -r "$J" ]; then
    EVENTS=$(jq -r '.states.wait.accepts.event.values[]' "$J")
    [ -n "$EVENTS" ] || bad "9: wait accepts an event enum" "none in the compiled template"
    # Record numbers from 901 up, one per event, clear of every other case's
    # record however many events wait accepts.
    n=900
    for ev in $EVENTS; do
        n=$((n + 1))
        # The expected spoke: the arm for this value, and for a `vars.` guard
        # the one that holds at roadmap scope (DISCIPLINE unset).
        WANT=$(jq -r --arg e "$ev" '[.states.wait.transitions[] | select(.when.event == $e)
            | select((.when["vars.DISCIPLINE"] // null) == null or .when["vars.DISCIPLINE"].is_set == false) | .target][0] // ""' "$J")
        if ! to_pick "spoke-$ev" "$(record_json roadmap "spoke-$ev" | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')" "$n" \
            || [ "$(at --with-data '{"choice":"hold"}')" != wait ]; then
            bad "9: reach wait for $ev" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"; continue
        fi
        SEQ=$(jq -s 'map(.seq) | max' "$(logf)")
        # answer and evidence name their decision (and an answer its round):
        # wait's arms for them need the fields present.
        R=$(tick --with-data "$(jq -nc --arg e "$ev" '{event: $e, unit: "feat-1"}
            + (if $e == "answer" then {decision: "1", round: "1"} elif $e == "evidence" then {decision: "1"} else {} end)')")
        GOT=$(jq -r --argjson q "$SEQ" 'select(.seq > $q and .type == "transitioned" and .payload.from == "wait") | .payload.to' "$(logf)" | head -1)
        TE=$( { printf '%s\n' "$R"; cat "$T/tick.err"; jq -c --argjson q "$SEQ" 'select(.seq > $q)' "$(logf)"; } | grep -c 'template_error')
        if [ -n "$WANT" ] && [ "$GOT" = "$WANT" ] && [ "$TE" = 0 ]; then
            ok "9: event $ev reaches $WANT"
        else
            bad "9: event $ev reaches ${WANT:-its spoke}" "got [$GOT], template_error lines $TE, response $(printf '%s' "$R" | head -c 300)"
        fi
    done
else
    bad "9: compile the template" "koto template compile failed"
fi

# ---- 10. two silent quiet checks ---------------------------------------------
echo "== 10. two silent checks reach failure =="
if to_pick quiet "$(record_json roadmap quiet | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')" 100 \
    && [ "$(at --with-data '{"choice":"hold"}')" = wait ]; then
    echo 1860 > "$T/clock"
    eq "10: the first silent check sends a status message" status_message "$(at --with-data '{"event":"quiet"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name QUIET)" in
        "first-silence feat-1 "*) ok "10: the first sweep reads first-silence" ;; *) bad "10: the first sweep reads first-silence" ;;
    esac
    eq "10: status sent returns to wait" wait "$(at --with-data '{"sent":"sent"}')"
    echo 3720 > "$T/clock"
    eq "10: the second silent check reaches failure" failure "$(at --with-data '{"event":"quiet"}')"
    rm -f "$T/clock"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name QUIET)" in
        "second-silence feat-1 "*) ok "10: the second sweep reads second-silence" ;; *) bad "10: the second sweep reads second-silence" ;;
    esac
    eq "10: no teardown" 0 "$(entered teardown)"
    eq "10: the holding is still on the record" feat-1 "$(live_body 100 | jq -r '.holdings[0].worker')"
else
    rm -f "$T/clock"
    bad "10: reach wait with a holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 11. land ----------------------------------------------------------------
echo "== 11. land needs a recorded verified head, and refuses a moved one =="
# land_run <name> <number>: a run whose holding links acme/widgets#12, driven
# wait -> report -> classify_report (done) -> verify, then on through
# verify_board (the complete-board fixture) to verified_confirm.
land_row() { # land_row [verified-head]
    holding feat-1 "$(jq -nc --arg h "${1-}" '{unit: "Feature 1", branch: "feat/x", verified_head: $h,
        pull_request: "[#12](https://github.com/acme/widgets/pull/12)"}')"
}
land_run() {
    db '.prs = [{repo: "acme/widgets", number: 12, title: "feat", body: "", state: "OPEN", isDraft: false,
        isCrossRepository: false, baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice",
        mergeStateStatus: "CLEAN"}]' --arg h "$H"
    bt_board complete-board
    to_pick "$1" "$(record_json roadmap "$1" | jq -c --argjson h "$(land_row)" '.holdings = [$h]')" "$2" || return 1
    [ "$(at --with-data '{"choice":"hold"}')" = wait ] || return 1
    [ "$(at --with-data '{"event":"report","unit":"feat-1","report":"PR #12 is ready; CI is green."}')" = classify_report ] || return 1
    [ "$(at --with-data '{"classification":"done"}')" = verify ] || return 1
    [ "$(at --with-data '{"predicted":"recorded","prediction":"every job green"}')" = verified_confirm ]
}
record_verified() { # the agent writes the verified head into the unit's row
    land_row "$H" > "$T/row.json"
    write_as_agent record-holding.sh --topic feat-1 --row-file "$T/row.json"
}
if land_run landing 110; then
    ok "11: a verified board with no recorded head stops at verified_confirm"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name VERIFIED)" in
        "verified 12 $H "*) ok "11: VERIFIED is the sealed verified head" ;; *) bad "11: VERIFIED is the sealed verified head" ;;
    esac
    eq "11: another tick still holds at verified_confirm" verified_confirm "$(at)"
    eq "11: land is not entered before the head is recorded" 0 "$(entered land)"
    record_verified
    eq "11: record-holding.sh (agent-run) records the verified head" 0 $?
    eq "11: with the head recorded, land permits and reaches land_merge" land_merge "$(at)"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name LAND)" in
        "permit 12 $H "*) ok "11: LAND is the sealed permit" ;; *) bad "11: LAND is the sealed permit" ;;
    esac
else
    bad "11: reach verified_confirm" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
if land_run moving 111; then
    record_verified
    # A push after verify: the board's live head (snapshot and ref) moves.
    jq -c --arg m "$MOVED" '.data.repository.pullRequest.headRefOid = $m | .data.repository.pullRequest.commits.nodes[0].commit.oid = $m' \
        "$GH_BOARD_DIR/snapshot.out" > "$T/s" && mv "$T/s" "$GH_BOARD_DIR/snapshot.out"
    jq -c --arg m "$MOVED" '.object.sha = $m' "$GH_BOARD_DIR/ref.out" > "$T/r" && mv "$T/r" "$GH_BOARD_DIR/ref.out"
    eq "11: a head moved since verify is refused at land, back to verify" verify "$(at)"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name LAND)" in
        "moved 12 $H $MOVED "*) ok "11: LAND reads moved" ;; *) bad "11: LAND reads moved" ;;
    esac
    eq "11: land_merge is never entered" 0 "$(entered land_merge)"
else
    bad "11: reach verified_confirm for the moved head" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"

# ---- 16. a report's pull request reaches the holding --------------------------
echo "== 16. a report's pull request reaches an empty holding; done with none doesn't stick =="
# empty_row [return path]: feat-1's holding with Branch and Pull request empty,
# as dispatch-worker.sh writes it.
empty_row() {
    holding feat-1 "$(jq -nc --arg r "${1:-message}" '{unit: "Feature 1", branch: "", verified_head: "", pull_request: "", return_path: $r}')"
}
# empty_run <name> <number> [return path]: a run at wait whose one holding has
# no pull request yet; acme/widgets#12 is open on feat/w-head, board complete.
empty_run() {
    db '.prs = [{repo: "acme/widgets", number: 12, title: "feat", body: "", state: "OPEN", isDraft: false,
        isCrossRepository: false, baseRefName: "main", headRefName: "feat/w-head", headRefOid: $h, author: "alice",
        mergeStateStatus: "CLEAN"}]' --arg h "$H"
    bt_board complete-board
    to_pick "$1" "$(record_json roadmap "$1" | jq -c --argjson h "$(empty_row "${3-}")" '.holdings = [$h]')" "$2" || return 1
    [ "$(at --with-data '{"choice":"hold"}')" = wait ]
}
linked_row() { live_body "$1" | jq -c '.holdings[] | select(.worker == "feat-1") | {branch, pull_request}'; }
LINKED='{"branch":"feat/w-head","pull_request":"[#12](https://github.com/acme/widgets/pull/12)"}'
# link_through <label> <number>: at report_link, the agent runs holding-link.sh
# and submits written; the run reads the holding again and reaches
# classify_report, then verify_board reads #12's board.
link_through() {
    write_as_agent holding-link.sh
    eq "16 $1: holding-link.sh (agent-run) writes the pull request" 0 $?
    eq "16 $1: Branch is the headRefName GitHub reports, Pull request the link" "$LINKED" "$(linked_row "$2")"
    eq "16 $1: written reads the holding again and reaches classify_report" classify_report "$(at --with-data '{"linked":"written"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name REPORT)" in
        "holding 12 feat-1 "*) ok "16 $1: report_facts now reads the holding's own pull request" ;;
        *) bad "16 $1: report_facts now reads the holding's own pull request" ;;
    esac
    eq "16 $1: done reaches verify" verify "$(at --with-data '{"classification":"done"}')"
    eq "16 $1: verify_board reads #12 with no hand write" verified_confirm "$(at --with-data '{"predicted":"recorded","prediction":"every job green"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name VERIFIED)" in
        "verified 12 $H "*) ok "16 $1: VERIFIED is #12's head" ;; *) bad "16 $1: VERIFIED is #12's head" ;;
    esac
}
if empty_run linkmsg 125; then
    eq "16 message: a report naming its pull request goes to report_link" report_link \
        "$(at --with-data '{"event":"report","unit":"feat-1","report":"PR is ready","pull_request":"https://github.com/acme/widgets/pull/12"}')"
    link_through message 125
    # A restart reads the pull request off the holding: reconcile reports its
    # state, not "no pull request".
    sleep 1
    if open_run linkmsg && [ "$(at)" = reconcile ]; then
        koto context get "$S" reconcile/report.md > "$T/rec.md" 2>/dev/null
        grep -q '| `feat-1` | \[#12\](https://github.com/acme/widgets/pull/12) | executing; open (measured)' "$T/rec.md" && ok "16 message: a restart's reconcile reports the pull request open" \
            || bad "16 message: a restart's reconcile reports the pull request open" "$(cat "$T/rec.md")"
        grep -q 'no pull request' "$T/rec.md" && bad "16 message: and never says no pull request" "$(cat "$T/rec.md")" \
            || ok "16 message: and never says no pull request"
    else
        bad "16 message: the restart reaches reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    fi
else
    bad "16 message: reach wait with an empty holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# The leg path: a stand-in worker template whose result names #12.
mkdir -p "$T/tpl"
cat > "$T/tpl/deliver.md" <<'EOF'
---
name: deliver
version: "1.0"
description: a stand-in worker for coordinate_engine_test.sh
initial_state: work
states:
  work:
    accepts:
      finish:
        type: enum
        values: [go]
        required: true
    transitions:
      - target: done
        when:
          finish: go
  done:
    terminal: true
    result:
      outcome: ready
      pr: https://github.com/acme/widgets/pull/12
---
## work
Stand-in.
## done
Done.
EOF
LREQ=$(cd "$T/work" && koto request create --role deliver --template deliver.md --inputs '{}' \
    --requested-by coord --coordinator-of-record coordinate-linkleg | jq -r .request_id)
if [ -n "$LREQ" ] && empty_run linkleg 126 "leg $LREQ:deliver"; then
    (cd "$T" && koto init deliver-feat-1 --template "$T/tpl/deliver.md" --koto-leg "$LREQ:deliver" > /dev/null 2> "$T/child.err" \
        && koto next deliver-feat-1 --with-data '{"finish":"go"}' > /dev/null 2>&1) \
        || bad "16 leg: the stand-in worker promotes its result" "$(cat "$T/child.err")"
    eq "16 leg: a leg result carrying pr goes to report_link" report_link "$(at --with-data '{"event":"leg"}')"
    link_through leg 126
else
    bad "16 leg: reach wait with a leg-bound empty holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# done for a report naming no pull request goes back to the hub, never to a
# verify_board that can't leave; the next report naming one gets through.
if empty_run linknone 127; then
    eq "16 none: a report naming no pull request reaches classify_report" classify_report \
        "$(at --with-data '{"event":"report","unit":"feat-1","report":"all done"}')"
    eq "16 none: done with no pull request goes back to wait" wait "$(at --with-data '{"classification":"done"}')"
    eq "16 none: verify is never entered" 0 "$(entered verify)"
    eq "16 none: verify_board is never entered" 0 "$(entered verify_board)"
    eq "16 none: the worker's next report, naming it, reaches report_link" report_link \
        "$(at --with-data '{"event":"report","unit":"feat-1","report":"PR is up","pull_request":"acme/widgets#12"}')"
    link_through none 127
else
    bad "16 none: reach wait with an empty holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
# blocked and needs_fix don't route on report_pr, so a holding with no pull
# request still takes them.
for c in "blocked surface 128" "needs_fix rebrief 129"; do
    set -- $c
    if empty_run "linkno$1" "$3"; then
        at --with-data '{"event":"report","unit":"feat-1","report":"stuck before any PR"}' > /dev/null
        eq "16 none: $1 with no pull request reaches $2" "$2" "$(at --with-data "{\"classification\":\"$1\"}")"
    else
        bad "16 none: reach wait for $1" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    fi
done
rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"

# ---- 12 to 15. the decision loop ----------------------------------------------
# dent <n> <state> [jq object to merge]: one Decisions entry. The escalation
# fields go through --arg: bash 3.2 misreads escaped quotes nested in "$(...)".
dent() {
    local extra=${3-}
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg n "$1" --arg s "$2" --argjson x "$extra" '{decision: $n, round: "0", question: "Ship the loader first?",
        options: "ship -- the loader is ready\nwait -- the registry needs it", state: $s,
        source: "self [20260925T080000Z raise \($n)]", updated: "2026-09-26T07:00Z"} + $x'
}
ESCF='{"round": "1", "verdict": "escalate", "recommendation": "wait", "reason": "the registry lands Friday", "context": "The loader is done.", "problem": "The registry depends on it.", "grounds": "scope", "target": "a person"}'
SENT=$(jq -nc --argjson e "$ESCF" '$e + {asked: "2026-09-26T07:30Z"}')
UNSENT=$(jq -nc --argjson e "$ESCF" '$e + {owed: "escalation"}')
with_decisions() { # with_decisions <name> <entries-json>
    record_json roadmap "$1" | jq -c --argjson e "$2" '.decisions = {next: 20, entries: $e}'
}
# to_reconciled <name> <record-json> <number>: open a run and tick past
# reconcile; sets S and REACHED, the state it lands on. Never called in $(...),
# which would keep S from the caller.
to_reconciled() {
    REACHED=
    seed_roadmap "$1"; seed_record "$1" "$3" "$2"
    open_run "$1" || return 1
    [ "$(at)" = reconcile ] || return 1
    REACHED=$(at --with-data '{"reconciled":"reported"}')
}
entry_of() { live_body "$1" | jq -c --arg d "$2" '.decisions.entries[] | select(.decision == $d)'; }

echo "== 12. a restart takes over every entry before its first dispatch =="
E12=$(jq -nc --argjson a "$(dent 1 proposed)" --argjson b "$(dent 2 coordinator-verdict)" \
    --argjson c "$(dent 3 escalated "$SENT")" --argjson d "$(dent 4 coordinator-verdict '{"verdict": "hold", "reason": "waits on the benchmark"}')" \
    --argjson e "$(dent 5 escalated "$UNSENT")" '[$a, $b, $c, $d, $e]')
to_reconciled takeover "$(with_decisions takeover "$E12")" 120
if [ "$REACHED" = escalate_send ]; then
    ok "12: the unsent escalation is rendered first, before any dispatch"
    eq "12: the render names entry 5" "message escalation 5 1" "$(bash "$PS/coord-log.sh" capture --session "$S" --name ESCALATE_MESSAGE | cut -d' ' -f1-4)"
    write_as_agent record-decision.sh --sent --route message
    eq "12: --sent (agent-run) marks it" 0 $?
    eq "12: then the proposed entry is taken up" decision_take "$(at --with-data '{"sent":"sent"}')"
    write_as_agent record-decision.sh --take
    eq "12: then the unjudged one is routed for a verdict" decision_verdict "$(at --with-data '{"taken":"taken"}')"
    eq "12: its entry is in coord/decision.json" 1 "$(koto context get "$S" coord/decision.json | jq -r .decision)"
    write_as_agent record-decision.sh --settle --outcome ship --reason "the loader is ready"
    eq "12: then entry 2" decision_verdict "$(at --with-data '{"verdict":"settle","rationale":"ready"}')"
    write_as_agent record-decision.sh --settle --outcome wait --reason "the registry needs it"
    eq "12: with nothing owed the run reaches pick" pick "$(at --with-data '{"verdict":"settle","rationale":"needed"}')"
    eq "12: the escalation was rendered once" 1 "$(entered escalate)"
    eq "12: nothing was dispatched first" 0 "$(entered dispatch_check)"
    eq "12: the sent escalation and the held entry are left alone" "escalated 2026-09-26T07:30Z|coordinator-verdict hold" \
        "$(entry_of 120 3 | jq -r '"\(.state) \(.asked)"')|$(entry_of 120 4 | jq -r '"\(.state) \(.verdict)"')"
else
    bad "12: reach escalate_send" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo "== 13. an answer that reverses a supplied decision is a reversal =="
E13=$(jq -nc --argjson a "$(dent 1 escalated "$SENT")" '[$a | .source = "dispatcher [20260925T080000Z raise 1]"]')
to_reconciled reversal "$(with_decisions reversal "$E13")" 130
if [ "$REACHED" = pick ] \
    && [ "$(at --with-data '{"choice":"hold"}')" = wait ]; then
    eq "13: the answer reaches decision_answer" decision_answer "$(at --with-data '{"event":"answer","decision":"1","round":"1"}')"
    write_as_agent record-decision.sh --answer --outcome ship
    eq "13: --answer (agent-run) settles the entry" "settled|ship; reason: the loader is ready|a person" \
        "$(entry_of 130 1 | jq -r '"\(.state)|\(.outcome)|\(.decided_by)"')"
    eq "13: a reversal goes to decision_apply" decision_apply "$(at --with-data '{"answered":"reversal"}')"
    # The evidence comes first: record waits until the record is written after it.
    eq "13: the reversal holds at record until the record is written" record "$(at --with-data '{"change":"reversal"}')"
    sleep 1
    live_body 130 | jq -c '.reversals += [{date: $d, reversed: "wait for the registry", now: "ship the loader first", reason: "the answer to decision 1", from: "a person"}]' \
        --arg d "$(date -u +%Y-%m-%dT%H:%MZ)" > "$T/rev.json"
    # Edited from the live body, so it carries the live written time.
    jq 'del(.written)' "$T/rev.json" > "$T/rev.next.json"
    bash "$PS/record-render.sh" --container issue --written "$(jq -r .written "$T/rev.json")" "$T/rev.next.json" > "$T/rev.md"
    write_as_agent record-write.sh --body-file "$T/rev.md"
    eq "13: record-write.sh (agent-run) adds the Reversals row" 0 $?
    # The entry came from the dispatcher, so its settle owes it a reply, which
    # the loop renders before it goes on.
    eq "13: record confirms the Reversals row, and the reply to the dispatcher is rendered" decision_reply_send "$(at)"
    write_as_agent record-decision.sh --sent
    eq "13: with the reply sent the run goes on" pick "$(at --with-data '{"sent":"sent"}')"
    eq "13: the Reversals row is on the record" 1 "$(live_body 130 | jq '.reversals | length')"
else
    bad "13: reach wait" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo "== 14. a close with an escalation still out reports it and waits =="
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-closing.md"] = $t' --arg t "$(roadmap_text Active | sed 's/\*\*Status:\*\* Planned/**Status:** Done/')"
seed_record closing 140 "$(with_decisions closing "$(jq -nc --argjson a "$(dent 1 escalated "$SENT")" '[$a]')")"
if open_run closing && [ "$(at)" = reconcile ]; then
    eq "14: every feature done and an escalation sent reaches roadmap_blocked" roadmap_blocked "$(at --with-data '{"reconciled":"reported"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name ROADMAP_CLOSE)" in
        "decisions "*) ok "14: the close is blocked on decisions" ;; *) bad "14: the close is blocked on decisions" ;;
    esac
    eq "14: noted returns to wait, where the answer arrives" wait "$(at --with-data '{"noted":"noted"}')"
else
    bad "14: reach reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo "== 15. escalate_send's two routes to a person =="
for route in tool message; do
    n=$([ "$route" = tool ] && echo 150 || echo 151)
    to_reconciled "route-$route" "$(with_decisions "route-$route" "$(jq -nc --argjson a "$(dent 1 escalated "$UNSENT")" '[$a]')")" "$n"
    if [ "$REACHED" = escalate_send ]; then
        write_as_agent record-decision.sh --sent --route "$route"
        case "$(entry_of "$n" 1 | jq -r .evidence)" in
            *"asked by $route"*) ok "15 $route: the route is recorded on the entry" ;; *) bad "15 $route: the route is recorded on the entry" "$(cat "$T/w.err") $(entry_of "$n" 1)" ;;
        esac
        if [ "$route" = tool ]; then
            eq "15 tool: the answer comes back from escalate_send" decision_answer "$(at --with-data '{"sent":"answered","decision":"1","round":"1"}')"
        else
            eq "15 message: sent goes on, and nothing is owed" pick "$(at --with-data '{"sent":"sent"}')"
            eq "15 message: the loop goes on to wait" wait "$(at --with-data '{"choice":"hold"}')"
            eq "15 message: an answer naming no round doesn't leave wait" wait "$(at --with-data '{"event":"answer","decision":"1"}')"
            eq "15 message: the answer comes back from wait" decision_answer "$(at --with-data '{"event":"answer","decision":"1","round":"1"}')"
        fi
        write_as_agent record-decision.sh --answer --outcome wait
        eq "15 $route: --answer settles the entry" "settled a person" "$(entry_of "$n" 1 | jq -r '"\(.state) \(.decided_by)"')"
        eq "15 $route: recorded goes back through decision_next to pick" pick "$(at --with-data '{"answered":"recorded"}')"
        if [ "$route" = message ]; then
            # A later answer naming nothing isn't carried by the earlier visit's fields.
            eq "15 message: back at wait" wait "$(at --with-data '{"choice":"hold"}')"
            eq "15 message: a later answer naming no decision doesn't leave wait" wait "$(at --with-data '{"event":"answer"}')"
        fi
    else
        bad "15 $route: reach escalate_send" "$(cat "$T/open.err" "$T/tick.err" "$T/w.err" 2>/dev/null)"
    fi
done

# ---- 16. a unit that isn't a topic is refused where it is read ----------------
echo "== 16. a unit's tag in place of its topic goes back to be submitted again =="
if to_pick untopic "$(record_json roadmap untopic | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')" 960; then
    # pick's unit is a dispatch topic, never the unit's tag (shirabe#492).
    eq "16: dispatch with unit \"Feature 1\" comes back to pick" pick "$(at --with-data '{"choice":"dispatch","unit":"Feature 1"}')"
    from_to dispatch_check pick_facts && ok "16: the route was dispatch_check -> pick_facts" || bad "16: the route was dispatch_check -> pick_facts"
    eq "16: dispatch is never entered" 0 "$(entered dispatch)"
    case "$(cd "$WD" && koto context get "$S" coord/dispatch_check.json 2>/dev/null | jq -r .reason)" in
        "pick's unit [Feature 1] is not a dispatch topic"*) ok "16: the refusal names the field and the value" ;;
        *) bad "16: the refusal names the field and the value" "$(cd "$WD" && koto context get "$S" coord/dispatch_check.json 2>&1)" ;;
    esac
    eq "16: the same pick with its topic goes on to dispatch" dispatch "$(at --with-data '{"choice":"dispatch","unit":"feat-2"}')"
else
    bad "16: reach pick" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
if to_pick unmerged "$(record_json roadmap unmerged | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')" 961 \
    && [ "$(at --with-data '{"choice":"hold"}')" = wait ]; then
    # A merged event naming the unit's title rather than its topic (shirabe#547).
    eq "16: merged with a unit's title comes back to wait" wait "$(at --with-data '{"event":"merged","unit":"Feature 16: example"}')"
    from_to merged_facts wait && ok "16: the route was merged_facts -> wait" || bad "16: the route was merged_facts -> wait"
    case "$(cd "$WD" && koto context get "$S" coord/merged_facts.json 2>/dev/null | jq -r .reason)" in
        "the merged event's unit [Feature 16: example] is not a topic; unit takes the dispatch topic of a holding"*)
            ok "16: the refusal names the field, the value and what it takes" ;;
        *) bad "16: the refusal names the field, the value and what it takes" "$(cd "$WD" && koto context get "$S" coord/merged_facts.json 2>&1)" ;;
    esac
    tick --with-data '{"event":"quiet"}' >/dev/null
    from_to wait quiet_check && ok "16: back at wait, the next event is taken" || bad "16: back at wait, the next event is taken" "$(now_at)"
else
    bad "16: reach wait" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo
echo "coordinate_engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
