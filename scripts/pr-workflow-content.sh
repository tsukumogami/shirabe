#!/usr/bin/env bash
# pr-workflow-content.sh -- whether a repository opts in to workflow content in
# the pull request titles, bodies and commit messages shirabe's skills write.
#
# Usage: pr-workflow-content.sh [<repository directory>]
#
# Prints one word on stdout:
#   include   the repository declares `## PR Workflow Content: include`: the
#             skills write today's workflow records (the review round table,
#             override and deferral notes, the run's record lines, pointers to
#             PLAN and ROADMAP files, per-child outcome tables, the artifact
#             skills' jury verdicts)
#   omit      anything else, the default: titles, bodies and commit messages
#             describe the change and how it was verified in plain terms, and
#             the records stay in the run's own session
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
# It reads files on disk, so it needs the repository's checkout. A workspace's
# opt-in arrives as CLAUDE.local.md, which isn't committed, so a step that
# runs with no checkout of the repository (after its instance is reaped, or
# against GitHub alone) reads omit for a repository whose own run read
# include. Omit is the safe side of that gap for the pull request's text: the
# records stay out of it and remain in the run's session. It also means a gate
# that, under include, checks a record in the body (the verification-deferral
# record) checks nothing there and takes the run's own record instead. Run it
# in the checkout the pull request comes from: niwa writes CLAUDE.local.md
# into each worktree it provisions, so a linked worktree carries its own copy.
#
# The directory defaults to the root of the git work tree holding the current
# directory, else the current directory. It is the one interface every skill,
# gate and script uses to read the switch, so they can't disagree about a
# repository; call it, don't parse the header yourself.
#
# Exit codes: 0 printed; 2 the directory doesn't exist; 64 usage.
#
# Written for the bash 3.2 floor.
set -u

case $# in
    0) DIR=$(git rev-parse --show-toplevel 2>/dev/null) || DIR=$PWD ;;
    1) case "$1" in -*) DIR= ;; *) DIR=$1 ;; esac
       [ -n "$DIR" ] || { echo "usage: pr-workflow-content.sh [<repository directory>]" >&2; exit 64; } ;;
    *) echo "usage: pr-workflow-content.sh [<repository directory>]" >&2; exit 64 ;;
esac
[ -d "$DIR" ] || { echo "pr-workflow-content: $DIR is not a directory" >&2; exit 2; }

for f in "$DIR/CLAUDE.local.md" "$DIR/CLAUDE.md"; do
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
        exit 0
    fi
done
echo omit
