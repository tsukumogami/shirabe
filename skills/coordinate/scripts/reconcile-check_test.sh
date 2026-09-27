#!/usr/bin/env bash
# reconcile-check_test.sh -- reconcile-check.sh makes each GitHub re-check
# with read-only calls and prints one fact, turning a failed or late read
# into a not_verified fact and refusing a bad row value before any call.
#
# gh and git are keyed stand-ins on PATH: each call is logged and served
# from <case>/<key>.out.<N> (the Nth call to that key), with an optional
# .rc.<N> exit status, .err.<N> stderr, and .sleep.<N> delay. The record
# feature's board and deferral checks are stand-ins too, reached through
# reconcile-deps.sh's test-only overrides. Needs bash and jq only.
#
# Usage: bash skills/coordinate/scripts/reconcile-check_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/reconcile-check.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-check-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
BIN="$T/bin"
mkdir -p "$BIN"

# The keyed stand-in. The key is the call's shape: gh pr view -> pr-view,
# gh pr list -> pr-list, gh issue view -> issue-view, gh api .../files ->
# api-files, gh api .../contents/<p>?ref=<r> -> contents-<r>, git ls-remote
# -> ls-remote, the two record-feature checks -> board, deferral.
cat > "$BIN/stub" <<'STUB'
#!/usr/bin/env bash
name=$(basename "$0")
printf '%s %s\n' "$name" "$*" >> "$STUB_LOG"
case "$name:$1:$2" in
    gh:pr:view) key=pr-view ;;
    gh:pr:list) key=pr-list ;;
    gh:issue:view) key=issue-view ;;
    gh:api:*/files*) key=api-files ;;
    gh:api:*/contents/*) ref=${2##*ref=}; key=contents-$ref ;;
    git:ls-remote:*) key=ls-remote ;;
    board-verdict.sh:*) key=board ;;
    deferral-check.sh:*) key=deferral ;;
    *) echo "stub: unexpected call: $name $*" >&2; exit 99 ;;
esac
n_file="$STUB_DIR/.n.$key"
n=$(( $(cat "$n_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$n_file"
[ -f "$STUB_DIR/$key.sleep.$n" ] && sleep "$(cat "$STUB_DIR/$key.sleep.$n")"
[ -f "$STUB_DIR/$key.err.$n" ] && cat "$STUB_DIR/$key.err.$n" >&2
[ -f "$STUB_DIR/$key.out.$n" ] && cat "$STUB_DIR/$key.out.$n"
exit "$(cat "$STUB_DIR/$key.rc.$n" 2>/dev/null || echo 0)"
STUB
chmod +x "$BIN/stub"
for n in gh git board-verdict.sh deferral-check.sh; do ln -s stub "$BIN/$n"; done

CASE=""
new_case() {
    CASE="$T/case-$1"
    mkdir -p "$CASE"
    : > "$CASE/log"
}
serve() { printf '%s' "$3" > "$CASE/$1.out.$2"; }       # serve <key> <n> <stdout>
fail_with() { echo "$3" > "$CASE/$1.rc.$2"; [ -n "${4-}" ] && printf '%s' "$4" > "$CASE/$1.err.$2"; }
run() {
    STUB_LOG="$CASE/log" STUB_DIR="$CASE" PATH="$BIN:$PATH" \
      RECONCILE_BOARD_CHECK="$BIN/board-verdict.sh" RECONCILE_DEFERRAL_CHECK="$BIN/deferral-check.sh" \
      RECONCILE_READ_DEADLINE="${DL:-5}" bash "$S" "$@"
}
expect() {  # expect <label> <jq predicate> <output>
    if printf '%s' "$3" | jq -e "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1" "$3"; fi
}

VH=1111111111111111111111111111111111111111
LH=2222222222222222222222222222222222222222
R=acme/widgets

echo "== pr =="
new_case pr-merged
serve pr-view 1 "{\"state\":\"MERGED\",\"isDraft\":false,\"headRefOid\":\"$VH\",\"mergeStateStatus\":\"UNKNOWN\",\"baseRefName\":\"main\"}"
expect "a merged pull request is a measured merged fact" '.kind == "pr" and .status == "ok" and .state == "MERGED" and .base == "main"' "$(run pr --repo $R --number 7)"
new_case pr-draft
serve pr-view 1 "{\"state\":\"OPEN\",\"isDraft\":true,\"headRefOid\":\"$VH\",\"mergeStateStatus\":\"DRAFT\",\"baseRefName\":\"main\"}"
expect "a draft pull request carries its draft flag and merge state" '.draft == true and .merge_state == "DRAFT"' "$(run pr --repo $R --number 7)"

echo "== board =="
new_case board-fails
serve board 1 '{"verdict":"unverified","head":null,"reasons":[{"code":"job-no-runner","run":1,"job":2,"name":"build","detail":"no runner"}]}'
out=$(run board --repo $R --sha $VH --base main)
expect "an unverified board fails, naming the job" '.verdict == "fails" and (.detail | startswith("build")) and .at == "'$VH'"' "$out"
grep -q "board-verdict.sh --repo $R --sha $VH --base main" "$CASE/log" && ok "the board check is called through the seam at the given sha" || bad "board called through the seam" "$(cat "$CASE/log")"
new_case board-holds
serve board 1 '{"verdict":"verified","head":null,"reasons":[]}'
expect "a verified board holds" '.verdict == "holds"' "$(run board --repo $R --sha $VH --base main)"
new_case board-pending
serve board 1 '{"verdict":"pending","reasons":[{"code":"run-pending","name":"ci"}]}'
expect "a pending board is pending" '.verdict == "pending"' "$(run board --repo $R --sha $VH --base main)"
new_case board-error
serve board 1 '{"verdict":"error:board-read","reasons":[]}'
expect "a board read error is not verified" '.status == "not_verified" and (.reason | test("board-read"))' "$(run board --repo $R --sha $VH --base main)"

echo "== branch =="
new_case branch-gone
serve ls-remote 1 ""
expect "an absent ref reads branch gone" '.state == "gone"' "$(run branch --repo $R --branch feat/x)"
grep -q "git ls-remote https://github.com/$R.git refs/heads/feat/x" "$CASE/log" && ok "ls-remote reads the row's repository URL" || bad "ls-remote reads the row's repository URL" "$(cat "$CASE/log")"
new_case branch-present
serve ls-remote 1 "$LH	refs/heads/feat/x"
expect "a present ref carries its tip" '.state == "present" and .tip == "'$LH'"' "$(run branch --repo $R --branch feat/x)"

echo "== appeared =="
new_case appeared-one
serve pr-list 1 '[{"number":9,"state":"OPEN","url":"https://github.com/acme/widgets/pull/9"}]'
expect "one pull request on the branch is listed" '(.prs | length) == 1 and .prs[0].number == 9' "$(run appeared --repo $R --branch feat/x)"
new_case appeared-two
serve pr-list 1 '[{"number":9,"state":"OPEN","url":"u9"},{"number":10,"state":"CLOSED","url":"u10"}]'
expect "two pull requests are both listed" '(.prs | length) == 2' "$(run appeared --repo $R --branch feat/x)"

echo "== files =="
new_case files
serve api-files 1 "$(printf 'docs/a.md\nsrc/new.go\nsrc/old.go\n')"
out=$(run files --repo $R --number 7 --cap 2)
expect "files are listed up to the cap, with a truncation note" '.paths == ["docs/a.md","src/new.go"] and .truncated == true' "$out"
grep -q 'per_page=100 --paginate' "$CASE/log" && ok "the file list is paginated" || bad "the file list is paginated" "$(cat "$CASE/log")"

echo "== merge =="
new_case merge-confirmed
serve pr-view 1 '{"state":"MERGED","baseRefName":"main"}'
serve api-files 1 "$(printf 'modified\tsrc/a.go\nremoved\tsrc/gone.go\n')"
serve "contents-$VH" 1 "blobA"
serve contents-main 1 "blobA"
fail_with contents-main 2 1 "gh: Not Found (HTTP 404)"
expect "files matching at the verified head, and a deletion absent on main, confirm the merge" '.verdict == "confirmed"' "$(run merge --repo $R --number 7 --verified-head $VH)"
new_case merge-moved
serve pr-view 1 '{"state":"MERGED","baseRefName":"main"}'
serve api-files 1 "$(printf 'modified\tsrc/a.go\n')"
serve "contents-$VH" 1 "blobA"
serve contents-main 1 "blobB"
out=$(run merge --repo $R --number 7 --verified-head $VH)
expect "a branch moved past the verified head reads not confirmed though merged" '.verdict == "not_confirmed" and (.reason | test("src/a.go"))' "$out"
grep -q "ref=$LH" "$CASE/log" && bad "never compares against the branch's current head" || ok "never compares against the branch's current head"
new_case merge-open
serve pr-view 1 '{"state":"OPEN","baseRefName":"main"}'
expect "an unmerged pull request is not confirmed" '.verdict == "not_confirmed" and .reason == "pull request is open"' "$(run merge --repo $R --number 7 --verified-head $VH)"
new_case merge-deleted-still-there
serve pr-view 1 '{"state":"MERGED","baseRefName":"main"}'
serve api-files 1 "$(printf 'removed\tsrc/gone.go\n')"
serve contents-main 1 "blobZ"
expect "a file deleted at the verified head but present on main is not confirmed" '.verdict == "not_confirmed"' "$(run merge --repo $R --number 7 --verified-head $VH)"
for bad_path in '../etc/passwd' '/abs/path' 'a//b'; do
    new_case "merge-path"
    serve pr-view 1 '{"state":"MERGED","baseRefName":"main"}'
    serve api-files 1 "$(printf 'modified\t%s\n' "$bad_path")"
    out=$(run merge --repo $R --number 7 --verified-head $VH)
    if printf '%s' "$out" | jq -e '.status == "not_verified"' >/dev/null && ! grep -q contents "$CASE/log"; then
        ok "the path '$bad_path' is refused before any contents read"
    else bad "the path '$bad_path' is refused" "$out $(cat "$CASE/log")"; fi
done
new_case merge-encode
serve pr-view 1 '{"state":"MERGED","baseRefName":"main"}'
serve api-files 1 "$(printf 'modified\tdocs/a b#c.md\n')"
serve "contents-$VH" 1 "x"
serve contents-main 1 "x"
run merge --repo $R --number 7 --verified-head $VH >/dev/null
grep -q 'contents/docs/a%20b%23c.md?ref=' "$CASE/log" && ok "a path is percent-encoded per segment" || bad "a path is percent-encoded per segment" "$(cat "$CASE/log")"

echo "== close =="
new_case close-closed
serve issue-view 1 '{"state":"CLOSED"}'
expect "a closed target confirms the close" '.verdict == "confirmed"' "$(run close --repo $R --kind issue --number 3)"
new_case close-open
serve pr-view 1 '{"state":"OPEN"}'
expect "an open target does not" '.verdict == "not_confirmed"' "$(run close --repo $R --kind pr --number 3)"

echo "== deferral =="
ROW="$T/row.json"
echo '{"deferral":"d","reason":"r","raised":"2026-09-20","disposition":"filed #5"}' > "$ROW"
new_case deferral-filed
serve deferral 1 "disposed filed 5"
serve issue-view 1 '{"number":5}'
expect "a filed deferral whose issue exists is disposed" '.disposed == true and .how == "filed #5"' "$(run deferral --repo $R --row-file "$ROW" --run-start 2026-09-27T00:00:00Z)"
new_case deferral-filed-missing
serve deferral 1 "disposed filed 5"
fail_with issue-view 1 1 "GraphQL: Could not resolve to an issue"
expect "a filed deferral whose issue can't be read is not verified" '.status == "not_verified"' "$(run deferral --repo $R --row-file "$ROW" --run-start 2026-09-27T00:00:00Z)"
new_case deferral-closed
serve deferral 1 "disposed closed"
expect "a closed deferral is disposed" '.disposed == true and .how == "closed"' "$(run deferral --repo $R --row-file "$ROW" --run-start 2026-09-27T00:00:00Z)"
new_case deferral-carried
serve deferral 1 "disposed carried 2026-09-27T01:00:00Z"
expect "a carried deferral is disposed" '.disposed == true and (.how | startswith("carried"))' "$(run deferral --repo $R --row-file "$ROW" --run-start 2026-09-27T00:00:00Z)"
new_case deferral-open
serve deferral 1 "undisposed empty"
fail_with deferral 1 1
expect "an undisposed deferral is undisposed" '.disposed == false and .how == "empty"' "$(run deferral --repo $R --row-file "$ROW" --run-start 2026-09-27T00:00:00Z)"

echo "== bad row values reach no command =="
for args in "pr --repo a;b --number 1" "pr --repo acme/widgets --number 0" "branch --repo acme/widgets --branch -x" "branch --repo acme/widgets --branch a;b" "board --repo acme/widgets --sha nothex --base main"; do
    new_case bad
    # shellcheck disable=SC2086
    out=$(run $args)
    if printf '%s' "$out" | jq -e '.status == "not_verified"' >/dev/null && [ ! -s "$CASE/log" ]; then
        ok "refused before any call: $args"
    else bad "refused before any call: $args" "$out $(cat "$CASE/log")"; fi
done

echo "== deadlines and failures =="
new_case slow
echo 5 > "$CASE/pr-view.sleep.1"
serve pr-view 1 '{"state":"OPEN"}'
out=$(DL=1 run pr --repo $R --number 7)
expect "a read past its deadline is not verified, with the reason" '.status == "not_verified" and (.reason | test("timed out"))' "$out"
for sub in "appeared --repo $R --branch x:pr-list" "branch --repo $R --branch x:ls-remote" "files --repo $R --number 7:api-files" "close --repo $R --kind issue --number 3:issue-view"; do
    args=${sub%:*}; key=${sub##*:}
    new_case fail
    fail_with "$key" 1 1 "boom"
    # shellcheck disable=SC2086
    out=$(run $args)
    expect "a failed $key read is not verified" '.status == "not_verified" and (.reason | test("failed"))' "$out"
done

echo "== read-only =="
ALL="$T/all.log"
cat "$T"/case-*/log > "$ALL"
bad_calls=$(grep -vE '^(gh (pr view|pr list|issue view|api repos/[^ ]+/(pulls/[0-9]+/files\?per_page=100 --paginate|contents/[^ ]+) --jq [^ ]+( .*)?)|git ls-remote https://github\.com/[^ ]+\.git refs/heads/[^ ]+|board-verdict\.sh --repo .*|deferral-check\.sh --row-file .*)' "$ALL" | grep -vE '^gh (pr view|pr list|issue view) ' || true)
grep -qE ' (-f|-F|--input|--method (POST|PUT|PATCH|DELETE)|-X (POST|PUT|PATCH|DELETE))( |$)' "$ALL" && bad "no gh api write flags" "$(grep -E ' (-f|-F|--input|--method|-X) ' "$ALL")" || ok "no gh api write flags anywhere"
[ -z "$bad_calls" ] && ok "every call is on the read allowlist" || bad "every call is on the read allowlist" "$bad_calls"
grep -qE '^git (fetch|pull|push|checkout|commit)' "$ALL" && bad "git never writes" || ok "git never writes"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
