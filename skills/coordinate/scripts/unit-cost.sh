#!/usr/bin/env bash
# unit-cost.sh -- one torn-down unit's cost, as a `unit-cost/1` entry on the
# coordinator's record.
#
# The teardown pass (teardown-pass.sh run) calls `capture` once the archive,
# its MANIFEST and its README are written and before it destroys anything,
# under its own deadline, with this script's streams going nowhere the pass
# reads and its status ignored. So nothing here can change the pass: a
# failure costs the unit its entry, never the teardown its outcome.
#
# Usage:
#   unit-cost.sh compute --archive DIR --topic T --prs-file F [--unit-json J]
#       Prints the unit's `unit-cost/1` object, compact, on stdout. DIR is the
#       teardown archive (its name is the capture key, `<UTC date>-<T>-<job
#       id>`); F holds the sealed verdict's `owner/repo#n <merge sha>` lines;
#       J holds the record's facts, {scope, name, repo, unit}, or
#       {unit_reason} when they couldn't be read. Without J the record is
#       null and the milestone `not recoverable`.
#   unit-cost.sh capture --session S --archive DIR --topic T --prs-file F
#       Reads the run's record facts (coord-log.sh run-facts) and the
#       Holdings row whose Worker is T (record-holding.sh --read), computes
#       the object, writes it to DIR/unit-cost.json through a temporary name
#       in DIR (a symlink at that name is replaced, never written through),
#       lists the record's entries (record-append.sh --list) and posts one
#       entry of kind `cost` unless a `cost` entry's JSON already carries the
#       same key. A list that fails posts anyway: readers keep the latest
#       entry per key, so a duplicate is harmless and a skipped post loses
#       the unit. An object over 50,000 bytes is posted without the
#       per-session `states` maps (`sessions.states`, `entry size`);
#       unit-cost.json keeps them. It posts it with record-append.sh --on on
#       the item it is about: the
#       holding's pull request (the row's Pull request cell, else the sealed
#       verdict's first), else the Unit's issue (`#n` on the host or
#       `owner/repo#n`), else `--on none`, which keeps it in the session,
#       posted nowhere; the last stderr line says which.
#   unit-cost.sh gh-check <gh arguments...>
#       Runs nothing: 0 when the capture's GitHub wrapper would make that
#       call, 1 when it refuses it. The suite's view of the wrapper.
#
# The object holds, in this order: schema, key, captured_at, topic, record,
# unit, milestone, plan_shape, pulls, dispatch, "niwa.dispatch.id", figures,
# sessions, tokens, complete and missing. A figure is {value, raw, state, source}; state is
# `measured`, `bound`, `not recoverable` or `not applicable`, and every figure
# not taken is listed in `missing` with a reason from a closed list: `no
# source`, `read failed`, `time limit`, `entry size`, `invalid input`.
# references/unit-cost.md has the definitions; each figure is computed the
# way the baseline derivation those definitions come from computes it.
#
# Plan shape, first match wins, over the archived sessions in byte order of
# their names: a `deliver` session's context key plan_execution_mode; an
# `execute` session's template file (execute-coordinated.md is coordinated,
# execute.md single-pr); a `work-on` session's entry `mode` (plan_backed is
# multi-pr, issue_backed and free_form are issue); else none. A session that
# matches but whose value can't be read, or a session whose header can't be
# read (it may be any of them), makes the shape `not recoverable`.
#
# Milestone: the Unit cell cut at its first `: `. An issue reference (`#n`,
# `owner/repo#n`) or a discipline record gives `none`; a roadmap record gives
# {roadmap: ROADMAP-<name>, tag}. A Unit outside the safety pattern is null,
# its milestone `not recoverable` (`invalid input`).
#
# The archive's transcripts: claude-projects/<project directory>/, every
# Claude Code project directory of the instance (teardown-pass.sh). A main
# session transcript is a `<session id>.jsonl` directly in one of them. The
# worker's session id is job/state.json's sessionId, else teardown.json's
# job.session. One scan reads every .jsonl there, the worker's files first:
# its main transcript and every .jsonl under <session id>/subagents/, in
# every directory. An archive made before that layout holds transcript/
# instead, read as before for the worker; its nested row is `not
# recoverable` (`no source`) and it gives dispatch and credit nothing.
#
# Dispatch: the earliest of three. The created_at of the unit's koto
# request, found through the archived sessions' request-leg.toml files (of
# the requests they name, those whose requested_by is one of the archived
# sessions, a /deliver asking its /scope, say, are the unit's own nested
# requests; the earliest of the rest is the coordinator's); the job's
# createdAt; and each main session transcript's first event (its earliest
# `timestamp`). The request wins a tie; source is `koto-request` when it is
# the earliest, else `job-state`. dispatch.jobs counts the main session
# transcripts read. With none of them, `not recoverable`. A request id
# outside koto's grammar makes it `not recoverable` (`invalid input`): the
# request it names can't be read.
#
# Credit: `pulls` holds the holding's merged pull requests (the sealed
# verdict's, `via: holding`), then each pull request a `pr-link` record in
# claude-projects/ names that GitHub reads, at capture, as: in a repository
# whose owner is the holding's (case-insensitive); not from a fork (its head
# repository's owner is the same); created at or after dispatch and merged;
# and either on a head branch (not its base) that is some line's gitBranch,
# or linked within 120 seconds of its creation, either way, inclusive
# (`via: session`), by merge time then number. A link's repository, number
# and the gitBranch values are matched to their patterns before any use. At
# most 200 candidates are read, one `gh pr view` each out of the read
# budget, and `pulls` holds at most 100. The first reason a pull request was
# left out is one `pulls` entry in `missing`: `no source` (dispatch not
# recoverable), `read failed`, `time limit` or `entry size`. Credit never
# changes a figure: green, merge and failing heads read the holding's only.
#
# niwa's dispatch id: teardown.json's niwa.dispatch_id, written by the pass,
# as the top-level "niwa.dispatch.id"; else null, `missing` naming it with
# the file's reason (`no source`, `invalid input`), `no source` without the
# file.
#
# Time: per session, a state lasts from the transitioned or rewound event that
# entered it to the next one, up to the first entry into done (else the last
# event). `states` and `span_s` are those seconds to the millisecond, so a
# session's states sum to its span; the figures take the unrounded seconds.
# Unit sessions are the work-on ones. GitHub, per pull request: its heads in
# commit order, every workflow run on its head branch for those heads, and
# every earlier attempt of each. Green is the first head whose runs' final
# attempts all concluded success or skipped, at the latest of their finish
# times; a head whose final attempts have not all concluded, none failing,
# makes green `bound` at the latest finish so far, and the figures computed
# from green bound with it.
#
# Tokens: per message id (assistant lines with a string id and a usage
# object; a line without one is not counted at all), the largest value of
# each class, summed. `worker` is the worker's session, as above; `nested` is
# every other .jsonl in claude-projects/. A message id counts once across the
# archive: one the worker row holds is never counted in `nested`. A line that
# isn't JSON makes its row `not recoverable` (`invalid input`).
#
# Public hosts: when the record's repository is public (or its visibility
# can't be read), every pull request whose repository isn't read as public,
# credited ones included, is written as {repo: "not public"} and nothing
# else, and an `owner/repo#n` Unit naming one as "not public". A failed
# lookup counts as not public.
#
# Untrusted input: the archive and GitHub fields are read only through jq
# filters that keep numbers, ids, timestamps and closed-set words; every kept
# string is matched to its shape first. Only regular files are read; a
# symlink anywhere in the archive is skipped. Diagnostics are fixed strings.
#
# Every external command (each GitHub read, the record scripts, the post)
# runs under dc_with_deadline in its own process group, which the deadline
# stops whole, so no grandchild outlives this script. The reads share a
# budget; once it is spent, what is not yet taken is `time limit` and the
# capture goes straight to writing and posting what it has.
#
# Exit codes: 0 printed (compute), posted, kept in the session (a unit with
# no pull request or issue) or already posted (capture), or
# admitted (gh-check); 1 not posted, or refused (gh-check); 64 usage; 65 the
# archive's name is not a capture key for the topic.
#
# Environment: GH names gh (tests); KOTO_REQUESTS (default
# $HOME/.koto/requests); UNIT_COST_FETCH_SECS (each GitHub read's bound,
# default 8, the pass's own); UNIT_COST_BUDGET_SECS (the reads' budget,
# default 90); UNIT_COST_LIST_SECS (the entry list's bound, default 15);
# UNIT_COST_POST_SECS (the post's bound, default 25); UNIT_COST_NOW (a fixed
# captured_at, tests); DC_COORD_LOG and DC_RECORD_HOLDING (dispatch-common.sh's
# overrides for the run-facts and Holdings readers). The reads and the list
# share the 90-second budget and the post adds its 25, so a capture ends
# inside the pass's 120 (TEARDOWN_CAPTURE_SECS); change them together.
# bash 3.2.
set -uo pipefail
export LC_ALL=C

PROG=unit-cost
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

GH="${GH:-gh}"
KOTO_REQUESTS="${KOTO_REQUESTS:-$HOME/.koto/requests}"
num_or() { case "$1" in '' | *[!0-9]*) printf '%s\n' "$2" ;; *) printf '%s\n' "$1" ;; esac; }
FETCH_SECS=$(num_or "${UNIT_COST_FETCH_SECS:-}" 8)
BUDGET_SECS=$(num_or "${UNIT_COST_BUDGET_SECS:-}" 90)
LIST_SECS=$(num_or "${UNIT_COST_LIST_SECS:-}" 15)
POST_SECS=$(num_or "${UNIT_COST_POST_SECS:-}" 25)
SIZE_LIMIT=50000
SECONDS=0

usage() { sed -n '/^# Usage:/,/^# The object holds/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

RE_REPO='^[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*$'
RE_TS='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z$'
# The baseline's own shapes for what its derivation reads: a koto event's
# timestamp and state, a ledger's panel, a run's timestamp, a head branch.
RE_EVTS='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z$'
RE_STATE='^[a-z][a-z0-9_]{0,63}$'
RE_PANEL='^[a-z][a-z0-9_-]{0,31}$'
RE_BRANCH='^[A-Za-z0-9._/-]{1,100}$'
RE_SHA='^[0-9a-f]{40}$'
RE_NUM='^[1-9][0-9]{0,9}$'
# A Claude Code session id, as the handoff and the pass match it.
RE_SID='^[0-9a-f][0-9a-f-]{7,63}$'
# niwa's dispatch id, as the handoff seals it.
RE_DID='^[A-Za-z0-9._:-]{1,128}$'

# A repository: the pattern, no `..`, and neither part starting with `-`, so
# it can never read as an option.
repo_ok() { [[ $1 =~ $RE_REPO ]] && case "$1" in *..* | -* | */-*) return 1 ;; esac; }
# A head branch: the baseline's pattern, never an option, no `..`.
branch_ok() { [[ $1 =~ $RE_BRANCH ]] && case "$1" in *..* | -*) return 1 ;; esac; }
# A regular file, not a symlink.
reg() { [ -f "$1" ] && [ ! -L "$1" ]; }

# ---------------------------------------------------------------------------
# Bounded commands.

# uc_run <secs> <out-file> <command...>: the command bounded, its stdout in
# the file (never a pipe, so nothing left running holds a caller open), its
# stderr discarded and its stdin empty. Returns its status, 124 on timeout.
# dc_tree runs it in a process group of its own, so the deadline's TERM (or
# this script's own trap) stops the whole group, and a hung gh under
# record-append.sh dies with it.
uc_run() {
    local secs=$1 out=$2
    shift 2
    dc_with_deadline "$secs" dc_tree "$@" </dev/null >"$out" 2>/dev/null
}

# uc_left: the seconds left of the reads' budget (0 when spent).
uc_left() {
    local l=$((BUDGET_SECS - SECONDS))
    [ "$l" -gt 0 ] || l=0
    printf '%s\n' "$l"
}

# uc_bound <secs>: the bound for one read, the smaller of <secs> and the
# budget left; 0 when the budget is spent.
uc_bound() {
    local l
    l=$(uc_left)
    [ "$1" -lt "$l" ] && l=$1
    printf '%s\n' "$l"
}

# uc_jq <jq arguments...>: jq over input the worker or GitHub wrote. Its
# messages can quote that input, so they go nowhere; every caller acts on the
# status instead (a failure is that figure's `invalid input`).
uc_jq() { jq "$@" 2>/dev/null; }

# uc_gh_ok <gh arguments...>: 0 when the wrapper admits the call. Admitted:
#   pr view <n> --repo <owner/repo> --json <fields>
#   run list --repo <owner/repo> [--branch <b>] [--commit <sha>] [--json <fields>] [--limit <n>]
#   api --method GET repos/<owner>/<repo>[/<path>] [--paginate] [--jq <filter>]
# Nothing that writes, nothing without its repository named.
uc_gh_ok() {
    local fields_re='^[A-Za-z][A-Za-z,]*$'
    case "${1:-} ${2:-}" in
        "pr view")
            [ $# -eq 7 ] && [[ $3 =~ $RE_NUM ]] && [ "$4" = --repo ] && repo_ok "$5" \
                && [ "$6" = --json ] && [[ $7 =~ $fields_re ]]
            return
            ;;
        "run list")
            [ $# -ge 4 ] && [ "$3" = --repo ] && repo_ok "$4" || return 1
            shift 4
            while [ $# -gt 0 ]; do
                [ $# -ge 2 ] || return 1
                case "$1" in
                    --branch) case "$2" in '' | -*) return 1 ;; esac
                        grep -Eq '^[A-Za-z0-9._/+-]{1,200}$' <<<"$2" || return 1 ;;
                    --commit) [[ $2 =~ $RE_SHA ]] || return 1 ;;
                    --json) [[ $2 =~ $fields_re ]] || return 1 ;;
                    --limit) [[ $2 =~ $RE_NUM ]] || return 1 ;;
                    *) return 1 ;;
                esac
                shift 2
            done
            return 0
            ;;
        "api --method")
            [ $# -ge 4 ] && [ "$3" = GET ] || return 1
            case "$4" in repos/*) ;; *) return 1 ;; esac
            case "$4" in *..*) return 1 ;; esac
            grep -Eq '^repos/[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*(/[A-Za-z0-9_.,=&?/-]*)?$' <<<"$4" || return 1
            shift 4
            while [ $# -gt 0 ]; do
                case "$1" in
                    --paginate) shift ;;
                    --jq) [ $# -ge 2 ] || return 1; shift 2 ;;
                    *) return 1 ;;
                esac
            done
            return 0
            ;;
    esac
    return 1
}

# uc_gh <out-file> <gh arguments...>: one admitted GitHub read, bounded by the
# fetch bound and the budget. Returns gh's status, 64 refused (no call made),
# 125 the budget is spent (no call made), 124 the deadline stopped it.
uc_gh() {
    local out=$1 b
    shift
    uc_gh_ok "$@" || return 64
    b=$(uc_bound "$FETCH_SECS")
    [ "$b" -gt 0 ] || return 125
    uc_run "$b" "$out" "$GH" "$@"
}

# The reason a failed read gives a figure.
read_reason() { case "$1" in 125) echo "time limit" ;; 64) echo "invalid input" ;; *) echo "read failed" ;; esac; }

# ---------------------------------------------------------------------------
# Arguments.

MODE="${1:-}"
[ $# -gt 0 ] && shift
if [ "$MODE" = gh-check ]; then
    uc_gh_ok "$@" && exit 0
    exit 1
fi
SESSION="" ARCH="" TOPIC="" PRS_FILE="" UNIT_JSON=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --archive) [ $# -ge 2 ] || usage; ARCH=$2; shift 2 ;;
        --topic) [ $# -ge 2 ] || usage; TOPIC=$2; shift 2 ;;
        --prs-file) [ $# -ge 2 ] || usage; PRS_FILE=$2; shift 2 ;;
        --unit-json) [ $# -ge 2 ] || usage; UNIT_JSON=$2; shift 2 ;;
        *) usage ;;
    esac
done
case "$MODE" in
    compute) [ -z "$SESSION" ] || usage ;;
    capture) [ -n "$SESSION" ] && [ -z "$UNIT_JSON" ] || usage ;;
    *) usage ;;
esac
[ -n "$ARCH" ] && [ -n "$TOPIC" ] && [ -n "$PRS_FILE" ] || usage
dc_valid_topic "$TOPIC" || { say "the topic is not a dispatch topic"; exit 64; }
[ -d "$ARCH" ] && [ ! -L "$ARCH" ] || { say "the archive is not a directory"; exit 64; }
[ -f "$PRS_FILE" ] && [ -r "$PRS_FILE" ] || { say "the pull request file can't be read"; exit 64; }
[ -z "$UNIT_JSON" ] || [ -r "$UNIT_JSON" ] || { say "the unit file can't be read"; exit 64; }
ARCH=$(cd "$ARCH" && pwd -P) || exit 64
KEY=${ARCH##*/}
[[ $KEY =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-${TOPIC}-[0-9a-f]{6,64}$ ]] \
    || { say "the archive's name is not a capture key for the topic"; exit 65; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/unit-cost.XXXXXX") || exit 1
trap 'rm -rf "$WD"' EXIT
WD=$(cd "$WD" && pwd -P) || exit 1
cp "$PRS_FILE" "$WD/prs" 2>/dev/null || { say "the pull request file can't be read"; exit 64; }
[ -z "$UNIT_JSON" ] || cp "$UNIT_JSON" "$WD/unit.json" 2>/dev/null || { say "the unit file can't be read"; exit 64; }
# A TERM (the pass's deadline) stops every job still running, which stops
# each one's process group through dc_tree's own trap, and leaves.
# shellcheck disable=SC2329 # the TERM trap's handler
uc_stop() {
    local j
    for j in $(jobs -p); do kill -TERM "$j" >/dev/null 2>&1; done
    exit 143
}
trap uc_stop TERM
# Every command runs from here, outside the instance and the archive.
cd "$WD" || exit 1

# ---------------------------------------------------------------------------
# The pieces. Each writes its JSON into $WD for uc_compute to assemble;
# `reason` fields name why a piece was not taken, and the assembly turns them
# into `missing`. uc_compute runs them in order: uc_sessions first, since
# uc_plan_shape and uc_dispatch read what it writes (sessions.json and
# session-names); uc_scan before uc_tokens, uc_dispatch and uc_credit, which
# read what it writes; uc_pulls and uc_dispatch before uc_credit; and
# uc_attribution, uc_pulls and uc_credit before uc_visibility, which reads the
# record's repository and every pull request's. The archive's own reads come
# first and GitHub's after, so a spent budget never costs a local figure
# that an earlier read could have taken.

# uc_ledger <file>: a session's verdict ledger as {rows: [{panel, round}]}, or
# {bad: true} when it isn't one.
uc_ledger() {
    uc_jq -c --arg re "$RE_PANEL" '
        if type == "object" and (.history | type) == "array" then
            [.history[] | if type == "object" and (.panel | type) == "string" and (.panel | test($re))
                             and (((.round | type) == "number" and .round >= 0 and .round == (.round | floor) and .round < 1000000)
                                  or ((.round | type) == "string" and (.round | test("^[0-9]{1,6}$"))))
                          then {panel, round: (.round | tostring)} else null end]
            | if any(.[]; . == null) then {bad: true} else {rows: .} end
        else {bad: true} end' "$1" || echo '{"bad":true}'
}

# Sessions: one line per archived session directory holding its state log,
# in byte order of the names. Names stay here: they carry a plan's issue
# titles, so the entry never holds one. Each line keeps the session's
# transitioned and rewound events ({seq, at, to}) and its ledger; `bad` marks
# a log with a line that isn't JSON or an event outside its shapes, and
# `unreadable` a header that can't be read.
uc_sessions() {
    local d name f plan hasplan req reqbad led i=0
    : >"$WD/sessions.jsonl"
    : >"$WD/session-names"
    for d in "$ARCH"/koto/*; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        name=${d##*/}
        f="$d/koto-$name.state.jsonl"
        reg "$f" || continue
        i=$((i + 1))
        hasplan=false plan=""
        if reg "$d/ctx/plan_execution_mode"; then
            hasplan=true
            plan=$(head -c 64 "$d/ctx/plan_execution_mode" | tr -d ' \t\r\n')
        fi
        req="" reqbad=false
        if reg "$d/request-leg.toml"; then
            req=$(sed -n 's/^request_id[[:space:]]*=[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "$d/request-leg.toml" | head -n 1)
            [ -z "$req" ] || [[ $req =~ $DC_RE_REQ ]] || { req=""; reqbad=true; }
        fi
        led=null
        if [ -d "$d/ctx" ] && [ ! -L "$d/ctx" ] && reg "$d/ctx/verdict_ledger.json"; then
            led=$(uc_ledger "$d/ctx/verdict_ledger.json")
        fi
        printf '%s\n' "$name" >>"$WD/session-names"
        uc_jq -R -n -c --argjson i "$i" --arg plan "$plan" --argjson hasplan "$hasplan" --arg req "$req" \
            --argjson reqbad "$reqbad" --argjson led "$led" --arg rets "$RE_EVTS" --arg rest "$RE_STATE" '
            [inputs | select(test("^[[:space:]]*$") | not) | (try {v: fromjson} catch {bad: true})] as $l
            | ([$l[] | select(has("v")) | .v][0]) as $h0
            | (($h0 | type) == "object" and ($h0.template_name | type) == "string") as $hok
            | (if $hok then $h0 else {} end) as $h
            | ($h.template_name // "") as $tn
            | [$l[] | select(has("v")) | .v
               | select(type == "object" and (.seq | type) == "number" and (.type == "transitioned" or .type == "rewound"))] as $ev
            | ($ev | all(.[]; (.timestamp | type) == "string" and (.timestamp | test($rets))
                         and (.payload | type) == "object" and (.payload.to | type) == "string" and (.payload.to | test($rest)))) as $evok
            | {index: $i,
               template: (if $tn == "deliver" or $tn == "scope" or $tn == "work-on" then $tn
                          elif $tn == "execute" or $tn == "execute-coordinated" then "execute"
                          else "other" end),
               unreadable: ($hok | not),
               source_file: ($h.template_source_file // "" | if type == "string" then . else "" end),
               mode: ([$l[] | select(has("v")) | .v | select(type == "object" and .type == "evidence_submitted"
                                     and (.payload | type) == "object" and .payload.state == "entry"
                                     and (.payload.fields | type) == "object" and (.payload.fields | has("mode")))
                       | .payload.fields.mode][0]),
               plan: (if $hasplan then $plan else null end),
               request: (if $req == "" then null else $req end),
               request_bad: $reqbad,
               bad: (any($l[]; has("bad")) or ($evok | not)),
               events: (if $evok then [$ev[] | {seq, at: .timestamp, to: .payload.to}] else [] end),
               ledger: $led}' "$f" >>"$WD/sessions.jsonl" \
            || jq -n -c --argjson i "$i" '{index: $i, template: "other", unreadable: true, source_file: "", mode: null, plan: null,
                   request: null, request_bad: false, bad: true, events: [], ledger: null}' >>"$WD/sessions.jsonl"
    done
    jq -s -c '.' "$WD/sessions.jsonl" >"$WD/sessions.json"
}

uc_plan_shape() {
    jq -c '
        def m($v): {value: $v, state: "measured", source: "koto-state"};
        def nr($r): {value: null, state: "not recoverable", source: "koto-state", reason: $r};
        def oneof($xs): . as $v | any($xs[]; . == $v);
        ([.[] | select(.template == "deliver")][0]) as $d
        | ([.[] | select(.template == "execute")][0]) as $x
        | ([.[] | select(.template == "work-on")][0]) as $w
        | if any(.[]; .unreadable) then nr("invalid input")
          elif $d != null then
              ($d.plan | if . == null or . == "" then nr("no source")
                         elif oneof(["single-pr", "multi-pr", "coordinated"]) then m(.)
                         else nr("invalid input") end)
          elif $x != null then
              ($x.source_file | if . == "execute-coordinated.md" then m("coordinated")
                                elif . == "execute.md" then m("single-pr")
                                elif . == "" then nr("no source")
                                else nr("invalid input") end)
          elif $w != null then
              ($w.mode | if . == "plan_backed" then m("multi-pr")
                         elif oneof(["issue_backed", "free_form"]) then m("issue")
                         elif . == null then nr("no source")
                         else nr("invalid input") end)
          else m("none") end' "$WD/sessions.json" >"$WD/shape.json"
}

# Dispatch, by the header's rule. A request whose requested_by names an
# archived session was made inside the unit (its /deliver asking /scope or
# /execute), after dispatch, so it is never the dispatch; requested_by is
# only compared, never kept. The candidates are compared by a key that pads
# the fraction, so `09:00:05Z` and `09:00:05.1Z` order as times do.
uc_dispatch() {
    local id f out bad
    : >"$WD/requests.jsonl"
    for id in $(jq -r '.[] | .request // empty' "$WD/sessions.json" | sort -u); do
        [[ $id =~ $DC_RE_REQ ]] || continue
        f="$KOTO_REQUESTS/$id/request.jsonl"
        reg "$f" || continue
        head -n 1 "$f" | uc_jq -R -c '(try fromjson catch null) | select(type == "object")
            | {created_at: (.created_at // "" | if type == "string" then . else "" end),
               by: (.requested_by // "" | if type == "string" then . else "" end)}' >>"$WD/requests.jsonl"
    done
    out=""
    if reg "$ARCH/job/state.json"; then
        out=$(uc_jq -r '.createdAt // "" | if type == "string" then . else "" end' "$ARCH/job/state.json") || out=""
    fi
    [[ $out =~ $RE_TS ]] || out=""
    bad=$(jq -r 'any(.[]; .request_bad)' "$WD/sessions.json")
    jq -s -c --rawfile names "$WD/session-names" --arg job "$out" --arg re "$RE_TS" --argjson bad "$bad" \
        --slurpfile scan "$WD/scan.json" '
        def key: if length > 20 then .[0:19] + "." + ((.[20:-1] + "000000000")[0:9]) else .[0:19] + ".000000000" end;
        ($names | split("\n") | map(select(. != ""))) as $n
        | $scan[0] as $s
        | ([.[] | select((.created_at | test($re)) and ((.by as $b | $n | index([$b])) == null)) | .created_at]
           | sort_by(key) | .[0]) as $r
        | ([(if $job != "" then $job else empty end), ($s.firsts // [])[]] | sort_by(key) | .[0]) as $o
        | ($s.jobs // 0) as $jobs
        | if $bad then {value: null, state: "not recoverable", source: "koto-request", jobs: $jobs, reason: "invalid input"}
          elif $s.reason != null and ($s.mains // 0) > 0 then
              {value: null, state: "not recoverable", source: "koto-request", jobs: $jobs, reason: $s.reason}
          elif $r != null and ($o == null or ($r | key) <= ($o | key)) then
              {value: $r, state: "measured", source: "koto-request", jobs: $jobs}
          elif $o != null then {value: $o, state: "measured", source: "job-state", jobs: $jobs}
          else {value: null, state: "not recoverable", source: "koto-request", jobs: $jobs, reason: "no source"} end' \
        "$WD/requests.jsonl" >"$WD/dispatch.json"
}

# uc_token_row <file-list>: the row over the transcripts listed, on stdout,
# for an archive made before claude-projects/. Run through uc_run, so a large
# transcript counts against the budget and a TERM never waits on a
# foreground jq.
# shellcheck disable=SC2329 # run through uc_run
uc_token_row() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        cat "$f"
        printf '\n'
    done <"$1" | jq -R -n -c '
        def n(x): if (x | type) == "number" and x >= 0 then (x | floor) else 0 end;
        reduce (inputs | select(test("^[[:space:]]*$") | not) | (try [fromjson] catch null)) as $l
            ({bad: false, m: {}};
             if $l == null then .bad = true
             else $l[0] as $o
                | if ($o | type) == "object" and $o.type == "assistant" and ($o.message | type) == "object"
                     and ($o.message.id | type) == "string" and ($o.message.usage | type) == "object" then
                      $o.message.usage as $u
                      | .m[$o.message.id] |= ((. // {i: 0, o: 0, cc: 0, cr: 0})
                          | .i = ([.i, n($u.input_tokens)] | max)
                          | .o = ([.o, n($u.output_tokens)] | max)
                          | .cc = ([.cc, n($u.cache_creation_input_tokens)] | max)
                          | .cr = ([.cr, n($u.cache_read_input_tokens)] | max))
                  else . end
             end)
        | {bad, messages: (.m | length), input: ([.m[].i] | add // 0), output: ([.m[].o] | add // 0),
           cache_creation: ([.m[].cc] | add // 0), cache_read: ([.m[].cr] | add // 0)}'
}

# The scan over claude-projects/, in one jq: the stream holds every listed
# file, each opened by an `F<row><main>` line and every one of its lines
# prefixed `L`, so nothing in a transcript can pass for a file boundary. Per
# row its messages by id (the worker's files come first, and `nested` skips
# an id the worker holds), per main session transcript its first event, the
# pr-link records whose repository and number fit their patterns (the rest
# are dropped here, never used), and the gitBranch values that fit the
# branch pattern.
UC_SCAN='
def n(x): if (x | type) == "number" and x >= 0 then (x | floor) else 0 end;
def key: if length > 20 then .[0:19] + "." + ((.[20:-1] + "000000000")[0:9]) else .[0:19] + ".000000000" end;
def repo_ok: type == "string" and test($re_repo) and (contains("..") | not) and (startswith("-") | not) and (contains("/-") | not);
def num_ok: (type == "number" and . >= 1 and . == floor and . < 10000000000) or (type == "string" and test($re_num));
def branch_ok: test($re_branch) and (contains("..") | not) and (startswith("-") | not);
def row: {bad, messages: (.m | length), input: ([.m[].i] | add // 0), output: ([.m[].o] | add // 0),
          cache_creation: ([.m[].cc] | add // 0), cache_read: ([.m[].cr] | add // 0)};
reduce inputs as $s
  ({row: "n", main: false, file: -1, mains: 0, w: {bad: false, m: {}}, n: {bad: false, m: {}}, first: {}, links: {}, branches: {}};
   if ($s | startswith("F")) then
       .row = (if $s[1:2] == "w" then "w" else "n" end) | .main = ($s[2:3] == "1") | .file += 1
       | if .main then .mains += 1 else . end
   elif ($s | startswith("L")) and ($s[1:] | test("[^[:space:]]")) then
       .row as $r
       | (try [$s[1:] | fromjson] catch null) as $l
       | if $l == null then .[$r].bad = true
         elif ($l[0] | type) != "object" then .
         else $l[0] as $o
           | (if $o.type == "assistant" and ($o.message | type) == "object" and ($o.message.id | type) == "string"
                 and ($o.message.usage | type) == "object" and ($r == "w" or (.w.m | has($o.message.id) | not)) then
                  $o.message.usage as $u
                  | .[$r].m[$o.message.id] |= ((. // {i: 0, o: 0, cc: 0, cr: 0})
                      | .i = ([.i, n($u.input_tokens)] | max)
                      | .o = ([.o, n($u.output_tokens)] | max)
                      | .cc = ([.cc, n($u.cache_creation_input_tokens)] | max)
                      | .cr = ([.cr, n($u.cache_read_input_tokens)] | max))
              else . end)
           | (if .main and ($o.timestamp | type) == "string" and ($o.timestamp | test($re_evts)) then
                  ($o.timestamp | key) as $k | (.file | tostring) as $f
                  | if .first[$f] == null or $k < .first[$f].k then .first[$f] = {k: $k, v: $o.timestamp} else . end
              else . end)
           | (if $o.type == "pr-link" and ($o.prRepository | repo_ok) and ($o.prNumber | num_ok) then
                  (($o.prRepository) + "#" + ($o.prNumber | tostring)) as $id
                  | .links[$id] = ((.links[$id] // {r: $o.prRepository, n: ($o.prNumber | tostring), ts: []})
                      | if ($o.timestamp | type) == "string" and ($o.timestamp | test($re_evts)) and (.ts | length) < 1000
                        then .ts += [$o.timestamp] else . end)
              else . end)
           | (if ($o.gitBranch | type) == "string" and ($o.gitBranch | branch_ok) then .branches[$o.gitBranch] = true else . end)
         end
   else . end)
| {worker: (.w | row), nested: (.n | row), mains: .mains, firsts: [.first[] | .v],
   links: [.links[] | .ts |= unique], branches: (.branches | keys)}'

# uc_scan_run: the stream over $WD/scan.list (`w <path>` then `n <path>`
# lines) through UC_SCAN, on stdout. Run through uc_run, like uc_token_row.
# shellcheck disable=SC2329 # run through uc_run
uc_scan_run() {
    local row f main
    while IFS=' ' read -r row f; do
        [ -n "$f" ] || continue
        main=0
        grep -qxF -- "$f" "$WD/main.list" && main=1
        printf 'F%s%s\n' "$row" "$main"
        sed 's/^/L/' "$f"
        printf '\n'
    done <"$WD/scan.list" | jq -R -n -c --arg re_repo "$RE_REPO" --arg re_num "$RE_NUM" --arg re_branch "$RE_BRANCH" \
        --arg re_evts "$RE_EVTS" "$UC_SCAN"
}

# uc_scan: the archive's layout (LAYOUT: projects, transcript or none), the
# worker's session id, and for claude-projects/ the scan, in $WD/scan.json:
# {reason, worker, nested, mains, jobs, firsts, links, branches}, reason null
# when the scan read every file. Only regular files are listed: find never
# follows a link, and a linked directory is never entered.
uc_scan() {
    local cp="$ARCH/claude-projects" sid="" d f b rc reason=""
    : >"$WD/worker.list"
    : >"$WD/nested.list"
    : >"$WD/main.list"
    : >"$WD/scan.list"
    if reg "$ARCH/job/state.json"; then
        sid=$(uc_jq -r '.sessionId // "" | if type == "string" then . else "" end' "$ARCH/job/state.json") || sid=""
    fi
    [[ $sid =~ $RE_SID ]] || sid=""
    if [ -z "$sid" ] && reg "$ARCH/teardown.json"; then
        sid=$(uc_jq -r '.job.session // "" | if type == "string" then . else "" end' "$ARCH/teardown.json") || sid=""
        [[ $sid =~ $RE_SID ]] || sid=""
    fi
    SID=$sid
    LAYOUT=none
    if [ -d "$cp" ] && [ ! -L "$cp" ]; then
        LAYOUT=projects
    elif [ -d "$ARCH/transcript" ] && [ ! -L "$ARCH/transcript" ]; then
        LAYOUT=transcript
    fi
    if [ "$LAYOUT" != projects ]; then
        echo '{"reason":null,"worker":null,"nested":null,"mains":0,"jobs":0,"firsts":[],"links":[],"branches":[]}' >"$WD/scan.json"
        return 0
    fi
    for d in "$cp"/*; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        for f in "$d"/*.jsonl; do
            reg "$f" || continue
            b=${f##*/}
            b=${b%.jsonl}
            [[ $b =~ $RE_SID ]] && printf '%s\n' "$f" >>"$WD/main.list"
        done
        [ -n "$sid" ] || continue
        reg "$d/$sid.jsonl" && printf '%s\n' "$d/$sid.jsonl" >>"$WD/worker.list"
        if [ -d "$d/$sid/subagents" ] && [ ! -L "$d/$sid" ] && [ ! -L "$d/$sid/subagents" ]; then
            find "$d/$sid/subagents" -type f -name '*.jsonl' 2>"$WD/find.err" | sort >>"$WD/worker.list"
        fi
    done
    find "$cp" -type f -name '*.jsonl' 2>"$WD/find.err" | sort | grep -vxF -f "$WD/worker.list" >"$WD/nested.list"
    sed 's/^/w /' "$WD/worker.list" >"$WD/scan.list"
    sed 's/^/n /' "$WD/nested.list" >>"$WD/scan.list"
    b=$(uc_left)
    if [ "$b" -le 0 ]; then
        reason="time limit"
    else
        uc_run "$b" "$WD/scan.raw" uc_scan_run
        rc=$?
        if [ "$rc" != 0 ] || ! uc_jq -e 'type == "object"' "$WD/scan.raw" >/dev/null; then
            reason="read failed"
            [ "$(uc_left)" -gt 0 ] || reason="time limit"
        fi
    fi
    if [ -n "$reason" ]; then
        jq -n -c --arg r "$reason" --argjson m "$(grep -c . "$WD/main.list")" \
            '{reason: $r, worker: null, nested: null, mains: $m, jobs: 0, firsts: [], links: [], branches: []}' >"$WD/scan.json"
    else
        jq -c '. + {reason: null, jobs: .mains}' "$WD/scan.raw" >"$WD/scan.json"
    fi
}

# Tokens: the rows from the scan, or, for an archive made before
# claude-projects/, the worker's row read as before and no nested row.
uc_tokens() {
    local tr="$ARCH/transcript" reason="" b why row
    if [ "$LAYOUT" = projects ]; then
        why=$(jq -r '.reason // ""' "$WD/scan.json")
        for row in worker nested; do
            reason=$why
            if [ -z "$reason" ]; then
                if [ "$row" = worker ] && [ ! -s "$WD/worker.list" ]; then
                    reason="no source"
                elif jq -e --arg r "$row" '.[$r].bad' "$WD/scan.json" >/dev/null; then
                    reason="invalid input"
                fi
            fi
            if [ -n "$reason" ]; then
                jq -n -c --arg r "$reason" '{messages: null, input: null, output: null, cache_creation: null, cache_read: null,
                    state: "not recoverable", source: "transcripts", reason: $r}' >"$WD/$row.json"
            else
                jq -c --arg r "$row" '.[$r] | del(.bad) + {state: "measured", source: "transcripts"}' "$WD/scan.json" >"$WD/$row.json"
            fi
        done
        return 0
    fi
    # find -type f lists regular files only: a symlink in transcript/ is never read.
    : >"$WD/worker.list"
    if [ "$LAYOUT" = transcript ] && [ -n "$SID" ] && reg "$tr/$SID.jsonl"; then
        printf '%s\n' "$tr/$SID.jsonl" >"$WD/worker.list"
        if [ -d "$tr/$SID/subagents" ] && [ ! -L "$tr/$SID" ] && [ ! -L "$tr/$SID/subagents" ]; then
            find "$tr/$SID/subagents" -type f -name '*.jsonl' 2>"$WD/find.err" | sort >>"$WD/worker.list"
        fi
    fi
    b=$(uc_left)
    if [ "$b" -le 0 ]; then
        reason="time limit"
    elif [ "$LAYOUT" != transcript ] || [ ! -s "$WD/worker.list" ]; then
        reason="no source"
    elif ! uc_run "$b" "$WD/worker.raw" uc_token_row "$WD/worker.list"; then
        reason="read failed"
        [ "$(uc_left)" -gt 0 ] || reason="time limit"
    elif [ ! -s "$WD/worker.raw" ]; then
        reason="read failed"
    elif jq -e '.bad' "$WD/worker.raw" >/dev/null; then
        reason="invalid input"
    fi
    if [ -n "$reason" ]; then
        jq -n -c --arg r "$reason" '{messages: null, input: null, output: null, cache_creation: null, cache_read: null,
            state: "not recoverable", source: "transcripts", reason: $r}' >"$WD/worker.json"
    else
        jq -c 'del(.bad) + {state: "measured", source: "transcripts"}' "$WD/worker.raw" >"$WD/worker.json"
    fi
    # Without claude-projects/ the archive holds no whole nested row to read.
    jq -n -c '{messages: null, input: null, output: null, cache_creation: null, cache_read: null,
        state: "not recoverable", source: "transcripts", reason: "no source"}' >"$WD/nested.json"
}

# uc_runs <repo> <n> <branch>: the pull request's heads and the runs on them,
# as {heads: [sha...], runs: [{run_id, head_sha, attempt, concluded,
# conclusion, finished_at}]} in $WD/gh.json, every attempt of every run on a
# head its own row. On a failed or refused read UC_WHY holds the reason and it
# returns 1.
uc_runs() {
    local repo=$1 n=$2 br=$3 rc id att k
    UC_WHY=""
    uc_gh "$WD/commits.raw" api --method GET "repos/$repo/pulls/$n/commits" --paginate
    rc=$?
    [ "$rc" = 0 ] || { UC_WHY=$(read_reason "$rc"); return 1; }
    uc_jq -s -c --arg re "$RE_SHA" '[.[] | if type == "array" then .[] else error("x") end
            | .sha | if type == "string" and test($re) then . else error("x") end]' "$WD/commits.raw" >"$WD/heads.json" \
        || { UC_WHY="invalid input"; return 1; }
    uc_gh "$WD/runs.raw" run list --repo "$repo" --branch "$br" --limit 300 \
        --json databaseId,headSha,attempt,status,conclusion,updatedAt
    rc=$?
    [ "$rc" = 0 ] || { UC_WHY=$(read_reason "$rc"); return 1; }
    uc_jq -c --slurpfile h "$WD/heads.json" --arg sha "$RE_SHA" --arg ts "$RE_EVTS" '
        def word: type == "string" and test("^[a-z_]{0,32}$");
        if type != "array" then error("x") else . end
        | map(if type == "object" and (.databaseId | type) == "number" and .databaseId >= 1 and .databaseId == (.databaseId | floor)
                 and (.headSha | type) == "string" and (.headSha | test($sha))
                 and (.attempt | type) == "number" and .attempt >= 1 and .attempt <= 999 and .attempt == (.attempt | floor)
                 and (.status | word) and ((.conclusion == null) or (.conclusion | word))
                 and (.updatedAt | type) == "string" and (.updatedAt | test($ts))
              then {run_id: .databaseId, head_sha: .headSha, attempt, concluded: (.status == "completed" and (.conclusion // "") != ""),
                    conclusion: (.conclusion // ""), finished_at: .updatedAt}
              else error("x") end)
        | map(select(.head_sha as $s | $h[0] | index([$s]) != null))' "$WD/runs.raw" >"$WD/runs.json" \
        || { UC_WHY="invalid input"; return 1; }
    cp "$WD/runs.json" "$WD/runrows.json"
    while read -r id att; do
        [ -n "$id" ] || continue
        k=1
        while [ "$k" -lt "$att" ]; do
            uc_gh "$WD/att.raw" api --method GET "repos/$repo/actions/runs/$id/attempts/$k"
            rc=$?
            [ "$rc" = 0 ] || { UC_WHY=$(read_reason "$rc"); return 1; }
            uc_jq -c --slurpfile r "$WD/runrows.json" --argjson id "$id" --argjson k "$k" --arg ts "$RE_EVTS" '
                def word: type == "string" and test("^[a-z_]{0,32}$");
                if type == "object" and (.status | word) and ((.conclusion == null) or (.conclusion | word))
                   and (.updated_at | type) == "string" and (.updated_at | test($ts))
                then $r[0] + [{run_id: $id, head_sha: ([$r[0][] | select(.run_id == $id)][0].head_sha), attempt: $k,
                               concluded: (.status == "completed" and (.conclusion // "") != ""),
                               conclusion: (.conclusion // ""), finished_at: .updated_at}]
                else error("x") end' "$WD/att.raw" >"$WD/runrows.new" \
                || { UC_WHY="invalid input"; return 1; }
            mv "$WD/runrows.new" "$WD/runrows.json"
            k=$((k + 1))
        done
    done <<EOF
$(jq -r '.[] | select(.attempt > 1) | "\(.run_id) \(.attempt)"' "$WD/runs.json")
EOF
    jq -n -c --slurpfile h "$WD/heads.json" --slurpfile r "$WD/runrows.json" '{heads: $h[0], runs: $r[0]}' >"$WD/gh.json"
}

# Pull requests: each verdict line's merge time, and its heads and runs for
# green and failing heads. A line outside the shapes is left out of `pulls`
# and makes every GitHub figure `invalid input`, since the unit's set of pull
# requests is then not whole.
uc_pulls() {
    local ref sha rest repo n rc at why br ghwhy
    : >"$WD/pulls.jsonl"
    : >"$WD/pull-reasons.jsonl"
    VERDICT_BAD=false
    while read -r ref sha rest; do
        [ -n "$ref" ] || continue
        repo=${ref%#*} n=${ref##*#}
        if [ -n "$rest" ] || [ "$repo" = "$ref" ] || ! repo_ok "$repo" || ! [[ $n =~ $RE_NUM ]] || ! [[ $sha =~ $RE_SHA ]]; then
            printf '{"figure":"pulls","reason":"invalid input"}\n' >>"$WD/pull-reasons.jsonl"
            VERDICT_BAD=true
            continue
        fi
        at="" why="" br="" ghwhy=""
        echo '{"heads":[],"runs":[]}' >"$WD/gh.json"
        uc_gh "$WD/pr.json" pr view "$n" --repo "$repo" --json mergedAt,headRefName
        rc=$?
        if [ "$rc" = 0 ]; then
            at=$(uc_jq -r '.mergedAt // "" | if type == "string" then . else "" end' "$WD/pr.json") || at=""
            [[ $at =~ $RE_TS ]] || { at=""; why="invalid input"; }
            br=$(uc_jq -r '.headRefName // "" | if type == "string" then . else "" end' "$WD/pr.json") || br=""
            if ! branch_ok "$br"; then
                ghwhy="invalid input"
            elif ! uc_runs "$repo" "$n" "$br"; then
                ghwhy=$UC_WHY
            fi
        else
            why=$(read_reason "$rc")
            ghwhy=$why
        fi
        [ -z "$why" ] || jq -n -c --arg r "$why" '{figure: "pulls.merged_at", reason: $r}' >>"$WD/pull-reasons.jsonl"
        jq -n -c --arg r "$repo" --argjson n "$n" --arg s "$sha" --arg at "$at" --arg why "$why" --arg ghwhy "$ghwhy" \
            --slurpfile g "$WD/gh.json" \
            '{repo: $r, number: $n, merge_commit: $s, merged_at: (if $at == "" then null else $at end),
              merged_reason: (if $why == "" then null else $why end),
              heads: $g[0].heads, runs: $g[0].runs, gh_reason: (if $ghwhy == "" then null else $ghwhy end)}' >>"$WD/pulls.jsonl"
    done <"$WD/prs"
    # One line per figure and reason, however many pull requests share it.
    jq -s -c 'unique' "$WD/pull-reasons.jsonl" >"$WD/pull-reasons.json"
    jq -s -c '.' "$WD/pulls.jsonl" >"$WD/pulls.json"
}

# Credit, by the header's rule. The candidates are the scan's pr-link
# records under the holding's owner (the owner of a pull request the sealed
# verdict names), less the holding's own, one per repository and number
# (case-insensitive), earliest link first; at most 200 are read. Each read
# is one `gh pr view` out of the budget, its answer read only through jq for
# the four conditions; a pull request that fails one is simply not credited.
# CREDIT_WHY holds the first reason one was left out.
uc_credit() {
    local total cand r n rc disp why
    CREDIT_WHY=""
    : >"$WD/credit.jsonl"
    echo '[]' >"$WD/credit.json"
    [ "$LAYOUT" = projects ] || return 0
    why=$(jq -r '.reason // ""' "$WD/scan.json")
    if [ -n "$why" ]; then
        CREDIT_WHY=$why
        return 0
    fi
    jq -c --slurpfile p "$WD/pulls.json" '
        def key: if length > 20 then .[0:19] + "." + ((.[20:-1] + "000000000")[0:9]) else .[0:19] + ".000000000" end;
        ([$p[0][] | .repo | ascii_downcase | split("/")[0]] | unique) as $owners
        | [$p[0][] | "\(.repo | ascii_downcase)#\(.number)"] as $held
        | [.links[] | select((.r | ascii_downcase | split("/")[0]) as $o | $owners | index([$o]) != null)
           | select("\(.r | ascii_downcase)#\(.n)" as $k | $held | index([$k]) == null)]
        | group_by([(.r | ascii_downcase), (.n | tonumber)])
        | map({r: .[0].r, n: .[0].n, ts: ([.[].ts[]] | unique)})
        | sort_by([((.ts | map(key) | min) // "~"), (.r | ascii_downcase), (.n | tonumber)])
        | .[]' "$WD/scan.json" >"$WD/cands.all"
    total=$(grep -c . "$WD/cands.all")
    [ "$total" -gt 0 ] || return 0
    # Created at or after dispatch can't be judged without one.
    if [ "$(jq -r .state "$WD/dispatch.json")" != measured ]; then
        CREDIT_WHY="no source"
        return 0
    fi
    disp=$(jq -r .value "$WD/dispatch.json")
    head -n 200 "$WD/cands.all" >"$WD/cands"
    [ "$total" -le 200 ] || CREDIT_WHY="entry size"
    while IFS= read -r cand; do
        [ -n "$cand" ] || continue
        r=$(printf '%s' "$cand" | jq -r .r)
        n=$(printf '%s' "$cand" | jq -r .n)
        # Matched again here, where the command is built.
        repo_ok "$r" && [[ $n =~ $RE_NUM ]] || continue
        uc_gh "$WD/cr.raw" pr view "$n" --repo "$r" --json state,createdAt,mergedAt,mergeCommit,headRefName,baseRefName,headRepositoryOwner
        rc=$?
        if [ "$rc" != 0 ]; then
            why="read failed"
            [ "$rc" != 125 ] && [ "$(uc_left)" -gt 0 ] || why="time limit"
            [ -n "$CREDIT_WHY" ] || CREDIT_WHY=$why
            [ "$why" = "time limit" ] && break
            continue
        fi
        uc_jq -c --argjson c "$cand" --arg d "$disp" --slurpfile s "$WD/scan.json" --arg sha "$RE_SHA" --arg evts "$RE_EVTS" "$UC_FIGURES"'
            def str($re): type == "string" and test($re);
            def abs: if . < 0 then -(.) else . end;
            if type != "object" then error("x") else . end
            | ($c.r | ascii_downcase | split("/")[0]) as $own
            | (.headRepositoryOwner | if type == "object" then .login else null end
               | if type == "string" then ascii_downcase else null end) as $hown
            | (.createdAt | if str($evts) then ts else null end) as $created
            | (.mergedAt | if str($evts) then . else null end) as $merged
            | (.mergeCommit | if type == "object" then .oid else null end | if str($sha) then . else null end) as $oid
            | (.headRefName | if type == "string" then . else null end) as $head
            | (.baseRefName | if type == "string" then . else null end) as $base
            | if $hown == $own and .state == "MERGED" and $merged != null and $oid != null
                 and $created != null and $created >= ($d | ts)
                 and (($head != null and $head != $base and ($s[0].branches | index([$head]) != null))
                      or any($c.ts[]; (ts - $created) | abs <= 120))
              then {repo: $c.r, number: ($c.n | tonumber), merge_commit: $oid, merged_at: $merged}
              else empty end' "$WD/cr.raw" >"$WD/cr.out" || { [ -n "$CREDIT_WHY" ] || CREDIT_WHY="read failed"; continue; }
        cat "$WD/cr.out" >>"$WD/credit.jsonl"
    done <"$WD/cands"
    jq -s -c 'def key: if length > 20 then .[0:19] + "." + ((.[20:-1] + "000000000")[0:9]) else .[0:19] + ".000000000" end;
        sort_by([(.merged_at | key), .number])' "$WD/credit.jsonl" >"$WD/credit.json"
}

# niwa's dispatch id, from teardown.json: {v, r}, r the reason v is null.
uc_niwa() {
    if ! reg "$ARCH/teardown.json"; then
        echo '{"v":null,"r":"no source"}' >"$WD/niwa.json"
        return 0
    fi
    uc_jq -c --arg re "$RE_DID" '
        if type != "object" or ((.niwa // {}) | type) != "object" then {v: null, r: "invalid input"}
        else (.niwa // {}) as $n
          | if ($n.dispatch_id | type) == "string" then
                (if ($n.dispatch_id | test($re)) then {v: $n.dispatch_id, r: null} else {v: null, r: "invalid input"} end)
            elif $n.dispatch_id == null then {v: null, r: (if $n.reason == "invalid input" then "invalid input" else "no source" end)}
            else {v: null, r: "invalid input"} end
        end' "$ARCH/teardown.json" >"$WD/niwa.json" \
        || echo '{"v":null,"r":"invalid input"}' >"$WD/niwa.json"
}

# The record, the Unit and the milestone, from the unit file. An issue
# reference is checked before the safety pattern: `#12` starts with `#`, which
# the pattern refuses, yet it is a plain Unit whose milestone is `none`. With
# no valid record facts the Unit is dropped too, since it came from the same
# read.
uc_attribution() {
    [ -s "$WD/unit.json" ] || echo '{"unit_reason": "no source"}' >"$WD/unit.json"
    uc_jq -c --arg re_repo "$RE_REPO" '
        def isstr: type == "string";
        (if type == "object" then . else {} end) as $j
        | ($j.unit_reason | if . == "read failed" or . == "time limit" or . == "no source" or . == "invalid input" then . else "no source" end) as $why
        | (if ($j.scope == "roadmap" or $j.scope == "discipline")
              and ($j.name | isstr and test("^[A-Za-z0-9._-]{1,100}$"))
              and ($j.repo | isstr and test($re_repo) and (contains("..") | not))
           # ref stays in the object shape, empty: the record is the session
           # of the run and has no issue or pull request number.
           then {scope: $j.scope, name: $j.name, repo: $j.repo, ref: ""}
           else null end) as $rec
        | (if $rec == null and ($j | has("scope")) then "invalid input" else $why end) as $recwhy
        | ($j.unit | if isstr then (split(": ") | .[0]) else null end) as $tag
        | ($tag != null and ($tag | test("^(#[1-9][0-9]*|[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*#[1-9][0-9]*)$"))
           and ($tag | contains("..") | not)) as $issue
        | ($issue or ($tag != null and ($tag | test("^[A-Za-z0-9][A-Za-z0-9 _.#/-]{0,63}$")))) as $safe
        | (if $safe and $rec != null then $tag else null end) as $unit
        | (if $tag == null then $why elif $safe then null else "invalid input" end) as $unitwhy
        | {record: $rec, record_reason: (if $rec == null then $recwhy else null end), unit: $unit,
           milestone: (if $rec == null then {value: null, state: "not recoverable", source: "record", reason: $recwhy}
                       elif $rec.scope == "discipline" then {value: "none", state: "measured", source: "record"}
                       elif $unit == null then {value: null, state: "not recoverable", source: "record", reason: $unitwhy}
                       elif $issue then {value: "none", state: "measured", source: "record"}
                       else {value: {roadmap: ("ROADMAP-" + $rec.name), tag: $unit}, state: "measured", source: "record"} end),
           unit_reason: (if $rec != null and $rec.scope == "discipline" and $unit == null then $unitwhy else null end)}
    ' "$WD/unit.json" >"$WD/attribution.json" \
        || jq -n -c '{record: null, record_reason: "invalid input", unit: null, unit_reason: null,
                      milestone: {value: null, state: "not recoverable", source: "record", reason: "invalid input"}}' >"$WD/attribution.json"
}

# uc_public <owner/repo>: 0 when GitHub reads the repository as public
# (`.private` is false). A failed, refused or late read is not public.
uc_public() {
    uc_gh "$WD/vis.raw" api --method GET "repos/$1" --jq .private || return 1
    [ "$(head -c 16 "$WD/vis.raw" | tr -d ' \r\n')" = false ]
}

# Visibility, for a public host: {host_public, public: {repo: bool}} over the
# pull requests' repositories and an `owner/repo#n` Unit's. The host is the
# record's repository; with none known, or its visibility unreadable, the
# host counts as public, so every repository is looked up. `uc_visibility
# holding` reads the host, the holding's repositories and the Unit's before
# credit spends any of the budget; `uc_visibility credited` adds the
# credited pull requests' repositories. Each writes vis.json.
uc_visibility() {
    local r
    if [ "$1" = holding ]; then
        HOST_PUBLIC=true
        : >"$WD/vis.jsonl"
        : >"$WD/vis.seen"
        r=$(jq -r '.record.repo // empty' "$WD/attribution.json")
        if [ -n "$r" ] && repo_ok "$r"; then
            if uc_gh "$WD/vis.raw" api --method GET "repos/$r" --jq .private \
                && [ "$(head -c 16 "$WD/vis.raw" | tr -d ' \r\n')" = true ]; then
                HOST_PUBLIC=false
            fi
        fi
        jq -r '.[].repo' "$WD/pulls.json" >"$WD/vis.want"
        jq -r '.unit // "" | select(test("^[^#]+/[^#]+#[0-9]+$")) | sub("#[0-9]+$"; "")' "$WD/attribution.json" >>"$WD/vis.want"
    else
        jq -r '.[].repo' "$WD/credit.json" >"$WD/vis.want"
    fi
    if [ "$HOST_PUBLIC" = true ]; then
        while IFS= read -r r; do
            repo_ok "$r" || continue
            grep -qxF -- "$r" "$WD/vis.seen" && continue
            printf '%s\n' "$r" >>"$WD/vis.seen"
            if uc_public "$r"; then
                jq -n -c --arg r "$r" '{($r): true}' >>"$WD/vis.jsonl"
            else
                jq -n -c --arg r "$r" '{($r): false}' >>"$WD/vis.jsonl"
            fi
        done <"$WD/vis.want"
    fi
    jq -s -c --argjson hp "$HOST_PUBLIC" '{host_public: $hp, public: (add // {})}' "$WD/vis.jsonl" >"$WD/vis.json"
}

# The figures, as the baseline's derivation computes them (its ts, rounding,
# state time and green), over what the pieces above read.
UC_FIGURES='
def ts: capture("^(?<s>[0-9-]+T[0-9:]+)(\\.(?<f>[0-9]+))?Z$")
  | ((.s + "Z") | fromdateiso8601) + (if .f then ("0." + .f | tonumber) else 0 end);
# Half up, once, from the unrounded value; a negative value by its magnitude.
def rnd($p): if $p == 0 then (. + 0.5 + 1e-9 | floor) else (. * 10 + 0.5 + 1e-9 | floor) end;
def v1: if . < 0 then (-(.) | v1 | -(.)) else rnd(1) / 10 end;
def review_of($t): ($t.scrutiny // 0) + ($t.review // 0) + ($t.qa_validation // 0);
def statetime($evs):
  ($evs | sort_by(.seq | tonumber) | map({at: (.at | ts), to: .to})) as $all
  | ($all | map(.to) | index("done")) as $d
  | (if $d == null then $all else $all[0:$d + 1] end) as $e
  | { done: ($d != null),
      totals: ([range(0; ($e | length) - 1) as $i | {k: $e[$i].to, v: ($e[$i + 1].at - $e[$i].at)}]
               | group_by(.k) | map({key: .[0].k, value: (map(.v) | add)}) | from_entries),
      span: (if ($e | length) > 0 then ($e[-1].at - $e[0].at) else 0 end) };
# The same segments to the millisecond: states and a span that sum exactly.
def statems($evs):
  ($evs | sort_by(.seq | tonumber) | map({at: (.at | ts), to: .to})) as $all
  | ($all | map(.to) | index("done")) as $d
  | (if $d == null then $all else $all[0:$d + 1] end) as $e
  | [range(0; ($e | length) - 1) as $i | {k: $e[$i].to, v: (($e[$i + 1].at - $e[$i].at) * 1000 | round)}] as $s
  | { states: ($s | group_by(.k) | map({key: .[0].k, value: ((map(.v) | add) / 1000)}) | from_entries),
      span_s: (($s | map(.v) | add // 0) / 1000) };
# Green and failing heads for one pull request. A head is green when its
# runs (each at its final attempt) concluded success or skipped; pending when none
# concluded otherwise and some have not concluded, which bounds green.
def prf($heads; $runs):
  [ range(0; $heads | length) as $i | $heads[$i] as $h
    | ($runs | map(select(.head_sha == $h))) as $rs
    | ($rs | group_by(.run_id) | map(max_by(.attempt))) as $final
    | ($final | map(select(.concluded))) as $done
    | { seq: $i,
        failing: ($rs | any(.conclusion == "failure" or .conclusion == "timed_out")),
        status: (if ($final | length) == 0 then "none"
                 elif ($done | all(.conclusion == "success" or .conclusion == "skipped")) | not then "red"
                 elif ($done | length) == ($final | length) then "green"
                 else "pending" end),
        at: (if ($final | length) > 0 then ($final | map(.finished_at | ts) | max) else null end) } ] as $per
  | ($per | map(select(.status == "green" or .status == "pending")) | first) as $g
  | { green: (if $g then $g.at else null end), bound: ($g != null and $g.status == "pending"),
      failing_heads: ($per | map(select(.failing and ($g == null or .seq <= $g.seq))) | length) };
def fig($v; $raw; $st; $src): {value: $v, raw: $raw, state: $st, source: $src};
def nrf($src; $r): {value: null, raw: null, state: "not recoverable", source: $src, reason: $r};
def naf($src): {value: null, raw: null, state: "not applicable", source: $src};
'

uc_compute() {
    local now
    now=${UNIT_COST_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
    [[ $now =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    uc_sessions
    uc_plan_shape
    uc_scan
    uc_tokens
    uc_dispatch
    uc_attribution
    uc_niwa
    uc_pulls
    uc_visibility holding
    uc_credit
    uc_visibility credited
    jq -n -c --arg key "$KEY" --arg now "$now" --arg topic "$TOPIC" --argjson vbad "$VERDICT_BAD" \
        --arg cwhy "$CREDIT_WHY" --slurpfile credit "$WD/credit.json" --slurpfile niwa "$WD/niwa.json" \
        --slurpfile att "$WD/attribution.json" --slurpfile shape "$WD/shape.json" \
        --slurpfile pulls "$WD/pulls.json" --slurpfile preasons "$WD/pull-reasons.json" \
        --slurpfile disp "$WD/dispatch.json" --slurpfile sess "$WD/sessions.json" --slurpfile vis "$WD/vis.json" \
        --slurpfile worker "$WD/worker.json" --slurpfile nested "$WD/nested.json" "$UC_FIGURES"'
        $att[0] as $a | $shape[0] as $p | $disp[0] as $d | $sess[0] as $S | $pulls[0] as $P | $vis[0] as $V

        # Unit sessions and their state time; $tr is why they give no
        # figures: "na" with none at all, a reason when one is unreadable.
        | ($S | map(select(.template == "work-on"))) as $U
        | (if ($U | length) == 0 then "na"
           elif any($U[]; .bad) then "invalid input"
           elif any($U[]; (.events | length) == 0) then "no source"
           else null end) as $tr
        | (if $tr == null then ($U | map(statetime(.events))) else null end) as $stt
        | (if $stt then {wc: ($stt | map(.totals.implementation // 0) | add),
                         rv: ($stt | map(review_of(.totals)) | add),
                         nodone: ($stt | map(select(.done | not)) | length),
                         summed: ($stt | map(.span) | add),
                         mean: ($stt | map(.span) | add / length)} else null end) as $t
        | def kfig($v; $raw): if $tr == "na" then naf("koto-state") elif $tr != null then nrf("koto-state"; $tr)
                              else fig($v; $raw; "measured"; "koto-state") end;

        # Dispatch, merge and green.
        (if $d.state == "measured" then ($d.value | ts) else null end) as $dsec
        | (if $vbad then {r: "invalid input"} elif ($P | length) == 0 then {r: "no source"}
           elif any($P[]; .merged_at == null) then {r: ([$P[] | select(.merged_at == null) | .merged_reason][0] // "read failed")}
           else {v: ($P | map(.merged_at | ts) | max)} end) as $merge
        | (if $vbad then {r: "invalid input"} elif ($P | length) == 0 then {r: "no source"}
           elif any($P[]; .gh_reason != null) then {r: ([$P[] | .gh_reason // empty][0])}
           elif any($P[]; (.heads | length) == 0) then {r: "no source"}
           else ($P | map(prf(.heads; .runs))) as $pf
             | {fh: ($pf | map(.failing_heads) | add), bound: any($pf[]; .bound)}
               + (if all($pf[]; .green != null) then {v: ($pf | map(.green) | max)} else {gr: "no source"} end) end) as $gh

        | (if $d.state != "measured" then nrf("derived"; $d.reason)
           elif $gh.r then nrf("derived"; $gh.r) elif $gh.gr then nrf("derived"; $gh.gr)
           else ($gh.v - $dsec) as $x | fig($x / 60 | v1; $x; (if $gh.bound then "bound" else "measured" end); "derived") end) as $d2g
        | (if $d.state != "measured" then nrf("derived"; $d.reason)
           elif $merge.r then nrf("derived"; $merge.r)
           else ($merge.v - $dsec) as $x | fig($x / 60 | v1; $x; "measured"; "derived") end) as $d2m
        | def share(num):
            if $tr == "na" then naf("derived") elif $tr != null then nrf("derived"; $tr)
            elif $d2g.state == "not recoverable" then nrf("derived"; $d2g.reason)
            elif $d2g.raw <= 0 then nrf("derived"; "invalid input")
            else (num * 100) as $x | fig($x | v1; $x; $d2g.state; "derived") end;

        { dispatch_to_green_min: $d2g,
          dispatch_to_merge_min: $d2m,
          writing_code_min: (if $t then kfig($t.wc / 60 | v1; $t.wc) else kfig(null; null) end),
          review_min: (if $t then kfig($t.rv / 60 | v1; $t.rv) else kfig(null; null) end),
          outside_share_pct: share(1 - $t.wc / $d2g.raw),
          review_share_pct: share($t.rv / $d2g.raw),
          panel_rounds:
            (if ($U | length) == 0 then naf("verdict-ledger")
             elif any($U[]; .ledger.bad == true) then nrf("verdict-ledger"; "invalid input")
             elif all($U[]; ((.ledger.rows // []) | length) == 0) then nrf("verdict-ledger"; "no source")
             else ($U | map((.ledger.rows // []) | group_by(.panel) | map((map(.round) | unique | length) - 1) | add // 0) | add) as $r
               | fig($r; $r; "measured"; "verdict-ledger") end),
          failing_heads: (if $gh.r then nrf("github-runs"; $gh.r)
                          else fig($gh.fh; $gh.fh; (if $gh.bound then "bound" else "measured" end); "github-runs") end),
          sessions_without_done: (if $t then kfig($t.nodone; $t.nodone) else kfig(null; null) end),
          summed_session_span_min: (if $t then kfig($t.summed / 60 | v1; $t.summed) else kfig(null; null) end),
          minutes_per_unit:
            (if $p.state != "measured" then nrf("koto-state"; $p.reason)
             elif $p.value == "issue" or $p.value == "none" then naf("koto-state")
             elif $t then kfig($t.mean / 60 | v1; $t.mean) else kfig(null; null) end) } as $figures

        # Per session: state time for every session, shares for unit sessions.
        | [$S[] | (.template == "work-on") as $us
           | (if .bad then "invalid input" elif (.events | length) == 0 then "no source" else null end) as $why
           | def sh($k): if $us | not then naf("koto-state") elif $why then nrf("koto-state"; $why) else $k end;
           if $why then
             {index, template, unit_session: $us, done: null, span_s: null, states: null,
              figures: {span_min: nrf("koto-state"; $why), impl_share_pct: sh(null), review_share_pct: sh(null)}}
           else statetime(.events) as $st | statems(.events) as $ms
             | {index, template, unit_session: $us, done: $st.done, span_s: $ms.span_s, states: $ms.states,
                figures: {span_min: fig($st.span / 60 | v1; $st.span; "measured"; "koto-state"),
                          impl_share_pct: sh(if $st.span > 0 then (($st.totals.implementation // 0) / $st.span * 100) as $x
                                             | fig($x | v1; $x; "measured"; "koto-state") else nrf("koto-state"; "no source") end),
                          review_share_pct: sh(if $st.span > 0 then (review_of($st.totals) / $st.span * 100) as $x
                                               | fig($x | v1; $x; "measured"; "koto-state") else nrf("koto-state"; "no source") end)}}
           end] as $sessions

        # A public host never names a repository it does not read as public.
        # The holding pull requests first, then the credited ones; 100 at
        # most, the first reason one was left out kept for `missing`.
        | def shown($r): ($V.host_public | not) or ($V.public[$r] == true);
        ([$P[] | if shown(.repo) then {repo, number, merge_commit, merged_at, via: "holding"} else {repo: "not public"} end]
         + [$credit[0][] | if shown(.repo) then {repo, number, merge_commit, merged_at, via: "session"} else {repo: "not public"} end]) as $all
        | ($all | .[0:100]) as $pulls_out
        | (if $cwhy != "" then $cwhy elif ($all | length) > 100 then "entry size" else null end) as $creditwhy
        | ($a.unit | if type == "string" and test("^[^#]+/[^#]+#[0-9]+$") and (shown(sub("#[0-9]+$"; "")) | not)
                     then "not public" else . end) as $unit

        | ([ (if $a.record == null then {figure: "record", reason: $a.record_reason} else empty end),
             (if $a.unit_reason != null then {figure: "unit", reason: $a.unit_reason} else empty end),
             (if $a.milestone.reason != null then {figure: "milestone", reason: $a.milestone.reason} else empty end),
             (if $p.reason != null then {figure: "plan_shape", reason: $p.reason} else empty end),
             $preasons[0][],
             (if $creditwhy != null and ([$preasons[0][] | select(.figure == "pulls")] | length) == 0
              then {figure: "pulls", reason: $creditwhy} else empty end),
             (if $d.reason != null then {figure: "dispatch", reason: $d.reason} else empty end),
             (if $niwa[0].r != null then {figure: "niwa.dispatch.id", reason: $niwa[0].r} else empty end),
             ($figures | to_entries[] | select(.value.state == "not recoverable") | {figure: .key, reason: .value.reason}),
             ($sessions[] | .figures[] | select(.state == "not recoverable") | {figure: "sessions", reason}),
             (if $worker[0].reason != null then {figure: "tokens.worker", reason: $worker[0].reason} else empty end),
             (if $nested[0].reason != null then {figure: "tokens.nested", reason: $nested[0].reason} else empty end)
           ] | reduce .[] as $m ([]; if index([$m]) == null then . + [$m] else . end)) as $missing
        | {schema: "unit-cost/1", key: $key, captured_at: $now, topic: $topic,
           record: $a.record, unit: $unit, milestone: ($a.milestone | del(.reason)),
           plan_shape: ($p | del(.reason)), pulls: $pulls_out, dispatch: ($d | del(.reason)),
           "niwa.dispatch.id": $niwa[0].v,
           figures: ($figures | map_values(del(.reason))),
           sessions: ($sessions | map(.figures |= map_values(del(.reason)))),
           tokens: {worker: ($worker[0] | del(.reason)), nested: ($nested[0] | del(.reason))},
           complete: ($missing | length == 0), missing: $missing}' >"$WD/entry.json"
}

# The posted copy: the object, or, past SIZE_LIMIT bytes, the object without
# the per-session states maps, which the archive copy keeps.
uc_posted() {
    local n
    n=$(wc -c <"$WD/entry.json" | tr -d ' ')
    if [ "$n" -gt "$SIZE_LIMIT" ]; then
        jq -c '.sessions |= map(.states = null)
            | .missing += [{figure: "sessions.states", reason: "entry size"}] | .complete = false' "$WD/entry.json" >"$WD/posted.json"
    else
        cp "$WD/entry.json" "$WD/posted.json"
    fi
}

# The comment text: one summary line, a blank line, and the posted object in
# one fenced json block.
uc_text() {
    jq -r '
        "Cost of \(.topic) (\(.key)): \(.sessions | length) sessions, "
        + (if .tokens.worker.state == "measured" then "\(.tokens.worker.output) output tokens" else "worker output tokens not recoverable" end)
        + ", dispatch to merge "
        + (if .figures.dispatch_to_merge_min.state == "measured"
           then (.figures.dispatch_to_merge_min.value | if . == floor then "\(.).0" else "\(.)" end) + " min." else "not recoverable." end)' "$WD/posted.json"
    printf '\n```json\n'
    cat "$WD/posted.json"
    printf '```\n'
}

# ---------------------------------------------------------------------------

if [ "$MODE" = compute ]; then
    uc_compute || { say "the entry could not be computed"; exit 1; }
    cat "$WD/entry.json"
    exit 0
fi

# capture: the record's facts and the Holdings row, while the row is there.
RECW="" ROW_OK=0
B=$(uc_bound "$FETCH_SECS")
if [ "$B" -le 0 ]; then
    RECW="time limit"
elif uc_run "$B" "$WD/facts.json" bash "$DC_COORD_LOG" run-facts --session "$SESSION" \
    && uc_jq -e 'type == "object"' "$WD/facts.json" >/dev/null; then
    B=$(uc_bound "$FETCH_SECS")
    if [ "$B" -le 0 ]; then
        jq -c '. + {unit: null, unit_reason: "time limit"}' "$WD/facts.json" >"$WD/unit.json"
    else
        uc_run "$B" "$WD/row.json" bash "$DC_RECORD_HOLDING" --read --topic "$TOPIC" --session "$SESSION"
        case $? in
            0) ROW_OK=1
                uc_jq -c --slurpfile r "$WD/row.json" '. + {unit: ($r[0].unit // null)}' "$WD/facts.json" >"$WD/unit.json" \
                || jq -c '. + {unit: null, unit_reason: "invalid input"}' "$WD/facts.json" >"$WD/unit.json" ;;
            1) jq -c '. + {unit: null, unit_reason: "no source"}' "$WD/facts.json" >"$WD/unit.json" ;;
            *) jq -c '. + {unit: null, unit_reason: "read failed"}' "$WD/facts.json" >"$WD/unit.json" ;;
        esac
    fi
else
    RECW="read failed"
fi
[ -z "$RECW" ] || jq -n -c --arg r "$RECW" '{unit_reason: $r}' >"$WD/unit.json"

# Where the entry goes: on the item it is about
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 2): the
# holding's pull request (its Pull request cell, else the first of the sealed
# verdict's), else the Unit's issue (`#n` on the host, or `owner/repo#n`), else
# nowhere, the entry kept in the session.
ON=none
RE_ITEM='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$'
[ "$ROW_OK" = 1 ] && ON=$(uc_jq -r -L "$HERE" 'include "record-codec"; .pull_request // "" | pr_link | "\(.repo)#\(.number)"' "$WD/row.json")
[[ $ON =~ $RE_ITEM ]] || ON=$(awk -v re="$RE_ITEM" '$1 ~ re { print $1; exit }' "$PRS_FILE")
if ! [[ $ON =~ $RE_ITEM ]]; then
    ON=none
    U=$(uc_jq -r '.unit // "" | if type == "string" then split(": ")[0] else "" end' "$WD/unit.json")
    H=$(uc_jq -r '.repo // ""' "$WD/unit.json")
    if [[ $U =~ ^#[1-9][0-9]*$ ]] && repo_ok "$H"; then ON="$H$U"
    elif [[ $U =~ $RE_ITEM ]]; then ON=$U
    fi
fi

uc_compute || { say "the entry could not be computed"; exit 1; }

# The archive's copy, renamed into place: a symlink at the name is removed,
# never followed, and a directory there is left alone.
if [ -d "$ARCH/unit-cost.json" ] && [ ! -L "$ARCH/unit-cost.json" ]; then
    say "unit-cost.json in the archive is a directory; no archive copy"
elif TMPF=$(mktemp "$ARCH/.unit-cost.json.XXXXXX" 2>/dev/null); then
    if cp "$WD/entry.json" "$TMPF" 2>/dev/null; then
        [ -L "$ARCH/unit-cost.json" ] && rm -f "$ARCH/unit-cost.json"
        mv -f "$TMPF" "$ARCH/unit-cost.json" 2>/dev/null || { rm -f "$TMPF"; say "the archive copy could not be written"; }
    else
        rm -f "$TMPF"
        say "the archive copy could not be written"
    fi
else
    say "the archive copy could not be written"
fi

# One entry per key: a `cost` entry already carrying it ends the capture.
# The list is a read, so its bound comes out of the budget too: every read
# together stays inside UNIT_COST_BUDGET_SECS (90), and the post's own bound
# (25) on top keeps the whole capture inside the pass's 120.
B=$(uc_bound "$LIST_SECS")
if [ "$B" -gt 0 ] && uc_run "$B" "$WD/entries.json" bash "$HERE/record-append.sh" --session "$SESSION" --list; then
    if uc_jq -e --arg k "$KEY" '
        [.[] | select(.kind == "cost") | (.text // "" | if type == "string" then . else "" end)
         | (capture("```json\n(?<j>[^\n]*)\n```") // empty) | .j | (try fromjson catch null)
         | select(type == "object") | .key] | index([$k]) != null' "$WD/entries.json" >/dev/null; then
        say "the record already holds this unit's cost entry"
        exit 0
    fi
fi

uc_posted || { say "the entry text could not be written"; exit 1; }
uc_text >"$WD/text" || { say "the entry text could not be written"; exit 1; }
set -- --on "$ON"
uc_run "$POST_SECS" "$WD/posted" bash "$HERE/record-append.sh" --session "$SESSION" --kind cost --text-file "$WD/text" "$@"
RC=$?
if [ "$RC" = 0 ]; then
    case "$ON" in
        none) say "kept the cost entry in the session: the unit has no pull request or issue, so it is posted nowhere" ;;
        *) say "posted the cost entry on $ON" ;;
    esac
    exit 0
fi
case "$RC" in
    124) say "the post did not finish in time" ;;
    *) say "the post failed (record-append exit $RC)" ;;
esac
exit 1
