#!/usr/bin/env bash
# check-hop-document_test.sh -- does check-hop-document.sh hold a /scope hop on
# exactly the document rules it should, name the right rule, and refuse to
# guess?
#
# Each case builds a throwaway repository holding topic documents and runs the
# gate against it. Two kinds of case:
#
#   - real-validator cases run the `shirabe` on PATH, because what they check
#     is which of the validator's findings the gate holds on. They need the
#     validator: where it is missing they SKIP with a notice (the macOS
#     bash-floor leg), and with SCOPE_GATE_REQUIRE_SHIRABE=1 (the Linux job
#     that builds it) a missing validator is a failure, so CI can't report
#     green having asserted nothing;
#   - stub cases put a fake `shirabe` first on PATH, to reach the envelopes and
#     exit codes a real validator doesn't produce on demand (a null line, a
#     wrong schema version, an unmapped code) and to record the arguments the
#     gate passes. They need only bash, git and jq, so they run everywhere.
#
# Every finding line the gate prints is checked against koto's finding shape,
# and logged through SHIRABE_FINDINGS_LOG; the log is verified against the rule
# registry at the end.
#
# Usage: check-hop-document_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-hop-document.sh"
RULES_FILE="$SCRIPT_DIR/../../writing-style/rules.yaml"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$CHECK" ] || { echo "$CHECK is missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/check-hop-document-test.XXXXXX") || exit 1
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 1
cleanup() { case "${WORKDIR:-}" in */check-hop-document-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

REAL_SHIRABE=$(command -v shirabe 2>/dev/null || true)
ORIG_PATH=$PATH

export HOME="$WORKDIR/home"
mkdir -p "$HOME"

# shellcheck source=../../../scripts/lib/rule-findings-testlib.sh
. "$SCRIPT_DIR/../../../scripts/lib/rule-findings-testlib.sh"
rf_test_setup "$WORKDIR"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
git config --global user.email t@example.invalid
git config --global user.name t
git config --global init.defaultBranch main

# shellcheck source=testdata/hop-document-fixtures.sh
. "$SCRIPT_DIR/testdata/hop-document-fixtures.sh"

# --- fixtures and running -------------------------------------------------------

# fixture <name> [<claude-md line>]: a fresh repository in $REPO with one commit
# (and a CLAUDE.md carrying the line, when given).
REPO=""
N=0
fixture() {
    N=$((N + 1))
    REPO="$WORKDIR/fx-$N-$1"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    printf 'readme\n' > "$REPO/README.md"
    [ -z "${2-}" ] || printf '# repo\n\n%s\n' "$2" > "$REPO/CLAUDE.md"
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "chore: seed the repository"
}

# put <path>: write stdin to <path> in $REPO.
put() {
    mkdir -p "$REPO/$(dirname "$1")"
    cat > "$REPO/$1"
}

commit_all() {
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "docs: fixture documents"
}

OUT="$WORKDIR/out"
ERR="$WORKDIR/err"
RC=0
# gate <args...>: run the gate from $REPO's root.
gate() {
    (cd "$REPO" && "$CHECK" "$@") > "$OUT" 2> "$ERR"
    RC=$?
}
# gate_from <dir> <args...>: run the gate from <dir>.
gate_from() {
    local d=$1
    shift
    (cd "$d" && "$CHECK" "$@") > "$OUT" 2> "$ERR"
    RC=$?
}

findings() { sed -n 's/^::koto-finding:://p' "$OUT"; }
finding_count() { findings | awk 'END { print NR }'; }

# expect <label> <rc> [<rule_id>...]: the exit code, and exactly these rule ids
# in this order, each finding in koto's shape.
expect() {
    local label=$1 want=$2 got_ids want_ids shape_ok=1
    shift 2
    want_ids=$(printf '%s\n' "$@" | awk 'NF' )
    got_ids=$(findings | jq -r '.rule_id' 2>/dev/null)
    # A finding missing any of koto's fields makes the shape check fail.
    if [ -s "$OUT" ] && findings | jq -e 'select((.rule_id and .level == "error" and .message and .rule_ref) | not)' >/dev/null 2>&1; then
        shape_ok=0
    fi
    if [ "$RC" -eq "$want" ] && [ "$got_ids" = "$want_ids" ] && [ "$shape_ok" -eq 1 ]; then
        pass "$label"
    else
        fail "$label: rc=$RC (want $want) ids=[$got_ids] (want [$want_ids]) shape_ok=$shape_ok stderr=[$(tail -n 2 "$ERR" | tr '\n' ' ')]"
    fi
}

# expect_undecided <label>: exit 2, no finding, a reason on stderr.
expect_undecided() {
    if [ "$RC" -eq 2 ] && [ "$(finding_count)" -eq 0 ] && grep -q 'check-hop-document:' "$ERR"; then
        pass "$1"
    else
        fail "$1: rc=$RC findings=$(finding_count) stderr=[$(tail -n 2 "$ERR" | tr '\n' ' ')]"
    fi
}

# expect_usage <label>: exit 2, no finding, the usage text on stderr.
expect_usage() {
    if [ "$RC" -eq 2 ] && [ "$(finding_count)" -eq 0 ] && grep -q 'Usage: check-hop-document.sh' "$ERR"; then
        pass "$1"
    else
        fail "$1: rc=$RC findings=$(finding_count) stderr=[$(tail -n 2 "$ERR" | tr '\n' ' ')]"
    fi
}

# --- a stub validator -------------------------------------------------------------
#
# It answers --version, logs every other call's arguments to $STUB_LOG, answers
# the canary (the gate's `canary.md`) with a banned-word notice unless
# STUB_CANARY=none, and answers anything else with the contents of $STUB_JSON
# and the exit code $STUB_RC.

STUB_BIN="$WORKDIR/stub-bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/shirabe" <<'STUB'
#!/usr/bin/env bash
if [ "${1-}" = --version ]; then echo "shirabe stub"; exit 0; fi
printf '%s\n' "$*" >> "${STUB_LOG:-/dev/null}"
last=""
for a in "$@"; do last=$a; done
if [ "$last" = canary.md ]; then
    if [ "${STUB_CANARY:-ok}" = ok ]; then
        printf '%s\n' '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean","errors":0,"notices":1},"findings":[{"code":"FC10","severity":"notice","message":"[FC10] writing-style banned word \"tier\" -- see skills/writing-style/rules.yaml","file":"canary.md","line":1}]}'
    else
        printf '%s\n' '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean","errors":0,"notices":0},"findings":[]}'
    fi
    exit 0
fi
cat "$STUB_JSON"
exit "${STUB_RC:-0}"
STUB
chmod +x "$STUB_BIN/shirabe"
export STUB_LOG="$WORKDIR/stub.log"
export STUB_JSON="$WORKDIR/stub.json"
export STUB_RC=0

stub_json() { printf '%s\n' "$1" > "$STUB_JSON"; }

# with_stub <args...>: run the gate with the stub first on PATH.
with_stub() {
    : > "$STUB_LOG"
    (cd "$REPO" && PATH="$STUB_BIN:$ORIG_PATH" "$CHECK" "$@") > "$OUT" 2> "$ERR"
    RC=$?
}

# path_without <tool>: a PATH directory linking every executable on PATH except
# <tool>, printed. Built once per tool.
path_without() {
    local tool=$1 dir="$WORKDIR/path-without-$1" d f b
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        local IFS=:
        for d in $ORIG_PATH; do
            [ -d "$d" ] || continue
            for f in "$d"/*; do
                b=${f##*/}
                [ "$b" = "$tool" ] && continue
                [ -e "$dir/$b" ] && continue
                [ -f "$f" ] && [ -x "$f" ] && ln -s "$f" "$dir/$b"
            done
        done
    fi
    printf '%s' "$dir"
}

CLEAN_ENVELOPE='{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean","errors":0,"notices":0},"findings":[]}'

# --- usage ------------------------------------------------------------------------

fixture usage
gate --topic t
expect_usage "usage: --hop missing"
gate --topic t --hop everything
expect_undecided "usage: an unknown hop"
gate --topic 'T/../x' --hop prd
expect_undecided "usage: a malformed topic"
gate --topic t- --hop prd
expect_undecided "usage: a topic ending in a hyphen"

# --- the code-to-rule map and the registry ----------------------------------------
#
# code_to_id in the script is the one place a validator code becomes a rule id.
# Every arm must name an active entry whose aliases hold that code, every entry
# this script checks must have an arm, and RULE_IDS must be exactly the mapped
# ids, so a code added on one side and not the other fails here rather than at
# a run that happens to report it.
REGISTRY="$SCRIPT_DIR/../../../references/rule-registry.json"
MAP=$(awk '/^code_to_id\(\)/ { on = 1; next } on && /^}/ { exit }
    on && /^[[:space:]]+[A-Z0-9-]+\)[[:space:]]+echo / {
        code = $1; sub(/\)$/, "", code); print code "\t" $3 }' "$CHECK")
if [ -z "$MAP" ]; then
    fail "code_to_id: no arms found in $CHECK"
else
    map_ok=1
    while IFS='	' read -r code id; do
        jq -e --arg id "$id" --arg code "$code" \
            '.rules[] | select(.id == $id and .status == "active") | .aliases | index($code)' \
            "$REGISTRY" >/dev/null 2>&1 || { map_ok=0; fail "code_to_id: $code -> $id is not an active entry aliasing $code"; }
    done <<EOF
$MAP
EOF
    [ "$map_ok" -eq 1 ] && pass "every code_to_id arm names an active registry entry that aliases its code"
    want=$(jq -r '.rules[] | select(.status == "active" and .check.path == "skills/scope/scripts/check-hop-document.sh") | .aliases[]' "$REGISTRY" | sort)
    have=$(printf '%s\n' "$MAP" | cut -f1 | sort)
    missing=$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$have"))
    if [ -z "$missing" ]; then
        pass "every entry the registry gives this script has a code_to_id arm"
    else
        fail "registry aliases with no code_to_id arm: $missing"
    fi
    ids=$(printf '%s\n' "$MAP" | cut -f2 | sort -u | tr '\n' ' ')
    rule_ids=$(sed -n 's/^RULE_IDS="\(.*\)"$/\1/p' "$CHECK" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    if [ "$ids" = "$rule_ids" ]; then
        pass "RULE_IDS lists exactly the ids code_to_id maps to"
    else
        fail "RULE_IDS [$rule_ids] differs from the mapped ids [$ids]"
    fi
fi

# The shared visibility library keeps its loop variables to itself.
LIB_OUT=$(f=mine v=mine; . "$SCRIPT_DIR/../../../scripts/lib/declared-visibility.sh"; cd "$WORKDIR" && declared_visibility >/dev/null; printf '%s %s' "$f" "$v")
if [ "$LIB_OUT" = "mine mine" ]; then
    pass "declared_visibility leaves its caller's f and v alone"
else
    fail "declared_visibility changed its caller's variables: [$LIB_OUT]"
fi

# --- stub cases -------------------------------------------------------------------

fixture stub-empty
with_stub --topic t --hop all
if [ "$RC" -eq 0 ] && grep -q 'no document' "$ERR"; then
    pass "no document at any path: exit 0, and stderr says so"
else
    fail "no document at any path: rc=$RC stderr=[$(cat "$ERR")]"
fi

fixture stub-args "## Repo Visibility: Public"
fx_prd t | put docs/prds/PRD-t.md
fx_design t | put docs/designs/DESIGN-t.md
commit_all
stub_json "$CLEAN_ENVELOPE"; STUB_RC=0
with_stub --topic t --hop all
calls=$(awk 'END { print NR }' "$STUB_LOG")
if [ "$RC" -eq 0 ] && [ "$calls" -eq 3 ]; then
    pass "the validator runs once per checked document plus once for the canary (3 calls for 2 documents)"
else
    fail "call count: rc=$RC calls=$calls log=[$(tr '\n' '|' < "$STUB_LOG")]"
fi
if grep -q -- 'validate --format json --visibility=public -- docs/prds/PRD-t.md' "$STUB_LOG"; then
    pass "a Public header passes --visibility=public"
else
    fail "visibility flag: log=[$(tr '\n' '|' < "$STUB_LOG")]"
fi
if grep -q -- '--check' "$STUB_LOG"; then
    fail "the gate passed --check: log=[$(tr '\n' '|' < "$STUB_LOG")]"
else
    pass "the gate never passes --check"
fi

fixture stub-novis
fx_prd t | put docs/prds/PRD-t.md
commit_all
with_stub --topic t --hop prd
if [ "$RC" -eq 0 ] && grep -q -- 'validate --format json -- docs/prds/PRD-t.md' "$STUB_LOG" && ! grep -q -- '--visibility' "$STUB_LOG"; then
    pass "no visibility header: no --visibility flag"
else
    fail "no visibility header: rc=$RC log=[$(tr '\n' '|' < "$STUB_LOG")]"
fi

stub_json '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"violations","errors":1,"notices":0},"findings":[{"code":"FC04","severity":"error","message":"[FC04] missing required section","file":"docs/prds/PRD-t.md","line":null}]}'
STUB_RC=2
with_stub --topic t --hop prd
if [ "$RC" -eq 1 ] && [ "$(finding_count)" -eq 1 ] && findings | jq -e 'has("line") | not' >/dev/null 2>&1 \
    && findings | jq -e '.rule_id == "docs/required-sections" and .path == "docs/prds/PRD-t.md"' >/dev/null 2>&1; then
    pass "a finding with a null line prints with no line key"
else
    fail "null line: rc=$RC out=[$(cat "$OUT")]"
fi

# The same violation against plugin copies with its rule at each stage: it
# prints at the stage's level, and only at block does it hold the hop.
hop_in_copy() { # <copy>
    cd "$REPO" && PATH="$STUB_BIN:$ORIG_PATH" "$1/skills/scope/scripts/check-hop-document.sh" --topic t --hop prd
}
rf_test_stages "--hop prd" docs/required-sections 1 "" hop_in_copy \
    skills/scope/scripts/check-hop-document.sh skills/writing-style/rules.yaml

# A retired rule's finding prints nothing, so the closing line must not say a
# finding below block printed.
HOP_COPY="$RF_TEST_DIR/hop-retired"
if rf_test_stage_copy "$HOP_COPY" docs/required-sections retired \
    skills/scope/scripts/check-hop-document.sh skills/writing-style/rules.yaml 2>"$ERR"; then
    hop_in_copy "$HOP_COPY" > "$OUT" 2> "$ERR"
    RC=$?
    if [ "$RC" -eq 0 ] && [ ! -s "$OUT" ] && ! grep -qF 'no violation is of a rule at block' "$ERR" \
        && grep -qF 'docs/prds/PRD-t.md pass' "$ERR"; then
        pass "a retired rule's finding prints nothing and the gate says only that the document passes"
    else
        fail "retired finding: rc=$RC out=[$(cat "$OUT")] stderr=[$(cat "$ERR")]"
    fi
else
    fail "could not make a plugin copy with docs/required-sections at retired: $(cat "$ERR")"
fi
rm -rf "$HOP_COPY"

# The escalation ladder runs on a block exit: with the template's context and
# koto's log saying the rule already failed this gate once, the rule's full
# text is delivered on stderr. docs/required-sections' text sits outside the
# paths `release` prints, so the ladder says where it is instead.
HOP_LADDER_LOG="$WORKDIR/hop-ladder.jsonl"
rf_test_ladder_log "$HOP_LADDER_LOG" prd_hop prd_document docs/required-sections 1
: > "$STUB_LOG"
(cd "$REPO" && PATH="$STUB_BIN:$ORIG_PATH" SHIRABE_GATE_LOG="$HOP_LADDER_LOG" SHIRABE_GATE_NAME=prd_document \
    "$CHECK" --topic t --hop prd) > "$OUT" 2> "$ERR"
RC=$?
if [ "$RC" -eq 1 ] && grep -qF "rule-findings: docs/required-sections's full text is at docs/" "$ERR"; then
    pass "a block exit runs the escalation ladder: a second failure delivers where the rule's text is"
else
    fail "ladder on a block exit: rc=$RC stderr=[$(cat "$ERR")]"
fi
(cd "$REPO" && PATH="$STUB_BIN:$ORIG_PATH" "$CHECK" --topic t --hop prd) > "$OUT" 2> "$ERR"
RC=$?
if [ "$RC" -eq 1 ] && ! grep -q '^::shirabe-rule::' "$ERR" && ! grep -qF 'full text is at' "$ERR"; then
    pass "without the ladder's context a block exit delivers no rule text"
else
    fail "no ladder context: rc=$RC stderr=[$(head -c 600 "$ERR")]"
fi

LONG=$(awk 'BEGIN { for (i = 0; i < 60; i++) printf "0123456789" }')
stub_json "{\"schema_version\":\"shirabe-validate/v1\",\"summary\":{\"outcome\":\"violations\",\"errors\":1,\"notices\":0},\"findings\":[{\"code\":\"R6\",\"severity\":\"error\",\"message\":\"[R6] $LONG\",\"file\":\"docs/prds/PRD-t.md\",\"line\":4}]}"
STUB_RC=2
with_stub --topic t --hop prd
summary=$(jq -r '.rules[] | select(.id == "docs/upstream-resolves") | .summary' "$REGISTRY")
detail=$(findings | jq -r '.message' | awk -v p="$summary: " '{ print substr($0, length(p) + 1) }')
if [ "$RC" -eq 1 ] && [ "${#detail}" -eq 400 ]; then
    case "$detail" in
        *...) pass "a long validator message is cut to 400 characters, ending in ..." ;;
        *) fail "long message: no ... at the end: [$detail]" ;;
    esac
else
    fail "long message: rc=$RC detail length ${#detail}"
fi

stub_json "$CLEAN_ENVELOPE"; STUB_RC=0
STUB_CANARY=none with_stub --topic t --hop prd
expect_undecided "a canary run the selector picks nothing from"

for code in 1 3 4; do
    stub_json "$CLEAN_ENVELOPE"; STUB_RC=$code
    with_stub --topic t --hop prd
    expect_undecided "a validator exiting $code"
done
STUB_RC=0
stub_json 'oops, not JSON'
with_stub --topic t --hop prd
expect_undecided "a validator printing no JSON"
stub_json '{"schema_version":"shirabe-validate/v2","summary":{"outcome":"clean"},"findings":[]}'
with_stub --topic t --hop prd
expect_undecided "a wrong schema_version"
stub_json '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean"},"findings":{}}'
with_stub --topic t --hop prd
expect_undecided "findings that is not an array"
stub_json '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"violations"},"findings":[{"code":"FC04","message":"x","file":"docs/prds/PRD-t.md","line":3}]}'
STUB_RC=2
with_stub --topic t --hop prd
expect_undecided "a finding with no severity"
stub_json '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"violations"},"findings":[{"code":"FC15","severity":"notice","message":"x","file":"docs/prds/PRD-t.md","line":3}]}'
with_stub --topic t --hop prd
expect_undecided "a validator exiting 2 with no error finding"
stub_json '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean"},"findings":[{"code":"FC04","severity":"error","message":"x","file":"docs/prds/PRD-t.md","line":3}]}'
STUB_RC=0
with_stub --topic t --hop prd
expect_undecided "a validator exiting 0 with an error finding"
stub_json '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"violations"},"findings":[{"code":"FC99","severity":"error","message":"[FC99] new","file":"docs/prds/PRD-t.md","line":3}]}'
STUB_RC=2
with_stub --topic t --hop prd
expect_undecided "an error-level code no registry entry aliases"
STUB_RC=0

# A validator planted inside the repository is refused.
mkdir -p "$REPO/bin"
cp "$STUB_BIN/shirabe" "$REPO/bin/shirabe"
stub_json "$CLEAN_ENVELOPE"
(cd "$REPO" && PATH="$REPO/bin:$ORIG_PATH" "$CHECK" --topic t --hop prd) > "$OUT" 2> "$ERR"
RC=$?
expect_undecided "a shirabe that resolves inside the repository"
mkdir -p "$WORKDIR/link-bin"
ln -sf "$REPO/bin/shirabe" "$WORKDIR/link-bin/shirabe"
(cd "$REPO" && PATH="$WORKDIR/link-bin:$ORIG_PATH" "$CHECK" --topic t --hop prd) > "$OUT" 2> "$ERR"
RC=$?
expect_undecided "a shirabe on PATH outside the repository that links to one inside it"
rm -rf "$REPO/bin" "$WORKDIR/link-bin"

for tool in git jq shirabe; do
    p=$(path_without "$tool")
    (cd "$REPO" && PATH="$p" "$CHECK" --topic t --hop prd) > "$OUT" 2> "$ERR"
    RC=$?
    expect_undecided "$tool missing from PATH"
done

# The rules file missing from the plugin tree: a copy of the plugin without it.
PLUGIN_COPY="$WORKDIR/plugin-copy"
rf_test_copy_plugin "$PLUGIN_COPY"
rm -f "$PLUGIN_COPY/skills/writing-style/rules.yaml"
(cd "$REPO" && PATH="$STUB_BIN:$ORIG_PATH" "$PLUGIN_COPY/skills/scope/scripts/check-hop-document.sh" --topic t --hop prd) > "$OUT" 2> "$ERR"
RC=$?
expect_undecided "the plugin's rules file missing"
rf_test_drop_plugin "$PLUGIN_COPY"

# Odd files at a topic path.
fixture odd
printf 'x\n' > "$WORKDIR/elsewhere.md"
mkdir -p "$REPO/docs/prds"
ln -s "$WORKDIR/elsewhere.md" "$REPO/docs/prds/PRD-t.md"
with_stub --topic t --hop prd
expect_undecided "a symlink at the topic path"
rm -f "$REPO/docs/prds/PRD-t.md"
: > "$REPO/docs/prds/PRD-t.md"
with_stub --topic t --hop prd
expect_undecided "an empty file at the topic path"
rm -rf "$REPO/docs/prds"
mkdir -p "$WORKDIR/outside-prds"
fx_prd t > "$WORKDIR/outside-prds/PRD-t.md"
ln -s "$WORKDIR/outside-prds" "$REPO/docs/prds"
with_stub --topic t --hop prd
expect_undecided "a topic path resolving outside the repository"

# --- real-validator cases -----------------------------------------------------------

run_real=0
if [ -n "$REAL_SHIRABE" ]; then
    run_real=1
elif [ "${SCOPE_GATE_REQUIRE_SHIRABE:-}" = 1 ]; then
    fail "shirabe is not on PATH and SCOPE_GATE_REQUIRE_SHIRABE=1: the real-validator cases can't run"
else
    echo "SKIP: shirabe not on PATH -- the real-validator cases did not run"
fi

if [ "$run_real" -eq 1 ]; then
    # The validator's FC10 wording, which the gate's selector matches.
    fixture prefixes
    fx_design t | put docs/designs/DESIGN-t.md
    printf '\nWe leverage it.\n' >> "$REPO/docs/designs/DESIGN-t.md"
    VOUT=$(cd "$REPO" && SHIRABE_RULES="$RULES_FILE" shirabe validate --format json -- docs/designs/DESIGN-t.md 2>/dev/null)
    if printf '%s' "$VOUT" | jq -e '[.findings[] | select(.code == "FC10")] | length > 0 and all(.message | startswith("[FC10] writing-style banned word "))' >/dev/null 2>&1; then
        pass "pin: the validator's banned-word message starts with the gate's prefix"
    else
        fail "pin: banned-word prefix: $VOUT"
    fi
    fx_design t | put docs/designs/DESIGN-t.md
    i=0
    while [ "$i" -lt 55 ]; do printf '\nWe leverage it.\n' >> "$REPO/docs/designs/DESIGN-t.md"; i=$((i + 1)); done
    VOUT=$(cd "$REPO" && SHIRABE_RULES="$RULES_FILE" shirabe validate --format json -- docs/designs/DESIGN-t.md 2>/dev/null)
    if printf '%s' "$VOUT" | jq -e '[.findings[] | select(.message | startswith("[FC10] writing-style findings truncated at "))] | length == 1' >/dev/null 2>&1; then
        pass "pin: the validator's truncation message starts with the gate's prefix"
    else
        fail "pin: truncation prefix: $(printf '%s' "$VOUT" | jq -c '[.findings[-1]]' 2>/dev/null)"
    fi
    commit_all
    gate --topic t --hop design
    last=$(findings | jq -r '.message' | tail -n 1)
    if [ "$RC" -eq 1 ] && [ "$(finding_count)" -eq 51 ] && [ -z "$(findings | jq -r 'select(.rule_id != "prose/banned-word") | .rule_id')" ]; then
        case "$last" in
            *"truncated at"*) pass "more than 50 banned words: 51 findings under prose/banned-word, the last the truncation" ;;
            *) fail "truncation: last message [$last]" ;;
        esac
    else
        fail "more than 50 banned words: rc=$RC count=$(finding_count)"
    fi

    # The canary word, read by the documented rule from the shipped file.
    word=$(awk '
        /^[[:space:]]*terms:[[:space:]]*$/ { inside = 1; next }
        inside && /^[[:space:]]*-[[:space:]]+/ { line = $0; sub(/^[[:space:]]*-[[:space:]]+/, "", line); print line; exit }' "$RULES_FILE")
    if [ -n "$word" ] && awk '/^words:/ { w = 1 } /^[a-z_]+:/ && !/^words:/ { w = 0 } w' "$RULES_FILE" | grep -q -- "- $word\$"; then
        pass "the canary word [$word] is the first term of the shipped rules' words: list"
    else
        fail "canary word: [$word]"
    fi

    # Each hop, clean.
    fixture clean
    fx_brief t | put docs/briefs/BRIEF-t.md
    fx_prd t docs/briefs/BRIEF-t.md | put docs/prds/PRD-t.md
    fx_design t | put docs/designs/DESIGN-t.md
    fx_plan t | put docs/plans/PLAN-t.md
    commit_all
    for hop in brief prd design; do
        gate --topic t --hop "$hop"
        expect "clean $hop: exit 0, no finding" 0
    done
    start=$(date +%s)
    gate --topic t --hop plan
    took=$(( $(date +%s) - start ))
    expect "clean plan: exit 0, no finding" 0
    if [ "$took" -lt 10 ]; then
        pass "the PLAN check finishes in under 10 seconds (${took}s)"
    else
        fail "the PLAN check took ${took}s"
    fi
    gate --topic t --hop all
    expect "clean, every document at the fold: exit 0" 0

    # From a subdirectory, the same answer.
    fixture subdir
    fx_prd t docs/briefs/BRIEF-missing.md | put docs/prds/PRD-t.md
    commit_all
    gate --topic t --hop prd
    root_out=$(findings | jq -c '{rule_id, path, line}')
    gate_from "$REPO/docs" --topic t --hop prd
    sub_out=$(findings | jq -c '{rule_id, path, line}')
    if [ "$RC" -eq 1 ] && [ -n "$root_out" ] && [ "$root_out" = "$sub_out" ]; then
        pass "run from a subdirectory, the result matches the root's"
    else
        fail "subdirectory: rc=$RC root=[$root_out] sub=[$sub_out]"
    fi

    # Each hop, one error-level violation.
    fixture one-each
    fx_brief t | sed 's/^status: Draft/status: Bogus/; s/^Draft$/Bogus/' | put docs/briefs/BRIEF-t.md
    fx_prd t docs/briefs/BRIEF-nope.md | put docs/prds/PRD-t.md
    fx_design t | grep -v '^## Consequences' | put docs/designs/DESIGN-t.md
    fx_plan t '<<ISSUE:9>>' | put docs/plans/PLAN-t.md
    commit_all
    gate --topic t --hop brief
    expect "brief with an invalid status: one finding" 1 docs/valid-status
    gate --topic t --hop prd
    expect "prd with a nonexistent upstream: one finding" 1 docs/upstream-resolves
    want_line=$(grep -n '^upstream:' "$REPO/docs/prds/PRD-t.md" | cut -d: -f1)
    if findings | jq -e --argjson l "$want_line" '.line == $l and .path == "docs/prds/PRD-t.md"' >/dev/null 2>&1; then
        pass "the upstream finding names the PRD and the upstream: line ($want_line)"
    else
        fail "upstream line: $(findings)"
    fi
    gate --topic t --hop design
    expect "design missing a section: one finding" 1 docs/required-sections
    gate --topic t --hop plan
    expect "plan with an outline dependency naming no outline: one finding" 1 plan/outline-dependency-resolves

    # An upstream that exists but isn't tracked.
    fixture untracked
    fx_prd t docs/briefs/BRIEF-t.md | put docs/prds/PRD-t.md
    commit_all
    fx_brief t | put docs/briefs/BRIEF-t.md
    gate --topic t --hop prd
    expect "an upstream that exists but isn't tracked" 1 docs/upstream-resolves

    # The design hop reads both locations.
    fixture design-current
    fx_design t | grep -v '^## Consequences' | put docs/designs/current/DESIGN-t.md
    commit_all
    gate --topic t --hop design
    expect "a design at docs/designs/current/ is checked" 1 docs/required-sections
    fx_design t | put docs/designs/DESIGN-t.md
    commit_all
    gate --topic t --hop design
    expect "documents at both design paths: a violation in either holds" 1 docs/required-sections

    # The banned words, raised; em-dash density and plan-structure notices, not.
    fixture banned
    fx_prd t | put docs/prds/PRD-t.md
    fx_design t | put docs/designs/DESIGN-t.md
    printf '\nWe leverage it.\n' >> "$REPO/docs/designs/DESIGN-t.md"
    commit_all
    want_line=$(grep -n 'We leverage it' "$REPO/docs/designs/DESIGN-t.md" | cut -d: -f1)
    gate --topic t --hop all
    expect "the fold: a clean PRD and a DESIGN with a banned word" 1 prose/banned-word
    if findings | jq -e --argjson l "$want_line" '.path == "docs/designs/DESIGN-t.md" and .line == $l' >/dev/null 2>&1; then
        pass "the banned-word finding names the DESIGN and the word's line, in a repository with no rules file of its own"
    else
        fail "banned-word location: $(findings)"
    fi
    (cd "$REPO" && SHIRABE_RULES=/dev/null "$CHECK" --topic t --hop design) > "$OUT" 2> "$ERR"
    RC=$?
    expect "an inherited SHIRABE_RULES=/dev/null doesn't switch the banned-word check off" 1 prose/banned-word

    fixture emdash
    fx_design t | put docs/designs/DESIGN-t.md
    i=0
    while [ "$i" -lt 40 ]; do
        printf '\nThe run writes one line \342\200\224 the path of a document it wrote today.\n' >> "$REPO/docs/designs/DESIGN-t.md"
        i=$((i + 1))
    done
    commit_all
    VOUT=$(cd "$REPO" && SHIRABE_RULES="$RULES_FILE" shirabe validate --format json -- docs/designs/DESIGN-t.md 2>/dev/null)
    if printf '%s' "$VOUT" | jq -e '[.findings[] | select(.code == "FC10")] | length == 1 and (.[0].message | contains("em-dash-density"))' >/dev/null 2>&1; then
        gate --topic t --hop design
        expect "an em-dash-density finding alone passes" 0
    else
        fail "fixture: the em-dash design doesn't carry exactly one em-dash-density finding: $(printf '%s' "$VOUT" | jq -c '[.findings[] | .message]' 2>/dev/null)"
    fi

    fixture plan-notice
    fx_plan t | sed 's/^issue_count: 1/issue_count: 2/' | put docs/plans/PLAN-t.md
    commit_all
    VOUT=$(cd "$REPO" && shirabe validate --format json -- docs/plans/PLAN-t.md 2>/dev/null)
    if printf '%s' "$VOUT" | jq -e '[.findings[].severity] | length > 0 and all(. == "notice")' >/dev/null 2>&1; then
        gate --topic t --hop plan
        expect "plan-structure notices alone pass" 0
    else
        fail "fixture: the plan doesn't carry notices only: $VOUT"
    fi

    # Mixed: two banned words and one error-level violation, and the message shape.
    fixture mixed
    fx_design t | grep -v '^## Consequences' | put docs/designs/DESIGN-t.md
    printf '\nWe leverage it.\n\nWe leverage more.\n' >> "$REPO/docs/designs/DESIGN-t.md"
    commit_all
    gate --topic t --hop design
    if [ "$RC" -eq 1 ] && [ "$(finding_count)" -eq 3 ]; then
        pass "two banned words and one error: three findings"
    else
        fail "mixed: rc=$RC count=$(finding_count) out=[$(cat "$OUT")]"
    fi
    VOUT=$(cd "$REPO" && SHIRABE_RULES="$RULES_FILE" shirabe validate --format json -- docs/designs/DESIGN-t.md 2>/dev/null)
    vmsg=$(jq -r '.findings[] | select(.code == "FC04") | .message' <<<"$VOUT" | head -n 1)
    summary=$(jq -r '.rules[] | select(.id == "docs/required-sections") | .summary' "$SCRIPT_DIR/../../../references/rule-registry.json")
    gmsg=$(findings | jq -r 'select(.rule_id == "docs/required-sections") | .message')
    if [ -n "$vmsg" ] && [ "$gmsg" = "$summary: $vmsg" ]; then
        pass "a finding's message is the entry summary, ': ', and the validator's message"
    else
        fail "message shape: got [$gmsg] want [$summary: $vmsg]"
    fi

    # A schema-less document: the validator checks nothing, so the gate can't decide.
    fixture schemaless
    printf 'No frontmatter.\n\n## Status\n\nDraft\n' | put docs/prds/PRD-t.md
    commit_all
    gate --topic t --hop prd
    expect_undecided "a schema-less document"
fi

rf_test_verify "check-hop-document"

echo
echo "check-hop-document_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
