#!/usr/bin/env bash
# read-once_test.sh -- one record read per step (the record seam's
# rs_once_begin; shirabe#1094, #1095), counted through the gh and koto
# stand-ins.
#
# Covers: report-facts.sh reading a 110-holding GitHub record once per
# invocation where it read it twice, with the same verdict, seal and
# coord/report.json, and staying inside its 30-second action limit with each
# record read held to 3 seconds, a moved head included (a GitHub record gets no
# pushed-head write); the same step on the session store assembling the record
# once; a reconcile pass's reads (reconcile-read.sh, then the holding rows the
# settle and the legs classification read) sharing one read on either store; a
# write in the step dropping the shared read, so the next read is live and sees
# it, even when a read the step gave up on lands after the write; a session-store record at the 60,000-byte record budget read by
# reconcile-read.sh inside its own 8-second deadline and the pass's 12, and a
# read past its deadline still named as the record read that timed out; and
# report-facts.sh on that record with a moved head, writing only the holding's
# pushed head, the body and its Written: time untouched, well inside its limit.
#
# The wall-clock cases read the host's own speed: this suite is not on the
# macOS bash 3.2 floor list, whose runners are slower and shared.
#
# Usage: bash skills/coordinate/scripts/read-once_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RF="$HERE/report-facts.sh"
RR="$HERE/reconcile-read.sh"
RH="$HERE/record-holding.sh"

# A gh in front of the stand-in that counts the record's reads (any view of
# issue 7) and, with GH_READ_DELAY set, takes that long over each one: the
# record as it was when the read was asked for, answered that much later.
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
    "issue view 7 "*)
        echo read >> "$T/reads"
        if [ -n "\${GH_READ_DELAY:-}" ]; then
            out=\$("$HERE/testdata/gh" "\$@"); rc=\$?
            sleep "\$GH_READ_DELAY"
            printf '%s\\n' "\$out"
            exit \$rc
        fi ;;
esac
exec "$HERE/testdata/gh" "\$@"
EOF
chmod +x "$T/bin/gh"
PATH="$T/bin:$PATH"
export PATH

reads() { if [ -f "$T/reads" ]; then grep -c read "$T/reads"; else echo 0; fi; }
zero() { : > "$T/reads"; : > "$KOTO_STORE/calls"; }
# assemblies <session>: the session-store reads, one section listing each.
assemblies() { grep -c "^context list $1 --prefix record/\$" "$KOTO_STORE/calls" || true; }
now() { date +%s; }
# shared: the step's shared read is there (rs_once_begin's layout: read.<n>,
# where n counts the writes the step has made).
shared() { [ -d "$RS_ONCE/read.$(cat "$RS_ONCE/gen" 2> /dev/null || echo 0)" ]; }

# holdings <n> [pushed head]: n Holdings rows, worker-<i> on pull request 100+i.
holdings() {
    jq -nc --argjson n "$1" --arg p "${2:-}" '[range(1; $n + 1) | {unit: "Feature \(.): a feature with a long enough title to take some room",
        entry_point: "/shirabe:deliver", mode: "--auto", phase: "executing", dispatch_status: "dispatched", return_path: "message",
        worker: "worker-\(.)", repo: "acme/widgets", branch: "feat/branch-\(.)", verified_head: "", dispatched: "2026-09-26",
        pull_request: "[#\(100 + .)](https://github.com/acme/widgets/pull/\(100 + .))"}
        + (if $p == "" then {} else {pushed_head: $p} end)]'
}
# seed <n>: the GitHub record (#7) with n holdings, and worker-5's pull request.
seed() {
    db_init
    record_json roadmap plugin-system | jq -c --argjson h "$(holdings "$1")" '.holdings = $h' > "$T/rec.json"
    db '.issues += [{repo: "acme/widgets", number: 7, title: "ROADMAP-plugin-system", body: $b, state: "open", author: "alice", editor: null}]' \
        --arg b "$(render "$(cat "$T/rec.json")" issue 2026-10-01T08:00:00Z)"
    db '.prs += [{repo: "acme/widgets", number: 105, title: "w", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/branch-5", headRefOid: $h, author: "alice", editor: null, mergeStateStatus: "CLEAN"}]' \
        --arg h "$SHA_HEAD"
}
# run_report <session>: the hub takes worker-5's report and report_facts runs.
run_report() {
    log_evidence "$1" wait '{"event":"report","unit":"worker-5"}'
    log_to "$1" wait report_facts
    OUT=$(bash "$RF" --session "$1" 2>"$T/err")
    RC=$?
    log_to "$1" report_facts wait
}

echo "== report-facts.sh on GitHub: one read, inside the action limit =="
seed 110
S=coordinate-roadmap-plugin-system-20260926T080000Z
found_session "$S" "$(roadmap_vars plugin-system)" 7
log_to "$S" reconcile wait
zero
run_report "$S"
eq "the report is found" "0 holding 105 worker-5" "$RC ${OUT% sealed:*}"
eq "  ... with one read of the 110-holding record (it read it twice)" 1 "$(reads)"
eq "  ... sealed as the verdict always was" "$(bash "$HERE/coord-log.sh" seal --session "$S" --state report_facts --token "holding 105 worker-5")" "$OUT"
jq -nc --arg h "$SHA_HEAD" --argjson row "$(jq -c '.holdings[4]' "$T/rec.json")" '{unit: "worker-5",
    pull_request: {repo: "acme/widgets", number: 105, url: "https://github.com/acme/widgets/pull/105"},
    state: "OPEN", draft: false, head: $h, merge_state: "CLEAN", holding: $row}' > "$T/want-report.json"
eq "  ... and coord/report.json holds the same facts" "$(jq -cS . "$T/want-report.json")" "$(koto context get "$S" coord/report.json | jq -cS .)"
grep -q '^issue edit' "$GH_DB.calls" && bad "  ... and no record write on GitHub for the moved head" "$(calls)" \
    || ok "  ... and no record write on GitHub for the moved head"
zero
T0=$(now)
GH_READ_DELAY=3 run_report "$S"
EL=$(( $(now) - T0 ))
eq "with each record read taking 3 s, the step still reads once" "0 1" "$RC $(reads)"
[ "$EL" -lt 30 ] && ok "  ... and ends inside its 30 s action limit (${EL}s)" || bad "  ... and ends inside its 30 s action limit" "${EL}s"

echo "== report-facts.sh on the session store: one assembly =="
SS=coordinate-roadmap-plugin-system-20260926T090000Z
found_session "$SS" "$(roadmap_vars plugin-system)" "7 session"
record_json roadmap plugin-system | jq -c --argjson h "$(holdings 110 "$SHA_HEAD")" '.holdings = $h | .written = "2026-10-01T08:00:00Z"' > "$T/srec.json"
session_keys "$SS" "$T/srec.json"
log_to "$SS" reconcile wait
zero
run_report "$SS"
eq "the report is found on the session store" "0 holding 105 worker-5" "$RC ${OUT% sealed:*}"
eq "  ... with one assembly of the record's keys" 1 "$(assemblies "$SS")"
eq "  ... and no GitHub read of it" 0 "$(reads)"

echo "== a reconcile pass's reads share one read =="
pass_reads() { # pass_reads <session>: reconcile-read.sh, then the settle's and the legs' row reads, under one RS_ONCE
    rm -rf "$T/once"
    RS_ONCE="$T/once"; mkdir -p "$RS_ONCE"; export RS_ONCE
    bash "$RR" --session "$1" > "$T/rr.json" 2> "$T/rr.err"; RR_RC=$?
    bash "$RH" --session "$1" --topic worker-3 --read > "$T/row3.json" 2>/dev/null; H3=$?
    bash "$RH" --session "$1" --topic worker-9 --read > "$T/row9.json" 2>/dev/null; H9=$?
    unset RS_ONCE
}
zero
pass_reads "$S"
eq "on GitHub, the record and two holdings are read" "0 found 0 0" "$RR_RC $(jq -r .status "$T/rr.json") $H3 $H9"
eq "  ... from one read" 1 "$(reads)"
eq "  ... the rows the holdings' own" "worker-3 worker-9" "$(jq -r .worker "$T/row3.json") $(jq -r .worker "$T/row9.json")"
zero
pass_reads "$SS"
eq "on the session store, the record and two holdings are read" "0 found 0 0" "$RR_RC $(jq -r .status "$T/rr.json") $H3 $H9"
eq "  ... from one assembly" 1 "$(assemblies "$SS")"

echo "== a write drops the shared read =="
zero
RS_ONCE="$T/once2"; mkdir -p "$RS_ONCE"; export RS_ONCE
# The override flags: two runs of this scope are live here, so a write
# through either session's checks would be refused.
OV=(--scope roadmap --name plugin-system --repo acme/widgets --ref 7)
bash "$RH" "${OV[@]}" --topic worker-3 --read > "$T/before.json" 2>/dev/null
shared && ok "a row read in the step keeps the shared read" || bad "a row read in the step keeps the shared read" "$(ls "$RS_ONCE")"
jq -c '.phase = "held"' "$T/before.json" > "$T/new.json"
bash "$RH" "${OV[@]}" --skip-session-checks --topic worker-3 --row-file "$T/new.json" > /dev/null 2> "$T/w.err"; WRC=$?
eq "a holding row is written in the step" 0 "$WRC"
shared && bad "  ... and the shared read is gone" "$(ls "$RS_ONCE")" || ok "  ... and the shared read is gone"
bash "$RH" "${OV[@]}" --topic worker-3 --read > "$T/after.json" 2>/dev/null
eq "  ... so the next read is live and sees it" "held" "$(jq -r .phase "$T/after.json")"
unset RS_ONCE

echo "== a read that outlives a write leaves no stale shared read =="
# A deadline stops a read's process, never its children, so a read the step
# gave up on can still finish after a later write: what it read is the record
# from before that write, and the step's reads must not take it.
RS_ONCE="$T/once3"; mkdir -p "$RS_ONCE"; export RS_ONCE
GH_READ_DELAY=8 bash "$RH" "${OV[@]}" --topic worker-3 --read > "$T/late.json" 2>/dev/null &
LATE=$!
sleep 2
jq -c '.phase = "scoping"' "$T/after.json" > "$T/new.json"
bash "$RH" "${OV[@]}" --skip-session-checks --topic worker-3 --row-file "$T/new.json" > /dev/null 2> "$T/w.err"; WRC=$?
wait "$LATE"
eq "a row is written while an earlier read is still out" 0 "$WRC"
eq "  ... and that read, landing after the write, reads again and sees it" scoping "$(jq -r .phase "$T/late.json")"
bash "$RH" "${OV[@]}" --topic worker-3 --read > "$T/after.json" 2>/dev/null
eq "  ... as does the step's next read" scoping "$(jq -r .phase "$T/after.json")"
unset RS_ONCE

echo "== a session-store record at the budget, inside the deadlines =="
# The other two runs end, so this one is the scope's live run and may write.
log_end "$S"
log_end "$SS"
SB=coordinate-roadmap-plugin-system-20260926T100000Z
found_session "$SB" "$(roadmap_vars plugin-system)" "7 session"
# The largest row count whose body is still inside the 60,000-byte budget.
n=245
while :; do
    record_json roadmap plugin-system | jq -c --argjson h "$(holdings "$n")" '.holdings = $h | .written = "2026-10-01T08:00:00Z"' > "$T/brec.json"
    SIZE=$(render "$(cat "$T/brec.json")" issue 2026-10-01T08:00:00Z | wc -c | tr -d ' ')
    [ "$SIZE" -le 60000 ] && break
    n=$((n - 5))
done
[ "$SIZE" -gt 57000 ] && ok "the record's body is at the budget ($SIZE of 60000 bytes, $n holdings)" || bad "the record's body is at the budget" "$SIZE bytes"
session_keys "$SB" "$T/brec.json"
log_to "$SB" reconcile wait
T0=$(now)
bash "$RR" --session "$SB" > "$T/rb.json" 2> "$T/rb.err"; RC=$?
EL=$(( $(now) - T0 ))
eq "reconcile-read.sh reads it, inside its own 8 s deadline on the read" "0 found" "$RC $(jq -r .status "$T/rb.json")"
[ "$EL" -lt 12 ] && ok "  ... and the whole read inside the pass's 12 s (${EL}s)" || bad "  ... and the whole read inside the pass's 12 s" "${EL}s"
RECONCILE_READ_DEADLINE=1 bash "$RR" --session "$SB" > "$T/rt.json" 2>/dev/null; RC=$?
eq "a read past its deadline still names the record read" '5 reading the record timed out' "$RC $(jq -r .reason "$T/rt.json")"

session_snapshot "$SB" | grep -v '^./holdings ' > "$T/snap.before"
zero
T0=$(now)
run_report "$SB"
EL=$(( $(now) - T0 ))
eq "report-facts.sh on it, worker-5's head moved, finds the report" "0 holding 105 worker-5" "$RC ${OUT% sealed:*}"
eq "  ... and keeps the new head beside the holding" "$SHA_HEAD" "$(koto context get "$SB" record/holdings | jq -r '.[] | select(.worker == "worker-5") | .pushed_head')"
eq "  ... with no failed write named" "" "$(grep 'pushed head' "$T/err")"
eq "  ... writing only record/holdings, never the body's keys or its Written: time" "$(cat "$T/snap.before")" "$(session_snapshot "$SB" | grep -v '^./holdings ')"
eq "  ... from one assembly of the record" 1 "$(assemblies "$SB")"
[ "$EL" -lt 15 ] && ok "  ... well inside the 30 s action limit (${EL}s)" || bad "  ... well inside the 30 s action limit" "${EL}s"

done_tests read-once_test
