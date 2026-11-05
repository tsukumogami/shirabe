#!/usr/bin/env bash
# state-entry_test.sh -- state-entry.sh, the one way an entry is written to
# the coordinator record: a key in the run's session, read back as a list.
#
# Covers: two entries written to a roadmap record and read back in order with
# their host-clock stamps, the coordinator's address as author, kind and text,
# each a record/entries/<n> key holding {n, stamp, kind, text}, nothing written
# on GitHub; `@` and `&` kept exactly; blank edge lines trimmed; no
# coordinator row leaving the author empty; an entry on a discipline record;
# the refusals: no session (10), an empty entry, a control character, an entry
# over the budget, an unknown kind, an outward kind (cost, milestone-verdict,
# goal-fit, milestone-failure) without --on, a goal-fit entry with `--on none`
# (a milestone-verdict, milestone-failure or cost entry is written with
# `--on none`, under its kind), and on a public host a private repository (as
# owner/repo#n and as a link), a home-directory path and a token-shaped
# string, without echoing it; what is fine: a tab and CRLF line endings, a
# public repository, and a private repository on a private host; a failed
# entry write (11); the sequence: two entries sharing a stamp kept in order, a
# number another writer took moving to the next, at most three times
# (entry-exists); --repost of an entry that stays in the session, and --repost
# without --on, refused; usage errors. Posting on an item (--on) is
# state-entry-on_test.sh's.
#
# The alignment entry: a well-formed seven-line text of each call written and
# kept in the session, under its kind, with every source form accepted; and
# every refusal alignment_check makes, each 65 with nothing written: a
# missing, extra or reordered line, a blank line, an empty value, a first
# line naming another pull request, a head that isn't 40 hex, a call, Read,
# source, Evidence item, follow-up or Action outside its set, `fits with
# follow-ups` with no follow-up, another call with one, `diverges` with
# Sources `none` or an Action other than `hold`, `hold` on another call, a
# one-line read on a call other than `fits`, and a text over 16 KiB; and
# `--kind alignment` with no --on (65).
#
# Usage: bash skills/coordinate/scripts/state-entry_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RA="$HERE/state-entry.sh"

SR=coordinate-roadmap-plugin-system-20260926T150000Z
export RS_SESSION=$SR
RM=(--scope roadmap --name plugin-system --repo "$REPO")
seed() {
    db_init
    seed_session "$SR" "$(record_json roadmap plugin-system)"
    rm -rf "$KOTO_STORE/context/$SR/record/entries" "$KOTO_STORE/context/$SR/record/posted" "$KOTO_STORE/context/$SR/record/archive"
    jq -nc '[{key: "coordinator", value: "coord", set_by: "alice", set: "2026-10-07T09:00Z"}]' | koto context add "$SR" record/run
}
entry() { printf '%s\n' "$1" > "$T/entry.txt"; }
list() { bash "$RA" "$@" --list; }
key() { koto context get "$SR" "record/entries/$1"; }
gh_writes() { grep -E 'issue (create|edit|close)|pr (create|edit)|comment|--method (POST|PUT|PATCH|DELETE)' "$GH_DB.calls"; }
STAMP_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

echo "== append and read back =="
seed
entry "Dispatched Feature 2 to worker-f2; the brief names the cap of two."
OUT=$(bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "an entry is written" "0 record/entries/000001" "$rc $OUT"
eq "  ... as {n, stamp, kind, text}" '["kind","n","stamp","text"]' "$(key 000001 | jq -c 'keys')"
eq "  ... nothing written on GitHub" "" "$(gh_writes)"
printf 'Asked @alice about the release.\n\nShe said go.\n' > "$T/entry2.txt"
OUT=$(bash "$RA" "${RM[@]}" --kind entry --text-file "$T/entry2.txt" 2>"$T/err"); rc=$?
eq "a second entry is written" "0 record/entries/000002" "$rc $OUT"
L=$(list "${RM[@]}" 2>"$T/err"); eq "the list reads" 0 $?
eq "both entries, oldest first" "1 2" "$(printf '%s' "$L" | jq -r 'map(.id | tostring) | join(" ")')"
eq "  ... created is the stamp" "true" "$(printf '%s' "$L" | jq -r 'all(.[]; .created == .stamp)')"
stamps=$(printf '%s' "$L" | jq -r '.[].stamp')
grep -Evq "$STAMP_RE" <<<"$stamps" && bad "  ... each with a host-clock stamp to the second" "$L" || ok "  ... each with a host-clock stamp to the second"
eq "  ... the author (the coordinator Run row) and kind" "coord entry coord entry" "$(printf '%s' "$L" | jq -r 'map("\(.author) \(.kind)") | join(" ")')"
eq "  ... the text as written" "Dispatched Feature 2 to worker-f2; the brief names the cap of two." "$(printf '%s' "$L" | jq -r '.[0].text')"
eq "  ... a multi-line text kept whole, @ kept" "$(printf 'Asked @alice about the release.\n\nShe said go.')" "$(printf '%s' "$L" | jq -r '.[1].text')"
eq "  ... neither edited" "false false" "$(printf '%s' "$L" | jq -r 'map(.edited | tostring) | join(" ")')"
eq "  ... the text carries no trailing newline" '"Dispatched Feature 2 to worker-f2; the brief names the cap of two."' "$(printf '%s' "$L" | jq -c '.[0].text')"
eq "  ... in the list's shape" '["author","created","edited","id","kind","stamp","text"]' "$(printf '%s' "$L" | jq -c '.[0] | keys')"
printf '  \n\t\nkeep &#64;this & @that\n \n' > "$T/amp.txt"
bash "$RA" "${RM[@]}" --text-file "$T/amp.txt" >/dev/null 2>"$T/err"
eq "blank-only edge lines are trimmed, and & and @ come back exactly" "keep &#64;this & @that" "$(list "${RM[@]}" | jq -r '.[-1].text')"
eq "a read writes nothing on GitHub" "" "$(gh_writes)"
rm -rf "$KOTO_STORE/context/$SR/record/run"
eq "a record with no coordinator row lists an empty author" "" "$(list "${RM[@]}" | jq -r '.[0].author')"
eq "no entry so far is marked as archived" "" "$(ls "$KOTO_STORE/context/$SR/record/archive" 2>/dev/null)"
entry "Decisions 3, settled, moved out of the record body as it held them."
OUT=$(bash "$RA" "${RM[@]}" --kind decisions --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "a decisions entry is written" "0 record/entries/000004" "$rc $OUT"
eq "  ... with its marker, record/archive/<n> holding {n}" '000004 {"n":4}' \
    "$(ls "$KOTO_STORE/context/$SR/record/archive") $(koto context get "$SR" record/archive/000004)"
KOTO_FAIL_ADD=record/archive/000005 bash "$RA" "${RM[@]}" --kind decisions --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; rc=$?
eq "  ... and a failed marker write writes no entry (11)" "11 000004" "$rc $(ls "$KOTO_STORE/context/$SR/record/entries" | tail -1)"

echo "== discipline scope =="
SD=coordinate-discipline-perf-20260926T150000Z
db_init
seed_session "$SD" "$(record_json discipline perf)"
DM=(--scope discipline --name perf --repo "$REPO")
entry "Rotation opened."
OUT=$(RS_SESSION=$SD bash "$RA" "${DM[@]}" --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "an entry on a discipline record" "0 record/entries/000001" "$rc $OUT"
eq "  ... read back" "Rotation opened." "$(RS_SESSION=$SD list "${DM[@]}" | jq -r '.[0].text')"
eq "  ... in its own session" "Rotation opened." "$(koto context get "$SD" record/entries/000001 | jq -r .text)"

echo "== refusals =="
seed
entry "x"
RS_SESSION= bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "no session holding the entries is refused" 10 $?
printf '\n  \n\n' > "$T/blank.txt"
bash "$RA" "${RM[@]}" --text-file "$T/blank.txt" >/dev/null 2>"$T/err"; eq "an empty entry is refused" 65 $?
printf 'a bell \007 here\n' > "$T/ctl.txt"
bash "$RA" "${RM[@]}" --text-file "$T/ctl.txt" >/dev/null 2>"$T/err"; eq "a control character is refused" 65 $?
printf 'tabs\tand\r\nCRLF are fine\n' > "$T/ok.txt"
bash "$RA" "${RM[@]}" --text-file "$T/ok.txt" >/dev/null 2>"$T/err"; eq "a tab and CRLF line endings are fine" 0 $?
head -c 60001 /dev/zero | tr '\0' 'a' > "$T/big.txt"
bash "$RA" "${RM[@]}" --text-file "$T/big.txt" >/dev/null 2>"$T/err"; eq "an entry over the budget is refused" 65 $?
bash "$RA" "${RM[@]}" --kind gossip --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "an unknown kind is a usage error" 64 $?
N0=$(list "${RM[@]}" | jq length)
for k in cost milestone-verdict goal-fit milestone-failure; do
    bash "$RA" "${RM[@]}" --kind "$k" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a $k entry without --on is refused" 65 $?
done
grep -q -- '--on none' "$T/err" && ok "  ... naming --on" || bad "  ... naming --on" "$(cat "$T/err")"
eq "  ... with nothing written" "$N0" "$(list "${RM[@]}" | jq length)"
bash "$RA" "${RM[@]}" --kind milestone-verdict --on none --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a milestone-verdict entry is written with --on none" 0 $?
eq "  ... under its kind" "milestone-verdict" "$(list "${RM[@]}" | jq -r '.[-1].kind')"
bash "$RA" "${RM[@]}" --kind milestone-verdicts --on none --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "  ... and a kind close to it is still a usage error" 64 $?
bash "$RA" "${RM[@]}" --kind goal-fit --on none --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a goal-fit entry with --on none is refused" 65 $?
bash "$RA" "${RM[@]}" --kind goal_fit --on none --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "  ... and goal_fit is a usage error" 64 $?
bash "$RA" "${RM[@]}" --kind milestone-failure --on none --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a milestone-failure entry is written with --on none" 0 $?
eq "  ... under its kind" "milestone-failure" "$(list "${RM[@]}" | jq -r '.[-1].kind')"
bash "$RA" "${RM[@]}" --kind milestone-failures --on none --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "  ... and a kind close to it is still a usage error" 64 $?
bash "$RA" "${RM[@]}" --kind cost --on none --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a cost entry is written with --on none" 0 $?
eq "  ... nothing posted" "" "$(gh_writes)"
entry "Blocked on acme/secret#5 landing."
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a private repository on a public host is refused" 65 $?
grep -q 'acme/secret' "$T/err" && ok "  ... naming it" || bad "  ... naming it" "$(cat "$T/err")"
entry "See https://github.com/acme/secret/pull/3 for why."
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "  ... as a link too" 65 $?
entry "Waiting on acme/gadgets#346, which is public."
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a public repository is fine" 0 $?
# The fixtures below are built at run time, so the repository never carries a
# home-directory path or a token-shaped string itself.
entry "The log is in /ho""me/someone/run.log."
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a home-directory path is refused" 65 $?
entry "token gh""p_abcdefghijklmnopqrstuvwxyz0123 leaked"
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a token-shaped string is refused" 65 $?
grep -q ghp_ "$T/err" && bad "  ... without echoing it" "$(cat "$T/err")" || ok "  ... without echoing it"
db '.repos["acme/widgets"].private = true'
entry "Blocked on acme/secret#5 landing."
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a private host may name a private repository" 0 $?
NEXT=$(printf 'record/entries/%06d' $(( $(list "${RM[@]}" | jq length) + 1 )))
KOTO_FAIL_ADD=$NEXT bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a failed entry write is 11" 11 $?
koto context exists "$SR" "$NEXT" && bad "  ... with no key written" "" || ok "  ... with no key written"
eq "nothing in the refusals reached GitHub" "" "$(gh_writes)"

echo "== the sequence =="
# A host clock frozen at one second, so two entries share a stamp.
mkdir -p "$T/frozen"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in +*) echo 2026-10-12T15:00:00Z; exit 0 ;; esac; done\nexec /bin/date "$@"\n' > "$T/frozen/date"
chmod +x "$T/frozen/date"
FROZEN=(env PATH="$T/frozen:$PATH")
seed
entry "first"; O1=$("${FROZEN[@]}" bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" 2>"$T/err")
entry "second"; O2=$("${FROZEN[@]}" bash "$RA" "${RM[@]}" --kind answer --text-file "$T/entry.txt" 2>"$T/err")
eq "two entries are keys in sequence" "record/entries/000001 record/entries/000002" "$O1 $O2"
L=$(list "${RM[@]}" 2>"$T/err")
eq "  ... listed in sequence order, though their stamps are equal" "1:first 2:second" "$(printf '%s' "$L" | jq -r '[.[] | "\(.id):\(.text)"] | join(" ")')"
eq "  ... sharing the stamp" "2026-10-12T15:00:00Z 2026-10-12T15:00:00Z" "$(printf '%s' "$L" | jq -r 'map(.stamp) | join(" ")')"
# A number another writer took between the list and the write moves to the next.
koto context add "$SR" record/entries/000003 < <(jq -nc '{n: 3, stamp: "2026-10-12T15:00:01Z", kind: "entry", text: "by another writer"}')
entry "third"; O=$(KOTO_LIST_HIDE=2 bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" 2>"$T/err")
eq "a taken number moves to the next" record/entries/000004 "$O"
eq "  ... leaving the other writer's entry as it was" "by another writer" "$(key 000003 | jq -r .text)"
koto context add "$SR" record/entries/000005 < <(jq -nc '{n: 5, stamp: "2026-10-12T15:00:02Z", kind: "entry", text: "x"}')
koto context add "$SR" record/entries/000006 < <(jq -nc '{n: 6, stamp: "2026-10-12T15:00:03Z", kind: "entry", text: "y"}')
koto context add "$SR" record/entries/000007 < <(jq -nc '{n: 7, stamp: "2026-10-12T15:00:04Z", kind: "entry", text: "z"}')
entry "fourth"; KOTO_LIST_HIDE=4 bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; rc=$?
eq "  ... at most three times, then entry-exists" 65 "$rc"
grep -q 'entry-exists' "$T/err" && ok "  ... naming entry-exists" || bad "  ... naming entry-exists" "$(cat "$T/err")"
bash "$RA" "${RM[@]}" --repost 2 --on acme/widgets#12 >/dev/null 2>"$T/err"; eq "--repost of an entry that stays in the session is refused" 65 $?
bash "$RA" "${RM[@]}" --repost 2 >/dev/null 2>"$T/err"; eq "--repost without --on is refused" 65 $?
eq "nothing in the sequence reached GitHub" "" "$(gh_writes)"

echo "== usage =="
entry "x"
bash "$RA" "${RM[@]}" >/dev/null 2>&1; eq "no text file and no --list" 64 $?
bash "$RA" --scope roadmap --name plugin-system --text-file "$T/entry.txt" >/dev/null 2>&1; eq "the addressed form without --repo" 64 $?
bash "$RA" "${RM[@]}" --ref 7 --text-file "$T/entry.txt" >/dev/null 2>&1; eq "--ref is no option" 64 $?
bash "$RA" "${RM[@]}" --list --text-file "$T/entry.txt" >/dev/null 2>&1; eq "--list with a text file" 64 $?
bash "$RA" "${RM[@]}" --list --on none >/dev/null 2>&1; eq "--list with --on" 64 $?
bash "$RA" "${RM[@]}" --kind cost --on acme/widgets --text-file "$T/entry.txt" >/dev/null 2>&1; eq "a malformed --on" 64 $?
bash "$RA" "${RM[@]}" --kind answer --on none --text-file "$T/entry.txt" >/dev/null 2>&1; eq "--on with a kind that stays in the session" 64 $?
bash "$RA" "${RM[@]}" --repost 2 --on none >/dev/null 2>&1; eq "--repost --on none" 64 $?
bash "$RA" "${RM[@]}" --repost two --on acme/widgets#12 >/dev/null 2>&1; eq "--repost of no number" 64 $?

echo "== alignment entries =="
seed
ALH=0123456789abcdef0123456789abcdef01234567
ALS="roadmap docs/roadmaps/ROADMAP-plugin-system.md at $SHA_MAIN Feature 2 clause 1"
# al <call> [Read] [Sources] [Evidence] [Follow-ups] [Action]: a seven-line
# alignment text on acme/widgets#12 at ALH, in $T/al.txt.
al() {
    printf 'Alignment: acme/widgets#12 at %s -- %s\nRead: %s\nSources: %s\nReason: %s\nEvidence: %s\nFollow-ups: %s\nAction: %s\n' \
        "$ALH" "$1" "${2:-full}" "${3:-$ALS}" "the loader skips the manifest the roadmap names" "${4:-1 not met}" "${5:-none}" "${6:-hold}" > "$T/al.txt"
}
alw() { bash "$RA" "${RM[@]}" --kind alignment --on acme/widgets#12 --text-file "$T/al.txt" 2>"$T/err"; }
al diverges
OUT=$(alw); rc=$?
eq "a well-formed diverges call is written" "0 record/entries/000001" "$rc $OUT"
eq "  ... under its kind, its text as written" "alignment|$(cat "$T/al.txt")" "$(key 000001 | jq -r '"\(.kind)|\(.text)"')"
eq "  ... kept in the session, nothing on GitHub" "" "$(gh_writes)"
al fits full "standing s1; decision 3; lane feat-a acme/gadgets#4; lane feat-b docs/designs/x.md; strategy docs/STRATEGY.md at $SHA_MAIN The bet" "1 met; 2 met" none merge
OUT=$(alw); rc=$?
eq "a fits call naming every other source form is written" "0 record/entries/000002" "$rc $OUT"
al fits one-line none none none recommend
OUT=$(alw); rc=$?
eq "a one-line fits call with no sources is written" "0 record/entries/000003" "$rc $OUT"
al "fits with follow-ups" full "$ALS" "1 met" "new: document the flag; new: a second loader" recommend
OUT=$(alw); rc=$?
eq "a fits with follow-ups call is written" "0 record/entries/000004" "$rc $OUT"
N0=$(list "${RM[@]}" | jq length)
# refused <label>: the text in $T/al.txt is refused, 65, nothing written.
refused() {
    alw >/dev/null; local rc=$?
    eq "$1" "65 $N0" "$rc $(list "${RM[@]}" | jq length)"
}
al diverges; sed '7d' "$T/al.txt" > "$T/al.new" && mv "$T/al.new" "$T/al.txt"
refused "a missing line is refused, nothing written"
al diverges; printf 'Note: an eighth line\n' >> "$T/al.txt"
refused "an extra line is refused"
al diverges; awk 'NR == 2 { r = $0; next } NR == 3 { print; print r; next } { print }' "$T/al.txt" > "$T/al.new" && mv "$T/al.new" "$T/al.txt"
refused "a reordered line is refused"
al diverges; awk 'NR == 3 { print; print ""; next } { print }' "$T/al.txt" > "$T/al.new" && mv "$T/al.new" "$T/al.txt"
refused "a blank line between the lines is refused"
al diverges; sed 's/^Reason: .*/Reason: /' "$T/al.txt" > "$T/al.new" && mv "$T/al.new" "$T/al.txt"
refused "an empty Reason is refused"
al diverges; sed 's/acme\/widgets#12/acme\/widgets#13/' "$T/al.txt" > "$T/al.new" && mv "$T/al.new" "$T/al.txt"
refused "a first line naming another pull request is refused"
grep -q 'names acme/widgets#13, not acme/widgets#12' "$T/err" && ok "  ... naming both" || bad "  ... naming both" "$(cat "$T/err")"
ALH=0123456789abcdef; al diverges
refused "a head that isn't 40 hex is refused"
ALH=0123456789ABCDEF0123456789ABCDEF01234567; al diverges
refused "  ... and one in upper case"
ALH=0123456789abcdef0123456789abcdef01234567
al "fits, mostly" full "$ALS" "1 met" none merge
refused "a call outside fits, fits with follow-ups and diverges is refused"
al diverges skimmed
refused "a Read outside full and one-line is refused"
al diverges full "a hunch"
refused "a source of no known form is refused"
al diverges full "roadmap docs/roadmaps/ROADMAP-plugin-system.md at $SHA_MAIN Feature 2"
refused "  ... and a roadmap source with no clause"
al diverges full "$ALS" "1 mostly"
refused "an Evidence item that isn't met or not met is refused"
al "fits with follow-ups" full "$ALS" "1 met" "document the flag" recommend
refused "a follow-up that isn't \`new: <title>\` is refused"
al diverges full "$ALS" "1 not met" none block
refused "an Action outside merge, recommend, hold and none is refused"
al "fits with follow-ups" full "$ALS" "1 met" none recommend
refused "fits with follow-ups and Follow-ups none is refused"
al fits full "$ALS" "1 met" "new: document the flag" merge
refused "fits with a follow-up is refused"
al diverges full none
refused "diverges with Sources none is refused"
al diverges full "$ALS" "1 not met" none none
refused "diverges with an Action other than hold is refused"
al fits full "$ALS" "1 met" none hold
refused "Action hold on a fits call is refused"
al diverges one-line
refused "a one-line read on a diverges call is refused"
al "fits with follow-ups" one-line "$ALS" "1 met" "new: document the flag" recommend
refused "  ... and on a fits with follow-ups call"
al diverges; { head -c 16400 /dev/zero | tr '\0' 'a'; echo; } > "$T/long"
awk -v l="$(cat "$T/long")" 'NR == 4 { print "Reason: " l; next } { print }' "$T/al.txt" > "$T/al.new" && mv "$T/al.new" "$T/al.txt"
refused "an alignment text over 16 KiB is refused"
al diverges
bash "$RA" "${RM[@]}" --kind alignment --text-file "$T/al.txt" >/dev/null 2>"$T/err"; rc=$?
eq "an alignment entry with no --on is refused" "65 $N0" "$rc $(list "${RM[@]}" | jq length)"
eq "nothing in the alignment cases reached GitHub" "" "$(gh_writes)"

done_tests state-entry_test
