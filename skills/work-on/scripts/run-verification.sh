#!/usr/bin/env bash
# run-verification.sh -- start the verification map's commands for this head,
# bounded, without waiting for them.
# Part of the work-on skill
#
# The `verification` state's default_action runs `--start`. koto gives one
# action run 30 seconds and a test suite takes minutes, so this never runs a
# command itself: it starts a detached supervisor that does, and returns within
# a second. check-verification.sh reads the result the supervisor writes, and
# the state's `poll:` gate waits on it.
#
#   --start --session <s> [--base-ref <ref>]
#       1. Resolve HEAD and the merge-base of HEAD and the default branch. A
#          result for this head and merge-base already on disk: exit 0.
#       2. Tracked files with uncommitted changes: write a `dirty-tree` result.
#       3. Read the map at the merge-base
#          (`git show <merge-base>:.claude/shirabe-extensions/verification-map.json`),
#          so a branch that edits the map is still verified by the map it
#          started from. Absent: a `no-map` result. Doesn't parse: `bad-map`.
#       4. Select commands for `git diff --name-only <merge-base>..HEAD`.
#          Nothing selected: `no-map`. A selected `unattended: false`
#          command: `attended`, and nothing is started.
#       5. A lock naming a live supervisor for this head: exit 0. A lock
#          whose process is gone is removed.
#       6. Start the supervisor in its own process group (job control, not a
#          new-session command, which the macOS floor lacks), standard input from
#          /dev/null, both outputs to its log, koto's tick marker
#          (KOTO_TICK_SESSION) removed from its environment, and exit 0.
#   --locate --session <s> [--base-ref <ref>]
#       Print three lines: the head, the merge-base, and the result file's
#       path. check-verification.sh calls this so the path rules live here.
#   --supervise <dir>
#       Internal: the supervisor. Never calls koto.
#
# --base-ref names the default branch. Without it: the ref origin/HEAD points
# at, else origin/main, else main.
#
# Where things go: ${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/
# <session>/<head>/, every directory created with mode 0700, outside every
# repository, and only the ten most recent heads per session kept. The head
# directory holds the supervisor's log, one log per command, and result.json,
# written atomically:
#
#   {"schema": "shirabe-verification-result/v1", "head": "...",
#    "merge_base": "...", "status": "done|no-map|bad-map|attended|dirty-tree|
#    timed-out|supervisor-error", "detail": "...", "commands": [{"id", "argv",
#    "exit_status", "duration_secs", "timed_out", "runaway", "not_started",
#    "pgid", "log", "baseline"?}]}
#
# The comparison with the merge-base: when every command ran to an exit
# status within the budget and one or more exited non-zero, each of those is
# run twice more before the result is written, back to back: once at the
# merge-base and once at the head, each in a fresh worktree of the
# repository (`git -c core.hooksPath=/dev/null worktree add --detach`) inside
# the head directory, removed after the attempt, and bounded the same way as
# a head command. The command's entry gains an optional `baseline` object:
#
#   {"verdict": "preexisting|caused|undecidable", "reason": "...",
#    "merge_base": <attempt>|null, "clean_head": <attempt>|null}
#   <attempt> = {"commit", "exit_status", "duration_secs", "timed_out",
#                "runaway", "not_started", "log"}
#
# By exit status, B at the merge-base and C in the clean head: the same
# non-zero B and C is `preexisting`; B 0 with C equal to the head's status is
# `caused`; anything else is `undecidable`, as is an attempt that times out,
# runs away, is cut by the budget, can't get its worktree or can't start, and
# an `each` directory absent at the merge-base (checked with ls-tree, nothing
# run). An attempt that never ran is null; when the base attempt decides
# nothing, the clean-head one is skipped. A result without `baseline` is read
# as before. A supervisor killed with SIGKILL during an attempt can leave the
# attempt's worktree registered in the repository; a HUP, INT or TERM removes
# it.
#
# The bound on each command: its own process group and its own deadline
# (timeout_secs; TERM to the group, then KILL), and a watchdog that counts the
# group's processes and kills the group when the count passes max_procs. Where
# `systemd-run --user --scope` works, the command also runs in a scope with
# TasksMax at twice max_procs plus 64: a hard ceiling for a storm between two
# watchdog polls, set well above max_procs on purpose. At the ceiling a fork
# fails, and a shell whose fork fails exits, often before the next poll; the
# watchdog then never sees the count and the runaway reads as an ordinary
# failure (exit 1). With the ceiling well above the bound, the watchdog sees
# the count pass max_procs first. (TasksMax also counts threads, which the
# watchdog doesn't, hence the fixed headroom.) The group is killed after every command, so nothing a
# command left running outlives it, and a HUP, INT or TERM that stops the supervisor stops the
# running command's group first (TERM, then KILL). A descendant that moves to its own session
# or process group escapes both; the schema reference states that residual.
#
# The bound on the whole run: the supervisor stops after BUDGET_SECS (7200,
# the verification gate's poll timeout_secs, so the run can't outlive the wait
# for it). A command still running at the budget is killed as a timeout, the
# commands after it are not started, and the result's status is `timed-out`.
# SHIRABE_VERIFICATION_BUDGET_SECS overrides it for tests; koto's cleared
# environment never carries it.
#
# Exit status: 0 the launcher did its job (a result exists, or a supervisor is
# running); 2 it could not decide (usage, a missing tool, no HEAD, no
# merge-base, no state directory). The verdict is never this script's exit.
#
# Written for the bash 3.2 floor, without `set -e`, and without the GNU-only
# time-limit and new-session commands, which the macOS floor lacks.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SELF="$HERE/$(basename "$0")"
MAP_PATH=.claude/shirabe-extensions/verification-map.json
KEEP_HEADS=10
RESULT_SCHEMA=shirabe-verification-result/v1
BUDGET_SECS=7200

usage() {
    cat >&2 <<'EOF'
Usage: run-verification.sh --start --session <s> [--base-ref <ref>]
       run-verification.sh --locate --session <s> [--base-ref <ref>]
EOF
}

die() {
    echo "run-verification: $*" >&2
    exit 2
}

# --- the map: validation, defaults and selection, in one jq program -------------
#
# Input: the map. $changed: the changed paths. Output: {"error": "..."} or
# {"invocations": [...], "attended": [ids]}. Globs: `**` matches across path
# components, `*` within one; every other character is literal.
SELECT_JQ='
def glob_re:
  "^" + (split("**")
         | map(gsub("(?<c>[.+?^$(){}|\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*"; "[^/]*"))
         | join(".*")) + "$";
def is_int: type == "number" and . == floor;
def need(cond; msg): if cond then . else error(msg) end;
def command_ok($id):
  need(type == "object"; "command \($id) is not an object")
  | need((.run | type) == "array" and (.run | length) > 0 and (.run | all(type == "string")) and (.run[0] != "");
         "command \($id): run is not a non-empty array of strings")
  | need((has("each") | not) or ((.each | type) == "string" and .each != ""); "command \($id): each is not a glob string")
  | need((has("timeout_secs") | not) or ((.timeout_secs | is_int) and .timeout_secs >= 1 and .timeout_secs <= 3600);
         "command \($id): timeout_secs is not an integer from 1 to 3600")
  | need((has("network") | not) or (.network | type) == "boolean"; "command \($id): network is not a boolean")
  | need((has("unattended") | not) or (.unattended | type) == "boolean"; "command \($id): unattended is not a boolean")
  | need((.network != true) or has("unattended"); "command \($id): network is true and unattended is not set")
  | need((has("max_procs") | not) or ((.max_procs | is_int) and .max_procs >= 1); "command \($id): max_procs is not a positive integer")
  | {id: $id, run: .run, each: (.each // null), timeout_secs: (.timeout_secs // 1800),
     max_procs: (.max_procs // 256), unattended: (if has("unattended") then .unattended else true end)};
def ids_ok($where; $defined):
  need(type == "array" and all(type == "string"); "\($where) is not an array of command ids")
  | (map(select(. as $i | $defined | index([$i]) | not))) as $bad
  | need(($bad | length) == 0; "\($where) names undefined command ids: \($bad | join(", "))");
def dedupe: reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end);

try (
  need(type == "object"; "the map is not a JSON object")
  | need(.schema == "shirabe-verification-map/v1"; "schema is not shirabe-verification-map/v1")
  | need((.commands | type) == "object"; "commands is not an object")
  | need((.entries | type) == "array"; "entries is not an array")
  | (.commands | keys) as $defined
  | (.commands | to_entries | map(.key as $k | .value | command_ok($k))) as $cmds
  | (.entries | to_entries | map(
       .key as $n | .value
       | need(type == "object"; "entry \($n) is not an object")
       | need((.paths | type) == "array" and (.paths | length) > 0 and (.paths | all(type == "string"));
              "entry \($n): paths is not a non-empty array of globs")
       | (.commands | ids_ok("entry \($n) commands"; $defined)) as $_
       | {res: (.paths | map(glob_re)), commands: .commands})) as $entries
  | (if has("default") then (.default | ids_ok("default"; $defined)) else [] end) as $default
  | ($entries | map(. as $e | select(any($changed[]; . as $p | any($e.res[]; . as $r | $p | test($r)))))
     | map(.commands[])) as $from_entries
  | ([$changed[] | . as $p | select(all($entries[]; all(.res[]; . as $r | $p | test($r) | not)))] | length) as $unmatched
  | ($from_entries + (if $unmatched > 0 then $default else [] end) | dedupe) as $ids
  | ($cmds | map({key: .id, value: .}) | from_entries) as $byid
  | [$changed[] | split("/") as $parts | range(1; $parts | length) | $parts[0:.] | join("/")] | unique as $dirs
  | [$ids[] | $byid[.] as $c
     | if $c.each == null then {id: $c.id, argv: $c.run, each_dir: null, timeout_secs: $c.timeout_secs, max_procs: $c.max_procs, unattended: $c.unattended}
       else ($c.each | glob_re) as $er
         | $dirs[] | select(test($er))
         | {id: $c.id, argv: ($c.run + [split("/") | last]), each_dir: ., timeout_secs: $c.timeout_secs, max_procs: $c.max_procs, unattended: $c.unattended}
       end] as $inv
  | {invocations: $inv, attended: ($inv | map(select(.unattended == false) | .id) | dedupe)}
) catch {error: (if type == "string" then . else tostring end)}
'

# --- shared: where this head's result lives ---------------------------------------

# resolve: sets ROOT, HEAD_SHA, MB, SESSION_DIR, HEAD_DIR, RESULT.
resolve() {
    for tool in git jq; do
        command -v "$tool" >/dev/null 2>&1 || die "$tool is not on PATH"
    done
    ROOT=$(git rev-parse --show-toplevel) || die "not inside a git working tree"
    HEAD_SHA=$(git -C "$ROOT" rev-parse --verify -q "HEAD^{commit}") || die "HEAD does not name a commit"
    local base=$BASE_REF
    if [ -z "$base" ]; then
        base=$(git -C "$ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD)
        if [ -z "$base" ]; then
            if git -C "$ROOT" rev-parse --verify -q "origin/main^{commit}" >/dev/null; then
                base=origin/main
            else
                base=main
            fi
        fi
    fi
    git -C "$ROOT" rev-parse --verify -q "${base}^{commit}" >/dev/null \
        || die "the default branch [$base] does not resolve to a commit"
    MB=$(git -C "$ROOT" merge-base HEAD "$base") || die "HEAD shares no history with [$base]"
    local state=${XDG_STATE_HOME:-}
    if [ -z "$state" ]; then
        [ -n "${HOME:-}" ] || die "neither XDG_STATE_HOME nor HOME is set"
        state="$HOME/.local/state"
    fi
    SESSION_DIR="$state/shirabe/verification/$SESSION"
    HEAD_DIR="$SESSION_DIR/$HEAD_SHA"
    RESULT="$HEAD_DIR/result.json"
}

# write_result <file> <json>: atomically, through a temporary file beside it.
write_result() {
    local tmp
    tmp=$(mktemp "$(dirname "$1")/.result.XXXXXX") || return 1
    printf '%s\n' "$2" > "$tmp" && mv -f "$tmp" "$1"
}

# settle <status> <detail> [<commands json>]: write a result that needs no run.
settle() {
    write_result "$RESULT" "$(jq -cn --arg schema "$RESULT_SCHEMA" --arg head "$HEAD_SHA" --arg mb "$MB" \
        --arg status "$1" --arg detail "$2" --argjson commands "${3:-[]}" \
        '{schema: $schema, head: $head, merge_base: $mb, status: $status, detail: $detail, commands: $commands}')" \
        || die "could not write $RESULT"
    exit 0
}

# prune: keep the KEEP_HEADS most recently modified head directories.
prune() {
    local n=0 d
    # ls -t sorts by modification time, newest first; head names are hex.
    for d in $(ls -t "$SESSION_DIR" 2>/dev/null); do
        case "$d" in *[!0-9a-f]*) continue ;; esac
        [ -d "$SESSION_DIR/$d" ] || continue
        n=$((n + 1))
        [ "$n" -le "$KEEP_HEADS" ] && continue
        [ "$SESSION_DIR/$d" = "$HEAD_DIR" ] && continue
        rm -rf "${SESSION_DIR:?}/$d"
    done
}

# lock_live <lock>: true when the lock names a running supervisor of ours.
lock_live() {
    local pid
    pid=$(readlink "$1" 2>/dev/null) || return 1
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    # A recycled pid belongs to some other program; only ours counts.
    case "$(ps -p "$pid" -o command= 2>/dev/null)" in
        *run-verification.sh*) return 0 ;;
    esac
    return 1
}

# --- --supervise ---------------------------------------------------------------------

count_group() {
    ps -A -o pgid= 2>/dev/null | awk -v g="$1" '$1 == g { c++ } END { print c + 0 }'
}

kill_group() {
    kill "-$1" -- "-$2" 2>/dev/null
}

# resolve_prog <root> <prog>: the program to start, a relative path resolved
# against <root> and a bare name against PATH; empty when there is none.
resolve_prog() {
    case "$2" in
        /*) printf '%s' "$2" ;;
        */*) printf '%s' "$1/$2" ;;
        *) type -P "$2" 2>/dev/null ;;
    esac
}

# bounded <cwd> <log> <limit> <maxp>: run ARGV (a global array whose first
# word is already resolved) from <cwd>, in its own process group with standard
# input from /dev/null and both outputs appended to <log>, under the deadline
# <limit> and the max_procs watchdog <maxp>; the group is killed after. Sets
# RUN_STATUS, RUN_TO, RUN_RA, RUN_PID and RUN_DUR. The head commands and the
# comparison attempts share it, so both are bounded the same way.
bounded() {
    local cwd=$1 log=$2 limit=$3 maxp=$4 start now pid count
    start=$(date +%s)
    RUN_TO=false; RUN_RA=false
    set -m
    if [ "$SUP_SCOPE" -eq 1 ]; then
        (cd "$cwd" && exec systemd-run --user --scope --quiet -p "TasksMax=$((maxp * 2 + 64))" -- "${ARGV[@]}") </dev/null >>"$log" 2>&1 &
    else
        (cd "$cwd" && exec "${ARGV[@]}") </dev/null >>"$log" 2>&1 &
    fi
    pid=$!
    SUP_PGID=$pid
    set +m
    # The job's process group is its pid: job control put it there.
    while kill -0 "$pid" 2>/dev/null; do
        count=$(count_group "$pid")
        if [ "$count" -gt "$maxp" ]; then
            kill_group KILL "$pid"; RUN_RA=true; break
        fi
        now=$(date +%s)
        if [ $((now - start)) -ge "$limit" ]; then
            kill_group TERM "$pid"; sleep 1; kill_group KILL "$pid"; RUN_TO=true; break
        fi
        sleep 0.25
    done
    # The leader may exit leaving its group behind; a group still past the
    # bound at that point is a runaway too.
    if [ "$RUN_RA" = false ] && [ "$RUN_TO" = false ] && [ "$(count_group "$pid")" -gt "$maxp" ]; then
        RUN_RA=true
    fi
    wait "$pid" 2>/dev/null
    RUN_STATUS=$?
    kill_group KILL "$pid"
    SUP_PGID=""
    RUN_PID=$pid
    now=$(date +%s)
    RUN_DUR=$((now - start))
}

# drop_worktree: remove the comparison attempt's worktree, if one is in
# flight, with git's output in the attempt's log. A removal that fails leaves
# the registration behind; nothing here sweeps registrations it didn't make.
drop_worktree() {
    [ -n "$SUP_WT" ] || return 0
    git -c core.hooksPath=/dev/null -C "$ROOT" worktree remove --force "$SUP_WT" </dev/null >>"$SUP_WT_LOG" 2>&1 \
        || echo "could not remove the worktree $SUP_WT" >>"$SUP_WT_LOG"
    SUP_WT=""
}

# attempt <k> <kind> <commit>: one comparison attempt for invocation <k>, in a
# fresh worktree of the repository at <commit>, detached, with hooks off, inside
# the head's state directory, and removed after. <kind> is `base` or
# `clean-head`, and names the log. Sets ATT_JSON (the attempt object, or null
# when nothing ran) and ATT_WHY (empty when the command ran to an exit status,
# else why the attempt decides nothing).
attempt() {
    local k=$1 kind=$2 commit=$3 id safe log wt prog limit left maxp a
    ATT_JSON=null ATT_WHY=""
    id=$(jq -r --argjson k "$k" '.invocations[$k].id' "$RUN")
    safe=$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')
    log="$SUP_DIR/$k-$safe.$kind.log"
    left=$((SUP_START + SUP_BUDGET - $(date +%s)))
    if [ "$left" -le 0 ]; then
        ATT_WHY="the run's budget was spent before the $kind attempt could start"
        return 0
    fi
    limit=$(jq -r --argjson k "$k" '.invocations[$k].timeout_secs' "$RUN")
    [ "$left" -ge "$limit" ] || limit=$left
    maxp=$(jq -r --argjson k "$k" '.invocations[$k].max_procs' "$RUN")
    wt="$SUP_DIR/wt-$k-$kind"
    # Named before the add, so a signal that lands while git registers the
    # worktree still has the trap remove it.
    SUP_WT=$wt SUP_WT_LOG=$log
    if ! git -c core.hooksPath=/dev/null -C "$ROOT" worktree add --detach --quiet "$wt" "$commit" </dev/null >"$log" 2>&1; then
        SUP_WT=""
        ATT_WHY="a worktree at $commit for the $kind attempt could not be made (log: $log)"
        return 0
    fi
    ARGV=()
    while IFS= read -r -d '' a; do ARGV+=("$a"); done < <(jq -j --argjson k "$k" '.invocations[$k].argv[] | (., "\u0000")' "$RUN")
    prog=$(resolve_prog "$wt" "${ARGV[0]}")
    if [ -z "$prog" ] || [ ! -f "$prog" ] || [ ! -x "$prog" ]; then
        echo "not started: [${ARGV[0]}] is not an executable program in the $kind worktree" >>"$log"
        drop_worktree
        ATT_JSON=$(jq -cn --arg c "$commit" --arg log "$log" \
            '{commit: $c, exit_status: null, duration_secs: 0, timed_out: false, runaway: false, not_started: true, log: $log}')
        ATT_WHY="[${ARGV[0]}] is not an executable program in the $kind worktree"
        return 0
    fi
    ARGV[0]=$prog
    bounded "$wt" "$log" "$limit" "$maxp"
    drop_worktree
    ATT_JSON=$(jq -cn --arg c "$commit" --argjson status "$RUN_STATUS" --argjson dur "$RUN_DUR" \
        --argjson to "$RUN_TO" --argjson ra "$RUN_RA" --arg log "$log" \
        '{commit: $c, exit_status: $status, duration_secs: $dur, timed_out: $to, runaway: $ra, not_started: false, log: $log}')
    if [ "$RUN_RA" = true ]; then
        ATT_WHY="the $kind attempt grew past its max_procs and was killed"
    elif [ "$RUN_TO" = true ]; then
        ATT_WHY="the $kind attempt ran past its timeout_secs or the run's budget and was killed"
    fi
}

# compare <k> <head-status>: compare failed invocation <k> with the
# merge-base. One attempt at the merge-base, then one in a clean checkout of
# the head, back to back, by exit status (B and C):
#   preexisting  B and C are the same non-zero status
#   caused       B is 0 and C equals the head's status
#   undecidable  anything else, an attempt that didn't run to a status, or an
#                `each` directory absent at the merge-base (nothing runs)
# Sets BASELINE to the command's `baseline` object. A global, not a command
# substitution: the in-flight worktree must be visible to the signal trap.
compare() {
    local k=$1 h=$2 each entry base=null clean=null b c verdict="" reason=""
    each=$(jq -r --argjson k "$k" '.invocations[$k].each_dir // empty' "$RUN")
    if [ -n "$each" ]; then
        # ls-tree prints nothing for an absent path and exits 0.
        if ! entry=$(git -C "$ROOT" ls-tree "$MB" -- "$each" </dev/null); then
            reason="could not list the each directory $each at the merge-base"
        elif [ -z "$entry" ]; then
            reason="the each directory $each does not exist at the merge-base, so the command can't run there"
        fi
    fi
    if [ -z "$reason" ]; then
        attempt "$k" base "$MB"
        base=$ATT_JSON reason=$ATT_WHY
    fi
    if [ -z "$reason" ]; then
        attempt "$k" clean-head "$HEAD_SHA"
        clean=$ATT_JSON reason=$ATT_WHY
    fi
    if [ -z "$reason" ]; then
        b=$(printf '%s' "$base" | jq -r .exit_status)
        c=$(printf '%s' "$clean" | jq -r .exit_status)
        if [ "$c" -eq 0 ]; then
            reason="the failure did not reproduce in a clean checkout of the head: it exited 0 there and $h in the working tree"
        elif [ "$b" -eq "$c" ]; then
            verdict=preexisting
            reason="it exited $c at the merge-base and in a clean checkout of the head"
        elif [ "$b" -eq 0 ] && [ "$c" -eq "$h" ]; then
            verdict=caused
            reason="it passed at the merge-base and exited $c in a clean checkout of the head"
        else
            reason="it exited $b at the merge-base and $c in a clean checkout of the head, against $h in the working tree"
        fi
    fi
    [ -n "$verdict" ] || verdict=undecidable
    BASELINE=$(jq -cn --arg v "$verdict" --arg r "$reason" --argjson base "$base" --argjson clean "$clean" \
        '{verdict: $v, reason: $r, merge_base: $base, clean_head: $clean}')
}

supervise() {
    local dir=$1
    RUN="$dir/run.json"
    [ -r "$RUN" ] || { echo "no run.json in $dir" >&2; exit 2; }
    ROOT=$(jq -r .root "$RUN"); HEAD_SHA=$(jq -r .head "$RUN"); MB=$(jq -r .merge_base "$RUN")
    RESULT="$dir/result.json"
    # Globals, not locals: the EXIT trap reads them after the function is gone.
    SUP_LOCK="$dir/lock"
    SUP_ENTRIES="$dir/.entries"
    SUP_WRITTEN=0
    # The running command's process group, empty between commands.
    SUP_PGID=""
    # The comparison attempt's worktree and its log, empty between attempts.
    SUP_WT="" SUP_WT_LOG=""
    SUP_DIR=$dir
    : > "$SUP_ENTRIES"

    # Whatever stops the supervisor, a result gets written, so the verdict
    # never waits on a supervisor that is gone.
    finish() {
        drop_worktree
        [ "$SUP_WRITTEN" -eq 1 ] && return 0
        write_result "$RESULT" "$(jq -cs --arg schema "$RESULT_SCHEMA" --arg head "$HEAD_SHA" --arg mb "$MB" \
            '{schema: $schema, head: $head, merge_base: $mb, status: "supervisor-error",
              detail: "the supervisor stopped before every command ran", commands: .}' "$SUP_ENTRIES")"
        rm -f "$SUP_LOCK" "$SUP_ENTRIES"
    }
    # A signal that stops the supervisor stops the running command too. The
    # command has its own process group, so nothing sent to the supervisor
    # reaches it, and exiting without this left it and everything it started
    # running after the supervisor was gone. The same TERM, then KILL, as a
    # command past its deadline. A comparison attempt's worktree goes with it.
    stop_running() {
        if [ -n "$SUP_PGID" ]; then
            kill_group TERM "$SUP_PGID"; sleep 1; kill_group KILL "$SUP_PGID"
            SUP_PGID=""
        fi
        drop_worktree
    }
    trap finish EXIT
    trap 'stop_running; exit 1' HUP INT TERM

    cd "$ROOT" || exit 1

    SUP_SCOPE=0
    if command -v systemd-run >/dev/null 2>&1 \
        && systemd-run --user --scope --quiet -p TasksMax=8 true </dev/null >/dev/null 2>&1; then
        SUP_SCOPE=1
    fi

    local n i id safe limit maxp prog log left capped=0 over=0 stopped="" a
    SUP_BUDGET=$(jq -r ".budget_secs // $BUDGET_SECS" "$RUN")
    case "$SUP_BUDGET" in ''|*[!0-9]*|0) SUP_BUDGET=$BUDGET_SECS ;; esac
    SUP_START=$(date +%s)
    n=$(jq '.invocations | length' "$RUN")
    i=0
    while [ "$i" -lt "$n" ]; do
        id=$(jq -r --argjson i "$i" '.invocations[$i].id' "$RUN")
        limit=$(jq -r --argjson i "$i" '.invocations[$i].timeout_secs' "$RUN")
        # The run's budget caps each command's own deadline.
        left=$((SUP_START + SUP_BUDGET - $(date +%s)))
        if [ "$left" -le 0 ]; then
            over=1; break
        fi
        capped=0
        if [ "$left" -lt "$limit" ]; then
            limit=$left; capped=1
        fi
        maxp=$(jq -r --argjson i "$i" '.invocations[$i].max_procs' "$RUN")
        ARGV=()
        while IFS= read -r -d '' a; do ARGV+=("$a"); done < <(jq -j --argjson i "$i" '.invocations[$i].argv[] | (., "\u0000")' "$RUN")
        safe=$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')
        log="$dir/$i-$safe.log"
        prog=$(resolve_prog "$ROOT" "${ARGV[0]}")
        if [ -z "$prog" ] || [ ! -f "$prog" ] || [ ! -x "$prog" ]; then
            jq -cn --arg id "$id" --argjson i "$i" --slurpfile run "$RUN" --arg log "$log" \
                '{id: $id, argv: $run[0].invocations[$i].argv, exit_status: null, duration_secs: 0,
                  timed_out: false, runaway: false, not_started: true, pgid: null, log: $log}' >> "$SUP_ENTRIES"
            echo "not started: [${ARGV[0]}] is not an executable program" > "$log"
            i=$((i + 1)); continue
        fi
        ARGV[0]=$prog

        : > "$log"
        bounded "$ROOT" "$log" "$limit" "$maxp"
        jq -cn --arg id "$id" --argjson i "$i" --slurpfile run "$RUN" --argjson status "$RUN_STATUS" \
            --argjson dur "$RUN_DUR" --argjson to "$RUN_TO" --argjson ra "$RUN_RA" \
            --argjson pgid "$RUN_PID" --arg log "$log" \
            '{id: $id, argv: $run[0].invocations[$i].argv, exit_status: $status, duration_secs: $dur,
              timed_out: $to, runaway: $ra, not_started: false, pgid: $pgid, log: $log}' >> "$SUP_ENTRIES"
        i=$((i + 1))
        if [ "$RUN_TO" = true ] && [ "$capped" -eq 1 ]; then
            over=1; stopped=$id; break
        fi
    done

    # The comparison with the merge-base, before the result is written: for
    # each command that ran and exited non-zero, one attempt at the merge-base
    # and one in a clean checkout of the head (compare). Skipped when the run
    # passed its budget or a command timed out, ran away or didn't start: that
    # verdict is 4, and the comparison would decide nothing.
    if [ "$over" -eq 0 ] \
        && jq -se 'all(.[]; (.timed_out or .runaway or .not_started) | not) and any(.[]; .exit_status != 0)' "$SUP_ENTRIES" >/dev/null; then
        local k=0 entry hs
        : > "$SUP_ENTRIES.compared"
        while IFS= read -r entry <&3; do
            hs=$(printf '%s' "$entry" | jq -r .exit_status)
            if [ "$hs" != 0 ]; then
                compare "$k" "$hs"
                printf '%s' "$entry" | jq -c --argjson bl "$BASELINE" '. + {baseline: $bl}' >> "$SUP_ENTRIES.compared"
            else
                printf '%s\n' "$entry" >> "$SUP_ENTRIES.compared"
            fi
            k=$((k + 1))
        done 3< "$SUP_ENTRIES"
        mv -f "$SUP_ENTRIES.compared" "$SUP_ENTRIES"
    fi

    local final=done detail=""
    if [ "$over" -eq 1 ]; then
        final=timed-out
        detail="the run passed its total budget of $SUP_BUDGET seconds"
        [ -n "$stopped" ] && detail="$detail; command $stopped was stopped"
        [ "$i" -lt "$n" ] && detail="$detail; $((n - i)) later command(s) were not started: $(jq -r --argjson i "$i" '[.invocations[$i:][].id] | join(", ")' "$RUN")"
    fi
    write_result "$RESULT" "$(jq -cs --arg schema "$RESULT_SCHEMA" --arg head "$HEAD_SHA" --arg mb "$MB" \
        --arg status "$final" --arg detail "$detail" \
        '{schema: $schema, head: $head, merge_base: $mb, status: $status, detail: $detail, commands: .}' "$SUP_ENTRIES")" \
        && SUP_WRITTEN=1
    rm -f "$SUP_LOCK" "$SUP_ENTRIES"
    exit 0
}

# --- arguments -------------------------------------------------------------------------

[ $# -ge 1 ] || { usage; exit 2; }
MODE=$1
shift
case "$MODE" in
    --supervise)
        [ $# -eq 1 ] || { usage; exit 2; }
        supervise "$1" ;;
    --start|--locate) ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac

SESSION=""
BASE_REF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session)
            [ $# -ge 2 ] && [ -z "$SESSION" ] || { usage; exit 2; }
            SESSION=$2; shift 2 ;;
        --base-ref)
            [ $# -ge 2 ] && [ -z "$BASE_REF" ] || { usage; exit 2; }
            BASE_REF=$2; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done
[ -n "$SESSION" ] || { usage; exit 2; }
grep -Eq '^[A-Za-z0-9._][A-Za-z0-9._-]*$' <<<"$SESSION" && [ "$SESSION" != . ] && [ "$SESSION" != .. ] \
    || die "--session [$SESSION] is not a session name"
if [ -n "$BASE_REF" ]; then
    grep -Eq '^[A-Za-z0-9._][A-Za-z0-9._/-]*$' <<<"$BASE_REF" \
        && ! grep -q '\.\.' <<<"$BASE_REF" \
        || die "--base-ref [$BASE_REF] is not a ref name"
fi

resolve

if [ "$MODE" = --locate ]; then
    printf '%s\n%s\n%s\n' "$HEAD_SHA" "$MB" "$RESULT"
    exit 0
fi

# --- --start -----------------------------------------------------------------------------

(umask 077 && mkdir -p "$HEAD_DIR") || die "could not create $HEAD_DIR"
touch "$HEAD_DIR"
prune

# 1. A result for this head and merge-base stands, except a dirty-tree one,
#    which the next start re-checks once the tree is clean.
if [ -f "$RESULT" ]; then
    if jq -e --arg mb "$MB" '.merge_base == $mb and .status != "dirty-tree"' "$RESULT" >/dev/null; then
        exit 0
    fi
    lock_live "$HEAD_DIR/lock" && exit 0
    rm -f "$RESULT"
fi

# 2. The paths selected on and the code tested must be the same commit.
DIRTY=$(git -C "$ROOT" status --porcelain --untracked-files=no) \
    || die "could not read the working tree's status"
if [ -n "$DIRTY" ]; then
    settle dirty-tree "tracked files have uncommitted changes: $(head -n 10 <<<"$DIRTY" | cut -c4- | tr '\n' ' ')"
fi

# 3. The map, from the merge-base.
# ls-tree prints nothing for an absent path and exits 0, so absence is read
# from its output and a failure from its status, with git's message intact.
MAP_ENTRY=$(git -C "$ROOT" ls-tree "$MB" -- "$MAP_PATH") \
    || die "could not list $MAP_PATH at $MB"
if [ -z "$MAP_ENTRY" ]; then
    settle no-map "no $MAP_PATH at the merge-base $MB"
fi
MAP_JSON=$(git -C "$ROOT" show "$MB:$MAP_PATH") || die "could not read $MAP_PATH at $MB"
CHANGED=$(git -C "$ROOT" diff --name-only -z "$MB..HEAD" | jq -Rs 'split("\u0000") | map(select(length > 0))') \
    || die "could not list the changed paths"
if ! printf '%s' "$MAP_JSON" | jq -se 'length == 1' >/dev/null; then
    settle bad-map "$MAP_PATH at $MB is not one valid JSON value"
fi
SELECTION=$(printf '%s' "$MAP_JSON" | jq -c --argjson changed "$CHANGED" "$SELECT_JQ") \
    || die "the selection program failed"
ERR=$(printf '%s' "$SELECTION" | jq -r '.error // empty')
[ -z "$ERR" ] || settle bad-map "$ERR"

# 4. What to run.
if [ "$(printf '%s' "$SELECTION" | jq '.invocations | length')" -eq 0 ]; then
    settle no-map "the map selects nothing for this change"
fi
ATTENDED=$(printf '%s' "$SELECTION" | jq -r '.attended | join(", ")')
if [ -n "$ATTENDED" ]; then
    settle attended "commands marked unattended: false need a person: $ATTENDED" \
        "$(printf '%s' "$SELECTION" | jq -c '[.invocations[] | select(.unattended == false)
            | {id, argv, exit_status: null, duration_secs: 0, timed_out: false, runaway: false,
               not_started: true, pgid: null, log: null}]')"
fi

# 5. One supervisor per head. The lock is a symlink whose target is a pid:
#    creating one is atomic, and so is renaming another over it.
LOCK="$HEAD_DIR/lock"
if ! ln -s "$$" "$LOCK" 2>/dev/null; then
    lock_live "$LOCK" && exit 0
    rm -f "$LOCK"
    ln -s "$$" "$LOCK" 2>/dev/null || exit 0
fi

BUDGET=${SHIRABE_VERIFICATION_BUDGET_SECS:-$BUDGET_SECS}
case "$BUDGET" in ''|*[!0-9]*|0) BUDGET=$BUDGET_SECS ;; esac
jq -cn --arg root "$ROOT" --arg head "$HEAD_SHA" --arg mb "$MB" --argjson sel "$SELECTION" --argjson budget "$BUDGET" \
    '{root: $root, head: $head, merge_base: $mb, budget_secs: $budget, invocations: $sel.invocations}' > "$HEAD_DIR/run.json" \
    || { rm -f "$LOCK"; die "could not write run.json"; }

# 6. Detach. `set -m` gives the background job its own process group, so the
#    group kill koto applies to this action never reaches the supervisor.
set -m
(
    unset KOTO_TICK_SESSION
    exec "$SELF" --supervise "$HEAD_DIR"
) </dev/null >>"$HEAD_DIR/supervisor.log" 2>&1 &
SUP=$!
set +m
ln -s "$SUP" "$LOCK.new" && mv -f "$LOCK.new" "$LOCK"
exit 0
