#!/usr/bin/env bash
# discipline-session_test.sh -- a discipline rotation on the session store
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3),
# through the scripts with the koto and gh stand-ins.
#
# Covers: state-stored-set.sh --rotation and --reasoning-file write record/rotation
# and record/reasoning under the state writer, an accepted write reads back as
# the same JSON, and reasoning of 16 KiB plus one byte, a rotation missing
# start, end or host_repo and a predecessor off the session-name pattern are
# each refused (65) with no key written; --reasoning-check. The find's session
# path seals found, first, predecessor <session> or unreadable <session>: one
# case per rule an earlier session breaks (its
# name, provenance, discipline, host, a predecessor another rotation names, two
# at one stamp, and, called directly, a rotation still open), and a
# predecessor whose record/meta is malformed; a third rotation after a carried
# second finds the second. state-open.sh opens a first rotation in the
# session, building the empty record itself from the window it is given (no
# body), with no GitHub write and no store row; --carry carries a
# predecessor's hold, Standing row, Work row, deferral, unsettled decision,
# next decision number and the legacy store session row, and reports the holds
# and Standing rows; a carry run again reads as carried; reconcile-read.sh
# classifies the predecessor's reasoning present, or not_recorded when its
# window ended without it. A committed handoff file is never read: with no
# earlier session the rotation is first, and decision-next.sh owes no carry
# from one. The handover gate lists carry-unacknowledged until a go-ahead set
# after the run's start, and a carried go-ahead doesn't clear it.
# closeout-read.sh has nothing to read at discipline scope, pick-facts.sh reads
# the window, and state-entry.sh keeps the entries in the session and refuses
# an outward one with nowhere to go.
#
# Usage: bash skills/coordinate/scripts/discipline-session_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
db_init

day() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }
TODAY=$(date -u +%Y-%m-%d)
YESTERDAY=$(day -1)
WEEK_AGO=$(day -7)
TOMORROW=$(day 1)

# The empty record of a discipline, as a reader is handed it.
empty_record() { record_json discipline "$1" | jq -c '. + {written: "2026-09-26T09:00:00Z"}'; }
# sealed <session> <token>: the run's find sealed <token> at record_find.
sealed() {
    log_to "$1" start_posture record_find 2026-09-26T08:01:00.000Z
    log_capture "$1" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$1" --state record_find --token "$2")" 2026-09-26T08:01:00.000Z
}
# rotation <session> <discipline> <start> <end> [<predecessor> [<reasoning>]]:
# a rotation on the session store: its log (opened from this plugin, its find
# sealed a bare found), record/meta and the empty sections, record/rotation,
# and record/reasoning when given. STATE_JSON, when set, is its record.
rotation() {
    local s=$1 d=$2 p=${5:-} r=${6:-}
    log_new "$s" "${VARS_JSON:-$(discipline_vars "$d")}" "${HASH:-feedface}"
    sealed "$s" found
    if [ -n "${STATE_JSON:-}" ]; then printf '%s' "$STATE_JSON" > "$T/rs.json"; else empty_record "$d" > "$T/rs.json"; fi
    session_keys "$s" "$T/rs.json"
    jq -nc --arg s "$3" --arg e "$4" --arg p "$p" '{start: $s, end: $e, host_repo: "acme/widgets", predecessor: (if $p == "" then null else $p end)}' \
        | koto context add "$s" record/rotation
    [ -z "$r" ] || printf '%s' "$r" | jq -R -s . | koto context add "$s" record/reasoning
}
ended() { touch "$KOTO_STORE/sessions/$1/.terminal"; }
# run_find <session> <discipline>: a new run's session whose find hasn't sealed
# yet, and the find's bare token for it.
run_find() {
    [ -d "$KOTO_STORE/sessions/$1" ] || log_new "$1" "$(discipline_vars "$2")"
    bash "$HERE/state-find.sh" --session "$1" --no-seal 2> "$T/find.err"
}
key() { koto context get "$1" "$2" 2>/dev/null; }

echo "== state-stored-set.sh: record/rotation and record/reasoning =="
S=coordinate-discipline-rs-20261001T100000Z
rotation "$S" rs "$TODAY" "$TOMORROW"
printf '%s' '{"start":"2026-10-01","end":"2026-10-07","host_repo":"acme/widgets","predecessor":null}' > "$T/rot.json"
bash "$HERE/state-stored-set.sh" --session "$S" --rotation "$T/rot.json" > "$T/out" 2> "$T/err"
eq "a rotation is written" 0 $?
eq "  ... and reads back as the same JSON" "$(jq -cS . "$T/rot.json")" "$(key "$S" record/rotation | jq -cS .)"
SNAP=$(session_snapshot "$S")
refused_rot() { # refused_rot <label> <json>
    printf '%s' "$2" > "$T/rot.json"
    bash "$HERE/state-stored-set.sh" --session "$S" --rotation "$T/rot.json" > /dev/null 2> "$T/err"
    eq "$1 is refused" 65 $?
    eq "  ... with no key written" "$SNAP" "$(session_snapshot "$S")"
}
refused_rot "a rotation missing start" '{"end":"2026-10-07","host_repo":"acme/widgets","predecessor":null}'
refused_rot "a rotation missing end" '{"start":"2026-10-01","host_repo":"acme/widgets","predecessor":null}'
refused_rot "a rotation missing host_repo" '{"start":"2026-10-01","end":"2026-10-07","predecessor":null}'
refused_rot "a predecessor off the session-name pattern" '{"start":"2026-10-01","end":"2026-10-07","host_repo":"acme/widgets","predecessor":"coordinate-discipline-rs-yesterday"}'
refused_rot "a predecessor of another discipline" '{"start":"2026-10-01","end":"2026-10-07","host_repo":"acme/widgets","predecessor":"coordinate-discipline-other-20260901T100000Z"}'
refused_rot "a rotation on another host" '{"start":"2026-10-01","end":"2026-10-07","host_repo":"acme/gadgets","predecessor":null}'
refused_rot "an end before the start" '{"start":"2026-10-07","end":"2026-10-01","host_repo":"acme/widgets","predecessor":null}'
bash "$HERE/state-stored-set.sh" --session "$S" --reasoning-check > /dev/null 2>&1; eq "--reasoning-check reads none yet" 1 $?
head -c 16385 /dev/zero | tr '\0' 'x' > "$T/big.txt"
bash "$HERE/state-stored-set.sh" --session "$S" --reasoning-file "$T/big.txt" > /dev/null 2> "$T/err"
eq "reasoning of 16 KiB plus one byte is refused" 65 $?
grep -q '16384' "$T/err" && ok "  ... naming the limit" || bad "  ... naming the limit" "$(cat "$T/err")"
eq "  ... with no key written" "$SNAP" "$(session_snapshot "$S")"
head -c 16384 /dev/zero | tr '\0' 'y' > "$T/max.txt"
bash "$HERE/state-stored-set.sh" --session "$S" --reasoning-file "$T/max.txt" > /dev/null 2> "$T/err"
eq "reasoning of exactly 16 KiB is written" 0 $?
printf 'The flaky job is timing.\n\nNext: watch the cache.\n' > "$T/why.txt"
bash "$HERE/state-stored-set.sh" --session "$S" --reasoning-file "$T/why.txt" > /dev/null 2> "$T/err"
eq "  ... and replaced" 0 $?
eq "  ... reading back as the same JSON" "$(jq -R -s -c . "$T/why.txt")" "$(key "$S" record/reasoning | jq -c .)"
bash "$HERE/state-stored-set.sh" --session "$S" --reasoning-check > /dev/null 2>&1; eq "--reasoning-check reads it" 0 $?
GH=coordinate-discipline-rsgh-20261001T100000Z
log_new "$GH" "$(discipline_vars rsgh)"; sealed "$GH" first
printf '%s' '{"start":"2026-10-01","end":"2026-10-07","host_repo":"acme/widgets","predecessor":null}' > "$T/rot.json"
bash "$HERE/state-stored-set.sh" --session "$GH" --rotation "$T/rot.json" > /dev/null 2> "$T/err"
eq "a session holding no record keeps no record/rotation" 10 $?
# A predecessor that isn't a session (`predecessor <n>`, a rotation that ran on
# GitHub) is no record of this run; a rotation's own token reads with no
# record number.
GHP=coordinate-discipline-rsghp-20261001T100000Z
log_new "$GHP" "$(discipline_vars rsghp)"; sealed "$GHP" "predecessor 21"
bash "$HERE/coord-log.sh" run-facts --session "$GHP" > /dev/null 2>&1
eq "run-facts reads no record for a predecessor that isn't a session" 1 $?
SRF=coordinate-discipline-rsfirst-20261001T100000Z
log_new "$SRF" "$(discipline_vars rsfirst)"; sealed "$SRF" first
eq "  ... and the scope, name and host, no number, for a first rotation" '{"scope":"discipline","name":"rsfirst","repo":"acme/widgets"}' \
    "$(bash "$HERE/coord-log.sh" run-facts --session "$SRF")"

echo "== the find: a rotation on the session store =="
# Each case is its own discipline, so its sessions are the only ones of its slug.
SELF=coordinate-discipline-own-20261005T100000Z
rotation "$SELF" own "$TODAY" "$TOMORROW"
eq "this run's own rotation is found" found "$(run_find "$SELF" own)"
eq "the discipline's first rotation is first" first "$(run_find coordinate-discipline-new-20261005T100000Z new)"
P=coordinate-discipline-pred-20261001T100000Z
rotation "$P" pred "$WEEK_AGO" "$YESTERDAY"; ended "$P"
eq "an ended earlier rotation is the predecessor" "predecessor $P" "$(run_find coordinate-discipline-pred-20261005T100000Z pred)"
P=coordinate-discipline-closed-20261001T100000Z
rotation "$P" closed "$WEEK_AGO" "$TOMORROW" "" "closed early"; ended "$P"
eq "a rotation closed early inside its window is the predecessor" "predecessor $P" "$(run_find coordinate-discipline-closed-20261005T100000Z closed)"

unreadable() { # unreadable <label> <discipline> <expected-session> <reason-substring>
    local tok
    tok=$(run_find "coordinate-discipline-$2-20261005T100000Z" "$2")
    eq "$1 is unreadable" "unreadable $3" "$tok"
    grep -q -- "$4" "$T/find.err" && ok "  ... saying why" || bad "  ... saying why" "$(cat "$T/find.err")"
}
P=coordinate-discipline-badname-20261001T100000Zx
rotation "$P" badname "$WEEK_AGO" "$YESTERDAY"; ended "$P"
unreadable "an earlier session whose name isn't coordinate-<slug>-<stamp>" badname "$P" "is not named"
P=coordinate-discipline-prov-20261001T100000Z
HASH=0ddba11 rotation "$P" prov "$WEEK_AGO" "$YESTERDAY"; ended "$P"
unreadable "an earlier session that fails provenance" prov "$P" "fails provenance"
P=coordinate-discipline-disc-20261001T100000Z
VARS_JSON=$(discipline_vars other) rotation "$P" disc "$WEEK_AGO" "$YESTERDAY"; ended "$P"
unreadable "an earlier session of another discipline" disc "$P" "another discipline"
P=coordinate-discipline-host-20261001T100000Z
VARS_JSON=$(discipline_vars host | jq -c '.HOST_REPO = "acme/gadgets"') rotation "$P" host "$WEEK_AGO" "$YESTERDAY"; ended "$P"
unreadable "an earlier session on another host" host "$P" "not acme/widgets"
P=coordinate-discipline-named-20261001T100000Z
rotation "$P" named "$WEEK_AGO" "$YESTERDAY"; ended "$P"
X=coordinate-discipline-named-20261009T100000Z
log_new "$X" "$(discipline_vars named)"
jq -nc --arg p "$P" '{start: "2026-10-09", end: "2026-10-15", host_repo: "acme/widgets", predecessor: $p}' | koto context add "$X" record/rotation
unreadable "a predecessor another rotation already names" named "$P" "already carried by $X"
P=coordinate-discipline-twin-20261001T100000Z
rotation "$P" twin "$WEEK_AGO" "$YESTERDAY"; ended "$P"
rotation "${P}b" twin "$WEEK_AGO" "$YESTERDAY"; ended "${P}b"
unreadable "two earlier rotations at one stamp" twin "$P" "share the stamp"
P=coordinate-discipline-open-20261001T100000Z
rotation "$P" open "$WEEK_AGO" "$TOMORROW"; ended "$P"
unreadable "a predecessor still open, called directly" open "$P" "still open"
P=coordinate-discipline-meta-20261001T100000Z
rotation "$P" meta "$WEEK_AGO" "$YESTERDAY"; ended "$P"
printf '%s' '{"scope": "not a scope"}' | koto context add "$P" record/meta
unreadable "a predecessor whose record/meta is malformed" meta "$P" "doesn't read back"

echo "== a third rotation carries the second =="
A=coordinate-discipline-chain-20261001T100000Z
B=coordinate-discipline-chain-20261008T100000Z
rotation "$A" chain "$WEEK_AGO" "$WEEK_AGO" "" "first rotation"; ended "$A"
rotation "$B" chain "$WEEK_AGO" "$YESTERDAY" "$A" "second rotation"; ended "$B"
eq "the third rotation's predecessor is the second, never the first" "predecessor $B" "$(run_find coordinate-discipline-chain-20261015T100000Z chain)"

echo "== state-open.sh: the first rotation, in the session =="
S=coordinate-discipline-first-20261005T100000Z
log_new "$S" "$(discipline_vars first)"; sealed "$S" first
reset_calls
OUT=$(bash "$HERE/state-open.sh" --session "$S" --start "$TODAY" --end "$TOMORROW" 2> "$T/err")
eq "the first rotation opens" "0 record=$S" "$? $OUT"
eq "  ... with its window and no predecessor" "$(jq -nc --arg s "$TODAY" --arg e "$TOMORROW" '{start: $s, end: $e, host_repo: "acme/widgets", predecessor: null}')" \
    "$(key "$S" record/rotation | jq -c .)"
eq "  ... and no store row: the session holds no Run section" "" "$(key "$S" record/run)"
grep -Eq '^(pr create|pr ready|api --method (POST|DELETE|PUT))' "$GH_DB.calls" && bad "  ... with no GitHub write" "$(calls)" || ok "  ... with no GitHub write"
eq "  ... and the find then reads it as found" found "$(run_find "$S" first)"

echo "== state-open.sh --carry: a predecessor's state =="
P=coordinate-discipline-carry-20261001T100000Z
DEC_OPEN=$(jq -nc '{decision: "3", round: "0", question: "Pin the cache?", options: "pin\nfloat", state: "proposed",
    source: "worker cache [20261001T100000Z report 4]", verdict: "", recommendation: "", reason: "", context: "", problem: "",
    grounds: "", target: "", owed: "", asked: "", evidence: "", outcome: "", decided_by: "", updated: "2026-10-01T10:30Z"}')
DEC_DONE=$(printf '%s' "$DEC_OPEN" | jq -c '.decision = "2" | .state = "settled" | .outcome = "float" | .decided_by = "a person"')
STATE_JSON=$(empty_record carry | jq -c --argjson o "$DEC_OPEN" --argjson d "$DEC_DONE" '
    .deferrals = [{deferral: "flaky cache test", reason: "not now", raised: "2026-10-01T10:00Z", disposition: ""}]
    | .holds = [{hold: "after-release", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-10-01T10:00Z", lifted: ""}]
    | .run = [{key: "store", value: "session", set_by: "the session rotation", set: "2026-10-01T10:00Z"},
              {key: "cap", value: "2", set_by: "the human", set: "2026-10-01T10:00Z"}]
    | .standing = [{standing: "s1", kind: "approval", on: "", until: "", what: "merge the cache fix", owner: "the human", relayed_by: "", set: "2026-10-01T10:00Z"},
                   {standing: "s2", kind: "go-ahead", on: "", until: "", what: "go ahead", owner: "the human", relayed_by: "", set: "2026-10-01T10:05Z"}]
    | .work = [{item: "cache audit", kind: "local-agent", who: "local agent", next: "finish the audit", wakes: "0", updated: "2026-10-01T10:00Z"}]
    | .decisions = {next: 5, entries: [$d, $o]}')
rotation "$P" carry "$WEEK_AGO" "$YESTERDAY" "" "Watch the cache; the flaky test is timing."; ended "$P"
STATE_JSON=
S=coordinate-discipline-carry-20261008T100000Z
log_new "$S" "$(discipline_vars carry)"; sealed "$S" "predecessor $P"
reset_calls
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry 2> "$T/err")
eq "the carry exits 0" 0 $?
eq "  ... printing carried=<predecessor>" "carried=$P" "$(printf '%s\n' "$OUT" | tail -1)"
eq "  ... carrying the deferral" "flaky cache test" "$(key "$S" record/deferrals | jq -r '.[0].deferral')"
eq "  ... the hold" "after-release" "$(key "$S" record/holds | jq -r '.[0].hold')"
eq "  ... the Standing rows" "s1 s2" "$(key "$S" record/standing | jq -r '[.[].standing] | join(" ")')"
eq "  ... the Work row" "cache audit" "$(key "$S" record/work | jq -r '.[0].item')"
eq "  ... the cap" "2" "$(key "$S" record/run | jq -r '.[] | select(.key == "cap") | .value')"
eq "  ... and the legacy store session row as the predecessor held it" "session" "$(key "$S" record/run | jq -r '.[] | select(.key == "store") | .value')"
eq "  ... the unsettled decision only, under the same next number" "5 3" "$(key "$S" record/decisions | jq -r '"\(.next) \([.entries[].decision] | join(" "))"')"
eq "  ... the window from today, naming the predecessor" "$TODAY $P" "$(key "$S" record/rotation | jq -r '"\(.start) \(.predecessor)"')"
eq "  ... and reports the holds and Standing rows" "after-release|s1:approval:the human s2:go-ahead:the human" \
    "$(key "$S" coord/predecessor_carry.json | jq -r '"\([.holds[].hold] | join(" "))|\([.standing[] | "\(.standing):\(.kind):\(.owner)"] | join(" "))"')"
grep -Eq '^(pr create|pr ready|api --method (POST|DELETE|PUT))' "$GH_DB.calls" && bad "  ... with no GitHub write" "$(calls)" || ok "  ... with no GitHub write"
SNAP=$(session_snapshot "$S")
OUT=$(bash "$HERE/state-open.sh" --session "$S" --carry 2> "$T/err")
eq "a carry run again reads as carried" "0 carried=$P" "$? $(printf '%s\n' "$OUT" | tail -1)"
eq "  ... and changes no key" "$SNAP" "$(session_snapshot "$S")"
bash "$HERE/reconcile-read.sh" --session "$S" --reasoning-out "$T/reasoning.txt" > "$T/rec.json" 2> "$T/err"
eq "reconcile reads the carried rotation" "0 found" "$? $(jq -r .status "$T/rec.json" 2>/dev/null)"
eq "  ... classifying the predecessor's reasoning present" present "$(jq -r .reasoning "$T/rec.json")"
eq "  ... writing it verbatim" "Watch the cache; the flaky test is timing." "$(cat "$T/reasoning.txt" 2>/dev/null)"

echo "== a predecessor whose window ended without reasoning =="
P=coordinate-discipline-mute-20261001T100000Z
rotation "$P" mute "$WEEK_AGO" "$YESTERDAY"; ended "$P"
S=coordinate-discipline-mute-20261008T100000Z
log_new "$S" "$(discipline_vars mute)"; sealed "$S" "predecessor $P"
bash "$HERE/state-open.sh" --session "$S" --carry > /dev/null 2> "$T/err"; eq "it is carried" 0 $?
bash "$HERE/reconcile-read.sh" --session "$S" > "$T/rec.json" 2> "$T/err"
eq "  ... and its reasoning is not_recorded" not_recorded "$(jq -r .reasoning "$T/rec.json" 2>/dev/null)"

echo "== no bridge: nothing on GitHub is read for a first rotation =="
S=coordinate-discipline-bridge-20261005T100000Z
reset_calls
eq "with no earlier session the rotation is first" first "$(run_find "$S" bridge)"
eq "  ... and nothing on GitHub is read, a committed handoff file among it" "" "$(calls)"
# decision-next.sh carries nothing from GitHub either: a rotation's decisions
# come only from its predecessor's session.
S=coordinate-discipline-carry-20261008T100000Z
OUT=$(bash "$HERE/decision-next.sh" --session "$S" --owed dispatch 2> "$T/err"); rc=$?
case "$OUT" in carry*) bad "a committed handoff is no carry" "$rc $OUT $(cat "$T/err")" ;;
    *) eq "a committed handoff is no carry" 0 "$rc" ;; esac
S=coordinate-discipline-carry-20261008T100000Z
bash "$HERE/state-decision.sh" --session "$S" --list > /dev/null 2> "$T/err"; eq "  ... and the carried record lists its decisions" 0 $?

echo "== the handover gate: carry-unacknowledged =="
S=coordinate-discipline-carry-20261008T100000Z
gaps() { bash "$HERE/state-handover.sh" --session "$S" 2> "$T/err" | jq -r '[.gaps[].gap] | join(" ")'; }
case " $(gaps) " in *" carry-unacknowledged "*) ok "a carried rotation's gate lists carry-unacknowledged" ;;
    *) bad "a carried rotation's gate lists carry-unacknowledged" "$(gaps) $(cat "$T/err")" ;; esac
eq "  ... though the carry brought a go-ahead" "go-ahead" "$(key "$S" record/standing | jq -r '.[] | select(.standing == "s2") | .kind')"
bash "$HERE/state-stored-set.sh" --session "$S" --standing go-ahead --what "the carried state is acknowledged" --owner "the human" > /dev/null 2> "$T/err"
eq "a person's go-ahead is recorded" 0 $?
case " $(gaps) " in *" carry-unacknowledged "*) bad "  ... and clears it" "$(gaps)" ;; *) ok "  ... and clears it" ;; esac
S=coordinate-discipline-own-20261005T100000Z
case " $(gaps) " in *" carry-unacknowledged "*) bad "a rotation that carried nothing has no such gap" "$(gaps)" ;; *) ok "a rotation that carried nothing has no such gap" ;; esac

echo "== the close-out, the pick and the entries of a rotation =="
S=coordinate-discipline-own-20261005T100000Z
bash "$HERE/closeout-read.sh" --session "$S" --no-seal > /dev/null 2> "$T/err"
eq "closeout-read.sh has no close-out to read at discipline scope" 64 $?
printf 'A new entry.\n' > "$T/entry.txt"
OUT=$(bash "$HERE/state-entry.sh" --session "$S" --kind entry --text-file "$T/entry.txt" 2> "$T/err")
eq "an entry is kept in the session" "0 record/entries/000001" "$? $OUT"
bash "$HERE/state-entry.sh" --session "$S" --kind cost --text-file "$T/entry.txt" > /dev/null 2> "$T/err"
eq "an outward entry with nowhere to go is refused" 65 $?
S=coordinate-discipline-over-20261005T100000Z
rotation "$S" over "$WEEK_AGO" "$YESTERDAY"
bash "$HERE/pick-facts.sh" --session "$S" --no-seal > "$T/pick.out" 2> "$T/err"
eq "pick-facts.sh reads a session rotation past its end as rotation-over" "rotation-over" "$(head -1 "$T/pick.out")"

done_tests discipline-session
