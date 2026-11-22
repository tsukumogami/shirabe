#!/usr/bin/env bash
# step-draft.sh -- the next step's draft, written by the step agent that just
# finished, and the owner's record that a step is ready to start.
#
# Under /execute's lead shape the owning session details each step after the
# first before its agent starts, and records the entry as committed in
# `step_refine/<step>.md` (koto-templates/execute.md, spawn_and_await). The
# step agent that just finished knows what its step landed, so it drafts the
# entry of each outlined step that waits only on its own step, and stores the
# draft here as `step_draft/<step>.md` in the owning session. The draft is
# untrusted input: its author has read issue text and code. The owner checks it
# against the DESIGN and the PLAN's outline for that step, edits it if needed,
# and records the step_refine key from it as before. A draft never starts a
# step; only the owner's record does.
#
# A step id becomes part of a context key here and, under concurrent steps, a
# worktree directory and a branch name, so every subcommand refuses an id
# outside ^[a-z0-9][a-z0-9-]{0,62}$ before it reads or writes anything. The
# owning session runs `id` on a step and on every step it names for drafting
# before it starts that step's agent (execute.md, "The hand-off"), and starts
# none for an id refused here: the step stops before any key, worktree or
# branch exists for it, which is earlier than a hold at the child's
# validation_exit, since no child state is entered at all.
#
# Usage:
#   step-draft.sh id <step>
#   step-draft.sh write <session> <step> <file>
#   step-draft.sh ready <session> <step>
#
#   id     exits 0 for a valid step id, 1 naming the id otherwise.
#   write  stores <file> as step_draft/<step>.md in <session> (the owning
#          session, execute-<plan-slug>). Nothing is written for a bad id or an
#          unreadable file.
#   ready  exits 0 when step_refine/<step>.md exists in <session>, 1 naming the
#          step when it doesn't, a draft or not.
#
# Exit codes: 0 done, 1 refused (a bad id, an unreadable file, no record yet;
# koto answers a missing session the same as a missing key, so `ready` on a
# session that doesn't exist also exits 1), 2 a koto call failed, 64 usage (a
# wrong argument count, an unknown subcommand, or a session name outside
# [A-Za-z0-9._-]).
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

RE_STEP='^[a-z0-9][a-z0-9-]{0,62}$'
RE_SESSION='^[A-Za-z0-9._-]+$'

usage() { sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
die() { echo "step-draft: $2" >&2; exit "$1"; }

check_id() {
    [[ $1 =~ $RE_STEP ]] || die 1 "refused step id [$1]: a step id matches $RE_STEP"
}
check_session() {
    [[ $1 =~ $RE_SESSION ]] || usage
}

[ $# -ge 1 ] || usage
cmd=$1; shift
case "$cmd" in
    id)
        [ $# -eq 1 ] || usage
        check_id "$1"
        ;;
    write)
        [ $# -eq 3 ] || usage
        check_session "$1"; check_id "$2"
        [ -r "$3" ] || die 1 "cannot read the draft file [$3]"
        command -v koto >/dev/null || die 2 "the koto CLI is not on PATH"
        koto context add "$1" "step_draft/$2.md" --from-file "$3" >/dev/null \
            || die 2 "koto could not store step_draft/$2.md in $1"
        echo "drafted=$2"
        ;;
    ready)
        [ $# -eq 2 ] || usage
        check_session "$1"; check_id "$2"
        command -v koto >/dev/null || die 2 "the koto CLI is not on PATH"
        # koto answers 0 present and 1 absent, saying nothing; anything it does
        # print, or any other exit, is a failed check, shown as koto wrote it.
        rc=0
        out=$(koto context exists "$1" "step_refine/$2.md" 2>&1) || rc=$?
        if [ "$rc" -gt 1 ] || { [ "$rc" -eq 1 ] && [ -n "$out" ]; }; then
            [ -n "$out" ] && printf '%s\n' "$out" >&2
            die 2 "koto could not check step_refine/$2.md in $1 (exit $rc)"
        fi
        case "$rc" in
            0) echo "ready=$2" ;;
            1) die 1 "step $2 has no step_refine/$2.md in $1: the owner records the entry before the step starts" ;;
        esac
        ;;
    *) usage ;;
esac
exit 0
