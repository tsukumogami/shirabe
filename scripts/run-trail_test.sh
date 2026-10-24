#!/usr/bin/env bash
# run-trail_test.sh -- scripts/run-trail.sh, the one writer of a run's record
#
# Against the stand-in koto (scripts/testdata/record-koto/koto), which keys a
# session by workspace:
#
#   self   trail/self holds the checkout's canonical path, the session's koto
#          id from the session list and its run_id; no run_id refuses (65)
#   pr     trail/pr/<owner>.<repo>.<n> holds the repository (lowercased), the
#          number as a number, the role and the state; a role, state,
#          repository or number outside its pattern refuses (65) and writes
#          nothing
#   index  run/<run_id> in pr.<owner>.<repo>.<n>, opened and written from
#          the shared address, naming the root's workspace, session, session
#          id, mode and topic; trail/self written first when it's absent,
#          except in mode coordinated, which refuses (65) with nothing
#          written until the root has one; a second write attaches and
#          rewrites; with the option present no write carries --workspace
#   plan   the PLAN's text as committed at HEAD and {sha, entry, recorded_at};
#          an absolute path to docs/plans/PLAN-<topic>.md in another
#          checkout read at that checkout's HEAD; a path outside
#          docs/plans/PLAN-<topic>.md (../secrets.md, a subdirectory, a
#          case change, an absolute one outside that layout, outside any git
#          checkout or under a missing directory), a PLAN not at HEAD and a
#          PLAN holding a token refuse (65) with the key list unchanged
#   step   the step session and this checkout; the same name again changes
#          nothing; another name refuses (65) without --supersede and moves
#          the earlier one to superseded with it; --child-workspace records
#          that directory (canonical) instead, a relative or missing one
#          refuses (65), and it is 64 given twice or to another verb
#   departure, decision
#          text only as one JSON document on stdin: an argument is 64, a
#          document that isn't JSON, lacks a field, holds an empty or
#          oversized one, or holds a token shape, an Authorization: line or a
#          private-key header is 65, each with the key list unchanged and no
#          koto decisions record; the four kinds each against its step, n
#          counting up; a decision's actor (agent:<name>, person,
#          person:<login>) in its trail key and its choice and rationale in
#          koto's decision log
#   carry  a snapshot of one session's trail (trail/self left out) carried
#          into a fresh session byte for byte; a key the session holds is
#          kept; a snapshot that isn't an object of text, or names a key
#          outside the layout, refuses (65) and writes nothing
#   usage  an unknown verb or flag, a repeated flag, a missing one: 64, no
#          koto call
#   koto   a failed write is 70
#
# Before the first case the suite checks that the koto on PATH is the
# stand-in, and stops when it isn't.
#
# Usage: run-trail_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
TRAIL="$SCRIPT_DIR/run-trail.sh"
STUB_DIR="$SCRIPT_DIR/testdata/record-koto"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-trail-test.XXXXXX") || exit 1
OWNER="rttest-$$-$(od -An -tx1 -N4 /dev/urandom | tr -d ' \n')"
trap 'rm -rf "$WORK" "/tmp/shirabe-run-record/$OWNER"' EXIT
export PATH="$STUB_DIR:$PATH"
export RECORD_KOTO_STORE="$WORK/store"
A="$WORK/a"
mkdir -p "$A"
A=$(cd "$A" && pwd -P)
S=execute-topic
RID=00112233445566778899aabbccddeeff

# The koto on PATH must be the stand-in: these cases write sessions, and a
# real koto would write them to a real store.
if [ "$(command -v koto)" != "$STUB_DIR/koto" ] \
    || [ "$(RECORD_KOTO_STORE="$WORK/stub-probe" koto version </dev/null)" != "koto 0.0.0-record-stub" ]; then
    echo "FAIL: the koto on PATH is not the stand-in at $STUB_DIR/koto; no case ran" >&2
    exit 1
fi

# The root's checkout is a git repository holding the PLAN the plan verb reads.
(cd "$A" && git init -q . && git config user.email t@example.com && git config user.name t \
    && mkdir -p docs/plans && printf '# PLAN\n\n### Step 1: one\n\n### Step 2: two\n' > docs/plans/PLAN-topic.md \
    && git add docs/plans/PLAN-topic.md && git commit -q -m plan) || { echo "FAIL: could not make the fixture repository" >&2; exit 1; }

new_store() {
    rm -rf "$RECORD_KOTO_STORE"
    mkdir -p "$RECORD_KOTO_STORE"
    (cd "$A" && koto init "$S" --template t >/dev/null && printf '%s' "$RID" | koto context add "$S" run_id)
    : > "$RECORD_KOTO_STORE/calls.log"
}
run_trail() { # run_trail <args>: from the root's checkout
    OUT=$(cd "$A" && bash "$TRAIL" "$@" </dev/null 2>"$WORK/stderr")
    RC=$?
}
get_in() { # get_in <dir> <session> <key>
    (cd "$1" && koto context get "$2" "$3" 2>/dev/null)
}
root_get() { get_in "$A" "$S" "$1"; }
keys() { (cd "$A" && koto context list "$S"); }
writes() { grep -cE "$(printf '\t')(init|context add|context remove|decisions record) " "$RECORD_KOTO_STORE/calls.log"; }
run_trail_in() { # run_trail_in <stdin file> <args>: from the root's checkout
    local in=$1
    shift
    OUT=$(cd "$A" && bash "$TRAIL" "$@" <"$in" 2>"$WORK/stderr")
    RC=$?
}
doc() { printf '%s' "$1" > "$WORK/in.json"; } # doc <json>: the next stdin
decisions() { (cd "$A" && koto decisions list "$S"); }
# refused <label> <args>: the call exits 65 (or 64 when $WANT is set) and
# leaves the key list and the decision log as they were.
refused() {
    local label=$1 want=${WANT:-65} before
    shift
    before=$(keys)
    : > "$RECORD_KOTO_STORE/calls.log"
    run_trail_in "$WORK/in.json" "$@"
    if [ "$RC" -eq "$want" ] && [ "$(keys)" = "$before" ] && [ "$(writes)" -eq 0 ]; then
        pass "$label: $want, key list unchanged, nothing written"
    else
        fail "$label: exit $RC (want $want), writes $(writes), keys [$(keys)] were [$before], stderr [$(cat "$WORK/stderr")]"
    fi
}

# --- self ---------------------------------------------------------------------------

new_store
run_trail self --session "$S"
SELF=$(root_get trail/self)
SID=$(cd "$A" && koto session list | jq -r --arg s "$S" '.[] | select(.id == $s) | .session_id')
if [ "$RC" -eq 0 ] && [ "$(jq -r '.workspace' <<<"$SELF")" = "$A" ] && [ "$(jq -r '.session' <<<"$SELF")" = "$S" ] \
    && [ "$(jq -r '.session_id' <<<"$SELF")" = "$SID" ] && [ "$(jq -r '.run_id' <<<"$SELF")" = "$RID" ]; then
    pass "self: trail/self names the checkout, the session, its koto id and its run_id"
else
    fail "self: exit $RC, [$SELF], stderr [$(cat "$WORK/stderr")]"
fi

new_store
(cd "$A" && koto context remove "$S" run_id)
run_trail self --session "$S"
[ "$RC" -eq 65 ] && [ -z "$(root_get trail/self)" ] && pass "self: a session with no run_id refuses (65), nothing written" \
    || fail "self without run_id: exit $RC"

# --- pr -------------------------------------------------------------------------------

new_store
run_trail pr --session "$S" --repo Octo/Repo.X --number 12 --role home --state open
DOC=$(root_get trail/pr/octo.repo.x.12)
if [ "$RC" -eq 0 ] && [ "$(jq -c '{repo, number, role, state}' <<<"$DOC")" = '{"repo":"octo/repo.x","number":12,"role":"home","state":"open"}' ] \
    && [[ $(jq -r '.recorded_at' <<<"$DOC") =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]; then
    pass "pr: trail/pr/<owner>.<repo>.<n> holds the lowercased repository, the number, role, state and time"
else
    fail "pr: exit $RC, [$DOC], stderr [$(cat "$WORK/stderr")]"
fi

for args in "--repo o/r --number 7 --role boss --state open" \
            "--repo o/r --number 7 --role home --state shipped" \
            "--repo o --number 7 --role home --state open" \
            "--repo o/r/x --number 7 --role home --state open" \
            "--repo -o/r --number 7 --role home --state open" \
            "--repo o/.. --number 7 --role home --state open" \
            "--repo o/r --number 0 --role home --state open" \
            "--repo o/r --number 7x --role home --state open"; do
    new_store
    # shellcheck disable=SC2086
    run_trail pr --session "$S" $args
    [ "$RC" -eq 65 ] && [ "$(writes)" -eq 0 ] && pass "pr refuses [$args] (65), nothing written" \
        || fail "pr [$args]: exit $RC, writes $(writes)"
done

# --- index ------------------------------------------------------------------------------

DIR="/tmp/shirabe-run-record/$OWNER"
new_store
run_trail index --repo "$OWNER/R" --number 7 --session "$S" --mode single-pr --topic topic
CANON=$(cd "$DIR" 2>/dev/null && pwd -P)
NAME="pr.$OWNER.r.7"
ENTRY=$(get_in "$DIR" "$NAME" "run/$RID")
SID=$(cd "$A" && koto session list | jq -r --arg s "$S" '.[] | select(.id == $s) | .session_id')
if [ "$RC" -eq 0 ] \
    && [ "$(jq -c '{workspace, session, session_id, mode, topic}' <<<"$ENTRY")" = "$(jq -nc --arg w "$A" --arg s "$S" --arg i "$SID" '{workspace: $w, session: $s, session_id: $i, mode: "single-pr", topic: "topic"}')" ] \
    && [[ $(jq -r '.written_at' <<<"$ENTRY") =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]; then
    pass "index: run/<run_id> in pr.<owner>.<repo>.<n> names the root's workspace, session, id, mode and topic"
else
    fail "index: exit $RC, entry [$ENTRY], stderr [$(cat "$WORK/stderr")]"
fi
if grep -qF "$(printf '%s\tinit %s --template ' "$CANON" "$NAME")" "$RECORD_KOTO_STORE/calls.log" \
    && grep -qF "$(printf '%s\tcontext add %s run/%s' "$CANON" "$NAME" "$RID")" "$RECORD_KOTO_STORE/calls.log"; then
    pass "index: the session is opened and written from the shared address"
else
    fail "index calls: [$(cat "$RECORD_KOTO_STORE/calls.log")]"
fi
if [ -n "$(root_get trail/self)" ]; then
    pass "index: a root with no trail/self gets one first"
else
    fail "index: no trail/self written"
fi
if grep -q 'skill-session.md --attach-live' "$RECORD_KOTO_STORE/calls.log"; then
    pass "index: the index session is opened from the skill-session template, attaching when it exists"
else
    fail "index template: [$(grep init "$RECORD_KOTO_STORE/calls.log")]"
fi

run_trail index --repo "$OWNER/r" --number 7 --session "$S" --mode single-pr --topic topic
[ "$RC" -eq 0 ] && pass "index: a second write attaches to the index session and rewrites the entry" \
    || fail "index again: exit $RC, stderr [$(cat "$WORK/stderr")]"

# A trail/self naming another session is not this root's address.
new_store
(cd "$A" && jq -nc --arg w "$A" '{workspace: $w, session: "execute-other", session_id: "abc", run_id: "00112233445566778899aabbccddeeff"}' \
    | koto context add "$S" trail/self)
run_trail index --repo "$OWNER/r" --number 8 --session "$S" --mode single-pr --topic topic
[ "$RC" -eq 65 ] && [ -z "$(get_in "$DIR" "pr.$OWNER.r.8" "run/$RID")" ] \
    && pass "index: a trail/self naming another session refuses (65), no entry" \
    || fail "index with a foreign trail/self: exit $RC"

# A coordinated root's trail/self is record-coord-setup.sh's, written in the
# coordination checkout: an index entry for a node PR, written from the
# node's worktree, never writes one in its place.
new_store
run_trail index --repo "$OWNER/r" --number 12 --session "$S" --mode coordinated --topic topic
[ "$RC" -eq 65 ] && [ "$(writes)" -eq 0 ] && [ -z "$(root_get trail/self)" ] \
    && pass "index --mode coordinated: a root with no trail/self refuses (65), writes none, no entry" \
    || fail "coordinated index without trail/self: exit $RC, writes $(writes)"
run_trail self --session "$S"
run_trail index --repo "$OWNER/r" --number 12 --session "$S" --mode coordinated --topic topic
[ "$RC" -eq 0 ] && [ "$(jq -r .mode <<<"$(get_in "$DIR" "pr.$OWNER.r.12" "run/$RID")")" = coordinated ] \
    && pass "index --mode coordinated: with the root's trail/self, the entry is written" \
    || fail "coordinated index: exit $RC, stderr [$(cat "$WORK/stderr")]"

for args in "--mode serial --topic topic" "--mode single-pr --topic Topic" "--mode single-pr --topic a/b"; do
    new_store
    # shellcheck disable=SC2086
    run_trail index --repo "$OWNER/r" --number 7 --session "$S" $args
    [ "$RC" -eq 65 ] && [ "$(writes)" -eq 0 ] && pass "index refuses [$args] (65), nothing written" \
        || fail "index [$args]: exit $RC"
done

new_store
export RECORD_KOTO_WORKSPACE_OPTION=present
run_trail pr --session "$S" --repo "$OWNER/r" --number 9 --role home --state open
R1=$RC
run_trail index --repo "$OWNER/r" --number 9 --session "$S" --mode single-pr --topic topic
unset RECORD_KOTO_WORKSPACE_OPTION
if [ "$R1" -eq 0 ] && [ "$RC" -eq 0 ] && ! grep -q -- '--workspace' "$RECORD_KOTO_STORE/calls.log"; then
    pass "option present: every write still runs from its directory, none carries --workspace"
else
    fail "present-mode writes: pr $R1, index $RC, calls [$(cat "$RECORD_KOTO_STORE/calls.log")]"
fi

# --- plan -------------------------------------------------------------------------------------

new_store
run_trail plan --session "$S" --step step-1 --plan docs/plans/PLAN-topic.md
SNAP=$(root_get trail/plan/step-1.json)
HEAD_SHA=$(cd "$A" && git rev-parse HEAD)
(cd "$A" && koto context get "$S" trail/plan/step-1.md --to-file "$WORK/text.md")
(cd "$A" && git show HEAD:docs/plans/PLAN-topic.md) > "$WORK/want.md"
if [ "$RC" -eq 0 ] && cmp -s "$WORK/text.md" "$WORK/want.md" \
    && [ "$(jq -r .sha <<<"$SNAP")" = "$HEAD_SHA" ] && [ "$(jq -r .entry <<<"$SNAP")" = "### Step 1: one" ] \
    && [[ $(jq -r .recorded_at <<<"$SNAP") =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]; then
    pass "plan: the PLAN's committed text byte for byte, HEAD's sha, the step's heading and the time"
else
    fail "plan: exit $RC, [$SNAP], stderr [$(cat "$WORK/stderr")]"
fi
run_trail plan --session "$S" --step issue-4 --plan docs/plans/PLAN-topic.md
[ "$RC" -eq 0 ] && [ "$(jq -r .entry <<<"$(root_get trail/plan/issue-4.json)")" = null ] \
    && pass "plan: a step id with no heading in the PLAN records entry null" \
    || fail "plan issue-4: exit $RC, [$(root_get trail/plan/issue-4.json)]"

# A coordinated run's plan_abs: the PLAN by absolute path in another
# checkout C (the coordination checkout), read at C's HEAD, from A.
C="$WORK/c"
mkdir -p "$C"
C=$(cd "$C" && pwd -P)
(cd "$C" && git init -q . && git config user.email t@example.com && git config user.name t \
    && mkdir -p docs/plans && printf '# PLAN\n\nthe coordination checkout copy\n' > docs/plans/PLAN-topic.md \
    && git add docs/plans/PLAN-topic.md && git commit -q -m plan) || { echo "FAIL: could not make the second fixture repository" >&2; exit 1; }
run_trail plan --session "$S" --step work-on-topic-core-1 --plan "$C/docs/plans/PLAN-topic.md"
(cd "$A" && koto context get "$S" trail/plan/work-on-topic-core-1.md --to-file "$WORK/abs-text.md")
(cd "$C" && git show HEAD:docs/plans/PLAN-topic.md) > "$WORK/abs-want.md"
SNAP=$(root_get trail/plan/work-on-topic-core-1.json)
if [ "$RC" -eq 0 ] && cmp -s "$WORK/abs-text.md" "$WORK/abs-want.md" \
    && [ "$(jq -r .sha <<<"$SNAP")" = "$(cd "$C" && git rev-parse HEAD)" ] && [ "$(jq -r .entry <<<"$SNAP")" = null ]; then
    pass "plan: an absolute PLAN path is read at its own checkout's HEAD, text and sha, written to this root"
else
    fail "plan absolute: exit $RC, [$SNAP], stderr [$(cat "$WORK/stderr")]"
fi
mkdir -p "$WORK/plain/docs/plans" "$C/docs/plans/sub"
printf 'x\n' > "$WORK/plain/docs/plans/PLAN-topic.md"

doc '{}'
for p in ../secrets.md docs/plans/sub/PLAN-x.md docs/plans/PLAN-Topic.md \
         docs/plans/PLAN-topic.md.bak docs/plans/../plans/PLAN-topic.md \
         "$C/docs/plans/sub/PLAN-x.md" "$C/docs/plans/PLAN-Topic.md" "$C/docs/PLAN-topic.md" \
         "$WORK/plain/docs/plans/PLAN-topic.md" "$WORK/missing/docs/plans/PLAN-topic.md" "$C/docs/plans/PLAN-other.md"; do
    refused "plan refuses --plan [$p]" plan --session "$S" --step step-2 --plan "$p"
done
refused "plan refuses a PLAN not committed at HEAD" plan --session "$S" --step step-2 --plan docs/plans/PLAN-other.md
(cd "$A" && printf '# PLAN\n\ntoken ghp_%s\n' "abcdefghijklmnopqrstuvwxyz0123456789" > docs/plans/PLAN-leak.md \
    && git add docs/plans/PLAN-leak.md && git commit -q -m leak)
refused "plan refuses a PLAN holding a token" plan --session "$S" --step step-2 --plan docs/plans/PLAN-leak.md
refused "plan refuses a step id outside the pattern" plan --session "$S" --step ../x --plan docs/plans/PLAN-topic.md

# --- step ---------------------------------------------------------------------------------------

new_store
run_trail step --session "$S" --step step-1 --child "$S.step-1"
REC=$(root_get trail/step/step-1)
[ "$RC" -eq 0 ] && [ "$REC" = "$(jq -nc --arg s "$S.step-1" --arg w "$A" '{session: $s, workspace: $w, superseded: []}')" ] \
    && pass "step: trail/step/<step> names the step session and this checkout, nothing superseded" \
    || fail "step: exit $RC, [$REC], stderr [$(cat "$WORK/stderr")]"
run_trail step --session "$S" --step step-1 --child "$S.step-1" --supersede
[ "$RC" -eq 0 ] && [ "$(root_get trail/step/step-1)" = "$REC" ] \
    && pass "step: the same session again changes nothing, --supersede or not" \
    || fail "step again: exit $RC, [$(root_get trail/step/step-1)]"
doc '{}'
refused "step refuses another session without --supersede" step --session "$S" --step step-1 --child "$S.step-1_r2"
run_trail step --session "$S" --step step-1 --child "$S.step-1_r2" --supersede
run_trail step --session "$S" --step step-1 --child "$S.step-1_r3" --supersede
[ "$RC" -eq 0 ] && [ "$(jq -c '{session, superseded}' <<<"$(root_get trail/step/step-1)")" \
    = "$(jq -nc --arg s "$S" '{session: ($s + ".step-1_r3"), superseded: [($s + ".step-1"), ($s + ".step-1_r2")]}')" ] \
    && pass "step: a new step agent's session, with --supersede, lists each earlier name as superseded" \
    || fail "step supersede: exit $RC, [$(root_get trail/step/step-1)]"
refused "step refuses a child outside the session pattern" step --session "$S" --step step-2 --child "-x"

# A coordinated work item's session lives in its node's worktree.
mkdir -p "$WORK/node-wt"
WT=$(cd "$WORK/node-wt" && pwd -P)
run_trail step --session "$S" --step work-on-topic-core-1 --child work-on-topic-core-1 --child-workspace "$WORK/node-wt/."
[ "$RC" -eq 0 ] && [ "$(root_get trail/step/work-on-topic-core-1)" \
    = "$(jq -nc --arg w "$WT" '{session: "work-on-topic-core-1", workspace: $w, superseded: []}')" ] \
    && pass "step --child-workspace: the step session's workspace is that directory, canonical, written in this root" \
    || fail "step --child-workspace: exit $RC, [$(root_get trail/step/work-on-topic-core-1)], stderr [$(cat "$WORK/stderr")]"
refused "step refuses a relative --child-workspace" step --session "$S" --step step-3 --child x --child-workspace node-wt
refused "step refuses a --child-workspace that is not a directory" step --session "$S" --step step-3 --child x --child-workspace "$WORK/nope"
WANT=64 refused "step refuses --child-workspace given twice" step --session "$S" --step step-3 --child x \
    --child-workspace "$WT" --child-workspace "$WT"
WANT=64 refused "plan refuses --child-workspace" plan --session "$S" --step step-3 --plan docs/plans/PLAN-topic.md \
    --child-workspace "$WT"

# --- departure and decision ---------------------------------------------------------------------

new_store
N=0
for pair in "step-1 deviated" "step-2 deferral" "step-2 scope-change" "step-3 entry-rewritten"; do
    st=${pair% *}; kind=${pair#* }
    N=$((N + 1))
    doc "$(jq -nc --arg k "$kind" '{what: ("the " + $k + " part"), why: ("because of " + $k)}')"
    run_trail_in "$WORK/in.json" departure --session "$S" --step "$st" --kind "$kind"
    D=$(root_get "trail/departure/$N.json")
    if [ "$RC" -eq 0 ] && [ "$(jq -c '{step, kind, what, why}' <<<"$D")" \
        = "$(jq -nc --arg s "$st" --arg k "$kind" '{step: $s, kind: $k, what: ("the " + $k + " part"), why: ("because of " + $k)}')" ] \
        && [[ $(jq -r .at <<<"$D") =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]; then
        pass "departure $N: $kind against $st, with its what and a non-empty why"
    else
        fail "departure $kind: exit $RC, [$D], stderr [$(cat "$WORK/stderr")]"
    fi
done

doc '{"choice": "keep the cap", "rationale": "the PLAN says so", "alternatives_considered": ["drop it"]}'
run_trail_in "$WORK/in.json" decision --session "$S" --step step-2 --actor "agent:$S.step-2"
D1=$(root_get trail/decision/1.json)
doc '{"choice": "defer the export", "rationale": "the reviewer approved it"}'
run_trail_in "$WORK/in.json" decision --session "$S" --step step-2 --actor person
D2=$(root_get trail/decision/2.json)
doc '{"choice": "c", "rationale": "r"}'
run_trail_in "$WORK/in.json" decision --session "$S" --step step-3 --actor person:octo-cat
D3=$(root_get trail/decision/3.json)
if [ "$(jq -c '{step, actor, choice, rationale, alternatives_considered}' <<<"$D1")" \
        = "$(jq -nc --arg a "agent:$S.step-2" '{step: "step-2", actor: $a, choice: "keep the cap", rationale: "the PLAN says so", alternatives_considered: ["drop it"]}')" ] \
    && [ "$(jq -r .actor <<<"$D2")" = person ] && [ "$(jq -r .actor <<<"$D3")" = person:octo-cat ]; then
    pass "decision: each trail/decision/<n>.json names its step and actor (agent:<name>, person, person:<login>)"
else
    fail "decision trail: [$D1] [$D2] [$D3], stderr [$(cat "$WORK/stderr")]"
fi
if [ "$(decisions | jq -c '[.decisions.items[] | {choice, rationale}]')" \
    = '[{"choice":"keep the cap","rationale":"the PLAN says so"},{"choice":"defer the export","rationale":"the reviewer approved it"},{"choice":"c","rationale":"r"}]' ]; then
    pass "decision: the same choice and rationale go through koto decisions record"
else
    fail "decision log: [$(decisions)]"
fi

# The refusals: text as an argument is usage (64); a document the verb can't
# take is 65. Neither writes a key or records a decision.
doc '{"what": "w", "why": "y"}'
WANT=64 refused "departure refuses text passed as a flag" departure --session "$S" --step step-1 --kind deviated --what w
WANT=64 refused "departure refuses text passed as an argument" departure --session "$S" --step step-1 --kind deviated "the why"
WANT=64 refused "decision refuses text passed as a flag" decision --session "$S" --step step-1 --actor person --choice c
doc 'not json'
refused "departure refuses a stdin that isn't JSON" departure --session "$S" --step step-1 --kind deviated
doc '["what", "why"]'
refused "departure refuses a JSON document that isn't an object" departure --session "$S" --step step-1 --kind deviated
doc '{"what": "w"}'
refused "departure refuses a document without why" departure --session "$S" --step step-1 --kind deviated
doc '{"what": "w", "why": ""}'
refused "departure refuses an empty why" departure --session "$S" --step step-1 --kind deviated
doc '{"what": "w", "why": 3}'
refused "departure refuses a why that isn't text" departure --session "$S" --step step-1 --kind deviated
: > "$WORK/in.json"
refused "departure refuses an empty stdin" departure --session "$S" --step step-1 --kind deviated
doc "$(jq -nc --arg w "$(printf 'x%.0s' $(seq 1 16385))" '{what: $w, why: "y"}')"
refused "departure refuses a field over 16 KiB" departure --session "$S" --step step-1 --kind deviated
doc '{"what": "w", "why": "y"}'
refused "departure refuses a kind outside the set" departure --session "$S" --step step-1 --kind skipped
doc '{"choice": "c"}'
refused "decision refuses a document without rationale" decision --session "$S" --step step-1 --actor person
doc '{"choice": "c", "rationale": "r"}'
for actor in agent "agent:" "agent:-x" "person:" "person:a/b" "bot:x" human; do
    refused "decision refuses --actor [$actor]" decision --session "$S" --step step-1 --actor "$actor"
done
doc '{"choice": "c", "rationale": "r", "alternatives_considered": "one"}'
refused "decision refuses alternatives that aren't a list of text" decision --session "$S" --step step-1 --actor person

# Secret-shaped fixtures are built from parts so the source itself holds none.
TOKEN="gh""p_abcdefghijklmnopqrstuvwxyz0123456789"
doc "$(jq -nc --arg t "$TOKEN" '{what: "a leak", why: ("the token " + $t)}')"
refused "departure refuses a ghp_ token in its why" departure --session "$S" --step step-1 --kind deviated
KEY_HEADER="-----BEGIN OPENSSH ""PRIVATE KEY-----"
doc "$(jq -nc --arg k "$KEY_HEADER" '{choice: "c", rationale: ($k + "\nabc")}')"
refused "decision refuses a private-key header, koto decisions record included" decision --session "$S" --step step-1 --actor person
doc "$(jq -nc '{choice: "c", rationale: "r", alternatives_considered: ["curl -H x\nAuthorization: Bearer abc"]}')"
refused "decision refuses an Authorization: line in an alternative" decision --session "$S" --step step-1 --actor person
PAT="github""_pat_11ABCDEFG0123456789_abcdefghijk"
doc "$(jq -nc --arg p "$PAT" '{choice: $p, rationale: "r"}')"
refused "decision refuses a github_pat_ token" decision --session "$S" --step step-1 --actor person
for clean in "the ghp_ prefix names a token" "an Authorization: header" "AKIA is a key prefix"; do
    doc "$(jq -nc --arg w "$clean" '{what: $w, why: "prose about tokens, not one"}')"
    run_trail_in "$WORK/in.json" departure --session "$S" --step step-9 --kind deviated
    [ "$RC" -eq 0 ] && pass "departure takes prose that only names a shape: [$clean]" \
        || fail "prose [$clean]: exit $RC, stderr [$(cat "$WORK/stderr")]"
done

# --- snapshot and carry --------------------------------------------------------------------------

new_store
run_trail self --session "$S"
run_trail plan --session "$S" --step step-1 --plan docs/plans/PLAN-topic.md
run_trail step --session "$S" --step step-1 --child "$S.step-1"
doc '{"what": "w", "why": "y"}'
run_trail_in "$WORK/in.json" departure --session "$S" --step step-1 --kind entry-rewritten
(cd "$A" && printf 'x' | koto context add "$S" trail/stray)
run_trail snapshot --session "$S"
printf '%s' "$OUT" > "$WORK/snap.json"
if [ "$RC" -eq 0 ] && [ "$(jq -c 'keys' "$WORK/snap.json")" \
        = '["trail/departure/1.json","trail/plan/step-1.json","trail/plan/step-1.md","trail/step/step-1"]' ] \
    && grep -q 'trail/stray' "$WORK/stderr"; then
    pass "snapshot: every trail key but trail/self, one outside the layout left out and named"
else
    fail "snapshot: exit $RC, keys [$(jq -c keys "$WORK/snap.json")], stderr [$(cat "$WORK/stderr")]"
fi
# The replacement: a fresh session under the same name, holding one key of its own.
(cd "$A" && rm -rf "$RECORD_KOTO_STORE/ws" && koto init "$S" --template t >/dev/null \
    && printf 'mine' | koto context add "$S" trail/step/step-1)
run_trail_in "$WORK/snap.json" carry --session "$S"
(cd "$A" && koto context get "$S" trail/plan/step-1.md --to-file "$WORK/carried.md")
if [ "$RC" -eq 0 ] && [ "$OUT" = carried=3 ] && cmp -s "$WORK/carried.md" "$WORK/want.md" \
    && [ "$(root_get trail/step/step-1)" = mine ] && [ -z "$(root_get trail/self)" ] \
    && [ "$(jq -r .kind <<<"$(root_get trail/departure/1.json)")" = entry-rewritten ]; then
    pass "carry: the trail lands in the replacement byte for byte, a key it holds kept, trail/self not carried"
else
    fail "carry: exit $RC, out [$OUT], step [$(root_get trail/step/step-1)], stderr [$(cat "$WORK/stderr")]"
fi
run_trail_in "$WORK/snap.json" carry --session "$S"
[ "$RC" -eq 0 ] && [ "$OUT" = carried=0 ] && pass "carry again: nothing left to write (carried=0)" \
    || fail "carry again: exit $RC, out [$OUT]"
new_store
doc '{"trail/self": "x"}'
refused "carry refuses a snapshot naming trail/self" carry --session "$S"
doc '{"trail/plan/step-1.md": "x", "run/setup": "{}"}'
refused "carry refuses a snapshot naming a key outside the layout" carry --session "$S"
doc '{"trail/step/step-1": {"session": "x"}}'
refused "carry refuses a value that isn't text" carry --session "$S"
doc '[]'
refused "carry refuses a snapshot that isn't an object" carry --session "$S"

# --- usage and koto failures ------------------------------------------------------------------

for args in "" "nope --session $S" "pr --session $S" "self --session $S --session $S" \
            "self --session" "self --session $S --repo o/r" "pr --session $S --repo o/r --number 7 --role home --state open --extra x"; do
    new_store
    # shellcheck disable=SC2086
    run_trail $args
    [ "$RC" -eq 64 ] && [ ! -s "$RECORD_KOTO_STORE/calls.log" ] && pass "usage: [$args] is 64, no koto call" \
        || fail "usage [$args]: exit $RC, calls [$(cat "$RECORD_KOTO_STORE/calls.log")]"
done

new_store
export RECORD_KOTO_FAIL_WRITES=1
run_trail pr --session "$S" --repo o/r --number 7 --role home --state open
unset RECORD_KOTO_FAIL_WRITES
[ "$RC" -eq 70 ] && pass "a failed koto write is 70" || fail "failed write: exit $RC"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
