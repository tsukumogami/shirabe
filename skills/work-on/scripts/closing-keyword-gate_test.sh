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
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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
# '.url, .body'`), it prints $PR_URL on the first line, as gh does. Asked for
# a repository (`gh api --hostname <host> repos/<owner>/<name> --jq
# .full_name`), it prints the name it was asked for, the new name when
# $GH_RENAMED lists the name as `old=new` (GitHub's rename redirect, which gh
# follows), and gh's 404 when $GH_MISSING lists it. $GH_API_FAIL makes every
# lookup fail the way gh does: `rate` (403, rate limit), `limit` (429),
# `net` (no connection) or `5xx` (502). $GH_API_SLEEP makes it wait that many
# seconds before it answers, and $GH_PR_SLEEP the pull request read.
# $GH_API_WARN makes a lookup that works also write to stderr.
STUB_DIR=$(mktemp -d) || exit 1; TMPS+=("$STUB_DIR")
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Stands in for `gh pr view --json body --jq .body`,
# `gh pr view --json url,body --jq '.url, .body'` and
# `gh api --hostname <host> repos/<owner>/<name> --jq .full_name`.
[[ -z "${GH_LOG:-}" ]] || echo "$*" >> "$GH_LOG"
if [[ "${1:-}" == "api" ]]; then
    name=""
    for a in "$@"; do [[ "$a" == repos/* ]] && name=${a#repos/}; done
    lname=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    [[ -z "${GH_API_SLEEP:-}" ]] || sleep "$GH_API_SLEEP"
    # gh writes debug output to stderr when GH_DEBUG is set, even on success.
    [[ -z "${GH_API_WARN:-}" ]] || echo "[git remote -v] debug: request took 0.2s" >&2
    case "${GH_API_FAIL:-}" in
        rate) echo '{"message":"API rate limit exceeded for user ID 1.","status":"403"}gh: API rate limit exceeded for user ID 1. (HTTP 403)' >&2; exit 1 ;;
        limit) echo 'gh: You have exceeded a secondary rate limit. (HTTP 429)' >&2; exit 1 ;;
        net) echo 'error connecting to api.github.com' >&2; exit 1 ;;
        5xx) echo 'gh: Bad Gateway (HTTP 502)' >&2; exit 1 ;;
    esac
    for m in ${GH_MISSING:-}; do
        if [[ "$m" == "$lname" ]]; then
            echo '{"message":"Not Found","status":"404"}gh: Not Found (HTTP 404)' >&2
            exit 1
        fi
    done
    for r in ${GH_RENAMED:-}; do
        if [[ "${r%%=*}" == "$lname" ]]; then printf '%s\n' "${r#*=}"; exit 0; fi
    done
    printf '%s\n' "$name"
    exit 0
fi
[[ -z "${GH_PR_SLEEP:-}" ]] || sleep "$GH_PR_SLEEP"
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
        GH_RENAMED="${GH_RENAMED:-}" GH_MISSING="${GH_MISSING:-}" GH_API_FAIL="${GH_API_FAIL:-}" \
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
# GitHub closes on these too (#1044), but the same-repository expression is
# left as it was: it still asks for `Fixes #N`.
expect "a same-repository GH-N is still not recognised" 1 42 "Fixes GH-42"
expect "a same-repository markdown link is still not recognised" 1 42 "Fixes [#42](https://github.com/acme/app/issues/42)"

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

# GitHub closes this repository's issue on `Fixes GH-N` and on the markdown
# link `[#N](<this repo's issue URL>)` (#1044), so both fail, alone and beside
# the right reference.
expect "cross-repo: GH-N alone fails" 1 42 "Fixes GH-42"
expect "cross-repo: GH-N beside the right reference fails" 1 42 "Fixes acme/tracker#42
Fixes GH-42"
expect "cross-repo: GH-N in lower case fails" 1 42 "Fixes acme/tracker#42
fixes gh-42"
expect "cross-repo: GH-N after a colon fails" 1 42 "Fixes acme/tracker#42
Fixes: GH-42"
expect "cross-repo: GH-N on the same line fails" 1 42 "Fixes acme/tracker#42, fixes GH-42"
expect "cross-repo: GH-N with more digits passes" 0 42 "Fixes acme/tracker#42
Fixes GH-421"
expect "cross-repo: a markdown link to this repo's issue alone fails" 1 42 "Fixes [#42](https://github.com/acme/app/issues/42)"
expect "cross-repo: a markdown link to this repo's issue beside the right reference fails" 1 42 "Fixes acme/tracker#42
Fixes [#42](https://github.com/acme/app/issues/42)"
expect "cross-repo: the link with GH-N as its text fails" 1 42 "Fixes acme/tracker#42
Fixes [GH-42](https://github.com/acme/app/issues/42)"
expect "cross-repo: the link with this repo's owner/repo#N as its text fails" 1 42 "Fixes acme/tracker#42
Fixes [acme/app#42](https://github.com/acme/app/issues/42)"
# A markdown link whose text and target both name the issue elsewhere passes:
# either reading of the link closes that issue.
expect "cross-repo: a link with the right text and target passes" 0 42 "Fixes [acme/tracker#42](https://github.com/acme/tracker/issues/42)"
expect "cross-repo: the right link beside the right reference passes" 0 42 "Fixes [acme/tracker#42](https://github.com/acme/tracker/issues/42)
Fixes acme/tracker#42"
# The right text pointing anywhere else isn't that link, and doesn't count
# on its own.
expect "cross-repo: the right text pointing at another repository's issue fails" 1 42 "Fixes [acme/tracker#42](https://github.com/acme/other/issues/42)"
expect "cross-repo: the right text pointing at another issue fails" 1 42 "Fixes [acme/tracker#42](https://github.com/acme/tracker/issues/43)"
expect "cross-repo: the right text pointing at a page that isn't an issue fails" 1 42 "Fixes [acme/tracker#42](https://example.com/notes)"
expect "cross-repo: the right text pointing elsewhere passes beside the plain reference" 0 42 "Fixes acme/tracker#42
See [acme/tracker#42](https://example.com/notes)"
# The plain reference is read wherever it stands, inside a link's text too,
# as before this change: telling link text apart is out of this gate's scope.
expect "cross-repo: the right reference inside a link's text passes, as before" 0 42 "[Fixes acme/tracker#42](https://example.com/notes)"
expect "cross-repo: the right reference in parentheses passes" 0 42 "(Fixes acme/tracker#42)"
expect "cross-repo: this repo's issue URL in prose without a keyword passes" 0 42 "Fixes acme/tracker#42
History: https://github.com/acme/app/issues/42 has the first report."

# Spellings not measured to close aren't refused: a refusal blocks a pull
# request. #1065 measures each one; flip its case here when it closes.
expect "cross-repo: owner shorthand isn't refused until measured (#1065)" 0 42 "Fixes acme/tracker#42
Fixes acme#42"
expect "cross-repo: an issue path without a host isn't refused until measured (#1065)" 0 42 "Fixes acme/tracker#42
Fixes acme/app/issues/42"
expect "cross-repo: a link with text #N pointing elsewhere isn't refused until measured (#1065)" 0 42 "Fixes acme/tracker#42
Fixes [#42](https://github.com/acme/tracker/issues/42)"
expect "cross-repo: a link to this repo's issue with other text isn't refused until measured (#1065)" 0 42 "Fixes acme/tracker#42
Fixes [the bug](https://github.com/acme/app/issues/42)"
expect "cross-repo: a link to this repo's issue without a keyword isn't refused until measured (#1065)" 0 42 "Fixes acme/tracker#42
See [#42](https://github.com/acme/app/issues/42)"
expect "cross-repo: a reference-style link isn't refused until measured (#1065)" 0 42 "Fixes acme/tracker#42
Fixes [the bug][1]

[1]: https://github.com/acme/app/issues/42"
expect "cross-repo: emphasis around the keyword isn't refused until measured (#1065)" 0 42 "Fixes acme/tracker#42
**Fixes:** #42"
expect "cross-repo: #N in parentheses isn't refused until measured (#1065)" 0 42 "Fixes acme/tracker#42
Fixes (#42)"

# Without the right reference the gate says no before any lookup, so a
# failing lookup can't turn a plain no into a hold.
GH_API_FAIL=rate expect "cross-repo: a body without the right reference fails before any lookup" 1 42 "Fixes acme/other#42"
# A body of plain mentions costs nothing to read: no keyword, no lookup.
MENTIONS="Fixes acme/tracker#42
"
for i in $(seq 1 1000); do MENTIONS="${MENTIONS}a/b$i#42 "; done
# Nor does a body of closing references to repositories GitHub can't have.
DOTS="Fixes acme/tracker#42
"
for i in $(seq 1 1000); do DOTS="${DOTS}Fixes o$i/.#42 "; done
START=$SECONDS
expect "cross-repo: 1000 closing references to . repositories pass" 0 42 "$DOTS"
if (( SECONDS - START <= 5 )); then
    pass "cross-repo: 1000 closing references to . repositories were read in $((SECONDS - START))s"
else
    fail "cross-repo: 1000 closing references to . repositories took $((SECONDS - START))s"
fi
START=$SECONDS
expect "cross-repo: a body with 1000 plain mentions passes" 0 42 "$MENTIONS"
if (( SECONDS - START <= 5 )); then
    pass "cross-repo: 1000 plain mentions were read in $((SECONDS - START))s"
else
    fail "cross-repo: 1000 plain mentions took $((SECONDS - START))s"
fi

# A name the repository had before a rename still closes its issue N (#1044).
# The stub answers the lookup as GitHub's redirect does.
export GH_RENAMED="acme/old-app=acme/app"
expect "cross-repo: this repo's old name alone fails" 1 42 "Fixes acme/old-app#42"
expect "cross-repo: this repo's old name beside the right reference fails" 1 42 "Fixes acme/tracker#42
Fixes acme/old-app#42"
expect "cross-repo: this repo's old name in another case fails" 1 42 "Fixes acme/tracker#42
Fixes ACME/Old-App#42"
expect "cross-repo: this repo's old-name issue URL fails" 1 42 "Fixes acme/tracker#42
Closes https://github.com/acme/old-app/issues/42"
expect "cross-repo: this repo's old name as a link's text fails" 1 42 "Fixes acme/tracker#42
Fixes [acme/old-app#42](https://github.com/acme/tracker/issues/42)"
expect "cross-repo: this repo's old name on the line after the keyword fails" 1 42 "Fixes acme/tracker#42
Fixes
acme/old-app#42"
expect "cross-repo: the measured link with this repo's old name fails" 1 42 "Fixes acme/tracker#42
Fixes [#42](https://github.com/acme/old-app/issues/42)"
GH_API_WARN=1 expect "cross-repo: a lookup that also writes to stderr still finds the old name" 1 42 "Fixes acme/tracker#42
Fixes acme/old-app#42"
# An old name right after another reference: the match that ends at N
# mustn't eat the next one's first character.
expect "cross-repo: an old-name reference run into another fails" 1 42 "Fixes acme/tracker#42
Fixes x/y#42Fixes acme/old-app#42"
# The name is the URL's two path segments, whatever the case of /issues/.
expect "cross-repo: an old-name URL with /ISSUES/ fails" 1 42 "Fixes acme/tracker#42
Closes https://github.com/acme/old-app/ISSUES/42"
export GH_RENAMED="acme/old-app=acme/app acme/issues=acme/app"
expect "cross-repo: an old name that is itself 'issues' fails" 1 42 "Fixes acme/tracker#42
Closes https://github.com/acme/issues/issues/42"
export GH_RENAMED="acme/old-app=acme/app jdoe_acme/app=acme/app"
expect "cross-repo: an old name under an owner with an underscore fails" 1 42 "Fixes acme/tracker#42
Fixes jdoe_acme/app#42"
export GH_RENAMED="acme/old-app=acme/app"
expect "cross-repo: this repo's old name without a keyword passes" 0 42 "Fixes acme/tracker#42
See acme/old-app#42"
expect "cross-repo: this repo's old name with another issue passes" 0 42 "Fixes acme/tracker#42
Fixes acme/old-app#43"
export GH_MISSING="acme/gone"
expect "cross-repo: a repository that doesn't exist doesn't count" 0 42 "Fixes acme/tracker#42
Fixes acme/gone#42"
expect "cross-repo: a third repository's issue passes" 0 42 "Fixes acme/tracker#42
Fixes acme/other#42"
# A private repository the token can't read answers 404 as well, and doesn't
# count either: the token reads this repository, so it isn't an old name.
export GH_MISSING="acme/gone acme/private-thing"
expect "cross-repo: a private repository the token can't read doesn't count" 0 42 "Fixes acme/tracker#42
Fixes acme/private-thing#42"

# Any other failure decides nothing: exit 3, which no pr_creation edge
# routes, so the state holds. Not a pass, and not done_blocked for a blip.
for kind in rate limit net 5xx; do
    GH_API_FAIL=$kind expect "cross-repo: a lookup failing with $kind holds the gate" 3 42 "Fixes acme/tracker#42
Fixes acme/other#42"
done
GH_API_FAIL=rate expect "cross-repo: a failed lookup of an old name holds rather than passing" 3 42 "Fixes acme/tracker#42
Fixes acme/old-app#42"
GH_API_FAIL=rate expect "cross-repo: no lookup is needed for the right reference alone" 0 42 "Fixes acme/tracker#42
See acme/other#42"
GH_API_FAIL=rate expect "cross-repo: this repo's own reference still fails before any lookup" 1 42 "Fixes acme/tracker#42
Fixes acme/other#42
Fixes #42"

# A slow answer is cut off at the lookups' time, and the gate holds well
# inside koto's 30-second gate default instead of being killed by it. The
# answer would take 20s; anything under 8 means it was cut off, with room
# for a loaded runner.
START=$SECONDS
GH_API_SLEEP=20 CHECK_CLOSING_KEYWORD_LOOKUP_SECS=1 \
    expect "cross-repo: a lookup slower than its time holds the gate" 3 42 "Fixes acme/tracker#42
Fixes acme/other#42"
if (( SECONDS - START < 8 )); then
    pass "cross-repo: the slow lookup was cut off after about its time ($((SECONDS - START))s)"
else
    fail "cross-repo: the slow lookup ran $((SECONDS - START))s against a 1s limit"
fi
GH_API_SLEEP=1 CHECK_CLOSING_KEYWORD_LOOKUP_SECS=15 \
    expect "cross-repo: a slow lookup inside its time still answers" 1 42 "Fixes acme/tracker#42
Fixes acme/old-app#42"
# The time counts from the script's start, so a slow pull request read
# leaves the lookups less of it.
GH_PR_SLEEP=2 CHECK_CLOSING_KEYWORD_LOOKUP_SECS=1 \
    expect "cross-repo: a slow pull request read spends the lookups' time" 3 42 "Fixes acme/tracker#42
Fixes acme/other#42"
# A failure that doesn't clear ends once the body stops closing the issue in
# that repository, as the message says.
GH_API_FAIL=rate expect "cross-repo: dropping the keyword ends a lookup that keeps failing" 0 42 "Fixes acme/tracker#42
Refs acme/other#42"
for bad in 0 x 1s; do
    CHECK_CLOSING_KEYWORD_LOOKUP_SECS=$bad \
        expect "a lookup time of [$bad] is a usage error" 2 42 "Fixes acme/tracker#42"
done
unset GH_RENAMED GH_MISSING

# The lookup runs only for another repository the body closes issue N in, on
# the pull request's host.
GH_LOG=$(mktemp) || exit 1; TMPS+=("$GH_LOG")
export GH_LOG
run_gate 42 "Fixes acme/tracker#42
See acme/other#42 and Fixes acme/app#421"
if ! grep -q '^api' "$GH_LOG"; then
    pass "cross-repo: the right reference alone makes no lookup"
else
    fail "cross-repo: the right reference alone made a lookup: $(cat "$GH_LOG")"
fi
: > "$GH_LOG"
run_gate 42 "Fixes acme/tracker#42
Fixes acme/other#42"
if [[ "$(grep -c '^api' "$GH_LOG")" == 1 ]] && grep -qx 'api --hostname github.com repos/acme/other --jq .full_name' "$GH_LOG"; then
    pass "cross-repo: another repository is looked up once, on the PR's host"
else
    fail "cross-repo: unexpected lookups: $(cat "$GH_LOG")"
fi

# The body's size can't turn into calls: a name is looked up once however
# often it appears, in whatever case or form, and a body that closes issue N
# in more than five other repositories fails with no lookup at all.
: > "$GH_LOG"
run_gate 42 "Fixes acme/tracker#42
Fixes acme/other#42, fixes ACME/Other#42, closes https://github.com/acme/other/issues/42
Fixes [acme/other#42](https://github.com/acme/other/issues/42)"
if [[ "$(grep -c '^api' "$GH_LOG")" == 1 ]]; then
    pass "cross-repo: one repository named many ways is looked up once"
else
    fail "cross-repo: one repository made $(grep -c '^api' "$GH_LOG") lookups"
fi
FIVE="Fixes acme/tracker#42"
for i in 1 2 3 4 5; do FIVE="$FIVE
Fixes acme/r$i#42"; done
SIX="$FIVE
Fixes acme/r6#42"
expect "cross-repo: five other repositories are looked up and pass" 0 42 "$FIVE"
: > "$GH_LOG"
expect "cross-repo: six other repositories fail" 1 42 "$SIX"
if ! grep -q '^api' "$GH_LOG"; then
    pass "cross-repo: six other repositories fail before any lookup"
else
    fail "cross-repo: six other repositories made lookups: $(cat "$GH_LOG")"
fi
MANY="Fixes acme/tracker#42"
for i in $(seq 1 200); do MANY="$MANY
Fixes acme/r$i#42 and see acme/s$i#42"; done
: > "$GH_LOG"
expect "cross-repo: a body naming 200 other repositories fails" 1 42 "$MANY"
if ! grep -q '^api' "$GH_LOG"; then
    pass "cross-repo: a body naming 200 other repositories makes no lookup"
else
    fail "cross-repo: a body naming 200 other repositories made $(grep -c '^api' "$GH_LOG") lookups"
fi
: > "$GH_LOG"
expect "cross-repo: mentions without a keyword don't count toward the limit" 0 42 "$FIVE
See acme/s1#42, acme/s2#42, acme/s3#42 and https://github.com/acme/s4/issues/42"
if [[ "$(grep -c '^api' "$GH_LOG")" == 5 ]]; then
    pass "cross-repo: only the five closing references were looked up"
else
    fail "cross-repo: expected 5 lookups, got $(grep -c '^api' "$GH_LOG")"
fi
unset GH_LOG

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
