#!/usr/bin/env bash
# ci-fix-tests_test.sh -- ci-fix-tests.sh against a git fixture and a koto
# stand-in.
# Part of the execute skill
#
# Covers:
#   0  the newest counted head is HEAD; a production-only commit after it;
#      of two children, the newer head is the one compared; a child's own
#      rules copy decides what is a test
#   1  a test edited after the newest counted head, named; a new test too
#   2  no child, no child with a counted head, a head that isn't 40 hex, one
#      that names no commit, one that isn't an ancestor of HEAD, a failed
#      children listing
#   it writes nothing: the stand-in logs every koto write and the log stays
#   empty; the work tree and refs are unchanged
#
# Usage: bash skills/execute/scripts/ci-fix-tests_test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/ci-fix-tests.sh"
RULES="$HERE/../../work-on/references/review-level-rules.tsv"
command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$3] lacks [$2]" ;; esac; }

W=$(mktemp -d "${TMPDIR:-/tmp}/ci-fix-tests-test.XXXXXX") || { echo "FAIL: no temporary directory"; exit 1; }
trap 'rm -rf "$W"' EXIT
export HOME="$W/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t

# --- koto stand-in: `workflows --children <s>` lists the directories under
# $SHIM_STORE/<s>/ as children (exit 1 when $SHIM_STORE/<s>.fail exists);
# `context exists|get <child> <key>` reads $SHIM_STORE/children/<child>/<key>.
# Every other call is logged to $SHIM_LOG as a write and fails.
BIN="$W/bin"
STORE="$W/store"
export SHIM_STORE="$STORE" SHIM_LOG="$W/koto.writes"
mkdir -p "$BIN" "$STORE/children"
: > "$SHIM_LOG"
cat > "$BIN/koto" <<'SHIM'
#!/usr/bin/env bash
if [ "$1 ${2-}" = "workflows --children" ]; then
    [ ! -e "$SHIM_STORE/$3.fail" ] || { echo "shim: listing failed" >&2; exit 1; }
    for d in "$SHIM_STORE/$3"/*/; do
        [ -d "$d" ] || continue
        jq -nc --arg n "$(basename "$d")" --arg p "$3" '{name: $n, parent_workflow: $p}'
    done | jq -s .
    exit 0
fi
if [ "$1" = context ]; then
    f="$SHIM_STORE/children/$3/$4"
    case "$2" in
        exists) [ -f "$f" ]; exit $? ;;
        get) [ -f "$f" ] || exit 1; cat "$f"; exit 0 ;;
    esac
fi
printf '%s\n' "$*" >> "$SHIM_LOG"
exit 2
SHIM
chmod +x "$BIN/koto"

# child <parent> <child> [<counted head> [<rules file>]]: a child session,
# with the keys given.
child() {
    mkdir -p "$STORE/$1/$2" "$STORE/children/$2"
    [ -z "${3:-}" ] || printf '%s\n' "$3" > "$STORE/children/$2/counted_head"
    [ -z "${4:-}" ] || cp "$4" "$STORE/children/$2/review_level_rules.tsv"
}

R="$W/repo"
mkdir -p "$R/tests"
cd "$R" || exit 1
git init -q -b main .
printf '#!/bin/sh\necho "Hello, $1!"\n' > greet.sh
printf '#!/bin/sh\n[ "$(./greet.sh World)" = "Hello, World!" ]\n' > tests/greet_test.sh
git add -A && git commit -q -m base
C0=$(git rev-parse HEAD)

OUT="" ERR="" RC=0
run() {
    OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>"$W/err")
    RC=$?
    ERR=$(cat "$W/err")
}

echo "--- 0: nothing to judge"
child p0 p0.step-1 "$C0"
run p0
eq "the counted head is HEAD: exit 0" 0 "$RC"
has "says nothing changed" "judged: no test file changed since $C0" "$OUT"

printf 'echo more\n' >> greet.sh
git commit -q -am "fix: a production-only CI fix"
C1=$(git rev-parse HEAD)
run p0
eq "a production-only commit after the counted head: exit 0" 0 "$RC"

echo "--- 1: a test changed after the counted head"
sed -i.bak 's/World!/World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "fix: a CI fix that edits a test"
C2=$(git rev-parse HEAD)
run p0
eq "an edited test after the counted head: exit 1" 1 "$RC"
has "the edited test is named" "untested: tests/greet_test.sh" "$OUT"
has "stderr says to start a fix round" "start a fix round" "$ERR"

printf '#!/bin/sh\ntrue\n' > tests/new_test.sh
git add -A && git commit -q -m "test: a new test"
C3=$(git rev-parse HEAD)
run p0
eq "a new test too: exit 1" 1 "$RC"
has "the new test is named" "untested: tests/new_test.sh" "$OUT"

echo "--- the newest counted head"
child p1 p1.step-1 "$C0"
child p1 p1.step-2 "$C1"
child p1 p1.step-2-fix-1 "$C3"
run p1
eq "a fix round counted at HEAD: exit 0" 0 "$RC"
has "the fix round's head is the one compared" "$C3, the counted head p1.step-2-fix-1" "$OUT"
child p2 p2.step-2-fix-1 "$C3"
child p2 p2.step-1 "$C1"
run p2
eq "the newest is chosen whatever the listing order: exit 0" 0 "$RC"
child p3 p3.step-1 "$C1"
child p3 p3.step-2 "$C2"
run p3
eq "the newest counted before the new test: exit 1" 1 "$RC"
has "only the test added since is named" "untested: tests/new_test.sh" "$OUT"
case "$OUT" in *greet_test*) bad "the test counted at the newest head is not named" "$OUT" ;; *) ok "the test counted at the newest head is not named" ;; esac

echo "--- the child's rules copy"
printf 'class\ttest\t**/spec/**\n' > "$W/narrow.tsv"
child p4 p4.step-1 "$C1" "$W/narrow.tsv"
run p4
eq "a rules copy whose test class has no tests/: exit 0" 0 "$RC"

echo "--- 2: could not decide"
mkdir -p "$STORE/p5"
run p5
eq "no child: exit 2" 2 "$RC"
has "no child: says so" "recorded a counted_head" "$ERR"
child p6 p6.step-1
run p6
eq "no child with a counted head: exit 2" 2 "$RC"
child p7 p7.step-1 "$C3"
child p7 p7.step-2 "not-a-head"
run p7
eq "a head that isn't hex: exit 2" 2 "$RC"
has "names the child" "p7.step-2" "$ERR"
child p8 p8.step-1 "${C3:0:12}"
run p8
eq "a short head: exit 2" 2 "$RC"
child p9 p9.step-1 0123456789abcdef0123456789abcdef01234567
run p9
eq "a head that names no commit: exit 2" 2 "$RC"
git checkout -q -b side "$C0"
printf 'side\n' > SIDE.md && git add SIDE.md && git commit -q -m side
SIDE=$(git rev-parse HEAD)
git checkout -q main
child p10 p10.step-1 "$C3"
child p10 p10.step-2 "$SIDE"
run p10
eq "a head that isn't an ancestor of HEAD: exit 2" 2 "$RC"
has "says it isn't an ancestor" "not an ancestor of HEAD" "$ERR"
child p11 p11.step-1 "$C3"
: > "$STORE/p11.fail"
run p11
eq "a failed children listing: exit 2" 2 "$RC"
run
eq "no argument: exit 64" 64 "$RC"
run "../x"
eq "a bad session name: exit 64" 64 "$RC"

echo "--- it writes nothing"
eq "no koto write was attempted" "" "$(cat "$SHIM_LOG")"
eq "HEAD unchanged" "$C3" "$(git rev-parse HEAD)"
eq "the work tree is clean" "" "$(git status --porcelain)"

echo
echo "ci-fix-tests_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
