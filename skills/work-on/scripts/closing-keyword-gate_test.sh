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
# check-closing-keyword.sh's two other modes, --non-closing (a pull request
# that refers to its issue without closing it) and --approved-pass (the state
# log probe), are called directly, with the same stub ahead of the real gh,
# along with the script's usage refusals. The gate picks between the modes
# from DELIVERY and the probe's answer, so the gate cases run with no state log
# (closing mode, as before), and a section near the end writes one where the
# gate looks for it.
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
ktg_on_exit cleanup

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
# $GH_API_WARN makes a lookup that works also write to stderr. Asked for
# `--json url,title,body,commits` (the script's non-closing read), it prints
# that JSON object, built from $PR_URL, $PR_TITLE, $PR_BODY and $PR_COMMITS
# (a JSON array of {oid, messageHeadline, messageBody}), or $GH_RAW as it
# stands when that is set, for an answer jq can't parse.
STUB_DIR=$(mktemp -d) || exit 1; TMPS+=("$STUB_DIR")
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Stands in for `gh pr view --json body --jq .body`,
# `gh pr view --json url,body --jq '.url, .body'`,
# `gh pr view --json url,title,body,commits` and
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
if [[ " $* " == *" url,title,body,commits "* ]]; then
    if [[ -n "${GH_RAW:-}" ]]; then printf '%s\n' "$GH_RAW"; exit 0; fi
    jq -n --arg url "${PR_URL:-https://github.com/acme/app/pull/7}" --arg title "${PR_TITLE:-}" \
        --arg body "${PR_BODY:-}" --argjson commits "${PR_COMMITS:-[]}" \
        '{url: $url, title: $title, body: $body, commits: $commits}'
    exit
fi
[[ " $* " == *" url,body "* ]] && printf '%s\n' "${PR_URL:-https://github.com/acme/app/pull/7}"
printf '%s\n' "${PR_BODY:-}"
STUB
chmod +x "$STUB_DIR/gh"

# The plugin root the gate reaches check-closing-keyword.sh through.
PLUGIN_DIR=$(cd "$SKILL_DIR/../.." && pwd)
# The script itself, for the cases that call it directly.
SCRIPT="$SCRIPT_DIR/check-closing-keyword.sh"

# The session the gate reads its state log from: {{SESSION_DIR}} and
# {{SESSION_NAME}} resolve to these, so the log is $GATE_LOG. It doesn't exist
# until a case writes it, so every case before then runs in closing mode.
GATE_SESSION_DIR=$(mktemp -d) || exit 1; TMPS+=("$GATE_SESSION_DIR")
GATE_SESSION_NAME=gate-test
GATE_LOG="$GATE_SESSION_DIR/koto-$GATE_SESSION_NAME.state.jsonl"

# run_gate <issue-number> <body> [<gh-fails>] — substitute {{ISSUE_NUMBER}},
# {{ISSUE_REPO}} (from $ISSUE_REPO, empty by default, as an unset variable
# resolves), {{DELIVERY}} (from $DELIVERY, `closes` by default, as the
# template declares), {{SESSION_DIR}}, {{SESSION_NAME}} and {{PLUGIN_ROOT}} as
# koto would, then run the expression with the stub ahead of the real gh. A
# `{{` left after that fails the case: an unsubstituted log path reads as no
# log, and a case would pass in closing mode for the wrong reason.
run_gate() {
    local issue="$1" body="$2"
    local cmd="${GATE//\{\{ISSUE_NUMBER\}\}/$issue}"
    cmd="${cmd//\{\{ISSUE_REPO\}\}/${ISSUE_REPO:-}}"
    cmd="${cmd//\{\{DELIVERY\}\}/${DELIVERY:-closes}}"
    cmd="${cmd//\{\{SESSION_DIR\}\}/$GATE_SESSION_DIR}"
    cmd="${cmd//\{\{SESSION_NAME\}\}/$GATE_SESSION_NAME}"
    cmd="${cmd//\{\{PLUGIN_ROOT\}\}/$PLUGIN_DIR}"
    if [[ "$cmd" == *'{{'* ]]; then
        fail "the gate command still holds a template variable after substitution: $cmd"
        return 125
    fi
    PATH="$STUB_DIR:$PATH" PR_BODY="$body" PR_URL="${PR_URL:-}" GH_FAIL="${3:-0}" \
        PR_TITLE="${PR_TITLE:-}" PR_COMMITS="${PR_COMMITS:-[]}" \
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
# gh for the url, which only check-closing-keyword.sh's closing and
# non-closing modes do: a same-repository closing run starts the script only
# as the log probe, which makes no gh call, and reads only the body.
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

# --- the script's non-closing mode --------------------------------------------
# A pull request that delivers part of its issue, or follows an approved
# deferral, leaves the issue open: its body must refer to the issue with Ref,
# Refs or Part of, and nothing in its body, title or commits may close it.
ERR=$(mktemp) || exit 1; TMPS+=("$ERR")
# run_script <args...>: the script with the stub ahead of the real gh, its
# stderr kept in $ERR for the message checks.
run_script() {
    PATH="$STUB_DIR:$PATH" PR_BODY="${PR_BODY:-}" PR_TITLE="${PR_TITLE:-}" \
        PR_COMMITS="${PR_COMMITS:-[]}" PR_URL="${PR_URL:-}" GH_FAIL="${GH_FAIL:-0}" \
        GH_RAW="${GH_RAW:-}" GH_RENAMED="${GH_RENAMED:-}" GH_MISSING="${GH_MISSING:-}" \
        GH_API_FAIL="${GH_API_FAIL:-}" "$SCRIPT" "$@" >/dev/null 2>"$ERR"
}
# expect_open <label> <want> <body>: non-closing mode for issue 42, with
# --repo "$ISSUE_REPO" when that is set.
expect_open() {
    local label="$1" want="$2" args got
    args=(--issue 42 --non-closing)
    [[ -z "${ISSUE_REPO:-}" ]] || args+=(--repo "$ISSUE_REPO")
    PR_BODY="$3" run_script "${args[@]}"; got=$?
    if [[ "$got" == "$want" ]]; then pass "$label (exit $got)"
    else fail "$label: expected exit $want, got $got: $(cat "$ERR")"; fi
}
# expect_got <label> <want> <got>: a direct call's exit status.
expect_got() {
    if [[ "$3" == "$2" ]]; then pass "$1 (exit $3)"
    else fail "$1: expected exit $2, got $3"; fi
}
# expect_said <label> <text>: the last run's stderr holds <text>.
expect_said() {
    if grep -qF -- "$2" "$ERR"; then pass "$1"
    else fail "$1: stderr lacks [$2]: $(cat "$ERR")"; fi
}

# The three words, in the forms closing mode passes with its keywords.
expect_open "non-closing: Refs #N passes" 0 "Refs #42"
expect_open "non-closing: Ref #N passes" 0 "Ref #42"
expect_open "non-closing: Part of #N after Part 1 passes" 0 "Part 1

---

Part of #42"
expect_open "non-closing: a colon after the word passes" 0 "Part of: #42"
expect_open "non-closing: Refs: #N passes" 0 "Refs: #42"
expect_open "non-closing: a lowercase word passes" 0 "part of #42"
expect_open "non-closing: a reference followed by a full stop passes" 0 "Refs #42."
expect_open "non-closing: a reference mid-line passes" 0 "Refs #841, part of #42."
expect_open "non-closing: the qualified form passes" 0 "Part of acme/app#42"
expect_open "non-closing: a closing keyword for another issue passes" 0 "Fixes #43
Part of #42"

# What isn't the reference: refused as missing, though none of it closes.
expect_open "non-closing: #N running into more digits is no reference" 1 "Refs #421"
expect_said "non-closing: a missing reference gives the line to add" "add the line Part of #42"
expect_open "non-closing: the word inside a word is no reference" 1 "prefs #42"
expect_open "non-closing: See #N is no reference" 1 "See #42"
expect_open "non-closing: a bare issue URL is no reference" 1 "https://github.com/acme/app/issues/42"
expect_open "non-closing: a bare #N is no reference" 1 "#42"
expect_open "non-closing: Part and of on two lines is no reference" 1 "Part
of #42"
expect_open "non-closing: an empty body fails" 1 ""

# Every form that closes the issue is refused, even beside the reference. GH-N,
# the issue URL and the link don't satisfy closing mode's same-repository
# expression, but GitHub closes the issue on each (#1044): refused here on
# purpose.
expect_open "non-closing: Fixes #N is refused" 1 "Fixes #42"
expect_said "non-closing: the refusal quotes the phrase and where it stands" 'body: "Fixes #42" closes #42 on merge'
expect_said "non-closing: the missing reference is reported beside it" "body: no Ref, Refs or Part of reference to #42"
expect_said "non-closing: the refusal says why the issue stays open" "declared a partial delivery or came from an approved deferral"
expect_said "non-closing: the refusal warns off the closing keyword" "not Fixes #42"
expect_open "non-closing: Fixes #N beside Part of #N is refused" 1 "Part of #42
Fixes #42"
expect_open "non-closing: Fixes GH-N is refused" 1 "Part of #42
Fixes GH-42"
expect_open "non-closing: Fixes <issue URL> is refused" 1 "Part of #42
Fixes https://github.com/acme/app/issues/42"
expect_open "non-closing: the markdown link is refused" 1 "Part of #42
Fixes [#42](https://github.com/acme/app/issues/42)"
expect_said "non-closing: the link is quoted whole" '"Fixes [#42](https://github.com/acme/app/issues/42)"'
expect_open "non-closing: Closes <PR repo>#N is refused" 1 "Part of #42
Closes acme/app#42"
expect_open "non-closing: Fixes:#N with no space is refused" 1 "Part of #42
Fixes:#42"
expect_open "non-closing: a keyword inside a word is refused" 1 "Part of #42
prefixes #42"
expect_open "non-closing: a keyword split from #N by a newline is refused" 1 "Part of #42
Fixes
#42"

# The title and the commits are read for refusals too, and every finding is
# reported in one run.
PR_TITLE="fix: parser (closes #42)" \
    PR_COMMITS='[{"oid":"abcdef0123456789","messageHeadline":"fix: parser","messageBody":"Fixes #42"}]' \
    expect_open "non-closing: closing forms in the body, title and a commit are refused" 1 "Fixes #42"
expect_said "non-closing: the title is named" 'title: "closes #42" closes #42 on merge'
expect_said "non-closing: the commit is named by its short SHA" 'commit abcdef0: "Fixes #42" closes #42 on merge'
expect_said "non-closing: the body is named in the same run" 'body: "Fixes #42"'
expect_said "non-closing: the missing reference is named in the same run" "body: no Ref, Refs or Part of reference to #42"
PR_TITLE="Fixes #42" expect_open "non-closing: a closing keyword in the title alone is refused" 1 "Part of #42"
expect_said "non-closing: a title refusal says what to do" "take it out of the title"
PR_COMMITS='[{"oid":"0123456789abcdef","messageHeadline":"feat: step one","messageBody":"Resolves\n#42"}]' \
    expect_open "non-closing: a commit closing the issue across its lines is refused" 1 "Part of #42"
expect_said "non-closing: that commit is named" 'commit 0123456: "Resolves #42"'
PR_COMMITS='[{"oid":"1111111aaaa","messageHeadline":"feat: one","messageBody":""},{"oid":"2222222bbbb","messageHeadline":"fixes #42","messageBody":""}]' \
    expect_open "non-closing: a closing headline in the second commit is refused" 1 "Part of #42"
expect_said "non-closing: the second commit is the one named" 'commit 2222222: "fixes #42"'
PR_COMMITS='[{"oid":"0123456789abcdef","messageHeadline":"fix: other","messageBody":"Fixes #43"}]' \
    expect_open "non-closing: a commit closing another issue passes" 0 "Part of #42"
PR_TITLE="Part of #42" expect_open "non-closing: a reference only in the title is missing" 1 ""
PR_COMMITS='[{"oid":"0123456789abcdef","messageHeadline":"feat: x","messageBody":"Part of #42"}]' \
    expect_open "non-closing: a reference only in a commit is missing" 1 ""
PR_COMMITS='[{"oid":"0123456789abcdef","messageHeadline":"feat: x","messageBody":"token-s3cr3t-value Fixes #42 trailing-words"}]' \
    expect_open "non-closing: a commit refusal" 1 "Part of #42"
if grep -q 's3cr3t' "$ERR" || grep -q 'trailing-words' "$ERR"; then
    fail "non-closing: a refusal echoed more than the matched phrase: $(cat "$ERR")"
else
    pass "non-closing: a refusal quotes only the matched phrase"
fi

# An unreadable pull request fails closed, as in closing mode.
GH_FAIL=1 expect_open "non-closing: an unreadable pull request fails" 1 "Part of #42"
GH_RAW="not json" expect_open "non-closing: an answer jq can't parse fails" 1 "Part of #42"
PR_URL=not-a-url expect_open "non-closing: an unreadable PR url fails closed" 1 "Part of #42"
EMPTY_DIR=$(mktemp -d) || exit 1; TMPS+=("$EMPTY_DIR")
PATH="$EMPTY_DIR" "$BASH" "$SCRIPT" --issue 42 --non-closing >/dev/null 2>&1; got=$?
expect_got "non-closing: no jq holds" 2 "$got"

# One read of the pull request, with the four fields.
GH_LOG=$(mktemp) || exit 1; TMPS+=("$GH_LOG")
export GH_LOG
expect_open "non-closing: a plain reference passes" 0 "Part of #42"
if [[ "$(grep -c . "$GH_LOG")" == 1 ]] && grep -qx 'pr view --json url,title,body,commits' "$GH_LOG"; then
    pass "non-closing: one gh pr view reads url, title, body and commits"
else
    fail "non-closing: unexpected gh calls: $(cat "$GH_LOG")"
fi

# Old names, from every source, under one cap and one deadline.
export GH_RENAMED="acme/old-app=acme/app"
expect_open "non-closing: this repo's old name in the body is refused" 1 "Part of #42
Fixes acme/old-app#42"
expect_said "non-closing: the old name is named" "body: acme/old-app is an old name of acme/app"
PR_COMMITS='[{"oid":"abcdef0123456789","messageHeadline":"fix: x","messageBody":"Fixes acme/old-app#42"}]' \
    expect_open "non-closing: this repo's old name in a commit is refused" 1 "Part of #42"
expect_said "non-closing: the old name's commit is named" "commit abcdef0: acme/old-app is an old name of acme/app"
PR_TITLE="Closes acme/old-app#42" expect_open "non-closing: this repo's old name in the title is refused" 1 "Part of #42"
expect_said "non-closing: the old name's title is named" "title: acme/old-app is an old name of acme/app"
expect_open "non-closing: a third repository's issue passes" 0 "Part of #42
Fixes acme/other#42"
: > "$GH_LOG"
PR_TITLE="Fixes acme/other#42" \
    PR_COMMITS='[{"oid":"abcdef0123456789","messageHeadline":"Fixes ACME/Other#42","messageBody":""}]' \
    expect_open "non-closing: one name in the body, title and a commit passes" 0 "Part of #42
Fixes acme/other#42"
if [[ "$(grep -c '^api' "$GH_LOG")" == 1 ]]; then
    pass "non-closing: one name across the sources is looked up once"
else
    fail "non-closing: one name made $(grep -c '^api' "$GH_LOG") lookups"
fi
: > "$GH_LOG"
PR_TITLE="Fixes acme/r4#42" \
    PR_COMMITS='[{"oid":"abcdef0123456789","messageHeadline":"Fixes acme/r5#42","messageBody":"Fixes acme/r6#42"}]' \
    expect_open "non-closing: six other repositories across the sources fail" 1 "Part of #42
Fixes acme/r1#42, fixes acme/r2#42, fixes acme/r3#42"
expect_said "non-closing: the cap is named" "in more than 5 other repositories"
if ! grep -q '^api' "$GH_LOG"; then
    pass "non-closing: six other repositories fail before any lookup"
else
    fail "non-closing: six other repositories made lookups: $(cat "$GH_LOG")"
fi
: > "$GH_LOG"
PR_TITLE="Fixes acme/r4#42" \
    PR_COMMITS='[{"oid":"abcdef0123456789","messageHeadline":"Fixes acme/r5#42","messageBody":""}]' \
    expect_open "non-closing: five other repositories across the sources pass" 0 "Part of #42
Fixes acme/r1#42, fixes acme/r2#42, fixes acme/r3#42"
if [[ "$(grep -c '^api' "$GH_LOG")" == 5 ]]; then
    pass "non-closing: the five are looked up"
else
    fail "non-closing: expected 5 lookups, got $(grep -c '^api' "$GH_LOG")"
fi
: > "$GH_LOG"
GH_API_FAIL=rate expect_open "non-closing: a local finding is reported before any lookup" 1 "Part of #42
Fixes #42
Fixes acme/other#42"
if ! grep -q '^api' "$GH_LOG"; then
    pass "non-closing: a local finding makes no lookup"
else
    fail "non-closing: a local finding made lookups: $(cat "$GH_LOG")"
fi
GH_API_FAIL=rate expect_open "non-closing: a failed lookup holds the gate" 3 "Part of #42
Fixes acme/other#42"
unset GH_LOG

# An issue in another repository: the reference is qualified or linked, and
# the issue's own closing forms are refused along with this repository's.
export ISSUE_REPO=acme/tracker
expect_open "non-closing cross-repo: Part of owner/repo#N passes" 0 "Part of acme/tracker#42"
expect_open "non-closing cross-repo: the link passes" 0 "Refs [acme/tracker#42](https://github.com/acme/tracker/issues/42)"
expect_open "non-closing cross-repo: owner/repo in another case passes" 0 "part of ACME/Tracker#42"
expect_open "non-closing cross-repo: a bare Part of #N is no reference" 1 "Part of #42"
expect_said "non-closing cross-repo: the missing reference gives the qualified line" "add the line Part of acme/tracker#42"
expect_open "non-closing cross-repo: Fixes owner/repo#N is refused" 1 "Part of acme/tracker#42
Fixes acme/tracker#42"
expect_said "non-closing cross-repo: it names the issue it closes" 'body: "Fixes acme/tracker#42" closes acme/tracker#42 on merge'
expect_open "non-closing cross-repo: the link closing mode accepts is refused" 1 "Part of acme/tracker#42
Fixes [acme/tracker#42](https://github.com/acme/tracker/issues/42)"
expect_open "non-closing cross-repo: the issue's URL is refused" 1 "Part of acme/tracker#42
Closes https://github.com/acme/tracker/issues/42"
expect_open "non-closing cross-repo: Fixes #N, closing this repo's issue, is refused" 1 "Part of acme/tracker#42
Fixes #42"
expect_said "non-closing cross-repo: it names this repo's issue" 'body: "Fixes #42" closes acme/app#42 on merge'
expect_open "non-closing cross-repo: another issue there passes" 0 "Part of acme/tracker#42
Fixes acme/tracker#43"
export GH_RENAMED="acme/old-tracker=acme/tracker acme/old-app=acme/app"
expect_open "non-closing cross-repo: the issue repository's old name is refused" 1 "Part of acme/tracker#42
Fixes acme/old-tracker#42"
expect_said "non-closing cross-repo: that old name is named" "acme/old-tracker is an old name of acme/tracker"
expect_open "non-closing cross-repo: this repo's old name is refused" 1 "Part of acme/tracker#42
Fixes acme/old-app#42"
unset GH_RENAMED
export ISSUE_REPO=ACME/App
expect_open "non-closing: ISSUE_REPO naming the PR's repo in another case takes Part of #N" 0 "Part of #42"
unset ISSUE_REPO

# --- the script's log probe -----------------------------------------------------
# Did this pass reach pre_pr_evidence through the engine's approved transition
# out of deferral_approval, with no return to finalization or
# deferral_approval since?
LOGS=$(mktemp -d) || exit 1; TMPS+=("$LOGS")
PROBE_LOG="$LOGS/koto-run.state.jsonl"
HDR='{"schema_version":1,"workflow":"work-on"}'
# ev <type> <from> <to>: one event line, in the shape koto writes.
ev() { printf '{"seq":1,"timestamp":"t","type":"%s","payload":{"from":"%s","to":"%s"}}' "$1" "$2" "$3"; }
UP_TO_APPROVAL="$(ev transitioned implementation finalization)
$(ev transitioned finalization deferral_approval)
{\"seq\":1,\"type\":\"decision_recorded\",\"payload\":{\"state\":\"deferral_approval\",\"decision\":{\"choice\":\"approve\"}}}
$(ev transitioned deferral_approval pre_pr_evidence)"
APPROVED="$HDR
$UP_TO_APPROVAL
{\"seq\":1,\"type\":\"evidence_submitted\",\"payload\":\"not an object\"}
$(ev transitioned pre_pr_evidence pr_precheck)
$(ev transitioned pr_precheck pr_creation)"
# expect_probe <label> <want> <log content>
expect_probe() {
    local got
    printf '%s\n' "$3" > "$PROBE_LOG"
    run_script --approved-pass "$PROBE_LOG"; got=$?
    if [[ "$got" == "$2" ]]; then pass "$1 (exit $got)"
    else fail "$1: expected exit $2, got $got: $(cat "$ERR")"; fi
}
GH_LOG=$(mktemp) || exit 1; TMPS+=("$GH_LOG")
export GH_LOG
expect_probe "probe: an approved pass" 0 "$APPROVED"
if [[ ! -s "$GH_LOG" ]]; then pass "probe: makes no gh call"
else fail "probe: made gh calls: $(cat "$GH_LOG")"; fi
unset GH_LOG
expect_probe "probe: a header-less log reads" 0 "$UP_TO_APPROVAL"
expect_probe "probe: a recount back through finalization to ready_for_pr is not approved" 1 "$APPROVED
$(ev transitioned pr_creation pr_precheck)
$(ev transitioned pr_precheck finalization)
$(ev transitioned finalization pre_pr_evidence)
$(ev transitioned pre_pr_evidence pr_precheck)
$(ev transitioned pr_precheck pr_creation)"
expect_probe "probe: a return to finalization with no arrival since is not approved" 1 "$APPROVED
$(ev transitioned pr_creation finalization)"
expect_probe "probe: a directed move into deferral_approval cancels the approval" 1 "$APPROVED
$(ev directed_transition pr_creation deferral_approval)"
expect_probe "probe: a directed arrival from deferral_approval is not approved" 1 "$HDR
$(ev transitioned implementation finalization)
$(ev transitioned finalization deferral_approval)
$(ev directed_transition deferral_approval pre_pr_evidence)
$(ev transitioned pre_pr_evidence pr_creation)"
# The same log twice, differing only in the latest arrival's type: the
# directed one is what makes the answer no.
expect_probe "probe: a later transitioned arrival from deferral_approval is approved" 0 "$HDR
$UP_TO_APPROVAL
$(ev transitioned deferral_approval pre_pr_evidence)"
expect_probe "probe: a later directed arrival after an approval is not approved" 1 "$HDR
$UP_TO_APPROVAL
$(ev directed_transition deferral_approval pre_pr_evidence)"
expect_probe "probe: a rewind into pr_creation after the approval keeps it" 0 "$APPROVED
$(ev transitioned pr_creation done_blocked)
$(ev rewound done_blocked pr_creation)"
expect_probe "probe: a rewind into pre_pr_evidence after the approval keeps it" 0 "$APPROVED
$(ev rewound pr_creation pre_pr_evidence)"
expect_probe "probe: a rewind to finalization after the approval is not approved" 1 "$APPROVED
$(ev rewound pr_creation finalization)"
expect_probe "probe: a rewind out of deferral_approval is no arrival" 1 "$HDR
$(ev transitioned finalization pre_pr_evidence)
$(ev transitioned pre_pr_evidence deferral_approval)
$(ev rewound deferral_approval pre_pr_evidence)"
expect_probe "probe: an arrival from finalization is not approved" 1 "$HDR
$(ev transitioned implementation finalization)
$(ev transitioned finalization pre_pr_evidence)
$(ev transitioned pre_pr_evidence pr_creation)"
expect_probe "probe: a header alone is not approved" 1 "$HDR"
expect_probe "probe: a line that isn't JSON holds" 2 "$APPROVED
not json"
expect_probe "probe: a truncated line holds" 2 "$APPROVED
{\"seq\":9,\"type\":\"transitioned\",\"payload\":{\"to\":\"done\""
rm -f "$PROBE_LOG"
run_script --approved-pass "$PROBE_LOG"; got=$?
expect_got "probe: an absent log is not approved" 1 "$got"
: > "$PROBE_LOG"
run_script --approved-pass "$PROBE_LOG"; got=$?
expect_got "probe: an empty log is not approved" 1 "$got"
run_script --approved-pass "$LOGS"; got=$?
expect_got "probe: a path that can't be read as a file holds" 2 "$got"
printf '%s\n' "$APPROVED" > "$PROBE_LOG"
PATH="$EMPTY_DIR" "$BASH" "$SCRIPT" --approved-pass "$PROBE_LOG" >/dev/null 2>&1; got=$?
expect_got "probe: no jq holds" 2 "$got"

# --- the gate picks its mode ----------------------------------------------------
# Through the gate command, as the template has it: DELIVERY=partial goes to
# non-closing mode without reading the log; otherwise the probe reads the log
# at {{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl, and an approved pass is
# non-closing, anything it says no to is closing, and a log it can't read
# holds.
rm -f "$GATE_LOG"
DELIVERY=partial expect "gate, declared split: Part of #N passes" 0 42 "Part 1

---

Part of #42"
DELIVERY=partial expect "gate, declared split: Refs #N passes" 0 42 "Refs #42"
DELIVERY=partial expect "gate, declared split: Fixes #N is refused" 1 42 "Fixes #42"
DELIVERY=partial expect "gate, declared split: Fixes #N beside Part of #N is refused" 1 42 "Part of #42
Fixes #42"
DELIVERY=partial expect "gate, declared split: no reference fails" 1 42 "See #42"
DELIVERY=partial PR_TITLE="Fixes #42" \
    expect "gate, declared split: a closing title is refused" 1 42 "Part of #42"
DELIVERY=partial PR_COMMITS='[{"oid":"abcdef0123456789","messageHeadline":"fix: x","messageBody":"Closes #42"}]' \
    expect "gate, declared split: a closing commit is refused" 1 42 "Part of #42"
DELIVERY=partial expect "gate, declared split: an empty issue number still passes" 0 "" "Fixes #42"
# A declared split never reads the log, so a log that would hold doesn't.
printf '%s\n' "not json" > "$GATE_LOG"
DELIVERY=partial expect "gate, declared split: an unreadable log isn't read" 0 42 "Part of #42"
rm -f "$GATE_LOG"
export ISSUE_REPO=acme/tracker
DELIVERY=partial expect "gate, declared split cross-repo: Part of owner/repo#N passes" 0 42 "Part of acme/tracker#42"
DELIVERY=partial expect "gate, declared split cross-repo: the link passes" 0 42 "Part of [acme/tracker#42](https://github.com/acme/tracker/issues/42)"
DELIVERY=partial expect "gate, declared split cross-repo: a bare Part of #N fails" 1 42 "Part of #42"
DELIVERY=partial expect "gate, declared split cross-repo: Fixes owner/repo#N is refused" 1 42 "Part of acme/tracker#42
Fixes acme/tracker#42"
DELIVERY=partial expect "gate, declared split cross-repo: Fixes #N is refused" 1 42 "Part of acme/tracker#42
Fixes #42"
unset ISSUE_REPO

# An approved pass in the log switches a run with DELIVERY=closes, the
# default, to non-closing mode.
printf '%s\n' "$APPROVED" > "$GATE_LOG"
expect "gate, approved pass: Part of #N passes" 0 42 "Part of #42"
expect "gate, approved pass: Fixes #N is refused" 1 42 "Fixes #42"
DELIVERY=closes expect "gate, approved pass with DELIVERY=closes written out: Fixes #N is refused" 1 42 "Fixes #42"
export ISSUE_REPO=acme/tracker
expect "gate, approved pass cross-repo: Part of owner/repo#N passes" 0 42 "Part of acme/tracker#42"
expect "gate, approved pass cross-repo: Fixes owner/repo#N is refused" 1 42 "Fixes acme/tracker#42"
unset ISSUE_REPO
# A rewind from done_blocked back into pr_creation keeps the approval.
printf '%s\n' "$APPROVED
$(ev transitioned pr_creation done_blocked)
$(ev rewound done_blocked pr_creation)" > "$GATE_LOG"
expect "gate, approved pass then a rewind into pr_creation: still non-closing" 0 42 "Part of #42"

# A recount back through finalization to ready_for_pr is closing again.
RECOUNT="$APPROVED
$(ev transitioned pr_creation pr_precheck)
$(ev transitioned pr_precheck finalization)
$(ev transitioned finalization pre_pr_evidence)
$(ev transitioned pre_pr_evidence pr_precheck)
$(ev transitioned pr_precheck pr_creation)"
printf '%s\n' "$RECOUNT" > "$GATE_LOG"
expect "gate, recount: Fixes #N passes" 0 42 "Fixes #42"
expect "gate, recount: Part of #N fails" 1 42 "Part of #42"
export ISSUE_REPO=acme/tracker
expect "gate, recount cross-repo: Fixes owner/repo#N passes" 0 42 "Fixes acme/tracker#42"
unset ISSUE_REPO
# A directed arrival from deferral_approval is no approval either.
printf '%s\n' "$HDR
$UP_TO_APPROVAL
$(ev directed_transition deferral_approval pre_pr_evidence)" > "$GATE_LOG"
expect "gate, directed arrival: Fixes #N passes" 0 42 "Fixes #42"
expect "gate, directed arrival: Part of #N fails" 1 42 "Part of #42"

# A log the probe can't read holds the state, whatever the body says.
printf '%s\n' "$APPROVED
not json" > "$GATE_LOG"
expect "gate, unparseable log: Fixes #N holds" 2 42 "Fixes #42"
expect "gate, unparseable log: Part of #N holds" 2 42 "Part of #42"
export ISSUE_REPO=acme/tracker
expect "gate, unparseable log cross-repo: holds" 2 42 "Fixes acme/tracker#42"
unset ISSUE_REPO
expect "gate, unparseable log: an empty issue number still passes" 0 "" "no keyword here"

# What the gate asks gh. A same-repository closing run with a log that holds
# no approval still makes only the inline read, and asks for no url.
GH_LOG=$(mktemp) || exit 1; TMPS+=("$GH_LOG")
export GH_LOG
printf '%s\n' "$RECOUNT" > "$GATE_LOG"
run_gate 42 "Fixes #42"
if [[ "$(grep -c . "$GH_LOG")" == 1 ]] && grep -qx 'pr view --json body --jq .body' "$GH_LOG"; then
    pass "gate, a non-approved log: a same-repository closing run reads only the body"
else
    fail "gate, a non-approved log: unexpected gh calls: $(cat "$GH_LOG")"
fi
# A non-closing run, either way in, makes one pr view with the four fields.
: > "$GH_LOG"
DELIVERY=partial run_gate 42 "Part of #42"
if [[ "$(grep -c . "$GH_LOG")" == 1 ]] && grep -qx 'pr view --json url,title,body,commits' "$GH_LOG"; then
    pass "gate, declared split: one gh pr view reads url, title, body and commits"
else
    fail "gate, declared split: unexpected gh calls: $(cat "$GH_LOG")"
fi
: > "$GH_LOG"
printf '%s\n' "$APPROVED" > "$GATE_LOG"
run_gate 42 "Part of #42"
if [[ "$(grep -c . "$GH_LOG")" == 1 ]] && grep -qx 'pr view --json url,title,body,commits' "$GH_LOG"; then
    pass "gate, approved pass: one gh pr view reads url, title, body and commits"
else
    fail "gate, approved pass: unexpected gh calls: $(cat "$GH_LOG")"
fi
unset GH_LOG
rm -f "$GATE_LOG"

# --- the script's own usage refusals ------------------------------------------
# Exit 2, which no pr_creation edge routes, so the state holds rather than
# reaching done_blocked or ci_monitor.
for args in "" "--issue 42" "--repo acme/tracker" "--issue 042 --repo acme/tracker" \
            "--issue 4x2 --repo acme/tracker" "--issue 42 --repo acme" \
            "--issue 42 --repo acme/tracker/extra" "--issue 42 --repo acme/tr;cker" \
            "--issue 42 --repo acme/tracker --bogus" "--bogus" \
            "--non-closing" "--repo acme/tracker --non-closing" \
            "--issue 42 --non-closing yes" "--issue 042 --non-closing" \
            "--issue 42 --non-closing --repo acme" "--issue 42 --non-closing --bogus" \
            "--issue --non-closing" "--approved-pass" \
            "--approved-pass $LOGS/x --issue 42" "--issue 42 --approved-pass $LOGS/x" \
            "--approved-pass $LOGS/x --repo acme/tracker" "--approved-pass $LOGS/x --non-closing" \
            "--issue 42 --repo acme/tracker --approved-pass $LOGS/x"; do
    # shellcheck disable=SC2086
    PATH="$STUB_DIR:$PATH" PR_BODY="Fixes acme/tracker#42" "$SCRIPT" $args >/dev/null 2>&1; got=$?
    if [[ "$got" == 2 ]]; then pass "usage [$args] exits 2"
    else fail "usage [$args]: expected exit 2, got $got"; fi
done
PATH="$STUB_DIR:$PATH" PR_BODY="Fixes acme/tracker#42" "$SCRIPT" --issue 42 --repo "acme/tracker
evil/x" >/dev/null 2>&1; got=$?
[[ "$got" == 2 ]] && pass "a repo value with a newline exits 2" || fail "a repo value with a newline: exit $got"
PATH="$STUB_DIR:$PATH" "$SCRIPT" --approved-pass "" >/dev/null 2>&1; got=$?
expect_got "an empty --approved-pass value is a usage error" 2 "$got"

echo
echo "closing-keyword-gate_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
