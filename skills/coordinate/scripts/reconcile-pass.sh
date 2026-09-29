#!/usr/bin/env bash
# reconcile-pass.sh -- the reconcile_pass state's action: one bounded pass of
# the full reconcile, printing exactly one line for the engine to capture.
#
# koto runs this on entry to reconcile_pass and on every later tick without
# evidence. Each pass advances a work file scoped to the state's current
# visit: it reads the record once per visit (reconcile-read.sh), then runs the
# re-checks (reconcile-check.sh), at most four at once, launching none after
# 20 seconds and giving each a deadline clipped to the time left before the
# 24-second mark, which leaves the report and its seal the rest of koto's
# 30-second cap. When every re-check is done it builds the report
# (reconcile-report.sh), writes it to context, and prints the sealed line.
#
# Output, one line on stdout (every child's stdout goes to stderr):
#   pending:<seq>:<n>:<sha256 of the work file>   n re-checks left; tick again
#   blocked:<case>                                 none | unreadable
#   reconciled <sha256 of report.json> sealed:<seq>:<sha256>
# The last is sealed with the record feature's coord-log.sh for this state's
# visit <seq>. The state's gates hold the workflow until it appears and the
# stored report matches it. Exit 0 for all three; any other exit is an action
# failure, which koto reports without evaluating the gates.
#
# Context keys written (all under reconcile/): progress (while pending),
# refusal (when blocked), report.json, report.md, reasoning.md (when the
# predecessor left reasoning). progress and refusal are cleared at the start
# of every pass; a new visit removes the rest.
#
# The pass writes the record in one case only: a holding left `dispatching`
# whose worker the listing finds (and whose leg, when it has one, is bound or
# resolved) is rewritten `dispatched` by reconcile-settle.sh, launched like a
# re-check once those facts are in, and reported under "Changed since then".
# A deferral's carry is judged against the chain start (coord-log.sh
# chain-start), so a restart doesn't re-decide what the run it replaced
# carried.
#
# The work file, <session-dir>/coordinate-reconcile/visit.json, is trusted
# only when its sha256 is the one this state's last engine-logged output
# named; otherwise (edited, or left by a killed pass) the visit's reads start
# again. A worker not found in the listing is read again no sooner than 30
# seconds after the first read: in the same pass when that fits before the
# 20-second cutoff, otherwise in a later pass. A teardown is confirmed only by
# two listing reads 30 seconds apart.
#
# Usage:
#   reconcile-pass.sh --session S --session-dir D
# Tests call
#   reconcile-pass.sh --test-entry --clock-file F --session S --session-dir D
# which takes the time from F (epoch seconds), where a wait adds to F instead
# of sleeping. The template never passes it.
#
# Like every check, the pass runs in the environment of the `koto next` call
# that triggered it (koto#261; see SKILL.md's Known Limitations).
#
# Requires: bash 3.2+, jq, gh, git, koto, niwa, pkill, and a sha256 tool.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CLOCK_FILE="" TEST_ENTRY=0
[ "${1-}" = --test-entry ] && { shift; TEST_ENTRY=1; }

PROG=reconcile-pass
# The bash running this script runs every script it starts.
RUNBASH=("$BASH")
# shellcheck source=reconcile-deps.sh
. "$HERE/reconcile-deps.sh"

# Only the final line reaches stdout.
exec 3>&1 1>&2

STATE=reconcile_pass
CUTOFF=20
READS_END=24
PARALLEL=4

SESSION="" SDIR=""
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || { echo "reconcile-pass: usage" >&2; exit 64; }
    case "$1" in
        --session) SESSION=$2 ;;
        --session-dir) SDIR=$2 ;;
        --clock-file) [ "$TEST_ENTRY" = 1 ] || { echo "reconcile-pass: --clock-file is for the test entry only" >&2; exit 64; }; CLOCK_FILE=$2 ;;
        *) echo "reconcile-pass: usage" >&2; exit 64 ;;
    esac
    shift 2
done
[[ $SESSION =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]] || { echo "reconcile-pass: invalid session name" >&2; exit 64; }
[ -d "$SDIR" ] && [ "$(basename "$SDIR")" = "$SESSION" ] || { echo "reconcile-pass: the session directory does not name this session" >&2; exit 64; }

# The test entry's clock file is shared with the test's stand-in re-checks,
# which advance it while this pass reads it. Both sides write it whole (a
# temp file of the writer's own, renamed into place), and a read that still
# comes back empty is retried rather than taken for a time: an empty `t`
# reaches jq as `--argjson t ""`. `now` runs in `$(...)`, where `die` ends only
# the subshell, so every caller takes it in a plain assignment that exits on
# its status, never inside arithmetic, where a failed read turns into a
# wrong number instead.
now() {
    [ -n "$CLOCK_FILE" ] || { date +%s; return; }
    local v i=0
    while :; do
        v=$(cat "$CLOCK_FILE" 2>/dev/null)
        [ -n "$v" ] && { printf '%s\n' "$v"; return; }
        i=$((i + 1)); [ "$i" -ge 50 ] && die "the test clock $CLOCK_FILE read empty"
        sleep 0.02
    done
}
# Under the test entry the wait advances the clock without the stand-ins'
# lock: its one caller waits only when no re-check is running, so nothing
# else writes the clock meanwhile.
wait_secs() {
    if [ -n "$CLOCK_FILE" ]; then
        local c tmp
        c=$(now) || exit 1
        tmp=$(mktemp "$CLOCK_FILE.XXXXXX") || die "can't write the test clock"
        echo $(( c + $1 )) > "$tmp" && mv "$tmp" "$CLOCK_FILE" || die "can't write the test clock"
    else sleep "$1"; fi
}
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { printf '%s\n' "$1" >&3; exit 0; }
die() { echo "reconcile-pass: $1" >&2; exit 1; }

ctx_put() { koto context add "$SESSION" "$1" --from-file "$2" >/dev/null || die "koto context add $1 failed"; }
ctx_rm() { koto context remove "$SESSION" "$1" >/dev/null 2>&1 || true; }
ctx_rm_all() { local k; for k in progress refusal report.json report.md reasoning.md; do ctx_rm "reconcile/$k"; done; }

T0=$(now) || exit 1
W="$SDIR/coordinate-reconcile"
WORK="$W/visit.json"
mkdir -p "$W" || die "can't create the work directory"
T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-pass.XXXXXX") || die "no temp directory"
trap 'rm -rf "$T"' EXIT
# This pass's reads and deferral rows: its own directory, gone when it ends.
R="$T/reads"
mkdir -p "$R" || die "can't create the reads directory"

ctx_rm reconcile/refusal
ctx_rm reconcile/progress

# The visit: the sequence number of the latest entry into this state.
PROBE=$("${RUNBASH[@]}" "$RD_COORD_LOG" seal --session "$SESSION" --state "$STATE" --token visit) \
    || die "the session log has no entry into $STATE"
[[ $PROBE =~ ^visit\ sealed:([0-9]+): ]] || die "unreadable seal from coord-log.sh"
VISIT=${BASH_REMATCH[1]}

# discard -- drop the work file and every reconcile/ key.
discard() { rm -rf "$WORK" "$W/report.json" "$W/report.md" "$W/reasoning.md" "$W/reads" "$W"/d*.row.json; WJ=""; ctx_rm_all; }

# The work document, held in memory for the whole pass. It is read from the
# file once, after its hash is checked against the last logged pass, and the
# file is only ever written after that, so an edit made while a pass runs is
# overwritten rather than trusted.
WJ=""
# save JSON -- keep JSON as the work document and replace the file atomically.
# Callers build JSON in `$(jq ...)` and check jq's status before calling this:
# `save "$(jq ...)"` would lose it and store jq's empty output as the work
# file. An empty document is refused here as well.
save() {
    [ -n "$1" ] || die "refusing to write an empty work file"
    WJ=$1; printf '%s\n' "$WJ" > "$WORK.tmp" && mv "$WORK.tmp" "$WORK" || die "can't write the work file"
}
wj() { printf '%s\n' "$WJ" | jq "$@"; }

if [ -f "$WORK" ]; then
    WJ=$(cat "$WORK")
    WSHA=$(printf '%s\n' "$WJ" | rd_sha256)
    LAST=$("${RUNBASH[@]}" "$RD_COORD_LOG" capture --session "$SESSION" --name RECONCILE_SEAL 2>/dev/null) || LAST=""
    WV=$(wj -r '.visit // empty' 2>/dev/null)
    if [ "$WV" != "$VISIT" ]; then
        discard
    elif [[ $LAST =~ ^reconciled\ ([0-9a-f]{64})\ sealed:([0-9]+): ]] && [ "${BASH_REMATCH[2]}" = "$VISIT" ] \
         && [ -f "$W/report.json" ] && [ "$(rd_sha256 < "$W/report.json")" = "${BASH_REMATCH[1]}" ] \
         && [ "$(wj -r '.done // false')" = true ]; then
        # This visit is already sealed: put the sealed report back (the keys
        # may have been removed) and say the same line again.
        ctx_put reconcile/report.json "$W/report.json"
        ctx_put reconcile/report.md "$W/report.md"
        [ -f "$W/reasoning.md" ] && ctx_put reconcile/reasoning.md "$W/reasoning.md"
        say "$LAST"
    elif ! [[ $LAST =~ ^pending:$VISIT:[0-9]+:([0-9a-f]{64})$ ]] || [ "${BASH_REMATCH[1]}" != "$WSHA" ]; then
        # Edited since the last logged pass, or left by a pass that never
        # finished: its reads aren't trusted.
        discard
    fi
else
    discard
fi

# The record, once per visit.
if [ -z "$WJ" ]; then
    rm -f "$W/reasoning.md"
    REC=$(rd_deadline 12 "${RUNBASH[@]}" "$HERE/reconcile-read.sh" --session "$SESSION" --reasoning-out "$W/reasoning.md" 2>/dev/null 3>&-)
    RC=$?
    if [ "$RC" -ne 0 ]; then
        case "$RC" in
            3) CASE=none ;;
            *) CASE=unreadable ;;
        esac
        REASON=$(printf '%s' "$REC" | jq -r '.reason // empty' 2>/dev/null)
        [ "$RC" = 124 ] && REASON="reading the record timed out"
        [ -n "$REASON" ] || REASON="the record could not be read"
        printf 'case: %s\nreason: %s\n' "$CASE" "$REASON" > "$T/refusal"
        ctx_put reconcile/refusal "$T/refusal"
        say "blocked:$CASE"
    fi
    RUN_START=$("${RUNBASH[@]}" "$RD_COORD_LOG" run-start --session "$SESSION") || die "the run's start can't be read"
    # A deferral carried by a run this one restarted counts as disposed.
    CHAIN_START=$("${RUNBASH[@]}" "$RD_COORD_LOG" chain-start --session "$SESSION") || die "the run's chain start can't be read"
    # Where the scripts sit relative to the repository being worked on.
    PR_ROOT=$(cd "$HERE/../../.." && pwd -P)
    TOP=$(rd_git rev-parse --show-toplevel 2>/dev/null) && TOP=$(cd "$TOP" && pwd -P) || TOP=""
    PLACE=null
    if [ -n "$TOP" ]; then
        case "$PR_ROOT/" in "$TOP"/*) PLACE='"inside"' ;; *) PLACE='"outside"' ;; esac
    fi
    NEW=$(jq -c -n --argjson rec "$REC" --arg v "$VISIT" --arg rs "$RUN_START" --arg cs "$CHAIN_START" --argjson place "$PLACE" \
        '{visit: $v, record: $rec, run_start: $rs, chain_start: $cs, plugin_root: $place, facts: {}, done: false}') \
        || die "the record could not be stored"
    save "$NEW"
fi

# plan NOW -- the re-checks not yet done, one JSON object per line:
# {id, sub, args, natural, due}. natural is the read's own deadline; a read
# with due later than NOW waits.
plan() {
    wj -c --argjson now "$1" --arg w "$R" --arg session "$SESSION" '
        . as $work | .facts as $f | .record as $rec
        | def okf($id): (($f[$id].status // "") == "ok");
          def prnum: [(. // "") | capture("^\\[#(?<n>[0-9]+)\\]") | .n][0];
          def target: [(. // "") | capture("^(?:(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#(?<n>[0-9]+)$")][0];
          def holding_repo($n): [$rec.holdings[].row | select((.pull_request | prnum) == $n) | .repo][0];
        [ ($rec.holdings | to_entries[] | .key as $i | .value.row as $h | "h\($i)" as $p
            | ($h.pull_request | prnum) as $n
            | (if $n != null then
                 {id: "\($p).pr", sub: "pr", args: ["--repo", $h.repo, "--number", $n], natural: 8},
                 (if ($h.verified_head // "") != "" and okf("\($p).pr") then
                    {id: "\($p).board.v", sub: "board", args: ["--repo", $h.repo, "--sha", $h.verified_head, "--base", ($f["\($p).pr"].base // "")], natural: 26}
                  else empty end),
                 (if okf("\($p).pr") and $f["\($p).pr"].state == "OPEN" and ($f["\($p).pr"].head // "") != ""
                     and $f["\($p).pr"].head != ($h.verified_head // "") then
                    {id: "\($p).board.l", sub: "board", args: ["--repo", $h.repo, "--sha", $f["\($p).pr"].head, "--base", ($f["\($p).pr"].base // "")], natural: 26}
                  else empty end),
                 (if ($h.branch // "") != "" then {id: "\($p).branch", sub: "branch", args: ["--repo", $h.repo, "--branch", $h.branch], natural: 8} else empty end),
                 (if ($h.phase // "") == "scoping-ahead" then {id: "\($p).files", sub: "files", args: ["--repo", $h.repo, "--number", $n], natural: 8} else empty end)
               else
                 (if ($h.branch // "") != "" then {id: "\($p).appeared", sub: "appeared", args: ["--repo", $h.repo, "--branch", $h.branch], natural: 8} else empty end),
                 (if ($h.worker // "") != "" then
                    {id: "\($p).host1", sub: "host", args: ["--topic", $h.worker], natural: 8},
                    (if okf("\($p).host1") and $f["\($p).host1"].state == "missed" then
                       {id: "\($p).host2", sub: "host", args: ["--topic", $h.worker], natural: 8, due: ($f["\($p).host1"].t + 30)}
                     else empty end),
                    ([$f["\($p).host1"], $f["\($p).host2"]] | map(select(. != null and .status == "ok" and .state == "found")) | .[0]) as $found
                    | (if $found != null then {id: "\($p).inv", sub: "inventory", args: ["--path", $found.path], natural: 20} else empty end),
                      # A row left dispatching with its worker live (and its
                      # leg, when it has one, bound or resolved) is settled.
                      (if $found != null and ($h.dispatch_status // "") == "dispatching"
                          and ((($h.return_path // "") | startswith("leg ") | not)
                               or (okf("\($p).leg") and ($f["\($p).leg"].disposition | IN("bound", "resolved")))) then
                         {id: "\($p).settle", sub: "settle", args: ["--session", $session, "--topic", $h.worker, "--return-path", ($h.return_path // "")], natural: 20}
                       else empty end)
                  else empty end)
               end),
              (if (($h.return_path // "") | startswith("leg ")) then {id: "\($p).leg", sub: "leg", args: ["--return-path", $h.return_path], natural: 8} else empty end)),
          ($rec.side_effects | to_entries[] | .key as $j | .value.row as $s | "s\($j)" as $p
            | ($s.target | target) as $t
            | (($s.action // "") | ascii_downcase) as $a
            | (if $t == null then empty
               else ($t.r // holding_repo($t.n) // $rec.scope.repo) as $repo
               | if $a == "merge" then {id: $p, sub: "merge", args: ["--repo", $repo, "--number", $t.n, "--verified-head", ($s.verified_head // "")], natural: 20}
                 elif $a == "close" then {id: $p, sub: "close", args: ["--repo", $repo, "--kind", (if holding_repo($t.n) != null then "pr" else "issue" end), "--number", $t.n], natural: 8}
                 else empty end
               end),
              (if $a == "teardown" then
                 {id: $p, sub: "teardown", args: ["--topic", ($s.target // "")], natural: 8},
                 (if ($f[$p].verdict // "") == "confirmed" then {id: "\($p).2", sub: "teardown", args: ["--topic", ($s.target // "")], natural: 8, due: ($f[$p].t + 30)} else empty end)
               else empty end)),
          ($rec.deferrals | to_entries[] | "d\(.key)" as $p
            | {id: $p, sub: "deferral", args: ["--repo", $rec.scope.repo, "--row-file", "\($w)/\($p).row.json", "--run-start", $work.run_start, "--chain-start", ($work.chain_start // $work.run_start)], natural: 8})
        ]
        | map(select($f[.id] == null) | .due = (.due // 0))[]'
}

# The launch loop.
RUN_IDS=() RUN_PIDS=() RUN_END=() RUN_CLIPPED=()

# collect -- fold every finished read into the work file.
collect() {
    local i id keep_ids=() keep_pids=() keep_end=() keep_clip=() fact clipped t new
    i=0
    while [ "$i" -lt "${#RUN_IDS[@]}" ]; do
        id=${RUN_IDS[$i]}
        t=$(now) || exit 1
        # A result counts only once its own read has ended.
        if [ -f "$R/$id.rc" ] && ! kill -0 "${RUN_PIDS[$i]}" 2>/dev/null; then
            fact=$(jq -c '.' "$R/$id.out" 2>/dev/null | head -1)
            clipped=${RUN_CLIPPED[$i]}
            if [ -z "$fact" ] || ! printf '%s' "$fact" | jq -e '(.kind | type) == "string" and (.status | type) == "string"' >/dev/null 2>&1; then
                fact=$(jq -nc --arg id "$id" '{kind: "unknown", status: "not_verified", reason: "the re-check printed nothing readable"}')
            fi
            if [ "$clipped" = 1 ] && printf '%s' "$fact" | jq -e '.status != "ok" and ((.reason // "") | test("timed out"))' >/dev/null 2>&1; then
                :   # cut short by this pass's budget, not by its own deadline: read again next pass
            else
                new=$(wj -c --arg id "$id" --argjson f "$fact" --argjson t "$t" '.facts[$id] = ($f + {t: $t})') \
                    || die "the fact for $id could not be written"
                save "$new"
            fi
            rm -f "$R/$id".*
        elif [ "$t" -ge "${RUN_END[$i]}" ]; then
            # Past its budget and still running: stop it; it is read again
            # in a later pass.
            pkill -TERM -P "${RUN_PIDS[$i]}" 2>/dev/null; kill -TERM "${RUN_PIDS[$i]}" 2>/dev/null
            rm -f "$R/$id".*
        else
            keep_ids+=("$id"); keep_pids+=("${RUN_PIDS[$i]}"); keep_end+=("${RUN_END[$i]}"); keep_clip+=("${RUN_CLIPPED[$i]}")
        fi
        i=$((i + 1))
    done
    RUN_IDS=(${keep_ids[@]+"${keep_ids[@]}"}); RUN_PIDS=(${keep_pids[@]+"${keep_pids[@]}"})
    RUN_END=(${keep_end[@]+"${keep_end[@]}"}); RUN_CLIPPED=(${keep_clip[@]+"${keep_clip[@]}"})
}

running() { local x; for x in ${RUN_IDS[@]+"${RUN_IDS[@]}"}; do [ "$x" = "$1" ] && return 0; done; return 1; }

# launch SPEC LEFT -- start one re-check in the background with its deadline
# clipped to LEFT seconds.
launch() {
    local spec=$1 left=$2 id sub nat budget d bd clipped=0 pid tl
    id=$(printf '%s' "$spec" | jq -r .id)
    sub=$(printf '%s' "$spec" | jq -r .sub)
    nat=$(printf '%s' "$spec" | jq -r .natural)
    budget=$nat
    [ "$left" -lt "$budget" ] && { budget=$left; clipped=1; }
    d=8; [ "$budget" -lt "$d" ] && d=$budget
    bd=26; [ "$budget" -lt "$bd" ] && bd=$budget
    echo "reconcile-pass: launch $id at +$((READS_END - left))s with ${budget}s" >&2
    # Nothing left from an earlier launch of this read.
    rm -f "$R/$id".*
    printf '%s' "$spec" | jq -r '.args[]' > "$R/$id.args"
    # A deferral's row, from the work document, written for this launch only.
    case "$id" in d[0-9]*) wj -c ".record.deferrals[${id#d}].row" > "$R/$id.row.json" || die "can't write a deferral row" ;; esac
    (
        # The engine's stdout stays with the pass: a re-check left running
        # past its budget must not hold the capture open.
        exec 3>&-
        args=()
        while IFS= read -r a; do args+=("$a"); done < "$R/$id.args"
        # The settle is the pass's one write, in a script of its own; every
        # other read is a re-check.
        if [ "$sub" = settle ]; then
            RECONCILE_READ_DEADLINE=$d "${RUNBASH[@]}" "$HERE/reconcile-settle.sh" ${args[@]+"${args[@]}"} > "$R/$id.out" 2> "$R/$id.err" < /dev/null
        else
            RECONCILE_READ_DEADLINE=$d RECONCILE_BOARD_DEADLINE=$bd \
                "${RUNBASH[@]}" "$HERE/reconcile-check.sh" "$sub" ${args[@]+"${args[@]}"} > "$R/$id.out" 2> "$R/$id.err" < /dev/null
        fi
        echo $? > "$R/$id.rc.tmp" && mv "$R/$id.rc.tmp" "$R/$id.rc"
    ) &
    pid=$!
    tl=$(now) || exit 1
    RUN_IDS+=("$id"); RUN_PIDS+=("$pid"); RUN_END+=($((tl + budget + 2))); RUN_CLIPPED+=("$clipped")
}

while :; do
    collect
    t=$(now) || exit 1
    el=$((t - T0))
    plan "$t" > "$T/plan" || die "the plan could not be read"
    ready=0 wait_until=0
    while IFS= read -r spec; do
        [ -n "$spec" ] || continue
        id=$(printf '%s' "$spec" | jq -r .id)
        running "$id" && continue
        due=$(printf '%s' "$spec" | jq -r .due)
        if [ "$due" -gt "$t" ]; then
            { [ "$wait_until" = 0 ] || [ "$due" -lt "$wait_until" ]; } && wait_until=$due
            continue
        fi
        ready=$((ready + 1))
        tn=$(now) || exit 1
        el=$((tn - T0))
        left=$((READS_END - el))
        if [ "$el" -lt "$CUTOFF" ] && [ "${#RUN_IDS[@]}" -lt "$PARALLEL" ] && [ "$left" -ge 2 ]; then
            launch "$spec" "$left"
            ready=$((ready - 1))
        fi
    done < "$T/plan"
    if [ "${#RUN_IDS[@]}" -eq 0 ]; then
        [ "$ready" -gt 0 ] && break                        # past the cutoff with reads left
        [ "$wait_until" = 0 ] && break                     # nothing left: done
        [ $((wait_until - T0)) -lt "$CUTOFF" ] || break    # the wait doesn't fit this pass
        wait_secs $((wait_until - t))
        continue
    fi
    sleep 0.05
done

# Anything left is read in a later pass. A plan that can't be read must not
# count as nothing left, or the pass would seal with re-checks unread.
t=$(now) || exit 1
plan "$t" > "$T/plan" || die "the plan could not be read"
LEFT=$(grep -c . "$T/plan" || true)
if [ "$LEFT" -gt 0 ]; then
    H=$(printf '%s\n' "$WJ" | rd_sha256)
    printf '%s re-checks left in this visit; tick again with no evidence.\n' "$LEFT" > "$T/progress"
    ctx_put reconcile/progress "$T/progress"
    say "pending:$VISIT:$LEFT:$H"
fi

# Every re-check is done: the facts, the report, the seal.
jq -c --arg at "$(iso)" '
    .facts as $f | .record as $rec
    | def strip: del(.t);
      def get($id): if $f[$id] == null then empty else $f[$id] | strip end;
    {schema: "coordinate-reconcile-facts/v1",
     scope: $rec.scope, record: $rec.record, reconciled_at: $at, plugin_root: .plugin_root,
     decisions: ($rec.decisions // []),
     holdings: [$rec.holdings | to_entries[] | .key as $i | "h\($i)" as $p
       | (if $f["\($p).host2"] != null then ($f["\($p).host2"] | strip | .reads = 2)
          elif $f["\($p).host1"] != null then ($f["\($p).host1"] | strip) else null end) as $host
       | {source: .value.source, row: .value.row, refused: null,
          facts: ([get("\($p).pr"), get("\($p).board.v"), get("\($p).board.l"), get("\($p).branch"),
                   get("\($p).appeared"), get("\($p).files"), get("\($p).leg"), get("\($p).settle")]
                  + (if $host == null then [] else [$host | del(.path)] end)
                  + (if $f["\($p).inv"] != null then [get("\($p).inv")]
                     elif $host != null and $host.status == "ok" and $host.state == "missed" then
                       [{kind: "inventory", status: "ok", taken: false, reason: "the worker was not found on this read", read_at: $host.read_at}]
                     elif $host != null and $host.status == "ok" and $host.state == "ambiguous" then
                       [{kind: "inventory", status: "ok", taken: false, reason: "the worker matched more than one instance", read_at: $host.read_at}]
                     else [] end))}],
     side_effects: [$rec.side_effects | to_entries[] | "s\(.key)" as $p | .value.row as $s
       | (($s.action // "") | ascii_downcase) as $a
       | {row: $s,
          fact: (if $f["\($p).2"] != null then get("\($p).2")
                 elif $f[$p] != null then get($p)
                 elif ($a == "merge" or $a == "close" or $a == "teardown") then
                   {kind: $a, status: "not_verified", reason: "the target is not #<number> or owner/repo#<number>", verdict: "not_confirmed"}
                 else {kind: "other", status: "ok", verdict: "not_rechecked", reason: ""} end)}],
     deferrals: [$rec.deferrals | to_entries[] | "d\(.key)" as $p
       | {row: .value.row} + (if $f[$p] != null then (get($p) | {disposed, how, status, reason}) else {status: "not_verified", reason: "not read"} end)],
     reasoning: $rec.reasoning, unparseable: $rec.unparseable}' > "$T/facts.json" <<< "$WJ" \
    || die "the facts could not be assembled"
"${RUNBASH[@]}" "$HERE/reconcile-report.sh" json < "$T/facts.json" > "$W/report.json" || die "the report could not be built"
"${RUNBASH[@]}" "$HERE/reconcile-report.sh" md < "$W/report.json" > "$W/report.md" || die "the report could not be rendered"
DIGEST=$(rd_sha256 < "$W/report.json")
ctx_put reconcile/report.json "$W/report.json"
ctx_put reconcile/report.md "$W/report.md"
if [ "$(wj -r '.record.reasoning // empty')" = present ] && [ -f "$W/reasoning.md" ]; then
    ctx_put reconcile/reasoning.md "$W/reasoning.md"
else
    rm -f "$W/reasoning.md"
fi
koto context get "$SESSION" reconcile/report.json > "$T/back.json" 2>/dev/null || die "the stored report can't be read back"
[ "$(rd_sha256 < "$T/back.json")" = "$DIGEST" ] || die "the stored report differs from the one written"
NEW=$(wj -c '.done = true') || die "the work file could not be marked done"
save "$NEW"
LINE=$("${RUNBASH[@]}" "$RD_COORD_LOG" seal --session "$SESSION" --state "$STATE" --token "reconciled $DIGEST") \
    || die "the report could not be sealed"
# The facts are this visit's: a seal for a later entry into the state would
# put them on a visit they weren't read in.
[[ $LINE =~ \ sealed:$VISIT: ]] || die "the state was entered again during this pass; tick again"
say "$LINE"
