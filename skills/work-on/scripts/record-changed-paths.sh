#!/usr/bin/env bash
# record-changed-paths.sh -- for /work-on: record which paths the implementation
# changed, as mechanical facts for the issue-type question.
#
# `/work-on` asks one routing question after implementation: is this issue
# `code`, `docs`, or `task`? The answer is a judgment, but what it's judged
# against is not. This script records the part git can answer -- where the work
# started and which paths it touched -- so the question is asked with the facts
# already in context and nothing has to be reconstructed by hand.
#
# The template runs it twice, as two `default_action`s:
#
#   --base  <session>   on `analysis`: records `impl_base`, the commit the work
#                       starts from. Written once. Every later entry (a
#                       scope_changed_retry lap, a scope_expanded_retry return)
#                       leaves the stored SHA alone, so commits made during
#                       implementation never move the base.
#
#   --write <session>   on `changed_paths_record`: writes `changed_paths.txt`,
#                       the paths changed between the base and HEAD. That
#                       state's `changed_paths_recorded` gate reads the key.
#
# Usage: record-changed-paths.sh --base  <koto-session-name>
#        record-changed-paths.sh --write <koto-session-name>
#
# ## The base
#
# `--write` uses `impl_base` when it is set. On a shared branch that is what
# keeps a sibling's commits out: the orchestrator's other children commit to
# the same branch, and every commit they made before this run reached
# `analysis` is behind `impl_base`, so none of them appears here.
# Limitation: a rebase after `analysis` can leave `impl_base` off HEAD's history; the diff then includes what the rebase pulled in.
#
# When `impl_base` is unset (the `analysis` action failed and the agent went on
# without it), the base is `git merge-base HEAD origin/<default-branch>`, where
# the default branch is what `origin/HEAD` names, or `main` when origin names
# none. With no usable origin ref at all it falls back to `git merge-base HEAD
# main`. A shared branch loses its sibling filtering on this path; the file
# still records which base it used.
#
# ## Output
#
# Nothing on stdout. One context key, `changed_paths.txt`:
#
#   base: <sha>
#   commits: <n>
#   <one `git diff --name-status -M <base> HEAD` line per path>
#
# `commits` counts `<base>..HEAD`. Rename detection is on, so a moved file is a
# single `R<score>` line rather than a delete and an add. The path lines are
# capped at 200 and the whole file at 8192 bytes; when either cap cuts it, the
# last line is `... N more paths`, with N the exact number of path lines left
# out. The file records paths and statuses only. It never classifies them --
# deciding what a change set means is the question's job, not this script's.
#
# Diagnostics go to stderr.
#
# Exit codes:
#   0  -- `--base`: impl_base written, or already present and left untouched
#         `--write`: changed_paths.txt written
#   64 -- no base resolves: not a git repository, no commit at HEAD, or (for
#         `--write` with impl_base unset) no merge-base with origin's default
#         branch or local main. `--write` also removes a changed_paths.txt left
#         by an earlier lap, so the gate reads the key as absent rather than
#         passing on paths from a previous round.
#   66 -- a `koto context add` failed; koto's own stderr says why
#   67 -- the mode or the session argument is missing or unrecognised
#
# On 64 or 67 no changed_paths.txt is written.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

MAX_LINES=200
MAX_BYTES=8192

die() {
    # $1 exit code, $2 message
    echo "record-changed-paths: $2" >&2
    exit "$1"
}

MODE="${1:-}"
SESSION="${2:-}"

case "$MODE" in
    --base|--write) ;;
    "") die 67 "missing mode: expected --base or --write" ;;
    *)  die 67 "unrecognised mode [$MODE]: expected --base or --write" ;;
esac
[ -n "$SESSION" ] || die 67 "missing session argument for $MODE"

git rev-parse --git-dir >/dev/null || die 64 "not inside a git repository"

# ---------------------------------------------------------------- --base ------

if [ "$MODE" = "--base" ]; then
    # An existing value is never rewritten: the base is where the work started,
    # and a re-entry into analysis after commits must not move it forward past
    # them. `koto context exists` exits 1, silently, for an absent key.
    if koto context exists "$SESSION" impl_base; then
        exit 0
    fi
    head=$(git rev-parse --verify -q "HEAD^{commit}") \
        || die 64 "HEAD does not name a commit; nothing to record as impl_base"
    printf '%s\n' "$head" | koto context add "$SESSION" impl_base >/dev/null \
        || die 66 "koto context add failed for impl_base on session [$SESSION]"
    exit 0
fi

# ---------------------------------------------------------------- --write -----

# A changed_paths.txt from an earlier lap must not survive a failed recompute:
# the state's gate would find it and route on the previous round's paths.
no_base() {
    koto context remove "$SESSION" changed_paths.txt >/dev/null
    die 64 "$1"
}

git rev-parse --verify -q "HEAD^{commit}" >/dev/null \
    || no_base "HEAD does not name a commit"

BASE=""
stored=""
if koto context exists "$SESSION" impl_base; then
    stored=$(koto context get "$SESSION" impl_base | tr -d '[:space:]')
fi
if [ -n "$stored" ]; then
    if BASE=$(git rev-parse --verify -q "${stored}^{commit}"); then
        :
    else
        BASE=""
        echo "record-changed-paths: impl_base [$stored] is not a commit in this repository; falling back to the merge-base" >&2
    fi
fi

if [ -z "$BASE" ]; then
    # origin's default branch: what origin/HEAD points at, else origin/main.
    default_ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD)
    if [ -z "$default_ref" ] && git rev-parse --verify -q "refs/remotes/origin/main^{commit}" >/dev/null; then
        default_ref=origin/main
    fi
    if [ -n "$default_ref" ]; then
        BASE=$(git merge-base HEAD "$default_ref")
    fi
    if [ -z "$BASE" ] && git rev-parse --verify -q "refs/heads/main^{commit}" >/dev/null; then
        BASE=$(git merge-base HEAD main)
    fi
fi
[ -n "$BASE" ] || no_base "no base resolves: impl_base is unset and HEAD shares no history with origin's default branch or local main"

COMMITS=$(git rev-list --count "$BASE..HEAD") || no_base "could not count commits in $BASE..HEAD"

WORK=$(mktemp -d) || die 64 "could not create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

git diff --name-status -M "$BASE" HEAD > "$WORK/paths" \
    || no_base "git diff --name-status -M $BASE HEAD failed"

# Apply both caps. The header counts toward the byte cap. When something is
# cut, the trailer's worst-case size (the total path count has at least as many
# digits as the omitted count) is reserved up front, so appending it can never
# push the file past the cap. LC_ALL=C makes length() count bytes.
LC_ALL=C awk -v base="$BASE" -v commits="$COMMITS" \
    -v max_lines="$MAX_LINES" -v max_bytes="$MAX_BYTES" '
    { line[NR] = $0 }
    END {
        header = "base: " base "\ncommits: " commits "\n"
        used = length(header)
        total = NR
        full = used
        for (i = 1; i <= total; i++) full += length(line[i]) + 1
        if (total <= max_lines && full <= max_bytes) {
            printf "%s", header
            for (i = 1; i <= total; i++) print line[i]
            exit
        }
        budget = max_bytes - length("... " total " more paths\n")
        kept = 0
        for (i = 1; i <= total; i++) {
            if (kept >= max_lines) break
            if (used + length(line[i]) + 1 > budget) break
            used += length(line[i]) + 1
            kept++
        }
        printf "%s", header
        for (i = 1; i <= kept; i++) print line[i]
        print "... " (total - kept) " more paths"
    }
' "$WORK/paths" > "$WORK/changed_paths.txt"

koto context add "$SESSION" changed_paths.txt < "$WORK/changed_paths.txt" >/dev/null \
    || die 66 "koto context add failed for changed_paths.txt on session [$SESSION]"
exit 0
