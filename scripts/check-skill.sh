#!/usr/bin/env bash
#
# check-skill.sh - the deterministic checks a pull request that changes a
# skill must pass
#
# The `skills/**` entry of .claude/shirabe-extensions/work-on.md runs this once
# per changed skill at /work-on's definition-of-done gate. It replaces running
# the eval harness there: evals run in the release precondition
# (.claude/shirabe-extensions/release.md), not in a pull request. Nothing here
# starts `claude` or calls a model.
#
# For skills/<skill>/ it:
#   1. checks koto, python3 and git are on PATH, naming each one that is
#      missing (exit 2);
#   2. runs `shirabe validate` once over the skill's Markdown outside evals/
#      and koto-templates/, with the branch's own shirabe where the tree can
#      give one (SHIRABE_BIN, the tree's fresh target/release build, or a
#      build of it) and the installed one otherwise, naming which (exit 2
#      when there is none);
#   3. runs `koto template compile` on each koto-templates/*.md that is not a
#      *.mermaid.md;
#   4. runs each scripts/*_test.sh with `bash`, from the repository root, the
#      way the CI workflows invoke them, up to CHECK_SKILL_JOBS of them at
#      once, the costliest first, reporting each in the order a serial run
#      would. A failed suite is reported with every FAIL line in its log (and
#      the indented lines under each), the 1-minute load when it ended, and
#      its last 60 lines; the run opens with the load at its start;
#   5. runs scripts/lib/check-evals-shape.py on evals/evals.json (a skill whose
#      SKILL.md declares disable-model-invocation: true may have none);
#   6. runs the script cases that check the skill's hand-offs, with the
#      tree's own runner, `scripts/lib/script-cases.py --for <skill>`: the
#      skill's own `grader: script` cases and every other skill's whose
#      `handoff` names it, so a change to a skill fails the cases other skills
#      keep on their hand-offs to it. Each failing case is its own failure,
#      `script case: <skill> <id> <name>`, with the runner's reason under it.
#      A runner that is missing or exits with anything but 0 or 1 (an
#      evals.json it can't parse, say) fails the check closed;
#   7. runs scripts/check-pipe-readers.sh over the skill's directory, which
#      refuses a printf, echo or cat piped into grep -q or head;
#   8. runs scripts/check-mktemp-guards.sh over the skill's directory, which
#      refuses an unchecked mktemp whose value a cd, rm, mv or git acts on.
#
# Every check runs even after one fails. Each failure is reported with the
# file it concerns, and the run ends with the list of failures.
#
# Usage: scripts/check-skill.sh [--changed] [--list] <skill>
#   Run from anywhere; paths resolve against the repository root.
#   <skill> is the directory name under skills/, matching ^[a-z0-9][a-z0-9-]*$.
#   --changed  Run only the suites the branch's changes touch (step 4); every
#              other check runs as before, the script cases (step 6) in full
#              whatever changed: a branch that changes only an evals/ selects
#              few suites or none, and its cases still run. Used by the
#              verification map, never by CI. See "Selecting suites" below.
#   --list     Print the suites step 4 would launch, costliest first, one
#              repository-relative skills/<skill>/scripts/<name>_test.sh line
#              each, then the script cases step 6 would run, one
#              `script case: <skill> <id> <name>` line each, then exit 0
#              without running any check. With --changed the suites are the
#              selected ones, after a `check-skill: --changed ...` line giving
#              the reason for the selection; without it they are every suite
#              `check-skill.sh <skill>` runs, with no such line. The second
#              form is the full set a CI job running the plain command
#              covers, which the verification map's hosted declaration is
#              tested against.
#
# Selecting suites (--changed). The changed paths are `git diff --name-only
# --no-renames <merge-base>` plus untracked files, where the merge-base is
# HEAD's with the default branch (origin/HEAD's target, else origin/main,
# else main), as the verification gate computes it. Selection is opt-in: a
# skill with no check-skill.tsv runs every suite, unless every changed path is
# under an evals/ (the rule below). Otherwise each changed path is classified,
# and any path that selects every suite settles the run:
#   - nothing changed, or no merge-base: every suite;
#   - a path under any skill's evals/ (skills/<name>/evals/): the suites
#     that can read it (evals_readers: those that name evals directly or
#     through a helper, and those that walk the tree). The eval harness
#     reads evals/, the script suites mostly don't, so a change to it alone
#     runs few suites, or none;
#   - a Markdown file under docs/ or at the repository root, or a file under
#     .github/workflows/: the suites that name it (by file name, which a
#     suite naming its path does too). None names it: it selects none, and
#     says so. Suites that walk the tree are not added for these paths, since
#     CI runs every suite and the walkers are about half of coordinate's;
#   - any other path outside skills/<skill>/ (scripts/, references/, another
#     skill's files): every suite;
#   - a path under a subdirectory of scripts/ (testdata, test libraries):
#     every suite;
#   - scripts/<name>_test.sh: that suite;
#   - a deleted scripts/<file>: every suite;
#   - scripts/<file> named on a `shared` or `all` row of check-skill.tsv, or
#     sourced by two or more of the skill's files, and the skill's SKILL.md, a
#     file under its references/ or a koto-templates/<name>.md: what it
#     reaches (shirabe#1934). That's the suites that name it or one of its
#     callers, the own <stem>_test.sh of it and of each caller, and every
#     engine suite when it is a template or a template's front matter, where
#     koto's gates and actions run scripts, names it or a caller. Its callers
#     are the skill's scripts and the files under scripts/ subdirectories
#     whose code, not a comment, names it or another caller, followed to the
#     end of every chain. A jq module is also named by its
#     quoted stem, the way `include` names it; a file under references/ also
#     by `references`, and by `SKILL.md` when SKILL.md lists it. It or a
#     caller on an `all` row, deleted, or nothing selected: every suite. See
#     reach_suites;
#   - any other scripts/<file>: a script on an `all` row runs it, directly or
#     through other scripts (callers followed all the way up), every suite;
#     otherwise its own <stem>_test.sh, and every unit suite
#     (not *_engine_test.sh) that names the file or one of its callers, the
#     skill's other scripts/*.sh and *.jq files that name it, shared ones
#     excepted. Engine suites are taken only when no unit suite names any of
#     them, and when none does either, every suite runs;
#   - koto-templates/<name>.compat.json: as a scripts/ file would, since the
#     skill's scripts are what read it: the suites that name it or a script
#     that names it, unit suites first;
#   - anything else (other Markdown and data, check-skill.tsv itself): every
#     suite.
# Whatever the kind of a path under skills/<skill>/, every suite a `walk` row
# of check-skill.tsv declares as walking it is added to the selection: a suite
# that lists the tree with find or git ls-files and reads what it finds reaches
# the file without naming it, so nothing above would see it. A malformed walk
# row, or one naming no suite of the skill, runs every suite.
#
# Each suite's launch prints `check-skill: started bash <suite> (<n> of <m>)`,
# and a TERM or INT first prints `check-skill: stopped with <k> of <m> suites
# done; still running: <suites>`, so a check stopped at a time limit says
# where it stood.
#
# check-skill.tsv sits at skills/<skill>/check-skill.tsv, tab-separated, with
# `#` comments, and has four kinds of row:
#   shared <file under scripts/>   a change to it runs what it reaches, engine
#                                  suites included, not only its unit suites
#   all <file under scripts/>      the file runs every suite (a test runner),
#                                  so a change to it, or to any file it runs
#                                  directly or through other scripts, runs
#                                  every suite
#   walk <suite file name> <glob> [<skip glob>]
#                                  the suite walks the skill's tree and reads
#                                  every file whose path under skills/<skill>/
#                                  matches <glob> and not <skip glob> (case
#                                  patterns, where * also matches /), so a
#                                  change to any such file selects it,
#                                  whatever else the path selects. A suite
#                                  whose walk covers several globs has a row
#                                  for each
#   cost <suite file name> <secs>  the suite's measured CPU seconds; suites
#                                  launch costliest first, unlisted ones last
#                                  in glob order
# .claude/shirabe-extensions/README.md has the rule for keeping it current.
#
# Environment:
#   CHECK_SKILL_JOBS   How many of the skill's suites run at once, 1 to 99,
#                      default 4. 1 runs them one after another. Anything else
#                      is a usage error (exit 2).
#   CHECK_SKILL_ROOT   TEST-ONLY. Replaces the repository root, so
#                      scripts/check-skill_test.sh can point the checks at a
#                      throwaway skills/ tree. The shape helper always comes
#                      from this script's own checkout; the script-case runner
#                      always comes from the tree, since it runs the cases of
#                      the repository two levels above its own file. No
#                      extension file or workflow sets it.
#   CHECK_SKILL_CHANGED
#                      TEST-ONLY. With --changed, the changed paths, one per
#                      line, in place of the ones git reports. No extension
#                      file or workflow sets it.
#   SHIRABE_SUITE_SUMMARY
#                      A file to keep the suite summary in, which the
#                      verification gate's supervisor sets for each command it
#                      runs and copies into the command's record. When set (and
#                      not with --list), the script writes one JSON object,
#                      {"passed": [...], "failed": [...], "running": [...],
#                      "not_started": [...]}, each list the suites in that state
#                      by the names --changed --list prints, every selected
#                      suite in exactly one list. It is written once the
#                      selection is known, at each launch, as each suite ends,
#                      at the end and first thing on TERM or INT, each time to
#                      a temporary file renamed over the last, so a KILL leaves
#                      the last whole summary. The variable is unset before any
#                      check runs, so no suite can write the summary itself.
#                      Unset, nothing is written and nothing else changes.
#   SHIRABE_SUITE_LOCK_DIR, SHIRABE_SUITE_LOCK_SLOTS,
#   SHIRABE_SUITE_LOCK_WAIT_SECS, SHIRABE_SUITE_LOCK
#                      The host suite lock (scripts/lib/suite-lock.sh). Once
#                      the selection is known, and before anything heavy runs
#                      (the shirabe build, the suites), the run takes the lock,
#                      so two check-skill runs on one host, or one beside a
#                      verification run, never run their suites at once: the
#                      second prints who holds the lock and waits, up to
#                      SHIRABE_SUITE_LOCK_WAIT_SECS (default 3600). A run
#                      under a holder (the verification supervisor, which sets
#                      SHIRABE_SUITE_LOCK_HELD) takes nothing. --list takes
#                      nothing either.
#   KOTO_SESSIONS_BASE, KOTO_TICK_SESSION, KOTO_SESSION_*
#                      Cleared before any check runs: a koto session running
#                      this script passes its own store and session to it, and
#                      no suite may reach the caller's store.
#
# Exit codes:
#   0 - every check passed
#   1 - at least one check failed; each is listed
#   2 - usage error, an unknown skill, a required tool is missing, or the
#       repository root or a temporary file can't be set up
#   75 - the wait for the host suite lock passed its bound; nothing ran
#   130, 143 - stopped by INT or TERM; the suites it had started are stopped
#              too

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHAPE_CHECK="$SCRIPT_DIR/lib/check-evals-shape.py"
# shellcheck source=lib/suite-lock.sh
. "$SCRIPT_DIR/lib/suite-lock.sh" || { echo "check-skill: cannot load scripts/lib/suite-lock.sh" >&2; exit 2; }
# The tree's own script-case runner, relative to the root (step 6).
CASE_RUNNER="scripts/lib/script-cases.py"
ROOT="${CHECK_SKILL_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

usage() {
    echo "usage: scripts/check-skill.sh [--changed] [--list] <skill>" >&2
    exit 2
}

CHANGED=0
LIST=0
while [ $# -gt 1 ]; do
    case "$1" in
        --changed) CHANGED=1 ;;
        --list) LIST=1 ;;
        *) usage ;;
    esac
    shift
done
[ $# -eq 1 ] || usage
SKILL="$1"

# The suite summary's file (see the header). Taken here and unset, so nothing
# this script starts sees it: a suite that wrote there would put its own
# summary in place of this script's.
SUMMARY="${SHIRABE_SUITE_SUMMARY:-}"
unset SHIRABE_SUITE_SUMMARY
[ "$LIST" = 0 ] || SUMMARY=""

if ! grep -Eq '^[a-z0-9][a-z0-9-]*$' <<<"$SKILL" \
    || [ "$(printf '%s\n' "$SKILL" | wc -l | tr -d ' ')" != "1" ]; then
    echo "check-skill: invalid skill name (must match ^[a-z0-9][a-z0-9-]*\$)" >&2
    exit 2
fi

missing=""
for tool in koto python3 git; do
    command -v "$tool" >/dev/null || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "check-skill: required tool(s) not on PATH:$missing" >&2
    exit 2
fi

# koto hands the commands it runs its own session context: KOTO_SESSIONS_BASE
# names the session store, and KOTO_TICK_SESSION the session ticking. A
# check run from a koto session (the verification gate is one) would pass
# them to every suite, which then reads and writes that real store whatever
# HOME it gives itself. The KOTO_SESSION_* settings (a backend, a bucket) are
# cleared too, so a suite never reaches an owner's cloud store either.
unset KOTO_SESSIONS_BASE KOTO_TICK_SESSION
for v in $(env | sed -n 's/^\(KOTO_SESSION_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$v"
done

cd "$ROOT" || { echo "check-skill: cannot enter $ROOT" >&2; exit 2; }

SKILL_DIR="skills/$SKILL"
if [ ! -d "$SKILL_DIR" ]; then
    echo "check-skill: no such skill: $SKILL_DIR" >&2
    exit 2
fi

JOBS="${CHECK_SKILL_JOBS:-4}"
if ! grep -Eq '^[1-9][0-9]?$' <<<"$JOBS" \
    || [ "$(printf '%s\n' "$JOBS" | wc -l | tr -d ' ')" != "1" ]; then
    echo "check-skill: CHECK_SKILL_JOBS must be a whole number from 1 to 99" >&2
    exit 2
fi

LOG="$(mktemp)" || { echo "check-skill: cannot create a temporary file" >&2; exit 2; }
RUNS="$(mktemp -d)" || { rm -f "$LOG"; echo "check-skill: cannot create a temporary directory" >&2; exit 2; }
trap 'rm -rf "$LOG" "$RUNS"; sl_release' EXIT
# A stopped check stops the suites it started too: verification's timeout
# signals the whole process group, but a person's ^C or a plain kill of this
# script must not leave them running. Signalling each job and the two levels
# below it left anything deeper running (a script a suite runs, and what that
# script starts), and so did a suite that ignores TERM or drops one as it
# forks. So the whole tree is read from one process table, TERMed, given up to
# two seconds, and whatever is still there then, or started meanwhile, is
# KILLed. The suites stay in this script's process group rather than getting
# groups of their own: the verification gate counts that group's processes for
# its max_procs bound and kills the group after every command, and a suite in
# another group would escape both.
#
# our_processes prints every process started under this script, at any depth,
# and, when this script leads its own process group (a terminal's job, or the
# gate's command), every other member of that group: a suite's child whose
# parent already exited was reparented to pid 1 and is nobody's descendant
# here, but it kept the group. The ps and awk it runs are listed too; they have
# exited by the time anything is signalled.
our_processes() {
    ps -A -o pid=,ppid=,pgid= 2>/dev/null | awk -v me="$$" '
        { pid[NR] = $1; par[NR] = $2; grp[NR] = $3; if ($1 == me) mine = $3 }
        END {
            under[me] = 1
            do {
                more = 0
                for (i = 1; i <= NR; i++)
                    if (!(pid[i] in under) && (par[i] in under)) { under[pid[i]] = 1; more = 1 }
            } while (more)
            for (i = 1; i <= NR; i++)
                if (pid[i] != me && ((pid[i] in under) || (mine == me && grp[i] == me))) print pid[i]
        }'
}
stop_suites() {
    local first p alive n=0
    first=$(our_processes)
    [ -n "$first" ] || return 0
    # shellcheck disable=SC2086 # a list of pids
    kill -TERM $first 2>/dev/null
    while [ "$n" -lt 20 ]; do
        alive=""
        for p in $first; do
            if kill -0 "$p" 2>/dev/null; then alive=1; break; fi
        done
        [ -n "$alive" ] || break
        sleep 0.1
        n=$((n + 1))
    done
    # shellcheck disable=SC2086,SC2046 # lists of pids
    kill -KILL $first $(our_processes) 2>/dev/null
}
# report_stopped: once suites have launched, says how many finished and which
# are still running (a log but no status yet). It runs first in the traps,
# before stop_suites, because the verification gate sends KILL a second after
# TERM and a KILL runs no trap; the launch lines are what's left then.
LAUNCHED=0
report_stopped() {
    local i=0 finished=0 running=""
    [ "$LAUNCHED" -gt 0 ] || return 0
    while [ "$i" -lt "${#suites[@]}" ]; do
        if [ -f "$RUNS/$i.rc" ]; then
            finished=$((finished + 1))
        elif [ -f "$RUNS/$i.log" ]; then
            running="$running${running:+, }${suites[$i]}"
        fi
        i=$((i + 1))
    done
    echo "check-skill: stopped with $finished of ${#suites[@]} suites done; still running: ${running:-none}"
}
# write_summary [final]: the suite summary, when one is asked for (see the
# header), from each suite's files under $RUNS: a status file, finished (passed
# on 0, failed otherwise); a log and no status, running, or failed once every
# job has ended (`final`), which report_ready reports as no exit status
# recorded; neither, not started. Builtins only but the rename, since the TERM
# trap runs it with the verification gate's KILL a second away. QSUITES holds
# the suites' names already quoted for JSON, and SUMMARY_READY says they are
# known: a TERM before that has no selection to report.
SUMMARY_READY=0
SUMMARY_SEEN=""
write_summary() {
    [ -n "$SUMMARY" ] && [ "$SUMMARY_READY" = 1 ] || return 0
    local i=0 rc q p="" f="" r="" n="" tmp="$SUMMARY.$$.tmp"
    while [ "$i" -lt "${#suites[@]}" ]; do
        q=${QSUITES[$i]}
        if [ -f "$RUNS/$i.rc" ]; then
            rc=""
            read -r rc < "$RUNS/$i.rc"
            if [ "$rc" = 0 ]; then p="$p${p:+,}$q"; else f="$f${f:+,}$q"; fi
        elif [ -f "$RUNS/$i.log" ]; then
            if [ "${1:-}" = final ]; then f="$f${f:+,}$q"; else r="$r${r:+,}$q"; fi
        else
            n="$n${n:+,}$q"
        fi
        i=$((i + 1))
    done
    if printf '{"passed":[%s],"failed":[%s],"running":[%s],"not_started":[%s]}\n' \
            "$p" "$f" "$r" "$n" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$SUMMARY" 2>/dev/null || rm -f "$tmp"
    else
        rm -f "$tmp" 2>/dev/null
    fi
    return 0
}
# summary_tick: write the summary when a suite launched or ended since the
# last write, so the polling loops don't rewrite an unchanged one.
summary_tick() {
    [ -n "$SUMMARY" ] || return 0
    local i=0 ended=0
    while [ "$i" -lt "${#suites[@]}" ]; do
        [ -f "$RUNS/$i.rc" ] && ended=$((ended + 1))
        i=$((i + 1))
    done
    [ "$LAUNCHED:$ended" != "$SUMMARY_SEEN" ] || return 0
    SUMMARY_SEEN="$LAUNCHED:$ended"
    write_summary
}
trap 'write_summary; report_stopped; stop_suites; exit 143' TERM
trap 'write_summary; report_stopped; stop_suites; exit 130' INT

FAILURES=""
fail() {
    FAILURES="$FAILURES
  $1"
    echo "FAIL: $1"
}

# Show the tail of a failed command's output, so the failure reads on its own.
show_log() {
    sed -e 's/^/    /' "${1:-$LOG}" | tail -n 60
}

# load1: the host's 1-minute load average (Linux /proc/loadavg, or macOS
# sysctl's "{ 1.23 4.56 7.89 }"), or "unknown".
load1() {
    local l=""
    if [ -r /proc/loadavg ]; then
        read -r l _ < /proc/loadavg
    else
        l=$(sysctl -n vm.loadavg 2>/dev/null)
        l=${l#\{ }
        l=${l%% *}
    fi
    printf '%s\n' "${l:-unknown}"
}

# show_suite_failure <log> <load-file>: every FAIL line of a failed suite
# with the indented detail lines under it, wherever they fall in the log, then
# the 1-minute load when the suite ended and the log's tail. The tail alone
# lost the failing case's name when a long suite failed early (shirabe#867),
# and a load failure couldn't be filed without running the suite again.
show_suite_failure() {
    local lines
    lines=$(awk '/^[[:space:]]*(.\[[0-9;]*m)?(FAIL|not ok)([^A-Za-z]|$)/ { print "      " $0; d = 1; next }
                 d && /^[ \t]/ && !/^[[:space:]]*(.\[[0-9;]*m)?(ok|PASS)([^A-Za-z]|$)/ { print "      " $0; next }
                 { d = 0 }' "$1")
    if [ -n "$lines" ]; then
        echo "    every FAIL line:"
        printf '%s\n' "$lines"
    fi
    echo "    load when it ended: $(cat "$2" 2>/dev/null || echo unknown)"
    echo "    the log's last 60 lines:"
    show_log "$1"
}

echo "check-skill: $SKILL, load $(load1) at start"

suites=()
for t in "$SKILL_DIR"/scripts/*_test.sh; do
    [ -f "$t" ] && suites+=("$t")
done
MAP="$SKILL_DIR/check-skill.tsv"

# map_rows <kind>: the fields after <kind> on each of check-skill.tsv's rows of
# that kind, tab-separated.
map_rows() {
    [ -f "$MAP" ] || return 0
    awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print }' "$MAP"
}

# changed_paths: the paths this branch changes, one per line (see "Selecting
# suites"). Returns 1 when there is no merge-base to diff against.
changed_paths() {
    if [ -n "${CHECK_SKILL_CHANGED+set}" ]; then
        printf '%s\n' "$CHECK_SKILL_CHANGED" | sed '/^$/d'
        return 0
    fi
    local base mb
    base=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
    if [ -z "$base" ]; then
        if git rev-parse --verify -q "origin/main^{commit}" >/dev/null 2>&1; then
            base=origin/main
        else
            base=main
        fi
    fi
    mb=$(git merge-base HEAD "$base" 2>/dev/null) || return 1
    { git diff --name-only --no-renames "$mb" -- && git ls-files --others --exclude-standard; } \
        | sort -u
}

# in_list <word> <list>: whether <list> (one word per line) holds <word>.
# grep reads the list from a here-document, not a pipe, so a match that ends
# grep early can't fail the writer under pipefail.
in_list() {
    grep -qxF -- "$1" <<EOF
$2
EOF
}

# sourced_by_several: each file name that two or more of the skill's shell
# files source (`. path` or `source path`), with the count, tab-separated.
sourced_by_several() {
    grep -rE --include='*.sh' '^[[:space:]]*(\.|source)[[:space:]]' "$SKILL_DIR" 2>/dev/null | awk '
        {
            i = index($0, ":"); f = substr($0, 1, i - 1); l = substr($0, i + 1)
            while (match(l, /[A-Za-z0-9_.-]+\.(sh|jq)/)) {
                n = substr(l, RSTART, RLENGTH)
                if (!((f, n) in seen)) { seen[f, n] = 1; c[n]++ }
                l = substr(l, RSTART + RLENGTH)
            }
        }
        END { for (n in c) if (c[n] >= 2) printf "%s\t%d\n", n, c[n] }'
}

# callers_of <name> <shared>: <name>, then each of the skill's scripts/*.sh and
# *.jq files that names it, suites and the <shared> files (one per line)
# excepted. One file name per line. One level only: the scripts name each
# other so widely that following callers further reaches most of the skill
# (45 of coordinate's 77 suites from almost any script), which selects nothing
# worth having; CI runs every suite. This is for a plain script only: a shared
# file's callers are followed to the end of every chain (reach_suites).
callers_of() {
    local f
    echo "$1"
    for f in $(grep -lF -- "$1" "$SKILL_DIR"/scripts/*.sh "$SKILL_DIR"/scripts/*.jq 2>/dev/null); do
        f=$(basename "$f")
        case "$f" in *_test.sh|"$1") continue ;; esac
        in_list "$f" "$2" || echo "$f"
    done
}

# A path under a skill's evals/: skills/<name>/evals/...
EVALS_PATH_RE='^skills/[^/]*/evals/'

# evals_readers: the suites that can read a skill's evals/ (shirabe#851), one
# per line. That's those that name evals, directly or through a helper (any
# file under the skill's scripts/ that isn't a suite) that names evals or names
# such a helper, two levels in all; and those that walk the tree (find, ls -R,
# cp -r, grep -r or --recursive, git grep, git ls-files, rg), which read
# whatever it holds. Unlike the rules for scripts, this one can't fall back to
# every suite when it misses: a suite that reaches evals/ some other way (a
# third-level helper, a path built at run time) is left out. Matching errs
# toward selecting more.
evals_readers() {
    local walk h1 h2 pats
    walk='evals|(^|[^A-Za-z0-9_-])(find|rg|git grep)[[:space:]]|(^|[^A-Za-z0-9_-])grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*[rR][A-Za-z]*([[:space:]]|$)|grep[[:space:]].*--recursive|ls-files|(^|[^A-Za-z0-9_-])ls[[:space:]]+-[A-Za-z]*R|(^|[^A-Za-z0-9_-])cp[[:space:]]+-[A-Za-z]*[rRa]'
    h1=$(find "$SKILL_DIR/scripts" -type f ! -name '*_test.sh' -exec grep -lF evals {} + 2>/dev/null \
        | sed 's|.*/||' | sort -u)
    h2=""
    [ -z "$h1" ] || h2=$(find "$SKILL_DIR/scripts" -type f ! -name '*_test.sh' \
        -exec grep -lF -f <(printf '%s\n' "$h1") {} + 2>/dev/null | sed 's|.*/||' | sort -u)
    pats=$(printf '%s\n%s\n' "$h1" "$h2" | sed '/^$/d')
    {
        grep -lE "$walk" "${suites[@]}"
        [ -z "$pats" ] || grep -lF -f - "${suites[@]}" <<<"$pats"
    } | sort -u
}

# naming_suites <path>: adds to SELECTED the suites that name <path>'s file
# name, which every suite naming its repository-relative path does too. When
# none names it, it selects none and says so; suites that walk the tree are not
# added, since CI runs every suite.
naming_suites() {
    local hits
    hits=$(grep -lF -- "${1##*/}" "${suites[@]}")
    if [ -n "$hits" ]; then
        SELECTED="$SELECTED
$hits"
    else
        echo "check-skill: --changed: no suite names $1, so it selects none (CI runs every suite)"
    fi
}

# is_template <path>: whether <path> is one of the skill's koto templates,
# koto-templates/<name>.md and not a .mermaid.md diagram.
is_template() {
    case "$1" in
        "$SKILL_DIR"/koto-templates/*.mermaid.md) return 1 ;;
        "$SKILL_DIR"/koto-templates/*/*) return 1 ;;
        "$SKILL_DIR"/koto-templates/*.md) return 0 ;;
    esac
    return 1
}

# template_heads: the front matter of each of the skill's koto templates, where
# the gates and default actions name the scripts koto itself runs. The body's
# directives only tell the agent what to run, which an engine suite doesn't.
template_heads() {
    local t
    for t in "$SKILL_DIR"/koto-templates/*.md; do
        [ -f "$t" ] && is_template "$t" || continue
        awk 'NR == 1 && /^---[[:space:]]*$/ { on = 1; next }
             on && /^---[[:space:]]*$/ { exit }
             on' "$t"
    done
}

# CODE_NAMES: an awk program that, given CODE_NAMES_WANT=<strings, one per
# line> in its environment (macOS awk refuses a newline in -v), prints each
# input file with a line naming one of the strings, a comment line (first
# non-blank character #) not counting. Standard input prints as "-".
CODE_NAMES='BEGIN { n = split(ENVIRON["CODE_NAMES_WANT"], want, "\n") }
FNR == 1 { done = 0 }
done || /^[[:space:]]*#/ { next }
{ for (i = 1; i <= n; i++) if (want[i] != "" && index($0, want[i])) { print (FILENAME == "" ? "-" : FILENAME); done = 1; next } }'

# name_forms <file>: the strings that name <file> in code, one per line: its
# file name, and for a jq module also its quoted stem, which is how jq's
# `include` and `import` name it.
name_forms() {
    local n=${1##*/}
    echo "$n"
    case "$n" in *.jq) printf '"%s"\n' "${n%.jq}" ;; esac
}

# caller_closure <path> <names>: <path>'s callers, followed to a fixpoint.
# <names> are the strings that name <path>, one per line. Sets CLOSURE (<path>
# then each caller, newline-separated) and CLOSURE_NAMES (<names> plus each
# caller's name forms). A caller is one of the skill's scripts, or a file under
# a subdirectory of scripts/, whose code names <path> or a caller already
# found, a comment line not counting. Each round looks for the files naming
# what the last round found and stops when a round finds nothing new; a file
# already found isn't followed again, which ends a cycle.
CLOSURE=""
CLOSURE_NAMES=""
caller_closure() {
    local want found c
    CLOSURE=$1
    CLOSURE_NAMES=$2
    want=$2
    while [ -n "$want" ]; do
        found=$({
            find "$SKILL_DIR/scripts" -mindepth 1 -maxdepth 1 -type f ! -name '*_test.sh' \
                -exec env CODE_NAMES_WANT="$want" awk "$CODE_NAMES" {} + 2>/dev/null
            find "$SKILL_DIR/scripts" -mindepth 2 -type f \
                -exec env CODE_NAMES_WANT="$want" awk "$CODE_NAMES" {} + 2>/dev/null
        } | sort -u)
        want=""
        for c in $found; do
            in_list "$c" "$CLOSURE" && continue
            CLOSURE="$CLOSURE
$c"
            want="$want
$(name_forms "$c")"
        done
        want=$(printf '%s\n' "$want" | sed '/^$/d')
        [ -z "$want" ] || CLOSURE_NAMES="$CLOSURE_NAMES
$want"
    done
}

# all_row_reason <path> <closure>: prints why every suite runs when <path> or
# a file in its caller closure (one per line) is on an `all` row of
# check-skill.tsv, a script that runs every suite; prints nothing otherwise.
all_row_reason() {
    local c every
    every=$(map_rows all | cut -f1)
    [ -n "$every" ] || return 0
    for c in $2; do
        in_list "${c##*/}" "$every" || continue
        if [ "$c" = "$1" ]; then
            echo "$1 runs every suite (an all row of check-skill.tsv)"
        else
            echo "$1 is reached through ${c##*/}, which runs every suite (an all row of check-skill.tsv)"
        fi
        return 0
    done
}

# reach_suites <path>: the suites a change to <path> can reach
# (shirabe#1934), for a script that several of the skill's files source and
# for the skill's own Markdown and data files (SKILL.md, references/, koto
# templates), which all used to select every suite, and for a script on a
# shared row of check-skill.tsv. Sets REACH (suite paths, newline-separated)
# or REACH_ALL (why every suite runs).
#   - Names: <path>'s name forms. A file under references/ also counts as
#     named by `references`, since suites and scripts build those paths at run
#     time and glob the directory, and by `SKILL.md` when SKILL.md names it,
#     since a script can follow SKILL.md's table of reference files.
#   - Callers, followed to a fixpoint: each of the skill's scripts, and each
#     file under a subdirectory of scripts/ (test libraries, testdata), whose
#     code names <path> or a caller already found, a comment line not
#     counting, since a comment runs and reads nothing. A suite that reaches
#     <path> only through a chain of scripts reaches it all the same, so the
#     chain is followed to its end; a file already found isn't followed again,
#     which ends a cycle.
#   - <path> or any caller on an `all` row of check-skill.tsv (a script that
#     runs every suite, such as a test runner): every suite.
#   - The suites that name <path> or a caller (anywhere in the file, comments
#     included, the way a suite declares a script it reaches only through a
#     variable), and the own <stem>_test.sh of <path> and of each caller.
#   - Every engine suite (*_engine_test.sh) when <path> is a koto template, or
#     when a template's front matter names <path> or a caller: koto runs
#     those scripts in any engine run that reaches the state.
#   - Nothing selected: every suite, since nothing says where it reaches.
REACH=""
REACH_ALL=""
reach_suites() {
    local p=$1 names closure c s engine=""
    REACH="" REACH_ALL=""
    names=$(name_forms "$p")
    case "$p" in
        "$SKILL_DIR"/references/*)
            names="$names
references"
            if [ -f "$SKILL_DIR/SKILL.md" ] && grep -qF -- "${p##*/}" "$SKILL_DIR/SKILL.md"; then
                names="$names
SKILL.md"
            fi ;;
    esac
    caller_closure "$p" "$names"
    closure=$CLOSURE names=$CLOSURE_NAMES
    REACH_ALL=$(all_row_reason "$p" "$closure")
    [ -z "$REACH_ALL" ] || return 0
    REACH=$(grep -lF -- "$names" "${suites[@]}")
    for c in $closure; do
        case "$c" in
            "$SKILL_DIR"/scripts/*) ;;
            *) continue ;;
        esac
        c=${c##*/}
        s="$SKILL_DIR/scripts/${c%.*}_test.sh"
        [ -f "$s" ] && REACH="$REACH
$s"
    done
    if is_template "$p" || [ -n "$(template_heads | CODE_NAMES_WANT="$names" awk "$CODE_NAMES")" ]; then
        engine=1
        for s in "${suites[@]}"; do
            case "$s" in
                *_engine_test.sh) REACH="$REACH
$s" ;;
            esac
        done
    fi
    REACH=$(printf '%s\n' "$REACH" | sed '/^$/d')
    if [ -z "$REACH" ]; then
        REACH_ALL="no suite names $p${engine:+ and the skill has no engine suite}"
    fi
}

# walk_problem: prints why check-skill.tsv's walk rows can't be used, a row
# without a suite and a glob, with more than one skip glob, or naming a file
# that isn't one of the skill's suites; prints nothing when they can. A walk
# row that can't be used would drop the suite it declares, so the caller runs
# every suite instead.
walk_problem() {
    local line suite all
    line=$(awk -F'\t' '$1 == "walk" && (NF < 3 || NF > 4 || $2 == "" || $3 == "") { print NR; exit }' "$MAP")
    if [ -n "$line" ]; then
        echo "line $line of check-skill.tsv is a malformed walk row"
        return 0
    fi
    all=$(printf '%s\n' "${suites[@]}")
    for suite in $(map_rows walk | cut -f1); do
        if ! in_list "$SKILL_DIR/scripts/$suite" "$all"; then
            echo "a walk row of check-skill.tsv names $suite, which is not one of $SKILL_DIR's suites"
            return 0
        fi
    done
}

# walkers <path>: the suites a `walk` row of check-skill.tsv declares as reading
# <path>, one per line: <path> is under the skill's directory, and the rest of
# it matches the row's glob and not its skip glob. Reads WALK_ROWS.
WALK_ROWS=""
walkers() {
    local rel=${1#"$SKILL_DIR"/} suite glob skip
    [ "$rel" != "$1" ] || return 0
    while IFS='	' read -r suite glob skip; do
        [ -n "$suite" ] && [ -n "$glob" ] || continue
        # Unquoted, so each is a pattern; a case pattern's * matches / too.
        # shellcheck disable=SC2254
        case "$rel" in $glob) ;; *) continue ;; esac
        if [ -n "$skip" ]; then
            # shellcheck disable=SC2254
            case "$rel" in $skip) continue ;; esac
        fi
        echo "$SKILL_DIR/scripts/$suite"
    done <<EOF
$WALK_ROWS
EOF
}

# select_suites: sets SELECTED (suite paths, newline-separated, possibly with
# repeats) or ALL_REASON, which means every suite runs.
SELECTED=""
ALL_REASON=""
READERS=""
READERS_DONE=""
select_suites() {
    local paths p name rows every sourced shared names hits units engines s
    if [ ! -f "$MAP" ]; then
        # Without the file, a change only to evals/ still selects, since the
        # rule needs none of its rows.
        if [ ${#suites[@]} -gt 0 ] && paths=$(changed_paths) && [ -n "$paths" ] \
            && ! grep -qv "$EVALS_PATH_RE" <<<"$paths"; then
            SELECTED=$(evals_readers)
            return
        fi
        ALL_REASON="$SKILL_DIR has no check-skill.tsv"
        return
    fi
    if [ ${#suites[@]} -eq 0 ]; then
        ALL_REASON="$SKILL_DIR has no suites"
        return
    fi
    if ! paths=$(changed_paths); then
        ALL_REASON="no merge-base with the default branch"
        return
    fi
    if [ -z "$paths" ]; then
        ALL_REASON="no changed path"
        return
    fi
    ALL_REASON=$(walk_problem)
    [ -z "$ALL_REASON" ] || return
    WALK_ROWS=$(map_rows walk)
    # A script on an `all` row is shared too: reach_suites sees the row and
    # runs every suite for it and for whatever it runs.
    rows=$(map_rows shared | cut -f1; map_rows all | cut -f1)
    every=$(map_rows all | cut -f1)
    sourced=$(sourced_by_several)
    shared=$(printf '%s\n%s\n' "$rows" "$sourced" | cut -f1 | sed '/^$/d')
    while IFS= read -r p; do
        # The suites that walk the tree to <path> (walk rows), whatever kind
        # of path it is; the rules below add the suites that name it.
        SELECTED="$SELECTED
$(walkers "$p")"
        case "$p" in
            "$SKILL_DIR"/scripts/*/*)
                ALL_REASON="$p is shared test code"; return ;;
            "$SKILL_DIR"/scripts/*_test.sh)
                if [ ! -f "$p" ]; then
                    ALL_REASON="$p is deleted"; return
                fi
                SELECTED="$SELECTED
$p" ;;
            skills/*/evals/*)
                # A case `*` crosses `/`, so skills/x/scripts/evals/y lands
                # here too; it isn't an evals path and runs every suite.
                if ! grep -q "$EVALS_PATH_RE" <<<"$p"; then
                    ALL_REASON="$p is not one of $SKILL_DIR's scripts"; return
                fi
                [ -n "$READERS_DONE" ] || { READERS=$(evals_readers); READERS_DONE=1; }
                SELECTED="$SELECTED
$READERS" ;;
            "$SKILL_DIR"/scripts/*|"$SKILL_DIR"/koto-templates/*.compat.json)
                # A compat file is read by the skill's scripts, so it selects
                # as a change to one of them would.
                name=${p##*/}
                if [ ! -f "$p" ]; then
                    ALL_REASON="$p is deleted"; return
                fi
                if in_list "$name" "$shared"; then
                    # On a shared row or sourced by several: everything it
                    # and its callers reach, engine suites included.
                    reach_suites "$p"
                    if [ -n "$REACH_ALL" ]; then
                        ALL_REASON=$REACH_ALL; return
                    fi
                    SELECTED="$SELECTED
$REACH"
                    continue
                fi
                # A script that one on an `all` row runs, directly or through
                # other scripts: every suite. Only that test follows callers
                # all the way up; the selection below stays one level.
                if [ -n "$every" ]; then
                    caller_closure "$p" "$(name_forms "$p")"
                    ALL_REASON=$(all_row_reason "$p" "$CLOSURE")
                    [ -z "$ALL_REASON" ] || return
                fi
                names=$(callers_of "$name" "$shared")
                hits=$(grep -lF -f - "${suites[@]}" <<<"$names")
                # The script's own suite counts whether or not it names it.
                s="$SKILL_DIR/scripts/${name%.*}_test.sh"
                [ -f "$s" ] && hits="$hits
$s"
                units=$(printf '%s\n' "$hits" | grep -v '_engine_test\.sh$')
                engines=$(printf '%s\n' "$hits" | grep '_engine_test\.sh$')
                if [ -n "$units" ]; then
                    SELECTED="$SELECTED
$units"
                elif [ -n "$engines" ]; then
                    SELECTED="$SELECTED
$engines"
                else
                    ALL_REASON="no suite names $p"; return
                fi ;;
            "$SKILL_DIR"/SKILL.md|"$SKILL_DIR"/references/*|"$SKILL_DIR"/koto-templates/*.md)
                # The skill's own documents and the template: the suites
                # they can reach (reach_suites).
                if [ ! -f "$p" ]; then
                    ALL_REASON="$p is deleted"; return
                fi
                reach_suites "$p"
                if [ -n "$REACH_ALL" ]; then
                    ALL_REASON=$REACH_ALL; return
                fi
                SELECTED="$SELECTED
$REACH" ;;
            docs/*.md|.github/workflows/*)
                naming_suites "$p" ;;
            *.md)
                # Only a document at the repository root; other Markdown
                # (SKILL.md, references/) runs every suite.
                case "$p" in
                    */*) ALL_REASON="$p is not one of $SKILL_DIR's scripts"; return ;;
                esac
                naming_suites "$p" ;;
            *)
                ALL_REASON="$p is not one of $SKILL_DIR's scripts"; return ;;
        esac
    done <<EOF
$paths
EOF
}

# The launch order: suite indexes, the costliest first by check-skill.tsv's
# cost rows; suites with no cost row follow in the glob's order.
ORDER=()
order_suites() {
    local i=0 c costs keyed="" sorted
    costs=$(map_rows cost)
    while [ "$i" -lt "${#suites[@]}" ]; do
        c=$(printf '%s\n' "$costs" | awk -F'\t' -v s="$(basename "${suites[$i]}")" '$1 == s { print $2; exit }')
        case "$c" in ''|*[!0-9]*) c=-1 ;; esac
        keyed="$keyed$c $i
"
        i=$((i + 1))
    done
    sorted=$(printf '%s' "$keyed" | sort -k1,1nr -k2,2n | cut -d' ' -f2)
    for i in $sorted; do
        ORDER+=("$i")
    done
}

if [ "$CHANGED" = 1 ]; then
    select_suites
    if [ -z "$ALL_REASON" ]; then
        kept=()
        for t in "${suites[@]}"; do
            in_list "$t" "$SELECTED" && kept+=("$t")
        done
        echo "check-skill: --changed selects ${#kept[@]} of ${#suites[@]} suites"
        suites=("${kept[@]+"${kept[@]}"}")
    else
        echo "check-skill: --changed runs every suite: $ALL_REASON"
    fi
fi
order_suites

if [ "$LIST" = 1 ]; then
    for i in "${ORDER[@]+"${ORDER[@]}"}"; do
        echo "${suites[$i]}"
    done
    # The script cases step 6 would run, listed by the runner, which runs none.
    if [ ! -f "$CASE_RUNNER" ]; then
        echo "check-skill: script cases: no runner at $CASE_RUNNER" >&2
        exit 2
    fi
    if ! python3 "$CASE_RUNNER" --for "$SKILL" --list >"$LOG" 2>&1; then
        show_log >&2
        echo "check-skill: script cases: the runner could not list them" >&2
        exit 2
    fi
    sed -e '/^$/d' -e 's/^/script case: /' "$LOG"
    exit 0
fi

# The selection is known: every suite starts as not started in the summary.
QSUITES=()
for t in "${suites[@]+"${suites[@]}"}"; do
    q=${t//\\/\\\\}
    q=${q//\"/\\\"}
    QSUITES+=("\"$q\"")
done
SUMMARY_READY=1
write_summary

echo "check-skill: $SKILL_DIR"

# One heavy suite at a time on this host (see SHIRABE_SUITE_LOCK_* above).
# Taken here, after the selection and before the shirabe build, so a run that
# would only list or refuse never queues. The wait's lines go to stdout with
# the rest of the run's report.
if [ "$CHANGED" = 1 ]; then SL_LABEL="check-skill --changed $SKILL in $ROOT"; else SL_LABEL="check-skill $SKILL in $ROOT"; fi
sl_acquire "$SL_LABEL" 2>&1
case $? in
    0) ;;
    1) echo "check-skill: nothing ran: the host suite lock was still held by $SL_HOLDER"; exit 75 ;;
    *) echo "check-skill: the host suite lock could not be set up; running without it" ;;
esac

# The shirabe that validates (shirabe#860): the branch's own wherever the
# tree can give one, so a format newer than the installed release (a PLAN
# schema, say) is judged by the code that ships with it rather than failing
# on content that is correct. In order:
#   1. SHIRABE_BIN, when set to an executable (CI builds the branch's);
#   2. the tree's target/release/shirabe, when nothing under crates/ and no
#      Cargo.toml or Cargo.lock is newer than it;
#   3. a build of it (cargo build --release --locked -p shirabe), once, when
#      the tree is shirabe's source and cargo is on PATH;
#   4. the installed shirabe on PATH.
# The run says which it used. A binary from 1 to 3 is also exported as
# SHIRABE_BIN, which the suites that run shirabe read.
resolve_shirabe() {
    local bin="target/release/shirabe" newer
    if [ -n "${SHIRABE_BIN:-}" ] && [ -x "$SHIRABE_BIN" ]; then
        VALIDATOR=$SHIRABE_BIN VALIDATOR_FROM="SHIRABE_BIN"
        return 0
    fi
    [ -f crates/shirabe/Cargo.toml ] || return 1
    if [ -x "$bin" ]; then
        newer=$(find crates Cargo.toml Cargo.lock -newer "$bin" -type f 2>/dev/null)
        if [ -z "$newer" ]; then
            VALIDATOR="$ROOT/$bin" VALIDATOR_FROM="the tree's build"
            return 0
        fi
    fi
    command -v cargo >/dev/null || return 1
    echo "check-skill: building shirabe from the tree (cargo build --release --locked -p shirabe)"
    if cargo build --release --locked -p shirabe >"$LOG" 2>&1 && [ -x "$bin" ]; then
        VALIDATOR="$ROOT/$bin" VALIDATOR_FROM="a build of the tree"
        return 0
    fi
    show_log
    echo "check-skill: the build failed; falling back to the installed shirabe"
    return 1
}
VALIDATOR="" VALIDATOR_FROM=""
if resolve_shirabe; then
    export SHIRABE_BIN="$VALIDATOR"
elif command -v shirabe >/dev/null; then
    VALIDATOR=$(command -v shirabe) VALIDATOR_FROM="the installed release"
else
    echo "check-skill: required tool(s) not on PATH: shirabe (and the tree builds none)" >&2
    exit 2
fi
echo "check-skill: validating with $VALIDATOR ($VALIDATOR_FROM)"

# 2. shirabe validate, once, over the skill's Markdown outside evals/ and
# koto-templates/. Collected into an array so names reach the tool intact.
md_files=()
while IFS= read -r f; do
    [ -n "$f" ] && md_files+=("$f")
done <<EOF
$(find "$SKILL_DIR" -type f -name '*.md' \
    -not -path "$SKILL_DIR/evals/*" -not -path "$SKILL_DIR/koto-templates/*" | sort)
EOF

if [ ${#md_files[@]} -eq 0 ]; then
    echo "shirabe validate: no Markdown outside evals/ and koto-templates/"
elif "$VALIDATOR" validate "${md_files[@]}" >"$LOG" 2>&1; then
    echo "ok: shirabe validate (${#md_files[@]} files)"
else
    show_log
    fail "shirabe validate rejected the skill's Markdown (files named above under $SKILL_DIR)"
fi

# 3. koto template compile on each template that is not a mermaid rendering.
for t in "$SKILL_DIR"/koto-templates/*.md; do
    [ -f "$t" ] || continue
    case "$t" in
        *.mermaid.md) continue ;;
    esac
    if koto template compile "$t" >"$LOG" 2>&1; then
        echo "ok: koto template compile $t"
    else
        show_log
        fail "koto template compile: $t"
    fi
done

# 4. The skill's own script suites, from the repository root. Up to $JOBS run
# at once, each into its own log. A suite keeps what it writes in its own
# temporary directory (and points HOME or TMPDIR there when a tool it runs
# writes under them), so suites don't meet; the one exception, a build of
# target/release/ in the checkout, is made by at most one suite per skill.
# They launch in ORDER, the costliest first, so the longest suites don't start
# last and set the tail. Results print in the glob's order, each as soon as it
# and every suite before it are done, so the output reads as it did when the
# suites ran one after another.
NEXT=0
# report_ready: print, in order, every result whose suite and predecessors
# are done.
report_ready() {
    local rc
    while [ "$NEXT" -lt "${#suites[@]}" ] && [ -f "$RUNS/$NEXT.rc" ]; do
        rc=$(cat "$RUNS/$NEXT.rc")
        if [ "$rc" = 0 ]; then
            echo "ok: bash ${suites[$NEXT]}"
        else
            show_suite_failure "$RUNS/$NEXT.log" "$RUNS/$NEXT.load"
            fail "bash ${suites[$NEXT]}"
        fi
        NEXT=$((NEXT + 1))
    done
}
for i in "${ORDER[@]+"${ORDER[@]}"}"; do
    # Slots are counted from live jobs, not from .rc files: a job whose wrapper
    # died writes none, and counting files would wait for it forever.
    while [ "$(jobs -r | wc -l | tr -d ' ')" -ge "$JOBS" ]; do
        report_ready
        summary_tick
        sleep 0.2
    done
    # The .rc file appears whole (written, then renamed), so a reader never
    # sees a suite as finished before its status is there.
    # A failed suite also records the load as it ended, which a failure under
    # load is filed with. Each launch is named as it happens, which a KILL
    # leaves in the log when no trap can run. The log is made here, before
    # the job starts, so a stop always counts a launched suite as running.
    LAUNCHED=$((LAUNCHED + 1))
    echo "check-skill: started bash ${suites[$i]} ($LAUNCHED of ${#suites[@]})"
    : > "$RUNS/$i.log"
    ( bash "${suites[$i]}" </dev/null >"$RUNS/$i.log" 2>&1
      rc=$?
      [ "$rc" = 0 ] || load1 > "$RUNS/$i.load"
      echo "$rc" > "$RUNS/$i.rc.tmp" && mv "$RUNS/$i.rc.tmp" "$RUNS/$i.rc" ) &
    summary_tick
done
# With a summary asked for, the last suites are polled rather than waited on,
# so the summary records each as it ends; without one, the plain wait as before.
if [ -n "$SUMMARY" ]; then
    while [ "$(jobs -r | wc -l | tr -d ' ')" -gt 0 ]; do
        report_ready
        summary_tick
        sleep 0.2
    done
fi
wait
report_ready
# A suite with no status after every job has ended (its wrapper killed before
# it could write one) is a failure, never a silent gap in the report.
while [ "$NEXT" -lt "${#suites[@]}" ]; do
    [ -f "$RUNS/$NEXT.log" ] && show_suite_failure "$RUNS/$NEXT.log" "$RUNS/$NEXT.load"
    fail "bash ${suites[$NEXT]} (no exit status recorded)"
    NEXT=$((NEXT + 1))
    report_ready
done
write_summary final

# 5. The shape of the eval scenarios.
evals_json="$SKILL_DIR/evals/evals.json"
if python3 "$SHAPE_CHECK" "$evals_json" "$SKILL_DIR/SKILL.md" >"$LOG" 2>&1; then
    echo "ok: eval shape ($evals_json)"
else
    show_log
    fail "eval shape: $evals_json"
fi

# 6. The script cases that check the skill's hand-offs. The runner runs in the
#    background and is waited for, because bash runs a trap only once the
#    foreground command has ended: a TERM to this script has to reach
#    stop_suites, which stops the runner, while a case is still running. The
#    runner kills the running case's process group when it is signalled.
#
# report_script_cases <rc>: one failure per failing case, named
# `script case: <skill> <id> <name>` with its reason under it, read from the
# runner's `== <skill>` headers and FAIL lines in $LOG. Anything else but a
# pass fails closed, with the runner's output.
report_script_cases() {
    local rc="$1" total line failed
    total=$(sed -n 's/^script cases: \([0-9][0-9]* of [0-9][0-9]* passed\)$/\1/p' "$LOG" | tail -n 1)
    if [ "$rc" = 0 ] && [ -n "$total" ]; then
        echo "ok: script cases ($total)"
        return
    fi
    failed=$(awk '
        /^== / { skill = substr($0, 4); d = 0; next }
        /^FAIL / {
            rest = substr($0, 6); sp = index(rest, " ")
            id = substr(rest, 1, sp - 1); rest = substr(rest, sp + 1)
            c = index(rest, ": ")
            print "@@ " skill " " id " " substr(rest, 1, c - 1)
            print "    " substr(rest, c + 2); d = 1; next
        }
        d && /^    / { print "    " $0; next }
        { d = 0 }' "$LOG")
    if [ "$rc" = 1 ] && [ -n "$total" ] && [ -n "$failed" ]; then
        while IFS= read -r line; do
            case "$line" in
                "@@ "*) fail "script case: ${line#@@ }" ;;
                *) printf '%s\n' "$line" ;;
            esac
        done <<EOF
$failed
EOF
        echo "    script cases: $total"
        return
    fi
    show_log
    fail "script cases: the runner exited $rc ($CASE_RUNNER --for $SKILL)"
}
if [ ! -f "$CASE_RUNNER" ]; then
    fail "script cases: no runner at $CASE_RUNNER"
else
    python3 "$CASE_RUNNER" --for "$SKILL" >"$LOG" 2>&1 &
    wait "$!"
    report_script_cases "$?"
fi

# 7. No shell value piped into a reader that stops early (grep -q, head):
#    under pipefail the writer can be cut off and a match read as no match.
if bash "$SCRIPT_DIR/check-pipe-readers.sh" "$SKILL_DIR" >"$LOG" 2>&1; then
    echo "ok: pipe readers ($SKILL_DIR)"
else
    show_log
    fail "pipe readers: $SKILL_DIR (scripts/check-pipe-readers.sh)"
fi

# 8. No unchecked mktemp feeding a cd, rm, mv or git: a failed mktemp leaves
#    the value empty, and `cd ""` stays in the caller's directory.
if bash "$SCRIPT_DIR/check-mktemp-guards.sh" "$SKILL_DIR" >"$LOG" 2>&1; then
    echo "ok: mktemp guards ($SKILL_DIR)"
else
    show_log
    fail "mktemp guards: $SKILL_DIR (scripts/check-mktemp-guards.sh)"
fi

if [ -n "$FAILURES" ]; then
    echo ""
    echo "check-skill: $SKILL failed:$FAILURES"
    exit 1
fi

echo ""
echo "check-skill: $SKILL passed"
exit 0
