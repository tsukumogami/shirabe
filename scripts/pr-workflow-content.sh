#!/usr/bin/env bash
# pr-workflow-content.sh -- whether a repository opts in to workflow content in
# the pull request titles, bodies and commit messages shirabe's skills write.
#
# Usage:
#   pr-workflow-content.sh [<repository directory>]
#   pr-workflow-content.sh --record <session> [<repository directory>]
#   pr-workflow-content.sh --session <session>
#   pr-workflow-content.sh --reference <record root session>
#
# Prints one word on stdout:
#   include   the repository declares `## PR Workflow Content: include`: the
#             skills write today's workflow records (the review round table,
#             override and deferral notes, the run's record lines, pointers to
#             PLAN and ROADMAP files, per-child outcome tables, the artifact
#             skills' jury verdicts), and every PR a plan's run opens or
#             rewrites carries one Part 2 line naming the run's record,
#             `Run record: <record root session> (run <run_id>)`
#   omit      anything else, the default: titles, bodies and commit messages
#             describe the change and how it was verified in plain terms, and
#             the records stay in the run's own session. No PR carries a run
#             marker, run lines, a PR index or a session name
#
# The declaration is a header line in the repository root's CLAUDE.local.md,
# else its CLAUDE.md, read the way the `## Repo Visibility:` header is read:
# the first well-formed header in a file wins, case doesn't matter, and
# CLAUDE.local.md is read before CLAUDE.md. A workspace that manages its
# repositories' CLAUDE.local.md (as niwa does) opts a repository in from its
# workspace configuration that way; a repository can also declare it in its
# own CLAUDE.md. A header whose value is neither word is not well-formed and
# is passed over.
#
# Read once per invocation. A run doesn't read the files at each write: its
# opener (execute-open.sh, work-on-open.sh, scope-open.sh, deliver-open.sh)
# runs `--record <session>` once, which reads the files and stores the value
# as the session's context key `pr_content`, and every PR writer and gate in
# that run reads it back with `--session <session>`. So a value can't flip
# mid-run when a step runs without a checkout, and an invocation started after
# the header is turned off records omit and writes no reference. A
# plan-backed child of /execute reads its parent's key (`--session
# execute-<slug>`). `--session` falls back to the files only when the key is
# absent (a session opened before the key existed); a key holding anything
# but include reads omit. Only exit 0 with include counts as include.
#
# The reference. `--reference <record root session>` prints the one Part 2
# line a PR gets under include, `Run record: <session> (run <run_id>)`, the
# run_id read from that session, and prints nothing under omit. For a
# multi-pr item's /work-on session (one holding `record_root`) the line names
# the plan root and its run_id, read at the shared address through
# lib/record-store.sh. Every PR
# writer of a plan's run puts that output, and nothing else of the run, below
# the body's top-level `---`, never in the title or Part 1. It reads the
# recorded value as --session does, so it is the same switch.
#
# It reads files on disk, so it needs the repository's checkout. A workspace's
# opt-in arrives as CLAUDE.local.md, which isn't committed, so an opener that
# runs with no checkout of the repository records omit for a repository whose
# own checkout reads include. Omit is the safe side of that gap for the pull
# request's text: the records stay out of it and remain in the run's session.
# Run it in the checkout the pull request comes from: niwa writes
# CLAUDE.local.md into each worktree it provisions, so a linked worktree
# carries its own copy.
#
# The directory defaults to the root of the git work tree holding the current
# directory, else the current directory. It is the one interface every skill,
# gate and script uses to read the switch, so they can't disagree about a
# repository; call it, don't parse the header yourself. The no-argument form
# is what the artifact skills call, outside any plan's run.
#
# Exit codes: 0 printed; 2 the directory doesn't exist; 64 usage; 66 a koto
# context call failed (--record: nothing recorded, the value read is still
# printed; --session: omit is printed; --reference: nothing is printed).
#
# Requires: koto for --record and --session. Written for the bash 3.2 floor.
set -u

PROG=pr-workflow-content
RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$'

usage() {
    echo "$PROG: $*" >&2
    echo "usage: pr-workflow-content.sh [<repository directory>] | --record <session> [<repository directory>] | --session <session> | --reference <session>" >&2
    exit 64
}

# read_files <dir>: the switch as the directory's files declare it.
read_files() {
    local f v
    [ -d "$1" ] || { echo "$PROG: $1 is not a directory" >&2; return 2; }
    for f in "$1/CLAUDE.local.md" "$1/CLAUDE.md"; do
        [ -f "$f" ] || continue
        v=$(LC_ALL=C tr '[:upper:]' '[:lower:]' < "$f" | awk '
            {
                line = $0
                sub(/\r$/, "", line)
                sub(/^[ \t]+/, "", line)
                if (index(line, "## pr workflow content:") != 1) next
                value = substr(line, length("## pr workflow content:") + 1)
                sub(/^[ \t]+/, "", value)
                sub(/[ \t]+$/, "", value)
                if (value == "include" || value == "omit") { print value; exit }
            }')
        if [ -n "$v" ]; then
            printf '%s\n' "$v"
            return 0
        fi
    done
    echo omit
}

default_dir() {
    git rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$PWD"
}

MODE=files SESSION=""
case "${1:-}" in
    --record|--session|--reference)
        MODE=${1#--}
        [ $# -ge 2 ] || usage "$1 needs a session"
        SESSION=$2
        [[ $SESSION =~ $RE_SESSION ]] || usage "[$SESSION] is not a koto session name"
        shift 2
        ;;
esac

case "$MODE" in
    files|record)
        case $# in
            0) DIR=$(default_dir) ;;
            1) case "$1" in -*) usage "unexpected option [$1]" ;; esac
               DIR=$1 ;;
            *) usage "too many arguments" ;;
        esac
        V=$(read_files "$DIR") || exit $?
        if [ "$MODE" = record ]; then
            if ! printf '%s' "$V" | koto context add "$SESSION" pr_content >/dev/null; then
                echo "$PROG: could not record pr_content in session $SESSION" >&2
                printf '%s\n' "$V"
                exit 66
            fi
        fi
        printf '%s\n' "$V"
        ;;
    reference)
        [ $# -eq 0 ] || usage "--reference takes no directory: the recorded value is the run's"
        V=$("$BASH" "$0" --session "$SESSION") || exit $?
        [ "$V" = include ] || exit 0
        ROOT=$SESSION
        if koto context exists "$SESSION" record_root </dev/null >/dev/null 2>&1; then
            # A multi-pr item: its record is the plan root at the shared
            # address (skills/work-on/scripts/multi-pr-item-record.sh), and
            # the run_id is the plan root's.
            # shellcheck source=lib/record-store.sh
            . "$(dirname "$0")/lib/record-store.sh" || exit 66
            ROOT=$(koto context get "$SESSION" record_root </dev/null 2>/dev/null) || ROOT=""
            OWNER=$(rs_plan_root_owner "$ROOT") || {
                echo "$PROG: session $SESSION's record_root is not a plan root; no reference written" >&2
                exit 66
            }
            RID=""
            while IFS= read -r FORM; do
                [ -n "$FORM" ] || continue
                RID=$(rs_koto_read "$FORM" context get "$ROOT" run_id </dev/null 2>/dev/null) && break
                RID=""
            done <<<"$(rs_shared_forms "$OWNER")"
        else
            RID=$(koto context get "$SESSION" run_id </dev/null 2>/dev/null) || RID=""
        fi
        if ! [[ $RID =~ ^[0-9a-f]{32}$ ]]; then
            echo "$PROG: $ROOT holds no usable run_id; no reference written" >&2
            exit 66
        fi
        printf 'Run record: %s (run %s)\n' "$ROOT" "$RID"
        ;;
    session)
        [ $# -eq 0 ] || usage "--session takes no directory: the recorded value is the run's"
        koto context exists "$SESSION" pr_content </dev/null >/dev/null 2>&1
        case $? in
            0)
                if ! V=$(koto context get "$SESSION" pr_content </dev/null 2>/dev/null); then
                    echo "$PROG: could not read pr_content from session $SESSION" >&2
                    echo omit
                    exit 66
                fi
                case "$V" in
                    include) echo include ;;
                    *) echo omit ;;
                esac
                ;;
            1)
                read_files "$(default_dir)" || exit $?
                ;;
            *)
                echo "$PROG: could not check pr_content in session $SESSION" >&2
                echo omit
                exit 66
                ;;
        esac
        ;;
esac
exit 0
