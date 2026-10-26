#!/usr/bin/env bash
# release-grant.sh -- does this session hold cut-release, so /release can take
# the version-and-notes go from its grant instead of asking a person?
#
# Usage: release-grant.sh        (no arguments)
#
# Prints exactly one line on stdout and exits 0 in every case, so a caller
# reads the line, never the exit code:
#
#   go=grant dispatch=<dispatch id>
#       niwa answered `bound` for this session, the grant names cut-release,
#       and the cut-release point reads decider `session` and author
#       exclusion `off`.
#   go=person reason=<token>
#       anything else, with the token one of:
#         no-niwa            no absolute niwa from `command -v niwa`, nor an
#                            absolute executable $NIWA_BIN, outside the
#                            repository's working tree
#         no-session-id      CLAUDE_CODE_SESSION_ID is unset or empty
#         no-instance-root   no directory at or above the repository root
#                            holds .niwa/instance.json
#         lookup-failed      niwa exited non-zero (an `authority` command
#                            without `check` included) or ran past the bound
#         unreadable-answer  the answer isn't exactly one
#                            niwa.authority.check/v1 document with every
#                            state, authority, level, decider and
#                            author-exclusion value in niwa's vocabularies and
#                            any dispatch_id a lowercase UUID (or jq is
#                            missing, so it can't be read)
#         not-dispatched     niwa didn't dispatch this session
#         record-unusable    the session's dispatch record can't be used
#         not-held           the grant doesn't name cut-release
#         decider-dispatcher cut-release is settled by the dispatcher
#         decider-person     cut-release is settled by a person
#         author-exclusion   cut-release carries author exclusion
#
# The lookup is one call, made only when niwa, the session id and the
# instance root are all found:
#
#   niwa authority check --json --session "$CLAUDE_CODE_SESSION_ID" \
#       -C <instance root> --point cut-release
#
# with stdin closed and its output in a mktemp file removed on every exit,
# under `timeout -s KILL` or, where timeout isn't installed (macOS), a
# background job and a KILL watcher. The bound is 3 seconds, or
# NIWA_LOOKUP_SECONDS when that is 1 or 2, as the workspace gate reads it.
# KILL is what bounds it: a niwa that traps TERM can't hold the caller.
#
# A niwa whose resolved path (symlinks followed) lies under the repository's
# working tree is never run: a committed settings file can point PATH or
# NIWA_BIN there. The instance root is the nearest directory at or above
# `git rev-parse --show-toplevel` holding .niwa/instance.json; niwa itself
# resolves an outer instance from there.
#
# The answer is advisory. The session id comes from the environment and the
# instance from the working directory, both the session's own to change, so a
# session could make this print go=grant falsely. That costs only the skill's
# own questions: the gate reads the hook payload's session id and its own
# installed path, and still decides the draft and the dispatch.
#
# Needs bash 3.2+, git and jq; never koto. Without niwa it prints go=person.

set -u

say() { printf '%s\n' "$1"; exit 0; }
person() { say "go=person reason=$1"; }

# resolve <path>: the path with every symlink followed, as an absolute path
# whose directories are physical. Fails when a directory can't be entered.
resolve() {
    local p="$1" t n=0 d
    while [ -L "$p" ] && [ "$n" -lt 40 ]; do
        t=$(readlink "$p") || return 1
        case "$t" in
            /*) p=$t ;;
            *) p="${p%/*}/$t" ;;
        esac
        n=$((n + 1))
    done
    d=$(cd -P -- "${p%/*}/" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "${d%/}" "${p##*/}"
}

TOP=$(git rev-parse --show-toplevel 2>/dev/null) && TOP=$(cd -P -- "$TOP" 2>/dev/null && pwd -P) || TOP=

# usable <candidate>: an absolute, executable file outside the working tree.
usable() {
    local r
    case "$1" in /*) ;; *) return 1 ;; esac
    [ -f "$1" ] && [ -x "$1" ] || return 1
    r=$(resolve "$1") || return 1
    if [ -n "$TOP" ]; then
        case "$r/" in "$TOP"/*) return 1 ;; esac
    fi
    return 0
}

NIWA=
c=$(command -v niwa 2>/dev/null) || c=
if usable "$c"; then
    NIWA=$c
elif usable "${NIWA_BIN:-}"; then
    NIWA=$NIWA_BIN
fi
[ -n "$NIWA" ] || person no-niwa

[ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || person no-session-id

ROOT=
if [ -n "$TOP" ]; then
    d=$TOP
    while :; do
        if [ -f "$d/.niwa/instance.json" ]; then ROOT=$d; break; fi
        [ "$d" = / ] && break
        d=${d%/*}
        [ -n "$d" ] || d=/
    done
fi
[ -n "$ROOT" ] || person no-instance-root

case "${NIWA_LOOKUP_SECONDS:-}" in
    1 | 2) SECS=$NIWA_LOOKUP_SECONDS ;;
    *) SECS=3 ;;
esac

DOC=$(mktemp "${TMPDIR:-/tmp}/release-grant.XXXXXX" 2>/dev/null) || person lookup-failed
trap 'rm -f "$DOC"' EXIT
trap 'rm -f "$DOC"; exit 0' HUP INT TERM

set -- authority check --json --session "$CLAUDE_CODE_SESSION_ID" -C "$ROOT" --point cut-release
if command -v timeout >/dev/null 2>&1; then
    timeout -s KILL "$SECS" "$NIWA" "$@" </dev/null >"$DOC" 2>/dev/null
    rc=$?
else
    "$NIWA" "$@" </dev/null >"$DOC" 2>/dev/null &
    pid=$!
    (sleep "$SECS"; kill -KILL "$pid") </dev/null >/dev/null 2>&1 &
    watcher=$!
    wait "$pid" 2>/dev/null
    rc=$?
    kill "$watcher" 2>/dev/null
fi
[ "$rc" -eq 0 ] || person lookup-failed

command -v jq >/dev/null 2>&1 || person unreadable-answer

# Exactly one document, every value from niwa's vocabularies (an answer
# holding anything unknown is from a niwa this script doesn't understand, and
# none of it is trusted), and any dispatch_id a lowercase UUID.
LINE=$(jq -r -s '
    def oneof($set): . as $v | any($set[]; . == $v);
    def uuid: type == "string"
        and test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
    if length != 1 then error("not one document") else .[0] end
    | if type != "object" or .schema != "niwa.authority.check/v1" then error("schema") else . end
    | if (.state | oneof(["bound", "record-unusable", "not-dispatched"])) then . else error("state") end
    | if has("dispatch_id") and (.dispatch_id | uuid | not) then error("dispatch_id") else . end
    | if .state != "bound" then "go=person reason=\(.state)"
      else
        (.grant | if type == "array" then . else error("grant") end) as $grant
        | if all($grant[]; type == "object"
                and (.authority | oneof(["merge-pr", "close-issue", "cut-release"])))
          then . else error("authority") end
        | if (.level | oneof(["autonomous", "supervised", "strict"])) then . else error("level") end
        | (.points | if type == "array" then . else error("points") end) as $points
        | if all($points[]; type == "object"
                and (.decider | oneof(["session", "dispatcher", "person"]))
                and (.author_exclusion | oneof(["on", "off"])))
          then . else error("point") end
        | if (.dispatch_id | uuid) then . else error("dispatch_id") end
        | if (any($grant[]; .authority == "cut-release") | not) then "go=person reason=not-held"
          else
            ([$points[] | select(.point == "cut-release")] | .[0]
              | if . == null then error("no cut-release point") else . end) as $p
            | if $p.decider == "dispatcher" then "go=person reason=decider-dispatcher"
              elif $p.decider == "person" then "go=person reason=decider-person"
              elif $p.author_exclusion == "on" then "go=person reason=author-exclusion"
              else "go=grant dispatch=\(.dispatch_id)"
              end
          end
      end' "$DOC" 2>/dev/null) || person unreadable-answer

case "$LINE" in
    "go=grant dispatch="* | "go=person reason="*) say "$LINE" ;;
    *) person unreadable-answer ;;
esac
