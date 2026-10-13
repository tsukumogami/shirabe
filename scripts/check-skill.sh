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
#      once, reporting each in the order a serial run would;
#   5. runs scripts/lib/check-evals-shape.py on evals/evals.json (a skill whose
#      SKILL.md declares disable-model-invocation: true may have none).
#
# Every check runs even after one fails. Each failure is reported with the
# file it concerns, and the run ends with the list of failures.
#
# Usage: scripts/check-skill.sh <skill>
#   Run from anywhere; paths resolve against the repository root.
#   <skill> is the directory name under skills/, matching ^[a-z0-9][a-z0-9-]*$.
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
#
# Exit codes:
#   0 - every check passed
#   1 - at least one check failed; each is listed
#   2 - usage error, an unknown skill, or a required tool is missing
#   130, 143 - stopped by INT or TERM; the suites it had started are stopped
#              too

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHAPE_CHECK="$SCRIPT_DIR/lib/check-evals-shape.py"
ROOT="${CHECK_SKILL_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

usage() {
    echo "usage: scripts/check-skill.sh <skill>" >&2
    exit 2
}

[ $# -eq 1 ] || usage
SKILL="$1"

if ! printf '%s\n' "$SKILL" | grep -Eq '^[a-z0-9][a-z0-9-]*$' \
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

cd "$ROOT" || { echo "check-skill: cannot enter $ROOT" >&2; exit 2; }
SKILL_DIR="skills/$SKILL"
if [ ! -d "$SKILL_DIR" ]; then
    echo "check-skill: no such skill: $SKILL_DIR" >&2
    exit 2
fi

JOBS="${CHECK_SKILL_JOBS:-4}"
if ! printf '%s\n' "$JOBS" | grep -Eq '^[1-9][0-9]?$' \
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
# suite, so the suite is signalled first, then the subshell.
stop_suites() {
    local p
    for p in $(jobs -p); do
        pkill -TERM -P "$p" 2>/dev/null
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
# Results print in the glob's order, each as soon as it and every suite before
# it are done, so the output reads as it did when the suites ran one after
# another.
suites=()
for t in "$SKILL_DIR"/scripts/*_test.sh; do
    [ -f "$t" ] && suites+=("$t")
done
# done_count: suites finished so far (each leaves <i>.rc when it ends).
done_count() {
    find "$RUNS" -name '*.rc' | wc -l | tr -d ' '
}
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
i=0
while [ "$i" -lt "${#suites[@]}" ]; do
    while [ $((i - $(done_count))) -ge "$JOBS" ]; do
        report_ready
        sleep 0.2
    done
    # The .rc file appears whole (written, then renamed), so a reader never
    # sees a suite as finished before its status is there.
    ( bash "${suites[$i]}" </dev/null >"$RUNS/$i.log" 2>&1
      echo $? > "$RUNS/$i.rc.tmp" && mv "$RUNS/$i.rc.tmp" "$RUNS/$i.rc" ) &
    i=$((i + 1))
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

if [ -n "$FAILURES" ]; then
    echo ""
    echo "check-skill: $SKILL failed:$FAILURES"
    exit 1
fi

echo ""
echo "check-skill: $SKILL passed"
exit 0
