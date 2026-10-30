#!/usr/bin/env bash
# deferral-check_test.sh -- deferral-check.sh, the check in front of every
# dispatch, and its row mode.
#
# Covers, row mode: `filed #12`, `closed: <reason>` and a carry at or after
# the run start disposed; an earlier carry time, `filed` without a number, an
# empty Disposition and a row that isn't JSON undisposed (exit 1); an
# undisposed row raised this run (exit 0); a carry judged against
# --chain-start; a decide-by (`carried <time> until <time>: <reason>`) still
# ahead disposed, one passed open (inside the chain too), a malformed one
# refused. Check mode: a restart honouring the carry of the cancelled run it
# replaced (coord-log.sh chain-start), unless its decide-by passed; a run
# ended at a terminal state breaking the chain; a `None.` section and
# every disposed form passing with the pick's topic; an earlier carry, an
# empty Disposition before the run start, `filed #<n>` naming no issue or a
# pull request, each deferral-open; a row raised this run exempt; a discipline
# rotation's carried deferrals judged as its own rows, no handoff file read and
# no carry owed at dispatch; record-changed for a session whose record is gone,
# no longer canonical or another scope's, and a run without a found record; at-cap at the cap and at the parked bound, with
# send_execution adding no active worker, and CAP from the session; a failed
# read (2); the sealed token and its detail; every token in koto's capture
# alphabet; verdict-owed for a topic whose holding covers a milestone with a
# verdict-owed row, or that the row names as its Who, and ok for another topic.
# The record read once per check (one assembly, record/meta got and never
# listed), with decision-next judging that read and not a later one. The
# check's koto calls the same with 3 entries and with 300, no entry read and
# record/ never listed: the sections the verdicts read are got directly, an
# absent one listed by its own key, and a listed one that can't be got exits 2.
#
# Usage: bash skills/coordinate/scripts/deferral-check_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
DC="$HERE/deferral-check.sh"
CL="$HERE/coord-log.sh"
tok_shape() {
    local re='^[A-Za-z0-9 :/_.@-]*$'
    if [[ ${2% sealed:*} =~ $re ]]; then ok "$1"; else bad "$1" "[$2]"; fi
}
RS=2026-09-26T08:00:00.000Z   # test-lib's run start

echo "== row mode =="
row() { # row <disposition> [raised]: judge one row
    jq -nc --arg d "$1" --arg r "${2:-2026-09-25T10:00Z}" '{deferral: "x", reason: "r", raised: $r, disposition: $d}' > "$T/row.json"
    bash "$DC" --row-file "$T/row.json" --run-start "$RS"
}
OUT=$(row 'filed #12'); eq "filed #12 is disposed" "0 disposed filed 12" "$? $OUT"
OUT=$(row 'closed: moot now'); eq "closed: <reason> is disposed" "0 disposed closed" "$? $OUT"
OUT=$(row 'carried 2026-09-26T08:30Z: waits on infra'); eq "a carry after the run start is disposed" "0 disposed carried 2026-09-26T08:30Z" "$? $OUT"
OUT=$(row 'carried 2026-09-26T08:00Z: same minute'); eq "a carry in the run start's minute is disposed" "0 disposed carried 2026-09-26T08:00Z" "$? $OUT"
OUT=$(row 'carried 2026-09-25T08:30Z: last run'); eq "an earlier carry time is refused" "1 undisposed carried-before-chain-start" "$? $OUT"
OUT=$(row 'filed'); eq "filed without a number is refused" "1 undisposed malformed" "$? $OUT"
OUT=$(row 'filed #abc'); eq "filed with a non-number is refused" "1 undisposed malformed" "$? $OUT"
OUT=$(row 'carried soon: later'); eq "a carry without a time is refused" "1 undisposed malformed" "$? $OUT"
OUT=$(row ''); eq "an empty Disposition is refused" "1 undisposed empty" "$? $OUT"
OUT=$(row '' 2026-09-26T09:00Z); eq "an undisposed row raised this run isn't the predecessor's" "0 undisposed raised-this-run" "$? $OUT"
OUT=$(row 'carried 2026-09-25T08:30Z: x' 2026-09-26T09:00Z); eq "a bad carry on a row raised this run is exempt too" "0 undisposed raised-this-run" "$? $OUT"
# The chain start: a restart honours a carry made since the run it replaced
# began; the run start alone still decides without one.
CS=2026-09-25T08:00:00.000Z
rowc() { jq -nc --arg d "$1" '{deferral: "x", reason: "r", raised: "2026-09-24T10:00Z", disposition: $d}' > "$T/row.json"; bash "$DC" --row-file "$T/row.json" --run-start "$RS" --chain-start "$CS"; }
OUT=$(rowc 'carried 2026-09-25T08:30Z: last run'); eq "a carry since the chain start is disposed" "0 disposed carried 2026-09-25T08:30Z" "$? $OUT"
OUT=$(rowc 'carried 2026-09-24T08:30Z: before the chain'); eq "a carry before the chain start is refused" "1 undisposed carried-before-chain-start" "$? $OUT"
# The decide-by: `carried <time> until <time>: <reason>`.
OUT=$(row 'carried 2026-09-26T08:30Z until 2099-01-01T00:00Z: waits on infra'); eq "a carry with a decide-by still ahead is disposed" "0 disposed carried 2026-09-26T08:30Z" "$? $OUT"
OUT=$(row 'carried 2026-09-26T08:30Z until 2026-09-26T09:00Z: waits on infra'); eq "a carry whose decide-by has passed is open" "1 undisposed decide-by-passed" "$? $OUT"
OUT=$(rowc 'carried 2026-09-25T08:30Z until 2026-09-26T09:00Z: last run'); eq "a passed decide-by reopens a carry inside the chain" "1 undisposed decide-by-passed" "$? $OUT"
OUT=$(row 'carried 2026-09-26T08:30Z until soon: x'); eq "a decide-by that isn't a time is malformed" "1 undisposed malformed" "$? $OUT"
OUT=$(row 'carried 2026-09-26T08:30Z until 2099-01-01T00:00Z:  '); eq "a decide-by with no reason is malformed" "1 undisposed malformed" "$? $OUT"
bash "$DC" --row-file "$T/row.json" --run-start "$RS" --chain-start later >/dev/null 2>&1; eq "a chain start that isn't a time is a usage error" 64 $?
printf 'not json' > "$T/row.json"
OUT=$(bash "$DC" --row-file "$T/row.json" --run-start "$RS" 2>/dev/null); eq "a row that isn't JSON is malformed" "1 undisposed malformed" "$? $OUT"
bash "$DC" --row-file "$T/row.json" >/dev/null 2>&1; eq "row mode without --run-start is a usage error" 64 $?
bash "$DC" --row-file "$T/row.json" --run-start yesterday >/dev/null 2>&1; eq "a run start that isn't a time is a usage error" 64 $?

echo "== check mode: deferrals =="
# seed <record-json>: issue #12 and pull request #13 on the host, and the
# record: written into the current run's session (S), and into each session
# session() opens after.
seed() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 12, title: "a filed deferral", body: "", state: "open", author: "alice", editor: null}]
        | .prs += [{repo: "acme/widgets", number: 13, title: "a pull request", body: "", state: "OPEN", isDraft: false,
                    isCrossRepository: false, baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice", editor: null}]' \
        --arg h "$SHA_HEAD"
    REC=$1
    [ -z "${S:-}" ] || seed_session "$S" "$REC"
}
def() { # def <disposition> [raised]
    jq -nc --arg d "$1" --arg r "${2:-2026-09-25T10:00Z}" --arg t "d-$RANDOM" '{deferral: $t, reason: "r", raised: $r, disposition: $d}'
}
with_deferrals() { record_json roadmap plugin-system | jq -c --argjson d "[$(IFS=,; echo "$*")]" '.deferrals = $d'; }
N=0
session() { # session <vars-json> [choice] [unit]: a run at dispatch_check after a pick, holding the seeded record
    N=$((N + 1))
    S="coordinate-roadmap-plugin-system-20260926T08$(printf %02d "$N")00Z"
    found_session "$S" "$1"
    seed_session "$S" "$REC"
    log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick
    log_evidence "$S" pick "$(jq -nc --arg c "${2:-dispatch}" --arg u "${3:-beta}" '{choice: $c, unit: $u}')"
    log_to "$S" pick dispatch_check
}
check() { bash "$DC" --session "$S" 2>"$T/err" | sed 's/ sealed:.*//'; }
seed "$(record_json roadmap plugin-system)"; session "$(roadmap_vars plugin-system)"
OUT=$(bash "$DC" --session "$S" 2>"$T/err")
eq "a None. section passes with the pick's topic" "ok beta" "${OUT% sealed:*}"
tok_shape "ok is in koto's capture alphabet" "$OUT"
bash "$CL" check --session "$S" --state dispatch_check --sealed "$OUT" && ok "the token is sealed to dispatch_check" || bad "the token is sealed to dispatch_check"
eq "the detail goes to coord/dispatch_check.json" "ok 0 0 5 3" "$(jq -r '"\(.verdict) \(.active) \(.parked) \(.cap) \(.parked_bound)"' "$KOTO_STORE/context/$S/coord/dispatch_check.json")"
seed "$(with_deferrals "$(def 'filed #12')" "$(def 'closed: moot')" "$(def 'carried 2026-09-26T08:30Z: later')")"
eq "filed (an existing issue), closed and a carry after the run start pass" "ok beta" "$(check)"
grep -q '^api --method GET repos/acme/widgets/issues/12$' "$GH_DB.calls" && ok "the filed issue is read in the host" || bad "the filed issue is read in the host" "$(calls)"
seed "$(with_deferrals "$(def 'filed #99')")"
OUT=$(check); eq "filed #<n> naming no issue is open" "deferral-open 1" "$OUT"
tok_shape "deferral-open is in koto's capture alphabet" "$OUT"
seed "$(with_deferrals "$(def 'filed #13')")"
eq "filed #<n> naming a pull request is open" "deferral-open 1" "$(check)"
seed "$(with_deferrals "$(def 'filed #0')")"
eq "filed #0 is open" "deferral-open 1" "$(check)"
seed "$(with_deferrals "$(def 'carried 2026-09-25T08:30Z: last run')" "$(def '')")"
eq "an earlier carry and an empty Disposition are two open" "deferral-open 2" "$(check)"
seed "$(with_deferrals "$(def '' 2026-09-26T09:00Z)")"
eq "a deferral raised this run may stay open" "ok beta" "$(check)"
# A restart: the run before this one, of the same scope, started at 07:00 and
# was cancelled when this one opened, which carried it and holds a
# dispatched-by link to it, as coordinate-open.sh writes one. Its 07:30 carry
# still counts, unless its decide-by has passed; a run before it that ended at
# a terminal state breaks the chain, so its carries don't.
SAVED_S=$S
at() { # at <session> <created_at>: set the run's start
    local f="$KOTO_STORE/sessions/$1/koto-$1.state.jsonl"
    jq -c --arg t "$2" 'if .type == null then .created_at = $t else . end' "$f" > "$f.new" && mv "$f.new" "$f"
}
PREV=coordinate-roadmap-plugin-system-20260926T070000Z
PREV2=coordinate-roadmap-plugin-system-20260926T060000Z
S=coordinate-roadmap-plugin-system-20260926T080000Z
log_new "$PREV2" "$(roadmap_vars plugin-system)"; at "$PREV2" 2026-09-26T06:00:00.000Z; : > "$KOTO_STORE/sessions/$PREV2/.terminal"
log_new "$PREV" "$(roadmap_vars plugin-system)"; at "$PREV" 2026-09-26T07:00:00.000Z; log_end "$PREV"
found_session "$S" "$(roadmap_vars plugin-system)"
log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick
log_evidence "$S" pick '{"choice":"dispatch","unit":"beta"}'
log_to "$S" pick dispatch_check
carried() { mkdir -p "$KOTO_STORE/context/$1/koto/links/dispatched-by" && : > "$KOTO_STORE/context/$1/koto/links/dispatched-by/$2"; } # carried <run> <run it carried>
carried "$S" "$PREV"; carried "$PREV" "$PREV2"
f="$KOTO_STORE/sessions/$PREV/koto-$PREV.state.jsonl"; grep -v workflow_cancelled "$f" > "$f.new" && mv "$f.new" "$f"
eq "a run just before this one that wasn't cancelled gives this run's own start" 2026-09-26T08:00:00.000Z "$(bash "$CL" chain-start --session "$S")"
log_end "$PREV"
eq "chain-start reaches the cancelled run before this one" 2026-09-26T07:00:00.000Z "$(bash "$CL" chain-start --session "$S")"
seed "$(with_deferrals "$(def 'carried 2026-09-26T07:30Z: the run this one restarted carried it')")"
eq "a restart doesn't re-decide a carry made by the run it replaced" "ok beta" "$(check)"
seed "$(with_deferrals "$(def 'carried 2026-09-26T07:30Z until 2026-09-26T07:45Z: decide by then')")"
eq "unless the carry's decide-by has passed" "deferral-open 1" "$(check)"
seed "$(with_deferrals "$(def 'carried 2026-09-26T06:30Z: carried before the chain')")"
eq "a carry from before the chain is still open" "deferral-open 1" "$(check)"
log_end "$PREV2"; rm -f "$KOTO_STORE/sessions/$PREV2/.terminal"
eq "a chain of two cancelled runs reaches the earlier one" 2026-09-26T06:00:00.000Z "$(bash "$CL" chain-start --session "$S")"
eq "and honours its carry" "ok beta" "$(check)"
for s in "$PREV" "$PREV2" "$S"; do rm -rf "$KOTO_STORE/sessions/$s" "$KOTO_STORE/context/$s/koto"; done
S=$SAVED_S
seed "$(with_deferrals "$(def 'filed #12')")"; db '.fail = [{match: "issues/12", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
check >/dev/null; eq "a failed issue read exits 2" 2 ${PIPESTATUS[0]}

echo "== check mode: the record =="
seed "$(record_json roadmap plugin-system)"; rm -rf "$KOTO_STORE/context/$S/record"
OUT=$(check); eq "a session whose record is gone is record-changed" "record-changed" "$OUT"
tok_shape "record-changed is in koto's capture alphabet" "$OUT"
seed "$(record_json roadmap plugin-system)"; printf '"stray"' | koto context add "$S" record/holdings
eq "a record no longer canonical is record-changed" "record-changed" "$(check)"
seed "$(record_json roadmap other)"
eq "another scope's record in the session is record-changed" "record-changed" "$(check)"
seed "$(record_json roadmap plugin-system)"
KOTO_NO_LIST_PREFIX=1 bash "$DC" --session "$S" >/dev/null 2>&1; eq "a failed record read exits 2" 2 $?
N=$((N + 1)); S="coordinate-roadmap-plugin-system-20260926T08$(printf %02d "$N")00Z"
log_new "$S" "$(roadmap_vars plugin-system)"; log_to "$S" pick dispatch_check
seed "$(record_json roadmap plugin-system)"
eq "a run without a found record is record-changed" "record-changed" "$(check)"

echo "== check mode: owed decision work, the DESIGN's blocking table row by row =="
ESC='"round": "1", "verdict": "escalate", "recommendation": "wait", "reason": "r", "context": "c", "problem": "p", "grounds": "scope", "target": "a person"'
dentry() { # dentry <n> <state> [extra JSON members]: one Decisions entry
    printf '{"decision": "%s", "round": "0", "question": "Q%s?", "options": "ship -- now\\nwait -- later", "state": "%s", "source": "self [20260925T080000Z raise %s]", "updated": "2026-09-26T07:00Z"%s}' \
        "$1" "$1" "$2" "$1" "${3:+, $3}"
}
with_entries() { record_json roadmap plugin-system | jq -c --argjson e "[$(IFS=,; echo "$*")]" '.decisions = {next: 20, entries: $e}'; }
# later: the run has already dispatched once, and this is a second pick.
later() {
    log_to "$S" dispatch_check dispatch; log_to "$S" dispatch record; log_to "$S" record pick_facts; log_to "$S" pick_facts pick
    log_evidence "$S" pick '{"choice":"dispatch","unit":"gamma"}'
    log_to "$S" pick dispatch_check
}
# row <label> <first-dispatch verdict> <later-dispatch verdict> <entries...>
row_owed() {
    local label=$1 first=$2 next=$3; shift 3
    seed "$(with_entries "$@")"; session "$(roadmap_vars plugin-system)"
    eq "$label: the first dispatch" "$first" "$(check)"
    session "$(roadmap_vars plugin-system)"; later
    eq "$label: a later dispatch" "$next" "$(check)"
}
# 2 an unrecorded write: a visit to decision_raise with no entry stamped for it.
seed "$(record_json roadmap plugin-system)"; session "$(roadmap_vars plugin-system)"
log_to "$S" dispatch_check decision_raise; log_to "$S" decision_raise pick_facts; log_to "$S" pick_facts pick
log_evidence "$S" pick '{"choice":"dispatch","unit":"beta"}'; log_to "$S" pick dispatch_check
eq "an unrecorded write: the first dispatch" "decision-owed unrecorded-raise" "$(check)"
later
eq "an unrecorded write: a later dispatch" "decision-owed unrecorded-raise" "$(check)"
# 3 to 6 an owed message.
row_owed "an owed withdrawal" "decision-owed withdraw" "decision-owed withdraw" "$(dentry 2 coordinator-verdict '"owed": "withdrawal"')"
row_owed "an owed reply" "decision-owed reply" "decision-owed reply" \
    "$(dentry 3 settled '"owed": "reply", "outcome": "wait; reason: r", "decided_by": "a person", "source": "worker w1 [20260925T080000Z report 1.1]"')"
row_owed "an owed escalation" "decision-owed escalate" "decision-owed escalate" "$(dentry 5 escalated "$ESC, \"owed\": \"escalation\"")"
# 7 and 8, and the two rows that block nothing.
row_owed "a proposed entry" "decision-owed take" "ok gamma" "$(dentry 6 proposed)"
row_owed "an unjudged entry" "decision-owed verdict" "ok gamma" "$(dentry 7 coordinator-verdict)"
row_owed "a held entry" "ok beta" "ok gamma" "$(dentry 7 coordinator-verdict '"verdict": "hold", "reason": "waits on the benchmark"')"
row_owed "an escalated entry that owes nothing" "ok beta" "ok gamma" "$(dentry 5 escalated "$ESC")"
OUT=$(seed "$(with_entries "$(dentry 6 proposed)")"; session "$(roadmap_vars plugin-system)"; bash "$DC" --session "$S" 2>/dev/null)
tok_shape "decision-owed is in koto's capture alphabet" "$OUT"

echo "== check mode: the record is read once, and decision-next judges that read =="
# decision-next.sh takes the record the check read (--parsed) rather than
# reading it again (shirabe#1156). A koto in front of the stand-in serves
# record/decisions as seeded on its first read and, on any later one, the
# Decisions section in $T/reread: a callee that read the record again, or
# ignored what it was handed, would judge the second section instead.
mkdir -p "$T/bin"
cat > "$T/bin/koto" <<EOF
#!/usr/bin/env bash
if [ "\${1:-} \${2:-} \${4:-}" = "context get record/decisions" ]; then
    if [ -f "$T/reread.served" ]; then
        printf '%s\n' "\$*" >> "\$KOTO_STORE/calls"
        cat "$T/reread"
        exit 0
    fi
    : > "$T/reread.served"
fi
exec "$HERE/testdata/koto" "\$@"
EOF
chmod +x "$T/bin/koto"
# reread_case <record-json> <later-read-json>: seed the first, serve the
# second's Decisions section on a re-read.
reread_case() {
    seed "$1"; session "$(roadmap_vars plugin-system)"
    seed_session reread-scratch "$2" && cp "$KOTO_STORE/context/reread-scratch/record/decisions" "$T/reread"
    rm -f "$T/reread.served"
    : > "$KOTO_STORE/calls"
}
reread_case "$(with_entries "$(dentry 6 proposed)")" "$(with_entries)"
eq "a proposed entry in the record the check read blocks the first dispatch" "decision-owed take" "$(PATH="$T/bin:$PATH" check)"
eq "  ... from one assembly of the record, which never lists record/" 0 "$(grep -c "^context list $S --prefix record/\$" "$KOTO_STORE/calls")"
eq "  ... record/decisions read once" 1 "$(grep -c "^context get $S record/decisions\$" "$KOTO_STORE/calls")"
eq "  ... record/meta got before and after the sections, never listed" "2 0" \
    "$(grep -c "^context get $S record/meta\$" "$KOTO_STORE/calls") $(grep -c "^context list $S --prefix record/meta\$" "$KOTO_STORE/calls")"
reread_case "$(with_entries)" "$(with_entries "$(dentry 6 proposed)")"
eq "a record owing nothing when the check read it passes, whatever a later read says" "ok beta" "$(PATH="$T/bin:$PATH" check)"
rm -f "$T/reread" "$T/reread.served"

echo "== check mode: a topic already held =="
pr_dup() { db '.prs += [{repo: "acme/widgets", number: 41, title: "w", body: "", state: "OPEN", isDraft: true, isCrossRepository: false,
    baseRefName: "main", headRefName: "feat/41", headRefOid: $h, author: "alice", editor: null}]' --arg h "$SHA_HEAD"; }
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding beta '{"pull_request": "[#41](https://github.com/acme/widgets/pull/41)"}')" '.holdings = [$h]')"
pr_dup
session "$(roadmap_vars plugin-system)"
OUT=$(check); eq "dispatching a topic a Holdings row already names is refused" "duplicate-topic beta" "$OUT"
tok_shape "duplicate-topic is in koto's capture alphabet" "$OUT"
session "$(roadmap_vars plugin-system)" scope_ahead beta
eq "scope_ahead on a held topic is refused too" "duplicate-topic beta" "$(check)"
session "$(roadmap_vars plugin-system)" scope beta
eq "scope on a held topic is refused too" "duplicate-topic beta" "$(check)"
session "$(roadmap_vars plugin-system)" scope gamma
eq "scope on a free topic is clear" "ok gamma" "$(check)"
session "$(roadmap_vars plugin-system)" dispatch gamma
eq "another topic is clear" "ok gamma" "$(check)"

echo "== check mode: a milestone whose verdict is owed =="
# A verdict-owed Work row (docs/designs/DESIGN-milestone-verdicts.md): the
# topic that held the milestone, through its holding or the row's Who, gets
# no dispatch.
OWEDROW() { jq -nc --arg t "$1" --arg w "$2" '{item: $t, kind: "verdict-owed", who: $w, next: "verdict owed since 2026-09-26", wakes: "0", updated: "2026-09-26T07:00Z"}'; }
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding beta '{"unit": "MV1: the plugin list", "phase": "scoping-ahead", "pull_request": ""}')" \
    --argjson o "$(OWEDROW MV1 beta)" --argjson p "$(OWEDROW MV2 epsilon)" '.holdings = [$h] | .work = [$o, $p]')"
session "$(roadmap_vars plugin-system)" send_execution beta
OUT=$(check); eq "sending a held milestone's worker more work is refused" "verdict-owed MV1" "$OUT"
tok_shape "verdict-owed is in koto's capture alphabet" "$OUT"
session "$(roadmap_vars plugin-system)" dispatch epsilon
eq "dispatching the topic a verdict-owed row names, its holding gone, is refused" "verdict-owed MV2" "$(check)"
session "$(roadmap_vars plugin-system)" dispatch gamma
eq "another topic is clear" "ok gamma" "$(check)"

echo "== check mode: the topic is the one this visit's path chose =="
# A pick from an earlier visit of pick is not the one checked: a later visit
# whose evidence names another unit is.
session "$(roadmap_vars plugin-system)" dispatch gamma
log_to "$S" dispatch_check dispatch; log_evidence "$S" dispatch '{"dispatched":"failed","topic":"gamma"}'
log_to "$S" dispatch failure; log_evidence "$S" failure '{"move":"escalate"}'; log_to "$S" failure wait
log_to "$S" wait pick_facts; log_to "$S" pick_facts pick
log_evidence "$S" pick '{"choice":"dispatch","unit":"delta"}'; log_to "$S" pick dispatch_check
eq "the pick after the latest entry into pick is checked, not an earlier one" "ok delta" "$(check)"
session "$(roadmap_vars plugin-system)" dispatch gamma
log_to "$S" dispatch_check deferral_dispose; log_evidence "$S" deferral_dispose '{"rewritten":"rewritten"}'
log_to "$S" deferral_dispose dispatch_check
eq "back from deferral_dispose, the same pick is checked" "ok gamma" "$(check)"
# A redispatch after a failed dispatch checks the unit this state sealed before.
session "$(roadmap_vars plugin-system)" dispatch gamma
log_capture "$S" DISPATCH_CHECK "$(bash "$CL" seal --session "$S" --state dispatch_check --token "ok gamma")"
log_to "$S" dispatch_check dispatch; log_evidence "$S" dispatch '{"dispatched":"failed","topic":"gamma"}'
log_to "$S" dispatch failure; log_evidence "$S" failure '{"move":"redispatch"}'; log_to "$S" failure dispatch_check
eq "a redispatch after a failed dispatch checks the unit that failed" "ok gamma" "$(check)"
# A redispatch of a held unit (a dead worker, via wait) is not a duplicate.
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding beta '{"pull_request": "[#41](https://github.com/acme/widgets/pull/41)"}')" '.holdings = [$h]')"
session "$(roadmap_vars plugin-system)" dispatch gamma
log_to "$S" dispatch_check dispatch; log_to "$S" dispatch record; log_to "$S" record wait
log_evidence "$S" wait '{"event":"failed","unit":"beta"}'; log_to "$S" wait failure
log_evidence "$S" failure '{"move":"redispatch"}'; log_to "$S" failure dispatch_check
eq "a redispatch of a held unit is checked on that unit and isn't a duplicate" "ok beta" "$(check)"

echo "== check mode: a redispatch on the leg path =="
# The unit that failed arrived on a koto request leg: its wait evidence names
# no unit, so the unit is the holding whose Return path is the captured leg
# (lib_unit, as report-facts.sh resolves it), never `-`.
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding theta '{"return_path": "leg req-1:execute", "pull_request": "[#41](https://github.com/acme/widgets/pull/41)"}')" '.holdings = [$h]')"
session "$(roadmap_vars plugin-system)" dispatch gamma
log_to "$S" dispatch_check dispatch; log_to "$S" dispatch record; log_to "$S" record wait
log_evidence "$S" wait '{"event":"leg"}'; log_to "$S" wait leg_pick
log_capture "$S" WAIT_REQ req-1; log_to "$S" leg_pick wait_leg
log_capture "$S" WAIT_LEG execute; log_to "$S" wait_leg take_report
log_to "$S" take_report failure
log_evidence "$S" failure '{"move":"redispatch"}'; log_to "$S" failure dispatch_check
eq "a redispatch after a leg arrival checks the holding the leg names" "ok theta" "$(check)"
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding theta '{"return_path": "leg req-9:execute"}')" '.holdings = [$h]')"
OUT=$(bash "$DC" --session "$S" 2>/dev/null)
eq "a leg no holding carries resolves to no unit, and is refused rather than sealed ok -" "unresolved-topic" "${OUT% sealed:*}"
tok_shape "unresolved-topic is in koto's capture alphabet" "$OUT"
jq -e '.verdict == "unresolved-topic" and (.reason | test("^the unit to redispatch could not be resolved") and test("Workers are: theta; escalate if none fits$"))' "$KOTO_STORE/context/$S/coord/dispatch_check.json" >/dev/null \
    && ok "the refusal says why and names the Holdings rows' Workers" || bad "the refusal says why and names the Holdings rows' Workers" "$(cat "$KOTO_STORE/context/$S/coord/dispatch_check.json")"
# A redispatch whose Worker the dispatch path would refuse names that Worker.
seed "$(record_json roadmap plugin-system | jq -c --argjson h "$(holding Theta.v2 '{"return_path": "leg req-1:execute", "pull_request": "[#41](https://github.com/acme/widgets/pull/41)"}')" '.holdings = [$h]')"
eq "a redispatch whose Worker isn't a dispatch topic is refused too" "unresolved-topic" "$(check)"
jq -e '.reason | test("resolves to the Worker \\[Theta.v2\\]")' "$KOTO_STORE/context/$S/coord/dispatch_check.json" >/dev/null \
    && ok "that refusal names the Worker" || bad "that refusal names the Worker" "$(cat "$KOTO_STORE/context/$S/coord/dispatch_check.json")"

echo "== check mode: pick's unit must be a dispatch topic =="
# A unit's tag from coord/pick.json in place of its topic (shirabe#492): refused
# before any read, so nothing reaches dispatch, and nothing is written.
seed "$(record_json roadmap plugin-system)"; session "$(roadmap_vars plugin-system)" dispatch "Feature 1"
reset_calls
OUT=$(bash "$DC" --session "$S" 2>"$T/err")
eq "dispatch with unit \"Feature 1\" is refused" "unknown-topic" "${OUT% sealed:*}"
tok_shape "unknown-topic is in koto's capture alphabet" "$OUT"
bash "$CL" check --session "$S" --state dispatch_check --sealed "$OUT" && ok "the refusal is sealed to dispatch_check" || bad "the refusal is sealed to dispatch_check"
jq -e '.verdict == "unknown-topic" and .topic == "-" and (.reason | test("^pick.s unit \\[Feature 1\\] is not a dispatch topic")) and (.reason | test("\\^\\[a-z0-9\\]\\[a-z0-9-\\]\\*\\$"))' \
    "$KOTO_STORE/context/$S/coord/dispatch_check.json" >/dev/null \
    && ok "the refusal names the field, the value and the accepted pattern" || bad "the refusal names the field, the value and the accepted pattern" "$(cat "$KOTO_STORE/context/$S/coord/dispatch_check.json")"
[ -s "$GH_DB.calls" ] && bad "the refusal makes no read and no write" "$(calls)" || ok "the refusal makes no read and no write"
session "$(roadmap_vars plugin-system)" scope_ahead "Feature 3"
eq "scope_ahead with a unit's tag is refused" "unknown-topic" "$(check)"
session "$(roadmap_vars plugin-system)" scope "Feature 3"
eq "scope with a unit's tag is refused" "unknown-topic" "$(check)"
session "$(roadmap_vars plugin-system)" send_execution "Feature 3"
eq "send_execution with a unit's tag is refused" "unknown-topic" "$(check)"
jq -e '.reason | test("scoping-ahead holding")' "$KOTO_STORE/context/$S/coord/dispatch_check.json" >/dev/null \
    && ok "send_execution's refusal says it names a scoping-ahead holding" || bad "send_execution's refusal says it names a scoping-ahead holding"
session "$(roadmap_vars plugin-system)" dispatch "Feature_1"
eq "a Worker-cell shape the dispatch path would refuse is refused here" "unknown-topic" "$(check)"
session "$(roadmap_vars plugin-system)"
log_to "$S" dispatch_check pick; log_evidence "$S" pick '{"choice":"dispatch"}'; log_to "$S" pick dispatch_check
eq "a dispatch with no unit is refused" "unknown-topic" "$(check)"
session "$(roadmap_vars plugin-system)" dispatch "plugin-api"
eq "a dispatch topic passes" "ok plugin-api" "$(check)"

echo "== check mode: the cap and the parked bound =="
pr() { # pr <n> <state> <draft>
    db '.prs += [{repo: "acme/widgets", number: $n, title: "w", body: "", state: $s, isDraft: ($d == "true"), isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/\($n)", headRefOid: $h, author: "alice", editor: null}]' \
        --argjson n "$1" --arg s "$2" --arg d "$3" --arg h "$SHA_HEAD"
}
active() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\"}"; }
parked() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\", \"verified_head\": \"$SHA_HEAD\"}"; }
with_holdings() { record_json roadmap plugin-system | jq -c --argjson h "[$(IFS=,; echo "$*")]" '.holdings = $h'; }
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(active a4 24)" "$(active a5 25)")"
for n in 21 22 23 24 25; do pr $n OPEN true; done
session "$(roadmap_vars plugin-system)"
OUT=$(check); eq "five active workers under a cap of five is at-cap" "at-cap 5/5 0/3" "$OUT"
tok_shape "at-cap is in koto's capture alphabet" "$OUT"
session "$(roadmap_vars plugin-system)" scope beta
eq "scope adds an active worker, so it is at-cap too" "at-cap 5/5 0/3" "$(check)"
scoping() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\", \"phase\": \"scoping-ahead\"}"; }
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(active a4 24)" "$(scoping a5 25)")"
session "$(roadmap_vars plugin-system)" send_execution a5
eq "send_execution to a scoping-ahead holding adds no active worker" "ok a5" "$(check)"
session "$(roadmap_vars plugin-system)" send_execution a4
eq "send_execution to a holding that isn't scoping ahead is judged as a dispatch" "at-cap 5/5 0/3" "$(check)"
session "$(roadmap_vars plugin-system)" send_execution nobody
eq "send_execution to a unit with no holding is judged as a dispatch" "at-cap 5/5 0/3" "$(check)"
session "$(roadmap_vars plugin-system | jq -c '.CAP = "6"')"
eq "the cap comes from the session's CAP" "ok beta" "$(check)"
seed "$(with_holdings "$(parked p1 31)" "$(parked p2 32)" "$(parked p3 33)")"
for n in 31 32 33; do pr $n OPEN false; done
session "$(roadmap_vars plugin-system)"
eq "three parked workers is at the parked bound" "at-cap 0/5 3/3" "$(check)"
seed "$(with_holdings "$(parked p1 31)" "$(parked p2 32)" "$(parked p3 33)" "$(scoping s1 34)")"
for n in 31 32 33; do pr $n OPEN false; done; pr 34 OPEN true
session "$(roadmap_vars plugin-system)" send_execution s1
eq "send_execution dispatches nothing new, so the parked bound doesn't stop it" "ok s1" "$(check)"
seed "$(with_holdings "$(parked p1 31)" "$(parked p2 32)" "$(parked p3 33)")"
pr 31 OPEN false; pr 32 OPEN true; pr 33 MERGED false
session "$(roadmap_vars plugin-system)"
eq "a verified draft and a merged pull request aren't parked" "ok beta" "$(check)"
eq "the draft counts as active; the merged one, verified, holds no slot (shirabe#1385)" "1 1" "$(jq -r '"\(.active) \(.parked)"' "$KOTO_STORE/context/$S/coord/dispatch_check.json")"
# A confirmed merge clears the row's Pull request cell and keeps it until
# teardown: such a row holds no slot under the cap.
merged() { holding "$1" "{\"pull_request\": \"\", \"verified_head\": \"$SHA_HEAD\"}"; }
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(active a4 24)" "$(merged m1)")"
for n in 21 22 23 24; do pr $n OPEN true; done
session "$(roadmap_vars plugin-system)"
eq "a merged row waiting for teardown holds no slot under the cap" "ok beta" "$(check)"
eq "it counts as neither active nor parked" "4 0" "$(jq -r '"\(.active) \(.parked)"' "$KOTO_STORE/context/$S/coord/dispatch_check.json")"
# A merge the record hasn't confirmed yet frees the slot too, when GitHub reads
# the linked pull request MERGED and the worker has nothing left: a Verified
# head, or the work-on entry point (shirabe#1385).
workon() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\", \"entry_point\": \"work-on\"}"; }
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(parked v1 41)" "$(workon w1 42)")"
for n in 21 22 23; do pr $n OPEN true; done; pr 41 MERGED false; pr 42 MERGED false
session "$(roadmap_vars plugin-system)"
eq "merged pull requests the record hasn't confirmed no longer count against the run's worker cap" "ok beta" "$(check)"
eq "  ... three active, none parked" "3 0" "$(jq -r '"\(.active) \(.parked)"' "$KOTO_STORE/context/$S/coord/dispatch_check.json")"
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(parked v1 41)" "$(workon w1 42)")"
for n in 21 22 23 41 42; do pr $n OPEN true; done
session "$(roadmap_vars plugin-system)"
eq "the same pull requests open as drafts are at-cap again" "at-cap 5/5 0/3" "$(check)"
# A /deliver row with no Verified head may be on a multi-pr plan whose first
# pull request merged, and a scoping-ahead row waits for its execution: both
# keep their slot, merged link or not.
verified_scoping() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\", \"phase\": \"scoping-ahead\", \"verified_head\": \"$SHA_HEAD\"}"; }
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(active d1 43)" "$(verified_scoping s1 44)")"
for n in 21 22 23; do pr $n OPEN true; done; pr 43 MERGED false; pr 44 MERGED false
session "$(roadmap_vars plugin-system)"
eq "a merged first pull request of a /deliver row, and a scoping-ahead row's, keep their slots" "at-cap 5/5 0/3" "$(check)"
session "$(roadmap_vars plugin-system)" send_execution s1
eq "  ... so send_execution to that scoping-ahead row stays within the cap" "ok s1" "$(check)"
# Once sent, the row is executing under the execution's entry point and keeps
# the scoping's Verified head and merged link: it still holds its slot.
sent() { holding "$1" "{\"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\", \"entry_point\": \"/shirabe:execute\", \"verified_head\": \"$SHA_HEAD\"}"; }
seed "$(with_holdings "$(active a1 21)" "$(active a2 22)" "$(active a3 23)" "$(active a4 24)" "$(sent x1 44)")"
for n in 21 22 23 24; do pr $n OPEN true; done; pr 44 MERGED false
session "$(roadmap_vars plugin-system)"
eq "a row send_execution moved on keeps its slot after its scoping pull request merged" "at-cap 5/5 0/3" "$(check)"

echo "== check mode: a discipline rotation =="
# A rotation's predecessor's deferrals are rows of its own record from its
# first state (state-open.sh --carry), judged as any other row; no handoff
# file is read, and no carry is owed at dispatch.
PREV='{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-16T10:00Z","disposition":""}'
dseed() { # dseed <record-json>: issue #12 on the host, and the rotation's record
    db_init
    db '.issues += [{repo: "acme/widgets", number: 12, title: "lint", body: "", state: "open", author: "alice", editor: null}]'
    REC=$1
}
dsession() {
    N=$((N + 1))
    S="coordinate-discipline-ci-health-20260926T08$(printf %02d "$N")00Z"
    found_session "$S" "$(discipline_vars ci-health)"
    seed_session "$S" "$REC"
    log_to "$S" reconcile pick_facts; log_to "$S" pick_facts pick
    log_evidence "$S" pick '{"choice":"dispatch","unit":"beta"}'
    log_to "$S" pick dispatch_check
}
mine() { record_json discipline ci-health | jq -c --argjson d "[$(IFS=,; echo "$*")]" '.deferrals = $d'; }
dseed "$(mine "$PREV")"; dsession
reset_calls
eq "a carried deferral left without a disposition is open" "deferral-open 1" "$(check)"
grep -q 'contents/' "$GH_DB.calls" && bad "  ... and no handoff file is read" "$(calls)" || ok "  ... and no handoff file is read"
dseed "$(mine '{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-16T10:00Z","disposition":"carried 2026-09-26T08:10Z: infra owns it"}')"; dsession
eq "a carried deferral with a carry since the run start passes" "ok beta" "$(check)"
dseed "$(mine '{"deferral":"flaky lint job","reason":"needs a runner","raised":"2026-09-16T10:00Z","disposition":"filed #12"}')"; dsession
eq "one filed passes" "ok beta" "$(check)"
# The predecessor's unsettled decision: carried when the rotation opened, so
# nothing is owed at dispatch even with the predecessor still holding it.
PRED=coordinate-discipline-ci-health-20260919T080000Z
dseed "$(record_json discipline ci-health)"
seed_session "$PRED" "$(record_json discipline ci-health | jq -c --argjson e "[$(dentry 5 escalated "$ESC")]" '.decisions = {next: 9, entries: $e}')"
dsession
jq -nc --arg p "$PRED" '{start: "2026-09-26", end: "2026-10-03", host_repo: "acme/widgets", predecessor: $p}' | koto context add "$S" record/rotation
eq "a predecessor's unsettled decision owes no carry at dispatch" "ok beta" "$(check)"
# The discipline equivalent of a unit's tag: an issue's "#<n>".
dseed "$(record_json discipline ci-health)"
dsession
log_to "$S" dispatch_check pick; log_evidence "$S" pick '{"choice":"dispatch","unit":"#1712"}'; log_to "$S" pick dispatch_check
reset_calls
eq "a discipline pick with an issue's \"#1712\" as its unit is refused" "unknown-topic" "$(check)"
[ -s "$GH_DB.calls" ] && bad "that refusal makes no read either" "$(calls)" || ok "that refusal makes no read either"

echo "== check mode: pauses =="
prow() { # prow <id> <kind> <on> <until>
    jq -nc --arg s "$1" --arg k "$2" --arg o "$3" --arg u "$4" \
        '{standing: $s, kind: $k, on: $o, until: $u, what: "x", owner: "the human", relayed_by: "", set: "2026-10-01T19:37Z"}'
}
with_pauses() { # with_pauses <record-json> <row>...
    local r=$1; shift
    printf '%s' "$r" | jq -c --argjson s "[$(IFS=,; echo "$*")]" '.standing = $s'
}
seed "$(with_pauses "$(with_holdings "$(scoping a5 25)" | jq -c '.deferrals = [{deferral: "open one", reason: "r", raised: "2026-09-25T10:00Z", disposition: ""}]')" "$(prow s1 pause all lifted)")"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)"
OUT=$(bash "$DC" --session "$S" 2>"$T/err")
eq "a pause on all holds a new dispatch, ahead of an open deferral" "paused s1" "${OUT% sealed:*}"
tok_shape "paused is in koto's capture alphabet" "$OUT"
jq -r '.reason' "$KOTO_STORE/context/$S/coord/dispatch_check.json" | grep -q 'held by pause s1: on all, until lifted' \
    && ok "  ... the detail names the pause" || bad "  ... the detail names the pause" "$(cat "$KOTO_STORE/context/$S/coord/dispatch_check.json")"
seed "$(with_pauses "$(with_holdings "$(scoping a5 25)")" "$(prow s2 pause "Feature 2" lifted)")"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
eq "a unit's pause holds sending its holding the execution" "paused s2" "$(check)"
session "$(roadmap_vars plugin-system)" dispatch plugin-api
eq "  ... and not a new dispatch, whose unit this check can't name" "ok plugin-api" "$(check)"
seed "$(with_pauses "$(with_holdings "$(scoping a5 25)")" "$(prow s2 pause "Feature 2" lifted)" "$(prow s3 go-ahead "Feature 2" "")")"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
eq "a go-ahead on the unit lets it through" "ok a5" "$(check)"
seed "$(with_pauses "$(with_holdings "$(scoping a5 25)")" "$(prow s1 pause all lifted)" "$(prow s3 go-ahead "Feature 2" "")")"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
eq "a go-ahead lets its unit through a pause on all at dispatch too" "ok a5" "$(check)"
session "$(roadmap_vars plugin-system)" dispatch plugin-api
eq "  ... and a new dispatch under it is left to dispatch-worker.sh, which knows its unit" "ok plugin-api" "$(check)"
seed "$(with_pauses "$(with_holdings "$(scoping a5 25)")" "$(prow s4 pause all "time 2000-01-01T00:00Z")")"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
eq "a pause whose minute has passed holds nothing" "ok a5" "$(check)"
# A roadmap moved to roadmap/v3: the holding names the unit `Milestone 2`, the
# pause was written on `Feature 2` before the move.
ms_holding() { with_holdings "$(scoping a5 25)" | jq -c '.holdings[0].unit = "Milestone 2"'; }
seed "$(with_pauses "$(ms_holding)" "$(prow s2 pause "Feature 2" lifted)")"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
eq "a pause on Feature 2 holds sending the execution to the holding under Milestone 2" "paused s2" "$(check)"
seed "$(with_pauses "$(ms_holding)" "$(prow s2 pause "Feature 2" lifted)" "$(prow s3 go-ahead "Feature 2" "")")"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
eq "  ... and a go-ahead on Feature 2 lets it through" "ok a5" "$(check)"
seed "$(with_pauses "$(with_holdings "$(scoping a5 25)" | jq -c '.holdings[0].unit = "Milestone 12"')" "$(prow s2 pause "Feature 2" lifted)")"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
eq "a pause on Feature 2 doesn't hold a holding under Milestone 12" "ok a5" "$(check)"

echo "== check mode: the check's koto calls don't grow with the entries (shirabe#1308) =="
# The check gets the sections its verdicts read, each directly, and never
# lists record/, which names every entry: the same check on a record with a
# few entries and with 300 more makes the same koto calls, and reads no entry.
# filler <session> <count>: plain entries numbered from 1.
filler() {
    local d="$KOTO_STORE/context/$1/record/entries" i
    mkdir -p "$d"
    for ((i = 1; i <= $2; i++)); do
        printf '{"n":%d,"stamp":"2026-09-26T08:00:00Z","kind":"entry","text":"note %d"}' "$i" "$i" > "$d/$(printf '%06d' "$i")"
    done
}
# FULL holds every section the check reads, and two it doesn't (Side
# effects, Reversals): two holdings under the Run section's cap of 1, so
# sending a5 its execution is at-cap only when Run is read. BARE holds the
# one holding and none of the optional sections.
FULL=$(with_pauses "$(with_holdings "$(scoping a5 25)" "$(active a6 26)")" "$(prow s3 go-ahead "Feature 2" "")" \
    | jq -c --argjson e "[$(dentry 7 coordinator-verdict '"verdict": "hold", "reason": "waits on the benchmark"')]" \
        --argjson o "$(OWEDROW MV9 nobody)" \
        '.decisions = {next: 20, entries: $e} | .work = [$o] | .run = [{key: "cap", value: "1", set_by: "the human", set: "2026-09-26T07:00Z"}]
         | .deferrals = [{deferral: "a carried one", reason: "r", raised: "2026-09-25T10:00Z", disposition: "carried 2026-09-26T08:30Z: later"}]')
BARE=$(with_holdings "$(scoping a5 25)")
# koto_calls <record-json> <entries>: the check's verdict and its koto calls
# on that record with <entries> entries, the calls kept in $T/kc.calls.
koto_calls() {
    seed "$1"; pr 25 OPEN true; pr 26 OPEN true
    session "$(roadmap_vars plugin-system)" send_execution a5
    filler "$S" "$2"
    : > "$KOTO_STORE/calls"
    printf '%s %s' "$(check)" "$(wc -l < "$KOTO_STORE/calls" | tr -d ' ')"
    cp "$KOTO_STORE/calls" "$T/kc.calls"
}
for name in FULL BARE; do
    FEW=$(koto_calls "${!name}" 3)
    MANY=$(koto_calls "${!name}" 300)
    case "${FEW##* }" in ''|*[!0-9]*) bad "$name: the check runs" "$FEW"; continue ;; esac
    eq "$name: the same verdict and koto calls with 3 entries and with 300 (${FEW##* } calls)" "$FEW" "$MANY"
    eq "  ... reading no entry and never listing record/" "0 0" \
        "$(grep -c '^context get [^ ]* record/entries/' "$T/kc.calls") $(grep -c '^context list [^ ]* --prefix record/$' "$T/kc.calls")"
    eval "VERDICT_$name=\${FEW% *}"
done
eq "FULL is judged on the Run section's cap" "at-cap 2/1 0/3" "$VERDICT_FULL"
eq "BARE is clear" "ok a5" "$VERDICT_BARE"
koto_calls "$FULL" 300 > /dev/null
eq "FULL: it reads only the sections and keys its checks need, each got once" \
    "decisions deferrals holdings run standing work" \
    "$(sed -n "s|^context get $S record/\([a-z-]*\)\$|\1|p" "$T/kc.calls" | grep -vx meta | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
# The chain start (coord-log.sh chain-start) lists the run's koto/links/
# relations, a fixed few keys; no record/ key is listed.
eq "  ... and no record key is listed, since every one it reads is there" 0 "$(grep -c "^context list $S --prefix record/" "$T/kc.calls")"
# A section that isn't there is told apart from a failed get by a listing of
# that one key, which names no entry.
koto_calls "$BARE" 300 > /dev/null
eq "BARE: each absent section is listed alone, by its own key" "record/decisions record/run record/standing record/work" \
    "$(sed -n "s|^context list $S --prefix \(record/[a-z-]*\)\$|\1|p" "$T/kc.calls" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
# A key that is listed but can't be got is a failed read (2), not an absent
# section.
cat > "$T/bin/koto" <<EOF
#!/usr/bin/env bash
if [ "\${1:-} \${2:-} \${4:-}" = "context get record/standing" ]; then
    printf '%s\n' "\$*" >> "\$KOTO_STORE/calls"
    echo "koto stub: read failed" >&2
    exit 1
fi
exec "$HERE/testdata/koto" "\$@"
EOF
seed "$FULL"; pr 25 OPEN true; pr 26 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
PATH="$T/bin:$PATH" bash "$DC" --session "$S" > /dev/null 2>&1
eq "a section that is listed but can't be got exits 2" 2 $?

echo "== check mode: the reads that don't wait on each other run together (shirabe#1406) =="
# A koto in front of the stand-in that takes SLOW seconds over every call, as
# each koto call does on a loaded host. The check's verdict is the same, and
# its wall time is well under the sum of its calls: one after another, the
# check takes that sum and outruns koto's 30 s action limit.
mkdir -p "$T/slow"
cat > "$T/slow/koto" <<EOF
#!/usr/bin/env bash
sleep "\${SLOW:-0}"
exec "$HERE/testdata/koto" "\$@"
EOF
chmod +x "$T/slow/koto"
SLOW=1
seed "$(with_holdings "$(scoping a5 25)" | jq -c --argjson d "[$(def 'carried 2026-09-26T08:30Z: later')]" '.deferrals = $d')"
pr 25 OPEN true
session "$(roadmap_vars plugin-system)" send_execution a5
: > "$KOTO_STORE/calls"
start=$(date +%s)
OUT=$(SLOW=$SLOW PATH="$T/slow:$PATH" bash "$DC" --session "$S" 2> "$T/err")
took=$(($(date +%s) - start))
CALLS=$(wc -l < "$KOTO_STORE/calls" | tr -d ' ')
eq "a check behind a slow koto gives the same verdict" "ok a5" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state dispatch_check --sealed "$OUT" && ok "  ... sealed to dispatch_check" || bad "  ... sealed to dispatch_check" "$OUT"
# The bound is half the sum of the calls: far below the check made one call
# at a time, far above one call.
if [ "$took" -lt "$SLOW" ]; then
    bad "  ... its koto reads run together" "took ${took} s, less than one ${SLOW} s call: the slow koto was not called"
elif [ "$took" -lt $((CALLS * SLOW / 2)) ]; then
    ok "  ... its koto reads run together: ${took} s for $CALLS calls of ${SLOW} s each"
else
    bad "  ... its koto reads run together" "took ${took} s for $CALLS calls of ${SLOW} s each, over the bound of half their sum, $((CALLS * SLOW / 2)) s: reads made one after another, which on a loaded host run past koto's 30-second action limit"
fi
# A check killed while its reads are out (koto's action timeout, say) stops
# them and still removes its temporary directory.
PT="$T/check-tmp"
mkdir -p "$PT"
(SLOW=3 PATH="$T/slow:$PATH" TMPDIR="$PT" exec bash "$DC" --session "$S" > /dev/null 2>&1) &
pid=$!
i=0
while [ -z "$(ls -A "$PT")" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
sleep 1
kill -TERM "$pid" 2> /dev/null
wait "$pid" 2> /dev/null
if [ -z "$(ls -A "$PT")" ]; then ok "a check killed mid-read leaves no temporary directory"; else bad "a check killed mid-read leaves no temporary directory" "$(ls -A "$PT")"; fi

done_tests deferral-check
