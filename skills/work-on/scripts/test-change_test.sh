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
#   the person-required declaration
#              `## Test Change Acceptance: person` in CLAUDE.md at impl_base or
#              at the remote default branch's tip makes the header record
#              person_required true with its source; a CLAUDE.local.md saying
#              agent leaves it true, one saying person makes it true, an
#              unknown value reads as person and is named; nothing declared is
#              false
#   a person-required repository
#              an edit holds and status prints the exact command a person
#              runs; seat refuses to commission a seat; an agent's accept is
#              refused person-required and a person's without a terminal
#              no-terminal, both recorded; under a pseudo-terminal (python3)
#              a wrong code is refused no-terminal, the right one counts the
#              unit at owner with the hunk and digest shown and a tag on the
#              line, and a line edited after tagging stops counting
#   overrule   refused for the author (author), a coordinator naming no
#              session (unknown-session), a seat at the same authority
#              (not-higher) and an acceptance id the ledger lacks; a
#              coordinator's overrule holds the unit `overruled`; a later
#              acceptance below coordinator leaves it held, one at
#              coordinator counts it again; record prints the kind, the test
#              files, every acceptance, refusal and overrule, and the state
#   a coordinator whose session is gone
#              its acceptance counts while the session exists; once the
#              session is cleaned up status exits 1 and the unit is held,
#              though the stored line still claims session_exists; a
#              coordinator's overrule, or decline, still holds the unit after
#              its session is cleaned up
#   record of a fix
#              the fix source, the red with its marker, the green, the
#              reproducing test as added, and the state
#   a refused read
#              a context read koto refuses fails status and init with 66, the
#              ledger untouched, never reading as an absent key
#   nothing reaches a pull request
#              gh is a stand-in that logs every call, and the log stays
#              empty; the script holds no gh pr edit or comment and has no
#              render subcommand
#   a moved work tree
#              the header's work tree gone: from a clone of the same
#              repository whose HEAD holds impl_base, status gates as it did
#              at the old path and appends one relocate line naming both
#              paths, a second status none, and seat and accept follow the
#              relocated tree; from a clone whose origin is another
#              repository, or one whose HEAD lacks impl_base, status still
#              exits 2 with the gone work tree's message and writes nothing;
#              covered and record write nothing, record never re-roots from
#              the directory it runs in, and once the move is recorded it
#              shows the relocation and reads the relocated tree from
#              anywhere
#
# Usage: bash skills/work-on/scripts/test-change_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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
ktg_on_exit 'rm -rf "$W"'
export HOME="$W/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
export SHIRABE_STATE_DIR="$W/state"
export TEST_CHANGE_LOCK_WAIT=1

# --- koto stand-in: context add|get|exists under $SHIM_STORE/<s>/<key>, a
# version at the floor, and status for a session whose directory exists. The
# version is read from assert-koto-floor.sh, so raising the floor doesn't
# leave the stand-in below it.
BIN="$W/bin"
STORE="$W/store"
mkdir -p "$BIN" "$STORE"
SHIM_FLOOR=$(env -u KOTO_FLOOR bash "$PLUGIN/scripts/assert-koto-floor.sh" --print-floor 2>"$W/floor.err")
[ -n "$SHIM_FLOOR" ] || { echo "FAIL: assert-koto-floor.sh --print-floor printed no floor: $(head -c 400 "$W/floor.err")"; exit 1; }
# SHIM_REFUSE=<s> refuses every context call on <s>, and SHIM_REFUSE_KEY=<key>
# every `context exists` of <key>, the way koto refuses a session bound to
# another workspace: the refusal on stdout, exit 2 (or SHIM_REFUSE_RC).
cat > "$BIN/koto" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
    version) echo "koto $SHIM_FLOOR (shim)"; exit 0 ;;
    status) [ -d "$SHIM_STORE/$2" ] || { echo "workflow not found" >&2; exit 2; }; echo '{}'; exit 0 ;;
    context) ;;
    *) echo "shim: unsupported $*" >&2; exit 2 ;;
esac
if [ "${SHIM_REFUSE:-}" = "$3" ] || { [ "$2" = exists ] && [ "${SHIM_REFUSE_KEY:-}" = "$4" ]; }; then
    printf '{"error":{"code":"session_bound_elsewhere","message":"session %s is bound to another workspace"}}\n' "$3"
    exit "${SHIM_REFUSE_RC:-2}"
fi
f="$SHIM_STORE/$3/$4"
case "$2" in
    add) mkdir -p "$SHIM_STORE/$3"; cat > "$f" ;;
    get) [ -f "$f" ] || exit 1; cat "$f" ;;
    exists) [ -f "$f" ] ;;
    remove) rm -f "$f" ;;
esac
SHIM
chmod +x "$BIN/koto"
export SHIM_STORE="$STORE" SHIM_FLOOR

# --- gh stand-in: logs every call and fails. Nothing test-change.sh does may
# reach GitHub, so the log must stay empty to the end.
export GH_LOG="$W/gh.calls"
: > "$GH_LOG"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
exit 1
SHIM
chmod +x "$BIN/gh"

# --- a pseudo-terminal for a person's attempt: runs the command under a pty,
# types back the code it prints (right) or another (wrong), and prints what the
# terminal showed. Exit: the command's.
PTY="$W/term_drive.py"
cat > "$PTY" <<'PY'
import os, pty, re, select, sys, time
mode, argv = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
out, sent, deadline = b"", False, time.time() + 60
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if fd not in r:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
    if not sent:
        m = re.search(rb"Type the code ([0-9a-f]{6})", out)
        if m:
            os.write(fd, (m.group(1) if mode == "right" else b"zzzzzz") + b"\n")
            sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace"))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 99)
PY
HAVE_PTY=0
command -v python3 >/dev/null 2>&1 && python3 -c 'import pty' 2>/dev/null && HAVE_PTY=1

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
eq "seat prints the identity first" "agent:$S/accept-1" "${OUT%%$'\n'*}"
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
eq "the second seat" "agent:$S/accept-2" "${OUT%%$'\n'*}"
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

# --- the person-required declaration -----------------------------------------------------
echo "--- the person-required declaration"

# start_here <session> [<init args>...]: a session whose impl_base is HEAD.
start_here() {
    local s="$1"
    shift
    rm -rf "${STORE:?}/$s"
    mkdir -p "$STORE/$s"
    git rev-parse HEAD > "$STORE/$s/impl_base"
    cp "$RULES" "$STORE/$s/review_level_rules.tsv"
    printf '## Acceptance Criteria\n\n- [ ] the greeting\n' > "$STORE/$s/context.md"
    run init "$s" "$@"
    [ "$RC" = 0 ] || bad "$s: init" "exit $RC: $OUT $(cat "$W/err")"
}
hdr_of() { ledger "$1" | head -n 1 | jq -r "$2"; }

git checkout -q main
git checkout -q -B b-undeclared
start_here und
eq "nothing declared: person_required false" false "$(hdr_of und .person_required)"
has "nothing declared: the source says so" "not declared" "$(hdr_of und .person_required_source)"

git checkout -q -B b-person main
printf '# greet\n\n```\n## Test Change Acceptance: agent\n```\n\n## Test Change Acceptance: person\n' > CLAUDE.md
git add CLAUDE.md && git commit -q -m "docs: require a person"
PERSON_BASE=$(git rev-parse HEAD)
start_here dp
eq "person at impl_base: person_required true" true "$(hdr_of dp .person_required)"
has "person at impl_base: the source names it" "CLAUDE.md at impl_base: person" "$(hdr_of dp .person_required_source)"
printf '## Test Change Acceptance: agent\n' > CLAUDE.local.md
start_here dpl
eq "a CLAUDE.local.md saying agent leaves it true" true "$(hdr_of dpl .person_required)"
has "the local file is named in the source" "CLAUDE.local.md: agent" "$(hdr_of dpl .person_required_source)"
rm -f CLAUDE.local.md

git checkout -q -B b-local main
printf '## Test Change Acceptance: person\n' > CLAUDE.local.md
start_here dlocal
eq "a CLAUDE.local.md saying person tightens to true" true "$(hdr_of dlocal .person_required)"
rm -f CLAUDE.local.md

git checkout -q -B b-unknown main
printf '## Test Change Acceptance: humans\n' > CLAUDE.md
git add CLAUDE.md && git commit -q -m "docs: an unknown value"
start_here dunk
eq "an unknown value reads as person" true "$(hdr_of dunk .person_required)"
has "the unknown value is named in the record" "[humans] is neither person nor agent, read as person" "$(hdr_of dunk .person_required_source)"

git checkout -q -B b-tip main
git update-ref refs/remotes/origin/main "$PERSON_BASE"
start_here dtip
eq "person at the remote default branch's tip: true" true "$(hdr_of dtip .person_required)"
has "the tip is named in the source" "CLAUDE.md at the remote default branch: person" "$(hdr_of dtip .person_required_source)"
git update-ref -d refs/remotes/origin/main


# --- a person-required repository ----------------------------------------------------------
echo "--- a person-required repository"
git checkout -q -B b-pr "$PERSON_BASE"
S=preq
start_here "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: drop the mark"
run status "$S"
eq "person-required: an edit holds" 1 "$RC"
has "the hold names the file" "held: unaccepted tests/greet_test.sh" "$OUT"
has "the hold prints the exact command a person runs" \
    "\"$HERE/test-change.sh\" accept $S --as person:<your-name> --authority owner --files tests/greet_test.sh --reason" "$OUT"
run seat "$S"
eq "person-required: seat exits 1" 1 "$RC"
has "person-required: seat refuses to commission a seat" "refused: this repository requires a person" "$OUT"
eq "person-required: no seat was minted" 0 "$(ledger "$S" | jq -r 'select(.event == "seat")' | wc -l | tr -d ' ')"
run accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "x"
eq "person-required: an agent's accept exits 1" 1 "$RC"
has "person-required: rule person-required" "rule person-required" "$OUT"
run accept "$S" --as person:pat --authority owner --all --reason "test was wrong"
eq "a person without a terminal: exit 1" 1 "$RC"
has "a person without a terminal: rule no-terminal" "rule no-terminal" "$OUT"
eq "both refusals are recorded" "person-required,no-terminal" \
    "$(ledger "$S" | jq -r 'select(.event == "refuse") | .rule_id' | paste -sd, -)"
has "the no-terminal refusal says why" "not one terminal" "$(ledger "$S" | jq -r 'select(.rule_id == "no-terminal") | .detail')"

if [ "$HAVE_PTY" -eq 1 ]; then
    OUT=$(cd "$R" && PATH="$BIN:$PATH" python3 -I "$PTY" wrong bash "$SCRIPT" accept "$S" --as person:pat --authority owner --all --reason "test was wrong" 2>&1); RC=$?
    eq "a person at a terminal typing the wrong code: exit 1" 1 "$RC"
    has "the wrong code: rule no-terminal" "rule no-terminal" "$OUT"
    run status "$S"
    eq "after the wrong code the unit is still held" 1 "$RC"
    OUT=$(cd "$R" && PATH="$BIN:$PATH" python3 -I "$PTY" right bash "$SCRIPT" accept "$S" --as person:pat --authority owner --all --reason "test was wrong" 2>&1); RC=$?
    eq "a person at a terminal typing the code back: exit 0" 0 "$RC"
    has "the terminal showed the edited hunk" '-[ "$out" = "Hello, World!" ]' "$OUT"
    has "the terminal showed the file and its digest" "tests/greet_test.sh  $(git rev-parse HEAD:tests/greet_test.sh)" "$OUT"
    run status "$S"
    eq "the person's acceptance counts the unit" 0 "$RC"
    PL=$(ledger "$S" | jq -c 'select(.event == "accept")')
    eq "the person line records person:pat at owner" "person:pat|person|owner" "$(printf '%s' "$PL" | jq -r '"\(.identity)|\(.kind)|\(.authority)"')"
    has "the person line carries a tag" '"tag":"' "$PL"
    cp "$STORE/$S/test_change_ledger.jsonl" "$W/preq.ledger"
    jq -c 'if .event == "accept" then .reason = "edited by hand" else . end' "$W/preq.ledger" > "$STORE/$S/test_change_ledger.jsonl"
    run status "$S"
    eq "a person line whose tag no longer checks never counts" 1 "$RC"
    cp "$W/preq.ledger" "$STORE/$S/test_change_ledger.jsonl"
    run status "$S"
    eq "restored, the tagged line counts again" 0 "$RC"
else
    echo "SKIP: python3 with pty not found; the pseudo-terminal person cases did not run"
fi

# --- overrule ----------------------------------------------------------------------------------
echo "--- overrule"
git checkout -q main
S=ovr
start "$S"
printf '{"ts":"t","event":"determine","kind":"change","source":"none"}\n' > "$STORE/$S/fix_kind.jsonl"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: loosen"
run seat "$S"
run accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "looks right"
ACC_ID=$(ledger "$S" | jq -r 'select(.event == "accept") | .id')
run status "$S"
eq "accepted by the seat: counted" 0 "$RC"
mkdir -p "$STORE/coord_c"
run overrule "$S" --as "agent:$S" --authority coordinator --acceptance "$ACC_ID" --reason x
eq "the author overruling: exit 1" 1 "$RC"
has "the author overruling: rule author" "rule author" "$OUT"
run overrule "$S" --as agent:no-such-session --authority coordinator --acceptance "$ACC_ID" --reason x
eq "a coordinator naming no session: exit 1" 1 "$RC"
has "a coordinator naming no session: rule unknown-session" "rule unknown-session" "$OUT"
run seat "$S"
run overrule "$S" --as "agent:$S/accept-2" --authority reviewer --acceptance "$ACC_ID" --reason x
eq "an overrule at the same authority: exit 1" 1 "$RC"
has "an overrule at the same authority: rule not-higher" "rule not-higher" "$OUT"
run overrule "$S" --as agent:coord_c --authority coordinator --acceptance accept-999 --reason x
eq "an overrule naming no acceptance: exit 1" 1 "$RC"
has "an overrule naming no acceptance: refused without a line" "holds no acceptance accept-999" "$OUT"
run status "$S"
eq "after refused overrules the unit is still counted" 0 "$RC"
run overrule "$S" --as agent:coord_c --authority coordinator --acceptance "$ACC_ID" --reason "loosens the assertion"
eq "a coordinator overrules the reviewer's acceptance: exit 0" 0 "$RC"
run status "$S"
eq "overruled: status exits 1" 1 "$RC"
has "overruled: held with the reason" "held: overruled tests/greet_test.sh by agent:coord_c" "$OUT"
eq "the refusals name their rules" "author,unknown-session,not-higher" \
    "$(ledger "$S" | jq -r 'select(.event == "refuse" and .action == "overrule") | .rule_id' | paste -sd, -)"
OVR=$(ledger "$S" | jq -c 'select(.event == "overrule")')
eq "the overrule line names its target and its authority" "$ACC_ID|reviewer|coordinator|tests/greet_test.sh" \
    "$(printf '%s' "$OVR" | jq -r '"\(.target)|\(.target_authority)|\(.authority)|\(.files[0].path)"')"
run seat "$S"
run accept "$S" --as "agent:$S/accept-3" --authority reviewer --all --reason "fine by me"
eq "a seat's accept after the overrule is recorded" 0 "$RC"
run status "$S"
eq "an acceptance below the overruling's authority leaves it held" 1 "$RC"
has "still overruled" "held: overruled tests/greet_test.sh" "$OUT"
mkdir -p "$STORE/coord_d"
run accept "$S" --as agent:coord_d --authority coordinator --all --reason "the coordinator agrees after all"
run status "$S"
eq "an acceptance at the overruling's authority counts it again" 0 "$RC"

run record "$S"
eq "record exits 0" 0 "$RC"
has "record prints the unit's kind" "unit: change (not a fix)" "$OUT"
has "record prints each test file as edited or added" "edited tests/greet_test.sh" "$OUT"
has "record prints the acceptance" "accept $ACC_ID by agent:$S/accept-1 (agent at reviewer)" "$OUT"
has "record prints the overrule" "overrule overrule-" "$OUT"
has "record prints a refusal with its rule" "refuse: overrule refused, rule not-higher" "$OUT"
has "record prints the state" "state: counted" "$OUT"

# The coordinator's session, cleaned up: its lines stop counting at replay.
echo "--- a coordinator whose session is gone"
S=gone
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: loosen"
mkdir -p "$STORE/coord_g"
run accept "$S" --as agent:coord_g --authority coordinator --all --reason "accepted by the coordinator"
eq "a coordinator naming an existing session accepts: exit 0" 0 "$RC"
run status "$S"
eq "while its session exists the acceptance counts" 0 "$RC"
rm -rf "${STORE:?}/coord_g"
eq "the stored line still claims the session existed" true "$(ledger "$S" | jq -r 'select(.event == "accept") | .session_exists')"
run status "$S"
eq "once the coordinator's session is cleaned up, status exits 1" 1 "$RC"
has "and the unit stays held" "held: unaccepted tests/greet_test.sh" "$OUT"

# An overrule, or a decline, outlives its writer's session: only an acceptance
# stops counting when the session is gone.
S=gone_ovr
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: loosen"
run seat "$S"
run accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "looks right"
ACC_ID=$(ledger "$S" | jq -r 'select(.event == "accept") | .id')
mkdir -p "$STORE/coord_h"
run overrule "$S" --as agent:coord_h --authority coordinator --acceptance "$ACC_ID" --reason "loosens the assertion"
eq "a coordinator overrules the seat's acceptance: exit 0" 0 "$RC"
rm -rf "${STORE:?}/coord_h"
run status "$S"
eq "after the overruling coordinator's session is cleaned up, status still exits 1" 1 "$RC"
has "and the unit is still held as overruled" "held: overruled tests/greet_test.sh by agent:coord_h" "$OUT"
run record "$S"
has "record still shows the overruled state" "held: overruled tests/greet_test.sh by agent:coord_h" "$OUT"
S=gone_dec
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: loosen"
mkdir -p "$STORE/coord_i"
run decline "$S" --as agent:coord_i --authority coordinator --all --reason "weakens the check"
eq "a coordinator declines: exit 0" 0 "$RC"
rm -rf "${STORE:?}/coord_i"
run status "$S"
eq "after the declining coordinator's session is cleaned up, status still exits 1" 1 "$RC"
has "and the unit is still held as declined" "held: declined tests/greet_test.sh by agent:coord_i" "$OUT"

# --- record of a fix ---------------------------------------------------------------------------
echo "--- record of a fix"
S=rec
start "$S"
printf '{"ts":"t","event":"determine","kind":"fix","source":"label:bug","report_source":"issue"}\n' > "$STORE/$S/fix_kind.jsonl"
printf '#!/bin/sh\nfalse\n' > tests/empty_test.sh && git add -A && git commit -q -m "test: reproduce"
jq -n --arg b "$(git rev-parse HEAD:tests/empty_test.sh)" --arg base "$BASE" --arg head "$(git rev-parse HEAD)" '{schema: "shirabe-red-first/v1",
    red: {command: ["sh", "tests/run.sh"], base: $base, head: $base, tests: [{path: "tests/empty_test.sh", blob: $b}], harness: [], exit: 1,
          marker_context: "running\nerror: name required\ndone", passage: "prints Hello, ! instead of error: name required",
          marker: "error: name required", report_source: "issue", ran_at: "t1"},
    observations: {}, green: {command: ["sh", "tests/run.sh"], head: $head, exit: 0, ran_at: "t2"}}' > "$STORE/$S/red_first.json"
run record "$S"
eq "record of a fix: exit 0" 0 "$RC"
has "record prints the fix source" "unit: fix (source label:bug)" "$OUT"
has "record prints the red" "red: sh tests/run.sh on base $BASE exited 1" "$OUT"
has "record prints the marker" "marker: error: name required" "$OUT"
has "record prints the green" "green: sh tests/run.sh at $(git rev-parse HEAD) exited 0" "$OUT"
has "record prints the reproducing test as added" "added tests/empty_test.sh" "$OUT"
has "record prints the state" "state: counted" "$OUT"

# --- a refused read ------------------------------------------------------------------------
# koto refuses a read of a session bound to another workspace, printing the
# refusal on stdout and exiting 2. That is a failed read, which fails the
# command rather than reading as an absent key.
echo "--- a refused read"
S=refu
start "$S"
LEDGER_REFU=$(ledger "$S")
SHIM_REFUSE=$S run status "$S"
eq "status on a refused session: exit 66 rather than reading as an absent key" 66 "$RC"
hasnt "status on a refused session: koto's refusal kept off stdout" "session_bound_elsewhere" "$OUT"
has "status on a refused session: koto's refusal on stderr" "session_bound_elsewhere" "$(cat "$W/err")"
SHIM_REFUSE_KEY=test_change_ledger.jsonl run init "$S"
eq "init with the ledger read refused: exit 66 rather than reading as an absent key" 66 "$RC"
eq "init with the ledger read refused: the ledger is untouched" "$LEDGER_REFU" "$(ledger "$S")"
SHIM_REFUSE_KEY=test_change_ledger.jsonl SHIM_REFUSE_RC=1 run init "$S" --entry
eq "init --entry with the ledger read refused at exit 1 with the refusal: exit 66 rather than reading as an absent key" 66 "$RC"
SHIM_REFUSE_KEY=red_first.json run status "$S"
eq "status with the red-first record read refused: exit 66 rather than reading as an absent key" 66 "$RC"
has "status with the red-first record read refused: names the failed read" "could not read red_first.json" "$(cat "$W/err")"
run status "$S"
eq "status with nothing refused: counted as before" 0 "$RC"

# --- a moved work tree ---------------------------------------------------------------------
# The run's checkout moves: its work tree is cloned somewhere else and the old
# one removed, as a handover to a new checkout does. The fixture repository
# gets an origin named acme/greet so the header records a repository.
echo "--- a moved work tree"
run_in() {
    local d="$1"
    shift
    OUT=$(cd "$d" && PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>"$W/err")
    RC=$?
}
# exit_is <label> <want>: like eq on RC, with the command's stderr on a failure.
exit_is() {
    if [ "$RC" = "$2" ]; then ok "$1"; else bad "$1" "want exit $2, got $RC: $OUT $(cat "$W/err")"; fi
}
ORIGIN="$W/remote/acme/greet.git"
mkdir -p "$W/remote/acme"
git clone -q --bare "$R" "$ORIGIN"
MA="$W/moved-a"
git clone -q "$ORIGIN" "$MA"
git -C "$MA" checkout -q -b b-mv
S=mv
rm -rf "${STORE:?}/$S"
mkdir -p "$STORE/$S"
git -C "$MA" rev-parse HEAD > "$STORE/$S/impl_base"
cp "$RULES" "$STORE/$S/review_level_rules.tsv"
cp "$STORE/acc/context.md" "$STORE/$S/context.md"
run_in "$MA" init "$S"
exit_is "moved: init in the first work tree" 0
eq "moved: the header records the repository" acme/greet "$(ledger "$S" | head -n 1 | jq -r .repo)"
sed -i.bak 's/Hello, World!/Hello, World/' "$MA/tests/greet_test.sh"
rm -f "$MA/tests/greet_test.sh.bak"
git -C "$MA" commit -q -am "test: drop the exclamation mark"
run_in "$MA" status "$S"
exit_is "moved: before the move status holds the edit" 1
STATUS_BEFORE=$OUT
MA_TOP=$(git -C "$MA" rev-parse --show-toplevel)
MB="$W/moved-b"
git clone -q "$MA" "$MB"
git -C "$MB" remote set-url origin "$ORIGIN"
MB_TOP=$(git -C "$MB" rev-parse --show-toplevel)
MC="$W/moved-c"
git clone -q "$MA" "$MC"
git -C "$MC" remote set-url origin "$W/remote/acme/other.git"
MD="$W/moved-d"
git clone -q "$ORIGIN" "$MD"
git -C "$MD" checkout -q --orphan lone
git -C "$MD" commit -q -m "an unrelated history"
rm -rf "$MA"

run_in "$MC" status "$S"
exit_is "moved: from a work tree of another repository status exits 2" 2
has "moved: another repository keeps the gone work tree's message" "the run's work tree [$MA_TOP] is gone" "$(cat "$W/err")"
run_in "$MD" status "$S"
exit_is "moved: from a work tree whose HEAD lacks impl_base status exits 2" 2
has "moved: no impl_base keeps the gone work tree's message" "the run's work tree [$MA_TOP] is gone" "$(cat "$W/err")"
eq "moved: neither wrote a line" 1 "$(ledger "$S" | wc -l | tr -d ' ')"
run_in "$MB" record "$S"
exit_is "moved: record before the move is recorded exits 0" 0
has "moved: record doesn't re-root from the directory it runs in" "state: undecided" "$OUT"
run_in "$MB" covered "$S" tests/greet_test.sh
exit_is "moved: covered reads the moved tree and holds the edit" 1
has "moved: covered names the unaccepted edit" "held: unaccepted tests/greet_test.sh" "$OUT"
eq "moved: record and covered wrote nothing" 1 "$(ledger "$S" | wc -l | tr -d ' ')"

run_in "$MB" status "$S"
exit_is "moved: from a clone of the same repository status gates as before" 1
eq "moved: the same output as at the old path" "$STATUS_BEFORE" "$OUT"
has "moved: stderr names the move" "[$MA_TOP] is gone; following it to [$MB_TOP]" "$(cat "$W/err")"
eq "moved: one relocate line from the old tree to the new one" "relocate|$MA_TOP|$MB_TOP" \
    "$(ledger "$S" | sed -n 2p | jq -r '"\(.event)|\(.from)|\(.to)"')"
has "moved: the relocate line has a time" '"ts":"20' "$(ledger "$S" | sed -n 2p)"
run_in "$MB" status "$S"
exit_is "moved: a second status gates the same" 1
eq "moved: a second status writes no line" 2 "$(ledger "$S" | wc -l | tr -d ' ')"
hasnt "moved: a second status names no move" "following it" "$(cat "$W/err")"
run_in "$R" status "$S"
exit_is "moved: from an unrelated directory status reads the relocated tree" 1
run_in "$MB" seat "$S"
exit_is "moved: seat in the relocated tree" 0
has "moved: the seat's brief carries the edited hunk" '-[ "$out" = "Hello, World!" ]' "$OUT"
run_in "$MB" accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "corrects the expected value"
exit_is "moved: the seat's accept" 0
run_in "$MB" status "$S"
exit_is "moved: after the accept status counts" 0
LINES_NOW=$(ledger "$S" | wc -l | tr -d ' ')
run_in "$R" record "$S"
exit_is "moved: record from anywhere exits 0" 0
has "moved: record shows the relocation" "relocate: the work tree [$MA_TOP] moved to [$MB_TOP]" "$OUT"
has "moved: record reads the relocated tree" "state: counted" "$OUT"
eq "moved: record wrote nothing" "$LINES_NOW" "$(ledger "$S" | wc -l | tr -d ' ')"

# --- nothing reaches a pull request --------------------------------------------------------
echo "--- nothing reaches a pull request"
eq "no subcommand called gh" "" "$(cat "$GH_LOG")"
eq "test-change.sh has no gh pr edit or gh pr comment" 0 "$(grep -cE 'gh pr (edit|comment)' "$SCRIPT")"
run render rec
eq "there is no render subcommand" 64 "$RC"

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
