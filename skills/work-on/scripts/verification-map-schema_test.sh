#!/usr/bin/env bash
# verification-map-schema_test.sh -- does shirabe's committed verification map
# match the shirabe-verification-map/v1 schema, and does the schema reference
# document it?
#
# The map at .claude/shirabe-extensions/verification-map.json replaced the
# Markdown list in .claude/shirabe-extensions/work-on.md. This holds the map to
# what that list said (the same default commands, check-skill once per changed
# skill) and to the schema's one cross-field rule: a command marked
# network: true sets unattended explicitly. It also holds the schema reference
# to naming every field and the merge-base read, and work-on.md to pointing at
# the map without listing commands itself.
#
# Each `hosted` entry is also held to the workflow it names (see "hosted twins
# against their workflows" below): the file exists, runs on pull requests, has
# the named job, and that job's plan runs the same command as `runs`. Each
# `always_required` entry is held to its workflow the same way, and to a
# pull_request trigger with no paths filter (see "always_required against its
# workflows" below).
#
# Each jq check is a named query run against a file, so the negative cases run
# the same query on altered copies of the map and require it to fail; a check
# that passed everything would be caught.
#
# Usage: verification-map-schema_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
command -v git >/dev/null 2>&1 || { echo "git is required to run this suite" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }
ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) \
    || { echo "not inside a git working tree" >&2; exit 2; }

MAP="$ROOT/.claude/shirabe-extensions/verification-map.json"
EXT="$ROOT/.claude/shirabe-extensions/work-on.md"
REF="$ROOT/skills/work-on/references/verification-map.md"
for f in "$MAP" "$EXT" "$REF"; do
    [ -r "$f" ] || { echo "$f is not readable" >&2; exit 2; }
done

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/verification-map-schema-test.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# The queries. Each is true exactly when the map satisfies the rule.
Q_SCHEMA='.schema == "shirabe-verification-map/v1"'
# The default list, resolved to argv strings, is the three commands the
# Markdown default named, in that order.
Q_DEFAULT='. as $m | [$m.default[] | $m.commands[.].run | join(" ")]
    == ["cargo test --workspace",
        "skills/plan/scripts/plan-to-tasks_test.sh",
        "skills/work-on/scripts/run-cascade_test.sh"]'
# A skills/** entry exists, and one of its commands runs
# scripts/check-skill.sh --changed once per changed skill.
Q_SKILLS='. as $m | [$m.entries[] | select(.paths | index("skills/**"))
    | .commands[] | $m.commands[.]]
    | any(.run == ["scripts/check-skill.sh", "--changed"] and .each == "skills/*")'
# Every command that reaches the network says whether it may run unattended.
Q_NETWORK='[.commands[] | select(.network == true) | has("unattended")] | all'
# Every id an entry or the default names is defined.
Q_IDS='. as $m | [($m.entries[].commands[]), ($m.default // [])[]]
    | all(. as $id | $m.commands | has($id))'
# The check-skill row declares exactly the one hosted job that runs its
# suites in full, the Linux leg of skill-gate, while the row itself still runs
# only the changed suites.
Q_HOSTED='.commands["check-skill"]
    | .hosted == [{"workflow": ".github/workflows/check-skill-gate.yml",
                   "job": "skill-gate (ubuntu-latest)",
                   "runs": "check-skill {skill}"}]
      and (.run | index("--changed")) != null'

# holds <file> <query>: exit 0 when the query is true on the file.
holds() { jq -e "$2" "$1" >/dev/null 2>&1; }

check() { # check <label> <query>
    if holds "$MAP" "$2"; then pass "$1"; else fail "$1"; fi
}

check "the map declares schema shirabe-verification-map/v1" "$Q_SCHEMA"
check "the default list names the three Markdown default commands" "$Q_DEFAULT"
check "the skills/** entry runs scripts/check-skill.sh --changed with each: skills/*" "$Q_SKILLS"
check "every network: true command sets unattended explicitly" "$Q_NETWORK"
check "every command id an entry or the default names is defined" "$Q_IDS"
check "the check-skill row declares skill-gate (ubuntu-latest) running check-skill {skill}, and still runs --changed" "$Q_HOSTED"

# Negative cases: altered copies of the map must fail the same queries.
neg() { # neg <label> <query> <jq edit>
    local copy="$WORKDIR/neg.json"
    if ! jq "$3" "$MAP" > "$copy" 2>/dev/null; then
        fail "$1 (could not build the altered map)"; return
    fi
    if holds "$copy" "$2"; then fail "$1"; else pass "$1"; fi
}

neg "a different schema string is refused" "$Q_SCHEMA" \
    '.schema = "shirabe-verification-map/v2"'
neg "a default list missing run-cascade is refused" "$Q_DEFAULT" \
    '.default |= map(select(. != "run-cascade"))'
neg "a check-skill without each is refused" "$Q_SKILLS" \
    '.commands["check-skill"] |= del(.each)'
neg "a check-skill without --changed is refused" "$Q_SKILLS" \
    '.commands["check-skill"].run = ["scripts/check-skill.sh"]'
neg "a networked command without unattended is refused" "$Q_NETWORK" \
    '.commands["net"] = {"run": ["true"], "network": true}'
neg "an entry naming an undefined id is refused" "$Q_IDS" \
    '.entries += [{"paths": ["x/**"], "commands": ["nope"]}]'
neg "a check-skill row without its hosted entry is refused" "$Q_HOSTED" \
    '.commands["check-skill"] |= del(.hosted)'
neg "a hosted job of skill-gate (macos-latest) is refused" "$Q_HOSTED" \
    '.commands["check-skill"].hosted[0].job = "skill-gate (macos-latest)"'
neg "a hosted runs carrying --changed is refused" "$Q_HOSTED" \
    '.commands["check-skill"].hosted[0].runs = "check-skill --changed {skill}"'
neg "a check-skill row that stops running --changed is refused" "$Q_HOSTED" \
    '.commands["check-skill"].run = ["scripts/check-skill.sh"]'

# The positive twin of the network case: setting unattended either way passes.
copy="$WORKDIR/net.json"
if jq '.commands["net"] = {"run": ["true"], "network": true, "unattended": false}' \
        "$MAP" > "$copy" 2>/dev/null && holds "$copy" "$Q_NETWORK"; then
    pass "a networked command with unattended set explicitly is accepted"
else
    fail "a networked command with unattended set explicitly is accepted"
fi

# The schema reference names every field the design lists, and the merge-base
# read.
for field in run each timeout_secs network unattended max_procs entries default build_output always_required; do
    if grep -Fq "\`$field\`" "$REF"; then
        pass "verification-map.md documents \`$field\`"
    else
        fail "verification-map.md documents \`$field\`"
    fi
done
# The optional command field timeout_form, and the two fields each command
# record carries: outcome and suites.
for field in timeout_form outcome suites; do
    if grep -Fq "\`$field\`" "$REF"; then
        pass "verification-map.md documents \`$field\`"
    else
        fail "verification-map.md documents \`$field\`"
    fi
done
for value in passed failed timed-out-limit timed-out-inside SHIRABE_SUITE_SUMMARY; do
    if grep -Fq "\`$value\`" "$REF"; then
        pass "verification-map.md names \`$value\`"
    else
        fail "verification-map.md names \`$value\`"
    fi
done
# hosted is a row of the Command fields table, not only a word the reference
# uses: the field loops above grep for any mention, which prose or an example
# would satisfy. The check runs on a copy with the row removed too, and must
# fail there.
# hosted_row <file>: the file's `### Command fields` section has a table row
# whose first cell is `hosted`.
hosted_row() {
    awk '/^### / { in_cf = ($0 == "### Command fields") }
         in_cf && /^\| `hosted` \|/ { found = 1 }
         END { exit !found }' "$1"
}
if hosted_row "$REF"; then
    pass "verification-map.md's Command fields table has a \`hosted\` row"
else
    fail "verification-map.md's Command fields table has a \`hosted\` row"
fi
grep -v '^| `hosted` |' "$REF" > "$WORKDIR/ref-no-hosted.md"
if hosted_row "$WORKDIR/ref-no-hosted.md"; then
    fail "a copy of the reference without the \`hosted\` row still passes the row check"
else
    pass "a copy of the reference without the \`hosted\` row fails the row check"
fi
if grep -Fq 'or when `hosted` is malformed' "$REF"; then
    pass "verification-map.md says a malformed \`hosted\` does not parse"
else
    fail "verification-map.md says a malformed \`hosted\` does not parse"
fi

if grep -Fq 'git show <merge-base>:.claude/shirabe-extensions/verification-map.json' "$REF" \
        && grep -Fq 'merge-base' "$REF"; then
    pass "verification-map.md documents the read at the merge-base"
else
    fail "verification-map.md documents the read at the merge-base"
fi

# --- hosted twins against their workflows ----------------------------------------------
#
# VERIFICATION=auto lets a `hosted` entry stand in for a local run, so each one
# is held to the workflow it names, for every row that declares one: the
# workflow file exists; it runs on pull requests (an `on:` with pull_request,
# not pull_request_target); it has the job the entry names (`<job>` or
# `<job> (<matrix leg>)`), with no job-level `if:` that keeps it off pull
# requests; and that job's plan runs the same command as `runs`. The plan is
# what the job's step script prints with `--list` (the shape
# scripts/skill-gate.sh has), run in a throwaway repository on a diff that
# selects the row, with the base the job writes to $GITHUB_ENV; `runs`, with
# {skill} filled in for an `each` row, must be one of its lines, and the
# line's first word must name the row's program (scripts/check-skill.sh is
# `check-skill`), which the step script must run.
# verification-hosted-coverage_test.sh holds the declaration to every suite
# the row can select; this is the per-entry check any row with a twin gets.

# twin_workflow_ok <workflow file>: exists and runs on pull requests.
twin_workflow_ok() {
    [ -f "$1" ] || { echo "the workflow $1 does not exist"; return 1; }
    awk '
        /^on:[ ]*pull_request[ ]*$/ { ok = 1 }
        /^on:[ ]*\[/ && /[[ ,]pull_request[] ,]/ { ok = 1 }
        /^[^ #]/ { top = $0 }
        top ~ /^on:[ ]*$/ && /^  pull_request:/ { ok = 1 }
        END { exit !ok }' "$1" && return 0
    echo "$1 has no pull_request trigger"
    return 1
}

# twin_job_block <workflow file> <job id>: the job's lines under `jobs:`.
twin_job_block() {
    awk -v job="$2" '
        /^[^ #]/ { injobs = ($0 ~ /^jobs:/); cur = ""; next }
        injobs && /^  [A-Za-z0-9_-]+:/ { cur = $1; sub(/:.*/, "", cur); next }
        injobs && cur == job { print }
    ' "$1"
}

# twin_job_ok <workflow file> <job name>: the job exists, its leg is in its
# matrix, and no job-level `if:` keeps it off pull requests.
twin_job_ok() {
    local id leg block cond
    case "$2" in
        *" ("*")") id=${2%% (*}; leg=${2#* (}; leg=${leg%)} ;;
        *) id=$2; leg="" ;;
    esac
    block=$(twin_job_block "$1" "$id")
    [ -n "$block" ] || { echo "$1 has no job $id"; return 1; }
    if [ -n "$leg" ]; then
        case "$block" in *"$leg"*) ;; *) echo "job $id's matrix doesn't name $leg"; return 1 ;; esac
    fi
    cond=$(printf '%s\n' "$block" | sed -n 's/^    if:[ ]*//p')
    case "$cond" in
        "") ;;
        *event_name*"== 'pull_request'"*|*'event_name == "pull_request"'*) ;;
        *event_name*) echo "job $id's if: [$cond] can keep it off pull requests"; return 1 ;;
    esac
    return 0
}

# twin_plan_ok <workflow file> <job name> <runs> <row id>: the job's step
# script prints `runs` in its plan for a diff that selects the row, and the
# line names the row's program, which the script runs.
twin_plan_ok() {
    local wf="$1" job="$2" runs="$3" row="$4" id block planner envname prog word glob path each leaf want plan fix
    id=${job%% (*}
    block=$(twin_job_block "$wf" "$id")
    planner=""
    while IFS= read -r p; do
        [ -n "$p" ] && [ -f "$ROOT/$p" ] && { planner=$p; break; }
    done <<EOF
$(printf '%s\n' "$block" | sed -n -E 's/^ +run: (bash )?([A-Za-z0-9_.\/-]+\.sh)[ ]*$/\2/p')
EOF
    [ -n "$planner" ] || { echo "job $id has no step that runs a script of this repository"; return 1; }
    envname=$(sed -n -E 's/^ +echo "([A-Z_][A-Z0-9_]*)=.*>> "\$GITHUB_ENV".*/\1/p' <<<"$block")
    envname=${envname%%$'\n'*}
    prog=$(jq -r --arg id "$row" '.commands[$id].run[0]' "$MAP")
    word=${runs%% *}
    [ "$word" = "$(basename "$prog" .sh)" ] \
        || { echo "runs [$runs] starts with [$word], which doesn't name the row's program $prog"; return 1; }
    grep -qF "$prog" "$ROOT/$planner" \
        || { echo "$planner never runs $prog"; return 1; }
    # A concrete path for the first glob of the first entry that selects the row.
    glob=$(jq -r --arg id "$row" '[.entries[] | select(.commands | index([$id]))][0].paths[0] // empty' "$MAP")
    [ -n "$glob" ] || { echo "no map entry selects $row"; return 1; }
    path=$(printf '%s' "$glob" | sed -e 's#\*\*#probe/x#g' -e 's#\*#probe#g')
    want=$runs
    each=$(jq -r --arg id "$row" '.commands[$id].each // empty' "$MAP")
    if [ -n "$each" ]; then
        leaf=$(printf '%s' "$each" | sed -e 's#\*#probe#g')
        leaf=${leaf##*/}
        want=$(printf '%s' "$runs" | sed "s/[{]skill[}]/$leaf/g")
    fi
    fix="$WORKDIR/twin-plan.$$.$RANDOM"
    mkdir -p "$fix/$(dirname "$planner")" "$fix/$(dirname "$path")" || return 1
    cp "$ROOT/$planner" "$fix/$planner" || return 1
    (
        cd "$fix" || exit 1
        git init -q . && git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
            commit -q --allow-empty -m base || exit 1
        base=$(git rev-parse HEAD) || exit 1
        echo probe > "$path"
        git add -A && git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
            commit -q -m probe || exit 1
        if [ -n "$envname" ]; then
            env "$envname=$base" bash "$planner" --list
        else
            bash "$planner" --list
        fi
    ) > "$fix.plan" 2>"$fix.err" || { echo "$planner --list failed: $(head -c 300 "$fix.err")"; return 1; }
    plan=$(cat "$fix.plan")
    grep -Fxq -- "$want" "$fix.plan" && return 0
    echo "the plan of job $id for a change to $path is [$plan], with no line [$want]"
    return 1
}

twin_expect() { # twin_expect <label> <command...>
    local label="$1" msg
    shift
    if msg=$("$@"); then pass "$label"; else fail "$label: $msg"; fi
}
twin_refused() { # twin_refused <label> <fragment> <command...>
    local label="$1" want="$2" msg
    shift 2
    if msg=$("$@"); then
        fail "$label: the check passed"
    else
        case "$msg" in *"$want"*) pass "$label" ;; *) fail "$label: said [$msg], not [$want]" ;; esac
    fi
}

TWIN_ROWS=$(jq -r '.commands | to_entries[] | select(.value | has("hosted")) | .key' "$MAP")
[ -n "$TWIN_ROWS" ] && pass "the map declares hosted twins on: $(printf '%s ' $TWIN_ROWS)" \
    || fail "the map declares no hosted twin"
for row in $TWIN_ROWS; do
    n=$(jq -r --arg id "$row" '.commands[$id].hosted | length' "$MAP")
    i=0
    while [ "$i" -lt "$n" ]; do
        wf=$(jq -r --arg id "$row" --argjson i "$i" '.commands[$id].hosted[$i].workflow' "$MAP")
        job=$(jq -r --arg id "$row" --argjson i "$i" '.commands[$id].hosted[$i].job' "$MAP")
        runs=$(jq -r --arg id "$row" --argjson i "$i" '.commands[$id].hosted[$i].runs' "$MAP")
        twin_expect "$row: $wf exists and runs on pull requests" twin_workflow_ok "$ROOT/$wf"
        twin_expect "$row: $wf has job [$job], not kept off pull requests" twin_job_ok "$ROOT/$wf" "$job"
        twin_expect "$row: job [$job]'s plan runs [$runs]" twin_plan_ok "$ROOT/$wf" "$job" "$runs" "$row"
        i=$((i + 1))
    done
done

# Negative cases, on the first twin: altered copies of its workflow, and
# altered entries.
T_ROW=${TWIN_ROWS%%$'\n'*}
if [ -n "$T_ROW" ]; then
    T_WF=$(jq -r --arg id "$T_ROW" '.commands[$id].hosted[0].workflow' "$MAP")
    T_JOB=$(jq -r --arg id "$T_ROW" '.commands[$id].hosted[0].job' "$MAP")
    T_RUNS=$(jq -r --arg id "$T_ROW" '.commands[$id].hosted[0].runs' "$MAP")
    twin_refused "negative: a workflow file that doesn't exist fails" "does not exist" \
        twin_workflow_ok "$ROOT/.github/workflows/no-such-workflow.yml"
    awk '/^[^ #]/ { top = $0 } top ~ /^on:/ && /^  pull_request:/ { skip = 1; next }
         skip && /^    / { next } { skip = 0; print }' "$ROOT/$T_WF" > "$WORKDIR/no-pr.yml"
    twin_refused "negative: a workflow without its pull_request trigger fails" "no pull_request trigger" \
        twin_workflow_ok "$WORKDIR/no-pr.yml"
    printf 'on:\n  pull_request_target:\njobs: {}\n' > "$WORKDIR/prt.yml"
    twin_refused "negative: pull_request_target is not a pull_request trigger" "no pull_request trigger" \
        twin_workflow_ok "$WORKDIR/prt.yml"
    twin_refused "negative: a job the workflow doesn't have fails" "has no job" \
        twin_job_ok "$ROOT/$T_WF" "no-such-job (ubuntu-latest)"
    twin_refused "negative: a leg the job's matrix doesn't name fails" "doesn't name" \
        twin_job_ok "$ROOT/$T_WF" "${T_JOB%% (*} (windows-latest)"
    awk -v id="  ${T_JOB%% (*}:" '{ print } $0 == id { print "    if: github.event_name == '\''push'\''" }' \
        "$ROOT/$T_WF" > "$WORKDIR/push-only.yml"
    twin_refused "negative: a job kept to push events by its if: fails" "keep it off pull requests" \
        twin_job_ok "$WORKDIR/push-only.yml" "$T_JOB"
    twin_refused "negative: a runs naming another program fails" "doesn't name the row's program" \
        twin_plan_ok "$ROOT/$T_WF" "$T_JOB" "other-check {skill}" "$T_ROW"
    twin_refused "negative: a runs line the plan doesn't print fails" "with no line" \
        twin_plan_ok "$ROOT/$T_WF" "$T_JOB" "${T_RUNS%% *} --changed {skill}" "$T_ROW"
fi

# --- always_required against its workflows ----------------------------------------------
#
# always_required turns ci_monitor's relevant-checks wait on, and each entry
# is a check the run waits on whatever the change touches. So the key is a
# row of the top-level table, CI_WAIT=all is documented as the opt-out, and
# shirabe's list is held to its workflows: well formed, the public-content
# check (the one that guards what a public repository ships) among them, and
# each entry a job of a workflow that runs on every pull request. A paths:
# filter on the trigger is refused: such a workflow reports nothing on a
# change outside its paths, and the run would wait for a check that never
# comes.

Q_ALWAYS='(.always_required | type) == "array" and (.always_required | length) > 0
    and (.always_required | all(type == "object" and (keys == ["job", "workflow"])
        and all(.workflow, .job; type == "string" and . != "")
        and (.workflow | startswith(".github/workflows/") and (split("/") | all(. != ".." and . != "." and . != "")))))'
Q_ALWAYS_SECURITY='any(.always_required[]; . == {"workflow": ".github/workflows/check-public-content.yml", "job": "shipped-paths"})'
check "always_required is a non-empty list of {workflow, job} under .github/workflows/" "$Q_ALWAYS"
check "always_required holds the public-content check" "$Q_ALWAYS_SECURITY"
neg "an always_required entry without a job is refused" "$Q_ALWAYS" '.always_required[0] |= del(.job)'
neg "an always_required workflow outside .github/workflows/ is refused" "$Q_ALWAYS" \
    '.always_required[0].workflow = "scripts/x.yml"'
neg "an always_required that isn't an array is refused" "$Q_ALWAYS" '.always_required = {}'
neg "an always_required without the public-content check is refused" "$Q_ALWAYS_SECURITY" \
    '.always_required |= map(select(.workflow != ".github/workflows/check-public-content.yml"))'

# always_row <file>: the reference's `## The file` table has an
# `always_required` row.
always_row() {
    awk '/^## / { in_f = ($0 == "## The file") }
         in_f && /^\| `always_required` \|/ { found = 1 }
         END { exit !found }' "$1"
}
if always_row "$REF"; then
    pass "verification-map.md's top-level table has an \`always_required\` row"
else
    fail "verification-map.md's top-level table has an \`always_required\` row"
fi
grep -v '^| `always_required` |' "$REF" > "$WORKDIR/ref-no-always.md"
if always_row "$WORKDIR/ref-no-always.md"; then
    fail "a copy of the reference without the \`always_required\` row still passes the row check"
else
    pass "a copy of the reference without the \`always_required\` row fails the row check"
fi
if grep -Fq '**`CI_WAIT=all`**' "$REF" && grep -Fq -- '--ci-wait=all' "$REF"; then
    pass "verification-map.md documents CI_WAIT=all and --ci-wait=all"
else
    fail "verification-map.md documents CI_WAIT=all and --ci-wait=all"
fi

# always_unfiltered <workflow file>: its pull_request trigger has no paths:
# or paths-ignore: filter.
always_unfiltered() {
    awk '/^[^ #]/ { top = $0; inpr = 0 }
         top ~ /^on:/ && /^  [a-z_]+:/ { inpr = ($0 ~ /^  pull_request:/) }
         top ~ /^on:/ && inpr && /^    paths(-ignore)?:/ { bad = 1 }
         END { exit bad }' "$1" && return 0
    echo "$1 filters its pull_request trigger by paths, so it doesn't report on every pull request"
    return 1
}

n=$(jq -r '.always_required // [] | length' "$MAP")
i=0
while [ "$i" -lt "$n" ]; do
    wf=$(jq -r --argjson i "$i" '.always_required[$i].workflow' "$MAP")
    job=$(jq -r --argjson i "$i" '.always_required[$i].job' "$MAP")
    twin_expect "always_required: $wf exists and runs on pull requests" twin_workflow_ok "$ROOT/$wf"
    twin_expect "always_required: $wf has job [$job], not kept off pull requests" twin_job_ok "$ROOT/$wf" "$job"
    twin_expect "always_required: $wf runs on every pull request, with no paths filter" always_unfiltered "$ROOT/$wf"
    i=$((i + 1))
done
twin_refused "negative: a workflow filtered by paths can't be always required" "filters its pull_request trigger" \
    always_unfiltered "$ROOT/.github/workflows/check-pipe-readers.yml"
printf 'on:\n  pull_request:\n    paths-ignore:\n      - docs/**\njobs: {}\n' > "$WORKDIR/ignore.yml"
twin_refused "negative: a paths-ignore filter is refused too" "filters its pull_request trigger" \
    always_unfiltered "$WORKDIR/ignore.yml"
printf 'on:\n  pull_request:\n    types: [opened]\n  push:\n    paths:\n      - x/**\njobs: {}\n' > "$WORKDIR/push-paths.yml"
twin_expect "a paths filter on push alone leaves the pull_request trigger unfiltered" \
    always_unfiltered "$WORKDIR/push-paths.yml"

# work-on.md points at the map and lists no commands of its own.
n=$(grep -c 'verification-map.json' "$EXT")
if [ "$n" -ge 1 ]; then
    pass "work-on.md names verification-map.json"
else
    fail "work-on.md names verification-map.json (count $n)"
fi
n=$(grep -c 'cargo test' "$EXT")
if [ "$n" -eq 0 ]; then
    pass "work-on.md lists no commands (no cargo test)"
else
    fail "work-on.md lists no commands (cargo test appears $n times)"
fi

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
