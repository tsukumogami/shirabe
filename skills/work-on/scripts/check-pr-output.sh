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
#       `shirabe validate --pr-body <file> --pr-title <title> --format json
#        --writing-style <rules>`
#       (references/pr-body-conformance.md, PB1 to PB5). <rules> is always this
#       plugin's own skills/writing-style/rules.yaml, resolved from this
#       script's location, never one from the repository under review or from
#       SHIRABE_RULES, so PB5's banned words are the ones the plugin shipped.
#       The title reaches the validator as one argument and the body as a
#       mktemp file; nothing in either is evaluated. Without --owned the pull
#       request is the checked-out branch's; with --owned it is the one
#       owned-pr.sh resolves from the
#       arguments that follow, and anything but exactly one owned pull request
#       is exit 2.
#       Every exit 2 after the rules resolve prints one finding naming why,
#       so koto never credits the failure to the gate's name:
#         pr-body/pr-missing    no pull request yet (gh finds none for the
#                               branch, or owned-pr.sh answers 3)
#         pr-body/body-missing  gh returned no title or no body
#         pr-body/read-failed   anything else: a gh read or lookup that
#                               failed, a missing tool, missing writing-style
#                               rules, a validator that failed to run
#       The first two also print `::koto-not-ready::` on stdout, the
#       telemetry marker for a gate run before its input exists; read-failed
#       doesn't. Neither changes the exit.
#       Validator exit 0 -> 0, and 1, 3, 4 -> 2. Exit 2 prints one finding
#       per listed message, at its rule's stage, and maps to 1 when one of
#       them is of a rule at `block`, else 0. An exit 2 that lists no message
#       prints the pr-body/conformance finding instead. An installed shirabe
#       older than --writing-style rejects the flag with exit 1, so the gate
#       holds (2) and says to upgrade; preflight (requires.tsv) reports the
#       same gap when the skill loads.
#       Unless the repository opts in to workflow content in its PR bodies
#       (scripts/pr-workflow-content.sh prints include for the work tree this
#       runs in), the body is also scanned, outside fenced code, for workflow
#       records (references/pr-body-conformance.md, "Workflow content"): a
#       `## Review panel` heading, a Seat/Model/Run/Verdict/Reviewed head
#       table, a `Plan:` or `Roadmap:` line, an `Implements` line naming a
#       PLAN- or ROADMAP- file. Each is a pr-body/workflow-content finding, at
#       that rule's stage, whatever the validator answered.
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
#   --deferral-record --reason <reason> [--reason <reason>]...
#                     [--public-reason <text>]
#                     [--body] [--owned <owned-pr.sh arguments>]
#       For a run that deferred verification to hosted CI (work-on.md's
#       VERIFICATION=hosted-ci, #1012). In a repository that doesn't opt in
#       to workflow content (scripts/pr-workflow-content.sh prints omit, the
#       default) it passes (0) without reading GitHub: the deferral is
#       recorded in the run's context as verification_deferral, and the body
#       says in plain terms that hosted CI verified the change. In one that
#       opts in, or with --body (a coordinated node PR, whose body carries the
#       record whatever the setting), it reads the pull request body with
#       `gh pr view --json body` and checks that it records the deferral, in
#       three parts:
#         a line saying "local verification did not run"
#         for each <reason>, a line reading exactly `Reason: <reason>`
#         a line saying "hosted CI is the build of record"
#       The two phrases are matched without regard to case, anywhere in the
#       body. Each reason is matched exactly, since it is the one its run was
#       started with, and as a whole line: a reason that only appears inside
#       other text (a short one inside the build-of-record phrase) or that
#       starts a longer reason's line does not count. A CRLF or a lone CR in
#       the body is a line break, as GitHub renders it. A reason must be one
#       line with more than spaces in it.
#       --public-reason <text> is a wording of the deferral for a public
#       reader, recorded for a coordinated node in its run record
#       (run/node/<node>'s public_reason): a body with a line reading exactly
#       `Reason: <text>` passes the reason part in place of the verbatim
#       lines, which then need not appear. A body with the verbatim lines
#       still passes, and one with neither fails, so a deferral is never
#       silent. The other two parts are required either way. The text is held
#       to the same one-line, more-than-spaces rule as a reason. Without
#       --owned the pull request is the checked-out branch's (/work-on's
#       pr_creation, one reason); with --owned it is the one owned-pr.sh
#       resolves, as --pr-body --owned reads it (/execute's shared PR, whose
#       children may each have deferred, through shared-deferral-record.sh).
#         all present                                -> 0
#         any missing                                -> 1, one stderr line each
#                                                       (with --public-reason
#                                                       and no line of either
#                                                       kind, one more naming
#                                                       its line)
#         an empty reason or public wording, no single owned pull request,
#         gh missing or failing, no body             -> 2
#       It prints no ::koto-finding:: line. Like pr_creation's closing
#       keyword, the obligation is the template's own, with no registry rule
#       behind it, and the stderr lines say what is missing.
#
#   --rerun-record --session <name> [--session <name>]...
#                  [--print | --owned <owned-pr.sh arguments>]
#   --rerun-record --line <line> [--line <line>]...
#                  [--owned <owned-pr.sh arguments>]
#       For a run that re-ran a failed verification command at the same head
#       (run-verification.sh --archive). Before anything else it reads each
#       session's `verification_attempts` context key, the ledger: one JSON
#       line per archived attempt, with its attempt number, head, merge_base,
#       reason, status and commands[] (id, exit_status, timed_out). A key koto
#       reports missing (`koto context exists` exiting 1 with nothing on
#       stdout) is an empty ledger; any other failure, a failing get, or a line
#       that isn't a ledger line is a failed read (2), never an empty ledger.
#       When every session's ledger is empty it passes (0) without reading
#       GitHub, so a run that never re-ran sees no change. Otherwise it reads
#       each such session's `verification_results.json` (missing is fine), then
#       the pull request body with `gh pr view --json body`, and checks the
#       body's Verification section (a ## or ### heading named Verification,
#       up to the next heading of the same or a higher level, outside fenced
#       code, each CRLF or lone CR a line break) for one re-run line per
#       archived attempt:
#
#         Re-run attempt <n> at `<head>`: `<id>` failed[, `<id>` timed out]; reason `<reason>`; attempt <n+1> passed.
#
#       A line belongs to attempt n at head H when it starts (after an
#       optional `- ` or `* ` list marker) with `Re-run attempt <n>`, without
#       regard to case, and holds a run of 7 or more hex characters that
#       starts H. In it:
#         - each command of the attempt with a numeric non-zero exit_status or
#           timed_out true appears as a code span holding its id;
#         - the reason, with backticks removed, runs of whitespace made one
#           space and the ends trimmed, appears as a code span;
#         - when the next result is known, `attempt <n+1> <word>` appears,
#           without regard to case. The next result is the ledger line for
#           attempt n+1 at the same head and merge-base, or, for the last
#           archived attempt there, verification_results.json when its head
#           and merge-base match and its logs aren't the archived attempt's
#           own. <word> is `passed` (status done, every command exit 0, none
#           timed out), `timed out` (one timed out) or `failed`. With neither,
#           only the ids and the reason are asked for;
#         - no absolute path (a token starting / or ~/ after the line's start,
#           whitespace, a backtick, (, [, =, or a quote, or a drive-letter
#           path): log paths stay out of the body, which may be public.
#       An id or the reason present in the line but outside a code span is
#       its own refusal, apart from one the line doesn't name at all. Several
#       lines may claim one attempt; one that passes every part is enough.
#       With more than one --session, each message names the session. The
#       workflow-content setting doesn't change this check. Without --owned
#       the pull request is the checked-out branch's (/work-on's
#       pr_creation); with --owned it is the one owned-pr.sh resolves, as
#       --deferral-record --owned reads it (/execute's shared PR, through
#       shared-rerun-record.sh).
#       --print, with --session and no --owned, reads the ledgers as above
#       and prints the line each archived attempt asks for, one per line, the
#       same line once, and exits 0 without reading GitHub (nothing printed
#       when no ledger holds a line):
#         Re-run attempt <n> at `<12 hex of head>`: `<id>` failed[, `<id>` timed out]; reason `<reason>`[; attempt <n+1> <word>].
#       with each part after the colon left out when the attempt has none
#       (no failed id, an empty reason, no next result). /execute records
#       these lines for a coordinated node (run/node/<node>'s reruns,
#       through shared-rerun-record.sh) and writes them into the node PR's
#       body.
#       --line <line>, once per line, gives the re-runs as those recorded
#       lines in place of the sessions: no koto read at all. Each line is
#       read back in the shape --print writes (the attempt, 7 to 40 hex of
#       its head, and the ids, the reason and the next attempt's word it
#       carries), and the body is checked against it as against a ledger's
#       attempt: a body line claiming that attempt at that head, with each id
#       and the reason in code spans and the next word when the line gives
#       one. A line in another shape, or one spanning lines, is 2. It can't
#       be given with --session or --print.
#         every attempt has its line                 -> 0
#         a line missing or wrong                    -> 1, one stderr line each
#         a bad session name, koto or gh missing or
#         failing, a failed ledger read, no single
#         owned pull request, no body                -> 2
#       It prints no ::koto-finding:: line, like --deferral-record.
#
#   --hosted-record --session <s>
#       For a run that took the hosted-of-record route (the koto key
#       hosted_of_record, written by verification-route.sh --record). No key,
#       or a key whose head is not HEAD (a stale key is no record), passes (0)
#       without reading GitHub: such a run opens its pull request as today.
#       Otherwise it reads `gh pr view --json isDraft,body,url,headRefOid` and
#       requires a draft whose body carries exactly one `Hosted of record:`
#       line per recorded check, naming the check id, the record's head and
#       each declared job (verification-route.sh's vr_body_check, sourced
#       here, the same check the route's ready gate runs). Only lines that
#       start with the prefix count, so the reason line can't satisfy or forge
#       one.
#         a draft with every line                    -> 0
#         not a draft, or a line missing or wrong    -> 1, one stderr line each
#         koto or gh failing, an unreadable key      -> 2
#       No ::koto-finding:: line: as with --deferral-record, the obligation is
#       the template's own.
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
#   1  at least one violation of a rule at the `block` stage; one
#      `::koto-finding::` line per violation on stdout, and a line on stderr
#      saying how to dispute one (--pr-body only). Findings of rules below
#      block print at their stage's level and leave the exit at 0.
#      --deferral-record: the body does not record the deferral (stderr
#      only, no finding)
#      --rerun-record: the body lacks a re-run line, or one is wrong (stderr
#      only, no finding)
#      --hosted-record: not a draft, or a body line missing or wrong (stderr
#      only, no finding)
#   2  could not decide: a usage error, a missing tool, a read that failed
#      (a koto context read included), a validator that failed to run
#   3  --owned-pr only: the lookup answered, and the answer is not one PR
#
# --pr-body findings are koto's finding shape, built with jq, with the rule
# chosen by the validator's message:
#   PB1 (title)              pr-body/conventional-title
#   PB2 (separator, Part 1)  pr-body/one-separator
#   PB3 (AI attribution)     pr-body/no-ai-trailer
#   PB4 (heading in Part 1)  pr-body/no-heading-in-part1
#   PB5 (banned word)        pr-body/banned-word
#   anything else            pr-body/conformance
# and this script's own scan, pr-body/workflow-content, and its
# could-not-decide rules above. Beside each finding the rule library prints
# a ::koto-rule-delivered:: marker (scripts/lib/rule-findings.sh). Every line
# on stdout starts with one of the library's markers or ::koto-not-ready::;
# text from the pull request reaches stdout only inside a finding's JSON, so
# a body line can't start a marker.
# The rules are entries of references/rule-registry.json; scripts/lib/rule-findings.sh
# resolves each one's reference, summary and stage through scripts/rule-registry.sh.
#
# Written for the bash 3.2 floor and deliberately without `set -e`.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
RULE_IDS="pr-body/conventional-title pr-body/one-separator pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/banned-word pr-body/conformance pr-body/workflow-content pr-body/pr-missing pr-body/body-missing pr-body/read-failed"
# Seconds owned-pr.sh may run. koto stops a gate command at 30 seconds; this
# stays under it so the answer is this script's 2, not koto's timeout.
# CHECK_PR_OUTPUT_OWNED_TIMEOUT is the tests' seam, and also how
# /execute's shared-deferral-record.sh cuts the limit to the time it has
# left after reading its children.
OWNED_PR_TIMEOUT=${CHECK_PR_OUTPUT_OWNED_TIMEOUT:-20}
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'

usage() {
    cat >&2 <<'EOF'
Usage: check-pr-output.sh --pr-body [--owned <owned-pr.sh arguments>]
       check-pr-output.sh --owned-pr <owned-pr.sh arguments>
       check-pr-output.sh --deferral-record --reason <reason> [--reason <reason>]... [--public-reason <text>] [--body] [--owned <owned-pr.sh arguments>]
       check-pr-output.sh --rerun-record --session <name> [--session <name>]... [--print | --owned <owned-pr.sh arguments>]
       check-pr-output.sh --rerun-record --line <line> [--line <line>]... [--owned <owned-pr.sh arguments>]
       check-pr-output.sh --hosted-record --session <s>

--pr-body:        exit 0 conformant, 1 a violation (findings on stdout), 2 could not decide.
--owned-pr:        exit 0 one owned PR (its URL on stdout), 3 not exactly one, 2 could not decide.
--deferral-record: exit 0 the body records the deferral, 1 it does not, 2 could not decide.
--rerun-record:    exit 0 no re-run, or the body records each one, 1 it does not, 2 could not decide.
--hosted-record:   exit 0 no record at HEAD, or a draft with its lines; 1 not a draft or a line wrong; 2 could not decide.
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

# finding <rule_id> <detail>
finding() {
    rf_finding "$1" "$2"
}

# pr_undecided <rule_id> <detail>: --pr-body's could-not-decide, once its
# rules are resolved. Prints the reason on stderr and the rule's finding on
# stdout, so koto credits the failure to a pr-body rule rather than to the
# gate's name; for pr-body/pr-missing and pr-body/body-missing, whose input
# doesn't exist yet, also the ::koto-not-ready:: marker. The exit stays 2. It
# must run in the script's main shell, never inside $(...), where its stdout
# would be captured.
pr_undecided() {
    echo "check-pr-output: $2" >&2
    finding "$1" "$2"
    case "$1" in
        pr-body/pr-missing|pr-body/body-missing) printf '::koto-not-ready::\n' ;;
    esac
    exit 2
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
                && grep -Eq "$RE_URL" <<<"$out"; then
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
# PB5's messages carry a fixed prefix and can name the title, so they are
# matched first; PB4's message mentions the separator too, so it comes next.
rule_for_message() {
    case "$1" in
        "[PB5] "*) echo pr-body/banned-word ;;
        *"markdown section heading"*) echo pr-body/no-heading-in-part1 ;;
        *"AI-attribution"*) echo pr-body/no-ai-trailer ;;
        "PR title "*) echo pr-body/conventional-title ;;
        *"\`---\` separator"*) echo pr-body/one-separator ;;
        *) echo pr-body/conformance ;;
    esac
}

# workflow_content: pr-workflow-content.sh's answer for the
# repository this script runs in (the work tree holding the current
# directory), `include` or `omit`; any failure is undecided.
workflow_content() {
    local v
    v=$(bash "$HERE/../../../scripts/pr-workflow-content.sh" 2>"$WORK/pwc.err" </dev/null) \
        || undecided "scripts/pr-workflow-content.sh failed: $(tail -n 1 "$WORK/pwc.err")"
    case "$v" in
        include|omit) printf '%s\n' "$v" ;;
        *) undecided "scripts/pr-workflow-content.sh printed [$v], not include or omit" ;;
    esac
}

# workflow_records <body-file>: one line per workflow record the body carries
# outside fenced code (references/pr-body-conformance.md, "Workflow
# content"), naming it and its line. Shapes only, never words.
workflow_records() {
    awk '
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        {
            line = $0
            sub(/\r$/, "", line)
            t = line
            sub(/^[ \t]+/, "", t)
            sub(/[ \t]+$/, "", t)
            l = tolower(t)
            if (l == "## review panel") {
                printf "a `## Review panel` heading (line %d)\n", NR; next
            }
            if (substr(t, 1, 1) == "|") {
                c = l
                gsub(/`/, "", c)
                gsub(/[ \t]*\|[ \t]*/, "|", c)
                if (c == "|seat|model|run|verdict|reviewed head|") {
                    printf "a Seat, Model, Run, Verdict, Reviewed head table (line %d)\n", NR; next
                }
            }
            if (l ~ /^(plan|roadmap):/) {
                printf "a `%s` line (line %d)\n", substr(t, 1, index(t, ":")), NR; next
            }
            if (l ~ /^implements[ \t]/ && t ~ /(PLAN|ROADMAP)-[^ \t]*\.md/) {
                printf "an `Implements` line naming a PLAN or ROADMAP file (line %d)\n", NR; next
            }
        }' "$1"
}

check_pr_body() {
    require_rules pr-body/conventional-title pr-body/one-separator \
        pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/banned-word \
        pr-body/conformance pr-body/workflow-content \
        pr-body/pr-missing pr-body/body-missing pr-body/read-failed
    # From here every could-not-decide names its rule (pr_undecided):
    # pr-body/pr-missing when there is no pull request to read yet,
    # pr-body/body-missing when it has no title or body, and
    # pr-body/read-failed for anything else that stops the check.
    for tool in gh jq shirabe; do
        command -v "$tool" >/dev/null 2>&1 || pr_undecided pr-body/read-failed "$tool is not on PATH"
    done
    rules_dir=$(cd "$HERE/../../writing-style" 2>/dev/null && pwd -P) \
        || pr_undecided pr-body/read-failed "this plugin's skills/writing-style directory is missing"
    rules_file="$rules_dir/rules.yaml"
    [ -f "$rules_file" ] && [ -r "$rules_file" ] \
        || pr_undecided pr-body/read-failed "this plugin's writing-style rules are missing: $rules_file"
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-pr-output.XXXXXX") \
        || pr_undecided pr-body/read-failed "cannot create a temporary directory"
    if [ "$OWNED" = 1 ]; then
        lookup "$@"
        rc=$?
        case "$rc" in
            0) ;;
            3) pr_undecided pr-body/pr-missing "--owned: no single owned pull request to read (lookup answered 3)" ;;
            *) pr_undecided pr-body/read-failed "--owned: the owned pull request lookup failed (lookup answered $rc)" ;;
        esac
        gh pr view "$URL" --json title,body > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null \
            || pr_undecided pr-body/read-failed "gh pr view $URL failed: $(tail -n 1 "$WORK/gh.err")"
    elif ! gh pr view --json title,body > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null; then
        # gh's own wording for a branch with no pull request.
        if grep -qiF -- "no pull requests found" "$WORK/gh.err"; then
            pr_undecided pr-body/pr-missing "gh pr view found no pull request for the checked-out branch: $(tail -n 1 "$WORK/gh.err")"
        fi
        pr_undecided pr-body/read-failed "gh pr view failed: $(tail -n 1 "$WORK/gh.err")"
    fi
    jq -e 'type == "object" and (.title | type == "string") and (.body | type == "string")' \
        "$WORK/pr.json" >/dev/null 2>&1 \
        || pr_undecided pr-body/body-missing "gh pr view did not return a title and a body"
    title=$(jq -r '.title' "$WORK/pr.json")
    jq -j '.body' "$WORK/pr.json" > "$WORK/body.md"

    # Workflow records, unless the repository opts in to them. workflow_content
    # runs in a subshell, so its own refusal reaches stderr there and the
    # finding is printed here.
    : > "$WORK/records"
    content=$(workflow_content) \
        || pr_undecided pr-body/read-failed "could not tell whether the repository opts in to workflow content"
    if [ "$content" = omit ]; then
        workflow_records "$WORK/body.md" > "$WORK/records" \
            || pr_undecided pr-body/read-failed "the PR body couldn't be scanned for workflow records"
    fi

    # --writing-style goes last so the earlier arguments keep their positions.
    shirabe validate --pr-body "$WORK/body.md" --pr-title "$title" --format json \
        --writing-style "$rules_file" \
        > "$WORK/out" 2> "$WORK/err" < /dev/null
    rc=$?
    # A clean validator result still reports the workflow records the scan
    # found, so 0 falls through to the findings below when there are any; the
    # validator's own findings (and its fallback) are read only on its 2.
    case "$rc" in
        0)
            if [ ! -s "$WORK/records" ]; then
                echo "check-pr-output: the PR title and body conform" >&2
                exit 0
            fi
            ;;
        2) ;;
        *)
            # clap's last line is its usage hint, so the whole stderr is read.
            if grep -qF -- "unexpected argument '--writing-style'" "$WORK/err"; then
                pr_undecided pr-body/read-failed "the installed shirabe predates the PR writing-style check (--writing-style); upgrade shirabe"
            fi
            pr_undecided pr-body/read-failed "shirabe validate --pr-body exited $rc: $(tail -n 1 "$WORK/err")"
            ;;
    esac
    pb4=0
    listed=0
    if [ "$rc" -eq 2 ] && jq -r '.findings[].message' "$WORK/out" > "$WORK/messages" \
        && [ -s "$WORK/messages" ]; then
        while IFS= read -r msg; do
            [ -n "$msg" ] || continue
            listed=$((listed + 1))
            rule=$(rule_for_message "$msg")
            [ "$rule" != pr-body/no-heading-in-part1 ] || pb4=1
            finding "$rule" "$msg"
        done < "$WORK/messages"
    fi
    while IFS= read -r rec; do
        [ -n "$rec" ] || continue
        finding pr-body/workflow-content "$rec; the repository doesn't declare ## PR Workflow Content: include, so it belongs in the run's session, not the body"
    done < "$WORK/records"
    # The fallback stands in for a violation the validator didn't list, so it
    # prints only when nothing was listed: a listed finding below block is
    # still a listed finding, and the run passes on it.
    if [ "$rc" -eq 2 ] && [ "$listed" -eq 0 ]; then
        finding pr-body/conformance \
            "shirabe validate --pr-body reported violations it did not list; run it on the PR body for the detail"
    fi
    # PB4 is the rule the offload canary may leave out of a run's preloaded
    # text (DESIGN-offload-live-canary.md), so its full text reaches the agent
    # whenever its finding is shown as something to act on, and never at
    # shadow (an info line) or retired (nothing printed). At block, when the
    # template supplies the escalation ladder's context, the ladder delivers it
    # like every rule (its text from its second failure, rf_deliver below);
    # without that context -- /execute's gate, a test, an agent's own shell --
    # it is released here on every failure, as before the ladder. At warn the
    # gate passes and the ladder doesn't run, so it is released here. release
    # prints on stderr, which koto returns to the agent with the gate's output,
    # and always exits 0; rf_release adds only its delivery marker on stdout,
    # so no path changes this gate's result.
    if [ "$pb4" -eq 1 ]; then
        pb4_stage=$(rf_stage pr-body/no-heading-in-part1) || exit 2
        case "$pb4_stage" in
            warn) rf_release pr-body/no-heading-in-part1 ;;
            block) rf_ladder_active || rf_release pr-body/no-heading-in-part1 ;;
        esac
    fi
    if [ "$RF_BLOCKING" -gt 0 ]; then
        echo "check-pr-output: $RF_BLOCKING PR title/body violation(s)" >&2
        rf_dispute_hint
        rf_deliver
        exit 1
    fi
    # A finding of a retired rule printed nothing, so "above" holds only when
    # one printed.
    if [ "$RF_PRINTED" -gt 0 ]; then
        echo "check-pr-output: the PR title and body break no rule at block; the findings above are of rules below it" >&2
    else
        echo "check-pr-output: the PR title and body break no rule at block; every finding is of a retired rule, so none printed" >&2
    fi
    exit 0
}

check_deferral_record() {
    reasons=()
    while [ $# -gt 0 ] && [ "$1" = --reason ]; do
        [ $# -ge 2 ] || { usage; exit 2; }
        [ -n "$2" ] || undecided "--deferral-record needs a non-empty --reason"
        # A reason is matched as one whole line, and grep -F reads a pattern
        # with a newline as several patterns, any one of which would do.
        case "$2" in
            *$'\n'*|*$'\r'*) undecided "--deferral-record: a --reason must be one line" ;;
        esac
        # A reason of spaces alone names nothing, so a bare `Reason:` line
        # with trailing spaces would pass for it.
        case "$2" in
            *[![:space:]]*) ;;
            *) undecided "--deferral-record: a --reason must have more than spaces" ;;
        esac
        reasons+=("$2")
        shift 2
    done
    [ "${#reasons[@]}" -gt 0 ] || { usage; exit 2; }
    # One public wording may stand in for the verbatim reasons' lines; it is
    # matched as a whole line too, so it is held to the same rules.
    public_reason=""
    if [ $# -gt 0 ] && [ "$1" = --public-reason ]; then
        [ $# -ge 2 ] || { usage; exit 2; }
        [ -n "$2" ] || undecided "--deferral-record needs a non-empty --public-reason"
        case "$2" in
            *$'\n'*|*$'\r'*) undecided "--deferral-record: a --public-reason must be one line" ;;
        esac
        case "$2" in
            *[![:space:]]*) ;;
            *) undecided "--deferral-record: a --public-reason must have more than spaces" ;;
        esac
        public_reason=$2
        shift 2
    fi
    body_always=0
    if [ $# -gt 0 ] && [ "$1" = --body ]; then
        body_always=1
        shift
    fi
    if [ $# -gt 0 ]; then
        [ "$1" = --owned ] || { usage; exit 2; }
        shift
        [ $# -gt 0 ] || { usage; exit 2; }
        OWNED=1
    fi
    make_work
    # A repository that doesn't opt in to workflow content keeps the deferral
    # out of the body: the run's context already records it
    # (verification_deferral), and the body's Verification section says in
    # plain terms that hosted CI verified the change. --body reads the body
    # whatever the setting: a coordinated node PR always carries the record.
    content=include
    [ "$body_always" = 1 ] || content=$(workflow_content) || exit 2
    if [ "$content" = omit ]; then
        echo "check-pr-output: the repository doesn't declare ## PR Workflow Content: include, so the deferral is recorded in the run's context, not the PR body" >&2
        exit 0
    fi
    for tool in gh jq; do
        command -v "$tool" >/dev/null 2>&1 || undecided "$tool is not on PATH"
    done
    if [ "$OWNED" = 1 ]; then
        lookup "$@"
        rc=$?
        [ "$rc" -eq 0 ] || undecided "--owned: no single owned pull request to read (lookup answered $rc)"
        gh pr view "$URL" --json body > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null \
            || undecided "gh pr view $URL failed: $(tail -n 1 "$WORK/gh.err")"
    else
        gh pr view --json body > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null \
            || undecided "gh pr view failed: $(tail -n 1 "$WORK/gh.err")"
    fi
    jq -e 'type == "object" and (.body | type == "string")' "$WORK/pr.json" >/dev/null \
        || undecided "gh pr view did not return a body"
    # A body edited on GitHub's web form comes back with CRLF line ends, and
    # GitHub renders a lone CR as a line break too, so each CRLF and each
    # lone CR becomes a newline here: the whole-line match below then sees the
    # lines a reader sees. Deleting the CRs instead would join `Reason: fo`,
    # a CR and `o` into a `Reason: foo` line the body never shows.
    jq -j '.body | gsub("\r\n?"; "\n")' "$WORK/pr.json" > "$WORK/body.md"

    missing=0
    if ! grep -qiF -- "local verification did not run" "$WORK/body.md"; then
        echo "check-pr-output: the PR body does not say that local verification did not run" >&2
        missing=$((missing + 1))
    fi
    # Each reason must be a whole line, `Reason: <reason>`, not just appear
    # somewhere: a short reason ("CI") sits inside the required phrase below,
    # and a reason that starts another one sits inside that one's line. A
    # whole `Reason: <public wording>` line, when one was given, stands in for
    # all of them; without it, each verbatim line missing is reported, and
    # the public wording's line once more.
    if [ -z "$public_reason" ] || ! grep -qxF -- "Reason: $public_reason" "$WORK/body.md"; then
        verbatim_missing=0
        for reason in "${reasons[@]}"; do
            if ! grep -qxF -- "Reason: $reason" "$WORK/body.md"; then
                echo "check-pr-output: the PR body has no line reading exactly: Reason: $reason" >&2
                missing=$((missing + 1))
                verbatim_missing=1
            fi
        done
        if [ -n "$public_reason" ] && [ "$verbatim_missing" = 1 ]; then
            echo "check-pr-output: the PR body has no line reading exactly the public wording either: Reason: $public_reason" >&2
            missing=$((missing + 1))
        fi
    fi
    if ! grep -qiF -- "hosted CI is the build of record" "$WORK/body.md"; then
        echo "check-pr-output: the PR body does not say that hosted CI is the build of record" >&2
        missing=$((missing + 1))
    fi
    if [ "$missing" -gt 0 ]; then
        echo "check-pr-output: the PR body does not record the verification deferral ($missing part(s) missing); add the Verification section phase-6-pr.md gives, with gh pr edit" >&2
        exit 1
    fi
    echo "check-pr-output: the PR body records the verification deferral" >&2
    exit 0
}

# ctx_read <session> <key>: read a koto context key, as run-verification.sh
# reads one. Sets CTX_PRESENT (1 or 0) and writes the value to CTX_FILE
# (empty for an absent key), and returns 0, or 1 when the read failed. An
# absent key is `koto context exists` exiting 1 with nothing on stdout; any
# other failure is a failed read, never an empty value.
CTX_PRESENT=0
CTX_FILE=""
ctx_read() {
    local out rc
    CTX_PRESENT=0
    : > "$CTX_FILE" || return 1
    out=$(koto context exists "$1" "$2" < /dev/null)
    rc=$?
    if [ "$rc" -eq 1 ] && [ -z "$out" ]; then
        return 0
    fi
    [ "$rc" -eq 0 ] || return 1
    koto context get "$1" "$2" > "$CTX_FILE" < /dev/null || { : > "$CTX_FILE"; return 1; }
    CTX_PRESENT=1
    return 0
}

# verification_section <body-file>: the lines of the body's Verification
# sections (a ## or ### heading named Verification, up to the next heading of
# the same or a higher level), outside fenced code, one per line. The fence
# rule is workflow_records'; the body's line breaks are already newlines.
verification_section() {
    awk '
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        {
            line = $0
            sub(/\r$/, "", line)
            t = line
            sub(/^ +/, "", t)
            if (t ~ /^#+([ \t]|$)/) {
                match(t, /^#+/)
                lvl = RLENGTH
                h = substr(t, lvl + 1)
                sub(/^[ \t]+/, "", h)
                sub(/[ \t]+#+[ \t]*$/, "", h)
                sub(/[ \t]+$/, "", h)
                if (insec && lvl <= seclvl) insec = 0
                if (!insec && (lvl == 2 || lvl == 3) && tolower(h) == "verification") {
                    insec = 1; seclvl = lvl; next
                }
            }
            if (insec) print line
        }' "$1"
}

# The re-run line check, in jq programs sharing RERUN_DEFS. Each archived
# attempt becomes one expectation, {n, H, short, what, add, ids, fails,
# reason, next}: the attempt number, its head (the full head from a ledger,
# the hex a recorded line gives when short is true), how a message names it,
# the line a missing one is told to add, the failed command ids, the ids with
# their outcome, the reason, and the next result's word or null.
# RERUN_FROM_SESSIONS builds them from the sessions' ledgers ($S, slurped:
# [{session, entries, results}]) and RERUN_FROM_LINES from recorded re-run
# lines ($R, slurped: an array of strings), stopping with an error on a line
# it can't read. RERUN_CHECK checks the Verification section's lines ($LN,
# slurped: an array of strings) against them ($X, slurped), printing one
# message per missing or wrong part; nothing when every attempt has its line.
# render is the line an expectation from a ledger asks for, in phase-6-pr.md's
# shape, which RERUN_FROM_LINES reads back: --print writes it.
RERUN_DEFS='
def clean: tostring | gsub("`"; "") | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
def spans: [scan("`[^`]*`") | .[1:-1] | clean];
def lead: sub("^\\s+"; "") | sub("^[-*]\\s+"; "");
def hexes: [scan("[0-9A-Fa-f]{7,}") | ascii_downcase];
def abspath:
    test("(^|[\\s`(\\[=\"'"'"'])(~/|/)[^\\s]")
    or test("(^|[\\s`(\\[=\"'"'"'])[A-Za-z]:[\\\\/]");
def word:
    if ((.commands // []) | any(.[]; .timed_out == true)) then "timed out"
    elif .status == "done" and ((.commands // []) | all(.[]; .exit_status == 0 and .timed_out != true)) then "passed"
    else "failed" end;
def dedupe: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
def render:
    "Re-run attempt \(.n) at `\(.H[0:12])`"
    + ([ (if (.fails | length) > 0 then ([.fails[] | "`\(.id)` \(.out)"] | join(", ")) else empty end),
         (if .reason != "" then "reason `\(.reason)`" else empty end),
         (if .next != null then "attempt \(.n + 1) \(.next)" else empty end) ]
       | if length > 0 then ": " + join("; ") else "" end)
    + ".";
'
RERUN_FROM_SESSIONS='
$S[0] as $sessions
| ($sessions | length > 1) as $multi
| $sessions[] as $s
| ($s.entries) as $E
| $E[] as $e
| ($e.attempt) as $n
| ($e.head) as $H
| ($e.merge_base) as $M
| ([$E[] | select(.head == $H and .merge_base == $M and .attempt == $n + 1)] | .[0]) as $nx
| ([$E[] | select(.head == $H and .merge_base == $M and .attempt > $n)] | length == 0) as $last
| ([($e.commands // [])[] | .log | strings]) as $elogs
| (if $nx != null then ($nx | word)
   elif $last and ($s.results | type) == "object"
        and $s.results.head == $H and $s.results.merge_base == $M
        and ([($s.results.commands // [])[] | .log | strings]
             | any(.[]; . as $l | $elogs | any(.[]; . as $r | $l | endswith("/" + $r))) | not)
   then ($s.results | word)
   else null end) as $next
| ([($e.commands // [])[]
    | select(((.exit_status | type) == "number" and .exit_status != 0) or .timed_out == true)
    | {id: (.id | strings | clean), out: (if .timed_out == true then "timed out" else "failed" end)}
    | select(.id != "")]
   | reduce .[] as $f ([]; if any(.[]; .id == $f.id) then . else . + [$f] end)) as $fails
| (($e.reason // "") | clean) as $reason
| {n: $n, H: $H, short: false,
   what: ("attempt \($n) at \($H[0:12])" + (if $multi then " (session \($s.session))" else "" end)),
   add: ("Re-run attempt \($n) at `\($H[0:12])`: `<id>` failed; reason `<reason>`" + (if $next then "; attempt \($n + 1) \($next)." else "." end)),
   ids: [$fails[] | .id], fails: $fails, reason: $reason, next: $next}
'
# A recorded line is read in the shape render writes: the attempt, 7 to 40
# hex of its head, then, each optional, the failed ids with their outcome,
# the reason, and the next attempt with its word, ending in a period.
RERUN_FROM_LINES='
$R[0][] as $l
| ([$l | capture("^Re-run attempt (?<n>[1-9][0-9]*) at `(?<h>[0-9a-f]{7,40})`(?:: (?<f>`[^`]+` (?:failed|timed out)(?:, `[^`]+` (?:failed|timed out))*))?(?:(?:: |; )reason `(?<r>[^`]+)`)?(?:(?:: |; )attempt (?<nn>[1-9][0-9]*) (?<w>passed|failed|timed out))?\\.$")] | .[0]) as $c
| if $c == null then error("the recorded line [\($l)] is not a re-run line in the shape this check reads") else . end
| ($c.n | tonumber) as $n
| if $c.nn != null and ($c.nn | tonumber) != $n + 1 then error("the recorded line [\($l)] gives attempt \($c.nn) as the one after attempt \($n)") else . end
| {n: $n, H: $c.h, short: true,
   what: "attempt \($n) at \($c.h[0:12])",
   add: $l,
   ids: ([($c.f // "") | scan("`([^`]+)`") | .[0] | clean] | dedupe),
   fails: [], reason: (($c.r // "") | clean), next: $c.w}
'
RERUN_CHECK='
$LN[0] as $lines
| $X[] as $x
| ($x.n) as $n
| ($x.H) as $H
| ($x.what) as $what
| ($x.ids) as $ids
| ($x.reason) as $reason
| ($x.next) as $next
| [$lines[] | select(lead | ascii_downcase | test("^re-run attempt\\s+\($n)([^0-9]|$)"))
            | select(hexes | any(.[]; . as $y | ($H | startswith($y)) or ($x.short and ($y | startswith($H)))))] as $cands
| if ($cands | length) == 0 then
    "the PR body'"'"'s Verification section has no re-run line for \($what); add: \($x.add)"
  else
    [$cands[] as $L
     | [ (if ($L | abspath) then "the re-run line for \($what) holds an absolute path; log paths stay out of the PR body, which may be public, so name each command by its id only" else empty end),
         ($ids[] as $id
          | if ($L | spans | any(.[]; . == $id)) then empty
            elif ($L | index($id)) != null then "the re-run line for \($what) has command id \($id) outside a code span; write it in backticks"
            else "the re-run line for \($what) names no failed command \($id); add its id in a code span" end),
         (if $reason == "" then empty
          elif ($L | spans | any(.[]; . == $reason)) then empty
          elif ($L | clean | index($reason)) != null then "the re-run line for \($what) has its reason outside a code span; write it in backticks"
          else "the re-run line for \($what) carries no reason; add the \(if $x.short then "recorded" else "ledger'"'"'s" end) reason in a code span: \($reason)" end),
         (if $next == null then empty
          elif ($L | ascii_downcase | index("attempt \($n + 1) \($next)")) != null then empty
          else "the re-run line for \($what) does not say what attempt \($n + 1) showed; add: attempt \($n + 1) \($next)" end) ]] as $P
    | if any($P[]; length == 0) then empty else $P[0][] end
  end
'

RR_SESSIONS=()
RR_LINES=()
check_rerun_record() {
    local s i n total rc msg print=0 what
    while [ $# -gt 0 ]; do
        case "$1" in
            --session)
                [ $# -ge 2 ] || { usage; exit 2; }
                # The name run-verification.sh accepts for its session.
                grep -Eq '^[A-Za-z0-9._][A-Za-z0-9._-]*$' <<<"$2" && [ "$2" != . ] && [ "$2" != .. ] \
                    || undecided "--rerun-record: --session [$2] is not a session name"
                RR_SESSIONS+=("$2")
                shift 2
                ;;
            --line)
                [ $# -ge 2 ] && [ -n "$2" ] || { usage; exit 2; }
                case "$2" in
                    *$'\n'*|*$'\r'*) undecided "--rerun-record: a --line spans more than one line" ;;
                esac
                RR_LINES+=("$2")
                shift 2
                ;;
            --print) print=1; shift ;;
            *) break ;;
        esac
    done
    # One source of re-runs: the sessions' ledgers, or the recorded lines.
    # --print renders the ledgers' lines, so it takes sessions and no PR.
    if [ "${#RR_SESSIONS[@]}" -gt 0 ]; then
        [ "${#RR_LINES[@]}" -eq 0 ] || { usage; exit 2; }
    else
        [ "${#RR_LINES[@]}" -gt 0 ] && [ "$print" = 0 ] || { usage; exit 2; }
    fi
    if [ $# -gt 0 ]; then
        [ "$print" = 0 ] && [ "$1" = --owned ] || { usage; exit 2; }
        shift
        [ $# -gt 0 ] || { usage; exit 2; }
        OWNED=1
    fi
    command -v jq >/dev/null || undecided "jq is not on PATH"
    make_work

    if [ "${#RR_LINES[@]}" -gt 0 ]; then
        # The recorded lines stand in for the ledgers: no koto read.
        printf '%s\n' "${RR_LINES[@]}" > "$WORK/recorded"
        jq -Rn '[inputs]' "$WORK/recorded" > "$WORK/recorded.json" \
            || undecided "could not read the recorded re-run lines"
        jq -cn --slurpfile R "$WORK/recorded.json" "$RERUN_DEFS$RERUN_FROM_LINES" \
            > "$WORK/expect.jsonl" 2> "$WORK/jq.err" \
            || undecided "$(tail -n 1 "$WORK/jq.err" | sed 's/^jq: error[^:]*: //'); nothing is accepted"
        total=${#RR_LINES[@]}
        what="recorded re-run line(s)"
    else
        rr_expect_from_sessions
        total=$RR_TOTAL
        what="archived attempt(s)"
        if [ "$print" = 1 ]; then
            jq -r -s "$RERUN_DEFS"'map(render) | dedupe | .[]' "$WORK/expect.jsonl" \
                || undecided "could not render the re-run lines"
            exit 0
        fi
    fi
    rr_check_body "$total" "$what" "$@"
}

# rr_expect_from_sessions: the sessions' ledgers, read from koto context, as
# expectations in $WORK/expect.jsonl; RR_TOTAL is the number of archived
# attempts. With none it exits 0 without reading anything else (with --print,
# having printed nothing).
RR_TOTAL=0
rr_expect_from_sessions() {
    local s i n total
    command -v koto >/dev/null || undecided "koto is not on PATH"
    CTX_FILE="$WORK/ctx"

    # The ledgers first: with none, nothing else is read.
    total=0
    i=0
    for s in "${RR_SESSIONS[@]}"; do
        i=$((i + 1))
        ctx_read "$s" verification_attempts \
            || undecided "could not read verification_attempts for session $s from koto context; a failed read is not an empty ledger, so nothing is accepted"
        grep . "$CTX_FILE" > "$WORK/ledger.$i"
        n=$(grep -c . "$WORK/ledger.$i")
        total=$((total + n))
    done
    if [ "$total" -eq 0 ]; then
        echo "check-pr-output: no re-run in this run's verification_attempts; nothing to record" >&2
        exit 0
    fi

    # Each ledger line must be one, and each session with lines may have a
    # result to say what the last attempt's re-run showed.
    : > "$WORK/sessions.jsonl"
    i=0
    for s in "${RR_SESSIONS[@]}"; do
        i=$((i + 1))
        : > "$WORK/results.$i"
        if [ -s "$WORK/ledger.$i" ]; then
            jq -e -s 'all(.[]; type == "object"
                    and (.attempt | type) == "number" and .attempt >= 1 and .attempt == (.attempt | floor)
                    and (.head | type) == "string" and (.head | test("^[0-9a-f]{7,64}$"))
                    and (.merge_base | type) == "string"
                    and ((.commands // []) | type) == "array")' "$WORK/ledger.$i" >/dev/null \
                || undecided "verification_attempts for session $s holds a line that is not a ledger line (an attempt number, a head, a merge-base and commands); nothing is accepted"
            ctx_read "$s" verification_results.json \
                || undecided "could not read verification_results.json for session $s from koto context"
            if [ "$CTX_PRESENT" = 1 ] && [ -s "$CTX_FILE" ]; then
                jq -e 'type == "object"' "$CTX_FILE" >/dev/null \
                    || undecided "verification_results.json for session $s is not a JSON object"
                cp "$CTX_FILE" "$WORK/results.$i"
            fi
        fi
        jq -cn --arg s "$s" --slurpfile e "$WORK/ledger.$i" --slurpfile r "$WORK/results.$i" \
            '{session: $s, entries: $e, results: ($r[0] // null)}' >> "$WORK/sessions.jsonl" \
            || undecided "could not read the ledger of session $s"
    done
    jq -s . "$WORK/sessions.jsonl" > "$WORK/sessions.json" \
        || undecided "could not gather the sessions' ledgers"
    jq -cn --slurpfile S "$WORK/sessions.json" "$RERUN_DEFS$RERUN_FROM_SESSIONS" \
        > "$WORK/expect.jsonl" 2> "$WORK/jq.err" \
        || undecided "could not read the sessions' ledgers: $(tail -n 1 "$WORK/jq.err")"
    RR_TOTAL=$total
}

# rr_check_body <count> <what> [<owned-pr.sh arguments>]: the pull request's
# body against the expectations in $WORK/expect.jsonl, <count> <what> of
# them, and the exit: 0 when every one has its line, 1 when one doesn't.
rr_check_body() {
    local total=$1 what=$2 rc n msg
    shift 2
    # The pull request, as --deferral-record reads it.
    command -v gh >/dev/null || undecided "gh is not on PATH"
    if [ "$OWNED" = 1 ]; then
        lookup "$@"
        rc=$?
        [ "$rc" -eq 0 ] || undecided "--owned: no single owned pull request to read (lookup answered $rc)"
        gh pr view "$URL" --json body > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null \
            || undecided "gh pr view $URL failed: $(tail -n 1 "$WORK/gh.err")"
    else
        gh pr view --json body > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null \
            || undecided "gh pr view failed: $(tail -n 1 "$WORK/gh.err")"
    fi
    jq -e 'type == "object" and (.body | type == "string")' "$WORK/pr.json" >/dev/null \
        || undecided "gh pr view did not return a body"
    # Each CRLF and each lone CR is a line break, as GitHub renders it (see
    # --deferral-record).
    jq -j '.body | gsub("\r\n?"; "\n")' "$WORK/pr.json" > "$WORK/body.md"
    verification_section "$WORK/body.md" > "$WORK/section" \
        || undecided "the PR body's Verification section couldn't be read"

    jq -Rn '[inputs]' "$WORK/section" > "$WORK/lines.json" \
        || undecided "the PR body's Verification section couldn't be read"
    jq -rn --slurpfile X "$WORK/expect.jsonl" --slurpfile LN "$WORK/lines.json" "$RERUN_DEFS$RERUN_CHECK" \
        > "$WORK/problems" 2> "$WORK/jq.err" \
        || undecided "could not check the re-run lines: $(tail -n 1 "$WORK/jq.err")"

    if [ -s "$WORK/problems" ]; then
        n=0
        while IFS= read -r msg; do
            [ -n "$msg" ] || continue
            n=$((n + 1))
            echo "check-pr-output: $msg" >&2
        done < "$WORK/problems"
        echo "check-pr-output: the PR body does not record every verification re-run ($n part(s) missing or wrong); write one re-run line per archived attempt in its Verification section, as phase-6-pr.md gives it, with gh pr edit" >&2
        exit 1
    fi
    echo "check-pr-output: the PR body records every verification re-run ($total $what)" >&2
    exit 0
}

check_hosted_record() {
    local session rc key rec_head head url bad=0 c
    [ $# -eq 2 ] && [ "$1" = --session ] && [ -n "$2" ] || { usage; exit 2; }
    session=$2
    for tool in git jq koto; do
        command -v "$tool" >/dev/null 2>&1 || undecided "$tool is not on PATH"
    done
    koto context exists "$session" hosted_of_record
    rc=$?
    case "$rc" in
        0) ;;
        1) echo "check-pr-output: no hosted_of_record key: the pull request opens as it does without the route" >&2; exit 0 ;;
        *) undecided "koto context exists $session hosted_of_record exited $rc" ;;
    esac
    key=$(koto context get "$session" hosted_of_record) || undecided "could not read the hosted_of_record key of $session"
    rec_head=$(jq -r 'if type == "object" and (.head | type) == "string" then .head else error("no head") end' <<<"$key") \
        || undecided "the hosted_of_record key of $session names no head"
    head=$(git rev-parse --verify -q "HEAD^{commit}") || undecided "HEAD does not name a commit"
    if [ "$rec_head" != "$head" ]; then
        echo "check-pr-output: the hosted_of_record key is for $rec_head, not HEAD $head; a stale key is no record" >&2
        exit 0
    fi
    # Loaded only here: no other mode reads the route.
    # shellcheck source=verification-route.sh
    . "$HERE/verification-route.sh" || undecided "cannot load verification-route.sh"
    for tool in gh; do
        command -v "$tool" >/dev/null 2>&1 || undecided "$tool is not on PATH"
    done
    make_work
    gh pr view --json isDraft,body,url,headRefOid > "$WORK/pr.json" 2> "$WORK/gh.err" < /dev/null \
        || undecided "gh pr view failed: $(tail -n 1 "$WORK/gh.err")"
    jq -e 'type == "object" and (.isDraft | type) == "boolean" and (.body | type) == "string" and (.url | type) == "string"' \
        "$WORK/pr.json" >/dev/null || undecided "gh pr view did not return isDraft, body and url"
    url=$(jq -r .url "$WORK/pr.json")
    jq -j '.body' "$WORK/pr.json" > "$WORK/body.md"
    if [ "$(jq -r .isDraft "$WORK/pr.json")" != true ]; then
        echo "check-pr-output: $url is not a draft; a run on the hosted-of-record route opens its pull request with gh pr create --draft" >&2
        bad=$((bad + 1))
    fi
    if ! vr_body_check draft "$WORK/body.md" "$key" "$url"; then
        while IFS= read -r c; do
            [ -n "$c" ] || continue
            echo "check-pr-output: $c" >&2
            bad=$((bad + 1))
        done <<EOF
$VR_CAUSES
EOF
    fi
    if [ "$bad" -gt 0 ]; then
        echo "check-pr-output: the pull request does not carry the hosted-of-record route ($bad problem(s)); put the lines verification-route.sh --lines --session $session prints into the body verbatim, with gh pr edit --body-file" >&2
        exit 1
    fi
    echo "check-pr-output: the draft carries one Hosted of record line per recorded check" >&2
    exit 0
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
    --deferral-record) check_deferral_record "$@" ;;
    --rerun-record) check_rerun_record "$@" ;;
    --hosted-record) check_hosted_record "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac
