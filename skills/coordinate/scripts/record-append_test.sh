#!/usr/bin/env bash
# record-append_test.sh -- record-append.sh, the one way an entry is written to
# the coordinator record: a comment on its container, read back as a list.
#
# Covers: two entries appended to a roadmap record and read back in order with
# their host-clock stamps, author, kind and text, nothing else written (no body
# edit); `@` written encoded and read back decoded; the edited flag; comments
# without the marker, marked comments by an author without write access, and
# one by a login that isn't a collaborator (GitHub's 404), left out of the
# list; a failed access read listing nothing (2); an entry on a discipline
# rotation's pull request; the refusals: a closed record, a target without the
# declaration line, another scope's record, an empty entry, a control
# character, an entry over the budget, an unknown kind (a milestone-verdict,
# milestone-failure or goal-fit
# entry is posted under its kind), and on a public host a
# private repository (as owner/repo#n and as a link), a home-directory path
# and a token-shaped string, without echoing it; what is fine: a tab and CRLF
# line endings, a public repository, and a private repository on a private
# host; a failed post (11); usage errors.
#
# Usage: bash skills/coordinate/scripts/record-append_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RA="$HERE/record-append.sh"

TITLE="Coordinator record: ROADMAP-plugin-system"
RM=(--scope roadmap --name plugin-system --repo "$REPO" --ref 7)
seed() {
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: $t, body: $b, state: "open", author: "alice", editor: null}]' \
        --arg t "$TITLE" --arg b "$(render "$(record_json roadmap plugin-system)" issue 2026-09-26T08:00:00Z)"
}
entry() { printf '%s\n' "$1" > "$T/entry.txt"; }
list() { bash "$RA" "$@" --list; }
STAMP_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

echo "== append and read back =="
seed
db '.now = "2026-10-07T23:00:00Z"'
entry "Dispatched Feature 2 to worker-f2; the brief names the cap of two."
OUT=$(bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "an entry is posted" "0 https://github.com/acme/widgets/issues/7#issuecomment-1001" "$rc $OUT"
grep -q '^issue edit' "$GH_DB.calls" && bad "the body is never edited" "$(calls)" || ok "the body is never edited"
db '.now = "2026-10-07T23:05:00Z"'
printf 'Asked @alice about the release.\n\nShe said go.\n' > "$T/entry2.txt"
bash "$RA" "${RM[@]}" --kind entry --text-file "$T/entry2.txt" >/dev/null 2>"$T/err"; eq "a second entry is posted" 0 $?
L=$(list "${RM[@]}" 2>"$T/err"); eq "the list reads" 0 $?
eq "both entries, oldest first" "1001 1002" "$(printf '%s' "$L" | jq -r 'map(.id | tostring) | join(" ")')"
eq "  ... with GitHub's creation times" "2026-10-07T23:00:00Z 2026-10-07T23:05:00Z" "$(printf '%s' "$L" | jq -r 'map(.created) | join(" ")')"
stamps=$(printf '%s' "$L" | jq -r '.[].stamp')
grep -Evq "$STAMP_RE" <<<"$stamps" && bad "  ... each with a host-clock stamp to the second" "$L" || ok "  ... each with a host-clock stamp to the second"
eq "  ... the author and kind" "coord entry coord entry" "$(printf '%s' "$L" | jq -r 'map("\(.author) \(.kind)") | join(" ")')"
eq "  ... the text as written" "Dispatched Feature 2 to worker-f2; the brief names the cap of two." "$(printf '%s' "$L" | jq -r '.[0].text')"
eq "  ... a multi-line text kept whole, @ decoded" "$(printf 'Asked @alice about the release.\n\nShe said go.')" "$(printf '%s' "$L" | jq -r '.[1].text')"
eq "  ... neither edited" "false false" "$(printf '%s' "$L" | jq -r 'map(.edited | tostring) | join(" ")')"
eq "  ... the text carries no trailing newline" '"Dispatched Feature 2 to worker-f2; the brief names the cap of two."' "$(printf '%s' "$L" | jq -c '.[0].text')"
printf '  \n\t\nkeep &#64;this & @that\n \n' > "$T/amp.txt"
bash "$RA" "${RM[@]}" --text-file "$T/amp.txt" >/dev/null 2>"$T/err"
eq "blank-only edge lines are trimmed, and & and @ come back exactly" "keep &#64;this & @that" "$(list "${RM[@]}" | jq -r '.[-1].text')"
jq -r '.comments[1].body' "$GH_DB" | grep -q '&#64;alice' && ! jq -r '.comments[1].body' "$GH_DB" | grep -q '@alice' \
    && ok "an @ is posted encoded, so the entry mentions no one" || bad "an @ is posted encoded, so the entry mentions no one" "$(jq -r '.comments[1].body' "$GH_DB")"
eq "the comment opens with the marker" "<!-- coordinator-record-entry v1 kind=entry -->" "$(jq -r '.comments[0].body' "$GH_DB" | head -1)"
stamp_line=$(jq -r '.comments[0].body' "$GH_DB" | sed -n 2p)
grep -Eq '^\*\*[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\*\* \(host clock\) entry$' <<<"$stamp_line" \
    && ok "  ... then the stamp line" || bad "  ... then the stamp line" "$(jq -r '.comments[0].body' "$GH_DB")"

echo "== history: what the list counts =="
db '.comments[0].updated_at = "2026-10-07T23:30:00Z"'
eq "an entry changed after it was posted reads edited" "true" "$(list "${RM[@]}" | jq -r '.[0].edited')"
db '.comments += [{repo: "acme/widgets", number: 7, id: 2001, body: "A remark with no marker.", user: "alice",
    created_at: "2026-10-07T23:10:00Z", updated_at: "2026-10-07T23:10:00Z"},
  {repo: "acme/widgets", number: 7, id: 2002, body: "<!-- coordinator-record-entry v1 kind=entry -->\n**2026-10-07T23:11:00Z** (host clock) entry\n\nForged.",
    user: "bob", created_at: "2026-10-07T23:11:00Z", updated_at: "2026-10-07T23:11:00Z"},
  {repo: "acme/widgets", number: 7, id: 2003, body: "<!-- coordinator-record-entry v1 kind=answer -->\n**2026-10-07T23:12:00Z** (host clock) answer\n\nRelayed by hand.",
    user: "carol", created_at: "2026-10-07T23:12:00Z", updated_at: "2026-10-07T23:12:00Z"}]'
eq "an unmarked comment and a read-only author's marked one are left out" "1001 1002 1003 2003" \
    "$(list "${RM[@]}" | jq -r 'map(.id | tostring) | join(" ")')"
eq "  ... a write-access author's marked comment counts, with its kind" "answer" "$(list "${RM[@]}" | jq -r '.[3].kind')"
db '.comments += [{repo: "acme/widgets", number: 7, id: 2004, body: "<!-- coordinator-record-entry v1 kind=entry -->\n**2026-10-07T23:13:00Z** (host clock) entry\n\nFrom outside.",
    user: "mallory", created_at: "2026-10-07T23:13:00Z", updated_at: "2026-10-07T23:13:00Z"}]'
eq "a login that isn't a collaborator (GitHub's 404) is left out, not an error" "1001 1002 1003 2003" \
    "$(list "${RM[@]}" 2>"$T/err" | jq -r 'map(.id | tostring) | join(" ")')"
db '.fail = [{match: "collaborators/carol/permission", rc: 1, stderr: "gh: rate limited"}]'
list "${RM[@]}" >/dev/null 2>"$T/err"; eq "a failed access read lists nothing" 2 $?
db '.fail = []'

echo "== discipline scope =="
db_init
BODY=$(render "$(record_json discipline perf)" pr 2026-09-26T08:00:00Z)
db '.branches["acme/widgets"]["coordinate/discipline-perf"] = "1111111111111111111111111111111111111111"
    | .prs += [{repo: "acme/widgets", number: 9, title: "docs(coordinate): perf rotation 2026-10-06 to 2026-10-13", body: $b,
       state: "OPEN", isDraft: true, isCrossRepository: false, baseRefName: "main", headRefName: "coordinate/discipline-perf",
       headRefOid: "1111111111111111111111111111111111111111", author: "alice", editor: null}]' --arg b "$BODY"
DM=(--scope discipline --name perf --repo "$REPO" --ref 9)
entry "Rotation opened."
bash "$RA" "${DM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "an entry on a rotation's pull request" 0 $?
eq "  ... read back" "Rotation opened." "$(list "${DM[@]}" | jq -r '.[0].text')"

echo "== refusals =="
seed
entry "x"
db '(.issues[] | select(.number == 7)).state = "closed"'
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a closed record is refused" 10 $?
seed
db '(.issues[] | select(.number == 7)).body = "Just an issue."'
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a target without the declaration line is refused" 10 $?
bash "$RA" --scope roadmap --name other --repo "$REPO" --ref 7 --text-file "$T/entry.txt" >/dev/null 2>"$T/err"
eq "another scope's record is refused" 10 $?
seed
printf '\n  \n\n' > "$T/blank.txt"
bash "$RA" "${RM[@]}" --text-file "$T/blank.txt" >/dev/null 2>"$T/err"; eq "an empty entry is refused" 65 $?
printf 'a bell \007 here\n' > "$T/ctl.txt"
bash "$RA" "${RM[@]}" --text-file "$T/ctl.txt" >/dev/null 2>"$T/err"; eq "a control character is refused" 65 $?
printf 'tabs\tand\r\nCRLF are fine\n' > "$T/ok.txt"
bash "$RA" "${RM[@]}" --text-file "$T/ok.txt" >/dev/null 2>"$T/err"; eq "a tab and CRLF line endings are fine" 0 $?
head -c 60001 /dev/zero | tr '\0' 'a' > "$T/big.txt"
bash "$RA" "${RM[@]}" --text-file "$T/big.txt" >/dev/null 2>"$T/err"; eq "an entry over the budget is refused" 65 $?
bash "$RA" "${RM[@]}" --kind gossip --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "an unknown kind is a usage error" 64 $?
bash "$RA" "${RM[@]}" --kind milestone-verdict --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a milestone-verdict entry is posted" 0 $?
eq "  ... under its kind" "milestone-verdict" "$(list "${RM[@]}" | jq -r '.[-1].kind')"
bash "$RA" "${RM[@]}" --kind milestone-verdicts --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "  ... and a kind close to it is still a usage error" 64 $?
bash "$RA" "${RM[@]}" --kind goal-fit --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a goal-fit entry is posted" 0 $?
eq "  ... under its kind" "goal-fit" "$(list "${RM[@]}" | jq -r '.[-1].kind')"
bash "$RA" "${RM[@]}" --kind goal_fit --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "  ... and goal_fit is still a usage error" 64 $?
bash "$RA" "${RM[@]}" --kind milestone-failure --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a milestone-failure entry is posted" 0 $?
eq "  ... under its kind" "milestone-failure" "$(list "${RM[@]}" | jq -r '.[-1].kind')"
bash "$RA" "${RM[@]}" --kind milestone-failures --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "  ... and a kind close to it is still a usage error" 64 $?
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
db '.fail = [{match: "comments --input", rc: 1, stderr: "gh: You have exceeded a secondary rate limit (HTTP 403)"}]'
bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; eq "a refused post is 11" 11 $?
grep -q 'secondary rate limit' "$T/err" && ok "  ... with GitHub's message" || bad "  ... with GitHub's message" "$(cat "$T/err")"

echo "== usage =="
bash "$RA" "${RM[@]}" >/dev/null 2>&1; eq "no text file and no --list" 64 $?
bash "$RA" --scope roadmap --name plugin-system --repo "$REPO" --text-file "$T/entry.txt" >/dev/null 2>&1; eq "the addressed form without --ref" 64 $?
bash "$RA" "${RM[@]}" --list --text-file "$T/entry.txt" >/dev/null 2>&1; eq "--list with a text file" 64 $?

echo "== the session store =="
# A roadmap record on the session store (docs/designs/DESIGN-coordinator-session-record.md,
# Decision 5): entries are keys; the outward kinds are posted too.
SE=coordinate-roadmap-plugin-system-20260926T150000Z
SEN=(env RS_SOURCE=session RS_SESSION="$SE")
# A host clock frozen at one second, so two entries share a stamp.
mkdir -p "$T/frozen"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in +*) echo 2026-10-12T15:00:00Z; exit 0 ;; esac; done\nexec /bin/date "$@"\n' > "$T/frozen/date"
chmod +x "$T/frozen/date"
FROZEN=(env PATH="$T/frozen:$PATH")
seed
koto context add "$SE" record/run < <(jq -nc '[{key: "coordinator", value: "the lane'"'"'s coordinator", set_by: "alice", set: "2026-10-12T09:00Z"}]')
entry "first"; O1=$("${FROZEN[@]}" "${SEN[@]}" bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" 2>"$T/err")
entry "second"; O2=$("${FROZEN[@]}" "${SEN[@]}" bash "$RA" "${RM[@]}" --kind answer --text-file "$T/entry.txt" 2>"$T/err")
eq "two session entries are keys in sequence" "record/entries/000001 record/entries/000002" "$O1 $O2"
eq "  ... and post nothing to GitHub" 0 "$(jq '.comments // [] | length' "$GH_DB")"
L=$("${SEN[@]}" bash "$RA" "${RM[@]}" --list 2>"$T/err"); eq "--list reads them" 0 $?
eq "  ... in sequence order, though their stamps are equal (R9)" "1:first 2:second" "$(printf '%s' "$L" | jq -r '[.[] | "\(.id):\(.text)"] | join(" ")')"
eq "  ... in the GitHub reader's shape" '["author","created","edited","id","kind","stamp","text"]' "$(printf '%s' "$L" | jq -c '.[0] | keys')"
eq "  ... author the coordinator's address, never edited" "the lane's coordinator|false|answer" "$(printf '%s' "$L" | jq -r '.[1] | "\(.author)|\(.edited)|\(.kind)"')"
# A number another writer took between the list and the write moves to the next.
koto context add "$SE" record/entries/000003 < <(jq -nc '{n: 3, stamp: "2026-10-12T15:00:01Z", kind: "entry", text: "by another writer"}')
entry "third"; O=$(KOTO_LIST_HIDE=2 "${SEN[@]}" bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" 2>"$T/err")
eq "a taken number moves to the next" record/entries/000004 "$O"
koto context add "$SE" record/entries/000005 < <(jq -nc '{n: 5, stamp: "2026-10-12T15:00:02Z", kind: "entry", text: "x"}')
koto context add "$SE" record/entries/000006 < <(jq -nc '{n: 6, stamp: "2026-10-12T15:00:03Z", kind: "entry", text: "y"}')
koto context add "$SE" record/entries/000007 < <(jq -nc '{n: 7, stamp: "2026-10-12T15:00:04Z", kind: "entry", text: "z"}')
entry "fourth"; KOTO_LIST_HIDE=4 "${SEN[@]}" bash "$RA" "${RM[@]}" --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; rc=$?
eq "  ... at most three times, then entry-exists" 65 "$rc"
grep -q 'entry-exists' "$T/err" && ok "  ... naming entry-exists" || bad "  ... naming entry-exists" "$(cat "$T/err")"
# An outward kind is written to the session, then posted, its URL kept.
entry "cost of worker-f1"; O=$("${SEN[@]}" bash "$RA" "${RM[@]}" --kind cost --text-file "$T/entry.txt" 2>"$T/err"); rc=$?
eq "an outward entry is posted and its URL printed (R10)" "0 https://github.com/acme/widgets/issues/7#issuecomment-1001" "$rc $O"
eq "  ... kept in record/posted/<n>" "https://github.com/acme/widgets/issues/7#issuecomment-1001" "$(koto context get "$SE" record/posted/000008)"
eq "  ... and the session entry is there too" cost "$(koto context get "$SE" record/entries/000008 | jq -r .kind)"
eq "  ... posted exactly as on GitHub" '<!-- coordinator-record-entry v1 kind=cost -->' "$(jq -r '.comments[0].body' "$GH_DB" | head -1)"
# A failed post keeps the session entry and exits 14; --repost posts it once.
db '.fail = [{match: "POST repos/acme/widgets/issues/7/comments", rc: 1, stderr: "HTTP 502"}]'
entry "goal fit of #12"; "${SEN[@]}" bash "$RA" "${RM[@]}" --kind goal-fit --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; rc=$?
eq "a failed post exits 14" 14 "$rc"
eq "  ... with the session entry kept" goal-fit "$(koto context get "$SE" record/entries/000009 | jq -r .kind)"
koto context exists "$SE" record/posted/000009 && bad "  ... and no posted key" "" || ok "  ... and no posted key"
grep -q -- '--repost 9' "$T/err" && ok "  ... naming the retry" || bad "  ... naming the retry" "$(cat "$T/err")"
db '.fail = []'
O=$("${SEN[@]}" bash "$RA" "${RM[@]}" --repost 9 2>"$T/err"); rc=$?
eq "--repost posts it" "0 https://github.com/acme/widgets/issues/7#issuecomment-1002" "$rc $O"
O=$("${SEN[@]}" bash "$RA" "${RM[@]}" --repost 9 2>"$T/err"); rc=$?
eq "  ... and a second --repost posts nothing" "0 https://github.com/acme/widgets/issues/7#issuecomment-1002 2" "$rc $O $(jq '.comments | length' "$GH_DB")"
# A post that landed before a crash stands in for the entry; an identical earlier
# comment, or one by an author without write access, doesn't.
entry "verdict on M2"; printf '{"n":10,"stamp":"2026-10-12T16:00:00Z","kind":"milestone-verdict","text":"verdict on M2"}' | koto context add "$SE" record/entries/000010
mkc() { db '.comments += [{repo: "acme/widgets", number: 7, id: $i, user: $u, created_at: $c, updated_at: $c,
    body: "<!-- coordinator-record-entry v1 kind=milestone-verdict -->\n**2026-10-12T16:00:00Z** (host clock) milestone-verdict\n\nverdict on M2"}]' \
    --argjson i "$1" --arg u "$2" --arg c "$3"; }
mkc 1500 coord 2026-10-12T15:59:00Z
mkc 1501 bob 2026-10-12T16:00:05Z
db '.now = "2026-10-12T16:00:10Z"'
O=$("${SEN[@]}" bash "$RA" "${RM[@]}" --repost 10 2>"$T/err"); rc=$?
eq "an identical comment before the stamp, or by a reader without write access, doesn't stop the post" \
    "0 https://github.com/acme/widgets/issues/7#issuecomment-1502" "$rc $O"
printf '{"n":11,"stamp":"2026-10-12T17:00:00Z","kind":"milestone-verdict","text":"verdict on M2"}' | koto context add "$SE" record/entries/000011
db '.comments += [{repo: "acme/widgets", number: 7, id: 1600, user: "carol", created_at: "2026-10-12T17:00:03Z", updated_at: "2026-10-12T17:00:03Z",
    body: "<!-- coordinator-record-entry v1 kind=milestone-verdict -->\n**2026-10-12T17:00:00Z** (host clock) milestone-verdict\n\nverdict on M2"}]'
N0=$(jq '.comments | length' "$GH_DB")
O=$("${SEN[@]}" bash "$RA" "${RM[@]}" --repost 11 2>"$T/err"); rc=$?
eq "one by a writer at or after the stamp stands in for it, and nothing is posted" \
    "0 https://github.com/acme/widgets/issues/7#issuecomment-1600 $N0" "$rc $O $(jq '.comments | length' "$GH_DB")"
eq "  ... its URL kept" "https://github.com/acme/widgets/issues/7#issuecomment-1600" "$(koto context get "$SE" record/posted/000011)"
# Another identical entry: every writer's comment from its stamp on is already
# kept as entry 10's or 11's post, so this one is posted.
printf '{"n":12,"stamp":"2026-10-12T16:00:00Z","kind":"milestone-verdict","text":"verdict on M2"}' | koto context add "$SE" record/entries/000012
O=$("${SEN[@]}" bash "$RA" "${RM[@]}" --repost 12 2>"$T/err"); rc=$?
eq "a comment already kept as another entry's post never stands in" "0 https://github.com/acme/widgets/issues/7#issuecomment-1601" "$rc $O"
# A posted URL is a comment on this record, or it isn't kept.
db '.fail = [{match: "POST repos/acme/widgets/issues/7/comments", rc: 0, stderr: ""}]'
entry "cost of worker-f2"; "${SEN[@]}" bash "$RA" "${RM[@]}" --kind cost --text-file "$T/entry.txt" >/dev/null 2>"$T/err"; rc=$?
eq "a post that answers with no comment URL on this record is refused" 65 "$rc"
koto context exists "$SE" record/posted/000013 && bad "  ... and no posted key is kept" "" || ok "  ... and no posted key is kept"
db '.fail = []'
"${SEN[@]}" bash "$RA" "${RM[@]}" --repost 2 >/dev/null 2>"$T/err"; eq "--repost of an entry that stays in the session is refused" 65 $?
bash "$RA" "${RM[@]}" --repost 2 >/dev/null 2>"$T/err"; eq "--repost on the GitHub store is a usage error" 64 $?

done_tests record-append_test
