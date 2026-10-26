#!/usr/bin/env bash
# after-release.sh -- Phase 7 of /release: the host installs a repository
# declares under `## After release` in its release extension, run once this
# run's own release is published.
#
# Usage:
#   after-release.sh plan <topic>
#   after-release.sh run <topic> [--tracked-approved] [--local-approved <n>]...
#
# The two halves are split so the skill can put its questions between them.
#
#   plan   reads the commands, waits for the release this run dispatched to be
#          published, reads the session's grant again, and stores what it will
#          run in release-<topic> (work/after, work/after-go), so `run` runs
#          exactly the commands the question showed. In order:
#
#          1. The commands. The tracked ones are the bullets under
#             `## After release` in .claude/shirabe-extensions/release.md as
#             committed at work/head (`git show <head>:<path>`), so an edit to
#             the working copy during a long run can't add one. The local ones
#             are the same heading in the untracked release.local.md. A
#             bullet's command is its first backtick span; a bullet with none
#             is skipped with a warning naming it on stderr. Neither file
#             naming any command means there is nothing to install: plan
#             prints nothing at all and exits 0.
#          2. The gate. The installs run only after this run dispatched the
#             release workflow (work/dispatched, written by `release-state.sh
#             mark`) and saw that run conclude success (work/concluded). A dry
#             run, a refused or failed dispatch, and a failed or unfinished
#             workflow leave one of them missing or different: plan prints
#             refused=not-dispatched or refused=workflow-<conclusion>, a
#             not-run line per command, and exits 2.
#          3. The wait. `gh release view v<version> --json isDraft,tagName`,
#             every RELEASE_AFTER_POLL_SECONDS (30) for up to
#             RELEASE_AFTER_WAIT_SECONDS (1800), until it names this run's tag
#             with isDraft false. A failed view, an answer naming another
#             tag, or the wait running out prints published=no
#             reason=<view-failed|wait-ran-out>, a not-run line per command,
#             and exits 3.
#          4. The grant, read again with release-grant.sh: a session that held
#             it at the go may not hold it now.
#
#          Prints, once published:
#            published=v<version>
#            go=grant dispatch=<id> | go=person reason=<token>
#            install tracked <n> <command>      one per tracked command
#            install local <n> <command>        one per local command
#
#   run    runs the commands plan stored, in order, tracked before local:
#          a tracked command runs when plan's grant line was go=grant, or with
#          --tracked-approved (a person's yes to the one question that lists
#          them); a local command runs only when --local-approved names its
#          <n>, for every session. Each runs from the repository root through
#          bash -c with stdin closed and
#            RELEASE_VERSION          work/dispatched, bare X.Y.Z
#            RELEASE_WORKSPACE_ROOT   the nearest directory strictly above the
#                                     repository root holding
#                                     .niwa/workspace.toml, or empty
#            RELEASE_DRY_RUN          0
#          The first command that exits non-zero stops the list: the ones
#          after it don't run, so a failed reinstall or version check never
#          reaches `niwa apply`. Prints one line per command,
#            result <passed|failed|not-run|declined> <tracked|local> <n> <command>
#          and after a failed one the last 20 lines of its output, each
#          prefixed "  | ". The output is the run's own report; it is never
#          copied into an issue or a pull request. run makes no gh call, so
#          the release stays published whatever happens here.
#
# Exit codes:
#   0    plan: nothing to install, or published and stored; run: every
#        command that ran passed
#   1    run: a command failed; either: a koto, git or gh operation failed,
#        or a key a phase writes is absent (named on stderr)
#   2    plan: refused, the installs aren't this run's to make
#   3    plan: the release wasn't seen published
#   64   usage error
#   127  koto, git, gh or jq is not on PATH
#
# Environment:
#   KOTO_BIN                     the koto binary (default: koto from PATH)
#   RELEASE_AFTER_WAIT_SECONDS   the publication wait, in seconds (1800)
#   RELEASE_AFTER_POLL_SECONDS   the poll interval, in seconds (30)
#   TMPDIR                       where temporary files are made
#
# Requires: bash 3.2+, git, jq, koto, and gh for plan. No eval, no
# associative arrays, no mapfile.

set -uo pipefail

PROG="after-release"

SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
BASH_BIN="${BASH:-bash}"
KOTO="${KOTO_BIN:-koto}"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_VERSION='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
RE_HEADING='^## After release[[:space:]]*$'
# shellcheck disable=SC2016 # literal backticks, nothing to expand
RE_SPAN='`([^`]+)`'
EXT_TRACKED=.claude/shirabe-extensions/release.md
EXT_LOCAL=.claude/shirabe-extensions/release.local.md

say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
    printf 'error=usage\n'
    say "$1"
    say "usage: after-release.sh plan <topic> | run <topic> [--tracked-approved] [--local-approved <n>]... (see the header of this script)"
    exit 64
}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'failed=%s_missing\n' "$1"
        say "$1 is not on PATH"
        exit 127
    fi
}

TMPD=""
cleanup() { [ -n "$TMPD" ] && rm -rf "$TMPD"; return 0; }
make_tmp() {
    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/after-release.XXXXXX") || { say "cannot make a temporary directory"; exit 1; }
    trap cleanup EXIT
}

# get_key <session> <key> -- print the key, or exit 1 naming it when absent.
get_key() {
    local rc=0
    "$KOTO" context exists "$1" "$2" >/dev/null || rc=$?
    case "$rc" in
        0) ;;
        1) say "$2 is absent from $1"; exit 1 ;;
        *) say "koto context exists $2 failed (exit $rc)"; exit 1 ;;
    esac
    "$KOTO" context get "$1" "$2" || { say "cannot read $2"; exit 1; }
}

# opt_key <session> <key> -- print the key, or nothing when it is absent.
opt_key() {
    local rc=0
    "$KOTO" context exists "$1" "$2" >/dev/null || rc=$?
    case "$rc" in
        0) "$KOTO" context get "$1" "$2" || { say "cannot read $2"; exit 1; } ;;
        1) ;;
        *) say "koto context exists $2 failed (exit $rc)"; exit 1 ;;
    esac
}

put_key() {
    "$KOTO" context add "$1" "$2" --from-file "$3" >/dev/null || { say "koto context add $2 failed"; exit 1; }
}

# bullets <kind> -- read an extension on stdin and print "<kind>\t<n>\t<command>"
# for each bullet under `## After release`, outside code fences.
bullets() {
    local kind="$1" line in=0 fence=0 n=0 cmd
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            '```'*) fence=$((1 - fence)); continue ;;
        esac
        [ "$fence" -eq 0 ] || continue
        case "$line" in
            '## '*)
                if [[ "$line" =~ $RE_HEADING ]]; then in=1; else in=0; fi
                continue
                ;;
        esac
        [ "$in" -eq 1 ] || continue
        case "$line" in
            '- '* | '* '*) ;;
            *) continue ;;
        esac
        if [[ "$line" =~ $RE_SPAN ]]; then
            cmd="${BASH_REMATCH[1]}"
            n=$((n + 1))
            printf '%s\t%s\t%s\n' "$kind" "$n" "$cmd"
        else
            say "warning: skipped a bullet under ## After release in the $kind extension with no command in backticks: $line"
        fi
    done
}

not_run_all() { # not_run_all <file>
    local kind n cmd
    while IFS='	' read -r kind n cmd; do
        printf 'not-run %s %s %s\n' "$kind" "$n" "$cmd"
    done <"$1"
}

# --- plan -------------------------------------------------------------------------------

cmd_plan() {
    local topic s top head version concluded wait poll waited view state grant kind n cmd
    [ "$#" -eq 1 ] || usage "plan takes <topic>"
    topic="$1"
    [[ "$topic" =~ $RE_TOPIC ]] || usage "topic must match $RE_TOPIC"
    need_tool "$KOTO"
    need_tool git
    need_tool jq
    s="release-$topic"
    top=$(git rev-parse --show-toplevel) || { say "not in a git work tree"; exit 1; }
    make_tmp

    head=$(get_key "$s" work/head) || exit 1
    head=$(printf '%s' "$head" | tr -d '[:space:]')
    : >"$TMPD/after"
    if git -C "$top" cat-file -e "$head:$EXT_TRACKED" 2>/dev/null; then
        git -C "$top" show "$head:$EXT_TRACKED" | bullets tracked >>"$TMPD/after"
    fi
    if [ -f "$top/$EXT_LOCAL" ]; then
        bullets local <"$top/$EXT_LOCAL" >>"$TMPD/after"
    fi
    [ -s "$TMPD/after" ] || exit 0

    version=$(opt_key "$s" work/dispatched | tr -d '[:space:]')
    concluded=$(opt_key "$s" work/concluded | tr -d '[:space:]')
    if ! [[ "$version" =~ $RE_VERSION ]]; then
        printf 'refused=not-dispatched\n'
        not_run_all "$TMPD/after"
        say "this run didn't dispatch a release workflow, so none of these installs ran"
        exit 2
    fi
    if [ "$concluded" != success ]; then
        printf 'refused=workflow-%s\n' "${concluded:-unknown}"
        not_run_all "$TMPD/after"
        say "the release workflow didn't conclude success (${concluded:-not recorded}), so none of these installs ran"
        exit 2
    fi

    wait="${RELEASE_AFTER_WAIT_SECONDS:-1800}"
    poll="${RELEASE_AFTER_POLL_SECONDS:-30}"
    case "$wait$poll" in *[!0-9]*) usage "RELEASE_AFTER_WAIT_SECONDS and RELEASE_AFTER_POLL_SECONDS take whole seconds" ;; esac
    [ "$poll" -gt 0 ] || poll=1
    need_tool gh
    waited=0
    while :; do
        if ! view=$(gh release view "v$version" --json isDraft,tagName </dev/null 2>"$TMPD/view.err"); then
            printf 'published=no reason=view-failed\n'
            not_run_all "$TMPD/after"
            say "gh release view v$version failed: $(tail -1 "$TMPD/view.err"); none of these installs ran"
            exit 3
        fi
        state=$(printf '%s' "$view" | jq -r --arg t "v$version" '
            if type == "object" and .tagName == $t and (.isDraft | type) == "boolean"
            then (if .isDraft then "draft" else "published" end) else "other" end' 2>/dev/null) || state=other
        case "$state" in
            published) break ;;
            draft) ;;
            *)
                printf 'published=no reason=view-failed\n'
                not_run_all "$TMPD/after"
                say "gh release view v$version answered something that isn't this release; none of these installs ran"
                exit 3
                ;;
        esac
        if [ "$waited" -ge "$wait" ]; then
            printf 'published=no reason=wait-ran-out\n'
            not_run_all "$TMPD/after"
            say "v$version isn't published yet after ${wait}s; these installs did not run, and can be run by hand once it is"
            exit 3
        fi
        sleep "$poll"
        waited=$((waited + poll))
    done

    grant=$("$BASH_BIN" "$SCRIPT_DIR/release-grant.sh")
    case "$grant" in
        "go=grant dispatch="* | "go=person reason="*) ;;
        *) grant="go=person reason=unreadable-answer" ;;
    esac
    printf '%s\n' "$grant" >"$TMPD/go"
    put_key "$s" work/after "$TMPD/after"
    put_key "$s" work/after-go "$TMPD/go"

    printf 'published=v%s\n' "$version"
    printf '%s\n' "$grant"
    while IFS='	' read -r kind n cmd; do
        printf 'install %s %s %s\n' "$kind" "$n" "$cmd"
    done <"$TMPD/after"
}

# --- run --------------------------------------------------------------------------------

cmd_run() {
    local topic s top tracked_ok=0 local_ok=" " version grant root d kind n cmd stopped=0 failed=0 rc
    [ "$#" -ge 1 ] || usage "run takes <topic>"
    topic="$1"
    shift
    [[ "$topic" =~ $RE_TOPIC ]] || usage "topic must match $RE_TOPIC"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --tracked-approved) tracked_ok=1 ;;
            --local-approved)
                [ "$#" -ge 2 ] || usage "--local-approved takes a command's number"
                case "$2" in '' | *[!0-9]*) usage "--local-approved takes a command's number" ;; esac
                local_ok="$local_ok$2 "
                shift
                ;;
            *) usage "unknown run argument: $1" ;;
        esac
        shift
    done
    need_tool "$KOTO"
    need_tool git
    s="release-$topic"
    top=$(git rev-parse --show-toplevel) || { say "not in a git work tree"; exit 1; }
    make_tmp

    get_key "$s" work/after >"$TMPD/after" || exit 1
    grant=$(get_key "$s" work/after-go) || exit 1
    version=$(get_key "$s" work/dispatched | tr -d '[:space:]') || exit 1
    [[ "$version" =~ $RE_VERSION ]] || { say "work/dispatched holds no version"; exit 1; }
    case "$grant" in "go=grant dispatch="*) tracked_ok=1 ;; esac

    root=
    d=${top%/*}
    while [ -n "$d" ]; do
        if [ -f "$d/.niwa/workspace.toml" ]; then root=$d; break; fi
        d=${d%/*}
    done

    while IFS='	' read -r kind n cmd; do
        [ -n "$kind" ] || continue
        if [ "$stopped" -eq 1 ]; then
            printf 'result not-run %s %s %s\n' "$kind" "$n" "$cmd"
            continue
        fi
        case "$kind" in
            tracked) [ "$tracked_ok" -eq 1 ] || { printf 'result declined %s %s %s\n' "$kind" "$n" "$cmd"; continue; } ;;
            *) case "$local_ok" in *" $n "*) ;; *) printf 'result declined %s %s %s\n' "$kind" "$n" "$cmd"; continue ;; esac ;;
        esac
        rc=0
        (cd "$top" && RELEASE_VERSION="$version" RELEASE_WORKSPACE_ROOT="$root" RELEASE_DRY_RUN=0 \
            "$BASH_BIN" -c "$cmd") </dev/null >"$TMPD/out" 2>&1 || rc=$?
        if [ "$rc" -eq 0 ]; then
            printf 'result passed %s %s %s\n' "$kind" "$n" "$cmd"
        else
            printf 'result failed %s %s %s\n' "$kind" "$n" "$cmd"
            tail -20 "$TMPD/out" | sed 's/^/  | /'
            stopped=1
            failed=1
        fi
    done <"$TMPD/after"
    [ "$failed" -eq 0 ]
}

# --- dispatch ---------------------------------------------------------------------------

[ "$#" -ge 1 ] || usage "a subcommand is required"
sub="$1"
shift
case "$sub" in
    plan) cmd_plan "$@" ;;
    run) cmd_run "$@" ;;
    *) usage "unknown subcommand: $sub" ;;
esac
