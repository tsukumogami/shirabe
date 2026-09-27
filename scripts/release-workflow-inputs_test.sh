#!/usr/bin/env bash
# Runs the step scripts of the reusable release workflows with hostile input
# values and checks that no input text is ever executed as shell.
#
# The callers of release.yml and finalize-release.yml validate the tag before
# they pass it, so none of this is reachable through them. This test covers the
# case where that caller-side check is missing: the payload arrives in the
# workflow as-is.
#
# How it runs a workflow. The Actions runner renders every expression in a
# step's `run:` text and `env:` values by plain text substitution, then runs
# the script with `bash -e`. This harness does the same thing: it pulls each
# step out of the workflow with yq, substitutes the expressions it knows
# (inputs, github.repository, github.token, secrets.token, step outputs),
# and runs the result with `bash -e` in a scratch directory. gh, git and sleep
# are stubbed on PATH so the scripts run to completion offline. An expression
# the harness doesn't know makes the run VOID rather than guessing.
#
# Every payload carries `touch <canary>`. If any step creates its canary, some
# input text was executed and the row fails.
#
# Two execution modes:
#   sequential  the runner's own semantics: the job stops at the first failing
#               step, and `if:` conditions are evaluated.
#   every-step  every `run:` step executes regardless of earlier failures or
#               its `if:`, so every step sees the payload even if an earlier
#               format check would have stopped the job. This is the row that
#               shows the env-passing holds on its own.
#
# Other rows:
#   clean       valid inputs, sequential, both dry-run values: every step that
#               runs must exit 0. Shows the stubs let the scripts run, so a
#               green payload row isn't green because everything crashed early.
#   control     a fixture workflow that interpolates the tag into its script:
#               the harness must see its canary fire. If it doesn't, the harness
#               can't detect anything and the suite is VOID.
#   static      no `run:` text may contain an inputs.* or steps.* expression.
#
# Usage:
#   scripts/release-workflow-inputs_test.sh [--workflows DIR]
#
# DIR defaults to .github/workflows and must hold release.yml and
# finalize-release.yml. Pointing it at older copies of those two files is how
# the suite is shown failing against them.
#
# Exit codes: 0 all rows pass, 1 a row failed, 2 VOID (the harness could not
# establish a premise, so nothing was tested).

# This file handles workflow expression syntax and shell payloads as literal
# text throughout, so single-quoted $ and backticks are intended.
# shellcheck disable=SC2016

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WF_DIR="$REPO_ROOT/.github/workflows"

while [ $# -gt 0 ]; do
    case "$1" in
        --workflows) WF_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

command -v yq >/dev/null || { echo "VOID: yq not found" >&2; exit 2; }
command -v jq >/dev/null || { echo "VOID: jq not found" >&2; exit 2; }

# The canary paths end up inside the payloads, and release.yml splits the
# version on dots before doing arithmetic on it. A dot in the path would cut
# the arithmetic payload apart before it reached the arithmetic, and that row
# would pass without testing anything. So the scratch path must be dot-free.
WORK=$(mktemp -d /tmp/release-wf-test-XXXXXX)
trap 'rm -rf "$WORK"' EXIT
case "$WORK" in
    *.*) echo "VOID: scratch path $WORK contains a dot" >&2; exit 2 ;;
esac

PASS=0
FAIL=0
VOID=0

pass() { PASS=$((PASS + 1)); echo "PASS  $*"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL  $*"; }
void() { VOID=$((VOID + 1)); echo "VOID  $*"; }

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

STUBS="$WORK/stubs"
mkdir -p "$STUBS"

cat > "$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
# A draft release with five assets, no existing releases in lists, push access.
case "$1 $2" in
    "release view") echo '{"isDraft":true,"assets":[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"},{"name":"e"}]}' ;;
    "release list") echo '[]' ;;
    "release edit") ;;
    api\ *)
        case "$2" in
            */releases) echo '[]' ;;
            *) echo 'true' ;;
        esac ;;
    *) echo "gh stub: unhandled: $*" >&2; exit 1 ;;
esac
EOF

cat > "$STUBS/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    rev-parse) echo 0000000000000000000000000000000000000000 ;;
    *) ;;
esac
EOF

printf '#!/bin/sh\nexit 0\n' > "$STUBS/sleep"
chmod +x "$STUBS/gh" "$STUBS/git" "$STUBS/sleep"

# ---------------------------------------------------------------------------
# Workflow extraction
# ---------------------------------------------------------------------------

# Reads a file into the variable named $1 without losing trailing newlines.
read_file() {
    IFS= read -r -d '' "$1" < "$2" || true
}

# extract <workflow> <dest>: writes the single job's steps as
# <dest>/steps/<i>/{name,id,if,run,env-keys,env/<key>} and the workflow_call
# inputs as <dest>/inputs (name type default, one per line).
extract() {
    local wf="$1" dest="$2" jobs job n i k
    jobs=$(yq -r '.jobs | keys | length' "$wf")
    [ "$jobs" = 1 ] || { echo "expected one job in $wf, found $jobs"; return 1; }
    job=$(yq -r '.jobs | keys | .[0]' "$wf")
    n=$(yq -r ".jobs.\"$job\".steps | length" "$wf")
    echo "$n" > "$dest/step-count"
    i=0
    while [ "$i" -lt "$n" ]; do
        mkdir -p "$dest/steps/$i/env"
        yq -r ".jobs.\"$job\".steps[$i].name // \"step $i\"" "$wf" > "$dest/steps/$i/name"
        yq -r ".jobs.\"$job\".steps[$i].id // \"\"" "$wf" > "$dest/steps/$i/id"
        yq -r ".jobs.\"$job\".steps[$i].if // \"\"" "$wf" > "$dest/steps/$i/if"
        if [ "$(yq -r ".jobs.\"$job\".steps[$i] | has(\"run\")" "$wf")" = true ]; then
            yq -r ".jobs.\"$job\".steps[$i].run" "$wf" > "$dest/steps/$i/run"
        fi
        yq -r ".jobs.\"$job\".steps[$i].env // {} | keys | .[]" "$wf" > "$dest/steps/$i/env-keys"
        while IFS= read -r k; do
            [ -n "$k" ] || continue
            yq -r ".jobs.\"$job\".steps[$i].env.\"$k\"" "$wf" > "$dest/steps/$i/env/$k"
        done < "$dest/steps/$i/env-keys"
        i=$((i + 1))
    done
    yq -r '.on.workflow_call.inputs | to_entries | .[] | .key + " " + .value.type + " " + ((.value.default // "") | tostring)' "$wf" > "$dest/inputs"
}

# ---------------------------------------------------------------------------
# Expression rendering
# ---------------------------------------------------------------------------

# Per-run state, set by run_workflow.
IN=""       # directory of input values, one file per input name
OUTS=""     # directory of step outputs, <id>/<key>
RESULT=""
UNKNOWN=""

# eval_expr <inner>: sets RESULT to the expression's value. Returns 1 and sets
# UNKNOWN for anything the harness doesn't model.
eval_expr() {
    local e="$1" id key
    case "$e" in
        inputs.*)
            key="${e#inputs.}"
            [ -f "$IN/$key" ] || { UNKNOWN="$e"; return 1; }
            read_file RESULT "$IN/$key" ;;
        github.repository) RESULT="example-org/example-repo" ;;
        github.token) RESULT="fake-github-token" ;;
        secrets.token) RESULT="" ;;
        steps.*.outputs.*)
            id="${e#steps.}"; id="${id%%.*}"
            key="${e##*.outputs.}"
            if [ -f "$OUTS/$id/$key" ]; then read_file RESULT "$OUTS/$id/$key"; else RESULT=""; fi ;;
        *) UNKNOWN="$e"; return 1 ;;
    esac
}

# render <text>: sets RENDERED to <text> with every expression substituted.
render() {
    local rest="$1" pre inner out=""
    while :; do
        case "$rest" in
            *'${{'*) ;;
            *) break ;;
        esac
        pre="${rest%%'${{'*}"
        rest="${rest#*'${{'}"
        case "$rest" in
            *'}}'*) ;;
            *) UNKNOWN="unterminated expression"; return 1 ;;
        esac
        inner="${rest%%'}}'*}"
        rest="${rest#*'}}'}"
        inner="$(printf '%s' "$inner" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        eval_expr "$inner" || return 1
        out="$out$pre$RESULT"
    done
    RENDERED="$out$rest"
}

# eval_if <condition>: returns 0 if the step should run, 1 if not, 2 if the
# harness can't evaluate the condition.
eval_if() {
    local c="$1" lhs op rhs
    [ -n "$c" ] || return 0
    c="${c#'${{'}"; c="${c%'}}'}"
    c="$(printf '%s' "$c" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$c" in
        *' == '*) op='=='; lhs="${c%% == *}"; rhs="${c#* == }" ;;
        *' != '*) op='!='; lhs="${c%% != *}"; rhs="${c#* != }" ;;
        *) UNKNOWN="if: $c"; return 2 ;;
    esac
    eval_expr "$lhs" || return 2
    rhs="${rhs#\'}"; rhs="${rhs%\'}"
    if [ "$op" = '==' ]; then
        [ "$RESULT" = "$rhs" ]
    else
        [ "$RESULT" != "$rhs" ]
    fi
}

# ---------------------------------------------------------------------------
# Running a workflow
# ---------------------------------------------------------------------------

# run_workflow <extracted-dir> <mode> <canary-dir>
# Runs the steps; sets FIRED to the names of steps after which a canary
# appeared, STEP_FAILURES to the number of steps that exited non-zero, RAN to
# the number of run steps executed. Returns 2 on VOID.
run_workflow() {
    local ex="$1" mode="$2" canaries="$3" n i name id cond rc k envargs
    local ws="$WORK/ws" out f fired
    FIRED=""
    STEP_FAILURES=0
    RAN=0
    rm -rf "$ws" "$OUTS"
    mkdir -p "$ws" "$OUTS"
    read_file n "$ex/step-count"
    n="${n%$'\n'}"
    i=0
    while [ "$i" -lt "$n" ]; do
        if [ ! -f "$ex/steps/$i/run" ]; then i=$((i + 1)); continue; fi
        read_file name "$ex/steps/$i/name"; name="${name%$'\n'}"
        read_file id "$ex/steps/$i/id"; id="${id%$'\n'}"
        read_file cond "$ex/steps/$i/if"; cond="${cond%$'\n'}"
        if [ "$mode" = sequential ]; then
            rc=0
            eval_if "$cond" || rc=$?
            if [ "$rc" = 2 ]; then echo "  cannot evaluate $UNKNOWN in step '$name'"; return 2; fi
            if [ "$rc" = 1 ]; then i=$((i + 1)); continue; fi
        fi

        envargs=()
        while IFS= read -r k; do
            [ -n "$k" ] || continue
            read_file RENDERED "$ex/steps/$i/env/$k"
            render "${RENDERED%$'\n'}" || { echo "  cannot render $UNKNOWN in env $k of step '$name'"; return 2; }
            envargs+=("$k=$RENDERED")
        done < "$ex/steps/$i/env-keys"

        read_file RENDERED "$ex/steps/$i/run"
        render "$RENDERED" || { echo "  cannot render $UNKNOWN in step '$name'"; return 2; }
        printf '%s' "$RENDERED" > "$WORK/step.sh"

        out="$WORK/step-output"
        : > "$out"
        rc=0
        (cd "$ws" && env PATH="$STUBS:$PATH" GITHUB_OUTPUT="$out" \
            GITHUB_REPOSITORY="example-org/example-repo" TMPDIR="$WORK" \
            ${envargs[@]+"${envargs[@]}"} \
            bash -e "$WORK/step.sh") > "$WORK/step-log" 2>&1 || rc=$?
        RAN=$((RAN + 1))
        [ "$rc" = 0 ] || STEP_FAILURES=$((STEP_FAILURES + 1))

        if [ -n "$id" ]; then
            mkdir -p "$OUTS/$id"
            while IFS= read -r k; do
                case "$k" in *=*) printf '%s' "${k#*=}" > "$OUTS/$id/${k%%=*}" ;; esac
            done < "$out"
        fi

        fired=""
        for f in "$canaries"/*; do
            [ -e "$f" ] || continue
            fired="$fired ${f##*/}"
            rm -f "$f"
        done
        [ -z "$fired" ] || FIRED="$FIRED [$name:$fired]"

        if [ "$mode" = sequential ] && [ "$rc" != 0 ]; then
            break
        fi
        i=$((i + 1))
    done
}

# set_inputs <extracted-dir> <payload-or-empty> <dry-run>
# Writes one file per workflow_call input. String inputs get the payload, or a
# valid value when the payload is empty. Booleans get <dry-run>. Numbers get
# their default.
set_inputs() {
    local ex="$1" payload="$2" dry="$3" name type def
    rm -rf "$IN"
    mkdir -p "$IN"
    while read -r name type def; do
        [ -n "$name" ] || continue
        case "$type" in
            string)
                if [ -n "$payload" ]; then
                    printf '%s' "$payload" > "$IN/$name"
                else
                    case "$name" in
                        tag) printf 'v1.2.3' > "$IN/$name" ;;
                        version) printf '1.2.3' > "$IN/$name" ;;
                        ref) printf 'main' > "$IN/$name" ;;
                        dev-suffix) printf -- '-dev' > "$IN/$name" ;;
                        *) echo "  no clean value for string input $name"; return 2 ;;
                    esac
                fi ;;
            boolean) printf '%s' "$dry" > "$IN/$name" ;;
            number) printf '%s' "$def" > "$IN/$name" ;;
            *) echo "  unhandled input type $type for $name"; return 2 ;;
        esac
    done < "$ex/inputs"
}

IN="$WORK/inputs"
OUTS="$WORK/outputs"
CANARIES="$WORK/canaries"
mkdir -p "$CANARIES"

# Each payload tries a different way out of the script text it lands in.
PAYLOAD_NAMES=(double-quote single-quote command-substitution backtick semicolon newline arithmetic-subscript)
payload_for() {
    local c="$CANARIES/$1"
    case "$1" in
        double-quote)          printf 'v1.0.0"; touch %s; echo "' "$c" ;;
        single-quote)          printf "v1.0.0'; touch %s; echo '" "$c" ;;
        command-substitution)  printf 'v1.0.0$(touch %s)' "$c" ;;
        backtick)              printf 'v1.0.0`touch %s`' "$c" ;;
        semicolon)             printf 'v1.0.0; touch %s' "$c" ;;
        newline)               printf 'v1.0.0\ntouch %s' "$c" ;;
        arithmetic-subscript)  printf 'x[$(touch %s)]' "$c" ;;
    esac
}

# ---------------------------------------------------------------------------
# Control: the harness must catch a workflow that interpolates its input.
# ---------------------------------------------------------------------------

CONTROL="$WORK/control.yml"
cat > "$CONTROL" <<'EOF'
on:
  workflow_call:
    inputs:
      tag:
        type: string
        required: true
jobs:
  control:
    runs-on: ubuntu-latest
    steps:
      - name: Interpolates the tag
        run: |
          echo "Tag: ${{ inputs.tag }}"
EOF
mkdir -p "$WORK/ex-control"
extract "$CONTROL" "$WORK/ex-control" >/dev/null || { void "control: extraction failed"; exit 2; }
set_inputs "$WORK/ex-control" "$(payload_for double-quote)" false || { void "control: inputs"; exit 2; }
run_workflow "$WORK/ex-control" sequential "$CANARIES" || { void "control: harness could not run the fixture"; exit 2; }
if [ -n "$FIRED" ]; then
    pass "control: harness detects an interpolated input ($FIRED )"
else
    void "control: fixture interpolates the tag but no canary fired, so the harness detects nothing"
    exit 2
fi

# ---------------------------------------------------------------------------
# The workflows under test
# ---------------------------------------------------------------------------

for wf in release.yml finalize-release.yml; do
    path="$WF_DIR/$wf"
    [ -f "$path" ] || { void "$wf: not found in $WF_DIR"; continue; }
    ex="$WORK/ex-$wf"
    mkdir -p "$ex"
    if ! msg=$(extract "$path" "$ex"); then void "$wf: $msg"; continue; fi

    # static: no inputs.* or steps.* expression inside run text.
    hits=""
    for d in "$ex"/steps/*; do
        [ -f "$d/run" ] || continue
        if grep -qE '\$\{\{[[:space:]]*(inputs|steps)\.' "$d/run"; then
            hits="$hits '$(cat "$d/name")'"
        fi
    done
    if [ -z "$hits" ]; then
        pass "$wf static: no inputs.* or steps.* expression in any run: block"
    else
        fail "$wf static: expressions expanded into run: text in step(s)$hits"
    fi

    # clean: valid inputs run to completion.
    for dry in false true; do
        if ! set_inputs "$ex" "" "$dry"; then void "$wf clean dry-run=$dry: inputs"; continue; fi
        rc=0; run_workflow "$ex" sequential "$CANARIES" || rc=$?
        if [ "$rc" = 2 ]; then void "$wf clean dry-run=$dry"; continue; fi
        if [ "$STEP_FAILURES" = 0 ] && [ "$RAN" -gt 0 ]; then
            pass "$wf clean dry-run=$dry: $RAN run step(s), all exit 0"
        else
            fail "$wf clean dry-run=$dry: $STEP_FAILURES of $RAN step(s) failed; last log:"
            sed 's/^/        /' "$WORK/step-log"
        fi
    done

    # payloads, both modes.
    for mode in sequential every-step; do
        for p in "${PAYLOAD_NAMES[@]}"; do
            for dry in false true; do
                if ! set_inputs "$ex" "$(payload_for "$p")" "$dry"; then void "$wf $mode $p: inputs"; continue; fi
                rc=0; run_workflow "$ex" "$mode" "$CANARIES" || rc=$?
                if [ "$rc" = 2 ]; then void "$wf $mode $p dry-run=$dry"; continue; fi
                if [ "$RAN" = 0 ]; then void "$wf $mode $p dry-run=$dry: no step ran"; continue; fi
                if [ -z "$FIRED" ]; then
                    pass "$wf $mode $p dry-run=$dry: $RAN step(s) ran, no canary"
                else
                    fail "$wf $mode $p dry-run=$dry: input executed as shell in$FIRED"
                fi
            done
        done
    done
done

echo
echo "$PASS passed, $FAIL failed, $VOID void"
[ "$VOID" = 0 ] || exit 2
[ "$FAIL" = 0 ] || exit 1
exit 0
