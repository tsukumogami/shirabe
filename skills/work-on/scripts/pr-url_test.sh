#!/usr/bin/env bash
# pr-url_test.sh -- does pr_url_parse take a pull request URL apart into its
# host, owner and repository, and refuse anything else?
#
# pr-url.sh is the one parse ci-none-declared.sh and ci-cancel-after-merge.sh
# share (#1051). Their own suites run it through each script against a
# stubbed gh; this one sources it and checks its answer for each URL: what
# it sets, what it returns, and that a refusal leaves nothing behind from an
# earlier parse.
#
# Usage: pr-url_test.sh
# Exit codes: 0 all pass, 1 any failed.
#
# Bash 3.2: no associative arrays, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

OPTS_BEFORE="$-:$(set -o | tr -s ' \t' ' ' | tr '\n' ',')"
SOURCED=$(. "$SCRIPT_DIR/pr-url.sh" 2>&1)
if [ -z "$SOURCED" ]; then pass "sourcing prints nothing"
else fail "sourcing printed: $SOURCED"; fi
# shellcheck source=pr-url.sh
. "$SCRIPT_DIR/pr-url.sh" || { echo "pr-url_test: could not source pr-url.sh" >&2; exit 1; }
OPTS_AFTER="$-:$(set -o | tr -s ' \t' ' ' | tr '\n' ',')"
if [ "$OPTS_BEFORE" = "$OPTS_AFTER" ]; then pass "sourcing changes no shell option"
else fail "sourcing changed the shell options"; fi

# accepts <url> <host> <owner> <repo>: parses, returns 0, sets all three.
accepts() {
    local url="$1" host="$2" owner="$3" repo="$4" rc=0
    pr_url_parse "$url" || rc=$?
    if [ "$rc" = 0 ] && [ "$PR_HOST" = "$host" ] && [ "$PR_OWNER" = "$owner" ] \
        && [ "$PR_REPO" = "$repo" ]; then
        pass "accepts [$url] as $host $owner/$repo"
    else
        fail "[$url]: rc $rc, host [$PR_HOST] owner [$PR_OWNER] repo [$PR_REPO]; wanted $host $owner/$repo"
    fi
}

# refuses <url>: returns 1 and clears all three, even after a good parse.
refuses() {
    local url="$1" rc=0
    pr_url_parse "https://github.com/acme/widgets/pull/1" || true
    pr_url_parse "$url" || rc=$?
    if [ "$rc" = 1 ] && [ -z "$PR_HOST" ] && [ -z "$PR_OWNER" ] && [ -z "$PR_REPO" ]; then
        pass "refuses [$url]"
    else
        fail "[$url]: rc $rc, host [$PR_HOST] owner [$PR_OWNER] repo [$PR_REPO]; wanted a refusal"
    fi
}

# --- what gh answers, on github.com and elsewhere ------------------------------
accepts "https://github.com/acme/widgets/pull/7" github.com acme widgets
accepts "https://ghe.example.com/acme/widgets/pull/7" ghe.example.com acme widgets
accepts "https://octo.ghe.com/acme/widgets/pull/1051" octo.ghe.com acme widgets
accepts "https://ghe.example.com:8443/acme/widgets/pull/7" ghe.example.com:8443 acme widgets
accepts "https://github.com/acme/.github/pull/7" github.com acme .github
accepts "https://github.com/my-org/my_repo.js/pull/7" github.com my-org my_repo.js
accepts "https://GitHub.com/Acme/Widgets/pull/7" GitHub.com Acme Widgets

# --- a suffix after the number is ignored --------------------------------------
accepts "https://github.com/acme/widgets/pull/7/" github.com acme widgets
accepts "https://github.com/acme/widgets/pull/7/files" github.com acme widgets
accepts "https://github.com/acme/widgets/pull/7?w=1" github.com acme widgets
accepts "https://github.com/acme/widgets/pull/7#discussion_r1" github.com acme widgets

# --- anything else is refused ---------------------------------------------------
refuses ""
refuses "not a url"
refuses "no pull requests found for branch \"impl/x\""
refuses "http://github.com/acme/widgets/pull/7"
refuses "ssh://github.com/acme/widgets/pull/7"
refuses "https:///acme/widgets/pull/7"
refuses "https://u@github.com/acme/widgets/pull/7"
refuses "https://-github.com/acme/widgets/pull/7"
refuses "https://github.com:/acme/widgets/pull/7"
refuses "https://github.com/acme/widgets/issues/7"
refuses "https://github.com/acme/widgets/pull/"
refuses "https://github.com/acme/widgets/pull/abc"
refuses "https://github.com/acme/widgets/pull/7x"
refuses "https://github.com/acme/widgets/pulls"
refuses "https://github.com/acme/pull/7"
refuses "https://github.com//widgets/pull/7"
refuses "https://github.com/acme//pull/7"
refuses "https://github.com/../widgets/pull/7"
refuses "https://github.com/acme/../pull/7"
refuses "https://github.com/acme/./pull/7"
# A server under a path prefix: <prefix> would otherwise be read as the owner.
refuses "https://ghe.example.com/prefix/acme/widgets/pull/7"
refuses "https://github.com/acme/widgets/tree/main/pull/7"
refuses " https://github.com/acme/widgets/pull/7"
refuses "https://github.com/acme/widgets/pull/7 "
refuses "https://github.com/ac me/widgets/pull/7"
refuses "https://github.com/acme/widgets/pull/7"$'\r'
# Two URLs, one per line, are not one pull request.
refuses "https://github.com/acme/widgets/pull/7
https://github.com/acme/widgets/pull/8"
refuses "https://github.com/acme/widgets/pull/7#
https://ghe.example.com/other/repo/pull/8"

# --- no argument at all ----------------------------------------------------------
rc=0
pr_url_parse || rc=$?
if [ "$rc" = 1 ] && [ -z "$PR_HOST" ]; then pass "no argument is refused under set -u"
else fail "no argument: rc $rc, host [$PR_HOST]"; fi

echo
echo "pr-url_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" = 0 ]
