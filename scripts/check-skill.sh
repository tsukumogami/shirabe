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
# Usage: scripts/check-skill.sh [--changed [--list]] <skill>
#   Run from anywhere; paths resolve against the repository root.
#   <skill> is the directory name under skills/, matching ^[a-z0-9][a-z0-9-]*$.
#   --changed  Run only the suites the branch's changes touch (step 4); every
#              other check runs as before, the script cases (step 6) in full
#              whatever changed: a branch that changes only an evals/ selects
#              few suites or none, and its cases still run. Used by the
#              verification map, never by CI. See "Selecting suites" below.
#   --list     With --changed: print the selected suites, costliest first, and
#              the reason for the selection, then the script cases step 6
#              would run, one `script case: <skill> <id> <name>` line each,
#              then exit 0 without running any check.
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
#   - any other path outside skills/<skill>/: every suite;
#   - a path under a subdirectory of scripts/ (testdata, test libraries):
#     every suite;
#   - scripts/<name>_test.sh: that suite;
#   - scripts/<file> named on a `shared` row of check-skill.tsv, sourced by
#     two or more of the skill's files, or deleted: every suite;
#   - any other scripts/<file>: its own <stem>_test.sh, and every unit suite
#     (not *_engine_test.sh) that names the file or one of its callers, the
#     skill's other scripts/*.sh and *.jq files that name it, shared ones
#     excepted. Engine suites are taken only when no unit suite names any of
#     them, and when none does either, every suite runs;
#   - anything else (Markdown, templates, check-skill.tsv itself): every
#     suite.
#
# check-skill.tsv sits at skills/<skill>/check-skill.tsv, tab-separated, with
# `#` comments, and has two kinds of row:
#   shared <file under scripts/>   a change to it runs every suite
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
#   130, 143 - stopped by INT or TERM; the suites it had started are stopped
#              too

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHAPE_CHECK="$SCRIPT_DIR/lib/check-evals-shape.py"
# The tree's own script-case runner, relative to the root (step 6).
CASE_RUNNER="scripts/lib/script-cases.py"
ROOT="${CHECK_SKILL_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

usage() {
    echo "usage: scripts/check-skill.sh [--changed [--list]] <skill>" >&2
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
[ "$LIST" = 0 ] || [ "$CHANGED" = 1 ] || usage
SKILL="$1"

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
trap 'rm -rf "$LOG" "$RUNS"' EXIT
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
trap 'stop_suites; exit 143' TERM
trap 'stop_suites; exit 130' INT

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
# worth having; CI runs every suite.
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

# select_suites: sets SELECTED (suite paths, newline-separated, possibly with
# repeats) or ALL_REASON, which means every suite runs.
SELECTED=""
ALL_REASON=""
READERS=""
READERS_DONE=""
select_suites() {
    local paths p name rows sourced shared names hits units engines s
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
    rows=$(map_rows shared | cut -f1)
    sourced=$(sourced_by_several)
    shared=$(printf '%s\n%s\n' "$rows" "$sourced" | cut -f1 | sed '/^$/d')
    while IFS= read -r p; do
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
            "$SKILL_DIR"/scripts/*)
                name=${p#"$SKILL_DIR"/scripts/}
                if [ ! -f "$p" ]; then
                    ALL_REASON="$p is deleted"; return
                fi
                if in_list "$name" "$rows"; then
                    ALL_REASON="$p is shared (check-skill.tsv)"; return
                fi
                if in_list "$name" "$shared"; then
                    ALL_REASON="$p is sourced by $(printf '%s\n' "$sourced" | awk -F'\t' -v n="$name" '$1 == n { print $2 }') files"
                    return
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

echo "check-skill: $SKILL_DIR"

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
        sleep 0.2
    done
    # The .rc file appears whole (written, then renamed), so a reader never
    # sees a suite as finished before its status is there.
    # A failed suite also records the load as it ended, which a failure under
    # load is filed with.
    ( bash "${suites[$i]}" </dev/null >"$RUNS/$i.log" 2>&1
      rc=$?
      [ "$rc" = 0 ] || load1 > "$RUNS/$i.load"
      echo "$rc" > "$RUNS/$i.rc.tmp" && mv "$RUNS/$i.rc.tmp" "$RUNS/$i.rc" ) &
done
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
