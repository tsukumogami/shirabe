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
#       5b. In a fix round, carry what the run it follows passed (below).
#       6. A lock naming a live supervisor for this head: exit 0. A lock
#          whose process is gone is removed.
#       7. Start the supervisor held, in its own process group (job control,
#          not a new-session command, which the macOS floor lacks), standard
#          input from /dev/null, both outputs to its log, koto's tick marker
#          (KOTO_TICK_SESSION) removed from its environment. It waits on a
#          fifo before it reads anything. Take the lock in the supervisor's
#          pid, so the lock never names a process that ends before the run
#          does. Under the lock, a result for this head and merge-base that
#          appeared since step 2 (a supervisor that finished in between) stops
#          the start, with the held supervisor let go. Otherwise take the
#          next free attempt number n at this head, create attempts/<n>/,
#          record n in run.json as "attempt", release the supervisor and exit
#          0. A --start stopped before the release leaves a supervisor that
#          reads end of file, removes the lock it names and exits, having run
#          nothing. None of the koto calls in steps 0 and 1 waits on a suite,
#          so this stays fast.
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
#          "merge_base", "exit", "status", "reason" (cleaned),
#          "archived_at": "<UTC ISO 8601>", "commands": [{"id" (cleaned),
#          "exit_status", "timed_out", "duration_secs",
#          "log": "attempts/<n>/<index>-<name>.log", or null for any other
#          path}]}
#
#       `exit` is the gate exit the result came through, worked out from its
#       records the way check-verification.sh ranks them
#       (verification-eligibility.sh's verification_gate_exit): 1 when a
#       command failed, beside a timed-out one or not, and 5 for a timeout
#       with nothing failed, held at the timed-out hold.
#   --locate --session <s> [--base-ref <ref>]
#       Print three lines: the head, the merge-base, and the result file's
#       path. check-verification.sh calls this so the path rules live here.
#   --plan --session <s> [--shared-branch <branch>] [--base-ref <ref>]
#       VERIFICATION=auto's resolution, the routing gate of the work-on
#       template's verification_plan state. Starts nothing and writes no
#       result. It resolves to `hosted-ci` (exit 0) when every command the
#       run would start has a `hosted` twin in the merge-base's map and no
#       changed path (both sides of a rename) is in the ci, security,
#       template or engine class of review-level.sh classify, nor under the
#       top-level scripts/ the hosted gate runs from the branch
#       (PLAN_PLANNER_PREFIX); to `local` (exit 1) otherwise. "Would
#       start" is --start's selection after a fix round's carry (step 5b): a check the carry marks `carried` runs
#       nothing, so it needs no twin, and a round with nothing left to start
#       resolves to local, where its carried records make the result. It also
#       resolves to local, saying why, for a non-empty --shared-branch (a
#       step on /execute's shared branch, whose pull request is /execute's),
#       for a session holding `verification_twin_gone` (ci_monitor found a
#       twin gone; see --twins), and for every case --start would settle
#       without a run: a dirty tree, no map or a bad one at the merge-base, a
#       selection of nothing, an attended command. It first removes any
#       `verification_plan` an earlier visit left, then, either way, writes
#       the koto key `verification_plan`:
#
#         {"schema": "shirabe-verification-plan/v1", "head", "merge_base",
#          "resolution": "hosted-ci|local", "reason", "started": [{"check",
#          "id", "hosted"}], "carried": [{"check", "carried_from"}],
#          "decided_at"}
#
#       and prints `<resolution>: <reason>`. A hosted resolution's reason is
#       `hosted twins cover every selected command`, the deferral reason
#       verification_deferred writes for an auto run. Without koto on PATH it
#       resolves to local and records nothing. Exit 2: usage, a koto read or
#       write that failed, or no HEAD or merge-base; the template routes that
#       to local verification too.
#   --resolved --session <s> [--base-ref <ref>]
#       Print `hosted-ci` when the session's `verification_plan` resolved to
#       hosted-ci and it holds no `verification_twin_gone`, else `local` (no
#       record included). Exit 0, or 2 when koto can't answer. pr_creation's
#       deferral record gate reads it for an auto run.
#   --twins --session <s> [--base-ref <ref>]
#       ci_monitor's re-check, before its green edge. Exit 0 when the run did
#       not resolve to hosted-ci (as --resolved decides). Otherwise it fetches
#       the default branch when it is a remote-tracking ref (origin/<b>), reads
#       its current map, and exits 0 when each started command of the record
#       still has one of the twins it resolved with: the same workflow, job
#       and runs on the same row, with the workflow file on the default
#       branch. Exit 1, naming each check on stderr, when one has none (or the
#       map is gone or isn't a map), which sends the run back to local
#       verification. Exit 2 when koto, the fetch or git can't answer.
#   --relevant --session <s> [--ci-wait <all|>] [--base-ref <ref>]
#       ci_monitor's relevant set: the checks the run waits on before its
#       green edge (ci-relevant.sh runs this on every read of ci_passing).
#       Prints `off`, writes nothing and exits 0, so the run waits on every
#       check as before, when --ci-wait is `all` (CI_WAIT=all; without the
#       flag the CI_WAIT environment variable is read), when the merge-base
#       has no map, or one that is not one JSON value, has no
#       `always_required` key, an `always_required` that is not an array of
#       {workflow, job} objects (workflow a file under .github/workflows/,
#       job the check's name), or a map --start's selection refuses, and when
#       the set comes out empty; each but CI_WAIT=all is named on stderr. An
#       empty `always_required` array counts as present. Otherwise the set is
#       the union of two reads, each the `hosted` twins of the commands
#       --start's selection (SELECT_JQ, over `git diff --name-only
#       <merge-base>..HEAD`) picks plus the map's `always_required`: one of
#       the merge-base's map, and one of the current default branch's,
#       fetched first when it is a remote-tracking ref, as --twins does. A
#       current map that is absent or doesn't parse adds nothing, and says
#       so; the union never drops a merge-base entry. Each check of the set is
#       one line per display name its workflow file has at HEAD, the
#       merge-base or the default branch (`name:`, or the file's path when it
#       has none, which is what GitHub shows): `<workflow file>\t<job>\t
#       <display name>`, sorted, the format pr-checks.sh --relevant reads.
#       The lines go to the koto key `relevant_checks.txt` and to stdout.
#       Exit 2: usage, koto, the fetch or git failing.
#   --await-removals
#       Check once whether a build-output removal is still running in this
#       work tree, and exit: 0 when none is (no records directory, no records,
#       or only ended or unparsable ones), 1 when one is, each live record
#       named on stderr, 2 only for a usage error. Takes no --session,
#       resolves no merge-base, starts no command and changes nothing. A
#       directory git can't answer for reads as no records directory, so this
#       exits 0 there too. work-on.md's `await_removals` gate runs it before
#       setup, whose baseline builds.
#   --supervise <dir>
#       Internal: the supervisor. Never calls koto (only --start's steps 0
#       and 1 do). Reads one line from its fd 3 before anything else and runs
#       only when --start wrote `go` there.
#
# A build-output removal (clean-build-output.sh) renames a work tree's
# declared build output into trash inside its git directory and deletes it
# in the background, recording each removal as removal-<stamp>.json in the
# directory build-output-lib.sh's bo_dir names. A build started while a delete
# is still running competes with it for the same disk, so the supervisor,
# after it takes the run's start time and before its first command, waits
# while any record there reads live (bo_record_live, the one judgement the
# cleanup's reaper uses too). The wait spends the run's own budget, so
# --start still returns at once and the run never outlives its budget
# because of it. A record that doesn't parse counts as ended and is named
# once on stderr. When the budget runs out with a record still live, the
# supervisor starts no command and writes a `removal-running` result with
# `commands: []` and a `detail` naming the record, which check-verification.sh
# holds on as it does on `supervisor-error`; --start keeps it (step 2), so a
# held tick never starts another wait. The runner only reads the records
# directory: it never deletes, renames or rewrites anything in it. Only the
# supervisor and --await-removals load build-output-lib.sh; one that can't
# load it says so and reads no record, as work-on's gate passes a plugin root
# with no runner.
#
# --base-ref names the default branch. Without it: the ref origin/HEAD points
# at, else origin/main, else main.
#
# A fix round's carry (step 4b). A session whose koto context holds
# `fix_round.json` ({from, round, base}, written by fix-round.sh) is a fix
# round, and `base` is the head the run it follows left. That run is the
# previous round (the line before this session's in the original's
# `fix_rounds.jsonl`), else `from`. Its result is found by the same path
# rules as --locate, with that session and head = base; when there is none,
# the newest result with status `done` that session wrote at an ancestor of
# base (`git merge-base --is-ancestor`) is used instead, since a run that
# reached done often committed after its verification. The head of the
# result used is the carry base, and the round's own diff is
# `git diff --name-only <carry base>..HEAD`, so commits between the parent's
# verified head and the round's base count as the round's changes. Selection
# for the result is still the merge-base diff, so the round's set of checks
# is a full run's; only what runs changes. For each selected check:
#   - the parent's record for the same check passed (`outcome` passed or
#     carried) with the same argv, and the round's diff, selected through the
#     same map, doesn't select it: it doesn't run. Its record is written with
#     `outcome: carried` and `carried_from: {session, head}` naming the
#     parent session and the carry base, exit_status 0, duration_secs 0,
#     not_started false, log and suites null;
#   - the parent passed it and the round's diff selects it: it runs, and an
#     `each` row's command (check `<row id>:<leaf>`) gets
#     SHIRABE_VERIFY_BASE=<carry base> in its environment, so check-skill.sh
#     --changed diffs against it, not the merge-base;
#   - otherwise (the parent failed it, timed out, never ran it) it runs as in
#     a full run, with no SHIRABE_VERIFY_BASE.
# A round that touches shared code reruns the full selection: when the
# round's diff holds a path outside one skill's directory (not under
# skills/<name>/) or a path no map entry matches, nothing is carried, since
# such a path selects no check for the skills whose suites may run it.
# The carry is also off, and every selected check runs, with no
# fix_round.json, with `fresh: true` in it (fix-round.sh start --fresh), with
# SHIRABE_VERIFY_FULL=1 in --start's environment, without koto on PATH, or
# when the base or no parent result at or before it can be read; each but
# the first says so on stderr. koto runs this launcher in a cleared
# environment, so SHIRABE_VERIFY_FULL=1 takes effect on a --start run by
# hand. A koto failure reading the keys is exit 2, as in step 0. A result
# already at this head stands either way: move it aside to run again.
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
#    timed-out|supervisor-error|removal-running", "detail": "...", "finished_at": "<UTC
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
#   carried           not run: a fix round's parent passed it at the carry
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
# Test hook, read only from the environment, which koto's fixed environment
# never carries. Only the tests set it, to stop --start at a point and kill it
# there:
#   SHIRABE_VERIFICATION_TEST_PAUSE  a directory: at a point <p> the test
#                                    armed with `<p>.wait`, touch
#                                    `<p>.reached` and wait for `<p>.go`, as
#                                    long as test_pause's loop bound allows.
#                                    Points, all in --start: lock, held,
#                                    started
#
# Exit status: 0 the launcher did its job (a result exists, or a supervisor is
# running, or --archive archived); 1 --archive refused; 2 it could not decide
# (usage, a missing tool, no HEAD, no merge-base, no state directory). The
# verdict is never this script's exit. --await-removals has its own (above).
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
# VERIFICATION=auto's record (--plan), the key ci_monitor's demotion edge
# writes, the deferral reason a hosted resolution carries, and the path
# classes that keep a run local.
PLAN_KEY=verification_plan
PLAN_SCHEMA=shirabe-verification-plan/v1
GONE_KEY=verification_twin_gone
HOSTED_REASON="hosted twins cover every selected command"
# ci_monitor's relevant set (--relevant).
REL_KEY=relevant_checks.txt
PLAN_RISKY_CLASSES="ci security template engine"
# The top-level directory a hosted twin's job runs from the branch itself: the
# skill gate plans and runs its suites with scripts/skill-gate.sh,
# scripts/check-skill.sh and scripts/lib/. A change there could make the twin
# pass without running a suite, so it keeps the run local whatever the map says.
PLAN_PLANNER_PREFIX="scripts/"
# The failure lines a timeout_form is matched against: the pattern
# check-skill.sh's show_suite_failure uses to pick a failed suite's FAIL lines,
# in jq's regex syntax (passed with --arg, so read as written).
FAILURE_LINE_RE='^[[:space:]]*(\x1b\[[0-9;]*m)?(FAIL|not ok)([^A-Za-z]|$)'

usage() {
    cat >&2 <<'EOF'
Usage: run-verification.sh --start --session <s> [--base-ref <ref>]
       run-verification.sh --archive --session <s> --reason <text> [--base-ref <ref>]
       run-verification.sh --locate --session <s> [--base-ref <ref>]
       run-verification.sh --plan --session <s> [--shared-branch <branch>] [--base-ref <ref>]
       run-verification.sh --resolved --session <s> [--base-ref <ref>]
       run-verification.sh --twins --session <s> [--base-ref <ref>]
       run-verification.sh --relevant --session <s> [--ci-wait <all|>] [--base-ref <ref>]
       run-verification.sh --await-removals
EOF
}

die() {
    echo "run-verification: $*" >&2
    exit 2
}

test_pause() {
    local d=${SHIRABE_VERIFICATION_TEST_PAUSE:-} i=0
    [ -n "$d" ] && [ -d "$d" ] && [ -e "$d/$1.wait" ] || return 0
    : > "$d/$1.reached"
    while [ ! -e "$d/$1.go" ] && [ "$i" -lt 300 ]; do
        sleep 0.1
        i=$((i + 1))
    done
}

# shellcheck source=SCRIPTDIR/verification-eligibility.sh
. "$HERE/verification-eligibility.sh" || die "cannot load verification-eligibility.sh"

# --- build-output removals (see the header) ---------------------------------------

# bo_lib: load build-output-lib.sh, once, and return 0; return 1, saying so on
# stderr, when it can't be loaded. Loaded only by the two modes that read
# records, so --start, --locate and --archive run as before without it. A
# runner without the library can't read a record, and goes on as if there were
# none, as work-on's gate does for a plugin root with no runner.
BO_LIB=""
bo_lib() {
    [ "$BO_LIB" = loaded ] && return 0
    # shellcheck source=SCRIPTDIR/build-output-lib.sh
    if [ -r "$HERE/build-output-lib.sh" ] && . "$HERE/build-output-lib.sh"; then
        BO_LIB=loaded
        return 0
    fi
    echo "run-verification: cannot load $HERE/build-output-lib.sh, so no build-output removal record is read" >&2
    return 1
}

# The unparsable records already named on stderr, each between bars, so a
# wait that polls names each one once.
RV_NAMED="|"

# live_removals <dir>: set RV_LIVE to the removal records in <dir> that
# bo_record_live reads live, comma-separated, empty when none is. A record
# that doesn't parse (a symlink included) counts as ended and is named once on
# stderr. Sets a variable rather than printing, so RV_NAMED survives the call.
# Reads only.
RV_LIVE=""
live_removals() {
    local d=$1 rec
    RV_LIVE=""
    [ -d "$d" ] || return 0
    for rec in "$d"/removal-*.json; do
        [ -e "$rec" ] || [ -L "$rec" ] || continue
        if bo_record_live "$rec"; then
            RV_LIVE="${RV_LIVE:+$RV_LIVE, }$rec"
        elif ! bo_record_parses "$rec"; then
            case "$RV_NAMED" in
                *"|$rec|"*) ;;
                *)
                    echo "run-verification: the build-output removal record $rec does not parse; it counts as ended" >&2
                    RV_NAMED="$RV_NAMED$rec|"
                    ;;
            esac
        fi
    done
    return 0
}

# await_removals_once: --await-removals (see the header). Never returns.
await_removals_once() {
    local root dir
    bo_lib || exit 0
    root=$(git rev-parse --show-toplevel) || exit 0
    dir=$(bo_dir "$root") || exit 0
    live_removals "$dir"
    [ -n "$RV_LIVE" ] || exit 0
    echo "run-verification: a build-output removal is still running in this work tree ($RV_LIVE);" \
        "nothing may build here until it ends, so tick again in a minute" >&2
    exit 1
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
  | [$changed[] | . as $p | select(all($entries[]; all(.res[]; . as $r | $p | test($r) | not)))] as $unmatched_paths
  | ($unmatched_paths | length) as $unmatched
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
  | {invocations: $inv, attended: ($inv | map(select(.unattended == false) | .id) | dedupe),
     unmatched: $unmatched_paths}
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
    BASE_RESOLVED=$base
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

# lock_take <lock> [<pid>]: hold the lock for <pid>, this process when it is
# not given (--start takes it for the supervisor it just launched). Returns 0
# holding it, with LOCK_TOOK=1 when this call created it and LOCK_TOOK=0 when
# it already named <pid>: --start's consume_request takes the lock and then
# calls archive_attempt, which takes it again, and the inner call must not
# release the outer hold. Returns 1 when it can't: LOCK_HOLDER is the pid of
# the live process that holds it, or empty when the lock couldn't be created at
# all. A lock whose process is gone is removed and taken.
lock_take() {
    local pid=${2:-$$}
    LOCK_TOOK=0
    LOCK_HOLDER=""
    [ "$(readlink "$1" 2>/dev/null)" = "$pid" ] && return 0
    if ln -s "$pid" "$1" 2>/dev/null; then
        LOCK_TOOK=1
        return 0
    fi
    if lock_live "$1"; then
        LOCK_HOLDER=$(readlink "$1" 2>/dev/null)
        return 1
    fi
    rm -f "$1"
    if ln -s "$pid" "$1" 2>/dev/null; then
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
    local reason elig n adir at disk mode prior last k status gexit line back back_count back_last lcount
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
        # The gate exit the result came through: 1 beside any failed command, 5
        # for a timed-out check with nothing failed, held at the timed-out hold.
        gexit=$(verification_gate_exit "$RESULT") \
            || { archive_refuse "could not build the ledger line"; return 1; }
        # Command ids get the reason's cleaning. A log path is kept only in the
        # shape this script writes, attempts/<n>/<index>-<safe id>.log, relative
        # to the head directory; anything else is stored as null.
        line=$(jq -nc --argjson attempt "$k" --argjson folder "$n" --argjson exit "$gexit" \
            --arg head "$HEAD_SHA" --arg mb "$MB" --arg status "$status" --arg reason "$reason" \
            --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg hd "$HEAD_DIR/" --slurpfile result "$RESULT" "$VE_CLEAN_JQ"'
            def rel: if (type == "string") and startswith($hd) then .[($hd | length):] else null end
                     | if (type == "string") and test("^attempts/[0-9]+/[0-9]+-[A-Za-z0-9._-]+\\.log$") then . else null end;
            {attempt: $attempt, folder: $folder, head: $head, merge_base: $mb, exit: $exit, status: $status,
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
    local dir=$1 go=""
    # Held until --start writes `go` on fd 3 (its step 6), so run.json is
    # read only once it is written. End of file instead means --start stopped
    # first: the lock goes if it names this process, and nothing runs.
    read -r go <&3
    exec 3<&-
    if [ "$go" != go ]; then
        [ "$(readlink "$dir/lock" 2>/dev/null)" = "$$" ] && rm -f "$dir/lock"
        echo "run-verification: --start stopped before it released the supervisor; nothing ran" >&2
        exit 0
    fi
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
    # A build-output removal still running in this work tree: wait for it
    # inside the run's budget, polling once a second, so nothing builds while
    # it deletes (see the header).
    local bodir rm_detail
    if bo_lib && bodir=$(bo_dir "$ROOT"); then
        live_removals "$bodir"
        while [ -n "$RV_LIVE" ]; do
            if [ $((sup_start + budget - $(date +%s))) -le 0 ]; then
                # Built outside the substitution below: bash 3.2 misparses a
                # quote inside a double-quoted string nested in "$( )".
                rm_detail="a build-output removal was still running when the run budget of $budget seconds ran out"
                rm_detail="$rm_detail, so no command started: $RV_LIVE"
                write_result "$RESULT" "$(jq -cn --arg schema "$RESULT_SCHEMA" --arg head "$HEAD_SHA" --arg mb "$MB" \
                    --arg detail "$rm_detail" --arg fin "$(now_iso)" \
                    '{schema: $schema, head: $head, merge_base: $mb, status: "removal-running", detail: $detail,
                      finished_at: $fin, commands: []}')" \
                    && SUP_WRITTEN=1
                rm -f "$SUP_LOCK" "$SUP_ENTRIES"
                exit 0
            fi
            sleep 1
            live_removals "$bodir"
        done
    fi
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
    --await-removals)
        [ $# -eq 0 ] || { usage; exit 2; }
        await_removals_once ;;
    --start|--locate|--archive|--plan|--resolved|--twins|--relevant) ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac

SESSION=""
BASE_REF=""
REASON=""
REASON_SET=0
SHARED_BRANCH=""
SHARED_SET=0
CI_WAIT_ARG=${CI_WAIT:-}
CI_WAIT_SET=0
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
        --shared-branch)
            # Empty is allowed: the gate passes an unset SHARED_BRANCH as "".
            [ "$MODE" = --plan ] && [ $# -ge 2 ] && [ "$SHARED_SET" -eq 0 ] || { usage; exit 2; }
            SHARED_BRANCH=$2; SHARED_SET=1; shift 2 ;;
        --ci-wait)
            # Empty is allowed: the gate passes an unset CI_WAIT as "".
            [ "$MODE" = --relevant ] && [ $# -ge 2 ] && [ "$CI_WAIT_SET" -eq 0 ] || { usage; exit 2; }
            CI_WAIT_ARG=$2; CI_WAIT_SET=1; shift 2 ;;
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

if [ "$MODE" = --relevant ]; then
    case "$CI_WAIT_ARG" in
        ''|all) ;;
        *) die "--ci-wait [$CI_WAIT_ARG] is neither all nor empty" ;;
    esac
    if [ "$CI_WAIT_ARG" = all ]; then
        echo off
        exit 0
    fi
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

# --- a fix round's carry ----------------------------------------------------------------
#
# Defined here, ahead of the modes, because --plan runs it as well as --start.

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
    local rc fr from round fresh base prev rounds sdir cbase d h parent_result round_changed round_sel round_checks shared out
    if ! command -v koto >/dev/null 2>&1; then
        note "koto is not on PATH, so no fix_round.json can be read and nothing is carried; every selected check runs"
        return 0
    fi
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
        note "fix_round.json of $SESSION names no run, round or base head, so nothing is carried; every selected check runs"
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
        note "the round's base $base is not a commit here, so nothing is carried; every selected check runs"
        return 0
    fi

    # The carry base: the parent's result at the round's base, else the newest
    # `done` result it wrote at an ancestor of the base. A run that reached
    # done often committed after its verification (finalization, CI fixes),
    # so the exact head is often missing; the commits between the carry base
    # and the round's base then count as the round's own changes below.
    sdir="${SESSION_DIR%/*}/$prev"
    cbase=""
    if [ -f "$sdir/$base/result.json" ] && jq -e --arg schema "$RESULT_SCHEMA" --arg h "$base" \
            '.schema == $schema and .head == $h and (.commands | type) == "array"' "$sdir/$base/result.json" >/dev/null; then
        cbase=$base
    else
        for d in "$sdir"/*; do
            h=${d##*/}
            grep -Eq '^[0-9a-f]{40}([0-9a-f]{24})?$' <<<"$h" || continue
            [ "$h" != "$base" ] && [ -f "$d/result.json" ] || continue
            jq -e --arg schema "$RESULT_SCHEMA" --arg h "$h" \
                '.schema == $schema and .head == $h and .status == "done" and (.commands | type) == "array"' \
                "$d/result.json" >/dev/null || continue
            git -C "$ROOT" rev-parse --verify -q "${h}^{commit}" >/dev/null || continue
            git -C "$ROOT" merge-base --is-ancestor "$h" "$base" || continue
            # The newest by ancestry: a candidate replaces the one held when
            # the held one is its ancestor.
            if [ -z "$cbase" ] || git -C "$ROOT" merge-base --is-ancestor "$cbase" "$h"; then
                cbase=$h
            fi
        done
        if [ -z "$cbase" ]; then
            note "$prev has no verification result at the round's base $base or at a done head before it, so nothing is carried; every selected check runs"
            return 0
        fi
        note "$prev has no result at the round's base $base; carrying from its result at $cbase, an ancestor of it"
    fi
    parent_result="$sdir/$cbase/result.json"

    # The round's own diff, from the carry base, selected through the same map.
    if ! round_changed=$(set -o pipefail; git -C "$ROOT" diff --name-only -z "$cbase..HEAD" \
            | jq -Rs 'split("\u0000") | map(select(length > 0))'); then
        note "could not list the paths changed since $cbase, so nothing is carried; every selected check runs"
        return 0
    fi
    round_sel=$(printf '%s' "$MAP_JSON" | jq -c --argjson changed "$round_changed" "$SELECT_JQ") \
        || die "the selection program failed on the round's diff"
    round_checks=$(printf '%s' "$round_sel" | jq -c 'if has("error") then null else [.invocations[].check] end')
    if [ "$round_checks" = null ] || [ -z "$round_checks" ]; then
        note "the map does not select on the round's diff, so nothing is carried; every selected check runs"
        return 0
    fi

    # Shared code: a path outside one skill's directory, or one no map entry
    # matches, selects no check for the skills whose suites may run it, so a
    # pass carried for them would be a pass made with the old code.
    shared=$(printf '%s' "$round_sel" | jq -r --argjson changed "$round_changed" '
        ([$changed[] | select(test("^skills/[^/]+/.") | not)] + (.unmatched // [])) | unique
        | if length == 0 then "" else "\(.[0:5] | join(", "))\(if length > 5 then " and \(length - 5) more" else "" end)" end')
    if [ -n "$shared" ]; then
        note "the round's diff since $cbase touches shared code ($shared): a path outside one skill's directory or matched by no map entry. A round that touches shared code reruns the full selection, so nothing is carried"
        return 0
    fi

    INVOCATIONS=$(printf '%s' "$INVOCATIONS" | jq -c --slurpfile parent "$parent_result" \
        --argjson round "$round_checks" --arg from "$prev" --arg base "$cbase" \
        '$parent[0] as $parent | '"$CARRY_JQ") \
        || die "could not apply the carry from $parent_result"
    note "$(printf '%s' "$INVOCATIONS" | jq -r --arg p "$prev" --arg b "$cbase" '
        "carried \([.[] | select(.carried)] | length) check(s) \($p) passed at \($b); running \([.[] | select(.carried | not)] | length): \([.[] | select(.carried | not) | .check] | join(", "))"')"
}

# --- --plan, --resolved and --twins ------------------------------------------------------
#
# VERIFICATION=auto's resolution (see the header). --plan decides and records,
# --resolved reads what was decided, and --twins re-reads the twins from the
# current default branch's map at ci_monitor.

# plan_local <reason>: resolve to local, for the reason given.
plan_local() {
    PLAN_RES=local
    PLAN_REASON=$1
}

# plan_decide: sets PLAN_RES, PLAN_REASON, PLAN_STARTED and PLAN_CARRIED. Every
# question it can't answer resolves to local, which runs the map and reports
# the cause there; only a koto read that fails is exit 2.
plan_decide() {
    local rc dirty map_entry err classes risky planner started untwinned
    PLAN_STARTED="[]"
    PLAN_CARRIED="[]"
    if [ -n "$SHARED_BRANCH" ]; then
        plan_local "a step on the shared branch $SHARED_BRANCH verifies locally: its pull request is /execute's, and this run never reaches ci_monitor to re-check a twin"
        return 0
    fi
    koto context exists "$SESSION" "$GONE_KEY"
    rc=$?
    case "$rc" in
        0)
            plan_local "a hosted twin left the default branch's map while this run waited at ci_monitor ($GONE_KEY), so it verifies locally from here"
            return 0
            ;;
        1) ;;
        *) die "koto context exists $SESSION $GONE_KEY exited $rc" ;;
    esac
    dirty=$(git -C "$ROOT" status --porcelain --untracked-files=no) \
        || { plan_local "the working tree's status could not be read"; return 0; }
    if [ -n "$dirty" ]; then
        plan_local "tracked files have uncommitted changes"
        return 0
    fi
    map_entry=$(git -C "$ROOT" ls-tree "$MB" -- "$MAP_PATH") \
        || { plan_local "$MAP_PATH could not be listed at the merge-base $MB"; return 0; }
    if [ -z "$map_entry" ]; then
        plan_local "no $MAP_PATH at the merge-base $MB"
        return 0
    fi
    MAP_JSON=$(git -C "$ROOT" show "$MB:$MAP_PATH") \
        || { plan_local "$MAP_PATH could not be read at $MB"; return 0; }
    CHANGED=$(git -C "$ROOT" diff --name-only -z "$MB..HEAD" | jq -Rs 'split("\u0000") | map(select(length > 0))') \
        || { plan_local "the changed paths could not be listed"; return 0; }
    if ! printf '%s' "$MAP_JSON" | jq -se 'length == 1' >/dev/null; then
        plan_local "$MAP_PATH at $MB is not one valid JSON value"
        return 0
    fi
    SELECTION=$(printf '%s' "$MAP_JSON" | jq -c --argjson changed "$CHANGED" "$SELECT_JQ") \
        || { plan_local "the selection program failed"; return 0; }
    err=$(printf '%s' "$SELECTION" | jq -r '.error // empty')
    if [ -n "$err" ]; then
        plan_local "the map at the merge-base does not parse: $err"
        return 0
    fi
    if [ "$(printf '%s' "$SELECTION" | jq '.invocations | length')" -eq 0 ]; then
        plan_local "the map selects nothing for this change"
        return 0
    fi
    if [ -n "$(printf '%s' "$SELECTION" | jq -r '.attended | join(", ")')" ]; then
        plan_local "a selected command is marked unattended: false"
        return 0
    fi

    # The path classes, both sides of a rename: a path in the ci, security,
    # template or engine class can change what CI itself runs, or what decides
    # this run's route.
    classes=$(set -o pipefail; git -C "$ROOT" diff --name-only --no-renames -z "$MB..HEAD" | xargs -0 "$HERE/review-level.sh" classify) \
        || { plan_local "review-level.sh classify could not classify the changed paths"; return 0; }
    risky=$(printf '%s\n' "$classes" | awk -F'\t' -v risk="$PLAN_RISKY_CLASSES" '
        BEGIN { n = split(risk, r, " "); for (i = 1; i <= n; i++) want[r[i]] = 1 }
        NF >= 2 {
            m = split($2, c, ","); hit = ""
            for (i = 1; i <= m; i++) if (c[i] in want) hit = hit (hit == "" ? "" : ",") c[i]
            if (hit != "") { count++; if (count <= 5) list = list (list == "" ? "" : ", ") $1 " (" hit ")" }
        }
        END { if (count > 5) list = list " and " (count - 5) " more"; print list }')
    if [ -n "$risky" ]; then
        plan_local "the change touches a path in the ci, security, template or engine class: $risky"
        return 0
    fi
    planner=$(set -o pipefail; git -C "$ROOT" diff --name-only --no-renames -z "$MB..HEAD" | jq -Rrs --arg p "$PLAN_PLANNER_PREFIX" '
        split("\u0000") | map(select(startswith($p))) as $hit
        | if ($hit | length) == 0 then "" else ($hit[:5] | join(", ")) + (if ($hit | length) > 5 then " and \(($hit | length) - 5) more" else "" end) end') \
        || { plan_local "the changed paths could not be listed"; return 0; }
    if [ -n "$planner" ]; then
        plan_local "the change touches the hosted gate's own scripts under $PLAN_PLANNER_PREFIX, which its job runs from the branch: $planner"
        return 0
    fi

    INVOCATIONS=$(printf '%s' "$SELECTION" | jq -c '.invocations') \
        || { plan_local "the selection could not be read"; return 0; }
    carry
    PLAN_STARTED=$(printf '%s' "$INVOCATIONS" | jq -c '[.[] | select(.carried == null) | {check, id, hosted}]') \
        || { plan_local "the started commands could not be read"; return 0; }
    PLAN_CARRIED=$(printf '%s' "$INVOCATIONS" | jq -c '[.[] | select(.carried != null) | {check, carried_from: .carried.carried_from}]') \
        || PLAN_CARRIED="[]"
    started=$(printf '%s' "$PLAN_STARTED" | jq 'length')
    if [ "$started" -eq 0 ]; then
        plan_local "every selected check is carried from the run this round follows, so nothing would start"
        return 0
    fi
    untwinned=$(printf '%s' "$PLAN_STARTED" | jq -r '[.[] | select((.hosted | length) == 0) | .check] | join(", ")')
    if [ -n "$untwinned" ]; then
        plan_local "no hosted twin in the merge-base's map for: $untwinned"
        return 0
    fi
    PLAN_RES=hosted-ci
    PLAN_REASON=$HOSTED_REASON
}

if [ "$MODE" = --plan ]; then
    command -v koto >/dev/null 2>&1 || {
        echo "local: koto is not on PATH, so no resolution can be recorded"
        exit 1
    }
    # An earlier visit's record goes first, so a plan stopped before it writes
    # (exit 2, routed to local) never leaves a hosted resolution behind for
    # --resolved and --twins to read.
    koto context exists "$SESSION" "$PLAN_KEY"
    rc=$?
    case "$rc" in
        0) koto context remove "$SESSION" "$PLAN_KEY" >/dev/null || die "could not remove the earlier $PLAN_KEY of $SESSION" ;;
        1) ;;
        *) die "koto context exists $SESSION $PLAN_KEY exited $rc" ;;
    esac
    PLAN_RES=local
    PLAN_REASON=""
    plan_decide
    PLAN_TMP=$(mktemp "${TMPDIR:-/tmp}/run-verification-plan.XXXXXX") || die "could not create a temporary file"
    trap 'rm -f "$PLAN_TMP"' EXIT
    jq -n --arg schema "$PLAN_SCHEMA" --arg head "$HEAD_SHA" --arg mb "$MB" --arg res "$PLAN_RES" \
        --arg reason "$PLAN_REASON" --argjson started "$PLAN_STARTED" --argjson carried "$PLAN_CARRIED" \
        --arg at "$(now_iso)" \
        '{schema: $schema, head: $head, merge_base: $mb, resolution: $res, reason: $reason,
          started: $started, carried: $carried, decided_at: $at}' > "$PLAN_TMP" \
        || die "could not build the $PLAN_KEY record"
    koto context add "$SESSION" "$PLAN_KEY" --from-file "$PLAN_TMP" >/dev/null \
        || die "could not write $PLAN_KEY for session $SESSION"
    printf '%s: %s\n' "$PLAN_RES" "$PLAN_REASON"
    [ "$PLAN_RES" = hosted-ci ] && exit 0
    exit 1
fi

# plan_hosted: true when this run's recorded resolution is hosted-ci and no
# twin has gone since. Dies (exit 2) when koto can't answer.
plan_hosted() {
    local rc res
    command -v koto >/dev/null || die "koto is not on PATH"
    ctx_read "$PLAN_KEY" || die "could not read $PLAN_KEY for session $SESSION"
    [ "$CTX_PRESENT" -eq 1 ] || return 1
    res=$(printf '%s' "$CTX_VALUE" | jq -r 'if type == "object" and (.resolution | type) == "string" then .resolution else "" end') \
        || res=""
    [ "$res" = hosted-ci ] || return 1
    koto context exists "$SESSION" "$GONE_KEY"
    rc=$?
    case "$rc" in
        0) return 1 ;;
        1) return 0 ;;
        *) die "koto context exists $SESSION $GONE_KEY exited $rc" ;;
    esac
}

if [ "$MODE" = --resolved ]; then
    if plan_hosted; then
        echo hosted-ci
    else
        echo local
    fi
    exit 0
fi

if [ "$MODE" = --twins ]; then
    plan_hosted || exit 0
    # The current default branch, fetched first when it is a remote-tracking
    # ref, so a twin removed on the remote since the run began is seen.
    case "$BASE_RESOLVED" in
        origin/*)
            git -C "$ROOT" fetch --quiet origin "${BASE_RESOLVED#origin/}" \
                || die "could not fetch ${BASE_RESOLVED#origin/} from origin"
            ;;
    esac
    CUR_ENTRY=$(git -C "$ROOT" ls-tree "$BASE_RESOLVED" -- "$MAP_PATH") \
        || die "could not list $MAP_PATH at $BASE_RESOLVED"
    if [ -z "$CUR_ENTRY" ]; then
        echo "run-verification: twins: $BASE_RESOLVED has no $MAP_PATH, so no hosted twin of this run's commands is left" >&2
        exit 1
    fi
    CUR_MAP=$(git -C "$ROOT" show "$BASE_RESOLVED:$MAP_PATH") || die "could not read $MAP_PATH at $BASE_RESOLVED"
    if ! CUR_MAP=$(printf '%s' "$CUR_MAP" | jq -ce 'if type == "object" and (.commands | type) == "object" then . else error("no commands object") end'); then
        echo "run-verification: twins: $MAP_PATH at $BASE_RESOLVED is not a map with a commands object, so no twin can be confirmed" >&2
        exit 1
    fi
    # Each started command keeps at least one of the twins it resolved with:
    # the same workflow, job and runs on the same row, and the workflow file
    # still on the default branch.
    GONE=""
    STARTED=$(printf '%s' "$CTX_VALUE" | jq -c '.started // [] | .[]') || die "could not read the started commands from $PLAN_KEY"
    while IFS= read -r inv; do
        [ -n "$inv" ] || continue
        check=$(printf '%s' "$inv" | jq -r '.check')
        kept=$(printf '%s' "$CUR_MAP" | jq -c --argjson inv "$inv" \
            '[(.commands[$inv.id].hosted // []) as $cur | $inv.hosted[] | select(. as $t | $cur | index([$t]) != null)]')
        ok=0
        while IFS= read -r wf; do
            [ -n "$wf" ] || continue
            if [ -n "$(git -C "$ROOT" ls-tree "$BASE_RESOLVED" -- "$wf")" ]; then
                ok=1
                break
            fi
        done <<EOF
$(printf '%s' "$kept" | jq -r '.[].workflow')
EOF
        [ "$ok" -eq 1 ] || GONE="$GONE${GONE:+, }$check"
    done <<EOF
$STARTED
EOF
    if [ -n "$GONE" ]; then
        echo "run-verification: twins: the default branch ($BASE_RESOLVED) no longer has a hosted twin this run resolved with for: $GONE; the run goes back to local verification" >&2
        exit 1
    fi
    exit 0
fi

# --- --relevant -------------------------------------------------------------------------
#
# ci_monitor's relevant set (see the header). Never a selection of its own:
# the twins come from SELECT_JQ, as --start's and --plan's do.

# rel_off <reason>: the filter is off for this read, and ci_monitor waits on
# every check.
rel_off() {
    echo "run-verification: relevant: $1, so ci_monitor waits on every check" >&2
    echo off
    exit 0
}

# The map's always_required, checked entry by entry: {workflow, job} each, or
# an error naming what is wrong.
REL_ALWAYS_JQ='
    if (.always_required | type) != "array" then error("always_required is not an array")
    else .always_required[]
      | if type != "object" or (.workflow | type) != "string" or (.job | type) != "string"
           or .workflow == "" or .job == ""
          then error("an always_required entry is not an object with non-empty string workflow and job")
        elif (.workflow | startswith(".github/workflows/") and (split("/") | all(. != ".." and . != "." and . != ""))) | not
          then error("always_required names a workflow outside .github/workflows/: \(.workflow)")
        elif (.workflow + .job) | test("[\\t\\n\\r]")
          then error("an always_required entry carries a tab or a line break")
        else {workflow, job} end
    end'

# rel_set <map json> <1 when always_required must be there, else 0>: sets
# REL_SET, a JSON array of {workflow, job}: the twins of the commands the
# selection picks for CHANGED, plus always_required. Returns 1, the reason in
# REL_WHY, when the map can't give one.
rel_set() {
    local sel err always twins
    REL_SET="[]"
    REL_WHY=""
    if ! printf '%s' "$1" | jq -se 'length == 1' >/dev/null; then
        REL_WHY="it is not one valid JSON value"
        return 1
    fi
    if ! printf '%s' "$1" | jq -e 'type == "object" and has("always_required")' >/dev/null; then
        if [ "$2" -eq 1 ]; then
            REL_WHY="it has no always_required"
            return 1
        fi
        always="[]"
    else
        always=$(printf '%s' "$1" | jq -c "[$REL_ALWAYS_JQ]") || { REL_WHY="its always_required is malformed"; return 1; }
    fi
    sel=$(printf '%s' "$1" | jq -c --argjson changed "$CHANGED" "$SELECT_JQ") \
        || { REL_WHY="the selection program failed"; return 1; }
    err=$(printf '%s' "$sel" | jq -r '.error // empty')
    if [ -n "$err" ]; then
        REL_WHY="it does not parse: $err"
        return 1
    fi
    twins=$(printf '%s' "$sel" | jq -c '[.invocations[].hosted[] | {workflow, job}
        | select((.workflow + .job) | test("[\\t\\n\\r]") | not)]') \
        || { REL_WHY="its twins could not be read"; return 1; }
    REL_SET=$(jq -cn --argjson a "$always" --argjson t "$twins" '$a + $t | unique') \
        || { REL_WHY="the set could not be built"; return 1; }
}

# wf_display <ref> <workflow file>: the workflow's display name at <ref>, the
# name gh reports a check's workflow by: its top-level `name:`, unquoted, or
# its path when it has none. Returns 1 when the file isn't at <ref>, or its
# name holds a tab.
wf_display() {
    local entry body name
    entry=$(git -C "$ROOT" ls-tree "$1" -- "$2") || return 1
    [ -n "$entry" ] || return 1
    body=$(git -C "$ROOT" show "$1:$2") || return 1
    name=$(awk -v q="'" '
        /^name:/ {
            v = $0; sub(/^name:[ \t]*/, "", v); c = substr(v, 1, 1)
            if (c == "\"" || c == q) { v = substr(v, 2); i = index(v, c); if (i) v = substr(v, 1, i - 1) }
            else { sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v) }
            print v; exit
        }' <<<"$body")
    [ -n "$name" ] || name=$2
    case "$name" in *"	"*) return 1 ;; esac
    printf '%s\n' "$name"
}

if [ "$MODE" = --relevant ]; then
    command -v koto >/dev/null || die "koto is not on PATH, so the relevant set can't be recorded"
    MB_ENTRY=$(git -C "$ROOT" ls-tree "$MB" -- "$MAP_PATH") || die "could not list $MAP_PATH at $MB"
    [ -n "$MB_ENTRY" ] || rel_off "no $MAP_PATH at the merge-base $MB"
    MB_MAP=$(git -C "$ROOT" show "$MB:$MAP_PATH") || die "could not read $MAP_PATH at $MB"
    CHANGED=$(git -C "$ROOT" diff --name-only -z "$MB..HEAD" | jq -Rs 'split("\u0000") | map(select(length > 0))') \
        || die "could not list the changed paths"
    rel_set "$MB_MAP" 1 || rel_off "$MAP_PATH at the merge-base $MB: $REL_WHY"
    MB_SET=$REL_SET

    # The current default branch, fetched first as --twins does, so an entry
    # added there since the run began is waited on too.
    case "$BASE_RESOLVED" in
        origin/*)
            git -C "$ROOT" fetch --quiet origin "${BASE_RESOLVED#origin/}" \
                || die "could not fetch ${BASE_RESOLVED#origin/} from origin"
            ;;
    esac
    CUR_SET="[]"
    CUR_ENTRY=$(git -C "$ROOT" ls-tree "$BASE_RESOLVED" -- "$MAP_PATH") \
        || die "could not list $MAP_PATH at $BASE_RESOLVED"
    if [ -z "$CUR_ENTRY" ]; then
        echo "run-verification: relevant: $BASE_RESOLVED has no $MAP_PATH, so the merge-base's set stands alone" >&2
    else
        CUR_MAP=$(git -C "$ROOT" show "$BASE_RESOLVED:$MAP_PATH") || die "could not read $MAP_PATH at $BASE_RESOLVED"
        if rel_set "$CUR_MAP" 0; then
            CUR_SET=$REL_SET
        else
            echo "run-verification: relevant: $MAP_PATH at $BASE_RESOLVED: $REL_WHY, so it adds nothing to the merge-base's set" >&2
        fi
    fi
    UNION=$(jq -cn --argjson a "$MB_SET" --argjson b "$CUR_SET" '$a + $b | unique') \
        || die "could not join the two reads"
    [ "$(jq 'length' <<<"$UNION")" -gt 0 ] \
        || rel_off "the relevant set is empty: no selected command has a hosted twin, and always_required is empty"

    REL_TMP=$(mktemp "${TMPDIR:-/tmp}/run-verification-relevant.XXXXXX") || die "could not create a temporary file"
    trap 'rm -f "$REL_TMP" "$REL_TMP.lines"' EXIT
    : > "$REL_TMP.lines"
    while IFS=$'\t' read -r wf job; do
        [ -n "$wf" ] || continue
        found=0
        for ref in HEAD "$MB" "$BASE_RESOLVED"; do
            if name=$(wf_display "$ref" "$wf"); then
                printf '%s\t%s\t%s\n' "$wf" "$job" "$name" >> "$REL_TMP.lines"
                found=1
            fi
        done
        if [ "$found" -eq 0 ]; then
            echo "run-verification: relevant: $wf is at none of HEAD, the merge-base and $BASE_RESOLVED; its check is matched by its path" >&2
            printf '%s\t%s\t%s\n' "$wf" "$job" "$wf" >> "$REL_TMP.lines"
        fi
    done <<EOF
$(jq -r '.[] | [.workflow, .job] | @tsv' <<<"$UNION")
EOF
    LC_ALL=C sort -u "$REL_TMP.lines" > "$REL_TMP" || die "could not sort the relevant set"
    koto context add "$SESSION" "$REL_KEY" --from-file "$REL_TMP" >/dev/null \
        || die "could not write $REL_KEY for session $SESSION"
    cat "$REL_TMP"
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

# 5b. A fix round's carry (see the header). Sets INVOCATIONS: the selection's
#     invocations, each with `carried` (the record to write in place of a run)
#     or `verify_base` (SHIRABE_VERIFY_BASE for its command) where the carry
#     applies.
INVOCATIONS=$(printf '%s' "$SELECTION" | jq -c '.invocations') || die "could not read the selection"

carry

# 5. One supervisor per head. The lock is a symlink whose target is a pid:
#    creating one is atomic. It names the supervisor from the moment it is
#    taken, never this process, so a --start stopped anywhere below (koto
#    kills an action's process group past its limit) leaves no lock that
#    reads as stale while a run is live.
LOCK="$HEAD_DIR/lock"
test_pause lock
lock_other "$LOCK" && exit 0

BUDGET=${SHIRABE_VERIFICATION_BUDGET_SECS:-$BUDGET_SECS}
case "$BUDGET" in ''|*[!0-9]*|0) BUDGET=$BUDGET_SECS ;; esac

# 6. Detach, held. `set -m` gives the background job its own process group,
#    so the group kill koto applies to this action never reaches the
#    supervisor. The supervisor first reads one line from a fifo on its fd 3
#    and runs only on `go`. This process holds the fifo's only write end, so
#    if it stops before the go, the supervisor reads end of file instead,
#    removes the lock if it names it, and exits having run nothing.
HOLD="$HEAD_DIR/hold.$$"
rm -f "$HOLD"
(umask 077 && mkfifo "$HOLD") || die "could not create $HOLD"
# The read-write open first, so neither one-way open after it blocks; then
# only the write end here and the read end the supervisor takes stay open.
if ! { exec 5<>"$HOLD"; } || ! { exec 3>"$HOLD"; } || ! { exec 4<"$HOLD"; }; then
    rm -f "$HOLD"; die "could not open $HOLD"
fi
exec 5<&-
rm -f "$HOLD"
set -m
(
    unset KOTO_TICK_SESSION
    # Moved by a bare exec: a redirection on the exec that runs the script
    # leaves bash 3.2's saved copies of fds 3 and 4 open in it, the write end
    # among them, and the supervisor would never read end of file.
    exec 3<&4 4<&-
    exec "$SELF" --supervise "$HEAD_DIR"
) </dev/null >>"$HEAD_DIR/supervisor.log" 2>&1 &
SUP=$!
set +m
exec 4<&-

# held_abort: stop the held supervisor: remove the lock if it names it, then
# close the write end, which the supervisor reads as end of file.
held_abort() {
    [ "$(readlink "$LOCK" 2>/dev/null)" = "$SUP" ] && rm -f "$LOCK"
    exec 3>&-
}

if ! lock_take "$LOCK" "$SUP"; then
    held_abort
    exit 0
fi

# A supervisor that finished after step 1's check wrote its result before it
# removed its lock, so the check made again under the lock is exact.
if [ -f "$RESULT" ] && jq -e --arg mb "$MB" '.merge_base == $mb and .status != "dirty-tree"' "$RESULT" >/dev/null; then
    held_abort
    exit 0
fi

# This run's attempt folder: the next free number, created here under the
# lock, so two starts can't share one.
if [ -L "$HEAD_DIR/attempts" ]; then
    held_abort; die "$HEAD_DIR/attempts is a symlink"
fi
ATTEMPT=$(next_attempt)
(umask 077 && mkdir -p "$HEAD_DIR/attempts" && mkdir "$HEAD_DIR/attempts/$ATTEMPT") \
    || { held_abort; die "could not create $HEAD_DIR/attempts/$ATTEMPT"; }

# The invocations are the selection's after step 5b, a fix round's carried
# records included.
jq -cn --arg root "$ROOT" --arg head "$HEAD_SHA" --arg mb "$MB" --argjson inv "$INVOCATIONS" --argjson budget "$BUDGET" \
    --argjson attempt "$ATTEMPT" \
    '{root: $root, head: $head, merge_base: $mb, budget_secs: $budget, attempt: $attempt, invocations: $inv}' \
    > "$HEAD_DIR/run.json" \
    || { held_abort; die "could not write run.json"; }

test_pause held
printf 'go\n' >&3 || { held_abort; die "could not release the supervisor"; }
exec 3>&-
test_pause started
exit 0
