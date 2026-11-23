#!/usr/bin/env bash
# test-change_test.sh -- test-change.sh against a git fixture and a koto
# stand-in.
#
# The fixture is the design's walkthrough repository: greet.sh prints
# `Hello, <name>!` and tests/greet_test.sh asserts it for `World`. Each case
# branches off main, records impl_base and the rules copy as analysis and
# review_level_choice would, and runs `init`. A panel's judgment is written
# into the session's verdict_ledger.json as panel-scope.sh --record leaves it
# (judge, below), and status reads it back through panel-scope.sh --due-items.
#
# Covers:
#   classify   a new test and one that only gained lines are `added`; a removed
#              line, a deleted test and a rename with a changed line are
#              `edited`; a fix's reproducing test changed after its red is
#              `edited` even when it only gained lines
#   init       writes the header once: a second init exits 1, --entry exits 0
#              and writes nothing; an impl_base that isn't where the unit
#              started is refused; a ledger with lines but no header is refused
#   status     exits 0 for added-only tests; with no panel recorded, exits 1
#              holding every edited test as due (`<path> due: no panel has
#              judged it`) with finding test-change/held and no word of a
#              seat; a panel's judgment at the test's content counts it; a
#              later commit to the test holds it as due for that panel until
#              a judgment at the new content; an open weakens finding holds
#              it; uncommitted changes hold; exit 3 when an item is held and
#              the panel retry budget is spent, exit 1 while a retry is left,
#              exit 2 when the retry record can't be read
#   legacy lines
#              hand-written seat, accept, decline, refuse and overrule lines
#              leave status's exit code and output unchanged, held or
#              counted; record lists them as legacy history
#   the retired person-acceptance header
#              a repository whose CLAUDE.md still declares the header that
#              once required a person to accept (`## $DECL: person`) gets
#              the same status output as one without it
#   removed subcommands
#              seat, accept, decline and overrule exit 64 as unknown
#   observations  due until a panel judges the pair; `covered` and
#              red-first.sh check-green then pass
#   the lock   a live owner makes a writer exit 75; a dead owner's lock is
#              broken
#   record     the kind, the test files, the legacy lines and the state; for
#              a fix, the fix source, the red with its marker, the green and
#              the reproducing test as added
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
#              paths, a second status none, and a judgment made in the
#              relocated tree counts; from a clone whose origin is another
#              repository, or one whose HEAD lacks impl_base, status still
#              exits 2 with the gone work tree's message and writes nothing;
#              covered and record write nothing, record never re-roots from
#              the directory it runs in, and once the move is recorded it
#              shows the relocation and reads the relocated tree from
#              anywhere
#   a rebound session
#              the session listed in another checkout of the same work while
#              the header's work tree still exists: status from it appends
#              one relocate line carrying its HEAD, classify holds its digest,
#              a judgment at the old tree's content leaves it held and one at
#              the bound tree's counts it, status counts from an unrelated
#              directory, and record prints the relocate head; a bound
#              checkout of another repository, or a failed listing, exits 2
#              and writes nothing
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
    session)
        # `session list`: one {id, execution_dir} per session under
        # $SHIM_STORE, the directory read from its execution_dir file and left
        # out when there is none. SHIM_LIST_FAIL makes the listing fail.
        [ "$2" = list ] || { echo "shim: unsupported $*" >&2; exit 2; }
        [ -z "${SHIM_LIST_FAIL:-}" ] || { echo "shim: session list failed" >&2; exit 1; }
        for d in "$SHIM_STORE"/*/; do
            [ -d "$d" ] || continue
            id=$(basename "$d")
            if [ -f "$d/execution_dir" ]; then
                jq -nc --arg id "$id" --arg dir "$(cat "$d/execution_dir")" '{id: $id, execution_dir: $dir}'
            else
                jq -nc --arg id "$id" '{id: $id}'
            fi
        done | jq -s .
        exit 0 ;;
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


# judge <session> <dir> <item> [<content> [<judgment> [<panel>]]]: one
# recorded round of <panel> (scrutiny by default) whose seat judged <item> at
# <content> (a test's blob at <dir>'s HEAD by default) as <judgment> (corrects
# by default), at <dir>'s HEAD, in verdict_ledger.json as panel-scope.sh
# --record leaves it.
judge() {
    local s="$1" d="$2" item="$3" content="${4:-}" verdict="${5:-corrects}" panel="${6:-scrutiny}" head f run
    head=$(git -C "$d" rev-parse HEAD)
    [ -n "$content" ] || content=$(git -C "$d" rev-parse "HEAD:$item")
    f="$STORE/$s/verdict_ledger.json"
    [ -s "$f" ] || printf '{}\n' > "$f"
    run="run-$(jq '(.history // []) | length' "$f")-$panel"
    jq --arg p "$panel" --arg run "$run" --arg item "$item" --arg c "$content" --arg j "$verdict" --arg h "$head" '
        .seats["\($p)/seat"] = {verdict: "pass", run: $run}
        | .history = ((.history // []) + [{panel: $p, decisions: [{seat: "seat", run: $run, decision: "full"}]}])
        | .runs[$run] = {recorded: true, panel: $p}
        | .judgments[$p] = ((.judgments[$p] // []) + [{item: $item, content: $c, judgment: $j, by: "seat", run: $run, judged_at: $h}])' \
        "$f" > "$f.next" && mv "$f.next" "$f"
}
# spend <session>: the panel retry budget used up, as panel-retry-budget.sh
# records three granted retries.
spend() { printf 'scrutiny 3\nscrutiny 2\nscrutiny 1\n' > "$STORE/$1/panel_retries"; }

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
has "added-only: counted" "counted: no edited test or observation needs a panel's judgment" "$OUT"
eq "added-only: no acceptance recorded" 0 "$(ledger "$S" | jq -r 'select(.event == "accept")' | wc -l | tr -d ' ')"

sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git rm -q tests/other_test.sh
git commit -q -am "test: edit and delete"
run classify "$S"
has "a removed line is edited" "edited	tests/greet_test.sh	$(git rev-parse HEAD:tests/greet_test.sh)" "$OUT"
has "a deleted test is edited" "edited	tests/other_test.sh	deleted" "$OUT"
run status "$S"
eq "an edit: status exits 1" 1 "$RC"
has "an edit: held as due" "held: tests/greet_test.sh due: no panel has judged it" "$OUT"
has "a deletion: held as due" "held: tests/other_test.sh due: no panel has judged it" "$OUT"
has "the hold prints finding test-change/held" '"rule_id":"test-change/held"' "$OUT"

S=ren
start "$S"
git mv tests/greet_test.sh tests/hello_test.sh
sed -i.bak 's/Hello, World!/Hello, World/' tests/hello_test.sh && rm -f tests/hello_test.sh.bak
git commit -q -am "test: rename with a change"
run classify "$S"
has "a rename with a changed line is edited" "edited	tests/hello_test.sh	" "$OUT"
run status "$S"
has "a rename with a change: held" "held: tests/hello_test.sh due: no panel has judged it" "$OUT"

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


# --- the panels judge ------------------------------------------------------------------
echo "--- the panels judge"
S=acc
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: drop the exclamation mark"
run note "$S" --file tests/greet_test.sh --reason "the issue drops the exclamation mark"
eq "note exits 0" 0 "$RC"
run status "$S"
eq "no panel recorded: an edited test holds (exit 1)" 1 "$RC"
has "no panel recorded: the test is named as due" "held: tests/greet_test.sh due: no panel has judged it" "$OUT"
has "no panel recorded: the hold prints finding test-change/held" '"rule_id":"test-change/held"' "$OUT"
hasnt "no panel recorded: nothing says to mint a seat" "mint" "$OUT"
hasnt "no panel recorded: nothing says to commission a seat" "commission" "$OUT"
hasnt "no panel recorded: no seat is named" "seat" "$OUT"
eq "status wrote no line" 2 "$(ledger "$S" | wc -l | tr -d ' ')"

judge "$S" "$R" tests/greet_test.sh
run status "$S"
eq "a panel's corrects at the test's content: status exits 0" 0 "$RC"
has "the panels' judgment counts it" "counted: the panels judged every edited test" "$OUT"

printf '# changed again\n' >> tests/greet_test.sh
git commit -q -am "test: touch the judged test"
run status "$S"
eq "a later commit to a judged test: exit 1" 1 "$RC"
has "a later commit: due for the panel that judged it" "held: tests/greet_test.sh due for scrutiny" "$OUT"
judge "$S" "$R" tests/greet_test.sh
run status "$S"
eq "a judgment at the new content: status exits 0" 0 "$RC"

printf 'dirty\n' >> greet.sh
run status "$S"
eq "uncommitted changes: exit 1" 1 "$RC"
has "uncommitted changes: held" "held: uncommitted changes" "$OUT"
git checkout -q -- greet.sh

# An open weakens finding holds the test though a judgment matches its content.
S=weak
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: loosen"
judge "$S" "$R" tests/greet_test.sh "" weakens
jq '.findings = {f1: {panel: "scrutiny", severity: "blocking", rule_id: "review/test-edit-weakens",
                      summary: "the edit drops the check", location: {path: "tests/greet_test.sh"},
                      raiser: {kind: "seat", name: "seat"}, round: 1, records: []}}' \
    "$STORE/$S/verdict_ledger.json" > "$W/weak.json" && mv "$W/weak.json" "$STORE/$S/verdict_ledger.json"
run status "$S"
eq "an open weakens: exit 1" 1 "$RC"
has "an open weakens: held naming it" "held: tests/greet_test.sh weakens: an open finding of scrutiny" "$OUT"

# The retry budget: a held item with no retry left ends the run (exit 3).
S=spent
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: loosen"
printf 'scrutiny 3\nscrutiny 2\n' > "$STORE/$S/panel_retries"
run status "$S"
eq "a held test with a retry left: exit 1" 1 "$RC"
hasnt "a retry left: no budget line" "budget spent" "$OUT"
spend "$S"
run status "$S"
eq "a held test with the budget spent: exit 3" 3 "$RC"
has "the budget spent: held says so" "held: budget spent: panel-retry-budget.sh --remaining reports no retry left" "$OUT"
judge "$S" "$R" tests/greet_test.sh
run status "$S"
eq "the budget spent but nothing held: exit 0" 0 "$RC"
printf 'dirty\n' >> greet.sh
run status "$S"
eq "the budget spent, held only by uncommitted changes: exit 1" 1 "$RC"
git checkout -q -- greet.sh
printf '# again\n' >> tests/greet_test.sh && git commit -q -am "test: again"
printf 'not a record line\n' > "$STORE/$S/panel_retries"
run status "$S"
eq "a retry record that can't be read: exit 2" 2 "$RC"

# --- legacy lines ----------------------------------------------------------------------
# Seat, accept, decline, refuse and overrule lines a run wrote before the
# panels took over: nothing counts them, held or counted.
echo "--- legacy lines"
S=legacy
start "$S"
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: loosen"
LEG_DIGEST=$(git rev-parse HEAD:tests/greet_test.sh)
legacy_lines() {
    jq -nc --arg s "$1" --arg d "$LEG_DIGEST" '
        {ts: "2026-01-01T00:00:00Z", event: "seat", identity: "agent:\($s)/accept-1", nonce: "n", source: "session", rule: "interim"},
        {ts: "2026-01-01T00:00:01Z", event: "accept", id: "accept-3", identity: "agent:\($s)/accept-1", kind: "agent", authority: "reviewer",
         files: [{path: "tests/greet_test.sh", digest: $d}], reason: "hand-written acceptance", outcome: "allow", session_exists: false, source: "session", rule: "interim"},
        {ts: "2026-01-01T00:00:02Z", event: "decline", id: "decline-4", identity: "agent:\($s)/accept-2", kind: "agent", authority: "reviewer",
         files: [{path: "tests/greet_test.sh", digest: $d}], reason: "hand-written decline", outcome: "allow", session_exists: false, source: "session", rule: "interim"},
        {ts: "2026-01-01T00:00:03Z", event: "refuse", action: "accept", identity: "agent:other", kind: "agent", authority: "reviewer",
         files: [], reason: "x", outcome: "refuse", rule_id: "unminted-seat", detail: "d", source: "session", rule: "interim"},
        {ts: "2026-01-01T00:00:04Z", event: "overrule", id: "overrule-5", identity: "agent:coord", kind: "agent", authority: "coordinator",
         target: "accept-3", target_authority: "reviewer", files: [{path: "tests/greet_test.sh", digest: $d}], reason: "hand-written overrule",
         outcome: "allow", session_exists: true, source: "session", rule: "interim"}'
}
run status "$S"
HELD_RC=$RC HELD_OUT=$OUT
cp "$STORE/$S/test_change_ledger.jsonl" "$W/legacy.clean"
legacy_lines "$S" >> "$STORE/$S/test_change_ledger.jsonl"
run status "$S"
eq "legacy lines, held: the same exit code" "$HELD_RC" "$RC"
eq "legacy lines, held: the same output" "$HELD_OUT" "$OUT"
judge "$S" "$R" tests/greet_test.sh
cp "$W/legacy.clean" "$STORE/$S/test_change_ledger.jsonl"
run status "$S"
CNT_RC=$RC CNT_OUT=$OUT
legacy_lines "$S" >> "$STORE/$S/test_change_ledger.jsonl"
run status "$S"
eq "legacy lines, counted: the same exit code" "$CNT_RC" "$RC"
eq "legacy lines, counted: the same output" "$CNT_OUT" "$OUT"
eq "legacy lines, counted: exit 0" 0 "$RC"
run record "$S"
eq "record with legacy lines exits 0" 0 "$RC"
has "record lists a seat line as legacy" "legacy, ignored: seat agent:$S/accept-1 minted" "$OUT"
has "record lists an accept line as legacy" "legacy, ignored: accept accept-3 by agent:$S/accept-1" "$OUT"
has "record lists a decline line as legacy" "legacy, ignored: decline decline-4" "$OUT"
has "record lists a refuse line as legacy" "legacy, ignored: refuse: accept refused, rule unminted-seat" "$OUT"
has "record lists an overrule line as legacy" "legacy, ignored: overrule overrule-5" "$OUT"
has "record prints the state from the panels" "state: counted" "$OUT"
has "record prints the unit's kind" "unit: not determined" "$OUT"
has "record prints each test file as edited" "edited tests/greet_test.sh" "$OUT"

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
has "the pair is due" "held: observation due: no panel has judged it" "$OUT"
run covered "$S" observation:before observation:after
eq "covered before a panel judged the pair: exit 1" 1 "$RC"
OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$HERE/red-first.sh" check-green "$S" 2>/dev/null); RC=$?
eq "check-green before a panel judged the pair: exit 1" 1 "$RC"
has "check-green before a panel judged the pair: the pair is not counted" "refused: the observation pair is not counted at its current digests" "$OUT"
judge "$S" "$R" observation b1b1/a2a2 shown
run covered "$S" observation:before observation:after
eq "covered after a panel judged the pair shown: exit 0" 0 "$RC"
OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$HERE/red-first.sh" check-green "$S" 2>/dev/null); RC=$?
eq "check-green after a panel judged the pair shown: exit 0" 0 "$RC"
run status "$S"
eq "status after a panel judged the pair shown: exit 0" 0 "$RC"

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
has "and held" "held: tests/empty_test.sh due: no panel has judged it" "$OUT"

# --- removed subcommands ----------------------------------------------------------------
echo "--- removed subcommands"
for sub in seat accept decline overrule; do
    run "$sub" acc
    eq "$sub: exit 64" 64 "$RC"
    has "$sub: named as an unknown subcommand" "unknown subcommand [$sub]" "$(cat "$W/err")"
done

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
sleep 30 &
LIVE=$!
printf '%s\t%s\n' "$LIVE" "$(ps -o lstart= -p "$LIVE" | tr -s ' ' | sed 's/^ //; s/ $//')" > "$LOCKDIR"
run note "$S" --file tests/greet_test.sh --reason "x"
eq "a lock file with a live owner: exit 75" 75 "$RC"
kill "$LIVE" 2>/dev/null
wait "$LIVE" 2>/dev/null
run note "$S" --file tests/greet_test.sh --reason "x"
eq "a lock file whose owner is gone is broken" 0 "$RC"
[ -e "$LOCKDIR" ] && bad "the lock is released after the write" "[$LOCKDIR] is there" || ok "the lock is released after the write"

# Five writers race for one session's lock, under a mkdir that reports success
# for a directory that already exists, the way uutils mkdir (Ubuntu 26.04) did
# when it lost the race to create one. The writer that gets the lock is held at
# its first ledger read until the others have given up.
rm -rf "$LOCKDIR"
RACE="$W/race"
rm -rf "$RACE"
mkdir -p "$RACE/bin"
printf '#!/bin/sh\nexec %s -p "$@"\n' "$(command -v mkdir)" > "$RACE/bin/mkdir"
cat > "$RACE/bin/koto" <<EOF
#!/usr/bin/env bash
if [ "\${1-}" = context ] && [ "\${2-}" = exists ]; then
    : > "$RACE/in.\$\$"
    n=0
    until [ -e "$RACE/release" ] || [ "\$n" -ge 150 ]; do sleep 0.1; n=\$((n + 1)); done
fi
exec "$BIN/koto" "\$@"
EOF
chmod +x "$RACE/bin/mkdir" "$RACE/bin/koto"
PIDS=""
for i in 1 2 3 4 5; do
    (cd "$R" && PATH="$RACE/bin:$BIN:$PATH" bash "$SCRIPT" note "$S" --file tests/greet_test.sh --reason "race $i" >/dev/null 2>&1
     echo "$?" > "$RACE/rc.$i") &
    PIDS="$PIDS $!"
done
n=0
until [ "$(ls "$RACE" | grep -c '^rc\.')" -ge 4 ] || [ "$n" -ge 150 ]; do sleep 0.1; n=$((n + 1)); done
eq "five writers racing for one session's lock: exactly one wins" 1 "$(ls "$RACE" | grep -c '^in\.')"
: > "$RACE/release"
# shellcheck disable=SC2086
wait $PIDS
eq "  ... and the other four exit 75" 4 "$(cat "$RACE"/rc.* | grep -c '^75$')"

# --- the retired person-acceptance header ----------------------------------------------
# The declaration is no longer read: a repository that still carries it gets
# the same status output as one without it.
# The header's name is built from two parts, so a search for it finds no
# reader anywhere in the plugin.
DECL="Test Change"
DECL="$DECL Acceptance"
echo "--- the retired person-acceptance header"

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
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: drop the mark"
run status und
UND_RC=$RC UND_OUT=$OUT
hasnt "the header records no person requirement" "person_required" "$(hdr_of und .)"

git checkout -q -B b-person main
printf '# greet\n\n## %s: person\n' "$DECL" > CLAUDE.md
git add CLAUDE.md && git commit -q -m "docs: require a person"
start_here dp
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: drop the mark"
printf '## %s: person\n' "$DECL" > CLAUDE.local.md
run status dp
rm -f CLAUDE.local.md
eq "a person header: the same exit code as none" "$UND_RC" "$RC"
eq "a person header: the same status output as none" "$UND_OUT" "$OUT"
hasnt "a person header: the header records no person requirement" "person_required" "$(hdr_of dp .)"


# --- a merge of main onto a branch-only base (#1603) ----------------------------------------
# impl_base is a commit only on the branch, so it isn't an ancestor of the
# merge-base with main. The default branch here is b-1603-main, read through
# origin/main, so main itself stays where the other sections expect it.
echo "--- a merge of main onto a branch-only base"
git checkout -q -B b-1603-main "$BASE"
git checkout -q -B b-1603 "$BASE"
printf '#!/bin/sh\n[ 2 -eq 2 ]\n' > tests/shared_test.sh
git add -A && git commit -q -m "test: shared work before the unit"
S=mob
start_here "$S"
printf '#!/bin/sh\n' > tests/other_test.sh
git commit -q -am "test: the unit's own edit"
git checkout -q b-1603-main
sed -i.bak 's/Hello, World!/Hello, World/' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
git commit -q -am "test: main edits a test"
git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
git checkout -q b-1603
git merge -q --no-edit b-1603-main >/dev/null
run status "$S"
eq "a merge of main onto a branch-only base: status holds on the unit's own edit" 1 "$RC"
has "a merge of main onto a branch-only base: the unit's own edit is held" "held: tests/other_test.sh due: no panel has judged it" "$OUT"
case "$OUT" in
    *"held: tests/greet_test.sh"*) bad "a merge of main onto a branch-only base: main's test edit isn't held as the unit's own" "[$OUT]" ;;
    *) ok "a merge of main onto a branch-only base: main's test edit isn't held as the unit's own" ;;
esac
git update-ref -d refs/remotes/origin/main


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
has "moved: covered names the due edit" "held: tests/greet_test.sh due: no panel has judged it" "$OUT"
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
judge "$S" "$MB" tests/greet_test.sh
run_in "$MB" status "$S"
exit_is "moved: after a panel's judgment in the relocated tree status counts" 0
LINES_NOW=$(ledger "$S" | wc -l | tr -d ' ')
run_in "$R" record "$S"
exit_is "moved: record from anywhere exits 0" 0
has "moved: record shows the relocation" "relocate: the work tree [$MA_TOP] moved to [$MB_TOP]" "$OUT"
has "moved: record reads the relocated tree" "state: counted" "$OUT"
eq "moved: record wrote nothing" "$LINES_NOW" "$(ledger "$S" | wc -l | tr -d ' ')"

# --- a rebound session ---------------------------------------------------------------------
# The run's session is rebound to a new checkout while the old one stays on
# disk. Checkout A holds an edited test and is where init ran; checkout B is a
# clone of it, a commit further on the same test, and is the directory koto
# lists for the session. Every call that reads the work tree follows B.
echo "--- a rebound session"
RA="$W/rebound-a"
git clone -q "$ORIGIN" "$RA"
git -C "$RA" checkout -q -b b-rb
# rebound_session <session>: impl_base and the rules copy, then init in A.
rebound_session() {
    rm -rf "${STORE:?}/$1"
    mkdir -p "$STORE/$1"
    git -C "$RA" rev-parse HEAD > "$STORE/$1/impl_base"
    cp "$RULES" "$STORE/$1/review_level_rules.tsv"
    run_in "$RA" init "$1"
    exit_is "rebound: init $1 in the first work tree" 0
}
rebound_session rb
rebound_session rbx
rebound_session rbf
sed -i.bak 's/Hello, World!/Hello, World/' "$RA/tests/greet_test.sh"
rm -f "$RA/tests/greet_test.sh.bak"
git -C "$RA" commit -q -am "test: drop the exclamation mark"
RA_TOP=$(git -C "$RA" rev-parse --show-toplevel)
RB="$W/rebound-b"
git clone -q "$RA" "$RB"
git -C "$RB" remote set-url origin "$ORIGIN"
sed -i.bak 's/Hello, World/Hello there, World/' "$RB/tests/greet_test.sh"
rm -f "$RB/tests/greet_test.sh.bak"
git -C "$RB" commit -q -am "test: greet by a longer phrase"
RB_TOP=$(git -C "$RB" rev-parse --show-toplevel)
RB_HEAD=$(git -C "$RB" rev-parse HEAD)
RB_DIGEST=$(git -C "$RB" rev-parse HEAD:tests/greet_test.sh)
RX="$W/rebound-x"
git clone -q "$RA" "$RX"
git -C "$RX" remote set-url origin "$W/remote/acme/other.git"
RX_TOP=$(git -C "$RX" rev-parse --show-toplevel)
S=rb
printf '%s\n' "$RB_TOP" > "$STORE/$S/execution_dir"
[ -d "$RA_TOP" ] || bad "rebound: the old work tree is still on disk" "[$RA_TOP] is gone"

run_in "$RB" status "$S"
exit_is "rebound: status from the bound tree holds the edit" 1
eq "rebound: status follows the bound tree with one relocate line from the old tree, whether or not the old tree still exists" \
    "relocate|$RA_TOP|$RB_TOP|$RB_HEAD" \
    "$(ledger "$S" | jq -r 'select(.event == "relocate") | "\(.event)|\(.from)|\(.to)|\(.head)"')"
run_in "$RB" classify "$S"
has "rebound: the held digest is the bound tree's" "edited	tests/greet_test.sh	$RB_DIGEST" "$OUT"
judge "$S" "$RA" tests/greet_test.sh
run_in "$RB" status "$S"
exit_is "rebound: a judgment at the old tree's content leaves it held" 1
has "rebound: held as due at the bound tree's content" "held: tests/greet_test.sh due for scrutiny" "$OUT"
judge "$S" "$RB" tests/greet_test.sh
run_in "$RB" status "$S"
exit_is "rebound: after a judgment at the bound tree's content status counts" 0
run_in "$R" status "$S"
exit_is "rebound: from an unrelated directory status reads the bound tree and counts" 0
eq "rebound: still one relocate line" 1 "$(ledger "$S" | jq -r 'select(.event == "relocate") | .to' | wc -l | tr -d ' ')"
run_in "$R" record "$S"
exit_is "rebound: record exits 0" 0
has "rebound: record prints the relocate head" "moved to [$RB_TOP] at $RB_HEAD" "$OUT"

S=rbx
printf '%s\n' "$RX_TOP" > "$STORE/$S/execution_dir"
run_in "$RX" status "$S"
exit_is "rebound: a bound tree of another repository, the old tree present: status exits 2" 2
has "rebound: another repository names the old tree" "$RA_TOP" "$(cat "$W/err")"
has "rebound: another repository names the bound tree" "$RX_TOP" "$(cat "$W/err")"
eq "rebound: another repository writes no line" 1 "$(ledger "$S" | wc -l | tr -d ' ')"

S=rbf
printf '%s\n' "$RB_TOP" > "$STORE/$S/execution_dir"
SHIM_LIST_FAIL=1 run_in "$RB" status "$S"
exit_is "rebound: a failed session listing: status exits 2" 2
eq "rebound: a failed session listing writes no line" 1 "$(ledger "$S" | wc -l | tr -d ' ')"

# --- nothing reaches a pull request --------------------------------------------------------
echo "--- nothing reaches a pull request"
eq "no subcommand called gh" "" "$(cat "$GH_LOG")"
eq "test-change.sh has no gh pr edit or gh pr comment" 0 "$(grep -cE 'gh pr (edit|comment)' "$SCRIPT")"
run render rec
eq "there is no render subcommand" 64 "$RC"
echo
echo "test-change: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
