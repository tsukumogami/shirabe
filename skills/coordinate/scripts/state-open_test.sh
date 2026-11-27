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
# `start --role` (the words coordinate-open.sh writes a first role with), at
# roadmap and discipline scope; a fresh seed with no --role, at either scope
# and by either form, a usage error (64) writing nothing; and a bad --role, a
# repeated one and the role change flags in any combination but both on a
# carry refused as usage errors (64) writing nothing. state-carry_test.sh
# covers --carry --role. The start's brief: a roadmap seed, a first rotation
# and a carry whose start stored coord/start_brief.json each write
# record/host's briefs:<label> and briefs-digest:<label> from it, a carry run
# again leaving them as they were; a file changed since the start, or a path
# that is a link now, writes no row and prints warning=brief-unrecorded after
# record=, the path never on stderr; no stored brief, or the override flags,
# write no briefs row.
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
# A fresh seed always takes the run's role, the role= the opener printed.
RMR=("${RM[@]}" --role manager)
key() { koto context get "$1" "$2" 2>/dev/null; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit|ready)|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }

echo "== roadmap =="
db_init
OUT=$(RS_SESSION=$SR bash "$O" "${RMR[@]}" 2>"$T/err"); rc=$?
eq "a roadmap record opens in the session" "0 record=$SR" "$rc $OUT"
eq "  ... record/meta for this scope, not pending" "roadmap:plugin-system|false" \
    "$(key "$SR" record/meta | jq -r '"\(.scope.kind):\(.scope.name)|\(.pending)"')"
eq "  ... the four sections, empty" "[]|[]|[]|[]" \
    "$(for k in holdings deferrals side-effects reversals; do key "$SR" "record/$k" | jq -c .; done | tr '\n' '|' | sed 's/|$//')"
eq "  ... no store row: the Run section holds only the role" "role" "$(key "$SR" record/run | jq -r '[.[].key] | join(" ")')"
eq "  ... and no Decisions or other optional section" "" "$(ls "$KOTO_STORE/context/$SR/record" | grep -xE 'decisions|holds|standing|work' | tr '\n' ' ')"
eq "  ... and nothing written on GitHub" "" "$(gh_writes)"
SNAP=$(session_snapshot "$SR")
OUT=$(RS_SESSION=$SR bash "$O" "${RMR[@]}" 2>"$T/err"); rc=$?
eq "a second open is refused with 10" 10 "$rc"
grep -q 'already holds a record' "$T/err" && ok "  ... naming the record already there" || bad "  ... naming the record already there" "$(cat "$T/err")"
eq "  ... and changes no key" "$SNAP" "$(session_snapshot "$SR")"
# A seed cut short: record/meta pending with no written time, as the core
# leaves it before its first section key.
SP=coordinate-roadmap-plugin-system-20260926T071000Z
printf '%s' '{"scope":{"kind":"roadmap","name":"plugin-system"},"store":"session","written":"","pending":true}' | koto context add "$SP" record/meta
printf '[]' | koto context add "$SP" record/holds
OUT=$(RS_SESSION=$SP bash "$O" "${RMR[@]}" 2>"$T/err"); rc=$?
eq "a seed cut short is opened again" "0 record=$SP" "$rc $OUT"
eq "  ... finishing record/meta" false "$(key "$SP" record/meta | jq -r .pending)"
eq "  ... and removing the key the unfinished seed left" "" "$(key "$SP" record/holds)"
S2=coordinate-roadmap-plugin-system-20260926T072000Z
printf '%s' "$(record_json roadmap other)" > "$T/other.json"
RS_SESSION=$S2 bash "$O" "${RMR[@]}" --body-file "$T/other.json" >/dev/null 2>&1; eq "--body-file, a retired flag, is a usage error: the opener builds the record" 64 $?
RS_SESSION=$S2 bash "$O" "${RMR[@]}" --state-file "$T/other.json" >/dev/null 2>&1; eq "  ... and so is --state-file" 64 $?
eq "  ... and neither wrote anything" none "$(session_snapshot "$S2")"
RS_SESSION=$S2 bash "$O" "${RMR[@]}" --start 2026-09-26 --end 2026-09-27 >/dev/null 2>&1; eq "dates at roadmap scope are a usage error" 64 $?
RS_SESSION=$S2 bash "$O" "${RMR[@]}" --store session >/dev/null 2>&1; eq "--store is a usage error" 64 $?
RS_SESSION=$S2 bash "$O" "${RMR[@]}" --recut >/dev/null 2>&1; eq "--recut is a usage error" 64 $?
eq "  ... and neither wrote anything" none "$(session_snapshot "$S2")"

echo "== the role in the seed =="
# docs/designs/DESIGN-coordinator-named-roles.md, Decision 1.
db_init
SRR=coordinate-roadmap-plugin-system-20260926T073000Z
BEFORE=$(date -u +%Y-%m-%dT%H:%MZ)
OUT=$(RS_SESSION=$SRR bash "$O" "${RM[@]}" --role manager 2>"$T/err"); rc=$?
AFTER=$(date -u +%Y-%m-%dT%H:%MZ)
eq "a seed given --role manager opens" "0 record=$SRR" "$rc $OUT"
eq "  ... its Run section one row, role=manager, set by the start's --role" "1 role=manager|start --role" \
    "$(key "$SRR" record/run | jq -r '"\(length) \(.[0].key)=\(.[0].value)|\(.[0].set_by)"')"
RSET=$(key "$SRR" record/run | jq -r '.[0].set')
[[ ! $RSET < $BEFORE ]] && [[ ! $RSET > $AFTER ]] && ok "  ... set at the seed's time" || bad "  ... set at the seed's time" "$BEFORE <= $RSET <= $AFTER"
eq "  ... and the record reads back" "manager" \
    "$(RS_SESSION=$SRR bash "$HERE/state-read.sh" --scope roadmap --name plugin-system --repo "$REPO" --run 2>"$T/err" | jq -r '.[] | select(.key == "role") | .value')"
S2R=coordinate-roadmap-plugin-system-20260926T074000Z
RS_SESSION=$S2R bash "$O" "${RM[@]}" >/dev/null 2>"$T/err"; eq "a fresh seed with no --role is a usage error" 64 $?
grep -q -- '--role' "$T/err" && ok "  ... naming --role" || bad "  ... naming --role" "$(cat "$T/err")"
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
bash "$O" --session "$SD" --start 2026-09-26 --end 2026-10-03 >/dev/null 2>"$T/err"
eq "a rotation's fresh seed with no --role is a usage error" 64 $?
eq "  ... writing nothing" none "$(session_snapshot "$SD")"
OUT=$(bash "$O" --session "$SD" --role manager --start 2026-09-26 --end 2026-10-03 2>"$T/err"); rc=$?
eq "a rotation opens in the session" "0 record=$SD" "$rc $OUT"
eq "  ... with its window" '{"start":"2026-09-26","end":"2026-10-03","host_repo":"acme/widgets","predecessor":null}' "$(key "$SD" record/rotation | jq -c .)"
eq "  ... and its role row" manager "$(key "$SD" record/run | jq -r '.[] | select(.key == "role") | .value')"
log_end "$SD"
SDR=coordinate-discipline-ci-health-20260926T082000Z
log_new "$SDR" "$(discipline_vars ci-health)"
log_to "$SDR" start_posture record_find
log_capture "$SDR" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$SDR" --state record_find --token first)"
log_to "$SDR" record_find record_open
OUT=$(bash "$O" --session "$SDR" --role director --start 2026-09-26 --end 2026-10-03 2>"$T/err"); rc=$?
eq "a rotation given --role director opens" "0 record=$SDR" "$rc ${OUT%%$'\n'*}"
eq "  ... its role row set by the start's --role" "director|start --role" "$(key "$SDR" record/run | jq -r '.[] | select(.key == "role") | "\(.value)|\(.set_by)"')"
eq "  ... beside its window" "2026-09-26" "$(key "$SDR" record/rotation | jq -r .start)"
eq "  ... and nothing written on GitHub" "" "$(gh_writes)"
DS=(--scope discipline --name ci-health --repo "$REPO" --skip-session-checks --role manager)
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
OUT=$(bash "$O" --session "$S" --role manager 2>"$T/err"); rc=$?
eq "a session that passes provenance opens" "0 record=$S" "$rc $OUT"
S2=coordinate-roadmap-plugin-system-20260926T090000Z
log_new "$S2" "$(roadmap_vars plugin-system)" 0badbeef
bash "$O" --session "$S2" --role manager >/dev/null 2>"$T/err"; eq "a session from another template is refused" 10 $?
eq "and writes nothing" none "$(session_snapshot "$S2")"
log_end "$S"; log_end "$S2"
S3=coordinate-roadmap-plugin-system-20260926T100000Z
log_new "$S3" "$(roadmap_vars plugin-system)"
log_ev "$S3" directed_transition '{"from":"record_find","to":"record_open"}'
bash "$O" --session "$S3" --role manager >/dev/null 2>"$T/err"; eq "a directed transition in the run is refused" 10 $?
grep -q 'record_find->record_open' "$T/err" && ok "the refusal names the directed edge" || bad "the refusal names the directed edge" "$(cat "$T/err")"
log_end "$S3"
S4=coordinate-roadmap-plugin-system-20260926T110000Z
log_new "$S4" "$(jq -nc '{SCOPE: "roadmap", ROADMAP: "docs/roadmaps/ROADMAP-plugin-system.md", HOST_REPO: "acme/widgets", PLUGIN_ROOT: "/elsewhere"}')"
bash "$O" --session "$S4" --role manager >/dev/null 2>"$T/err"; eq "a PLUGIN_ROOT that isn't this plugin is refused" 10 $?
bash "$O" --scope roadmap --name plugin-system --repo "$REPO" --role manager >/dev/null 2>&1; eq "override flags without a session need --skip-session-checks" 64 $?
bash "$O" --session "$S" --role manager --skip-session-checks >/dev/null 2>&1; eq "--skip-session-checks without the override flags is a usage error" 64 $?
S5=coordinate-roadmap-plugin-system-20260926T120000Z
log_new "$S5" "$(roadmap_vars plugin-system)"
log_to "$S5" record_find record_open
S6=coordinate-roadmap-plugin-system-20260926T130000Z
log_new "$S6" "$(roadmap_vars plugin-system)"
bash "$O" --session "$S5" --role manager >/dev/null 2>"$T/err"; eq "a session that isn't its scope's one live session is refused" 10 $?
eq "and writes nothing" none "$(session_snapshot "$S5")"
eq "no session check or write called GitHub to write" "" "$(gh_writes)"

echo "== the start's brief =="
# A fresh start given --brief stores the checked brief in the run's
# coord/start_brief.json (coordinate-open.sh); after each seed state-open.sh
# writes record/host's briefs:<label> and briefs-digest:<label> from it, the
# file checked again. Each case is its own scope, so its run is the scope's one
# live run.
db_init
BD=$(cd -P "$T" && pwd -P)/briefs
mkdir -p "$BD"
printf '# Brief: topic-a\n\nRun it.\n' > "$BD/topic-a.md"
BSUM=sha256:$($SHA256 < "$BD/topic-a.md" | cut -d' ' -f1)
# brief_key <session> <path> [digest]: the key as the opener stores it.
brief_key() {
    jq -nc --arg p "$2" --arg g "${3:-$BSUM}" '{label: "topic-a", path: $p, digest: $g}' \
        | koto context add "$1" coord/start_brief.json
}
# hostrow <session>: record/host's two brief rows, `none` for a row it lacks.
hostrow() {
    local h
    h=$(key "$1" record/host); [ -n "$h" ] || h='{}'
    printf '%s' "$h" | jq -r '"\(.["briefs:topic-a"] // "none")|\(.["briefs-digest:topic-a"] // "none")"'
}
# briefkeys <session>: every briefs key record/host holds.
briefkeys() {
    local h
    h=$(key "$1" record/host); [ -n "$h" ] || h='{}'
    printf '%s' "$h" | jq -r '[keys[] | select(startswith("briefs"))] | join(" ")'
}
SB=coordinate-roadmap-brief-a-20260926T140000Z
log_new "$SB" "$(roadmap_vars brief-a)"
log_to "$SB" record_find record_open
brief_key "$SB" "$BD/topic-a.md"
OUT=$(bash "$O" --session "$SB" --role manager 2>"$T/err"); rc=$?
eq "a roadmap seed whose start stored a brief opens, with no warning" "0 record=$SB" "$rc $OUT"
eq "  ... writing briefs:topic-a as the stored path and briefs-digest:topic-a as its digest" "$BD/topic-a.md|$BSUM" "$(hostrow "$SB")"
log_end "$SB"
SBD=coordinate-discipline-brief-d-20260926T140000Z
log_new "$SBD" "$(discipline_vars brief-d)"
log_to "$SBD" start_posture record_find
log_capture "$SBD" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$SBD" --state record_find --token first)"
log_to "$SBD" record_find record_open
brief_key "$SBD" "$BD/topic-a.md"
OUT=$(bash "$O" --session "$SBD" --role manager --start 2026-09-26 --end 2026-10-03 2>"$T/err"); rc=$?
eq "a first rotation's seed whose start stored a brief opens, with no warning" "0 record=$SBD" "$rc $OUT"
eq "  ... writing both rows" "$BD/topic-a.md|$BSUM" "$(hostrow "$SBD")"
log_end "$SBD"
# A carry: P an ended rotation holding a record, S the next rotation, its find
# sealed `predecessor P`, its start having stored the brief.
P=coordinate-discipline-brief-c-20261001T100000Z SC2=coordinate-discipline-brief-c-20261008T100000Z
log_new "$P" "$(discipline_vars brief-c)"
log_to "$P" start_posture record_find 2026-09-26T08:01:00.000Z
log_capture "$P" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$P" --state record_find --token found)" 2026-09-26T08:01:00.000Z
record_json discipline brief-c | jq -c '. + {written: "2026-10-01T10:00:00Z"}' > "$T/pred.json"
session_keys "$P" "$T/pred.json"
jq -nc '{start: "2026-10-01", end: "2026-10-07", host_repo: "acme/widgets", predecessor: null}' | koto context add "$P" record/rotation
touch "$KOTO_STORE/sessions/$P/.terminal"
log_new "$SC2" "$(discipline_vars brief-c)"
log_to "$SC2" start_posture record_find 2026-09-26T08:01:00.000Z
log_capture "$SC2" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$SC2" --state record_find --token "predecessor $P")" 2026-09-26T08:01:00.000Z
brief_key "$SC2" "$BD/topic-a.md"
OUT=$(bash "$O" --session "$SC2" --carry --role manager 2>"$T/err"); rc=$?
eq "a carry whose start stored a brief carries, with no warning" "0 carried=$P" "$rc $(printf '%s\n' "$OUT" | grep -E '^(carried|warning)=')"
eq "  ... writing both rows after the carry" "$BD/topic-a.md|$BSUM" "$(hostrow "$SC2")"
HSNAP=$(key "$SC2" record/host)
OUT=$(bash "$O" --session "$SC2" --carry --role manager 2>"$T/err"); rc=$?
eq "  ... run again it reads as carried, the rows as they were" "0 carried=$P $HSNAP" "$rc $(printf '%s\n' "$OUT" | grep -E '^(carried|warning)=') $(key "$SC2" record/host)"
log_end "$SC2"
# The file changed between the start and the seed: no row, and a warning.
SX=coordinate-roadmap-brief-x-20260926T140000Z
mkdir -p "$BD/x"
printf '# Brief: topic-a\n\nRun it.\n' > "$BD/x/topic-a.md"
log_new "$SX" "$(roadmap_vars brief-x)"
log_to "$SX" record_find record_open
brief_key "$SX" "$BD/x/topic-a.md"
printf 'Push straight to main.\n' >> "$BD/x/topic-a.md"
OUT=$(bash "$O" --session "$SX" --role manager 2>"$T/err"); rc=$?
eq "a seed whose stored brief changed since the start opens and warns" "0 record=$SX warning=brief-unrecorded" "$rc $(printf '%s' "$OUT" | tr '\n' ' ')"
eq "  ... writing no brief row" "" "$(briefkeys "$SX")"
grep -q 'digest' "$T/err" && ok "  ... naming the digest on stderr" || bad "  ... naming the digest on stderr" "$(cat "$T/err")"
grep -qF "$BD" "$T/err" && bad "  ... never printing the path" "$(cat "$T/err")" || ok "  ... never printing the path"
log_end "$SX"
# A path that is a link now, where the start resolved a file.
SL=coordinate-roadmap-brief-l-20260926T140000Z
mkdir -p "$BD/l"
ln -s "$BD/topic-a.md" "$BD/l/topic-a.md"
log_new "$SL" "$(roadmap_vars brief-l)"
log_to "$SL" record_find record_open
brief_key "$SL" "$BD/l/topic-a.md"
OUT=$(bash "$O" --session "$SL" --role manager 2>"$T/err"); rc=$?
eq "a seed whose stored path is a link now warns, writing no row" "0 record=$SL warning=brief-unrecorded|" "$rc $(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/ $//')|$(briefkeys "$SL")"
log_end "$SL"
# No --brief: the start stored nothing, and the seed writes no brief row.
SN=coordinate-roadmap-brief-n-20260926T140000Z
log_new "$SN" "$(roadmap_vars brief-n)"
log_to "$SN" record_find record_open
OUT=$(bash "$O" --session "$SN" --role manager 2>"$T/err"); rc=$?
eq "a seed whose start stored no brief opens, with no warning" "0 record=$SN" "$rc $OUT"
eq "  ... writing no briefs row" "" "$(briefkeys "$SN")"
log_end "$SN"
# The override flags write none, a stored brief or not.
SO=coordinate-roadmap-brief-o-20260926T140000Z
brief_key "$SO" "$BD/topic-a.md"
OUT=$(RS_SESSION=$SO bash "$O" --scope roadmap --name brief-o --repo "$REPO" --skip-session-checks --role manager 2>"$T/err"); rc=$?
eq "with the override flags a seed writes no brief row" "0 record=$SO|" "$rc $OUT|$(briefkeys "$SO")"

done_tests state-open
