#!/usr/bin/env bash
# closing-keyword-gate_test.sh — does pr_creation's gate recognise a closing
# keyword, and refuse a body that lacks one? For an issue in another
# repository (ISSUE_REPO set), does it take only `Fixes owner/repo#N` for that
# repository and refuse a bare `#N`?
#
# The gate is a shell expression inside the template, so the cases run the
# expression EXTRACTED FROM THE TEMPLATE rather than a copy pasted here. A copy
# would keep passing after someone edited the real one.
#
# `gh` is replaced with a stub that prints a body from the environment. That is
# the whole point: the gate must be exercised against bodies, and reaching the
# real GitHub would test the network instead. What the stub cannot cover is the
# shape of `gh pr view --json body --jq .body` itself — if that invocation is
# wrong, these cases still pass. The merge-state gate has the same exposure and
# the same answer: the invocation is copied from a shipped, working gate.
#
# Usage: closing-keyword-gate_test.sh
# Exit codes: 0 all pass, 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMPS=()
# The trailing `return 0` is load-bearing: the loop's last command is a test
# that is FALSE when TMPS is empty, and under `set -e` an EXIT trap's final
# status replaces the script's own, turning a clean exit into a failure that
# prints nothing at all. The trigger is `set -e` and not any shell version --
# measured, bash 5.2 and 3.2 behave identically.
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; return 0; }
trap cleanup EXIT

# The gate command, read out of the template: the `command:` line belonging to
# the closing_keyword gate, unquoted from its YAML single-quoted scalar.
GATE=$(awk '
    /^      closing_keyword:$/ { found=1 }
    found && /^        command:/ {
        sub(/^        command:[[:space:]]*/, "")
        sub(/^'"'"'/, ""); sub(/'"'"'$/, "")
        print
        exit
    }
' "$TEMPLATE")

if [[ -z "$GATE" ]]; then
    echo "could not read the closing_keyword gate command from $TEMPLATE" >&2
    exit 2
fi

# A gh stub that prints $PR_BODY, so the gate can be run against any body.
# Asked for the url too (check-closing-keyword.sh's `--json url,body --jq
# '.url, .body'`), it prints $PR_URL on the first line, as gh does.
STUB_DIR=$(mktemp -d) || exit 1; TMPS+=("$STUB_DIR")
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Stands in for `gh pr view --json body --jq .body` and
# `gh pr view --json url,body --jq '.url, .body'`.
[[ -z "${GH_LOG:-}" ]] || echo "$*" >> "$GH_LOG"
if [[ "${GH_FAIL:-0}" == "1" ]]; then
    echo "gh: could not resolve to a PullRequest" >&2
    exit 1
fi
[[ " $* " == *" url,body "* ]] && printf '%s\n' "${PR_URL:-https://github.com/acme/app/pull/7}"
printf '%s\n' "${PR_BODY:-}"
STUB
chmod +x "$STUB_DIR/gh"

# The plugin root the gate reaches check-closing-keyword.sh through.
PLUGIN_DIR=$(cd "$SKILL_DIR/../.." && pwd)

# run_gate <issue-number> <body> [<gh-fails>] — substitute {{ISSUE_NUMBER}},
# {{ISSUE_REPO}} (from $ISSUE_REPO, empty by default, as an unset variable
# resolves) and {{PLUGIN_ROOT}} as koto would, then run the expression with
# the stub ahead of the real gh.
run_gate() {
    local issue="$1" body="$2"
    local cmd="${GATE//\{\{ISSUE_NUMBER\}\}/$issue}"
    cmd="${cmd//\{\{ISSUE_REPO\}\}/${ISSUE_REPO:-}}"
    cmd="${cmd//\{\{PLUGIN_ROOT\}\}/$PLUGIN_DIR}"
    PATH="$STUB_DIR:$PATH" PR_BODY="$body" PR_URL="${PR_URL:-}" GH_FAIL="${3:-0}" \
        sh -c "$cmd" >/dev/null 2>&1
}

expect() {
    local label="$1" want="$2" issue="$3" body="$4" ghfail="${5:-0}"
    run_gate "$issue" "$body" "$ghfail"; local got=$?
    if [[ "$got" == "$want" ]]; then pass "$label (exit $got)"
    else fail "$label: expected exit $want, got $got"; fi
}

# --- bodies that must pass ---------------------------------------------------
expect "Fixes #42 is recognised" 0 42 "Part 1

---

Fixes #42"
expect "lowercase fixes is recognised" 0 42 "fixes #42"
expect "Closes is recognised" 0 42 "Closes #42"
expect "Resolved is recognised" 0 42 "Resolved #42"
expect "the keyword mid-body is recognised" 0 42 "Some context.
Fixes #42
More context."
# GitHub's documentation: "The keywords can be followed by colons or in
# uppercase. For example: Closes: #10, CLOSES #10, or CLOSES: #10."
expect "a colon after the keyword is recognised" 0 42 "Fixes: #42"
expect "an uppercase keyword with a colon is recognised" 0 42 "CLOSES: #42"
# The documented forms only: a colon with nothing after it isn't one.
expect "a colon with no space before #N is not recognised" 1 42 "Fixes:#42"

# --- bodies that must fail ---------------------------------------------------
expect "a body with no closing keyword fails" 1 42 "Part 1

---

Refs #42"
expect "a bare issue reference is not a closing keyword" 1 42 "See #42 for context"
expect "an empty body fails" 1 42 ""

# --- THE ANCHORING CASE ------------------------------------------------------
# A body closing #123 must not satisfy the gate for issue #12. This is the same
# substring defect the anchor finder exists to avoid, in a second place.
expect "Fixes #123 does NOT satisfy issue 12" 1 12 "Fixes #123"
expect "Fixes #12 DOES satisfy issue 12 at end of body" 0 12 "Fixes #12"
expect "Fixes #1234 does NOT satisfy issue 123" 1 123 "Fixes #1234"
expect "Fixes: #123 does NOT satisfy issue 12" 1 12 "Fixes: #123"

# --- free-form mode ----------------------------------------------------------
# No issue number means no issue to close, so the gate passes rather than
# blocking work that has nothing to reference.
expect "an empty issue number passes without consulting the body" 0 "" "no keyword here"

# --- fail-closed -------------------------------------------------------------
# An unreadable pull request must NOT read as satisfied.
expect "an unreadable pull request fails rather than passing" 1 42 "Fixes #42" 1

# --- same repository: ISSUE_REPO empty runs the expression unchanged ----------
# The run above had ISSUE_REPO empty throughout. This pins that it never asked
# gh for the url, which only check-closing-keyword.sh does, so a
# same-repository run never starts the script.
GH_LOG=$(mktemp) || exit 1; TMPS+=("$GH_LOG")
export GH_LOG
run_gate 42 "Fixes #42"
if ! grep -q 'url' "$GH_LOG" && grep -qx 'pr view --json body --jq .body' "$GH_LOG"; then
    pass "an empty ISSUE_REPO reads only the body, as before"
else
    fail "an empty ISSUE_REPO made gh calls: $(cat "$GH_LOG")"
fi
unset GH_LOG

# --- an issue in another repository -------------------------------------------
# The pull request is in acme/app (the stub's default url); the issue lives in
# acme/tracker. GitHub closes it only through `acme/tracker#42`, and a bare
# `#42` here would close acme/app#42 instead.
export ISSUE_REPO=acme/tracker
expect "cross-repo: Fixes owner/repo#N passes" 0 42 "Fixes acme/tracker#42"
expect "cross-repo: lowercase closes passes" 0 42 "closes acme/tracker#42"
expect "cross-repo: Resolved passes" 0 42 "Resolved acme/tracker#42"
expect "cross-repo: owner/repo matches in any case" 0 42 "Fixes ACME/Tracker#42"
expect "cross-repo: mid-body after Part 1 passes" 0 42 "Part 1

---

Fixes acme/tracker#42"
expect "cross-repo: a bare Fixes #N fails" 1 42 "Fixes #42"
expect "cross-repo: a bare #N beside the right reference still fails" 1 42 "Fixes acme/tracker#42
Fixes #42"
expect "cross-repo: no closing keyword fails" 1 42 "Refs acme/tracker#42"
expect "cross-repo: an empty body fails" 1 42 ""
expect "cross-repo: an unreadable pull request fails" 1 42 "Fixes acme/tracker#42" 1

# A closing keyword the old gate refused must not pass the new one for the
# wrong issue: another repository, a name that only contains the right one,
# or a longer number.
expect "cross-repo: another owner's repo of the same name fails" 1 42 "Fixes other/tracker#42"
expect "cross-repo: another repo of the same owner fails" 1 42 "Fixes acme/app#42"
expect "cross-repo: a longer repo name fails" 1 42 "Fixes acme/tracker2#42"
expect "cross-repo: a prefixed owner fails" 1 42 "Fixes xacme/tracker#42"
expect "cross-repo: a path that ends in the repo fails" 1 42 "Fixes evil/acme/tracker#42"
expect "cross-repo: #N running into more digits fails" 1 42 "Fixes acme/tracker#421"
expect "cross-repo: another issue number fails" 1 42 "Fixes acme/tracker#43"
expect "cross-repo: a keyword inside a word fails" 1 42 "prefixes acme/tracker#42"
expect "cross-repo: the keyword split from the reference by a newline fails" 1 42 "Fixes
acme/tracker#42"
expect "cross-repo: a colon after the keyword passes" 0 42 "Fixes: acme/tracker#42"
expect "cross-repo: a bare Fixes: #N fails" 1 42 "Fixes: #42"

# Any closing reference to issue N of the pull request's own repository closes
# that issue on merge, so it fails next to the right reference, in each form.
expect "cross-repo: this repo's owner/repo#N beside the right reference fails" 1 42 "Fixes acme/tracker#42
Fixes acme/app#42"
expect "cross-repo: this repo's issue URL beside the right reference fails" 1 42 "Fixes acme/tracker#42
Closes https://github.com/acme/app/issues/42"
expect "cross-repo: this repo's issue URL alone fails" 1 42 "Closes https://github.com/acme/app/issues/42"
expect "cross-repo: this repo's reference in another case fails" 1 42 "Fixes acme/tracker#42
fixes ACME/App#42"
expect "cross-repo: this repo's http issue URL fails" 1 42 "Fixes acme/tracker#42
Resolves http://github.com/acme/app/issues/42"
expect "cross-repo: this repo's reference after a colon fails" 1 42 "Fixes acme/tracker#42
Fixes: acme/app#42"
expect "cross-repo: a bare #N after a colon and no space fails" 1 42 "Fixes acme/tracker#42
Fixes:#42"
expect "cross-repo: this repo's URL after a colon and no space fails" 1 42 "Fixes acme/tracker#42
Fixes:https://github.com/acme/app/issues/42"
expect "cross-repo: this repo's reference on the same line fails" 1 42 "Fixes acme/tracker#42, fixes acme/app#42"
PR_URL=https://ghe.example.com/acme/app/pull/7 \
    expect "cross-repo: this repo's issue URL on another host fails" 1 42 "Fixes acme/tracker#42
Fixes https://ghe.example.com/acme/app/issues/42"
# Spellings GitHub doesn't document either way fail too, on the safe side:
# a www. host, leading zeros, and a keyword whose reference is on the next line.
expect "cross-repo: this repo's www. issue URL fails" 1 42 "Fixes acme/tracker#42
Fixes https://www.github.com/acme/app/issues/42"
expect "cross-repo: this repo's #N with leading zeros fails" 1 42 "Fixes acme/tracker#42
Fixes #042"
expect "cross-repo: this repo's reference on the line after the keyword fails" 1 42 "Fixes acme/tracker#42
Fixes
acme/app#42"
expect "cross-repo: a bare #N on the line after a colon fails" 1 42 "Fixes acme/tracker#42
Fixes:
#42"

# What closes nothing in this repository, or another issue there, still passes.
expect "cross-repo: a mention of this repo's issue without a keyword passes" 0 42 "Fixes acme/tracker#42
See acme/app#42 and https://github.com/acme/app/issues/42"
expect "cross-repo: this repo's issue N with more digits passes" 0 42 "Fixes acme/tracker#42
Fixes acme/app#421 and https://github.com/acme/app/issues/420"
expect "cross-repo: the issue's own URL beside the right reference passes" 0 42 "Fixes acme/tracker#42
Fixes https://github.com/acme/tracker/issues/42"
expect "cross-repo: an issue URL that only ends in this repo passes" 0 42 "Fixes acme/tracker#42
Fixes https://github.com/xacme/app/issues/42"

# A `.` in the recorded name is a literal dot, not any character.
export ISSUE_REPO=acme/.github
expect "a dotted repo name passes for itself" 0 7 "Fixes acme/.github#7"
expect "a dotted repo name does not match any character there" 1 7 "Fixes acme/xgithub#7"

# ISSUE_REPO naming the pull request's own repository is a same-repository run:
# a bare #N and the qualified form both close the issue.
export ISSUE_REPO=acme/app
expect "ISSUE_REPO equal to the PR's repo: a bare Fixes #N passes" 0 42 "Fixes #42"
expect "ISSUE_REPO equal to the PR's repo: the qualified form passes" 0 42 "Fixes acme/app#42"
expect "ISSUE_REPO equal to the PR's repo: no keyword fails" 1 42 "See #42"
expect "ISSUE_REPO equal to the PR's repo: a colon after the keyword passes" 0 42 "Fixes: #42"
PR_URL=https://github.com/ACME/App/pull/7 \
    expect "ISSUE_REPO equal to the PR's repo in another case: a bare Fixes #N passes" 0 42 "Fixes #42"

# A url the script can't read a repository from fails closed.
export ISSUE_REPO=acme/tracker
PR_URL=not-a-url expect "an unreadable PR url fails closed" 1 42 "Fixes acme/tracker#42"

# Free-form mode still passes without reading anything, whatever ISSUE_REPO.
expect "an empty issue number passes with ISSUE_REPO set" 0 "" "no keyword here"
unset ISSUE_REPO

# --- the script's own usage refusals ------------------------------------------
# Exit 2, which no pr_creation edge routes, so the state holds rather than
# reaching done_blocked or ci_monitor.
SCRIPT="$SCRIPT_DIR/check-closing-keyword.sh"
for args in "" "--issue 42" "--repo acme/tracker" "--issue 042 --repo acme/tracker" \
            "--issue 4x2 --repo acme/tracker" "--issue 42 --repo acme" \
            "--issue 42 --repo acme/tracker/extra" "--issue 42 --repo acme/tr;cker" \
            "--issue 42 --repo acme/tracker --bogus"; do
    # shellcheck disable=SC2086
    PATH="$STUB_DIR:$PATH" PR_BODY="Fixes acme/tracker#42" "$SCRIPT" $args >/dev/null 2>&1; got=$?
    if [[ "$got" == 2 ]]; then pass "usage [$args] exits 2"
    else fail "usage [$args]: expected exit 2, got $got"; fi
done
PATH="$STUB_DIR:$PATH" PR_BODY="Fixes acme/tracker#42" "$SCRIPT" --issue 42 --repo "acme/tracker
evil/x" >/dev/null 2>&1; got=$?
[[ "$got" == 2 ]] && pass "a repo value with a newline exits 2" || fail "a repo value with a newline: exit $got"

echo
echo "closing-keyword-gate_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
