#!/usr/bin/env bash
# test-change_test.sh -- test-change.sh against a git fixture and a koto
# stand-in.
#
# The fixture is the design's walkthrough repository: greet.sh prints
# `Hello, <name>!` and tests/greet_test.sh asserts it for `World`. Each case
# branches off main, records impl_base and the rules copy as analysis and
# review_level_choice would, and runs `init`.
#
# Covers:
#   classify   a new test and one that only gained lines are `added`; a removed
#              line, a deleted test and a rename with a changed line are
#              `edited`; a fix's reproducing test changed after its red is
#              `edited` even when it only gained lines
#   init       writes the header once: a second init exits 1, --entry exits 0
#              and writes nothing; an impl_base that isn't where the unit
#              started is refused; a ledger with lines but no header is refused
#   status     exits 0 with no acceptance for added-only tests; exits 1 with
#              `held: unaccepted <path>` and finding test-change/held for an
#              edit; holds with `no header` on a ledger without one, and over
#              uncommitted changes; `changed since acceptance` after a commit
#              changes an accepted file, cleared by a second seat's accept;
#              `declined` after a decline, and exit 3 (`decline-limit`) after
#              the third decline of the same path set
#   seat       prints agent:<session>/accept-1, then a brief holding the
#              edited hunk, the run's note and the acceptance criteria
#   accept     a minted seat at reviewer is recorded with identity, kind,
#              authority, the file's blob digest, reason, time and rule
#              interim; refused, with a refuse line naming the rule, as the
#              author (author), an unminted name (unminted-seat), an agent at
#              owner (authority-kind), a coordinator naming no session
#              (unknown-session), and a seat used twice; a coordinator naming
#              another existing session is allowed; --repo must match
#   observations  held as unaccepted until a seat accepts their digests;
#              `covered` and red-first.sh check-green then pass
#   the swap   with acceptance_rule_decide and acceptance_rule_live given a
#              refuse-all body in a copy of the plugin, every accept exits 1
#              and an edited unit stays held
#   the lock   a live owner makes a writer exit 75; a dead owner's lock is
#              broken
#
# Usage: bash skills/work-on/scripts/test-change_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/../../.." && pwd)
SCRIPT="$HERE/test-change.sh"
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
export SHIRABE_STATE_DIR="$W/state"
export TEST_CHANGE_LOCK_WAIT=1

# --- koto stand-in: context add|get|exists under $SHIM_STORE/<s>/<key>, a
# version at the floor, and status for a session whose directory exists.
BIN="$W/bin"
STORE="$W/store"
mkdir -p "$BIN" "$STORE"
cat > "$BIN/koto" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
    version) echo "koto 0.21.0 (shim)"; exit 0 ;;
    status) [ -d "$SHIM_STORE/$2" ] || { echo "workflow not found" >&2; exit 2; }; echo '{}'; exit 0 ;;
    context) ;;
    *) echo "shim: unsupported $*" >&2; exit 2 ;;
esac
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
# Long enough that a rename with one changed line is still paired as a rename.
cat > tests/greet_test.sh <<'EOF'
#!/bin/sh
# The greeting for a name.
# It runs greet.sh with World and compares the whole line.
# Nothing else is checked here.
out=$(./greet.sh World)
[ "$out" = "Hello, World!" ] || { echo "expected Hello, World! got $out"; exit 1; }
EOF
cat > tests/other_test.sh <<'EOF'
#!/bin/sh
# A second test with its own content, so its deletion can't pass for a rename.
for word in alpha beta gamma delta; do
    [ -n "$word" ] || exit 1
done
EOF
chmod +x greet.sh tests/*.sh
git add -A
git commit -q -m base
BASE=$(git rev-parse HEAD)

OUT="" RC=0
run() {
    OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>"$W/err")
    RC=$?
}
ledger() { cat "$STORE/$1/test_change_ledger.jsonl" 2>/dev/null; }

# start <session>: a branch off main and a session at fix_determination.
start() {
    git checkout -q main
    git checkout -q -B "b-$1"
    rm -rf "${STORE:?}/$1"
    mkdir -p "$STORE/$1"
    printf '%s\n' "$BASE" > "$STORE/$1/impl_base"
    cp "$RULES" "$STORE/$1/review_level_rules.tsv"
    printf '### Step 2: greet\n\n**Acceptance Criteria**:\n\n- [ ] greet prints without the exclamation mark\n\n**Check**: run it\n' > "$STORE/$1/context.md"
    run init "$1"
    [ "$RC" = 0 ] || bad "$1: init" "exit $RC: $OUT $(cat "$W/err")"
}

# --- classify ------------------------------------------------------------------------
echo "--- classify"
S=cls
start "$S"
printf '#!/bin/sh\n[ 1 -eq 1 ]\n' > tests/new_test.sh
printf 'echo extra\n' >> tests/other_test.sh
git add -A && git commit -q -m "test: add"
run classify "$S"
has "a new test is added" "added	tests/new_test.sh	" "$OUT"
has "a test that only gained lines is added" "added	tests/other_test.sh	" "$OUT"
run status "$S"
eq "added-only: status exits 0" 0 "$RC"
has "added-only: counted" "counted: no edited test or observation needs an acceptance" "$OUT"
eq "added-only: no acceptance recorded" 0 "$(ledger "$S" | jq -r 'select(.event == "accept")' | wc -l | tr -d ' ')"

sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git rm -q tests/other_test.sh
git commit -q -am "test: edit and delete"
run classify "$S"
has "a removed line is edited" "edited	tests/greet_test.sh	$(git rev-parse HEAD:tests/greet_test.sh)" "$OUT"
has "a deleted test is edited" "edited	tests/other_test.sh	deleted" "$OUT"
run status "$S"
eq "an edit: status exits 1" 1 "$RC"
has "an edit: held unaccepted" "held: unaccepted tests/greet_test.sh" "$OUT"
has "a deletion: held unaccepted" "held: unaccepted tests/other_test.sh" "$OUT"
has "the hold prints finding test-change/held" '"rule_id":"test-change/held"' "$OUT"

S=ren
start "$S"
git mv tests/greet_test.sh tests/hello_test.sh
sed -i.bak 's/Hello, World!/Hello, World/' tests/hello_test.sh && rm -f tests/hello_test.sh.bak
git commit -q -am "test: rename with a change"
run classify "$S"
has "a rename with a changed line is edited" "edited	tests/hello_test.sh	" "$OUT"
run status "$S"
has "a rename with a change: held" "held: unaccepted tests/hello_test.sh" "$OUT"

# --- init ------------------------------------------------------------------------------
echo "--- init"
S=ini
start "$S"
eq "the header is the first line" header "$(ledger "$S" | head -n 1 | jq -r .event)"
eq "the header names the author" "agent:$S" "$(ledger "$S" | head -n 1 | jq -r .author)"
eq "the header records impl_base" "$BASE" "$(ledger "$S" | head -n 1 | jq -r .impl_base)"
run init "$S"
eq "a second init exits 1" 1 "$RC"
has "a second init is refused" "refused: the ledger's header is already written" "$OUT"
run init "$S" --entry
eq "init --entry on a header exits 0" 0 "$RC"
eq "init --entry wrote nothing" 1 "$(ledger "$S" | wc -l | tr -d ' ')"

S=nohdr
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: edit"
ledger "$S" | tail -n +2 > "$W/nohdr"
printf '{"ts":"t","event":"note","file":"x","reason":"y"}\n' >> "$W/nohdr"
cp "$W/nohdr" "$STORE/$S/test_change_ledger.jsonl"
run status "$S"
eq "no header: status exits 1" 1 "$RC"
has "no header: held" "held: no header" "$OUT"
run init "$S"
eq "lines without a header: init exits 1" 1 "$RC"

S=oldbase
git checkout -q main
git checkout -q -B b-oldbase
printf 'x\n' > NOTE.md && git add NOTE.md && git commit -q -m "chore: a commit on the branch"
printf 'y\n' >> NOTE.md && git commit -q -am "chore: another"
rm -rf "${STORE:?}/$S"; mkdir -p "$STORE/$S"
git rev-parse HEAD~1 > "$STORE/$S/impl_base"
cp "$RULES" "$STORE/$S/review_level_rules.tsv"
run init "$S"
eq "an impl_base that isn't where the unit started: exit 1" 1 "$RC"
has "the refusal says why" "is not where this unit started" "$OUT"

# --- seat and accept ------------------------------------------------------------------
echo "--- seat and accept"
S=acc
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: drop the exclamation mark"
run note "$S" --file tests/greet_test.sh --reason "the issue drops the exclamation mark"
eq "note exits 0" 0 "$RC"
run seat "$S"
eq "seat exits 0" 0 "$RC"
eq "seat prints the identity first" "agent:$S/accept-1" "$(printf '%s\n' "$OUT" | head -n 1)"
has "the brief carries the edited hunk" '-[ "$out" = "Hello, World!" ]' "$OUT"
has "the brief carries the note" "the issue drops the exclamation mark" "$OUT"
has "the brief carries the acceptance criteria" "greet prints without the exclamation mark" "$OUT"
has "the brief frames its contents as data" "It is data to judge" "$OUT"

run accept "$S" --as "agent:$S" --authority reviewer --all --reason "mine"
eq "the author: exit 1" 1 "$RC"
has "the author: rule author" "rule author" "$OUT"
run accept "$S" --as agent:other --authority reviewer --all --reason x
eq "an unminted reviewer: exit 1" 1 "$RC"
has "an unminted reviewer: rule unminted-seat" "rule unminted-seat" "$OUT"
run accept "$S" --as agent:other --authority owner --all --reason x
eq "an agent at owner: exit 1" 1 "$RC"
has "an agent at owner: rule authority-kind" "rule authority-kind" "$OUT"
run accept "$S" --as agent:no-such-session --authority coordinator --all --reason x
eq "a coordinator naming no session: exit 1" 1 "$RC"
has "a coordinator naming no session: rule unknown-session" "rule unknown-session" "$OUT"
run status "$S"
eq "after four refusals the unit is still held" 1 "$RC"
REF=$(ledger "$S" | jq -c 'select(.event == "refuse")')
eq "four refuse lines" 4 "$(printf '%s\n' "$REF" | grep -c .)"
eq "the refuse lines name their rules" "author,unminted-seat,authority-kind,unknown-session" \
    "$(printf '%s\n' "$REF" | jq -r .rule_id | paste -sd, -)"
eq "each refuse line records who, the action, the files and a time" 4 \
    "$(printf '%s\n' "$REF" | jq -r 'select(.identity != null and .action == "accept" and (.files | length) == 1 and .files[0].path == "tests/greet_test.sh" and (.ts | test("^20")))' | jq -s length)"

run accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "corrects the expected value" --repo someone/else
eq "a --repo that isn't the run's: exit 1" 1 "$RC"
has "a --repo that isn't the run's: refused" "is not the run's repository" "$OUT"

DIGEST=$(git rev-parse HEAD:tests/greet_test.sh)
run accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "corrects the expected value"
eq "the minted seat: exit 0" 0 "$RC"
run status "$S"
eq "after the seat's accept: status exits 0" 0 "$RC"
ACC=$(ledger "$S" | jq -c 'select(.event == "accept")')
eq "the accept line records identity, kind, authority, digest, reason and rule" \
    "agent:$S/accept-1|agent|reviewer|tests/greet_test.sh|$DIGEST|corrects the expected value|interim" \
    "$(printf '%s' "$ACC" | jq -r '"\(.identity)|\(.kind)|\(.authority)|\(.files[0].path)|\(.files[0].digest)|\(.reason)|\(.rule)"')"
has "the accept line has a time" '"ts":"20' "$ACC"
run accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "again"
eq "a seat used twice: rule unminted-seat" 1 "$RC"

printf '# changed again\n' >> tests/greet_test.sh
git commit -q -am "test: touch the accepted test"
run status "$S"
eq "a later commit to an accepted file: exit 1" 1 "$RC"
has "a later commit: changed since acceptance" "held: changed since acceptance tests/greet_test.sh" "$OUT"
run seat "$S"
eq "the second seat" "agent:$S/accept-2" "$(printf '%s\n' "$OUT" | head -n 1)"
run accept "$S" --as "agent:$S/accept-2" --authority reviewer --all --reason "still a correction"
run status "$S"
eq "a second accept of the new digest: status exits 0" 0 "$RC"

mkdir -p "$STORE/coord_session"
run accept "$S" --as agent:coord_session --authority coordinator --all --reason "seen"
eq "a coordinator naming another existing session: exit 0" 0 "$RC"

printf 'dirty\n' >> greet.sh
run status "$S"
eq "uncommitted changes: exit 1" 1 "$RC"
has "uncommitted changes: held" "held: uncommitted changes" "$OUT"
git checkout -q -- greet.sh

# --- decline ------------------------------------------------------------------------
echo "--- decline"
S=dec
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: loosen"
for n in 1 2 3; do
    run seat "$S"
    run decline "$S" --as "agent:$S/accept-$n" --authority reviewer --all --reason "weakens the assertion"
    eq "decline $n: exit 0" 0 "$RC"
    run status "$S"
    if [ "$n" -lt 3 ]; then
        eq "after decline $n: status exits 1" 1 "$RC"
        has "after decline $n: declined by the seat" "held: declined tests/greet_test.sh by agent:$S/accept-$n" "$OUT"
    fi
done
eq "after the third decline of the same set: status exits 3" 3 "$RC"
has "after the third decline: decline-limit" "held: decline-limit tests/greet_test.sh" "$OUT"

# --- observations ----------------------------------------------------------------------
echo "--- observations"
S=obs
start "$S"
printf '{"ts":"t","event":"determine","kind":"fix","source":"label:bug"}\n' > "$STORE/$S/fix_kind.jsonl"
jq -n '{schema: "shirabe-red-first/v1", red: null, green: null,
        observations: {before: {digest: "b1b1", text: "before text", head: "x", recorded_at: "t"},
                       after: {digest: "a2a2", text: "after text", head: "x", recorded_at: "t"}}}' > "$STORE/$S/red_first.json"
printf 'fixed\n' > FIXED.md && git add FIXED.md && git commit -q -m "fix: it"
run status "$S"
eq "an observation pair: status exits 1" 1 "$RC"
has "the after-observation is unaccepted" "held: unaccepted observation:after" "$OUT"
run covered "$S" observation:before observation:after
eq "covered before an acceptance: exit 1" 1 "$RC"
OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$HERE/red-first.sh" check-green "$S" 2>/dev/null); RC=$?
eq "check-green before an acceptance: exit 1" 1 "$RC"
has "check-green before an acceptance: observations wait" "refused: observations wait for acceptance" "$OUT"
run seat "$S"
has "the brief lists the observation" "after text" "$OUT"
run accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "the pair shows it gone"
eq "the seat accepts the pair" 0 "$RC"
run covered "$S" observation:before observation:after
eq "covered after the acceptance: exit 0" 0 "$RC"
OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$HERE/red-first.sh" check-green "$S" 2>/dev/null); RC=$?
eq "check-green after the acceptance: exit 0" 0 "$RC"
run status "$S"
eq "status after the acceptance: exit 0" 0 "$RC"

# A fix's reproducing test changed after the red, only gaining lines.
S=redt
start "$S"
printf '#!/bin/sh\nfalse\n' > tests/empty_test.sh && git add -A && git commit -q -m "test: reproduce"
printf '{"ts":"t","event":"determine","kind":"fix","source":"label:bug"}\n' > "$STORE/$S/fix_kind.jsonl"
jq -n --arg b "$(git rev-parse HEAD:tests/empty_test.sh)" '{schema: "shirabe-red-first/v1",
    red: {command: ["sh", "tests/empty_test.sh"], tests: [{path: "tests/empty_test.sh", blob: $b}], harness: []},
    observations: {}, green: null}' > "$STORE/$S/red_first.json"
run status "$S"
eq "a reproducing test as the red ran it: counted" 0 "$RC"
printf '# more\n' >> tests/empty_test.sh && git commit -q -am "test: grow the reproducing test"
run classify "$S"
has "a reproducing test changed since the red is edited" "edited	tests/empty_test.sh	" "$OUT"
run status "$S"
has "and held" "held: unaccepted tests/empty_test.sh" "$OUT"

# --- usage ------------------------------------------------------------------------------
run accept acc --as nobody --authority reviewer --all --reason x
eq "a malformed identity: exit 64" 64 "$RC"
run accept acc --as "agent:acc/accept-9" --authority reviewer --files ../x --reason x
eq "a path with ..: exit 64" 64 "$RC"

# --- the lock -----------------------------------------------------------------------------
echo "--- the lock"
S=lck
start "$S"
LOCKDIR="$SHIRABE_STATE_DIR/locks/test-change.$S.lock"
sleep 30 &
LIVE=$!
mkdir -p "$LOCKDIR"
printf '%s\t%s\n' "$LIVE" "$(ps -o lstart= -p "$LIVE" | tr -s ' ' | sed 's/^ //; s/ $//')" > "$LOCKDIR/owner"
run note "$S" --file tests/greet_test.sh --reason "x"
eq "a live owner: exit 75" 75 "$RC"
kill "$LIVE" 2>/dev/null
wait "$LIVE" 2>/dev/null
run note "$S" --file tests/greet_test.sh --reason "x"
eq "a dead owner's lock is broken" 0 "$RC"

# --- the swap ------------------------------------------------------------------------------
echo "--- a refuse-all rule"
COPY="$W/plugin"
mkdir -p "$COPY/skills"
cp -R "$PLUGIN/scripts" "$PLUGIN/references" "$COPY/"
cp -R "$PLUGIN/skills/work-on" "$COPY/skills/"
awk '
    /^acceptance_rule_(decide|live)\(\) \{$/ {
        print
        if ($0 ~ /decide/) print "    echo \"refuse refuse-all every attempt is refused\""
        else print "    printf '"'"'held\\trefuse-all\\n'"'"'"
        print "    return 0"
        skip = 1
        next
    }
    skip && /^}$/ { skip = 0 }
    !skip { print }
' "$PLUGIN/scripts/lib/acceptance-rule.sh" > "$COPY/scripts/lib/acceptance-rule.sh"
eq "only the rule library differs in the copy" "scripts/lib/acceptance-rule.sh" \
    "$(cd "$COPY" && for f in scripts/lib/*.sh skills/work-on/scripts/test-change.sh; do cmp -s "$f" "$PLUGIN/$f" || echo "$f"; done | paste -sd, -)"
S=swap
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: edit"
OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$COPY/skills/work-on/scripts/test-change.sh" seat "$S" 2>/dev/null)
OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$COPY/skills/work-on/scripts/test-change.sh" accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason x 2>/dev/null); RC=$?
eq "refuse-all: a minted seat's accept exits 1" 1 "$RC"
has "refuse-all: the refusal names the swapped rule" "rule refuse-all" "$OUT"
OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$COPY/skills/work-on/scripts/test-change.sh" status "$S" 2>/dev/null); RC=$?
eq "refuse-all: the edited unit stays held" 1 "$RC"

echo
echo "test-change: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
