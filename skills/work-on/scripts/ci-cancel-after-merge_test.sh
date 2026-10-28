#!/usr/bin/env bash
# ci-cancel-after-merge_test.sh -- does ci_passing's fallback pass a MERGED pull
# request's cancelled macOS floor checks, and nothing else?
#
# ci-cancel-after-merge.sh is reached only when ci_passing's own filter says not
# green (#952). The cases run it against a throwaway git repository whose
# scripts/check-macos-floor-setup.sh is a stub printing the floor list, with
# gh and koto stubbed on PATH, so no case reaches GitHub or a real session.
# The gh stub serves fixture JSON and applies `--jq` with jq, the way gh
# does, so the script's own filters are what decide.
#
# The wiring cases then run the ci_passing command EXTRACTED FROM THE
# TEMPLATE, with {{PLUGIN_ROOT}} and {{SESSION_NAME}} substituted as koto
# would, so the fallback is pinned where it ships and not in a copy: a green
# PR never reaches it, a MERGED PR with floor cancels passes through it, and
# a script that can't run still leaves the gate at exactly 1.
#
# What the stubs can't cover is gh's own answers. Those were measured on
# #950, MERGED with two cancelled floor checks: `gh pr list --head` returns
# [] for a MERGED branch, `gh pr view` on the branch returns it, and each
# check's link is .../actions/runs/<id>/job/<id>, whose run path is
# .github/workflows/<file>.
#
# Usage: ci-cancel-after-merge_test.sh
# Exit codes: 0 all pass, 1 any failed.
#
# Bash 3.2: no associative arrays, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
FALLBACK="$SCRIPT_DIR/ci-cancel-after-merge.sh"

# shellcheck source=../../../scripts/lib/koto-gates.sh
. "$REPO_ROOT/scripts/lib/koto-gates.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

command -v jq >/dev/null || { echo "ci-cancel-after-merge_test: jq is required" >&2; exit 1; }
command -v git >/dev/null || { echo "ci-cancel-after-merge_test: git is required" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/ci-cancel-after-merge-test.XXXXXX") || exit 1
# The trailing `return 0` keeps the trap's status from replacing the script's.
cleanup() { rm -rf "$T"; return 0; }
ktg_on_exit cleanup

REPO_URL="https://github.com/acme/widgets"
RUN="$REPO_URL/actions/runs"

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

mkdir -p "$T/bin" "$T/fixture" || exit 1

# gh: `pr list`, `pr view` and `pr checks` print $FIX/<list|view|checks>.json
# through --jq when one is given; `api repos/<r>/actions/runs/<id>` looks the
# run up in $FIX/runs (`<repo> <id> <path>` lines) and fails like a 404 when
# it isn't there. The runs live on one server, the host in $FIX/host
# (github.com without it): an api call sent anywhere else, by its --hostname
# or by gh's default, github.com, when it has none, gets the 404 too, as a
# read sent to the wrong server would. Every call is logged to $FIX/gh.log.
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
FIX="${GH_FIXTURE:?}"
echo "$*" >> "$FIX/gh.log"
jqf=""
host=github.com
prev=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jqf="$a"
    [ "$prev" = "--hostname" ] && host="$a"
    prev="$a"
done
serve() {
    [ -f "$FIX/$1.json" ] || { echo "gh: no $1 fixture" >&2; exit 1; }
    if [ -n "$jqf" ]; then jq -r "$jqf" "$FIX/$1.json"; else cat "$FIX/$1.json"; fi
}
case "$1 $2" in
    "pr list") serve list ;;
    "pr view") serve view ;;
    "pr checks") serve checks ;;
    "api "*)
        served=github.com
        [ -f "$FIX/host" ] && served=$(cat "$FIX/host")
        [ "$host" = "$served" ] || { echo "gh: HTTP 404: Not Found" >&2; exit 1; }
        path="${2#repos/}"
        repo="${path%/actions/runs/*}"
        id="${path##*/}"
        line=$(grep -E "^$repo $id " "$FIX/runs" 2>/dev/null | head -n 1)
        [ -n "$line" ] || { echo "gh: HTTP 404: Not Found" >&2; exit 1; }
        echo "${line#* * }"
        ;;
    *) echo "gh stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB

# koto: `context add <session> <key>` stores stdin at $FIX/ctx-<key>, or fails
# under KOTO_FAIL=1. Every call is logged to $FIX/koto.log.
cat > "$T/bin/koto" <<'STUB'
#!/usr/bin/env bash
FIX="${GH_FIXTURE:?}"
echo "$*" >> "$FIX/koto.log"
[ "${KOTO_FAIL:-0}" = 1 ] && { echo "koto: context write failed" >&2; exit 1; }
[ "$1 $2" = "context add" ] || { echo "koto stub: unexpected call: $*" >&2; exit 1; }
cat > "$FIX/ctx-$4"
STUB
chmod +x "$T/bin/gh" "$T/bin/koto" || exit 1

# A repository on a feature branch, with the floor script stubbed.
make_repo() {
    local dir="$1"
    mkdir -p "$dir" || return 1
    git -C "$dir" init -q || return 1
    git -C "$dir" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init || return 1
    git -C "$dir" checkout -q -b fix/1-thing || return 1
}
REPO="$T/repo"
make_repo "$REPO" || exit 1
mkdir -p "$REPO/scripts" || exit 1
cat > "$REPO/scripts/check-macos-floor-setup.sh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = --workflows ] || exit 2
[ "${FLOOR_FAIL:-0}" = 1 ] && { echo "check-macos-floor-setup: yq is required" >&2; exit 2; }
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
PASS_CHECK=$(check pass "test (ubuntu-latest)" "Check work-on scripts" "$RUN/100/job/1")
SKIP_CHECK=$(check skipping "optional" "Check evals" "$RUN/101/job/2")
CANCEL_REG=$(check cancel "test-rule-registry (macos-latest)" "Check rule registry" "$RUN/200/job/3")
CANCEL_COORD=$(check cancel "test-coordinate-scripts (macos-latest)" "Check coordinate scripts" "$RUN/201/job/4")

# fixture <state> <open-number> <checks-json-objects...>: a fresh fixture. The
# pull request's URL is $PR_URL, and its runs are served from $RUNS_HOST.
PR_URL="$REPO_URL/pull/7"
RUNS_HOST=github.com
fixture() {
    local state="$1" open="$2"
    shift 2
    rm -rf "$T/fixture" && mkdir -p "$T/fixture" || return 1
    if [ -n "$open" ]; then
        printf '[{"number": %s}]\n' "$open" > "$T/fixture/list.json"
    else
        echo '[]' > "$T/fixture/list.json"
    fi
    jq -cn --arg s "$state" --arg u "$PR_URL" '{number: 7, state: $s, url: $u}' > "$T/fixture/view.json"
    echo "$RUNS_HOST" > "$T/fixture/host"
    printf '%s\n' "$@" | jq -s . > "$T/fixture/checks.json"
    cat > "$T/fixture/runs" <<RUNS
acme/widgets 100 .github/workflows/check-work-on-scripts.yml
acme/widgets 101 .github/workflows/check-evals.yml
acme/widgets 200 .github/workflows/check-rule-registry.yml
acme/widgets 201 .github/workflows/check-coordinate-scripts.yml
acme/widgets 300 .github/workflows/check-templates.yml
acme/widgets 301 .github/workflows/macos-floor.yml
acme/widgets 302 .github/workflows/sub/check-rule-registry.yml
acme/widgets 303 check-rule-registry.yml
RUNS
    : > "$T/fixture/gh.log"
    : > "$T/fixture/koto.log"
}

# ---------------------------------------------------------------------------
# Running the script
# ---------------------------------------------------------------------------

# run_fallback <dir> [env assignments...]: runs the script in <dir> and sets
# GOT (exit), OUT (stdout) and ERR (stderr).
run_fallback() {
    local dir="$1"
    shift
    (cd "$dir" && env PATH="$T/bin:$PATH" GH_FIXTURE="$T/fixture" "$@" \
        "$FALLBACK" sess) >"$T/out" 2>"$T/err"
    GOT=$?
    OUT=$(cat "$T/out")
    ERR=$(cat "$T/err")
}

expect_exit() {
    local label="$1" want="$2"
    if [ "$GOT" = "$want" ]; then pass "$label (exit $GOT)"
    else fail "$label: expected exit $want, got $GOT; stderr: $ERR"; fi
    if [ -n "$OUT" ]; then fail "$label: stdout is not empty: $OUT"; fi
}
expect_note() {
    local label="$1"
    if [ -f "$T/fixture/ctx-ci_cancelled_after_merge.txt" ]; then pass "$label"
    else fail "$label: ci_cancelled_after_merge.txt was not recorded"; fi
}
expect_no_note() {
    local label="$1"
    if [ -f "$T/fixture/ctx-ci_cancelled_after_merge.txt" ]; then
        fail "$label: a note was recorded: $(cat "$T/fixture/ctx-ci_cancelled_after_merge.txt")"
    else pass "$label"; fi
}
note_has() {
    local label="$1" text="$2"
    if grep -qF -- "$text" "$T/fixture/ctx-ci_cancelled_after_merge.txt"; then pass "$label"
    else fail "$label: the note lacks: $text"; fi
}
gh_calls() { grep -c -- "$1" "$T/fixture/gh.log"; }

# --- MERGED, every non-green check a floor cancel: passes and records ---------
fixture MERGED "" "$PASS_CHECK" "$SKIP_CHECK" "$CANCEL_REG" "$CANCEL_COORD"
run_fallback "$REPO"
expect_exit "MERGED with only floor cancels passes" 0
expect_note "MERGED with only floor cancels records the note"
note_has "the note names the rule-registry check" "test-rule-registry (macos-latest)"$'\t'"Check rule registry"$'\t'"$RUN/200/job/3"
note_has "the note names the coordinate-scripts check" "test-coordinate-scripts (macos-latest)"
note_has "the note says the PR is MERGED" "#7 is MERGED"
if grep -qF "test (ubuntu-latest)" "$T/fixture/ctx-ci_cancelled_after_merge.txt"; then
    fail "the note names a passing check"
else
    pass "the note names only the cancelled checks"
fi
if grep -qx "context add sess ci_cancelled_after_merge.txt" "$T/fixture/koto.log"; then
    pass "the note is written to the session named on the command line"
else
    fail "unexpected koto calls: $(cat "$T/fixture/koto.log")"
fi
# On github.com the runs are read from github.com, named outright.
if grep -qxF "api repos/acme/widgets/actions/runs/200 --hostname github.com --jq .path" "$T/fixture/gh.log"; then
    pass "a github.com PR's runs are read from github.com"
else
    fail "the run read did not name github.com: $(grep '^api' "$T/fixture/gh.log")"
fi

# --- OPEN with a floor cancel: blocks, before looking any further --------------
fixture OPEN 7 "$PASS_CHECK" "$CANCEL_REG"
run_fallback "$REPO"
expect_exit "an open PR with a floor cancel blocks" 1
expect_no_note "an open PR records no note"
if [ "$(gh_calls "pr view")" = 0 ] && [ -z "$ERR" ]; then
    pass "an open PR stops at the list, quietly"
else
    fail "an open PR went on to: $(cat "$T/fixture/gh.log"); stderr: $ERR"
fi

# --- CLOSED without merging: blocks ---------------------------------------------
fixture CLOSED "" "$CANCEL_REG"
run_fallback "$REPO"
expect_exit "a CLOSED, unmerged PR with a floor cancel blocks" 1
expect_no_note "a CLOSED PR records no note"

# --- MERGED with a failed check: blocks ------------------------------------------
fixture MERGED "" "$CANCEL_REG" "$(check fail "test (ubuntu-latest)" "Check work-on scripts" "$RUN/100/job/1")"
run_fallback "$REPO"
expect_exit "MERGED with a failed check blocks" 1
expect_no_note "MERGED with a failed check records no note"
case "$ERR" in
    *"is fail, not cancelled"*) pass "the failed check is named on stderr" ;;
    *) fail "stderr does not name the failed check: $ERR" ;;
esac

# --- MERGED with a pending check: blocks -----------------------------------------
fixture MERGED "" "$CANCEL_REG" "$(check pending "test-x (macos-latest)" "Check rule registry" "$RUN/200/job/9")"
run_fallback "$REPO"
expect_exit "MERGED with a pending check blocks" 1

# --- MERGED with a cancel outside the floor workflows: blocks ---------------------
fixture MERGED "" "$CANCEL_REG" "$(check cancel "templates" "Check templates" "$RUN/300/job/5")"
run_fallback "$REPO"
expect_exit "MERGED with a non-floor cancel blocks" 1
expect_no_note "a non-floor cancel records no note"

fixture MERGED "" "$(check cancel "floor (plan)" "macOS floor" "$RUN/301/job/6")"
run_fallback "$REPO"
expect_exit "MERGED with a cancelled macos-floor.yml run blocks" 1

fixture MERGED "" "$(check cancel "nested" "Check rule registry" "$RUN/302/job/7")"
run_fallback "$REPO"
expect_exit "a run path below .github/workflows/ blocks" 1

fixture MERGED "" "$(check cancel "bare" "Check rule registry" "$RUN/303/job/8")"
run_fallback "$REPO"
expect_exit "a run path outside .github/workflows/ blocks" 1

fixture MERGED "" "$(check cancel "gone" "Check rule registry" "$RUN/999/job/1")"
run_fallback "$REPO"
expect_exit "a run gh can't read blocks" 1
# The message is the one it was before the host was passed (#1051).
if [ "$(tail -n 1 <<<"$ERR")" = "ci-cancel-after-merge: could not read run 999 of acme/widgets" ]; then
    pass "a run gh can't read is named as before"
else
    fail "unexpected stderr for a run gh can't read: $ERR"
fi

# --- MERGED with nothing non-green: the inline filter's answer, not this one's ---
fixture MERGED "" "$PASS_CHECK" "$SKIP_CHECK"
run_fallback "$REPO"
expect_exit "MERGED with no cancelled checks is left to the inline filter" 1
expect_no_note "MERGED with no cancelled checks records no note"

# --- links that aren't an Actions run of this repository: block ------------------
fixture MERGED "" "$(check cancel "external" "" "https://ci.example.com/status/1")"
run_fallback "$REPO"
expect_exit "an external status that was cancelled blocks" 1
case "$ERR" in
    *"is not an Actions run of acme/widgets"*) pass "the external check is named on stderr" ;;
    *) fail "stderr does not explain the external check: $ERR" ;;
esac

fixture MERGED "" "$(check cancel "elsewhere" "Check rule registry" "https://github.com/other/repo/actions/runs/200/job/3")"
run_fallback "$REPO"
expect_exit "another repository's run blocks" 1

fixture MERGED "" "$(check cancel "no link" "Check rule registry" "")"
run_fallback "$REPO"
expect_exit "a cancelled check with no link blocks" 1

fixture MERGED "" "$(check cancel "no run id" "Check rule registry" "$RUN/abc/job/3")"
run_fallback "$REPO"
expect_exit "a run link with no numeric id blocks" 1

# --- the floor list --------------------------------------------------------------
fixture MERGED "" "$CANCEL_REG"
run_fallback "$BARE"
expect_exit "a repository with no floor script blocks" 1
if [ -z "$ERR" ] && [ ! -s "$T/fixture/gh.log" ]; then
    pass "a repository with no floor script blocks quietly, with no gh call"
else
    fail "no-floor-script repository: stderr [$ERR], gh calls [$(cat "$T/fixture/gh.log")]"
fi

fixture MERGED "" "$CANCEL_REG"
run_fallback "$REPO" FLOOR_FAIL=1
expect_exit "a floor script that fails blocks" 1
expect_no_note "a failed floor list records no note"

# --- recording -------------------------------------------------------------------
fixture MERGED "" "$CANCEL_REG"
run_fallback "$REPO" KOTO_FAIL=1
expect_exit "a failed context write blocks" 1

# Two checks of one run cost one run lookup.
fixture MERGED "" "$CANCEL_REG" "$(check cancel "test-rule-registry (macos-14)" "Check rule registry" "$RUN/200/job/10")"
run_fallback "$REPO"
expect_exit "two cancels in one floor run pass" 0
if [ "$(gh_calls "actions/runs/200")" = 1 ]; then pass "a run is looked up once"
else fail "run 200 was looked up $(gh_calls "actions/runs/200") times"; fi

# --- a pull request on a host that isn't gh's default (#1051) --------------------
# The runs are served only from ghe.example.com. Before #1051 the run read
# went to gh's default host and got a 404, so this case blocked.
GHE_RUN="https://ghe.example.com/acme/widgets/actions/runs"
PR_URL="https://ghe.example.com/acme/widgets/pull/7"
RUNS_HOST=ghe.example.com
fixture MERGED "" "$(check cancel "test-rule-registry (macos-latest)" "Check rule registry" "$GHE_RUN/200/job/3")"
run_fallback "$REPO"
expect_exit "an enterprise PR with only floor cancels passes" 0
expect_note "an enterprise PR's pass records the note"
note_has "the note names the enterprise run" "$GHE_RUN/200/job/3"
if grep -qxF "api repos/acme/widgets/actions/runs/200 --hostname ghe.example.com --jq .path" "$T/fixture/gh.log"; then
    pass "an enterprise PR's runs are read from its own host"
else
    fail "the run read did not go to ghe.example.com: $(grep '^api' "$T/fixture/gh.log")"
fi

# The same repository's run on github.com is another server's run.
fixture MERGED "" "$(check cancel "elsewhere" "Check rule registry" "$RUN/200/job/3")"
run_fallback "$REPO"
expect_exit "an enterprise PR's cancel linking to github.com blocks" 1
case "$ERR" in
    *"is not an Actions run of acme/widgets"*) pass "the other host's run is named on stderr" ;;
    *) fail "stderr does not explain the other host's run: $ERR" ;;
esac

# A port is part of the host, in the link match and the read.
PR_URL="https://ghe.example.com:8443/acme/widgets/pull/7"
RUNS_HOST=ghe.example.com:8443
fixture MERGED "" "$(check cancel "ported" "Check rule registry" "https://ghe.example.com:8443/acme/widgets/actions/runs/200/job/3")"
run_fallback "$REPO"
expect_exit "a PR on a host with a port passes" 0
if [ "$(gh_calls "^api .* --hostname ghe.example.com:8443 ")" = 1 ]; then
    pass "a host's port is kept in the run read"
else
    fail "the run read did not keep the port: $(grep '^api' "$T/fixture/gh.log")"
fi
PR_URL="$REPO_URL/pull/7"
RUNS_HOST=github.com

# --- a URL that isn't a pull request's: named, and nothing more is read ----------
for bad in "https://github.com/acme/widgets/issues/7" \
    "https://ghe.example.com/prefix/acme/widgets/pull/7" \
    "not a url"; do
    PR_URL="$bad"
    fixture MERGED "" "$CANCEL_REG"
    run_fallback "$REPO"
    expect_exit "a MERGED PR whose URL is [$bad] blocks" 1
    expect_no_note "a URL that isn't a pull request's records no note [$bad]"
    case "$ERR" in
        *"could not read the pull request's URL: gh answered [$bad]"*) pass "the URL is named on stderr [$bad]" ;;
        *) fail "stderr does not name the URL [$bad]: $ERR" ;;
    esac
    if [ "$(gh_calls "pr checks")" = 0 ] && [ "$(gh_calls "^api")" = 0 ]; then
        pass "no checks or runs are read for [$bad]"
    else
        fail "reads went on for [$bad]: $(cat "$T/fixture/gh.log")"
    fi
done
PR_URL="$REPO_URL/pull/7"

# A missing session argument is exit 1, never anything the edges don't match.
fixture MERGED "" "$CANCEL_REG"
(cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$T/fixture" "$FALLBACK") >"$T/out" 2>"$T/err"
GOT=$?
OUT=$(cat "$T/out")
ERR=$(cat "$T/err")
expect_exit "a missing session argument blocks" 1

# ---------------------------------------------------------------------------
# Wiring: the ci_passing command as the template ships it
# ---------------------------------------------------------------------------

RAW=$(koto_gate_command "$TEMPLATE" ci_passing)
if [ -z "$RAW" ]; then
    fail "could not read the ci_passing gate command from $TEMPLATE"
else
    GATE=$(koto_unquote_scalar "$RAW")
    case "$GATE" in
        *'{{PLUGIN_ROOT}}/skills/work-on/scripts/ci-cancel-after-merge.sh'*'{{SESSION_NAME}}'*'|| exit 1') \
            pass "ci_passing falls back to ci-cancel-after-merge.sh and ends in || exit 1" ;;
        *) fail "ci_passing does not end in the fallback: $GATE" ;;
    esac

    # run_gate <plugin-root> [env assignments...]: the gate as koto runs it.
    run_gate() {
        local root="$1"
        shift
        local cmd="${GATE//\{\{PLUGIN_ROOT\}\}/$root}"
        cmd="${cmd//\{\{SESSION_NAME\}\}/sess}"
        (cd "$REPO" && env PATH="$T/bin:$PATH" GH_FIXTURE="$T/fixture" "$@" sh -c "$cmd") \
            >"$T/out" 2>"$T/err"
        GOT=$?
        OUT=""
        ERR=$(cat "$T/err")
    }

    fixture OPEN 7 "$PASS_CHECK" "$SKIP_CHECK"
    run_gate "$REPO_ROOT"
    expect_exit "the gate passes a green PR" 0
    if [ "$(gh_calls "pr view")" = 0 ] && [ ! -s "$T/fixture/koto.log" ]; then
        pass "a green PR never reaches the fallback"
    else
        fail "a green PR reached the fallback: $(cat "$T/fixture/gh.log")"
    fi

    # The gate's own list call finds no open PR for a MERGED branch, and its
    # `gh pr checks` then resolves the branch, as gh does.
    fixture MERGED "" "$PASS_CHECK" "$CANCEL_REG"
    run_gate "$REPO_ROOT"
    expect_exit "the gate passes a MERGED PR whose only non-green checks are floor cancels" 0
    expect_note "the gate's pass records the note"

    fixture OPEN 7 "$PASS_CHECK" "$CANCEL_REG"
    run_gate "$REPO_ROOT"
    expect_exit "the gate still fails an open PR with a floor cancel" 1

    fixture MERGED "" "$CANCEL_REG" "$(check fail "test (ubuntu-latest)" "Check work-on scripts" "$RUN/100/job/1")"
    run_gate "$REPO_ROOT"
    expect_exit "the gate still fails a MERGED PR with a failed check" 1

    mkdir -p "$T/empty-plugin" || exit 1
    fixture MERGED "" "$CANCEL_REG"
    run_gate "$T/empty-plugin"
    expect_exit "the gate exits exactly 1 when the fallback can't run" 1
fi

echo
echo "ci-cancel-after-merge_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
