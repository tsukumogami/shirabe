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
#                      equal dispatch_topic, or report_topic under --rebrief.
#                      Its optional `grant` is what the worker is dispatched
#                      holding: the authorities for the landing steps the
#                      brief hands it (merge-pr, close-issue, cut-release),
#                      none when it hands it none, or `own` for a successor
#                      (entry point coordinate), which takes this
#                      coordinator's own grant (below). Anything else exits
#                      1 with nothing written
#   coord/posture.json the coordinator's own `niwa authority check` answer,
#                      as posture-read.sh stored it under grant_check: `own`
#                      is its grant when its state is bound, and none
#                      otherwise, or when the key can't be read
#   the record's Run   its `coordinator` address (DC_RECORD_STATE --list),
#                      written into the input as reports_to, the address
#                      every brief tells its worker to report to; none
#                      exits 1 with nothing written
#   --session          the coordinator run itself, written into the input as
#                      dispatcher_session, over any value the input gave: the
#                      run a leg names as its requester, and the run a
#                      message-path worker records as its dispatcher
#                      (render-brief.sh), so a re-brief names the run that
#                      rendered it
#   report_topic       --rebrief: the worker whose report needs a fix;
#                      --releg: the worker whose leg was spent
#   coord/pick.json    the units pick_facts listed; the brief input's unit
#                      must be a form pick reads as covering one of them
#                      (dispatch-common.sh dc_unit_forms: a feature's tag or
#                      `<tag>: <title>`, an issue's `#<n>` or
#                      `<host>#<n>`), else exit 1 at step 3, before anything
#                      is written, naming the forms that would match. Read
#                      only for a new dispatch: a resumed one's holding
#                      already records its unit, and --rebrief writes no
#                      holding. A unit pick marked paused (its `paused`
#                      set, or `paused_all` set) exits 10 before anything is
#                      written: the dispatch check can't name a new
#                      dispatch's unit, so this is where a unit's pause holds
#                      one (docs/designs/current/DESIGN-coordinate-paused-state.md,
#                      Decision 1); so does a unit pick marked
#                      verdict_owed, a milestone whose verdict is owed
#                      (docs/designs/DESIGN-milestone-verdicts.md)
#
# The run, in order, under a per-topic lock:
#
#   1. Read the topic's holding. `dispatched`: print already-dispatched, exit
#      0. `dispatch-failed` or `stranded`: exit 3 (such a topic is
#      re-dispatched under a new topic, by the coordinator's choice).
#      `dispatching`: an earlier run
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
#      niwa lists both flags in `niwa dispatch --help`. When it lists
#      `--grant`, the worker's grant goes on as one `--grant <authority>` per
#      authority, and none at all for a worker granted nothing; when it
#      doesn't, no grant goes on and the brief says the worker holds no named
#      authority (the grant is settled before the brief renders, so the brief
#      names exactly what the launch asks for). When it lists `--parent-from`
#      and this script runs inside a niwa instance (the first directory at or
#      above the current one holding .niwa/instance.json), `--parent-from
#      <that instance root>` goes on too, so the worker's record names this
#      coordinator's dispatch as its parent. niwa refuses a grant wider than
#      its dispatcher's; that refusal is the one this script reports as such
#      (exit 11), and nothing retries it with another grant.
#   7. Confirm: on success, rewrite the row `dispatched` and print the session
#      name niwa reported, which the coordinator uses to message the worker
#      and never records. A rework Work row on the unit (a milestone a
#      confirmed changes-needed verdict or reopen sent back, whose text the brief
#      quoted) is removed then, with state-stored-set.sh --done --kind rework;
#      a failed removal is reported on stderr and the dispatch still
#      succeeds. On a failure or the deadline, look for the topic's
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
# worker a message pointing at the brief. The brief names the coordinator's
# current address, so the worker is recorded as told for it
# (state-stored-set.sh --told), unless it already is; that clears a pending
# row for it too.
#
# send_execution. A topic held `dispatched` at phase `scoping-ahead`, reached
# from a pick whose choice is send_execution for that topic (the latest
# `pick` evidence in the session log), is sent its execution rather than
# reported already dispatched (shirabe#553). The brief input is the
# execution's: its phase must read `executing` and its entry point must
# differ from the holding's, else exit 1 with nothing written. The brief is
# rendered from it; a new leg is opened when the execution's entry point
# takes one (the scoping leg is spent, and any request still open under the
# topic's coordinator is abandoned first), else the return path is
# `message`; and the holding is rewritten with the new entry point, mode,
# phase `executing`, return path and today's date, its unit, repository,
# branch and pull request kept. Nothing is launched: the coordinator messages
# the worker's existing session the brief, whose name is printed when the
# listing finds it. The record step then confirms the phase moved.
#
# --releg replaces a leg spent before its worker reported (shirabe#506): one
# cancelled, refused at the entry point's preflight, abandoned, or missing,
# with no promoted result on it. The holding must be `dispatched` on a leg,
# with no pull request. Its entry point, repository and flags come from the
# holding; the brief input supplies the rest of the brief, as for --rebrief.
# Every request still open under the topic's coordinator is abandoned, a new
# one-leg request is opened, the brief is rendered with the new
# --koto-leg, and the holding's return path and date are rewritten. The
# worker is not retired and nothing is launched: the coordinator messages its
# session the brief, to run its entry point again on the new leg. A leg still
# open, or one holding a promoted result (the worker reported), is not spent
# early: exit 9 with nothing written.
#
# Every leg this script opens is written to the coordinator's own session as
# the key legs/<request>/<leg> (dispatch-common.sh dc_leg_put), state `open`,
# with the worker's topic and the leg's declaration (its templates and pinned
# inputs), on either store (PRD R13). A leg a new one replaces (--releg, an
# execution sent) is marked `replaced`, and a failed launch's leg `spent`.
#
# --releg-imported <topic> re-attaches a worker that moved here with the
# coordinator's session (`koto session import`) to a new request on this host,
# whose request store never held the old one (docs/designs/DESIGN-coordinator-
# session-record.md, Decision 7). It reads no brief input and launches
# nothing. The holding must be dispatched on a leg whose key names <topic>,
# with the bound child's session name recorded (wait-target.sh writes it), and
# that session must be on this host, bound to no open leg here, compiled from
# one of the templates the holding's entry point admits, and holding the
# pinned inputs the key declared. The leg's name, its template set and the
# names of its pinned variables are recomputed from the holding's entry
# point, never read from the key. The pinned values do come from the key,
# which recorded them at dispatch: they were taken from the brief's
# positional argument (a topic slug or a PLAN's slug), which no holding cell
# carries. The child's own variables must equal them, and koto's `request
# attach` checks the child against the new request's declaration again. The steps, each idempotent: open the new request and
# write it into the old key as `releg-pending`; attach the child; write the
# new key `open` (from the old request); rewrite the holding's return path;
# mark the old key `relegged`. A re-run finds whichever step is missing and
# finishes it, so a crash leaves no leg bound to nothing and never two
# bindings. A refusal after the new request opened abandons it and sets the
# old key back to `open`.
#
# Usage:
#   dispatch-worker.sh --session <koto-session> [--rebrief | --releg]
#   dispatch-worker.sh --session <koto-session> --releg-imported <topic>
#
# Output: `already-dispatched`, or `session=<name>` for a launched worker, or
# `brief=<path>` for --rebrief (and `told=<topic>` when it recorded the
# worker told), or `brief=<path>` and `leg=<request>:<leg>`
# (and `session=<name>` when the listing finds it) for --releg and a sent
# execution, or `leg=<request>:<leg>` and `child=<session>` for
# --releg-imported; reasons on stderr.
#
# Exit codes:
#   0  dispatched, confirmed, already dispatched, re-briefed, a leg
#      replaced (--releg), or an execution sent
#   1  brief refused, a send_execution brief input that isn't the
#      execution's, or a /shirabe:deliver or /shirabe:scope brief for a unit
#      whose scoping landed (pick's follow_up); nothing written
#   2  usage, mismatched topic, no workspace root, a failed read or write
#   3  the topic already failed or is stranded; dispatch under a new topic
#   4  the launch failed; the row says dispatch-failed
#   5  a live session already uses the topic
#   6  the launch outcome is unknown; the row stays dispatching
#   7  another run holds this topic's lock
#   8  the record refused the write (no open record, or a directed transition
#      in the run log): the run must restart before it writes again
#   9  --releg on a leg that isn't spent early (still open, holding the
#      worker's promoted result, or resolved by hand as a success), on a
#      holding that links a pull request, or for an entry point that takes no
#      leg; a send_execution whose scoping leg a worker is still bound to;
#      nothing written. --releg-imported refused: the holding isn't
#      dispatched on a leg, its leg key is missing, names another worker or
#      is in no state to re-leg, its request is held on this host, no child
#      is recorded, the child's name fails the grammar, it isn't on this
#      host, it is bound to another leg, its template or pinned inputs differ
#      from the declaration, or koto refused the attach; nothing is left
#      half-done
#   10 a new dispatch of a unit a pause holds, a decision parks or whose
#      milestone verdict is owed, as pick
#      marked it; nothing written (submit `dispatched: paused`)
#   11 niwa refused the launch because the grant asked for is wider than the
#      dispatcher's (every line of its refusal contains `is wider than the
#      dispatcher's grant:`, which is printed); the row says
#      dispatch-failed and the request is abandoned. Report the refusal:
#      don't dispatch the unit again asking for more
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
usage() { die 2 "usage: $PROG --session <koto-session> [--rebrief | --releg | --releg-imported <topic>]"; }

SESSION=""
REBRIEF=0
RELEG=0
IMPORTED=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        --rebrief) REBRIEF=1; shift ;;
        --releg) RELEG=1; shift ;;
        --releg-imported) [ $# -ge 2 ] || usage; IMPORTED="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
[ "$REBRIEF$RELEG" != 11 ] || usage
[ -z "$IMPORTED" ] || [ "$REBRIEF$RELEG" = 00 ] || usage
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

# read_inputs: the brief input, the topic and the address every brief gives.
# --releg-imported renders no brief, so it reads none of them.
read_inputs() {
    INPUT="$WORK/brief_input.json"
    ctx brief_input.json >"$INPUT" || die 2 "cannot read brief_input.json from the session's context"
    jq -e 'type == "object"' "$INPUT" >/dev/null || die 2 "brief_input.json is not a JSON object"
    IN_TOPIC=$(jq -r '.topic // "" | strings' "$INPUT")

    if [ "$REBRIEF" = 1 ] || [ "$RELEG" = 1 ]; then
        TOPIC=$(ctx report_topic) || die 2 "cannot read report_topic from the session's context"
    else
        TOPIC=$(ctx dispatch_topic) || die 2 "cannot read dispatch_topic from the session's context"
    fi
    dc_valid_topic "$TOPIC" || die 2 "the topic in context isn't a valid topic: $TOPIC"
    [ "$IN_TOPIC" = "$TOPIC" ] || die 2 "brief_input.json names topic [$IN_TOPIC], not [$TOPIC]"

    # The address the brief tells the worker to report to is the record's:
    # its Run section's `coordinator`, the address messages to this
    # coordinator reach (shirabe#610). The koto session name in
    # dispatcher_session is no address. It is written into the input every
    # brief renders from, over any value the input gave; a record that names
    # no address refuses the dispatch.
    bash "$DC_RECORD_STATE" --list --session "$SESSION" >"$WORK/state.json" 2>"$WORK/state.err" ||
        die 2 "cannot read the record's Run section: $(head -1 "$WORK/state.err")"
    ADDRESS=$(jq -r '[(.run // [])[] | select(.key == "coordinator") | .value][0] // empty' "$WORK/state.json") ||
        die 2 "the record's Run section is not state-stored-set.sh's JSON"
    if [ -z "$ADDRESS" ]; then
        printf '%s: refused: the record names no coordinator address for the brief to give the worker; set it with state-stored-set.sh --session %s --run coordinator <address> --by <who>\n' "$PROG" "$SESSION" >&2
        exit 1
    fi
    # The dispatcher a brief names is this run, the one rendering it: a
    # message-path worker records it as its dispatcher, so after a re-brief,
    # or once a carried or imported run has taken over, it names the run that
    # rendered the new brief, whatever an older input said. A new leg's
    # --requested-by is read from the same field, so it names this run too.
    jq --arg a "$ADDRESS" --arg s "$SESSION" '.reports_to = $a | .dispatcher_session = $s' "$INPUT" >"$WORK/in.json" \
        && mv "$WORK/in.json" "$INPUT" || die 2 "jq failed"
}

# resolve_grant: what the worker is dispatched holding, settled before any
# brief renders. The coordinator's own grant is the answer posture-read.sh
# stored, never a second lookup. The input's `grant` is replaced by the grant
# the launch asks for, so the brief's authority line names exactly that: none
# when niwa can't take --grant. So a worker asking for a grant has the help
# read here, before its brief renders; any other dispatch reads it only at the
# launch (launch_flags), as before, and a run that launches nothing (a refusal,
# a re-brief, a re-leg, a sent execution) makes no niwa call for it. A
# re-brief, a re-leg and a sent execution resolve the grant the same way, from
# the input, the stored posture and the help as they read now. niwa never
# changes a running session's grant, so keep the input's `grant` as it was at
# the dispatch: the line is then what the worker holds unless niwa or the
# posture changed since. --releg-imported renders no brief, so it skips this.
HELP=""
PROBED=0
GRANT='[]'
GRANT_ARGS=()
PARENT_ARGS=()
# probe_help: read `niwa dispatch --help` into HELP, once per run.
probe_help() {
    [ "$PROBED" = 1 ] && return 0
    HELP=$(dc_with_deadline 30 "$NIWA" dispatch --help 2>/dev/null) || HELP=""
    PROBED=1
}
resolve_grant() {
    local req
    req=$(jq -c '.grant // []' "$INPUT") || die 2 "jq failed"
    if [ "$req" = '"own"' ]; then
        if [ "$(jq -r '.entry_point // "" | strings' "$INPUT")" != coordinate ]; then
            printf '%s: refused: grant: own is only for a successor coordinator (entry point coordinate)\n' "$PROG" >&2
            exit 1
        fi
        # A missing or unreadable key leaves koto's or jq's own message on
        # stderr, then the line below.
        req=$(ctx coord/posture.json | jq -c '((.grant_check | objects) // {}) as $g
            | if $g.state == "bound" then [($g.grant // [])[] | select(IN("merge-pr", "close-issue", "cut-release"))] | unique
              else [] end') || req=""
        if [ -z "$req" ]; then
            printf '%s: coord/posture.json can'\''t be read, so the successor is dispatched holding no named authority\n' "$PROG" >&2
            req='[]'
        fi
    fi
    if ! jq -e 'type == "array" and all(.[]; IN("merge-pr", "close-issue", "cut-release")) and length == (unique | length)' <<<"$req" >/dev/null; then
        printf '%s: refused: grant: a list of distinct authorities from merge-pr, close-issue and cut-release, or own\n' "$PROG" >&2
        exit 1
    fi
    if [ "$req" != '[]' ]; then
        probe_help
        case "$HELP" in
            *--grant*) ;;
            *)
                printf '%s: this niwa dispatch takes no --grant, so the worker is dispatched holding no named authority\n' "$PROG" >&2
                req='[]'
                ;;
        esac
    fi
    GRANT=$req
    jq --argjson g "$req" '.grant = $g' "$INPUT" >"$WORK/in.json" && mv "$WORK/in.json" "$INPUT" || die 2 "jq failed"
}

# launch_flags: the flags that carry the grant and the parent, from the help:
# one `--grant <authority>` per authority, and `--parent-from` with the first
# directory at or above this one holding .niwa/instance.json.
launch_flags() {
    local a d
    probe_help
    case "$HELP" in
        *--grant*)
            while IFS= read -r a; do
                [ -n "$a" ] && GRANT_ARGS+=(--grant "$a")
            done <<EOF
$(jq -r '.[]' <<<"$GRANT")
EOF
            ;;
    esac
    case "$HELP" in
        *--parent-from*)
            d=$(pwd -P)
            while [ "$d" != / ]; do
                if [ -f "$d/.niwa/instance.json" ]; then
                    PARENT_ARGS=(--parent-from "$d")
                    break
                fi
                d=$(dirname "$d")
            done
            ;;
    esac
}

if [ -n "$IMPORTED" ]; then
    TOPIC=$IMPORTED
    dc_valid_topic "$TOPIC" || die 2 "--releg-imported names no valid topic: $TOPIC"
else
    read_inputs
    resolve_grant
fi

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

# open_leg <entry> <positional> <why>: set RETURN_PATH for a worker on
# <entry>. When references/entry-points.tsv gives the entry point a leg, every
# request still open under the topic's coordinator is abandoned (with <why>
# as the rationale) and a one-leg request is opened, admitting the entry
# point's templates and pinning its inputs; otherwise the return path is
# `message`.
open_leg() {
    local entry=$1 pos=$2 why=$3 leg templates pinned inputs pair var src val left old data dispatcher out req
    leg=$(dc_entry_field "$entry" "$DC_F_LEG") || die 2 "no entry-point row for $entry"
    [ "$leg" = - ] || grep -Eq "$DC_RE_LEG" <<<"$leg" || die 2 "entry-points.tsv names a malformed leg for $entry: $leg"
    # /work-on answers its leg only for an issue or a task. Given a PLAN path
    # it never reaches the leg, which would then stay open with nothing to
    # resolve it, so that worker reports by message.
    if [ "$entry" = work-on ]; then
        case "$pos" in *PLAN-*.md) leg=- ;; esac
    fi
    if [ "$leg" = - ]; then
        RETURN_PATH=message
        return 0
    fi
    templates=$(dc_entry_field "$entry" "$DC_F_TEMPLATES")
    pinned=$(dc_entry_field "$entry" "$DC_F_PINNED")
    inputs='{}'
    if [ "$pinned" != - ]; then
        IFS=, read -r -a PAIRS <<EOF
$pinned
EOF
        for pair in "${PAIRS[@]}"; do
            var=${pair%%=*}
            src=${pair#*=}
            case "$src" in
                arg) val="$pos" ;;
                plan-slug)
                    val=$(basename "$pos" .md)
                    val=${val#PLAN-}
                    ;;
                *) die 2 "entry-points.tsv names an unknown input source: $src" ;;
            esac
            inputs=$(printf '%s' "$inputs" | jq -c --arg k "$var" --arg v "$val" '.[$k] = $v')
        done
    fi
    # Any request still open under this topic's coordinator is one no new
    # row will name: left by an interrupted dispatch, or the leg this one
    # replaces. Abandon it before opening the one the row will name.
    left=$("$KOTO" request list --coordinator-of-record "coordinate-$TOPIC" --state open </dev/null) ||
        die 2 "koto request list failed for $TOPIC"
    while IFS= read -r old; do
        [ -n "$old" ] || continue
        grep -Eq "$RE_REQ" <<<"$old" || continue
        "$KOTO" request abandon-request "$old" --rationale "$why" </dev/null >/dev/null ||
            die 2 "could not abandon the open request $old for $TOPIC"
    done <<EOF
$(printf '%s' "$left" | jq -r --arg c "coordinate-$TOPIC" '(.requests // [])[] | select(.coordinator_of_record == $c and .request_state == "open") | .request_id')
EOF
    data=$(jq -nc --arg leg "$leg" --arg t "$templates" --argjson in "$inputs" \
        '{legs: [{name: $leg, role: $leg, template: ($t | split(",") | if length == 1 then .[0] else . end), inputs: $in}]}')
    dispatcher=$(jq -r '.dispatcher_session' "$INPUT")
    out=$("$KOTO" request create --with-data "$data" \
        --requested-by "$dispatcher" --coordinator-of-record "coordinate-$TOPIC" </dev/null) ||
        die 2 "koto request create failed for $TOPIC"
    req=$(printf '%s' "$out" | jq -r '.request_id // "" | strings')
    grep -Eq "$RE_REQ" <<<"$req" || die 2 "koto request create printed no usable request id"
    RETURN_PATH="$req:$leg"
    # The leg as a key of the coordinator's own session (PRD R13), before any
    # holding names it. A failed write leaves the request open with no row
    # naming it, which the next dispatch of the topic abandons above. It also
    # holds the dispatch's unit, when its tag (the part before the first `: `)
    # has the shape the cost capture reads, so a capture after the holding is
    # gone still finds the milestone.
    local unit
    unit=$(jq -r '.unit // "" | strings | select(length <= 200 and (test("[[:cntrl:]]") | not))' "$INPUT") || unit=""
    [[ ${unit%%: *} =~ ^[A-Za-z0-9][A-Za-z0-9\ _.#/-]{0,63}$ ]] || unit=""
    dc_leg_put "$SESSION" "$req" "$leg" "$(jq -nc --arg r "$req" --arg l "$leg" --arg t "$TOPIC" \
        --arg tp "$templates" --argjson in "$inputs" --arg u "$unit" \
        '{request: $r, leg: $l, topic: $t, state: "open", templates: ($tp | split(",")), inputs: $in}
         + (if $u == "" then {} else {unit: $u} end)')" ||
        die 2 "could not write the leg key for $TOPIC's leg $RETURN_PATH"
}

# mark_leg <return-path> <state>: set the state of the leg key a return path
# names, when it has one. A leg opened before leg keys existed has none, and a
# failed write is reported, never fatal: the holding already says what
# happened, and the key only adds to it.
mark_leg() {
    local rp=$1 st=$2 key
    case "$rp" in message | '') return 0 ;; esac
    key=$(dc_leg_get "$SESSION" "${rp%%:*}" "${rp#*:}")
    case "$?" in
        0) dc_leg_put "$SESSION" "${rp%%:*}" "${rp#*:}" "$(jq -c --arg s "$st" '.state = $s' <<<"$key")" && return 0 ;;
        1) return 0 ;;
    esac
    printf '%s: could not mark the leg key for %s %s\n' "$PROG" "$rp" "$st" >&2
}

# leg_state <request> <leg>: how koto holds a worker's leg, one word: open
# (open, nobody attached), bound (open, the worker's session attached),
# promoted (the worker's own result), succeeded (resolved by hand as a
# success), spent (resolved otherwise: cancelled, refused at preflight; or
# abandoned, or open on a closed request), or missing (the request or the leg
# is gone). koto exits 2 for a request it doesn't hold, which reconcile-check.sh
# reads the same way; any other failed read exits 2 here. It runs in a
# command substitution, so call it as `x=$(leg_state ...) || exit 2`.
leg_state() {
    local view rc
    view=$("$KOTO" request get "$1" </dev/null)
    rc=$?
    [ "$rc" = 2 ] && { printf 'missing\n'; return 0; }
    [ "$rc" = 0 ] || die 2 "cannot read request $1 for $TOPIC"
    printf '%s' "$view" | jq -r --arg l "$2" '(.request // .) as $r | ($r.legs[$l] // null) as $g
        | if $g == null then "missing"
          elif $g.disposition == "open" and (($r.request_state // "open") == "open") then
            (if $g.bound_child != null then "bound" else "open" end)
          elif $g.disposition == "resolved" and $g.result_source == "promoted" then "promoted"
          elif $g.disposition == "resolved" and (($g.result.status // "") == "success") then "succeeded"
          else "spent" end' || die 2 "koto's record of request $1 is not JSON"
}

# rebind <input> <why> <row-jq> <need-leg>: never returns. Open the worker's new
# return path for the input's entry point, render its brief with it, and
# rewrite the holding through <row-jq> (given $rp, $ep, $mode, $d). Prints
# brief=, leg= and, when the listing finds the worker, session=. Launches
# nothing: the coordinator messages the worker's session the brief.
rebind() {
    local input=$1 why=$2 rowjq=$3 needleg=$4 ep pos mode brief name
    ep=$(jq -r '.entry_point // "" | strings' "$input")
    pos=$(jq -r '.entry_args[0] // "" | strings' "$input")
    mode=$(dc_mode "$input")
    if [ "$needleg" = yes ] && [ "$(dc_entry_field "$ep" "$DC_F_LEG")" = - ]; then
        die 9 "/shirabe:$ep takes no request leg: $TOPIC has no leg to replace"
    fi
    # The brief is checked before the leg opens: a refused input opens nothing.
    bash "$HERE/render-brief.sh" --input "$input" --stdout >/dev/null
    case "$?" in
        0) ;;
        1) exit 1 ;;
        *) die 2 "rendering the brief failed" ;;
    esac
    open_leg "$ep" "$pos" "$why"
    brief=$(bash "$HERE/render-brief.sh" --input "$input" --workspace-root "$ROOT" --return-path "$RETURN_PATH" --targets-checked)
    case "$?" in
        0) ;;
        1) exit 1 ;;
        *) die 2 "rendering the brief failed" ;;
    esac
    write_row "$(printf '%s' "$ROW" | jq -c --arg rp "$(dc_rp_to_row "$RETURN_PATH")" --arg ep "$ep" --arg mode "$mode" --arg d "$TODAY" "$rowjq")"
    mark_leg "$(dc_rp_from_row "$(printf '%s' "$ROW" | jq -r '.return_path // "" | strings')")" replaced
    printf 'brief=%s\n' "$brief"
    [ "$RETURN_PATH" = message ] || printf 'leg=%s\n' "$RETURN_PATH"
    if name=$(find_session); then printf 'session=%s\n' "$name"; fi
    exit 0
}

# --- --releg-imported -------------------------------------------------------------------------

# request_view <request>: koto's record of a request on this host, into VIEW.
# Returns 0 read, 1 this host's store doesn't hold it, 2 a failed read. koto
# answers a request its store doesn't hold with exit 2 (request_not_found),
# the code reconcile-check.sh's leg read and state-handover.sh read the
# same way.
request_view() {
    local rc
    VIEW=$("$KOTO" request get "$1" </dev/null)
    rc=$?
    [ "$rc" = 0 ] && return 0
    [ "$rc" = 2 ] && return 1
    return 2
}

# child_facts <session>: the child session's template file and variables, from
# the header and the first initialization of its own log, as one JSON object
# {template, variables}. Returns 2 when the log can't be read.
child_facts() {
    local dir log
    dir=$("$KOTO" session dir "$1" </dev/null) || return 2
    log="$dir/koto-$1.state.jsonl"
    [ -r "$log" ] || return 2
    jq -sc '{template: (.[0].template_source_file // ""),
             variables: ([.[] | select(.type == "workflow_initialized")][0].payload.variables // {})}' "$log"
}

# bound_elsewhere <session> <pending-request> <relegged-request>: 0 when the
# session is bound to an open leg of any open request on this host other than
# this re-leg's own two (the pending new one, and the old one, which this
# host's store doesn't hold anyway). A
# request it can't read stops the run (exit 2) rather than being passed
# over: binding a session a second time is the one thing a re-leg must not do.
bound_elsewhere() {
    local list r v
    list=$("$KOTO" request list --state open </dev/null) || die 2 "koto request list failed"
    while IFS= read -r r; do
        [ -n "$r" ] && [ "$r" != "$2" ] && [ "$r" != "$3" ] || continue
        v=$("$KOTO" request get "$r" </dev/null) || die 2 "cannot read request $r to check what $1 is bound to"
        jq -e --arg c "$1" '(.request // .) | [.legs[]? | select(.disposition == "open" and .bound_child == $c)] | length > 0' <<<"$v" >/dev/null &&
            return 0
    done <<EOF
$(jq -r '(.requests // [])[] | .request_id' <<<"$list")
EOF
    return 1
}

if [ -n "$IMPORTED" ]; then
    [ "$HAVE_ROW" = 1 ] || die 9 "no holding for $TOPIC to re-leg"
    [ "$STATUS" = dispatched ] || die 9 "the holding for $TOPIC is $STATUS, not dispatched"
    RP=$(dc_rp_from_row "$(jq -r '.return_path // "" | strings' <<<"$ROW")")
    case "$RP" in message | '') die 9 "the holding for $TOPIC reports by message: it has no leg to re-leg" ;; esac
    REQ=${RP%%:*}
    LEG=${RP#*:}
    KEY=$(dc_leg_get "$SESSION" "$REQ" "$LEG")
    case "$?" in
        0) ;;
        1) die 9 "the leg $RP of $TOPIC has no leg key: no child was recorded, so it can't be re-legged" ;;
        *) die 2 "cannot read the leg key for $RP" ;;
    esac
    [ "$(jq -r '.topic // "" | strings' <<<"$KEY")" = "$TOPIC" ] ||
        die 9 "the leg key for $RP names worker [$(jq -r '.topic // ""' <<<"$KEY")], not the holding's $TOPIC"
    KSTATE=$(jq -r '.state // "" | strings' <<<"$KEY")
    CHILD=$(jq -r '.child // "" | strings' <<<"$KEY")

    FROM=$(jq -r '.from // "" | strings' <<<"$KEY")
    case "$KSTATE" in
        open)
            request_view "$REQ"
            case "$?" in
                0)
                    # This host holds the leg's request. Either the holding
                    # was never moved, or a re-run finds the holding already
                    # on the new leg, whose key says where it came from: then
                    # only the old key's mark is left.
                    [ -n "$FROM" ] || die 9 "this host holds the request of $RP: $TOPIC is watched as before, not re-legged"
                    if OLD=$(dc_leg_get "$SESSION" "$FROM" "$LEG"); then
                        [ "$(jq -r '.state // ""' <<<"$OLD")" = relegged ] ||
                            dc_leg_put "$SESSION" "$FROM" "$LEG" "$(jq -c --arg n "$REQ" '.state = "relegged" | .new_request = $n' <<<"$OLD")" ||
                            die 2 "could not mark the leg key for $FROM:$LEG relegged"
                    fi
                    printf 'leg=%s\nchild=%s\n' "$RP" "$CHILD"
                    exit 0
                    ;;
                1) ;;
                *) die 2 "cannot read request $REQ" ;;
            esac
            NEW=""
            ;;
        releg-pending) NEW=$(jq -r '.new_request // "" | strings' <<<"$KEY") ;;
        *) die 9 "the leg key for $RP is $KSTATE: there is no leg to re-attach" ;;
    esac

    [ -n "$CHILD" ] || die 9 "no child session was recorded for $RP: $TOPIC can't be re-legged"
    [[ $CHILD =~ $DC_RE_SESSION ]] || die 9 "the child recorded for $RP isn't a koto session name"
    "$KOTO" session list </dev/null >"$WORK/sessions.json" || die 2 "koto session list failed"
    jq -e --arg c "$CHILD" 'any(.[]; .id == $c)' "$WORK/sessions.json" >/dev/null ||
        die 9 "the child $CHILD of $RP isn't on this host: $TOPIC can't be re-legged"

    # The declaration, recomputed from the holding's entry point: the leg it
    # answers, the templates it admits and the inputs it pins. Only the pinned
    # values come from the key, which recorded them at dispatch; the child's
    # own variables must equal them.
    EP=$(jq -r '.entry_point // "" | strings' <<<"$ROW")
    EP_LEG=$(dc_entry_field "$EP" "$DC_F_LEG") || die 9 "the holding's entry point $EP has no entry-point row"
    [ "$EP_LEG" = "$LEG" ] || die 9 "the holding's entry point $EP answers leg [$EP_LEG], not [$LEG]"
    TEMPLATES=$(dc_entry_field "$EP" "$DC_F_TEMPLATES") || die 2 "no templates for $EP"
    PINNED=$(dc_entry_field "$EP" "$DC_F_PINNED") || die 2 "no pinned inputs for $EP"
    INPUTS='{}'
    if [ "$PINNED" != - ]; then
        IFS=, read -r -a PAIRS <<<"$PINNED"
        for pair in "${PAIRS[@]}"; do
            var=${pair%%=*}
            val=$(jq -r --arg v "$var" '.inputs[$v] // "" | strings' <<<"$KEY")
            [ -n "$val" ] || die 9 "the leg key for $RP records no $var for the declaration"
            INPUTS=$(jq -c --arg k "$var" --arg v "$val" '.[$k] = $v' <<<"$INPUTS")
        done
    fi
    FACTS=$(child_facts "$CHILD") || die 2 "cannot read the log of $CHILD"
    CT=$(jq -r '.template' <<<"$FACTS")
    case ",$TEMPLATES," in
        *",$CT,"*) ;;
        *) die 9 "the child $CHILD runs template [$CT], which $EP's leg doesn't admit ($TEMPLATES)" ;;
    esac
    jq -e --argjson in "$INPUTS" '.variables as $v | all($in | to_entries[]; $v[.key] == .value)' <<<"$FACTS" >/dev/null ||
        die 9 "the child $CHILD's variables differ from the declaration $INPUTS"
    if bound_elsewhere "$CHILD" "$NEW" "$REQ"; then
        die 9 "the child $CHILD is bound to another leg on this host: $TOPIC can't be re-legged"
    fi

    # refuse_after_open <reason>: a refusal once the new request exists. The
    # request is abandoned and the old key goes back to open, so nothing is
    # left half-done and the classification can send the worker to message.
    refuse_after_open() {
        "$KOTO" request abandon-request "$NEW" --rationale "the re-leg of $TOPIC was refused" </dev/null >/dev/null ||
            printf '%s: could not abandon request %s\n' "$PROG" "$NEW" >&2
        dc_leg_put "$SESSION" "$REQ" "$LEG" "$(jq -c '.state = "open" | del(.new_request)' <<<"$KEY")" ||
            printf '%s: could not set the leg key for %s back to open\n' "$PROG" "$RP" >&2
        die 9 "$1"
    }

    # 1. The new request, written into the old key before anything is bound.
    # A pending one this host no longer holds is opened again.
    if [ -n "$NEW" ]; then
        request_view "$NEW"
        case "$?" in
            0) ;;
            1) NEW="" ;;
            *) die 2 "cannot read the pending request $NEW" ;;
        esac
    fi
    if [ -z "$NEW" ]; then
        # A request an earlier run opened under this topic and was stopped
        # before it recorded is named by no key: abandon it, so the one this
        # run opens is the topic's only open request here. The leg being
        # re-legged is never among them (this host's store doesn't hold its
        # request, which is how this run got here), and is skipped by name
        # all the same.
        LEFT=$("$KOTO" request list --coordinator-of-record "coordinate-$TOPIC" --state open </dev/null) ||
            die 2 "koto request list failed for $TOPIC"
        while IFS= read -r old; do
            [[ $old =~ $RE_REQ ]] || continue
            [ "$old" != "$REQ" ] || continue
            "$KOTO" request abandon-request "$old" --rationale "left by an interrupted re-leg of $TOPIC" </dev/null >/dev/null ||
                die 2 "could not abandon the open request $old for $TOPIC"
        done <<EOF
$(jq -r --arg c "coordinate-$TOPIC" '(.requests // [])[] | select(.coordinator_of_record == $c and .request_state == "open") | .request_id' <<<"$LEFT")
EOF
        DATA=$(jq -nc --arg leg "$LEG" --arg t "$TEMPLATES" --argjson in "$INPUTS" \
            '{legs: [{name: $leg, role: $leg, template: ($t | split(",") | if length == 1 then .[0] else . end), inputs: $in}]}')
        OUT=$("$KOTO" request create --with-data "$DATA" --requested-by "$SESSION" \
            --coordinator-of-record "coordinate-$TOPIC" </dev/null) || die 2 "koto request create failed for $TOPIC"
        NEW=$(jq -r '.request_id // "" | strings' <<<"$OUT")
        [[ $NEW =~ $RE_REQ ]] || die 2 "koto request create printed no usable request id"
        KEY=$(jq -c --arg n "$NEW" '.state = "releg-pending" | .new_request = $n' <<<"$KEY")
        dc_leg_put "$SESSION" "$REQ" "$LEG" "$KEY" || {
            "$KOTO" request abandon-request "$NEW" --rationale "the re-leg of $TOPIC could not be recorded" </dev/null >/dev/null ||
                printf '%s: could not abandon request %s\n' "$PROG" "$NEW" >&2
            die 2 "could not write the leg key for $RP"
        }
        request_view "$NEW" || die 2 "cannot read the new request $NEW"
    fi

    # 2. The child attached, unless an earlier run already did.
    BOUND=$(jq -r --arg l "$LEG" '(.request // .) | .legs[$l].bound_child // "" | strings' <<<"$VIEW")
    if [ -z "$BOUND" ]; then
        if ! "$KOTO" request attach --session "$CHILD" "$NEW" "$LEG" </dev/null >"$WORK/attach.out" 2>&1; then
            WHY=$(cut -c1-300 "$WORK/attach.out" | head -n 3)
            refuse_after_open "the attach of $CHILD to $NEW:$LEG was refused: $WHY"
        fi
    elif [ "$BOUND" != "$CHILD" ]; then
        refuse_after_open "the new request $NEW is bound to $BOUND, not $CHILD"
    fi

    # 3. The new leg's key, naming where it came from.
    dc_leg_put "$SESSION" "$NEW" "$LEG" "$(jq -c --arg n "$NEW" --arg f "$REQ" --argjson in "$INPUTS" --arg t "$TEMPLATES" \
        '{request: $n, leg, topic, state: "open", templates: ($t | split(",")), inputs: $in, child, from: $f}
         + (if has("unit") then {unit} else {} end)' <<<"$KEY")" ||
        die 2 "could not write the leg key for $NEW:$LEG"
    # 4. The holding's return path, then 5. the old key marked.
    write_row "$(jq -c --arg rp "$(dc_rp_to_row "$NEW:$LEG")" '.return_path = $rp' <<<"$ROW")"
    dc_leg_put "$SESSION" "$REQ" "$LEG" "$(jq -c '.state = "relegged"' <<<"$KEY")" ||
        die 2 "could not mark the leg key for $RP relegged"
    printf 'leg=%s:%s\nchild=%s\n' "$NEW" "$LEG" "$CHILD"
    exit 0
fi

# --- --releg ----------------------------------------------------------------------------------

if [ "$RELEG" = 1 ]; then
    [ "$HAVE_ROW" = 1 ] || die 2 "no holding for $TOPIC to re-bind"
    [ "$STATUS" = dispatched ] || die 2 "the holding for $TOPIC is $STATUS, not dispatched"
    [ -z "$(printf '%s' "$ROW" | jq -r '.pull_request // "" | strings')" ] ||
        die 9 "the holding for $TOPIC links a pull request: its worker produced something, so its leg isn't spent early"
    OLD_RP=$(dc_rp_from_row "$(printf '%s' "$ROW" | jq -r '.return_path // "" | strings')")
    case "$OLD_RP" in
        message | '') die 9 "the holding for $TOPIC reports by message: it has no leg to replace" ;;
    esac
    OLD_REQ=${OLD_RP%%:*}
    OLD_LEG=${OLD_RP#*:}
    # The spent leg, as koto holds it: open or bound is not spent, a
    # promoted result is the worker's report, and a hand-made success means
    # the work was done another way. A leg koto no longer has is missing,
    # which counts as spent.
    SPENT=$(leg_state "$OLD_REQ" "$OLD_LEG") || exit 2
    case "$SPENT" in
        open | bound) die 9 "the leg $OLD_RP of $TOPIC is still open: nothing to replace" ;;
        promoted) die 9 "the leg $OLD_RP of $TOPIC holds the worker's promoted result: it reported, so its leg isn't spent early" ;;
        succeeded) die 9 "the leg $OLD_RP of $TOPIC was resolved as a success: the work was done, so its leg isn't spent early" ;;
    esac
    # Entry point, repository and flags from the holding, as for --rebrief.
    jq --argjson row "$ROW" '.repo = $row.repo | .entry_point = $row.entry_point
        | .run_mode = $row.mode | .entry_args = [.entry_args[0]]' "$INPUT" >"$WORK/releg.json" ||
        die 2 "cannot build the re-bound brief input"
    rebind "$WORK/releg.json" "the leg $OLD_RP of $TOPIC was spent before the worker reported; it is replaced" \
        '.return_path = $rp | .dispatched = $d' yes
fi

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
    # The brief just written names the coordinator's current address, which
    # is how the worker learns it, so the re-brief records the worker as told
    # for it (tsukumogami/shirabe#1245); a worker already told is left as it
    # is. A record that refuses the row warns and changes nothing else: the
    # brief stands, and the handover gate still names the gap.
    if ! jq -e --arg w "$TOPIC" 'any((.run // [])[]; .key == "told" and .value == $w)' "$WORK/state.json" >/dev/null; then
        if bash "$DC_RECORD_STATE" --session "$SESSION" --told "$TOPIC" --by "$ADDRESS" >/dev/null 2>"$WORK/told.err"; then
            printf 'told=%s\n' "$TOPIC"
        else
            printf '%s: the brief gives %s the address, but recording it told failed: %s\n' "$PROG" "$TOPIC" "$(head -1 "$WORK/told.err")" >&2
        fi
    fi
    exit 0
fi

# --- dispatch ---------------------------------------------------------------------------------

# send_execution: the pick the run came from, read from the session log. A
# log that can't be read exits 2 rather than reading as no send, which would
# print already-dispatched for a send that never happened.
pick_sends_execution() {
    local ent ev choice unit rc
    ent=$(bash "$HERE/coord-log.sh" entry --session "$SESSION" --state pick)
    rc=$?
    [ "$rc" = 1 ] && return 1
    [ "$rc" = 0 ] || die 2 "cannot read the session log for $TOPIC's pick"
    [ -n "$ent" ] || return 1
    ev=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state pick --after "${ent%% *}")
    rc=$?
    [ "$rc" = 1 ] && return 1
    [ "$rc" = 0 ] || die 2 "cannot read the session log for $TOPIC's pick"
    choice=$(printf '%s' "$ev" | jq -r '.fields.choice // "" | tostring')
    unit=$(printf '%s' "$ev" | jq -r '.fields.unit // "" | tostring')
    [ "$choice" = send_execution ] && [ "$unit" = "$TOPIC" ]
}

case "$STATUS" in
    dispatched)
        PHASE=$(printf '%s' "$ROW" | jq -r '.phase // "" | strings')
        if [ "$PHASE" = scoping-ahead ] && pick_sends_execution; then
            # The execution's brief input, never the scoping's again.
            [ "$(jq -r '.phase // "" | strings' "$INPUT")" = executing ] ||
                { printf '%s: send_execution for %s: brief_input.json must be the execution'"'"'s (phase executing)\n' "$PROG" "$TOPIC" >&2; exit 1; }
            [ "$(jq -r '.entry_point // "" | strings' "$INPUT")" != "$(printf '%s' "$ROW" | jq -r '.entry_point // "" | strings')" ] ||
                { printf '%s: send_execution for %s: brief_input.json names the scoping entry point again\n' "$PROG" "$TOPIC" >&2; exit 1; }
            # A worker still attached to its scoping leg is still scoping:
            # its leg would be abandoned under it.
            SRP=$(dc_rp_from_row "$(printf '%s' "$ROW" | jq -r '.return_path // "" | strings')")
            case "$SRP" in
                message | '') ;;
                *) SST=$(leg_state "${SRP%%:*}" "${SRP#*:}") || exit 2
                   [ "$SST" = bound ] &&
                       die 9 "send_execution for $TOPIC: its worker is still attached to its scoping leg $SRP" ;;
            esac
            # The holding's unit and repository stay the holding's.
            jq --argjson row "$ROW" '.unit = $row.unit | .repo = $row.repo' "$INPUT" >"$WORK/execution.json" ||
                die 2 "cannot build the execution's brief input"
            rebind "$WORK/execution.json" "$TOPIC is sent its execution; its scoping leg is done" \
                '.entry_point = $ep | .mode = $mode | .phase = "executing" | .return_path = $rp | .dispatched = $d' no
        fi
        printf 'already-dispatched\n'
        exit 0
        ;;
    dispatch-failed)
        die 3 "the dispatch of $TOPIC already failed; dispatch the unit under a new topic"
        ;;
    stranded)
        die 3 "$TOPIC is stranded; dispatch the unit under a new topic"
        ;;
esac

ENTRY=$(jq -r '.entry_point // "" | strings' "$INPUT")
REPO=$(jq -r '.repo // "" | strings' "$INPUT")

confirm() {
    write_row "$(with_status "$ROW" dispatched)"
    clear_rework "$(printf '%s' "$ROW" | jq -r '.unit // ""')"
    retire_stranded
    printf 'session=%s\n' "$1"
    exit 0
}
# retire_stranded: remove the stranded rows this dispatch replaced. The new
# worker is already launched, so a failed removal is reported, not fatal: the
# row stays stranded, which nothing dispatches or watches, and the next
# dispatch of the unit retires it.
retire_stranded() {
    local old
    [ -n "${STRANDED:-}" ] && [ "$STRANDED" != '[]' ] || return 0
    while IFS= read -r old; do
        [ -n "$old" ] || continue
        bash "$DC_RECORD_HOLDING" --session "$SESSION" --topic "$old" --retire >/dev/null 2>"$WORK/retire.err" ||
            printf '%s: %s is dispatched, but the stranded row %s stands (%s); remove it with state-holding.sh --session %s --topic %s --retire\n' \
                "$PROG" "$TOPIC" "$old" "$(head -1 "$WORK/retire.err")" "$SESSION" "$old" >&2
    done <<EOF
$(jq -r '.[].worker' <<<"$STRANDED")
EOF
}
# clear_rework <unit cell>: a milestone a changes-needed verdict or a reopen sent back
# carries a rework row until a worker is dispatched for it, whose brief
# quoted the row (render-brief.sh); the dispatch confirmed, the row goes.
# The worker is already launched, so a failed removal is reported, not
# fatal: the row stays and the next brief for the unit quotes it again.
clear_rework() {
    local item
    item=$(jq -r --arg u "$1" '[(.work // [])[] | select(.kind == "rework") | .item as $x
        | select($x == $u or ($u | startswith($x + ": ")))][0].item // empty' "$WORK/state.json") || item=""
    [ -n "$item" ] || return 0
    bash "$DC_RECORD_STATE" --session "$SESSION" --done "$item" --kind rework >/dev/null 2>"$WORK/rework.err" ||
        printf '%s: %s is dispatched, but its rework row stands (%s); remove it with state-stored-set.sh --session %s --done "%s" --kind rework\n' \
            "$PROG" "$TOPIC" "$(head -1 "$WORK/rework.err")" "$SESSION" "$item" >&2
}

# A unit whose earlier worker was stranded (state-holding.sh --strand) goes
# out again under this new topic. Its brief names the stranded row's branch
# and last pushed head, so the new worker continues from what was pushed, and
# the stranded row is retired once this one is dispatched (PRD R15;
# shirabe#732). A report from the retired topic then matches no holding.
ALL_ROWS=$(dc_record_list "$SESSION")
case "$?" in
    0) ;;
    10) die 8 "the record refused the read for $TOPIC (no open record, or a directed transition in the run log)" ;;
    *) die 2 "reading the holdings failed" ;;
esac
STRANDED=$(jq -c --arg u "$(jq -r '.unit // ""' "$INPUT")" --arg t "$TOPIC" \
    '[.[] | select(.dispatch_status == "stranded" and .unit == $u and .worker != $t)]' <<<"$ALL_ROWS") ||
    die 2 "the holdings are not JSON"
if [ "$STRANDED" != '[]' ]; then
    jq --argjson s "$STRANDED" '.decisions = ((.decisions // []) + [$s[]
        | ((.pushed_head // "") | if . == "" then null else . end) as $p
        | ((.verified_head // "") | if . == "" then null else . end) as $v
        | {decision: ("This unit was held by worker " + .worker + ", which was stranded: continue from its branch "
            + (if (.branch // "") == "" then "(it recorded none)" else "`" + .branch + "`" end)
            + (if ($p // $v) != null then ", last pushed head `" + ($p // $v) + "`" else ", with no pushed head recorded" end)
            + ", rather than starting over."),
           by: "the coordinator'"'"'s record"}])' "$INPUT" >"$WORK/in.json" && mv "$WORK/in.json" "$INPUT" ||
        die 2 "cannot add the stranded worker's branch to the brief input"
fi

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
# (coord/pick.json, which only pick-facts.sh writes, as pick_facts' action).
# A new dispatch with no coord/pick.json exits 2. A resumed dispatch's
# holding already records its unit, so it isn't checked again.
UNITS_FILE=""
if [ "$STATUS" != dispatching ]; then
    UNITS_FILE="$WORK/pick.json"
    ctx coord/pick.json >"$UNITS_FILE" || die 2 "cannot read coord/pick.json, the units pick_facts listed"
    # The unit pick listed under one of its forms (dc_unit_forms' rule) and
    # what pick_facts said holds it; pick's `paused` already lets a go-ahead's
    # unit through a pause on all. A unit pick didn't list falls back to
    # paused_all; render-brief.sh refuses it below anyway.
    jq -c --arg u "$(jq -r '.unit // ""' "$INPUT")" '
        (.host // "") as $h
        | [.units[]? | .unit as $x | select($x == $u or ($u | startswith($x + ": ")) or ($h != "" and ($h + $x) == $u))][0] as $m
        | {paused: (if $m == null then (.paused_all // null) else ($m.paused // null) end),
           awaiting: ($m.awaiting // null), follow_up: ($m.follow_up // null), verdict_owed: ($m.verdict_owed // false)}' "$UNITS_FILE" >"$WORK/unit-facts.json" \
        || die 2 "coord/pick.json is not pick_facts' JSON"
    PAUSED=$(jq -r '.paused // empty' "$WORK/unit-facts.json")
    [ -z "$PAUSED" ] || die 10 "pause $PAUSED holds this unit, as pick_facts read it: nothing dispatched; submit dispatched: paused"
    # A milestone whose verdict is owed waits for that verdict, never a new
    # worker (docs/designs/DESIGN-milestone-verdicts.md, Decision 1).
    jq -e '.verdict_owed == true' "$WORK/unit-facts.json" >/dev/null \
        && die 10 "a verdict is owed on this milestone, as pick_facts read it: nothing dispatched until its verdict's roadmap edit is confirmed; submit dispatched: paused"
    # A unit parked on a decision waits for its answer like a pause; one
    # whose scoping landed is sent its execution, never scoped again.
    AWAITING=$(jq -r '.awaiting // empty' "$WORK/unit-facts.json")
    [ -z "$AWAITING" ] || die 10 "decision $AWAITING parks this unit until it is settled, as pick_facts read it: nothing dispatched; submit dispatched: paused"
    if jq -e '.follow_up != null' "$WORK/unit-facts.json" >/dev/null; then
        case "$ENTRY" in
            deliver|scope)
                printf '%s: refused: this unit'\''s scoping landed as %s; brief its execution (%s), not /shirabe:%s\n' "$PROG" \
                    "$(jq -r '.follow_up.after' "$WORK/unit-facts.json")" "$(jq -r '.follow_up.next' "$WORK/unit-facts.json")" "$ENTRY" >&2
                exit 1
                ;;
        esac
    fi
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
    open_leg "$ENTRY" "$(jq -r '.entry_args[0]' "$INPUT")" "left by an interrupted dispatch of $TOPIC"
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
# as <plugin>:<name> in lowercase letters, digits and dashes. The help is read
# once per run (probe_help), with the grant's flags.
launch_flags
LINEAGE=()
case "$HELP" in
    *--brief*)
        case "$HELP" in
            *--skill*)
                LINEAGE=(--brief "$BRIEF")
                grep -Eq '^[a-z0-9][a-z0-9-]*$' <<<"$ENTRY" && LINEAGE+=(--skill "shirabe:$ENTRY")
                ;;
        esac
        ;;
esac

# Launch. The deadline's TERM reaches niwa alone, not its process group
# (dc_tree): niwa may start the worker's hand-off in that group, and a TERM
# to it could stop the worker being launched. The git commands niwa runs can
# outlive it until niwa stops them on TERM itself (tsukumogami/niwa#391).
# niwa's stderr is kept to tell its never-wider refusal from any other
# failure, and passed on whole.
LOG="$WORK/niwa.out"
(cd "$ROOT" && dc_with_deadline "$DEADLINE" "$NIWA" dispatch "$PROMPT" --name "$TOPIC" --detach \
    ${LINEAGE[@]+"${LINEAGE[@]}"} ${GRANT_ARGS[@]+"${GRANT_ARGS[@]}"} ${PARENT_ARGS[@]+"${PARENT_ARGS[@]}"}) >"$LOG" 2>"$WORK/niwa.err"
RC=$?
cat "$WORK/niwa.err" >&2
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
                mark_leg "$RETURN_PATH" spent
                ;;
        esac
        if [ "$RC" -ne 0 ] && grep -q "is wider than the dispatcher's grant:" "$WORK/niwa.err"; then
            die 11 "niwa refused $TOPIC's grant as wider than this coordinator's own; report the refusal and don't dispatch it again asking for more"
        fi
        die 4 "niwa dispatch failed for $TOPIC (exit $RC)"
        ;;
    *)
        die 6 "niwa dispatch exited $RC and niwa list can't be read; $TOPIC stays dispatching"
        ;;
esac
