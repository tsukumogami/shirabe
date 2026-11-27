#!/usr/bin/env bash
# reconcile-settle_test.sh -- reconcile-settle.sh, the one record write the
# reconcile pass makes, through the real state-holding.sh and state-write.sh
# against the gh and koto stand-ins.
#
# Covers: a row still dispatching is rewritten dispatched and nothing else in
# it changes; a row already dispatched, a row whose return path changed since
# the pass read it, and a topic with no row are left alone (settled false); a
# run that fails provenance is refused and reported not verified; a failed
# read is not verified; every fact is one JSON object on stdout, exit 0. The
# record is the run's session's; nothing is written on GitHub.
#
# Usage: bash skills/coordinate/scripts/reconcile-settle_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
ST="$HERE/reconcile-settle.sh"

seed() { # seed <holdings-json-array>: the record, in the current run's session
    db_init
    SR=$S
    seed_session "$SR" "$(record_json roadmap plugin-system | jq -c --argjson h "$1" '.holdings = $h')" 2026-09-26T08:00:00Z
}
live() { session_state "$SR"; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }
stuck() { holding stuck '{"dispatch_status": "dispatching", "branch": "", "verified_head": "", "pull_request": ""}'; }
settle() { bash "$ST" --session "$S" --topic "${1:-stuck}" --return-path "${2:-message}" 2>/dev/null; }

S=coordinate-roadmap-plugin-system-20260926T080000Z
found_session "$S" "$(roadmap_vars plugin-system)"

echo "== settled =="
seed "[$(stuck), $(holding other)]"
OUT=$(settle); rc=$?
eq "a dispatching row is settled" "0 true" "$rc $(printf '%s' "$OUT" | jq -r '.settled')"
eq "the record now says dispatched" dispatched "$(live | jq -r '.holdings[] | select(.worker == "stuck") | .dispatch_status')"
eq "and nothing else in the row changed" "$(stuck | jq -c '.dispatch_status = "dispatched"')" "$(live | jq -c '.holdings[] | select(.worker == "stuck")')"
eq "the other holding is untouched" "$(holding other)" "$(live | jq -c '.holdings[] | select(.worker == "other")')"
eq "the write is the session's record/holdings" dispatched \
    "$(koto context get "$S" record/holdings | jq -r '.[] | select(.worker == "stuck") | .dispatch_status')"
eq "  ... with nothing written on GitHub" "" "$(gh_writes)"

echo "== left alone =="
SNAP=$(session_snapshot "$S")
OUT=$(settle); rc=$?
eq "a row already dispatched is not written again, and says it is dispatched now" "0 false dispatched" "$rc $(printf '%s' "$OUT" | jq -r '"\(.settled) \(.now)"')"
eq "and nothing is written" "$SNAP" "$(session_snapshot "$S")"
seed "[$(stuck)]"
OUT=$(settle stuck "leg req1:work-on"); rc=$?
eq "a row whose return path changed since the pass read it is left alone" "0 false" "$rc $(printf '%s' "$OUT" | jq -r '.settled')"
eq "it stays dispatching" dispatching "$(live | jq -r '.holdings[0].dispatch_status')"
OUT=$(settle nobody); rc=$?
eq "a topic with no row is left alone" "0 false" "$rc $(printf '%s' "$OUT" | jq -r '.settled')"

echo "== not verified =="
S2=coordinate-roadmap-plugin-system-20260926T090000Z
log_end "$S"
found_session "$S2" "$(roadmap_vars plugin-system)" 0badbeef
seed_session "$S2" "$(record_json roadmap plugin-system | jq -c --argjson h "[$(stuck)]" '.holdings = $h')"
OUT=$(bash "$ST" --session "$S2" --topic stuck --return-path message 2>/dev/null); rc=$?
eq "a run that fails provenance is not verified, exit 0" "0 not_verified" "$rc $(printf '%s' "$OUT" | jq -r '.status')"
eq "it stays dispatching" dispatching "$(session_state "$S2" | jq -r '.holdings[0].dispatch_status')"
log_end "$S2"
S=coordinate-roadmap-plugin-system-20260926T100000Z
found_session "$S" "$(roadmap_vars plugin-system)"
seed "[$(stuck)]"
OUT=$(KOTO_NO_LIST_PREFIX=1 bash "$ST" --session "$S" --topic stuck --return-path message 2>/dev/null); rc=$?
eq "a failed read is not verified, exit 0" "0 not_verified" "$rc $(printf '%s' "$OUT" | jq -r '.status')"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$OUT" | jq -e '.kind == "settle"' >/dev/null
eq "every answer is one settle fact" 0 $?
bash "$ST" --session "$S" --topic stuck >/dev/null 2>&1; eq "a missing return path is a usage error" 64 $?

# --- --successor: the Run successor row settled under the successor lock ---------
#
# The stored set's stand-in keeps the row in a file, so each --successor
# write moves it and is logged; STW_RC fails a write. The niwa stand-in lists
# $SS/sessions.json, or fails with $SS/list-fail. The settle runs from a
# workspace root, where the lock lives.
SS="$T/succ"
mkdir -p "$SS/root/.niwa/dispatch-briefs"
: >"$SS/root/.niwa/workspace.toml"
cat >"$SS/state.sh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = --list ]; then
    jq -nc --arg s "$(cat "$SS/row" 2>/dev/null)" '{run: (if $s == "" then [] else [{key: "successor", value: $s, set_by: "coord", set: "2026-09-26T08:00Z"}] end)}'
    exit 0
fi
printf '%s\n' "$*" >>"$SS/writes.log"
[ "${STW_RC:-0}" = 0 ] || { echo "state-stored-set: refused" >&2; exit "$STW_RC"; }
printf '%s %s 2026-11-25\n' "$4" "$5" >"$SS/row"
EOF
cat >"$SS/niwa" <<'EOF'
#!/usr/bin/env bash
[ "$1" = list ] || exit 64
[ ! -f "$SS/list-fail" ] || exit 1
cat "$SS/sessions.json"
EOF
chmod +x "$SS/state.sh" "$SS/niwa"
export SS
SUCC_S=succ_one-""1a2b3c4d
LOCK="$SS/root/.niwa/dispatch-briefs/.successor.coord.lock"
# succ <row> <listed: yes|no|fail>: prints "<rc>|<status settled listing session>|<now>|<row after>|<writes>"
succ() {
    rm -f "$SS/row" "$SS/writes.log" "$SS/list-fail"
    [ -z "$1" ] || printf '%s\n' "$1" >"$SS/row"
    case "$2" in
        yes) printf '[{"name":"x","path":"/p","session_name":"%s"}]\n' "$SUCC_S" >"$SS/sessions.json" ;;
        no) printf '[]\n' >"$SS/sessions.json" ;;
        fail) : >"$SS/list-fail" ;;
    esac
    local out rc
    out=$(cd "$SS/root" && DC_RECORD_STATE="$SS/state.sh" NIWA="$SS/niwa" bash "$ST" --successor --session coord 2>/dev/null); rc=$?
    printf '%s|%s|%s|%s|%s' "$rc" "$(printf '%s' "$out" | jq -r '"\(.status) \(.settled) \(.listing) \(.session)"')" \
        "$(printf '%s' "$out" | jq -r '.now')" "$(cat "$SS/row" 2>/dev/null)" "$(cat "$SS/writes.log" 2>/dev/null)"
}

echo "== --successor =="
eq "a listed dispatching row is written dispatched" \
    "0|ok true listed $SUCC_S|dispatched succ-one 2026-11-25|dispatched succ-one 2026-11-25|--session coord --successor dispatched succ-one --by coord" \
    "$(succ "dispatching succ-one 2026-09-26" yes)"
eq "  ... and the lock it took is gone" no "$([ -e "$LOCK" ] && echo yes || echo no)"
eq "an unlisted dispatched row is written stranded" \
    "0|ok true unlisted |stranded succ-one 2026-11-25|stranded succ-one 2026-11-25|--session coord --successor stranded succ-one --by coord" \
    "$(succ "dispatched succ-one 2026-09-26" no)"
eq "an unlisted dispatching row is left alone" \
    "0|ok false unlisted |dispatching succ-one 2026-09-26|dispatching succ-one 2026-09-26|" "$(succ "dispatching succ-one 2026-09-26" no)"
eq "a listed dispatched row is left alone" \
    "0|ok false listed $SUCC_S|dispatched succ-one 2026-09-26|dispatched succ-one 2026-09-26|" "$(succ "dispatched succ-one 2026-09-26" yes)"
eq "no row is left alone, reading no listing" "0|ok false  |||" "$(succ "" fail)"
eq "a settled row is left alone" \
    "0|ok false  |stranded succ-one 2026-09-26|stranded succ-one 2026-09-26|" "$(succ "stranded succ-one 2026-09-26" no)"
eq "a listing that can't be read is not verified, with no write" \
    "0|not_verified false unread |dispatched succ-one 2026-09-26|dispatched succ-one 2026-09-26|" "$(succ "dispatched succ-one 2026-09-26" fail)"
export STW_RC=65
eq "a write the record refuses is not verified" \
    "0|not_verified false unlisted |dispatched succ-one 2026-09-26|dispatched succ-one 2026-09-26|--session coord --successor stranded succ-one --by coord" \
    "$(succ "dispatched succ-one 2026-09-26" no)"
unset STW_RC
printf '4242\n' >"$LOCK"
eq "a held lock is never taken over: not verified, no listing read, no write" \
    "0|not_verified false  ||dispatched succ-one 2026-09-26|" "$(succ "dispatched succ-one 2026-09-26" no)"
eq "  ... and the held lock is left as it was" 4242 "$(cat "$LOCK")"
OUT=$(cd "$SS/root" && DC_RECORD_STATE="$SS/state.sh" NIWA="$SS/niwa" bash "$ST" --successor --session coord 2>/dev/null)
# The reason names the lock under the workspace root as the settle resolves
# it, the physical path: on macOS the scratch tree is under /var, a link to
# /private/var.
LOCK_P="$(cd "$SS/root" && pwd -P)/.niwa/dispatch-briefs/.successor.coord.lock"
eq "  ... its reason names the lock" yes "$(printf '%s' "$OUT" | jq -r --arg l "$LOCK_P" 'if (.reason | contains($l)) then "yes" else "no" end')"
rm -f "$LOCK"
OUT=$(cd "$SS/root" && DC_RECORD_STATE=/bin/false NIWA="$SS/niwa" bash "$ST" --successor --session coord 2>/dev/null); rc=$?
eq "a row that can't be read is not verified, exit 0" "0 not_verified successor" "$rc $(printf '%s' "$OUT" | jq -r '"\(.status) \(.kind)"')"
bash "$ST" --successor >/dev/null 2>&1; eq "--successor with no session is a usage error" 64 $?
bash "$ST" --successor --session coord --topic x >/dev/null 2>&1; eq "--successor with a topic is a usage error" 64 $?

done_tests reconcile-settle
