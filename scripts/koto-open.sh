#!/usr/bin/env bash
# koto-open.sh -- the one koto entry every koto-backed skill in the tactical
# chain goes through: exactly one `koto init` call, four outcomes.
#
# A skill that enters the same session on every invocation does not read the
# session first and decide what to do. It writes its variables to an args file,
# calls this script, and reads the one result line it prints:
#
#   a new session                            opened=new
#   an attached live session                 opened=attached
#   a fresh session replacing a finished one opened=replaced
#   a refusal with a typed koto error        refused=<code>
#
# koto makes every decision (template, origin record, fixed variables, the
# request leg). This script builds the call, keeps user tokens out of any
# shell, removes the args file, and renders koto's refusal in the caller's
# wording. The per-skill thin wrappers (scope-open.sh, /execute's entry,
# deliver-open.sh) sit on top of it.
#
# Usage:
#   koto-open.sh <session> <template> <args-file>
#                [--attach-live] [--replace-terminal]
#                [--koto-leg <request-id>:<leg>] [--wording <file>]
#   koto-open.sh --alloc-dir
#
# Arguments:
#   <session>     the koto session name. ^[A-Za-z0-9][A-Za-z0-9._-]*$, so it
#                 can never be read as an option.
#   <template>    the template path passed to `koto init --template`.
#   <args-file>   a JSON list of ["NAME", "VALUE"] string pairs, built by the
#                 caller with jq, e.g. [["TOPIC","t1"],["MERGE","true"]]. A
#                 list, not an object, so a flag given twice stays two pairs
#                 and koto refuses it as duplicate_var. The script never reads
#                 a value out of it: the file reaches koto only through
#                 --vars-file. It must lie outside the work tree (see
#                 Location), and it is REMOVED on every exit path.
#   --attach-live       passed through: attach to a running session whose
#                       template, origin record, and explicitly passed
#                       non-rebind variables match; rebind variables are
#                       re-applied in the same step.
#   --replace-terminal  passed through: replace a finished session.
#   --koto-leg <request-id>:<leg>
#                       passed through (as `--koto-leg <request-id>:<leg>`)
#                       after the value is checked against koto's grammars:
#                       request id ^[a-z0-9_-]{1,64}$, leg ^[A-Za-z0-9_-]{1,64}$,
#                       neither starting with `-`. A malformed value is a usage
#                       error and no koto call is made. Under this flag koto
#                       records a refusal on the leg itself; this script never
#                       writes to the request store.
#   --wording <file>    the caller's wording table (see Rendering).
#   --alloc-dir         print the path of a new private directory (mode 0700,
#                       from `mktemp -d`) for the caller to write its args file
#                       into, and exit 0. When the args file later passed to
#                       this script sits in such a directory, the directory is
#                       removed along with the file.
#
# Location. The args file's resolved path (symlinks and `..` segments
# followed) must not lie inside `git rev-parse --show-toplevel` of the current
# directory. The koto session directory (`koto session dir <name>`) and a
# private `mktemp -d` directory are both outside it. An args file inside the
# work tree is refused before any koto call (refused=args_file_in_work_tree,
# exit 2), and it is still removed, unless git tracks it.
#
# Output. stdout carries machine-readable lines only, the result line first:
#
#   opened=new|attached|replaced
#   rebound=<compact JSON object>    attached: the rebind variables koto
#                                    re-applied, as koto reported them
#   replaced_state=<state>           replaced: the old session's final state
#   replaced_result=<compact JSON>   replaced: the old session's workflow
#                                    result (`null` when it recorded none);
#                                    this is what the caller may print
#   leg=<compact JSON object>        under --koto-leg, on success
#
#   refused=<code>                   koto's typed error code (invalid_var,
#                                    duplicate_var, unknown_var, var_mismatch,
#                                    template_mismatch, origin_mismatch,
#                                    session_live, session_terminal,
#                                    invalid_vars_file, leg_* and the rest),
#                                    `already_exists` for koto's untyped
#                                    "already exists" refusal, or this
#                                    script's own args_file_in_work_tree
#   failed=<kind>                    koto_missing, jq_missing, koto_crashed
#                                    (no parseable output), koto_error (a
#                                    non-zero exit with no typed code)
#   error=usage                      this script's own usage error
#
# The human-readable message goes to stderr: on a refusal, the rendered
# wording; on failure or usage error, a diagnostic.
#
# Rendering. A refusal is rendered from the caller's wording table when it
# maps the code, and from koto's own `error` message otherwise, so an unmapped
# code never prints nothing. The table is a file of `<code><TAB><text>` lines
# (`#` lines and blank lines ignored; the first line for a code wins). In
# <text>, `\n` is a newline, `\t` a tab, `\\` a backslash, and these
# placeholders are replaced with koto's fields, never evaluated:
#   {session} {var} {value} {constraint} {recorded} {requested} {state} {error}
# One exception is fixed: an origin_mismatch against a session with NO origin
# record (created by a koto older than the entry flags) always prints koto's
# own message, which tells the user to finish the session with the koto that
# started it or remove it with `koto session cleanup <name>`. A generic
# mismatch wording would hide the only way out.
#
# Exit codes:
#   0    opened (new, attached, or replaced)
#   2    refused: koto's refusal (koto's own exit code passes through when it
#        is not 2, e.g. 1 for template_not_found or lock_contention), or an
#        args file inside the work tree
#   64   this script's own usage error; no koto call was made
#   127  koto or jq is not on PATH; no koto call was made
#   other  koto's exit code on a failure with no typed code
#   130/143  interrupted by SIGINT/SIGTERM (koto is stopped, the file removed)
#
# Environment:
#   KOTO_BIN   the koto binary to run (default: `koto` from PATH)
#
# Requires: bash 3.2+, jq. No eval anywhere, and no token from the args file
# is ever interpolated into a command line.

set -uo pipefail

PROG=koto-open

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_REQ='^[a-z0-9_][a-z0-9_-]{0,63}$'
RE_LEG='^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$'
ALLOC_MARKER=".koto-open-alloc"

ARGS_FILE=""
WORK=""
KPID=""

# One cleanup for every exit path, installed before the args file is touched.
cleanup() {
    if [ -n "$KPID" ]; then
        kill -TERM "$KPID" 2>/dev/null
        KPID=""
    fi
    if [ -n "$ARGS_FILE" ]; then
        remove_args_file
        ARGS_FILE=""
    fi
    if [ -n "$WORK" ]; then
        rm -rf -- "$WORK"
        WORK=""
    fi
    return 0
}

on_signal() {
    cleanup
    trap - EXIT
    exit "$1"
}

trap cleanup EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

# remove_args_file -- remove the args file, and the directory --alloc-dir made
# for it. A file git tracks is left alone: that is not an args file a skill
# wrote, it is a caller passing the wrong path, and deleting it would be worse
# than the refusal already printed.
remove_args_file() {
    local f="$ARGS_FILE" dir
    [ -e "$f" ] || [ -L "$f" ] || return 0
    [ -d "$f" ] && [ ! -L "$f" ] && return 0
    if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
        return 0
    fi
    rm -f -- "$f"
    dir=$(dirname -- "$f")
    if [ -f "$dir/$ALLOC_MARKER" ] && [ ! -L "$dir/$ALLOC_MARKER" ]; then
        rm -f -- "$dir/$ALLOC_MARKER"
        rmdir -- "$dir" 2>/dev/null
    fi
    return 0
}

usage_error() {
    printf 'error=usage\n'
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: koto-open.sh <session> <template> <args-file> [--attach-live] [--replace-terminal] [--koto-leg <request-id>:<leg>] [--wording <file>]\n' >&2
    exit 64
}

# resolve_path <path> -- print the physical absolute path, following symlinks
# on the file itself and on every directory above it.
resolve_path() {
    local p="$1" d b t n=0
    while [ -L "$p" ]; do
        n=$((n + 1))
        [ "$n" -le 40 ] || return 1
        t=$(readlink -- "$p") || return 1
        case "$t" in
            /*) p="$t" ;;
            *) p="$(dirname -- "$p")/$t" ;;
        esac
    done
    d=$(dirname -- "$p")
    b=$(basename -- "$p")
    d=$(cd -P -- "$d" 2>/dev/null && pwd -P) || return 1
    case "$b" in
        .|..) d=$(cd -P -- "$d/$b" 2>/dev/null && pwd -P) || return 1; printf '%s' "$d"; return 0 ;;
    esac
    if [ "$d" = "/" ]; then
        printf '/%s' "$b"
    else
        printf '%s/%s' "$d" "$b"
    fi
}

# --- the --alloc-dir mode ----------------------------------------------------

if [ "$#" -eq 1 ] && [ "$1" = "--alloc-dir" ]; then
    d=$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/koto-open-args.XXXXXX") || { printf 'error=usage\n'; printf '%s: mktemp -d failed\n' "$PROG" >&2; exit 64; }
    chmod 0700 "$d" || { rmdir -- "$d"; printf 'error=usage\n'; exit 64; }
    : >"$d/$ALLOC_MARKER"
    printf '%s\n' "$d"
    exit 0
fi

# --- arguments ---------------------------------------------------------------

SESSION=""
TEMPLATE=""
POS=0
ATTACH_LIVE=0
REPLACE_TERMINAL=0
KOTO_LEG=""
HAVE_LEG=0
WORDING=""
BAD=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --attach-live) ATTACH_LIVE=1 ;;
        --replace-terminal) REPLACE_TERMINAL=1 ;;
        --koto-leg)
            if [ "$#" -lt 2 ]; then BAD="--koto-leg needs <request-id>:<leg>"; shift; continue; fi
            KOTO_LEG="$2"; HAVE_LEG=1; shift ;;
        --koto-leg=*) KOTO_LEG="${1#--koto-leg=}"; HAVE_LEG=1 ;;
        --wording)
            if [ "$#" -lt 2 ]; then BAD="--wording needs a file"; shift; continue; fi
            WORDING="$2"; shift ;;
        --wording=*) WORDING="${1#--wording=}" ;;
        --alloc-dir) [ -n "$BAD" ] || BAD="--alloc-dir takes no other argument" ;;
        --*) [ -n "$BAD" ] || BAD="unknown option: $1" ;;
        *)
            POS=$((POS + 1))
            case "$POS" in
                1) SESSION="$1" ;;
                2) TEMPLATE="$1" ;;
                3) ARGS_FILE="$1" ;;
                *) [ -n "$BAD" ] || BAD="unexpected argument: $1" ;;
            esac
            ;;
    esac
    shift
done

# From here on ARGS_FILE, when given, is removed by the EXIT trap whatever
# happens next, usage errors included.
[ -z "$BAD" ] || usage_error "$BAD"
[ "$POS" -eq 3 ] || usage_error "expected <session> <template> <args-file>"
[[ "$SESSION" =~ $RE_SESSION ]] || usage_error "session name must match $RE_SESSION"
[ -n "$TEMPLATE" ] || usage_error "empty template path"
[ -n "$ARGS_FILE" ] || usage_error "empty args-file path"
if [ "$HAVE_LEG" -eq 1 ]; then
    case "$KOTO_LEG" in
        *:*) ;;
        *) usage_error "--koto-leg must be <request-id>:<leg>" ;;
    esac
    LEG_REQ="${KOTO_LEG%%:*}"
    LEG_NAME="${KOTO_LEG#*:}"
    [[ "$LEG_REQ" =~ $RE_REQ ]] || usage_error "--koto-leg request id must match $RE_REQ"
    [[ "$LEG_NAME" =~ $RE_LEG ]] || usage_error "--koto-leg leg name must match $RE_LEG"
fi
if [ -n "$WORDING" ] && [ ! -f "$WORDING" ]; then
    usage_error "wording table not found: $WORDING"
fi
case "$TEMPLATE" in
    -*) TEMPLATE="./$TEMPLATE" ;;
esac

# --- location: never inside the work tree ------------------------------------

ARGS_INSIDE=0
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || TOPLEVEL=""
if [ -n "$TOPLEVEL" ]; then
    TOPLEVEL=$(cd -P -- "$TOPLEVEL" 2>/dev/null && pwd -P) || TOPLEVEL=""
fi
RESOLVED=$(resolve_path "$ARGS_FILE") || RESOLVED=""
if [ -z "$RESOLVED" ]; then
    # Nothing to resolve (a missing directory, a symlink loop). koto refuses
    # what it cannot read as invalid_vars_file; the location rule can only be
    # applied to a path that exists.
    RESOLVED="$ARGS_FILE"
fi
if [ -n "$TOPLEVEL" ]; then
    case "$RESOLVED" in
        "$TOPLEVEL"|"$TOPLEVEL"/*) ARGS_INSIDE=1 ;;
    esac
fi
if [ "$ARGS_INSIDE" -eq 1 ]; then
    printf 'refused=args_file_in_work_tree\n'
    printf '%s: the args file %s lies inside the work tree %s; write it to the koto session directory or a private mktemp -d directory\n' \
        "$PROG" "$ARGS_FILE" "$TOPLEVEL" >&2
    exit 2
fi

# koto reads the file itself; hand it an absolute path so a relative one can
# never be read as an option.
case "$ARGS_FILE" in
    /*) VARS_PATH="$ARGS_FILE" ;;
    *) VARS_PATH="$(pwd -P)/$ARGS_FILE" ;;
esac

# --- tools -------------------------------------------------------------------

KOTO="${KOTO_BIN:-koto}"
if ! command -v "$KOTO" >/dev/null 2>&1; then
    printf 'failed=koto_missing\n'
    printf '%s: koto is not on PATH; install it with `tsuku install koto`\n' "$PROG" >&2
    exit 127
fi
if ! command -v jq >/dev/null 2>&1; then
    printf 'failed=jq_missing\n'
    printf '%s: jq is not on PATH\n' "$PROG" >&2
    exit 127
fi

WORK=$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/koto-open.XXXXXX") || { printf 'failed=koto_error\n'; printf '%s: mktemp -d failed\n' "$PROG" >&2; exit 1; }

# --- the one koto init call --------------------------------------------------

set -- init "$SESSION" --template "$TEMPLATE" --vars-file "$VARS_PATH"
[ "$ATTACH_LIVE" -eq 1 ] && set -- "$@" --attach-live
[ "$REPLACE_TERMINAL" -eq 1 ] && set -- "$@" --replace-terminal
[ "$HAVE_LEG" -eq 1 ] && set -- "$@" --koto-leg "$KOTO_LEG"

# Run in the background and wait, so SIGINT/SIGTERM reach the trap at once
# instead of after koto returns.
"$KOTO" "$@" >"$WORK/out" 2>"$WORK/err" </dev/null &
KPID=$!
wait "$KPID"
RC=$?
KPID=""

OUT="$WORK/out"

# jq_field <key> -- set FIELD to a top-level field of koto's JSON, strings raw
# and anything else as compact JSON, preserving every byte (a trailing newline
# included). Absent or null reads as empty.
FIELD=""
jq_field() {
    FIELD=$(jq -j --arg k "$1" '.[$k] // "" | if type == "string" then . else tojson end' <"$OUT" 2>/dev/null; printf '.')
    FIELD="${FIELD%.}"
}

if ! jq -e 'type == "object"' <"$OUT" >/dev/null 2>&1; then
    printf 'failed=koto_crashed\n'
    printf '%s: koto init exited %s with no parseable output\n' "$PROG" "$RC" >&2
    [ -s "$WORK/err" ] && sed 's/^/  koto: /' "$WORK/err" >&2
    [ "$RC" -ne 0 ] || RC=1
    exit "$RC"
fi

# --- success -----------------------------------------------------------------

if [ "$RC" -eq 0 ]; then
    jq_field outcome
    case "$FIELD" in
        created) printf 'opened=new\n' ;;
        attached) printf 'opened=attached\n' ;;
        replaced) printf 'opened=replaced\n' ;;
        *)
            printf 'failed=koto_error\n'
            printf '%s: koto init exited 0 with an unrecognized outcome\n' "$PROG" >&2
            exit 1
            ;;
    esac
    if [ "$FIELD" = "attached" ]; then
        printf 'rebound=%s\n' "$(jq -c '.rebound // {}' <"$OUT")"
    fi
    if [ "$FIELD" = "replaced" ]; then
        printf 'replaced_state=%s\n' "$(jq -r '.replaced_state // ""' <"$OUT" | tr -d '\n')"
        printf 'replaced_result=%s\n' "$(jq -c '.replaced_result' <"$OUT")"
    fi
    if jq -e 'has("leg")' <"$OUT" >/dev/null 2>&1; then
        printf 'leg=%s\n' "$(jq -c '.leg' <"$OUT")"
    fi
    exit 0
fi

# --- refusal or failure ------------------------------------------------------

jq_field error;      K_ERROR="$FIELD"
jq_field code;       CODE="$FIELD"
jq_field var;        K_VAR="$FIELD"
jq_field value;      K_VALUE="$FIELD"
jq_field constraint; K_CONSTRAINT="$FIELD"
jq_field recorded;   K_RECORDED="$FIELD"
jq_field requested;  K_REQUESTED="$FIELD"
jq_field state;      K_STATE="$FIELD"

if [ -z "$CODE" ]; then
    case "$K_ERROR" in
        *"already exists"*) CODE="already_exists" ;;
    esac
fi
if [ -z "$CODE" ]; then
    printf 'failed=koto_error\n'
    printf '%s\n' "$K_ERROR" >&2
    exit "$RC"
fi
# A code is an identifier; anything else is not printed on the result line.
case "$CODE" in
    *[!a-z0-9_]*) printf 'failed=koto_error\n'; printf '%s\n' "$K_ERROR" >&2; exit "$RC" ;;
esac

# render <text> -- one left-to-right pass over the caller's wording: `\n`, `\t`
# and `\\` become their bytes, and each {placeholder} becomes koto's field.
# Substituted values are copied as bytes and never rescanned, so a value that
# itself holds `{var}`, `\n`, `&`, or `$(...)` prints literally. Sets REPLACED.
REPLACED=""
render() {
    local s="$1" out="" c name rest
    while [ -n "$s" ]; do
        c="${s:0:1}"
        s="${s:1}"
        if [ "$c" = "\\" ] && [ -n "$s" ]; then
            case "${s:0:1}" in
                n) out="$out
"; s="${s:1}"; continue ;;
                t) out="$out	"; s="${s:1}"; continue ;;
                "\\") out="$out\\"; s="${s:1}"; continue ;;
            esac
        elif [ "$c" = "{" ]; then
            case "$s" in
                *"}"*)
                    name="${s%%\}*}"
                    rest="${s#*\}}"
                    case "$name" in
                        session) out="$out$SESSION"; s="$rest"; continue ;;
                        var) out="$out$K_VAR"; s="$rest"; continue ;;
                        value) out="$out$K_VALUE"; s="$rest"; continue ;;
                        constraint) out="$out$K_CONSTRAINT"; s="$rest"; continue ;;
                        recorded) out="$out$K_RECORDED"; s="$rest"; continue ;;
                        requested) out="$out$K_REQUESTED"; s="$rest"; continue ;;
                        state) out="$out$K_STATE"; s="$rest"; continue ;;
                        error) out="$out$K_ERROR"; s="$rest"; continue ;;
                    esac
                    ;;
            esac
        fi
        out="$out$c"
    done
    REPLACED="$out"
}

lookup_wording() {
    local code="$1" line key text tab
    tab=$(printf '\t')
    [ -n "$WORDING" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        case "$line" in
            *"$tab"*) ;;
            *) continue ;;
        esac
        key="${line%%"$tab"*}"
        text="${line#*"$tab"}"
        if [ "$key" = "$code" ]; then
            REPLACED="$text"
            return 0
        fi
    done <"$WORDING"
    return 1
}

MESSAGE="$K_ERROR"
NO_ORIGIN=0
if [ "$CODE" = "origin_mismatch" ] && [ -z "$K_RECORDED" ]; then
    NO_ORIGIN=1
fi
if [ "$NO_ORIGIN" -eq 0 ] && lookup_wording "$CODE"; then
    render "$REPLACED"
    MESSAGE="$REPLACED"
fi

printf 'refused=%s\n' "$CODE"
printf '%s\n' "$MESSAGE" >&2
exit "$RC"
