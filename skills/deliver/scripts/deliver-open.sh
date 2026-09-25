#!/usr/bin/env bash
# deliver-open.sh -- /deliver's entry into koto: the invocation's raw tokens in,
# a fresh deliver-<topic> session out, through the shared scripts/koto-open.sh.
#
# Every /deliver invocation starts a fresh session: --merge and the mode are
# per invocation, and a run's progress is re-derived from the PLAN and the
# owned PR, never carried over. What this script must not do is remove a
# same-named session that belongs to someone else. Session names are
# machine-wide, and only koto can tell whose a session is: it compares the
# session's origin record (worktree and store), which it doesn't expose. So
# the script asks koto, in two calls:
#
#   1. a probe: koto-open.sh --attach-live --replace-terminal with an args file
#      carrying only TOPIC and PLUGIN_ROOT, so no other non-rebind variable is
#      compared. `refused=origin_mismatch` (another worktree or store) or
#      `refused=template_mismatch` is a collision: the run stops with koto's
#      refusal, and that session is left untouched. `opened=new`, `attached`
#      or `replaced` means the name is this worktree's, and the session is
#      removed with `koto session cleanup deliver-<topic>`.
#   2. the open: koto-open.sh once more, with no attach flags and the full
#      args file, so the session is always new. koto checks every argument
#      here and its refusal is printed.
#
# It never reads a session's origin record or state file.
#
# Usage:
#   deliver-open.sh [--plugin-root <path>] <args-file>
#
#   <args-file>    a JSON array of strings: the invocation's raw tokens in
#                  order, the positional topic included, written by the agent
#                  with jq into a directory from `koto-open.sh --alloc-dir`,
#                  never into the work tree. REMOVED on every exit path unless
#                  git tracks it.
#   --plugin-root  the shirabe plugin root, passed as PLUGIN_ROOT. Defaults to
#                  the tree this script ships in.
#
# Token mapping (every occurrence is its own pair, so a repeat is a duplicate
# koto refuses as duplicate_var):
#
#   --auto              MODE=auto
#   --interactive       MODE=interactive
#   (neither)           MODE from the repository's `## Execution Mode:` header
#                       in CLAUDE.md (auto or interactive), else interactive
#   --no-merge          MERGE=false
#   (no --no-merge)     MERGE=true
#   --coordinated       COORDINATION=coordinated
#   --no-coordinated    COORDINATION=no-coordinated
#   --max-rounds=<n>    MAX_ROUNDS=<n>   (bare --max-rounds: the literal token)
#   --upstream <path>   UPSTREAM=<path>, also --upstream=<path>; with no value
#                       the literal token --upstream, which the pattern rejects
#   anything else       the positional residue; joined with single spaces it
#                       is TOPIC, so a second word or an unknown flag fails the
#                       topic pattern at koto
#
# Output. stdout carries koto-open.sh's machine-readable lines (the probe's
# only when it stopped the run), then:
#
#   session=deliver-<topic>          on success
#   outcome=error                    on every refusal or failure, followed by
#   step=deliver:refused
#
# koto's refusal wording goes to stderr, from deliver-open.wording.tsv.
#
# Exit codes: koto-open.sh's (0 opened, 2 refused, 64 usage, 127 koto or jq
# missing, koto's own code otherwise); 1 when the cleanup of this worktree's
# earlier session failed; 64 for this script's own usage refusals.
#
# Requires: bash 3.2+, jq, koto. No eval anywhere, and no token is ever
# expanded by a shell: the tokens reach koto only through the vars file.
set -uo pipefail

PROG=deliver-open
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO_OPEN="$HERE/../../../scripts/koto-open.sh"
REPORT="$HERE/deliver-report.sh"
WORDING="$HERE/deliver-open.wording.tsv"
KOTO="${KOTO_BIN:-koto}"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'

ARGS_FILE=""

TOP=""
if [ "$(git rev-parse --is-inside-work-tree 2>&1)" = "true" ]; then
    TOP=$(git rev-parse --show-toplevel) || TOP=""
    [ -z "$TOP" ] || TOP=$(cd -P -- "$TOP" && pwd -P) || TOP=""
fi

# remove_if_untracked <file> -- remove the args file, but never one git
# tracks: that is a caller passing the wrong path.
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
    # The private directory `koto-open.sh --alloc-dir` made for the args file.
    if [ -n "$dir" ] && [ -f "$dir/.koto-open-alloc" ] && [ ! -L "$dir/.koto-open-alloc" ]; then
        if [ -z "$(ls -A -- "$dir" | grep -vx '.koto-open-alloc')" ]; then
            rm -f -- "$dir/.koto-open-alloc"
            rmdir -- "$dir"
        fi
    fi
    return 0
}
trap cleanup EXIT
trap 'cleanup; trap - EXIT; exit 130' INT
trap 'cleanup; trap - EXIT; exit 143' TERM

# stop <result-line> <message> <exit> -- this script's own refusal.
stop() {
    printf '%s\n' "$1"
    bash "$REPORT" --refused
    printf '/deliver: %s\n' "$2" >&2
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

[ -z "$BAD" ] || stop "error=usage" "$BAD" 64
[ "$POS" -eq 1 ] && [ -n "$ARGS_FILE" ] || stop "error=usage" "expected one <args-file>" 64
[ "$PLUGIN_ROOT_SEEN" -le 1 ] || stop "error=usage" "--plugin-root given more than once" 64
if [ "$PLUGIN_ROOT_SEEN" -eq 0 ]; then
    PLUGIN_ROOT=$(cd "$HERE/../../.." && pwd)
fi
command -v jq >/dev/null || stop "failed=jq_missing" "jq is not on PATH" 127
[ -f "$ARGS_FILE" ] && [ -r "$ARGS_FILE" ] || stop "error=usage" "the args file cannot be read: $ARGS_FILE" 64

# The repository's `## Execution Mode:` header, used only when neither mode
# flag was given. Anything but auto or interactive is ignored.
HEADER_MODE=""
if [ -n "$TOP" ] && [ -f "$TOP/CLAUDE.md" ]; then
    HEADER_MODE=$(sed -n 's/^## Execution Mode:[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$TOP/CLAUDE.md" | sed -n 1p | tr '[:upper:]' '[:lower:]')
fi
case "$HEADER_MODE" in auto|interactive) ;; *) HEADER_MODE=interactive ;; esac

# --- tokens to pairs, in jq ---------------------------------------------------

MAP='
def step($t):
  if $t == "--auto" then .modes += [["MODE", "auto"]]
  elif $t == "--interactive" then .modes += [["MODE", "interactive"]]
  elif $t == "--no-merge" then .merges += [["MERGE", "false"]]
  elif $t == "--coordinated" then .pairs += [["COORDINATION", "coordinated"]]
  elif $t == "--no-coordinated" then .pairs += [["COORDINATION", "no-coordinated"]]
  elif $t == "--max-rounds" then .pairs += [["MAX_ROUNDS", "--max-rounds"]]
  elif ($t | startswith("--max-rounds=")) then .pairs += [["MAX_ROUNDS", $t[13:]]]
  elif $t == "--upstream" then .pending = "upstream"
  elif ($t | startswith("--upstream=")) then .pairs += [["UPSTREAM", $t[11:]]]
  else .residue += [$t]
  end;
def flush:
  if .pending == "upstream" then .pairs += [["UPSTREAM", "--upstream"]] | .pending = null else . end;
if (type != "array") or (map(type == "string") | all | not) then
  error("the args file must be a JSON array of strings")
else
  reduce .[] as $t ({pairs: [], modes: [], merges: [], residue: [], pending: null};
    if .pending != null and ($t | startswith("--") | not) then
      .pairs += [["UPSTREAM", $t]] | .pending = null
    else flush | step($t) end)
  | flush
  | (.residue | join(" ")) as $topic
  | {
      topic: $topic,
      vars: ([["TOPIC", $topic]] + .pairs
             + (if .modes == [] then [["MODE", $header]] else .modes end)
             + (if .merges == [] then [["MERGE", "true"]] else .merges end))
    }
end
'
MAPPED=$(jq -c --arg header "$HEADER_MODE" "$MAP" <"$ARGS_FILE") \
    || stop "error=usage" "the args file is not a JSON array of strings: $ARGS_FILE" 64
remove_if_untracked "$ARGS_FILE"

TOPIC=$(printf '%s' "$MAPPED" | jq -j '.topic')
if [[ "$TOPIC" =~ $RE_TOPIC ]]; then
    SESSION="deliver-$TOPIC"
else
    # koto refuses TOPIC before it looks at any session, so the placeholder
    # only has to be a name koto-open.sh accepts.
    SESSION="deliver-invalid-topic"
fi
TEMPLATE="$PLUGIN_ROOT/skills/deliver/koto-templates/deliver.md"

# write_vars <jq filter over MAPPED> -- a vars file in its own private
# directory; koto-open.sh removes both.
write_vars() {
    local dir f
    dir=$(bash "$KOTO_OPEN" --alloc-dir) || return 1
    f="$dir/deliver-vars.json"
    printf '%s' "$MAPPED" | jq -c --arg root "$PLUGIN_ROOT" "$1" >"$f" || { rm -rf -- "$dir"; return 1; }
    printf '%s' "$f"
}

# --- 1. the probe ------------------------------------------------------------------

PROBE_VARS=$(write_vars '[["TOPIC", .topic], ["PLUGIN_ROOT", $root]]') \
    || stop "error=usage" "could not write the probe's vars file" 64
PROBE=$(bash "$KOTO_OPEN" "$SESSION" "$TEMPLATE" "$PROBE_VARS" --attach-live --replace-terminal --wording "$WORDING")
RC=$?
case "$PROBE" in
    opened=*)
        if ! "$KOTO" session cleanup "$SESSION" </dev/null >/dev/null; then
            stop "failed=cleanup" "could not remove this worktree's earlier $SESSION session" 1
        fi
        ;;
    *)
        # A collision (origin_mismatch, template_mismatch) or any other
        # refusal: koto's own wording is already on stderr, and the session,
        # if any, is untouched.
        [ -n "$PROBE" ] && printf '%s\n' "$PROBE"
        bash "$REPORT" --refused
        [ "$RC" -ne 0 ] || RC=1
        exit "$RC"
        ;;
esac

# --- 2. the open -----------------------------------------------------------------------

VARS=$(write_vars '.vars + [["PLUGIN_ROOT", $root]]') \
    || stop "error=usage" "could not write the vars file" 64
OUT=$(bash "$KOTO_OPEN" "$SESSION" "$TEMPLATE" "$VARS" --wording "$WORDING")
RC=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT"
if [ "$RC" -eq 0 ]; then
    printf 'session=%s\n' "$SESSION"
else
    bash "$REPORT" --refused
fi
exit "$RC"
