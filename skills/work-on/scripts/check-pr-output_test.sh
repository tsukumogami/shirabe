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

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/check-pr-output-test.XXXXXX") || exit 1
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 1
cleanup() { case "${WORKDIR:-}" in */check-pr-output-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
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

# --- --pr-body: stages -----------------------------------------------------------
#
# A finding prints at its rule's stage and only a block finding fails the gate.
# The copies' findings go to logs of their own, verified against each copy's
# registry, so the suite's log keeps only real-registry findings.

PR_PATHS="skills/work-on/scripts/check-pr-output.sh skills/writing-style/rules.yaml"
pr_body_in_copy() { # <copy>
    "$1/skills/work-on/scripts/check-pr-output.sh" --pr-body
}
FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB2")
# shellcheck disable=SC2086 # the two paths, split on purpose
rf_test_stages "--pr-body" pr-body/one-separator 1 "" pr_body_in_copy $PR_PATHS

STAGE_COPY="$RF_TEST_DIR/stage-copy"
STAGE_LOG="$RF_TEST_DIR/stage-copy.log"
# run_copy: --pr-body from the copy; sets OUT and RC, stderr to the usual file.
run_copy() {
    : > "$STAGE_LOG"
    OUT=$(SHIRABE_FINDINGS_LOG="$STAGE_LOG" "$STAGE_COPY/skills/work-on/scripts/check-pr-output.sh" --pr-body 2>"$WORKDIR/stderr")
    RC=$?
}

# A listed finding below block is still a listed finding: no fallback is added
# for it, and the gate passes.
# shellcheck disable=SC2086 # the two paths, split on purpose
if rf_test_stage_copy "$STAGE_COPY" pr-body/one-separator warn $PR_PATHS; then
    run_copy
    if [ "$RC" -eq 0 ] && [ "$(findings | jq -r '.rule_id' | tr '\n' ' ')" = "pr-body/one-separator " ]; then
        pass "--pr-body: a warn-stage finding as the only listed one exits 0 with no pr-body/conformance finding"
    else
        fail "--pr-body: warn-stage only: rc $RC, findings $OUT"
    fi
    rf_test_verify_copy "--pr-body warn-only" "$STAGE_COPY" "$STAGE_LOG"
    if grep -qF 'the findings above are of rules below it' "$WORKDIR/stderr"; then
        pass "--pr-body: a passing run that printed a finding points at the findings above"
    else
        fail "--pr-body: warn-stage only: stderr $(cat "$WORKDIR/stderr")"
    fi
else
    fail "--pr-body: could not make a plugin copy with pr-body/one-separator at warn"
fi

# A finding of a retired rule prints nothing, so the closing line must not
# point at findings above it.
# shellcheck disable=SC2086 # the two paths, split on purpose
if rf_test_stage_copy "$STAGE_COPY" pr-body/one-separator retired $PR_PATHS; then
    run_copy
    if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && ! grep -qF 'findings above' "$WORKDIR/stderr" \
        && grep -qF 'every finding is of a retired rule, so none printed' "$WORKDIR/stderr"; then
        pass "--pr-body: a retired-only finding prints nothing and the closing line says none printed"
    else
        fail "--pr-body: retired only: rc $RC, out [$OUT], stderr $(cat "$WORKDIR/stderr")"
    fi
else
    fail "--pr-body: could not make a plugin copy with pr-body/one-separator at retired"
fi

# Violations the validator didn't list still fail the gate, through the
# fallback rule.
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"violations","findings":[]}'
run --pr-body
if [ "$RC" -eq 1 ] && [ "$(findings | jq -r '.rule_id' | tr '\n' ' ')" = "pr-body/conformance " ]; then
    pass "--pr-body: a validator exit 2 listing no finding prints the pr-body/conformance fallback and exits 1"
else
    fail "--pr-body: unlisted violations: rc $RC, findings $OUT"
fi

# PB4's text is released only when its finding is shown as something to act
# on: at warn and at block, once; at shadow, not at all.
FAKE_SHIRABE_OUT=$(msg_json "$PB4" "$PB4")
for pair in shadow:0:0 warn:0:1 block:1:1; do
    stage=${pair%%:*}; rest=${pair#*:}; want_rc=${rest%%:*}; want_rel=${rest#*:}
    # shellcheck disable=SC2086 # the two paths, split on purpose
    if rf_test_stage_copy "$STAGE_COPY" pr-body/no-heading-in-part1 "$stage" $PR_PATHS; then
        run_copy
        if [ "$RC" -eq "$want_rc" ] && [ "$(release_count)" -eq "$want_rel" ] && [ "$(finding_count)" -eq 2 ]; then
            pass "--pr-body: two PB4 findings at $stage exit $want_rc and release PB4's text $want_rel time(s)"
        else
            fail "--pr-body: PB4 at $stage: rc $RC, $(finding_count) findings, $(release_count) releases"
        fi
        rf_test_verify_copy "--pr-body PB4 at $stage" "$STAGE_COPY" "$STAGE_LOG"
    else
        fail "--pr-body: could not make a plugin copy with pr-body/no-heading-in-part1 at $stage"
    fi
done
rm -rf "$STAGE_COPY" "$STAGE_LOG"
FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"clean","findings":[]}'

# --- --pr-body: the escalation ladder -------------------------------------------
#
# With the template's ladder context, PB4 is delivered like every rule: its
# summary on the first failure, its text from the second (koto's count, read
# from the session log). The cases above, run without the context, are the
# no-ladder path: PB4's text on every failure.

LADDER_LOG="$WORKDIR/ladder.jsonl"
run_ladder() {
    OUT=$(SHIRABE_GATE_LOG="$LADDER_LOG" SHIRABE_GATE_NAME=pr_body_conformant \
        SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" \
        "$CHECK" "$@" 2>"$WORKDIR/stderr")
    RC=$?
}
# same_with_ladder <label>: the run with the context exits and prints on
# standard output exactly what the run without it did.
same_with_ladder() {
    local plain_out plain_rc
    run --pr-body; plain_out=$OUT; plain_rc=$RC
    run_ladder --pr-body
    if [ "$RC" -eq "$plain_rc" ] && [ "$OUT" = "$plain_out" ]; then
        pass "--pr-body ladder: $1 exits and prints the same with the context"
    else
        fail "--pr-body ladder: $1 differs with the context: rc $RC vs $plain_rc"
    fi
}

FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB4")
rf_test_ladder_log "$LADDER_LOG" pr_creation pr_body_conformant
run_ladder --pr-body
if [ "$RC" -eq 1 ] && [ "$(release_count)" -eq 0 ] \
    && [ "$(findings | jq -r '.rule_id')" = pr-body/no-heading-in-part1 ]; then
    pass "--pr-body ladder: PB4's first failure prints its summary finding and no text"
else
    fail "--pr-body ladder: count 1: rc $RC, $(release_count) releases, stderr $(cat "$WORKDIR/stderr")"
fi
same_with_ladder "a PB4 violation at count 1"

rf_test_ladder_log "$LADDER_LOG" pr_creation pr_body_conformant pr-body/no-heading-in-part1 1
run_ladder --pr-body
if [ "$RC" -eq 1 ] && [ "$(release_count)" -eq 1 ] && grep -qF -- "$PB4_FIRST" "$WORKDIR/stderr" \
    && ! grep -q '^::shirabe-check-exit::' "$WORKDIR/stderr"; then
    pass "--pr-body ladder: PB4's second failure releases its text once"
else
    fail "--pr-body ladder: count 2: rc $RC, $(release_count) releases, stderr $(cat "$WORKDIR/stderr")"
fi
same_with_ladder "a PB4 violation at count 2"

rf_test_ladder_log "$LADDER_LOG" pr_creation pr_body_conformant pr-body/no-heading-in-part1 2
run_ladder --pr-body
if [ "$RC" -eq 1 ] && [ "$(release_count)" -eq 1 ] \
    && grep -q '^::shirabe-check-exit::{"rule_id":"pr-body/no-heading-in-part1","count":3,"state":"pr_creation","submit":{"pr_status":"check_unsatisfiable"' "$WORKDIR/stderr"; then
    pass "--pr-body ladder: PB4's third failure offers the pr_creation exit"
else
    fail "--pr-body ladder: count 3: rc $RC, stderr $(cat "$WORKDIR/stderr")"
fi

FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"clean","findings":[]}'
same_with_ladder "a conformant body"
FAKE_SHIRABE_RC=1
FAKE_SHIRABE_OUT='not json'
same_with_ladder "a validator that fails to run (undecided)"

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
rf_test_drop_plugin "$NORULES"

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
    rf_test_drop_plugin "$BROKEN"
fi

# --- --deferral-record: the verification deferral in the body (#1012) -----------

DREASON="host is in a measurement window until 02:40Z"
FAKE_GH_RC=0
export FAKE_GH_RC

# The body holds the deferral only in a repository that opts in to workflow
# content; everything from here to the rule registry runs in one, then the
# default is pinned at the end of the section.
SUITE_PWD=$PWD
mkdir -p "$WORKDIR/include-repo" "$WORKDIR/omit-repo"
printf '# A repo\n\n## PR Workflow Content: include\n' > "$WORKDIR/include-repo/CLAUDE.md"
printf '# A repo\n' > "$WORKDIR/omit-repo/CLAUDE.md"
cd "$WORKDIR/include-repo" || exit 2
deferral_body() {
    # deferral_body <local line> <reason line> <record line>
    pr_json "feat: a deferred change" "A change.

---

## Verification

$1
$2
$3

Fixes #12"
}

FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "Reason: $DREASON" "Hosted CI is the build of record for this change.")
run --deferral-record --reason "$DREASON"
if [ "$RC" -eq 0 ] && [ -z "$(findings)" ]; then
    pass "--deferral-record: a body with all three parts passes, with no finding"
else
    fail "--deferral-record: complete body rc $RC, stdout [$OUT]"
fi
if [ "$(cat "$LOG/gh/arg.1" "$LOG/gh/arg.2" "$LOG/gh/arg.3" "$LOG/gh/arg.4" 2>/dev/null | tr -d '\n')" = "prview--jsonbody" ] \
    && [ "$(cat "$LOG/gh/argc")" = 4 ]; then
    pass "--deferral-record: reads the checked-out branch's body with gh pr view --json body"
else
    fail "--deferral-record: gh was called with $(cat "$LOG/gh/argc" 2>/dev/null) argument(s)"
fi

FAKE_GH_BRANCH_JSON=$(deferral_body "LOCAL VERIFICATION DID NOT RUN." \
    "Reason: $DREASON" "hosted ci is the build of record.")
run --deferral-record --reason "$DREASON"
[ "$RC" -eq 0 ] && pass "--deferral-record: the two phrases match without regard to case" \
    || fail "--deferral-record: case-folded phrases rc $RC"

FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "Reason: the host was busy" "Hosted CI is the build of record for this change.")
run --deferral-record --reason "$DREASON"
if [ "$RC" -eq 1 ] && [ -z "$(findings)" ] \
    && grep -qF "no line reading exactly: Reason: $DREASON" "$WORKDIR/stderr"; then
    pass "--deferral-record: a body with another reason fails (1), naming the line it wants, with no finding"
else
    fail "--deferral-record: wrong reason rc $RC, stdout [$OUT], stderr [$(cat "$WORKDIR/stderr")]"
fi

# A reason is a whole `Reason: <reason>` line (#1053). Each short reason below
# is inside the required "hosted CI is the build of record" phrase, so a
# substring match would pass a body that never records it.
for short in CI hosted build "hosted CI" "build of record"; do
    FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
        "Reason: the host was busy" "Hosted CI is the build of record for this change.")
    run --deferral-record --reason "$short"
    if [ "$RC" -eq 1 ] && grep -qF "no line reading exactly: Reason: $short" "$WORKDIR/stderr"; then
        pass "--deferral-record: reason [$short], found only inside the build-of-record phrase, fails (1)"
    else
        fail "--deferral-record: reason [$short] inside the phrase rc $RC, stderr [$(cat "$WORKDIR/stderr")]"
    fi
done

FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "Reason: CI" "Hosted CI is the build of record for this change.")
run --deferral-record --reason CI
[ "$RC" -eq 0 ] && pass "--deferral-record: a short reason on its own Reason: line passes" \
    || fail "--deferral-record: short reason on its line rc $RC, stderr [$(cat "$WORKDIR/stderr")]"

FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "The $DREASON, so nothing ran here." "Hosted CI is the build of record for this change.")
run --deferral-record --reason "$DREASON"
[ "$RC" -eq 1 ] && pass "--deferral-record: the reason in prose, with no Reason: line, fails (1)" \
    || fail "--deferral-record: reason in prose rc $RC"

for shape in "- Reason: $DREASON" "Reason:  $DREASON" "reason: $DREASON" "Reason: $DREASON." \
    " Reason: $DREASON" "**Reason:** $DREASON" "> Reason: $DREASON"; do
    FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
        "$shape" "Hosted CI is the build of record for this change.")
    run --deferral-record --reason "$DREASON"
    [ "$RC" -eq 1 ] && pass "--deferral-record: a line [$shape] is not the Reason: line (1)" \
        || fail "--deferral-record: line [$shape] rc $RC"
done

# One reason that starts another: the longer one's line must not satisfy the
# shorter, in either order of the --reason flags.
PREFIX="runner pool is down"
LONGER="runner pool is down until Monday"
FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "Reason: $LONGER" "Hosted CI is the build of record for this change.")
run --deferral-record --reason "$PREFIX" --reason "$LONGER"
if [ "$RC" -eq 1 ] && grep -qxF "check-pr-output: the PR body has no line reading exactly: Reason: $PREFIX" "$WORKDIR/stderr" \
    && ! grep -qF "exactly: Reason: $LONGER" "$WORKDIR/stderr"; then
    pass "--deferral-record: a reason that starts a longer one isn't satisfied by the longer one's line (1)"
else
    fail "--deferral-record: prefix reason rc $RC, stderr [$(cat "$WORKDIR/stderr")]"
fi
run --deferral-record --reason "$LONGER" --reason "$PREFIX"
[ "$RC" -eq 1 ] && pass "--deferral-record: the same, with the longer reason given first (1)" \
    || fail "--deferral-record: prefix reason, longer first, rc $RC"
FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "Reason: $PREFIX" "Hosted CI is the build of record for this change.")
run --deferral-record --reason "$LONGER"
[ "$RC" -eq 1 ] && pass "--deferral-record: the shorter reason's line doesn't satisfy the longer reason (1)" \
    || fail "--deferral-record: longer reason against the shorter line rc $RC"
FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "Reason: $PREFIX
Reason: $LONGER
Reason: CI" "Hosted CI is the build of record for this change.")
run --deferral-record --reason "$PREFIX" --reason "$LONGER" --reason CI
[ "$RC" -eq 0 ] && pass "--deferral-record: three reasons, a prefix pair among them, each on its own Reason: line, pass" \
    || fail "--deferral-record: three reason lines rc $RC, stderr [$(cat "$WORKDIR/stderr")]"

# A body edited on GitHub's web form comes back with CRLF line ends.
CR=$(printf '\r')
FAKE_GH_BRANCH_JSON=$(pr_json "feat: a deferred change" "A change.$CR
$CR
---$CR
$CR
## Verification$CR
$CR
Local verification did not run: it was deferred to hosted CI.$CR
Reason: $DREASON$CR
Hosted CI is the build of record for this change.$CR
$CR
Fixes #12")
run --deferral-record --reason "$DREASON"
[ "$RC" -eq 0 ] && pass "--deferral-record: a CRLF body with the Reason: line passes" \
    || fail "--deferral-record: CRLF body rc $RC, stderr [$(cat "$WORKDIR/stderr")]"
FAKE_GH_BRANCH_JSON=$(pr_json "feat: a deferred change" "Local verification did not run.$CR
Reason: the host was busy$CR
Hosted CI is the build of record.$CR")
run --deferral-record --reason "$DREASON"
[ "$RC" -eq 1 ] && pass "--deferral-record: a CRLF body without the Reason: line still fails (1)" \
    || fail "--deferral-record: CRLF body, wrong reason, rc $RC"

# GitHub renders a lone CR as a line break, so a CR inside what looks like
# the Reason line splits it: none of these bodies shows `Reason: foo`.
for split in "Reason: fo${CR}o" "Rea${CR}son: foo" "Reason: ${CR}foo"; do
    FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
        "$split" "Hosted CI is the build of record for this change.")
    run --deferral-record --reason foo
    [ "$RC" -eq 1 ] && pass "--deferral-record: a lone CR splitting the Reason line fails (1) [$(printf '%s' "$split" | tr '\r' '^')]" \
        || fail "--deferral-record: lone CR split [$(printf '%s' "$split" | tr '\r' '^')] rc $RC"
done
# ... and a lone CR before a real Reason line is a line break before it.
FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "Notes.${CR}Reason: foo" "Hosted CI is the build of record for this change.")
run --deferral-record --reason foo
[ "$RC" -eq 0 ] && pass "--deferral-record: a Reason line after a lone CR is its own line and passes" \
    || fail "--deferral-record: Reason line after a lone CR rc $RC, stderr [$(cat "$WORKDIR/stderr")]"

FAKE_GH_BRANCH_JSON=$(deferral_body "Local verification did not run: it was deferred to hosted CI." \
    "Reason: $DREASON" "CI will run on the pull request.")
run --deferral-record --reason "$DREASON"
if [ "$RC" -eq 1 ] && grep -q 'build of record' "$WORKDIR/stderr"; then
    pass "--deferral-record: a body that doesn't name hosted CI as the build of record fails (1)"
else
    fail "--deferral-record: no build-of-record line rc $RC, stderr [$(cat "$WORKDIR/stderr")]"
fi

FAKE_GH_BRANCH_JSON=$(deferral_body "Tests were skipped." \
    "Reason: $DREASON" "Hosted CI is the build of record for this change.")
run --deferral-record --reason "$DREASON"
if [ "$RC" -eq 1 ] && grep -q 'local verification did not run' "$WORKDIR/stderr"; then
    pass "--deferral-record: a body that doesn't say local verification did not run fails (1)"
else
    fail "--deferral-record: no local line rc $RC, stderr [$(cat "$WORKDIR/stderr")]"
fi

FAKE_GH_BRANCH_JSON=$(pr_json "feat: a plain change" "A change.

---

Fixes #12")
run --deferral-record --reason "$DREASON"
[ "$RC" -eq 1 ] && pass "--deferral-record: a body with no Verification section fails (1)" \
    || fail "--deferral-record: no section rc $RC"

run --deferral-record --reason ""
[ "$RC" -eq 2 ] && pass "--deferral-record: an empty reason can't be decided (2)" \
    || fail "--deferral-record: empty reason rc $RC"
run --deferral-record
[ "$RC" -eq 2 ] && pass "--deferral-record: no --reason is a usage error (2)" \
    || fail "--deferral-record: no --reason rc $RC"
run --deferral-record --because "$DREASON"
[ "$RC" -eq 2 ] && pass "--deferral-record: an unknown flag is a usage error (2)" \
    || fail "--deferral-record: unknown flag rc $RC"

FAKE_GH_RC=1
run --deferral-record --reason "$DREASON"
[ "$RC" -eq 2 ] && pass "--deferral-record: a failed gh read can't be decided (2)" \
    || fail "--deferral-record: gh failure rc $RC"
FAKE_GH_RC=0

# --- --deferral-record with several reasons and --owned (/execute's shared PR, #1017)

DREASON2="CI only while the runner pool is down"
FAKE_GH_OWNED_JSON=$(pr_json "feat: a shared change" "A change.

---

## Verification

Local verification did not run: it was deferred to hosted CI.
Reason: $DREASON
Reason: $DREASON2
Hosted CI is the build of record for this change.")
FAKE_GH_BRANCH_JSON=$(pr_json "feat: the branch PR" "Branch body.

---

Context.")
export FAKE_OWNED_OUT FAKE_OWNED_RC
FAKE_OWNED_OUT="$URL1"
FAKE_OWNED_RC=0

# shellcheck disable=SC2086
run --deferral-record --reason "$DREASON" --reason "$DREASON2" --owned $OWNED_ARGS
if [ "$RC" -eq 0 ] && [ "$(cat "$LOG/gh/arg.3" 2>/dev/null)" = "$URL1" ]; then
    pass "--deferral-record --owned: reads the owned PR's body and passes with both reasons"
else
    fail "--deferral-record --owned: two reasons rc $RC, gh arg 3 [$(cat "$LOG/gh/arg.3" 2>/dev/null)], stderr [$(cat "$WORKDIR/stderr")]"
fi
if [ "$(cat "$LOG/owned/arg.1" "$LOG/owned/arg.2" 2>/dev/null | tr -d '\n')" = "--repoacme/widgets" ]; then
    pass "--deferral-record --owned: hands the arguments after --owned to owned-pr.sh"
else
    fail "--deferral-record --owned: owned-pr.sh got [$(cat "$LOG/owned/arg.1" "$LOG/owned/arg.2" 2>/dev/null)]"
fi

# shellcheck disable=SC2086
run --deferral-record --reason "$DREASON" --reason "a reason no child gave" --owned $OWNED_ARGS
if [ "$RC" -eq 1 ] && grep -qF 'exactly: Reason: a reason no child gave' "$WORKDIR/stderr" \
    && ! grep -qF "exactly: Reason: $DREASON" "$WORKDIR/stderr"; then
    pass "--deferral-record: a second reason the body lacks fails (1), naming only that reason"
else
    fail "--deferral-record: missing second reason rc $RC, stderr [$(cat "$WORKDIR/stderr")]"
fi

run --deferral-record --reason "$DREASON" --reason "$DREASON2"
[ "$RC" -eq 1 ] && pass "--deferral-record without --owned reads the checked-out branch's PR, not the owned one (1)" \
    || fail "--deferral-record without --owned: rc $RC"

FAKE_OWNED_RC=3
FAKE_OWNED_OUT=""
# shellcheck disable=SC2086
run --deferral-record --reason "$DREASON" --owned $OWNED_ARGS
[ "$RC" -eq 2 ] && pass "--deferral-record --owned: no single owned PR can't be decided (2)" \
    || fail "--deferral-record --owned: lookup 3 rc $RC"
FAKE_OWNED_RC=0
FAKE_OWNED_OUT="$URL1"

run --deferral-record --reason "$DREASON" --owned
[ "$RC" -eq 2 ] && pass "--deferral-record: --owned with no arguments is a usage error (2)" \
    || fail "--deferral-record: bare --owned rc $RC"
run --deferral-record --reason "$DREASON" --reason
[ "$RC" -eq 2 ] && pass "--deferral-record: a --reason with no value is a usage error (2)" \
    || fail "--deferral-record: dangling --reason rc $RC"
run --deferral-record --reason "$DREASON" --reason ""
[ "$RC" -eq 2 ] && pass "--deferral-record: an empty second reason can't be decided (2)" \
    || fail "--deferral-record: empty second reason rc $RC"
# grep -F would read a reason with a newline as two patterns, either of which
# would do, so a reason must be one line.
# shellcheck disable=SC2086
run --deferral-record --reason "a reason no child gave
Hosted CI is the build of record for this change." --owned $OWNED_ARGS
[ "$RC" -eq 2 ] && pass "--deferral-record: a reason over two lines can't be decided (2)" \
    || fail "--deferral-record: two-line reason rc $RC"
# shellcheck disable=SC2086
run --deferral-record --reason "$DREASON$(printf '\r')" --owned $OWNED_ARGS
[ "$RC" -eq 2 ] && pass "--deferral-record: a reason with a carriage return can't be decided (2)" \
    || fail "--deferral-record: reason with a CR rc $RC"
for blank in " " "   " "$(printf '\t')"; do
    # shellcheck disable=SC2086
    run --deferral-record --reason "$blank" --owned $OWNED_ARGS
    [ "$RC" -eq 2 ] && pass "--deferral-record: a reason of spaces alone can't be decided (2)" \
        || fail "--deferral-record: blank reason [$blank] rc $RC"
done
# shellcheck disable=SC2086
run --deferral-record --owned $OWNED_ARGS
[ "$RC" -eq 2 ] && pass "--deferral-record: --owned with no --reason is a usage error (2)" \
    || fail "--deferral-record: --owned without a reason rc $RC"

# --- workflow content: the default omits it, a repository opts in (#1114) ------

cd "$WORKDIR/omit-repo" || exit 2
rm -rf "$LOG/gh"
FAKE_GH_BRANCH_JSON=$(pr_json "feat: a deferred change" "A change.

---

Hosted CI verified this change.

Fixes #12")
run --deferral-record --reason "$DREASON"
expect_rc "--deferral-record, default: passes without the deferral in the body" 0
[ ! -e "$LOG/gh/calls" ] && pass "--deferral-record, default: reads nothing from GitHub" \
    || fail "--deferral-record, default: gh was called"
# shellcheck disable=SC2086
run --deferral-record --reason "$DREASON" --owned $OWNED_ARGS
expect_rc "--deferral-record --owned, default: passes too" 0
run --deferral-record
expect_rc "--deferral-record, default: still refuses a missing --reason (2)" 2

FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"clean","findings":[]}'
H40=0123456789abcdef0123456789abcdef01234567
WC_BODY="Reads the review round from the session.

---

## Review panel

| Seat | Model | Run | Verdict | Reviewed head |
|---|---|---|---|---|
| architect | sonnet | agent-1 | pass | $H40 |

Plan: docs/plans/PLAN-demo.md
Roadmap: docs/roadmaps/ROADMAP-demo.md
Implements docs/plans/PLAN-demo.md.

Fixes #12"
FAKE_GH_BRANCH_JSON=$(pr_json "feat: read the round" "$WC_BODY")
run --pr-body
expect_rc "--pr-body, default: workflow records in the body hold the gate (1)" 1
check_shape "--pr-body, default: workflow records"
[ "$(findings | jq -r 'select(.rule_id == "pr-body/workflow-content") | .rule_id' | grep -c .)" -eq 5 ] \
    && pass "--pr-body, default: the heading, the table, Plan:, Roadmap: and Implements are five findings" \
    || fail "--pr-body, default: workflow-content findings: $OUT"
WC_MESSAGES=$(findings | jq -r .message)
grep -qF 'a `## Review panel` heading (line 5)' <<<"$WC_MESSAGES" \
    && pass "--pr-body, default: a finding names the record and its line" \
    || fail "--pr-body, default: no line-numbered heading finding: $OUT"
FAKE_SHIRABE_RC=2
FAKE_SHIRABE_OUT=$(msg_json "$PB1")
run --pr-body
[ "$(findings | jq -r .rule_id | sort -u | tr '\n' ' ')" = "pr-body/conventional-title pr-body/workflow-content " ] \
    && pass "--pr-body, default: workflow findings print beside the validator's" \
    || fail "--pr-body, default: with a validator finding: $OUT"
FAKE_SHIRABE_RC=0
FAKE_SHIRABE_OUT='{"schema":"shirabe-pr-body/v1","outcome":"clean","findings":[]}'
FAKE_GH_BRANCH_JSON=$(pr_json "feat: read the round" "Reads the review round from the session.

---

The plan was to read the round from the review panel; the Plan file is gone.
A run implements docs/plans/PLAN-demo.md in prose here.

\`\`\`text
## Review panel
| Seat | Model | Run | Verdict | Reviewed head |
Plan: docs/plans/PLAN-demo.md
\`\`\`

Fixes #12")
run --pr-body
expect_rc "--pr-body, default: prose about plans and panels, and records inside a fence, pass" 0
[ "$(finding_count)" -eq 0 ] && pass "--pr-body, default: ... with no finding" || fail "--pr-body, default: fenced records: $OUT"

cd "$WORKDIR/include-repo" || exit 2
FAKE_GH_BRANCH_JSON=$(pr_json "feat: read the round" "$WC_BODY")
run --pr-body
expect_rc "--pr-body, include: today's workflow records pass" 0
[ "$(finding_count)" -eq 0 ] && pass "--pr-body, include: ... with no finding" || fail "--pr-body, include: $OUT"
cd "$SUITE_PWD" || exit 2

# The run's own traces, refused under omit: a marker line (built from parts
# so this file carries none), a run line, the PR index heading and a line of
# it, the merge order heading, a Run record line, and a result line.
RUN_TRACES="Reads the round.

---

<!-- shirabe""-run: 0123456789abcdef0123456789abcdef -->
topic=demo
run=0123456789abcdef0123456789abcdef

## PR Index

- core | acme/repo:docs/plans/PLAN-demo.md#11 | open

## Merge Order

Run record: execute-demo (run 0123456789abcdef0123456789abcdef)
record: unpinned

Fixes #12"
FAKE_GH_BRANCH_JSON=$(pr_json "feat: read the round" "$RUN_TRACES")
run --pr-body
expect_rc "--pr-body, default: the run's traces in the body hold the gate (1)" 1
[ "$(findings | jq -r 'select(.rule_id == "pr-body/workflow-content") | .rule_id' | grep -c .)" -eq 8 ] \
    && pass "--pr-body, default: marker, two run lines, two headings, an index line, a Run record line and a result line are eight findings" \
    || fail "--pr-body, default: run trace findings: $OUT"

# --session reads the switch the run recorded, not the checkout's files. The
# session lives in the record stub koto, asserted to be the koto on PATH.
REC_STUB=$(cd "$SCRIPT_DIR/../../../scripts/testdata/record-koto" && pwd)
export RECORD_KOTO_STORE="$WORKDIR/record-koto-store"
mkdir -p "$RECORD_KOTO_STORE"
case "$(PATH="$REC_STUB:$PATH" command -v koto)" in
    "$REC_STUB/koto") pass "--session cases: the koto on PATH is the record stub" ;;
    *) fail "--session cases: the koto on PATH is not the record stub"; exit 1 ;;
esac
(cd "$SUITE_PWD" && PATH="$REC_STUB:$PATH" koto init work-inc --template t >/dev/null \
    && printf 'include' | PATH="$REC_STUB:$PATH" koto context add work-inc pr_content >/dev/null)
FAKE_GH_BRANCH_JSON=$(pr_json "feat: read the round" "$WC_BODY")
PATH="$REC_STUB:$PATH" run --pr-body --session work-inc
expect_rc "--pr-body --session: a run that recorded include passes its records, whatever the files say" 0
(cd "$WORKDIR/include-repo" && PATH="$REC_STUB:$PATH" koto init work-omit --template t >/dev/null \
    && printf 'omit' | PATH="$REC_STUB:$PATH" koto context add work-omit pr_content >/dev/null)
cd "$WORKDIR/include-repo" || exit 2
PATH="$REC_STUB:$PATH" run --pr-body --session work-omit
expect_rc "--pr-body --session: a run that recorded omit refuses its records in an include checkout (1)" 1
PATH="$REC_STUB:$PATH" run --deferral-record --session work-omit --reason "$DREASON"
expect_rc "--deferral-record --session: a run that recorded omit passes without the body" 0
cd "$SUITE_PWD" || exit 2
run --pr-body --session 'a b'
expect_rc "--pr-body --session with a bad name is a usage error (2)" 2

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
