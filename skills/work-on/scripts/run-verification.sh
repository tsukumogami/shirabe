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
#       1. Resolve HEAD and the merge-base of HEAD and the default branch. With
#          koto on PATH, take the head's lock and, holding it, read the context
#          key `verification_rerun_request` (its text is the reason for a
#          re-run). Present: archive the result as --archive does (which runs
#          inside this hold rather than taking the lock again), remove the key,
#          release the lock and go on, so step 2 finds no result and a fresh
#          suite starts in the next attempt folder. A refused archive (a pass,
#          no result, a dirty tree, an empty reason, the cap spent, a ledger
#          that disagrees with the disk) removes the key all the same, says why
#          on stderr, and goes on as if there were no request, so a pass is
#          still reused. A failed read of the request, or of the ledger, keeps
#          the key and re-runs nothing: a failed read is not an empty ledger.
#          When another live process holds the lock, a suite is running at this
#          head, so a request names a result that is no longer current: the key
#          is removed without the lock and nothing is archived.
#       2. A result for this head and merge-base already on disk: exit 0.
#       3. Tracked files with uncommitted changes: write a `dirty-tree` result.
#       4. Read the map at the merge-base
#          (`git show <merge-base>:.claude/shirabe-extensions/verification-map.json`),
#          so a branch that edits the map is still verified by the map it
#          started from. Absent: a `no-map` result. Doesn't parse: `bad-map`.
#       5. Select commands for `git diff --name-only <merge-base>..HEAD`.
#          Nothing selected: `no-map`. A selected `unattended: false`
#          command: `attended`, and nothing is started.
#       6. A lock naming a live supervisor for this head: exit 0. A lock
#          whose process is gone is removed.
#       7. Take the next free attempt number n at this head, create
#          attempts/<n>/, record n in run.json as "attempt", start the
#          supervisor in its own process group (job control, not a
#          new-session command, which the macOS floor lacks), standard input from
#          /dev/null, both outputs to its log, koto's tick marker
#          (KOTO_TICK_SESSION) removed from its environment, and exit 0. None
#          of the koto calls in steps 0 and 1 waits on a suite, so this stays fast.
#   --archive --session <s> --reason <text> [--base-ref <ref>]
#       Set the result at this head aside so the next --start runs the suite
#       again. The reason is cleaned first (verification-eligibility.sh's
#       VE_CLEAN_JQ: control characters, newlines, ANSI escape sequences and
#       Unicode format characters stripped, capped at 500 characters). Then,
#       all under the head's lock, so no supervisor starts while the attempt
#       moves: the file checks, the ledger read, the count, the cross-check
#       against the disk, the eligibility check, the ledger write and the move.
#       Refuses, exit 1, moving nothing and writing nothing, when the reason is
#       empty after cleaning, koto is not on PATH, a live supervisor holds the
#       lock, there is no result for this head and merge-base, run.json records
#       an `attempt` that isn't a whole number from 1 to 999999999, the ledger
#       can't be read or doesn't parse, the ledger's count of lines at this head
#       and merge-base disagrees with the archived attempts/*/result.json files
#       at that pair, VE_CAP (2) attempts are already archived at the pair
#       (`over-cap`), or verification-eligibility.sh doesn't call the result
#       `eligible`. Otherwise it appends one JSON line for the outgoing attempt
#       to the koto context key `verification_attempts` (the ledger), reads the
#       key back and checks the line landed, and only then moves result.json
#       and run.json into attempts/<n>/, n being the attempt run.json records
#       (the next free folder for a run.json from before attempt folders).
#       Prints one line naming the archived attempt and exits 0.
#
#       One disagreement is recovered rather than refused: an archive stopped
#       between its ledger write and its move leaves a last ledger line at this
#       head and merge-base naming folder n, one line more than the disk
#       holds, and no attempts/<n>/result.json. Then the eligibility check runs
#       against the ledger without that line, and the move finishes without a
#       second line. A ledger line:
#
#         {"attempt": <ledger lines at the pair + 1>, "folder": n, "head",
#          "merge_base", "exit": 1, "status", "reason" (cleaned),
#          "archived_at": "<UTC ISO 8601>", "commands": [{"id" (cleaned),
#          "exit_status", "timed_out", "duration_secs",
#          "log": "attempts/<n>/<index>-<name>.log", or null for any other
#          path}]}
#   --locate --session <s> [--base-ref <ref>]
#       Print three lines: the head, the merge-base, and the result file's
#       path. check-verification.sh calls this so the path rules live here.
#   --supervise <dir>
#       Internal: the supervisor. Never calls koto (only --start's steps 0
#       and 1 do).
#
# --base-ref names the default branch. Without it: the ref origin/HEAD points
# at, else origin/main, else main.
#
# Where things go: ${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/
# <session>/<head>/, every directory created with mode 0700, outside every
# repository, and only the ten most recent heads per session kept. The head
# directory holds the supervisor's log, run.json, the lock and result.json, and
# one folder per attempt, attempts/<n>/, numbered from 1, holding that
# attempt's command logs (<index>-<id>.log, mode 0600, the id with every
# character outside [A-Za-z0-9._-] replaced) and, once archived, its
# result.json and run.json. A run.json from before attempt folders, with no
# "attempt", keeps its command logs in the head directory itself. result.json
# is written atomically:
#
#   {"schema": "shirabe-verification-result/v1", "head": "...",
#    "merge_base": "...", "status": "done|no-map|bad-map|attended|dirty-tree|
#    timed-out|supervisor-error", "detail": "...", "finished_at": "<UTC
#    ISO-8601>", "commands": [{"id", "check", "argv", "exit_status",
#    "duration_secs", "timed_out", "runaway", "not_started", "pgid", "log",
#    "outcome", "suites"}]}
#
# `id` is the map row's id; `check` names the check the record is: the row id
# for a plain row, `<row id>:<last argv>` for an `each` row (check-skill's
# `check-skill:coordinate`), so two runs of one row are told apart.
# `finished_at` is when the result was written; the hosted-of-record record's
# taken_at may not be earlier.
#
# Each command's `outcome` says how it ended, as one of four values:
#   passed            exit 0 inside its limit;
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
# running, or --archive archived); 1 --archive refused; 2 it could not decide
# (usage, a missing tool, no HEAD, no merge-base, no state directory). The
# verdict is never this script's exit.
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
       run-verification.sh --archive --session <s> --reason <text> [--base-ref <ref>]
       run-verification.sh --locate --session <s> [--base-ref <ref>]
EOF
}

die() {
    echo "run-verification: $*" >&2
    exit 2
}

# shellcheck source=SCRIPTDIR/verification-eligibility.sh
. "$HERE/verification-eligibility.sh" || die "cannot load verification-eligibility.sh"

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
    # The head names a directory that --archive moves files under and prune
    # removes, so it is checked before it forms any path (SESSION is checked
    # where the arguments are read).
    case "$HEAD_SHA" in
        ''|.|..|*[!A-Za-z0-9._-]*) die "HEAD [$HEAD_SHA] is not a head name" ;;
    esac
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

# lock_other <lock>: true when the lock names a running supervisor of ours
# that is not this process. lock_live is true for this process too, so a step
# that asks "is someone else running?" asks this instead, and a lock this
# process holds never reads as a suite to wait for.
lock_other() {
    [ "$(readlink "$1" 2>/dev/null)" = "$$" ] && return 1
    lock_live "$1"
}

LOCK_TOOK=0
LOCK_HOLDER=""

# lock_take <lock>: hold the lock for this process. Returns 0 holding it, with
# LOCK_TOOK=1 when this call created it and LOCK_TOOK=0 when it already named
# this process: --start's consume_request takes the lock and then calls
# archive_attempt, which takes it again, and the inner call must not release
# the outer hold. Returns 1 when it can't: LOCK_HOLDER is the pid of the live
# process that holds it, or empty when the lock couldn't be created at all. A
# lock whose process is gone is removed and taken.
lock_take() {
    LOCK_TOOK=0
    LOCK_HOLDER=""
    [ "$(readlink "$1" 2>/dev/null)" = "$$" ] && return 0
    if ln -s "$$" "$1" 2>/dev/null; then
        LOCK_TOOK=1
        return 0
    fi
    if lock_live "$1"; then
        LOCK_HOLDER=$(readlink "$1" 2>/dev/null)
        return 1
    fi
    rm -f "$1"
    if ln -s "$$" "$1" 2>/dev/null; then
        LOCK_TOOK=1
        return 0
    fi
    # Another start took it between the two attempts.
    lock_live "$1" && LOCK_HOLDER=$(readlink "$1" 2>/dev/null)
    return 1
}

# lock_release <lock> <took>: remove the lock when <took> is 1 (this caller's
# own lock_take created it) and it still names this process.
lock_release() {
    [ "${2:-0}" = 1 ] || return 0
    [ "$(readlink "$1" 2>/dev/null)" = "$$" ] && rm -f "$1"
    return 0
}

# --- attempts and the ledger ---------------------------------------------------------

LEDGER_KEY=verification_attempts
REQUEST_KEY=verification_rerun_request

# next_attempt: print the next free attempt number at HEAD_DIR, 1 when
# attempts/ holds no numeric folder.
next_attempt() {
    local max=0 d name
    for d in "$HEAD_DIR"/attempts/*; do
        [ -d "$d" ] || continue
        name=${d##*/}
        case "$name" in ''|*[!0-9]*) continue ;; esac
        [ "${#name}" -le 9 ] || continue
        # 10# so a leading zero never reads as octal.
        [ $((10#$name)) -gt "$max" ] && max=$((10#$name))
    done
    echo $((max + 1))
}

# ctx_read <key>: read a koto context key for SESSION. Sets CTX_PRESENT (1 or
# 0) and CTX_VALUE (empty for an absent key) and returns 0, or returns 1 when
# the read failed. An absent key is `koto context exists` exiting 1 with
# nothing on stdout; any other failure is a failed read, never an empty value.
ctx_read() {
    local out rc
    CTX_VALUE=""
    CTX_PRESENT=0
    out=$(koto context exists "$SESSION" "$1")
    rc=$?
    if [ "$rc" -eq 1 ] && [ -z "$out" ]; then
        return 0
    fi
    [ "$rc" -eq 0 ] || return 1
    CTX_VALUE=$(koto context get "$SESSION" "$1") || { CTX_VALUE=""; return 1; }
    CTX_PRESENT=1
    return 0
}

# count_lines <text>: the number of non-empty lines.
count_lines() {
    printf '%s\n' "$1" | grep -c .
}

# ledger_fetch <out-file>: write the ledger's non-empty lines to <out-file>, an
# empty file for a missing key. Returns 1 on a failed read, which is never an
# empty ledger. verification-eligibility.sh reads only files, so the koto read
# stays here, with ctx_read's missing-key rule.
ledger_fetch() {
    : > "$1" || return 1
    ctx_read "$LEDGER_KEY" || return 1
    [ "$CTX_PRESENT" -eq 1 ] || return 0
    printf '%s\n' "$CTX_VALUE" | grep . > "$1"
    # grep exits 1 for a value with no non-empty line, which is an empty ledger.
    [ $? -le 1 ] || return 1
    return 0
}

# archived_at_pair: how many attempts/<n>/result.json files under HEAD_DIR are
# for this head and merge-base. A file jq can't read is not at the pair, and
# jq's error is left on stderr so the damaged file is seen.
archived_at_pair() {
    local count=0 f d name
    for f in "$HEAD_DIR"/attempts/*/result.json; do
        [ -f "$f" ] || continue
        d=${f%/result.json}
        name=${d##*/}
        case "$name" in ''|*[!0-9]*) continue ;; esac
        jq -e --arg head "$HEAD_SHA" --arg mb "$MB" '.head == $head and .merge_base == $mb' "$f" >/dev/null \
            && count=$((count + 1))
    done
    echo "$count"
}

RUN_ATTEMPT=""

# run_attempt <run.json>: set RUN_ATTEMPT to the attempt the file records and
# return 0; RUN_ATTEMPT is empty for a missing file or one with no `attempt`
# key, a run.json from before attempt folders, whose caller falls back to
# next_attempt. Returns 1 when `attempt` is present but isn't a whole number
# from 1 to 999999999, or the file doesn't parse, RUN_ATTEMPT then holding the
# value as JSON, cleaned, for the message. The number forms a path that mv
# writes to, so nothing else gets through.
run_attempt() {
    local v
    RUN_ATTEMPT=""
    [ -e "$1" ] || return 0
    v=$(jq -r "$VE_CLEAN_JQ"'
        if type != "object" then "bad " + (tojson | clean)
        elif (has("attempt") | not) then "none"
        elif (.attempt | type) == "number" and .attempt == (.attempt | floor)
             and .attempt >= 1 and .attempt <= 999999999
        then "ok \(.attempt | floor)"
        else "bad " + (.attempt | tojson | clean) end' "$1") || v="bad unreadable"
    case "$v" in
        none) return 0 ;;
        "ok "*)
            RUN_ATTEMPT=${v#ok }
            case "$RUN_ATTEMPT" in
                ''|*[!0-9]*) return 1 ;;
            esac
            return 0
            ;;
    esac
    RUN_ATTEMPT=${v#bad }
    return 1
}

ARCH_TMP=""
ARCH_LOCKED=0

# archive_done <status>: remove the temporary folder, release the lock if
# archive_attempt's own lock_take created it (not when it ran inside
# consume_request's hold), and return <status>.
archive_done() {
    [ -n "$ARCH_TMP" ] && rm -rf "$ARCH_TMP"
    ARCH_TMP=""
    lock_release "$HEAD_DIR/lock" "$ARCH_LOCKED"
    ARCH_LOCKED=0
    return "$1"
}

# archive_refuse <reason>: say why on stderr and return 1, having moved
# nothing.
archive_refuse() {
    echo "run-verification: archive refused: $*" >&2
    archive_done 1
}

# archive_attempt <reason>: archive the result at HEAD_DIR (see --archive in
# the header). Needs resolve() to have run. Returns 0 once the ledger line is
# confirmed and the files are moved (or, in recovery, the move is finished), 1
# on a refusal, and 3 when the ledger read failed, so consume_request can keep
# the request. Everything after the reason and the koto check runs under the
# head's lock. A lock this call took is released before it returns, so a
# --start that follows can take it; inside consume_request's hold it takes
# nothing and releases nothing.
archive_attempt() {
    local reason elig n adir at disk mode prior last k status line back back_count back_last lcount
    reason=$(verification_clean "$1") || reason=""
    [ -n "$reason" ] || { archive_refuse "the reason is empty after cleaning"; return 1; }
    command -v koto >/dev/null || { archive_refuse "koto is not on PATH"; return 1; }
    [ -d "$HEAD_DIR" ] || { archive_refuse "there is no result for $HEAD_SHA"; return 1; }

    # The lock first, so no supervisor starts at this head while the checks
    # below run and the result moves. Its refusal comes before any file check.
    if ! lock_take "$HEAD_DIR/lock"; then
        if [ -n "$LOCK_HOLDER" ]; then
            archive_refuse "a verification run for $HEAD_SHA is still running"
        else
            archive_refuse "could not take the lock at $HEAD_SHA"
        fi
        return 1
    fi
    ARCH_LOCKED=$LOCK_TOOK

    [ -L "$RESULT" ] && { archive_refuse "$RESULT is a symlink"; return 1; }
    [ -L "$HEAD_DIR/run.json" ] && { archive_refuse "$HEAD_DIR/run.json is a symlink"; return 1; }
    [ -L "$HEAD_DIR/attempts" ] && { archive_refuse "$HEAD_DIR/attempts is a symlink"; return 1; }
    [ -f "$RESULT" ] || { archive_refuse "there is no result for $HEAD_SHA"; return 1; }
    jq -e --arg head "$HEAD_SHA" --arg mb "$MB" '.head == $head and .merge_base == $mb' "$RESULT" >/dev/null \
        || { archive_refuse "the result at $HEAD_SHA is not for merge-base $MB"; return 1; }

    if ! run_attempt "$HEAD_DIR/run.json"; then
        archive_refuse "run.json records attempt [$RUN_ATTEMPT], which is not a whole number from 1 to 999999999"
        return 1
    fi
    n=$RUN_ATTEMPT
    [ -n "$n" ] || n=$(next_attempt)
    adir="$HEAD_DIR/attempts/$n"
    [ -L "$adir" ] && { archive_refuse "$adir is a symlink"; return 1; }

    # The trap covers a signal between here and archive_done, which removes it
    # on every return.
    trap 'if [ -n "$ARCH_TMP" ]; then rm -rf "$ARCH_TMP"; fi' EXIT
    ARCH_TMP=$(mktemp -d "${TMPDIR:-/tmp}/run-verification.XXXXXX") \
        || { ARCH_TMP=""; archive_refuse "could not create a temporary folder"; return 1; }

    if ! ledger_fetch "$ARCH_TMP/ledger.old"; then
        archive_refuse "could not read $LEDGER_KEY for session $SESSION"
        return 3
    fi
    # A line that will not parse refuses the archive before any write.
    at=$(verification_attempts_at "$ARCH_TMP/ledger.old" "$HEAD_SHA" "$MB") \
        || { archive_refuse "could not count the attempts in $LEDGER_KEY for session $SESSION"; return 1; }
    disk=$(archived_at_pair)

    # The ledger and the disk must agree on how many attempts are archived at
    # this pair, so a removed key or a pruned folder can't reset the count. A
    # ledger one line ahead of the disk is an archive stopped between its
    # write and its move, and only when its last line is at this pair, names
    # this attempt's folder, and that folder holds no result yet.
    if [ "$disk" -eq "$at" ]; then
        mode=normal
        prior=$at
        cp "$ARCH_TMP/ledger.old" "$ARCH_TMP/ledger.elig" \
            || { archive_refuse "could not copy the ledger to a temporary file"; return 1; }
        [ -e "$adir/result.json" ] && { archive_refuse "$adir already holds a result.json"; return 1; }
    else
        mode=""
        if [ "$disk" -eq $((at - 1)) ] && [ ! -e "$adir/result.json" ]; then
            last=$(tail -n 1 "$ARCH_TMP/ledger.old")
            if printf '%s\n' "$last" | jq -e --arg head "$HEAD_SHA" --arg mb "$MB" --argjson n "$n" \
                    '.head == $head and .merge_base == $mb and (.folder | type) == "number" and .folder == $n' \
                    >/dev/null; then
                mode=recover
            fi
        fi
        if [ "$mode" != recover ]; then
            archive_refuse "$LEDGER_KEY records $at attempt(s) at head $HEAD_SHA and merge-base $MB," \
                "but $disk archived result(s) at that pair are on disk under attempts/; they disagree," \
                "so nothing is archived. The ways out are a real fix (a new head) or implementation_status: blocked"
            return 1
        fi
        # The eligibility check sees the ledger as it was before the stopped
        # archive wrote, so the line being finished doesn't count against it.
        prior=$((at - 1))
        lcount=$(grep -c . "$ARCH_TMP/ledger.old")
        # awk rather than head: the count is 0 for a one-line ledger, and
        # BSD head refuses `-n 0`.
        awk -v n="$((lcount - 1))" 'NR <= n' "$ARCH_TMP/ledger.old" > "$ARCH_TMP/ledger.elig" \
            || { archive_refuse "could not copy the ledger to a temporary file"; return 1; }
    fi

    elig=$(verification_eligibility "$RESULT" "$ARCH_TMP/ledger.elig")
    case "$elig" in
        eligible) ;;
        over-cap)
            archive_refuse "the cap is spent: $prior attempts are already archived at head $HEAD_SHA and" \
                "merge-base $MB, and the cap is $VE_CAP re-runs per head and merge-base." \
                "The ways out are a real fix (a new head) or implementation_status: blocked"
            return 1
            ;;
        *) archive_refuse "the result at $HEAD_SHA is $elig"; return 1 ;;
    esac

    if [ "$mode" = normal ]; then
        k=$((at + 1))
        status=$(jq -r .status "$RESULT")
        # Command ids get the reason's cleaning. A log path is kept only in the
        # shape this script writes, attempts/<n>/<index>-<safe id>.log, relative
        # to the head directory; anything else is stored as null.
        line=$(jq -nc --argjson attempt "$k" --argjson folder "$n" \
            --arg head "$HEAD_SHA" --arg mb "$MB" --arg status "$status" --arg reason "$reason" \
            --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg hd "$HEAD_DIR/" --slurpfile result "$RESULT" "$VE_CLEAN_JQ"'
            def rel: if (type == "string") and startswith($hd) then .[($hd | length):] else null end
                     | if (type == "string") and test("^attempts/[0-9]+/[0-9]+-[A-Za-z0-9._-]+\\.log$") then . else null end;
            {attempt: $attempt, folder: $folder, head: $head, merge_base: $mb, exit: 1, status: $status,
             reason: $reason, archived_at: $at,
             commands: [$result[0].commands[] | {id: (.id | if type == "string" then clean else null end),
                                                 exit_status, timed_out, duration_secs, log: (.log | rel)}]}') \
            || { archive_refuse "could not build the ledger line"; return 1; }
        lcount=$(grep -c . "$ARCH_TMP/ledger.old")
        { cat "$ARCH_TMP/ledger.old" && printf '%s\n' "$line"; } > "$ARCH_TMP/ledger" \
            || { archive_refuse "could not write the ledger to a temporary file"; return 1; }
        [ -s "$ARCH_TMP/ledger" ] || { archive_refuse "could not write the ledger to a temporary file"; return 1; }
        koto context add "$SESSION" "$LEDGER_KEY" --from-file "$ARCH_TMP/ledger" >/dev/null \
            || { archive_refuse "could not write $LEDGER_KEY for session $SESSION"; return 1; }
        back=$(koto context get "$SESSION" "$LEDGER_KEY") \
            || { archive_refuse "could not read back $LEDGER_KEY for session $SESSION"; return 1; }
        back_count=$(count_lines "$back")
        back_last=$(printf '%s\n' "$back" | grep . | tail -n 1)
        if [ "$back_count" -ne $((lcount + 1)) ] || [ "$back_last" != "$line" ]; then
            archive_refuse "$LEDGER_KEY for session $SESSION did not take this attempt's line"
            return 1
        fi
    else
        k=$at
    fi

    # The ledger has the attempt; now, and only now, the files move.
    if [ ! -d "$adir" ]; then
        (umask 077 && mkdir -p "$adir") \
            || { archive_refuse "the ledger has attempt $k, but $adir could not be created"; return 1; }
    fi
    mv -f "$RESULT" "$adir/result.json" \
        || { archive_refuse "the ledger has attempt $k, but $RESULT could not be moved"; return 1; }
    if [ -f "$HEAD_DIR/run.json" ]; then
        mv -f "$HEAD_DIR/run.json" "$adir/run.json" \
            || { archive_refuse "attempt $k is archived, but $HEAD_DIR/run.json could not be moved"; return 1; }
    fi
    if [ "$mode" = normal ]; then
        echo "run-verification: archived attempt $k at $HEAD_SHA into attempts/$n"
    else
        echo "run-verification: finished archiving attempt $k at $HEAD_SHA into attempts/$n; its ledger line was already written"
    fi
    archive_done 0
}

CONSUME_LOCKED=0

# consume_done: release the lock if consume_request's own lock_take created
# it. Every return from consume_request past lock_take goes through here, so no
# branch leaves a lock naming this process for step 1 or step 5 to trip on.
consume_done() {
    lock_release "$HEAD_DIR/lock" "$CONSUME_LOCKED"
    CONSUME_LOCKED=0
    return 0
}

# consume_request: --start's step 1 (see the header). Never fails the start.
consume_request() {
    local rc
    command -v koto >/dev/null 2>&1 || return 0
    if ! lock_take "$HEAD_DIR/lock"; then
        if [ -z "$LOCK_HOLDER" ]; then
            echo "run-verification: could not take the lock at $HEAD_SHA; $REQUEST_KEY is kept and nothing is re-run" >&2
            return 0
        fi
        # A suite is running at this head. The result a request was judged on
        # is no longer the current one, and leaving the key would let a later
        # start archive a fresh failure nobody judged. This is the one removal
        # made without the lock, and it never archives.
        if ! ctx_read "$REQUEST_KEY"; then
            echo "run-verification: could not read $REQUEST_KEY for session $SESSION; the request is kept and nothing is re-run" >&2
            return 0
        fi
        [ "$CTX_PRESENT" -eq 1 ] || return 0
        echo "run-verification: rerun request dropped: a verification suite was running at this head (pid $LOCK_HOLDER)," \
            "so the request named a result that is no longer current; nothing was archived" >&2
        koto context remove "$SESSION" "$REQUEST_KEY" >/dev/null \
            || echo "run-verification: could not remove $REQUEST_KEY for session $SESSION" >&2
        return 0
    fi
    CONSUME_LOCKED=$LOCK_TOOK

    if ! ctx_read "$REQUEST_KEY"; then
        echo "run-verification: could not read $REQUEST_KEY for session $SESSION; the request is kept and nothing is re-run" >&2
        consume_done
        return 0
    fi
    if [ "$CTX_PRESENT" -ne 1 ]; then
        consume_done
        return 0
    fi
    archive_attempt "$CTX_VALUE" >&2
    rc=$?
    case "$rc" in
        0) ;;
        3)
            echo "run-verification: could not read $LEDGER_KEY for session $SESSION; $REQUEST_KEY is kept and nothing is re-run" >&2
            consume_done
            return 0
            ;;
        *) echo "run-verification: rerun request dropped: the archive was refused" >&2 ;;
    esac
    koto context remove "$SESSION" "$REQUEST_KEY" >/dev/null \
        || echo "run-verification: could not remove $REQUEST_KEY for session $SESSION" >&2
    consume_done
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

    local n i id safe limit maxp prog log start now pid status timed_out runaway count
    local budget sup_start left capped=0 over=0 stopped="" sumf form suites outcome attempt logdir
    # The attempt's folder holds its logs; a run.json without one (written
    # before attempt folders) keeps them in the head directory.
    logdir=$dir
    attempt=$(jq -r '.attempt // empty | numbers | tostring' "$RUN")
    case "$attempt" in
        ''|*[!0-9]*) ;;
        *)
            logdir="$dir/attempts/$attempt"
            if [ ! -d "$logdir" ]; then
                (umask 077 && mkdir -p "$logdir") || { echo "could not create $logdir" >&2; exit 1; }
            fi
            ;;
    esac
    budget=$(jq -r ".budget_secs // $BUDGET_SECS" "$RUN")
    case "$budget" in ''|*[!0-9]*|0) budget=$BUDGET_SECS ;; esac
    sup_start=$(date +%s)
    n=$(jq '.invocations | length' "$RUN")
    i=0
    while [ "$i" -lt "$n" ]; do
        id=$(jq -r --argjson i "$i" '.invocations[$i].id' "$RUN")
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
        log="$logdir/$i-$safe.log"
        # Created 0600 here, so the redirections below only truncate it; a
        # umask for the command itself would change what it creates.
        (umask 077 && : > "$log") 2>/dev/null
        chmod 600 "$log" 2>/dev/null
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

    local final=done detail=""
    if [ "$over" -eq 1 ]; then
        final=timed-out
        detail="the run passed its total budget of $budget seconds"
        [ -n "$stopped" ] && detail="$detail; command $stopped was stopped"
        [ "$i" -lt "$n" ] && detail="$detail; $((n - i)) later command(s) were not started: $(jq -r --argjson i "$i" '[.invocations[$i:][].id] | join(", ")' "$RUN")"
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
    --start|--locate|--archive) ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac

SESSION=""
BASE_REF=""
REASON=""
REASON_SET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --session)
            [ $# -ge 2 ] && [ -z "$SESSION" ] || { usage; exit 2; }
            SESSION=$2; shift 2 ;;
        --base-ref)
            [ $# -ge 2 ] && [ -z "$BASE_REF" ] || { usage; exit 2; }
            BASE_REF=$2; shift 2 ;;
        --reason)
            [ "$MODE" = --archive ] && [ $# -ge 2 ] && [ "$REASON_SET" -eq 0 ] || { usage; exit 2; }
            REASON=$2; REASON_SET=1; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done
[ -n "$SESSION" ] || { usage; exit 2; }
[ "$MODE" != --archive ] || [ "$REASON_SET" -eq 1 ] || { usage; exit 2; }
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

# --- --archive ---------------------------------------------------------------------------

if [ "$MODE" = --archive ]; then
    archive_attempt "$REASON" || exit 1
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

# 0. A re-run request, read before the reuse check below so an archived
#    result is not reused.
consume_request

# 1. A result for this head and merge-base stands, except a dirty-tree one,
#    which the next start re-checks once the tree is clean.
if [ -f "$RESULT" ]; then
    if jq -e --arg mb "$MB" '.merge_base == $mb and .status != "dirty-tree"' "$RESULT" >/dev/null; then
        exit 0
    fi
    # Another process's lock, not one this process holds: consume_request
    # releases its hold, but a lock naming this pid must never stop the start.
    lock_other "$HEAD_DIR/lock" && exit 0
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

# 5. One supervisor per head. The lock is a symlink whose target is a pid:
#    creating one is atomic, and so is renaming another over it. A lock that
#    already names this process counts as taken.
LOCK="$HEAD_DIR/lock"
lock_take "$LOCK" || exit 0

BUDGET=${SHIRABE_VERIFICATION_BUDGET_SECS:-$BUDGET_SECS}
case "$BUDGET" in ''|*[!0-9]*|0) BUDGET=$BUDGET_SECS ;; esac

# This run's attempt folder: the next free number, created here under the
# lock, so two starts can't share one.
if [ -L "$HEAD_DIR/attempts" ]; then
    rm -f "$LOCK"; die "$HEAD_DIR/attempts is a symlink"
fi
ATTEMPT=$(next_attempt)
(umask 077 && mkdir -p "$HEAD_DIR/attempts" && mkdir "$HEAD_DIR/attempts/$ATTEMPT") \
    || { rm -f "$LOCK"; die "could not create $HEAD_DIR/attempts/$ATTEMPT"; }

jq -cn --arg root "$ROOT" --arg head "$HEAD_SHA" --arg mb "$MB" --argjson sel "$SELECTION" --argjson budget "$BUDGET" \
    --argjson attempt "$ATTEMPT" \
    '{root: $root, head: $head, merge_base: $mb, budget_secs: $budget, attempt: $attempt, invocations: $sel.invocations}' \
    > "$HEAD_DIR/run.json" \
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
