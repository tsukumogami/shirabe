#!/usr/bin/env bash
# check-tick-launches_test.sh -- test harness for scripts/check-tick-launches.sh.
#
# Usage: bash scripts/check-tick-launches_test.sh
#
# Cases:
#   the shipped tree passes: no template command, and no script one runs,
#     launches `niwa dispatch` or `claude` without unsetting KOTO_SESSION_*
#   a copy of a shipped template with one offending gate added fails, naming
#     the template line (the fixture that shows the check bites)
#   in a fixture plugin root, each of these fails, named by template line or
#     by script and line: a gate's `niwa dispatch`, a default action's
#     `claude -p`, a block-scalar command, a script a command runs, a script
#     that script runs, a `"$NIWA" dispatch` and a `"$CLAUDE_BIN" -p`, and a
#     Python argument list
#   and each of these passes: the same launches after `unset KOTO_SESSION_*`
#     or with `env -u KOTO_SESSION_...` on the line, a message that mentions
#     claude or niwa dispatch, `claude agents`/`claude rm`, `niwa dispatch
#     --help`, a comment, and a script nothing runs
#   an allow record exempts the one call it names, a script run from
#     elsewhere is still followed, a stale record fails, and a record with no
#     reason is refused
#
# Exit codes: 0 all pass, 1 a failure
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
CHECK="$SCRIPT_DIR/check-tick-launches.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-tick-launches-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */check-tick-launches-test.*) rm -rf "$T" ;; esac'

RC=0
OUT=""
ERR=""
run() {
    RC=0
    "$BASH_BIN" "$CHECK" "$@" >"$T/out" 2>"$T/err" || RC=$?
    OUT=$(cat "$T/out")
    ERR=$(cat "$T/err")
}
expect_pass() {
    if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then pass "$1"; else fail "$1: exit $RC, out [$OUT] err [$ERR]"; fi
}
expect_fail() { # expect_fail <label> <text the output must hold>
    if [ "$RC" -eq 1 ]; then
        case "$OUT" in
            *"$2"*) pass "$1" ;;
            *) fail "$1: exit 1 but the output does not name [$2]: [$OUT]" ;;
        esac
    else
        fail "$1: want exit 1, got $RC, out [$OUT] err [$ERR]"
    fi
}

# --- the shipped tree --------------------------------------------------------

run
expect_pass "the shipped templates and the scripts they run launch nothing inside a tick"
case "$ERR" in
    *"OK ("*" template command(s) and the "*" script(s) they run"*) pass "the summary counts what was read: [$ERR]" ;;
    *) fail "no OK summary: [$ERR]" ;;
esac

# A copy of a shipped template with one offending gate added.
TPL="$REPO/skills/work-on/koto-templates/work-on.md"
if [ -f "$TPL" ]; then
    awk '
        !done && /^    gates:[[:space:]]*$/ {
            print
            print "      fixture_launch:"
            print "        type: command"
            print "        command: '"'"'niwa dispatch \"take the next step\" --name fixture --detach'"'"'"
            done = 1
            next
        }
        { print }
    ' "$TPL" >"$T/work-on-launch.md"
    LINE=$(grep -n 'fixture_launch:' "$T/work-on-launch.md" | head -1 | cut -d: -f1)
    LINE=$((LINE + 2))
    run --root "$REPO" "$T/work-on-launch.md"
    expect_fail "a shipped template with an added niwa dispatch gate fails" "work-on-launch.md:$LINE: the command, its line 1: launches niwa dispatch"
    run --root "$REPO" "$TPL"
    expect_pass "the unmodified template passes on its own"
else
    fail "no work-on.md at $TPL to copy"
fi

# --- a fixture plugin root ---------------------------------------------------

F="$T/plugin"
mkdir -p "$F/koto-templates" "$F/scripts/lib" "$F/skills/demo/koto-templates" "$F/skills/demo/scripts"

# template <path> <command yaml lines...> -- a template whose one state has a
# gate per given command line, written as YAML under `command:`.
template() {
    local path="$1"
    shift
    {
        printf -- '---\nname: fixture\nversion: "1.0"\ninitial_state: work\nstates:\n  work:\n'
        cat
        printf '    transitions:\n      - target: done\n  done:\n    terminal: true\n---\n\n## work\n\nWork.\n\n## done\n\nDone.\n'
    } >"$path"
}
script() { # script <path> -- the script's body from stdin
    cat >"$1"
    chmod +x "$1"
}
fresh() { rm -rf "$F/koto-templates"/* "$F/skills/demo/koto-templates"/* "$F/scripts"/*.sh "$F/scripts/lib"/* "$F/skills/demo/scripts"/* "$F/scripts/check-tick-launches.allow"; }

# A gate's niwa dispatch, in the command itself.
fresh
template "$F/koto-templates/a.md" <<'EOF'
    gates:
      go:
        type: command
        command: 'niwa dispatch "do it" --name x --detach'
EOF
run --root "$F"
expect_fail "a gate command that runs niwa dispatch fails" "koto-templates/a.md:10: the command, its line 1: launches niwa dispatch"

# A default action's claude -p, double-quoted YAML.
fresh
template "$F/skills/demo/koto-templates/b.md" <<'EOF'
    default_action:
      command: "claude -p \"summarize\" > out.txt"
EOF
run --root "$F"
expect_fail "a default action that runs claude -p fails" "skills/demo/koto-templates/b.md:8: the command, its line 1: launches claude"

# A block-scalar command.
fresh
template "$F/koto-templates/c.md" <<'EOF'
    default_action:
      command: >-
        cd "{{SESSION_DIR}}" &&
        claude --print "go"
      fallback: none
EOF
run --root "$F"
expect_fail "a block-scalar command that runs claude fails" "koto-templates/c.md:8: the command, its line 2: launches claude"

# A script the command runs, and a script that script runs.
fresh
template "$F/koto-templates/d.md" <<'EOF'
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/demo/scripts/outer.sh" --session "{{SESSION_NAME}}"'
EOF
script "$F/skills/demo/scripts/outer.sh" <<'EOF'
#!/usr/bin/env bash
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../scripts/lib/common.sh"
bash "$HERE/inner.sh" "$1"
EOF
script "$F/scripts/lib/common.sh" <<'EOF'
say() { printf '%s\n' "$*" >&2; }
EOF
script "$F/skills/demo/scripts/inner.sh" <<'EOF'
#!/usr/bin/env bash
NIWA="${NIWA:-niwa}"
say "starting niwa dispatch for the worker"
"$NIWA" dispatch "$PROMPT" --name "$1" --detach
EOF
run --root "$F"
expect_fail "a script two calls down that runs \"\$NIWA\" dispatch fails" "koto-templates/d.md:8 runs skills/demo/scripts/inner.sh:4: launches niwa dispatch"
case "$OUT" in
    *inner.sh:3*) fail "a message naming niwa dispatch was read as a launch: [$OUT]" ;;
    *) pass "a message naming niwa dispatch is not a launch" ;;
esac

# The same script, unsetting KOTO_SESSION_* first, passes.
script "$F/skills/demo/scripts/inner.sh" <<'EOF'
#!/usr/bin/env bash
NIWA="${NIWA:-niwa}"
unset KOTO_SESSION_BACKEND KOTO_SESSION_CLOUD_BUCKET KOTO_SESSION_CLOUD_ACCESS_KEY KOTO_SESSION_CLOUD_SECRET_KEY
"$NIWA" dispatch "$PROMPT" --name "$1" --detach
EOF
run --root "$F"
expect_pass "a launch after unset KOTO_SESSION_* passes"

# env -u on the launch line itself passes; a launch above the unset does not.
script "$F/skills/demo/scripts/inner.sh" <<'EOF'
#!/usr/bin/env bash
env -u KOTO_SESSION_BACKEND -u KOTO_SESSION_CLOUD_BUCKET "$CLAUDE_BIN" -p "go"
EOF
run --root "$F"
expect_pass "a launch through env -u KOTO_SESSION_* on its own line passes"
script "$F/skills/demo/scripts/inner.sh" <<'EOF'
#!/usr/bin/env bash
"$CLAUDE_BIN" -p "go"
unset KOTO_SESSION_BACKEND
EOF
run --root "$F"
expect_fail "a \"\$CLAUDE_BIN\" -p before the unset fails" "skills/demo/scripts/inner.sh:2: launches claude"

# Launches that hide behind a path, a shell's -c, or a harmless subcommand on
# the same line.
for body in \
    '/usr/local/bin/claude -p "go"' \
    '"$HOME/.local/bin/claude" --print "go"' \
    './bin/niwa dispatch "$PROMPT" --name x' \
    "bash -c 'claude -p \"go\"'" \
    'sh -c "niwa dispatch t --detach"' \
    'claude --version && claude -p "go"' \
    'niwa dispatch --help >/dev/null; niwa dispatch "$PROMPT" --name x'; do
    printf '#!/usr/bin/env bash\n%s\n' "$body" >"$F/skills/demo/scripts/inner.sh"
    run --root "$F"
    expect_fail "a launch written as [$body] fails" "skills/demo/scripts/inner.sh:2: launches"
done

# What is not a launch.
script "$F/skills/demo/scripts/inner.sh" <<'EOF'
#!/usr/bin/env bash
# claude -p "a comment is not a launch"; niwa dispatch "nor is this"
CLAUDE_CLI="${CLAUDE_CLI:-claude}"
AG=$("$CLAUDE_CLI" agents --json --all) || say "claude agents could not be read"
"$CLAUDE_CLI" rm "$JOB" || say "claude rm failed; niwa dispatch is not retried"
HELP=$(niwa dispatch --help 2>/dev/null)
[ -n "$CLAUDE_MD" ] && grep -q claude-session "$CLAUDE_MD"
printf '%s\n' "generated with claude code"
EOF
run --root "$F"
expect_pass "comments, messages, claude agents/rm, niwa dispatch --help and CLAUDE_MD are not launches"

# A script nothing runs is not read.
fresh
template "$F/koto-templates/e.md" <<'EOF'
    gates:
      go:
        type: command
        command: 'true'
EOF
script "$F/scripts/unused.sh" <<'EOF'
#!/usr/bin/env bash
claude -p "never run from a tick"
EOF
run --root "$F"
expect_pass "a script no command reaches is not read"

# A Python argument list.
fresh
template "$F/koto-templates/f.md" <<'EOF'
    default_action:
      command: 'python3 "{{PLUGIN_ROOT}}/scripts/spawn.py"'
EOF
script "$F/scripts/spawn.py" <<'EOF'
import subprocess
subprocess.run(["claude", "-p", "go"], check=True)
EOF
run --root "$F"
expect_fail "a Python script that runs [\"claude\", ...] fails" "runs scripts/spawn.py:2: launches claude or niwa dispatch"
script "$F/scripts/spawn.py" <<'EOF'
import os, subprocess
env = {k: v for k, v in os.environ.items() if not k.startswith("KOTO_SESSION_")}
subprocess.run(["claude", "-p", "go"], check=True, env=env)
EOF
run --root "$F"
expect_pass "the same Python launch with KOTO_SESSION_* dropped from its environment passes"

# --- the allow records -------------------------------------------------------

fresh
template "$F/koto-templates/g.md" <<'EOF'
    default_action:
      command: '"{{PLUGIN_ROOT}}/scripts/caller.sh" --imported x'
EOF
script "$F/scripts/caller.sh" <<'EOF'
#!/usr/bin/env bash
HERE=$(cd "$(dirname "$0")" && pwd)
bash "$HERE/worker.sh" --imported "$2"
EOF
script "$F/scripts/worker.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = --imported ] && exit 0
niwa dispatch "$PROMPT" --name "$2"
EOF
run --root "$F"
expect_fail "without a record, the call into a launching script fails" "runs scripts/worker.sh:3: launches niwa dispatch"
printf '# a comment\nscripts/caller.sh\tscripts/worker.sh\tcaller.sh runs it only with --imported, which exits first\n' \
    >"$F/scripts/check-tick-launches.allow"
run --root "$F"
expect_pass "a record exempts the one call it names"

template "$F/koto-templates/h.md" <<'EOF'
    gates:
      go:
        type: command
        command: '"{{PLUGIN_ROOT}}/scripts/worker.sh" --now'
EOF
run --root "$F"
expect_fail "the callee is still followed from a command the record doesn't name" "koto-templates/h.md:10 runs scripts/worker.sh:3: launches niwa dispatch"
rm -f "$F/koto-templates/h.md"

printf 'scripts/caller.sh\tscripts/gone.sh\tno longer called\n' >>"$F/scripts/check-tick-launches.allow"
run --root "$F"
expect_fail "a record naming a call nothing makes is stale and fails" "stale record: scripts/caller.sh -> scripts/gone.sh"

printf 'scripts/caller.sh\tscripts/worker.sh\n' >"$F/scripts/check-tick-launches.allow"
run --root "$F"
if [ "$RC" -eq 2 ]; then pass "a record with no reason is refused (exit 2)"; else fail "a record with no reason: exit $RC, err [$ERR]"; fi

# --- usage ------------------------------------------------------------------

run --frobnicate
if [ "$RC" -eq 2 ]; then pass "an unknown option exits 2"; else fail "an unknown option: exit $RC"; fi
run "$T/no-such-template.md"
if [ "$RC" -eq 2 ]; then pass "a missing template exits 2"; else fail "a missing template: exit $RC"; fi

echo
echo "check-tick-launches_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
