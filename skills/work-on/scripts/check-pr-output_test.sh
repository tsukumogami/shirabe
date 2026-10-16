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

# A real validator for the PB5 cases near the end, found before the stand-ins
# go on PATH: CHECK_PR_OUTPUT_REAL_SHIRABE, else the shirabe already on PATH.
# The cases run only when it knows --writing-style; CI builds one from this
# checkout and sets CHECK_PR_OUTPUT_REQUIRE_SHIRABE=1, which makes a missing
# one a failure instead of a skip.
REAL_SHIRABE=${CHECK_PR_OUTPUT_REAL_SHIRABE:-$(command -v shirabe 2>/dev/null || true)}

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
# One line per call, appended, so a case can count calls.
printf 'call\n' >> "$LOG/$tool/calls"
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

# --- --pr-body: PB4's text is released when PB4 is broken -----------------------
#
# The offload canary may leave PB4 out of a run's preloaded text, so a PB4
# finding releases the rule's lines on stderr, once, and nothing else does.

release_count() { grep -c '^::shirabe-rule::{"rule_id":"pr-body/no-heading-in-part1"' "$WORKDIR/stderr"; }
PB4_FIRST=$(jq -r '.rules[] | select(.id == "pr-body/no-heading-in-part1") | .text.first' \
    "$SCRIPT_DIR/../../../references/rule-registry.json")

# PB4 has one home: outside the lines its entry anchors, the conformance file
# names neither PB4 nor a heading, so leaving those lines out leaves no trace
# of the rule; and the lines fit release's 60-line cap.
CONF="$SCRIPT_DIR/../../../references/pr-body-conformance.md"
PB4_RANGE=$(rf_test_expected_range pr-body/no-heading-in-part1)
PB4_A=${PB4_RANGE#*#L}; PB4_A=${PB4_A%-L*}
PB4_B=${PB4_RANGE##*-L}
OUTSIDE=$(awk -v a="$PB4_A" -v b="$PB4_B" 'NR < a || NR > b' "$CONF" | grep -ciE 'PB4|heading')
if [ "$OUTSIDE" -eq 0 ] && [ $((PB4_B - PB4_A + 1)) -le 60 ]; then
    pass "references/pr-body-conformance.md states PB4 only inside its anchored lines ($PB4_RANGE)"
else
    fail "references/pr-body-conformance.md: $OUTSIDE lines outside $PB4_RANGE mention PB4 or a heading"
fi

FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB4")
run --pr-body
expect_rc "--pr-body: a PB4 finding exits 1" 1
if [ "$(release_count)" -eq 1 ] && grep -qF -- "$PB4_FIRST" "$WORKDIR/stderr" \
    && grep -q '^::shirabe-rule-end::$' "$WORKDIR/stderr"; then
    pass "--pr-body: a PB4 finding releases PB4's text between the marker lines"
else
    fail "--pr-body: PB4 release missing from stderr: $(cat "$WORKDIR/stderr")"
fi
[ "$(findings | jq -r '.rule_id')" = pr-body/no-heading-in-part1 ] \
    && pass "--pr-body: the release leaves the finding on stdout unchanged" \
    || fail "--pr-body: findings with a release: $OUT"

FAKE_SHIRABE_OUT=$(msg_json "$PB4" "$PB3")
run --pr-body
if [ "$RC" -eq 1 ] && [ "$(finding_count)" -eq 2 ] && [ "$(release_count)" -eq 1 ]; then
    pass "--pr-body: PB4 and PB3 print both findings and release PB4's text once"
else
    fail "--pr-body: PB4+PB3: rc $RC, $(finding_count) findings, $(release_count) releases"
fi

FAKE_SHIRABE_OUT=$(msg_json "$PB2")
run --pr-body
if [ "$RC" -eq 1 ] && ! grep -q '^::shirabe-rule::' "$WORKDIR/stderr"; then
    pass "--pr-body: a PB2-only violation releases no rule text"
else
    fail "--pr-body: PB2 only: rc $RC, stderr $(cat "$WORKDIR/stderr")"
fi

FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"clean","findings":[]}'
run --pr-body
if [ "$RC" -eq 0 ] && ! grep -q '^::shirabe-rule::' "$WORKDIR/stderr"; then
    pass "--pr-body: a conformant body releases no rule text"
else
    fail "--pr-body: conformant: rc $RC, stderr $(cat "$WORKDIR/stderr")"
fi

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

# --- --pr-body: banned words (PB5, --writing-style) ----------------------------

PLUGIN_RULES="$(cd "$SCRIPT_DIR/../../writing-style" && pwd -P)/rules.yaml"
PB5_BODY='[PB5] writing-style banned word "leverage" on line 3 -- Prefer the plain verb. Most of these are longer ways to say use, help, or show.'
PB5_TITLE='[PB5] writing-style banned word "seamless" in the title -- These assert a quality instead of demonstrating it. Cut, or replace with the specific claim.'

# arg_after <tool> <flag>: the argument the stand-in received after <flag>.
arg_after() {
    local i=1 n
    n=$(cat "$LOG/$1/argc")
    while [ "$i" -lt "$n" ]; do
        if [ "$(cat "$LOG/$1/arg.$i")" = "$2" ]; then
            cat "$LOG/$1/arg.$((i + 1))"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"clean","findings":[]}'
run --pr-body
if [ "$RC" -eq 0 ] && [ "$(arg_after shirabe --writing-style)" = "$PLUGIN_RULES" ] \
    && [ "$(cat "$LOG/shirabe/arg.4")" = --pr-title ] && [ "$(cat "$LOG/shirabe/arg.6")" = --format ]; then
    pass "--pr-body: the validator gets --writing-style with this plugin's own rules.yaml, after the existing arguments"
else
    fail "--pr-body: --writing-style got [$(arg_after shirabe --writing-style)], want [$PLUGIN_RULES]"
fi

# Neither SHIRABE_RULES nor a rules.yaml where the gate runs changes the file
# the validator is told to load.
mkdir -p "$WORKDIR/repo/skills/writing-style"
printf 'words: []\n' > "$WORKDIR/repo/skills/writing-style/rules.yaml"
OUT=$(cd "$WORKDIR/repo" && SHIRABE_RULES=/dev/null "$CHECK" --pr-body 2>"$WORKDIR/stderr")
RC=$?
if [ "$RC" -eq 0 ] && [ "$(arg_after shirabe --writing-style)" = "$PLUGIN_RULES" ]; then
    pass "--pr-body: SHIRABE_RULES and a rules.yaml in the working directory don't change the rules passed"
else
    fail "--pr-body: with SHIRABE_RULES and a local rules.yaml, --writing-style got [$(arg_after shirabe --writing-style)]"
fi

# Each stand-in appends one line to its `calls` file per call.
rm -rf "$LOG/gh" "$LOG/shirabe"
run --pr-body
calls() { grep -c . "$LOG/$1/calls" 2>/dev/null || echo 0; }
if [ "$(calls gh)" -eq 1 ] && [ "$(calls shirabe)" -eq 1 ]; then
    pass "--pr-body: one gh pr view and one validator run per evaluation"
else
    fail "--pr-body: gh ran $(calls gh), shirabe ran $(calls shirabe) times"
fi

FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB5_BODY")
run --pr-body
expect_rc "--pr-body: a PB5 finding exits 1" 1
check_shape "--pr-body: PB5"
F=$(findings)
REF=$(printf '%s' "$F" | jq -r '.rule_ref')
WANT_REF=$("$SCRIPT_DIR/../../../scripts/rule-registry.sh" ref pr-body/banned-word)
SUMMARY=$("$SCRIPT_DIR/../../../scripts/rule-registry.sh" summary pr-body/banned-word)
if [ "$(finding_count)" -eq 1 ] && [ "$(printf '%s' "$F" | jq -r '.rule_id')" = pr-body/banned-word ] \
    && [ "$(printf '%s' "$F" | jq -r '.level')" = error ] && [ "$REF" = "$WANT_REF" ] \
    && [ "$(printf '%s' "$F" | jq -r '.message')" = "$SUMMARY: $PB5_BODY" ]; then
    pass "--pr-body: a [PB5] message is one pr-body/banned-word finding at level error, with the entry's summary and rule_ref"
else
    fail "--pr-body: PB5 finding [$F], want rule_ref [$WANT_REF]"
fi
case "$REF" in
    skills/writing-style/rules.yaml#L*) pass "--pr-body: pr-body/banned-word's rule_ref opens skills/writing-style/rules.yaml" ;;
    *) fail "--pr-body: pr-body/banned-word rule_ref [$REF]" ;;
esac

FAKE_SHIRABE_OUT=$(msg_json "$PB5_TITLE")
# shellcheck disable=SC2086
run --pr-body --owned $OWNED_ARGS
GOT=$(findings | jq -r '.rule_id' | tr '\n' ' ')
if [ "$RC" -eq 1 ] && [ "$GOT" = "pr-body/banned-word " ]; then
    pass "--pr-body --owned: a title-only PB5 finding is pr-body/banned-word, not pr-body/conventional-title"
else
    fail "--pr-body --owned: title PB5 rc $RC, rules [$GOT]"
fi

FAKE_SHIRABE_OUT=$(msg_json "$PB2" "$PB5_BODY")
run --pr-body
GOT=$(findings | jq -r '.rule_id' | tr '\n' ' ')
if [ "$RC" -eq 1 ] && [ "$GOT" = "pr-body/one-separator pr-body/banned-word " ]; then
    pass "--pr-body: PB2 and PB5 together print both findings and exit 1"
else
    fail "--pr-body: PB2+PB5 rc $RC, rules [$GOT]"
fi

# A validator exit 1 for any reason but the flag holds the gate, without the
# upgrade wording.
FAKE_SHIRABE_RC=1
FAKE_SHIRABE_OUT=''
run --pr-body
if [ "$RC" -eq 2 ] && [ "$(finding_count)" -eq 0 ] && ! grep -q 'predates' "$WORKDIR/stderr"; then
    pass "--pr-body: a validator exit 1 for another reason holds the gate (2) without the upgrade message"
else
    fail "--pr-body: validator exit 1: rc $RC, stderr $(cat "$WORKDIR/stderr")"
fi

# An installed shirabe older than --writing-style: clap rejects the flag (exit
# 1, its usage hint on the last stderr line), and the gate holds and says to
# upgrade. That validator lives in its own directory, put ahead of $BIN for
# this one run, so the suite's stand-in is never rewritten. The message is the
# one clap prints today; the gate matches on it, so a clap upgrade that
# rewords it would show up here first.
OLDSH="$WORKDIR/oldsh"
mkdir -p "$OLDSH"
cat > "$OLDSH/shirabe" <<'EOF'
#!/usr/bin/env bash
echo "error: unexpected argument '--writing-style' found" >&2
echo "" >&2
echo "For more information, try '--help'." >&2
exit 1
EOF
chmod +x "$OLDSH/shirabe"
OUT=$(PATH="$OLDSH:$PATH" "$CHECK" --pr-body 2>"$WORKDIR/stderr")
RC=$?
if [ "$RC" -eq 2 ] && [ "$(finding_count)" -eq 0 ] && grep -q 'predates the PR writing-style check' "$WORKDIR/stderr"; then
    pass "--pr-body: a shirabe that rejects --writing-style holds the gate (2), no finding, and names the upgrade"
else
    fail "--pr-body: old shirabe: rc $RC, stderr $(cat "$WORKDIR/stderr")"
fi

# No shirabe on PATH at all.
NOSH="$WORKDIR/nosh"
mkdir -p "$NOSH"
for t in gh record.sh owned-pr.sh; do cp "$BIN/$t" "$NOSH/"; done
for t in jq bash cat sed grep awk mktemp rm tail wc tr cut head dirname printf mkdir cp git; do
    p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NOSH/$t"
done
OUT=$(PATH="$NOSH" "$CHECK" --pr-body 2>"$WORKDIR/stderr")
RC=$?
if [ "$RC" -eq 2 ] && [ "$(finding_count)" -eq 0 ]; then
    pass "--pr-body: no shirabe on PATH holds the gate (2) with no finding"
else
    fail "--pr-body: without shirabe: rc $RC, stdout $OUT"
fi

# This plugin's rules.yaml missing from an installed-style copy: the gate
# holds with no finding (the control is the unaltered copy deciding).
NORULES="$WORKDIR/norules"
rf_test_copy_plugin "$NORULES"
FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"clean","findings":[]}'
OUT=$(SHIRABE_FINDINGS_LOG="" "$NORULES/skills/work-on/scripts/check-pr-output.sh" --pr-body 2>"$WORKDIR/stderr")
RC_CONTROL=$?
rm -f "$NORULES/skills/writing-style/rules.yaml"
OUT=$(SHIRABE_FINDINGS_LOG="" "$NORULES/skills/work-on/scripts/check-pr-output.sh" --pr-body 2>"$WORKDIR/stderr")
RC=$?
if [ "$RC_CONTROL" -eq 0 ] && [ "$RC" -eq 2 ] && [ "$(finding_count)" -eq 0 ]; then
    pass "--pr-body: a plugin copy without its rules.yaml holds the gate (2) with no finding"
else
    fail "--pr-body: missing rules.yaml: control rc $RC_CONTROL, rc $RC, stderr $(cat "$WORKDIR/stderr")"
fi

# --- --pr-body against a real validator -----------------------------------------
#
# The stand-in can't show that the real messages carry the prefix the gate
# maps on, or that a broken rules file stops the real validator.

real_ok=0
if [ -n "$REAL_SHIRABE" ] && [ -x "$REAL_SHIRABE" ] \
    && grep -q -- '--writing-style' <<<"$("$REAL_SHIRABE" validate --help 2>/dev/null)"; then
    real_ok=1
fi
if [ "$real_ok" -eq 0 ]; then
    if [ "${CHECK_PR_OUTPUT_REQUIRE_SHIRABE:-0}" = 1 ]; then
        fail "real validator: no shirabe with --writing-style (got [${REAL_SHIRABE:-none}])"
    else
        echo "SKIP: real-validator cases (no shirabe with --writing-style; set CHECK_PR_OUTPUT_REAL_SHIRABE)"
    fi
else
    REALBIN="$WORKDIR/realbin"
    mkdir -p "$REALBIN" "$WORKDIR/realcwd"
    ln -sf "$REAL_SHIRABE" "$REALBIN/shirabe"
    real_run() { # <plugin root> [args...]: run that plugin's gate with the real validator
        local root=$1
        shift
        OUT=$(cd "$WORKDIR/realcwd" && PATH="$REALBIN:$PATH" "$root/skills/work-on/scripts/check-pr-output.sh" "$@" 2>"$WORKDIR/stderr")
        RC=$?
    }
    PLUGIN_ROOT_HERE=$(cd "$SCRIPT_DIR/../../.." && pwd -P)

    FAKE_GH_BRANCH_JSON=$(pr_json "feat: a plain title" "Part one.

We will leverage the cache.

---

Part two.")
    real_run "$PLUGIN_ROOT_HERE" --pr-body
    F=$(findings)
    if [ "$RC" -eq 1 ] && [ "$(finding_count)" -eq 1 ] \
        && [ "$(printf '%s' "$F" | jq -r '.rule_id')" = pr-body/banned-word ] \
        && [ "$(printf '%s' "$F" | jq -r '.rule_ref')" = "$WANT_REF" ] \
        && grep -qF -- "$SUMMARY: [PB5] writing-style banned word \"leverage\" on line 3 -- Prefer the plain verb." <<<"$(jq -r '.message' <<<"$F")"; then
        pass "real validator: body line 3's leverage is one pr-body/banned-word finding with the summary, line, guidance and rule_ref"
    else
        fail "real validator: line-3 case rc $RC, findings [$F], stderr $(cat "$WORKDIR/stderr")"
    fi

    MANY=""
    i=0
    while [ "$i" -lt 60 ]; do MANY="$MANY
leverage
"; i=$((i + 1)); done
    FAKE_GH_BRANCH_JSON=$(pr_json "feat: a plain title" "Part one.
$MANY
---

Part two.")
    real_run "$PLUGIN_ROOT_HERE" --pr-body
    N=$(findings | jq -r 'select(.rule_id == "pr-body/banned-word") | .message' | grep -c 'truncated at 50')
    if [ "$RC" -eq 1 ] && [ "$(finding_count)" -eq 51 ] && [ "$N" -eq 1 ]; then
        pass "real validator: 60 occurrences give 50 findings and one truncation finding, all pr-body/banned-word"
    else
        fail "real validator: truncation rc $RC, $(finding_count) findings, $N truncation"
    fi

    # Broken copies of this plugin's rules.yaml: the anchors the registry reads
    # stay, so the rule still resolves and the validator is what refuses.
    BROKEN="$WORKDIR/broken"
    rf_test_copy_plugin "$BROKEN"
    FAKE_GH_BRANCH_JSON=$(pr_json "feat: a plain title" "We will leverage it.

---

Part two.")
    printf '%s\n' '# Banned words, grouped by the category the guidance uses.' 'words: [unclosed' '# - Moreover' \
        > "$BROKEN/skills/writing-style/rules.yaml"
    real_run "$BROKEN" --pr-body
    if [ "$RC" -eq 2 ] && [ "$(finding_count)" -eq 0 ]; then
        pass "real validator: invalid YAML in the plugin's rules.yaml holds the gate (2) with no finding"
    else
        fail "real validator: invalid rules rc $RC, stdout $OUT"
    fi
    printf '%s\n' '# Banned words, grouped by the category the guidance uses.' 'words: []' '# - Moreover' \
        > "$BROKEN/skills/writing-style/rules.yaml"
    real_run "$BROKEN" --pr-body
    if [ "$RC" -eq 2 ] && [ "$(finding_count)" -eq 0 ]; then
        pass "real validator: an emptied words: block holds the gate (2) with no finding"
    else
        fail "real validator: empty rules rc $RC, stdout $OUT"
    fi
fi

# --- the rule registry ----------------------------------------------------------

# The stand-in validator reports a PB3 violation, so the unaltered copy's
# control run in rf_test_refusals decides (exit 1) and the --pr-body rules are
# the ones the refusals exercise.
FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB3")
rf_test_refusals "--pr-body" skills/work-on/scripts/check-pr-output.sh pr-body/no-ai-trailer --pr-body
# The log verify-findings checks holds the PB5 findings printed above, so the
# new rule is among the ones it verifies.
if grep -q '"rule_id":"pr-body/banned-word"' "$SHIRABE_FINDINGS_LOG"; then
    pass "--pr-body: the verified findings log includes pr-body/banned-word findings"
else
    fail "--pr-body: no pr-body/banned-word finding in $SHIRABE_FINDINGS_LOG"
fi
rf_test_verify "--pr-body"

echo
echo "check-pr-output_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
