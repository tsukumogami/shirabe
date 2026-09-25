#!/usr/bin/env bash
# resume-probe.sh -- /scope's resume ladder as one read-only probe.
#
# `resume_route` in skills/scope/koto-templates/scope.md runs this as its one
# gate and sends each exit code to a state. The ladder used to run as agent
# prose; the rows, their order and their prompts are specified in
# skills/scope/references/phases/phase-resume.md, which stays the normative
# spec and names this probe's exit code on every row.
#
# It reads the artifact tree, the run's state file, the child partials under
# wip/, the /explore handoff, and the current branch name. It writes nothing,
# and it makes no gh call and no network call. RUN_INTENT arrives as an
# argument, because the intent shortcuts (rows 40 and 44) exist only on intent
# runs and a plan-active topic (row 41) is refused only without one.
#
# Rows, first match wins (the ladder's order, most-downstream first):
#
#   state file present (meta-ladder rows 1-4)
#     25  malformed: unreadable, a duplicate or missing required field, or a
#         value outside its enum or pattern (exit, phase_pointer, intent,
#         plan_execution_mode, publish_error, published_pr, and the exit
#         path's sub-shape fields)
#     27  exit: full-run with publish_error: recorded, intent set
#     28  exit: re-evaluation with publish_error: recorded, intent set
#     29  exit: abandonment-forced with publish_error: recorded, intent set
#     26  exit set, no publish pending (or no intent to publish with)
#     24  exit unset and last_updated 7 days old or more (not with
#         --ignore-stale, which resume_stale's Resume choice uses)
#     20  exit unset, fresh, phase_pointer 0 or 1   -> discovery
#     21  exit unset, fresh, phase_pointer 2        -> hop_select
#     22  exit unset, fresh, phase_pointer 3        -> finalize
#   no state file: Slot 5, the artifact tree
#     40  a PLAN at Active or Draft, intent set                -> republish
#     42  a PLAN at Done                                       -> refused
#     41  a PLAN at Active, no intent                          -> refused
#     43  a PLAN at Draft, no intent                           -> resume_draft
#     44  no PLAN, a DESIGN under docs/designs/current/, intent set
#                                                              -> executed_report
#     45  a settled DESIGN (Accepted, Planned or Current; either location),
#         which is also where an executed topic without intent lands
#     46  a Proposed DESIGN                                    -> resume_draft
#     47  a settled PRD (Accepted, In Progress or Done)        -> resume_boundary
#     48  a Draft PRD                                          -> resume_draft
#     49  an Accepted or Done BRIEF                            -> setup
#     50  a Draft BRIEF                                        -> resume_draft
#   Slot 6, a child partial
#     60  wip/plan_<topic>_*
#     61  wip/design_<topic>_coordination.json
#     62  wip/prd_<topic>_decisions.md
#     63  wip/brief_<topic>_*
#   Slot 7, and the meta-ladder tail
#     12  the /explore handoff wip/scope_<topic>_handoff.md
#     11  nothing on disk, on a branch whose name contains the topic
#     10  nothing on disk, any other branch
#
#   2   cannot tell: an invalid topic or intent, an artifact whose status
#       cannot be read, or a git read that failed
#   64  usage error
#
# A status outside the sets above (a Superseded DESIGN, say) is not a row of
# its own; the ladder falls through to the rows below it.
#
# stdout carries one line naming the row, `row=<code> <name>`, for a person
# reading a gate's blocking conditions; koto routes on the exit code alone.
#
# Usage:
#   resume-probe.sh --topic <slug> --intent <continue|stop|none> [--ignore-stale]
#
# The working directory is the repository being scoped. SCOPE_PROBE_NOW, an
# epoch second count, replaces the clock for the staleness test (tests only).
#
# Requires: bash 3.2+, git, awk.
set -uo pipefail

PROG=resume-probe

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
STALE_SECS=$((7 * 24 * 3600))

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: resume-probe.sh --topic <slug> --intent <continue|stop|none> [--ignore-stale]\n' >&2
    exit 64
}

row() { # row <code> <name>
    printf 'row=%s %s\n' "$1" "$2"
    exit "$1"
}

cannot_tell() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    row 2 cannot-tell
}

TOPIC=""; INTENT=""; IGNORE_STALE=0
SEEN_TOPIC=0; SEEN_INTENT=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --topic)  [ "$#" -ge 2 ] || usage "--topic needs a value"; TOPIC="$2"; SEEN_TOPIC=$((SEEN_TOPIC + 1)); shift ;;
        --intent) [ "$#" -ge 2 ] || usage "--intent needs a value"; INTENT="$2"; SEEN_INTENT=$((SEEN_INTENT + 1)); shift ;;
        --ignore-stale) IGNORE_STALE=1 ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
[ "$SEEN_TOPIC" -eq 1 ] || usage "--topic is required once"
[ "$SEEN_INTENT" -eq 1 ] || usage "--intent is required once"

[[ "$TOPIC" =~ $RE_TOPIC ]] || cannot_tell "topic [$TOPIC] does not match $RE_TOPIC"
case "$INTENT" in
    continue|stop) HAS_INTENT=1 ;;
    none) HAS_INTENT=0 ;;
    *) cannot_tell "intent [$INTENT] is not continue, stop or none" ;;
esac

STATE="wip/scope_${TOPIC}_state.md"
PLAN="docs/plans/PLAN-${TOPIC}.md"
DESIGN_CUR="docs/designs/current/DESIGN-${TOPIC}.md"
DESIGN="docs/designs/DESIGN-${TOPIC}.md"
PRD="docs/prds/PRD-${TOPIC}.md"
BRIEF="docs/briefs/BRIEF-${TOPIC}.md"
HANDOFF="wip/scope_${TOPIC}_handoff.md"

present() { [ -e "$1" ] || [ -L "$1" ]; }

# --- the state file ---------------------------------------------------------------

# sfield <name> -- the value of the one column-0 `<name>:` line. Prints
# nothing when the field is absent; returns 3 when it appears twice.
sfield() {
    awk -v k="$1" '
        index($0, k ":") == 1 {
            n++
            v = substr($0, length(k) + 2)
            sub(/[[:space:]]+#.*$/, "", v)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
        }
        END { if (n > 1) exit 3; if (n == 1) print v }
    ' "$STATE"
}

malformed() {
    printf '%s: state file %s is malformed: %s\n' "$PROG" "$STATE" "$1" >&2
    row 25 state-malformed
}

# epoch <iso-8601> -- seconds since the epoch, from YYYY-MM-DD with an
# optional THH:MM[:SS] and an optional Z or +HH:MM/-HH:MM. Empty on a value
# that is not one.
epoch() {
    printf '%s\n' "$1" | awk '
        {
            s = $0
            if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) exit
            y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
            if (m < 1 || m > 12 || d < 1 || d > 31) exit
            rest = substr(s, 11)
            hh = 0; mi = 0; ss = 0; off = 0
            if (rest != "") {
                if (rest !~ /^[T ][0-9][0-9]:[0-9][0-9]/) exit
                hh = substr(rest, 2, 2) + 0; mi = substr(rest, 5, 2) + 0
                rest = substr(rest, 7)
                if (rest ~ /^:[0-9][0-9]/) { ss = substr(rest, 2, 2) + 0; rest = substr(rest, 4) }
                sub(/^\.[0-9]+/, "", rest)
                if (rest == "Z" || rest == "") off = 0
                else if (rest ~ /^[+-][0-9][0-9]:?[0-9][0-9]$/) {
                    sign = (substr(rest, 1, 1) == "-") ? -1 : 1
                    gsub(/:/, "", rest)
                    off = sign * ((substr(rest, 2, 2) + 0) * 3600 + (substr(rest, 4, 2) + 0) * 60)
                } else exit
            }
            # days from civil (proleptic Gregorian)
            yy = (m <= 2) ? y - 1 : y
            era = int((yy >= 0 ? yy : yy - 399) / 400)
            yoe = yy - era * 400
            mp = (m + 9) % 12
            doy = int((153 * mp + 2) / 5) + d - 1
            doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
            days = era * 146097 + doe - 719468
            printf "%d\n", days * 86400 + hh * 3600 + mi * 60 + ss - off
        }'
}

probe_state() {
    [ -f "$STATE" ] && [ -r "$STATE" ] || malformed "it exists but is not a readable file"

    local f v exitv pointer updated intentv perr now then
    for f in topic phase_pointer last_updated exit intent publish_error boundary \
             decision_record_sub_shape triggering_child plan_execution_mode published_pr; do
        sfield "$f" >/dev/null || malformed "$f: appears more than once"
    done

    v=$(sfield topic)
    [ "$v" = "$TOPIC" ] || malformed "topic: is [$v], not $TOPIC"

    intentv=$(sfield intent)
    case "$intentv" in
        ''|continue|stop|none) ;;
        *) malformed "intent: [$intentv] is not continue, stop or none" ;;
    esac

    pointer=$(sfield phase_pointer)
    case "$pointer" in
        0|1|2|3|4) ;;
        '') malformed "phase_pointer: is missing" ;;
        *) malformed "phase_pointer: [$pointer] is not 0-4" ;;
    esac

    exitv=$(sfield exit)
    case "$exitv" in
        ''|null|'~') exitv="" ;;
        full-run)
            v=$(sfield plan_execution_mode)
            case "$v" in
                single-pr|multi-pr|coordinated) ;;
                *) malformed "exit: full-run without a plan_execution_mode: in {single-pr, multi-pr, coordinated}" ;;
            esac
            ;;
        re-evaluation)
            v=$(sfield boundary)
            case "$v" in prd|design) ;; *) malformed "exit: re-evaluation without boundary: prd or design" ;; esac
            v=$(sfield decision_record_sub_shape)
            case "$v" in re-evaluation|rejection) ;; *) malformed "exit: re-evaluation without decision_record_sub_shape:" ;; esac
            ;;
        abandonment-forced)
            v=$(sfield triggering_child)
            case "$v" in brief|prd|design|plan) ;; *) malformed "exit: abandonment-forced without triggering_child:" ;; esac
            ;;
        *) malformed "exit: [$exitv] is not full-run, re-evaluation or abandonment-forced" ;;
    esac

    perr=$(sfield publish_error)
    case "$perr" in
        ''|scope:push|scope:pr-create) ;;
        *) malformed "publish_error: [$perr] is not scope:push or scope:pr-create" ;;
    esac
    if [ -n "$perr" ] && [ -z "$exitv" ]; then
        malformed "publish_error: is recorded but exit: is not"
    fi
    v=$(sfield published_pr)
    if [ -n "$v" ] && ! [[ "$v" =~ $RE_PR_URL ]]; then
        malformed "published_pr: is not a pull request URL"
    fi
    v=$(sfield plan_execution_mode)
    case "$v" in
        ''|single-pr|multi-pr|coordinated) ;;
        *) malformed "plan_execution_mode: [$v] is not single-pr, multi-pr or coordinated" ;;
    esac

    if [ -n "$exitv" ]; then
        if [ -n "$perr" ] && [ "$HAS_INTENT" -eq 1 ]; then
            case "$exitv" in
                full-run) row 27 publish-retry-full-run ;;
                re-evaluation) row 28 publish-retry-re-evaluation ;;
                abandonment-forced) row 29 publish-retry-abandonment ;;
            esac
        fi
        row 26 exit-set
    fi

    [ "$pointer" != 4 ] || malformed "phase_pointer: 4 without an exit:"

    if [ "$IGNORE_STALE" -eq 0 ]; then
        updated=$(sfield last_updated)
        [ -n "$updated" ] || malformed "last_updated: is missing"
        then=$(epoch "$updated")
        [ -n "$then" ] || malformed "last_updated: [$updated] is not an ISO-8601 timestamp"
        now="${SCOPE_PROBE_NOW:-$(date -u +%s)}"
        case "$now" in ''|*[!0-9]*) cannot_tell "the clock could not be read" ;; esac
        if [ $((now - then)) -ge "$STALE_SECS" ]; then
            row 24 state-stale
        fi
    fi

    case "$pointer" in
        0|1) row 20 fresh-phase-1 ;;
        2) row 21 fresh-phase-2 ;;
        3) row 22 fresh-phase-3 ;;
    esac
}

if present "$STATE"; then
    probe_state
fi

# --- Slot 5: the artifact tree ------------------------------------------------------

# status_of <path> -- the frontmatter `status:` value. Returns 1 when the file
# has no readable frontmatter status.
status_of() {
    [ -f "$1" ] && [ -r "$1" ] || return 1
    local s
    s=$(awk '
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; inside = 1; next }
        inside && /^---[[:space:]]*$/ { exit }
        inside && /^status:/ {
            v = substr($0, 8)
            sub(/[[:space:]]+#.*$/, "", v)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
            print v; exit
        }
    ' "$1")
    [ -n "$s" ] || return 1
    printf '%s' "$s"
}

need_status() { # need_status <path> -- sets S to the status, or reports cannot-tell
    S=$(status_of "$1") || cannot_tell "$1 exists but its frontmatter status: cannot be read"
}

if present "$PLAN"; then
    need_status "$PLAN"
    case "$S" in
        Done) row 42 plan-done ;;
        Active)
            [ "$HAS_INTENT" -eq 1 ] && row 40 plan-republish
            row 41 plan-active
            ;;
        Draft)
            [ "$HAS_INTENT" -eq 1 ] && row 40 plan-republish
            row 43 plan-draft
            ;;
    esac
fi

if ! present "$PLAN" && present "$DESIGN_CUR" && [ "$HAS_INTENT" -eq 1 ]; then
    row 44 executed
fi

for d in "$DESIGN_CUR" "$DESIGN"; do
    present "$d" || continue
    need_status "$d"
    case "$S" in
        Accepted|Planned|Current) row 45 design-boundary ;;
        Proposed) row 46 design-draft ;;
    esac
done

if present "$PRD"; then
    need_status "$PRD"
    case "$S" in
        Accepted|"In Progress"|Done) row 47 prd-boundary ;;
        Draft) row 48 prd-draft ;;
    esac
fi

if present "$BRIEF"; then
    need_status "$BRIEF"
    case "$S" in
        Accepted|Done) row 49 brief-accepted ;;
        Draft) row 50 brief-draft ;;
    esac
fi

# --- Slot 6: a child partial -------------------------------------------------------------

has_prefix() { # has_prefix <glob-prefix> -- any wip/ entry starting with it
    local p
    for p in "$1"*; do
        present "$p" && return 0
    done
    return 1
}

has_prefix "wip/plan_${TOPIC}_" && row 60 plan-partial
present "wip/design_${TOPIC}_coordination.json" && row 61 design-partial
present "wip/prd_${TOPIC}_decisions.md" && row 62 prd-partial
has_prefix "wip/brief_${TOPIC}_" && row 63 brief-partial

# --- Slot 7 and the tail ------------------------------------------------------------------

present "$HANDOFF" && row 12 explore-handoff

BRANCH=$(git symbolic-ref --quiet --short HEAD) || BRANCH=""
if [ -z "$BRANCH" ]; then
    git rev-parse --git-dir >/dev/null || cannot_tell "not inside a git repository"
fi
case "$BRANCH" in
    *"$TOPIC"*) row 11 topic-branch ;;
esac
row 10 fresh-start
