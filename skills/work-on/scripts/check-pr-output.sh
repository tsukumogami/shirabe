#!/usr/bin/env bash
# check-pr-output.sh -- does the pull request a run produced pass the output
# rules, and which pull request does the run own?
# Part of the work-on skill
#
# A gate script: koto runs it as a command gate and routes on its exit status.
# Each mode calls a check that already ships, unchanged, and translates its
# result:
#
#   --pr-body [--owned <owned-pr.sh arguments>]
#       Reads the pull request's title and body with `gh pr view --json
#       title,body` and runs
#       `shirabe validate --pr-body <file> --pr-title <title> --format json`
#       (references/pr-body-conformance.md, PB1 to PB4). The title reaches the
#       validator as one argument and the body as a mktemp file; nothing in
#       either is evaluated. Without --owned the pull request is the checked-out
#       branch's; with --owned it is the one owned-pr.sh resolves from the
#       arguments that follow, and anything but exactly one owned pull request
#       is exit 2.
#       Validator exit 0 -> 0, 2 -> 1, and 1, 3, 4 -> 2.
#
#   --owned-pr <owned-pr.sh arguments>
#       Runs skills/execute/scripts/owned-pr.sh with the arguments, bounded in
#       time. A routing gate: its non-zero exits are answers, not violations,
#       so it never prints a finding. On exit 0 the URL is the only stdout.
#         owned-pr.sh exit 0 with one URL            -> 0
#         owned-pr.sh exit 0 with no output, 3, 4, 5 -> 3 (no single owned PR)
#         owned-pr.sh exit 2, 64, a timeout, or anything else -> 2
#       `--take-over` is refused: a gate never writes to GitHub.
#
# owned-pr.sh is always the execute skill's copy beside this one
# (skills/execute/scripts/owned-pr.sh under the same plugin root), never one
# found on PATH. A gate runs with the PATH recorded when the session was
# created, so a PATH lookup let whatever owned-pr.sh came first there -- a
# stale install, another checkout -- answer which pull request a run owns, and
# the gate would route on its answer. CHECK_PR_OUTPUT_OWNED_PR, set to a path,
# replaces the copy; it is the test suite's seam, and koto's cleared
# environment never passes it to a gate.
#
# Exit status (the gate scripts' shared convention):
#   0  the output passes (--owned-pr: exactly one owned pull request)
#   1  at least one violation; one `::koto-finding::` line per violation on
#      stdout (--pr-body only)
#   2  could not decide: a usage error, a missing tool, a read that failed, a
#      validator that failed to run
#   3  --owned-pr only: the lookup answered, and the answer is not one PR
#
# --pr-body findings are koto's finding shape, built with jq, with the rule
# chosen by the validator's message:
#   PB1 (title)              pr-body/conventional-title
#   PB2 (separator, Part 1)  pr-body/one-separator
#   PB3 (AI attribution)     pr-body/no-ai-trailer
#   PB4 (heading in Part 1)  pr-body/no-heading-in-part1
#   anything else            pr-body/conformance
# The rules are entries of references/rule-registry.json; scripts/lib/rule-findings.sh
# resolves each one's reference and summary through scripts/rule-registry.sh.
#
# Written for the bash 3.2 floor and deliberately without `set -e`.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
RULE_IDS="pr-body/conventional-title pr-body/one-separator pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/conformance"
# Seconds owned-pr.sh may run. koto stops a gate command at 30 seconds; this
# stays under it so the answer is this script's 2, not koto's timeout.
OWNED_PR_TIMEOUT=${CHECK_PR_OUTPUT_OWNED_TIMEOUT:-20}
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'

usage() {
    cat >&2 <<'EOF'
Usage: check-pr-output.sh --pr-body [--owned <owned-pr.sh arguments>]
       check-pr-output.sh --owned-pr <owned-pr.sh arguments>

--pr-body:  exit 0 conformant, 1 a violation (findings on stdout), 2 could not decide.
--owned-pr: exit 0 one owned PR (its URL on stdout), 3 not exactly one, 2 could not decide.
EOF
}

undecided() {
    echo "check-pr-output: $*" >&2
    exit 2
}

# shellcheck source=../../../scripts/lib/rule-findings.sh
. "$HERE/../../../scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"

require_rules() {
    rf_require "$@"
}

VIOLATIONS=0

# finding <rule_id> <detail>
finding() {
    VIOLATIONS=$((VIOLATIONS + 1))
    rf_finding "$1" "$2"
}

WORK=""
cleanup() { [ -z "$WORK" ] || rm -rf "$WORK"; return 0; }
trap cleanup EXIT
make_work() {
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-pr-output.XXXXXX") \
        || undecided "cannot create a temporary directory"
}

owned_pr_script() {
    if [ -n "${CHECK_PR_OUTPUT_OWNED_PR:-}" ]; then
        printf '%s\n' "$CHECK_PR_OUTPUT_OWNED_PR"
    else
        printf '%s\n' "$HERE/../../execute/scripts/owned-pr.sh"
    fi
}

# lookup <args>...: runs owned-pr.sh bounded in time and maps its answer.
# Sets URL on 0; returns 0, 3 or 2 as --owned-pr documents.
URL=""
lookup() {
    for a in "$@"; do
        [ "$a" != "--take-over" ] || { echo "check-pr-output: --take-over is refused; a gate never writes" >&2; return 2; }
    done
    script=$(owned_pr_script)
    [ -x "$script" ] || { echo "check-pr-output: owned-pr.sh not found at $script" >&2; return 2; }
    "$script" "$@" > "$WORK/owned.out" 2> "$WORK/owned.err" < /dev/null &
    pid=$!
    # Job control and a sleep loop rather than GNU timeout, which the macOS
    # floor lacks. Five polls a second.
    ticks=0
    limit=$((OWNED_PR_TIMEOUT * 5))
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge "$limit" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            echo "check-pr-output: owned-pr.sh did not answer within ${OWNED_PR_TIMEOUT}s" >&2
            return 2
        fi
        sleep 0.2
        ticks=$((ticks + 1))
    done
    wait "$pid"
    rc=$?
    out=$(cat "$WORK/owned.out")
    case "$rc" in
        0)
            if [ -z "$out" ]; then
                echo "check-pr-output: owned-pr.sh found no owned pull request" >&2
                return 3
            fi
            if [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] \
                && printf '%s' "$out" | grep -Eq "$RE_URL"; then
                URL=$out
                return 0
            fi
            echo "check-pr-output: owned-pr.sh exited 0 with output that is not one URL" >&2
            return 2
            ;;
        3|4|5)
            echo "check-pr-output: owned-pr.sh exited $rc: not exactly one owned pull request. $(tail -n 1 "$WORK/owned.err")" >&2
            return 3
            ;;
        *)
            echo "check-pr-output: owned-pr.sh exited $rc: $(tail -n 1 "$WORK/owned.err")" >&2
            return 2
            ;;
    esac
}

# rule_for_message <message>: the pr-body rule the validator's message names.
# PB4's message mentions the separator too, so it is matched first.
rule_for_message() {
    case "$1" in
        *"markdown section heading"*) echo pr-body/no-heading-in-part1 ;;
        *"AI-attribution"*) echo pr-body/no-ai-trailer ;;
        "PR title "*) echo pr-body/conventional-title ;;
        *"\`---\` separator"*) echo pr-body/one-separator ;;
        *) echo pr-body/conformance ;;
    esac
}

check_pr_body() {
    require_rules pr-body/conventional-title pr-body/one-separator \
        pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/conformance
    for tool in gh jq shirabe; do
        command -v "$tool" >/dev/null 2>&1 || undecided "$tool is not on PATH"
    done
    make_work
    if [ "$OWNED" = 1 ]; then
        lookup "$@"
        rc=$?
        [ "$rc" -eq 0 ] || undecided "--owned: no single owned pull request to read (lookup answered $rc)"
        gh pr view "$URL" --json title,body > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null \
            || undecided "gh pr view $URL failed: $(tail -n 1 "$WORK/gh.err")"
    else
        gh pr view --json title,body > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null \
            || undecided "gh pr view failed: $(tail -n 1 "$WORK/gh.err")"
    fi
    jq -e 'type == "object" and (.title | type == "string") and (.body | type == "string")' \
        "$WORK/pr.json" >/dev/null || undecided "gh pr view did not return a title and a body"
    title=$(jq -r '.title' "$WORK/pr.json")
    jq -j '.body' "$WORK/pr.json" > "$WORK/body.md"

    shirabe validate --pr-body "$WORK/body.md" --pr-title "$title" --format json \
        > "$WORK/out" 2> "$WORK/err" < /dev/null
    rc=$?
    case "$rc" in
        0)
            echo "check-pr-output: the PR title and body conform" >&2
            exit 0
            ;;
        2) ;;
        *) undecided "shirabe validate --pr-body exited $rc: $(tail -n 1 "$WORK/err")" ;;
    esac
    if jq -r '.findings[].message' "$WORK/out" > "$WORK/messages" \
        && [ -s "$WORK/messages" ]; then
        while IFS= read -r msg; do
            [ -n "$msg" ] || continue
            finding "$(rule_for_message "$msg")" "$msg"
        done < "$WORK/messages"
    fi
    if [ "$VIOLATIONS" -eq 0 ]; then
        finding pr-body/conformance \
            "shirabe validate --pr-body reported violations it did not list; run it on the PR body for the detail"
    fi
    echo "check-pr-output: $VIOLATIONS PR title/body violation(s)" >&2
    exit 1
}

check_owned_pr() {
    [ $# -gt 0 ] || { usage; exit 2; }
    make_work
    lookup "$@"
    rc=$?
    [ "$rc" -ne 0 ] || printf '%s\n' "$URL"
    exit "$rc"
}

[ $# -ge 1 ] || { usage; exit 2; }
MODE=$1
shift
OWNED=0
case "$MODE" in
    --pr-body)
        if [ $# -gt 0 ]; then
            [ "$1" = --owned ] || { usage; exit 2; }
            shift
            [ $# -gt 0 ] || { usage; exit 2; }
            OWNED=1
        fi
        check_pr_body "$@"
        ;;
    --owned-pr) check_owned_pr "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac
