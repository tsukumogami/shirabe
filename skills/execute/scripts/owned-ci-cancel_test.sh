#!/usr/bin/env bash
# owned-ci-cancel_test.sh -- does /execute's ci_monitor follow the run's PR
# past its merge, and pass a MERGED PR's cancelled macOS floor checks and
# nothing else?
# Part of the execute skill
#
# Since #950, closing a pull request cancels its unfinished macOS floor runs.
# /work-on's ci_passing passes a MERGED PR whose only non-green checks are
# those cancels through skills/work-on/scripts/ci-cancel-after-merge.sh
# (#952). /execute's owned_ci_passing reaches the same script with
# `--owned <owned-pr.sh arguments>` (#958), so the rule has one copy, and
# its ci_monitor gates look the PR up with owned-pr.sh's
# `--state open-else-merged`, so a MERGED PR is still the run's PR. The
# fourth gate, owned_pr_merged, answers whether that PR has merged (#917).
#
# Two parts:
#
#   script   ci-cancel-after-merge.sh --owned, against the real owned-pr.sh,
#            in a throwaway git repository whose floor script is a stub
#   wiring   owned_ci_passing, owned_merge_state_clean, monitor_owned_pr and
#            owned_pr_merged EXTRACTED FROM execute.md, with {{PLUGIN_ROOT}}
#            and {{PLAN_SLUG}} substituted as koto would, so what ships is
#            what runs
#
# gh and koto are stubs on PATH, so no case reaches GitHub or a real session.
# The gh stub serves per-PR fixture JSON and applies `--jq` with jq, as gh
# does, so the scripts' own filters decide. The answers it stands in for were
# read from GitHub on #957 and #950, both MERGED with cancelled floor checks:
# mergeStateStatus is UNKNOWN on a MERGED PR, and each check's link is
# .../actions/runs/<id>/job/<id>.
#
# /work-on's own path through the script is pinned, unchanged, by
# skills/work-on/scripts/ci-cancel-after-merge_test.sh.
#
# Usage: owned-ci-cancel_test.sh
# Exit codes: 0 all pass, 1 any failed.
#
# Bash 3.2: no associative arrays, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
TEMPLATE="$REPO_ROOT/skills/execute/koto-templates/execute.md"
FALLBACK="$REPO_ROOT/skills/work-on/scripts/ci-cancel-after-merge.sh"

# shellcheck source=../../../scripts/lib/koto-gates.sh
. "$REPO_ROOT/scripts/lib/koto-gates.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

command -v jq >/dev/null || { echo "owned-ci-cancel_test: jq is required" >&2; exit 1; }
command -v git >/dev/null || { echo "owned-ci-cancel_test: git is required" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/owned-ci-cancel-test.XXXXXX") || exit 1
# The trailing `return 0` keeps the trap's status from replacing the script's.
cleanup() { rm -rf "$T"; return 0; }
ktg_on_exit cleanup

R=acme/widgets
REPO_URL="https://github.com/$R"
RUN="$REPO_URL/actions/runs"
ME=octo
MINE=0123456789abcdef0123456789abcdef
OTHER=fedcba9876543210fedcba9876543210
BRANCH=impl/x
FIX="$T/fixture"

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

mkdir -p "$T/bin" || exit 1

# gh:
#   api user                          {"login": $ME}
#   api repos/<R>                     its default branch, main
#   api repos/<R>/actions/runs/<id>   the run's path, from $FIX/runs
#                                     (`<repo> <id> <path>` lines), else a 404
#   pr list --state <s>               $FIX/prs.json, filtered by state as gh
#                                     does (open, merged, closed, all)
#   pr view <url> / pr checks <url>   $FIX/view-<n>.json / checks-<n>.json for
#                                     the PR number the URL ends in
# --jq is applied with jq. Every call is logged to $FIX/gh.log.
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
FIX="${GH_FIXTURE:?}"
echo "$*" >> "$FIX/gh.log"
jqf=""
state=open
prev=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jqf="$a"
    [ "$prev" = "--state" ] && state="$a"
    prev="$a"
done
out() {
    if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi
}
pr_file() {
    local n="${3##*/}"
    case "$n" in ''|*[!0-9]*) echo "gh stub: $1 $2 needs a PR URL, got [$3]" >&2; exit 1 ;; esac
    [ -f "$FIX/$4-$n.json" ] || { echo "gh stub: no $4 fixture for #$n" >&2; exit 1; }
    out < "$FIX/$4-$n.json"
}
case "$1 ${2:-}" in
    "api user") echo "{\"login\": \"${GH_LOGIN:-octo}\"}" | out ;;
    "api repos/"*/actions/runs/*)
        path="${2#repos/}"
        repo="${path%/actions/runs/*}"
        id="${path##*/}"
        line=$(grep -E "^$repo $id " "$FIX/runs" 2>/dev/null | head -n 1)
        [ -n "$line" ] || { echo "gh: HTTP 404: Not Found" >&2; exit 1; }
        printf '{"path": "%s"}\n' "${line#* * }" | out
        ;;
    "api repos/"*) echo '{"default_branch": "main"}' | out ;;
    "pr list")
        jq --arg s "$state" '[.[] | select($s == "all"
            or ($s == "open" and .state == "OPEN")
            or ($s == "merged" and .state == "MERGED")
            or ($s == "closed" and .state == "CLOSED"))]' "$FIX/prs.json" | out
        ;;
    "pr view") pr_file "$1" "$2" "${3:-}" view ;;
    "pr checks") pr_file "$1" "$2" "${3:-}" checks ;;
    *) echo "gh stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB

# koto: `context get|exists <session> <key>` read $FIX/ctx-<key>, and
# `context add <session> <key>` stores stdin there, or fails under
# KOTO_FAIL=1. Every call is logged to $FIX/koto.log.
cat > "$T/bin/koto" <<'STUB'
#!/usr/bin/env bash
FIX="${GH_FIXTURE:?}"
echo "$*" >> "$FIX/koto.log"
case "$1 ${2:-}" in
    "context get") [ -f "$FIX/ctx-$4" ] || exit 1; cat "$FIX/ctx-$4" ;;
    "context exists") [ -f "$FIX/ctx-$4" ] ;;
    "context add")
        [ "${KOTO_FAIL:-0}" = 1 ] && { echo "koto: context write failed" >&2; exit 1; }
        cat > "$FIX/ctx-$4"
        echo "$3 $4" >> "$FIX/added"
        ;;
    *) echo "koto stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh" "$T/bin/koto" || exit 1

# A repository on the run's branch, with the floor script stubbed.
make_repo() {
    local dir="$1"
    mkdir -p "$dir" || return 1
    git -C "$dir" init -q || return 1
    git -C "$dir" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init || return 1
    git -C "$dir" checkout -q -b "$BRANCH" || return 1
}
REPO="$T/repo"
make_repo "$REPO" || exit 1
mkdir -p "$REPO/scripts" || exit 1
cat > "$REPO/scripts/check-macos-floor-setup.sh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = --workflows ] || exit 2
echo '["check-coordinate-scripts.yml", "check-rule-registry.yml"]'
STUB
chmod +x "$REPO/scripts/check-macos-floor-setup.sh" || exit 1

# The repository tsuku, koto and niwa look like: no floor script.
BARE="$T/bare"
make_repo "$BARE" || exit 1

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# check <bucket> <name> <workflow> <link>: one `gh pr checks` entry.
check() {
    jq -cn --arg b "$1" --arg n "$2" --arg w "$3" --arg l "$4" \
        '{bucket: $b, name: $n, workflow: $w, link: $l}'
}
PASS_CHECK=$(check pass "test (ubuntu-latest)" "Check execute scripts" "$RUN/100/job/1")
SKIP_CHECK=$(check skipping "optional" "Check evals" "$RUN/101/job/2")
CANCEL_REG=$(check cancel "test-rule-registry (macos-latest)" "Check rule registry" "$RUN/200/job/3")
CANCEL_COORD=$(check cancel "test-coordinate-scripts (macos-latest)" "Check coordinate scripts" "$RUN/201/job/4")
FAIL_CHECK=$(check fail "test (ubuntu-latest)" "Check execute scripts" "$RUN/100/job/1")
PENDING_CHECK=$(check pending "test-x (macos-latest)" "Check rule registry" "$RUN/200/job/9")
CANCEL_OTHER=$(check cancel "templates" "Check templates" "$RUN/300/job/5")

# fixture: a fresh fixture with no PRs, the run's context recorded.
fixture() {
    rm -rf "$FIX" && mkdir -p "$FIX" || return 1
    echo '[]' > "$FIX/prs.json"
    printf '%s' "$R" > "$FIX/ctx-repos"
    printf '%s' "$BRANCH" > "$FIX/ctx-settled_branch"
    printf '%s' "$MINE" > "$FIX/ctx-run_id"
    cat > "$FIX/runs" <<RUNS
$R 100 .github/workflows/check-execute-scripts.yml
$R 101 .github/workflows/check-evals.yml
$R 200 .github/workflows/check-rule-registry.yml
$R 201 .github/workflows/check-coordinate-scripts.yml
$R 300 .github/workflows/check-templates.yml
RUNS
    : > "$FIX/gh.log"
    : > "$FIX/koto.log"
}

# pr <number> <state> <run-id|-> <merge-state> -- <check-json...>: adds one PR
# on the run's branch, owned by $ME, marked with <run-id> (`-` for no marker),
# with its view and its checks.
pr() {
    local n="$1" state="$2" mark="$3" merge="$4" body=""
    shift 4
    [ "${1:-}" = -- ] && shift
    [ "$mark" = - ] || body="Implements docs/plans/PLAN-x.md.

<!-- shirabe-run: $mark -->
"
    jq --arg u "$REPO_URL/pull/$n" --arg s "$state" --arg me "$ME" --arg b "$body" \
        --arg h "$BRANCH" '. + [{url: $u, state: $s, isCrossRepository: false,
            author: {login: $me}, baseRefName: "main", headRefName: $h, body: $b}]' \
        "$FIX/prs.json" > "$FIX/prs.new" && mv "$FIX/prs.new" "$FIX/prs.json" || return 1
    jq -n --argjson n "$n" --arg s "$state" --arg u "$REPO_URL/pull/$n" --arg m "$merge" \
        '{number: $n, state: $s, url: $u, mergeStateStatus: $m}' > "$FIX/view-$n.json" || return 1
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | jq -s . > "$FIX/checks-$n.json"
    else
        echo '[]' > "$FIX/checks-$n.json"
    fi
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

LOOKUP=(--repo "$R" --head "$BRANCH" --state open-else-merged --run-id "$MINE")

# run_fallback <dir> [args...]: the script, in <dir>, with the stubs on PATH.
run_fallback() {
    local dir="$1"
    shift
    (cd "$dir" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" "$FALLBACK" "$@") \
        >"$T/out" 2>"$T/err"
    GOT=$?
    OUT=$(cat "$T/out")
    ERR=$(cat "$T/err")
}

expect_exit() {
    local label="$1" want="$2"
    if [ "$GOT" = "$want" ]; then pass "$label (exit $GOT)"
    else fail "$label: expected exit $want, got $GOT; stderr: $ERR"; fi
}
expect_quiet_stdout() {
    if [ -n "$OUT" ]; then fail "$1: stdout is not empty: $OUT"; fi
}
NOTE="$FIX/ctx-ci_cancelled_after_merge.txt"
expect_note() {
    if [ -f "$NOTE" ]; then pass "$1"
    else fail "$1: ci_cancelled_after_merge.txt was not recorded"; fi
}
expect_no_note() {
    if [ -f "$NOTE" ]; then fail "$1: a note was recorded: $(cat "$NOTE")"
    else pass "$1"; fi
}
gh_calls() { grep -c -- "$1" "$FIX/gh.log"; }

# ---------------------------------------------------------------------------
# The script, --owned
# ---------------------------------------------------------------------------

# --- the run's MERGED PR, every non-green check a floor cancel -----------------
fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$PASS_CHECK" "$SKIP_CHECK" "$CANCEL_REG" "$CANCEL_COORD"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: the run's MERGED PR with only floor cancels passes" 0
expect_quiet_stdout "--owned pass"
expect_note "--owned: the pass records the cancelled checks"
if grep -qF "#7 is MERGED" "$NOTE" 2>/dev/null \
    && grep -qF "test-rule-registry (macos-latest)"$'\t'"Check rule registry"$'\t'"$RUN/200/job/3" "$NOTE" \
    && grep -qF "test-coordinate-scripts (macos-latest)" "$NOTE" \
    && ! grep -qF "test (ubuntu-latest)" "$NOTE"; then
    pass "--owned: the note names the PR and only its cancelled checks"
else
    fail "--owned: unexpected note: $(cat "$NOTE" 2>/dev/null)"
fi
if grep -qx "execute-x ci_cancelled_after_merge.txt" "$FIX/added" 2>/dev/null; then
    pass "--owned: the note goes to the session named on the command line"
else
    fail "--owned: unexpected context writes: $(cat "$FIX/added" 2>/dev/null)"
fi
if grep -qF "pr checks $REPO_URL/pull/7 " "$FIX/gh.log" && grep -qF "pr view $REPO_URL/pull/7 " "$FIX/gh.log"; then
    pass "--owned: the PR is read by the URL the lookup answered"
else
    fail "--owned: the PR was not read by its URL: $(cat "$FIX/gh.log")"
fi
if grep -qF "api repos/$R/actions/runs/200 --hostname github.com " "$FIX/gh.log"; then
    pass "--owned: the runs are read from the host the lookup's URL names"
else
    fail "--owned: the run read did not name the URL's host: $(grep '^api' "$FIX/gh.log")"
fi
# The arguments reach owned-pr.sh as given: open-else-merged is the one value
# that lists every state and still answers the MERGED PR here, while a
# MERGED PR is no answer to --state open.
if grep -q -- "pr list --repo $R --head $BRANCH --state all " "$FIX/gh.log"; then
    pass "--owned: the lookup arguments reach owned-pr.sh, which lists every state"
else
    fail "--owned: no --state all list call: $(cat "$FIX/gh.log")"
fi
fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
run_fallback "$REPO" execute-x --owned --repo "$R" --head "$BRANCH" --state open --run-id "$MINE"
expect_exit "--owned with --state open finds no MERGED PR, so it blocks" 1
expect_no_note "--owned with --state open records no note"

# --- an open PR with a floor cancel: blocks -----------------------------------
fixture
pr 7 OPEN "$MINE" CLEAN -- "$PASS_CHECK" "$CANCEL_REG"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: an open PR with a floor cancel blocks" 1
expect_no_note "--owned: an open PR records no note"
if [ "$(gh_calls "pr checks")" = 0 ] && [ -z "$ERR" ]; then
    pass "--owned: an open PR stops at its state, quietly"
else
    fail "--owned: an open PR went on: $(cat "$FIX/gh.log"); stderr: $ERR"
fi

# --- an earlier run's MERGED PR beside this run's open one: the open one -------
fixture
pr 6 MERGED "$OTHER" UNKNOWN -- "$CANCEL_REG"
pr 7 OPEN "$MINE" CLEAN -- "$CANCEL_REG"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: another run's MERGED PR never stands in for this run's open one" 1
expect_no_note "--owned: the earlier MERGED PR records no note"
if [ "$(gh_calls "pull/6")" = 0 ]; then pass "--owned: the earlier run's PR is never read"
else fail "--owned: the earlier run's PR was read: $(cat "$FIX/gh.log")"; fi

# --- a failed, a pending, or a non-floor check: blocks -------------------------
fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG" "$FAIL_CHECK"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: MERGED with a failed check blocks" 1
expect_no_note "--owned: a failed check records no note"
case "$ERR" in
    *"is fail, not cancelled"*) pass "--owned: the failed check is named on stderr" ;;
    *) fail "--owned: stderr does not name the failed check: $ERR" ;;
esac

fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG" "$PENDING_CHECK"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: MERGED with a pending check blocks" 1

fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG" "$CANCEL_OTHER"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: MERGED with a cancel outside the floor workflows blocks" 1
expect_no_note "--owned: a non-floor cancel records no note"

# --- a PR the run doesn't own: blocks before it is read -------------------------
fixture
pr 7 MERGED "$OTHER" UNKNOWN -- "$CANCEL_REG"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: another run's MERGED PR blocks" 1
if [ "$(gh_calls "pr view")" = 0 ] && [ "$(gh_calls "pr checks")" = 0 ]; then
    pass "--owned: another run's PR is never read"
else
    fail "--owned: another run's PR was read: $(cat "$FIX/gh.log")"
fi

fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
GOT_MINE=$GOT
fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
(cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" GH_LOGIN=someone-else \
    "$FALLBACK" execute-x --owned "${LOOKUP[@]}") >"$T/out" 2>"$T/err"
GOT=$?
ERR=$(cat "$T/err")
if [ "$GOT_MINE" = 0 ] && [ "$GOT" = 1 ]; then
    pass "--owned: another author's MERGED PR blocks (exit 1, where the author's own passes)"
else
    fail "--owned: author check: own [$GOT_MINE], another author [$GOT]; stderr: $ERR"
fi

# --- no PR, or a closed-unmerged one: blocks quietly ---------------------------
fixture
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: no PR on the branch blocks" 1
[ -z "$ERR" ] && pass "--owned: no PR blocks quietly" || fail "--owned: no PR: stderr [$ERR]"

fixture
pr 7 CLOSED "$MINE" UNKNOWN -- "$CANCEL_REG"
run_fallback "$REPO" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: a closed-unmerged PR blocks" 1
if [ "$(gh_calls "pr view")" = 0 ]; then pass "--owned: a closed-unmerged PR is no lookup answer"
else fail "--owned: a closed-unmerged PR was read: $(cat "$FIX/gh.log")"; fi

# --- a repository without the floor script: quiet, no gh call ------------------
fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
run_fallback "$BARE" execute-x --owned "${LOOKUP[@]}"
expect_exit "--owned: a repository with no floor script blocks" 1
if [ -z "$ERR" ] && [ ! -s "$FIX/gh.log" ]; then
    pass "--owned: no floor script means no gh call and no stderr"
else
    fail "--owned: no floor script: stderr [$ERR], gh calls [$(cat "$FIX/gh.log")]"
fi

# --- the arguments ---------------------------------------------------------------
fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
run_fallback "$REPO" execute-x --owned
expect_exit "--owned with no lookup arguments blocks" 1
run_fallback "$REPO" execute-x --repo "$R"
expect_exit "an argument other than --owned after the session blocks" 1
run_fallback "$REPO" execute-x --owned --repo "$R" --head "$BRANCH" --state bogus --run-id "$MINE"
expect_exit "a lookup owned-pr.sh refuses blocks" 1
expect_no_note "a refused lookup records no note"

# The script finds owned-pr.sh beside itself under one plugin root; a tree
# without the execute skill blocks rather than running something else.
mkdir -p "$T/lone/skills/work-on/scripts" || exit 1
cp "$FALLBACK" "$T/lone/skills/work-on/scripts/" || exit 1
fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
(cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" \
    "$T/lone/skills/work-on/scripts/ci-cancel-after-merge.sh" execute-x --owned "${LOOKUP[@]}") \
    >"$T/out" 2>"$T/err"
GOT=$?
ERR=$(cat "$T/err")
expect_exit "--owned with no owned-pr.sh under the plugin root blocks" 1

fixture
pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
(cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" KOTO_FAIL=1 \
    "$FALLBACK" execute-x --owned "${LOOKUP[@]}") >"$T/out" 2>"$T/err"
GOT=$?
ERR=$(cat "$T/err")
expect_exit "--owned: a failed context write blocks" 1

# ---------------------------------------------------------------------------
# Wiring: the ci_monitor gates as execute.md ships them
# ---------------------------------------------------------------------------

# gate_command <name>: the gate's command, unquoted. owned_ci_passing and
# owned_merge_state_clean are double-quoted YAML scalars, which
# koto_unquote_scalar reads; monitor_owned_pr is single-quoted, where the
# only escape is a doubled quote.
gate_command() {
    local raw q="'"
    raw=$(koto_gate_command "$TEMPLATE" "$1") || return 1
    [ -n "$raw" ] || return 1
    case "$raw" in
        "$q"*"$q")
            raw="${raw#"$q"}"
            raw="${raw%"$q"}"
            printf '%s' "${raw//"$q$q"/$q}"
            ;;
        *) koto_unquote_scalar "$raw" ;;
    esac
}

# run_gate [plugin-root]: the gate in GATE_CMD as koto runs it, from the
# repository.
run_gate() {
    local cmd="$GATE_CMD" root="${1:-$REPO_ROOT}"
    cmd="${cmd//\{\{PLUGIN_ROOT\}\}/$root}"
    cmd="${cmd//\{\{PLAN_SLUG\}\}/x}"
    (cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" sh -c "$cmd") >/dev/null 2>"$T/err"
    GOT=$?
    ERR=$(cat "$T/err")
}

for g in owned_ci_passing owned_merge_state_clean monitor_owned_pr owned_pr_merged; do
    c=$(gate_command "$g")
    # Every --state the command passes, deduplicated: exactly the one value.
    states=$(printf '%s' "$c" | grep -oE -- '--state [a-z-]+' | sort -u | tr '\n' ' ')
    if [ "$states" = "--state open-else-merged " ]; then
        pass "$g looks the PR up with --state open-else-merged, and with nothing else"
    else
        fail "$g's lookups pass [$states]"
    fi
done

# --- owned_ci_passing -------------------------------------------------------------
GATE_CMD=$(gate_command owned_ci_passing)
if [ -z "$GATE_CMD" ]; then
    fail "could not read owned_ci_passing from $TEMPLATE"
else
    case "$GATE_CMD" in
        *'| grep -q true || "{{PLUGIN_ROOT}}/skills/work-on/scripts/ci-cancel-after-merge.sh" execute-{{PLAN_SLUG}} --owned --repo '*'--state open-else-merged --run-id '*'|| exit 1') \
            pass "owned_ci_passing falls back to ci-cancel-after-merge.sh --owned and ends in || exit 1" ;;
        *) fail "owned_ci_passing does not end in the --owned fallback: $GATE_CMD" ;;
    esac

    fixture
    pr 7 OPEN "$MINE" CLEAN -- "$PASS_CHECK" "$SKIP_CHECK"
    run_gate
    expect_exit "owned_ci_passing passes a green open PR" 0
    if [ ! -f "$FIX/added" ]; then pass "a green PR never reaches the fallback"
    else fail "a green PR reached the fallback: $(cat "$FIX/added")"; fi

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$PASS_CHECK" "$SKIP_CHECK"
    run_gate
    expect_exit "owned_ci_passing passes the run's green MERGED PR on its own filter" 0

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$PASS_CHECK" "$CANCEL_REG" "$CANCEL_COORD"
    run_gate
    expect_exit "owned_ci_passing passes a MERGED PR whose only non-green checks are floor cancels" 0
    expect_note "owned_ci_passing's pass records the cancelled checks"
    if grep -qx "execute-x ci_cancelled_after_merge.txt" "$FIX/added" 2>/dev/null; then
        pass "the note goes to the run's session, execute-<slug>"
    else
        fail "unexpected context writes: $(cat "$FIX/added" 2>/dev/null)"
    fi

    fixture
    pr 7 OPEN "$MINE" CLEAN -- "$PASS_CHECK" "$CANCEL_REG"
    run_gate
    expect_exit "owned_ci_passing still fails an open PR with a floor cancel" 1

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG" "$FAIL_CHECK"
    run_gate
    expect_exit "owned_ci_passing still fails a MERGED PR with a failed check" 1

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG" "$PENDING_CHECK"
    run_gate
    expect_exit "owned_ci_passing still fails a MERGED PR with a pending check" 1

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_OTHER"
    run_gate
    expect_exit "owned_ci_passing still fails a MERGED PR with a cancel outside the floor workflows" 1

    fixture
    pr 7 MERGED "$OTHER" UNKNOWN -- "$PASS_CHECK" "$CANCEL_REG"
    run_gate
    expect_exit "owned_ci_passing still fails another run's MERGED PR" 1
    if [ "$(gh_calls "pr checks")" = 0 ]; then pass "another run's PR's checks are never read"
    else fail "another run's PR's checks were read: $(cat "$FIX/gh.log")"; fi

    fixture
    pr 6 MERGED "$OTHER" UNKNOWN -- "$PASS_CHECK"
    pr 7 OPEN "$MINE" CLEAN -- "$PASS_CHECK" "$CANCEL_REG"
    run_gate
    expect_exit "owned_ci_passing reads this run's open PR, not an earlier run's green MERGED one" 1

    fixture
    pr 7 CLOSED "$MINE" UNKNOWN -- "$PASS_CHECK"
    run_gate
    expect_exit "owned_ci_passing fails a branch whose only PR is closed-unmerged, as before" 1

    # The repository tsuku, koto and niwa look like: the gate is the filter
    # alone, and a MERGED PR's floor cancel fails it.
    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$PASS_CHECK" "$CANCEL_REG"
    cmd="${GATE_CMD//\{\{PLUGIN_ROOT\}\}/$REPO_ROOT}"
    cmd="${cmd//\{\{PLAN_SLUG\}\}/x}"
    (cd "$BARE" && env PATH="$T/bin:$PATH" GH_FIXTURE="$FIX" sh -c "$cmd") >/dev/null 2>"$T/err"
    GOT=$?
    ERR=$(cat "$T/err")
    expect_exit "owned_ci_passing still fails in a repository without the floor script" 1

    mkdir -p "$T/empty-plugin" || exit 1
    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
    run_gate "$T/empty-plugin"
    expect_exit "owned_ci_passing exits exactly 1 when nothing it calls can run" 1
fi

# --- owned_merge_state_clean -------------------------------------------------------
GATE_CMD=$(gate_command owned_merge_state_clean)
if [ -z "$GATE_CMD" ]; then
    fail "could not read owned_merge_state_clean from $TEMPLATE"
else
    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
    run_gate
    expect_exit "owned_merge_state_clean passes the run's MERGED PR (mergeStateStatus UNKNOWN)" 0

    fixture
    pr 7 OPEN "$MINE" CLEAN -- "$PASS_CHECK"
    run_gate
    expect_exit "owned_merge_state_clean passes a clean open PR" 0

    fixture
    pr 7 OPEN "$MINE" DIRTY -- "$PASS_CHECK"
    run_gate
    expect_exit "owned_merge_state_clean still answers 1 on a DIRTY open PR" 1

    fixture
    pr 7 CLOSED "$MINE" UNKNOWN -- "$PASS_CHECK"
    run_gate
    expect_exit "owned_merge_state_clean still holds (2) with no PR to read" 2
fi

# --- monitor_owned_pr ------------------------------------------------------------------
GATE_CMD=$(gate_command monitor_owned_pr)
if [ -z "$GATE_CMD" ]; then
    fail "could not read monitor_owned_pr from $TEMPLATE"
else
    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$CANCEL_REG"
    run_gate
    expect_exit "monitor_owned_pr finds the run's MERGED PR" 0

    fixture
    pr 7 OPEN "$MINE" CLEAN -- "$PASS_CHECK"
    run_gate
    expect_exit "monitor_owned_pr finds the run's open PR" 0

    fixture
    pr 6 MERGED "$MINE" UNKNOWN -- "$PASS_CHECK"
    pr 7 OPEN "$MINE" CLEAN -- "$PASS_CHECK"
    run_gate
    expect_exit "monitor_owned_pr: an open PR beside a MERGED one is one answer, the open one" 0

    fixture
    pr 7 MERGED "$OTHER" UNKNOWN -- "$CANCEL_REG"
    run_gate
    expect_exit "monitor_owned_pr: another run's MERGED PR is no single owned PR" 3

    fixture
    pr 7 CLOSED "$MINE" UNKNOWN -- "$CANCEL_REG"
    run_gate
    expect_exit "monitor_owned_pr: a closed-unmerged PR alone is no single owned PR, as before" 3

    fixture
    run_gate
    expect_exit "monitor_owned_pr: no PR is no single owned PR, as before" 3
fi

# --- owned_pr_merged -------------------------------------------------------------------
# 0 routes a MERGED PR to merge_readiness whatever its checks say (#917), so
# only the run's own MERGED PR may answer 0. Every other answer is 1, which
# leaves ci_monitor's routes as they were.
GATE_CMD=$(gate_command owned_pr_merged)
if [ -z "$GATE_CMD" ]; then
    fail "could not read owned_pr_merged from $TEMPLATE"
else
    case "$GATE_CMD" in
        *' | xargs -r -I{} gh pr view {} --json state --jq .state | '*) \
            pass "owned_pr_merged reads the state of the PR the lookup resolves, never the branch's" ;;
        *) fail "owned_pr_merged does not read the resolved PR's state: $GATE_CMD" ;;
    esac

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$PASS_CHECK" "$FAIL_CHECK"
    run_gate
    expect_exit "owned_pr_merged: the run's MERGED PR, a check failed" 0

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$PENDING_CHECK"
    run_gate
    expect_exit "owned_pr_merged: the run's MERGED PR, a check still running" 0

    fixture
    pr 7 MERGED - UNKNOWN -- "$PASS_CHECK"
    run_gate
    expect_exit "owned_pr_merged: an unmarked MERGED PR this login owns" 0

    fixture
    pr 7 OPEN "$MINE" CLEAN -- "$FAIL_CHECK"
    run_gate
    expect_exit "owned_pr_merged: the run's open PR is not merged" 1

    fixture
    pr 7 CLOSED "$MINE" UNKNOWN -- "$PASS_CHECK"
    run_gate
    expect_exit "owned_pr_merged: a closed-unmerged PR alone is not merged" 1
    if [ "$(gh_calls "pr view")" = 0 ]; then pass "a closed-unmerged PR is never read: the lookup is empty"
    else fail "a closed-unmerged PR was read: $(cat "$FIX/gh.log")"; fi

    fixture
    run_gate
    expect_exit "owned_pr_merged: no PR is not merged" 1

    fixture
    pr 7 MERGED "$OTHER" UNKNOWN -- "$PASS_CHECK"
    run_gate
    expect_exit "owned_pr_merged: another run's MERGED PR is not this run's" 1
    if [ "$(gh_calls "pr view")" = 0 ]; then pass "another run's MERGED PR is never read"
    else fail "another run's MERGED PR was read: $(cat "$FIX/gh.log")"; fi

    fixture
    pr 7 MERGED - UNKNOWN -- "$PASS_CHECK"
    export GH_LOGIN=someone-else
    run_gate
    unset GH_LOGIN
    expect_exit "owned_pr_merged: another author's MERGED PR is not this run's" 1

    fixture
    pr 6 MERGED - UNKNOWN -- "$PASS_CHECK"
    pr 7 OPEN "$MINE" CLEAN -- "$FAIL_CHECK"
    run_gate
    expect_exit "owned_pr_merged: an earlier MERGED PR beside this run's open one reads the open one" 1

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$PASS_CHECK"
    rm -f "$FIX/view-7.json"
    run_gate
    expect_exit "owned_pr_merged: a failed state read is not merged" 1

    fixture
    pr 7 MERGED "$MINE" UNKNOWN -- "$PASS_CHECK"
    run_gate "$T/empty-plugin"
    expect_exit "owned_pr_merged exits exactly 1 when the lookup can't run" 1
fi

echo
echo "owned-ci-cancel_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
