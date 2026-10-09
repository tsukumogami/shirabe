#!/usr/bin/env bash
# check-pr-output_test.sh -- does check-pr-output.sh translate the shipped
# checks' answers into the gate convention, name the right rule, and pass the
# PR's text through as data?
#
# gh, shirabe and owned-pr.sh are stand-ins on PATH, driven by environment
# variables, so each case sets the exact exit status and output the script
# must translate. The stand-ins record their arguments one file per argument,
# which is how the title is shown to arrive as a single argument.
#
# What the stand-ins cannot cover is the shape of the real tools' output. The
# PB messages below are copied from crates/shirabe-validate/src/pr_body.rs;
# owned-pr.sh's exit codes are its documented contract.
#
# Every finding line the script prints is checked against koto's finding shape
# (`jq -e '.rule_id and .level and .message and .rule_ref'`).
#
# Usage: check-pr-output_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-pr-output.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }
[ -x "$CHECK" ] || { echo "$CHECK is missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/check-pr-output-test.XXXXXX")
WORKDIR=$(cd -P "$WORKDIR" && pwd -P)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

BIN="$WORKDIR/bin"
LOG="$WORKDIR/log"
mkdir -p "$BIN" "$LOG"
export LOG

# Every finding the runs below print is logged and verified against the rule
# registry at the end.
# shellcheck source=../../../scripts/lib/rule-findings-testlib.sh
. "$SCRIPT_DIR/../../../scripts/lib/rule-findings-testlib.sh"
rf_test_setup "$WORKDIR"

# record <tool> <args>...: one file per argument under $LOG/<tool>/.
cat > "$BIN/record.sh" <<'EOF'
tool=$1
shift
mkdir -p "$LOG/$tool"
rm -f "$LOG/$tool"/arg.*
i=0
for a in "$@"; do
    i=$((i + 1))
    printf '%s' "$a" > "$LOG/$tool/arg.$i"
done
printf '%s\n' "$i" > "$LOG/$tool/argc"
EOF

# gh pr view [<url>] --json title,body: FAKE_GH_OWNED_JSON for a URL,
# FAKE_GH_BRANCH_JSON for the checked-out branch; FAKE_GH_RC overrides.
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
. "$(dirname "$0")/record.sh" gh "$@"
[ "${FAKE_GH_RC:-0}" = 0 ] || { echo "gh: failed" >&2; exit "$FAKE_GH_RC"; }
case "${3-}" in
    https://*) printf '%s\n' "$FAKE_GH_OWNED_JSON" ;;
    *) printf '%s\n' "$FAKE_GH_BRANCH_JSON" ;;
esac
EOF

# shirabe validate ...: prints FAKE_SHIRABE_OUT, exits FAKE_SHIRABE_RC, and
# keeps a copy of the body file it was handed.
cat > "$BIN/shirabe" <<'EOF'
#!/usr/bin/env bash
. "$(dirname "$0")/record.sh" shirabe "$@"
prev=""
for a in "$@"; do
    [ "$prev" != --pr-body ] || cp "$a" "$LOG/shirabe/body"
    prev=$a
done
printf '%s\n' "${FAKE_SHIRABE_OUT-}"
exit "${FAKE_SHIRABE_RC:-0}"
EOF

# owned-pr.sh: prints FAKE_OWNED_OUT, exits FAKE_OWNED_RC, after sleeping
# FAKE_OWNED_SLEEP seconds.
cat > "$BIN/owned-pr.sh" <<'EOF'
#!/usr/bin/env bash
. "$(dirname "$0")/record.sh" owned "$@"
[ -z "${FAKE_OWNED_SLEEP-}" ] || sleep "$FAKE_OWNED_SLEEP"
[ -z "${FAKE_OWNED_OUT-}" ] || printf '%s\n' "$FAKE_OWNED_OUT"
exit "${FAKE_OWNED_RC:-0}"
EOF
chmod +x "$BIN/gh" "$BIN/shirabe" "$BIN/owned-pr.sh"
export PATH="$BIN:$PATH"
# The script never takes owned-pr.sh from PATH; this variable is its one seam.
# The stand-in also sits on PATH, so the case at the end can show PATH's copy
# is ignored once the variable is unset.
CHECK_PR_OUTPUT_OWNED_PR="$BIN/owned-pr.sh"
export CHECK_PR_OUTPUT_OWNED_PR

URL1='https://github.com/acme/widgets/pull/12'
OWNED_ARGS="--repo acme/widgets --head impl/x --state open"

pr_json() { jq -cn --arg t "$1" --arg b "$2" '{title: $t, body: $b}'; }
export FAKE_GH_BRANCH_JSON
export FAKE_GH_OWNED_JSON
FAKE_GH_BRANCH_JSON=$(pr_json "feat: the branch PR" "Branch body.

---

Context.")
FAKE_GH_OWNED_JSON=$(pr_json "feat: the owned PR" "Owned body.

---

Context.")

OUT=""
RC=0
run() {
    OUT=$("$CHECK" "$@" 2>"$WORKDIR/stderr")
    RC=$?
}

findings() { printf '%s\n' "$OUT" | sed -n 's/^::koto-finding:://p'; }
finding_count() { printf '%s\n' "$OUT" | grep -c '^::koto-finding::'; }

check_shape() { # <label>
    local line bad=0 n=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        n=$((n + 1))
        printf '%s' "$line" | jq -e '.rule_id and .level and .message and .rule_ref' >/dev/null 2>&1 || bad=1
    done <<EOF
$(findings)
EOF
    if [ "$bad" -ne 0 ]; then
        fail "$1: a finding line does not parse as koto's finding shape: $OUT"
    else
        pass "$1: finding lines parse as koto's finding shape ($n)"
    fi
}

expect_rc() { # <label> <exit>
    if [ "$RC" -eq "$2" ]; then
        pass "$1"
    else
        fail "$1: want exit $2, got $RC (stdout: $OUT; stderr: $(cat "$WORKDIR/stderr"))"
    fi
}

msg_json() { # <message>... -> the validator's JSON envelope
    local items="[]" m
    for m in "$@"; do
        items=$(printf '%s' "$items" | jq -c --arg m "$m" '. + [{line: 1, message: $m}]')
    done
    printf '{"schema":"shirabe-pr-body/v1","outcome":"violations","findings":%s}' "$items"
}

# --- --pr-body: the validator's exit status ------------------------------------

export FAKE_SHIRABE_RC FAKE_SHIRABE_OUT
FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"clean","findings":[]}'
run --pr-body
expect_rc "--pr-body: validator exit 0 maps to 0" 0
[ "$(finding_count)" -eq 0 ] && pass "--pr-body: a clean body prints no finding" || fail "--pr-body: a clean body printed findings: $OUT"

PB1='PR title "added stuff" is not Conventional Commits. Use `<type>[optional scope]: <description>` with <type> one of feat|fix|docs|style|refactor|perf|test|chore|ci|build|revert; see references/pr-body-conformance.md.'
PB2='the PR body has no `---` separator. Add a single line that is exactly `---` between Part 1 (the squash commit body) and Part 2 (reviewer context deleted at merge); see references/pr-body-conformance.md.'
PB2_EMPTY='Part 1 (everything above the `---` separator) is empty. Part 1 becomes the squash commit body, so it must contain a factual description of the change; see references/pr-body-conformance.md.'
PB2_MANY='the PR body has 2 top-level `---` separators; it must have exactly one. Everything from the first `---` down is deleted at merge, so a second bare `---` is ambiguous; see references/pr-body-conformance.md.'
PB3='the PR body carries an AI-attribution / co-author footer. Remove the `Co-Authored-By:` AI trailer or the "Generated with Claude Code" line; the org convention forbids AI attribution and co-author lines (see references/pr-body-conformance.md).'
PB4='Part 1 (the squash commit body, above the `---` separator) contains a markdown section heading. Part 1 lands permanently on `main` as the commit message and must be plain prose, not a heading-structured document; rewrite Part 1 as prose and move any `## Section` headings below the `---` into Part 2 (see references/pr-body-conformance.md).'
UNKNOWN='something the gate has never seen'

FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB1")
run --pr-body
expect_rc "--pr-body: validator exit 2 maps to 1" 1
check_shape "--pr-body: violations"

for rc in 1 3 4; do
    FAKE_SHIRABE_RC=$rc
    FAKE_SHIRABE_OUT=''
    run --pr-body
    expect_rc "--pr-body: validator exit $rc maps to 2" 2
    [ "$(finding_count)" -eq 0 ] && pass "--pr-body: validator exit $rc prints no finding" || fail "--pr-body: validator exit $rc printed findings: $OUT"
done

# --- --pr-body: the rule each message names ------------------------------------

FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB1" "$PB2" "$PB2_EMPTY" "$PB2_MANY" "$PB3" "$PB4" "$UNKNOWN")
run --pr-body
expect_rc "--pr-body: seven findings exit 1" 1
GOT=$(findings | jq -r '.rule_id' | tr '\n' ' ')
WANT='pr-body/conventional-title pr-body/one-separator pr-body/one-separator pr-body/one-separator pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/conformance '
if [ "$GOT" = "$WANT" ]; then
    pass "--pr-body: PB1 to PB4 map to their rule names and an unrecognized message to pr-body/conformance"
else
    fail "--pr-body: rule names: want [$WANT], got [$GOT]"
fi
REFS=$(findings | jq -r '.rule_ref' | grep -cE '^references/pr-body-conformance\.md#L[0-9]+-L[0-9]+@([0-9a-f]{12}|worktree)$')
[ "$REFS" -eq 7 ] && pass "--pr-body: every rule_ref is <path>#L<a>-L<b>@<revision>" || fail "--pr-body: rule_ref shape: $(findings | jq -r '.rule_ref')"
REF=$(findings | jq -r 'select(.rule_id == "pr-body/no-ai-trailer") | .rule_ref')
WANT_RANGE=$(rf_test_expected_range pr-body/no-ai-trailer)
[ "${REF%@*}" = "$WANT_RANGE" ] && pass "--pr-body: pr-body/no-ai-trailer's range is $WANT_RANGE, found from its anchors with grep" \
    || fail "--pr-body: pr-body/no-ai-trailer range [${REF%@*}], want [$WANT_RANGE]"
MSG=$(findings | jq -r 'select(.rule_id == "pr-body/no-ai-trailer") | .message')
SUMMARY=$("$SCRIPT_DIR/../../../scripts/rule-registry.sh" summary pr-body/no-ai-trailer)
[ "$MSG" = "$SUMMARY: $PB3" ] && pass "--pr-body: the finding carries the rule's summary, then the validator's message" || fail "--pr-body: message [$MSG]"
check_shape "--pr-body: every rule"

# --- --pr-body: which PR, and the title as data ----------------------------------

FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"outcome":"clean","findings":[]}'
run --pr-body
if [ "$(cat "$LOG/gh/argc")" = 4 ] && [ "$(cat "$LOG/gh/arg.3")" = --json ] \
    && [ "$(cat "$LOG/shirabe/arg.5")" = "feat: the branch PR" ]; then
    pass "--pr-body: without --owned it reads the checked-out branch's PR"
else
    fail "--pr-body: without --owned gh got $(cat "$LOG/gh/argc") args, title [$(cat "$LOG/shirabe/arg.5")]"
fi

export FAKE_OWNED_OUT FAKE_OWNED_RC
FAKE_OWNED_OUT=$URL1
FAKE_OWNED_RC=0
# shellcheck disable=SC2086
run --pr-body --owned $OWNED_ARGS
expect_rc "--pr-body --owned: a conformant owned PR" 0
if [ "$(cat "$LOG/gh/arg.3")" = "$URL1" ] && [ "$(cat "$LOG/shirabe/arg.5")" = "feat: the owned PR" ] \
    && grep -q 'Owned body.' "$LOG/shirabe/body"; then
    pass "--pr-body --owned reads the PR owned-pr.sh resolves, not the checked-out branch's"
else
    fail "--pr-body --owned: gh arg.3 [$(cat "$LOG/gh/arg.3")], title [$(cat "$LOG/shirabe/arg.5")]"
fi
if [ "$(cat "$LOG/owned/argc")" = 6 ] && [ "$(cat "$LOG/owned/arg.2")" = acme/widgets ]; then
    pass "--pr-body --owned passes the lookup arguments through"
else
    fail "--pr-body --owned: owned-pr.sh got $(cat "$LOG/owned/argc") args"
fi

FAKE_OWNED_OUT=''
FAKE_OWNED_RC=3
# shellcheck disable=SC2086
run --pr-body --owned $OWNED_ARGS
expect_rc "--pr-body --owned: no single owned PR cannot be decided" 2

FAKE_OWNED_OUT=$URL1
FAKE_OWNED_RC=0
TITLE="feat: x \$(touch $WORKDIR/pwned) \"quoted\" it's \`here\`"
FAKE_GH_OWNED_JSON=$(pr_json "$TITLE" "Body.

---

Context.")
# shellcheck disable=SC2086
run --pr-body --owned $OWNED_ARGS
if [ "$(cat "$LOG/shirabe/arg.4")" = --pr-title ] && [ "$(cat "$LOG/shirabe/arg.5")" = "$TITLE" ] \
    && [ "$(cat "$LOG/shirabe/arg.6")" = --format ] && [ ! -e "$WORKDIR/pwned" ]; then
    pass "--pr-body: a title containing \$( and quotes reaches the validator as one argument, unevaluated"
else
    fail "--pr-body: title argument [$(cat "$LOG/shirabe/arg.5")], argc $(cat "$LOG/shirabe/argc")"
fi

FAKE_GH_RC=7
export FAKE_GH_RC
run --pr-body
expect_rc "--pr-body: a gh read that fails cannot be decided" 2
unset FAKE_GH_RC

run --pr-body --bogus
expect_rc "--pr-body: an unknown flag is a usage error" 2

# --- --owned-pr: the lookup's answer -------------------------------------------

owned_case() { # <label> <owned rc> <owned stdout> <want exit>
    FAKE_OWNED_RC=$2
    FAKE_OWNED_OUT=$3
    # shellcheck disable=SC2086
    run --owned-pr $OWNED_ARGS
    expect_rc "--owned-pr: $1 maps to $4" "$4"
    if [ "$(finding_count)" -eq 0 ]; then
        pass "--owned-pr: $1 prints no finding"
    else
        fail "--owned-pr: $1 printed a finding: $OUT"
    fi
}
owned_case "exit 0 with one URL" 0 "$URL1" 0
[ "$OUT" = "$URL1" ] && pass "--owned-pr: the URL is the only stdout" || fail "--owned-pr: stdout [$OUT]"
owned_case "exit 0 with empty output" 0 "" 3
owned_case "exit 3" 3 "" 3
owned_case "exit 4" 4 "" 3
owned_case "exit 5" 5 "" 3
owned_case "exit 2" 2 "" 2
owned_case "exit 64" 64 "" 2
owned_case "exit 0 with two URLs" 0 "$URL1
https://github.com/acme/widgets/pull/13" 2

FAKE_OWNED_SLEEP=5
CHECK_PR_OUTPUT_OWNED_TIMEOUT=1
export FAKE_OWNED_SLEEP CHECK_PR_OUTPUT_OWNED_TIMEOUT
owned_case "a lookup that does not answer in time" 0 "$URL1" 2
unset FAKE_OWNED_SLEEP CHECK_PR_OUTPUT_OWNED_TIMEOUT

FAKE_OWNED_RC=0
FAKE_OWNED_OUT=$URL1
# shellcheck disable=SC2086
run --owned-pr $OWNED_ARGS --run-id 0123456789abcdef0123456789abcdef --take-over
expect_rc "--owned-pr: --take-over is refused" 2

# --- which owned-pr.sh runs ----------------------------------------------------
#
# Without the test variable, the script runs the execute skill's owned-pr.sh
# beside it, even with another owned-pr.sh on PATH. A copy of the script in a
# fake plugin tree, whose execute skill holds a second stand-in recording under
# its own name, shows which one answered.
PLUG="$WORKDIR/plugin"
mkdir -p "$PLUG/skills/work-on/scripts" "$PLUG/skills/execute/scripts" "$PLUG/scripts"
cp "$CHECK" "$PLUG/skills/work-on/scripts/"
cp -R "$SCRIPT_DIR/../../../scripts/lib" "$PLUG/scripts/"
cp "$SCRIPT_DIR/../../../scripts/rule-registry.sh" "$PLUG/scripts/"
cat > "$PLUG/skills/execute/scripts/owned-pr.sh" <<'EOF'
#!/usr/bin/env bash
. "$LOG/../bin/record.sh" owned-execute "$@"
printf '%s\n' "$FAKE_OWNED_OUT"
exit 0
EOF
chmod +x "$PLUG/skills/execute/scripts/owned-pr.sh"
rm -rf "$LOG/owned" "$LOG/owned-execute"
FAKE_OWNED_OUT=$URL1
OUT=$(env -u CHECK_PR_OUTPUT_OWNED_PR "$PLUG/skills/work-on/scripts/check-pr-output.sh" --owned-pr --repo acme/widgets 2>/dev/null)
RC=$?
if [ "$RC" -eq 0 ] && [ -f "$LOG/owned-execute/argc" ] && [ ! -e "$LOG/owned" ]; then
    pass "without CHECK_PR_OUTPUT_OWNED_PR the execute skill's owned-pr.sh answers, not PATH's"
else
    fail "owned-pr.sh resolution: rc=$RC, execute copy ran: $([ -f "$LOG/owned-execute/argc" ] && echo yes || echo no), PATH copy ran: $([ -e "$LOG/owned" ] && echo yes || echo no)"
fi

# --- the rule registry ----------------------------------------------------------

FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB3")
rf_test_refusals "--pr-body" skills/work-on/scripts/check-pr-output.sh pr-body/no-ai-trailer --pr-body
rf_test_verify "--pr-body"

echo
echo "check-pr-output_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
