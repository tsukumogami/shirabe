#!/usr/bin/env bash
# execute-open.sh — /execute's koto entry: map this invocation's tokens to the
# session's variables and open `execute-<slug>` through the shared koto-open.sh.
#
# Every /execute invocation, fresh or resumed, enters the same way: the agent
# writes the invocation's tokens (the words of $ARGUMENTS) to a file outside the
# work tree, and this script builds the variable pairs with jq -- never eval --
# and makes the one `koto init` call:
#
#   koto init execute-<slug> --template <execute.md> --vars-file <pairs>
#             --attach-live --replace-terminal [--koto-leg <request-id>:execute]
#
# koto then decides everything a variable can express, so /execute refuses
# nothing of its own that koto could: a repeated --merge is koto's
# duplicate_var, `--merge=yes` is invalid_var, a slug outside ^[a-z0-9-]+$ is
# invalid_var on PLAN_SLUG, a live session from another template, worktree, or
# store is template_mismatch or origin_mismatch. Under --koto-leg every one of
# those refusals is recorded on the leg by koto itself. This script's own
# refusals are only the ones where no koto call can be built at all: a
# malformed --koto-leg value, or a tokens file it cannot read. koto-open.sh
# adds the other two: an args file inside the work tree, and no koto binary.
#
# Usage: execute-open.sh <tokens-file>
#
#   <tokens-file>  a JSON array of strings, the invocation's tokens in order,
#                  written with jq into a directory from
#                  `koto-open.sh --alloc-dir`. This script removes it, and
#                  koto-open.sh removes the pairs file and the directory.
#
# The pairs, one per occurrence, so a repeat survives to be refused:
#
#   PLAN_DOC               the first token ending in .md that isn't a flag
#   PLAN_SLUG              its basename without PLAN- and .md
#   PLUGIN_ROOT            $CLAUDE_PLUGIN_ROOT, else this plugin's root
#   MERGE                  `--merge` -> true, `--merge=<v>` -> <v>, one pair per
#                          occurrence; none -> one pair, false. Passed
#                          explicitly on every invocation, so koto rebinds it on
#                          every accepted attach and a run is never merged on an
#                          earlier invocation's intent.
#   PAUSE_BEFORE_FINALIZE  one pair per mode flag (`--interactive` -> true,
#                          `--auto` -> false); with no mode flag, one pair from
#                          the repository's `## Execution Mode:` header in
#                          CLAUDE.md, else interactive (true). A resume of a
#                          session retained at paused_for_review passes false:
#                          re-invoking a paused run is the finalize invocation.
#
# `--koto-leg=<request-id>:<leg>` (or `--koto-leg <request-id>:<leg>`) is passed
# through once. The leg must be `execute`, the one leg /execute answers; the
# request id is checked by koto-open.sh against koto's pattern. The flag changes
# nothing but where the result goes.
#
# Output: koto-open.sh's lines (opened=..., refused=..., failed=...), then
# `session=execute-<slug>` when a session was opened, or, on a refusal, the exit
# lines print-exit.sh --refused prints (outcome=error, step=execute:refused).
# koto's refusal wording goes to stderr, from execute-open-wording.tsv.
#
# Exit codes: koto-open.sh's (0 opened, 2 refused, 127 no koto or jq, koto's
# own code otherwise), or 64 for this script's own usage refusals.
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=execute-open

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
SKILL_DIR=$(CDPATH='' cd "$SELF_DIR/.." && pwd) || exit 64
PLUGIN_DIR=$(CDPATH='' cd "$SKILL_DIR/../.." && pwd) || exit 64
TEMPLATE="$SKILL_DIR/koto-templates/execute.md"
KOTO_OPEN="$PLUGIN_DIR/scripts/koto-open.sh"
WORDING="$SELF_DIR/execute-open-wording.tsv"
PRINT_EXIT="$SELF_DIR/print-exit.sh"

TOKENS_FILE="${1:-}"
own_refusal() {
    [ -n "$TOKENS_FILE" ] && rm -f -- "$TOKENS_FILE"
    printf 'error=usage\n'
    echo "$PROG: $*" >&2
    exit 64
}

[ $# -eq 1 ] || own_refusal "usage: execute-open.sh <tokens-file>"
[ -f "$TOKENS_FILE" ] || own_refusal "no tokens file at [$TOKENS_FILE]"
command -v jq >/dev/null || { printf 'failed=jq_missing\n'; echo "$PROG: jq is not on PATH" >&2; exit 127; }
jq -e 'type == "array" and all(.[]; type == "string")' "$TOKENS_FILE" >/dev/null \
    || own_refusal "the tokens file is not a JSON array of strings"

TOKENS=$(cat -- "$TOKENS_FILE")
DIR=$(dirname -- "$TOKENS_FILE")
rm -f -- "$TOKENS_FILE"

# --koto-leg: the one flag this script checks itself, because without a
# well-formed value there is no leg for koto to record a refusal on.
LEGS=$(printf '%s' "$TOKENS" | jq -c '. as $t | [range(0; length) as $i
    | if $t[$i] == "--koto-leg" then ($t[$i + 1] // "")
      elif ($t[$i] | startswith("--koto-leg=")) then ($t[$i] | ltrimstr("--koto-leg="))
      else empty end]')
LEG_COUNT=$(printf '%s' "$LEGS" | jq 'length')
LEG=""
if [ "$LEG_COUNT" -gt 1 ]; then
    own_refusal "--koto-leg given more than once"
elif [ "$LEG_COUNT" -eq 1 ]; then
    LEG=$(printf '%s' "$LEGS" | jq -r '.[0]')
    case "$LEG" in
        *:execute) ;;
        *) own_refusal "--koto-leg must be <request-id>:execute, got [$LEG]" ;;
    esac
    case "${LEG%:execute}" in
        ""|*:*) own_refusal "--koto-leg must be <request-id>:execute, got [$LEG]" ;;
    esac
fi

# The PLAN: the first non-flag token ending in .md that is not --koto-leg's
# separate value.
PLAN=$(printf '%s' "$TOKENS" | jq -r '. as $t | [range(0; length) as $i
    | select(($t[$i] | startswith("-") | not) and ($t[$i] | endswith(".md"))
             and ($i == 0 or $t[$i - 1] != "--koto-leg"))
    | $t[$i]][0] // ""')
SLUG=$(basename -- "$PLAN" .md)
SLUG=${SLUG#PLAN-}

# A slug outside the pattern is koto's to refuse (invalid_var on PLAN_SLUG), and
# koto validates variables before it looks at the session name, so the call is
# made under a placeholder name that koto never reaches.
case "$SLUG" in
    ""|*[!a-z0-9-]*) SESSION="execute-unnamed" ;;
    *) SESSION="execute-$SLUG" ;;
esac

# A retained paused_for_review session means this invocation resumes a paused
# run: the finalize invocation.
RESUMING_PAUSE=0
if [ "$SESSION" != "execute-unnamed" ] && command -v koto >/dev/null; then
    if koto status "$SESSION" \
        | jq -e '.is_terminal == true and .current_state == "paused_for_review"' >/dev/null; then
        RESUMING_PAUSE=1
    fi
fi

HEADER_MODE=""
TOP=$(git rev-parse --show-toplevel) || TOP=""
if [ -n "$TOP" ] && [ -f "$TOP/CLAUDE.md" ]; then
    HEADER_MODE=$(sed -n 's/^## Execution Mode:[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$TOP/CLAUDE.md" | head -1)
fi

ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_DIR}"

PAIRS_FILE="$DIR/execute-vars.json"
printf '%s' "$TOKENS" | jq -c \
    --arg plan "$PLAN" --arg slug "$SLUG" --arg root "$ROOT" \
    --arg header "$HEADER_MODE" --argjson resuming "$RESUMING_PAUSE" '
    def pause_of($m): if $resuming == 1 then "false" elif $m == "auto" then "false" else "true" end;
    [ .[] | select(. == "--merge" or startswith("--merge=")) ] as $merges
    | [ .[] | select(. == "--auto" or . == "--interactive") ] as $modes
    | (if $plan == "" then [] else [["PLAN_DOC", $plan], ["PLAN_SLUG", $slug]] end)
      + [["PLUGIN_ROOT", $root]]
      + (if ($merges | length) == 0 then [["MERGE", "false"]]
         else [ $merges[] | ["MERGE", (if . == "--merge" then "true" else ltrimstr("--merge=") end)] ] end)
      + (if ($modes | length) == 0 then [["PAUSE_BEFORE_FINALIZE", pause_of($header)]]
         else [ $modes[] | ["PAUSE_BEFORE_FINALIZE", pause_of(ltrimstr("--"))] ] end)
    ' > "$PAIRS_FILE" || own_refusal "could not write the variables file"

set -- "$SESSION" "$TEMPLATE" "$PAIRS_FILE" --attach-live --replace-terminal --wording "$WORDING"
[ -n "$LEG" ] && set -- "$@" --koto-leg "$LEG"

OUT=$(bash "$KOTO_OPEN" "$@")
RC=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT"

case "$OUT" in
    opened=*) printf 'session=%s\n' "$SESSION" ;;
    refused=*) bash "$PRINT_EXIT" --refused ;;
esac
exit "$RC"
