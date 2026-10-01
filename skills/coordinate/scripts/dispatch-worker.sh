#!/usr/bin/env bash
# dispatch-worker.sh -- launch one worker and get its holding onto the record
# first.
#
# A worker that has launched but hasn't opened a pull request exists nowhere
# GitHub can show, so the record is the only place a restart or a successor
# can find it. This script writes the holding BEFORE it launches the worker
# (dispatch status `dispatching`), launches it, then rewrites the row as
# `dispatched` or `dispatch-failed`. A coordinator that dies at any point
# leaves either no worker or a row that names it. The dispatch state's gate,
# holding-recorded.sh, reads that row from the record, never a claim.
#
# The coordinator runs this script itself, in the dispatch state. koto can't:
# `niwa dispatch` clones an instance before it returns, which runs close to
# or past a default action's 30 seconds, and its success launches a session
# no later signal can take back. See references/default-action-conversion.md.
#
# Inputs, read from the session's context (never from arguments):
#
#   dispatch_topic     the topic pick chose; written fresh on the edge into
#                      dispatch_check and passed through to dispatch
#   brief_input.json   the brief input (see render-brief.sh); its topic must
#                      equal dispatch_topic, or report_topic under --rebrief
#   report_topic       --rebrief only: the worker whose report needs a fix
#   coord/pick.json    the units pick_facts listed; the brief input's unit
#                      must be a form pick reads as covering one of them
#                      (dispatch-common.sh dc_unit_forms: a feature's tag or
#                      `<tag>: <title>`, an issue's `#<n>` or
#                      `<host>#<n>`), else exit 1 at step 3, before anything
#                      is written, naming the forms that would match. Read
#                      only for a new dispatch: a resumed one's holding
#                      already records its unit, and --rebrief writes no
#                      holding
#
# The run, in order, under a per-topic lock:
#
#   1. Read the topic's holding. `dispatched`: print already-dispatched, exit
#      0. `dispatch-failed`: exit 3 (a failed topic is re-dispatched under a
#      new topic, by the coordinator's choice). `dispatching`: an earlier run
#      stopped partway. When `niwa list --json` shows the topic's session, go
#      to step 7 and confirm; otherwise re-check and re-render the brief
#      (steps 3 and 4, reusing the recorded return path, so no second leg) and
#      launch at step 6. This applies within the dispatch of the same topic
#      in the same run; once dispatch_check has seen the row, it refuses the
#      topic as duplicate-topic, and a later run's reconcile settles the row
#      instead (reconcile-settle.sh).
#   2. Refuse a topic a live session already uses (exit 5): koto session names
#      are machine-wide, so a second worker on one topic would collide.
#   3. Check the brief input (render-brief.sh), the entry point's target
#      requirement included. A refusal exits 1 with nothing written
#      anywhere; a target visibility that can't be read exits 2, also with
#      nothing written. On a resumed `dispatching` run the row and leg
#      already exist, so a refusal here (a target whose visibility changed
#      since) leaves them for the next run or reconcile. The brief itself is written after step 4, so
#      it shows the same invocation, --koto-leg included, as the prompt.
#   4. Open the leg, when references/entry-points.tsv gives the entry point
#      one: a one-leg koto request whose leg is the skill's own leg name,
#      admitting its templates and pinning the listed inputs. The return path
#      is `<request-id>:<leg>`, and `--koto-leg=<request-id>:<leg>` joins the
#      worker's invocation. Otherwise the return path is `message`.
#   5. Write ahead: the holding row with dispatch status `dispatching`, branch
#      empty (not yet known) and the pull request cell empty, the record's
#      "none yet".
#   6. Launch: `niwa dispatch "<prompt>" --name <topic> --detach` from the
#      workspace root, under a deadline (DISPATCH_DEADLINE_SECS, default 300),
#      plus `--brief <brief> --skill shirabe:<entry point>` when the installed
#      niwa lists both flags in `niwa dispatch --help`.
#   7. Confirm: on success, rewrite the row `dispatched` and print the session
#      name niwa reported, which the coordinator uses to message the worker
#      and never records. On a failure or the deadline, look for the topic's
#      session in `niwa list --json` before concluding anything: found means
#      it launched (confirm it); not found means it didn't (rewrite the row
#      `dispatch-failed`, abandon the request, exit 4); a listing that can't be
#      read leaves `dispatching` and exits 6 for the next run or reconcile.
#
# A topic's session is matched by its whole name, never by prefix (see
# dc_session_matches). niwa doesn't yet report the launched handle
# machine-readably (niwa#325), so the name comes from the `session name:` line
# of its output, or from `niwa list --json`'s session_name.
#
# --rebrief re-renders a held worker's brief after a report that needs a fix.
# It reads report_topic, takes the repository, entry point and flags from that
# topic's holding row rather than from the brief input or the report, writes
# the brief over the old one, and launches nothing. A leg carries one result,
# which the report just used, so the holding moves to the message path (its
# spent request is abandoned) and its `dispatched` date, which records when
# the worker was last briefed, is updated. The coordinator then sends the
# worker a message pointing at the brief.
#
# Usage:
#   dispatch-worker.sh --session <koto-session> [--rebrief]
#
# Output: `already-dispatched`, or `session=<name>` for a launched worker, or
# `brief=<path>` for --rebrief; reasons on stderr.
#
# Exit codes:
#   0  dispatched, confirmed, already dispatched, or re-briefed
#   1  brief refused; nothing written
#   2  usage, mismatched topic, no workspace root, a failed read or write
#   3  the topic already failed; dispatch under a new topic
#   4  the launch failed; the row says dispatch-failed
#   5  a live session already uses the topic
#   6  the launch outcome is unknown; the row stays dispatching
#   7  another run holds this topic's lock
#   8  the record refused the write (no open record, or a directed transition
#      in the run log): the run must restart before it writes again
#
# Environment: KOTO, NIWA (the binaries), DC_RECORD_HOLDING (the record's
# script), DISPATCH_DEADLINE_SECS. bash 3.2; needs jq.
set -uo pipefail

PROG=dispatch-worker
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

KOTO="${KOTO:-koto}"
NIWA="${NIWA:-niwa}"
DEADLINE="${DISPATCH_DEADLINE_SECS:-300}"
RE_REQ="$DC_RE_REQ"

die() { printf '%s: %s\n' "$PROG" "$2" >&2; exit "$1"; }
usage() { die 2 "usage: $PROG --session <koto-session> [--rebrief]"; }

SESSION=""
REBRIEF=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        --rebrief) REBRIEF=1; shift ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
command -v jq >/dev/null || die 2 "jq is not on PATH"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-worker.XXXXXX") || die 2 "cannot make a scratch directory"
LOCK=""
cleanup() {
    rm -rf "$WORK"
    [ -n "$LOCK" ] && rm -rf "$LOCK"
}
trap cleanup EXIT

ctx() { "$KOTO" context get "$SESSION" "$1"; }

# --- inputs ------------------------------------------------------------------------

INPUT="$WORK/brief_input.json"
ctx brief_input.json >"$INPUT" || die 2 "cannot read brief_input.json from the session's context"
jq -e 'type == "object"' "$INPUT" >/dev/null || die 2 "brief_input.json is not a JSON object"
IN_TOPIC=$(jq -r '.topic // "" | strings' "$INPUT")

if [ "$REBRIEF" = 1 ]; then
    TOPIC=$(ctx report_topic) || die 2 "cannot read report_topic from the session's context"
else
    TOPIC=$(ctx dispatch_topic) || die 2 "cannot read dispatch_topic from the session's context"
fi
dc_valid_topic "$TOPIC" || die 2 "the topic in context isn't a valid topic: $TOPIC"
[ "$IN_TOPIC" = "$TOPIC" ] || die 2 "brief_input.json names topic [$IN_TOPIC], not [$TOPIC]"

ROOT=$(dc_workspace_root) || die 2 "no workspace root found from $(pwd)"
BRIEFS="$ROOT/.niwa/dispatch-briefs"
mkdir -p "$BRIEFS" || die 2 "cannot create $BRIEFS"

# --- the per-topic lock --------------------------------------------------------------
#
# mkdir is atomic on every filesystem these run on, and flock isn't on macOS.
# A lock whose owner is gone (its pid no longer runs) is taken over.

#
# A lock with no pid file is one whose owner died between mkdir and writing
# its pid, a window of microseconds: once the directory is over a minute old
# it's taken over too. Two runs that find the same dead owner at the same
# moment can both take over; the second's rm then removes the first's lock.
# That race needs two coordinators dispatching one topic at once, which the
# record's one-holding-per-topic already rules out, so it is left as is.
LOCK_OWNER=""
take_lock() {
    local l="$BRIEFS/.$TOPIC.lock"
    if mkdir "$l" >/dev/null 2>&1; then
        printf '%s\n' "$$" >"$l/pid"
        LOCK="$l"
        return 0
    fi
    LOCK_OWNER=""
    [ -f "$l/pid" ] && LOCK_OWNER=$(cat "$l/pid")
    case "$LOCK_OWNER" in
        '')
            [ -n "$(find "$l" -maxdepth 0 -mmin +1)" ] || return 1
            ;;
        *[!0-9]*)
            return 1
            ;;
        *)
            kill -0 "$LOCK_OWNER" >/dev/null 2>&1 && return 1
            ;;
    esac
    rm -rf "$l"
    mkdir "$l" >/dev/null 2>&1 || return 1
    printf '%s\n' "$$" >"$l/pid"
    LOCK="$l"
}
take_lock || die 7 "another run holds the lock for $TOPIC (pid ${LOCK_OWNER:-not yet written}; the lock is $BRIEFS/.$TOPIC.lock)"

# --- helpers ---------------------------------------------------------------------------

# find_session: print the topic's live session name; 0 found, 1 none, 2 the
# listing couldn't be read.
find_session() {
    local found
    found=$(dc_find_session "$ROOT" "$TOPIC") || return $?
    printf '%s\n' "${found%%	*}"
}

# write_row <json>: write the topic's row; maps the writer's refusal to exit 8.
write_row() {
    printf '%s\n' "$1" >"$WORK/row.json"
    dc_record_write "$SESSION" "$TOPIC" "$WORK/row.json"
    case "$?" in
        0) return 0 ;;
        10) die 8 "the record refused the write for $TOPIC (no open record, or a directed transition in the run log)" ;;
        13) die 2 "the record is full (record-full): compact settled decisions or prune the record, then write the holding for $TOPIC again" ;;
        65) die 2 "the record refused the row for $TOPIC as malformed" ;;
        *) die 2 "writing the holding for $TOPIC failed" ;;
    esac
}

# with_status <row-json> <status>: the row with its dispatch status replaced.
with_status() { printf '%s' "$1" | jq -c --arg s "$2" '.dispatch_status = $s'; }

TODAY=$(date -u +%Y-%m-%d)

# --- read the holding ---------------------------------------------------------------------

ROW=$(dc_record_read "$SESSION" "$TOPIC")
case "$?" in
    0) HAVE_ROW=1 ;;
    1) HAVE_ROW=0; ROW="" ;;
    10) die 8 "the record refused the read for $TOPIC (no open record, or a directed transition in the run log)" ;;
    *) die 2 "reading the holding for $TOPIC failed" ;;
esac
STATUS=""
[ "$HAVE_ROW" = 1 ] && STATUS=$(printf '%s' "$ROW" | jq -r '.dispatch_status // "" | strings')

# --- --rebrief --------------------------------------------------------------------------------

if [ "$REBRIEF" = 1 ]; then
    [ "$HAVE_ROW" = 1 ] || die 2 "no holding for $TOPIC to re-brief"
    [ "$STATUS" = dispatched ] || die 2 "the holding for $TOPIC is $STATUS, not dispatched"
    # Repository and entry point come from the row, never from the report or
    # the brief input: a report is text the worker wrote.
    # Flags too: the holding's mode is the flags the worker was launched with,
    # and they become the re-brief's run mode, whatever the brief input says.
    jq --argjson row "$ROW" '.repo = $row.repo | .entry_point = $row.entry_point
        | .run_mode = $row.mode | .entry_args = [.entry_args[0]]' "$INPUT" >"$WORK/rebrief.json" ||
        die 2 "cannot build the re-brief input"
    # A worker's leg carries one result, and the fix comes after it, so a
    # re-briefed worker reports by message: the holding moves to the message
    # path and the spent request is abandoned. The brief says so by showing
    # the invocation without --koto-leg.
    ROW_RP=$(dc_rp_from_row "$(printf '%s' "$ROW" | jq -r '.return_path // "message" | strings')")
    BRIEF=$(bash "$HERE/render-brief.sh" --input "$WORK/rebrief.json" --workspace-root "$ROOT" --return-path message)
    case "$?" in
        0) ;;
        1) exit 1 ;;
        *) die 2 "rendering the brief failed" ;;
    esac
    write_row "$(printf '%s' "$ROW" | jq -c --arg d "$TODAY" '.dispatched = $d | .return_path = "message"')"
    if [ "$ROW_RP" != message ]; then
        "$KOTO" request abandon-request "${ROW_RP%%:*}" \
            --rationale "$TOPIC was re-briefed and reports by message from here" </dev/null >/dev/null ||
            printf '%s: could not abandon the spent request %s\n' "$PROG" "${ROW_RP%%:*}" >&2
    fi
    printf 'brief=%s\n' "$BRIEF"
    exit 0
fi

# --- dispatch ---------------------------------------------------------------------------------

case "$STATUS" in
    dispatched)
        printf 'already-dispatched\n'
        exit 0
        ;;
    dispatch-failed)
        die 3 "the dispatch of $TOPIC already failed; dispatch the unit under a new topic"
        ;;
esac

ENTRY=$(jq -r '.entry_point // "" | strings' "$INPUT")
REPO=$(jq -r '.repo // "" | strings' "$INPUT")

confirm() {
    write_row "$(with_status "$ROW" dispatched)"
    printf 'session=%s\n' "$1"
    exit 0
}

if [ "$STATUS" = dispatching ]; then
    NAME=$(find_session)
    case "$?" in
        0) confirm "$NAME" ;;
        1) RETURN_PATH=$(dc_rp_from_row "$(printf '%s' "$ROW" | jq -r '.return_path // "" | strings')") ;;
        *) die 6 "an earlier run left $TOPIC dispatching and niwa list can't be read to settle it" ;;
    esac
else
    NAME=$(find_session)
    case "$?" in
        0) die 5 "a live session already uses $TOPIC: $NAME" ;;
        1) ;;
        *) die 2 "niwa list can't be read to check $TOPIC is free" ;;
    esac
    RETURN_PATH=""
fi

# The unit becomes the holding's Unit cell, and pick finds a unit's holding
# only by the forms pick-facts.sh reads, so render-brief.sh --units refuses
# any other form against the units pick_facts listed in this pass
# (coord/pick.json, which only that check writes). A resumed dispatch's
# holding already records its unit, so it isn't checked again.
UNITS_FILE=""
if [ "$STATUS" != dispatching ]; then
    UNITS_FILE="$WORK/pick.json"
    ctx coord/pick.json >"$UNITS_FILE" || die 2 "cannot read coord/pick.json, the units pick_facts listed"
fi

# Check the brief before anything else happens: a refused input opens no leg
# and writes nothing. It's rendered for real once the return path is known,
# so the brief shows the same invocation the prompt carries.
bash "$HERE/render-brief.sh" --input "$INPUT" --units "$UNITS_FILE" --stdout >/dev/null
case "$?" in
    0) ;;
    1) exit 1 ;;
    *) die 2 "rendering the brief failed" ;;
esac

# The leg, opened once: a resumed run reuses the recorded return path.
if [ -z "$RETURN_PATH" ]; then
    LEG=$(dc_entry_field "$ENTRY" "$DC_F_LEG") || die 2 "no entry-point row for $ENTRY"
    [ "$LEG" = - ] || printf '%s' "$LEG" | grep -Eq "$DC_RE_LEG" || die 2 "entry-points.tsv names a malformed leg for $ENTRY: $LEG"
    POS=$(jq -r '.entry_args[0]' "$INPUT")
    # /work-on answers its leg only for an issue or a task. Given a PLAN path
    # it never reaches the leg, which would then stay open with nothing to
    # resolve it, so that worker reports by message.
    if [ "$ENTRY" = work-on ]; then
        case "$POS" in *PLAN-*.md) LEG=- ;; esac
    fi
    if [ "$LEG" = - ]; then
        RETURN_PATH=message
    else
        TEMPLATES=$(dc_entry_field "$ENTRY" "$DC_F_TEMPLATES")
        PINNED=$(dc_entry_field "$ENTRY" "$DC_F_PINNED")
        INPUTS='{}'
        if [ "$PINNED" != - ]; then
            IFS=, read -r -a PAIRS <<EOF
$PINNED
EOF
            for pair in "${PAIRS[@]}"; do
                var=${pair%%=*}
                src=${pair#*=}
                case "$src" in
                    arg) val="$POS" ;;
                    plan-slug)
                        val=$(basename "$POS" .md)
                        val=${val#PLAN-}
                        ;;
                    *) die 2 "entry-points.tsv names an unknown input source: $src" ;;
                esac
                INPUTS=$(printf '%s' "$INPUTS" | jq -c --arg k "$var" --arg v "$val" '.[$k] = $v')
            done
        fi
        # A run that died between opening its leg and writing the holding
        # left an open request under this topic's coordinator that no row
        # names. There is no row here, so any such request is that leftover:
        # abandon it before opening the one the row will name.
        LEFT=$("$KOTO" request list --coordinator-of-record "coordinate-$TOPIC" --state open </dev/null) ||
            die 2 "koto request list failed for $TOPIC"
        while IFS= read -r old; do
            [ -n "$old" ] || continue
            printf '%s' "$old" | grep -Eq "$RE_REQ" || continue
            "$KOTO" request abandon-request "$old" --rationale "left by an interrupted dispatch of $TOPIC" </dev/null >/dev/null ||
                die 2 "could not abandon the leftover request $old for $TOPIC"
        done <<EOF
$(printf '%s' "$LEFT" | jq -r --arg c "coordinate-$TOPIC" '(.requests // [])[] | select(.coordinator_of_record == $c and .request_state == "open") | .request_id')
EOF
        DATA=$(jq -nc --arg leg "$LEG" --arg t "$TEMPLATES" --argjson in "$INPUTS" \
            '{legs: [{name: $leg, role: $leg, template: ($t | split(",") | if length == 1 then .[0] else . end), inputs: $in}]}')
        DISPATCHER=$(jq -r '.dispatcher_session' "$INPUT")
        OUT=$("$KOTO" request create --with-data "$DATA" \
            --requested-by "$DISPATCHER" --coordinator-of-record "coordinate-$TOPIC" </dev/null) ||
            die 2 "koto request create failed for $TOPIC"
        REQ=$(printf '%s' "$OUT" | jq -r '.request_id // "" | strings')
        printf '%s' "$REQ" | grep -Eq "$RE_REQ" || die 2 "koto request create printed no usable request id"
        RETURN_PATH="$REQ:$LEG"
    fi
fi

# The brief, the worker's invocation and the prompt, all from the one builder.
BRIEF=$(bash "$HERE/render-brief.sh" --input "$INPUT" --units "$UNITS_FILE" --workspace-root "$ROOT" --return-path "$RETURN_PATH" --targets-checked)
case "$?" in
    0) ;;
    1) exit 1 ;;
    *) die 2 "rendering the brief failed" ;;
esac
INVOCATION=$(dc_invocation "$INPUT" "$RETURN_PATH") || die 2 "building the invocation failed"
PROMPT=$(jq -r --arg inv "$INVOCATION" --arg brief "$BRIEF" '
    .authority + " Run `" + $inv + "` in " + .repo + ", and stop at: " + (.checkpoints | last)
    + " Read " + $brief + " for your complete task brief, then do it."' "$INPUT")

# Write ahead, unless a resumed run's row is already there.
if [ "$STATUS" != dispatching ]; then
    ROW=$(jq -nc \
        --arg unit "$(jq -r '.unit' "$INPUT")" \
        --arg ep "$ENTRY" \
        --arg mode "$(dc_mode "$INPUT")" \
        --arg phase "$(jq -r '.phase' "$INPUT")" \
        --arg rp "$(dc_rp_to_row "$RETURN_PATH")" \
        --arg topic "$TOPIC" \
        --arg repo "$REPO" \
        --arg today "$TODAY" \
        '{unit: $unit, entry_point: $ep, mode: $mode, phase: $phase, dispatch_status: "dispatching",
          return_path: $rp, worker: $topic, repo: $repo, branch: "", verified_head: "",
          dispatched: $today, pull_request: ""}')
    write_row "$ROW"
fi

# The worker's lineage: the brief it runs and the skill it's asked to run, so
# niwa can put both on the worker's telemetry. niwa takes --brief and --skill
# from 0.28.0; an older niwa refuses flags it doesn't know, which would fail
# the dispatch, so they're added only when `niwa dispatch --help` lists both,
# and the launch is otherwise exactly what it was. The skill is the entry
# point's own name (the skill column of entry-points.tsv), which niwa requires
# as <plugin>:<name> in lowercase letters, digits and dashes.
LINEAGE=()
HELP=$(dc_with_deadline 30 "$NIWA" dispatch --help 2>/dev/null) || HELP=""
case "$HELP" in
    *--brief*)
        case "$HELP" in
            *--skill*)
                LINEAGE=(--brief "$BRIEF")
                printf '%s' "$ENTRY" | grep -Eq '^[a-z0-9][a-z0-9-]*$' && LINEAGE+=(--skill "shirabe:$ENTRY")
                ;;
        esac
        ;;
esac

# Launch.
LOG="$WORK/niwa.out"
(cd "$ROOT" && dc_with_deadline "$DEADLINE" "$NIWA" dispatch "$PROMPT" --name "$TOPIC" --detach ${LINEAGE[@]+"${LINEAGE[@]}"}) >"$LOG"
RC=$?
if [ "$RC" -eq 0 ]; then
    NAME=$(sed -n 's/^[[:space:]]*session name: //p' "$LOG" | head -1)
    if dc_session_matches "$TOPIC" "$NAME"; then
        confirm "$NAME"
    fi
    # Launched, but the name line is missing or unexpected: settle it from
    # the listing like any other unclear outcome.
fi

NAME=$(find_session)
case "$?" in
    0) confirm "$NAME" ;;
    1)
        write_row "$(with_status "$ROW" dispatch-failed)"
        case "$RETURN_PATH" in
            message) ;;
            *)
                "$KOTO" request abandon-request "${RETURN_PATH%%:*}" \
                    --rationale "the dispatch of $TOPIC failed" </dev/null >/dev/null ||
                    printf '%s: could not abandon request %s\n' "$PROG" "${RETURN_PATH%%:*}" >&2
                ;;
        esac
        die 4 "niwa dispatch failed for $TOPIC (exit $RC)"
        ;;
    *)
        die 6 "niwa dispatch exited $RC and niwa list can't be read; $TOPIC stays dispatching"
        ;;
esac
