#!/usr/bin/env bash
# record-find_test.sh -- record-find.sh finds the record by listing, never by
# search, and adopts it only with a declaration line, authority and a
# canonical body.
#
# Covers, at roadmap scope: the record among 150 open issues through the
# paginated listing; a closed issue, a -v2 title and a pull request with the
# title ignored; two matches; no declaration line (foreign); each of the four
# sections missing (malformed); a record for another scope; an unauthorized
# author and an unauthorized last editor; a failed permission read and a failed
# listing (exit 2). At discipline scope: none, unopened, stale-branch, found,
# predecessor, foreign, ambiguous (two open, an impossible date, end before
# start), malformed, unauthorized, a fork's and another base's pull requests
# ignored, and a failed branch read. Also the sealed token and its context
# detail, and facts read from the session.
#
# Usage: bash skills/coordinate/scripts/record-find_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
F="$HERE/record-find.sh"

RM=(--scope roadmap --name plugin-system --repo "$REPO" --no-seal)
DS=(--scope discipline --name ci-health --repo "$REPO" --today 2026-09-26 --no-seal)
ROADMAP_BODY=$(render "$(record_json roadmap plugin-system)" issue)
TITLE="Coordinator record: ROADMAP-plugin-system"

add_issue() { # add_issue <n> <title> <body> [state] [author] [editor]
    db '.issues += [{repo: "acme/widgets", number: $n, title: $t, body: $b, state: $s, author: $a,
        editor: (if $e == "" then null else $e end)}]' --argjson n "$1" --arg t "$2" --arg b "$3" \
        --arg s "${4:-open}" --arg a "${5:-alice}" --arg e "${6-}"
}
find_rm() { local o rc; o=$(bash "$F" "${RM[@]}" 2>"$T/err"); rc=$?; [ -z "$o" ] || seen "$o"; return $rc; }

drop_section() { # drop_section <body> <title>: the body without that section
    printf '%s\n' "$1" | awk -v t="## $2" '$0 == t { skip = 1; next } skip && /^## / { skip = 0 } !skip'
}

echo "== roadmap: the listing =="
db_init
# One DB edit for the 150 issues (seq isn't POSIX, and 150 edits are slow).
db '.issues += [range(1; 151) | if . == 75 then {repo: "acme/widgets", number: ., title: $t, body: $b, state: "open", author: "alice", editor: null}
    else {repo: "acme/widgets", number: ., title: "Issue number \(.)", body: "body \(.)", state: "open", author: "alice", editor: null} end]' \
    --arg t "$TITLE" --arg b "$ROADMAP_BODY"
db '.prs += [{repo: "acme/widgets", number: 151, title: $t, body: $b, state: "OPEN", isDraft: false, isCrossRepository: false,
    baseRefName: "main", headRefName: "x", headRefOid: $h, author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$ROADMAP_BODY" --arg h "$SHA_HEAD"
eq "the record among 150 open issues is found" "found 75" "$(find_rm)"
grep -q -- '--paginate' "$GH_DB.calls" && ok "the listing is paginated" || bad "the listing is paginated" "$(calls)"
db_init; add_issue 7 "$TITLE" "$(cat "$HERE/testdata/record/pre-decisions.md")"
eq "a record body written before the Decisions section is found and adopted" "found 7" "$(find_rm)"
db_init; add_issue 7 "$TITLE" "$(render "$(record_json roadmap plugin-system | jq -c '.decisions = {next: 3, entries: []}')" issue)"
eq "a record with a Decisions section is found and adopted" "found 7" "$(find_rm)"
db_init; add_issue 7 "$TITLE" "$(printf '%s\n\n## Decisions\n\nNext decision: 1\n\nNone.' "$ROADMAP_BODY")"
eq "a Decisions section holding only Next decision: 1 is malformed" "malformed 7" "$(find_rm)"
grep -qi 'search' "$GH_DB.calls" && bad "no search form is used" "$(calls)" || ok "no search form is used"

db_init
add_issue 3 "$TITLE" "$ROADMAP_BODY" closed
eq "a closed record is ignored" none "$(find_rm)"
add_issue 4 "$TITLE-v2" "$ROADMAP_BODY"
add_issue 5 "Coordinator record: ROADMAP-plugin-system-v2" "$(render "$(record_json roadmap plugin-system-v2)" issue)"
eq "a -v2 title is ignored" none "$(find_rm)"
db '.prs += [{repo: "acme/widgets", number: 9, title: $t, body: $b, state: "OPEN", isDraft: false, isCrossRepository: false,
    baseRefName: "main", headRefName: "x", headRefOid: $h, author: "alice", editor: null}]' --arg t "$TITLE" --arg b "$ROADMAP_BODY" --arg h "$SHA_HEAD"
eq "a pull request carrying the title is ignored" none "$(find_rm)"
add_issue 6 "$TITLE" "$ROADMAP_BODY"
add_issue 8 "$TITLE" "$ROADMAP_BODY"
eq "two matches are ambiguous" "ambiguous 8 6" "$(find_rm)"

echo "== roadmap: one candidate =="
db_init; add_issue 7 "$TITLE" "just an issue"
eq "a title match without the declaration line is foreign" "foreign 7" "$(find_rm)"
for sec in "Holdings" "Deferrals" "Side effects in flight" "Reversals"; do
    db_init; add_issue 7 "$TITLE" "$(drop_section "$ROADMAP_BODY" "$sec")"
    eq "a body missing $sec is malformed" "malformed 7" "$(find_rm)"
done
db_init; add_issue 7 "$TITLE" "$(render "$(record_json roadmap other)" issue)"
eq "a record declared for another roadmap is malformed" "malformed 7" "$(find_rm)"
db_init; add_issue 7 "$TITLE" "$ROADMAP_BODY" open bob
eq "an author without write access is unauthorized" "unauthorized 7" "$(find_rm)"
db_init; add_issue 7 "$TITLE" "$ROADMAP_BODY" open alice mallory
db '.permissions["acme/widgets"].mallory = "triage"'
eq "a last editor without write access is unauthorized" "unauthorized 7" "$(find_rm)"
db_init; add_issue 7 "$TITLE" "$ROADMAP_BODY" open carol dave
eq "write and maintain authors and editors are authorized" "found 7" "$(find_rm)"
db_init; add_issue 7 "$TITLE" "$ROADMAP_BODY" open alice
db '.fail = [{match: "collaborators/alice/permission", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
OUT=$(find_rm); rc=$?
eq "a failed permission read exits 2" 2 "$rc"
eq "a failed permission read prints no verdict" "" "$OUT"
db_init; add_issue 7 "$TITLE" "$ROADMAP_BODY" open ghost-user
eq "an author the permission read doesn't know fails closed" 2 "$(find_rm >/dev/null; echo $?)"
db_init; db '.fail = [{match: "issues?state=open", rc: 1}]'
find_rm >/dev/null; eq "a failed listing exits 2" 2 $?

echo "== discipline =="
DTITLE="docs(coordinate): ci-health rotation 2026-09-22 to 2026-09-29"
DBODY=$(render "$(record_json discipline ci-health)" pr)
BR=coordinate/discipline-ci-health
add_pr() { # add_pr <n> <title> <body> [state] [cross] [base] [author]
    db '.prs += [{repo: "acme/widgets", number: $n, title: $t, body: $b, state: $s, isDraft: true,
        isCrossRepository: ($x == "true"), baseRefName: $base, headRefName: $h, headRefOid: $sha, author: $a, editor: null}]' \
        --argjson n "$1" --arg t "$2" --arg b "$3" --arg s "${4:-OPEN}" --arg x "${5:-false}" --arg base "${6:-main}" \
        --arg h "$BR" --arg sha "$SHA_HEAD" --arg a "${7:-alice}"
}
branch() { db '.branches["acme/widgets"][$b] = $s' --arg b "$BR" --arg s "$SHA_HEAD"; }
find_ds() { local o rc; o=$(bash "$F" "${DS[@]}" 2>"$T/err"); rc=$?; [ -z "$o" ] || seen "$o"; return $rc; }

db_init
eq "no branch is none" none "$(find_ds)"
branch
eq "a branch that never had a pull request is unopened" unopened "$(find_ds)"
add_pr 20 "$DTITLE" "$DBODY" MERGED
eq "a branch whose last pull request merged is stale" stale-branch "$(find_ds)"
db_init; branch; add_pr 21 "$DTITLE" "$DBODY" CLOSED
eq "a branch whose last pull request closed is stale" stale-branch "$(find_ds)"
db_init; branch; add_pr 22 "$DTITLE" "$DBODY"
eq "an open, declared, authorized, canonical record is found" "found 22" "$(find_ds)"
db_init; branch; add_pr 22 "docs(coordinate): ci-health rotation 2026-09-18 to 2026-09-25" "$DBODY"
eq "a record past its end date is a predecessor" "predecessor 22" "$(find_ds)"
db_init; branch; add_pr 22 "docs(coordinate): ci-health rotation 2026-09-19 to 2026-09-26" "$DBODY"
eq "a record ending today is still this rotation" "found 22" "$(find_ds)"
db_init; branch; add_pr 22 "$DTITLE" "a draft about something else"
eq "an open pull request without the declaration is foreign" "foreign 22" "$(find_ds)"
db_init; branch; add_pr 22 "$DTITLE" "$DBODY"; add_pr 23 "$DTITLE" "$DBODY"
eq "two open pull requests are ambiguous" "ambiguous 22 23" "$(find_ds)"
db_init; branch; add_pr 22 "docs(coordinate): ci-health rotation 2026-02-30 to 2026-03-06" "$DBODY"
eq "an impossible title date is ambiguous" "ambiguous 22" "$(find_ds)"
db_init; branch; add_pr 22 "docs(coordinate): ci-health rotation 2026-09-29 to 2026-09-22" "$DBODY"
eq "an end before the start is ambiguous" "ambiguous 22" "$(find_ds)"
db_init; branch; add_pr 22 "docs(coordinate): other rotation 2026-09-22 to 2026-09-29" "$DBODY"
eq "another discipline's title is ambiguous" "ambiguous 22" "$(find_ds)"
db_init; branch; add_pr 22 "$DTITLE" "$(drop_section "$DBODY" Reversals)"
eq "a non-canonical record body is malformed" "malformed 22" "$(find_ds)"
db_init; branch; add_pr 22 "$DTITLE" "$(render "$(record_json roadmap ci-health)" issue)"
eq "a roadmap record body on the branch is malformed" "malformed 22" "$(find_ds)"
db_init; branch; add_pr 22 "$DTITLE" "$DBODY" OPEN false main bob
eq "an unauthorized author is unauthorized" "unauthorized 22" "$(find_ds)"
db_init; branch; add_pr 22 "$DTITLE" "$DBODY" OPEN true
eq "a fork's pull request from the same branch name is ignored" unopened "$(find_ds)"
db_init; branch; add_pr 22 "$DTITLE" "$DBODY" OPEN false develop
eq "a pull request into another base is ignored" unopened "$(find_ds)"
db_init; db '.prs += [{repo: "acme/widgets", number: 30, title: $t, body: $b, state: "OPEN", isDraft: true, isCrossRepository: false,
    baseRefName: "main", headRefName: "feat/other", headRefOid: $s, author: "alice", editor: null}]' --arg t "$DTITLE" --arg b "$DBODY" --arg s "$SHA_HEAD"
eq "a pull request from another branch is ignored" none "$(find_ds)"
db_init; db '.fail = [{match: "branches/coordinate", rc: 1, stderr: "gh: Server Error (HTTP 500)"}]'
find_ds >/dev/null; eq "a failed branch read (not a 404) exits 2" 2 $?
db_init; branch; db '.fail = [{match: "pr list", rc: 1}]'
find_ds >/dev/null; eq "a failed pull request listing exits 2" 2 $?

echo "== sealing and session facts =="
db_init; add_issue 7 "$TITLE" "$ROADMAP_BODY"
S=coordinate-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" start_posture record_find
OUT=$(bash "$F" --session "$S" 2>"$T/err"); rc=$?
eq "a session run exits 0" 0 "$rc"
seen "$OUT" > /dev/null
case "$OUT" in "found 7 sealed:"*) ok "the verdict is sealed" ;; *) bad "the verdict is sealed" "$OUT $(cat "$T/err")" ;; esac
bash "$HERE/coord-log.sh" check --session "$S" --state record_find --sealed "$OUT" && ok "the seal checks against the log" || bad "the seal checks against the log"
eq "the detail is stored as data" "found|7|https://github.com/acme/widgets/issues/7" \
    "$(jq -r '"\(.verdict)|\(.ref)|\(.url)"' "$KOTO_STORE/context/$S/coord/record_find.json" 2>&1)"
eq "the found record's URL goes to context key record_url, for the terminal results" "https://github.com/acme/widgets/issues/7" \
    "$(cat "$KOTO_STORE/context/$S/record_url" 2>&1)"
bash "$F" --scope roadmap --name plugin-system --repo "$REPO" >/dev/null 2>&1; eq "sealing without a session is a usage error" 64 $?
bash "$F" --scope roadmap --name plugin-system >/dev/null 2>&1; eq "partial override flags are a usage error" 64 $?
bash "$F" --scope roadmap --name 'a b' --repo "$REPO" --no-seal >/dev/null 2>&1; eq "a bad name is a usage error" 64 $?

tokens_ok record-find
done_tests record-find
