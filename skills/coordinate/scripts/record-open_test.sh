#!/usr/bin/env bash
# record-open_test.sh -- record-open.sh opens exactly one record, in the run's
# own koto session, and refuses when the session already holds one, when the
# body isn't a canonical record for the scope, or when the session fails
# provenance or has a directed transition.
#
# Covers: a roadmap record seeded into the session (record/meta, the empty
# sections, no store row) with no GitHub write and no issue, then refused on a
# second run (10); a seed cut short (record/meta pending, no written time)
# opened again; at discipline scope the record and its window in
# record/rotation; an end before the start, a body for another scope, and a
# body carrying a Decisions section refused (65); --store and --recut usage
# errors; provenance and directed-transition refusals through a prepared
# session log (10).
#
# Usage: bash skills/coordinate/scripts/record-open_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
O="$HERE/record-open.sh"

SR=coordinate-roadmap-plugin-system-20260926T070000Z
RM=(--scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks)
render "$(record_json roadmap plugin-system)" issue > "$T/rm.md"
render "$(record_json discipline ci-health)" issue > "$T/ds.md"
key() { koto context get "$1" "$2" 2>/dev/null; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit|ready)|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }

echo "== roadmap =="
db_init
OUT=$(RS_SESSION=$SR bash "$O" "${RM[@]}" --body-file "$T/rm.md" 2>"$T/err"); rc=$?
eq "a roadmap record opens in the session" "0 record=$SR" "$rc $OUT"
eq "  ... record/meta for this scope, not pending" "roadmap:plugin-system|false" \
    "$(key "$SR" record/meta | jq -r '"\(.scope.kind):\(.scope.name)|\(.pending)"')"
eq "  ... the four sections, empty" "[]|[]|[]|[]" \
    "$(for k in holdings deferrals side-effects reversals; do key "$SR" "record/$k" | jq -c .; done | tr '\n' '|' | sed 's/|$//')"
eq "  ... no store row: the record has no Run section" "" "$(key "$SR" record/run)"
eq "  ... and nothing written on GitHub" "" "$(gh_writes)"
SNAP=$(session_snapshot "$SR")
OUT=$(RS_SESSION=$SR bash "$O" "${RM[@]}" --body-file "$T/rm.md" 2>"$T/err"); rc=$?
eq "a second open is refused with 10" 10 "$rc"
grep -q 'already holds a record' "$T/err" && ok "  ... naming the record already there" || bad "  ... naming the record already there" "$(cat "$T/err")"
eq "  ... and changes no key" "$SNAP" "$(session_snapshot "$SR")"
# A seed cut short: record/meta pending with no written time, as the core
# leaves it before its first section key.
SP=coordinate-roadmap-plugin-system-20260926T071000Z
printf '%s' '{"scope":{"kind":"roadmap","name":"plugin-system"},"store":"session","written":"","pending":true}' | koto context add "$SP" record/meta
printf '[]' | koto context add "$SP" record/holds
OUT=$(RS_SESSION=$SP bash "$O" "${RM[@]}" --body-file "$T/rm.md" 2>"$T/err"); rc=$?
eq "a seed cut short is opened again" "0 record=$SP" "$rc $OUT"
eq "  ... finishing record/meta" false "$(key "$SP" record/meta | jq -r .pending)"
eq "  ... and removing the key the unfinished seed left" "" "$(key "$SP" record/holds)"
S2=coordinate-roadmap-plugin-system-20260926T072000Z
RS_SESSION=$S2 bash "$O" "${RM[@]}" --body-file "$T/ds.md" >/dev/null 2>&1; eq "a discipline body is refused at roadmap scope" 65 $?
render "$(record_json roadmap other)" issue > "$T/other.md"
RS_SESSION=$S2 bash "$O" "${RM[@]}" --body-file "$T/other.md" >/dev/null 2>&1; eq "another roadmap's body is refused" 65 $?
render "$(record_json roadmap plugin-system | jq -c '.decisions = {next: 3, entries: []}')" issue > "$T/dec.md"
RS_SESSION=$S2 bash "$O" "${RM[@]}" --body-file "$T/dec.md" >/dev/null 2>"$T/err"; eq "a body with a Decisions section is refused" 65 $?
grep -q 'record-decision.sh' "$T/err" && ok "the refusal names the decision writer" || bad "the refusal names the decision writer" "$(cat "$T/err")"
eq "a refused body writes nothing" none "$(session_snapshot "$S2")"
RS_SESSION=$S2 bash "$O" "${RM[@]}" --body-file "$T/rm.md" --start 2026-09-26 --end 2026-09-27 >/dev/null 2>&1; eq "dates at roadmap scope are a usage error" 64 $?
RS_SESSION=$S2 bash "$O" "${RM[@]}" --store session --body-file "$T/rm.md" >/dev/null 2>&1; eq "--store is a usage error" 64 $?
RS_SESSION=$S2 bash "$O" "${RM[@]}" --recut --body-file "$T/rm.md" >/dev/null 2>&1; eq "--recut is a usage error" 64 $?
eq "  ... and neither wrote anything" none "$(session_snapshot "$S2")"

echo "== discipline =="
# A rotation's window goes to record/rotation through record-state.sh, which
# needs the run's session: the run is opened and its find sealed `first`.
db_init
SD=coordinate-discipline-ci-health-20260926T080000Z
log_new "$SD" "$(discipline_vars ci-health)"
log_to "$SD" start_posture record_find
log_capture "$SD" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$SD" --state record_find --token first)"
log_to "$SD" record_find record_open
OUT=$(bash "$O" --session "$SD" --body-file "$T/ds.md" --start 2026-09-26 --end 2026-10-03 2>"$T/err"); rc=$?
eq "a rotation opens in the session" "0 record=$SD" "$rc $OUT"
eq "  ... with its window" '{"start":"2026-09-26","end":"2026-10-03","host_repo":"acme/widgets","predecessor":null}' "$(key "$SD" record/rotation | jq -c .)"
eq "  ... and nothing written on GitHub" "" "$(gh_writes)"
DS=(--scope discipline --name ci-health --repo "$REPO" --skip-session-checks)
S3=coordinate-discipline-ci-health-20260926T081000Z
RS_SESSION=$S3 bash "$O" "${DS[@]}" --start 2026-09-26 --end 2026-09-20 --body-file "$T/ds.md" >/dev/null 2>&1
eq "an end before the start is refused" 65 $?
RS_SESSION=$S3 bash "$O" "${DS[@]}" --start 2026-02-30 --end 2026-03-02 --body-file "$T/ds.md" >/dev/null 2>&1
eq "an impossible date is a usage error" 64 $?
RS_SESSION=$S3 bash "$O" "${DS[@]}" --body-file "$T/ds.md" >/dev/null 2>&1
eq "a rotation without its dates is a usage error" 64 $?
RS_SESSION=$S3 bash "$O" "${DS[@]}" --start 2026-09-26 --end 2026-10-03 --body-file "$T/rm.md" >/dev/null 2>&1
eq "a roadmap body is refused at discipline scope" 65 $?

echo "== session checks =="
db_init
S=coordinate-roadmap-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" record_find record_open
OUT=$(bash "$O" --session "$S" --body-file "$T/rm.md" 2>"$T/err"); rc=$?
eq "a session that passes provenance opens" "0 record=$S" "$rc $OUT"
S2=coordinate-roadmap-plugin-system-20260926T090000Z
log_new "$S2" "$(roadmap_vars plugin-system)" 0badbeef
bash "$O" --session "$S2" --body-file "$T/rm.md" >/dev/null 2>"$T/err"; eq "a session from another template is refused" 10 $?
eq "and writes nothing" none "$(session_snapshot "$S2")"
log_end "$S"; log_end "$S2"
S3=coordinate-roadmap-plugin-system-20260926T100000Z
log_new "$S3" "$(roadmap_vars plugin-system)"
log_ev "$S3" directed_transition '{"from":"record_find","to":"record_open"}'
bash "$O" --session "$S3" --body-file "$T/rm.md" >/dev/null 2>"$T/err"; eq "a directed transition in the run is refused" 10 $?
grep -q 'record_find->record_open' "$T/err" && ok "the refusal names the directed edge" || bad "the refusal names the directed edge" "$(cat "$T/err")"
log_end "$S3"
S4=coordinate-roadmap-plugin-system-20260926T110000Z
log_new "$S4" "$(jq -nc '{SCOPE: "roadmap", ROADMAP: "docs/roadmaps/ROADMAP-plugin-system.md", HOST_REPO: "acme/widgets", PLUGIN_ROOT: "/elsewhere"}')"
bash "$O" --session "$S4" --body-file "$T/rm.md" >/dev/null 2>"$T/err"; eq "a PLUGIN_ROOT that isn't this plugin is refused" 10 $?
bash "$O" --scope roadmap --name plugin-system --repo "$REPO" --body-file "$T/rm.md" >/dev/null 2>&1; eq "override flags without a session need --skip-session-checks" 64 $?
bash "$O" --session "$S" --skip-session-checks --body-file "$T/rm.md" >/dev/null 2>&1; eq "--skip-session-checks without the override flags is a usage error" 64 $?
S5=coordinate-roadmap-plugin-system-20260926T120000Z
log_new "$S5" "$(roadmap_vars plugin-system)"
log_to "$S5" record_find record_open
S6=coordinate-roadmap-plugin-system-20260926T130000Z
log_new "$S6" "$(roadmap_vars plugin-system)"
bash "$O" --session "$S5" --body-file "$T/rm.md" >/dev/null 2>"$T/err"; eq "a session that isn't its scope's one live session is refused" 10 $?
eq "and writes nothing" none "$(session_snapshot "$S5")"
eq "no session check or write called GitHub to write" "" "$(gh_writes)"

done_tests record-open
