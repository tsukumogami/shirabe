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
# the script asks koto:
#
#   0. a listing: `koto session list`, read only. When no session has the
#      name, there is nothing to probe or remove, and the run goes straight
#      to the open. A first run therefore runs no `koto session cleanup`:
#      a probe would make the session, koto would link it into the caller's
#      hierarchy, and removing it would warn that the retention rule would
#      have kept it. When the listing can't be read, the probe runs.
#   1. a probe, when the name is listed: koto-open.sh --attach-live
#      --replace-terminal with an args file carrying only TOPIC and
#      PLUGIN_ROOT, so no other non-rebind variable is compared.
#      `refused=origin_mismatch` (another worktree or store) or
#      `refused=template_mismatch` is a collision: the run stops with koto's
#      refusal, and that session is left untouched. `opened=new`, `attached`
#      or `replaced` means the name is this worktree's, and the session left
#      under it is removed with `koto session cleanup deliver-<topic>`:
#      after `attached` an earlier live session, after `replaced` the
#      probe's own replacement of an earlier finished run, after `new` (the
#      session went away between the listing and the probe) the probe's own
#      session. A finished run koto keeps for its hierarchy is not removed:
#      the probe's replace moves it aside to `deliver-<topic>_r<N>`, where
#      its record stays readable, and the probe's moved_to= and
#      moved_reason= lines are printed after the open's. When it can't be
#      moved, the probe is refused (replace_held_live or replace_failed) and
#      stops the run like any other refusal.
#   2. the open: koto-open.sh once more, with no attach flags and the full
#      args file, so the session is always new. koto checks every argument
#      here and its refusal is printed.
#
# Under --koto-leg only the open carries the leg: koto binds the new session
# to it, or records its refusal there. The probe never does, because its thin
# args file would be compared against inputs the leg pins (COORDINATION,
# UPSTREAM) and refused where the real open is not. When the probe stops the
# run under a leg, the probe is made once more with the full args file and the
# leg, so koto records the refusal on the leg. It carries the probe's own
# flags (--attach-live --replace-terminal), so koto refuses it for the same
# reason: a bad variable with the same code, a collision as template_mismatch
# or origin_mismatch. stdout's refused= line and the leg's reason then name the
# same refusal (the leg spells it in kebab-case). Should that call be accepted
# after all (the colliding session went away, or the probe's refusal was
# transient), the run goes on exactly as after an accepted probe: the session
# it opened is removed and the open below makes a fresh one, which re-binds
# the leg by name.
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
#   --review-floor=<level>
#                       REVIEW_FLOOR=<level> (bare --review-floor: the literal
#                       token, which the pattern refuses)
#   --review-ceiling=<level>
#                       REVIEW_CEILING=<level>, the same way. Both are the
#                       review-level bound, forwarded to /execute; without the
#                       flags no pair is written, so the session's variables
#                       are the ones it got before the flags existed
#   --upstream <path>   UPSTREAM=<path>, also --upstream=<path>; with no value
#                       the literal token --upstream, which the pattern rejects
#   --store <v>         STORE=<v>, also --store=<v>; with no value the literal
#                       token --store, which the pattern (github or session)
#                       rejects. Forwarded to /execute, beside the PR /scope
#                       published as --coordination-pr, on a coordinated PLAN
#                       only
#   --koto-leg <id>:deliver
#                       not a variable: also --koto-leg=<id>:deliver. The leg of
#                       a caller's request this run answers. Checked here, the
#                       one flag koto cannot refuse on the leg, because without
#                       a well-formed value there is no leg to record a refusal
#                       on: given twice, a leg other than `deliver`, or a
#                       request id outside ^[a-z0-9_][a-z0-9_-]{0,63}$ is this
#                       script's own refusal, exit 64, and no koto call is made.
#   anything else       the positional residue; joined with single spaces it
#                       is TOPIC, so a second word or an unknown flag fails the
#                       topic pattern at koto
#
# Output. stdout carries koto-open.sh's machine-readable lines (the probe's
# only when it stopped the run), then:
#
#   moved_to=<name>, moved_reason=<text>
#                                    when the probe moved this worktree's
#                                    finished run aside, whether the open
#                                    then succeeded or not
#   removed=deliver-<topic>, removed_predates=yes|no
#                                    when a session was removed before the
#                                    open, whether the open then succeeded or
#                                    not: yes for this worktree's earlier
#                                    live session, no for a session this
#                                    invocation's probe made
#   session=deliver-<topic>          on success
#   outcome=error                    on every refusal or failure, followed by
#   step=deliver:refused
#
# koto's refusal wording goes to stderr, from deliver-open.wording.tsv.
#
# Exit codes: koto-open.sh's (0 opened, 2 refused, 74 replace_failed, 75
# replace_held_live, 64 usage, 127 koto or jq missing, koto's own code
# otherwise); 1 when the cleanup of this worktree's
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
  elif $t == "--review-floor" then .pairs += [["REVIEW_FLOOR", "--review-floor"]]
  elif ($t | startswith("--review-floor=")) then .pairs += [["REVIEW_FLOOR", $t[15:]]]
  elif $t == "--review-ceiling" then .pairs += [["REVIEW_CEILING", "--review-ceiling"]]
  elif ($t | startswith("--review-ceiling=")) then .pairs += [["REVIEW_CEILING", $t[17:]]]
  elif $t == "--upstream" then .pending = "upstream"
  elif ($t | startswith("--upstream=")) then .pairs += [["UPSTREAM", $t[11:]]]
  elif $t == "--store" then .pending = "store"
  elif ($t | startswith("--store=")) then .pairs += [["STORE", $t[8:]]]
  elif $t == "--koto-leg" then .pending = "koto-leg"
  elif ($t | startswith("--koto-leg=")) then .legs += [$t[11:]]
  else .residue += [$t]
  end;
def flush:
  if .pending == "upstream" then .pairs += [["UPSTREAM", "--upstream"]] | .pending = null
  elif .pending == "store" then .pairs += [["STORE", "--store"]] | .pending = null
  elif .pending == "koto-leg" then .legs += [""] | .pending = null
  else . end;
if (type != "array") or (map(type == "string") | all | not) then
  error("the args file must be a JSON array of strings")
else
  reduce .[] as $t ({pairs: [], modes: [], merges: [], residue: [], legs: [], pending: null};
    if .pending == "upstream" and ($t | startswith("--") | not) then
      .pairs += [["UPSTREAM", $t]] | .pending = null
    elif .pending == "store" and ($t | startswith("--") | not) then
      .pairs += [["STORE", $t]] | .pending = null
    elif .pending == "koto-leg" and ($t | startswith("--") | not) then
      .legs += [$t] | .pending = null
    else flush | step($t) end)
  | flush
  | (.residue | join(" ")) as $topic
  | {
      topic: $topic,
      legs: .legs,
      vars: ([["TOPIC", $topic]] + .pairs
             + (if .modes == [] then [["MODE", $header]] else .modes end)
             + (if .merges == [] then [["MERGE", "true"]] else .merges end))
    }
end
'
MAPPED=$(jq -c --arg header "$HEADER_MODE" "$MAP" <"$ARGS_FILE") \
    || stop "error=usage" "the args file is not a JSON array of strings: $ARGS_FILE" 64
remove_if_untracked "$ARGS_FILE"

# --koto-leg: checked before any koto call. The leg name is fixed: /deliver
# answers only a leg named `deliver`.
RE_LEG='^[a-z0-9_][a-z0-9_-]{0,63}:deliver$'
LEG=""
case "$(printf '%s' "$MAPPED" | jq '.legs | length')" in
    0) ;;
    1)
        LEG=$(printf '%s' "$MAPPED" | jq -j '.legs[0]')
        [[ "$LEG" =~ $RE_LEG ]] \
            || stop "error=usage" "--koto-leg must be <request-id>:deliver, with a request id matching ^[a-z0-9_][a-z0-9_-]{0,63}\$" 64
        ;;
    *) stop "error=usage" "--koto-leg may be given at most once" 64 ;;
esac

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

# --- 0. the listing ----------------------------------------------------------------

# yes when koto lists a session by this name, no when it lists none, unknown
# when the listing can't be read. Only `no` skips the probe.
LISTED=unknown
if LISTING=$("$KOTO" session list </dev/null 2>/dev/null); then
    LISTED=$(printf '%s' "$LISTING" | jq -r --arg s "$SESSION" '
        if type == "array"
        then (if any(.[]; type == "object" and .id == $s) then "yes" else "no" end)
        else error("not a listing") end' 2>/dev/null) || LISTED=unknown
fi

# open_session [flag...] -- the full vars file, the leg when one was given,
# and any extra koto-open.sh flags. Without flags it is the open: no attach
# flags, so the session is always new. Sets OUT and RC.
open_session() {
    local vars
    vars=$(write_vars '.vars + [["PLUGIN_ROOT", $root]]') \
        || stop "error=usage" "could not write the vars file" 64
    set -- "$SESSION" "$TEMPLATE" "$vars" --wording "$WORDING" "$@"
    [ -n "$LEG" ] && set -- "$@" --koto-leg "$LEG"
    OUT=$(bash "$KOTO_OPEN" "$@")
    RC=$?
}

# fresh_start <probe-output> -- remove the session an accepted probe left
# under the name, so the open makes a new one, and record the removal in
# REMOVED. After opened=attached that is this worktree's earlier live
# session. After opened=replaced koto has already replaced the earlier
# finished run (or moved it aside, which moved_to= reports), so what is left
# is the probe's own replacement; after opened=new the probe made it. For a
# session this invocation made, koto's warning that the retention rule would
# have kept it describes seconds-old work, so that one line is dropped; every
# other line koto writes to stderr is passed on.
REMOVED=""
fresh_start() {
    local predates=no err rc
    case "$1" in opened=attached*) predates=yes ;; esac
    err=$("$KOTO" session cleanup "$SESSION" </dev/null 2>&1 >/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$predates" = no ]; then
        err=$(printf '%s\n' "$err" | grep -v -F "warning: removed '$SESSION', which the retention rule would have kept")
    fi
    [ -n "$err" ] && printf '%s\n' "$err" >&2
    if [ "$rc" -ne 0 ]; then
        if [ "$predates" = yes ]; then
            stop "failed=cleanup" "could not remove this worktree's earlier $SESSION session" 1
        fi
        stop "failed=cleanup" "could not remove the $SESSION session this run's probe made" 1
    fi
    REMOVED=$(printf 'removed=%s\nremoved_predates=%s' "$SESSION" "$predates")
}

# moved_lines <koto-open-output> -- the moved_to= and moved_reason= lines of an
# accepted probe: koto kept this worktree's finished session for its
# hierarchy and moved it aside rather than replacing it. Printed after the
# open's own lines, so the result line stays first.
MOVED=""
moved_lines() {
    MOVED=$(printf '%s\n' "$1" | grep -E '^moved_(to|reason)=')
}

# --- 1. the probe ------------------------------------------------------------------

# A name koto lists no session for needs no probe: the open below makes the
# session, and nothing is removed. A session that appears in between is
# refused by the open, which carries no attach flags.
if [ "$LISTED" != no ]; then
    PROBE_VARS=$(write_vars '[["TOPIC", .topic], ["PLUGIN_ROOT", $root]]') \
        || stop "error=usage" "could not write the probe's vars file" 64
    PROBE=$(bash "$KOTO_OPEN" "$SESSION" "$TEMPLATE" "$PROBE_VARS" --attach-live --replace-terminal --wording "$WORDING")
    RC=$?

    case "$PROBE" in
        opened=*) moved_lines "$PROBE"; fresh_start "$PROBE" ;;
        *)
            # A collision (origin_mismatch, template_mismatch) or any other
            # refusal: koto's own wording is already on stderr, and the
            # session, if any, is untouched. Under a leg, the probe is
            # repeated with the full vars and the leg so koto records the
            # same refusal on the leg; its wording would repeat the probe's,
            # so it is dropped.
            PROBE_RC=$RC
            RECORDED=""
            if [ -n "$LEG" ]; then
                open_session --attach-live --replace-terminal 2>/dev/null
                RECORDED=$OUT
            fi
            case "$RECORDED" in
                opened=*) moved_lines "$RECORDED"; fresh_start "$RECORDED" ;;
                *)
                    [ -n "$PROBE" ] && printf '%s\n' "$PROBE"
                    bash "$REPORT" --refused
                    [ "$PROBE_RC" -ne 0 ] || PROBE_RC=1
                    exit "$PROBE_RC"
                    ;;
            esac
            ;;
    esac
fi

# --- 2. the open -----------------------------------------------------------------------

open_session
[ -n "$OUT" ] && printf '%s\n' "$OUT"
if [ "$RC" -eq 0 ]; then
    # The run identity deliver-probe.sh's lookups carry: minted here, where the
    # session is born, and only read afterwards (run-id.sh get).
    bash "$PLUGIN_ROOT/skills/execute/scripts/run-id.sh" mint "$SESSION" </dev/null >/dev/null \
        || printf 'deliver-open: could not record a run identity in %s; its PR lookups will fail until it has one\n' "$SESSION" >&2
    [ -n "$MOVED" ] && printf '%s\n' "$MOVED"
    [ -n "$REMOVED" ] && printf '%s\n' "$REMOVED"
    printf 'session=%s\n' "$SESSION"
else
    # The probe already moved the earlier run aside, or a session was
    # removed; say so, even though this open failed.
    [ -n "$MOVED" ] && printf '%s\n' "$MOVED"
    [ -n "$REMOVED" ] && printf '%s\n' "$REMOVED"
    bash "$REPORT" --refused
fi
exit "$RC"
