#!/usr/bin/env bash
# check-event-sender-names_test.sh -- the check passes on this repository, and
# on a scratch repository it fails for each kind of code file that names the
# event sender and passes for the helper, its test and documentation.
#
# Usage: bash scripts/check-event-sender-names_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CHECK="$HERE/check-event-sender-names.sh"
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }

PASS=0
FAIL=0
ok() { echo "ok   $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1${2:+: $2}"; FAIL=$((FAIL + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-event-sender-names-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

# The names, built from parts like the check builds them.
FILE_NAME="event-""sink"
VAR_TAIL="EVENT_""SINK"

if bash "$CHECK" >"$T/out" 2>&1; then ok "this repository passes"; else bad "this repository passes" "$(cat "$T/out")"; fi

# repo <path> <content>: a scratch repository holding the helper, its test and
# one more tracked file.
repo() {
    rm -rf "$T/r"
    mkdir -p "$T/r/scripts" "$T/r/$(dirname "$1")"
    printf '%s\n' "x=\$HOME/.local/libexec/fleet/$FILE_NAME; [ \"\${FLEET_$VAR_TAIL-}\" = off ]" >"$T/r/scripts/emit-event.sh"
    printf '%s\n' "# $FILE_NAME" >"$T/r/scripts/emit-event_test.sh"
    printf '%s\n' "$2" >"$T/r/$1"
    git -C "$T/r" init -q
    git -C "$T/r" add -A
}

flags() { # flags <label> <path> <content>
    repo "$2" "$3"
    if bash "$CHECK" "$T/r" >"$T/out" 2>&1; then bad "$1" "passed"
    elif grep -qF "$2" "$T/out"; then ok "$1"
    else bad "$1" "$(cat "$T/out")"; fi
}
passes() { # passes <label> <path> <content>
    repo "$2" "$3"
    if bash "$CHECK" "$T/r" >"$T/out" 2>&1; then ok "$1"; else bad "$1" "$(cat "$T/out")"; fi
}

passes "the helper and its test may name it" "scripts/other.sh" "echo hello"
flags "a script naming the sender's file" "skills/x/scripts/send.sh" "\$HOME/.local/libexec/fleet/$FILE_NAME event"
flags "a script naming the off switch" "scripts/y.sh" "FLEET_$VAR_TAIL=off"
flags "a name assembled around the variable's tail" "scripts/z.sh" "v=FLEET_; eval \"\${v}$VAR_TAIL\""
MIXED="Event-""Sink"
flags "a different case" "scripts/w.py" "path = '$MIXED'"
flags "a koto template" "skills/x/koto-templates/t.md" "default_action: $FILE_NAME event"
flags "a test of another script" "skills/x/scripts/a_test.sh" "touch $FILE_NAME"
flags "a workflow" ".github/workflows/w.yml" "run: $FILE_NAME"
passes "a design document" "docs/designs/DESIGN-x.md" "the sender at $FILE_NAME"
passes "a skill's Markdown" "skills/x/SKILL.md" "never runs $FILE_NAME"
repo "scripts/q.sh" "echo ok"
printf '%s\n' "$FILE_NAME" >"$T/r/scripts/untracked.sh"
if bash "$CHECK" "$T/r" >/dev/null 2>&1; then ok "an untracked file is not read"; else bad "an untracked file is not read"; fi
if bash "$CHECK" "$T/nowhere" >/dev/null 2>&1; then bad "a root that isn't a repository is an error"; else
    [ $? = 2 ] && ok "a root that isn't a repository is an error" || bad "a root that isn't a repository exits 2"; fi

echo
echo "check-event-sender-names: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
