#!/usr/bin/env bash
# ci-relevant.sh -- ci_passing's read of the checks a change can reach.
# Part of the work-on skill
#
# work-on.md's ci_passing gate runs this first. It waits on the relevant set
# rather than on every check: the hosted twins of the commands the change
# selects and the map's always_required list, read from the merge-base's
# verification map and again from the current default branch's on every
# read (run-verification.sh --relevant, which keeps the union and records it
# as the koto key relevant_checks.txt).
#
# Usage: ci-relevant.sh --session <s> [--ci-wait <all|>] [<pr>]
#
#   <pr>  the pull request, as pr-checks.sh takes it (a number, a URL or a
#         branch); without it, the current branch's.
#
# 1. run-verification.sh --relevant. `off` (no always_required at the
#    merge-base, CI_WAIT=all, or nothing relevant) is exit 3, and the gate
#    waits on every check as it did before the filter existed. A failure of
#    that read is exit 2, which the gate treats the same way.
# 2. pr-checks.sh <pr> --relevant <set> --json name,workflow,bucket,link. The
#    set is green when it lists at least one check and every one is in the
#    bucket `pass` (RELEVANT_GREEN_JQ). A relevant check that is skipped is
#    not passed: a twin like skill-gate (ubuntu-latest) `needs:` its slices,
#    so a failed slice leaves it skipped. A relevant check not reported yet
#    is pending. Not green is exit 1, each relevant check not passed named on
#    stderr, and so is a check read that fails.
# 3. Green: the checks outside the set that failed are noted, then exit 0.
#    A failing check outside the set never holds the green edge. Each one
#    gets one pull request comment per head, carrying only its name and its
#    link, both neutral (verification-route.sh's VR_NEUTRAL_JQ: control
#    characters, backticks, @, #, <, >, [ and ] can't mention, reference,
#    link or render anything), and a line in the koto key
#    ci_outside_failures.txt:
#
#      <head>\t<workflow>\t<check name>\t<link>\t<posted|not-posted>
#
#    (all neutral). A check whose line at this head says `posted` is never
#    commented on again; a `not-posted` one is tried again on the next green
#    read at the head. The run's final report names every check the key
#    lists. A failure anywhere in this step is said on stderr and leaves the
#    exit 0: the notice never holds the run.
#
# Exit codes: 0 green; 1 not green; 2 usage or a failed relevant read; 3 the
# filter is off. The gate waits on every check for anything but 0 and 1.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

PROG=ci-relevant
OUTSIDE_KEY=ci_outside_failures.txt
# Green for the relevant set: at least one check, every one passed.
RELEVANT_GREEN_JQ='length > 0 and all(.[]; .bucket == "pass")'

usage() { echo "$PROG: $*" >&2; echo "usage: ci-relevant.sh --session <s> [--ci-wait <all|>] [<pr>]" >&2; exit 2; }
note() { echo "$PROG: $*" >&2; }

SESSION="" CI_WAIT_V="" SEL=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] && [ -z "$SESSION" ] || usage "--session needs one value"; SESSION=$2; shift 2 ;;
        --ci-wait) [ $# -ge 2 ] || usage "--ci-wait needs a value"; CI_WAIT_V=$2; shift 2 ;;
        -*) usage "unknown flag [$1]" ;;
        *) [ -z "$SEL" ] || usage "a second pull request [$1]"; SEL=$1; shift ;;
    esac
done
[ -n "$SESSION" ] || usage "--session is required"

HERE=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ci-relevant.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

# ---- 1. the relevant set -----------------------------------------------------
"$HERE/run-verification.sh" --relevant --session "$SESSION" --ci-wait "$CI_WAIT_V" >"$TMP/set" \
    || { note "the relevant set could not be read, so the gate waits on every check"; exit 2; }
if [ "$(cat "$TMP/set")" = off ]; then
    exit 3
fi

# ---- 2. the relevant checks ---------------------------------------------------
"$HERE/pr-checks.sh" ${SEL:+"$SEL"} --relevant "$TMP/set" --json name,workflow,bucket,link >"$TMP/rel.json" \
    || { note "the relevant checks could not be read"; exit 1; }
GREEN=$(jq -r "$RELEVANT_GREEN_JQ" "$TMP/rel.json") || { note "the relevant checks are not a list"; exit 1; }
if [ "$GREEN" != true ]; then
    jq -r '.[] | select(.bucket != "pass") | "\(.name) (\(.workflow)): \(.bucket)"' "$TMP/rel.json" \
        | sed "s/^/$PROG: relevant, not passed: /" >&2
    exit 1
fi

# ---- 3. the failing checks outside the set ------------------------------------
# notice: never changes the exit; every failure is said and returns.
notice() {
    local head pr_url n i check name wf link status
    "$HERE/pr-checks.sh" ${SEL:+"$SEL"} --outside "$TMP/set" --json name,workflow,bucket,link >"$TMP/out.json" \
        || { note "the checks outside the relevant set could not be read, so none is noted"; return 0; }
    # shellcheck source=verification-route.sh
    . "$HERE/verification-route.sh" || { note "cannot load verification-route.sh, so no outside check is noted"; return 0; }
    jq -c "$VR_NEUTRAL_JQ"' [.[] | select(.bucket == "fail")
        | {name: (.name // "" | neutral), workflow: (.workflow // "" | neutral), link: (.link // "" | neutral)}]' \
        "$TMP/out.json" >"$TMP/failed.json" || { note "the outside checks could not be read"; return 0; }
    [ "$(jq 'length' "$TMP/failed.json")" -gt 0 ] || return 0

    gh pr view ${SEL:+"$SEL"} --json headRefOid,url --jq '[.headRefOid, .url] | @tsv' </dev/null >"$TMP/pr" \
        || { note "the pull request could not be read, so no outside check is noted"; return 0; }
    IFS=$'\t' read -r head pr_url <"$TMP/pr"
    [[ ${head:-} =~ ^[0-9a-f]{40}$ ]] || { note "the pull request's head [${head:-}] is not a sha, so no outside check is noted"; return 0; }

    : >"$TMP/key"
    koto context exists "$SESSION" "$OUTSIDE_KEY"
    case $? in
        0) koto context get "$SESSION" "$OUTSIDE_KEY" >"$TMP/key" \
               || { note "could not read $OUTSIDE_KEY, so no outside check is noted"; return 0; } ;;
        1) ;;
        *) note "could not ask koto for $OUTSIDE_KEY, so no outside check is noted"; return 0 ;;
    esac
    jq -Rn '[inputs | select(length > 0) | split("\t")]' "$TMP/key" >"$TMP/key.json" \
        || { note "$OUTSIDE_KEY could not be read"; return 0; }

    # The checks still to post: no `posted` line at this head.
    jq -c --arg h "$head" --slurpfile k "$TMP/key.json" '
        [.[] | . as $c | select(any($k[0][]; .[0] == $h and .[1] == $c.workflow and .[2] == $c.name and .[4] == "posted") | not)]' \
        "$TMP/failed.json" >"$TMP/todo.json" || { note "the outside checks could not be compared"; return 0; }
    n=$(jq 'length' "$TMP/todo.json")
    : >"$TMP/new"
    i=0
    while [ "$i" -lt "$n" ]; do
        check=$(jq -c --argjson i "$i" '.[$i]' "$TMP/todo.json")
        name=$(jq -r '.name' <<<"$check")
        wf=$(jq -r '.workflow' <<<"$check")
        link=$(jq -r '.link' <<<"$check")
        {
            printf 'A check outside the ones this change can reach failed. This run did not wait on it.\n\n'
            printf '`%s` `%s`\n' "$name" "$link"
        } >"$TMP/body"
        status=not-posted
        if gh pr comment ${SEL:+"$SEL"} --body-file "$TMP/body" </dev/null >"$TMP/comment.out" 2>"$TMP/comment.err"; then
            status=posted
        else
            note "the comment on $name could not be posted: $(head -n 1 "$TMP/comment.err")"
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$head" "$wf" "$name" "$link" "$status" >>"$TMP/new"
        note "outside the relevant set, failed: $name ($link), comment $status on ${pr_url:-the pull request}"
        i=$((i + 1))
    done
    [ -s "$TMP/new" ] || return 0
    # The key: every line kept but the ones just retried, then the new ones.
    jq -Rn '[inputs | select(length > 0) | split("\t")]' "$TMP/new" >"$TMP/new.json" \
        || { note "the new lines could not be read"; return 0; }
    jq -r --slurpfile n "$TMP/new.json" '
        [.[] | . as $l | select(any($n[0][]; .[0] == $l[0] and .[1] == $l[1] and .[2] == $l[2]) | not)] + $n[0]
        | .[] | join("\t")' "$TMP/key.json" >"$TMP/key.next" \
        || { note "$OUTSIDE_KEY could not be rebuilt"; return 0; }
    koto context add "$SESSION" "$OUTSIDE_KEY" --from-file "$TMP/key.next" >/dev/null \
        || note "could not write $OUTSIDE_KEY"
    return 0
}
notice
exit 0
