#!/usr/bin/env bash
# work-on-open.sh -- /work-on's koto entry under --koto-leg: open or attach the
# run's session and bind it to a caller's request leg, in one `koto init`.
#
# Without --koto-leg, /work-on opens its session exactly as SKILL.md has always
# said (a plain `koto init` with --var), and this script is not used. With it,
# the agent writes the invocation's tokens (the words of $ARGUMENTS) to a file
# outside the work tree and calls this script, which makes the one call through
# the shared scripts/koto-open.sh:
#
#   koto init <workflow> --template <work-on.md> --vars-file <pairs>
#             --attach-live --koto-leg <request-id>:work-on
#
# --attach-live is what makes a resume work: a live session of the same name,
# template, and worktree is attached and bound to the leg instead of refused.
# There is no --replace-terminal. A finished session is the Resume guard's to
# handle before this script runs (SKILL.md), and koto's session_terminal
# refusal is what an unhandled one gets.
#
# koto then decides everything it can: a variable outside its constraint, a
# live session from another template or worktree, a leg that names another
# template or pins other inputs. Under --koto-leg every one of those refusals is
# recorded on the leg by koto itself. This script's own refusals are the ones
# where there is no leg to record anything on: no --koto-leg, a repeated one, a
# value that isn't <request-id>:work-on with a request id koto would accept, or
# a tokens file it cannot read. Each exits 64 with `error=usage` and makes no
# koto call. koto-open.sh adds two: an args file inside the work tree, and no
# koto binary.
#
# Usage:
#   work-on-open.sh --workflow <name> [--var NAME=VALUE]... <tokens-file>
#
#   --workflow     the session name, <WF> in SKILL.md: issue_<N> or task_<slug>.
#   --var          a template variable the agent derived for this run, as it
#                  would pass it to `koto init --var`: ISSUE_NUMBER and
#                  ARTIFACT_PREFIX. Written to the pairs file with jq, never
#                  through a shell.
#   <tokens-file>  a JSON array of strings, the invocation's tokens in order,
#                  written with jq into a directory from
#                  `koto-open.sh --alloc-dir`. Only the --koto-leg tokens are
#                  read from it: `--koto-leg=<v>` or `--koto-leg <v>`. This
#                  script removes it, and koto-open.sh removes the pairs file
#                  and the directory.
#
# PLUGIN_ROOT is added by this script: $CLAUDE_PLUGIN_ROOT, else the plugin
# root this script ships in. The template is this skill's work-on.md.
#
# Output: koto-open.sh's lines (opened=..., rebound=..., leg=..., refused=...,
# failed=...), then `session=<name>` when a session was opened or attached.
# koto's refusal wording goes to stderr.
#
# Exit codes: koto-open.sh's (0 opened, 2 refused, 127 no koto or jq, koto's
# own code otherwise), or 64 for this script's own usage refusals.
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=work-on-open

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
SKILL_DIR=$(CDPATH='' cd "$SELF_DIR/.." && pwd) || exit 64
PLUGIN_DIR=$(CDPATH='' cd "$SKILL_DIR/../.." && pwd) || exit 64
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
KOTO_OPEN="$PLUGIN_DIR/scripts/koto-open.sh"

RE_LEG='^[a-z0-9_][a-z0-9_-]{0,63}:work-on$'
RE_VAR='^[A-Z][A-Z0-9_]*='

TOKENS_FILE=""
own_refusal() {
    [ -n "$TOKENS_FILE" ] && [ -f "$TOKENS_FILE" ] && rm -f -- "$TOKENS_FILE"
    printf 'error=usage\n'
    echo "$PROG: $*" >&2
    exit 64
}

WORKFLOW=""
VARS=()
POS=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --workflow)
            [ "$#" -ge 2 ] || own_refusal "--workflow needs a name"
            WORKFLOW="$2"; shift ;;
        --var)
            [ "$#" -ge 2 ] || own_refusal "--var needs NAME=VALUE"
            [[ "$2" =~ $RE_VAR ]] || own_refusal "--var must be NAME=VALUE, got [$2]"
            VARS+=("$2"); shift ;;
        -*) own_refusal "unknown option: $1" ;;
        *)
            POS=$((POS + 1))
            [ "$POS" -eq 1 ] || own_refusal "unexpected argument: $1"
            TOKENS_FILE="$1" ;;
    esac
    shift
done

[ -n "$TOKENS_FILE" ] || own_refusal "usage: work-on-open.sh --workflow <name> [--var NAME=VALUE]... <tokens-file>"
if [ ! -f "$TOKENS_FILE" ]; then
    MISSING="$TOKENS_FILE"; TOKENS_FILE=""
    own_refusal "no tokens file at [$MISSING]"
fi
[ -n "$WORKFLOW" ] || own_refusal "--workflow is required"
command -v jq >/dev/null || { rm -f -- "$TOKENS_FILE"; printf 'failed=jq_missing\n'; echo "$PROG: jq is not on PATH" >&2; exit 127; }
jq -e 'type == "array" and all(.[]; type == "string")' "$TOKENS_FILE" >/dev/null \
    || own_refusal "the tokens file is not a JSON array of strings"

TOKENS=$(cat -- "$TOKENS_FILE")
DIR=$(dirname -- "$TOKENS_FILE")
rm -f -- "$TOKENS_FILE"
TOKENS_FILE=""

# --koto-leg: exactly once, naming the one leg /work-on answers.
LEGS=$(printf '%s' "$TOKENS" | jq -c '. as $t | [range(0; length) as $i
    | if $t[$i] == "--koto-leg" then ($t[$i + 1] // "")
      elif ($t[$i] | startswith("--koto-leg=")) then ($t[$i] | ltrimstr("--koto-leg="))
      else empty end]')
case "$(printf '%s' "$LEGS" | jq 'length')" in
    0) own_refusal "no --koto-leg in the tokens; without it /work-on opens its session with a plain koto init" ;;
    1) ;;
    *) own_refusal "--koto-leg given more than once" ;;
esac
LEG=$(printf '%s' "$LEGS" | jq -j '.[0]')
[[ "$LEG" =~ $RE_LEG ]] \
    || own_refusal "--koto-leg must be <request-id>:work-on, with a request id matching ^[a-z0-9_][a-z0-9_-]{0,63}\$, got [$LEG]"

ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_DIR}"

PAIRS_FILE="$DIR/work-on-vars.json"
jq -nc --arg root "$ROOT" '$ARGS.positional
    | map([(split("=")[0]), (.[(index("=") + 1):])])
    + [["PLUGIN_ROOT", $root]]' --args ${VARS[@]+"${VARS[@]}"} > "$PAIRS_FILE" \
    || own_refusal "could not write the variables file"

OUT=$(bash "$KOTO_OPEN" "$WORKFLOW" "$TEMPLATE" "$PAIRS_FILE" --attach-live --koto-leg "$LEG")
RC=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT"
case "$OUT" in
    opened=*) printf 'session=%s\n' "$WORKFLOW" ;;
esac
exit "$RC"
