#!/usr/bin/env bash
# coordinate_1_engine_test.sh -- part 1 of 4 of the coordinate engine cases: the
# shipped coordinate.md driven through real koto, from sessions
# coordinate-open.sh opens, against the testdata/gh stand-in. The four parts
# share their setup and helpers (testdata/coordinate-engine-lib.sh) and run side
# by side under scripts/check-skill.sh; the cases are split in file order, so a
# case that reuses an earlier case's fixtures stays in that case's part. Cases
# 7 and 8 start from runs cases 1, 4 and 6 drove and saved (snap_save), and
# case 9's later events from the run its first event drove to wait, rather
# than driving the same prefix again. Every record is in the run's koto
# session; none is on GitHub.
#
# Proves, one line per case:
#   1. dispatch is unreachable without the run's record: none stops at
#      record_open, state-open.sh builds the scope's empty record (no body is
#      handed to it) in the run's session and opens nothing on GitHub, the find then reaches reconcile with the session
#      recorded as the run's store, and the run reaches pick with no evidence
#      naming the record, after a new record's empty stored set held the
#      reconcile handover gate until state-stored-set.sh filled it;
#   2. a restart while the run is live resumes it (resumed=1, the same
#      session, where it stood) and never enters record_open again or looks
#      for a record on GitHub; the run's record names its session;
#   2b. a restart from a plugin at another root, whose coordinate.md differs in
#      text alone and whose compat table lists the run's template at its compat
#      number, resumes the run (resumed=1, rebound= naming PLUGIN_ROOT, the run's
#      PLUGIN_ROOT now that root, provenance passing there); a plugin whose
#      table doesn't list the run's template carries it into a new run, naming
#      the compat table;
#   3. an undisposed deferral holds dispatch_check at deferral_dispose until
#      state-write.sh --state-file disposes it, then dispatch is reached;
#   4. `dispatch` holds (the dispatch path's holding_recorded gate) until the
#      Holdings row shows dispatched, so record and wait are unreachable until
#      then, and record holds until the holding has its Work row;
#   5. a Draft roadmap ends at done_not_active;
#   6. an unread posture reaches posture_ask;
#   7. `koto overrides record` is refused on a check gate and on the dispatch
#      gate, with and without data;
#   8. evidence that contradicts the stand-in doesn't change a check's route;
#   9. every value of wait's event enum reaches its spoke with no
#      template_error.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/coordinate_1_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"

# ---- 1. no record, then the one record_open writes ----------------------------
echo "== 1. dispatch needs the run's record =="
seed_roadmap one
reset_calls
if open_run one; then
    eq "1: no record stops at record_open" record_open "$(at)"
    snap_save state-open
    tick --with-data '{"choice":"dispatch","unit":"feat-1"}' >/dev/null
    eq "1: record_open refuses pick's evidence and stays" record_open "$(now_at)"
    eq "1: dispatch is never entered without a record" 0 "$(entered dispatch)"
    write_as_agent state-open.sh; rc=$?
    eq "1: state-open.sh (agent-run) opens the record" 0 $rc
    (cd "$WD" && koto context exists "$S" record/meta) && ok "1:   ... in the run's session" || bad "1:   ... in the run's session" "$(cat "$T/w.err")"
    grep -Eq '^(issue (create|edit|close)|pr create)' "$GH_DB.calls" \
        && bad "1:   ... opening nothing on GitHub" "$(grep -E '^(issue|pr) ' "$GH_DB.calls")" || ok "1:   ... opening nothing on GitHub"
    eq "1: after record_open the run finds the record and reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
    eq "1: the find records the session as the run's store" session \
        "$( (cd "$WD" && koto context get "$S" coord/source.json 2>/dev/null) | jq -r '.source // empty')"
    eq "1: a new record's empty stored set holds the handover gate" reconcile "$(at --with-data '{"reconciled":"reported"}')"
    write_as_agent state-stored-set.sh --run arguments "docs/roadmaps/ROADMAP-one.md" --by "the human" \
        && write_as_agent state-stored-set.sh --run cap 5 --by "the human" \
        && write_as_agent state-stored-set.sh --run coordinator coord-test --by coord-test \
        && write_as_agent state-stored-set.sh --run reports-to "the human" --by "the human"
    eq "1: state-stored-set.sh (agent-run) writes the arguments, the cap, the address and who it reports to" 0 $?
    eq "1: the next advance reaches pick" pick "$(at --with-data '{"reconciled":"reported"}')"
    NAMED=$(jq -r 'select(.type == "evidence_submitted") | .payload.fields | tostring | select(test("issues/"))' "$(logf)")
    eq "1: no evidence named a record" "" "$NAMED"
else
    bad "1: open a run" "$(cat "$T/open.err")"
fi

# ---- 2. a restart while the run is live -----------------------------------------
echo "== 2. a restart resumes the run =="
seed_roadmap restart
if open_run restart && [ "$(at)" = record_open ]; then
    write_as_agent state-open.sh
    eq "2: the first run reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
    from_to record_find reconcile_pass && from_to reconcile_pass reconcile && ok "2: record_find -> reconcile_pass -> reconcile is the found arm" \
        || bad "2: record_find -> reconcile_pass -> reconcile is the found arm"
    # The terminal results' record field names the run's session, its record.
    eq "2: the found record, the run's session, is in context for the terminal results" "$S" "$(cd "$WD" && koto context get "$S" record_url 2>&1)"
    FIRST=$S
    sleep 1
    reset_calls
    if open_run restart; then
        eq "2: the restart resumes the first run" "$FIRST" "$S"
        grep -qx 'resumed=1' <<< "$OPEN_OUT" && ok "2:   ... printing resumed=1" || bad "2:   ... printing resumed=1" "$OPEN_OUT"
        eq "2:   ... where it stood" reconcile "$(now_at)"
        eq "2: the restart never enters record_open again" 1 "$(entered record_open)"
        eq "2: and never looks for a record on GitHub" 0 "$(grep -c 'issues?state=open' "$GH_DB.calls")"
        grep -Eq '^(issue|pr) (create|edit|close)' "$GH_DB.calls" && bad "2: nothing is opened on GitHub" "$(grep -E '^(issue|pr) ' "$GH_DB.calls")" \
            || ok "2: nothing is opened on GitHub"
    else
        bad "2: restart the run" "$(cat "$T/open.err")"
    fi
else
    bad "2: first run reaches record_open" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 2b. a restart from another plugin root, across a text-only change -------
echo "== 2b. a restart from another plugin root resumes a compatible run =="
# plugin_copy <dir> <compat>: the plugin copied to <dir>, its coordinate.md
# changed in a variable's description alone (so another compiled template with
# the same structure), and its compat table's compat number set to <compat>.
# At compat 1 the table is the shipped one, listing that structure at 1; at a
# higher number the structure stays listed at 1 and the plugin has moved on.
plugin_copy() {
    local d=$1 n=$2 c0 c1
    mkdir -p "$d" && cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$d/" || return 1
    sed -i.bak 's/Absolute path to the shirabe plugin root/Absolute path to the plugin root/' \
        "$d/skills/coordinate/koto-templates/coordinate.md" && rm -f "$d/skills/coordinate/koto-templates/coordinate.md.bak"
    c0=$(koto template compile "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.md") || return 1
    c1=$(koto template compile "$d/skills/coordinate/koto-templates/coordinate.md") || return 1
    [ "$(basename "$c0")" != "$(basename "$c1")" ] || return 1
    jq --argjson n "$n" '.compat = $n' "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.compat.json" \
        > "$d/skills/coordinate/koto-templates/coordinate.compat.json"
}
seed_roadmap rebind
if plugin_copy "$T/plugin-b" 1 && plugin_copy "$T/plugin-c" 2 && open_run rebind && [ "$(at)" = record_open ]; then
    write_as_agent state-open.sh
    eq "2b: the first run reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
    FIRST=$S
    sleep 1
    SAVED_PR=$PR SAVED_PS=$PS
    PR="$T/plugin-b" PS="$T/plugin-b/skills/coordinate/scripts"
    if open_run rebind; then
        eq "2b: a plugin at another root, its template changed in text alone, resumes the run" "$FIRST" "$S"
        grep -qx 'resumed=1' <<< "$OPEN_OUT" && ok "2b:   ... printing resumed=1" || bad "2b:   ... printing resumed=1" "$OPEN_OUT $(cat "$T/open.err")"
        grep -q '^rebound=.*PLUGIN_ROOT' <<< "$OPEN_OUT" && ok "2b:   ... and rebound=, naming PLUGIN_ROOT" || bad "2b:   ... and rebound=, naming PLUGIN_ROOT" "$OPEN_OUT"
        eq "2b:   ... whose PLUGIN_ROOT is now that plugin's root" "$T/plugin-b" \
            "$( (cd "$WD" && bash "$PS/coord-log.sh" plugin-root --session "$S") | jq -r .root)"
        (cd "$WD" && bash "$PS/coord-log.sh" provenance --session "$S" >/dev/null 2>&1) \
            && ok "2b:   ... and passes that plugin's provenance" || bad "2b:   ... and passes that plugin's provenance"
        eq "2b:   ... where it stood" reconcile "$(now_at)"
    else
        bad "2b: restart from the plugin at another root" "$(cat "$T/open.err")"
    fi
    # A plugin whose compat table no longer lists the run's template (its
    # compat moved on) carries it into a new run, as any other template does.
    PR="$T/plugin-c" PS="$T/plugin-c/skills/coordinate/scripts"
    sleep 1
    if open_run rebind; then
        [ "$S" != "$FIRST" ] && ok "2b: a plugin at another compat number opens a new run" || bad "2b: a plugin at another compat number opens a new run" "$OPEN_OUT"
        grep -qx "carried=$FIRST" <<< "$OPEN_OUT" && ok "2b:   ... carrying the run" || bad "2b:   ... carrying the run" "$OPEN_OUT $(cat "$T/open.err")"
        grep -q "compat table doesn't list" "$T/open.err" && ok "2b:   ... naming the compat table" || bad "2b:   ... naming the compat table" "$(cat "$T/open.err")"
    else
        bad "2b: restart from the plugin at another compat number" "$(cat "$T/open.err")"
    fi
    PR=$SAVED_PR PS=$SAVED_PS
else
    bad "2b: set up the plugin copies and the first run" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 3. an undisposed deferral ----------------------------------------------
echo "== 3. an undisposed deferral holds dispatch =="
REC3=$(record_json roadmap defer | jq -c '.deferrals = [{deferral: "retry flaky job", reason: "out of scope", raised: "2020-01-01T00:00Z", disposition: ""}]')
if to_pick defer "$REC3"; then
    eq "3: an undisposed deferral routes dispatch_check to deferral_dispose" deferral_dispose \
        "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')"
    eq "3: rewritten without a write returns to deferral_dispose" deferral_dispose "$(at --with-data '{"rewritten":"rewritten"}')"
    eq "3: dispatch is unreachable while it is open" 0 "$(entered dispatch)"
    # Edit the record keeping its written time: state-write.sh compares it
    # with the live record's before writing.
    live_body | jq -c '.deferrals[0].disposition = "closed: moot"' > "$T/rec.json"
    state_json "$(cat "$T/rec.json")" "$(jq -r .written "$T/rec.json")" > "$T/state.json"
    write_as_agent state-write.sh --state-file "$T/state.json"; rc=$?
    eq "3: state-write.sh (agent-run) disposes the deferral" 0 $rc
    eq "3: once disposed, dispatch_check reaches dispatch" dispatch "$(at --with-data '{"rewritten":"rewritten"}')"
else
    bad "3: reach pick" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 4. the record step holds until the Holdings row shows -------------------
echo "== 4. dispatch reaches wait only through a recorded holding =="
if SAVE_RECONCILE=empty-reconcile to_pick hold "$(record_json roadmap hold)" && [ "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')" = dispatch ]; then
    eq "4: dispatched without a row holds at dispatch" dispatch "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
    snap_save dispatch-held
    eq "4: another tick still holds" dispatch "$(at)"
    eq "4: record is unreachable before the row" 0 "$(entered record)"
    eq "4: wait is unreachable before the row" 0 "$(entered wait)"
    sleep 1
    dispatched_row feat-1 > "$T/row.json"
    write_as_agent state-holding.sh --topic feat-1 --row-file "$T/row.json"; rc=$?
    eq "4: state-holding.sh (agent-run) writes the row" 0 $rc
    eq "4: with the row in the record, dispatch leaves, and record waits for the holding's Work row" record "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
    write_as_agent state-stored-set.sh --work "Feature 1" --kind holding --who feat-1 --next "waiting on its first report"; rc=$?
    eq "4: state-stored-set.sh (agent-run) writes the holding's next step" 0 $rc
    eq "4: with the Work row in the record, record confirms and reaches pick" pick "$(at)"
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
seed_record unread
if open_run unread "$T/bare"; then
    eq "6: the found record still reaches reconcile" reconcile "$(at)"
    snap_save bare-reconcile
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
# Case 4's run, as it reached reconcile with one empty record.
if snap_load empty-reconcile && [ "$(now_at)" = reconcile ]; then
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
# Each part starts from a run an earlier case drove and asserted the same
# way: case 1's at record_open with no record, case 6's at reconcile with an
# unread posture, and case 4's held at dispatch with no Holdings row.
if snap_load state-open && [ "$(now_at)" = record_open ]; then
    eq "8: 'opened' with no record in the session routes record_find back to record_open" record_open "$(at --with-data '{"opened":"opened"}')"
    eq "8: record_find read none twice" 2 "$(jq -s '[.[] | select(.type == "variable_captured" and .payload.key == "RECORD_FIND" and (.payload.value | startswith("none ")))] | length' "$(logf)")"
else
    bad "8: reach record_open" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
if snap_load bare-reconcile && [ "$(now_at)" = reconcile ]; then
    R=$(tick --with-data '{"reconciled":"reported","merge":"permitted"}')
    [ -n "$(printf '%s' "$R" | jq -r '.error.code // empty')" ] && ok "8: reconcile refuses a field it doesn't accept" || bad "8: reconcile refuses a field it doesn't accept" "$R"
    eq "8: an unread posture routes to posture_ask whatever the evidence says" posture_ask "$(at --with-data '{"reconciled":"reported"}')"
else
    bad "8: reach reconcile with an unread posture" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
if snap_load dispatch-held && [ "$(now_at)" = dispatch ]; then
    R=$(tick --with-data '{"dispatched":"sent","topic":"feat-1","confirmed":"yes"}')
    [ -n "$(printf '%s' "$R" | jq -r '.error.code // empty')" ] && ok "8: dispatch refuses evidence claiming it is confirmed" || bad "8: dispatch refuses evidence claiming it is confirmed" "$R"
    eq "8: and stays at dispatch, the row not in the record" dispatch "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
else
    bad "8: reach a blocked dispatch" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 9. every wait event reaches its spoke -----------------------------------
echo "== 9. every wait event reaches its spoke =="
# Each value is submitted from a fresh wait visit. The first event's run is
# driven to wait the legitimate way (pick -> hold) and saved there; each later
# event loads that saved run, so every value is submitted from the same wait
# visit, never from a spoke an earlier event reached. No `koto next --to` is
# used: koto 0.13 only directs along a declared edge, and most spokes have
# none back to wait.
#
# Only the events no other engine test drives from wait to the state it lands
# in are driven here (shirabe#841). The others, each with its cover:
#   report      coordinate_2_engine_test.sh, dispatch-path_engine_test.sh
#   progress    dispatch-path_engine_test.sh ("progress, leg")
#   leg         dispatch-path_engine_test.sh, coordinate_3_engine_test.sh
#   quiet       coordinate_2_engine_test.sh, coordinate_4_engine_test.sh
#   decision    writeback_engine_test.sh ("the next pick is reached")
#   merged      coordinate_4_engine_test.sh, milestone-verdict_engine_test.sh
#   retire      dispatch-path_engine_test.sh ("retire arrives at teardown")
#   answer      coordinate_3_engine_test.sh, decisions-replay_engine_test.sh
#   landed      writeback_engine_test.sh ("landed goes to roadmap_status")
#   failure     milestone-verdict_engine_test.sh ("failure reaches milestone_reopen")
#   resume      pause_engine_test.sh, milestone-verdict_engine_test.sh
#   redispatch  pause_engine_test.sh ("taken up through the failure branch")
#   moved       handover_engine_test.sh ("the moved tick takes it through a full reconcile")
# evidence and raise stay here: coordinate-template-structure_engine_test.sh
# pins their wait edges and decisions-replay_engine_test.sh drives them inside
# its replay loop, but no test ticks one from wait and asserts the state it
# lands in. deferral and end have no other driver at all. An event wait gains
# later is in neither list and fails until it is put in one.
KEEP="deferral end evidence raise"
COVERED="report progress leg quiet decision merged retire answer landed failure resume redispatch moved"
J=$(koto template compile "$TPL" 2>/dev/null)
if [ -n "$J" ] && [ -r "$J" ]; then
    ALL=$(jq -r '.states.wait.accepts.event.values[]' "$J")
    [ -n "$ALL" ] || bad "9: wait accepts an event enum" "none in the compiled template"
    EVENTS=
    for ev in $ALL; do
        case " $KEEP " in *" $ev "*) EVENTS="$EVENTS $ev"; continue ;; esac
        case " $COVERED " in *" $ev "*) continue ;; esac
        bad "9: event $ev is driven here or names its cover" "add it to KEEP, or to COVERED with the test that drives it"
    done
    ALL1=" "$(printf '%s ' $ALL)
    for ev in $KEEP $COVERED; do
        case "$ALL1" in *" $ev "*) ;; *) bad "9: listed event $ev is one wait accepts" "remove it from KEEP or COVERED" ;; esac
    done
    WAIT9=
    for ev in $EVENTS; do
        # The expected spoke: the arm for this value, and for a `vars.` guard
        # the one that holds at roadmap scope (DISCIPLINE unset).
        WANT=$(jq -r --arg e "$ev" '[.states.wait.transitions[] | select(.when.event == $e)
            | select((.when["vars.DISCIPLINE"] // null) == null or .when["vars.DISCIPLINE"].is_set == false) | .target][0] // ""' "$J")
        if [ -n "$WAIT9" ]; then
            snap_load wait9 || continue
        elif to_pick spoke "$(record_json roadmap spoke | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')" \
            && [ "$(at --with-data '{"choice":"hold"}')" = wait ]; then
            snap_save wait9 && WAIT9=1
        else
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
            bad "9: event $ev reaches ${WANT:-its spoke}" "got [$GOT], template_error lines $TE, response $(head -c 300 <<<"$R")"
        fi
    done
else
    bad "9: compile the template" "koto template compile failed"
fi

echo
echo "coordinate_engine part 1: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
