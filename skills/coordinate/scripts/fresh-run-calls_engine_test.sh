#!/usr/bin/env bash
# fresh-run-calls_engine_test.sh -- a new roadmap coordinator run from its
# first start through a dispatch, a land and a merge, the shipped
# coordinate.md driven through real koto, with no coordinator record on GitHub
# to read or write (docs/designs/current/DESIGN-coordinator-record-teardown.md).
# The setup and helpers are the coordinate engine suites'
# (testdata/coordinate-engine-lib.sh).
#
# `gh` is the engine suites' stand-in behind a guard. The stand-in itself fails
# (exit 9) on any call it doesn't serve; the guard also fails, and records, every
# call that would touch a coordinator record: any `gh issue` subcommand but a
# label listing, an issue read, edit or delete through the API
# (repos/<r>/issues/<n>), an issue's comment list (repos/<r>/issues/<n>/comments),
# a collaborator-permission read (an API path ending in /permission), the
# record's author and editor query, and a pull request edit, ready or close. A comment read by id
# (repos/<r>/issues/comments/<id>) isn't one, and the open-issue listing is
# let through so it can be counted: the legacy importer's lookup makes it.
#
# Proves, in one run:
#   1. a fresh start of the new scope stops at record_open, having made one
#      open-issue listing (the importer's lookup, which finds no record);
#      record-open.sh writes the record into the session, and with its stored
#      set written the run reaches pick;
#   2. pick dispatches Feature 1 through dispatch-worker.sh, onto a /deliver
#      leg, and record confirms the holding once its Work row is written;
#   3. the worker's leg result names its pull request, which holding-link.sh
#      writes onto the holding, and the run is classified done and verified;
#   4. with the verified head recorded, land permits, goal_fit fits, the merge
#      is confirmed, and once the Pull request cell is cleared the run is back
#      at pick;
#   5. across the whole run the guard refused nothing: no issue create, edit,
#      view, close or list of a coordinator issue, no comment list and no
#      collaborator-permission read, and the one open-issue listing is the
#      only issue read, made on the fresh start.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/fresh-run-calls_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"

# The guard, in front of the engine suites' gh wrapper.
mv "$T/bin/gh" "$T/bin/gh-run"
: > "$T/refused"
cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
refuse() { printf '%s\n' "\$*" >> "$T/refused"; echo "gh guard: a coordinator-record call: \$*" >&2; exit 9; }
case "\${1-} \${2-}" in
    "issue list") case " \$* " in *" --label "*) ;; *) refuse "\$@" ;; esac ;;
    "issue "*) refuse "\$@" ;;
    "pr edit"|"pr ready"|"pr close") refuse "\$@" ;;
esac
case "\$*" in
    */permission|*"/permission "*|*"editor {"*) refuse "\$@" ;;
    *repos/*/issues/comments/*) ;;
    *repos/*/issues/[0-9]*) refuse "\$@" ;;
esac
exec "$T/bin/gh-run" "\$@"
EOF
chmod +x "$T/bin/gh"

# niwa, for the dispatch: `list --json` names the sessions launched so far,
# `dispatch --name <topic>` launches one.
mkdir -p "$T/niwa-bin"
printf '[]\n' > "$T/niwa-sessions.json"
cat > "$T/niwa-bin/niwa" <<EOF
#!/usr/bin/env bash
case "\$1 \${2-}" in
    "list --json") cat "$T/niwa-sessions.json" ;;
    "dispatch --help") : ;;
    dispatch*) shift; t=; while [ \$# -gt 0 ]; do [ "\$1" = --name ] && t=\$2; shift; done
        n="\$(printf '%s' "\$t" | tr '-' '_')-1a2b3c4d"
        jq -c --arg n "\$n" '. + [{name: "w", path: "/w", session_name: \$n}]' "$T/niwa-sessions.json" > "$T/niwa-s.tmp" && mv "$T/niwa-s.tmp" "$T/niwa-sessions.json"
        printf 'Dispatched\n  session name: %s\n' "\$n" ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$T/niwa-bin/niwa"

# A stand-in /deliver worker: one state, then a terminal whose result names
# its pull request, promoted to the leg it is bound to.
mkdir -p "$T/tpl"
cat > "$T/tpl/deliver.md" <<'EOF'
---
name: deliver
version: "1.0"
description: a stand-in /deliver for fresh-run-calls_engine_test.sh
initial_state: work
variables:
  TOPIC:
    required: true
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

listings() { grep -c 'issues?state=open' "$GH_DB.calls"; }
row() { (cd "$WD" && bash "$PS/record-holding.sh" --session "$S" --topic feat-1 --read 2>/dev/null); }

seed_roadmap ship
# The worker's pull request, its Review panel at the head, on feat/x; the
# board reads complete.
db '.prs = [{repo: "acme/widgets", number: 12, title: "feat: the loader", body: $b, state: "OPEN", isDraft: false,
    isCrossRepository: false, baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice",
    mergeStateStatus: "CLEAN"}]' --arg h "$H" --arg b "$(bt_body)"
bt_board complete-board
reset_calls

# ---- 1. the fresh start ------------------------------------------------------------
echo "== 1. a fresh start of the new scope =="
open_run ship || { bad "1: the run opens" "$(cat "$T/open.err")"; done_tests fresh-run-calls-engine; exit 1; }
ok "1: the run opens"
eq "1: with no record anywhere it stops at record_open" record_open "$(at)"
eq "1: the start made one open-issue listing, the importer's lookup" 1 "$(listings)"
write_as_agent record-open.sh
eq "1: record-open.sh (agent-run) opens the record in the session" 0 $?
eq "1: the next find reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
write_as_agent record-state.sh --run arguments "docs/roadmaps/ROADMAP-ship.md" --by "the human" \
    && write_as_agent record-state.sh --run cap 2 --by "the human" \
    && write_as_agent record-state.sh --run coordinator coord-test --by coord-test \
    && write_as_agent record-state.sh --run reports-to "the human" --by "the human"
eq "1: record-state.sh (agent-run) writes the stored set" 0 $?
eq "1: the run reaches pick" pick "$(at --with-data '{"reconciled":"reported"}')"

# ---- 2. the dispatch ----------------------------------------------------------------
echo "== 2. Feature 1 is dispatched =="
eq "2: pick's dispatch passes the dispatch check" dispatch "$(at --with-data '{"choice":"dispatch","unit":"feat-1"}')"
dispatch_as_agent "$(brief feat-1 "Feature 1" deliver feat-1 executing)"
eq "2: dispatch-worker.sh (agent-run) launches the worker" 0 "$DW_RC"
RP=$(row | jq -r '.return_path // ""')
REQ=${RP#leg }; REQ=${REQ%%:*}
case "$RP" in "leg "*":deliver") ok "2: the holding reports on a /deliver leg" ;; *) bad "2: the holding reports on a /deliver leg" "$RP $(cat "$T/dw.err")" ;; esac
eq "2: record waits for the holding's Work row" record "$(at --with-data '{"dispatched":"sent","topic":"feat-1"}')"
write_as_agent record-state.sh --work "Feature 1" --kind holding --who feat-1 --next "report at its first checkpoint"
eq "2: with the Work row written, record confirms and the run is back at pick" pick "$(at)"
eq "2: pick holds into wait" wait "$(at --with-data '{"choice":"hold"}')"

# ---- 3. the worker's pull request ----------------------------------------------------
echo "== 3. the worker's result names its pull request =="
(cd "$T" && koto init deliver-feat-1 --template "$T/tpl/deliver.md" --var TOPIC=feat-1 --koto-leg "$REQ:deliver" > /dev/null 2> "$T/child.err" \
    && koto next deliver-feat-1 --with-data '{"finish":"go"}' > /dev/null 2>&1) \
    || bad "3: the stand-in worker promotes its result" "$(cat "$T/child.err")"
eq "3: the leg result naming the pull request goes to report_link" report_link "$(at --with-data '{"event":"leg"}')"
write_as_agent holding-link.sh
eq "3: holding-link.sh (agent-run) writes it onto the holding" 0 $?
eq "3:   ... with the pull request's branch" 'feat/x [#12](https://github.com/acme/widgets/pull/12)' "$(row | jq -r '"\(.branch) \(.pull_request)"')"
eq "3: written reads the holding again and reaches classify_report" classify_report "$(at --with-data '{"linked":"written"}')"
eq "3: done reaches verify" verify "$(at --with-data '{"classification":"done"}')"
eq "3: verify_board reads #12's board, to verified_confirm" verified_confirm "$(at --with-data '{"predicted":"recorded","prediction":"every job green"}')"

# ---- 4. the land and the merge -------------------------------------------------------
echo "== 4. land, merge and the cleared cell =="
row | jq -c --arg h "$H" '.verified_head = $h' > "$T/row.json"
write_as_agent record-holding.sh --topic feat-1 --row-file "$T/row.json"
eq "4: record-holding.sh (agent-run) records the verified head" 0 $?
eq "4: land reads the round and permits, to goal_fit" goal_fit "$(at)"
eq "4: a fit pull request reaches land_merge" land_merge "$(at --with-data '{"fit":"fits","rationale":"delivers Feature 1"}')"
# The merge landed the verified head: MERGED from it, and its merge commit on
# main.
bt_merged MERGED; bt_reach behind
eq "4: a confirmed merge goes on to record" record "$(at --with-data '{"merge":"attempted"}')"
rm -rf "$GH_BOARD_DIR" && mkdir -p "$GH_BOARD_DIR"
row | jq -c '.pull_request = ""' > "$T/row.json"
write_as_agent record-holding.sh --topic feat-1 --row-file "$T/row.json"
eq "4: record-holding.sh (agent-run) clears the Pull request cell" 0 $?
eq "4: record confirms and the run is back at pick" pick "$(at)"

# ---- 5. the record calls ------------------------------------------------------------
echo "== 5. no coordinator-record call, the whole run =="
eq "5: the guard refused no call" "" "$(cat "$T/refused")"
eq "5: no issue create, edit, view, close or list reached the stand-in" "" "$(grep -E '^issue ' "$GH_DB.calls" | grep -v -- '--label')"
eq "5: no comment list and no issue read through the API" "" "$(grep -E 'repos/[^ ]*/issues/[0-9]' "$GH_DB.calls")"
eq "5: no collaborator-permission read" "" "$(grep -E '/permission( |$)' "$GH_DB.calls")"
eq "5: the one open-issue listing, from the fresh start, is the only issue read" 1 "$(listings)"

done_tests fresh-run-calls-engine
