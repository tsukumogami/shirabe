#!/usr/bin/env bash
# check-pr-output.sh -- does the pull request a run produced pass the output
# rules, and which pull request does the run own?
# Part of the work-on skill
#
# A gate script: koto runs it as a command gate and routes on its exit status.
# Each mode calls a check that already ships, unchanged, and translates its
# result:
#
#   --pr-body [--session <session>] [--owned <owned-pr.sh arguments>]
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
#       Validator exit 0 -> 0, and 1, 3, 4 -> 2. Exit 2 prints one finding
#       per listed message, at its rule's stage, and maps to 1 when one of
#       them is of a rule at `block`, else 0. An exit 2 that lists no message
#       prints the pr-body/conformance finding instead. An installed shirabe
#       older than --writing-style rejects the flag with exit 1, so the gate
#       holds (2) and says to upgrade; preflight (requires.tsv) reports the
#       same gap when the skill loads.
#       Unless the switch reads include (scripts/pr-workflow-content.sh: with
#       --session, the value that session's run recorded at its open, else
#       the files of the work tree this runs in), the body is also scanned,
#       outside fenced code, for workflow records
#       (references/pr-body-conformance.md, "Workflow content"): a
#       `## Review panel` heading, a Seat/Model/Run/Verdict/Reviewed head
#       table, a `Plan:` or `Roadmap:` line, an `Implements` line naming a
#       PLAN- or ROADMAP- file, and the run's own traces: a run marker line
#       (an HTML comment naming a shirabe run), a run line (`topic=`, `exit=`,
#       `outcome=`, `intent=`, `mode=`, `store=`, `run=`), a `## PR Index` or
#       `## Merge Order` heading or a PR index line, a `Run record:` line
#       (which names a session), and a `record:` or `unpinned` result line.
#       Each is a pr-body/workflow-content finding, at that rule's stage,
#       whatever the validator answered.
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
#   --deferral-record [--session <session>] --reason <reason>
#                     [--reason <reason>]... [--owned <owned-pr.sh arguments>]
#       For a run that deferred verification to hosted CI (work-on.md's
#       VERIFICATION=hosted-ci, #1012). When the switch reads omit (the
#       default; with --session, the value that session's run recorded) it
#       passes (0) without reading GitHub: the deferral is recorded in the
#       run's context as verification_deferral, and the body says in plain
#       terms that hosted CI verified the change. That holds for a
#       coordinated node PR too. When it reads include, it reads the pull
#       request body with
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
#       line with more than spaces in it. Without
#       --owned the pull request is the checked-out branch's (/work-on's
#       pr_creation, one reason); with --owned it is the one owned-pr.sh
#       resolves, as --pr-body --owned reads it (/execute's shared PR, whose
#       children may each have deferred, through shared-deferral-record.sh).
#         all present                                -> 0
#         any missing                                -> 1, one stderr line each
#         an empty reason, no single owned pull request, gh missing or
#         failing, no body                           -> 2
#       It prints no ::koto-finding:: line. Like pr_creation's closing
#       keyword, the obligation is the template's own, with no registry rule
#       behind it, and the stderr lines say what is missing.
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
#   PB5 (banned word)        pr-body/banned-word
#   anything else            pr-body/conformance
# and this script's own scan, pr-body/workflow-content.
# The rules are entries of references/rule-registry.json; scripts/lib/rule-findings.sh
# resolves each one's reference, summary and stage through scripts/rule-registry.sh.
#
# Written for the bash 3.2 floor and deliberately without `set -e`.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
RULE_IDS="pr-body/conventional-title pr-body/one-separator pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/banned-word pr-body/conformance pr-body/workflow-content"
# Seconds owned-pr.sh may run. koto stops a gate command at 30 seconds; this
# stays under it so the answer is this script's 2, not koto's timeout.
# CHECK_PR_OUTPUT_OWNED_TIMEOUT is the tests' seam, and also how
# /execute's shared-deferral-record.sh cuts the limit to the time it has
# left after reading its children.
OWNED_PR_TIMEOUT=${CHECK_PR_OUTPUT_OWNED_TIMEOUT:-20}
RE_URL='^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$'

usage() {
    cat >&2 <<'EOF'
Usage: check-pr-output.sh --pr-body [--session <session>] [--owned <owned-pr.sh arguments>]
       check-pr-output.sh --owned-pr <owned-pr.sh arguments>
       check-pr-output.sh --deferral-record [--session <session>] --reason <reason> [--reason <reason>]... [--owned <owned-pr.sh arguments>]

--pr-body:        exit 0 conformant, 1 a violation (findings on stdout), 2 could not decide.
--owned-pr:        exit 0 one owned PR (its URL on stdout), 3 not exactly one, 2 could not decide.
--deferral-record: exit 0 the body records the deferral, 1 it does not, 2 could not decide.
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

# workflow_content: pr-workflow-content.sh's answer, `include` or `omit`:
# the value --session's run recorded, else (no --session) the files of the
# work tree holding the current directory. Any failure is undecided.
workflow_content() {
    local v
    v=$(bash "$HERE/../../../scripts/pr-workflow-content.sh" ${CONTENT_SESSION:+--session "$CONTENT_SESSION"} 2>"$WORK/pwc.err" </dev/null) \
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
            if (l ~ /^<!--[ \t]*shirabe-run:/) {
                printf "a run marker line (line %d)\n", NR; next
            }
            if (t ~ /^(topic|exit|outcome|intent|mode|store|run)=[^ \t]+$/) {
                printf "a `%s` run line (line %d)\n", substr(t, 1, index(t, "=")), NR; next
            }
            if (l == "## pr index" || l == "## merge order") {
                printf "a `%s` heading (line %d)\n", t, NR; next
            }
            if (t ~ /^- [a-z][a-z0-9-]*(\/follow-up-[0-9]+)? \| [^ |]+\/[^ |]+:[^ |]+#[0-9]+ \|/) {
                printf "a PR index line (line %d)\n", NR; next
            }
            if (l ~ /^run record:/) {
                printf "a `Run record:` line naming a session (line %d)\n", NR; next
            }
            if (l ~ /^(record|record_unpinned|unpinned)[ \t]*[:=]/) {
                printf "a run record result line (line %d)\n", NR; next
            }
        }' "$1"
}

check_pr_body() {
    require_rules pr-body/conventional-title pr-body/one-separator \
        pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/banned-word \
        pr-body/conformance pr-body/workflow-content
    for tool in gh jq shirabe; do
        command -v "$tool" >/dev/null 2>&1 || undecided "$tool is not on PATH"
    done
    rules_dir=$(cd "$HERE/../../writing-style" 2>/dev/null && pwd -P) \
        || undecided "this plugin's skills/writing-style directory is missing"
    rules_file="$rules_dir/rules.yaml"
    [ -f "$rules_file" ] && [ -r "$rules_file" ] \
        || undecided "this plugin's writing-style rules are missing: $rules_file"
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

    # Workflow records, unless the repository opts in to them.
    : > "$WORK/records"
    content=$(workflow_content) || exit 2
    if [ "$content" = omit ]; then
        workflow_records "$WORK/body.md" > "$WORK/records" \
            || undecided "the PR body couldn't be scanned for workflow records"
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
                undecided "the installed shirabe predates the PR writing-style check (--writing-style); upgrade shirabe"
            fi
            undecided "shirabe validate --pr-body exited $rc: $(tail -n 1 "$WORK/err")"
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
    # and always exits 0, so no path changes this gate's result.
    if [ "$pb4" -eq 1 ]; then
        pb4_stage=$(rf_stage pr-body/no-heading-in-part1) || exit 2
        case "$pb4_stage" in
            warn) "$RF_HELPER" release pr-body/no-heading-in-part1 </dev/null ;;
            block) rf_ladder_active || "$RF_HELPER" release pr-body/no-heading-in-part1 </dev/null ;;
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
    if [ $# -gt 0 ]; then
        [ "$1" = --owned ] || { usage; exit 2; }
        shift
        [ $# -gt 0 ] || { usage; exit 2; }
        OWNED=1
    fi
    make_work
    # Under omit the deferral stays out of the body: the run's context already
    # records it (verification_deferral), and the body's Verification section
    # says in plain terms that hosted CI verified the change. A coordinated
    # node PR is no exception.
    content=$(workflow_content) || exit 2
    if [ "$content" = omit ]; then
        echo "check-pr-output: the run's switch reads omit, so the deferral is recorded in the run's context, not the PR body" >&2
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
    # and a reason that starts another one sits inside that one's line.
    for reason in "${reasons[@]}"; do
        if ! grep -qxF -- "Reason: $reason" "$WORK/body.md"; then
            echo "check-pr-output: the PR body has no line reading exactly: Reason: $reason" >&2
            missing=$((missing + 1))
        fi
    done
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
# --session <s>: read the switch the run recorded (pr-workflow-content.sh
# --session) rather than the files. --pr-body and --deferral-record take it.
CONTENT_SESSION=""
case "$MODE" in
    --pr-body|--deferral-record)
        if [ $# -gt 0 ] && [ "$1" = --session ]; then
            [ $# -ge 2 ] || { usage; exit 2; }
            [[ $2 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { usage; exit 2; }
            CONTENT_SESSION=$2
            shift 2
        fi
        ;;
esac
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
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac
