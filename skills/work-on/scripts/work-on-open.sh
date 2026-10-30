#!/usr/bin/env bash
# work-on-open.sh -- /work-on's koto entry: open the session of an
# issue-backed or free-form run in one `koto init`, and under --koto-leg attach
# a live one and bind it to a caller's request leg.
#
# Every issue-backed and free-form run opens through this script, with or
# without --koto-leg (SKILL.md's Initialize). The agent writes the invocation's
# tokens (the words of $ARGUMENTS) to a file outside the work tree and calls
# this script, which makes the one call through the shared
# scripts/koto-open.sh. Without --koto-leg in the tokens, the call is the plain
# open SKILL.md used to have the agent run itself:
#
#   koto init <workflow> --template <work-on.md> --vars-file <pairs>
#
# with no --attach-live: a new session, or koto's refusal when the name is in
# use. SKILL.md's Resume reads the session before any open, so a live one is
# ticked rather than opened and a finished one is cleaned up or renamed first.
# With --koto-leg the call is
#
#   koto init <workflow> --template <work-on.md> --vars-file <pairs>
#             --attach-live --koto-leg <request-id>:work-on
#
# --attach-live is what makes a resume work under the leg: a live session of
# the same name, template, and worktree is attached and bound to the leg
# instead of refused. Neither call has --replace-terminal. A finished session
# is the Resume guard's to handle before this script runs (SKILL.md), and
# koto's session_terminal refusal is what an unhandled one gets.
#
# Both calls hand koto-open.sh `--event-field unit.mode=issue_backed` when an
# ISSUE_NUMBER --var is given, and `--event-field unit.mode=free_form`
# otherwise. koto-open.sh adds the field to the session_opened event it sends
# once a session is opened or attached; this script sends nothing itself.
#
# koto then decides everything it can: a variable outside its constraint, a
# live session from another template or worktree, a leg that names another
# template or pins other inputs. Under --koto-leg koto records each of those
# refusals on the leg itself when the leg is still open and unbound; on a leg
# already bound to this session (a re-dispatch) it records nothing and the leg
# stays bound. This script's own refusals are the ones where there is no leg to
# record anything on: a repeated --koto-leg, a value that isn't
# <request-id>:work-on with a request id koto would accept, or a tokens file it
# cannot read. Under --koto-leg it also refuses the two input shapes the flag
# doesn't apply to, with the signals SKILL.md's Mode Detection uses: tokens
# that begin with `-- plan-backed` (a plan-backed child, whose result is
# /execute's) and a PLAN path (a token whose file name is PLAN-*.md, or a .md
# file whose frontmatter says `schema: plan/v1` or `schema: plan/v2`), which
# runs several issues or steps where one leg answers one. Without the leg
# neither shape is refused: a multi-pr PLAN run opens each issue's session
# here, with the PLAN path among its tokens, and a plan-backed child's session
# is opened by /execute, not through this script. Each refusal
# exits 64 with `error=usage` and makes no koto call. koto-open.sh adds two: an
# args file inside the work tree, and no koto binary.
#
# Usage:
#   work-on-open.sh --workflow <name> [--var NAME=VALUE]...
#                   [--dispatched-by <dispatcher>] <tokens-file>
#
#   --workflow     the session name, <WF> in SKILL.md: issue_<N> or task_<slug>.
#   --dispatched-by
#                  the session that dispatched this run, when one did: any koto
#                  session name (^[A-Za-z0-9][A-Za-z0-9._-]*$, at most 200
#                  bytes) other than <name>, given at most once. Anything else
#                  is this script's own usage refusal, before any koto call.
#                  Once the session is opened or attached, the script runs
#                  `koto session link <name> --dispatched-by <dispatcher>`,
#                  which records the link in the run's own session so koto
#                  keeps it while the dispatcher's hierarchy is alive
#                  (`koto session hierarchy <name>`). A failed link is run once
#                  more; a second failure prints
#                    warning=link-failed dispatched_by=<dispatcher>
#                  after session=<name>, records the same two facts in the
#                  run's own key session/link-warning, and leaves the exit
#                  code as the open's: the run goes on, only not joined to its
#                  dispatcher. A link that works prints nothing. Without the
#                  flag no link is written and the script behaves as before.
#                  The retry, warning and record are scripts/lib/
#                  dispatch-link.sh's, shared with skill-session.sh.
#   --var          a template variable the agent derived for this run, as it
#                  would pass it to `koto init --var`: ISSUE_NUMBER and
#                  ARTIFACT_PREFIX, and ISSUE_REPO for an issue in another
#                  repository. Written to the pairs file with jq, never
#                  through a shell.
#   <tokens-file>  a JSON array of strings, the invocation's tokens in order,
#                  written with the Write tool or jq into a directory from
#                  `koto-open.sh --alloc-dir`. Read from it: the --koto-leg
#                  tokens (`--koto-leg=<v>` or `--koto-leg <v>`) and the
#                  review-level bound, below. This script removes it, and
#                  koto-open.sh removes the pairs file and the directory.
#
# The review-level bound, mapped from the tokens to pairs, one per occurrence,
# so a repeat reaches koto and is refused there as duplicate_var:
#
#   --review-floor=<level>    REVIEW_FLOOR=<level>
#   --review-ceiling=<level>  REVIEW_CEILING=<level>
#
# A bare --review-floor or --review-ceiling becomes the literal token, which
# the variables' pattern ^(light|standard|full)?$ refuses (invalid_var), as
# does any value outside the three names. Without the flags no pair is
# written, so the session gets exactly the variables it got before the flags
# existed. Both variables are not rebind in work-on.md: an attach that passes
# a different bound than the session recorded is koto's var_mismatch, and one
# that passes none keeps the recorded bound.
#
# The verification deferral (#1012) is mapped the same way:
#
#   --verification=<local|hosted-ci>   VERIFICATION=<value>
#   --verification-reason=<text>       VERIFICATION_DEFERRAL_REASON=<text>
#
# koto refuses a value outside VERIFICATION's values, and a reason that does
# not start with a letter or digit (a bare flag among them), as invalid_var.
# This script refuses two shapes itself, each with error=usage and exit 64
# before any koto call:
#
#   - --verification=hosted-ci with no non-empty --verification-reason, since
#     koto can't relate two variables, so a run can't defer verification
#     without saying why;
#   - a --verification-reason with a character outside koto's variable
#     allowlist, ^[a-zA-Z0-9._/:@+ \-]*$: letters, digits, spaces and
#     . _ / : @ + -. A natural reason such as "host can't run suites, CI only"
#     has an apostrophe and a comma, and koto's own invalid_var names neither,
#     so the message names the characters that aren't allowed. This check runs
#     before the --koto-leg checks, so a caller gets the same answer with or
#     without the flag, and whatever --verification says, since koto checks
#     every value it is handed. A reason inside the allowlist passes through
#     unchanged. The rule that a reason starts with a letter or digit is not
#     repeated here: it is the template's pattern, its one source, and SKILL.md
#     states it.
#
# Both checks live in scripts/lib/verification-deferral.sh, which /execute's
# opener sources too, so the two skills refuse the same reasons in the same
# words.
#
# Like the bound, both variables are not rebind: an attach that passes none
# keeps what the session started with.
#
# PLUGIN_ROOT is added by this script: $CLAUDE_PLUGIN_ROOT, else the plugin
# root this script ships in. The template is this skill's work-on.md.
#
# Under --koto-leg, REVIEW_LEVEL is added when the session is live and its
# review_level.jsonl ledger records a level (`review-level.sh level`, the last
# level event's `to`). An attach resets every rebind variable it isn't passed,
# and without this a resume through this script would empty the run's chosen
# level. With no session or no ledger nothing is added, so a new session's
# variables are unchanged. Without --koto-leg the level is not read: that open
# never attaches, so a live session is refused whatever it is handed, and a
# new one has no ledger. A read that fails stops the open before koto init: `level`
# exiting non-zero, or printing anything but one level name. The second is
# what a session bound to another workspace gives, since koto's refusal of the
# read lands on `level`'s output. The script prints `failed=level_unreadable`,
# says why on stderr and exits 66, so nothing reaches the leg and a later open
# can still bind it.
#
# The other values handed to koto can't carry a failed read. The tokens file
# is read once, and a failed read is a usage refusal. PLUGIN_ROOT is the
# environment's CLAUDE_PLUGIN_ROOT or this script's own plugin directory,
# whose lookup exits 64 when it fails. The --var pairs and the values mapped
# from the tokens are the caller's input, not reads: koto checks them, and its
# invalid_var on the leg is their intended answer.
#
# Output: koto-open.sh's lines (opened=..., rebound=..., leg=..., refused=...,
# failed=...), then `session=<name>` when a session was opened or attached,
# then, under --dispatched-by, `warning=link-failed dispatched_by=<dispatcher>`
# when the link could not be recorded; or `failed=level_unreadable` alone.
# koto's refusal wording goes to stderr.
#
# Exit codes: koto-open.sh's (0 opened, 2 refused, 127 no koto or jq, koto's
# own code otherwise), 64 for this script's own usage refusals, or 66 for a
# failed review-level read under --koto-leg, with no koto init.
#
# A bare `--koto-leg` followed by another flag takes that flag as its value, so
# the value fails the leg pattern and exits 64. deliver-open.sh records an empty
# value in the same case; both end in the same refusal.
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=work-on-open

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
SKILL_DIR=$(CDPATH='' cd "$SELF_DIR/.." && pwd) || exit 64
PLUGIN_DIR=$(CDPATH='' cd "$SKILL_DIR/../.." && pwd) || exit 64
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
KOTO_OPEN="$PLUGIN_DIR/scripts/koto-open.sh"
# shellcheck source=../../../scripts/lib/verification-deferral.sh
. "$PLUGIN_DIR/scripts/lib/verification-deferral.sh" || exit 64
# shellcheck source=../../../scripts/lib/dispatch-link.sh
. "$PLUGIN_DIR/scripts/lib/dispatch-link.sh" || exit 64

RE_LEG='^[a-z0-9_][a-z0-9_-]{0,63}:work-on$'
RE_VAR='^[A-Z][A-Z0-9_]*='

TOKENS_FILE=""

# remove_tokens -- remove the tokens file and, when nothing else is left in it,
# the private directory `koto-open.sh --alloc-dir` made for it. On the open
# path koto-open.sh removes that directory along with the pairs file; on every
# path that never reaches koto-open.sh, this does.
remove_tokens() {
    local dir
    [ -n "$TOKENS_FILE" ] || return 0
    dir=$(dirname -- "$TOKENS_FILE")
    [ -f "$TOKENS_FILE" ] && rm -f -- "$TOKENS_FILE"
    if [ -f "$dir/.koto-open-alloc" ] && [ ! -L "$dir/.koto-open-alloc" ] \
        && [ -z "$(ls -A -- "$dir" | grep -vx '.koto-open-alloc')" ]; then
        rm -f -- "$dir/.koto-open-alloc"
        rmdir -- "$dir" 2>/dev/null
    fi
    return 0
}

own_refusal() {
    remove_tokens
    printf 'error=usage\n'
    echo "$PROG: $*" >&2
    exit 64
}

WORKFLOW=""
VARS=()
POS=0
DISPATCHER=""
HAVE_DISPATCHER=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --workflow)
            [ "$#" -ge 2 ] || own_refusal "--workflow needs a name"
            WORKFLOW="$2"; shift ;;
        --var)
            [ "$#" -ge 2 ] || own_refusal "--var needs NAME=VALUE"
            [[ "$2" =~ $RE_VAR ]] || own_refusal "--var must be NAME=VALUE, got [$2]"
            VARS+=("$2"); shift ;;
        --dispatched-by)
            [ "$#" -ge 2 ] || own_refusal "--dispatched-by needs the dispatcher's session name"
            HAVE_DISPATCHER=$((HAVE_DISPATCHER + 1))
            DISPATCHER="$2"; shift ;;
        -*) own_refusal "unknown option: $1" ;;
        *)
            POS=$((POS + 1))
            [ "$POS" -eq 1 ] || own_refusal "unexpected argument: $1"
            TOKENS_FILE="$1" ;;
    esac
    shift
done

[ -n "$TOKENS_FILE" ] || own_refusal "usage: work-on-open.sh --workflow <name> [--var NAME=VALUE]... [--dispatched-by <dispatcher>] <tokens-file>"
if [ ! -f "$TOKENS_FILE" ]; then
    MISSING="$TOKENS_FILE"; TOKENS_FILE=""
    own_refusal "no tokens file at [$MISSING]"
fi
[ -n "$WORKFLOW" ] || own_refusal "--workflow is required"
# Checked once the tokens file is known, so a refusal removes it.
[ "$HAVE_DISPATCHER" -le 1 ] || own_refusal "--dispatched-by given more than once"
if [ "$HAVE_DISPATCHER" -eq 1 ]; then
    dl_valid_dispatcher "$DISPATCHER" \
        || own_refusal "--dispatched-by must name a koto session: ^[A-Za-z0-9][A-Za-z0-9._-]*\$, at most 200 bytes, got [$DISPATCHER]"
    [ "$DISPATCHER" != "$WORKFLOW" ] || own_refusal "--dispatched-by names $WORKFLOW itself; a session is not its own dispatcher"
fi
command -v jq >/dev/null || { remove_tokens; printf 'failed=jq_missing\n'; echo "$PROG: jq is not on PATH" >&2; exit 127; }
jq -e 'type == "array" and all(.[]; type == "string")' "$TOKENS_FILE" >/dev/null \
    || own_refusal "the tokens file is not a JSON array of strings"

TOKENS=$(cat -- "$TOKENS_FILE") || own_refusal "could not read the tokens file"
DIR=$(dirname -- "$TOKENS_FILE")
rm -f -- "$TOKENS_FILE"

# A deferral reason koto would refuse, refused here first in words a caller can
# act on. The check is shared with /execute's opener.
REFUSAL=$(vd_reason_chars_refusal "$TOKENS")
[ -z "$REFUSAL" ] || own_refusal "$REFUSAL"

# --koto-leg: at most once, naming the one leg /work-on answers. Without it
# the open is the plain one, with no leg and no attach.
LEGS=$(printf '%s' "$TOKENS" | jq -c '. as $t | [range(0; length) as $i
    | if $t[$i] == "--koto-leg" then ($t[$i + 1] // "")
      elif ($t[$i] | startswith("--koto-leg=")) then ($t[$i] | ltrimstr("--koto-leg="))
      else empty end]')
LEG=""
case "$(printf '%s' "$LEGS" | jq 'length')" in
    0) ;;
    1)
        LEG=$(printf '%s' "$LEGS" | jq -j '.[0]')
        [[ "$LEG" =~ $RE_LEG ]] \
            || own_refusal "--koto-leg must be <request-id>:work-on, with a request id matching ^[a-z0-9_][a-z0-9_-]{0,63}\$, got [$LEG]"
        ;;
    *) own_refusal "--koto-leg given more than once" ;;
esac

# The inputs --koto-leg doesn't apply to. Every token but --koto-leg's own
# value is looked at. Without the leg there is nothing to refuse: a multi-pr
# PLAN run opens each issue's session here with the PLAN path in its tokens.
if [ -n "$LEG" ]; then
    REST=$(printf '%s' "$TOKENS" | jq -c '. as $t | [range(0; length) as $i
        | select(($t[$i] | startswith("--koto-leg")) | not)
        | select($i == 0 or $t[$i - 1] != "--koto-leg")
        | $t[$i]]')
    if printf '%s' "$REST" | jq -e '.[0] == "--" and .[1] == "plan-backed"' >/dev/null; then
        own_refusal "--koto-leg does not apply to a plan-backed child: /execute receives its result"
    fi
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        plan=0
        case "$(basename -- "$t")" in PLAN-*.md) plan=1 ;; esac
        if [ "$plan" -eq 0 ] && [ -f "$t" ] \
            && awk 'NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit 1; next }
                    /^---[[:space:]]*$/ { exit 1 }
                    /^schema:[[:space:]]*plan\/v[12][[:space:]]*$/ { found = 1; exit 0 }
                    END { exit found ? 0 : 1 }' "$t"; then
            plan=1
        fi
        [ "$plan" -eq 0 ] || own_refusal "--koto-leg does not apply to a PLAN ($t): one leg answers one issue's run"
    done <<TOKENS_EOF
$(printf '%s' "$REST" | jq -r '.[] | select(endswith(".md") and (startswith("-") | not))')
TOKENS_EOF
fi

# A deferral to hosted CI needs its reason (shared with /execute's opener).
REFUSAL=$(vd_missing_reason_refusal "$TOKENS")
[ -z "$REFUSAL" ] || own_refusal "$REFUSAL"

ROOT="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_DIR}"

# Under --koto-leg, the level the live session's ledger last recorded, or
# nothing. Anything but a clean read of nothing or one level name stops the
# open here, before koto init: passed on, it would reach koto as REVIEW_LEVEL,
# and koto's invalid_var would resolve a still-open leg as refused. The plain
# open never attaches, so it reads nothing.
LEVEL=""
if [ -n "$LEG" ]; then
    LEVEL_RC=0
    LEVEL=$(bash "$SELF_DIR/review-level.sh" level "$WORKFLOW" 2>"$DIR/level.err") || LEVEL_RC=$?
    case "$LEVEL_RC:$LEVEL" in
        0:|0:light|0:standard|0:full) ;;
        *)
            LEVEL_ERR=$( { printf '%s ' "$LEVEL"; cat -- "$DIR/level.err"; } 2>/dev/null | tr '\n' ' ')
            LEVEL_ERR=${LEVEL_ERR:0:300}
            rm -f -- "$DIR/level.err"
            remove_tokens
            printf 'failed=level_unreadable\n'
            echo "$PROG: could not read $WORKFLOW's review level (exit $LEVEL_RC), so the open stops with no koto init and the leg stays open: $LEVEL_ERR" >&2
            exit 66
            ;;
    esac
    rm -f -- "$DIR/level.err"
fi

PAIRS_FILE="$DIR/work-on-vars.json"
jq -nc --arg root "$ROOT" --arg level "$LEVEL" --argjson tokens "$TOKENS" '
    def bound($t; $flag; $var):
        if $t == $flag then [[$var, $t]]
        elif ($t | startswith($flag + "=")) then [[$var, ($t | ltrimstr($flag + "="))]]
        else [] end;
    ($ARGS.positional | map([(split("=")[0]), (.[(index("=") + 1):])]))
    + [ $tokens[] | bound(.; "--review-floor"; "REVIEW_FLOOR")[] ]
    + [ $tokens[] | bound(.; "--review-ceiling"; "REVIEW_CEILING")[] ]
    + [ $tokens[] | bound(.; "--verification"; "VERIFICATION")[] ]
    + [ $tokens[] | bound(.; "--verification-reason"; "VERIFICATION_DEFERRAL_REASON")[] ]
    + [["PLUGIN_ROOT", $root]]
    + (if $level == "" then [] else [["REVIEW_LEVEL", $level]] end)' --args ${VARS[@]+"${VARS[@]}"} > "$PAIRS_FILE" \
    || { rm -f -- "$PAIRS_FILE"; own_refusal "could not write the variables file"; }

# The run's entry mode, for koto-open.sh's session_opened event.
MODE=free_form
for v in ${VARS[@]+"${VARS[@]}"}; do
    case "$v" in ISSUE_NUMBER=*) MODE=issue_backed ;; esac
done

set -- "$WORKFLOW" "$TEMPLATE" "$PAIRS_FILE"
[ -z "$LEG" ] || set -- "$@" --attach-live --koto-leg "$LEG"
OUT=$(bash "$KOTO_OPEN" "$@" --event-field "unit.mode=$MODE")
RC=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT"
case "$OUT" in
    opened=*)
        printf 'session=%s\n' "$WORKFLOW"
        # A failed link has printed its warning and recorded it; the open stands.
        # koto-open.sh prints opened= only on exit 0; the check keeps it so if
        # that ever changes. It runs the koto KOTO_BIN names, as this does.
        if [ "$HAVE_DISPATCHER" -eq 1 ] && [ "$RC" -eq 0 ]; then
            dl_link "${KOTO_BIN:-koto}" "$WORKFLOW" "$DISPATCHER" || true
        fi
        ;;
esac
exit "$RC"
