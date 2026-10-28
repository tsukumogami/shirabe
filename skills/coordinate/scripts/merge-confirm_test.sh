#!/usr/bin/env bash
# merge-confirm_test.sh -- merge-confirm.sh reads the pull request and the
# head from land's own capture and confirms the merge from GitHub's record:
# the pull request MERGED from the verified head, its merge commit on the
# default branch.
#
# Covers: merged (the merge commit behind or identical to the default
# branch; a merge commit other than the head, as a plain merge commit or a
# rebase gives); unconfirmed when the head GitHub merged isn't the verified
# one (it moved after verify), when the merge commit isn't on the default
# branch, or when the pull request isn't merged yet; three reads whatever the
# pull request's size (a 300-file pull request); a failed or not-found
# comparison, a merged pull request with no merge commit, a comparison status
# that isn't one, a failed pull request read, and an absent, stale or
# non-permit land capture, each exit 2; the token sealed to merge_confirm;
# --pr that disagrees with the capture.
#
# Runs offline on the gh-board and koto stand-ins in a localized plugin tree.
# Usage: bash skills/coordinate/scripts/merge-confirm_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/merge-confirm-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
MC="$PS/merge-confirm.sh"
CL="$PS/coord-log.sh"
PERMIT="readable merge:permit close:permit teardown:permit release:permit"
N=0
at_confirm() { # a run whose land sealed permit 12 H and whose merge was attempted
    N=$((N + 1))
    S="coordinate-demo-20260926T1300$(printf '%02d' "$N")Z"
    bt_run "$S" "$PERMIT"
    bt_verified "$S" 12 "$H"
    bt_enter "$S" land
    bt_sealed "$S" land LAND "permit 12 $H"
    bt_enter "$S" land_merge
    bt_evidence "$S" land_merge '{"outcome":"attempted"}'
    bt_enter "$S" merge_confirm
    rm -rf "$GH_BOARD_DIR"; mkdir -p "$GH_BOARD_DIR"
    bt_merged MERGED; bt_reach behind
}
token() { bash "$MC" --session "$S" --repo acme/widgets "$@" 2>"$T/err" | sed 's/ sealed:.*//'; }
calls() { grep -c . "$GH_BOARD_DIR/calls" 2>/dev/null || echo 0; }

echo "== merged and unconfirmed =="
at_confirm
OUT=$(bash "$MC" --session "$S" --repo acme/widgets 2>"$T/err")
eq "merged from the verified head, its merge commit on main: merged" "merged 12 $H" "${OUT% sealed:*}"
bash "$CL" check --session "$S" --state merge_confirm --sealed "$OUT" && ok "sealed to the latest entry into merge_confirm" || bad "sealed to the latest entry into merge_confirm"
grep -q "compare/main...$BT_MC" "$GH_BOARD_DIR/calls" && grep -q 'pr view 12' "$GH_BOARD_DIR/calls" \
    && ok "the pull request's record is read and its merge commit compared with the default branch" \
    || bad "the pull request's record is read and its merge commit compared with the default branch" "$(cat "$GH_BOARD_DIR/calls")"
at_confirm; bt_reach identical
eq "a merge commit that is the default branch's head: merged" "merged 12 $H" "$(token)"
# A plain merge commit has the head as a parent and a rebase replays it: in
# both GitHub records a merge commit other than the head, which is what the
# check reads, so either confirms like a squash.
at_confirm; bt_merged MERGED "$H" "$MOVED"; bt_reach behind "$MOVED"
eq "a merge commit other than the head (a plain merge commit or a rebase): merged" "merged 12 $H" "$(token)"
at_confirm; bt_merged MERGED "$MOVED"
eq "the head moved after verify, and GitHub merged the new head: unconfirmed" "unconfirmed 12 $H" "$(token)"
grep -q "merged head $MOVED, not the verified $H" "$T/err" && ok "... naming both heads" || bad "... naming both heads" "$(cat "$T/err")"
at_confirm; bt_reach diverged
eq "a merge commit that isn't on the default branch: unconfirmed" "unconfirmed 12 $H" "$(token)"
at_confirm; bt_merged OPEN
eq "not merged yet: unconfirmed" "unconfirmed 12 $H" "$(token)"
grep -q compare "$GH_BOARD_DIR/calls" && bad "an unmerged pull request reads nothing past its record" || ok "an unmerged pull request reads nothing past its record"

echo "== three reads, whatever the size =="
# A 300-file pull request, as GitHub's record would carry it: the check reads
# the record, the repository and one comparison, and nothing per file.
at_confirm
jq -nc --arg h "$H" --arg m "$BT_MC" '{state: "MERGED", headRefOid: $h, mergeCommit: {oid: $m},
    files: [range(300) | {path: "src/f\(.).go", additions: 1, deletions: 0}]}' > "$GH_BOARD_DIR/prview-12.out"
eq "a 300-file pull request: merged" "merged 12 $H" "$(token)"
eq "... in three reads" 3 "$(calls)"
grep -q contents "$GH_BOARD_DIR/calls" && bad "... and no file is read" || ok "... and no file is read"

echo "== failures exit 2 =="
at_confirm; bt_reach fail
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a failed comparison read" 2 $?
at_confirm; bt_reach notfound
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a merge commit the comparison can't find" 2 $?
at_confirm; bt_merged MERGED "$H" ""
bash "$MC" --session "$S" --repo acme/widgets 2>"$T/err" >/dev/null; eq "a merged pull request with no merge commit" 2 $?
grep -q 'no merge commit' "$T/err" && ok "... naming it" || bad "... naming it" "$(cat "$T/err")"
at_confirm; bt_merged MERGED "not-a-sha"
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a merged head that isn't a sha" 2 $?
at_confirm; bt_reach "sideways"
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a comparison status that isn't one" 2 $?
at_confirm; echo 1 > "$GH_BOARD_DIR/prview-12.rc"
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a failed pull request read" 2 $?
at_confirm; bt_enter "$S" land
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a stale land capture" 2 $?
at_confirm; bt_enter "$S" land; bt_sealed "$S" land LAND "deny 12 $H"
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "a land capture that isn't permit" 2 $?
N=$((N + 1)); S="coordinate-demo-20260926T1300$(printf '%02d' "$N")Z"; bt_run "$S" "$PERMIT"; bt_enter "$S" merge_confirm
bash "$MC" --session "$S" --repo acme/widgets >/dev/null 2>&1; eq "no land capture" 2 $?
at_confirm
bash "$MC" --session "$S" --repo acme/widgets --pr 13 >/dev/null 2>&1; eq "--pr that disagrees with land's capture" 2 $?
eq "--no-seal prints the bare token" "merged 12 $H" "$(bash "$MC" --session "$S" --repo acme/widgets --no-seal 2>/dev/null)"
bash "$MC" --bogus >/dev/null 2>&1; eq "usage: exit 64" 64 $?

echo "== merge_confirm: the koto calls don't grow with the entries (shirabe#1315) =="
# Run as the template runs it, the check finds the repository in the record's
# Holdings section alone and never lists record/, which names every entry: the
# same confirmation on a record with a few entries and with 300 makes the same
# koto calls. The real state-holding.sh stands in the tree here, so the
# Holdings read reaches the session's keys.
# filler <session> <count>: plain entries numbered from 1, as the stand-in
# keeps keys.
filler() {
    local d="$KOTO_BOARD_DIR/sessions/$1/ctx" i
    mkdir -p "$d"
    for ((i = 1; i <= $2; i++)); do
        printf '{"n":%d,"stamp":"2026-09-26T08:00:00Z","kind":"entry","text":"note %d"}' "$i" "$i" > "$d/record__entries__$(printf '%06d' "$i")"
    done
}
# koto_calls <entries>: a run at merge_confirm whose record holds #12's row
# and <entries> entries; prints the token and the check's koto calls, the
# calls kept in $T/kc.calls.
koto_calls() {
    at_confirm
    bt_record_paused '[]'
    filler "$S" "$1"
    : > "$KOTO_BOARD_DIR/koto.calls"
    OUT=$(bash "$MC" --session "$S" 2>"$T/err")
    printf '%s %s' "${OUT% sealed:*}" "$(wc -l < "$KOTO_BOARD_DIR/koto.calls" | tr -d ' ')"
    cp "$KOTO_BOARD_DIR/koto.calls" "$T/kc.calls"
}
cp "$HERE/state-holding.sh" "$PS/state-holding.sh"
FEW=$(koto_calls 3)
MANY=$(koto_calls 300)
cp "$TD/board/stand-in-state-holding.sh" "$PS/state-holding.sh"
eq "the same token and koto calls with 3 entries and with 300 (${FEW##* } calls)" "$FEW" "$MANY"
eq "  ... merged from the verified head" "merged 12 $H" "${FEW% *}"
eq "  ... reading the Holdings section" 1 "$(grep -c '^context get [^ ]* record/holdings$' "$T/kc.calls")"
eq "  ... never listing record/" 0 "$(grep -cE '^context list (.* )?--prefix record/( |$)' "$T/kc.calls")"

echo
echo "merge-confirm: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
