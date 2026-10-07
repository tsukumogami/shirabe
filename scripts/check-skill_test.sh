#!/usr/bin/env bash
# check-skill_test.sh -- test harness for scripts/check-skill.sh, the checks
# the `skills/**` verification-map entry runs on a changed skill, and for
# scripts/lib/check-evals-shape.py, the evals.json shape check it calls.
#
# Usage: bash scripts/check-skill_test.sh
#        /bin/bash scripts/check-skill_test.sh     # the bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# Each case builds a throwaway skills/ tree and points the script at it through
# its test-only CHECK_SKILL_ROOT. Stub shirabe and koto stand in for the real
# tools: the shirabe stub rejects any file holding STUB-REJECT and logs its
# arguments, the koto stub fails to compile any template holding STUB-BAD. A
# recording claude stub sits on PATH too, and every case asserts it was never
# called: the gate must not start a model session. Needs bash, git and python3.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK_SH="$SCRIPT_DIR/check-skill.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$CHECK_SH" ] || { echo "FAIL: check-skill.sh not found at $CHECK_SH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 is required" >&2; exit 1; }
command -v git >/dev/null || { echo "FAIL: git is required" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Stubs: shirabe, koto, claude. A second directory holds the same stubs
# without koto, for the missing-tool case.
STUBS="$WORK/stubs"
NOKOTO="$WORK/stubs-nokoto"
mkdir -p "$STUBS" "$NOKOTO"
cat > "$STUBS/shirabe" <<'EOF'
#!/bin/sh
[ "$1" = validate ] || exit 2
shift
echo "call" >> "$SHIRABE_LOG"
rc=0
for f in "$@"; do
    echo "arg $f" >> "$SHIRABE_LOG"
    if grep -q STUB-REJECT "$f"; then
        echo "::error file=$f::stub rejection"
        rc=1
    fi
done
exit $rc
EOF
cat > "$STUBS/koto" <<'EOF'
#!/bin/sh
[ "$1" = template ] && [ "$2" = compile ] || exit 2
if grep -q STUB-BAD "$3"; then
    echo "error: $3: stub compile failure" >&2
    exit 1
fi
echo "compiled $3"
EOF
cat > "$STUBS/claude" <<'EOF'
#!/bin/sh
echo "claude $*" >> "$CLAUDE_LOG"
exit 0
EOF
chmod +x "$STUBS/shirabe" "$STUBS/koto" "$STUBS/claude"
cp "$STUBS/shirabe" "$STUBS/claude" "$NOKOTO/"

# For the missing-tool case the real tools' directories can't be on PATH (koto
# may sit next to shirabe), so link just what the script needs.
TOOLBIN="$WORK/toolbin"
mkdir -p "$TOOLBIN"
ln -s "$(command -v python3)" "$TOOLBIN/python3"
ln -s "$(command -v git)" "$TOOLBIN/git"
ln -s "$BASH_BIN" "$TOOLBIN/bash"

SHIRABE_LOG="$WORK/shirabe.log"
CLAUDE_LOG="$WORK/claude.log"
export SHIRABE_LOG CLAUDE_LOG

ROOT=""
OUT=""
RC=0

# new_tree: a fresh root holding skills/demo with a SKILL.md and a sound
# evals.json; each case then adds or breaks what it tests.
new_tree() {
    ROOT=$(mktemp -d "$WORK/root.XXXXXX")
    mkdir -p "$ROOT/skills/demo/evals"
    printf -- '---\nname: demo\ndescription: A demo skill.\n---\n\n# Demo\n' \
        > "$ROOT/skills/demo/SKILL.md"
    cat > "$ROOT/skills/demo/evals/evals.json" <<'EOF'
{"skill_name": "demo", "evals": [
  {"id": 1, "name": "first", "prompt": "do the thing", "expectations": ["it does the thing"]}
]}
EOF
    : > "$SHIRABE_LOG"
    : > "$CLAUDE_LOG"
}

write_evals() {
    printf '%s\n' "$1" > "$ROOT/skills/demo/evals/evals.json"
}

# run_check [<path>] -- runs the script on skill `demo` (or $SKILL_ARG),
# capturing output and exit code.
run_check() {
    local path="${1:-$STUBS:$PATH}"
    OUT=$(cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" PATH="$path" \
        "$BASH_BIN" "$CHECK_SH" "${SKILL_ARG:-demo}" 2>&1)
    RC=$?
}

claude_untouched() {
    [ ! -s "$CLAUDE_LOG" ]
}

expect() {
    # expect <name> <rc> [<substring>...]
    local name="$1" want="$2" s
    shift 2
    if [ "$RC" != "$want" ]; then
        fail "$name: exit $RC, want $want"
        printf '%s\n' "$OUT" | sed 's/^/    /'
        return
    fi
    for s in "$@"; do
        if ! printf '%s\n' "$OUT" | grep -qF -- "$s"; then
            fail "$name: output lacks '$s'"
            printf '%s\n' "$OUT" | sed 's/^/    /'
            return
        fi
    done
    if ! claude_untouched; then
        fail "$name: claude was called"
        return
    fi
    pass "$name"
}

# -- Cases ---------------------------------------------------------------------

new_tree
run_check
expect "clean skill with no templates or scripts passes" 0 "check-skill: demo passed"
if [ "$(grep -c '^call' "$SHIRABE_LOG")" = 1 ]; then
    pass "shirabe validate runs once"
else
    fail "shirabe validate ran $(grep -c '^call' "$SHIRABE_LOG") times, want 1"
fi

new_tree
write_evals '{"evals": [ {"name": "x"'
run_check
expect "invalid JSON fails, naming the file" 1 "skills/demo/evals/evals.json: invalid JSON"

new_tree
write_evals '{"evals": [{"prompt": "p", "expectations": ["e"]}]}'
run_check
expect "missing name fails, naming the eval" 1 "eval #1: missing or empty \`name\`"

new_tree
write_evals '{"evals": [{"name": "noprompt", "prompt": "  ", "expectations": ["e"]}]}'
run_check
expect "empty prompt fails, naming the eval" 1 "eval 'noprompt' (#1): missing or empty \`prompt\`"

new_tree
write_evals '{"evals": [{"name": "ok", "prompt": "p", "expectations": ["e"]}, {"name": "bare", "prompt": "p", "expectations": [], "assertions": []}]}'
run_check
expect "an eval with neither list non-empty fails, naming it" 1 \
    "eval 'bare' (#2): needs a non-empty \`expectations\` or \`assertions\` list"

new_tree
write_evals '{"evals": [{"name": "a", "prompt": "p", "assertions": [{"text": "t"}]}]}'
run_check
expect "assertions is accepted in place of expectations" 0

new_tree
write_evals '{"evals": []}'
run_check
expect "an empty evals list fails" 1 "skills/demo/evals/evals.json"

new_tree
rm "$ROOT/skills/demo/evals/evals.json"
run_check
expect "missing evals.json fails without disable-model-invocation" 1 \
    "skills/demo/evals/evals.json: missing"

new_tree
rm "$ROOT/skills/demo/evals/evals.json"
printf -- '---\nname: demo\ndescription: d\ndisable-model-invocation: true\n---\n' \
    > "$ROOT/skills/demo/SKILL.md"
run_check
expect "missing evals.json passes with disable-model-invocation: true" 0

new_tree
mkdir -p "$ROOT/skills/demo/references"
printf 'STUB-REJECT\n' > "$ROOT/skills/demo/references/bad.md"
run_check
expect "Markdown shirabe validate rejects fails, naming the file" 1 \
    "skills/demo/references/bad.md" "shirabe validate rejected"

new_tree
mkdir -p "$ROOT/skills/demo/koto-templates" "$ROOT/skills/demo/evals/fixtures"
printf 'STUB-REJECT\n' > "$ROOT/skills/demo/evals/fixtures/doc.md"
printf 'STUB-REJECT\n' > "$ROOT/skills/demo/koto-templates/t.md"
run_check
expect "Markdown under evals/ and koto-templates/ is not validated" 0
if grep -q 'evals/\|koto-templates/' "$SHIRABE_LOG"; then
    fail "shirabe validate was handed a file under evals/ or koto-templates/"
else
    pass "shirabe validate's arguments exclude evals/ and koto-templates/"
fi

new_tree
mkdir -p "$ROOT/skills/demo/koto-templates"
printf 'name: ok\n' > "$ROOT/skills/demo/koto-templates/good.md"
printf 'STUB-BAD\n' > "$ROOT/skills/demo/koto-templates/broken.md"
run_check
expect "a template that fails to compile fails, naming it" 1 \
    "koto template compile: skills/demo/koto-templates/broken.md"

new_tree
mkdir -p "$ROOT/skills/demo/koto-templates"
printf 'name: ok\n' > "$ROOT/skills/demo/koto-templates/good.md"
printf 'STUB-BAD\n' > "$ROOT/skills/demo/koto-templates/good.mermaid.md"
run_check
expect "*.mermaid.md is not compiled" 0 "ok: koto template compile skills/demo/koto-templates/good.md"
if printf '%s\n' "$OUT" | grep -q 'mermaid'; then
    fail "*.mermaid.md was compiled"
else
    pass "*.mermaid.md is skipped"
fi

new_tree
mkdir -p "$ROOT/skills/demo/scripts"
printf '#!/bin/sh\nexit 1\n' > "$ROOT/skills/demo/scripts/broken_test.sh"
printf '#!/bin/sh\nexit 1\n' > "$ROOT/skills/demo/scripts/helper.sh"
run_check
expect "a *_test.sh exiting 1 fails, naming it" 1 "bash skills/demo/scripts/broken_test.sh"
if printf '%s\n' "$OUT" | grep -q 'helper.sh'; then
    fail "a script that is not *_test.sh was run"
else
    pass "only *_test.sh scripts run"
fi

new_tree
mkdir -p "$ROOT/skills/demo/scripts"
printf '[ -f skills/demo/SKILL.md ] || { echo "not at the root"; exit 1; }\n' \
    > "$ROOT/skills/demo/scripts/cwd_test.sh"
run_check
expect "suites run from the repository root" 0 "ok: bash skills/demo/scripts/cwd_test.sh"

new_tree
mkdir -p "$ROOT/skills/demo/scripts" "$ROOT/skills/demo/koto-templates"
printf 'exit 1\n' > "$ROOT/skills/demo/scripts/a_test.sh"
printf 'STUB-BAD\n' > "$ROOT/skills/demo/koto-templates/t.md"
write_evals '{"evals": [{"name": "n", "prompt": "p"}]}'
run_check
expect "every failure is reported, not only the first" 1 \
    "koto template compile: skills/demo/koto-templates/t.md" \
    "bash skills/demo/scripts/a_test.sh" "eval shape: skills/demo/evals/evals.json"

new_tree
run_check "$NOKOTO:$TOOLBIN:/usr/bin:/bin"
expect "koto missing from PATH exits 2, naming it" 2 "not on PATH: koto"

new_tree
SKILL_ARG="../demo" run_check
expect "a skill name outside the pattern exits 2" 2 "invalid skill name"

new_tree
SKILL_ARG="nope" run_check
expect "an unknown skill exits 2" 2 "no such skill: skills/nope"

echo ""
echo "check-skill_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
