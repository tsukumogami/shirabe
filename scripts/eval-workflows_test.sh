#!/usr/bin/env bash
# eval-workflows_test.sh -- the workflows that run eval cases keep the
# properties Security Considerations in
# docs/designs/DESIGN-skill-regression-detection.md gives them.
#
# The two gates that run a pull request's script cases, check-evals.yml and
# check-skill-gate.yml, must:
#   - trigger on pull_request and never on pull_request_target, so a fork's
#     pull request runs with the fork's read-only token;
#   - declare `permissions: contents: read` at the workflow level, with no job
#     carrying a permissions key that differs from it;
#   - name no repository secret (`secrets` on a line outside a comment);
#   - run every job on GitHub-hosted runners: `runs-on` is ubuntu-latest,
#     macos-latest or `${{ matrix.os }}`, and every label in a matrix.os is
#     ubuntu-latest or macos-latest.
# check-evals.yml must still run scripts/check-evals-exist.sh on pull_request
# paths skills/**. check-skill-gate.yml's skill-gate job must take its base
# from a step before both run steps that writes SKILL_GATE_BASE to
# $GITHUB_ENV, from `git rev-parse HEAD^1` on pull_request; neither run step
# may set SKILL_GATE_BASE, and no step may read pull_request.base.sha.
# run-evals.yml must trigger on workflow_dispatch and nothing
# else. check-run-evals.yml must run this test after installing the yq that
# check-macos-floor-legs.yml pins, and start on a change to any of the files
# it reads.
#
# The real workflows are checked first, one PASS line per property. Then each
# way a gate could lose a property is applied to a copy in a temporary
# directory, and the check must fail on the copy naming the file and the
# property.
#
# Usage: bash scripts/eval-workflows_test.sh
#
# Requires mikefarah yq v4 on PATH; without it the test fails rather than
# skips. bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
WF_DIR="$ROOT/.github/workflows"

if ! command -v yq >/dev/null 2>&1; then
    echo "eval-workflows_test: yq (mikefarah v4) is required on PATH" >&2
    exit 1
fi
case "$(yq --version 2>&1)" in
    *mikefarah/yq*" version v4."*) ;;
    *) echo "eval-workflows_test: yq on PATH is not mikefarah yq v4: $(yq --version 2>&1)" >&2; exit 1 ;;
esac

T=$(mktemp -d "${TMPDIR:-/tmp}/eval-workflows-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n      %s\n' "$1" "${2-}"; }

# -- the properties -----------------------------------------------------------
#
# Each prop_* takes a workflow file, prints one `<file>: <problem>` line per
# problem it finds, and returns 1 when it found any.

# triggers <file>: the workflow's triggers, one per line, whether `on` is a
# map, a list or a single name.
triggers() {
    case "$(yq -r '.on | tag' "$1")" in
        '!!map') yq -r '.on | keys | .[]' "$1" ;;
        '!!seq') yq -r '.on[]' "$1" ;;
        '!!str') yq -r '.on' "$1" ;;
    esac
}

prop_pull_request() {
    local f=$1 name t found=0 bad=0
    name=$(basename "$f")
    for t in $(triggers "$f"); do
        case "$t" in
            pull_request) found=1 ;;
            pull_request_target) echo "$name: triggers on pull_request_target"; bad=1 ;;
        esac
    done
    if [ "$found" -ne 1 ]; then
        echo "$name: does not trigger on pull_request"
        bad=1
    fi
    return "$bad"
}

READ_ONLY='{"contents":"read"}'

prop_permissions() {
    local f=$1 name got
    name=$(basename "$f")
    got=$(yq -o=json -I=0 '.permissions' "$f")
    if [ "$got" != "$READ_ONLY" ]; then
        echo "$name: workflow permissions are $got, not contents: read"
        return 1
    fi
}

prop_job_permissions() {
    local f=$1 name j got bad=0
    name=$(basename "$f")
    for j in $(yq -r '.jobs | keys | .[]' "$f"); do
        [ "$(J=$j yq -r '.jobs[strenv(J)] | has("permissions")' "$f")" = true ] || continue
        got=$(J=$j yq -o=json -I=0 '.jobs[strenv(J)].permissions' "$f")
        if [ "$got" != "$READ_ONLY" ]; then
            echo "$name: job $j permissions are $got, not contents: read"
            bad=1
        fi
    done
    return "$bad"
}

prop_no_secrets() {
    local f=$1 name hits
    name=$(basename "$f")
    hits=$(grep -n 'secrets' "$f" | grep -v '^[0-9]*:[[:space:]]*#')
    if [ -n "$hits" ]; then
        echo "$name: reads a repository secret: $(printf '%s' "$hits" | tr '\n' ' ')"
        return 1
    fi
}

hosted() {
    case "$1" in
        ubuntu-latest|macos-latest) return 0 ;;
    esac
    return 1
}

prop_hosted_runners() {
    local f=$1 name j tag runs labels l bad=0
    name=$(basename "$f")
    for j in $(yq -r '.jobs | keys | .[]' "$f"); do
        tag=$(J=$j yq -r '.jobs[strenv(J)]."runs-on" | tag' "$f")
        runs=$(J=$j yq -o=json -I=0 '.jobs[strenv(J)]."runs-on"' "$f")
        if [ "$tag" != '!!str' ]; then
            echo "$name: job $j runs-on $runs is not a GitHub-hosted runner"
            bad=1
            continue
        fi
        runs=$(J=$j yq -r '.jobs[strenv(J)]."runs-on"' "$f")
        if hosted "$runs"; then
            continue
        fi
        if [ "$runs" != '${{ matrix.os }}' ]; then
            echo "$name: job $j runs-on $runs is not a GitHub-hosted runner"
            bad=1
            continue
        fi
        tag=$(J=$j yq -r '.jobs[strenv(J)].strategy.matrix.os | tag' "$f")
        case "$tag" in
            '!!seq') labels=$(J=$j yq -r '.jobs[strenv(J)].strategy.matrix.os[]' "$f") ;;
            # An expression: the runner labels are its double-quoted words.
            '!!str') labels=$(J=$j yq -r '.jobs[strenv(J)].strategy.matrix.os' "$f" | grep -o '"[^"]*"' | tr -d '"') ;;
            *) labels="" ;;
        esac
        if [ -z "$labels" ]; then
            echo "$name: job $j runs on matrix.os, which names no runner label"
            bad=1
            continue
        fi
        for l in $labels; do
            if ! hosted "$l"; then
                echo "$name: job $j matrix.os label $l is not a GitHub-hosted runner"
                bad=1
            fi
        done
    done
    return "$bad"
}

prop_evals_exist() {
    local f=$1 name bad=0
    name=$(basename "$f")
    if [ "$(yq -r '.on.pull_request.paths // [] | any_c(. == "skills/**")' "$f")" != true ]; then
        echo "$name: pull_request paths do not include skills/**"
        bad=1
    fi
    if [ "$(yq -r '[.jobs[].steps[]?.run // ""] | any_c(test("(^|\s)scripts/check-evals-exist\.sh(\s|$)"))' "$f")" != true ]; then
        echo "$name: no step runs scripts/check-evals-exist.sh"
        bad=1
    fi
    return "$bad"
}

prop_dispatch_only() {
    local f=$1 name t found=0 bad=0
    name=$(basename "$f")
    for t in $(triggers "$f"); do
        if [ "$t" = workflow_dispatch ]; then
            found=1
        else
            echo "$name: triggers on $t, not only workflow_dispatch"
            bad=1
        fi
    done
    if [ "$found" -ne 1 ]; then
        echo "$name: does not trigger on workflow_dispatch"
        bad=1
    fi
    return "$bad"
}

# check-run-evals.yml runs this test, after the yq install
# check-macos-floor-legs.yml pins, with the same version and digest.
prop_runs_this_test() {
    local f=$1 name ref_install ref_version ref_sha j n i run at install_at p bad=0
    name=$(basename "$f")
    ref_install=$(yq -r '.jobs."check-macos-floor-legs".steps[] | select(.name == "Install pinned mikefarah yq") | .run' "$WF_DIR/check-macos-floor-legs.yml")
    ref_version=$(yq -r '.jobs."check-macos-floor-legs".env.YQ_VERSION' "$WF_DIR/check-macos-floor-legs.yml")
    ref_sha=$(yq -r '.jobs."check-macos-floor-legs".env.YQ_SHA256' "$WF_DIR/check-macos-floor-legs.yml")
    if [ -z "$ref_install" ] || [ "$ref_version" = null ] || [ "$ref_sha" = null ]; then
        echo "$name: could not read the pinned yq install from check-macos-floor-legs.yml"
        return 1
    fi
    j=$(yq -r '.jobs | to_entries | .[] | select([.value.steps[]?.run // ""] | any_c(. == "bash scripts/eval-workflows_test.sh")) | .key' "$f" | head -n 1)
    if [ -z "$j" ]; then
        echo "$name: no job runs bash scripts/eval-workflows_test.sh"
        return 1
    fi
    # Each step's run, as read through the same command substitution as the
    # reference, so a block's trailing newline counts the same on both sides.
    n=$(J=$j yq -r '.jobs[strenv(J)].steps | length' "$f")
    at=""
    install_at=""
    i=0
    while [ "$i" -lt "$n" ]; do
        run=$(J=$j I=$i yq -r '.jobs[strenv(J)].steps[env(I)].run // ""' "$f")
        if [ -z "$at" ] && [ "$run" = "bash scripts/eval-workflows_test.sh" ]; then
            at=$i
        fi
        if [ -z "$install_at" ] && [ "$run" = "$ref_install" ]; then
            install_at=$i
        fi
        i=$((i + 1))
    done
    if [ -z "$install_at" ] || [ "$install_at" -ge "$at" ]; then
        echo "$name: job $j does not install the pinned yq as check-macos-floor-legs.yml does before the test"
        bad=1
    fi
    if [ "$(J=$j yq -r '.jobs[strenv(J)].env.YQ_VERSION' "$f")" != "$ref_version" ] \
        || [ "$(J=$j yq -r '.jobs[strenv(J)].env.YQ_SHA256' "$f")" != "$ref_sha" ]; then
        echo "$name: job $j does not pin yq $ref_version with check-macos-floor-legs.yml's SHA-256"
        bad=1
    fi
    for p in .github/workflows/run-evals.yml .github/workflows/check-evals.yml \
        .github/workflows/check-skill-gate.yml scripts/eval-workflows_test.sh; do
        if [ "$(P=$p yq -r '.on.pull_request.paths // [] | any_c(. == strenv(P))' "$f")" != true ]; then
            echo "$name: pull_request paths do not include $p"
            bad=1
        fi
    done
    return "$bad"
}

# The skill-gate job's base: a step before both run steps writes
# SKILL_GATE_BASE to $GITHUB_ENV, from `git rev-parse HEAD^1` (the merge
# commit's first parent) on pull_request; neither run step sets its own
# SKILL_GATE_BASE, which would override it; and no step reads
# pull_request.base.sha, which can be older than the commit the pull request
# merges into.
GATE_LINUX_RUN='bash scripts/skill-gate.sh'
GATE_MACOS_RUN='scripts/check-bash-floor.sh --backend system skill-gate'

prop_gate_base() {
    local f=$1 name n i run first="" base_at="" bad=0
    name=$(basename "$f")
    if [ "$(yq -r '.jobs | has("skill-gate")' "$f")" != true ]; then
        echo "$name: has no skill-gate job"
        return 1
    fi
    n=$(yq -r '.jobs."skill-gate".steps | length' "$f")
    i=0
    while [ "$i" -lt "$n" ]; do
        run=$(I=$i yq -r '.jobs."skill-gate".steps[env(I)].run // ""' "$f")
        case "$run" in
            "$GATE_LINUX_RUN"|"$GATE_MACOS_RUN")
                [ -n "$first" ] || first=$i
                if [ "$(I=$i yq -r '.jobs."skill-gate".steps[env(I)].env // {} | has("SKILL_GATE_BASE")' "$f")" = true ]; then
                    echo "$name: job skill-gate run step '$run' sets SKILL_GATE_BASE in its env, overriding the base step"
                    bad=1
                fi
                ;;
            *)
                if [ -z "$first" ] && [ -z "$base_at" ]; then
                    case "$run" in
                        *'git rev-parse HEAD^1'*)
                            case "$run" in
                                *pull_request*SKILL_GATE_BASE=*GITHUB_ENV*) base_at=$i ;;
                            esac
                            ;;
                    esac
                fi
                ;;
        esac
        case "$(I=$i yq -o=json -I=0 '.jobs."skill-gate".steps[env(I)]' "$f")" in
            *pull_request.base.sha*)
                echo "$name: job skill-gate step $i reads pull_request.base.sha"
                bad=1
                ;;
        esac
        i=$((i + 1))
    done
    if [ -z "$first" ]; then
        echo "$name: job skill-gate has no step running '$GATE_LINUX_RUN' or '$GATE_MACOS_RUN'"
        return 1
    fi
    if [ -z "$base_at" ]; then
        echo "$name: job skill-gate has no step before the run steps that writes SKILL_GATE_BASE to \$GITHUB_ENV from git rev-parse HEAD^1 on pull_request"
        bad=1
    elif [ "$(I=$base_at yq -r '.jobs."skill-gate".steps[env(I)] | has("if")' "$f")" = true ]; then
        echo "$name: job skill-gate's base step runs only under an if, not on both legs"
        bad=1
    fi
    return "$bad"
}

GATE_PROPS="prop_pull_request prop_permissions prop_job_permissions prop_no_secrets prop_hosted_runners"

# check_gate <file>: every gate property, plus the check-evals-exist one for
# check-evals.yml and the base selection for check-skill-gate.yml; prints each
# problem and returns 1 when there is any.
check_gate() {
    local f=$1 p bad=0
    for p in $GATE_PROPS; do
        "$p" "$f" || bad=1
    done
    case "$(basename "$f")" in
        check-evals.yml) prop_evals_exist "$f" || bad=1 ;;
        check-skill-gate.yml) prop_gate_base "$f" || bad=1 ;;
    esac
    return "$bad"
}

# -- the real workflows -------------------------------------------------------

# real <label> <prop> <file>
real() {
    local out
    if out=$("$2" "$WF_DIR/$3" 2>&1); then
        pass "$3: $1"
    else
        fail "$3: $1" "$out"
    fi
}

for wf in check-evals.yml check-skill-gate.yml; do
    if [ ! -f "$WF_DIR/$wf" ]; then
        fail "$wf exists" "no $WF_DIR/$wf"
        continue
    fi
    real "triggers on pull_request, not pull_request_target" prop_pull_request "$wf"
    real "workflow permissions are exactly contents: read" prop_permissions "$wf"
    real "no job permissions differ from contents: read" prop_job_permissions "$wf"
    real "no secrets outside a comment" prop_no_secrets "$wf"
    real "every job runs on a GitHub-hosted runner" prop_hosted_runners "$wf"
done
real "runs scripts/check-evals-exist.sh on pull_request paths skills/**" prop_evals_exist check-evals.yml
real "skill-gate's base is the merge commit's first parent, set before the run steps" \
    prop_gate_base check-skill-gate.yml
real "triggers on workflow_dispatch only" prop_dispatch_only run-evals.yml
real "runs this test after the pinned yq install, on changes to the files it reads" \
    prop_runs_this_test check-run-evals.yml

# -- mutations ----------------------------------------------------------------

N=0
# mutate <label> <file> <checker> <want text> <kind> <arg>: copies the real
# <file> into a fresh directory, applies the mutation (kind `yq`: a yq -i
# expression; kind `sed`: a sed expression) and expects <checker> to fail on
# the copy with a line naming the file and holding <want text>.
mutate() {
    local label=$1 file=$2 checker=$3 want=$4 kind=$5 arg=$6 dir copy out
    N=$((N + 1))
    dir="$T/m$N"
    mkdir -p "$dir" || { fail "$label" "mkdir $dir"; return; }
    copy="$dir/$file"
    cp "$WF_DIR/$file" "$copy" || { fail "$label" "cp $file"; return; }
    case "$kind" in
        yq) yq -i "$arg" "$copy" 2>"$dir/err" || { fail "$label" "yq: $(cat "$dir/err")"; return; } ;;
        sed)
            sed "$arg" "$WF_DIR/$file" >"$copy" 2>"$dir/err" || { fail "$label" "sed: $(cat "$dir/err")"; return; }
            ;;
    esac
    if cmp -s "$WF_DIR/$file" "$copy"; then
        fail "$label" "the mutation left $file unchanged"
        return
    fi
    if out=$("$checker" "$copy" 2>&1); then
        fail "$label" "the check passed on the mutated copy"
        return
    fi
    case "$out" in
        *"$file: "*"$want"*) pass "$file: $label" ;;
        *) fail "$file: $label" "the check failed without naming [$file] and [$want]: $out" ;;
    esac
}

# An unchanged copy passes, so the mutations below fail for their own reason.
for wf in check-evals.yml check-skill-gate.yml run-evals.yml; do
    mkdir -p "$T/same" || exit 1
    cp "$WF_DIR/$wf" "$T/same/$wf" || exit 1
done
for wf in check-evals.yml check-skill-gate.yml; do
    if out=$(check_gate "$T/same/$wf" 2>&1); then
        pass "$wf: an unchanged copy passes"
    else
        fail "$wf: an unchanged copy passes" "$out"
    fi
done
if out=$(prop_dispatch_only "$T/same/run-evals.yml" 2>&1); then
    pass "run-evals.yml: an unchanged copy passes"
else
    fail "run-evals.yml: an unchanged copy passes" "$out"
fi

for wf in check-evals.yml check-skill-gate.yml; do
    # The job a job-level mutation lands on: skill-gate where there is one.
    if [ "$(yq -r '.jobs | has("skill-gate")' "$WF_DIR/$wf")" = true ]; then
        job=skill-gate
    else
        job=$(yq -r '.jobs | keys | .[0]' "$WF_DIR/$wf")
    fi
    mutate "pull_request renamed to pull_request_target" "$wf" check_gate "triggers on pull_request_target" \
        yq '.on |= with_entries(.key |= sub("^pull_request$", "pull_request_target"))'
    mutate "pull_request_target added beside pull_request" "$wf" check_gate "triggers on pull_request_target" \
        yq '.on.pull_request_target = {}'
    mutate "permissions set to contents: write" "$wf" check_gate "workflow permissions" \
        yq '.permissions.contents = "write"'
    mutate "permissions set to write-all" "$wf" check_gate "workflow permissions" \
        yq '.permissions = "write-all"'
    mutate "id-token: write added to permissions" "$wf" check_gate "workflow permissions" \
        yq '.permissions."id-token" = "write"'
    mutate "permissions removed" "$wf" check_gate "workflow permissions" \
        yq 'del(.permissions)'
    mutate "job $job given permissions contents: write" "$wf" check_gate "job $job permissions" \
        yq ".jobs.\"$job\".permissions = {\"contents\": \"write\"}"
    mutate "job $job runs-on self-hosted" "$wf" check_gate "job $job runs-on" \
        yq ".jobs.\"$job\".\"runs-on\" = \"self-hosted\""
    mutate "ANTHROPIC_API_KEY from secrets added to a step's env" "$wf" check_gate "reads a repository secret" \
        yq ".jobs.\"$job\".steps[-1].env.ANTHROPIC_API_KEY = \"\${{ secrets.ANTHROPIC_API_KEY }}\""
done
mutate "a self-hosted label in the matrix.os expression" check-skill-gate.yml check_gate \
    "matrix.os label self-hosted" sed 's/"macos-latest"\]/"macos-latest", "self-hosted"]/'
mutate "the event's base.sha back as the Linux run step's SKILL_GATE_BASE" check-skill-gate.yml check_gate \
    "sets SKILL_GATE_BASE in its env" \
    yq "(.jobs.\"skill-gate\".steps[] | select(.run == \"$GATE_LINUX_RUN\")).env.SKILL_GATE_BASE = \"\${{ github.event.pull_request.base.sha || github.event.before }}\""
mutate "the base step dropped" check-skill-gate.yml check_gate \
    "no step before the run steps that writes SKILL_GATE_BASE" \
    yq 'del(.jobs."skill-gate".steps[] | select(.run // "" | test("SKILL_GATE_BASE=.*GITHUB_ENV")))'

for t in schedule push pull_request pull_request_target workflow_run workflow_call repository_dispatch; do
    case "$t" in
        schedule) value='[{"cron": "0 0 * * *"}]' ;;
        workflow_run) value='{"workflows": ["Check skill gate"]}' ;;
        *) value='{}' ;;
    esac
    mutate "a $t trigger added beside workflow_dispatch" run-evals.yml prop_dispatch_only "triggers on $t" \
        yq ".on.$t = $value"
done
mutate "on: [workflow_dispatch, push]" run-evals.yml prop_dispatch_only "triggers on push" \
    yq '.on = ["workflow_dispatch", "push"]'

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
