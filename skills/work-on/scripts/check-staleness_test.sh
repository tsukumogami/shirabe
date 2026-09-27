#!/usr/bin/env bash
# check-staleness_test.sh -- does check-staleness.sh reach the right verdict,
# carry it in the right exit status, and refuse to guess?
#
# `gh` is a stub on PATH that serves canned issue and milestone JSON chosen by
# environment variables and appends one line per call to a counter file, so the
# cases exercise the script's logic rather than the network. A throwaway git
# repository supplies files with and without commits since a chosen date. Dates
# are computed relative to now with jq, the same way the script computes age,
# so the cases hold on any day and on both GNU and BSD userlands.
#
# What the stub cannot cover is the shape of the real `gh` invocations: if
# `gh issue list --milestone ...` stopped accepting those flags, these cases
# still pass. The invocations match `gh`'s documented flags and were run
# against GitHub when the script was written.
#
# Usage: check-staleness_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-staleness.sh"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

for tool in jq git; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$CHECK" ] || { echo "$CHECK is not executable" >&2; exit 2; }

TMPS=()
# The trailing `return 0` keeps an EXIT trap from replacing the script's status
# when TMPS is empty; see closing-keyword-gate_test.sh for the measurement.
# Sessions the engine cases open are removed here, so an interrupted run leaves
# none behind. The cases open them inside command substitutions, whose array
# appends never reach this shell, so the names go to a file instead. Each
# session ends at a terminal or holds in staleness_check, and
# `koto session cleanup` removes either, where `koto cancel` refuses a
# finished one.
SESSIONS_FILE=""
cleanup() {
    if [ -n "$SESSIONS_FILE" ] && [ -f "$SESSIONS_FILE" ]; then
        while IFS= read -r s; do
            [ -n "$s" ] && koto session cleanup "$s" >/dev/null 2>&1
        done < "$SESSIONS_FILE"
    fi
    for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done
    return 0
}
trap cleanup EXIT

WORK=$(mktemp -d); TMPS+=("$WORK")
SESSIONS_FILE="$WORK/sessions"

# iso_days_ago <n> -- an ISO-8601 UTC timestamp n days before now.
iso_days_ago() { jq -nr --argjson n "$1" '(now - ($n * 86400)) | floor | todate'; }

# --- The gh stub -------------------------------------------------------------

STUB_DIR="$WORK/stub"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Stands in for gh issue view / gh issue list. One line per call to $GH_CALLS.
printf '%s\n' "$*" >> "${GH_CALLS:-/dev/null}"
case "$1 $2" in
    "issue view")
        if [ "${GH_FAIL_VIEW:-0}" = "1" ]; then
            printf '%s\n' "${GH_VIEW_STDERR:-HTTP 401: Bad credentials}" >&2
            exit 1
        fi
        printf '%s\n' "$STUB_ISSUE"
        ;;
    "issue list")
        case " $* " in
            *" --state closed "*)
                [ "${GH_FAIL_CLOSED:-0}" = "1" ] && { echo "HTTP 502" >&2; exit 1; }
                printf '%s\n' "${STUB_CLOSED:-[]}" ;;
            *" --state open "*)
                [ "${GH_FAIL_OPEN:-0}" = "1" ] && { echo "HTTP 502" >&2; exit 1; }
                printf '%s\n' "${STUB_OPEN:-[]}" ;;
            *) echo "stub: unexpected list call" >&2; exit 1 ;;
        esac
        ;;
    *) echo "stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$STUB_DIR/gh"

# A git wrapper that logs its arguments and runs the real git, so a case can
# assert what the script handed to git log.
REAL_GIT=$(command -v git)
GITLOG_DIR="$WORK/gitlog"
mkdir -p "$GITLOG_DIR"
cat > "$GITLOG_DIR/git" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${GIT_CALLS:-/dev/null}"
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$GITLOG_DIR/git"

# --- The repository fixture --------------------------------------------------

REPO="$WORK/repo"
mkdir -p "$REPO/src"
(
    cd "$REPO" || exit 1
    git init -q .
    git config user.email test@example.com
    git config user.name test
    OLD=$(iso_days_ago 60)
    echo old > src/old.go
    GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git add src/old.go
    GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD" git commit -q -m old
    echo new > src/new.go
    git add src/new.go
    git commit -q -m new
) || { echo "could not build the fixture repository" >&2; exit 2; }
# A file outside the repository that a body can name with `..`; it exists, so
# only the path filter keeps it from reaching git.
echo outside > "$WORK/outside.go"

# issue_json <days-old> <milestone-title-or-empty> <body>
issue_json() {
    jq -nc --arg created "$(iso_days_ago "$1")" --arg m "$2" --arg body "$3" \
        '{number: 7, title: "a title", createdAt: $created, body: $body,
          milestone: (if $m == "" then null else {title: $m} end)}'
}

# run_check [env assignments...] -- runs the script from the fixture repo with
# the stub first on PATH; sets OUT, RC, CALLS.
run_check() {
    local calls="$WORK/calls.$$.$RANDOM"
    : > "$calls"
    OUT=$(cd "$REPO" && env PATH="$STUB_DIR:$PATH" GH_CALLS="$calls" "$@" "$CHECK" --issue 7 2>/dev/null)
    RC=$?
    CALLS=$(wc -l < "$calls" | tr -d ' ')
}

expect_rc() {
    local label="$1" want="$2"
    if [ "$RC" = "$want" ]; then pass "$label (exit $RC)"; else fail "$label: want exit $want, got $RC; stdout: $OUT"; fi
}

expect_json() {
    local label="$1" filter="$2"
    if printf '%s' "$OUT" | jq -e "$filter" >/dev/null 2>&1; then pass "$label"; else fail "$label: '$filter' false on: $OUT"; fi
}

echo "== verdicts =="

run_check STUB_ISSUE="$(issue_json 2 '' 'Nothing to see; see `src/old.go`.')"
expect_rc "fresh issue is fresh" 0
expect_json "fresh verdict and reason" '.verdict == "fresh" and .introspection_recommended == false and .reason == "no staleness signals detected"'
expect_json "fresh report carries every signal" '.signals | has("issue_age_days") and has("age_threshold_days") and has("sibling_issues_closed_since_creation") and has("milestone_position") and has("files_modified_since_creation")'
expect_json "fresh report carries the issue" '.issue.number == 7 and .issue.milestone == null'
if [ "$CALLS" -eq 1 ]; then pass "no milestone: one gh call"; else fail "no milestone: want 1 gh call, got $CALLS"; fi

run_check STUB_ISSUE="$(issue_json 30 '' '')"
expect_rc "age over threshold alone is stale" 1
expect_json "age reason" '.verdict == "stale" and (.reason | test("30 days old")) and .signals.issue_age_days == 30'

run_check STUB_ISSUE="$(issue_json 14 '' '')"
expect_rc "age at the threshold is fresh" 0

CLOSED_AFTER=$(jq -nc --arg d "$(iso_days_ago 1)" '[{number: 1, closedAt: $d}]')
CLOSED_BEFORE=$(jq -nc --arg d "$(iso_days_ago 20)" '[{number: 1, closedAt: $d}]')
TWO_OPEN='[{"number":7},{"number":8}]'
THREE_OPEN='[{"number":7},{"number":8},{"number":9}]'

# The sibling signal can't fire alone: a closed sibling means the position is
# no longer "first", so the position signal fires with it (the signals
# reference says so). This case pins the sibling count and its reason; the
# position cases below use a sibling closed BEFORE creation to isolate
# position.
run_check STUB_ISSUE="$(issue_json 5 'M1' '')" STUB_CLOSED="$CLOSED_AFTER" STUB_OPEN="$TWO_OPEN"
expect_rc "a sibling closed since creation is stale" 1
expect_json "sibling signal and its reason" '.signals.sibling_issues_closed_since_creation == 1 and (.reason | test("1 sibling issues closed since creation"))'
if [ "$CALLS" -le 3 ]; then pass "milestone run: at most three gh calls ($CALLS)"; else fail "milestone run: $CALLS gh calls, want at most 3"; fi

run_check STUB_ISSUE="$(issue_json 5 'M1' '')" STUB_CLOSED='[]' STUB_OPEN="$TWO_OPEN"
expect_rc "first in milestone, nothing else, is fresh" 0
expect_json "position first" '.signals.milestone_position == "first" and .issue.milestone == "M1"'

run_check STUB_ISSUE="$(issue_json 5 'M1' '')" STUB_CLOSED="$CLOSED_BEFORE" STUB_OPEN="$THREE_OPEN"
expect_rc "middle position alone is stale" 1
expect_json "position middle, no sibling after creation" '.signals.milestone_position == "middle" and .signals.sibling_issues_closed_since_creation == 0'

run_check STUB_ISSUE="$(issue_json 5 'M1' '')" STUB_CLOSED="$CLOSED_BEFORE" STUB_OPEN='[{"number":7}]'
expect_rc "last position alone is stale" 1
expect_json "position last" '.signals.milestone_position == "last"'

run_check STUB_ISSUE="$(issue_json 5 '' 'Touches `src/new.go` and src/old.go.')"
expect_rc "a referenced file modified since creation is stale" 1
expect_json "modified file listed, unmodified one not" '.signals.files_modified_since_creation == ["src/new.go"]'

echo "== unavailable =="

run_check STUB_ISSUE="$(issue_json 2 '' '')" GH_FAIL_VIEW=1
expect_rc "gh issue view failing is unavailable" 3
expect_json "unavailable verdict names gh" '.verdict == "unavailable" and (.reason | test("gh issue view failed"))'

run_check STUB_ISSUE="$(issue_json 2 '' '')" GH_FAIL_VIEW=1 GH_VIEW_STDERR="token ghp_abcdefghijklmnop rejected"
expect_rc "token-shaped stderr is still unavailable" 3
if printf '%s' "$OUT" | grep -q 'ghp_'; then fail "token-shaped stderr reached the report: $OUT"; else pass "token-shaped stderr withheld from the report"; fi

run_check STUB_ISSUE="$(issue_json 2 'M1' '')" GH_FAIL_CLOSED=1
expect_rc "closed milestone list failing is unavailable" 3
run_check STUB_ISSUE="$(issue_json 2 'M1' '')" STUB_CLOSED='[]' GH_FAIL_OPEN=1
expect_rc "open milestone list failing is unavailable" 3

NOJQ="$WORK/nojq"
mkdir -p "$NOJQ"
ln -s "$STUB_DIR/gh" "$NOJQ/gh"
ln -s "$REAL_GIT" "$NOJQ/git"
OUT=$(cd "$REPO" && PATH="$NOJQ" "$BASH" "$CHECK" --issue 7 2>/dev/null); RC=$?
expect_rc "no jq on PATH is unavailable" 3
if printf '%s' "$OUT" | grep -q '"reason":"jq not found"'; then pass "no-jq report names jq"; else fail "no-jq report: $OUT"; fi

NOTREPO="$WORK/notrepo"
mkdir -p "$NOTREPO/src"
echo x > "$NOTREPO/src/new.go"
OUT=$(cd "$NOTREPO" && PATH="$STUB_DIR:$PATH" STUB_ISSUE="$(issue_json 2 '' 'see `src/new.go`')" "$CHECK" --issue 7 2>/dev/null); RC=$?
expect_rc "git log failing on a referenced file is unavailable" 3

echo "== path filtering =="

GIT_CALLS="$WORK/gitcalls"
: > "$GIT_CALLS"
OUT=$(cd "$REPO" && PATH="$GITLOG_DIR:$STUB_DIR:$PATH" GIT_CALLS="$GIT_CALLS" \
    STUB_ISSUE="$(issue_json 2 '' 'see `../outside.go` and `/etc/hosts.json` and `src/old.go`')" \
    "$CHECK" --issue 7 2>/dev/null); RC=$?
expect_rc "a body naming paths outside the tree still gets a verdict" 0
if grep -E -- '-- (/|\.\./|.*/\.\./)' "$GIT_CALLS" >/dev/null; then
    fail "an absolute or .. path reached git: $(cat "$GIT_CALLS")"
elif grep -q -- '-- src/old.go' "$GIT_CALLS"; then
    pass "only in-tree paths reached git log"
else
    fail "the in-tree path never reached git log: $(cat "$GIT_CALLS")"
fi

echo "== usage =="

for args in "7" "" "--issue" "--issue abc" "--issue 0" "--issue 7 extra" "--number 7"; do
    # shellcheck disable=SC2086
    OUT=$(cd "$REPO" && PATH="$STUB_DIR:$PATH" "$CHECK" $args 2>/dev/null); RC=$?
    if [ "$RC" = 2 ] && [ -z "$OUT" ]; then
        pass "usage error for '$args' (exit 2, empty stdout)"
    else
        fail "usage for '$args': want exit 2 and empty stdout, got $RC and '$OUT'"
    fi
done

echo "== the gate =="

# The gate command, read out of the shipped template rather than copied here:
# the `command:` line under staleness_fresh, unquoted from its YAML
# single-quoted scalar. {{PLUGIN_ROOT}} and {{ISSUE_NUMBER}} are substituted the
# way koto substitutes them, and the result runs under `sh -c` from the working
# repository, as koto runs a gate.
TEMPLATE="$SCRIPT_DIR/../koto-templates/work-on.md"
PLUGIN_ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
GATE=$(awk '
    /^      staleness_fresh:$/ { found=1 }
    found && /^        command:/ {
        sub(/^        command:[[:space:]]*/, "")
        sub(/^'"'"'/, ""); sub(/'"'"'$/, "")
        print
        exit
    }
' "$TEMPLATE")
[ -n "$GATE" ] || { echo "could not read the staleness_fresh gate command from $TEMPLATE" >&2; exit 2; }

# run_gate <plugin-root> <extra-path-dir> [env assignments...] -- sets RC.
run_gate() {
    local root="$1" extra="$2"; shift 2
    local cmd="${GATE//\{\{PLUGIN_ROOT\}\}/$root}"
    cmd="${cmd//\{\{ISSUE_NUMBER\}\}/7}"
    (cd "$REPO" && env PATH="$extra:$STUB_DIR:$PATH" "$@" sh -c "$cmd" >/dev/null 2>&1)
    RC=$?
}

gate_expect() {
    if [ "$RC" = "$2" ]; then pass "$1 (exit $RC)"; else fail "$1: want exit $2, got $RC"; fi
}

run_gate "$PLUGIN_ROOT_DIR" "" STUB_ISSUE="$(issue_json 2 '' '')"
gate_expect "gate passes on a fresh issue" 0
run_gate "$PLUGIN_ROOT_DIR" "" STUB_ISSUE="$(issue_json 30 '' '')"
gate_expect "gate fails with the stale status on a stale issue" 1
run_gate "" "" STUB_ISSUE="$(issue_json 2 '' '')"
gate_expect "gate with an empty PLUGIN_ROOT is unavailable, not stale" 3
run_gate "$PLUGIN_ROOT_DIR" "" STUB_ISSUE="$(issue_json 2 '' '')" GH_FAIL_VIEW=1
gate_expect "gate with gh failing is unavailable" 3

# A same-named script first on PATH that rejects --issue, as a separately
# installed one did. The gate must not reach it.
DECOY="$WORK/decoy"
mkdir -p "$DECOY"
cat > "$DECOY/check-staleness.sh" <<'STUB'
#!/usr/bin/env bash
echo "unknown option: $1" >&2
exit 1
STUB
chmod +x "$DECOY/check-staleness.sh"
run_gate "$PLUGIN_ROOT_DIR" "$DECOY" STUB_ISSUE="$(issue_json 2 '' '')"
gate_expect "a same-named script on PATH that rejects --issue doesn't change a fresh result" 0

echo "== the state, driven through koto =="

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH; the staleness_check routing cannot be driven without the engine"
else
    # The shipped staleness_check block, with its gate command replaced by a
    # fixed exit so each case controls the gate's result. `start` stands in for
    # the setup state that routes here; the targets are stub terminals, since
    # these cases are about which one the run lands on.
    BLOCK=$(awk '
        $0 == "  staleness_check:" { found=1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found { print }
    ' "$TEMPLATE")
    [ -n "$BLOCK" ] || { echo "staleness_check not found in $TEMPLATE" >&2; exit 2; }

    # drive <exit-or-timeout> <evidence-json> [block] -- prints the state the
    # run is in after one submission. `timeout` makes the gate outlive a
    # 1-second limit so koto reports exit_code -1. [block] replaces the shipped
    # block, for the mutation control below.
    drive() {
        local how="$1" data="$2" block="${3:-$BLOCK}" dir session cmd timeout_line=""
        dir=$(mktemp -d); TMPS+=("$dir")
        session="staleness-state-$$-$RANDOM"
        if [ "$how" = timeout ]; then
            cmd='sleep 5'; timeout_line='        timeout: 1'
        else
            cmd="exit $how"
        fi
        {
            printf '%s\n' '---' 'name: staleness-check-fixture' 'version: "1.0"' \
                'description: Fixture driving the shipped staleness_check state.' \
                'initial_state: start' 'variables:' '  ISSUE_NUMBER:' \
                '    description: Issue under test' '    required: false' \
                '  PLUGIN_ROOT:' '    description: Plugin root' '    required: false' \
                'states:' '  start:' '    transitions:' '      - target: staleness_check'
            printf '%s\n' "$block" | awk -v cmd="$cmd" -v tl="$timeout_line" '
                /^        command:/ { print "        command: \"" cmd "\""; if (tl != "") print tl; next }
                { print }'
            printf '%s\n' '  analysis:' '    terminal: true' '  introspection:' '    terminal: true' \
                '  done_blocked:' '    terminal: true' '    failure: true' '    accepts:' \
                '      failure_reason:' '        type: string' '---' '' \
                '## start' 'Start.' '## staleness_check' 'Submit staleness_signal.' \
                '## analysis' 'Analysis.' '## introspection' 'Introspection.' '## done_blocked' 'Blocked.'
        } > "$dir/fixture.md"
        koto init "$session" --template "$dir/fixture.md" --var ISSUE_NUMBER=7 >/dev/null 2>&1 || { echo "init-failed"; return; }
        printf '%s\n' "$session" >> "$SESSIONS_FILE"
        koto next "$session" >/dev/null 2>&1
        koto next "$session" --with-data "$data" 2>/dev/null | jq -r '.state // "none"'
    }

    # The full matrix: every evidence value against every gate result, 25
    # cells. `fresh` routes only on a passing gate and `unavailable` only on 3
    # or -1; anywhere else each stays in staleness_check. The other three route
    # whatever the gate said, which is what the directive tells the agent.
    expected() {
        case "$1:$2" in
            fresh:0) echo analysis ;;
            fresh:*) echo staleness_check ;;
            unavailable:3|unavailable:timeout) echo analysis ;;
            unavailable:*) echo staleness_check ;;
            stale_requires_introspection:*) echo introspection ;;
            override:*) echo analysis ;;
            blocked:*) echo done_blocked ;;
        esac
    }

    for signal in fresh stale_requires_introspection unavailable override blocked; do
        data="{\"staleness_signal\":\"$signal\",\"detail\":\"case detail\"}"
        for how in 0 1 2 3 timeout; do
            want=$(expected "$signal" "$how")
            got=$(drive "$how" "$data")
            label="$signal on gate result $how"
            [ "$how" = timeout ] && label="$signal on gate result -1 (timeout)"
            if [ "$got" = "$want" ]; then pass "$label -> $got"; else fail "$label: want $want, got $got"; fi
        done
    done

    # The mutation control: the shipped block with a trailing unconditional
    # edge put back, the shape this change removed. Under it, `unavailable` on
    # a passing gate falls through to analysis, which is the defect; this
    # proves the matrix cell `unavailable on gate result 0 -> staleness_check`
    # above would catch the edge coming back rather than passing either way.
    MUTANT=$(printf '%s\n%s\n' "$BLOCK" '      - target: analysis')
    got=$(drive 0 '{"staleness_signal":"unavailable","detail":"case detail"}' "$MUTANT")
    if [ "$got" = analysis ]; then
        pass "mutation control: with the trailing edge restored, unavailable on a passing gate reaches analysis"
    else
        fail "mutation control: expected the restored trailing edge to route unavailable on 0 to analysis, got $got"
    fi
fi

echo
echo "check-staleness: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
