#!/usr/bin/env bash
#
# step-detail-check_test.sh - tests for step-detail-check.sh and the
# plan_validation gate that runs it
#
# Script cases (git, jq and a plan/v2-aware shirabe):
#   - on the FC22-valid fixtures in testdata/ (single-pr and multi-pr), a
#     detailed step exits 0 and an outline step exits 1 with the refusal
#     line, and the script agrees with `shirabe plan outlines` on every step
#   - a malformed step is refused, naming the rule, before the plan is read
#   - a plan path that is missing, not a regular file, or outside the
#     repository (absolute, `..`, a symlink out) is refused
#   - a file that is not plan/v1 or plan/v2, a missing shirabe, and a shirabe
#     that cannot read the plan are refused saying so
#   - hostile step titles stay inert: no PWNED file, no title text printed
#   - the --task form the template uses, and a plan/v1 PLAN
#
# Engine cases (koto): the shipped work-on.md driven through plan_validation
# on an outline step (the gate fails with the refusal line, proceed is
# refused, exit reaches validation_exit), then the same child, rewound after
# the plan's owner commits the step's detail, passes the gate and proceeds;
# a plan/v1 task, which the gate passes without reading the plan; and a child
# initialized with exactly the vars /execute's spawn line (read from the
# compiled execute.md) puts on a plan-to-tasks.sh task, which carries PLAN_DOC
# and passes the gate, while the same task without PLAN_DOC holds with "no
# plan path given".
#
# The shirabe binary is $SHIRABE_BIN when set, otherwise a release build of
# this checkout (`cargo build --release -p shirabe`), as plan-to-tasks_test.sh
# does: an installed shirabe may predate plan/v2.
#
# Usage: bash skills/work-on/scripts/step-detail-check_test.sh
#
# Exit codes:
#   0 - every case passed (engine cases skip without koto)
#   1 - a case failed, or the shirabe binary could not be built

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
CHECK="$SCRIPT_DIR/step-detail-check.sh"
TESTDATA="$SCRIPT_DIR/testdata"
TEMPLATE="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
OUTLINE_MSG="the plan's owner details it before its work starts"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }
[ -x "$CHECK" ] || { echo "FAIL: $CHECK is missing or not executable" >&2; exit 1; }

if [ -n "${SHIRABE_BIN:-}" ] && [ -x "${SHIRABE_BIN:-}" ]; then
    echo "Using pre-set SHIRABE_BIN=$SHIRABE_BIN" >&2
else
    echo "Building shirabe release binary (cargo build --release -p shirabe)..." >&2
    if ! (cd "$REPO_ROOT" && cargo build --release -p shirabe) >&2; then
        echo "FAIL: could not build the shirabe release binary" >&2
        exit 1
    fi
    SHIRABE_BIN="$REPO_ROOT/target/release/shirabe"
fi
export SHIRABE_BIN

WORKDIR=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# A HOME of its own: git's identity for the fixture commits and koto's session
# store both live under it.
export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main

RC=0
OUT=""
ERR=""
# run <dir> <args...>: runs the check from <dir>.
run() {
    local dir="$1"
    shift
    OUT=$(cd "$dir" && "$CHECK" "$@" 2>"$WORKDIR/stderr")
    RC=$?
    ERR=$(cat "$WORKDIR/stderr")
}

# A repository of its own, so "outside the repository" has a boundary that
# does not depend on where the temporary directory sits.
REPO="$WORKDIR/repo"
OUTSIDE="$WORKDIR/outside"
mkdir -p "$REPO/docs/plans" "$OUTSIDE"
cp "$TESTDATA"/PLAN-v2-*.md "$REPO/docs/plans/"
(cd "$REPO" && git init -q . && git add -A && git commit -qm init) >/dev/null 2>&1

echo "--- detailed and outline steps"

for mode in single-pr multi-pr; do
    fx="$TESTDATA/PLAN-v2-$mode.md"
    if "$SHIRABE_BIN" validate "$fx" >"$WORKDIR/validate.out" 2>&1; then
        pass "$mode: the fixture validates clean (FC22 accepts it)"
    else
        fail "$mode: shirabe validate rejected the fixture: $(cat "$WORKDIR/validate.out")"
    fi
    for step in 1 2; do
        run "$REPO_ROOT" "skills/work-on/scripts/testdata/PLAN-v2-$mode.md" "$step"
        [ "$RC" -eq 0 ] && [ "$OUT" = "step $step is detailed" ] && [ -z "$ERR" ] \
            && pass "$mode: detailed step $step exits 0" \
            || fail "$mode: step $step: exit $RC, out [$OUT], err [$ERR]"
    done
    for step in 3 4; do
        run "$REPO_ROOT" "skills/work-on/scripts/testdata/PLAN-v2-$mode.md" "$step"
        [ "$RC" -eq 1 ] && [ "$ERR" = "step $step is an outline; $OUTLINE_MSG" ] && [ -z "$OUT" ] \
            && pass "$mode: outline step $step exits 1 with the refusal line" \
            || fail "$mode: step $step: exit $RC, out [$OUT], err [$ERR]"
    done
    # The script and the parser agree on every step.
    agree=1
    while IFS=' ' read -r n detailed; do
        [ -n "$n" ] || continue
        run "$REPO_ROOT" "$fx" "$n"
        if { [ "$detailed" = true ] && [ "$RC" -ne 0 ]; } || { [ "$detailed" = false ] && [ "$RC" -ne 1 ]; }; then
            agree=0
            fail "$mode: step $n is detailed=$detailed in the envelope, the check exited $RC"
        fi
    done <<EOF
$("$SHIRABE_BIN" plan outlines "$fx" | jq -r '.outlines[] | "\(.number) \(.detailed)"')
EOF
    [ "$agree" -eq 1 ] && pass "$mode: the check agrees with shirabe plan outlines on every step"
done

echo "--- the step argument, before the plan is read"

for bad in 0 01 1000 a "" "1;ls" "-1" "1 2"; do
    # The plan does not exist: a refusal naming the step rule shows the step
    # was checked first.
    run "$REPO" docs/plans/no-such-plan.md "$bad"
    if [ "$RC" -eq 2 ] && grep -qF 'step must match ^[1-9][0-9]{0,2}$' <<<"$ERR"; then
        pass "step [$bad] is refused naming the rule"
    else
        fail "step [$bad]: exit $RC, err [$ERR]"
    fi
done

echo "--- the plan path"

mkdir -p "$REPO/docs/plans/a-directory"
cp "$TESTDATA/PLAN-v2-single-pr.md" "$OUTSIDE/PLAN-v2-elsewhere.md"
ln -s "$OUTSIDE/PLAN-v2-elsewhere.md" "$REPO/docs/plans/PLAN-link-out.md"
ln -s PLAN-v2-single-pr.md "$REPO/docs/plans/PLAN-link-in.md"
ln -s "$OUTSIDE/missing.md" "$REPO/docs/plans/PLAN-dangling.md"

# path_refused <label> <dir> <plan> <expected message fragment>
path_refused() {
    run "$2" "$3" 1
    if [ "$RC" -eq 2 ] && grep -qF "$4" <<<"$ERR"; then
        pass "$1 is refused: $ERR"
    else
        fail "$1: exit $RC, out [$OUT], err [$ERR]"
    fi
}
path_refused "a missing plan" "$REPO" docs/plans/PLAN-missing.md "plan not found"
path_refused "an empty plan path" "$REPO" "" "no plan path given"
path_refused "a directory" "$REPO" docs/plans/a-directory "not a regular file"
path_refused "a symlink to nothing" "$REPO" docs/plans/PLAN-dangling.md "plan not found"
path_refused "an absolute path outside the repository" "$REPO" "$OUTSIDE/PLAN-v2-elsewhere.md" "outside the repository"
path_refused "a .. path out of the repository" "$REPO" ../outside/PLAN-v2-elsewhere.md "outside the repository"
path_refused "a symlink out of the repository" "$REPO" docs/plans/PLAN-link-out.md "outside the repository"
path_refused "a run outside any git repository" "$OUTSIDE" PLAN-v2-elsewhere.md "not inside a git repository"

run "$REPO" docs/plans/PLAN-link-in.md 1
[ "$RC" -eq 0 ] && pass "a symlink that stays inside the repository is followed" \
    || fail "symlink inside: exit $RC, err [$ERR]"
run "$REPO/docs" ../docs/plans/PLAN-v2-single-pr.md 3
[ "$RC" -eq 1 ] && pass "a .. path that stays inside the repository is read" \
    || fail ".. inside: exit $RC, err [$ERR]"

echo "--- what the plan is, and the tools that read it"

printf '# not a plan\n' > "$REPO/README.md"
sed 's/^schema: plan\/v2$/schema: plan\/v3/' "$TESTDATA/PLAN-v2-single-pr.md" > "$REPO/docs/plans/PLAN-v3.md"
path_refused "a file with no frontmatter" "$REPO" README.md "not a plan/v1 or plan/v2 PLAN"
path_refused "a plan/v3 file" "$REPO" docs/plans/PLAN-v3.md "not a plan/v1 or plan/v2 PLAN"

run "$REPO" docs/plans/PLAN-v2-single-pr.md 9
[ "$RC" -eq 2 ] && grep -qF "the plan has no step 9" <<<"$ERR" \
    && pass "a step the plan does not have is refused" || fail "step 9: exit $RC, err [$ERR]"

# No shirabe anywhere: a PATH holding only git and jq beside the system dirs.
TOOLS="$WORKDIR/tools"
mkdir -p "$TOOLS"
ln -s "$(command -v jq)" "$TOOLS/jq"
ln -s "$(command -v git)" "$TOOLS/git"
OUT=$(cd "$REPO" && env -u SHIRABE_BIN PATH="$TOOLS:/usr/bin:/bin" "$CHECK" docs/plans/PLAN-v2-single-pr.md 1 2>"$WORKDIR/stderr")
RC=$?
ERR=$(cat "$WORKDIR/stderr")
[ "$RC" -eq 2 ] && grep -qF "shirabe binary not found" <<<"$ERR" \
    && pass "a missing shirabe is refused saying so" || fail "no shirabe: exit $RC, err [$ERR]"

printf 'not executable\n' > "$WORKDIR/not-exec"
OUT=$(cd "$REPO" && SHIRABE_BIN="$WORKDIR/not-exec" "$CHECK" docs/plans/PLAN-v2-single-pr.md 1 2>"$WORKDIR/stderr")
RC=$?
ERR=$(cat "$WORKDIR/stderr")
[ "$RC" -eq 2 ] && grep -qF "SHIRABE_BIN is set but is not an executable file" <<<"$ERR" \
    && pass "a SHIRABE_BIN that cannot run is refused" || fail "non-executable SHIRABE_BIN: exit $RC, err [$ERR]"

# A shirabe from before plan/v2, which refuses the file the way 0.25.0 does.
cat > "$WORKDIR/old-shirabe" <<'OLD'
#!/usr/bin/env bash
echo "[plan outlines] $3 is not a PLAN document (expected 'schema: plan/v1', found 'plan/v2')" >&2
exit 2
OLD
chmod +x "$WORKDIR/old-shirabe"
OUT=$(cd "$REPO" && SHIRABE_BIN="$WORKDIR/old-shirabe" "$CHECK" docs/plans/PLAN-v2-single-pr.md 1 2>"$WORKDIR/stderr")
RC=$?
ERR=$(cat "$WORKDIR/stderr")
if [ "$RC" -eq 2 ] && grep -qF "could not read the plan" <<<"$ERR" \
    && grep -qF "docs/plans/PLAN-v2-single-pr.md is not a PLAN document" <<<"$ERR"; then
    pass "a shirabe that cannot read plan/v2 is refused, quoting what it said"
else
    fail "old shirabe: exit $RC, err [$ERR]"
fi

echo "--- hostile step titles"

HOSTILE="docs/plans/PLAN-v2-hostile.md"
if "$SHIRABE_BIN" validate "$TESTDATA/PLAN-v2-hostile.md" >"$WORKDIR/validate.out" 2>&1; then
    pass "the hostile fixture validates clean (FC22 accepts it)"
else
    fail "shirabe validate rejected the hostile fixture: $(cat "$WORKDIR/validate.out")"
fi
ESC=$(printf '\033')
for pair in 1:0 2:0 3:1 4:1; do
    step=${pair%%:*}
    want=${pair#*:}
    run "$REPO" "$HOSTILE" "$step"
    all="$OUT$ERR"
    if [ "$RC" -ne "$want" ]; then
        fail "hostile step $step: expected exit $want, got $RC, out [$OUT], err [$ERR]"
    elif case "$all" in *"$ESC"* | *PWNED* | *touch* | *--help* | *red*) true ;; *) false ;; esac; then
        fail "hostile step $step: step text reached the output: [$all]"
    else
        pass "hostile step $step exits $want and prints no step text"
    fi
done
if [ -e "$REPO/PWNED" ] || [ -e "$REPO/docs/plans/PWNED" ] || [ -e "$REPO_ROOT/PWNED" ] || [ -e "$SCRIPT_DIR/PWNED" ]; then
    fail "a PWNED file was created"
else
    pass "no PWNED file was created"
fi

echo "--- the --task form, and plan/v1"

run "$REPO" --task step-3 docs/plans/PLAN-v2-single-pr.md
[ "$RC" -eq 1 ] && [ "$ERR" = "step 3 is an outline; $OUTLINE_MSG" ] \
    && pass "--task step-3 checks step 3" || fail "--task step-3: exit $RC, err [$ERR]"
run "$REPO" --task step-1 docs/plans/PLAN-v2-multi-pr.md
[ "$RC" -eq 0 ] && pass "--task step-1 passes a detailed step" || fail "--task step-1: exit $RC, err [$ERR]"
run "$REPO" --task o-feat-some-slug docs/plans/no-such-plan.md
[ "$RC" -eq 0 ] && [ -z "$OUT$ERR" ] \
    && pass "--task with a plan/v1 task name passes without reading the plan" \
    || fail "--task plan/v1 name: exit $RC, out [$OUT], err [$ERR]"
run "$REPO" --task step-01 docs/plans/PLAN-v2-single-pr.md
[ "$RC" -eq 2 ] && grep -qF 'step must match' <<<"$ERR" \
    && pass "--task step-01 is refused naming the rule" || fail "--task step-01: exit $RC, err [$ERR]"
run "$REPO" --task step-1
[ "$RC" -eq 2 ] && grep -qF usage <<<"$ERR" \
    && pass "--task with no plan is a usage refusal" || fail "--task no plan: exit $RC, err [$ERR]"
run "$REPO" docs/plans/PLAN-v2-single-pr.md
[ "$RC" -eq 2 ] && grep -qF usage <<<"$ERR" \
    && pass "a missing step argument is a usage refusal" || fail "no step: exit $RC, err [$ERR]"

cp "$REPO_ROOT/crates/shirabe-validate/tests/fixtures/PLAN-v1-five-layer.md" "$REPO/docs/plans/PLAN-v1.md"
run "$REPO" docs/plans/PLAN-v1.md 1
[ "$RC" -eq 0 ] && [ "$OUT" = "issue 1 is detailed" ] \
    && pass "a plan/v1 issue is detailed" || fail "plan/v1 issue 1: exit $RC, out [$OUT], err [$ERR]"
run "$REPO" docs/plans/PLAN-v1.md 99
[ "$RC" -eq 2 ] && grep -qF "the plan has no issue 99" <<<"$ERR" \
    && pass "a plan/v1 issue the plan does not have is refused" || fail "plan/v1 issue 99: exit $RC, err [$ERR]"

# --- engine cases --------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- engine cases did not run"
else
    echo "--- plan_validation in the shipped template"

    # koto runs the gate with the PATH it records at init, so the shirabe this
    # suite built goes first on it.
    BIN_DIR="$WORKDIR/bin"
    mkdir -p "$BIN_DIR"
    ln -s "$SHIRABE_BIN" "$BIN_DIR/shirabe"
    ENGINE_PATH="$BIN_DIR:$PATH"

    ER="$WORKDIR/engine"
    mkdir -p "$ER/docs/plans"
    cp "$TESTDATA/PLAN-v2-single-pr.md" "$ER/docs/plans/PLAN-steps.md"
    cp "$REPO_ROOT/crates/shirabe-validate/tests/fixtures/PLAN-v1-five-layer.md" "$ER/docs/plans/PLAN-v1.md"
    (cd "$ER" && git init -q . && git add -A && git commit -qm init) >/dev/null 2>&1

    RESP=""
    STATE=""
    tick() { # tick <session> [<data>]
        if [ -n "${2:-}" ]; then
            RESP=$(cd "$ER" && PATH="$ENGINE_PATH" koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
        else
            RESP=$(cd "$ER" && PATH="$ENGINE_PATH" koto next "$1" --no-cleanup 2>/dev/null)
        fi
        STATE=$(printf '%s' "$RESP" | jq -r '.state // empty' 2>/dev/null)
    }
    # to_validation <session> <task name> <plan>: a plan-backed child, from
    # init to plan_validation, with the step's block (or a stand-in) as
    # context.md.
    to_validation() {
        (cd "$ER" && PATH="$ENGINE_PATH" koto init "$1" --template "$TEMPLATE" \
            --var ARTIFACT_PREFIX="$2" --var ISSUE_SOURCE=plan_outline \
            --var PLAN_DOC="$3" --var SHARED_BRANCH=main \
            --var PLUGIN_ROOT="$REPO_ROOT" >/dev/null 2>&1)
        tick "$1"
        [ "$STATE" = entry ] && tick "$1" '{"mode":"plan_backed","issue_source":"plan_outline"}'
        printf 'the outline item\n' | (cd "$ER" && koto context add "$1" context.md) >/dev/null 2>&1
        tick "$1" '{"status":"completed","issue_source":"plan_outline"}'
    }
    gate_message() {
        printf '%s' "$RESP" | jq -r '.blocking_conditions[]? | select(.name == "step_detail") | .failure.findings[0].message // empty' 2>/dev/null
    }

    to_validation s-outline step-3 docs/plans/PLAN-steps.md
    MSG=$(gate_message)
    if [ "$STATE" = plan_validation ] && [ "$MSG" = "step 3 is an outline; $OUTLINE_MSG" ]; then
        pass "an outline step's child holds at plan_validation with the refusal line"
    else
        fail "outline step: state [$STATE], gate message [$MSG]"
    fi
    tick s-outline '{"verdict":"proceed"}'
    [ "$STATE" = plan_validation ] && pass "proceed is refused while the step is an outline" \
        || fail "proceed on an outline step reached [$STATE]"
    tick s-outline "$(jq -cn --arg m "$MSG" '{verdict: "exit", rationale: $m}')"
    [ "$STATE" = validation_exit ] && pass "verdict exit with the refusal line reaches validation_exit" \
        || fail "exit reached [$STATE]"

    # The plan's owner details step 3 in a commit of its own; the same child,
    # run again from plan_validation, reads the plan as committed now.
    awk '
        /^A pipe into `wc-lite -` is counted the way a file is\.$/ {
            print "**Goal**: `wc-lite -` counts what arrives on standard input."
            print ""
            print "**Acceptance Criteria**:"
            print ""
            print "- [ ] `printf \"a b\" | wc-lite -` prints `2`."
            print ""
            print "**Check**: Run `printf \"a b\" | wc-lite -` and see `2`."
            print ""
            print "**Dependencies**: Step 1"
            next
        }
        { print }
    ' "$ER/docs/plans/PLAN-steps.md" > "$WORKDIR/detailed.md"
    mv "$WORKDIR/detailed.md" "$ER/docs/plans/PLAN-steps.md"
    (cd "$ER" && git commit -qam "docs(plan): detail step 3") >/dev/null 2>&1
    if "$SHIRABE_BIN" validate "$ER/docs/plans/PLAN-steps.md" >/dev/null 2>&1; then
        pass "the detailed plan validates clean"
    else
        fail "the detailed plan does not validate"
    fi
    (cd "$ER" && koto rewind s-outline) >/dev/null 2>&1
    tick s-outline
    MSG=$(gate_message)
    if [ "$STATE" = plan_validation ] && [ -z "$MSG" ]; then
        pass "after the detail commit, the same child's gate passes"
    else
        fail "after detailing: state [$STATE], gate message [$MSG]"
    fi
    tick s-outline '{"verdict":"proceed"}'
    case "$STATE" in
        setup_plan_backed | analysis) pass "after detailing, verdict proceed moves on to [$STATE]" ;;
        *) fail "after detailing, proceed reached [$STATE]" ;;
    esac

    # A plan/v1 task is never named step-<N>; the gate passes it as before.
    to_validation s-v1 o-feat-some-issue docs/plans/PLAN-v1.md
    tick s-v1 '{"verdict":"proceed"}'
    case "$STATE" in
        setup_plan_backed | analysis) pass "a plan/v1 task proceeds past plan_validation" ;;
        *) fail "plan/v1 task reached [$STATE]" ;;
    esac

    echo "--- a child built from /execute's spawn"

    # The cases above hand the child its PLAN_DOC. /execute's children get only
    # the vars its spawn tick puts on each task (#1160), so build the tasks the
    # way the run does: plan-to-tasks.sh over the step plan, then the
    # TASKS_WITH_BRANCH line from execute.md's compiled directive, rendered as
    # koto renders it for a run on docs/plans/PLAN-steps.md with no bound and
    # no deferral. A child initialized with exactly one task's vars then meets
    # the step_detail gate with nothing else to go on.
    EXEC_JSON=$(koto template compile "$REPO_ROOT/skills/execute/koto-templates/execute.md" 2>/dev/null | tail -1)
    SPAWN_LINE=""
    if [ -n "$EXEC_JSON" ] && [ -f "$EXEC_JSON" ]; then
        SPAWN_LINE=$(jq -r '.states.spawn_and_await.directive' "$EXEC_JSON" | grep '^TASKS_WITH_BRANCH=')
    fi
    SPAWNED=""
    if [ -n "$SPAWN_LINE" ]; then
        LINE=$(printf '%s' "$SPAWN_LINE" | sed -e 's|{{PLAN_DOC}}|docs/plans/PLAN-steps.md|g' \
            -e 's/{{REVIEW_FLOOR}}//g' -e 's/{{REVIEW_CEILING}}//g' \
            -e 's/{{VERIFICATION}}/local/g' -e 's/{{VERIFICATION_DEFERRAL_REASON}}//g')
        TASKS_JSON=$(cd "$ER" && "$REPO_ROOT/skills/plan/scripts/plan-to-tasks.sh" docs/plans/PLAN-steps.md 2>/dev/null)
        SPAWNED=$(cd "$ER" && TASKS="$TASKS_JSON" SETTLED_BRANCH=main CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
            bash -c "$LINE"' && printf "%s" "$TASKS_WITH_BRANCH"' 2>/dev/null)
    fi
    STEP1=$(printf '%s' "$SPAWNED" | jq -c '.[]? | select(.name == "step-1")' 2>/dev/null)

    # from_task <session> <task>: a child with the task's vars and no others,
    # as koto materializes one, from init to plan_validation.
    from_task() {
        local kv
        local -a vars=()
        while IFS= read -r kv; do
            vars+=(--var "$kv")
        done < <(printf '%s' "$2" | jq -r '.vars | to_entries[] | "\(.key)=\(.value)"')
        (cd "$ER" && PATH="$ENGINE_PATH" koto init "$1" --template "$TEMPLATE" "${vars[@]}" >/dev/null 2>&1)
        tick "$1"
        [ "$STATE" = entry ] && tick "$1" '{"mode":"plan_backed","issue_source":"plan_outline"}'
        printf 'the outline item\n' | (cd "$ER" && koto context add "$1" context.md) >/dev/null 2>&1
        tick "$1" '{"status":"completed","issue_source":"plan_outline"}'
    }

    if [ -z "$STEP1" ]; then
        fail "the spawn built no step-1 task (spawn line [$SPAWN_LINE], tasks [$SPAWNED])"
    else
        if [ "$(printf '%s' "$STEP1" | jq -r '.vars.PLAN_DOC // empty')" = docs/plans/PLAN-steps.md ]; then
            pass "the spawned step-1 task carries the run's PLAN_DOC"
        else
            fail "the spawned step-1 task's vars: $(printf '%s' "$STEP1" | jq -c '.vars')"
        fi
        from_task s-spawned "$STEP1"
        MSG=$(gate_message)
        if [ "$STATE" = plan_validation ] && [ -z "$MSG" ]; then
            pass "a child built from a spawned task passes step_detail on its detailed step"
        else
            fail "spawned child: state [$STATE], gate message [$MSG]"
        fi
        tick s-spawned '{"verdict":"proceed"}'
        case "$STATE" in
            setup_plan_backed | analysis) pass "the spawned child's verdict proceed moves on to [$STATE]" ;;
            *) fail "the spawned child's proceed reached [$STATE]" ;;
        esac

        # The same task without PLAN_DOC is the child the issue reported: the
        # gate refuses, so proceed can't move it.
        from_task s-noplan "$(printf '%s' "$STEP1" | jq -c 'del(.vars.PLAN_DOC)')"
        if [ "$STATE" = plan_validation ] \
            && printf '%s' "$RESP" | jq -e '[.blocking_conditions[]? | select(.name == "step_detail") | tostring | contains("no plan path given")] | any' >/dev/null 2>&1; then
            pass "the same task without PLAN_DOC holds at step_detail with no plan path given"
        else
            fail "task without PLAN_DOC: state [$STATE], response [$RESP]"
        fi
        tick s-noplan '{"verdict":"proceed"}'
        [ "$STATE" = plan_validation ] && pass "proceed is refused for the task without PLAN_DOC" \
            || fail "proceed without PLAN_DOC reached [$STATE]"
    fi
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
