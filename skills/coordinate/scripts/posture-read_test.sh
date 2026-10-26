#!/usr/bin/env bash
# posture-read_test.sh -- posture-read.sh reads the workspace's and the
# instance's settings and hooks, never runs a hook, and reports permit, deny,
# confirm or unread for merge, close, teardown and release; for a session
# niwa reports bound, the grant decides merge, close and release.
#
# Covers: the default mode (confirm) and bypassPermissions (permit); deny, ask
# and allow rules in both the `:*` and ` *` forms; rules on gh pr merge,
# merge-exec.sh and land-merge.sh each governing the one merge step; deny
# winning over allow across files; a hook naming a step's command reserving it
# (confirm), including a shell-escaped spelling, while a deny stays deny; a
# hook whose matcher doesn't cover Bash ignored; a sentinel hook script that
# would write a file if run left unrun; an unreadable hook script and an
# unparseable settings file giving unread; every hook shape the reader can't
# locate and read (an interpreter's bare script name, a PATH command, a path
# outside the roots, a missing file, a command substitution, `-m`) giving
# unread, while an interpreter's script under a root, a relative path and
# inline code are read; niwa's PATH-first worktree hooks (`command -v` a
# lookup, `2>&1` not a command) leaving the posture as if no hook were there,
# while any other niwa path, subcommand or argument stays unread; no roots
# found giving unread
# everywhere; the roots found by walking up from the working directory with a
# cloned repository's own settings ignored; $CLAUDE_PROJECT_DIR in a hook
# command; the release step read from rules and hooks naming gh release
# create; the grant from a stub niwa: each row of the gate's table, a rule
# that still wins over it, the lookup's exact arguments, $NIWA_BIN when niwa
# isn't on PATH, and every failed lookup (no niwa, a non-zero exit, empty or
# malformed output, values outside niwa's vocabularies, a hang) and
# not-dispatched reading as with no grant, while record-unusable denies the
# merge; the sealed token and its detail, with source=grant on the steps the
# grant decided.
#
# Usage: bash skills/coordinate/scripts/posture-read_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
PRD="$HERE/posture-read.sh"
# Every read below runs with no session id and no NIWA_BIN unless a case sets
# them, so no niwa on this host is ever asked; the grant cases use a stub.
unset CLAUDE_CODE_SESSION_ID NIWA_BIN

WS="$T/ws"
IN="$WS/inst"
fresh() {
    rm -rf "$WS"
    mkdir -p "$WS/.niwa" "$WS/.claude" "$IN/.niwa" "$IN/.claude" "$IN/public/repo/.claude" "$IN/hooks"
    : > "$WS/.niwa/workspace.toml"
    printf '{}' > "$IN/.niwa/instance.json"
}
ws_settings() { printf '%s' "$1" > "$WS/.claude/settings.json"; }
in_settings() { printf '%s' "$1" > "$IN/.claude/settings.json"; }
in_local() { printf '%s' "$1" > "$IN/.claude/settings.local.json"; }
read_roots() { seen "$(bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")"; }
perm() { jq -nc --arg k "$1" --arg r "$2" --arg m "${3-}" '{permissions: ({($k): [$r]} + (if $m == "" then {} else {defaultMode: $m} end))}'; }
hook() { # hook <matcher> <command> [mode]
    jq -nc --arg m "$1" --arg c "$2" --arg d "${3-}" '{hooks: {PreToolUse: [{matcher: $m, hooks: [{type: "command", command: $c}]}]}}
        + (if $d == "" then {} else {permissions: {defaultMode: $d}} end)'
}

echo "== modes and rules =="
fresh
eq "no rules and the default mode confirm every step" "readable merge:confirm close:confirm teardown:confirm release:confirm" "$(read_roots)"
in_settings '{"permissions":{"defaultMode":"bypassPermissions"}}'
eq "bypassPermissions with no rule permits every step" "readable merge:permit close:permit teardown:permit release:permit" "$(read_roots)"
in_settings '{"permissions":{"defaultMode":"acceptEdits"}}'
eq "acceptEdits with no rule confirms" "readable merge:confirm close:confirm teardown:confirm release:confirm" "$(read_roots)"
fresh; in_settings "$(perm deny 'Bash(gh pr merge:*)' bypassPermissions)"
eq "a deny rule on gh pr merge denies the merge step" "readable merge:deny close:permit teardown:permit release:permit" "$(read_roots)"
for r in 'Bash(*merge-exec.sh*)' 'Bash(bash */land-merge.sh:*)' 'Bash(gh pr merge *)' 'Bash(land-merge.sh)'; do
    fresh; in_settings "$(perm deny "$r" bypassPermissions)"
    eq "deny $r governs the one merge step" "readable merge:deny close:permit teardown:permit release:permit" "$(read_roots)"
done
for r in 'Bash(gh pr merge:*)' 'Bash(bash */merge-exec.sh *)' 'Bash(*/land-merge.sh:*)'; do
    fresh; in_settings "$(perm allow "$r")"
    eq "allow $r permits the one merge step" "readable merge:permit close:confirm teardown:confirm release:confirm" "$(read_roots)"
done
fresh; in_settings "$(perm ask 'Bash(gh issue close *)' bypassPermissions)"
eq "an ask rule on gh issue close confirms close" "readable merge:permit close:confirm teardown:permit release:permit" "$(read_roots)"
fresh; in_settings "$(perm ask 'Bash(gh pr close *)' bypassPermissions)"
eq "an ask rule on gh pr close confirms close" "readable merge:permit close:confirm teardown:permit release:permit" "$(read_roots)"
# The record has no issue or pull request to close: state-write.sh closes
# nothing, so a rule on it no longer governs the close step.
fresh; in_settings "$(perm ask 'Bash(*state-write.sh*--close*)' bypassPermissions)"
eq "an ask rule on state-write.sh --close governs nothing" "readable merge:permit close:permit teardown:permit release:permit" "$(read_roots)"
fresh; in_settings "$(perm allow 'Bash(niwa destroy:*)')"
eq "an allow rule on niwa destroy permits teardown" "readable merge:confirm close:confirm teardown:permit release:confirm" "$(read_roots)"
fresh; in_settings "$(perm deny 'Bash(niwa destroy --force:*)' bypassPermissions)"
eq "a deny on niwa destroy --force denies teardown" "readable merge:permit close:permit teardown:deny release:permit" "$(read_roots)"
# The teardown pass runs claude rm and niwa destroy inside teardown-pass.sh,
# so a rule on either, or on the script, governs the step.
for r in 'Bash(claude rm:*)' 'Bash(*teardown-pass.sh*)'; do
    fresh; in_settings "$(perm deny "$r" bypassPermissions)"
    eq "a deny on $r denies teardown" "readable merge:permit close:permit teardown:deny release:permit" "$(read_roots)"
    fresh; in_settings "$(perm ask "$r" bypassPermissions)"
    eq "an ask on $r confirms teardown" "readable merge:permit close:permit teardown:confirm release:permit" "$(read_roots)"
done
# The skill never runs niwa reap or the other untargeted removals, so a rule
# about them leaves the teardown step alone (shirabe#616).
for r in 'Bash(niwa reap)' 'Bash(niwa reap:*)' 'Bash(niwa instance remove:*)' 'Bash(niwa remove:*)'; do
    fresh; in_settings "$(perm deny "$r" bypassPermissions)"
    eq "a deny on $r leaves teardown permitted" "readable merge:permit close:permit teardown:permit release:permit" "$(read_roots)"
done
fresh; ws_settings "$(perm deny 'Bash(gh pr merge:*)')"; in_settings "$(perm allow 'Bash(gh:*)')"
eq "a workspace deny wins over an instance allow" "readable merge:deny close:permit teardown:confirm release:permit" "$(read_roots)"
fresh; in_settings "$(perm allow 'Bash(gh pr merge:*)')"; in_local "$(perm ask 'Bash(gh pr merge:*)')"
eq "ask wins over allow" "readable merge:confirm close:confirm teardown:confirm release:confirm" "$(read_roots)"
fresh; in_settings "$(perm allow 'Bash')"
eq "a bare Bash allow permits every step" "readable merge:permit close:permit teardown:permit release:permit" "$(read_roots)"
fresh; in_settings "$(perm deny 'Read(./secrets/**)' bypassPermissions)"
eq "a rule for another tool is ignored" "readable merge:permit close:permit teardown:permit release:permit" "$(read_roots)"

echo "== hooks, never run =="
fresh
SENT="$T/sentinel-ran"
printf '#!/bin/sh\ntouch %s\ncase "$1" in gh\\ pr\\ merge*) exit 2 ;; esac\n' "$SENT" > "$IN/hooks/guard.sh"
chmod +x "$IN/hooks/guard.sh"
in_settings "$(hook Bash "$IN/hooks/guard.sh" bypassPermissions)"
eq "a hook mentioning gh pr merge reserves merge" "readable merge:confirm close:permit teardown:permit release:permit" "$(read_roots)"
[ -e "$SENT" ] && bad "the sentinel hook is never run" || ok "the sentinel hook is never run"
fresh
printf '#!/bin/sh\ntouch %s\ngrep -q "niwa destroy" && exit 2\n' "$SENT" > "$IN/hooks/guard.sh"
in_settings "$(hook 'Bash|Edit' 'bash "$CLAUDE_PROJECT_DIR"/hooks/guard.sh' bypassPermissions)"
eq "a hook named through \$CLAUDE_PROJECT_DIR is read" "readable merge:permit close:permit teardown:confirm release:permit" "$(read_roots)"
[ -e "$SENT" ] && bad "a \$CLAUDE_PROJECT_DIR hook is never run" || ok "a \$CLAUDE_PROJECT_DIR hook is never run"
fresh
in_settings "$(hook Bash 'jq -r .tool_input.command | grep -q "gh pr close" && exit 2' bypassPermissions)"
eq "an inline hook command is read as text" "readable merge:permit close:confirm teardown:permit release:permit" "$(read_roots)"
fresh
printf 'gh pr merge\n' > "$IN/hooks/edit.sh"
in_settings "$(hook Edit "$IN/hooks/edit.sh" bypassPermissions)"
eq "a hook whose matcher doesn't cover Bash is ignored" "readable merge:permit close:permit teardown:permit release:permit" "$(read_roots)"
fresh
in_settings "$(hook '' "$IN/hooks/missing.sh" bypassPermissions)"
eq "an unreadable hook script leaves every step unread" "unread merge:unread close:unread teardown:unread release:unread" "$(read_roots)"
ws_settings "$(perm deny 'Bash(gh pr merge:*)')"
eq "a deny stays deny beside an unreadable hook" "unread merge:deny close:unread teardown:unread release:unread" "$(read_roots)"
fresh
printf 'case $c in gh\\ pr\\ merge*) deny ;; esac\n' > "$IN/hooks/g.sh"
ws_settings "$(perm deny 'Bash(gh pr merge:*)')"
in_settings "$(hook Bash "$IN/hooks/g.sh")"
eq "a hook can't lift a deny" "readable merge:deny close:confirm teardown:confirm release:confirm" "$(read_roots)"

echo "== hooks the reader can't locate =="
# Each shape leaves the reader unable to see what the hook decides, so every
# step that isn't already deny is unread, never permit under bypass.
mkdir -p "$T/outside"
printf 'import sys\n' > "$T/outside/merge-guard"
UNREAD_ALL="unread merge:unread close:unread teardown:unread release:unread"
for c in 'python3 guard.py' 'merge-guard-hook' '/usr/local/bin/merge-guard' "$T/outside/merge-guard" \
         "python3 $T/outside/merge-guard" '$CLAUDE_PROJECT_DIR/hooks/missing.sh' 'bash hooks/missing.sh' \
         'python3 -m guard' 'bash "$(dirname "$0")/g.sh"' 'jq -r .tool_input.command | merge-guard-hook' \
         'if true; then merge-guard-hook; fi' 'env FOO=1 guard-hook --check' 'bash -e guard.sh' 'node -r x guard.js' \
         'bash -c /usr/local/bin/merge-guard' 'bash -c "exec merge-guard"' 'sh -c ". /opt/guard.sh"' 'source /opt/guard.sh'; do
    fresh
    printf 'print(1)\n' > "$IN/guard.py"
    in_settings "$(hook Bash "$c" bypassPermissions)"
    eq "hook [$c] leaves every step unread" "$UNREAD_ALL" "$(read_roots)"
done
fresh
in_settings "$(hook Bash 'merge-guard-hook' bypassPermissions)"
ws_settings "$(perm deny 'Bash(niwa destroy:*)')"
eq "a deny stays deny beside a PATH-command hook" "unread merge:unread close:unread teardown:deny release:unread" "$(read_roots)"
fresh
printf 'if "gh pr merge" in cmd: sys.exit(2)\n' > "$IN/hooks/g.py"
in_settings "$(hook Bash 'python3 "$CLAUDE_PROJECT_DIR"/hooks/g.py' bypassPermissions)"
eq "an interpreter's script under the root is read" "readable merge:confirm close:permit teardown:permit release:permit" "$(read_roots)"
fresh
printf 'niwa destroy\n' > "$IN/hooks/g.sh"
in_settings "$(hook Bash 'bash -euo pipefail hooks/g.sh 2>/dev/null' bypassPermissions)"
eq "a relative script path under the root is read" "readable merge:permit close:permit teardown:confirm release:permit" "$(read_roots)"
fresh
# A gate hook that denies only the reap sweep, in the shape a workspace
# installs: its text names niwa reap and niwa, never niwa destroy.
printf '#!/bin/sh\nawk '"'"'t ~ /niwa[ \\t\\n]+reap/ { exit 2 }'"'"'\nsplit("gh niwa git", g, " ")\n' > "$IN/hooks/gate.sh"
in_settings "$(hook Bash "$IN/hooks/gate.sh" bypassPermissions)"
eq "a hook that denies only niwa reap leaves teardown permitted" "readable merge:permit close:permit teardown:permit release:permit" "$(read_roots)"
fresh
in_settings "$(hook Bash 'bash -c "grep -q gh\ pr\ close && exit 2"' bypassPermissions)"
eq "an interpreter given inline code is read as text" "readable merge:permit close:confirm teardown:permit release:permit" "$(read_roots)"

fresh
printf 'gh pr merge\n' > "$IN/hooks/g.sh"
in_settings "$(hook Bash 'bash -c "./hooks/g.sh"' bypassPermissions)"
eq "a shell's inline code that runs a script under the root reads that script" "readable merge:confirm close:permit teardown:permit release:permit" "$(cd "$IN" && read_roots)"

echo "== niwa's worktree hooks =="
# niwa writes its worktree hooks PATH-first with its installed path as the
# fallback (shirabe#988). `command -v` looks niwa up and runs nothing, `2>&1`
# is a redirection rather than a command, and the guard and from-hook
# subcommands gate none of the three steps, so the posture reads as if the
# hook weren't there.
NHOME="$T/home"
NIWA_ABS="$NHOME/.tsuku/tools/current/niwa"
read_home() { seen "$(HOME="$NHOME" bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")"; }
niwa_hook() { printf "command -v niwa >/dev/null 2>&1 && exec niwa %s; exec '%s' %s" "$1" "$NIWA_ABS" "$1"; }
for sub in 'worktree guard' 'worktree from-hook'; do
    fresh
    in_settings "$(hook 'EnterWorktree|Bash' "$(niwa_hook "$sub")" bypassPermissions)"
    eq "niwa's [$sub] hook leaves the posture readable" "readable merge:permit close:permit teardown:permit release:permit" "$(read_home)"
    fresh
    in_settings "$(hook 'EnterWorktree|Bash' "$(niwa_hook "$sub")")"
    eq "niwa's [$sub] hook under the default mode confirms, as with no hook" "readable merge:confirm close:confirm teardown:confirm release:confirm" "$(read_home)"
done
fresh
ws_settings "$(perm deny 'Bash(niwa destroy:*)')"
in_settings "$(hook 'EnterWorktree|Bash' "$(niwa_hook 'worktree guard')" bypassPermissions)"
eq "a deny stays deny beside niwa's guard" "readable merge:permit close:permit teardown:deny release:permit" "$(read_home)"
fresh
in_settings "$(hook Bash 'command -V niwa >/dev/null && exec niwa worktree guard' bypassPermissions)"
eq "command -V is a lookup too" "readable merge:permit close:permit teardown:permit release:permit" "$(read_home)"
# Only niwa's two worktree hooks, under the bare name or the path niwa
# installs, with nothing after them: anything else niwa could run stays unread.
for c in 'niwa worktree guard --force' 'niwa worktree' 'niwa destroy x' 'niwa worktree from-hook extra' \
         '/usr/local/bin/niwa worktree guard' "$NHOME/.tsuku/tools/0.34.1/niwa worktree guard" \
         "$T/niwa worktree guard" "command -v niwa >/dev/null 2>&1 && exec niwa worktree guard; exec '/opt/niwa' worktree guard" \
         'command -v niwa && exec niwa instance context' 'command -p merge-guard-hook' 'command merge-guard-hook' \
         'command -v merge-guard-hook; merge-guard-hook' 'merge-guard-hook 2>&1' 'merge-guard-hook>&2' 'true 2>&1 && merge-guard-hook' \
         'PATH=/tmp niwa worktree guard' 'env PATH=/tmp niwa worktree guard' 'exec env niwa worktree guard' \
         'command -v niwa merge-guard-hook' "$(printf 'command -v niwa\nmerge-guard-hook')" \
         'PATH=/tmp; niwa worktree guard' 'PATH=/tmp && exec niwa worktree guard' 'export PATH=/tmp; exec niwa worktree guard' \
         'cd /tmp && niwa worktree guard' 'true; niwa worktree guard' 'bash -c "niwa worktree guard"' \
         'command -v niwa >(merge-guard-hook)' 'true >(merge-guard-hook)'; do
    fresh
    in_settings "$(hook Bash "$c" bypassPermissions)"
    eq "hook [$c] leaves every step unread" "$UNREAD_ALL" "$(read_home)"
done
# Without a HOME the installed path can't be told from any other, so only the
# bare niwa passes; an empty HOME doesn't make /.tsuku/... niwa's.
fresh
in_settings "$(hook 'EnterWorktree|Bash' "$(niwa_hook 'worktree guard')" bypassPermissions)"
eq "with HOME unset the installed path is unread" "$UNREAD_ALL" \
    "$(seen "$(env -u HOME bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")")"
eq "with HOME empty the installed path is unread" "$UNREAD_ALL" \
    "$(seen "$(HOME='' bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")")"
fresh
in_settings "$(hook Bash 'exec niwa worktree guard' bypassPermissions)"
eq "with HOME unset the bare niwa still passes" "readable merge:permit close:permit teardown:permit release:permit" \
    "$(seen "$(env -u HOME bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")")"
# A plain `command` or `exec` still leads into the script it runs, read as before.
for lead in command exec; do
    fresh
    printf 'gh pr merge\n' > "$IN/hooks/g.sh"
    in_settings "$(hook Bash "$lead $IN/hooks/g.sh --check" bypassPermissions)"
    eq "[$lead <path> args] still reads the script" "readable merge:confirm close:permit teardown:permit release:permit" "$(read_home)"
done
fresh
printf 'gh pr close\n' > "$IN/hooks/g.sh"
in_settings "$(hook Bash "exec $IN/hooks/g.sh" bypassPermissions)"
eq "a bare [exec <path>] still reads the script" "readable merge:permit close:confirm teardown:permit release:permit" "$(read_home)"
fresh
in_settings "$(hook Bash 'jq -r .tool_input.command 2>&1 | grep -q "gh pr close" >&2 && exit 2' bypassPermissions)"
eq "a descriptor redirection isn't a command" "readable merge:permit close:confirm teardown:permit release:permit" "$(read_home)"

echo "== unreadable and missing =="
fresh; printf '{not json' > "$IN/.claude/settings.local.json"
eq "an unparseable settings file is unread" "unread merge:unread close:unread teardown:unread release:unread" "$(read_roots)"
fresh; rm -f "$WS/.claude/settings.json" "$IN/.claude/settings.json"
eq "missing settings files are fine" "readable merge:confirm close:confirm teardown:confirm release:confirm" "$(read_roots)"
mkdir -p "$T/nowhere"
eq "no roots at all leaves every step unread" "unread merge:unread close:unread teardown:unread release:unread" "$(seen "$(cd "$T/nowhere" && bash "$PRD" --no-seal 2>/dev/null)")"

echo "== roots from the working directory =="
fresh
ws_settings '{"permissions":{"defaultMode":"bypassPermissions"}}'
in_settings "$(perm deny 'Bash(niwa destroy:*)')"
printf '%s' "$(perm deny 'Bash(gh pr merge:*)')" > "$IN/public/repo/.claude/settings.json"
eq "the roots are found walking up; a cloned repository's settings are ignored" "readable merge:permit close:permit teardown:deny release:permit" \
    "$(cd "$IN/public/repo" && bash "$PRD" --no-seal 2>"$T/err")"

echo "== the release step =="
fresh
in_settings "$(hook Bash 'jq -r .tool_input.command | grep -q "gh release create" && exit 2' bypassPermissions)"
eq "with no grant, a hook naming gh release create confirms release" "readable merge:permit close:permit teardown:permit release:confirm" "$(read_roots)"
fresh; in_settings "$(perm deny 'Bash(gh release create:*)' bypassPermissions)"
eq "a deny rule on gh release create denies release" "readable merge:permit close:permit teardown:permit release:deny" "$(read_roots)"
fresh; in_settings "$(perm ask 'Bash(gh release:*)' bypassPermissions)"
eq "an ask rule on gh release confirms release" "readable merge:permit close:permit teardown:permit release:confirm" "$(read_roots)"
# An unread release alone doesn't make the token unread: beside three denied
# steps the token reads as it did before the release step existed.
fresh
ws_settings '{"permissions":{"deny":["Bash(gh pr merge:*)","Bash(gh issue close:*)","Bash(niwa destroy:*)"]}}'
in_settings "$(hook Bash 'merge-guard-hook' bypassPermissions)"
eq "an unread release leaves the leading word alone" "readable merge:deny close:deny teardown:deny release:unread" "$(read_roots)"

echo "== the grant =="
SID=session-under-test
STUB="$T/stub"
mkdir -p "$STUB"
# The stub logs its arguments and answers from $T/answer.json, or as
# $T/niwa.mode says: exit 1 (still printing the answer), print nothing, hang.
cat > "$STUB/niwa" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/niwa.calls"
case "\$(cat "$T/niwa.mode" 2>/dev/null)" in
    exit1) cat "$T/answer.json"; exit 1 ;;
    empty) exit 0 ;;
    hang) sleep 30 ;;
esac
cat "$T/answer.json"
EOF
chmod +x "$STUB/niwa"
# PATH with every directory holding a niwa replaced by a copy without it.
NOPATH= i=0
IFS=: read -r -a PATH_DIRS <<< "$PATH"
for d in "${PATH_DIRS[@]}"; do
    [ -n "$d" ] || continue
    if [ -e "$d/niwa" ]; then
        i=$((i + 1)); mkdir -p "$T/nopath$i"
        for f in "$d"/*; do [ "${f##*/}" = niwa ] || ln -s "$f" "$T/nopath$i/"; done
        d="$T/nopath$i"
    fi
    NOPATH="$NOPATH${NOPATH:+:}$d"
done
mode() { printf '%s' "$1" > "$T/niwa.mode"; rm -f "$T/niwa.calls"; }
answer() { printf '%s\n' "$1" > "$T/answer.json"; mode answer; }
# bound_doc <authorities, comma-separated> <level>: a bound answer whose
# points carry the decider and author exclusion niwa gives the level.
bound_doc() {
    jq -nc --arg g "$1" --arg l "$2" '
        {autonomous: ["session", "off"], supervised: ["dispatcher", "on"], strict: ["person", "on"]}[$l] as $d
        | {schema: "niwa.authority.check/v1", state: "bound", binding: "mapping",
           dispatch_id: "dispatch-under-test",
           parent: {dispatch_id: "parent-dispatch", instance: "coordinator-instance"},
           grant: [$g | split(",")[] | select(. != "") | {authority: ., sources: ["dispatch"]}],
           level: $l, level_source: "workspace", grant_ceiling_source: "workspace",
           points: [("merge-pr", "close-issue", "cut-release") | {point: ., decider: $d[0], author_exclusion: $d[1]}]}'
}
ALL3=merge-pr,close-issue,cut-release
read_grant() {
    seen "$(CLAUDE_CODE_SESSION_ID=$SID PATH="$STUB:$PATH" bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")"
}
# An instance whose gate hook names the merge, close and release commands,
# under bypassPermissions: today it reserves all three.
gate_fixture() {
    fresh
    printf '#!/bin/sh\ncase "$1" in *"gh pr merge"*|*"gh issue close"*|*"gh release create"*) exit 2 ;; esac\n' > "$IN/hooks/gate.sh"
    in_settings "$(hook Bash "$IN/hooks/gate.sh" "${1-bypassPermissions}")"
}
TODAY="readable merge:confirm close:confirm teardown:permit release:confirm"

gate_fixture; answer "$(bound_doc "$ALL3" autonomous)"
eq "bound holding all three at autonomous permits merge, close and release" \
    "readable merge:permit close:permit teardown:permit release:permit" "$(read_grant)"
eq "the lookup asks for this session, the instance root and the three points" \
    "authority check --json --session $SID -C $(cd "$IN" && pwd -P) --point merge-pr --point close-issue --point cut-release" \
    "$(cat "$T/niwa.calls")"
# The re-read before a merge (board-lib.sh's bl_merge_posture) runs with
# --session and --no-seal from inside the instance, the roots found by walking up.
eq "the re-read before a merge permits it too" "readable merge:permit close:permit teardown:permit release:permit" \
    "$(seen "$(cd "$IN/public/repo" && CLAUDE_CODE_SESSION_ID=$SID PATH="$STUB:$PATH" bash "$PRD" --session s --no-seal 2>"$T/err")")"
answer "$(bound_doc close-issue,cut-release autonomous)"
eq "bound without merge-pr denies the merge" "readable merge:deny close:permit teardown:permit release:permit" "$(read_grant)"
answer "$(bound_doc "$ALL3" strict)"
eq "at strict a person settles each step: merge and release deny, close confirms" \
    "readable merge:deny close:confirm teardown:permit release:deny" "$(read_grant)"
answer "$(bound_doc "$ALL3" supervised)"
eq "at supervised the dispatcher settles every step: deny" \
    "readable merge:deny close:deny teardown:permit release:deny" "$(read_grant)"
answer "$(bound_doc merge-pr,close-issue autonomous)"
eq "bound without cut-release denies the release, as without merge-pr the merge" \
    "readable merge:permit close:permit teardown:permit release:deny" "$(read_grant)"
answer "$(bound_doc '' autonomous)"
eq "bound with no grant denies merge, close and release" \
    "readable merge:deny close:deny teardown:permit release:deny" "$(read_grant)"
answer "$(bound_doc "$ALL3" autonomous | jq -c '.points[].author_exclusion = "on"')"
eq "author exclusion denies merge and release and confirms close" \
    "readable merge:deny close:confirm teardown:permit release:deny" "$(read_grant)"
answer "$(bound_doc "$ALL3" autonomous | jq -c '(.points[] | select(.point == "cut-release")).decider = "person"')"
eq "cut-release settled by a person denies the release alone" \
    "readable merge:permit close:permit teardown:permit release:deny" "$(read_grant)"
answer "$(bound_doc "$ALL3" autonomous | jq -c '(.points[] | select(.point == "close-issue")).decider = "person"')"
eq "close-issue settled by a person still confirms the close" \
    "readable merge:permit close:confirm teardown:permit release:permit" "$(read_grant)"
answer "$(bound_doc "$ALL3" autonomous)"
ws_settings "$(perm deny 'Bash(gh pr merge:*)')"
eq "a deny rule on gh pr merge still wins over a bound merge-pr" \
    "readable merge:deny close:permit teardown:permit release:permit" "$(read_grant)"
ws_settings "$(perm ask 'Bash(gh issue close *)')"
eq "an ask rule on gh issue close still confirms the close" \
    "readable merge:permit close:confirm teardown:permit release:permit" "$(read_grant)"
gate_fixture default; answer "$(bound_doc "$ALL3" autonomous)"
eq "under the default mode the grant can't lift Claude Code's own confirmation" \
    "readable merge:confirm close:confirm teardown:confirm release:confirm" "$(read_grant)"
fresh; in_settings "$(hook Bash 'merge-guard-hook' bypassPermissions)"
eq "with an unreadable hook the grant still decides merge, close and release" \
    "unread merge:permit close:permit teardown:unread release:permit" "$(read_grant)"
gate_fixture; answer "$(bound_doc "$ALL3" autonomous)"
eq "with niwa off PATH, NIWA_BIN names it" "readable merge:permit close:permit teardown:permit release:permit" \
    "$(seen "$(CLAUDE_CODE_SESSION_ID=$SID NIWA_BIN="$STUB/niwa" PATH="$NOPATH" bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")")"
answer '{"schema":"niwa.authority.check/v1","state":"record-unusable","reason":"record-missing","dispatch_id":"dispatch-under-test","grant":[]}'
eq "record-unusable denies merge and release and reads the rest as today" \
    "readable merge:deny close:confirm teardown:permit release:deny" "$(read_grant)"

# Every answer that isn't bound or record-unusable, and every failed lookup,
# reads exactly as with no niwa: today's token plus the release step.
eq "with no niwa at all the posture is today's" "$TODAY" \
    "$(seen "$(CLAUDE_CODE_SESSION_ID=$SID PATH="$NOPATH" bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")")"
answer '{"schema":"niwa.authority.check/v1","state":"not-dispatched","reason":"no-mapping","grant":[]}'
eq "not-dispatched reads as today" "$TODAY" "$(read_grant)"
answer "$(bound_doc "$ALL3" autonomous)"; mode exit1
eq "a niwa that exits 1 reads as today" "$TODAY" "$(read_grant)"
mode empty
eq "a niwa that prints nothing reads as today" "$TODAY" "$(read_grant)"
for patch in '.schema = "niwa.authority.check/v2"' '.state = "bound-ish"' '.points[0].decider = "owner"' \
             '.points[1].author_exclusion = "maybe"' '.grant[0].authority = "push-tag"' '.level = "relaxed"' \
             '.points = .points[1:]' 'del(.points)' '.grant = "merge-pr"' '[.]'; do
    answer "$(bound_doc "$ALL3" autonomous | jq -c "$patch")"
    eq "an answer with [$patch] reads as today" "$TODAY" "$(read_grant)"
done
answer 'not json'
eq "an answer that isn't JSON reads as today" "$TODAY" "$(read_grant)"
answer "$(bound_doc "$ALL3" autonomous)"
eq "with no session id there is no lookup" "$TODAY" \
    "$(seen "$(PATH="$STUB:$PATH" bash "$PRD" --instance-root "$IN" --workspace-root "$WS" --no-seal 2>"$T/err")")"
[ -e "$T/niwa.calls" ] && bad "with no session id niwa isn't run" || ok "with no session id niwa isn't run"
mode hang
start=$(date +%s)
eq "a niwa that hangs reads as today" "$TODAY" "$(read_grant)"
took=$(( $(date +%s) - start ))
[ "$took" -lt 5 ] && ok "a hanging niwa is cut off in under 5 seconds" || bad "a hanging niwa is cut off in under 5 seconds" "took ${took}s"

echo "== sealing =="
fresh
S=coordinate-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" start start_posture
OUT=$(bash "$PRD" --session "$S" --instance-root "$IN" --workspace-root "$WS" 2>"$T/err")
seen "$OUT" > /dev/null
case "$OUT" in "readable merge:confirm close:confirm teardown:confirm release:confirm sealed:"*) ok "the verdict is sealed" ;; *) bad "the verdict is sealed" "$OUT $(cat "$T/err")" ;; esac
bash "$HERE/coord-log.sh" check --session "$S" --state start_posture --sealed "$OUT" && ok "the seal checks" || bad "the seal checks"
eq "the detail names each step's verdict" confirm "$(jq -r .steps.merge.verdict "$KOTO_STORE/context/$S/coord/posture.json")"
jq -e 'tostring | contains("env") | not' "$KOTO_STORE/context/$S/coord/posture.json" >/dev/null && ok "the detail carries no env block" || bad "the detail carries no env block"
eq "with no grant every step's source is the workspace" workspace,workspace,workspace,workspace \
    "$(jq -r '[.steps[].source] | join(",")' "$KOTO_STORE/context/$S/coord/posture.json")"

gate_fixture; answer "$(bound_doc merge-pr,close-issue autonomous)"
S=coordinate-plugin-system-20260926T080500Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" start start_posture
OUT=$(CLAUDE_CODE_SESSION_ID=$SID PATH="$STUB:$PATH" bash "$PRD" --session "$S" --instance-root "$IN" --workspace-root "$WS" 2>"$T/err")
seen "$OUT" > /dev/null
case "$OUT" in "readable merge:permit close:permit teardown:permit release:deny sealed:"*) ok "a bound verdict is sealed" ;; *) bad "a bound verdict is sealed" "$OUT $(cat "$T/err")" ;; esac
D="$KOTO_STORE/context/$S/coord/posture.json"
eq "the grant's steps record source=grant" "merge=grant close=grant teardown=workspace release=grant" \
    "$(jq -r '[.steps | to_entries[] | "\(.key)=\(.value.source)"] | join(" ")' "$D")"
eq "a missing authority's reason names what the grant holds and lacks" "the grant holds merge-pr,close-issue; needs cut-release" \
    "$(jq -r .steps.release.why "$D")"
eq "the detail keeps the lookup's state, grant and parent" "bound merge-pr,close-issue coordinator-instance" \
    "$(jq -r '.grant_check | "\(.state) \(.grant | join(",")) \(.parent.instance)"' "$D")"
# A rule stricter than the grant's answer decides the step, so the step stays
# the workspace's, with the rule as its reason.
ws_settings "$(perm deny 'Bash(gh pr merge:*)')"
S=coordinate-plugin-system-20260926T081000Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" start start_posture
OUT=$(CLAUDE_CODE_SESSION_ID=$SID PATH="$STUB:$PATH" bash "$PRD" --session "$S" --instance-root "$IN" --workspace-root "$WS" 2>"$T/err")
seen "$OUT" > /dev/null
D="$KOTO_STORE/context/$S/coord/posture.json"
eq "a deny rule that beats the grant keeps the merge step the workspace's" "deny workspace deny Bash(gh pr merge:*)" \
    "$(jq -r '.steps.merge | "\(.verdict) \(.source) \(.why)"' "$D")"
eq "the steps the grant still decides keep source=grant" "grant grant" "$(jq -r '"\(.steps.close.source) \(.steps.release.source)"' "$D")"

tokens_ok posture-read
done_tests posture-read
