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
#   1. checks shirabe, koto, python3 and git are on PATH, naming each one that
#      is missing (exit 2);
#   2. runs `shirabe validate` once over the skill's Markdown outside evals/
#      and koto-templates/;
#   3. runs `koto template compile` on each koto-templates/*.md that is not a
#      *.mermaid.md;
#   4. runs each scripts/*_test.sh with `bash`, from the repository root, the
#      way the CI workflows invoke them, up to CHECK_SKILL_JOBS of them at
#      once, the costliest first, reporting each in the order a serial run
#      would;
#   5. runs scripts/lib/check-evals-shape.py on evals/evals.json (a skill whose
#      SKILL.md declares disable-model-invocation: true may have none);
#   6. runs scripts/check-pipe-readers.sh over the skill's directory, which
#      refuses a printf, echo or cat piped into grep -q or head.
#
# Every check runs even after one fails. Each failure is reported with the
# file it concerns, and the run ends with the list of failures.
#
# Usage: scripts/check-skill.sh [--changed [--list]] <skill>
#   Run from anywhere; paths resolve against the repository root.
#   <skill> is the directory name under skills/, matching ^[a-z0-9][a-z0-9-]*$.
#   --changed  Run only the suites the branch's changes touch (step 4); every
#              other check runs as before. Used by the verification map, never
#              by CI. See "Selecting suites" below.
#   --list     With --changed: print the selected suites, costliest first, and
#              the reason for the selection, then exit 0 without running any
#              check.
#
# Selecting suites (--changed). The changed paths are `git diff --name-only
# --no-renames <merge-base>` plus untracked files, where the merge-base is
# HEAD's with the default branch (origin/HEAD's target, else origin/main,
# else main), as the verification gate computes it. Selection is opt-in: a
# skill with no check-skill.tsv runs every suite. Otherwise each changed path
# is classified, and any path that selects every suite settles the run:
#   - nothing changed, or no merge-base: every suite;
#   - a path outside skills/<skill>/: every suite;
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
#                      from this script's own checkout. No extension file or
#                      workflow sets it.
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
for tool in shirabe koto python3 git; do
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
# script must not leave them running. Each job is a subshell waiting on its
# suite, so the suite's own children are signalled first (a suite waiting on
# them would otherwise leave them behind), then the suite, then the subshell.
stop_suites() {
    local p k
    for p in $(jobs -p); do
        for k in $(pgrep -P "$p"); do
            pkill -TERM -P "$k" 2>/dev/null
            kill -TERM "$k" 2>/dev/null
        done
        kill -TERM "$p" 2>/dev/null
    done
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

# select_suites: sets SELECTED (suite paths, newline-separated, possibly with
# repeats) or ALL_REASON, which means every suite runs.
SELECTED=""
ALL_REASON=""
select_suites() {
    local paths p name rows sourced shared names hits units engines s
    if [ ! -f "$MAP" ]; then
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
    exit 0
fi

echo "check-skill: $SKILL_DIR"

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
elif shirabe validate "${md_files[@]}" >"$LOG" 2>&1; then
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
            show_log "$RUNS/$NEXT.log"
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
    ( bash "${suites[$i]}" </dev/null >"$RUNS/$i.log" 2>&1
      echo $? > "$RUNS/$i.rc.tmp" && mv "$RUNS/$i.rc.tmp" "$RUNS/$i.rc" ) &
done
wait
report_ready
# A suite with no status after every job has ended (its wrapper killed before
# it could write one) is a failure, never a silent gap in the report.
while [ "$NEXT" -lt "${#suites[@]}" ]; do
    [ -f "$RUNS/$NEXT.log" ] && show_log "$RUNS/$NEXT.log"
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

# 6. No shell value piped into a reader that stops early (grep -q, head):
#    under pipefail the writer can be cut off and a match read as no match.
if bash "$SCRIPT_DIR/check-pipe-readers.sh" "$SKILL_DIR" >"$LOG" 2>&1; then
    echo "ok: pipe readers ($SKILL_DIR)"
else
    show_log
    fail "pipe readers: $SKILL_DIR (scripts/check-pipe-readers.sh)"
fi

if [ -n "$FAILURES" ]; then
    echo ""
    echo "check-skill: $SKILL failed:$FAILURES"
    exit 1
fi

echo ""
echo "check-skill: $SKILL passed"
exit 0
