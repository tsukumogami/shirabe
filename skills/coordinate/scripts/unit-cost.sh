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
#       J holds the record's facts, {scope, name, repo, ref, unit}, or
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
#       the unit.
#   unit-cost.sh gh-check <gh arguments...>
#       Runs nothing: 0 when the capture's GitHub wrapper would make that
#       call, 1 when it refuses it. The suite's view of the wrapper.
#
# The object holds, in this order: schema, key, captured_at, topic, record,
# unit, milestone, plan_shape, pulls, dispatch, figures, sessions, tokens,
# complete and missing. A figure is {value, raw, state, source}; state is
# `measured`, `bound`, `not recoverable` or `not applicable`, and every figure
# not taken is listed in `missing` with a reason from a closed list: `no
# source`, `read failed`, `time limit`, `entry size`, `invalid input`. This
# version takes the attribution (record, unit, milestone, plan shape, pull
# requests), dispatch and both token rows; the time, review and GitHub
# figures and the per-session figures are listed as `no source` until they
# are measured.
#
# Plan shape, first match wins, over the archived sessions in byte order of
# their names: a `deliver` session's context key plan_execution_mode; an
# `execute` session's template file (execute-coordinated.md is coordinated,
# execute.md single-pr); a `work-on` session's entry `mode` (plan_backed is
# multi-pr, issue_backed and free_form are issue); else none. A session that
# matches but whose value can't be read makes the shape `not recoverable`.
#
# Milestone: the Unit cell cut at its first `: `. An issue reference (`#n`,
# `owner/repo#n`) or a discipline record gives `none`; a roadmap record gives
# {roadmap: ROADMAP-<name>, tag}. A Unit outside the safety pattern is null,
# its milestone `not recoverable` (`invalid input`).
#
# Dispatch: the created_at of the unit's koto request, found through the
# archived sessions' request-leg.toml files: of the requests they name, the
# earliest one no archived session asked for (the coordinator's own); else
# the job's createdAt; else `not recoverable`.
#
# Tokens: per message id (assistant lines with a string id), the largest
# value of each class, summed. `worker` is the job's own transcript and its
# subagents/; `nested` is every other transcript in the archive. A line that
# isn't JSON makes its row `not recoverable` (`invalid input`).
#
# Untrusted input: the archive and GitHub fields are read only through jq
# filters that keep numbers, ids, timestamps and closed-set words; every kept
# string is matched to its shape first. Diagnostics are fixed strings.
#
# Every external command (each GitHub read, the record scripts, the post)
# runs under dc_with_deadline in its own process group, which the deadline
# stops whole, so no grandchild outlives this script. The reads share a
# budget; once it is spent, what is not yet taken is `time limit` and the
# capture goes straight to writing and posting what it has.
#
# Exit codes: 0 printed (compute), posted or already posted (capture), or
# admitted (gh-check); 1 not posted, or refused (gh-check); 64 usage; 65 the
# archive's name is not a capture key for the topic.
#
# Environment: GH names gh (tests); KOTO_REQUESTS (default
# $HOME/.koto/requests); UNIT_COST_FETCH_SECS (each GitHub read's bound,
# default 8, the pass's own); UNIT_COST_BUDGET_SECS (the reads' budget,
# default 90); UNIT_COST_LIST_SECS (the entry list's bound, default 15);
# UNIT_COST_POST_SECS (the post's bound, default 25); UNIT_COST_NOW (a fixed
# captured_at, tests). bash 3.2.
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
SECONDS=0

usage() { sed -n '/^# Usage:/,/^# The object holds/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

RE_REPO='^[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*$'
RE_TS='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z$'
RE_SHA='^[0-9a-f]{40}$'
RE_NUM='^[1-9][0-9]{0,9}$'

# A repository: the pattern, no `..`, and neither part starting with `-`, so
# it can never read as an option.
repo_ok() { [[ $1 =~ $RE_REPO ]] && case "$1" in *..* | -* | */-*) return 1 ;; esac; }

# ---------------------------------------------------------------------------
# Bounded commands.

# uc_tree <command...>: run the command in a process group of its own and
# wait for it; a TERM (dc_with_deadline's, or this script's own trap) stops
# the whole group, so a hung gh under record-append.sh dies with it. The trap
# kills and returns; it never waits on a child.
# shellcheck disable=SC2329 # run through dc_with_deadline's "$@"
uc_tree() {
    local p
    set -m 2>/dev/null
    "$@" &
    p=$!
    set +m 2>/dev/null
    trap 'kill -TERM -- "-$p" >/dev/null 2>&1; kill -TERM "$p" >/dev/null 2>&1; exit 143' TERM
    wait "$p"
}

# uc_run <secs> <out-file> <command...>: the command bounded, its stdout in
# the file (never a pipe, so nothing left running holds a caller open), its
# stderr discarded and its stdin empty. Returns its status, 124 on timeout.
uc_run() {
    local secs=$1 out=$2
    shift 2
    dc_with_deadline "$secs" uc_tree "$@" </dev/null >"$out" 2>/dev/null
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
                        printf '%s' "$2" | grep -Eq '^[A-Za-z0-9._/+-]{1,200}$' || return 1 ;;
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
            printf '%s' "$4" | grep -Eq '^repos/[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*(/[A-Za-z0-9_.,=&?/-]*)?$' || return 1
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
# each one's process group through uc_tree's own trap, and leaves.
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
# The pieces. Each writes one JSON file in $WD; `reason` fields name why a
# piece was not taken, and the assembly turns them into `missing`.

# Sessions: one line per archived session directory holding its state log,
# in byte order of the names. Names stay here: they carry a plan's issue
# titles, so the entry never holds one.
uc_sessions() {
    local d name f plan hasplan req i=0
    : >"$WD/sessions.jsonl"
    : >"$WD/session-names"
    for d in "$ARCH"/koto/*; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        name=${d##*/}
        f="$d/koto-$name.state.jsonl"
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        i=$((i + 1))
        hasplan=false plan=""
        if [ -f "$d/ctx/plan_execution_mode" ] && [ ! -L "$d/ctx/plan_execution_mode" ]; then
            hasplan=true
            plan=$(head -c 64 "$d/ctx/plan_execution_mode" | tr -d ' \t\r\n')
        fi
        req=""
        if [ -f "$d/request-leg.toml" ] && [ ! -L "$d/request-leg.toml" ]; then
            req=$(sed -n 's/^request_id[[:space:]]*=[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "$d/request-leg.toml" | head -n 1)
            [[ $req =~ $DC_RE_REQ ]] || req=""
        fi
        printf '%s\n' "$name" >>"$WD/session-names"
        jq -R -n -c --argjson i "$i" --arg plan "$plan" --argjson hasplan "$hasplan" --arg req "$req" '
            [inputs | select(test("^[[:space:]]*$") | not) | (try [fromjson] catch null) | select(. != null) | .[0]] as $e
            | ($e[0] // {}) as $h
            | (if ($h | type) == "object" then $h else {} end) as $h
            | ($h.template_name // "" | if type == "string" then . else "" end) as $tn
            | {index: $i,
               template: (if $tn == "deliver" or $tn == "scope" or $tn == "work-on" then $tn
                          elif $tn == "execute" or $tn == "execute-coordinated" then "execute"
                          else "other" end),
               source_file: ($h.template_source_file // "" | if type == "string" then . else "" end),
               mode: ([$e[] | select(type == "object" and .type == "evidence_submitted"
                                     and (.payload | type) == "object" and .payload.state == "entry"
                                     and (.payload.fields | type) == "object" and (.payload.fields | has("mode")))
                       | .payload.fields.mode][0]),
               plan: (if $hasplan then $plan else null end),
               request: (if $req == "" then null else $req end)}' "$f" 2>/dev/null >>"$WD/sessions.jsonl" \
            || printf '{"index":%s,"template":"other","source_file":"","mode":null,"plan":null,"request":null}\n' "$i" >>"$WD/sessions.jsonl"
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
        | if $d != null then
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

uc_dispatch() {
    local id f out
    : >"$WD/requests.jsonl"
    for id in $(jq -r '.[] | .request // empty' "$WD/sessions.json" | sort -u); do
        [[ $id =~ $DC_RE_REQ ]] || continue
        f="$KOTO_REQUESTS/$id/request.jsonl"
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        head -n 1 "$f" | jq -R -c '(try fromjson catch null) | select(type == "object")
            | {created_at: (.created_at // "" | if type == "string" then . else "" end),
               by: (.requested_by // "" | if type == "string" then . else "" end)}' 2>/dev/null >>"$WD/requests.jsonl"
    done
    out=""
    if [ -f "$ARCH/job/state.json" ] && [ ! -L "$ARCH/job/state.json" ]; then
        out=$(jq -r '.createdAt // "" | if type == "string" then . else "" end' "$ARCH/job/state.json" 2>/dev/null) || out=""
    fi
    [[ $out =~ $RE_TS ]] || out=""
    jq -s -c --rawfile names "$WD/session-names" --arg job "$out" --arg re "$RE_TS" '
        ($names | split("\n") | map(select(. != ""))) as $n
        | [.[] | select((.created_at | test($re)) and ((.by as $b | $n | index([$b])) == null)) | .created_at]
        | sort | .[0] as $r
        | if $r != null then {value: $r, state: "measured", source: "koto-request"}
          elif $job != "" then {value: $job, state: "measured", source: "job-state"}
          else {value: null, state: "not recoverable", source: "koto-request", reason: "no source"} end' \
        "$WD/requests.jsonl" >"$WD/dispatch.json"
}

# uc_token_row <file-list> <out>: the row over the transcripts listed.
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
                     and ($o.message.id | type) == "string" then
                      ($o.message.usage | if type == "object" then . else {} end) as $u
                      | .m[$o.message.id] |= ((. // {i: 0, o: 0, cc: 0, cr: 0})
                          | .i = ([.i, n($u.input_tokens)] | max)
                          | .o = ([.o, n($u.output_tokens)] | max)
                          | .cc = ([.cc, n($u.cache_creation_input_tokens)] | max)
                          | .cr = ([.cr, n($u.cache_read_input_tokens)] | max))
                  else . end
             end)
        | {bad, messages: (.m | length), input: ([.m[].i] | add // 0), output: ([.m[].o] | add // 0),
           cache_creation: ([.m[].cc] | add // 0), cache_read: ([.m[].cr] | add // 0)}' >"$2" 2>/dev/null
}

uc_tokens() {
    local sid="" tr="$ARCH/transcript" row reason
    : >"$WD/worker.list"
    : >"$WD/nested.list"
    if [ -f "$ARCH/job/state.json" ] && [ ! -L "$ARCH/job/state.json" ]; then
        sid=$(jq -r '.sessionId // "" | if type == "string" then . else "" end' "$ARCH/job/state.json" 2>/dev/null) || sid=""
    fi
    printf '%s' "$sid" | grep -Eq '^[0-9a-f][0-9a-f-]{7,63}$' || sid=""
    if [ -d "$tr" ] && [ ! -L "$tr" ]; then
        if [ -n "$sid" ] && [ -f "$tr/$sid.jsonl" ] && [ ! -L "$tr/$sid.jsonl" ]; then
            printf '%s\n' "$tr/$sid.jsonl" >"$WD/worker.list"
            if [ -d "$tr/$sid/subagents" ] && [ ! -L "$tr/$sid" ] && [ ! -L "$tr/$sid/subagents" ]; then
                find "$tr/$sid/subagents" -type f -name '*.jsonl' 2>/dev/null | sort >>"$WD/worker.list"
            fi
        fi
        find "$tr" -type f -name '*.jsonl' 2>/dev/null | sort | grep -vxF -f "$WD/worker.list" >"$WD/nested.list"
    fi
    for row in worker nested; do
        reason=""
        if [ "$(uc_left)" -le 0 ]; then
            reason="time limit"
        elif [ ! -d "$tr" ] || [ -L "$tr" ] || { [ "$row" = worker ] && [ ! -s "$WD/worker.list" ]; }; then
            reason="no source"
        elif ! uc_token_row "$WD/$row.list" "$WD/$row.raw" || [ ! -s "$WD/$row.raw" ]; then
            reason="read failed"
        elif jq -e '.bad' "$WD/$row.raw" >/dev/null; then
            reason="invalid input"
        fi
        if [ -n "$reason" ]; then
            jq -n -c --arg r "$reason" '{messages: null, input: null, output: null, cache_creation: null, cache_read: null,
                state: "not recoverable", source: "transcripts", reason: $r}' >"$WD/$row.json"
        else
            jq -c 'del(.bad) + {state: "measured", source: "transcripts"}' "$WD/$row.raw" >"$WD/$row.json"
        fi
    done
}

uc_pulls() {
    local ref sha rest repo n rc at why
    : >"$WD/pulls.jsonl"
    : >"$WD/pull-reasons.jsonl"
    while read -r ref sha rest; do
        [ -n "$ref" ] || continue
        repo=${ref%#*} n=${ref##*#}
        if [ -n "$rest" ] || [ "$repo" = "$ref" ] || ! repo_ok "$repo" || ! [[ $n =~ $RE_NUM ]] || ! [[ $sha =~ $RE_SHA ]]; then
            printf '{"figure":"pulls","reason":"invalid input"}\n' >>"$WD/pull-reasons.jsonl"
            continue
        fi
        at="" why=""
        uc_gh "$WD/pr.json" pr view "$n" --repo "$repo" --json mergedAt
        rc=$?
        if [ "$rc" = 0 ]; then
            at=$(jq -r '.mergedAt // "" | if type == "string" then . else "" end' "$WD/pr.json" 2>/dev/null) || at=""
            [[ $at =~ $RE_TS ]] || { at=""; why="invalid input"; }
        else
            why=$(read_reason "$rc")
        fi
        [ -z "$why" ] || jq -n -c --arg r "$why" '{figure: "pulls.merged_at", reason: $r}' >>"$WD/pull-reasons.jsonl"
        jq -n -c --arg r "$repo" --argjson n "$n" --arg s "$sha" --arg at "$at" \
            '{repo: $r, number: $n, merge_commit: $s, merged_at: (if $at == "" then null else $at end)}' >>"$WD/pulls.jsonl"
    done <"$WD/prs"
    # One line per figure and reason, however many pull requests share it.
    jq -s -c 'unique' "$WD/pull-reasons.jsonl" >"$WD/pull-reasons.json"
    jq -s -c '.' "$WD/pulls.jsonl" >"$WD/pulls.json"
}

# The record, the Unit and the milestone, from the unit file.
uc_attribution() {
    [ -s "$WD/unit.json" ] || echo '{"unit_reason": "no source"}' >"$WD/unit.json"
    jq -c --arg re_repo "$RE_REPO" '
        def isstr: type == "string";
        (if type == "object" then . else {} end) as $j
        | ($j.unit_reason | if . == "read failed" or . == "time limit" or . == "no source" or . == "invalid input" then . else "no source" end) as $why
        | (if ($j.scope == "roadmap" or $j.scope == "discipline")
              and ($j.name | isstr and test("^[A-Za-z0-9._-]{1,100}$"))
              and ($j.repo | isstr and test($re_repo) and (contains("..") | not))
              and ($j.ref | tostring | test("^[1-9][0-9]{0,9}$"))
           then {scope: $j.scope, name: $j.name, repo: $j.repo, ref: ($j.ref | tostring)}
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
    ' "$WD/unit.json" >"$WD/attribution.json" 2>/dev/null \
        || jq -n -c '{record: null, record_reason: "invalid input", unit: null, unit_reason: null,
                      milestone: {value: null, state: "not recoverable", source: "record", reason: "invalid input"}}' >"$WD/attribution.json"
}

uc_compute() {
    local now
    now=${UNIT_COST_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
    [[ $now =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    uc_sessions
    uc_plan_shape
    uc_dispatch
    uc_attribution
    uc_pulls
    uc_tokens
    jq -n -c --arg key "$KEY" --arg now "$now" --arg topic "$TOPIC" \
        --slurpfile att "$WD/attribution.json" --slurpfile shape "$WD/shape.json" \
        --slurpfile pulls "$WD/pulls.json" --slurpfile preasons "$WD/pull-reasons.json" \
        --slurpfile disp "$WD/dispatch.json" --slurpfile sess "$WD/sessions.json" \
        --slurpfile worker "$WD/worker.json" --slurpfile nested "$WD/nested.json" '
        def nr($src): {value: null, raw: null, state: "not recoverable", source: $src};
        $att[0] as $a | $shape[0] as $p | $disp[0] as $d
        | (if $p.state == "measured" and ($p.value == "issue" or $p.value == "none")
           then {value: null, raw: null, state: "not applicable", source: "derived"} else nr("derived") end) as $mpu
        | {dispatch_to_green_min: nr("derived"), dispatch_to_merge_min: nr("derived"),
           writing_code_min: nr("koto-state"), review_min: nr("koto-state"),
           outside_share_pct: nr("derived"), review_share_pct: nr("derived"),
           panel_rounds: nr("verdict-ledger"), failing_heads: nr("github-runs"),
           sessions_without_done: nr("koto-state"), summed_session_span_min: nr("koto-state"),
           minutes_per_unit: $mpu} as $figures
        | [$sess[0][] | {index, template, unit_session: (.template == "work-on"), done: null, span_s: null, states: null,
             figures: {span_min: nr("koto-state"), impl_share_pct: nr("koto-state"), review_share_pct: nr("koto-state")}}] as $sessions
        | ([ (if $a.record == null then {figure: "record", reason: $a.record_reason} else empty end),
             (if $a.unit_reason != null then {figure: "unit", reason: $a.unit_reason} else empty end),
             (if $a.milestone.reason != null then {figure: "milestone", reason: $a.milestone.reason} else empty end),
             (if $p.reason != null then {figure: "plan_shape", reason: $p.reason} else empty end),
             $preasons[0][],
             (if $d.reason != null then {figure: "dispatch", reason: $d.reason} else empty end),
             ($figures | to_entries[] | select(.value.state == "not recoverable") | {figure: .key, reason: "no source"}),
             (if ($sessions | length) > 0 then {figure: "sessions", reason: "no source"} else empty end),
             (if $worker[0].reason != null then {figure: "tokens.worker", reason: $worker[0].reason} else empty end),
             (if $nested[0].reason != null then {figure: "tokens.nested", reason: $nested[0].reason} else empty end)
           ] | reduce .[] as $m ([]; if index([$m]) == null then . + [$m] else . end)) as $missing
        | {schema: "unit-cost/1", key: $key, captured_at: $now, topic: $topic,
           record: $a.record, unit: $a.unit, milestone: ($a.milestone | del(.reason)),
           plan_shape: ($p | del(.reason)), pulls: $pulls[0], dispatch: ($d | del(.reason)),
           figures: $figures, sessions: $sessions,
           tokens: {worker: ($worker[0] | del(.reason)), nested: ($nested[0] | del(.reason))},
           complete: ($missing | length == 0), missing: $missing}' >"$WD/entry.json"
}

# The comment text: one summary line, a blank line, and the object in one
# fenced json block.
uc_text() {
    jq -r '
        "Cost of \(.topic) (\(.key)): \(.sessions | length) sessions, "
        + (if .tokens.worker.state == "measured" then "\(.tokens.worker.output) output tokens" else "worker output tokens not recoverable" end)
        + ", dispatch to merge "
        + (if .figures.dispatch_to_merge_min.state == "measured" then "\(.figures.dispatch_to_merge_min.value) min." else "not recoverable." end)' "$WD/entry.json"
    printf '\n```json\n'
    cat "$WD/entry.json"
    printf '```\n'
}

# ---------------------------------------------------------------------------

if [ "$MODE" = compute ]; then
    uc_compute || { say "the entry could not be computed"; exit 1; }
    cat "$WD/entry.json"
    exit 0
fi

# capture: the record's facts and the Holdings row, while the row is there.
RECW=""
B=$(uc_bound "$FETCH_SECS")
if [ "$B" -le 0 ]; then
    RECW="time limit"
elif uc_run "$B" "$WD/facts.json" bash "$DC_COORD_LOG" run-facts --session "$SESSION" \
    && jq -e 'type == "object"' "$WD/facts.json" >/dev/null 2>&1; then
    B=$(uc_bound "$FETCH_SECS")
    if [ "$B" -le 0 ]; then
        jq -c '. + {unit: null, unit_reason: "time limit"}' "$WD/facts.json" >"$WD/unit.json"
    else
        uc_run "$B" "$WD/row.json" bash "$DC_RECORD_HOLDING" --read --topic "$TOPIC" --session "$SESSION"
        case $? in
            0) jq -c --slurpfile r "$WD/row.json" '. + {unit: ($r[0].unit // null)}' "$WD/facts.json" >"$WD/unit.json" 2>/dev/null \
                || jq -c '. + {unit: null, unit_reason: "invalid input"}' "$WD/facts.json" >"$WD/unit.json" ;;
            1) jq -c '. + {unit: null, unit_reason: "no source"}' "$WD/facts.json" >"$WD/unit.json" ;;
            *) jq -c '. + {unit: null, unit_reason: "read failed"}' "$WD/facts.json" >"$WD/unit.json" ;;
        esac
    fi
else
    RECW="read failed"
fi
[ -z "$RECW" ] || jq -n -c --arg r "$RECW" '{unit_reason: $r}' >"$WD/unit.json"

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
B=$(uc_bound "$LIST_SECS")
if [ "$B" -gt 0 ] && uc_run "$B" "$WD/entries.json" bash "$HERE/record-append.sh" --session "$SESSION" --list; then
    if jq -e --arg k "$KEY" '
        [.[] | select(.kind == "cost") | (.text // "" | if type == "string" then . else "" end)
         | (capture("```json\n(?<j>[^\n]*)\n```") // empty) | .j | (try fromjson catch null)
         | select(type == "object") | .key] | index([$k]) != null' "$WD/entries.json" >/dev/null 2>&1; then
        say "the record already holds this unit's cost entry"
        exit 0
    fi
fi

uc_text >"$WD/text" || { say "the entry text could not be written"; exit 1; }
uc_run "$POST_SECS" "$WD/posted" bash "$HERE/record-append.sh" --session "$SESSION" --kind cost --text-file "$WD/text"
RC=$?
if [ "$RC" = 0 ]; then
    say "posted the cost entry"
    exit 0
fi
case "$RC" in
    124) say "the post did not finish in time" ;;
    *) say "the post failed (record-append exit $RC)" ;;
esac
exit 1
