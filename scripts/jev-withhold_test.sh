#!/usr/bin/env bash
# jev-withhold_test.sh -- the withhold script prints the withheld copy of a
# rule file only when every condition holds, and the full file otherwise.
#
# Each case builds a scratch plugin root (a registry with one trusted entry, the
# rule file, the real rule-registry.sh), a session directory with a koto log,
# and a stub koto on PATH whose answers the case sets. Nothing here reaches a
# real koto, a network or the caller's own configuration.

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd -P)
SCRIPT="$HERE/jev-withhold.sh"
READER="$HERE/rule-registry.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/jev-withhold-test.XXXXXX") || exit 1
T=$(CDPATH='' cd -P -- "$T" && pwd -P) || exit 1
cleanup() { rm -rf "$T"; return 0; }
ktg_on_exit cleanup

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); echo "PASS: $1"; }
fail() { FAILED=$((FAILED + 1)); echo "FAIL: $1 - $2"; }

RULE="demo/fits-facts"
REL="skills/demo/references/rules.md"
NAME="work-on-demo"

# A stub koto: `config get decider.mode` prints the mode file's content,
# `config get decider.api_key` exits with the key file's code.
mkdir -p "$T/bin"
cat > "$T/bin/koto" <<'EOF'
#!/usr/bin/env bash
dir=$(dirname -- "$0")
case "$1 $2 $3" in
    "config get decider.mode") cat "$dir/../mode" 2>/dev/null; exit "$(cat "$dir/../mode-rc" 2>/dev/null || echo 0)" ;;
    "config get decider.api_key") echo "sk-test"; exit "$(cat "$dir/../key-rc" 2>/dev/null || echo 0)" ;;
esac
exit 2
EOF
chmod +x "$T/bin/koto"
# The stub first, then the bash running this suite (on the 3.2 floor it may
# live outside /bin), then jq and the base tools; nothing else the caller has.
TOOLS="$T/bin:$(dirname -- "$BASH"):$(dirname -- "$(command -v jq)"):/usr/bin:/bin"

entry_json() {  # entry_json <state> <withhold> <text path>
    printf '{"schema": 1, "rules": [{"id": "%s", "status": "active", "summary": "s",
      "text": {"path": "%s", "first": "The rules:", "last": "- light otherwise."},
      "check": {"kind": "decider", "template": "skills/demo/koto-templates/demo.md",
                "state": "check_state", "gate": "fits", "criterion": "fits"},
      "withhold": "%s", "jev": {"state": "%s"}}]}\n' "$RULE" "$3" "$2" "$1"
}

# fresh: a new plugin root, session directory and project directory in the
# trusted, auto, clean state, under $T/c$N.
N=0
fresh() {
    N=$((N + 1))
    C="$T/c$N"
    ROOT="$C/plugin"
    SDIR="$C/session"
    PROJ="$C/project"
    mkdir -p "$ROOT/scripts" "$ROOT/references" "$ROOT/skills/demo/references" "$SDIR" "$PROJ"
    cp "$READER" "$ROOT/scripts/rule-registry.sh"
    printf '# Demo\n\nIntro.\n\nThe rules:\n- one\n- light otherwise.\n\nAfter.\n' > "$ROOT/$REL"
    entry_json trusted eligible "$REL" > "$ROOT/references/rule-registry.json"
    printf '{"schema_version":1,"session_id":"s1"}\n{"seq":1,"timestamp":"2026-10-20T10:00:00Z","type":"workflow_initialized","payload":{}}\n' \
        > "$SDIR/koto-$NAME.state.jsonl"
    printf 'auto\n' > "$T/mode"
    printf '0\n' > "$T/mode-rc"
    printf '0\n' > "$T/key-rc"
}

# run_it [args...]: runs the script from the project directory with the stub
# koto on PATH; sets OUT and RC.
run_it() {
    OUT=$(cd "$PROJ" && PATH="$TOOLS" bash "$SCRIPT" "$@" 2>/dev/null)
    RC=$?
}

expect_full() {  # expect_full <name>
    if [ "$RC" = 0 ] && [ "$OUT" = "$ROOT/$REL" ]; then
        pass "$1 prints the full file"
    else
        fail "$1" "rc=$RC out=[$OUT]"
    fi
}

event() {  # event <type> <gate> <criterion> [mode] [outcome]
    printf '{"seq":9,"timestamp":"2026-10-20T10:01:00Z","type":"%s","payload":{"state":"check_state","visit_seq":1,"gate":"%s","rule_id":"%s","mode":"%s","outcome":"%s"}}\n' \
        "$1" "$2" "$3" "${4:-veto}" "${5:-pass}" >> "$SDIR/koto-$NAME.state.jsonl"
}

# --- every condition holds ----------------------------------------------------
fresh
cp "$ROOT/$REL" "$C/rule-before.md"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"
want="$SDIR/jev-rules/demo-fits-facts-rules.md"
if [ "$RC" = 0 ] && [ "$OUT" = "$want" ] && [ -f "$want" ]; then
    pass "with every condition met it prints the withheld copy"
else
    fail "withheld copy" "rc=$RC out=[$OUT]"
fi
expected=$(printf '# Demo\n\nIntro.\n\n\nAfter.\n')
[ "$(cat "$want" 2>/dev/null)" = "$expected" ] && pass "the copy is the file without the rule's lines" \
    || fail "copy content" "[$(cat "$want" 2>/dev/null)]"
cmp -s "$ROOT/$REL" "$C/rule-before.md" && pass "the rule file itself is untouched" || fail "rule file" "changed"

for outcome in pass fail; do
    fresh; event decider_checked fits fits veto "$outcome"
    run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"
    [ "$OUT" = "$SDIR/jev-rules/demo-fits-facts-rules.md" ] && pass "a veto-mode decider_checked answered $outcome still allows the copy" \
        || fail "veto check $outcome" "out=[$OUT]"
done

SAVED_RULE=$RULE
RULE="rs-099"
fresh
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"
[ "$OUT" = "$SDIR/jev-rules/rs-099-rules.md" ] && pass "an rs- rule id is accepted, as the registry's checks accept it" \
    || fail "rs id" "out=[$OUT]"
RULE=$SAVED_RULE

# --- any one condition failing alone ------------------------------------------
fresh; entry_json untrusted eligible "$REL" > "$ROOT/references/rule-registry.json"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "an untrusted entry"

fresh; entry_json trusted never "$REL" > "$ROOT/references/rule-registry.json"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "withhold never"

fresh; entry_json trusted eligible "skills/demo/references/other.md" > "$ROOT/references/rule-registry.json"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a text path other than the rule file"

fresh; printf 'shadow\n' > "$T/mode"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a decider mode other than auto"

fresh; printf '1\n' > "$T/key-rc"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "no decider key"

fresh; mkdir -p "$PROJ/.koto"; printf '[decider]\nmode = "shadow"\n' > "$PROJ/.koto/config.toml"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a project config that mentions decider"

fresh; mkdir -p "$PROJ/.koto"; printf '# decider settings live in the user file\n[other]\nx = 1\n' > "$PROJ/.koto/config.toml"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"
[ "$OUT" = "$SDIR/jev-rules/demo-fits-facts-rules.md" ] && pass "a project config mentioning decider only in a comment doesn't count" \
    || fail "comment-only config" "out=[$OUT]"

fresh; event decider_fallback fits fits
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a decider_fallback for the criterion"

fresh; event decider_check_answered fits fits
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "an agent's answer for the criterion"

fresh; event decider_checked fits fits shadow
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a decider_checked that ran in shadow"

# An unanswered check is never a pass: a veto-mode check the decider didn't
# answer pass or fail keeps the rule loaded.
for outcome in unanswered escape not_graded; do
    fresh; event decider_checked fits fits veto "$outcome"
    run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a veto-mode decider_checked with outcome $outcome"
done
fresh
printf '{"seq":9,"timestamp":"2026-10-20T10:01:00Z","type":"decider_checked","payload":{"state":"check_state","visit_seq":1,"gate":"fits","rule_id":"fits","mode":"veto"}}\n' \
    >> "$SDIR/koto-$NAME.state.jsonl"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a veto-mode decider_checked with no outcome"

fresh; event decider_fallback fits other
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"
[ "$OUT" = "$SDIR/jev-rules/demo-fits-facts-rules.md" ] && pass "a fallback for another criterion of the same gate doesn't count" \
    || fail "other criterion" "out=[$OUT]"

fresh
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"
first=$OUT
event decider_fallback fits fits
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"
[ "$first" = "$SDIR/jev-rules/demo-fits-facts-rules.md" ] && [ "$OUT" = "$ROOT/$REL" ] \
    && pass "after a fallback every later call prints the full file" || fail "later call" "first=[$first] then=[$OUT]"

# --- bad input and broken surroundings ----------------------------------------
fresh; run_it "$RULE" "$REL" "$NAME" "$SDIR"
[ "$RC" = 0 ] && [ -z "$OUT" ] && pass "four arguments print nothing to fall back on and exit 0" || fail "four args" "rc=$RC out=[$OUT]"
fresh; run_it "Not A Rule" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a malformed rule id"
fresh; run_it "$RULE" "skills/../$REL" "$NAME" "$SDIR" "$ROOT"
[ "$RC" = 0 ] && [ "$OUT" = "$ROOT/skills/../$REL" ] && pass "a path with .. is never withheld" || fail "dotdot" "rc=$RC out=[$OUT]"
fresh; run_it "$RULE" "$REL" "bad name;x" "$SDIR" "$ROOT"; expect_full "a malformed session name"
fresh; ln -s "$SDIR" "$C/linked"; run_it "$RULE" "$REL" "$NAME" "$C/linked" "$ROOT"; expect_full "a symlinked session directory"
fresh; rm "$T/bin/koto"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "no koto on PATH"
cat > "$T/bin/koto" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$T/bin/koto"
fresh; run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a failing koto"
# Put the answering stub back for the cases below.
cat > "$T/bin/koto" <<'EOF'
#!/usr/bin/env bash
dir=$(dirname -- "$0")
case "$1 $2 $3" in
    "config get decider.mode") cat "$dir/../mode" 2>/dev/null; exit "$(cat "$dir/../mode-rc" 2>/dev/null || echo 0)" ;;
    "config get decider.api_key") echo "sk-test"; exit "$(cat "$dir/../key-rc" 2>/dev/null || echo 0)" ;;
esac
exit 2
EOF
chmod +x "$T/bin/koto"
fresh; rm "$SDIR/koto-$NAME.state.jsonl"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a missing session log"
fresh; printf 'not json\n{"seq":\n' >> "$SDIR/koto-$NAME.state.jsonl"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a malformed session log"
fresh; printf '{"rules": [' > "$ROOT/references/rule-registry.json"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "an unreadable registry"
fresh; mkdir -p "$C/elsewhere"; ln -s "$C/elsewhere" "$SDIR/jev-rules"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "a symlinked jev-rules directory"
fresh; mkdir -p "$SDIR/jev-rules/demo-fits-facts-rules.md"
run_it "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT"; expect_full "an output path that is a directory"

# --- the key never reaches output ---------------------------------------------
fresh
ALL=$(cd "$PROJ" && PATH="$TOOLS" bash "$SCRIPT" "$RULE" "$REL" "$NAME" "$SDIR" "$ROOT" 2>&1)
case "$ALL" in *sk-test*) fail "key" "the key reached the output" ;; *) pass "the key never reaches the output" ;; esac

echo
echo "jev-withhold_test: $PASSED passed, $FAILED failed"
[ "$FAILED" = 0 ]
