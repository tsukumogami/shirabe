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
printf '%s' "$L" | jq -r '.[].stamp' | grep -Evq "$STAMP_RE" && bad "  ... each with a host-clock stamp to the second" "$L" || ok "  ... each with a host-clock stamp to the second"
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
jq -r '.comments[0].body' "$GH_DB" | sed -n 2p | grep -Eq '^\*\*[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\*\* \(host clock\) entry$' \
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

done_tests record-append_test
