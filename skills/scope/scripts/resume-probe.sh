#!/usr/bin/env bash
# resume-probe.sh -- /scope's resume ladder as one read-only probe.
#
# `resume_route` in skills/scope/koto-templates/scope.md runs this as its one
# gate and sends each exit code to a state. The ladder used to run as agent
# prose; the rows, their order and their prompts are specified in
# skills/scope/references/phases/phase-resume.md, which stays the normative
# spec and names this probe's exit code on every row.
#
# It reads the artifact tree, the run's state (key work/state.md of session
# scope-<topic>) and, after a replace, the finished run's facts (key
# work/prior-run.md of the same session), the four children's koto sessions
# (through scripts/skill-session.sh has-work, which only reads), the /explore
# handoff (key handoff/scope.md of session explore-<topic>), and the current
# branch name. It writes nothing but a private temp directory, removed on
# exit, it ticks no session, and it makes no gh call and no network call.
#
# The seven koto lookups those reads start with (the two state keys, the four
# children's has-work and the handoff key) don't depend on each other, so they
# start together, as background jobs, and each writes its reply, its exit code
# and then a marker file into the temp directory. Under the cloud backend a
# lookup can cost koto seconds, and the gate gives the probe 30 s, so the
# probe keeps its own deadline of 20 s over every koto call it makes,
# including the `context get` reads of a key that exists, which start as jobs
# of the same kind once the ladder needs them.
#
# The probe doesn't wait for every answer. A poll loop walks the ladder in its
# own order on whatever has answered: a row whose inputs are settled answers
# at once, with later lookups still out, so a resumed topic is never held by
# the names it never opened. Walking in order keeps the row the one a probe
# running the lookups in turn would give: a lookup past the row that matches
# is ignored, whatever it answered. The first input the walk needs that koto
# can't tell about gives 2, and the first one koto refused gives 3. When the
# deadline passes first, the probe gives 3 for the lookups still out. Either
# way, every job still running is then killed with its descendants, by the
# process ids the probe started, never by name. RUN_INTENT arrives as an
# argument, because the intent shortcuts (rows 40 and 44) exist only on intent
# runs and a plan-active topic (row 41) is refused only without one.
#
# Rows, first match wins (the ladder's order, most-downstream first):
#
#   key work/state.md present in scope-<topic> (meta-ladder rows 1-4)
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
#   no work/state.md, but key work/prior-run.md holds a failed publish step
#   (step scope:push or scope:pr-create, exit full-run, re-evaluation or
#   abandonment-forced) and intent is set: the publish retry of a finished
#   run that scope-open.sh replaced. Any other content, or a key whose values
#   fail their closed sets, is no match and the ladder falls through.
#     27  exit full-run
#     28  exit re-evaluation
#     29  exit abandonment-forced
#   neither key: Slot 5, the artifact tree
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
#   Slot 6, a child partial: the child's session <child>-<topic> is live,
#   belongs to this branch and holds a key under work/ (`skill-session.sh
#   has-work <child> <topic>`)
#     60  plan-<topic>
#     61  design-<topic>
#     62  prd-<topic>
#     63  brief-<topic>
#   Slot 7, and the meta-ladder tail
#     12  key handoff/scope.md in session explore-<topic> (live or finished;
#         an absent session is no match)
#     11  nothing on disk, on a branch whose name contains the topic
#     10  nothing on disk, any other branch
#
#   2   cannot tell: an invalid topic or intent, an artifact whose status
#       cannot be read, a git read that failed, a key lookup koto answered
#       outside the reply table below, a child session whose state koto could
#       not report (has-work exit 4), or a temp directory that could not be
#       made. A retry won't change it; the run ends at done_error.
#   3   unsettled: a lookup the ladder needs was refused by koto, or was still
#       out at the deadline. No state routes it, so the run holds at
#       resume_route, and the finding lines below are on the gate's blocking
#       condition. A refusal or a lookup killed at the deadline is never read
#       as absent.
#   64  usage error
#
# The reply table. `koto context exists`: 0 present; 1 absent; 127 (koto
# absent from PATH: no session can exist) absent; exit 2, or exit 3 with code
# session_lookup_failed, refused; anything else cannot tell. has-work: 0 a
# partial; 1 or 127 none; 7 refused (koto refused the child's status or
# session/branch read); anything else, 4 among them, cannot tell.
#
# A status outside the sets above (a Superseded DESIGN, say) is not a row of
# its own; the ladder falls through to the rows below it.
#
# stdout carries one line naming the row, `row=<code> <name>`, for a person
# reading a gate's blocking conditions; koto routes on the exit code alone.
# Before row=3 unsettled it carries one finding line per lookup koto refused or
# that was still out at the deadline, from the one the walk stopped at on, in
# ladder order:
#
#   ::koto-finding:: lookup=<session>[ <key>] outcome=<deadline|refused> next=<tick-again|stop-and-act>[ remedy=declare-the-bucket-name-index] koto=<text>
#
# next=stop-and-act, with the remedy field, is for a lookup killed at the
# deadline and for a refusal saying this directory's prefix answered empty and
# koto can't tell whether another directory's prefix holds the session;
# declaring the bucket's name index is what lets koto look past it. Every
# other refusal is next=tick-again. koto= is always the last field: a deadline
# line's is `none before the deadline`, and a refusal's is koto's code and the
# first line of its message, reduced to letters, digits, space and ._:/'()-,
# any URL cut to scheme, host and path, at most 300 characters.
#
# Usage:
#   resume-probe.sh --topic <slug> --intent <continue|stop|none> [--ignore-stale]
#                   [--local-topic <stated|unstated>]
#
# --local-topic carries the operator's word that the topic has no session
# held elsewhere (stated) or not (unstated, the same as leaving it out). It is
# parsed and checked here, and nothing reads it yet.
#
# The working directory is the repository being scoped. Two variables replace
# a fixed value, for tests only, and no gate passes either: SCOPE_PROBE_NOW, an
# epoch second count, replaces the clock for the staleness test, and
# SCOPE_PROBE_DEADLINE, a whole number of seconds from 1 to 20, replaces the
# 20 s deadline (any other value reads as 20, so the deadline always beats the
# gate's 30 s). KOTO_BIN and KOTO_SESSIONS_BASE reach skill-session.sh
# unchanged, and KOTO_BIN names the koto the state, prior-run and handoff
# reads use. With koto absent no session can exist, so those reads match
# nothing.
#
# The probe's temp directory goes under TMPDIR (default /tmp).
#
# Requires: bash 3.2+, git, awk, sed, tr, mktemp, pgrep; koto for the key
# reads and Slot 6.
set -uo pipefail

PROG=resume-probe

HERE=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
SKILL_SESSION="$HERE/../../../scripts/skill-session.sh"
BASH_BIN="${BASH:-bash}"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
STALE_SECS=$((7 * 24 * 3600))

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: resume-probe.sh --topic <slug> --intent <continue|stop|none> [--ignore-stale] [--local-topic <stated|unstated>]\n' >&2
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

# Every argument is checked here, before any koto call. --local-topic takes
# its value as the next argument only: the equals form is an unknown argument.
TOPIC=""; INTENT=""; IGNORE_STALE=0; LOCAL_TOPIC=unstated
SEEN_TOPIC=0; SEEN_INTENT=0; SEEN_LOCAL=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --topic)  [ "$#" -ge 2 ] || usage "--topic needs a value"; TOPIC="$2"; SEEN_TOPIC=$((SEEN_TOPIC + 1)); shift ;;
        --intent) [ "$#" -ge 2 ] || usage "--intent needs a value"; INTENT="$2"; SEEN_INTENT=$((SEEN_INTENT + 1)); shift ;;
        --ignore-stale) IGNORE_STALE=1 ;;
        --local-topic)
            [ "$#" -ge 2 ] || usage "--local-topic needs a value"
            case "$2" in
                stated|unstated) LOCAL_TOPIC="$2" ;;
                *) usage "--local-topic is stated or unstated, not [$2]" ;;
            esac
            SEEN_LOCAL=$((SEEN_LOCAL + 1)); shift
            ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done
[ "$SEEN_TOPIC" -eq 1 ] || usage "--topic is required once"
[ "$SEEN_INTENT" -eq 1 ] || usage "--intent is required once"
[ "$SEEN_LOCAL" -le 1 ] || usage "--local-topic is accepted once"
: "$LOCAL_TOPIC"

[[ "$TOPIC" =~ $RE_TOPIC ]] || cannot_tell "topic [$TOPIC] does not match $RE_TOPIC"
case "$INTENT" in
    continue|stop) HAS_INTENT=1 ;;
    none) HAS_INTENT=0 ;;
    *) cannot_tell "intent [$INTENT] is not continue, stop or none" ;;
esac

# The deadline, in whole seconds from the first lookup. SCOPE_PROBE_DEADLINE
# is honoured only from 1 to 20, so no value can push the probe past the
# gate's 30 s.
case "${SCOPE_PROBE_DEADLINE-}" in
    [1-9]|1[0-9]|20) DEADLINE="$SCOPE_PROBE_DEADLINE" ;;
    *) DEADLINE=20 ;;
esac

SESSION="scope-${TOPIC}"
STATE="work/state.md"
PRIOR="work/prior-run.md"
KOTO="${KOTO_BIN:-koto}"
PLAN="docs/plans/PLAN-${TOPIC}.md"
DESIGN_CUR="docs/designs/current/DESIGN-${TOPIC}.md"
DESIGN="docs/designs/DESIGN-${TOPIC}.md"
PRD="docs/prds/PRD-${TOPIC}.md"
BRIEF="docs/briefs/BRIEF-${TOPIC}.md"
HANDOFF_SESSION="explore-${TOPIC}"
HANDOFF="handoff/scope.md"

present() { [ -e "$1" ] || [ -L "$1" ]; }

# Without skill-session.sh Slot 6 cannot be told; the ladder says so there.
HAVE_SKILL_SESSION=0
[ -f "$SKILL_SESSION" ] && HAVE_SKILL_SESSION=1

# --- the lookups, run as jobs under one deadline -----------------------------------

LOOKUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/resume-probe.XXXXXX") ||
    cannot_tell "could not make a temp directory for the koto lookups"
# JOBS lists every job started, as <name>:<pid>. A job that finished has
# written <name>.done in LOOKUP_DIR, after its <name>.rc.
JOBS=""

# job_pid <name> -- print the job's pid; returns 1 when it was never started.
job_pid() {
    local j
    for j in $JOBS; do
        case "$j" in "$1":*) printf '%s' "${j#*:}"; return 0 ;; esac
    done
    return 1
}

# start_job <name> <cmd> [<arg>...] -- run the command in the background,
# keeping its stdout, stderr and exit code in LOOKUP_DIR, then the marker. The
# wrapper's own stderr is discarded, so a killed job prints no notice on the
# probe's.
start_job() {
    local n="$1"
    shift
    (
        "$@" >"$LOOKUP_DIR/$n.out" 2>"$LOOKUP_DIR/$n.err" </dev/null
        printf '%s\n' "$?" >"$LOOKUP_DIR/$n.rc"
        : >"$LOOKUP_DIR/$n.done"
    ) 2>/dev/null &
    JOBS="$JOBS $n:$!"
}

done_job() { [ -e "$LOOKUP_DIR/$1.done" ]; }

# rc_job <name> -- set RC to a finished job's exit code.
rc_job() {
    RC=$(cat "$LOOKUP_DIR/$1.rc" 2>/dev/null) || RC=""
    case "$RC" in ''|*[!0-9]*) RC=255 ;; esac
}

# descendants <pid> -- every process below <pid>, children after their own
# descendants, found by parent id only.
descendants() {
    local c
    for c in $(pgrep -P "$1" 2>/dev/null); do
        descendants "$c"
        printf '%s\n' "$c"
    done
}

# kill_jobs -- signal every job that has written no marker, and its
# descendants, by id. The tree is read before the first signal, then
# signalled leaves first and the job last. has-work runs koto two levels down
# (the wrapper, skill-session.sh's bash, koto), so signalling the job alone
# would leave koto running.
kill_jobs() {
    local j n p tree
    for j in $JOBS; do
        n="${j%%:*}"; p="${j#*:}"
        done_job "$n" && continue
        tree=$(descendants "$p")
        [ -z "$tree" ] || kill $tree 2>/dev/null
        kill "$p" 2>/dev/null
        wait "$p" 2>/dev/null
    done
}

cleanup() {
    kill_jobs
    rm -rf "$LOOKUP_DIR"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# --- reading koto's replies ------------------------------------------------------------

# json_field <field> <file> -- the string value of <field> in the last line of
# <file> that carries one, its JSON escapes left as they are. Prints nothing
# when no line does. Read with sed, so the probe needs no JSON tool; a reply
# it can't parse has no code, which reads as cannot-tell, never as absent.
json_field() {
    sed -n -E 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' "$2" 2>/dev/null | tail -n 1
}

# The phrase koto v0.37.1 uses when this directory's prefix answered empty and
# the other prefixes went unchecked: declaring the bucket's name index is what
# lets koto look past it, so the finding says to stop and act, not to retry.
OWN_PREFIX_EMPTY="holds none under this directory's prefix"
OTHER_PREFIX_UNCHECKED="can't tell whether another directory's prefix holds it"

# CLS is what a lookup answered: pending (still out), present, absent,
# refused, or cannot (cannot tell).
CLS=""

# key_exists <job> -- classify `koto context exists` by the reply table:
# 0 present; 1, or 127 (koto absent: no session can exist), absent; exit 2, or
# exit 3 with code session_lookup_failed, refused; anything else cannot tell.
key_exists() {
    done_job "$1" || { CLS=pending; return; }
    rc_job "$1"
    case "$RC" in
        0) CLS=present ;;
        1|127) CLS=absent ;;
        2) CLS=refused ;;
        3) if [ "$(json_field code "$LOOKUP_DIR/$1.out")" = session_lookup_failed ]; then CLS=refused; else CLS=cannot; fi ;;
        *) CLS=cannot ;;
    esac
}

# child_partial <job> -- classify `skill-session.sh has-work`: 0 a partial
# (the child's session is live on this branch and holds a work/ key); 1, or
# 127, none; 7 koto refused the read; anything else (4) cannot tell. Only the
# child writes work/ keys in its own session, so a match always means the
# child itself ran; no feeder document can imitate one.
child_partial() {
    done_job "$1" || { CLS=pending; return; }
    rc_job "$1"
    case "$RC" in
        0) CLS=present ;;
        1|127) CLS=absent ;;
        7) CLS=refused ;;
        *) CLS=cannot ;;
    esac
}

# --- finding lines -----------------------------------------------------------------------

# reduce_koto <job> -- the koto= value for a refused lookup: koto's code, then
# the first line of its message, any URL cut to scheme, host and path, every
# character outside letters, digits, space and ._:/'()- dropped, runs of : made
# one (so no ::koto-finding:: survives inside it), at most 300 characters. The
# text is koto's, and it lands on the gate's blocking condition, so it is
# reduced by allowlist rather than escaped.
reduce_koto() {
    local f="$LOOKUP_DIR/$1.out" code msg v
    code=$(json_field code "$f")
    msg=$(json_field error "$f")
    [ -n "$msg" ] || msg=$(head -n 1 "$f" 2>/dev/null)
    msg="${msg%%\\n*}"
    v=$(printf '%s %s\n' "$code" "$msg" | head -n 1 |
        sed -E 's#([A-Za-z][A-Za-z0-9+.-]*://)([^/@[:space:]]*@)?([^/?#[:space:]]*)([^?#[:space:]]*)[^[:space:]]*#\1\3\4#g' |
        LC_ALL=C tr -cd "A-Za-z0-9 ._:/'()-" |
        sed -E 's/:{2,}/:/g; s/^ +//; s/ +$//')
    v="${v:0:300}"
    v="${v% }"
    if [ -z "$v" ]; then
        rc_job "$1"
        v="exit $RC with no reply"
    fi
    printf '%s' "$v"
}

# finding <lookup> <outcome> <next> <koto> -- one ::koto-finding:: line. A
# stop-and-act line names its remedy, declaring the bucket's name index,
# before koto=, which is always the last field.
finding() {
    local remedy=""
    [ "$3" = stop-and-act ] && remedy=" remedy=declare-the-bucket-name-index"
    printf '::koto-finding:: lookup=%s outcome=%s next=%s%s koto=%s\n' "$1" "$2" "$3" "$remedy" "$4"
}

# advice <job> -- stop-and-act when koto's refusal says this directory's
# prefix answered empty and the others went unchecked; tick-again otherwise.
advice() {
    local out
    out=$(cat "$LOOKUP_DIR/$1.out" 2>/dev/null)
    case "$out" in
        *"$OWN_PREFIX_EMPTY"*"$OTHER_PREFIX_UNCHECKED"*) printf 'stop-and-act' ;;
        *) printf 'tick-again' ;;
    esac
}

# --- the unsettled answer ----------------------------------------------------------------

# The lookups in the order the ladder reads them. st and pr are the two
# `context exists` reads of scope-<topic>, stg and prg their `context get`
# reads (started only once the key is present), then the four children's
# has-work, then the handoff.
LADDER="st stg pr prg plan design prd brief ho"
# POS is the lookup the walk stopped at: the one still out, or the first
# refused one it met.
POS=st

# label_of <job> -- the lookup= value: <session>, or <session> <key>.
label_of() {
    case "$1" in
        st|stg) printf '%s %s' "$SESSION" "$STATE" ;;
        pr|prg) printf '%s %s' "$SESSION" "$PRIOR" ;;
        ho) printf '%s %s' "$HANDOFF_SESSION" "$HANDOFF" ;;
        *) printf '%s-%s' "$1" "$TOPIC" ;;
    esac
}

# is_refused <job> -- the job finished and koto refused it.
is_refused() {
    case "$1" in
        st|pr|ho) key_exists "$1" ;;
        plan|design|prd|brief) child_partial "$1" ;;
        *) return 1 ;;
    esac
    [ "$CLS" = refused ]
}

# unsettled <deadline|refused> -- exit 3. Prints one finding line for each
# lookup from POS on, in ladder order, that koto refused, and, at the
# deadline, for each one still out; then row=3 unsettled. Once the state key
# is present nothing past its get can decide the row, so the list stops
# there. The lines are built before any job is signalled, so a job that
# writes its marker while it dies is not counted twice. Exit 3 has no route:
# the run holds at resume_route with these lines on the gate's blocking
# condition.
unsettled() {
    local j list="" seen=0 lines=""
    for j in $LADDER; do
        [ "$j" = "$POS" ] && seen=1
        [ "$seen" -eq 1 ] || continue
        job_pid "$j" >/dev/null || continue
        if ! done_job "$j"; then
            [ "$1" = deadline ] || continue
            lines="$lines$(finding "$(label_of "$j")" deadline stop-and-act "none before the deadline")
"
        elif is_refused "$j"; then
            lines="$lines$(finding "$(label_of "$j")" refused "$(advice "$j")" "$(reduce_koto "$j")")
"
        fi
        [ "$j" = stg ] && break
    done
    printf '%s' "$lines"
    row 3 unsettled
}

# --- the state key ----------------------------------------------------------------

# DOC holds the key's text, which the walk's read_key sets; sfield reads it.
DOC=""

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
    ' <<EOF_DOC
$DOC
EOF_DOC
}

malformed() {
    printf '%s: key %s of session %s is malformed: %s\n' "$PROG" "$STATE" "$SESSION" "$1" >&2
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
    # DOC holds the key's bytes: the walk read them before calling this.

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
            case "$v" in brief|prd|design) ;; *) malformed "exit: re-evaluation without boundary: brief, prd or design" ;; esac
            v=$(sfield decision_record_sub_shape)
            case "$v" in re-evaluation|rejection) ;; *) malformed "exit: re-evaluation without decision_record_sub_shape:" ;; esac
            # Nothing above a BRIEF can be re-evaluated: its boundary is a rejection only.
            [ "$(sfield boundary)" = brief ] && [ "$v" != rejection ] \
                && malformed "exit: re-evaluation at boundary: brief must be decision_record_sub_shape: rejection"
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

# --- the finished run's publish failure ---------------------------------------------

# probe_prior -- key work/prior-run.md, written by scope-open.sh from the
# replaced session's result. Every value must match its closed set; a key
# that does not is no match.
probe_prior() {
    # DOC holds the key's bytes: the walk read them before calling this.
    local f perr exitv intentv outc
    for f in outcome exit intent step; do
        sfield "$f" >/dev/null || return 0
    done
    perr=$(sfield step)
    case "$perr" in scope:push|scope:pr-create) ;; *) return 0 ;; esac
    exitv=$(sfield exit)
    intentv=$(sfield intent)
    case "$intentv" in ''|continue|stop|none) ;; *) return 0 ;; esac
    outc=$(sfield outcome)
    [[ "$outc" =~ ^[a-z][a-z-]*$ ]] || [ -z "$outc" ] || return 0
    [ "$HAS_INTENT" -eq 1 ] || return 0
    case "$exitv" in
        full-run) row 27 publish-retry-full-run ;;
        re-evaluation) row 28 publish-retry-re-evaluation ;;
        abandonment-forced) row 29 publish-retry-abandonment ;;
    esac
    return 0
}

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
# slot5 -- the artifact rows. Plain file reads, so the walk runs them again
# on every pass until a lookup ahead of Slot 6 is still out.
slot5() {
    local d
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
}

# --- Slot 7's tail ---------------------------------------------------------------------

tail_rows() {
    BRANCH=$(git symbolic-ref --quiet --short HEAD) || BRANCH=""
    if [ -z "$BRANCH" ]; then
        git rev-parse --git-dir >/dev/null || cannot_tell "not inside a git repository"
    fi
    case "$BRANCH" in
        *"$TOPIC"*) row 11 topic-branch ;;
    esac
    row 10 fresh-start
}

# --- the walk ---------------------------------------------------------------------------

# need <job> -- the walk's read of one lookup. Returns 1 while it is still out
# (POS names it). A refused lookup ends the probe unsettled and a cannot-tell
# one ends it at 2, each where the ladder first needs it. Otherwise CLS is
# present or absent.
need() {
    POS="$1"
    case "$1" in
        st|pr|ho) key_exists "$1" ;;
        *) child_partial "$1" ;;
    esac
    case "$CLS" in
        pending) return 1 ;;
        refused) unsettled refused ;;
        cannot)
            rc_job "$1"
            case "$1" in
                st) cannot_tell "koto context exists $SESSION $STATE exited $RC" ;;
                pr) cannot_tell "koto context exists $SESSION $PRIOR exited $RC" ;;
                ho) cannot_tell "koto context exists $HANDOFF_SESSION $HANDOFF exited $RC" ;;
                *) cannot_tell "skill-session.sh has-work $1 $TOPIC exited $RC: $(cat "$LOOKUP_DIR/$1.err" 2>/dev/null)" ;;
            esac
            ;;
    esac
    return 0
}

# read_key <job> <session> <key> -- start the key's `context get` as a job the
# first time the walk needs it. Returns 2 while it is still out (POS names
# it), 1 when koto could not return the bytes, 0 with DOC set to them.
read_key() {
    POS="$1"
    job_pid "$1" >/dev/null || start_job "$1" "$KOTO" context get "$2" "$3"
    done_job "$1" || return 2
    rc_job "$1"
    [ "$RC" -eq 0 ] || return 1
    DOC=$(cat "$LOOKUP_DIR/$1.out"; printf '.')
    DOC="${DOC%.}"
    return 0
}

# walk -- the ladder, top to bottom, on what has answered so far. It exits
# with the row as soon as the inputs that row needs are settled, even with
# later lookups still out. Returns 1 when it reaches a lookup still out.
walk() {
    local rc
    need st || return 1
    if [ "$CLS" = present ]; then
        rc=0; read_key stg "$SESSION" "$STATE" || rc=$?
        case "$rc" in
            2) return 1 ;;
            1) malformed "it exists but koto cannot read it" ;;
        esac
        probe_state
    fi

    need pr || return 1
    if [ "$CLS" = present ]; then
        rc=0; read_key prg "$SESSION" "$PRIOR" || rc=$?
        case "$rc" in
            2) return 1 ;;
            0) probe_prior ;;
        esac
    fi

    slot5

    [ "$HAVE_SKILL_SESSION" -eq 1 ] || cannot_tell "scripts/skill-session.sh not found at $SKILL_SESSION"
    need plan || return 1;   [ "$CLS" = present ] && row 60 plan-partial
    need design || return 1; [ "$CLS" = present ] && row 61 design-partial
    need prd || return 1;    [ "$CLS" = present ] && row 62 prd-partial
    need brief || return 1;  [ "$CLS" = present ] && row 63 brief-partial

    need ho || return 1
    [ "$CLS" = present ] && row 12 explore-handoff

    tail_rows
}

# --- the poll loop -------------------------------------------------------------------------

START=$SECONDS
start_job st "$KOTO" context exists "$SESSION" "$STATE"
start_job pr "$KOTO" context exists "$SESSION" "$PRIOR"
if [ "$HAVE_SKILL_SESSION" -eq 1 ]; then
    for c in plan design prd brief; do
        start_job "$c" "$BASH_BIN" "$SKILL_SESSION" has-work "$c" "$TOPIC"
    done
fi
start_job ho "$KOTO" context exists "$HANDOFF_SESSION" "$HANDOFF"

while :; do
    walk
    [ $((SECONDS - START)) -lt "$DEADLINE" ] || unsettled deadline
    sleep 0.1
done
