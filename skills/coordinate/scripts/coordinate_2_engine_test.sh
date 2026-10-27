#!/usr/bin/env bash
# coordinate_2_engine_test.sh -- part 2 of 4 of the coordinate engine cases: the
# shipped coordinate.md driven through real koto, from sessions
# coordinate-open.sh opens, against the testdata/gh stand-in. The four parts
# share their setup and helpers (testdata/coordinate-engine-lib.sh) and run side
# by side under scripts/check-skill.sh; the cases are split in file order, so a
# case that reuses an earlier case's fixtures stays in that case's part. Case
# 11's moved-head run and case 17 load the run case 11 first drove to
# verified_confirm, and the later runs of cases 18 and 19 load each case's
# first run (snap_save, snap_load), rather than driving the same prefix again.
#
# Proves, one line per case:
#  10. two silent quiet checks reach failure and no teardown;
#  11. land is unreachable until a verified head is recorded, and a moved head
#      is refused at land.
#  17. a merge confirmed at merge_confirm holds record until the unit's
#      Pull request cell is cleared, and the row stays (the shirabe#490
#      comment): a row still linking the pull request waits, the row written
#      back with the cell empty confirms, and the run goes on to pick with
#      the row in the record.
#  18. send_execution for a scoping-ahead holding: dispatch-worker.sh, run as
#      the agent runs it at dispatch, renders the execution brief, opens an
#      /execute leg in koto's request store and rewrites the holding to
#      executing; record confirms it and the run reaches pick. A dispatch
#      that leaves the holding scoping ahead holds at record.
#  19. a checkpoint report is progress (shirabe#491): on the message path
#      it goes through take_report, report_facts and report_questions back to
#      wait with no classification and no phase change; one naming a pull
#      request its holding lacks goes through report_link, where
#      holding-link.sh writes it; one asking a question opens a decision entry
#      and still isn't classified; a leg-bound worker's progress message is
#      accepted, not refused, and goes back to wait without touching its leg;
#      the same worker's later terminal report is classified as before. (19
#      sits before 17 in this file, beside the cases it reuses fixtures from.)
#      A leg-bound worker's checkpoint naming its pull request (shirabe#610)
#      has it written onto its holding, the leg's return path kept and the
#      leg never read. Its checkpoint asking a question is read as progress,
#      leaves the leg unread, and opens an entry naming the worker as its
#      source, the three parts in one case (shirabe#841).
#  22. work a person assigns outside the roadmap (shirabe#607, #627): an
#      issue and a release recorded as Standing assignment rows are listed by
#      pick and dispatched through dispatch-worker.sh at roadmap scope, the
#      issue on /shirabe:work-on and the release on /shirabe:release with no
#      leg and no run mode; each brief names the record's Run coordinator
#      address and never the koto session name (shirabe#610). (22 sits after
#      19.)
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/coordinate_2_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"

# ---- 10. two silent quiet checks ---------------------------------------------
echo "== 10. two silent checks reach failure =="
if to_pick quiet "$(record_json roadmap quiet | jq -c --argjson h "$(unit_row feat-1)" '.holdings = [$h]')" \
    && [ "$(at --with-data '{"choice":"hold"}')" = wait ]; then
    set_clock 1860
    eq "10: the first silent check sends a status message" status_message "$(at --with-data '{"event":"quiet"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name QUIET)" in
        "first-silence feat-1 "*) ok "10: the first sweep reads first-silence" ;; *) bad "10: the first sweep reads first-silence" ;;
    esac
    eq "10: status sent returns to wait" wait "$(at --with-data '{"sent":"sent"}')"
    set_clock 3720
    eq "10: the second silent check reaches failure" failure "$(at --with-data '{"event":"quiet"}')"
    clear_clock
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name QUIET)" in
        "second-silence feat-1 "*) ok "10: the second sweep reads second-silence" ;; *) bad "10: the second sweep reads second-silence" ;;
    esac
    eq "10: no teardown" 0 "$(entered teardown)"
    eq "10: the holding is still on the record" feat-1 "$(live_body | jq -r '.holdings[0].worker')"
else
    clear_clock
    bad "10: reach wait with a holding" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 11. land ----------------------------------------------------------------
echo "== 11. land needs a recorded verified head, and refuses a moved one =="
if land_run landing; then
    snap_save verified-confirm
    ok "11: a verified board with no recorded head stops at verified_confirm"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name VERIFIED)" in
        "verified 12 $H "*) ok "11: VERIFIED is the sealed verified head" ;; *) bad "11: VERIFIED is the sealed verified head" ;;
    esac
    eq "11: another tick still holds at verified_confirm" verified_confirm "$(at)"
    eq "11: land is not entered before the head is recorded" 0 "$(entered land)"
    record_verified
    eq "11: state-holding.sh (agent-run) records the verified head" 0 $?
    eq "11: with the head recorded, land reads the round and permits, to goal_fit" goal_fit "$(at)"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name LAND)" in
        "permit 12 $H "*) ok "11: LAND is the sealed permit" ;; *) bad "11: LAND is the sealed permit" ;;
    esac
    eq "11: a fit pull request reaches land_merge" land_merge "$(at --with-data '{"fit":"fits","rationale":"delivers Feature 1"}')"
else
    bad "11: reach verified_confirm" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
# The run above as land_run left it, at verified_confirm.
if snap_load verified-confirm; then
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
# ---- 19. a checkpoint report is progress --------------------------------------
echo "== 19. a checkpoint report is progress, on either return path =="
# feat-2's leg is a request this host's store holds, open, as a dispatch opens
# it: a leg naming a request the store lacks is one an import left, which the
# handover gate holds at reconcile until it has an end (leg-unclassified).
PREQ=$(koto request create --role deliver --template deliver.md --inputs '{"TOPIC":"feat-2"}' \
    --requested-by coord --coordinator-of-record coordinate-feat-2 | jq -r .request_id)
PROG_ROWS() {
    jq -nc --argjson a "$(holding feat-1 '{"unit": "Feature 1", "branch": "", "verified_head": "", "pull_request": "", "return_path": "message"}')" \
        --argjson b "$(holding feat-2 "$(jq -nc --arg rp "leg $PREQ:deliver" '{unit: "Feature 2", branch: "", verified_head: "", pull_request: "", return_path: $rp}')")" '[$a, $b]'
}
db '.prs = [{repo: "acme/widgets", number: 12, title: "feat", body: "", state: "OPEN", isDraft: false,
    isCrossRepository: false, baseRefName: "main", headRefName: "feat/w-head", headRefOid: $h, author: "alice",
    mergeStateStatus: "CLEAN"}]' --arg h "$H"
# The first run is driven to wait and saved there; the three after it load
# that wait visit.
if to_pick progress "$(record_json roadmap progress | jq -c --argjson h "$(PROG_ROWS)" '.holdings = $h')" \
    && [ "$(at --with-data '{"choice":"hold"}')" = wait ]; then
    snap_save progress-wait
    eq "19 message: progress naming no pull request goes back to wait" wait \
        "$(at --with-data '{"event":"progress","unit":"feat-1","report":"Checkpoint 1 reached: scoping started."}')"
    from_to take_report report_facts && from_to report_facts report_questions && from_to report_questions wait \
        && ok "19 message: through take_report, report_facts and report_questions" \
        || bad "19 message: through take_report, report_facts and report_questions"
    eq "19 message: never classified" 0 "$(entered classify_report)"
    eq "19 message: progress naming a pull request its holding lacks goes to report_link" report_link \
        "$(at --with-data '{"event":"progress","unit":"feat-1","report":"Checkpoint 2: PR is up.","pull_request":"acme/widgets#12"}')"
    write_as_agent holding-link.sh
    eq "19 message: holding-link.sh writes it" 0 $?
    eq "19 message: written goes back to wait through report_facts" wait "$(at --with-data '{"linked":"written"}')"
    live_body | jq -e '.holdings[] | select(.worker == "feat-1") | .pull_request == "[#12](https://github.com/acme/widgets/pull/12)" and .phase == "executing"' >/dev/null \
        && ok "19 message: the holding carries the pull request, its phase unchanged" || bad "19 message: the holding carries the pull request" "$(live_body | jq -c .holdings)"
    eq "19 message: still never classified" 0 "$(entered classify_report)"
    RF0=$(entered report_facts)
    eq "19 leg: a leg-bound worker's progress is accepted and goes back to wait" wait \
        "$(at --with-data '{"event":"progress","unit":"feat-2","report":"Checkpoint 1 reached."}')"
    eq "19 leg: it was read by report_facts, as progress, not refused at take_report" "$((RF0 + 1)) progress" "$(entered report_facts) $(cd "$WD" && koto context get "$S" report_source 2>/dev/null)"
    eq "19 leg: it never went to surface" 0 "$(entered surface)"
    eq "19 leg: and its leg was never read" 0 "$(entered wait_leg)"
    eq "19 leg: a report message from it is still refused at take_report" wait \
        "$(at --with-data '{"event":"report","unit":"feat-2","report":"Done."}')"
    eq "19 leg: still not classified" 0 "$(entered classify_report)"
    eq "19 terminal: the message worker's later report is classified" classify_report \
        "$(at --with-data '{"event":"report","unit":"feat-1","report":"Done: PR #12 is ready.","pull_request":"acme/widgets#12"}')"
else
    bad "19: reach wait" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
# A checkpoint report that asks a question: its question is read and opens a
# decision entry; the report is still never classified.
if snap_load progress-wait; then
    eq "19 question: progress asking a question opens a decision entry" decision_open \
        "$(at --with-data '{"event":"progress","unit":"feat-1","report":"Checkpoint 3 reached.\nQuestions:\n1. Should the loader pin v2?"}')"
    eq "19 question: and is never classified" 0 "$(entered classify_report)"
else
    bad "19 question: reach wait" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
# The three parts of a leg-bound worker's question, end to end (shirabe#841):
# its checkpoint is read as progress, its leg stays open, and the entry its
# question opens names the worker as its source. Each part has a test of its
# own (dispatch-path_engine_test.sh "progress, leg", the case above,
# state-decision_test.sh --open-from-report); this one fails if a change
# splits them.
if snap_load progress-wait; then
    eq "19 leg question: a leg-bound worker's checkpoint asking a question opens a decision entry" decision_open \
        "$(at --with-data '{"event":"progress","unit":"feat-2","report":"Checkpoint 3 reached.\nQuestions:\n1. Should the loader pin v2?"}')"
    eq "19 leg question: read as progress" progress "$(cd "$WD" && koto context get "$S" report_source 2>/dev/null)"
    eq "19 leg question: its leg was never read" 0 "$(entered wait_leg)"
    (cd "$WD" && koto context get "$S" coord/questions.json) \
        | jq '[.[] | {key: (.index | tostring), value: {question: .text, options: ["pin -- one upgrade", "float -- none"]}}] | from_entries' > "$T/words.json"
    write_as_agent state-decision.sh --open-from-report --text-file "$T/words.json"
    eq "19 leg question: state-decision.sh writes the entry" 0 $?
    case "$(live_body | jq -r '.decisions.entries[-1].source // ""')" in
        "worker feat-2 ["*) ok "19 leg question: the entry names the worker as its source" ;;
        *) bad "19 leg question: the entry names the worker as its source" "$(live_body | jq -c '.decisions')" ;;
    esac
    # The tick doesn't stop at decision_next: it routes on to the owed step.
    at --with-data '{"opened":"opened"}' >/dev/null
    from_to decision_open decision_next && ok "19 leg question: and the run goes on through decision_next" \
        || bad "19 leg question: and the run goes on through decision_next" "now at $(now_at)"
else
    bad "19 leg question: reach wait" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
# A leg-bound worker's checkpoint naming its pull request (shirabe#610): the
# pull request reaches its holding, while its leg stays open for its result.
if snap_load progress-wait; then
    eq "19 leg link: its checkpoint naming its pull request goes to report_link" report_link \
        "$(at --with-data '{"event":"progress","unit":"feat-2","report":"Checkpoint 2: PR is up.","pull_request":"acme/widgets#12"}')"
    write_as_agent holding-link.sh
    eq "19 leg link: holding-link.sh writes it onto the leg-bound holding" "[#12](https://github.com/acme/widgets/pull/12) leg $PREQ:deliver" \
        "$(live_body | jq -r '.holdings[] | select(.worker == "feat-2") | "\(.pull_request) \(.return_path)"')"
    eq "19 leg: and its leg was never read" 0 "$(entered wait_leg)"
else
    bad "19 leg: reach wait" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 22. assigned work and a release, dispatched at roadmap scope -------------
echo "== 22. an issue and a release a person assigned are dispatched at roadmap scope, the brief naming the record's address =="
# niwa, for these dispatches: `list --json` names the sessions launched so
# far, `dispatch --name <topic>` launches one.
mkdir -p "$T/niwa22"
printf '[]\n' > "$T/niwa22/sessions.json"
cat > "$T/niwa22/niwa" <<EOF
#!/usr/bin/env bash
case "\$1 \${2-}" in
    "list --json") cat "$T/niwa22/sessions.json" ;;
    "dispatch --help") : ;;
    dispatch*) shift; t=; while [ \$# -gt 0 ]; do [ "\$1" = --name ] && t=\$2; shift; done
        n="\$(printf '%s' "\$t" | tr '-' '_')-1a2b3c4d"
        jq -c --arg n "\$n" '. + [{name: "w", path: "/w", session_name: \$n}]' "$T/niwa22/sessions.json" > "$T/niwa22/s.tmp" && mv "$T/niwa22/s.tmp" "$T/niwa22/sessions.json"
        printf 'Dispatched\n  session name: %s\n' "\$n" ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$T/niwa22/niwa"
ASSIGNED='[{"standing": "s1", "kind": "assignment", "on": "acme/widgets#591", "until": "", "what": "pick the review level up front", "owner": "the human", "relayed_by": "", "set": "2026-10-06T15:00Z"},
    {"standing": "s2", "kind": "assignment", "on": "release acme/widgets v0.25.0", "until": "", "what": "cut v0.25.0", "owner": "the human", "relayed_by": "", "set": "2026-10-06T15:00Z"}]'
db '.issues += [{repo: "acme/widgets", number: 591, title: "pick the review level up front", body: "", state: "open", author: "alice", editor: null}]'
if to_pick assigned "$(record_json roadmap assigned | jq -c --argjson s "$ASSIGNED" '.standing = $s')"; then
    eq "22: pick lists the assigned issue and the release beside the roadmap's features" "acme/widgets#591:s1 release acme/widgets v0.25.0:s2" \
        "$(cd "$WD" && koto context get "$S" coord/pick.json | jq -r '[.units[] | select(.assigned != null) | "\(.unit):\(.assigned)"] | join(" ")')"
    eq "22: the assigned issue goes through the dispatch check" dispatch "$(at --with-data '{"choice":"dispatch","unit":"fix-591"}')"
    dispatch22 "$(assigned_brief fix-591 "acme/widgets#591" work-on 591 --auto)"
    eq "22: dispatch-worker.sh launches it at roadmap scope" 0 "$D22"
    eq "22: its holding's Unit is the issue" "acme/widgets#591" "$(live_body | jq -r '.holdings[] | select(.worker == "fix-591") | .unit')"
    B22=$(cat "$T/work/.niwa/dispatch-briefs/fix-591.md" 2>/dev/null)
    case "$B22" in *'addressed to `coord-test`, the address its record names'*) ok "22: the brief names the record's address" ;;
        *) bad "22: the brief names the record's address" "$(printf '%s' "$B22" | grep -i 'report to the coordinator') $(cat "$T/d22.err")" ;; esac
    case "$B22" in *"$S"*) bad "22: and never the koto session name" ;; *) ok "22: and never the koto session name" ;; esac
    eq "22: record waits for its Work row" record "$(at --with-data '{"dispatched":"sent","topic":"fix-591"}')"
    write_as_agent state-stored-set.sh --work "acme/widgets#591" --kind holding --who fix-591 --next "report at its first checkpoint"
    eq "22: then back to pick, the issue covered" "pick fix-591" \
        "$(at) $(cd "$WD" && koto context get "$S" coord/pick.json | jq -r '.units[] | select(.unit == "acme/widgets#591") | .holding.worker')"
    eq "22: the release goes through the dispatch check" dispatch "$(at --with-data '{"choice":"dispatch","unit":"release-0-25-0"}')"
    dispatch22 "$(assigned_brief release-0-25-0 "release acme/widgets v0.25.0" release v0.25.0 "")"
    eq "22: dispatch-worker.sh launches the release" 0 "$D22"
    eq "22: on the message path, entry point release, no mode" "message release " \
        "$(live_body | jq -r '.holdings[] | select(.worker == "release-0-25-0") | "\(.return_path) \(.entry_point) \(.mode)"')"
    grep -q 'Run `/shirabe:release v0.25.0` in acme/widgets' "$T/work/.niwa/dispatch-briefs/release-0-25-0.md" 2>/dev/null \
        && ok "22: the brief runs /shirabe:release with the version" || bad "22: the brief runs /shirabe:release with the version" "$(cat "$T/d22.err")"
    eq "22: record waits for its Work row" record "$(at --with-data '{"dispatched":"sent","topic":"release-0-25-0"}')"
    write_as_agent state-stored-set.sh --work "release acme/widgets v0.25.0" --kind holding --who release-0-25-0 --next "report the tag"
    eq "22: then back to pick" pick "$(at)"
else
    bad "22: reach pick" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 17. a confirmed merge clears the Pull request cell -----------------------
echo "== 17. a confirmed merge clears the Pull request cell and keeps the row =="
# Case 11's first run as land_run left it, at verified_confirm.
if snap_load verified-confirm; then
    record_verified
    # A fit with follow-ups goes on exactly as a fit does.
    if [ "$(at)" = goal_fit ] \
        && [ "$(at --with-data '{"fit":"fits_with_follow_ups","rationale":"delivers Feature 1; follow-up: document the loader flags"}')" = land_merge ]; then
        # The merge landed the verified head: MERGED from it, and its merge
        # commit on main.
        bt_merged MERGED; bt_reach behind
        eq "17: a confirmed merge goes on to record" record "$(at --with-data '{"merge":"attempted"}')"
        case "$(bash "$PS/coord-log.sh" capture --session "$S" --name MERGE_CONFIRM)" in
            "merged 12 $H "*) ok "17: MERGE_CONFIRM reads merged" ;; *) bad "17: MERGE_CONFIRM reads merged" ;;
        esac
        rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"
        eq "17: record holds while the row still links the pull request" record "$(at)"
        case "$(cd "$WD" && koto context get "$S" coord/record_confirm.json 2>/dev/null | jq -r .expectation)" in
            *"kept, with its Pull request cell cleared of #12"*) ok "17: the expectation says to clear the cell and keep the row" ;;
            *) bad "17: the expectation says to clear the cell and keep the row" "$(cd "$WD" && koto context get "$S" coord/record_confirm.json 2>&1)" ;;
        esac
        # The agent clears the cell, as the directive says: the row read back,
        # pull_request emptied, nothing else changed.
        (cd "$WD" && bash "$PS/state-holding.sh" --session "$S" --topic feat-1 --read) | jq -c '.pull_request = ""' > "$T/row.json"
        write_as_agent state-holding.sh --topic feat-1 --row-file "$T/row.json"
        eq "17: state-holding.sh (agent-run) clears the cell" 0 $?
        eq "17: with the cell cleared, record confirms and the run goes on to pick" pick "$(at)"
        live_body | jq -e --arg h "$H" '[.holdings[] | select(.worker == "feat-1")]
            | length == 1 and .[0].pull_request == "" and .[0].verified_head == $h' >/dev/null \
            && ok "17: the row stays, with its Verified head and no pull request" || bad "17: the row stays, with its Verified head and no pull request" "$(live_body | jq -c .holdings)"
    else
        bad "17: reach land_merge" "$(cat "$T/tick.err" 2>/dev/null)"
    fi
else
    bad "17: reach verified_confirm" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi
rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"
# ---- 18. send_execution moves a scoping-ahead holding to executing ------------
echo "== 18. send_execution moves a scoping-ahead holding to executing =="
SCOPING_ROW=$(holding feat-1 "$(jq -nc '{unit: "Feature 1", entry_point: "scope", mode: "--auto --intent=continue", phase: "scoping-ahead",
    pull_request: "", branch: "", return_path: "message"}')")
cat > "$T/exec-brief.json" <<'EOF'
{"topic": "feat-1", "repo": "acme/widgets", "unit": "Feature 1: first", "entry_point": "execute",
 "entry_args": ["docs/plans/PLAN-feat-1.md"], "run_mode": "--auto", "phase": "executing",
 "authority": "You are working for the owner on acme/widgets.", "goal": "Feature 1 ships.",
 "checkpoints": ["The PR is ready with every CI job green."], "acceptance": ["CI is green per job."],
 "dispatcher_session": "coord-engine"}
EOF
if send_exec_to_dispatch execsend; then
    snap_save exec-dispatch
    (cd "$WD" && koto context add "$S" brief_input.json --from-file "$T/exec-brief.json" >/dev/null)
    # The workspace root the dispatch script renders briefs under, for this
    # one run of it.
    : > "$T/work/.niwa/workspace.toml"
    OUT=$(cd "$WD" && bash "$PS/dispatch-worker.sh" --session "$S" 2>"$T/dw.err"); rc=$?
    rm -f "$T/work/.niwa/workspace.toml"
    eq "18: dispatch-worker.sh sends the execution (exit 0)" 0 "$rc"
    case "$OUT" in *already-dispatched*) bad "18: never already-dispatched" "$OUT" ;; *brief=*) ok "18: it prints the execution brief" ;; *) bad "18: it prints the execution brief" "$OUT $(cat "$T/dw.err")" ;; esac
    live_body | jq -e '.holdings[0] | .phase == "executing" and .entry_point == "execute" and (.return_path | test("^leg [^:]+:execute$"))' >/dev/null \
        && ok "18: the holding reads executing, on /execute's new leg" || bad "18: the holding reads executing, on /execute's new leg" "$(live_body | jq -c '.holdings')"
    eq "18: record confirms the moved phase and the run reaches pick" pick "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
else
    bad "18: reach dispatch on send_execution" "at=$(now_at) $(cat "$T/open.err" "$T/tick.err" 2>/dev/null) $(cd "$WD" && koto context get "$S" coord/dispatch_check.json 2>/dev/null)"
fi
# The run above as send_exec_to_dispatch left it, before anything was sent.
if snap_load exec-dispatch; then
    # Nothing was sent: the holding is still scoping ahead, so record holds.
    eq "18: a send that changed nothing holds at record" record "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
    case "$(cd "$WD" && koto context get "$S" coord/record_confirm.json 2>/dev/null | jq -r .expectation)" in
        *"means no execution was sent"*) ok "18: and says no execution was sent" ;;
        *) bad "18: and says no execution was sent" "$(cd "$WD" && koto context get "$S" coord/record_confirm.json 2>&1)" ;;
    esac
else
    bad "18: reach dispatch on send_execution, unchanged" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo
echo "coordinate_engine part 2: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
