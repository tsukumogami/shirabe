#!/usr/bin/env bash
# verification-hosted-coverage_test.sh -- does each hosted job a verification
# map row declares run every suite that row can select?
#
# A row's `hosted` declaration (skills/work-on/references/verification-map.md)
# says which hosted CI job runs the row's suites. The map can't prove that
# claim, so this suite does, for shirabe's committed map. For each row that
# declares hosted jobs, and each declared entry:
#
#   1. The declaration. `runs` is exactly `check-skill {skill}`, the full
#      check with no other flag; the workflow file exists; it has the job the
#      declared name points at (`skill-gate` for `skill-gate (ubuntu-latest)`),
#      with no `name:` of its own and a matrix of `os` alone whose fromJSON(...)
#      expression names the leg, so the name GitHub reports is the declared
#      one; and that job has a step guarded by `runner.os == 'Linux'` that runs
#      `bash scripts/skill-gate.sh`.
#   2. The trigger. The workflow's `pull_request:` paths list (not `push:`)
#      holds every path glob of every map entry that selects the row, so a
#      change that selects the row never has the job skipped by a path filter.
#   3. The selection. A throwaway repository holds a copy of the real
#      scripts/skill-gate.sh, the real map with every command's run replaced
#      by a stub, and one branch per fixture diff. For each diff the loader's
#      `run-verification.sh --start` writes run.json, whose invocations of the
#      row name the skills it selects, and `skill-gate.sh --list`, with
#      SKILL_GATE_BASE at the base, prints the job's plan. Every selected
#      skill has its plan line, the declared `runs` with {skill} replaced. The
#      one gap allowed is a skill the diff deletes: the row selects it and the
#      plan can't, and the gap is accepted only because check-skill.sh refuses
#      a skill missing at HEAD with exit 2, a failed check and never a timed-out
#      one, which this suite asserts.
#   4. The plan line runs the full check. The copied gate, run against a
#      recording stand-in check-skill.sh, passes each planned skill as the one
#      argument, with no flag.
#   5. The suites. For each diff and each selected skill, every suite
#      `check-skill.sh --changed --list <skill>` prints on the real tree, with
#      CHECK_SKILL_CHANGED set to the diff's paths, is in the skill's full set,
#      `check-skill.sh --list <skill>` without --changed. coordinate's full set
#      is every coordinate suite on disk.
#
# Each check is a function, and each has a negative case: an altered copy (a
# job the workflow doesn't have, `skills/**` dropped from the pull_request
# paths, a plan missing one skill's line, a coordinate set missing one suite, a
# `runs` carrying --changed, a gate passing --changed) must fail it.
#
# check-skill.sh needs koto and python3 even for --list, so the cases that
# call it (5, and the exit-2 assertion in 3) skip, saying so, where koto is
# missing; the macOS floor leg has none.
#
# Usage: verification-hosted-coverage_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.
#
# bash 3.2 floor: no associative arrays, no mapfile.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
for tool in git jq awk; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) \
    || { echo "not inside a git working tree" >&2; exit 2; }

MAP="$ROOT/.claude/shirabe-extensions/verification-map.json"
START="$SCRIPT_DIR/run-verification.sh"
GATE="$ROOT/scripts/skill-gate.sh"
CHECK_SKILL="$ROOT/scripts/check-skill.sh"
for f in "$MAP" "$START" "$GATE" "$CHECK_SKILL"; do
    [ -r "$f" ] || { echo "$f is not readable" >&2; exit 2; }
done

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf 'SKIP: %s\n' "$*"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/hosted-coverage-test.XXXXXX") || exit 2
WORKDIR=$(cd "$WORKDIR" && pwd -P) || exit 2
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
ktg_on_exit cleanup

export XDG_STATE_HOME="$WORKDIR/state"
export GIT_CONFIG_NOSYSTEM=1

# check-skill.sh refuses to run without koto, python3 and git.
CS_MISSING=""
for tool in koto python3; do
    command -v "$tool" >/dev/null 2>&1 || CS_MISSING="$CS_MISSING $tool"
done

# --- the checks ---------------------------------------------------------------------
#
# Each prints why it failed and returns 1, or returns 0 silently.

# runs_ok <runs>: the plan line is the full check, `check-skill {skill}`, with
# nothing else on it.
runs_ok() {
    [ "$1" = "check-skill {skill}" ] && return 0
    echo "runs is [$1], not [check-skill {skill}]: the plan line must be the full check with no other flag"
    return 1
}

# job_block <workflow> <job id>: the lines of that job under `jobs:`.
job_block() {
    awk -v job="$2" '
        /^[^ #]/ { injobs = ($0 ~ /^jobs:/); cur = ""; next }
        injobs && /^  [A-Za-z0-9_-]+:/ { cur = $1; sub(/:.*/, "", cur); next }
        injobs && cur == job { print }
    ' "$1"
}

# job_ok <workflow> <declared job name>: the workflow has the job the name
# points at, GitHub reports it under that name, and its Linux leg runs the
# gate.
job_ok() {
    local wf="$1" name="$2" id leg block keys os_line
    [ -f "$wf" ] || { echo "the workflow $wf does not exist"; return 1; }
    case "$name" in
        *" ("*")") id=${name%% (*}; leg=${name#* (}; leg=${leg%)} ;;
        *) echo "job [$name] is not <job> (<matrix leg>)"; return 1 ;;
    esac
    case "$id$leg" in
        *[!A-Za-z0-9._-]*) echo "job [$name] is not <job> (<matrix leg>)"; return 1 ;;
    esac
    block=$(job_block "$wf" "$id")
    [ -n "$block" ] || { echo "$wf has no job $id"; return 1; }
    if grep -q '^    name:' <<<"$block"; then
        echo "job $id sets its own name:, so GitHub doesn't report it as [$name]"; return 1
    fi
    keys=$(awk '
        /^      matrix:/ { m = 1; next }
        m && /^        [A-Za-z0-9_-]+:/ { k = $1; sub(/:.*/, "", k); print k; next }
        m && /^ *#/ { next }
        m && /^         / { next }
        m { m = 0 }' <<<"$block")
    [ "$keys" = os ] || { echo "job $id's matrix keys are [$keys], not os alone, so its reported name isn't $id (<os>)"; return 1; }
    os_line=$(grep -E '^        os: .*fromJSON\(' <<<"$block")
    case "$os_line" in
        *"\"$leg\""*) ;;
        *) echo "job $id's matrix.os expression doesn't name \"$leg\""; return 1 ;;
    esac
    case "$leg" in
        ubuntu-*) ;;
        *) echo "leg $leg is not a Linux leg, the one whose step runs the gate"; return 1 ;;
    esac
    if ! printf '%s\n' "$block" | awk -v q="'" '
            function settle() { if (linux && gate) found = 1; linux = 0; gate = 0 }
            /^      - / { settle() }
            $0 ~ ("^ +if: runner\\.os == " q "Linux" q "[ ]*$") { linux = 1 }
            /^ +run: bash scripts\/skill-gate\.sh[ ]*$/ { gate = 1 }
            END { settle(); exit !found }'; then
        echo "job $id has no step guarded by runner.os == 'Linux' that runs bash scripts/skill-gate.sh"; return 1
    fi
    return 0
}

# pr_paths <workflow>: the pull_request: paths list, one glob per line.
pr_paths() {
    awk -v q="'" '
        /^[^ #]/ { top = $0; inpr = 0; inpaths = 0; next }
        top ~ /^on:/ && /^  [A-Za-z_]+:/ { inpr = ($0 ~ /^  pull_request:/); inpaths = 0; next }
        inpr && /^    [A-Za-z_-]+:/ { inpaths = ($0 ~ /^    paths:/); next }
        inpr && inpaths && /^      - / {
            v = $0; sub(/^      - /, "", v); sub(/[ ]+#.*$/, "", v)
            gsub("^" q "|" q "$", "", v); gsub(/^"|"$/, "", v); print v }
    ' "$1"
}

# paths_ok <workflow> <row id>: every glob of every map entry that selects the
# row is on the workflow's pull_request: paths list (or the list has `**`).
paths_ok() {
    local list globs g missing=""
    list=$(pr_paths "$1")
    [ -n "$list" ] || { echo "$1 has no pull_request: paths list"; return 1; }
    globs=$(jq -r --arg id "$2" '.entries[] | select(.commands | index([$id])) | .paths[]' "$MAP")
    [ -n "$globs" ] || { echo "no map entry selects $2"; return 1; }
    # Read line by line: a glob in an unquoted word list would be expanded.
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        grep -Fxq -- "$g" <<<"$list" && continue
        grep -Fxq -- '**' <<<"$list" && continue
        missing="$missing $g"
    done <<EOF
$globs
EOF
    [ -z "$missing" ] && return 0
    echo "the pull_request: paths list of $1 lacks:$missing"
    return 1
}

# plan_covers <selected skills> <plan> <runs> <fixture>: every selected skill
# has its plan line, except a skill missing at the fixture's HEAD, which is
# added to GAPS.
GAPS=""
plan_covers() {
    local s line missing=""
    GAPS=""
    for s in $1; do
        line=$(sed "s/[{]skill[}]/$s/g" <<<"$3")
        grep -Fxq -- "$line" <<<"$2" && continue
        if [ "$(git -C "$4" cat-file -t "HEAD:skills/$s" 2>/dev/null)" != tree ]; then
            GAPS="$GAPS $s"
            continue
        fi
        missing="$missing [$line]"
    done
    [ -z "$missing" ] && return 0
    echo "the plan lacks:$missing"
    return 1
}

# suites_covered <selected suites> <full set>: every selected suite is in the
# full set; names each one that isn't.
suites_covered() {
    local s missing=""
    for s in $1; do
        grep -Fxq -- "$s" <<<"$2" || missing="$missing $s"
    done
    [ -z "$missing" ] && return 0
    echo "not in the full set:$missing"
    return 1
}

# suite_lines <skill>: the suite lines of check-skill.sh output on stdin.
suite_lines() {
    grep -E "^skills/$1/scripts/[^/]+_test\\.sh\$" | LC_ALL=C sort
}

# expect_ok <label> <command...>: the check passes.
expect_ok() {
    local label="$1" msg
    shift
    if msg=$("$@"); then pass "$label"; else fail "$label: $msg"; fi
}

# expect_refused <label> <want fragment> <command...>: the check fails, saying
# <fragment>.
expect_refused() {
    local label="$1" want="$2" msg
    shift 2
    if msg=$("$@"); then
        fail "$label: the check passed"
    else
        case "$msg" in
            *"$want"*) pass "$label" ;;
            *) fail "$label: refused, but said [$msg], not [$want]" ;;
        esac
    fi
}

# --- 1 and 2: the declaration and the trigger -----------------------------------------

ROWS=$(jq -r '.commands | to_entries[] | select(.value | has("hosted")) | .key' "$MAP")
if [ -n "$ROWS" ]; then
    pass "the committed map declares hosted jobs on: $(printf '%s ' $ROWS)"
else
    fail "the committed map declares no hosted job on any row"
fi

for row in $ROWS; do
    n=$(jq -r --arg id "$row" '.commands[$id].hosted | length' "$MAP")
    i=0
    while [ "$i" -lt "$n" ]; do
        wf=$(jq -r --arg id "$row" --argjson i "$i" '.commands[$id].hosted[$i].workflow' "$MAP")
        job=$(jq -r --arg id "$row" --argjson i "$i" '.commands[$id].hosted[$i].job' "$MAP")
        runs=$(jq -r --arg id "$row" --argjson i "$i" '.commands[$id].hosted[$i].runs' "$MAP")
        expect_ok "$row: runs [$runs] is the full check with no other flag" runs_ok "$runs"
        expect_ok "$row: $wf has job [$job], reported under that name, whose Linux leg runs skill-gate.sh" \
            job_ok "$ROOT/$wf" "$job"
        expect_ok "$row: $wf's pull_request: paths cover every glob that selects the row" \
            paths_ok "$ROOT/$wf" "$row"
        i=$((i + 1))
    done
done

WF="$ROOT/.github/workflows/check-skill-gate.yml"
expect_refused "negative: a declaration naming a job the workflow doesn't have fails" \
    "has no job" job_ok "$WF" "skill-gat (ubuntu-latest)"
expect_refused "negative: a declaration naming a leg the matrix doesn't have fails" \
    "doesn't name" job_ok "$WF" "skill-gate (ubuntu-20.04)"
expect_refused "negative: a declaration naming the macOS leg fails" \
    "not a Linux leg" job_ok "$WF" "skill-gate (macos-latest)"
expect_refused "negative: a runs carrying --changed fails" \
    "no other flag" runs_ok "check-skill --changed {skill}"

# The workflow with skills/** dropped from pull_request: only.
WF_COPY="$WORKDIR/check-skill-gate.yml"
awk -v q="'" '
    /^[^ #]/ { top = $0; inpr = 0 }
    top ~ /^on:/ && /^  [A-Za-z_]+:/ { inpr = ($0 ~ /^  pull_request:/) }
    inpr && $0 == ("      - " q "skills/**" q) { next }
    { print }' "$WF" > "$WF_COPY"
copy_paths=$(pr_paths "$WF_COPY")
if grep -Fxq 'skills/*/check-skill.tsv' <<<"$copy_paths" \
        && ! grep -Fxq 'skills/**' <<<"$copy_paths" \
        && grep -Fq "'skills/**'" "$WF_COPY"; then
    expect_refused "negative: pull_request: paths without skills/** fail, though skills/*/check-skill.tsv stays and push: keeps it" \
        "lacks: skills/**" paths_ok "$WF_COPY" check-skill
else
    fail "negative: could not build the workflow copy without skills/** on pull_request:"
fi

# --- 3 and 4: the selection and the plan, over fixture diffs ----------------------------

ROW=check-skill
RUNS=$(jq -r --arg id "$ROW" '.commands[$id].hosted[0].runs // empty' "$MAP")

FIX="$WORKDIR/fixture"
mkdir -p "$FIX/bin" "$FIX/scripts/lib" "$FIX/.claude/shirabe-extensions" || exit 2
g() { git -C "$FIX" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main . || exit 2
jq '.commands |= map_values(.run = ["bin/stub.sh"])' "$MAP" > "$FIX/.claude/shirabe-extensions/verification-map.json" || exit 2
printf '#!/bin/sh\nexit 0\n' > "$FIX/bin/stub.sh"
chmod +x "$FIX/bin/stub.sh"
cp "$GATE" "$FIX/scripts/skill-gate.sh" || exit 2
# A recording stand-in for check-skill.sh: the gate's arguments, one line per
# call.
cat > "$FIX/scripts/check-skill.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$GATE_REC"
EOF
printf 'import sys\nsys.exit(0)\n' > "$FIX/scripts/lib/script-cases.py"

# The fixture diffs: <label>|<paths>, `-` before a path deleting it.
DIFFS="a change under one skill's scripts/|skills/plan/scripts/plan-to-tasks.sh
changes under two skills|skills/plan/scripts/plan-to-tasks.sh skills/work-on/scripts/run-verification.sh
a nested scripts/testdata/ path|skills/work-on/scripts/testdata/fixture.txt
a root scripts/ change with a skill change|scripts/review-packet.sh skills/plan/SKILL.md
a change that selects all of coordinate's suites|skills/coordinate/check-skill.tsv
a deleted skill|-skills/retired/SKILL.md"
ALL_PATHS=$(printf '%s\n' "$DIFFS" | sed 's/^[^|]*|//' | tr ' ' '\n' | sed 's/^-//' | LC_ALL=C sort -u)
for p in $ALL_PATHS; do
    mkdir -p "$FIX/$(dirname "$p")"
    echo base > "$FIX/$p"
done
g add -A && g commit -q -m base || exit 2
BASE=$(g rev-parse HEAD) || exit 2

# wait_result <session>: until the supervisor has written the result, for at
# most 30s.
wait_result() {
    local res k=0
    res=$(cd "$FIX" && "$START" --locate --session "$1" 2>/dev/null | sed -n 3p)
    while [ -n "$res" ] && [ ! -f "$res" ] && [ "$k" -lt 150 ]; do
        sleep 0.2
        k=$((k + 1))
    done
}

FULL_CACHE="$WORKDIR/full"
mkdir -p "$FULL_CACHE"
# full_set <skill>: check-skill.sh --list <skill> on the real tree, cached.
full_set() {
    if [ ! -f "$FULL_CACHE/$1" ]; then
        (cd "$WORKDIR" && bash "$CHECK_SKILL" --list "$1" 2>/dev/null) | suite_lines "$1" > "$FULL_CACHE/$1"
    fi
    cat "$FULL_CACHE/$1"
}

d=0
# The diffs are read on fd 3, so nothing the loop runs can read them.
while IFS='|' read -r label paths <&3; do
    [ -n "$label" ] || continue
    d=$((d + 1))
    g checkout -q -B "d$d" "$BASE" || { fail "$label: could not branch"; continue; }
    changed=""
    for p in $paths; do
        case "$p" in
            -*) g rm -q -- "${p#-}" ;;
            *) echo "change $d" >> "$FIX/$p" ;;
        esac
        changed="$changed${p#-}
"
    done
    g add -A && g commit -q -m "diff $d" || { fail "$label: could not commit"; continue; }

    # The row's selection, from the loader.
    if ! (cd "$FIX" && "$START" --start --session "cov-$d" >"$WORKDIR/start.out" 2>&1); then
        fail "$label: --start failed: $(cat "$WORKDIR/start.out")"; continue
    fi
    wait_result "cov-$d"
    run_json="$(dirname "$(cd "$FIX" && "$START" --locate --session "cov-$d" | sed -n 3p)")/run.json"
    selected=$(jq -r --arg id "$ROW" '.invocations[] | select(.id == $id) | .argv[-1]' "$run_json" 2>/dev/null)
    if [ -z "$selected" ]; then
        fail "$label: the loader selected no $ROW invocation: $(head -c 400 "$run_json" 2>&1)"; continue
    fi
    jq -e --arg id "$ROW" --argjson h "$(jq -c --arg id "$ROW" '.commands[$id].hosted' "$MAP")" \
        '[.invocations[] | select(.id == $id) | .hosted] | all(. == $h)' "$run_json" >/dev/null 2>&1 \
        && pass "$label: each $ROW invocation carries the row's declaration" \
        || fail "$label: the $ROW invocations don't carry the row's declaration"

    # The job's plan for the same base and head.
    plan=$(cd "$WORKDIR" && SKILL_GATE_BASE="$BASE" bash "$FIX/scripts/skill-gate.sh" --list 2>"$WORKDIR/gate.err")
    gate_rc=$?
    if [ "$gate_rc" -ne 0 ]; then
        fail "$label: skill-gate.sh --list exited $gate_rc: $(cat "$WORKDIR/gate.err")"; continue
    fi
    sel_words=$(printf '%s ' $selected)
    if msg=$(plan_covers "$selected" "$plan" "$RUNS" "$FIX"); then
        pass "$label: every skill the row selects ($sel_words) has its plan line, a skill missing at HEAD excepted"
    else
        fail "$label: selected $sel_words: $msg"
    fi
    # Again outside a command substitution, for the gaps it records.
    plan_covers "$selected" "$plan" "$RUNS" "$FIX" >/dev/null
    gaps=$GAPS

    case "$label" in
        "a deleted skill")
            if [ "$gaps" = " retired" ]; then
                pass "$label: the row selects the deleted skill and the plan doesn't, the one gap"
            else
                fail "$label: the gap is [$gaps], not [ retired]"
            fi
            if [ -n "$CS_MISSING" ]; then
                skip "$label: check-skill.sh's exit 2 for a skill missing at HEAD (needs$CS_MISSING, not on PATH)"
            else
                out=$(cd "$WORKDIR" && CHECK_SKILL_ROOT="$FIX" bash "$CHECK_SKILL" --changed retired 2>&1)
                rc=$?
                case "$rc:$out" in
                    "2:"*"no such skill"*) pass "$label: check-skill.sh refuses the deleted skill with exit 2, a failed check, never a timeout" ;;
                    *) fail "$label: check-skill.sh on the deleted skill exited $rc: $out" ;;
                esac
            fi ;;
        *)
            [ -z "$gaps" ] && pass "$label: no gap" || fail "$label: a gap where no skill was deleted:$gaps" ;;
    esac

    if [ "$label" = "changes under two skills" ]; then
        drop=$(grep -Fx 'check-skill plan' <<<"$plan")
        short=$(grep -Fxv 'check-skill plan' <<<"$plan")
        if [ -n "$drop" ]; then
            expect_refused "negative: a plan with one selected skill's line removed fails" \
                "[check-skill plan]" plan_covers "$selected" "$short" "$RUNS" "$FIX"
        else
            fail "negative: the two-skill plan has no check-skill plan line to remove: [$plan]"
        fi
        expect_refused "negative: a runs carrying --changed matches no plan line" \
            "the plan lacks" plan_covers "$selected" "$plan" "check-skill --changed {skill}" "$FIX"

        # 4: the gate runs each planned skill as the one argument.
        : > "$WORKDIR/gate.rec"
        (cd "$WORKDIR" && GATE_REC="$WORKDIR/gate.rec" SKILL_GATE_BASE="$BASE" \
            bash "$FIX/scripts/skill-gate.sh" >/dev/null 2>&1)
        want=$(printf '%s\n' "$plan" | sed -n 's/^check-skill //p' | LC_ALL=C sort)
        got=$(LC_ALL=C sort "$WORKDIR/gate.rec")
        if [ -n "$want" ] && [ "$got" = "$want" ]; then
            pass "the gate runs each plan line as scripts/check-skill.sh <skill>, with no other flag"
        else
            fail "the gate ran check-skill.sh with [$(tr '\n' ';' < "$WORKDIR/gate.rec")], want [$(printf '%s' "$want" | tr '\n' ';')]"
        fi
        sed 's|bash scripts/check-skill.sh "|bash scripts/check-skill.sh --changed "|' "$GATE" > "$FIX/scripts/skill-gate-altered.sh"
        : > "$WORKDIR/gate.rec"
        (cd "$WORKDIR" && GATE_REC="$WORKDIR/gate.rec" SKILL_GATE_BASE="$BASE" \
            bash "$FIX/scripts/skill-gate-altered.sh" >/dev/null 2>&1)
        got=$(LC_ALL=C sort "$WORKDIR/gate.rec")
        if ! grep -Fq -- '--changed "' "$FIX/scripts/skill-gate-altered.sh"; then
            fail "negative: could not build a gate copy that passes --changed"
        elif [ "$got" != "$want" ]; then
            pass "negative: a gate whose plan line runs check-skill.sh --changed fails the check"
        else
            fail "negative: a gate passing --changed still matched [$got]"
        fi
        rm -f "$FIX/scripts/skill-gate-altered.sh"
    fi

    # 5: every suite the row's command can select is in the skill's full set.
    if [ -n "$CS_MISSING" ]; then
        skip "$label: the suite sets (check-skill.sh needs$CS_MISSING, not on PATH)"
        continue
    fi
    for s in $selected; do
        case " $gaps " in *" $s "*) continue ;; esac
        out=$(cd "$WORKDIR" && CHECK_SKILL_CHANGED="$changed" bash "$CHECK_SKILL" --changed --list "$s" 2>&1)
        rc=$?
        if [ "$rc" -ne 0 ]; then
            fail "$label: check-skill.sh --changed --list $s exited $rc: $(printf '%s' "$out" | tail -n 5)"; continue
        fi
        sel_suites=$(printf '%s\n' "$out" | suite_lines "$s")
        full=$(full_set "$s")
        if [ -z "$full" ]; then
            fail "$label: check-skill.sh --list $s listed no suite"; continue
        fi
        if msg=$(suites_covered "$sel_suites" "$full"); then
            pass "$label: the $(printf '%s\n' "$sel_suites" | grep -c .) suites --changed selects for $s are all in its full set of $(printf '%s\n' "$full" | grep -c .)"
        else
            fail "$label: $s: $msg"
        fi
        if [ "$s" = coordinate ] && [ "$label" = "a change that selects all of coordinate's suites" ]; then
            case "$out" in
                *"runs every suite"*) ;;
                *) fail "$label: --changed doesn't run every coordinate suite: $(printf '%s\n' "$out" | grep '^check-skill: --changed')" ;;
            esac
            if [ "$sel_suites" = "$full" ]; then
                pass "$label: the selection is coordinate's whole set"
            else
                fail "$label: the selection is not coordinate's whole set"
            fi
            COORD_SELECTED=$sel_suites
        fi
    done
done 3<<EOF
$DIFFS
EOF

if [ -z "$CS_MISSING" ]; then
    full=$(full_set coordinate)
    on_disk=$(cd "$ROOT" && ls skills/coordinate/scripts/*_test.sh | LC_ALL=C sort)
    if [ -n "$full" ] && [ "$full" = "$on_disk" ]; then
        pass "coordinate's full set is every coordinate suite on disk ($(printf '%s\n' "$full" | grep -c .))"
    else
        fail "coordinate's full set differs from the suites on disk"
    fi
    dropped=$(printf '%s\n' "$full" | sed -n 1p)
    short=$(printf '%s\n' "$full" | sed 1d)
    expect_refused "negative: a coordinate set missing one suite fails, naming it" \
        "$dropped" suites_covered "${COORD_SELECTED:-$full}" "$short"
else
    skip "coordinate's full set against the suites on disk (check-skill.sh needs$CS_MISSING, not on PATH)"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
