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
#       0. A koto key `hosted_of_record` (the hosted-of-record route's record,
#          written by verification-route.sh --record) whose head is not this
#          HEAD is removed (`koto context remove`), so a record left from an
#          earlier head never changes what a run at this head does. A key at
#          this head is kept. koto failing is exit 2; koto not on PATH skips
#          the step, since no key can exist without koto to hold it.
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
#       4b. In a fix round, carry what the run it follows passed (below).
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
#       Internal: the supervisor. Never calls koto (only --start's step 0
#       does).
#
# --base-ref names the default branch. Without it: the ref origin/HEAD points
# at, else origin/main, else main.
#
# A fix round's carry (step 4b). A session whose koto context holds
# `fix_round.json` ({from, round, base}, written by fix-round.sh) is a fix
# round, and `base` is the head the run it follows left. That run is the
# previous round (the line before this session's in the original's
# `fix_rounds.jsonl`), else `from`. Its result at `base` is found by the same
# path rules as --locate, with that session and head = base. Selection for the
# result is still the merge-base diff, so the round's set of checks is a full
# run's; only what runs changes. For each selected check:
#   - the parent's record for the same check passed (`outcome` passed or
#     carried) with the same argv, and the round's own diff
#     (`git diff --name-only <base>..HEAD`, selected through the same map)
#     doesn't select it: it doesn't run. Its record is written with
#     `outcome: carried` and `carried_from: {session, head}` naming the parent
#     result, exit_status 0, duration_secs 0, not_started false, log and
#     suites null;
#   - the parent passed it and the round's diff selects it: it runs, and an
#     `each` row's command (check `<row id>:<leaf>`) gets
#     SHIRABE_VERIFY_BASE=<base> in its environment, so check-skill.sh
#     --changed diffs against the round's base, not the merge-base;
#   - otherwise (the parent failed it, timed out, never ran it, or has no
#     result at base) it runs as in a full run, with no SHIRABE_VERIFY_BASE.
# The carry is off, and every selected check runs, with no fix_round.json,
# with `fresh: true` in it (fix-round.sh start --fresh), with
# SHIRABE_VERIFY_FULL=1 in --start's environment, or when the base or the
# parent's result can't be read; each but the first says so on stderr. koto
# runs this launcher in a cleared environment, so SHIRABE_VERIFY_FULL=1 takes
# effect on a --start run by hand. A koto failure reading the keys is exit 2,
# as in step 0. A result already at this head stands either way: move it
# aside to run again.
#
# Where things go: ${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/
# <session>/<head>/, every directory created with mode 0700, outside every
# repository, and only the ten most recent heads per session kept. The head
# directory holds the supervisor's log, one log per command, and result.json,
# written atomically:
#
#   {"schema": "shirabe-verification-result/v1", "head": "...",
#    "merge_base": "...", "status": "done|no-map|bad-map|attended|dirty-tree|
#    timed-out|supervisor-error", "detail": "...", "finished_at": "<UTC
#    ISO-8601>", "commands": [{"id", "check", "argv", "exit_status",
#    "duration_secs", "timed_out", "runaway", "not_started", "pgid", "log",
#    "outcome", "suites", "carried_from"}]}
#
# `carried_from` ({session, head}) is on a carried record only.
#
# `id` is the map row's id; `check` names the check the record is: the row id
# for a plain row, `<row id>:<last argv>` for an `each` row (check-skill's
# `check-skill:coordinate`), so two runs of one row are told apart.
# `finished_at` is when the result was written; the hosted-of-record record's
# taken_at may not be earlier.
#
# Each command's `outcome` says how it ended, as one of five values:
#   passed            exit 0 inside its limit;
#   carried           not run: a fix round's parent passed it at the round's
#                     base and the round's diff doesn't select it (above);
#                     the verdict counts it as passed;
#   timed-out-limit   stopped at its timeout_secs (or the run's budget), unless
#                     its suite summary lists a finished-failed suite;
#   timed-out-inside  a nonzero exit from a row that declares `timeout_form`,
#                     where the log reports at least one failure line and every
#                     failure line matches the form;
#   failed            anything else: a nonzero exit, a stop at the limit with
#                     a finished-failed suite, a runaway, a command that never
#                     started (whose flags still say which).
# A failure line is one check-skill.sh's own report counts as one: optional
# leading space and a colour code, then FAIL or `not ok` (FAILURE_LINE_RE).
# `suites` is the summary the command left at $SHIRABE_SUITE_SUMMARY, which the
# supervisor sets to <head dir>/<index>-<id>.suites.json for each command and
# clears before it starts, so a file an earlier run left is never read: an
# object of four string arrays, passed, failed, running and not_started, or
# null when the command wrote none (or wrote something else).
# check-verification.sh ranks the verdict on outcome (its header has the
# order): a failed record exits 1, a timed-out one exits 5 when the
# hosted-of-record route is open and 4 when it isn't.
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
# The failure lines a timeout_form is matched against: the pattern
# check-skill.sh's show_suite_failure uses to pick a failed suite's FAIL lines,
# in jq's regex syntax (passed with --arg, so read as written).
FAILURE_LINE_RE='^[[:space:]]*(\x1b\[[0-9;]*m)?(FAIL|not ok)([^A-Za-z]|$)'

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
# components, `*` within one; every other character is literal. Each
# invocation carries its row's validated `timeout_form` (null when the row has
# none) and `hosted` ([] when the row declares none), so a later reader takes
# them from run.json rather than parsing the map again. `hosted` names nothing
# that runs here: it is the row's declaration of the hosted jobs that run its
# suites, for the hosted-of-record route to read. `check` is the record's
# check id (see the header).
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
  | need((has("timeout_form") | not)
         or ((.timeout_form | type) == "string" and .timeout_form != ""
             and (.timeout_form as $f | try ("" | test($f) | true) catch false));
         "command \($id): timeout_form is not a non-empty string that compiles as a regular expression")
  | need((has("hosted") | not) or ((.hosted | type) == "array" and (.hosted | length) > 0);
         "command \($id): hosted is not a non-empty array")
  | need((has("hosted") | not)
         or (.hosted | all(type == "object"
                           and all(.workflow, .job, .runs; type == "string" and . != "")));
         "command \($id): hosted has an entry that is not an object with non-empty string workflow, job and runs")
  | need((has("hosted") | not)
         or (.hosted | all(.workflow | startswith(".github/workflows/")
                                       and (split("/") | all(. != ".." and . != "." and . != ""))));
         "command \($id): hosted names a workflow outside .github/workflows/")
  | {id: $id, run: .run, each: (.each // null), timeout_secs: (.timeout_secs // 1800),
     max_procs: (.max_procs // 256), unattended: (if has("unattended") then .unattended else true end),
     timeout_form: (.timeout_form // null), hosted: (.hosted // [])};
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
     | if $c.each == null then {id: $c.id, check: $c.id, argv: $c.run, timeout_secs: $c.timeout_secs, max_procs: $c.max_procs, unattended: $c.unattended,
                                timeout_form: $c.timeout_form, hosted: $c.hosted}
       else ($c.each | glob_re) as $er
         | $dirs[] | select(test($er))
         | (split("/") | last) as $leaf
         | {id: $c.id, check: "\($c.id):\($leaf)", argv: ($c.run + [$leaf]), timeout_secs: $c.timeout_secs, max_procs: $c.max_procs, unattended: $c.unattended,
            timeout_form: $c.timeout_form, hosted: $c.hosted}
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

# now_iso: the current UTC time, as a result's finished_at.
now_iso() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# settle <status> <detail> [<commands json>]: write a result that needs no run.
settle() {
    write_result "$RESULT" "$(jq -cn --arg schema "$RESULT_SCHEMA" --arg head "$HEAD_SHA" --arg mb "$MB" \
        --arg status "$1" --arg detail "$2" --argjson commands "${3:-[]}" --arg fin "$(now_iso)" \
        '{schema: $schema, head: $head, merge_base: $mb, status: $status, detail: $detail, finished_at: $fin,
          commands: $commands}')" \
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

# suites_of <file>: the suite summary a command left at <file>, compact, when
# it is one object of the four string arrays; null otherwise (no file, a file
# that doesn't parse, or one of another shape).
suites_of() {
    local s
    [ -f "$1" ] || { echo null; return 0; }
    s=$(jq -cs 'if length == 1 and (.[0] | type) == "object"
                   and ([.[0] as $o | ("passed", "failed", "running", "not_started") as $k
                         | ($o[$k] | type) == "array" and all($o[$k][]; type == "string")] | all)
                then .[0] | {passed, failed, running, not_started} else null end' "$1" 2>/dev/null)
    printf '%s\n' "${s:-null}"
}

# outcome_of <exit status> <timed_out> <runaway> <suites json> <timeout_form> <log>:
# the record's outcome (see the header). A stop at the limit with a
# finished-failed suite is failed: the change broke a check before the clock
# ran out. A nonzero exit counts as timed-out-inside only when the row
# declares a form and the log has at least one failure line, all of which
# match it; an empty set of failures never reads as a timeout.
outcome_of() {
    if [ "$3" = true ]; then
        echo failed
    elif [ "$2" = true ]; then
        if printf '%s' "$4" | jq -e '. != null and (.failed | length) > 0' >/dev/null; then
            echo failed
        else
            echo timed-out-limit
        fi
    elif [ "$1" -eq 0 ]; then
        echo passed
    elif [ -n "$5" ] && [ -f "$6" ] && jq -Rne --arg re "$FAILURE_LINE_RE" --arg form "$5" \
            '[inputs | select(test($re))] as $l | ($l | length) > 0 and all($l[]; test($form))' "$6" >/dev/null 2>&1; then
        echo timed-out-inside
    else
        echo failed
    fi
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
    : > "$SUP_ENTRIES"

    # Whatever stops the supervisor, a result gets written, so the verdict
    # never waits on a supervisor that is gone.
    finish() {
        [ "$SUP_WRITTEN" -eq 1 ] && return 0
        write_result "$RESULT" "$(jq -cs --arg schema "$RESULT_SCHEMA" --arg head "$HEAD_SHA" --arg mb "$MB" --arg fin "$(now_iso)" \
            '{schema: $schema, head: $head, merge_base: $mb, status: "supervisor-error",
              detail: "the supervisor stopped before every command ran", finished_at: $fin, commands: .}' "$SUP_ENTRIES")"
        rm -f "$SUP_LOCK" "$SUP_ENTRIES"
    }
    # A signal that stops the supervisor stops the running command too. The
    # command has its own process group, so nothing sent to the supervisor
    # reaches it, and exiting without this left it and everything it started
    # running after the supervisor was gone. The same TERM, then KILL, as a
    # command past its deadline.
    stop_running() {
        [ -n "$SUP_PGID" ] || return 0
        kill_group TERM "$SUP_PGID"; sleep 1; kill_group KILL "$SUP_PGID"
        SUP_PGID=""
    }
    trap finish EXIT
    trap 'stop_running; exit 1' HUP INT TERM

    cd "$ROOT" || exit 1

    local scope=0
    if command -v systemd-run >/dev/null 2>&1 \
        && systemd-run --user --scope --quiet -p TasksMax=8 true </dev/null >/dev/null 2>&1; then
        scope=1
    fi

    local n i id safe limit maxp prog log start now pid status timed_out runaway count carried vbase
    local budget sup_start left capped=0 over=0 stopped="" sumf form suites outcome
    budget=$(jq -r ".budget_secs // $BUDGET_SECS" "$RUN")
    case "$budget" in ''|*[!0-9]*|0) budget=$BUDGET_SECS ;; esac
    sup_start=$(date +%s)
    n=$(jq '.invocations | length' "$RUN")
    i=0
    while [ "$i" -lt "$n" ]; do
        id=$(jq -r --argjson i "$i" '.invocations[$i].id' "$RUN")
        # A fix round's carried check: its record was written by --start, and
        # nothing runs.
        carried=$(jq -c --argjson i "$i" '.invocations[$i].carried // empty' "$RUN")
        if [ -n "$carried" ]; then
            printf '%s\n' "$carried" >> "$SUP_ENTRIES"
            i=$((i + 1)); continue
        fi
        vbase=$(jq -r --argjson i "$i" '.invocations[$i].verify_base // empty' "$RUN")
        limit=$(jq -r --argjson i "$i" '.invocations[$i].timeout_secs' "$RUN")
        # The run's budget caps each command's own deadline.
        left=$((sup_start + budget - $(date +%s)))
        if [ "$left" -le 0 ]; then
            over=1; break
        fi
        capped=0
        if [ "$left" -lt "$limit" ]; then
            limit=$left; capped=1
        fi
        maxp=$(jq -r --argjson i "$i" '.invocations[$i].max_procs' "$RUN")
        argv=()
        while IFS= read -r -d '' a; do argv+=("$a"); done < <(jq -j --argjson i "$i" '.invocations[$i].argv[] | (., "\u0000")' "$RUN")
        safe=$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')
        log="$dir/$i-$safe.log"
        # The command's suite summary. Removed first, so a file a run before
        # this one left at the path is never read as this command's.
        sumf="$dir/$i-$safe.suites.json"
        rm -f "$sumf"
        form=$(jq -r --argjson i "$i" '.invocations[$i].timeout_form // empty' "$RUN")
        prog=${argv[0]}
        case "$prog" in
            /*) ;;
            */*) prog="$ROOT/$prog" ;;
            *) prog=$(type -P "$prog" 2>/dev/null) ;;
        esac
        if [ -z "$prog" ] || [ ! -f "$prog" ] || [ ! -x "$prog" ]; then
            jq -cn --arg id "$id" --argjson i "$i" --slurpfile run "$RUN" --arg log "$log" \
                '{id: $id, check: $run[0].invocations[$i].check, argv: $run[0].invocations[$i].argv, exit_status: null, duration_secs: 0,
                  timed_out: false, runaway: false, not_started: true, pgid: null, log: $log,
                  outcome: "failed", suites: null}' >> "$SUP_ENTRIES"
            echo "not started: [${argv[0]}] is not an executable program" > "$log"
            i=$((i + 1)); continue
        fi
        argv[0]=$prog

        start=$(date +%s)
        timed_out=false; runaway=false
        # The round's base, for the command the round's diff selects; no other
        # command sees one.
        if [ -n "$vbase" ]; then
            export SHIRABE_VERIFY_BASE="$vbase"
        else
            unset SHIRABE_VERIFY_BASE
        fi
        set -m
        if [ "$scope" -eq 1 ]; then
            SHIRABE_SUITE_SUMMARY=$sumf systemd-run --user --scope --quiet -p "TasksMax=$((maxp * 2 + 64))" -- "${argv[@]}" </dev/null >"$log" 2>&1 &
        else
            SHIRABE_SUITE_SUMMARY=$sumf "${argv[@]}" </dev/null >"$log" 2>&1 &
        fi
        pid=$!
        SUP_PGID=$pid
        set +m
        # The job's process group is its pid: job control put it there.
        while kill -0 "$pid" 2>/dev/null; do
            count=$(count_group "$pid")
            if [ "$count" -gt "$maxp" ]; then
                kill_group KILL "$pid"; runaway=true; break
            fi
            now=$(date +%s)
            if [ $((now - start)) -ge "$limit" ]; then
                kill_group TERM "$pid"; sleep 1; kill_group KILL "$pid"; timed_out=true; break
            fi
            sleep 0.25
        done
        # The leader may exit leaving its group behind; a group still past the
        # bound at that point is a runaway too.
        if [ "$runaway" = false ] && [ "$timed_out" = false ] && [ "$(count_group "$pid")" -gt "$maxp" ]; then
            runaway=true
        fi
        wait "$pid" 2>/dev/null
        status=$?
        kill_group KILL "$pid"
        SUP_PGID=""
        now=$(date +%s)
        suites=$(suites_of "$sumf")
        outcome=$(outcome_of "$status" "$timed_out" "$runaway" "$suites" "$form" "$log")
        jq -cn --arg id "$id" --argjson i "$i" --slurpfile run "$RUN" --argjson status "$status" \
            --argjson dur $((now - start)) --argjson to "$timed_out" --argjson ra "$runaway" \
            --argjson pgid "$pid" --arg log "$log" --arg outcome "$outcome" --argjson suites "$suites" \
            '{id: $id, check: $run[0].invocations[$i].check, argv: $run[0].invocations[$i].argv, exit_status: $status, duration_secs: $dur,
              timed_out: $to, runaway: $ra, not_started: false, pgid: $pgid, log: $log,
              outcome: $outcome, suites: $suites}' >> "$SUP_ENTRIES"
        i=$((i + 1))
        if [ "$timed_out" = true ] && [ "$capped" -eq 1 ]; then
            over=1; stopped=$id; break
        fi
    done

    local final=done detail="" left_ids
    if [ "$over" -eq 1 ]; then
        final=timed-out
        detail="the run passed its total budget of $budget seconds"
        [ -n "$stopped" ] && detail="$detail; command $stopped was stopped"
        # A carried check after the stop needs no time: its record is kept,
        # and only the checks that would have run are counted as not started.
        jq -c --argjson i "$i" '.invocations[$i:][] | .carried // empty' "$RUN" >> "$SUP_ENTRIES"
        left_ids=$(jq -r --argjson i "$i" '[.invocations[$i:][] | select(.carried == null) | .id] | join(", ")' "$RUN")
        [ -n "$left_ids" ] && detail="$detail; $(jq -r --argjson i "$i" '[.invocations[$i:][] | select(.carried == null)] | length' "$RUN") later command(s) were not started: $left_ids"
    fi
    write_result "$RESULT" "$(jq -cs --arg schema "$RESULT_SCHEMA" --arg head "$HEAD_SHA" --arg mb "$MB" \
        --arg status "$final" --arg detail "$detail" --arg fin "$(now_iso)" \
        '{schema: $schema, head: $head, merge_base: $mb, status: $status, detail: $detail, finished_at: $fin,
          commands: .}' "$SUP_ENTRIES")" \
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

# 0. A hosted-of-record key from another head is no record for this one.
#    Removed before anything else, so a result reused below, or one that then
#    passes, never meets a record the head it is for didn't take.
drop_stale_record() {
    local rc key head
    command -v koto >/dev/null 2>&1 || return 0
    koto context exists "$SESSION" hosted_of_record
    rc=$?
    case "$rc" in
        0) ;;
        1) return 0 ;;
        *) die "koto context exists $SESSION hosted_of_record exited $rc" ;;
    esac
    key=$(koto context get "$SESSION" hosted_of_record) \
        || die "could not read the hosted_of_record key of $SESSION"
    # A key that doesn't parse names no head, so it is stale too; jq's
    # message stays on stderr.
    head=$(printf '%s' "$key" | jq -r 'if type == "object" and (.head | type) == "string" then .head else "" end') || head=""
    [ "$head" = "$HEAD_SHA" ] && return 0
    koto context remove "$SESSION" hosted_of_record \
        || die "could not remove the hosted_of_record key of $SESSION, recorded for [$head], not $HEAD_SHA"
    echo "run-verification: removed the hosted_of_record key recorded for [$head]; this head is $HEAD_SHA" >&2
}
drop_stale_record

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
            | {id, check, argv, exit_status: null, duration_secs: 0, timed_out: false, runaway: false,
               not_started: true, pgid: null, log: null, outcome: "failed", suites: null}]')"
fi

# 4b. A fix round's carry (see the header). Sets INVOCATIONS: the selection's
#     invocations, each with `carried` (the record to write in place of a run)
#     or `verify_base` (SHIRABE_VERIFY_BASE for its command) where the carry
#     applies.
INVOCATIONS=$(printf '%s' "$SELECTION" | jq -c '.invocations') || die "could not read the selection"

# The parent result's records against this selection: a passed (or carried)
# record for the same check and argv that the round's diff doesn't select is
# carried; one the round's diff selects runs, an each row's with the base.
CARRY_JQ='
($parent.commands // [] | map(select(type == "object"))) as $pc
| map(. as $inv
    | ([$pc[] | select(.check == $inv.check)][0]) as $p
    | ($p != null and ($p.outcome == "passed" or $p.outcome == "carried") and $p.argv == $inv.argv
       and $p.not_started != true and $p.runaway != true and $p.timed_out != true) as $ok
    | ($round | index([$inv.check]) != null) as $touched
    | if $ok and ($touched | not) then
        . + {carried: {id: $p.id, check: $p.check, argv: $p.argv, exit_status: 0, duration_secs: 0,
                       timed_out: false, runaway: false, not_started: false, pgid: null, log: null,
                       outcome: "carried", suites: null, carried_from: {session: $from, head: $base}}}
      elif $ok and $inv.check != $inv.id then . + {verify_base: $base}
      else . end)
'

# note <message>: why the carry is off or what it did, on stderr.
note() {
    echo "run-verification: fix round: $*" >&2
}

carry() {
    local rc fr from round fresh base prev rounds parent_result round_changed round_sel round_checks out
    command -v koto >/dev/null 2>&1 || return 0
    koto context exists "$SESSION" fix_round.json
    rc=$?
    case "$rc" in
        0) ;;
        1) return 0 ;;
        *) die "koto context exists $SESSION fix_round.json exited $rc" ;;
    esac
    if [ "${SHIRABE_VERIFY_FULL:-}" = 1 ]; then
        note "SHIRABE_VERIFY_FULL=1, so nothing is carried; every selected check runs"
        return 0
    fi
    fr=$(koto context get "$SESSION" fix_round.json) || die "could not read the fix_round.json key of $SESSION"
    # One line per field, each empty when the key doesn't hold it as expected.
    out=$(printf '%s' "$fr" | jq -r 'if type == "object" then . else {} end
        | (.from | if type == "string" then . else "" end),
          (.round | if type != "number" then "" elif . == floor and . >= 1 then tostring else "" end),
          (.base | if type == "string" then . else "" end),
          (if .fresh == true then "true" else "false" end)') || out=""
    from=$(sed -n 1p <<<"$out"); round=$(sed -n 2p <<<"$out")
    base=$(sed -n 3p <<<"$out"); fresh=$(sed -n 4p <<<"$out")
    if [ "$fresh" = true ]; then
        note "fix_round.json has fresh: true, so nothing is carried; every selected check runs"
        return 0
    fi
    if ! grep -Eq '^[A-Za-z0-9._][A-Za-z0-9._-]*$' <<<"$from" || [ -z "$round" ] \
        || ! grep -Eq '^[0-9a-f]{40}([0-9a-f]{24})?$' <<<"$base"; then
        note "fix_round.json of $SESSION names no run, round or base head, so nothing is carried"
        return 0
    fi

    # The run this round follows: the previous round, else the original.
    prev=$from
    if [ "$round" -gt 1 ]; then
        koto context exists "$from" fix_rounds.jsonl
        rc=$?
        case "$rc" in
            0)
                rounds=$(koto context get "$from" fix_rounds.jsonl) \
                    || die "could not read the fix_rounds.jsonl key of $from"
                prev=$(printf '%s' "$rounds" | jq -rs --arg s "$SESSION" --argjson r "$round" --arg from "$from" '
                    map(select(type == "object")) as $l
                    | ($l | map(.session) | index($s)) as $i
                    | if $i == null then ([$l[] | select(.round == $r - 1) | .session][0] // $from)
                      elif $i > 0 then ($l[$i - 1].session // $from)
                      else $from end
                    | if type == "string" then . else $from end') || prev=$from
                ;;
            1) ;;
            *) die "koto context exists $from fix_rounds.jsonl exited $rc" ;;
        esac
        grep -Eq '^[A-Za-z0-9._][A-Za-z0-9._-]*$' <<<"$prev" || prev=$from
    fi

    if ! git -C "$ROOT" rev-parse --verify -q "${base}^{commit}" >/dev/null; then
        note "the round's base $base is not a commit here, so nothing is carried"
        return 0
    fi
    parent_result="${SESSION_DIR%/*}/$prev/$base/result.json"
    if [ ! -f "$parent_result" ]; then
        note "$prev has no verification result at the round's base $base, so nothing is carried"
        return 0
    fi
    if ! jq -e --arg schema "$RESULT_SCHEMA" --arg base "$base" \
            '.schema == $schema and .head == $base and (.commands | type) == "array"' "$parent_result" >/dev/null; then
        note "the result $parent_result is not a result for $base, so nothing is carried"
        return 0
    fi

    # The round's own diff, selected through the same map.
    if ! round_changed=$(set -o pipefail; git -C "$ROOT" diff --name-only -z "$base..HEAD" \
            | jq -Rs 'split("\u0000") | map(select(length > 0))'); then
        note "could not list the paths changed since the round's base $base, so nothing is carried"
        return 0
    fi
    round_sel=$(printf '%s' "$MAP_JSON" | jq -c --argjson changed "$round_changed" "$SELECT_JQ") \
        || die "the selection program failed on the round's diff"
    round_checks=$(printf '%s' "$round_sel" | jq -c 'if has("error") then null else [.invocations[].check] end')
    if [ "$round_checks" = null ] || [ -z "$round_checks" ]; then
        note "the map does not select on the round's diff, so nothing is carried"
        return 0
    fi

    INVOCATIONS=$(printf '%s' "$INVOCATIONS" | jq -c --slurpfile parent "$parent_result" \
        --argjson round "$round_checks" --arg from "$prev" --arg base "$base" \
        '$parent[0] as $parent | '"$CARRY_JQ") \
        || die "could not apply the carry from $parent_result"
    note "$(printf '%s' "$INVOCATIONS" | jq -r --arg p "$prev" --arg b "$base" '
        "carried \([.[] | select(.carried)] | length) check(s) \($p) passed at \($b); running \([.[] | select(.carried | not)] | length): \([.[] | select(.carried | not) | .check] | join(", "))"')"
}
carry

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
jq -cn --arg root "$ROOT" --arg head "$HEAD_SHA" --arg mb "$MB" --argjson inv "$INVOCATIONS" --argjson budget "$BUDGET" \
    '{root: $root, head: $head, merge_base: $mb, budget_secs: $budget, invocations: $inv}' > "$HEAD_DIR/run.json" \
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
