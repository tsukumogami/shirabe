#!/usr/bin/env bash
set -u

# End-to-end tests for the plugin's pre-action hook (hooks/hooks.json and
# hooks/pre-action-deny.sh), PRD-pre-action-denies R1, R7, R8, R16 and R17.
#
# Every case feeds PreToolUse JSON to the command hooks/hooks.json declares,
# read from that file with sed and run through /bin/sh -c the way Claude Code
# runs it, with a clean environment: CLAUDE_PLUGIN_ROOT, a scratch HOME and
# TMPDIR, and a PATH built here. That PATH holds links to the few tools the
# script and the binary use and nothing else, so no case can find jq or a
# shirabe installed on the host. Variants put the repository's binary first,
# no binary at all, or a stub that exits 2, checks fewer rules, panics,
# sleeps 40 seconds, or prints something other than a deny.
#
# The pushes run in scratch repositories: a bare origin and a clone whose
# unpushed commit carries `Co-Authored-By: Claude <noreply@anthropic.com>`,
# and a clone whose unpushed commit is clean.
#
# Needs bash, git, sed, grep, tr, awk and a built shirabe: SHIRABE_BIN, or
# target/release/shirabe (cargo build --release). jq, when present, checks
# that each deny is valid JSON; the hook itself never gets it. No network.
# The sleeping-binary case takes about 26 seconds.
#
# Usage:
#   bash hooks/pre-action-deny_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed, or no binary to test

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_JSON="$SCRIPT_DIR/hooks.json"
TSV="$SCRIPT_DIR/testdata/coarse-cases.tsv"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 - $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

SHIRABE="${SHIRABE_BIN:-$REPO_ROOT/target/release/shirabe}"
if [ ! -x "$SHIRABE" ]; then
    echo "pre-action-deny_test: no shirabe binary at $SHIRABE; run cargo build --release or set SHIRABE_BIN" >&2
    exit 1
fi
SHIRABE="$(cd "$(dirname "$SHIRABE")" && pwd)/$(basename "$SHIRABE")"

T=$(mktemp -d "${TMPDIR:-/tmp}/pre-action-deny-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */pre-action-deny-test.*) rm -rf "$T" ;; esac; return 0; }
trap cleanup EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

DENY_PREFIX='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",'
RULE_IDS=$(sed -n 's/^RULE_IDS="\(.*\)"$/\1/p' "$SCRIPT_DIR/pre-action-deny.sh")

# -- the declaration -----------------------------------------------------------

# No jq here, so these read hooks.json line by line: they expect its layout of
# one `"key": value` pair per line, which the file keeps.

HOOK_CMD=$(sed -n 's/^ *"command": "\(.*\)",\{0,1\}$/\1/p' "$HOOKS_JSON" | sed 's/\\"/"/g')

[ "$HOOK_CMD" = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/pre-action-deny.sh"' ] \
    && pass "hooks.json runs bash on the quoted script path" \
    || fail "hooks.json command" "[$HOOK_CMD]"

n_pre=$(grep -c '"PreToolUse"' "$HOOKS_JSON")
n_matcher=$(grep -c '"matcher": "Bash"' "$HOOKS_JSON")
n_cmd=$(grep -c '"type": "command"' "$HOOKS_JSON")
n_timeout=$(grep -c '"timeout": 30$' "$HOOKS_JSON")
n_fail=$(grep -c 'onFailure' "$HOOKS_JSON")
[ "$n_pre" = 1 ] && [ "$n_matcher" = 1 ] && [ "$n_cmd" = 1 ] && [ "$n_timeout" = 1 ] && [ "$n_fail" = 0 ] \
    && pass "hooks.json declares one PreToolUse Bash command hook, timeout 30, no onFailure" \
    || fail "hooks.json shape" "PreToolUse=$n_pre matcher=$n_matcher command=$n_cmd timeout=$n_timeout onFailure=$n_fail"

mode=$(git -C "$REPO_ROOT" ls-files -s hooks/pre-action-deny.sh | cut -d' ' -f1)
[ "$mode" = 100755 ] && pass "pre-action-deny.sh has mode 100755 in git" \
    || fail "script mode" "git ls-files -s gives [$mode]"

[ "$RULE_IDS" = "pr-body/conventional-title pr-body/one-separator pr-body/no-ai-trailer pr-body/no-heading-in-part1 pr-body/conformance commit/no-ai-trailer" ] \
    && pass "RULE_IDS lists the six rules" \
    || fail "RULE_IDS" "[$RULE_IDS]"

# -- the environment -----------------------------------------------------------

# The hook's PATH: links to what the script and the binary run, nothing else.
TOOLS="$T/tools"
mkdir -p "$TOOLS"
for tool in bash sh cat sed tr awk sleep git; do
    p=$(command -v "$tool") || { echo "pre-action-deny_test: $tool is required" >&2; exit 1; }
    ln -s "$p" "$TOOLS/$tool"
done
if PATH="$TOOLS" command -v jq >/dev/null 2>&1 || PATH="$TOOLS" command -v shirabe >/dev/null 2>&1; then
    fail "the hook's PATH" "jq or shirabe resolves on it"
else
    pass "the hook's PATH holds neither jq nor shirabe"
fi

REPO_BIN="$T/bin-repo"
mkdir -p "$REPO_BIN"
ln -s "$SHIRABE" "$REPO_BIN/shirabe"
P_REPO="$REPO_BIN:$TOOLS"
P_NONE="$TOOLS"

EMPTY_HOME="$T/home"
SCRATCH_TMP="$T/tmp"
mkdir -p "$EMPTY_HOME" "$SCRATCH_TMP"

WORK="$T/work"
mkdir -p "$WORK"
mkfifo "$WORK/fifo"

# Repositories: origin.git, its clone `trailer` with the trailer commit on
# main and on `topic`, and the clone `clean` with a clean unpushed commit.
R="$T/repos"
mkdir -p "$R"
git -c init.defaultBranch=main init -q --bare "$R/origin.git"
git clone -q "$R/origin.git" "$R/seed" 2>/dev/null
mkdir -p "$R/seed/sub"
echo x > "$R/seed/sub/f"
git -C "$R/seed" add sub/f
git -C "$R/seed" commit -q -m "chore: start"
git -C "$R/seed" push -q origin HEAD:main 2>/dev/null
git clone -q "$R/origin.git" "$R/trailer" 2>/dev/null
echo y > "$R/trailer/y"
git -C "$R/trailer" add y
git -C "$R/trailer" commit -q -m "feat: add y

Co-Authored-By: Claude <noreply@anthropic.com>"
git -C "$R/trailer" branch topic
TRAILER_HASH=$(git -C "$R/trailer" rev-parse --short=12 HEAD)
git clone -q "$R/origin.git" "$R/clean" 2>/dev/null
echo z > "$R/clean/z"
git -C "$R/clean" add z
git -C "$R/clean" commit -q -m "feat: add z"
TR="$R/trailer"

# run_hook <command as a JSON string value> [NAME=value...]: feeds a
# PreToolUse document holding it to the declared command, with HOOK_PATH,
# HOOK_HOME, HOOK_ROOT and HOOK_CWD, plus the extra environment given. Sets
# OUT and RC.
run_hook_raw() {
    local input="$1"
    shift
    OUT=$(cd "$HOOK_CWD" && printf '%s' "$input" |
        env -i "HOME=$HOOK_HOME" "TMPDIR=$SCRATCH_TMP" "PATH=$HOOK_PATH" "CLAUDE_PLUGIN_ROOT=$HOOK_ROOT" "$@" \
            /bin/sh -c "$HOOK_CMD")
    RC=$?
}
run_hook() {
    local cmd="$1"
    shift
    run_hook_raw "{\"session_id\":\"t\",\"transcript_path\":\"/dev/null\",\"cwd\":\"$HOOK_CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" "$@"
}
defaults() {
    HOOK_PATH="$P_REPO"
    HOOK_HOME="$EMPTY_HOME"
    HOOK_ROOT="$REPO_ROOT"
    HOOK_CWD="$TR"
}

# expect_none <name>: no decision, exit 0.
expect_none() {
    if [ "$RC" = 0 ] && [ -z "$OUT" ]; then
        pass "$1"
    else
        fail "$1" "expected no decision, got rc=$RC out=[$OUT]"
    fi
}

# expect_deny <name> <word>...: one deny line holding every word, exit 0.
# Each `!word` must be absent instead.
expect_deny() {
    local name="$1" w
    shift
    case "$OUT" in
        "$DENY_PREFIX"*) ;;
        *) fail "$name" "expected a deny, got rc=$RC out=[$OUT]"; return ;;
    esac
    if [ "$RC" != 0 ]; then
        fail "$name" "rc=$RC"
        return
    fi
    case "$OUT" in
        *"
"*) fail "$name" "more than one line: [$OUT]"; return ;;
    esac
    if command -v jq >/dev/null 2>&1 &&
        ! printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        fail "$name" "not valid JSON: [$OUT]"
        return
    fi
    for w in "$@"; do
        case "$w" in
            !*)
                case "$OUT" in
                    *"${w#!}"*) fail "$name" "holds ${w#!}: [$OUT]"; return ;;
                esac
                ;;
            *)
                case "$OUT" in
                    *"$w"*) ;;
                    *) fail "$name" "lacks $w: [$OUT]"; return ;;
                esac
                ;;
        esac
    done
    pass "$name"
}

# The fixed deny the script prints when the binary can't answer.
expect_binary_deny() {
    expect_deny "$1" "binary" "install.sh | sh" "ask the user" "commit/no-ai-trailer" \
        "pr-body/conventional-title" '!SHIRABE_PRE_ACTION_HOOK'
}

# Command strings, as JSON string values.
GOOD='\"Adds x.\n\n---\n\nContext.\"'
BAD='\"Adds x.\"'
PB4_ONLY='\"## Heading\n\nAdds x.\n\n---\n\nContext.\"'
BAD_CREATE="gh pr create --title \\\"feat: x\\\" --body $BAD"
TRAILER_PUSH='git push'

# -- the example table, with the repository's binary ---------------------------

defaults
for c in 'ls' 'git status' 'git commit -m x' 'gh pr view 3' 'echo \"gh pr create\"' \
    'gh issue create --title pr --body edit' 'git log --grep push'; do
    run_hook "$c"
    expect_none "table: $c gives no decision"
done

for c in 'sudo git push' 'env X=1 git push' 'bash -c \"git push\"' 'eval \"git push\"' '$GIT push' \
    'echo $(git push)' 'echo `gh pr create`'; do
    run_hook "$c"
    expect_deny "table: $c is wrapped" "wrapped" "ask the user" '!SHIRABE_PRE_ACTION_HOOK'
done

# gh pr merge's --body is the squash commit's message, not a pull request
# body: no decision, plain, after NAME= or behind env, whatever it says.
for c in 'gh pr merge 123 -R o/r --squash --subject \"fix: x\" --body \"Adds a new edit path.\"' \
    'GH_TOKEN= gh pr merge 123 --squash --body \"Adds a new edit path.\"' \
    'env -u GH_TOKEN gh pr merge 123 -R o/r --squash --subject \"fix: x\" --body \"Adds a new edit path.\"' \
    'env GH_TOKEN= gh pr merge 123 --squash --body \"Creates a new thing.\"' \
    'env -u GH_TOKEN gh pr merge 1 --squash --body \"Adds a new path\"'; do
    run_hook "$c"
    expect_none "merge: $c gives no decision"
done
# Naming gh pr create inside a quoted argument is no create.
for c in 'gh issue create --title \"hook refuses gh pr create\" --body \"x\"' \
    'env -u GH_TOKEN gh issue create --title \"hook refuses gh pr create\" --body \"x\"'; do
    run_hook "$c"
    expect_none "quoted mention: $c gives no decision"
done
# A create or edit behind env is still wrapped, whatever its body, after an
# operand env takes as an assignment or behind a launcher env runs.
for c in "env -u GH_TOKEN $BAD_CREATE" \
    "env -u GH_TOKEN gh pr create --title \\\"feat: x\\\" --body $GOOD" \
    "env GH_TOKEN= gh pr edit 12 --body $BAD" \
    "env a-b=1 gh pr create --title \\\"feat: x\\\" --body $GOOD" \
    "env stdbuf -oL gh pr create --title \\\"feat: x\\\" --body $GOOD" \
    'env caffeinate git push' \
    "env git -c 'alias.p=!git push' p" \
    "env 'BASH_FUNC_f%%=() { gh pr create --title x --body y; }' bash -c f" \
    "env 'BASH_FUNC_f%%=() { gh \\\"\$@\\\"; }' bash -c 'f pr create'" \
    "env 'BASH_FUNC_f%%=() { git \\\"\$@\\\"; }' bash -c 'f push'"; do
    run_hook "$c"
    expect_deny "env-wrapped: $c is wrapped" "wrapped" "ask the user" '!SHIRABE_PRE_ACTION_HOOK'
done

# A head in another case is the same program on a case-insensitive
# filesystem, so a wrapper is still a wrapper and gh is still gh.
for c in 'ENV gh pr create -t \"feat: x\" -b \"Adds x.\"' \
    'ENV -u GH_TOKEN gh pr create -t \"feat: x\" -b \"Adds x.\"' \
    'Sudo git push' 'BASH -c \"git push\"' '/USR/BIN/ENV git push'; do
    run_hook "$c"
    expect_deny "case: $c is wrapped" "wrapped" "ask the user" '!SHIRABE_PRE_ACTION_HOOK'
done
run_hook "GH pr create --title \\\"feat: x\\\" --body $BAD"
expect_deny "case: GH pr create with a bad body" "pr-body/one-separator"
run_hook 'ENV -u GH_TOKEN gh pr merge 1 --squash --body \"Adds a new path\"'
expect_none "case: ENV -u GH_TOKEN gh pr merge gives no decision"

for c in '/usr/bin/git push' 'git status && git push' 'if true; then git push; fi' \
    'git push --force origin +topic' 'git -c k=v push' 'cd sub && git push' 'git -C sub push' \
    'GIT push' 'Git -C sub push'; do
    run_hook "$c"
    expect_deny "table: $c with the trailer commit" "commit/no-ai-trailer" "$TRAILER_HASH"
done

for c in 'git commit -m x && git push' 'git checkout other && git push' \
    'echo $(git commit -qm x -m \"Co-Authored-By: Claude <noreply@anthropic.com>\") && git push' \
    'gh pr checkout 3 && git push'; do
    run_hook "$c"
    expect_deny "table: $c is the same command" "same command" "ask the user"
done

HOOK_CWD="$WORK"
run_hook "printf 'x' > b.md && gh pr create --title \\\"feat: x\\\" -F b.md"
expect_deny "table: a body file written earlier in the command" "same command"
run_hook "echo \$(printf 'Adds x.' > b.md) && gh pr create -t \\\"feat: x\\\" -F b.md"
expect_deny "a body file written in an earlier command substitution" "same command"
run_hook 'gh pr create --title \"feat: x\" -F fifo'
expect_deny "table: a FIFO body file" "regular file"
run_hook 'gh pr create --title \"feat: x\"'
expect_deny "table: a create with no body" "no body"
run_hook "gh pr create --body $GOOD"
expect_deny "table: a create with no title" "title" "ask the user"
run_hook "gh pr create --title \\\"feat: x\\\" --body $GOOD"
expect_none "table: a good create gives no decision"
run_hook "$BAD_CREATE"
expect_deny "table: a bad-body create" "pr-body/one-separator" "full text: $REPO_ROOT/references/pr-body-conformance.md lines"
run_hook "GH_TOKEN=t gh -R o/r pr create --title \\\"feat: x\\\" --body $BAD"
expect_deny "table: GH_TOKEN=t gh -R o/r pr create with a bad body" "pr-body/one-separator"
run_hook "git add . && gh pr create --title \\\"Add x\\\" --body $BAD"
expect_deny "table: a bad title and a bad body" "pr-body/conventional-title" "pr-body/one-separator"
first=${OUT%%pr-body/one-separator*}
case "$first" in
    *pr-body/conventional-title*) pass "table: the title block comes before the separator block" ;;
    *) fail "block order" "[$OUT]" ;;
esac
run_hook "gh pr create --title \\\"feat: x\\\" --body \\\"\$(cat <<'EOF'\nAdds x.\nEOF\n)\\\""
expect_deny "table: a here-document body with bad lines" "pr-body/one-separator"
run_hook 'gh pr create --title \"feat: x\" --body \"$BODY\"'
expect_deny "table: a variable body" "body" "--body-file" "ask the user"
run_hook 'gh pr create --fill'
expect_deny "table: a --fill create" "--fill"
run_hook "gh pr new --title \\\"feat: x\\\" --body $BAD"
expect_deny "table: gh pr new, gh's alias for create, with a bad body" "pr-body/one-separator"
# A short flag's value attached, as gh reads it.
run_hook "gh pr edit 12 -b'Adds x.'"
expect_deny "attached: an edit with -b'<bad>'" "pr-body/one-separator" '!pr-body/conventional-title'
run_hook "gh pr edit 12 -t'Add x'"
expect_deny "attached: an edit with -t'bad title'" "pr-body/conventional-title" '!pr-body/one-separator'
run_hook 'gh pr edit 12 --title \"bad title\"'
expect_deny "table: an edit with a bad title" "pr-body/conventional-title" '!pr-body/one-separator'
run_hook "gh pr edit 12 --body $BAD"
expect_deny "table: an edit with a bad body" "pr-body/one-separator" '!pr-body/conventional-title'
run_hook 'gh pr edit 12 --add-label x'
expect_none "table: an edit adding a label gives no decision"

defaults
run_hook "$TRAILER_PUSH"
expect_deny "table: git push with the trailer commit names it" "commit/no-ai-trailer" "$TRAILER_HASH" "subject: feat: add y"
HOOK_CWD="$R/clean"
run_hook 'git push'
expect_none "table: git push with only clean commits gives no decision"
HOOK_CWD="$TR"
for c in 'git push origin --delete topic' 'git push origin :topic'; do
    run_hook "$c"
    expect_none "table: $c gives no decision"
done
# A redirection is no refspec, with or without a space before it; `:` pushes
# the matching branches.
for c in 'git push origin topic 2>&1' 'git push origin topic > log' 'git push>/dev/null' \
    'cd sub 2>/dev/null && git push' 'git push origin :'; do
    run_hook "$c"
    expect_deny "redirected: $c with the trailer commit" "commit/no-ai-trailer" "$TRAILER_HASH"
done
HOOK_CWD="$R/clean"
for c in 'git push origin HEAD >/dev/null' 'git push -u origin main 2>&1' 'git push>/dev/null'; do
    run_hook "$c"
    expect_none "redirected: $c with only clean commits gives no decision"
done
HOOK_CWD="$TR"
run_hook 'cd \"$DIR\" && git push'
expect_deny "table: cd to a variable directory" "directory"
run_hook 'git push --some-new-option'
expect_deny "table: an unknown push option" "--some-new-option"

# -- the binary present, the input or the registry broken ----------------------

defaults
run_hook_raw 'not json, but git push'
expect_deny "malformed input naming git push is denied" "hook input" "ask the user"
run_hook_raw 'not json at all'
expect_none "malformed input naming nothing gives no decision"

NOREG="$T/noreg"
mkdir -p "$NOREG"
cp -R "$REPO_ROOT/hooks" "$NOREG/hooks"
HOOK_ROOT="$NOREG"
for c in 'ls' 'git status' 'gh pr view 3' 'echo \"gh pr create\"'; do
    run_hook "$c"
    expect_none "no registry: $c gives no decision"
done
run_hook "$BAD_CREATE"
expect_deny "no registry: a create is denied naming the rule" "registry" "ask the user"

# -- the binary missing or unable to run ---------------------------------------

defaults
HOOK_PATH="$P_NONE"
for c in 'ls' 'git status' 'git commit -m x' 'gh pr view 3'; do
    run_hook "$c"
    expect_none "no binary: $c gives no decision"
done
run_hook 'gh pr create --title t --body b'
expect_binary_deny "no binary: gh pr create is denied naming the binary"
run_hook 'echo \"git push\"'
expect_binary_deny "no binary: echo \"git push\" is denied naming the binary"
for id in $RULE_IDS; do
    case "$OUT" in
        *"$id"*) ;;
        *) fail "no binary: the deny lists $id" "[$OUT]" ;;
    esac
done
expected_reason='shirabe could not check this command (binary: the shirabe binary is missing, older than this plugin, or failed to run), so it is denied.\nIt names `gh pr create`, `gh pr edit` or `git push`, which are guarded by: '"${RULE_IDS// /, }"'.\nFix: ask the user to install or update the shirabe binary with `curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/main/install.sh | sh`, then run the command again.\nIf you believe this deny is wrong, ask the user.'
[ "$OUT" = "$DENY_PREFIX\"permissionDecisionReason\":\"$expected_reason\"}}" ] \
    && pass "no binary: the deny is the fixed text" \
    || fail "no binary: the fixed deny" "[$OUT]"

# The coarse test, row by row: a named command is denied, a clear one isn't.
# HOOK_PATH is still the no-binary one.
TAB=$(printf '\t')
rows=0
while IFS= read -r line; do
    case "$line" in
        ""|"#"*) continue ;;
    esac
    want=${line%%"$TAB"*}
    cmd=${line#*"$TAB"}
    rows=$((rows + 1))
    run_hook_raw "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}"
    case "$want:$OUT" in
        "named:$DENY_PREFIX"*|"clear:") ;;
        *) fail "coarse-cases.tsv: $cmd" "want $want, got [$OUT]" ;;
    esac
done < "$TSV"
[ "$rows" -gt 0 ] && pass "no binary: the script answers the $rows rows of coarse-cases.tsv" \
    || fail "coarse-cases.tsv" "no rows"

# ~/.shirabe/bin/shirabe, where install.sh puts it, when PATH (still the
# no-binary one) has none.
INSTALLED_HOME="$T/installed-home"
mkdir -p "$INSTALLED_HOME/.shirabe/bin"
ln -s "$SHIRABE" "$INSTALLED_HOME/.shirabe/bin/shirabe"
HOOK_HOME="$INSTALLED_HOME"
run_hook "$BAD_CREATE"
expect_deny "the binary at ~/.shirabe/bin answers when PATH has none" "pr-body/one-separator" '!binary'

# Stubs on PATH, each one way a binary can fail to answer.
STUBS="$T/stubs"
make_stub() {
    mkdir -p "$STUBS/$1"
    {
        echo '#!/bin/sh'
        cat
    } > "$STUBS/$1/shirabe"
    chmod +x "$STUBS/$1/shirabe"
}
make_stub exit2 <<'EOF'
echo "error: unrecognized subcommand 'pre-action-hook'" >&2
exit 2
EOF
make_stub fewer <<'EOF'
# Knows the subcommand but checks the PR-body rules only, as a binary older
# than the plugin would; the real binary's own exit 3 on an unknown rule is
# tested in crates/shirabe/tests/pre_action_hook.rs.
[ "$1" = pre-action-hook ] || exit 2
cat >/dev/null
rules=""
while [ $# -gt 0 ]; do
    case "$1" in
        --rules) rules=$2; shift ;;
    esac
    shift
done
for id in $rules; do
    case "$id" in
        pr-body/conventional-title|pr-body/one-separator|pr-body/no-ai-trailer|pr-body/no-heading-in-part1|pr-body/conformance) ;;
        *) echo "this binary doesn't check $id" >&2; exit 3 ;;
    esac
done
exit 0
EOF
make_stub panic <<'EOF'
cat >/dev/null
echo "thread 'main' panicked at crates/shirabe/src/main.rs:1:1:" >&2
exit 101
EOF
make_stub sleep <<'EOF'
cat >/dev/null
sleep 40
EOF
make_stub allow <<'EOF'
cat >/dev/null
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
EOF
make_stub ask <<'EOF'
cat >/dev/null
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"}}'
EOF
make_stub twolines <<'EOF'
cat >/dev/null
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"x"}}'
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"y"}}'
EOF
make_stub record <<EOF
printf '%s\n' "\$@" > "$T/record.args"
cat > "$T/record.stdin"
EOF

defaults
for s in exit2 fewer panic allow ask twolines; do
    HOOK_PATH="$STUBS/$s:$TOOLS"
    run_hook "$BAD_CREATE"
    expect_binary_deny "stub $s: a guarded create is denied naming the binary"
    run_hook "$TRAILER_PUSH"
    expect_binary_deny "stub $s: a guarded push is denied naming the binary"
    run_hook 'ls'
    expect_none "stub $s: ls gives no decision"
done

HOOK_PATH="$STUBS/exit2:$TOOLS"
run_hook 'cd repo\ngit push'
expect_binary_deny "stub exit2: a git push on the command's second line is denied"
run_hook 'git status'
expect_none "stub exit2: git status gives no decision"

HOOK_PATH="$STUBS/sleep:$TOOLS"
start=$SECONDS
run_hook "$TRAILER_PUSH"
elapsed=$((SECONDS - start))
expect_binary_deny "stub sleep: a binary sleeping 40 seconds gives the binary deny"
[ "$elapsed" -le 28 ] && pass "stub sleep: the deny came within 28 seconds (${elapsed}s)" \
    || fail "stub sleep: the watchdog" "took ${elapsed}s"

HOOK_PATH="$STUBS/record:$TOOLS"
input='{"tool_name":"Bash","tool_input":{"command":"git push"},"cwd":"/x y"}'
run_hook_raw "$input"
expect_none "stub record: an empty answer with exit 0 is passed through"
args=$(cat "$T/record.args" 2>/dev/null)
want_args="pre-action-hook
--plugin-root
$REPO_ROOT
--rules
$RULE_IDS"
[ "$args" = "$want_args" ] && pass "the binary gets --plugin-root and the RULE_IDS line" \
    || fail "the binary's arguments" "[$args]"
[ "$(cat "$T/record.stdin" 2>/dev/null)" = "$input" ] && pass "the binary gets the input unchanged" \
    || fail "the binary's input" "[$(cat "$T/record.stdin" 2>/dev/null)]"

# A shirabe on a relative PATH entry is never run.
mkdir -p "$WORK/rel"
cp "$STUBS/allow/shirabe" "$WORK/rel/shirabe"
HOOK_CWD="$WORK"
HOOK_PATH="rel:$TOOLS"
run_hook "$BAD_CREATE"
expect_binary_deny "a shirabe on a relative PATH entry is skipped"

# -- the off switches ----------------------------------------------------------

# SHIRABE_PRE_ACTION_HOOK=off, exactly, is the host's switch for the whole
# hook. PR_BODY_HOOK_DISABLE, the legacy entry point's switch, turns off only
# the PR-body rules, on both entry points (PRD R9).
defaults
run_hook "$BAD_CREATE" "SHIRABE_PRE_ACTION_HOOK=off"
expect_none "SHIRABE_PRE_ACTION_HOOK=off: the bad-body create gives no decision"
run_hook "$TRAILER_PUSH" "SHIRABE_PRE_ACTION_HOOK=off"
expect_none "SHIRABE_PRE_ACTION_HOOK=off: the trailer push gives no decision"
HOOK_PATH="$P_NONE"
run_hook "$BAD_CREATE" "SHIRABE_PRE_ACTION_HOOK=off"
expect_none "SHIRABE_PRE_ACTION_HOOK=off: the missing-binary create gives no decision"
HOOK_PATH="$P_REPO"
for v in on OFF 'off ' 0; do
    run_hook "$BAD_CREATE" "SHIRABE_PRE_ACTION_HOOK=$v"
    expect_deny "SHIRABE_PRE_ACTION_HOOK=[$v]: the bad-body create is denied" "pr-body/one-separator"
    run_hook "$TRAILER_PUSH" "SHIRABE_PRE_ACTION_HOOK=$v"
    expect_deny "SHIRABE_PRE_ACTION_HOOK=[$v]: the trailer push is denied" "commit/no-ai-trailer"
    HOOK_PATH="$P_NONE"
    run_hook "$BAD_CREATE" "SHIRABE_PRE_ACTION_HOOK=$v"
    expect_binary_deny "SHIRABE_PRE_ACTION_HOOK=[$v]: the missing-binary create is denied"
    HOOK_PATH="$P_REPO"
done

run_hook "$BAD_CREATE" "PR_BODY_HOOK_DISABLE=1"
expect_none "PR_BODY_HOOK_DISABLE=1: the bad-body create gives no decision"
run_hook "$TRAILER_PUSH" "PR_BODY_HOOK_DISABLE=1"
expect_deny "PR_BODY_HOOK_DISABLE=1: the trailer push is still denied" "commit/no-ai-trailer"
for v in '' 0 false; do
    run_hook "$BAD_CREATE" "PR_BODY_HOOK_DISABLE=$v"
    expect_deny "PR_BODY_HOOK_DISABLE=[$v]: the bad-body create is denied" "pr-body/one-separator"
done
# With no binary the script's coarse test honours it too: only a command
# naming `git` ... `push` is denied.
HOOK_PATH="$P_NONE"
for v in 1 yes; do
    run_hook "$BAD_CREATE" "PR_BODY_HOOK_DISABLE=$v"
    expect_none "PR_BODY_HOOK_DISABLE=$v, no binary: the create gives no decision"
    run_hook 'gh pr edit 3 --title x' "PR_BODY_HOOK_DISABLE=$v"
    expect_none "PR_BODY_HOOK_DISABLE=$v, no binary: the edit gives no decision"
    run_hook "$TRAILER_PUSH" "PR_BODY_HOOK_DISABLE=$v"
    expect_binary_deny "PR_BODY_HOOK_DISABLE=$v, no binary: git push is still denied"
    run_hook 'gh pr create --title t --body b && git push' "PR_BODY_HOOK_DISABLE=$v"
    expect_binary_deny "PR_BODY_HOOK_DISABLE=$v, no binary: a create and a push is denied"
done
for v in '' 0 false; do
    run_hook "$BAD_CREATE" "PR_BODY_HOOK_DISABLE=$v"
    expect_binary_deny "PR_BODY_HOOK_DISABLE=[$v], no binary: the create is denied"
done
HOOK_PATH="$P_REPO"

# -- the canary's PB4 exception ------------------------------------------------

defaults
CANARY_HOME="$T/canary-home"
mkdir -p "$CANARY_HOME/.config/shirabe"
printf 'on\n' > "$CANARY_HOME/.config/shirabe/offload-canary"
HOOK_HOME="$CANARY_HOME"
run_hook "gh pr create --title \\\"feat: x\\\" --body $PB4_ONLY"
expect_none "canary on: a create breaking only PB4 gives no decision"
run_hook "gh pr edit 12 --body $PB4_ONLY"
expect_none "canary on: an edit breaking only PB4 gives no decision"
run_hook "$BAD_CREATE"
expect_deny "canary on: a create breaking PB2 is denied" "pr-body/one-separator"
printf 'on\r\n' > "$CANARY_HOME/.config/shirabe/offload-canary"
run_hook "gh pr create --title \\\"feat: x\\\" --body $PB4_ONLY"
expect_deny "canary on\\r: PB4 is denied" "pr-body/no-heading-in-part1"
HOOK_HOME="$EMPTY_HOME"
run_hook "gh pr create --title \\\"feat: x\\\" --body $PB4_ONLY"
expect_deny "no canary: PB4 is denied" "pr-body/no-heading-in-part1"

# -- wired twice: niwa's pr-body-hook line in the user's settings --------------

# When the host's settings run `shirabe pr-body-hook` too, the plugin hook
# leaves the PR-body rules to it and keeps the push (PRD R12), so each broken
# rule is reported once between the two.

NIWA_LINE='command -v shirabe >/dev/null 2>&1 || exit 0; shirabe pr-body-hook 2>/dev/null || exit 0'
WIRED_HOME="$T/wired-home"
mkdir -p "$WIRED_HOME/.claude"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s"}]}]}}\n' \
    "$NIWA_LINE" > "$WIRED_HOME/.claude/settings.json"
defaults
HOOK_HOME="$WIRED_HOME"
run_hook "$BAD_CREATE"
expect_none "wired: the plugin hook leaves the bad-body create to pr-body-hook"
run_hook 'gh pr create --fill'
expect_none "wired: the plugin hook leaves the --fill create to pr-body-hook"
run_hook "$TRAILER_PUSH"
expect_deny "wired: the plugin hook still denies the trailer push" "commit/no-ai-trailer"
legacy_input="{\"cwd\":\"$TR\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$BAD_CREATE\"}}"
OUT=$(cd "$TR" && printf '%s' "$legacy_input" |
    env -i "HOME=$WIRED_HOME" "TMPDIR=$SCRATCH_TMP" "PATH=$P_REPO" /bin/sh -c "$NIWA_LINE")
RC=$?
expect_deny "wired: niwa's line denies the bad-body create, so the rule is reported once" "pr-body/one-separator"

# -- a plugin copy whose path holds a space ------------------------------------

SPACED="$T/plugin copy"
mkdir -p "$SPACED"
cp -R "$REPO_ROOT/hooks" "$SPACED/hooks"
cp -R "$REPO_ROOT/references" "$SPACED/references"
defaults
HOOK_ROOT="$SPACED"
run_hook "$BAD_CREATE"
expect_deny "spaced root: the bad-body create is denied from the copy" "pr-body/one-separator" \
    "full text: $SPACED/references/pr-body-conformance.md lines"
run_hook "$TRAILER_PUSH"
expect_deny "spaced root: the trailer push is denied" "commit/no-ai-trailer"
run_hook 'ls'
expect_none "spaced root: ls gives no decision"
HOOK_PATH="$P_NONE"
run_hook "$BAD_CREATE"
expect_binary_deny "spaced root, no binary: the script still starts and denies"

# -- nothing written -----------------------------------------------------------

leftover="$(ls -A "$SCRATCH_TMP")$(ls -A "$EMPTY_HOME")"
[ -z "$leftover" ] && pass "every run left TMPDIR and HOME empty" \
    || fail "files written" "[$leftover]"

echo ""
echo "pre-action-deny_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
