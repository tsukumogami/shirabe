#!/usr/bin/env bash
# red-first_test.sh -- red-first.sh against a git fixture and a koto stand-in.
#
# The fixture is the design's walkthrough repository: greet.sh prints
# `Hello, <name>!`, tests/run.sh runs every tests/*_test.sh, and the report
# says `./greet.sh ''` should print `error: name required`.
#
# Covers:
#   red        recorded with the base, the reproducing test and its blob id, a
#              harness file, a non-zero exit and an output tail holding the
#              marker; recorded again, still failing, with the correcting
#              change already committed (it runs on the base); refused, with
#              the record untouched, for a command that exits 0, a failure
#              without the marker, a marker under 8 characters, a passage
#              under 20, a marker not in the passage, a passage not in the
#              report (CRLF in the report counts as LF), a unit that isn't a
#              fix, no committed test file, a --tests path that names
#              nothing, a symlinked test file, and a command past its
#              timeout; credential variables don't reach the command
#   observe    a before-observation missing sections is refused naming them;
#              a complete one is recorded; an after needs a before
#   green      a failing green is recorded and exits 1; a passing one exits 0
#   check-red  passes for a non-fix, a red or a before-observation; holds a
#              fix with neither, printing finding red-first/no-red
#   check-green  passes for a non-fix and for a green at HEAD; holds with no
#              green, a failed green, and a green at an older head; holds an
#              observation pair with a `refused:` line saying observations
#              wait for acceptance, and passes it once a minted seat's
#              acceptance covers both digests; every hold prints
#              red-first/no-green
#
# Usage: bash skills/work-on/scripts/red-first_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/red-first.sh"
RULES="$HERE/../references/review-level-rules.tsv"
command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$3] lacks [$2]" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "[$3] holds [$2]" ;; *) ok "$1" ;; esac; }

W=$(mktemp -d) || { echo "FAIL: could not create a temporary directory"; exit 1; }
trap 'rm -rf "$W"' EXIT
export HOME="$W/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t

# --- koto stand-in: context add|get|exists|remove under $SHIM_STORE/<s>/<key> --
BIN="$W/bin"
STORE="$W/store"
mkdir -p "$BIN" "$STORE"
cat > "$BIN/koto" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = context ] || { echo "shim: unsupported $*" >&2; exit 2; }
f="$SHIM_STORE/$3/$4"
case "$2" in
    add) mkdir -p "$SHIM_STORE/$3"; cat > "$f" ;;
    get) [ -f "$f" ] || exit 1; cat "$f" ;;
    exists) [ -f "$f" ] ;;
    remove) rm -f "$f" ;;
esac
SHIM
chmod +x "$BIN/koto"
export SHIM_STORE="$STORE"

# --- the fixture repository --------------------------------------------------------
R="$W/repo"
mkdir -p "$R/tests"
cd "$R" || exit 1
git init -q -b main .
cat > greet.sh <<'EOF'
#!/bin/sh
echo "Hello, $1!"
EOF
cat > tests/run.sh <<'EOF'
#!/bin/sh
# Runs every tests/*_test.sh; non-zero when any fails.
rc=0
for t in tests/*_test.sh; do
    [ -e "$t" ] || continue
    sh "$t" || rc=1
done
exit $rc
EOF
cat > tests/greet_test.sh <<'EOF'
#!/bin/sh
out=$(./greet.sh World)
[ "$out" = "Hello, World!" ] || { echo "expected Hello, World! got $out"; exit 1; }
EOF
chmod +x greet.sh tests/run.sh tests/greet_test.sh
git add -A
git commit -q -m base
BASE=$(git rev-parse HEAD)

REPORT="Running \`./greet.sh ''\` prints \`Hello, !\` instead of \`error: name required\`."
MARKER="error: name required"
printf '%s' "Running \`./greet.sh ''\` prints \`Hello, !\` instead of \`error: name required\`" > "$W/passage"

S=fix1
new_session() {
    rm -rf "${STORE:?}/$1"
    mkdir -p "$STORE/$1"
    printf '%s\n' "$BASE" > "$STORE/$1/impl_base"
    cp "$RULES" "$STORE/$1/review_level_rules.tsv"
    printf '%s\r\n' "$REPORT" > "$STORE/$1/fix_report.txt"
    printf '{"ts":"t","event":"determine","kind":"%s","source":"label:bug","report_source":"issue"}\n' "${2:-fix}" > "$STORE/$1/fix_kind.jsonl"
}
new_session "$S"

OUT="" RC=0
run() {
    OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>"$W/err")
    RC=$?
}
record() { cat "$STORE/$1/red_first.json" 2>/dev/null; }

# --- check-red before anything -----------------------------------------------------
run check-red "$S"
eq "check-red with no red: exit 1" 1 "$RC"
has "check-red with no red: a hold line" "hold: the unit is a fix and has neither a red nor a before-observation" "$OUT"
has "check-red with no red: finding red-first/no-red" '"rule_id":"red-first/no-red"' "$OUT"

# --- red: refusals before the command runs ----------------------------------------
cat > tests/empty_name_test.sh <<'EOF'
#!/bin/sh
out=$(./greet.sh '' 2>&1)
[ "$out" = "error: name required" ] || { echo "expected error: name required, got $out"; exit 1; }
EOF
run red "$S" --marker "$MARKER" --passage-file "$W/passage" -- sh tests/run.sh
eq "no committed test file: exit 1" 1 "$RC"
has "no committed test file: refused, saying to commit it" "commit the reproducing test first" "$OUT"
git add tests/empty_name_test.sh
git commit -q -m "test: reproduce the empty name"
TEST_BLOB=$(git rev-parse HEAD:tests/empty_name_test.sh)

run red "$S" --marker "error" --passage-file "$W/passage" -- sh tests/run.sh
eq "a 5-character marker: exit 1" 1 "$RC"
has "a 5-character marker: refused naming the minimum" "it needs at least 8" "$OUT"
# Exactly 20 characters passes the length rule; `true` then fails the run
# check, which is the refusal it reaches.
printf 'error: name required' > "$W/short"
run red "$S" --marker "$MARKER" --passage-file "$W/short" -- true
has "a 20-character passage passes the length rule" "refused: the command exited 0" "$OUT"
printf 'name required!' > "$W/short2"
run red "$S" --marker "name required" --passage-file "$W/short2" -- sh tests/run.sh
eq "a 14-character passage: exit 1" 1 "$RC"
has "a 14-character passage: refused naming the minimum" "it needs at least 20" "$OUT"
run red "$S" --marker "Goodbye, world" --passage-file "$W/passage" -- sh tests/run.sh
has "a marker not in the passage: refused" "refused: the marker [Goodbye, world] is not in the passage" "$OUT"
printf 'greet.sh should print error: name required for an empty name' > "$W/foreign"
run red "$S" --marker "$MARKER" --passage-file "$W/foreign" -- sh tests/run.sh
eq "a passage not in the report: exit 1" 1 "$RC"
has "a passage not in the report: refused" "the passage is not verbatim in the unit's report" "$OUT"
eq "no refusal wrote a record" "" "$(record "$S")"

new_session change1 change
run red change1 --marker "$MARKER" --passage-file "$W/passage" -- sh tests/run.sh
has "a unit that isn't a fix: refused" "refused: the unit is not recorded as a fix" "$OUT"
run red "$S" --marker "$MARKER" --passage-file "$W/passage" --tests tests/nothing_test.sh -- sh tests/run.sh
has "--tests naming no committed file: refused" "names no committed file at HEAD" "$OUT"

# --- red: refusals from the command's result --------------------------------------
run red "$S" --marker "$MARKER" --passage-file "$W/passage" -- true
eq "a command that exits 0: exit 1" 1 "$RC"
has "a command that exits 0: refused" "refused: the command exited 0 on the base code" "$OUT"
run red "$S" --marker "$MARKER" --passage-file "$W/passage" -- sh -c 'echo "syntax error near line 3"; exit 2'
eq "a failure without the marker: exit 1" 1 "$RC"
has "a failure without the marker: refused" "but its output doesn't hold the marker" "$OUT"
run red "$S" --marker "$MARKER" --passage-file "$W/passage" --timeout 1 -- sh -c 'sleep 8; echo "error: name required"; exit 1'
has "a command past its timeout: refused" "ran past 1 seconds and was killed" "$OUT"
eq "no failed condition wrote a record" "" "$(record "$S")"

# --- red: recorded -----------------------------------------------------------------
GH_TOKEN=sekrit-token GITHUB_TOKEN=sekrit-token2 run red "$S" --marker "$MARKER" --passage-file "$W/passage" -- sh tests/run.sh
eq "the red: exit 0" 0 "$RC"
has "the red: recorded" "recorded: red at base $BASE" "$OUT"
REC=$(record "$S")
eq "the red's base is impl_base" "$BASE" "$(printf '%s' "$REC" | jq -r .red.base)"
eq "the reproducing test with its blob id" "tests/empty_name_test.sh $TEST_BLOB" "$(printf '%s' "$REC" | jq -r '.red.tests[] | "\(.path) \(.blob)"')"
eq "the harness file with its blob at the base" "tests/run.sh $(git rev-parse "$BASE:tests/run.sh")" "$(printf '%s' "$REC" | jq -r '.red.harness[] | "\(.path) \(.blob)"')"
eq "the exit is non-zero" 1 "$(printf '%s' "$REC" | jq -r .red.exit)"
has "the output tail holds the marker" "$MARKER" "$(printf '%s' "$REC" | jq -r .red.output_tail)"
has "the marker context holds the marker" "$MARKER" "$(printf '%s' "$REC" | jq -r .red.marker_context)"
eq "the command is recorded as argv" '["sh","tests/run.sh"]' "$(printf '%s' "$REC" | jq -c .red.command)"
eq "the passage, marker and report source" "$MARKER|issue" "$(printf '%s' "$REC" | jq -r '"\(.red.marker)|\(.red.report_source)"')"
has "the passage is recorded" "instead of" "$(printf '%s' "$REC" | jq -r .red.passage)"
eq "the tail is at most 4096 bytes" true "$(printf '%s' "$REC" | jq '.red.output_tail | length <= 4096')"
eq "the temporary worktree is gone" 1 "$(git worktree list | grep -c .)"

run red "$S" --marker "$MARKER" --passage-file "$W/passage" -- sh -c 'env; echo "error: name required"; exit 1'
hasnt "GH_TOKEN doesn't reach the command" "sekrit" "$(record "$S" | jq -r .red.output_tail)"

# The correcting change is committed already: the red still runs on the base.
cat > greet.sh <<'EOF'
#!/bin/sh
[ -n "$1" ] || { echo "error: name required"; exit 1; }
echo "Hello, $1!"
EOF
git commit -q -am "fix: refuse an empty name"
run red "$S" --marker "$MARKER" --passage-file "$W/passage" -- sh tests/run.sh
eq "with the fix committed, the red still fails and is recorded" 0 "$RC"
eq "with the fix committed, the red's base is still impl_base" "$BASE" "$(record "$S" | jq -r .red.base)"
eq "a new red drops the green" null "$(record "$S" | jq -c .green)"

run check-red "$S"
eq "check-red with a red: exit 0" 0 "$RC"

# --- symlinks ----------------------------------------------------------------------
git checkout -q -b links
ln -s empty_name_test.sh tests/link_test.sh
git add tests/link_test.sh
git commit -q -m link
run red "$S" --marker "$MARKER" --passage-file "$W/passage" -- sh tests/run.sh
has "a symlinked test file: refused" "is a symlink" "$OUT"
git checkout -q main

# A directory that is a symlink at the base, made a real directory by the unit:
# copying its test there would write through the link, outside the worktree.
mkdir -p "$W/outside"
git checkout -q -b linkdir "$BASE"
ln -s "$W/outside" evil
git add evil
git commit -q -m "a link at the base"
new_session sl
git rev-parse HEAD > "$STORE/sl/impl_base"
git rm -q evil
mkdir evil
cp tests/greet_test.sh evil/x_test.sh
git add evil
git commit -q -m "the unit makes it a directory"
run red sl --marker "$MARKER" --passage-file "$W/passage" -- sh tests/run.sh
has "a test under a directory that is a symlink at the base: refused" "is a symlink at the base" "$OUT"
[ -e "$W/outside/x_test.sh" ] && bad "nothing is written through the link" "found $W/outside/x_test.sh" \
    || ok "nothing is written through the link"
git checkout -q main

# --- green and check-green ---------------------------------------------------------
new_session g1
git checkout -q -b green-test "$BASE"
git checkout -q main -- tests/empty_name_test.sh
git commit -q -m "test: reproduce"
run red g1 --marker "$MARKER" --passage-file "$W/passage" -- sh tests/run.sh
eq "a red on the green branch" 0 "$RC"
run check-green g1
eq "check-green with no green: exit 1" 1 "$RC"
has "check-green with no green: says to run green" "no green is recorded" "$OUT"
has "check-green holds with finding red-first/no-green" '"rule_id":"red-first/no-green"' "$OUT"
run green g1
eq "a green before the fix: exit 1" 1 "$RC"
has "a green before the fix: failed" "failed: the check exited 1 at HEAD" "$OUT"
eq "a failing green is recorded" 1 "$(record g1 | jq -r .green.exit)"
run check-green g1
has "check-green after a failed green: holds naming the exit" "exited 1" "$OUT"
git checkout -q main -- greet.sh
git commit -q -m "fix: refuse an empty name"
run check-green g1
has "check-green with a green at an older head: holds" "not HEAD" "$OUT"
run green g1
eq "a green after the fix: exit 0" 0 "$RC"
eq "the green's head is HEAD" "$(git rev-parse HEAD)" "$(record g1 | jq -r .green.head)"
run check-green g1
eq "check-green with a green at HEAD: exit 0" 0 "$RC"
git commit -q --allow-empty -m later
run check-green g1
eq "a commit after the green: check-green holds again" 1 "$RC"
git checkout -q main

new_session c1 change
run check-green c1
eq "check-green for a change: exit 0" 0 "$RC"
run check-red c1
eq "check-red for a change: exit 0" 0 "$RC"

# --- observations ------------------------------------------------------------------
new_session o1
printf '## Produced\nran it by hand\n\n## Seen\nerror: name required was not printed\n' > "$W/obs-short.md"
run observe o1 --phase before --file "$W/obs-short.md"
eq "a before-observation missing sections: exit 1" 1 "$RC"
has "a before-observation missing sections: named" "the observation is missing: Environment, Why no check, Passage, Marker" "$OUT"
cat > "$W/obs-before.md" <<EOF
## Produced
Typed ./greet.sh '' at an interactive terminal.

## Environment
macOS 15, /bin/sh.

## Seen
It printed Hello, ! where the report expects error: name required.

## Why no check
Stands in for a terminal-only failure in this test.

## Passage
Running \`./greet.sh ''\` prints \`Hello, !\` instead of \`error: name required\`

## Marker
error: name required
EOF
run observe o1 --phase after --file "$W/obs-before.md"
has "an after-observation with no before: refused" "needs a before-observation first" "$OUT"
run observe o1 --phase before --file "$W/obs-before.md"
eq "a complete before-observation: exit 0" 0 "$RC"
eq "the before-observation's digest is its blob id" "$(git hash-object "$W/obs-before.md")" "$(record o1 | jq -r .observations.before.digest)"
run check-red o1
eq "check-red with a before-observation: exit 0" 0 "$RC"
run check-green o1
has "check-green with only a before-observation: holds" "no after-observation" "$OUT"
printf '## Produced\nTyped it again.\n\n## Environment\nmacOS 15.\n\n## Seen\nerror: name required, as expected.\n' > "$W/obs-after.md"
run observe o1 --phase after --file "$W/obs-after.md"
eq "an after-observation: exit 0" 0 "$RC"
run check-green o1
eq "an observation pair: check-green exit 1" 1 "$RC"
has "an observation pair: a refused line saying observations wait for acceptance" "refused: observations wait for acceptance" "$OUT"
has "an observation pair: finding red-first/no-green" '"rule_id":"red-first/no-green"' "$OUT"
# A minted seat's acceptance of both digests, as test-change.sh writes it.
jq -nc --arg wt "$R" --arg base "$BASE" '{event: "header", author: "agent:o1", impl_base: $base, worktree: $wt, person_required: false}' > "$STORE/o1/test_change_ledger.jsonl"
jq -nc '{event: "seat", identity: "agent:o1/accept-1"}' >> "$STORE/o1/test_change_ledger.jsonl"
jq -c '{event: "accept", identity: "agent:o1/accept-1", kind: "agent", authority: "reviewer",
        files: [{path: "observation:before", digest: .observations.before.digest},
                {path: "observation:after", digest: .observations.after.digest}]}' "$STORE/o1/red_first.json" >> "$STORE/o1/test_change_ledger.jsonl"
run check-green o1
eq "an accepted observation pair: check-green exit 0" 0 "$RC"
has "an accepted observation pair: passes" "pass: the observation pair has a live acceptance" "$OUT"

# --- usage -------------------------------------------------------------------------
run red "$S" --passage-file "$W/passage" -- true
eq "red without --marker: exit 64" 64 "$RC"
run red "$S" --marker "$MARKER" --passage-file "$W/passage"
eq "red without a command: exit 64" 64 "$RC"
run observe o1 --phase during --file "$W/obs-after.md"
eq "observe with a bad phase: exit 64" 64 "$RC"
run green "bad name"
eq "a bad session name: exit 64" 64 "$RC"
run frobnicate "$S"
eq "an unknown subcommand: exit 64" 64 "$RC"

echo
echo "red-first: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
