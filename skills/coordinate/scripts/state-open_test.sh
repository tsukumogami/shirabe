#!/usr/bin/env bash
# state-open_test.sh -- state-open.sh opens exactly one record, in the run's
# own koto session, building the scope's empty record itself, and refuses when
# the session already holds one, or when the session fails
# provenance or has a directed transition.
#
# Covers: a roadmap record seeded into the session (record/meta, the empty
# sections, no store row) with no GitHub write and no issue, then refused on a
# second run (10); a seed cut short (record/meta pending, no written time)
# opened again; at discipline scope the record and its window in
# record/rotation; an end before the start refused (65); --body-file,
# --state-file, --store and --recut usage
# errors; provenance and directed-transition refusals through a prepared
# session log (10); the Run `role` row: a seed given --role holding it, set by
# the session the record opens in, at roadmap and discipline scope, a seed
# without --role holding no Run section, and a bad --role, a repeated one and
# the role change flags in any combination but both on a carry refused as
# usage errors (64) writing nothing. state-carry_test.sh covers --carry --role.
#
# Usage: bash skills/coordinate/scripts/state-open_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
O="$HERE/state-open.sh"

SR=coordinate-roadmap-plugin-system-20260926T070000Z
RM=(--scope roadmap --name plugin-system --repo "$REPO" --skip-session-checks)
key() { koto context get "$1" "$2" 2>/dev/null; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit|ready)|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }

echo "== roadmap =="
db_init
OUT=$(RS_SESSION=$SR bash "$O" "${RM[@]}" 2>"$T/err"); rc=$?
eq "a roadmap record opens in the session" "0 record=$SR" "$rc $OUT"
eq "  ... record/meta for this scope, not pending" "roadmap:plugin-system|false" \
    "$(key "$SR" record/meta | jq -r '"\(.scope.kind):\(.scope.name)|\(.pending)"')"
eq "  ... the four sections, empty" "[]|[]|[]|[]" \
    "$(for k in holdings deferrals side-effects reversals; do key "$SR" "record/$k" | jq -c .; done | tr '\n' '|' | sed 's/|$//')"
eq "  ... no store row: the record has no Run section" "" "$(key "$SR" record/run)"
eq "  ... and no Decisions or other optional section" "" "$(ls "$KOTO_STORE/context/$SR/record" | grep -xE 'decisions|holds|standing|work' | tr '\n' ' ')"
eq "  ... and nothing written on GitHub" "" "$(gh_writes)"
SNAP=$(session_snapshot "$SR")
OUT=$(RS_SESSION=$SR bash "$O" "${RM[@]}" 2>"$T/err"); rc=$?
eq "a second open is refused with 10" 10 "$rc"
grep -q 'already holds a record' "$T/err" && ok "  ... naming the record already there" || bad "  ... naming the record already there" "$(cat "$T/err")"
eq "  ... and changes no key" "$SNAP" "$(session_snapshot "$SR")"
# A seed cut short: record/meta pending with no written time, as the core
# leaves it before its first section key.
SP=coordinate-roadmap-plugin-system-20260926T071000Z
printf '%s' '{"scope":{"kind":"roadmap","name":"plugin-system"},"store":"session","written":"","pending":true}' | koto context add "$SP" record/meta
printf '[]' | koto context add "$SP" record/holds
OUT=$(RS_SESSION=$SP bash "$O" "${RM[@]}" 2>"$T/err"); rc=$?
eq "a seed cut short is opened again" "0 record=$SP" "$rc $OUT"
eq "  ... finishing record/meta" false "$(key "$SP" record/meta | jq -r .pending)"
eq "  ... and removing the key the unfinished seed left" "" "$(key "$SP" record/holds)"
S2=coordinate-roadmap-plugin-system-20260926T072000Z
printf '%s' "$(record_json roadmap other)" > "$T/other.json"
RS_SESSION=$S2 bash "$O" "${RM[@]}" --body-file "$T/other.json" >/dev/null 2>&1; eq "--body-file, a retired flag, is a usage error: the opener builds the record" 64 $?
RS_SESSION=$S2 bash "$O" "${RM[@]}" --state-file "$T/other.json" >/dev/null 2>&1; eq "  ... and so is --state-file" 64 $?
eq "  ... and neither wrote anything" none "$(session_snapshot "$S2")"
RS_SESSION=$S2 bash "$O" "${RM[@]}" --start 2026-09-26 --end 2026-09-27 >/dev/null 2>&1; eq "dates at roadmap scope are a usage error" 64 $?
RS_SESSION=$S2 bash "$O" "${RM[@]}" --store session >/dev/null 2>&1; eq "--store is a usage error" 64 $?
RS_SESSION=$S2 bash "$O" "${RM[@]}" --recut >/dev/null 2>&1; eq "--recut is a usage error" 64 $?
eq "  ... and neither wrote anything" none "$(session_snapshot "$S2")"

echo "== the role in the seed =="
# docs/designs/DESIGN-coordinator-named-roles.md, Decision 1.
db_init
SRR=coordinate-roadmap-plugin-system-20260926T073000Z
BEFORE=$(date -u +%Y-%m-%dT%H:%MZ)
OUT=$(RS_SESSION=$SRR bash "$O" "${RM[@]}" --role manager 2>"$T/err"); rc=$?
AFTER=$(date -u +%Y-%m-%dT%H:%MZ)
eq "a seed given --role manager opens" "0 record=$SRR" "$rc $OUT"
eq "  ... its Run section one row, role=manager, set by the session it opens in" "1 role=manager|$SRR" \
    "$(key "$SRR" record/run | jq -r '"\(length) \(.[0].key)=\(.[0].value)|\(.[0].set_by)"')"
RSET=$(key "$SRR" record/run | jq -r '.[0].set')
[[ ! $RSET < $BEFORE ]] && [[ ! $RSET > $AFTER ]] && ok "  ... set at the seed's time" || bad "  ... set at the seed's time" "$BEFORE <= $RSET <= $AFTER"
eq "  ... and the record reads back" "manager" \
    "$(RS_SESSION=$SRR bash "$HERE/state-read.sh" --scope roadmap --name plugin-system --repo "$REPO" --run 2>"$T/err" | jq -r '.[] | select(.key == "role") | .value')"
eq "a seed with no --role still holds no Run section (above)" "" "$(key "$SR" record/run)"
S2R=coordinate-roadmap-plugin-system-20260926T074000Z
RS_SESSION=$S2R bash "$O" "${RM[@]}" --role Director >/dev/null 2>"$T/err"; eq "--role Director is a usage error" 64 $?
RS_SESSION=$S2R bash "$O" "${RM[@]}" --role lead >/dev/null 2>"$T/err"; eq "  ... and --role lead" 64 $?
RS_SESSION=$S2R bash "$O" "${RM[@]}" --role "" >/dev/null 2>"$T/err"; eq "  ... and an empty --role" 64 $?
RS_SESSION=$S2R bash "$O" "${RM[@]}" --role manager --role director >/dev/null 2>"$T/err"; eq "  ... and --role given twice" 64 $?
RS_SESSION=$S2R bash "$O" "${RM[@]}" --role manager --role-change-by "the human" --role-change-source person >/dev/null 2>"$T/err"
eq "the role change flags on a seed are a usage error: only a carry changes a role" 64 $?
eq "  ... and none of them wrote anything" none "$(session_snapshot "$S2R")"
# The change flags' own rules, checked before any read: a carry's session
# isn't even looked at.
SC=coordinate-discipline-ci-health-20260926T090000Z
bash "$O" --session "$SC" --carry --role director --role-change-by "the human" >/dev/null 2>"$T/err"
eq "--role-change-by without --role-change-source is a usage error" 64 $?
bash "$O" --session "$SC" --carry --role director --role-change-source person >/dev/null 2>"$T/err"
eq "  ... and --role-change-source without --role-change-by" 64 $?
bash "$O" --session "$SC" --carry --role-change-by "the human" --role-change-source person >/dev/null 2>"$T/err"
eq "  ... and both without --role" 64 $?
bash "$O" --session "$SC" --carry --role director --role-change-by "the human" --role-change-source boss >/dev/null 2>"$T/err"
eq "  ... and a source other than dispatcher or person" 64 $?
bash "$O" --session "$SC" --carry --role director --role-change-by "$(head -c 81 /dev/zero | tr '\0' 'a')" --role-change-source person >/dev/null 2>"$T/err"
eq "  ... and a --role-change-by over 80 characters" 64 $?
bash "$O" --session "$SC" --carry --role director --role-change-by 'the `human`' --role-change-source person >/dev/null 2>"$T/err"
eq "  ... and one holding a backtick" 64 $?
bash "$O" --session "$SC" --carry --role director --role-change-by "$(printf 'the\nhuman')" --role-change-source person >/dev/null 2>"$T/err"
eq "  ... and one holding a line break" 64 $?
bash "$O" --session "$SC" --carry --role director --role-change-by "" --role-change-source person >/dev/null 2>"$T/err"
eq "  ... and an empty one" 64 $?
eq "  ... none of them writing anything" none "$(session_snapshot "$SC")"

echo "== discipline =="
# A rotation's window goes to record/rotation through state-stored-set.sh, which
# needs the run's session: the run is opened and its find sealed `first`.
db_init
SD=coordinate-discipline-ci-health-20260926T080000Z
log_new "$SD" "$(discipline_vars ci-health)"
log_to "$SD" start_posture record_find
log_capture "$SD" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$SD" --state record_find --token first)"
log_to "$SD" record_find record_open
OUT=$(bash "$O" --session "$SD" --start 2026-09-26 --end 2026-10-03 2>"$T/err"); rc=$?
eq "a rotation opens in the session" "0 record=$SD" "$rc $OUT"
eq "  ... with its window" '{"start":"2026-09-26","end":"2026-10-03","host_repo":"acme/widgets","predecessor":null}' "$(key "$SD" record/rotation | jq -c .)"
eq "  ... and, given no --role, no role row" 0 "$(key "$SD" record/run | jq '[.[] | select(.key == "role")] | length')"
log_end "$SD"
SDR=coordinate-discipline-ci-health-20260926T082000Z
log_new "$SDR" "$(discipline_vars ci-health)"
log_to "$SDR" start_posture record_find
log_capture "$SDR" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$SDR" --state record_find --token first)"
log_to "$SDR" record_find record_open
OUT=$(bash "$O" --session "$SDR" --role director --start 2026-09-26 --end 2026-10-03 2>"$T/err"); rc=$?
eq "a rotation given --role director opens" "0 record=$SDR" "$rc $(printf '%s\n' "$OUT" | head -1)"
eq "  ... its role row set by its session" "director|$SDR" "$(key "$SDR" record/run | jq -r '.[] | select(.key == "role") | "\(.value)|\(.set_by)"')"
eq "  ... beside its window" "2026-09-26" "$(key "$SDR" record/rotation | jq -r .start)"
eq "  ... and nothing written on GitHub" "" "$(gh_writes)"
DS=(--scope discipline --name ci-health --repo "$REPO" --skip-session-checks)
S3=coordinate-discipline-ci-health-20260926T081000Z
RS_SESSION=$S3 bash "$O" "${DS[@]}" --start 2026-09-26 --end 2026-09-20 >/dev/null 2>&1
eq "an end before the start is refused" 65 $?
RS_SESSION=$S3 bash "$O" "${DS[@]}" --start 2026-02-30 --end 2026-03-02 >/dev/null 2>&1
eq "an impossible date is a usage error" 64 $?
RS_SESSION=$S3 bash "$O" "${DS[@]}" >/dev/null 2>&1
eq "a rotation without its dates is a usage error" 64 $?
RS_SESSION=$S3 bash "$O" "${DS[@]}" --start 2026-09-26 --end 2026-10-03 --body-file "$T/x" >/dev/null 2>&1
eq "--body-file, a retired flag, is a usage error at discipline scope too" 64 $?

echo "== session checks =="
db_init
S=coordinate-roadmap-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" record_find record_open
OUT=$(bash "$O" --session "$S" 2>"$T/err"); rc=$?
eq "a session that passes provenance opens" "0 record=$S" "$rc $OUT"
S2=coordinate-roadmap-plugin-system-20260926T090000Z
log_new "$S2" "$(roadmap_vars plugin-system)" 0badbeef
bash "$O" --session "$S2" >/dev/null 2>"$T/err"; eq "a session from another template is refused" 10 $?
eq "and writes nothing" none "$(session_snapshot "$S2")"
log_end "$S"; log_end "$S2"
S3=coordinate-roadmap-plugin-system-20260926T100000Z
log_new "$S3" "$(roadmap_vars plugin-system)"
log_ev "$S3" directed_transition '{"from":"record_find","to":"record_open"}'
bash "$O" --session "$S3" >/dev/null 2>"$T/err"; eq "a directed transition in the run is refused" 10 $?
grep -q 'record_find->record_open' "$T/err" && ok "the refusal names the directed edge" || bad "the refusal names the directed edge" "$(cat "$T/err")"
log_end "$S3"
S4=coordinate-roadmap-plugin-system-20260926T110000Z
log_new "$S4" "$(jq -nc '{SCOPE: "roadmap", ROADMAP: "docs/roadmaps/ROADMAP-plugin-system.md", HOST_REPO: "acme/widgets", PLUGIN_ROOT: "/elsewhere"}')"
bash "$O" --session "$S4" >/dev/null 2>"$T/err"; eq "a PLUGIN_ROOT that isn't this plugin is refused" 10 $?
bash "$O" --scope roadmap --name plugin-system --repo "$REPO" >/dev/null 2>&1; eq "override flags without a session need --skip-session-checks" 64 $?
bash "$O" --session "$S" --skip-session-checks >/dev/null 2>&1; eq "--skip-session-checks without the override flags is a usage error" 64 $?
S5=coordinate-roadmap-plugin-system-20260926T120000Z
log_new "$S5" "$(roadmap_vars plugin-system)"
log_to "$S5" record_find record_open
S6=coordinate-roadmap-plugin-system-20260926T130000Z
log_new "$S6" "$(roadmap_vars plugin-system)"
bash "$O" --session "$S5" >/dev/null 2>"$T/err"; eq "a session that isn't its scope's one live session is refused" 10 $?
eq "and writes nothing" none "$(session_snapshot "$S5")"
eq "no session check or write called GitHub to write" "" "$(gh_writes)"

done_tests state-open
