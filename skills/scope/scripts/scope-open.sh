#!/usr/bin/env bash
# scope-open.sh -- /scope's entry into koto: the invocation's raw tokens in,
# one `koto init` through the shared scripts/koto-open.sh, one result out.
#
# Phase 0 no longer validates /scope's arguments in prose. The agent tokenizes
# $ARGUMENTS, writes the raw tokens to an args file outside the work tree, and
# calls this script. It maps every flag occurrence to one ["NAME", "VALUE"]
# pair with jq and hands the pairs to koto, and koto refuses anything the
# variables in skills/scope/koto-templates/scope.md do not admit -- a bad or
# repeated --intent, a malformed topic, --auto with --interactive -- with exit
# 2 and no session. Under --koto-leg koto records the refusal on the leg, so a
# coordinator waiting on it reads the refusal instead of waiting.
#
# This script therefore never refuses on its own for a check a koto variable
# can express. It computes a value and lets koto refuse it:
#
#   INTENT_FLAG            the caller's --intent token, unmodified
#   PLUGIN_ROOT_PLACEMENT  `outside`, or `inside-worktree` when the plugin
#                          root lies in the work tree (symlinks resolved);
#                          the template admits only `outside`
#
# Its own refusals are the cases where no koto call can be built at all: an
# args file it cannot read, a malformed or repeated --koto-leg, a missing jq,
# and -- through koto-open.sh -- an args file inside the work tree or a
# missing koto binary.
#
# Usage:
#   scope-open.sh [--plugin-root <path>] <args-file>
#
#   <args-file>     a JSON array of strings: the invocation's raw tokens in
#                   order, the positional topic included, e.g.
#                   ["my-topic","--intent=continue","--upstream",
#                    "docs/roadmaps/ROADMAP-x.md"]. Written by the agent to
#                   the koto session directory or a private `mktemp -d`
#                   directory (`scripts/koto-open.sh --alloc-dir` makes one),
#                   never into the work tree. REMOVED on every exit path
#                   unless git tracks it.
#   --plugin-root   the shirabe plugin root, passed as PLUGIN_ROOT. Defaults
#                   to the tree this script ships in.
#
# Token mapping (every occurrence is its own pair, so a repeat is a duplicate
# koto refuses as duplicate_var):
#
#   --intent=<v>        INTENT_FLAG=<v>. A lone, explicitly empty `--intent=`
#                       is omitted, exactly like a missing flag. When --intent
#                       occurs more than once, every occurrence is written,
#                       an empty one included.
#   --intent            INTENT_FLAG=--intent, which the pattern rejects
#   --auto              EXEC_MODE=auto
#   --interactive       EXEC_MODE=interactive
#   --max-rounds=<n>    MAX_ROUNDS=<n>   (bare --max-rounds: the literal token)
#   --coordinated       COORDINATION=coordinated
#   --no-coordinated    COORDINATION=no-coordinated
#   --upstream <path>   UPSTREAM=<path>, also --upstream=<path>. With no value
#                       (last token, or the next token starts with `--`):
#                       the literal token --upstream, which the pattern rejects
#   --koto-leg <id>:<leg>, --koto-leg=<id>:<leg>
#                       not a variable: passed to koto-open.sh as --koto-leg.
#                       The request id must match koto's grammar and the leg
#                       must be `scope`.
#   anything else       the positional residue; joined with single spaces it
#                       is TOPIC, so a second word or an unknown flag fails
#                       the topic pattern at koto
#
# PLUGIN_ROOT and PLUGIN_ROOT_PLACEMENT are always passed. The session is
# `scope-<topic>` when the topic has the slug shape, and `scope-invalid-topic`
# otherwise: koto refuses the TOPIC value before any session is looked at, so
# the placeholder only has to be a name koto-open.sh accepts.
#
# Every call passes --attach-live and --replace-terminal: a live session with
# the same template, origin, and fixed variables is joined, and its rebind
# variables (PLUGIN_ROOT, PLUGIN_ROOT_PLACEMENT, EXEC_MODE, MAX_ROUNDS) take
# this invocation's values; a session that already reached a terminal is
# replaced by a fresh one (koto-open.sh prints opened=replaced and the old
# run's result), so a second /scope <topic> after a finished run starts over at
# intake rather than ticking the finished session.
#
# Output. stdout carries koto-open.sh's machine-readable lines, then:
#
#   session=scope-<topic>            on success
#   outcome=error                    on every refusal or failure, followed by
#   step=scope:refused
#
# `refused` is never printed after `outcome=`; it is only ever a value in a
# result payload. The human-readable message goes to stderr, rendered from
# scope-open.wording.tsv in /scope's refusal wording.
#
# Exit codes: koto-open.sh's, passed through (0 opened, 2 refused, 64 usage,
# 127 koto or jq missing, other koto failures); 64 for this script's own
# refusals.
#
# Requires: bash 3.2+, jq. No eval anywhere, and no token is ever expanded by
# a shell: the tokens reach koto only through the vars file.

set -uo pipefail

PROG=scope-open
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO_OPEN="$HERE/../../../scripts/koto-open.sh"
WORDING="$HERE/scope-open.wording.tsv"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_LEG='^[a-z0-9_][a-z0-9_-]{0,63}:scope$'

ARGS_FILE=""
VARS_FILE=""

# The work tree the run is scoped in, symlinks resolved. Empty outside one.
TOP=""
if [ "$(git rev-parse --is-inside-work-tree 2>&1)" = "true" ]; then
    TOP=$(git rev-parse --show-toplevel) || TOP=""
    [ -z "$TOP" ] || TOP=$(cd -P -- "$TOP" && pwd -P) || TOP=""
fi

# remove_if_untracked <file> -- remove a file this script owns, but never one
# git tracks: that is a caller passing the wrong path, and deleting it would be
# worse than the refusal already printed. Only a file inside the work tree can
# be tracked, so git is asked about nothing else.
remove_if_untracked() {
    local f="$1" dir phys
    [ -n "$f" ] || return 0
    [ -e "$f" ] || [ -L "$f" ] || return 0
    [ -d "$f" ] && [ ! -L "$f" ] && return 0
    if [ -n "$TOP" ]; then
        dir=$(cd -P -- "$(dirname -- "$f")" && pwd -P) || dir=""
        phys="$dir/$(basename -- "$f")"
        case "$phys" in
            "$TOP"/*)
                if [ -n "$(git -C "$TOP" ls-files -- "${phys#"$TOP"/}")" ]; then
                    return 0
                fi
                ;;
        esac
    fi
    rm -f -- "$f"
}

cleanup() {
    local dir=""
    [ -n "$ARGS_FILE" ] && dir=$(dirname -- "$ARGS_FILE")
    remove_if_untracked "$ARGS_FILE"
    remove_if_untracked "$VARS_FILE"
    # The private directory `koto-open.sh --alloc-dir` made, when koto-open.sh
    # never ran to remove it: only the marker is left, so it goes too.
    if [ -n "$dir" ] && [ -f "$dir/.koto-open-alloc" ] && [ ! -L "$dir/.koto-open-alloc" ]; then
        if [ -z "$(ls -A -- "$dir" 2>/dev/null | grep -vx '.koto-open-alloc')" ]; then
            rm -f -- "$dir/.koto-open-alloc"
            rmdir -- "$dir" 2>/dev/null
        fi
    fi
    return 0
}
trap cleanup EXIT
trap 'cleanup; trap - EXIT; exit 130' INT
trap 'cleanup; trap - EXIT; exit 143' TERM

# own_refusal <result-line> <message> <exit>
own_refusal() {
    printf '%s\n' "$1"
    printf 'outcome=error\n'
    printf 'step=scope:refused\n'
    printf '/scope: %s\n' "$2" >&2
    exit "$3"
}

PLUGIN_ROOT=""
PLUGIN_ROOT_SEEN=0
POS=0
BAD=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --plugin-root)
            if [ "$#" -lt 2 ]; then BAD="--plugin-root needs a path"; shift; continue; fi
            PLUGIN_ROOT="$2"; PLUGIN_ROOT_SEEN=$((PLUGIN_ROOT_SEEN + 1)); shift ;;
        --plugin-root=*)
            PLUGIN_ROOT="${1#--plugin-root=}"; PLUGIN_ROOT_SEEN=$((PLUGIN_ROOT_SEEN + 1)) ;;
        *)
            POS=$((POS + 1))
            if [ "$POS" -eq 1 ]; then ARGS_FILE="$1"; else [ -n "$BAD" ] || BAD="unexpected argument: $1"; fi
            ;;
    esac
    shift
done

[ -z "$BAD" ] || own_refusal "error=usage" "$BAD" 64
[ "$POS" -eq 1 ] && [ -n "$ARGS_FILE" ] || own_refusal "error=usage" "expected one <args-file>" 64
[ "$PLUGIN_ROOT_SEEN" -le 1 ] || own_refusal "error=usage" "--plugin-root given more than once" 64
if [ "$PLUGIN_ROOT_SEEN" -eq 0 ]; then
    PLUGIN_ROOT=$(cd "$HERE/../../.." && pwd)
fi

if ! command -v jq >/dev/null 2>&1; then
    own_refusal "failed=jq_missing" "jq is not on PATH" 127
fi
[ -f "$ARGS_FILE" ] && [ -r "$ARGS_FILE" ] || own_refusal "error=usage" "the args file cannot be read: $ARGS_FILE" 64

# --- tokens to pairs, in jq ----------------------------------------------------

# One reduce over the tokens. `pending` holds a flag waiting for its value
# (--upstream, --koto-leg); a following token that starts with `--` is not
# that value, so the flag is flushed as valueless and the token is processed
# on its own.
MAP='
def step($t):
  if $t == "--intent" then .intents += ["--intent"]
  elif ($t | startswith("--intent=")) then .intents += [$t[9:]]
  elif $t == "--auto" then .pairs += [["EXEC_MODE", "auto"]]
  elif $t == "--interactive" then .pairs += [["EXEC_MODE", "interactive"]]
  elif $t == "--coordinated" then .pairs += [["COORDINATION", "coordinated"]]
  elif $t == "--no-coordinated" then .pairs += [["COORDINATION", "no-coordinated"]]
  elif $t == "--max-rounds" then .pairs += [["MAX_ROUNDS", "--max-rounds"]]
  elif ($t | startswith("--max-rounds=")) then .pairs += [["MAX_ROUNDS", $t[13:]]]
  elif $t == "--upstream" then .pending = "upstream"
  elif ($t | startswith("--upstream=")) then .pairs += [["UPSTREAM", $t[11:]]]
  elif $t == "--koto-leg" then .pending = "koto-leg"
  elif ($t | startswith("--koto-leg=")) then .legs += [$t[11:]]
  else .residue += [$t]
  end;
def flush:
  if .pending == "upstream" then .pairs += [["UPSTREAM", "--upstream"]] | .pending = null
  elif .pending == "koto-leg" then .legs += [""] | .pending = null
  else . end;
if (type != "array") or (map(type == "string") | all | not) then
  error("the args file must be a JSON array of strings")
else
  reduce .[] as $t ({pairs: [], residue: [], intents: [], legs: [], pending: null};
    if .pending != null and ($t | startswith("--") | not) then
      (if .pending == "upstream" then .pairs += [["UPSTREAM", $t]] else .legs += [$t] end)
      | .pending = null
    else flush | step($t) end)
  | flush
  | (.residue | join(" ")) as $topic
  | {
      topic: $topic,
      legs: .legs,
      vars: ([["TOPIC", $topic]] + .pairs
             + (if .intents == [""] then [] else [.intents[] | ["INTENT_FLAG", .]] end))
    }
end
'

MAPPED=$(jq -c "$MAP" <"$ARGS_FILE") \
    || own_refusal "error=usage" "the args file is not a JSON array of strings: $ARGS_FILE" 64

# The tokens are read; the file is not needed again.
remove_if_untracked "$ARGS_FILE"

TOPIC=$(printf '%s' "$MAPPED" | jq -j '.topic')
LEG_COUNT=$(printf '%s' "$MAPPED" | jq -r '.legs | length')
KOTO_LEG=""
if [ "$LEG_COUNT" -gt 1 ]; then
    own_refusal "error=usage" "--koto-leg may be given at most once" 64
fi
if [ "$LEG_COUNT" -eq 1 ]; then
    KOTO_LEG=$(printf '%s' "$MAPPED" | jq -j '.legs[0]')
    [[ "$KOTO_LEG" =~ $RE_LEG ]] \
        || own_refusal "error=usage" "--koto-leg must be <request-id>:scope, with a request id matching ^[a-z0-9_][a-z0-9_-]{0,63}\$" 64
fi

# --- computed variables -------------------------------------------------------------

PLACEMENT=outside
ROOT_PHYS="$PLUGIN_ROOT"
if [ -d "$PLUGIN_ROOT" ]; then
    ROOT_PHYS=$(cd -P -- "$PLUGIN_ROOT" 2>/dev/null && pwd -P) || ROOT_PHYS="$PLUGIN_ROOT"
fi
if [ -n "$TOP" ]; then
    case "$ROOT_PHYS" in
        "$TOP"|"$TOP"/*) PLACEMENT=inside-worktree ;;
    esac
fi

if [[ "$TOPIC" =~ $RE_TOPIC ]]; then
    SESSION="scope-$TOPIC"
else
    SESSION="scope-invalid-topic"
fi

# --- the vars file ------------------------------------------------------------------

# Written beside the args file, so it inherits that location: koto-open.sh
# refuses it (and removes it) when that location is inside the work tree, and
# removes the private directory with it when --alloc-dir made one.
VARS_FILE=$(mktemp "$(dirname -- "$ARGS_FILE")/scope-open-vars.XXXXXX") \
    || own_refusal "error=usage" "could not write the vars file beside $ARGS_FILE" 64
printf '%s' "$MAPPED" | jq -c --arg root "$PLUGIN_ROOT" --arg placement "$PLACEMENT" \
    '.vars + [["PLUGIN_ROOT", $root], ["PLUGIN_ROOT_PLACEMENT", $placement]]' >"$VARS_FILE" \
    || own_refusal "error=usage" "could not write the vars file $VARS_FILE" 64

# --- the one koto init ----------------------------------------------------------------

# --replace-terminal beside --attach-live: a scope-<topic> session that already
# reached a terminal is replaced by a fresh one, which walks intake and
# resume_route like any new run, instead of being ticked into nothing. A live
# session is never replaced; --attach-live joins it or koto refuses.
set -- "$SESSION" "$PLUGIN_ROOT/skills/scope/koto-templates/scope.md" "$VARS_FILE" \
    --attach-live --replace-terminal --wording "$WORDING"
[ -n "$KOTO_LEG" ] && set -- "$@" --koto-leg "$KOTO_LEG"

OUT=$(bash "$KOTO_OPEN" "$@")
RC=$?
VARS_FILE=""   # koto-open.sh removed it on its own exit path

[ -n "$OUT" ] && printf '%s\n' "$OUT"
if [ "$RC" -eq 0 ]; then
    printf 'session=%s\n' "$SESSION"
else
    printf 'outcome=error\n'
    printf 'step=scope:refused\n'
fi
exit "$RC"
