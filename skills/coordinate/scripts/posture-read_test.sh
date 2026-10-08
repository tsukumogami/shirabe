#!/usr/bin/env bash
# posture-read_test.sh -- posture-read.sh reads the workspace's and the
# instance's settings and hooks, never runs a hook, and reports permit, deny,
# confirm or unread for merge, close and teardown.
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
# inline code are read; no roots found giving unread
# everywhere; the roots found by walking up from the working directory with a
# cloned repository's own settings ignored; $CLAUDE_PROJECT_DIR in a hook
# command; the sealed token and its detail.
#
# Usage: bash skills/coordinate/scripts/posture-read_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
PRD="$HERE/posture-read.sh"

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
eq "no rules and the default mode confirm every step" "readable merge:confirm close:confirm teardown:confirm" "$(read_roots)"
in_settings '{"permissions":{"defaultMode":"bypassPermissions"}}'
eq "bypassPermissions with no rule permits every step" "readable merge:permit close:permit teardown:permit" "$(read_roots)"
in_settings '{"permissions":{"defaultMode":"acceptEdits"}}'
eq "acceptEdits with no rule confirms" "readable merge:confirm close:confirm teardown:confirm" "$(read_roots)"
fresh; in_settings "$(perm deny 'Bash(gh pr merge:*)' bypassPermissions)"
eq "a deny rule on gh pr merge denies the merge step" "readable merge:deny close:permit teardown:permit" "$(read_roots)"
for r in 'Bash(*merge-exec.sh*)' 'Bash(bash */land-merge.sh:*)' 'Bash(gh pr merge *)' 'Bash(land-merge.sh)'; do
    fresh; in_settings "$(perm deny "$r" bypassPermissions)"
    eq "deny $r governs the one merge step" "readable merge:deny close:permit teardown:permit" "$(read_roots)"
done
for r in 'Bash(gh pr merge:*)' 'Bash(bash */merge-exec.sh *)' 'Bash(*/land-merge.sh:*)'; do
    fresh; in_settings "$(perm allow "$r")"
    eq "allow $r permits the one merge step" "readable merge:permit close:confirm teardown:confirm" "$(read_roots)"
done
fresh; in_settings "$(perm ask 'Bash(gh issue close *)' bypassPermissions)"
eq "an ask rule on gh issue close confirms close" "readable merge:permit close:confirm teardown:permit" "$(read_roots)"
fresh; in_settings "$(perm ask 'Bash(*record-write.sh*--close*)' bypassPermissions)"
eq "an ask rule on record-write.sh --close confirms close" "readable merge:permit close:confirm teardown:permit" "$(read_roots)"
fresh; in_settings "$(perm allow 'Bash(niwa destroy:*)')"
eq "an allow rule on niwa destroy permits teardown" "readable merge:confirm close:confirm teardown:permit" "$(read_roots)"
fresh; in_settings "$(perm deny 'Bash(niwa destroy --force:*)' bypassPermissions)"
eq "a deny on niwa destroy --force denies teardown" "readable merge:permit close:permit teardown:deny" "$(read_roots)"
# The teardown pass runs claude rm and niwa destroy inside teardown-pass.sh,
# so a rule on either, or on the script, governs the step.
for r in 'Bash(claude rm:*)' 'Bash(*teardown-pass.sh*)'; do
    fresh; in_settings "$(perm deny "$r" bypassPermissions)"
    eq "a deny on $r denies teardown" "readable merge:permit close:permit teardown:deny" "$(read_roots)"
    fresh; in_settings "$(perm ask "$r" bypassPermissions)"
    eq "an ask on $r confirms teardown" "readable merge:permit close:permit teardown:confirm" "$(read_roots)"
done
# The skill never runs niwa reap or the other untargeted removals, so a rule
# about them leaves the teardown step alone (shirabe#616).
for r in 'Bash(niwa reap)' 'Bash(niwa reap:*)' 'Bash(niwa instance remove:*)' 'Bash(niwa remove:*)'; do
    fresh; in_settings "$(perm deny "$r" bypassPermissions)"
    eq "a deny on $r leaves teardown permitted" "readable merge:permit close:permit teardown:permit" "$(read_roots)"
done
fresh; ws_settings "$(perm deny 'Bash(gh pr merge:*)')"; in_settings "$(perm allow 'Bash(gh:*)')"
eq "a workspace deny wins over an instance allow" "readable merge:deny close:permit teardown:confirm" "$(read_roots)"
fresh; in_settings "$(perm allow 'Bash(gh pr merge:*)')"; in_local "$(perm ask 'Bash(gh pr merge:*)')"
eq "ask wins over allow" "readable merge:confirm close:confirm teardown:confirm" "$(read_roots)"
fresh; in_settings "$(perm allow 'Bash')"
eq "a bare Bash allow permits every step" "readable merge:permit close:permit teardown:permit" "$(read_roots)"
fresh; in_settings "$(perm deny 'Read(./secrets/**)' bypassPermissions)"
eq "a rule for another tool is ignored" "readable merge:permit close:permit teardown:permit" "$(read_roots)"

echo "== hooks, never run =="
fresh
SENT="$T/sentinel-ran"
printf '#!/bin/sh\ntouch %s\ncase "$1" in gh\\ pr\\ merge*) exit 2 ;; esac\n' "$SENT" > "$IN/hooks/guard.sh"
chmod +x "$IN/hooks/guard.sh"
in_settings "$(hook Bash "$IN/hooks/guard.sh" bypassPermissions)"
eq "a hook mentioning gh pr merge reserves merge" "readable merge:confirm close:permit teardown:permit" "$(read_roots)"
[ -e "$SENT" ] && bad "the sentinel hook is never run" || ok "the sentinel hook is never run"
fresh
printf '#!/bin/sh\ntouch %s\ngrep -q "niwa destroy" && exit 2\n' "$SENT" > "$IN/hooks/guard.sh"
in_settings "$(hook 'Bash|Edit' 'bash "$CLAUDE_PROJECT_DIR"/hooks/guard.sh' bypassPermissions)"
eq "a hook named through \$CLAUDE_PROJECT_DIR is read" "readable merge:permit close:permit teardown:confirm" "$(read_roots)"
[ -e "$SENT" ] && bad "a \$CLAUDE_PROJECT_DIR hook is never run" || ok "a \$CLAUDE_PROJECT_DIR hook is never run"
fresh
in_settings "$(hook Bash 'jq -r .tool_input.command | grep -q "gh pr close" && exit 2' bypassPermissions)"
eq "an inline hook command is read as text" "readable merge:permit close:confirm teardown:permit" "$(read_roots)"
fresh
printf 'gh pr merge\n' > "$IN/hooks/edit.sh"
in_settings "$(hook Edit "$IN/hooks/edit.sh" bypassPermissions)"
eq "a hook whose matcher doesn't cover Bash is ignored" "readable merge:permit close:permit teardown:permit" "$(read_roots)"
fresh
in_settings "$(hook '' "$IN/hooks/missing.sh" bypassPermissions)"
eq "an unreadable hook script leaves every step unread" "unread merge:unread close:unread teardown:unread" "$(read_roots)"
ws_settings "$(perm deny 'Bash(gh pr merge:*)')"
eq "a deny stays deny beside an unreadable hook" "unread merge:deny close:unread teardown:unread" "$(read_roots)"
fresh
printf 'case $c in gh\\ pr\\ merge*) deny ;; esac\n' > "$IN/hooks/g.sh"
ws_settings "$(perm deny 'Bash(gh pr merge:*)')"
in_settings "$(hook Bash "$IN/hooks/g.sh")"
eq "a hook can't lift a deny" "readable merge:deny close:confirm teardown:confirm" "$(read_roots)"

echo "== hooks the reader can't locate =="
# Each shape leaves the reader unable to see what the hook decides, so every
# step that isn't already deny is unread, never permit under bypass.
mkdir -p "$T/outside"
printf 'import sys\n' > "$T/outside/merge-guard"
UNREAD_ALL="unread merge:unread close:unread teardown:unread"
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
eq "a deny stays deny beside a PATH-command hook" "unread merge:unread close:unread teardown:deny" "$(read_roots)"
fresh
printf 'if "gh pr merge" in cmd: sys.exit(2)\n' > "$IN/hooks/g.py"
in_settings "$(hook Bash 'python3 "$CLAUDE_PROJECT_DIR"/hooks/g.py' bypassPermissions)"
eq "an interpreter's script under the root is read" "readable merge:confirm close:permit teardown:permit" "$(read_roots)"
fresh
printf 'niwa destroy\n' > "$IN/hooks/g.sh"
in_settings "$(hook Bash 'bash -euo pipefail hooks/g.sh 2>/dev/null' bypassPermissions)"
eq "a relative script path under the root is read" "readable merge:permit close:permit teardown:confirm" "$(read_roots)"
fresh
# A gate hook that denies only the reap sweep, in the shape a workspace
# installs: its text names niwa reap and niwa, never niwa destroy.
printf '#!/bin/sh\nawk '"'"'t ~ /niwa[ \\t\\n]+reap/ { exit 2 }'"'"'\nsplit("gh niwa git", g, " ")\n' > "$IN/hooks/gate.sh"
in_settings "$(hook Bash "$IN/hooks/gate.sh" bypassPermissions)"
eq "a hook that denies only niwa reap leaves teardown permitted" "readable merge:permit close:permit teardown:permit" "$(read_roots)"
fresh
in_settings "$(hook Bash 'bash -c "grep -q gh\ pr\ close && exit 2"' bypassPermissions)"
eq "an interpreter given inline code is read as text" "readable merge:permit close:confirm teardown:permit" "$(read_roots)"

fresh
printf 'gh pr merge\n' > "$IN/hooks/g.sh"
in_settings "$(hook Bash 'bash -c "./hooks/g.sh"' bypassPermissions)"
eq "a shell's inline code that runs a script under the root reads that script" "readable merge:confirm close:permit teardown:permit" "$(cd "$IN" && read_roots)"

echo "== unreadable and missing =="
fresh; printf '{not json' > "$IN/.claude/settings.local.json"
eq "an unparseable settings file is unread" "unread merge:unread close:unread teardown:unread" "$(read_roots)"
fresh; rm -f "$WS/.claude/settings.json" "$IN/.claude/settings.json"
eq "missing settings files are fine" "readable merge:confirm close:confirm teardown:confirm" "$(read_roots)"
mkdir -p "$T/nowhere"
eq "no roots at all leaves every step unread" "unread merge:unread close:unread teardown:unread" "$(seen "$(cd "$T/nowhere" && bash "$PRD" --no-seal 2>/dev/null)")"

echo "== roots from the working directory =="
fresh
ws_settings '{"permissions":{"defaultMode":"bypassPermissions"}}'
in_settings "$(perm deny 'Bash(niwa destroy:*)')"
printf '%s' "$(perm deny 'Bash(gh pr merge:*)')" > "$IN/public/repo/.claude/settings.json"
eq "the roots are found walking up; a cloned repository's settings are ignored" "readable merge:permit close:permit teardown:deny" \
    "$(cd "$IN/public/repo" && bash "$PRD" --no-seal 2>"$T/err")"

echo "== sealing =="
fresh
S=coordinate-plugin-system-20260926T080000Z
log_new "$S" "$(roadmap_vars plugin-system)"
log_to "$S" start start_posture
OUT=$(bash "$PRD" --session "$S" --instance-root "$IN" --workspace-root "$WS" 2>"$T/err")
seen "$OUT" > /dev/null
case "$OUT" in "readable merge:confirm close:confirm teardown:confirm sealed:"*) ok "the verdict is sealed" ;; *) bad "the verdict is sealed" "$OUT $(cat "$T/err")" ;; esac
bash "$HERE/coord-log.sh" check --session "$S" --state start_posture --sealed "$OUT" && ok "the seal checks" || bad "the seal checks"
eq "the detail names each step's verdict" confirm "$(jq -r .steps.merge.verdict "$KOTO_STORE/context/$S/coord/posture.json")"
jq -e 'tostring | contains("env") | not' "$KOTO_STORE/context/$S/coord/posture.json" >/dev/null && ok "the detail carries no env block" || bad "the detail carries no env block"

tokens_ok posture-read
done_tests posture-read
