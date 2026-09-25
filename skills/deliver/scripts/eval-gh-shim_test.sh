#!/usr/bin/env bash
# eval-gh-shim_test.sh -- /deliver's eval gh shim (evals/fixtures/bin/gh).
#
# The shim adapts /scope's and /deliver's gh calls to /execute's repository
# model. This checks each adaptation against a real git checkout with a local
# bare origin: a PR named by URL, a `pr` call with no --repo, a PR's head
# following what origin holds, the one-time `pr create` failure, the
# shim-mark-open hook, every call logged, and owned-pr.sh and
# deliver-probe.sh's reads answered through it.
#
# Usage: bash skills/deliver/scripts/eval-gh-shim_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs bash, git and jq.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SKILL=$(cd "$HERE/.." && pwd)
REPO=$(cd "$SKILL/../.." && pwd)
SHIM_DIR="$SKILL/evals/fixtures/bin"
OWNED="$REPO/skills/execute/scripts/owned-pr.sh"

for bin in git jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH"; exit 0; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-eval-gh-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

R="$T/repo"
git init -q --bare -b main "$T/origin.git"
git init -q -b main "$R"
G() { git -C "$R" -c user.email=t@example.invalid -c user.name=t "$@"; }
printf 'x\n' >"$R/f"
G add f
G commit -q -m init
G remote add origin "$T/origin.git"
G push -q origin main
G checkout -q -b docs/t
G push -q origin HEAD:refs/heads/docs/t

# case_env <scenario> -- a fresh call log (and so a fresh repository model).
case_env() {
    export EVAL_SCENARIO="$1"
    export GH_CALL_LOG="$T/calls-$1-$RANDOM.log"
    : >"$GH_CALL_LOG"
}
gh_() { (cd "$R" && PATH="$SHIM_DIR:$PATH" gh "$@"); }

echo "== URLs, --repo, and the log =="
case_env deliver-mergeable
eq "a PR named by URL is read" MERGED "$(gh_ pr view https://github.com/eval-org/eval-repo/pull/77 --json state --jq .state)"
printf 'body\nintent=continue\n' >"$T/body.md"
URL=$(gh_ pr create --head docs/t --base main --title "docs: t" --body-file "$T/body.md")
eq "pr create with no --repo opens a PR in the scenario's repository" "https://github.com/eval-org/eval-repo/pull/42" "$URL"
eq "pr list with no --repo finds it" 1 "$(gh_ pr list --head docs/t --state open --json url | jq 'length')"
eq "its body reads back by URL" "intent=continue" "$(gh_ pr view "$URL" --json body --jq .body | sed -n 2p)"
if grep -q '^pr create .*--repo eval-org/eval-repo' "$GH_CALL_LOG"; then ok "the call log records the call"; else bad "the call log records the call" "$(cat "$GH_CALL_LOG")"; fi

echo "== the head follows origin =="
printf 'y\n' >>"$R/f"
G commit -q -am more
G push -q origin HEAD:refs/heads/docs/t
eq "an open PR reports the commit origin holds" "$(G rev-parse HEAD)" "$(gh_ pr view 42 --json headRefOid --jq .headRefOid)"

echo "== owned-pr.sh through the shim =="
eq "owned-pr.sh finds the owned open PR" "$URL" "$(cd "$R" && PATH="$SHIM_DIR:$PATH" bash "$OWNED" --repo eval-org/eval-repo --head docs/t --state open)"

echo "== shim-mark-open =="
gh_ pr merge 42 --repo eval-org/eval-repo --squash --match-head-commit "$(G rev-parse HEAD)" >/dev/null
eq "a merge in the model reads MERGED" MERGED "$(gh_ pr view "$URL" --json state --jq .state)"
lines=$(wc -l <"$GH_CALL_LOG")
gh_ shim-mark-open eval-org/eval-repo 42
eq "shim-mark-open makes it read OPEN again" OPEN "$(gh_ pr view "$URL" --json state --jq .state)"
eq "the hook itself is not logged" "$((lines + 1))" "$(wc -l <"$GH_CALL_LOG" | tr -d ' ')"

echo "== the one-time pr create failure =="
case_env deliver-pr-create-fails
gh_ pr create --head docs/t --base main --title x --body-file "$T/body.md" >/dev/null 2>&1
eq "the first pr create fails" 1 "$?"
eq "the failed call is logged" 1 "$(grep -c '^pr create' "$GH_CALL_LOG")"
URL=$(gh_ pr create --head docs/t --base main --title x --body-file "$T/body.md" 2>/dev/null)
eq "the next one succeeds" "https://github.com/eval-org/eval-repo/pull/42" "$URL"

echo "== usage =="
(cd "$R" && PATH="$SHIM_DIR:$PATH" EVAL_SCENARIO= gh api user >/dev/null 2>&1)
eq "no EVAL_SCENARIO is an error" 1 "$?"
(cd "$R" && PATH="$SHIM_DIR:$PATH" EVAL_SCENARIO=deliver-mergeable GH_CALL_LOG= gh api user >/dev/null 2>&1)
eq "no GH_CALL_LOG is an error" 1 "$?"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
