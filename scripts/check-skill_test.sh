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

# run_check_bounded <seconds>: run_check, but a check still running after
# <seconds> is killed and reported as hung (exit 124).
run_check_bounded() {
    local lim="$1" out="$WORK/bounded.out" pid n=0
    (cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" \
        "$BASH_BIN" "$CHECK_SH" "${SKILL_ARG:-demo}" >"$out" 2>&1) &
    pid=$!
    while kill -0 "$pid" 2>/dev/null && [ "$n" -lt $((lim * 10)) ]; do sleep 0.1; n=$((n + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
        pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        OUT="hung past ${lim}s"; RC=124
        return
    fi
    wait "$pid"; RC=$?
    OUT=$(cat "$out")
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

# -- koto's session context ------------------------------------------------------
# A koto session that runs the check hands it KOTO_SESSIONS_BASE and
# KOTO_TICK_SESSION; no suite may inherit them, nor any KOTO_SESSION_* setting.
new_tree
mkdir -p "$ROOT/skills/demo/scripts"
cat > "$ROOT/skills/demo/scripts/env_test.sh" <<'SUITE'
seen=$(env | grep -E '^KOTO_(SESSIONS_BASE|TICK_SESSION|SESSION_[A-Za-z0-9_]*)=' | cut -d= -f1)
[ -z "$seen" ] || { echo "inherited: $seen"; exit 1; }
SUITE
KOTO_SESSIONS_BASE="$WORK/caller-store" KOTO_TICK_SESSION=caller-run \
    KOTO_SESSION_BACKEND=cloud KOTO_SESSION_CLOUD_BUCKET=owner-bucket run_check
expect "a suite inherits none of koto's session context" 0 "ok: bash skills/demo/scripts/env_test.sh"

# With the real koto, a suite that gives itself a HOME keeps its sessions there,
# though the check was handed another store.
REAL_KOTO_BIN=$(command -v koto 2>/dev/null || true)
if [ -z "$REAL_KOTO_BIN" ]; then
    pass "a suite's koto session stays in its own store (not checked: koto isn't on PATH)"
else
    new_tree
    mkdir -p "$ROOT/skills/demo/scripts" "$WORK/caller-store"
    export REAL_KOTO_BIN
    cat > "$ROOT/skills/demo/scripts/store_test.sh" <<'SUITE'
T=$(mktemp -d)
export HOME="$T/home"; mkdir -p "$HOME"
printf -- '---\nname: probe\nversion: "1.0"\ndescription: One state.\ninitial_state: done\nstates:\n  done:\n    terminal: true\n---\n\n## done\n\nDone.\n' > "$T/probe.md"
(cd "$T" && "$REAL_KOTO_BIN" init store-probe --template "$T/probe.md" >/dev/null 2>&1) || { echo "koto init failed"; exit 1; }
[ -d "$HOME/.koto/sessions/store-probe" ] || { echo "the session isn't in the suite's own store"; exit 1; }
rm -rf "$T"
SUITE
    KOTO_SESSIONS_BASE="$WORK/caller-store" run_check
    expect "a suite's koto session stays in its own store" 0 "ok: bash skills/demo/scripts/store_test.sh"
    if [ -n "$(ls -A "$WORK/caller-store" 2>/dev/null)" ]; then
        fail "  ... and nothing reaches the store the check was handed: $(ls "$WORK/caller-store")"
    else
        pass "  ... and nothing reaches the store the check was handed"
    fi
    unset REAL_KOTO_BIN
fi

# -- Suites in parallel ----------------------------------------------------------
MARKS="$WORK/marks"
export MARKS
# marked_suite <file> <seconds> [exit]: a suite that leaves run.<pid> in
# $MARKS while it sleeps, appends how many run.* marks it saw to $MARKS/seen,
# prints "<name> output" and exits with <exit> (default 0). The most marks any
# suite saw at once is how many ran together.
marked_suite() {
    cat > "$1" <<'SUITE'
m="$MARKS/run.$$"; : > "$m"
ls "$MARKS" | grep -c '^run\.' >> "$MARKS/seen"
sleep @SECONDS@
rm -f "$m"
echo "@NAME@ output"
exit @EXIT@
SUITE
    sed -i.bak -e "s/@SECONDS@/$2/" -e "s/@NAME@/$(basename "$1")/" -e "s/@EXIT@/${3:-0}/" "$1" && rm -f "$1.bak"
}
max_seen() { sort -n "$MARKS/seen" 2>/dev/null | tail -1; }

new_tree
mkdir -p "$ROOT/skills/demo/scripts"
rm -rf "$MARKS"; mkdir -p "$MARKS"
marked_suite "$ROOT/skills/demo/scripts/a_test.sh" 2
marked_suite "$ROOT/skills/demo/scripts/b_test.sh" 0
marked_suite "$ROOT/skills/demo/scripts/c_test.sh" 0 1
marked_suite "$ROOT/skills/demo/scripts/d_test.sh" 1
run_check
expect "a failing suite among parallel ones fails the check, showing its output" 1 \
    "bash skills/demo/scripts/c_test.sh" "c_test.sh output"
order=$(printf '%s\n' "$OUT" | grep -E '^(ok|FAIL): bash ' | sed 's/.*scripts\///' | tr '\n' ' ')
if [ "$order" = "a_test.sh b_test.sh c_test.sh d_test.sh " ]; then
    pass "results print in the glob's order, whichever suite finishes first"
else
    fail "results print in the glob's order: got [$order]"
fi
if [ "$(max_seen)" -ge 2 ]; then
    pass "suites run at the same time by default"
else
    fail "suites run at the same time by default: at most $(max_seen) together"
fi

new_tree
mkdir -p "$ROOT/skills/demo/scripts"
rm -rf "$MARKS"; mkdir -p "$MARKS"
for s in a b c d e; do marked_suite "$ROOT/skills/demo/scripts/${s}_test.sh" 1; done
CHECK_SKILL_JOBS=2 run_check
expect "five suites pass two at a time" 0 "ok: bash skills/demo/scripts/e_test.sh"
if [ "$(max_seen)" = 2 ]; then
    pass "CHECK_SKILL_JOBS bounds how many suites run at once"
else
    fail "CHECK_SKILL_JOBS=2: at most $(max_seen) together"
fi

new_tree
mkdir -p "$ROOT/skills/demo/scripts"
rm -rf "$MARKS"; mkdir -p "$MARKS"
for s in a b c; do marked_suite "$ROOT/skills/demo/scripts/${s}_test.sh" 1; done
CHECK_SKILL_JOBS=1 run_check
expect "CHECK_SKILL_JOBS=1 runs the suites" 0 "ok: bash skills/demo/scripts/c_test.sh"
if [ "$(max_seen)" = 1 ]; then
    pass "CHECK_SKILL_JOBS=1 runs one suite at a time"
else
    fail "CHECK_SKILL_JOBS=1: at most $(max_seen) together"
fi

for bad in 0 abc 100 "2 3" -1; do
    new_tree
    CHECK_SKILL_JOBS="$bad" run_check
    expect "CHECK_SKILL_JOBS=$bad is a usage error" 2 "CHECK_SKILL_JOBS must be a whole number from 1 to 99"
done

# A suite whose wrapper dies before writing its status (here the suite kills
# its own parent) fails the check by name; the suites after it still report.
new_tree
mkdir -p "$ROOT/skills/demo/scripts"
printf 'kill -KILL $PPID\nexit 0\n' > "$ROOT/skills/demo/scripts/a_test.sh"
printf 'exit 0\n' > "$ROOT/skills/demo/scripts/b_test.sh"
run_check
expect "a suite with no exit status recorded fails the check" 1 \
    "bash skills/demo/scripts/a_test.sh (no exit status recorded)" "ok: bash skills/demo/scripts/b_test.sh"

# With one job at a time, that dead wrapper still frees its slot: the check
# goes on to the next suite instead of waiting for a status that never comes.
new_tree
mkdir -p "$ROOT/skills/demo/scripts"
printf 'kill -KILL $PPID\nexit 0\n' > "$ROOT/skills/demo/scripts/a_test.sh"
printf 'exit 0\n' > "$ROOT/skills/demo/scripts/b_test.sh"
CHECK_SKILL_JOBS=1 run_check_bounded 30
expect "CHECK_SKILL_JOBS=1 goes past a suite with no exit status" 1 \
    "bash skills/demo/scripts/a_test.sh (no exit status recorded)" "ok: bash skills/demo/scripts/b_test.sh"

# A check stopped with TERM stops the suites it started: each suite records
# its pid and sleeps; after the stop, none of them may still be alive.
new_tree
mkdir -p "$ROOT/skills/demo/scripts"
rm -rf "$MARKS"; mkdir -p "$MARKS"
for s in a b; do
    printf 'echo $$ > "$MARKS/pid.%s"\nsleep 30 &\necho $! > "$MARKS/pid.%s.child"\nwait\n' "$s" "$s" \
        > "$ROOT/skills/demo/scripts/${s}_test.sh"
done
# The check itself runs in the background, so $CHECKER is its own pid.
cd "$WORK" || exit 1
CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" "$BASH_BIN" "$CHECK_SH" demo >/dev/null 2>&1 &
CHECKER=$!
cd - >/dev/null || exit 1
n=0
while [ "$(ls "$MARKS" | grep -c '^pid\.')" -lt 4 ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -TERM "$CHECKER"
wait "$CHECKER" 2>/dev/null
sleep 0.5
alive=""
for f in "$MARKS"/pid.*; do
    [ -f "$f" ] || continue
    kill -0 "$(cat "$f")" 2>/dev/null && alive="$alive $(cat "$f")"
done
if [ "$(ls "$MARKS" | grep -c '^pid\.')" = 4 ] && [ -z "$alive" ]; then
    pass "a stopped check stops the suites it started, and what they started"
else
    fail "a stopped check stops the suites it started: still alive:${alive:- none}, pid files $(ls "$MARKS" | grep -c '^pid\.')"
    for p in $alive; do kill "$p" 2>/dev/null; done
fi

echo ""
echo "check-skill_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
