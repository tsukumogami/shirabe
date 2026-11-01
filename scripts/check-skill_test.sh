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
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1
# check-skill validates with SHIRABE_BIN when it is set (CI sets it for some
# suites); these fixtures exercise the stubs, so it is cleared here and set
# only by the case that tests it.
unset SHIRABE_BIN

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

WORK=$(mktemp -d) || exit 1
ktg_on_exit 'rm -rf "$WORK"'

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
    ROOT=$(mktemp -d "$WORK/root.XXXXXX") || exit 1
    mkdir -p "$ROOT/skills/demo/evals"
    # The script-case check runs the tree's own runner, so each tree has a copy.
    mkdir -p "$ROOT/scripts/lib"
    cp "$SCRIPT_DIR/lib/script-cases.py" "$ROOT/scripts/lib/"
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

# out_has <text>: whether $OUT holds <text>. grep reads a here-document, not a
# pipe: under pipefail, a grep -q that matches and exits before printf has
# written everything fails the writer, and with it the pipeline.
out_has() {
    grep -qF -- "$1" <<EOF
$OUT
EOF
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
        if ! out_has "$s"; then
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
if out_has 'mermaid'; then
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
if out_has 'helper.sh'; then
    fail "a script that is not *_test.sh was run"
else
    pass "only *_test.sh scripts run"
fi

# A failing case early in a long suite: the 60-line tail no longer holds it,
# so every FAIL line is listed, with the indented detail under it, and the
# load is recorded at the start and as the suite ended (shirabe#867).
new_tree
mkdir -p "$ROOT/skills/demo/scripts"
{
    printf '#!/bin/sh\necho "ok   first case"\n'
    printf 'echo "FAIL early case"\necho "     want [x], got [y]"\n'
    printf 'i=0; while [ "$i" -lt 100 ]; do echo "ok   case $i"; i=$((i + 1)); done\n'
    printf 'echo "1 failed"; exit 1\n'
} > "$ROOT/skills/demo/scripts/long_test.sh"
run_check
expect "a failing suite lists every FAIL line and the load" 1 \
    "check-skill: demo, load " "every FAIL line:" "      FAIL early case" \
    "      " "want [x], got [y]" "load when it ended: " "the log's last 60 lines:"
if awk '/every FAIL line:/ { s = 1; next } /load when it ended:/ { s = 0 } s && /ok   (first )?case/ { bad = 1 } END { exit !bad }' <<EOF
$OUT
EOF
then
    fail "the FAIL lines hold only failures and their detail"
else
    pass "the FAIL lines hold only failures and their detail"
fi

# The same, for the two other forms a suite prints a failure in: FAIL colored
# with ANSI codes, as panel-scope_test.sh prints it through echo -e, and TAP's
# "not ok". Colored PASS lines stay out of the list.
new_tree
mkdir -p "$ROOT/skills/demo/scripts"
{
    printf '#!/bin/sh\n'
    printf 'printf '"'"'\\033[0;32mPASS\\033[0m: first case\\n'"'"'\n'
    printf 'printf '"'"'\\033[0;31mFAIL\\033[0m: colored case\\n'"'"'\n'
    printf 'echo "    colored detail"\n'
    printf 'echo "not ok 3 - tap case"\n'
    printf 'i=0; while [ "$i" -lt 100 ]; do printf '"'"'\\033[0;32mPASS\\033[0m: case %%s\\n'"'"' "$i"; i=$((i + 1)); done\n'
    printf 'echo "1 failed"; exit 1\n'
} > "$ROOT/skills/demo/scripts/forms_test.sh"
run_check
expect "a failing suite lists its colored FAIL and not-ok lines" 1 \
    "every FAIL line:" "      "$'\033'"[0;31mFAIL"$'\033'"[0m: colored case" "          colored detail" \
    "      not ok 3 - tap case"
if awk '/every FAIL line:/ { s = 1; next } /load when it ended:/ { s = 0 } s && /PASS/ { bad = 1 } END { exit !bad }' <<EOF
$OUT
EOF
then
    fail "colored PASS lines are kept out of the FAIL lines"
else
    pass "colored PASS lines are kept out of the FAIL lines"
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

# Which shirabe validates (shirabe#860). The fixture tree here is shirabe's
# source (crates/shirabe/Cargo.toml) with a built target/release/shirabe that
# accepts everything, while the installed stub on PATH rejects STUB-REJECT:
# content only the branch's validator accepts.
branch_tree() { # branch_tree [stale]
    new_tree
    mkdir -p "$ROOT/crates/shirabe/src" "$ROOT/target/release" "$ROOT/skills/demo/references"
    printf '[package]\nname = "shirabe"\n' > "$ROOT/crates/shirabe/Cargo.toml"
    printf '[workspace]\n' > "$ROOT/Cargo.toml"
    : > "$ROOT/crates/shirabe/src/main.rs"
    touch -t 202001010000 "$ROOT/Cargo.toml" "$ROOT/crates/shirabe/Cargo.toml" "$ROOT/crates/shirabe/src/main.rs"
    printf '#!/bin/sh\n[ "$1" = validate ] || exit 2\necho "branch validator" >> "$SHIRABE_LOG"\nexit 0\n' > "$ROOT/target/release/shirabe"
    chmod +x "$ROOT/target/release/shirabe"
    [ "${1:-}" = stale ] && touch "$ROOT/crates/shirabe/src/main.rs"
    printf 'STUB-REJECT\n' > "$ROOT/skills/demo/references/v2.md"
}
branch_tree
run_check "$STUBS:$TOOLBIN:/usr/bin:/bin"
expect "the tree's fresh build validates what the installed release rejects" 0 \
    "validating with $ROOT/target/release/shirabe (the tree's build)" "ok: shirabe validate"
branch_tree stale
run_check "$STUBS:$TOOLBIN:/usr/bin:/bin"
expect "a stale build with no cargo falls back to the installed shirabe, and says so" 1 \
    "validating with $STUBS/shirabe (the installed release)" "shirabe validate rejected"
branch_tree stale
OUT=$(cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" SHIRABE_BIN="$ROOT/target/release/shirabe" PATH="$STUBS:$TOOLBIN:/usr/bin:/bin" \
    "$BASH_BIN" "$CHECK_SH" demo 2>&1); RC=$?
expect "SHIRABE_BIN, when set, is the validator" 0 "validating with $ROOT/target/release/shirabe (SHIRABE_BIN)"
new_tree
NOSHIRABE="$WORK/stubs-noshirabe"
mkdir -p "$NOSHIRABE"
cp "$STUBS/koto" "$STUBS/claude" "$NOSHIRABE/"
run_check "$NOSHIRABE:$TOOLBIN:/usr/bin:/bin"
expect "no shirabe on PATH and none in the tree exits 2, naming it" 2 "not on PATH: shirabe"

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
T=$(mktemp -d) || exit 1
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

# A plain TERM to the check reaches everything its suites started, however
# deep, and stops a suite that ignores TERM too. Each suite records the pids
# that must not survive:
#   deep:   the suite runs a script that runs a sleep, three levels below the
#           job that waits on the suite;
#   deaf:   the suite ignores TERM, and so does the sleep it starts, which
#           inherits the ignored signal;
#   orphan: the suite's sleep is left behind by a subshell that has already
#           exited, so it belongs to pid 1, not to the suite.
# `stopped_tree leader` runs the check as its own job, so it leads its process
# group the way it does as a terminal's job or as the verification gate's
# command, and all three suites run. `stopped_tree shared` runs it in this
# harness's group, where only its descendants are its own: the orphan suite is
# left out, and the other two show the walk of the tree reaches them without
# the group.
stopped_tree() {
    local mode="$1" want=4 f p n=0 alive=""
    new_tree
    mkdir -p "$ROOT/skills/demo/scripts"
    rm -rf "$MARKS"; mkdir -p "$MARKS"
    printf 'sleep 30 &\necho $! > "$MARKS/pid.deep"\nwait\n' > "$ROOT/skills/demo/scripts/deep-helper.sh"
    printf 'bash "$(dirname "$0")/deep-helper.sh" &\nwait\n' > "$ROOT/skills/demo/scripts/deep_test.sh"
    printf 'trap "" TERM\necho $$ > "$MARKS/pid.deaf"\nsleep 30 &\necho $! > "$MARKS/pid.deaf.child"\nwait\n' \
        > "$ROOT/skills/demo/scripts/deaf_test.sh"
    if [ "$mode" = leader ]; then
        printf '( sleep 30 &\n  echo $! > "$MARKS/pid.orphan" )\nsleep 30 &\nwait\n' \
            > "$ROOT/skills/demo/scripts/orphan_test.sh"
    else
        want=3
    fi
    cd "$WORK" || exit 1
    [ "$mode" = leader ] && set -m
    CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" "$BASH_BIN" "$CHECK_SH" demo >/dev/null 2>&1 &
    CHECKER=$!
    set +m
    cd - >/dev/null || exit 1
    while [ "$(ls "$MARKS" | grep -c '^pid\.')" -lt "$want" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    kill -TERM "$CHECKER"
    wait "$CHECKER" 2>/dev/null
    sleep 0.5
    for f in "$MARKS"/pid.*; do
        [ -f "$f" ] || continue
        kill -0 "$(cat "$f")" 2>/dev/null && alive="$alive $(basename "$f")=$(cat "$f")"
    done
    if [ "$(ls "$MARKS" | grep -c '^pid\.')" = "$want" ] && [ -z "$alive" ]; then
        pass "a plain TERM to the check ($mode group) stops its suites' deepest descendants and a suite ignoring TERM${2:+, $2}"
    else
        fail "a plain TERM to the check ($mode group) left processes running:${alive:- none}, pid files $(ls "$MARKS" | grep -c '^pid\.')"
        for p in $alive; do kill -KILL "${p#*=}" 2>/dev/null; done
    fi
}
stopped_tree leader "and an orphaned child"
stopped_tree shared

# -- Launch order ----------------------------------------------------------------
# check-skill.tsv's cost rows start the costliest suites first; a suite with no
# row starts after them, in the glob's order. Results still print in the glob's
# order.
new_tree
mkdir -p "$ROOT/skills/demo/scripts"
rm -rf "$MARKS"; mkdir -p "$MARKS"
for s in a b c d e; do
    printf 'echo %s >> "$MARKS/started"\n' "$s" > "$ROOT/skills/demo/scripts/${s}_test.sh"
done
printf '# costs\ncost\tb_test.sh\t5\ncost\td_test.sh\t300\ncost\ta_test.sh\t40\n' \
    > "$ROOT/skills/demo/check-skill.tsv"
CHECK_SKILL_JOBS=1 run_check
expect "suites with cost rows pass" 0 "ok: bash skills/demo/scripts/e_test.sh"
started=$(tr '\n' ' ' < "$MARKS/started")
if [ "$started" = "d a b c e " ]; then
    pass "suites launch costliest first, the ones with no cost row last in the glob's order"
else
    fail "launch order: got [$started], want [d a b c e ]"
fi
order=$(printf '%s\n' "$OUT" | grep -E '^ok: bash ' | sed 's/.*scripts\///' | tr '\n' ' ')
if [ "$order" = "a_test.sh b_test.sh c_test.sh d_test.sh e_test.sh " ]; then
    pass "results still print in the glob's order"
else
    fail "results print in the glob's order: got [$order]"
fi

# -- Selecting suites by changed path (--changed) ---------------------------------
# select_tree: skill demo with a check-skill.tsv and these scripts:
#   lib.sh       sourced by one.sh and two.sh, so shared without a row
#   pinned.sh    named on a shared row
#   one.sh       run by caller.sh
#   caller.sh    runs one.sh
#   lonely.sh    named by the engine suite alone
#   orphan.sh    named by no suite
#   two.sh       named by no suite, but two_test.sh is its own
# and suites one_test.sh (names one.sh), caller_test.sh (names caller.sh),
# two_test.sh (names nothing), flow_engine_test.sh (names one.sh and
# lonely.sh), and testdata/lib.sh. Each suite passes.
select_tree() {
    new_tree
    local d="$ROOT/skills/demo/scripts"
    mkdir -p "$d/testdata"
    printf 'shared\tpinned.sh\n' > "$ROOT/skills/demo/check-skill.tsv"
    printf 'x=1\n' > "$d/lib.sh"
    printf 'pinned\n' > "$d/pinned.sh"
    printf '. "$HERE/lib.sh"\n' > "$d/one.sh"
    printf '. "$HERE/lib.sh"\n' > "$d/two.sh"
    printf 'bash "$HERE/one.sh"\n' > "$d/caller.sh"
    printf 'lonely\n' > "$d/lonely.sh"
    printf 'orphan\n' > "$d/orphan.sh"
    printf 'helper\n' > "$d/testdata/lib.sh"
    printf '# one.sh\nexit 0\n' > "$d/one_test.sh"
    printf '# caller.sh\nexit 0\n' > "$d/caller_test.sh"
    printf 'exit 0\n' > "$d/two_test.sh"
    printf '# one.sh lonely.sh\nexit 0\n' > "$d/flow_engine_test.sh"
}
ALL_DEMO="skills/demo/scripts/caller_test.sh skills/demo/scripts/flow_engine_test.sh skills/demo/scripts/one_test.sh skills/demo/scripts/two_test.sh"

# run_list <changed paths, one per line>: --changed --list on demo; LISTED is
# the selected suites, sorted and space-separated.
run_list() {
    OUT=$(cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" CHECK_SKILL_CHANGED="$1" \
        "$BASH_BIN" "$CHECK_SH" --changed --list "${SKILL_ARG:-demo}" 2>&1)
    RC=$?
    LISTED=$(printf '%s\n' "$OUT" | grep '^skills/' | sort | tr '\n' ' ' | sed 's/ $//')
}

# expect_listed <name> <want, sorted and space-separated> [<substring>]
expect_listed() {
    if [ "$RC" != 0 ]; then
        fail "$1: exit $RC"; printf '%s\n' "$OUT" | sed 's/^/    /'; return
    fi
    if [ "$LISTED" != "$2" ]; then
        fail "$1: selected [$LISTED], want [$2]"; printf '%s\n' "$OUT" | sed 's/^/    /'; return
    fi
    if [ -n "${3:-}" ] && ! out_has "$3"; then
        fail "$1: output lacks '$3'"; printf '%s\n' "$OUT" | sed 's/^/    /'; return
    fi
    pass "$1"
}

select_tree
run_list skills/demo/scripts/one.sh
expect_listed "a one-script change selects its own suite and its caller's, no engine suite" \
    "skills/demo/scripts/caller_test.sh skills/demo/scripts/one_test.sh" "selects 2 of 4 suites"
if [ ! -s "$SHIRABE_LOG" ]; then
    pass "--list runs no check"
else
    fail "--list ran shirabe validate"
fi

select_tree
run_list skills/demo/scripts/caller.sh
expect_listed "a script nothing else runs selects only the suites naming it" \
    "skills/demo/scripts/caller_test.sh"

select_tree
run_list skills/demo/scripts/two_test.sh
expect_listed "a changed suite selects itself" "skills/demo/scripts/two_test.sh"

select_tree
run_list skills/demo/scripts/two.sh
expect_listed "a script's own suite is selected though it doesn't name the script" \
    "skills/demo/scripts/two_test.sh"

select_tree
run_list skills/demo/scripts/lonely.sh
expect_listed "a script only an engine suite names selects that engine suite" \
    "skills/demo/scripts/flow_engine_test.sh"

select_tree
run_list "skills/demo/scripts/caller.sh
skills/demo/scripts/two_test.sh"
expect_listed "selections from several paths add up" \
    "skills/demo/scripts/caller_test.sh skills/demo/scripts/two_test.sh"

# evals/ (shirabe#851): the suites that can read it, none in select_tree.
select_tree
run_list "skills/demo/evals/evals.json
skills/demo/evals/fixtures/plan.md"
expect_listed "an evals-only change selects no suite when none reads evals/" "" \
    "selects 0 of 4 suites"

select_tree
run_list "skills/demo/evals/evals.json
skills/demo/scripts/caller.sh"
expect_listed "an evals change beside a script change selects what the script change does" \
    "skills/demo/scripts/caller_test.sh"

select_tree
run_list skills/other/evals/evals.json
expect_listed "another skill's evals/ is classified the same way" "" "selects 0 of 4 suites"

# evals_tree: select_tree plus fixtures.sh, a helper that names evals/, and
# wrapper.sh, which names fixtures.sh; a suite for each way to reach evals/;
# and near_test.sh, whose record_find and --repo look like a walk and aren't.
evals_tree() {
    select_tree
    local d="$ROOT/skills/demo/scripts"
    printf 'cat "$HERE/../evals/fixtures/plan.md"\n' > "$d/fixtures.sh"
    printf '. "$HERE/fixtures.sh"\n' > "$d/wrapper.sh"
    printf '# ../evals/fixtures\nexit 0\n' > "$d/reader_test.sh"
    printf 'find "$HERE/.." -name "*.md"\nexit 0\n' > "$d/find_test.sh"
    printf 'grep -rn x "$HERE/.."\nexit 0\n' > "$d/grepr_test.sh"
    printf 'grep -l -R x "$HERE/.."\nexit 0\n' > "$d/grepcap_test.sh"
    printf 'git ls-files -- skills/demo\nexit 0\n' > "$d/lsfiles_test.sh"
    printf '# fixtures.sh\nexit 0\n' > "$d/uses_test.sh"
    printf '# wrapper.sh\nexit 0\n' > "$d/deep_test.sh"
    printf 'record_find x\ngrep -q -- --repo y\nexit 0\n' > "$d/near_test.sh"
}
evals_tree
run_list skills/demo/evals/fixtures/plan.md
expect_listed "an evals change selects the suites that name evals, walk the tree, or reach a helper that names evals" \
    "skills/demo/scripts/deep_test.sh skills/demo/scripts/find_test.sh skills/demo/scripts/grepcap_test.sh skills/demo/scripts/grepr_test.sh skills/demo/scripts/lsfiles_test.sh skills/demo/scripts/reader_test.sh skills/demo/scripts/uses_test.sh" \
    "selects 7 of 12 suites"

# Every way to reach every suite. Each case's reason must be printed too.
for c in \
    "skills/demo/scripts/lib.sh|is sourced by 2 files" \
    "skills/demo/scripts/pinned.sh|is shared (check-skill.tsv)" \
    "skills/demo/scripts/testdata/lib.sh|is shared test code" \
    "skills/demo/check-skill.tsv|is not one of skills/demo's scripts" \
    "skills/demo/SKILL.md|is not one of skills/demo's scripts" \
    "scripts/check-skill.sh|is not one of skills/demo's scripts" \
    "skills/other/x.sh|is not one of skills/demo's scripts" \
    "skills/other/scripts/evals/x.sh|is not one of skills/demo's scripts" \
    "skills/demo/scripts/evals/x.sh|is shared test code" \
    "skills/demo/scripts/orphan.sh|no suite names" \
    "skills/demo/scripts/gone.sh|is deleted" \
    "skills/demo/scripts/gone_test.sh|is deleted"; do
    path=${c%%|*}
    select_tree
    run_list "skills/demo/scripts/one.sh
$path"
    expect_listed "a change to $path runs every suite" "$ALL_DEMO" "${c#*|}"
done

select_tree
run_list ""
expect_listed "no changed path runs every suite" "$ALL_DEMO" "no changed path"

select_tree
rm "$ROOT/skills/demo/check-skill.tsv"
run_list skills/demo/scripts/one.sh
expect_listed "a skill with no check-skill.tsv runs every suite" "$ALL_DEMO" "has no check-skill.tsv"
run_list skills/demo/evals/evals.json
expect_listed "  ... but an evals-only change still selects its readers" "" "selects 0 of 4 suites"
run_list "skills/demo/evals/evals.json
skills/demo/scripts/caller.sh"
expect_listed "  ... and an evals change beside any other runs every suite" "$ALL_DEMO" \
    "has no check-skill.tsv"

new_tree
run_check_args() {
    OUT=$(cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" "$BASH_BIN" "$CHECK_SH" "$@" 2>&1)
    RC=$?
}
run_check_args --list demo
expect "--list without --changed is a usage error" 2 "usage:"
run_check_args --bogus demo
expect "an unknown option is a usage error" 2 "usage:"

# --changed runs only the selected suites, the other checks as before.
select_tree
printf '# one.sh\nexit 1\n' > "$ROOT/skills/demo/scripts/two_test.sh"
OUT=$(cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" \
    CHECK_SKILL_CHANGED=skills/demo/scripts/caller.sh "$BASH_BIN" "$CHECK_SH" --changed demo 2>&1)
RC=$?
expect "--changed runs the selected suites and skips the rest" 0 \
    "ok: bash skills/demo/scripts/caller_test.sh" "ok: eval shape" "check-skill: demo passed"
if out_has 'two_test.sh'; then
    fail "--changed ran a suite it didn't select"
else
    pass "  ... and an unselected failing suite doesn't run"
fi

# Without CHECK_SKILL_CHANGED, the paths come from git: the merge-base with
# main, committed and uncommitted changes, and untracked files.
select_tree
(cd "$ROOT" && git init -q -b main . && git add -A \
    && git -c user.name=t -c user.email=t@t commit -qm base \
    && git checkout -qb topic && printf 'changed\n' >> skills/demo/scripts/caller.sh \
    && git -c user.name=t -c user.email=t@t commit -qam change) >/dev/null 2>&1
OUT=$(cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" \
    "$BASH_BIN" "$CHECK_SH" --changed --list demo 2>&1)
RC=$?
LISTED=$(printf '%s\n' "$OUT" | grep '^skills/' | sort | tr '\n' ' ' | sed 's/ $//')
expect_listed "--changed reads the branch's commits against main" "skills/demo/scripts/caller_test.sh"
printf 'new\n' > "$ROOT/skills/demo/scripts/untracked.sh"
OUT=$(cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" \
    "$BASH_BIN" "$CHECK_SH" --changed --list demo 2>&1)
RC=$?
LISTED=$(printf '%s\n' "$OUT" | grep '^skills/' | sort | tr '\n' ' ' | sed 's/ $//')
expect_listed "  ... and counts an untracked file" "$ALL_DEMO" "untracked.sh"

# -- Script cases (check 6) -------------------------------------------------------
# The trees new_tree builds hold no script case and no git repository, and
# the check passes them having run none.
new_tree
run_check
expect "a tree with no script cases passes the script-case check" 0 \
    "ok: script cases (0 of 0 passed)" "check-skill: demo passed"

new_tree
rm "$ROOT/skills/demo/evals/evals.json"
printf -- '---\nname: demo\ndescription: d\ndisable-model-invocation: true\n---\n' \
    > "$ROOT/skills/demo/SKILL.md"
run_check
expect "a skill with no evals.json has no script cases of its own" 0 \
    "ok: script cases (0 of 0 passed)"

new_tree
rm "$ROOT/scripts/lib/script-cases.py"
run_check
expect "a tree with no runner fails the check closed, naming the path" 1 \
    "FAIL: script cases: no runner at scripts/lib/script-cases.py"

# case_repo: a fixture repository (git init, git add -A) with a copy of the
# runner and these skills and cases:
#   demo       1 graded; 2 own-check (handoff caller, ok.sh); a suite,
#              plain_test.sh, that leaves suite.ran
#   caller     7 handoff-demo (handoff demo, ok.sh); 8 graded-mark, graded,
#              whose run is mark.sh
#   bystander  3 handoff-caller (handoff caller, broken.sh)
# scripts/cases/: ok.sh exits 0; broken.sh prints the reason line and exits
# 1; mark.sh leaves mark.ran; hang.sh starts `sleep 300 &`, writes its own
# pid and its child's to case.pid and child.pid, and waits.
CASE_EDIT="$WORK/case-edit.py"
cat > "$CASE_EDIT" <<'EOF'
import json, sys
path, cid, key, value = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
with open(path) as fh:
    data = json.load(fh)
for case in data["evals"]:
    if case.get("id") == cid:
        case[key] = value
with open(path, "w") as fh:
    json.dump(data, fh, indent=1)
EOF
# set_case <skill> <id> <key> <value>: set one field of one case.
set_case() { python3 "$CASE_EDIT" "$ROOT/skills/$1/evals/evals.json" "$2" "$3" "$4"; }
REASON="outcome word landed is not expected"
case_repo() {
    local s
    new_tree
    mkdir -p "$ROOT/scripts/cases" "$ROOT/skills/demo/scripts"
    printf '#!/bin/sh\nexit 0\n' > "$ROOT/scripts/cases/ok.sh"
    printf '#!/bin/sh\necho "%s"\nexit 1\n' "$REASON" > "$ROOT/scripts/cases/broken.sh"
    printf '#!/bin/sh\n: > mark.ran\nexit 0\n' > "$ROOT/scripts/cases/mark.sh"
    printf '#!/bin/sh\nsleep 300 &\necho $! > child.pid\necho $$ > case.pid\nwait\n' \
        > "$ROOT/scripts/cases/hang.sh"
    chmod +x "$ROOT"/scripts/cases/*.sh
    printf ': > "$PWD/suite.ran"\n' > "$ROOT/skills/demo/scripts/plain_test.sh"
    for s in caller bystander; do
        mkdir -p "$ROOT/skills/$s/evals"
        printf -- '---\nname: %s\ndescription: A %s skill.\n---\n\n# %s\n' "$s" "$s" "$s" \
            > "$ROOT/skills/$s/SKILL.md"
    done
    cat > "$ROOT/skills/demo/evals/evals.json" <<'EOF'
{"skill_name": "demo", "evals": [
  {"id": 1, "name": "first", "prompt": "do the thing", "expectations": ["it does the thing"]},
  {"id": 2, "name": "own-check", "grader": "script", "handoff": "caller", "run": "scripts/cases/ok.sh"}
]}
EOF
    cat > "$ROOT/skills/caller/evals/evals.json" <<'EOF'
{"skill_name": "caller", "evals": [
  {"id": 7, "name": "handoff-demo", "grader": "script", "handoff": "demo", "run": "scripts/cases/ok.sh"},
  {"id": 8, "name": "graded-mark", "prompt": "p", "expectations": ["e"], "run": "scripts/cases/mark.sh"}
]}
EOF
    cat > "$ROOT/skills/bystander/evals/evals.json" <<'EOF'
{"skill_name": "bystander", "evals": [
  {"id": 3, "name": "handoff-caller", "grader": "script", "handoff": "caller", "run": "scripts/cases/broken.sh"}
]}
EOF
    (cd "$ROOT" && git init -q . && git add -A) >/dev/null 2>&1
}

# closing_has <text>: whether the closing `check-skill: <skill> failed:` list
# holds <text>.
closing_has() {
    awk -v t="$1" '/^check-skill: .* failed:$/ { s = 1; next } s && index($0, t) { f = 1 } END { exit !f }' <<EOF
$OUT
EOF
}
# below <first> <second>: whether a line holding <second> comes after the
# first line holding <first>.
below() {
    awk -v a="$1" -v b="$2" 'index($0, a) && !n { n = NR } n && NR > n && index($0, b) { f = 1 } END { exit !f }' <<EOF
$OUT
EOF
}
# count_of <text>: how many lines of $OUT hold <text>.
count_of() {
    awk -v t="$1" 'index($0, t) { c++ } END { print c + 0 }' <<EOF
$OUT
EOF
}

case_repo
run_check
expect "a skill's own script case and another skill's case that targets it pass" 0 \
    "ok: script cases (2 of 2 passed)" "check-skill: demo passed"
if out_has bystander || out_has handoff-caller || out_has graded-mark; then
    fail "  ... the check named a case that doesn't target demo"
    printf '%s\n' "$OUT" | sed 's/^/    /'
else
    pass "  ... and names neither a case aimed elsewhere nor a graded case"
fi
if [ -e "$ROOT/mark.ran" ]; then
    fail "  ... a graded case's run was executed"
else
    pass "  ... and no graded case's run is executed"
fi

case_repo
set_case caller 7 run scripts/cases/broken.sh
run_check
expect "another skill's failing case fails this skill's check" 1 \
    "FAIL: script case: caller 7 handoff-demo" "ok: bash skills/demo/scripts/plain_test.sh" \
    "ok: eval shape" "check-skill: demo failed:"
if below "FAIL: script case: caller 7 handoff-demo" "$REASON" \
    && closing_has "script case: caller 7 handoff-demo" \
    && [ "$(awk '/^check-skill: demo failed:$/ { s = 1; next } s && NF { c++ } END { print c + 0 }' <<EOF
$OUT
EOF
)" = 1 ]; then
    pass "  ... with its reason under it and only it in the closing list"
else
    fail "  ... the reason or the closing list is wrong"
    printf '%s\n' "$OUT" | sed 's/^/    /'
fi

case_repo
SKILL_ARG=caller run_check
expect "a case that targets the skill fails its check" 1 \
    "FAIL: script case: bystander 3 handoff-caller" "script cases: 2 of 3 passed"
if closing_has "script case: bystander 3 handoff-caller"; then
    pass "  ... and the closing list names it"
else
    fail "  ... the closing list lacks it"
fi

case_repo
set_case bystander 3 handoff demo
run_check
expect "the selection follows a case's handoff, not the skills its run names" 1 \
    "FAIL: script case: bystander 3 handoff-caller"

case_repo
python3 - "$ROOT/skills/demo/evals/evals.json" <<'EOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
data["evals"].append({"id": 4, "name": "self-check", "grader": "script", "handoff": "demo",
                      "run": "scripts/cases/broken.sh"})
with open(sys.argv[1], "w") as fh:
    json.dump(data, fh, indent=1)
EOF
run_check
expect "a skill's case on a hand-off to itself fails its check" 1 \
    "FAIL: script case: demo 4 self-check" "script cases: 2 of 3 passed"
if [ "$(count_of "FAIL: script case: demo 4 self-check")" = 1 ]; then
    pass "  ... and runs once"
else
    fail "  ... it ran $(count_of "FAIL: script case: demo 4 self-check") times"
fi

case_repo
set_case caller 7 run scripts/cases/broken.sh
set_case demo 2 run scripts/cases/broken.sh
run_check
expect "every failing case is listed" 1 \
    "FAIL: script case: demo 2 own-check" "FAIL: script case: caller 7 handoff-demo"
if closing_has "script case: demo 2 own-check" && closing_has "script case: caller 7 handoff-demo" \
    && ! out_has "ok: script cases"; then
    pass "  ... in the closing list, with no ok line"
else
    fail "  ... the closing list or the ok line is wrong"
    printf '%s\n' "$OUT" | sed 's/^/    /'
fi

case_repo
printf '{"evals": [\n' > "$ROOT/skills/bystander/evals/evals.json"
run_check
expect "a runner that can't run fails the check closed" 1 \
    "skills/bystander/evals/evals.json" "script cases: the runner exited 2"

# --changed: the suites narrow, the script cases run in full.
case_repo
set_case caller 7 run scripts/cases/broken.sh
OUT=$(cd "$WORK" && CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" \
    CHECK_SKILL_CHANGED=skills/demo/evals/evals.json "$BASH_BIN" "$CHECK_SH" --changed demo 2>&1)
RC=$?
expect "--changed on an evals-only change runs no suite but every script case" 1 \
    "--changed selects 0 of 1 suites" "FAIL: script case: caller 7 handoff-demo"
if [ -e "$ROOT/suite.ran" ]; then
    fail "  ... a suite ran"
else
    pass "  ... and no suite ran"
fi

case_repo
set_case demo 2 run scripts/cases/mark.sh
set_case caller 7 run scripts/cases/broken.sh
run_list skills/demo/evals/evals.json
expect "--changed --list lists the script cases and runs none" 0 \
    "script case: demo 2 own-check" "script case: caller 7 handoff-demo"
if [ ! -e "$ROOT/mark.ran" ] && [ ! -s "$SHIRABE_LOG" ] && [ ! -e "$ROOT/suite.ran" ]; then
    pass "  ... no case, check or suite ran"
else
    fail "  ... something ran: $(ls "$ROOT"), shirabe log $(wc -c < "$SHIRABE_LOG") bytes"
fi
run_list "skills/demo/evals/evals.json
skills/demo/scripts/plain_test.sh"
if [ "$RC" = 0 ] && below "skills/demo/scripts/plain_test.sh" "script case: demo 2 own-check" \
    && [ "$(printf '%s\n' "$OUT" | grep -c '^script case: ')" = 2 ]; then
    pass "  ... after the selected suites"
else
    fail "  ... the script cases don't follow the suites"
    printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# The runner's --for selection and its usage errors.
case_repo
RUNNER="$ROOT/scripts/lib/script-cases.py"
OUT=$(python3 "$RUNNER" --for demo --list 2>&1); RC=$?
if [ "$RC" = 0 ] && [ "$OUT" = "demo 2 own-check
caller 7 handoff-demo" ]; then
    pass "script-cases.py --for --list prints each selected case as <skill> <id> <name>"
else
    fail "script-cases.py --for --list: exit $RC, got [$OUT]"
fi
for c in \
    "--for demo --scenario own-check|--scenario" \
    "--for demo --summary-out s.json|--summary-out" \
    "--for nosuchskill|nosuchskill" \
    "--for demo --all|--all" \
    "--for demo caller|skill name" \
    "demo --list|--list"; do
    args=${c%%|*}
    # shellcheck disable=SC2086 # the arguments are words
    OUT=$(python3 "$RUNNER" $args 2>&1); RC=$?
    expect "script-cases.py $args is a usage error" 2 "${c#*|}"
done
if [ -e "$ROOT/s.json" ]; then
    fail "  ... a summary was written"
else
    pass "  ... and no summary is written"
fi

# <skill> and --all keep their output and summary.
case_repo
RUNNER="$ROOT/scripts/lib/script-cases.py"
OUT=$(python3 "$RUNNER" demo --summary-out "$WORK/one.json" 2>&1); RC=$?
expect "script-cases.py <skill> lists graded cases as refused and runs the rest" 0 \
    "REFUSED 1 first: graded cases don't run" "PASS 2 own-check" "script cases: 1 of 1 passed"
if python3 - "$WORK/one.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
d = s["skills"]["demo"]
assert s["schema"] == "script-cases-summary/v1"
assert list(s["skills"]) == ["demo"]
assert d["cases_run"] == 1 and d["cases_passed"] == 1 and d["pass_rate"] == 1.0
assert d["refused"] == [{"id": 1, "name": "first"}]
assert d["cases"] == [{"id": 2, "name": "own-check", "verdict": "pass"}]
EOF
then
    pass "  ... and writes its summary as before"
else
    fail "  ... its summary changed"
fi
OUT=$(python3 "$RUNNER" --all 2>&1); RC=$?
expect "script-cases.py --all runs every skill's cases under their headers" 1 \
    "== bystander" "FAIL 3 handoff-caller: exited 1" "== caller" "REFUSED 8 graded-mark" \
    "== demo" "script cases: 2 of 3 passed"

# A stopped check leaves no case running: hang.sh records its pid and its
# child's, and the check (then the runner alone) is sent TERM while it waits.
# wait_for_case: up to 60 seconds for both pid files.
wait_for_case() {
    local n=0
    while { [ ! -s "$ROOT/case.pid" ] || [ ! -s "$ROOT/child.pid" ]; } && [ "$n" -lt 600 ]; do
        sleep 0.1; n=$((n + 1))
    done
}
# case_alive: the recorded pids still alive, or nothing.
case_alive() {
    local f alive=""
    for f in "$ROOT/case.pid" "$ROOT/child.pid"; do
        [ -s "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null && alive="$alive $(cat "$f")"
    done
    printf '%s' "$alive"
}
case_repo
set_case demo 2 run scripts/cases/hang.sh
cd "$WORK" || exit 1
CHECK_SKILL_ROOT="$ROOT" PATH="$STUBS:$PATH" "$BASH_BIN" "$CHECK_SH" demo >/dev/null 2>&1 &
CHECKER=$!
cd - >/dev/null || exit 1
wait_for_case
kill -TERM "$CHECKER"
wait "$CHECKER"
RC=$?
sleep 0.5
alive=$(case_alive)
if [ "$RC" = 143 ] && [ -s "$ROOT/child.pid" ] && [ -z "$alive" ]; then
    pass "TERM to the check while a case runs exits 143 and leaves neither the case nor its child"
else
    fail "TERM to the check while a case runs: exit $RC, still alive:${alive:- none}"
    for p in $alive; do kill -KILL "$p" 2>/dev/null; done
fi

rm -f "$ROOT/case.pid" "$ROOT/child.pid"
python3 "$ROOT/scripts/lib/script-cases.py" --for demo >/dev/null 2>&1 &
CHECKER=$!
wait_for_case
kill -TERM "$CHECKER"
wait "$CHECKER"
RC=$?
sleep 0.5
alive=$(case_alive)
if [ "$RC" = 143 ] && [ -s "$ROOT/child.pid" ] && [ -z "$alive" ]; then
    pass "TERM to the runner alone kills the running case's group before it exits"
else
    fail "TERM to the runner alone: exit $RC, still alive:${alive:- none}"
    for p in $alive; do kill -KILL "$p" 2>/dev/null; done
fi

# -- The coordinate skill's own selection ----------------------------------------
# Against the real skills/coordinate: a change to anything shared selects every
# suite, and a one-script change selects only that script's suites.
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
COORD_ALL=$(cd "$REPO_ROOT" && ls skills/coordinate/scripts/*_test.sh | sort | tr '\n' ' ' | sed 's/ $//')
# run_coord_list <path>: --changed --list on the real coordinate skill.
run_coord_list() {
    OUT=$(cd "$REPO_ROOT" && PATH="$STUBS:$PATH" CHECK_SKILL_CHANGED="$1" \
        "$BASH_BIN" "$CHECK_SH" --changed --list coordinate 2>&1)
    RC=$?
    LISTED=$(printf '%s\n' "$OUT" | grep '^skills/' | sort | tr '\n' ' ' | sed 's/ $//')
}
for path in \
    skills/coordinate/scripts/dispatch-common.sh \
    skills/coordinate/scripts/state-common.sh \
    skills/coordinate/scripts/coord-log.sh \
    skills/coordinate/scripts/coord-verdict.sh \
    skills/coordinate/scripts/coordinate-open.sh \
    skills/coordinate/scripts/state-schema.jq \
    skills/coordinate/scripts/testdata/test-lib.sh \
    skills/coordinate/scripts/testdata/coordinate-engine-lib.sh \
    skills/coordinate/koto-templates/coordinate.md \
    skills/coordinate/check-skill.tsv \
    skills/coordinate/SKILL.md \
    scripts/check-skill.sh \
    scripts/lib/koto-legacy-env.sh; do
    run_coord_list "$path"
    expect_listed "coordinate: a change to shared $path selects all $(printf '%s\n' "$COORD_ALL" | wc -w | tr -d ' ') suites" \
        "$COORD_ALL" "runs every suite"
done
run_coord_list skills/coordinate/scripts/need-check.sh
expect_listed "coordinate: a change to need-check.sh selects only need-check_test.sh" \
    "skills/coordinate/scripts/need-check_test.sh" "selects 1 of"

# Every coordinate suite has a cost row and every cost row names a suite, so
# a new suite can't quietly launch last. scripts/check-cost-rows.sh holds the
# one copy of the comparison; pull request CI runs it in check-cost-rows.yml,
# and this case keeps it on the macOS floor.
if OUT=$("$BASH_BIN" "$SCRIPT_DIR/check-cost-rows.sh" coordinate 2>&1); then
    pass "coordinate: check-skill.tsv has one cost row per suite"
else
    fail "coordinate: cost rows and suites differ: $(printf '%s\n' "$OUT" | sed -n 's/^coordinate: //p' | tr '\n' ';')"
fi

# -- The real tree's script cases -------------------------------------------------
# What check 6 runs for each skill, read from --changed --list on an evals-only
# change, the way the coordinate cases read the real tree: a skill's own cases,
# then every other skill's whose handoff names it.
for c in \
    "execute|execute 86 handoff-work-on-contract;coordinate 44 handoff-execute-contract;deliver 34 handoff-execute-contract" \
    "work-on|coordinate 46 handoff-work-on-contract;execute 86 handoff-work-on-contract" \
    "scope|coordinate 45 handoff-scope-contract;deliver 35 handoff-scope-contract" \
    "deliver|deliver 34 handoff-execute-contract;deliver 35 handoff-scope-contract;coordinate 43 handoff-deliver-contract" \
    "coordinate|coordinate 43 handoff-deliver-contract;coordinate 44 handoff-execute-contract;coordinate 45 handoff-scope-contract;coordinate 46 handoff-work-on-contract" \
    "plan|"; do
    skill=${c%%|*}
    want=${c#*|}
    OUT=$(cd "$REPO_ROOT" && PATH="$STUBS:$PATH" CHECK_SKILL_CHANGED="skills/$skill/evals/evals.json" \
        "$BASH_BIN" "$CHECK_SH" --changed --list "$skill" 2>&1)
    RC=$?
    got=$(printf '%s\n' "$OUT" | sed -n 's/^script case: //p' | tr '\n' ';' | sed 's/;$//')
    if [ "$RC" = 0 ] && [ "$got" = "$want" ]; then
        pass "real tree: $skill's check runs [${want:-no script case}]"
    else
        fail "real tree: $skill's check: exit $RC, got [$got], want [$want]"
    fi
done

echo ""
echo "check-skill_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
