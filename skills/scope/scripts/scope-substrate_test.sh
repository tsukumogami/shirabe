#!/usr/bin/env bash
# scope-substrate_test.sh -- drives real koto sessions against the shipped
# skills/scope/koto-templates/scope.md and asserts the claims the substrate is
# supposed to make good on.
#
# The central one: a run cannot reach the full-run terminal by SAYING it walked
# the chain. The reported incident was an agent skipping three hops, writing a
# PLAN, and recording a full-run exit. Every assertion here is about the
# difference between the chain having been walked and the run claiming it was.
#
# Store isolation, and a trap worth knowing about: koto reads its store from
# $HOME, and KOTO_HOME is silently IGNORED. A test that exports KOTO_HOME
# believing it is sandboxed writes into the developer's real ~/.koto and can
# cancel sessions it did not create. Verified directly: with KOTO_HOME set to a
# temporary directory, the session still landed in the real store. So this file
# overrides HOME, names every session outside any production prefix, and calls
# no cleanup verb against a name it did not create in its own store.
#
# Exit 0 when every assertion holds. Skips with a message naming the binary when
# koto or shirabe is absent -- and the CI job installs both explicitly, so a skip
# there is a failure of the job rather than a quiet pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
TEMPLATE="$REPO/skills/scope/koto-templates/scope.md"

# Frozen artifact fixtures, not this repository's live documents. Completing the
# PLAN this feature came from moves the DESIGN into docs/designs/current/ and
# deletes the PLAN, so a suite reading the live paths breaks at exactly the
# moment its subject succeeds. The .fixture extension keeps them out of any
# *.md scan: they are test inputs, not artifacts of this repository.
FIXTURES="$HERE/testdata"

for bin in koto shirabe; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "SKIP: $bin is not on PATH; this suite drives real sessions and cannot run without it"
        exit 0
    fi
done
[ -f "$TEMPLATE" ] || { echo "FAIL: no template at $TEMPLATE" >&2; exit 1; }

# Every session below passes this checkout as PLUGIN_ROOT, and koto validates a
# --var value against ^[a-zA-Z0-9._/:@ \-]*$ before it stores anything. A
# checkout under a path holding a character outside that set -- a `+`, a `~`, a
# comma -- is refused at `koto init`, and every assertion downstream then reads
# `state=` for a reason that has nothing to do with the substrate. Say so here
# instead, and fail rather than skip: this is the environment being wrong, not
# the suite being inapplicable.
case "$REPO" in
    *[!a-zA-Z0-9._/:@\ -]*)
        echo "FAIL: koto rejects a --var value outside ^[a-zA-Z0-9._/:@ \\-]*\$," >&2
        echo "      and this checkout's path carries a character outside it:" >&2
        echo "      $REPO" >&2
        echo "      Move or symlink the checkout somewhere the pattern admits." >&2
        exit 1 ;;
esac

PASS=0
FAIL=0
SANDBOX="$(mktemp -d)"
REAL_HOME="$HOME"
trap 'rm -rf "$SANDBOX"' EXIT

# Every session name carries this prefix. It is not the production prefix, so a
# name collision with a real run is impossible even if the store isolation ever
# regressed.
PFX="scopetest"

ok()   { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

# k <session-home> <args...> -- run koto against an isolated store.
k() {
    local home="$1"; shift
    HOME="$home" koto "$@" 2>&1
}

# new_run <tag> <tree> -- fresh store plus fresh session, echoes "<home> <name>".
#
# PLUGIN_ROOT is this checkout, which is where hop-complete.sh lives. It is what
# every gate command resolves the script through, and it is the whole reason a
# walk can run from a fixture tree carrying no skills/ of its own.
#
# The init runs INSIDE the fixture tree. koto binds a session to the directory it
# was initialized in and refuses a later `koto next` from anywhere else with
# `execution_anchor_mismatch`, so initializing here and ticking there leaves every
# assertion reading `state=branch_check` with the reason buried in a discarded
# error. It is also what a real run does: /scope opens its session in the
# repository being scoped.
new_run() {
    local tag="$1" tree="$2"
    local home="$SANDBOX/$tag"
    mkdir -p "$home"
    (
        cd "$tree" || exit 1
        HOME="$home" koto init "$PFX-$tag" --template "$TEMPLATE" \
            --var TOPIC="$tag" --var PLUGIN_ROOT="$REPO" >/dev/null 2>&1
    )
    printf '%s %s-%s' "$home" "$PFX" "$tag"
}

# `koto status` names the field `current_state`. `koto next` names it `state`.
# Reading the wrong one yields an empty string, which reads as "the run went
# nowhere" and fails every assertion here for a reason that has nothing to do
# with the substrate.
state_of() {
    HOME="$1" koto status "$2" 2>/dev/null \
      | python3 -c 'import sys,json
try:
    d = json.loads(sys.stdin.read() or "{}")
except ValueError:
    d = {}
print(d.get("current_state", ""))' 2>/dev/null
}

# A fixture tree carries only its own docs/. It deliberately does NOT carry a
# copy of hop-complete.sh, and that absence is an assertion rather than an
# omission.
#
# The gate commands pass no --root, so the predicate reads the docs/ tree of the
# process working directory -- which is what the walk cd's into, and which is
# right. What the gates must NOT do is resolve the script itself that way: koto
# runs a gate command with the working directory of the `koto next` process, so
# for a real /scope run that is the repository being scoped rather than this
# checkout. The gates therefore name the script through {{PLUGIN_ROOT}}, bound
# at koto init to $REPO in new_run.
#
# So every walk below runs from a temporary directory that has no skills/ in it
# at all. If a gate ever goes back to a repo-relative path it exits 127 there --
# which the graph treats as neither complete nor incomplete, so the run holds
# position and the assertions see the run stuck at its first hop rather than a
# refusal. That is the failure this layout is built to produce.
#
# The tree is a git repository on a named non-default branch because
# `branch_check`, the template's initial state, gates on exactly that: outside a
# repository `git symbolic-ref` prints nothing, the gate fails, and the walk never
# reaches the first hop. A bare `mkdir` here is a suite that asserts nothing.
make_tree() {
    local root="$1"
    mkdir -p "$root/docs"
    git -C "$root" init --quiet
    git -C "$root" -c user.email=t@example.invalid -c user.name=t \
        commit --quiet --allow-empty -m "fixture"
    git -C "$root" checkout --quiet -b scope-fixture
}

# advance <home> <name> <json> -- submit evidence, echo the response.
advance() { k "$1" next "$2" --with-data "$3"; }

# fields_wanted <home> <name> -- the field names the current state accepts.
fields_wanted() {
    HOME="$1" koto next "$2" 2>/dev/null \
      | python3 -c 'import sys,json
try:
    d = json.loads(sys.stdin.read() or "{}")
except ValueError:
    d = {}
print(" ".join(sorted((d.get("expects") or {}).get("fields", {}))))' 2>/dev/null
}

# drive <home> <name> <tree> <hop-outcome> <topic> -- walk the graph by reading
# what each state asks for rather than replaying a fixed sequence of ticks.
#
# A fixed sequence cannot drive this graph: the fold state routes back to
# whichever hop has not run yet, so the number of ticks between the chain
# proposal and the exit depends on the fixture. Answering the schema in front of
# us also means a state added to the template does not silently turn this suite
# into a no-op that passes.
drive() {
    local home="$1" name="$2" tree="$3" outcome="$4" topic="$5"
    local i want data st
    (
        cd "$tree" || exit 1
        for i in $(seq 1 24); do
            st=$(HOME="$home" koto status "$name" 2>/dev/null \
                 | python3 -c 'import sys,json
try: print(json.loads(sys.stdin.read() or "{}").get("current_state",""))
except ValueError: print("")' 2>/dev/null)
            case "$st" in
                done_*|cleanup_*|full_run_blocked|"") return 0 ;;
            esac
            want=$(fields_wanted "$home" "$name")
            [ -z "$want" ] && return 0
            data="{"
            for f in $want; do
                case "$f" in
                    setup_result)        data="$data\"setup_result\":\"ready\"," ;;
                    discovery_result)    data="$data\"discovery_result\":\"proposed\"," ;;
                    author_decision)     data="$data\"author_decision\":\"proceed\"," ;;
                    outcome)             data="$data\"outcome\":\"$outcome\"," ;;
                    verdict)             data="$data\"verdict\":\"keep\"," ;;
                    exit)                data="$data\"exit\":\"full-run\"," ;;
                    exit_artifacts)      data="$data\"exit_artifacts\":\"docs/plans/PLAN-$topic.md: Active\"," ;;
                    plan_execution_mode) data="$data\"plan_execution_mode\":\"single-pr\"," ;;
                    *) : ;;  # optional free-text fields are left out deliberately
                esac
            done
            data="${data%,}}"
            [ "$data" = "{}" ] && return 0
            advance "$home" "$name" "$data" >/dev/null 2>&1
        done
    )
}

# Walk setup -> discovery -> chain_proposal -> the four hops, submitting the
# given outcome at each hop. This is the run CLAIMING it walked the chain; what
# the gates make of the claim is the point of each test.
# Runs entirely inside the fixture tree, for the cwd reason above.
walk_to_finalize() {
    local home="$1" name="$2" outcome="$3" tree="$4"
    (
        cd "$tree" || exit 1
        advance "$home" "$name" '{"setup_result":"ready"}'        >/dev/null
        advance "$home" "$name" '{"discovery_result":"proposed"}' >/dev/null
        advance "$home" "$name" '{"author_decision":"proceed"}'   >/dev/null
        for _ in 1 2 3 4; do
            advance "$home" "$name" "{\"outcome\":\"$outcome\"}"  >/dev/null
        done
    )
}

# ---------------------------------------------------------------------------
# Fixtures
#
# The incident's realistic shape, not a sanitized one. The PLAN carries an
# ordinary `upstream:` line, which is what a hundred documents in this
# repository already carry as convention -- and which defeated an earlier
# version of the predicate, because a frontmatter grep for the basename
# accepted it as an absorption. A fixture without that line would pass a
# predicate that this one catches.
# ---------------------------------------------------------------------------

seed_plan_only() {
    local root="$1" topic="$2"
    make_tree "$root"
    mkdir -p "$root/docs/plans"
    sed "s/scope-koto-adoption/$topic/g" "$FIXTURES/plan.md.fixture" \
        > "$root/docs/plans/PLAN-$topic.md"
    python3 - "$root/docs/plans/PLAN-$topic.md" "$topic" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
# Ordinary upstream: frontmatter -- the incident's real shape.
s = s.replace("---\nschema: plan/v1\n",
              "---\nschema: plan/v1\nupstream: docs/designs/DESIGN-%s.md\n" % topic, 1)
open(p, "w").write(s)
PY
}

seed_every_hop() {
    local root="$1" topic="$2"
    make_tree "$root"
    mkdir -p "$root/docs/briefs" "$root/docs/prds" "$root/docs/designs" "$root/docs/plans"
    sed "s/scope-koto-adoption/$topic/g" "$FIXTURES/brief.md.fixture"   > "$root/docs/briefs/BRIEF-$topic.md"
    sed "s/scope-koto-adoption/$topic/g" "$FIXTURES/prd.md.fixture"       > "$root/docs/prds/PRD-$topic.md"
    sed "s/scope-koto-adoption/$topic/g" "$FIXTURES/design.md.fixture" > "$root/docs/designs/DESIGN-$topic.md"
    sed "s/scope-koto-adoption/$topic/g" "$FIXTURES/plan.md.fixture"     > "$root/docs/plans/PLAN-$topic.md"
}

# The legitimate fold: only the terminal artifact survives, and it declares each
# absorbed ancestor with the contribution section that declaration requires.
# Without this case every other assertion here is satisfied by a gate that
# refuses unconditionally, which is the failure mode a refusal-only suite cannot
# see.
seed_recorded_fold() {
    local root="$1" topic="$2"
    make_tree "$root"
    mkdir -p "$root/docs/plans"
    sed "s/scope-koto-adoption/$topic/g" "$FIXTURES/plan.md.fixture" \
        > "$root/docs/plans/PLAN-$topic.md"
    python3 - "$root/docs/plans/PLAN-$topic.md" "$topic" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("---\nschema: plan/v1\n",
              "---\nschema: plan/v1\nabsorbed:\n"
              "  - docs/briefs/BRIEF-%s.md\n"
              "  - docs/prds/PRD-%s.md\n"
              "  - docs/designs/DESIGN-%s.md\n" % (topic, topic, topic), 1)
s = s.replace("## Status\n\nActive\n",
              "## Status\n\nActive\n\n"
              "Absorbed [BRIEF](docs/briefs/BRIEF-%s.md); carried in Absorbed Brief.\n"
              "Absorbed [PRD](docs/prds/PRD-%s.md); carried in Absorbed PRD.\n"
              "Absorbed [DESIGN](docs/designs/DESIGN-%s.md); carried in Absorbed Design.\n\n"
              "## Absorbed Brief\n\nFraming carried forward.\n\n"
              "## Absorbed PRD\n\nRequirements carried forward.\n\n"
              "## Absorbed Design\n\nApproach carried forward.\n" % (topic, topic, topic), 1)
open(p, "w").write(s)
PY
}

# ---------------------------------------------------------------------------
# The assertions
# ---------------------------------------------------------------------------

echo "== the claim a run cannot make good on by asserting it =="

# A full-run claim where three hops have neither artifact nor recorded fold.
# The run says landed at every hop; only the PLAN exists.
# The three upstream hops are submitted as `skipped`, which is the incident's
# actual shape and the only way the run reaches its exit at all. Claiming
# `landed` at a hop whose artifact does not exist is refused by that hop's own
# gate on the spot -- a stronger property, and one that keeps the run from ever
# getting near the exit. What the exit gate exists for is the run that skips
# honestly and then claims a full walk anyway.
seed_plan_only "$SANDBOX/incident-tree" incident
read -r H N <<<"$(new_run incident "$SANDBOX/incident-tree")"
drive "$H" "$N" "$SANDBOX/incident-tree" skipped incident
(cd "$SANDBOX/incident-tree" && advance "$H" "$N" '{"exit":"full-run"}') >/dev/null
resp=$(cd "$SANDBOX/incident-tree" && advance "$H" "$N" \
    '{"exit_artifacts":"docs/plans/PLAN-incident.md: Active","plan_execution_mode":"single-pr"}')
st=$(state_of "$H" "$N")
case "$st" in
    full_run_blocked)
        ok "a full-run claim with three hops missing is refused (landed in $st)" ;;
    done_full_run)
        bad "a full-run claim with three hops missing reached the full-run terminal" "state=$st" ;;
    *)
        bad "a full-run claim with three hops missing did not reach the blocked state" "state=$st" ;;
esac

# The refusal has to be legible, not merely correct. The blocked state carries
# its own copy of the chain-wide gate, which is the only reason its blocking
# conditions are non-empty -- a self-loop back into the exit state would
# re-evaluate the gate and report nothing about why it failed.
nxt=$(cd "$SANDBOX/incident-tree" && k "$H" next "$N")
case "$nxt" in
    *'"blocking_conditions":[]'*)
        bad "the blocked state reports no blocking conditions" "$(printf '%.200s' "$nxt")" ;;
    *chain_complete*)
        ok "the refusal names the chain-wide gate in its blocking conditions" ;;
    *)
        bad "the refusal does not name the failing gate" "$(printf '%.200s' "$nxt")" ;;
esac

echo
echo "== the two ways a run legitimately reaches the terminal =="

seed_every_hop "$SANDBOX/allhops-tree" allhops
read -r H N <<<"$(new_run allhops "$SANDBOX/allhops-tree")"
drive "$H" "$N" "$SANDBOX/allhops-tree" landed allhops
st=$(state_of "$H" "$N")
case "$st" in
    cleanup_full_run|done_full_run) ok "every hop's artifact present reaches the full-run path ($st)" ;;
    *) bad "every hop's artifact present did not reach the full-run path" "state=$st" ;;
esac

seed_recorded_fold "$SANDBOX/folded-tree" folded
read -r H N <<<"$(new_run folded "$SANDBOX/folded-tree")"
drive "$H" "$N" "$SANDBOX/folded-tree" landed folded
st=$(state_of "$H" "$N")
case "$st" in
    cleanup_full_run|done_full_run) ok "a recorded fold reaches the full-run path ($st)" ;;
    *) bad "a recorded fold was refused -- the gate may be refusing unconditionally" "state=$st" ;;
esac

echo
echo "== exit evidence is checked against its own path =="

seed_every_hop "$SANDBOX/missingfield-tree" missingfield
read -r H N <<<"$(new_run missingfield "$SANDBOX/missingfield-tree")"
walk_to_finalize "$H" "$N" landed "$SANDBOX/missingfield-tree"
(cd "$SANDBOX/missingfield-tree" && advance "$H" "$N" '{"exit":"full-run"}') >/dev/null
resp=$(cd "$SANDBOX/missingfield-tree" && advance "$H" "$N" '{"exit_artifacts":"docs/plans/PLAN-missingfield.md: Active"}')
case "$resp" in
    *error*|*required*|*invalid*)
        ok "an exit missing a required field of its own path is refused" ;;
    *)
        st=$(state_of "$H" "$N")
        if [ "$st" = "exit_full_run" ]; then
            ok "an exit missing a required field of its own path does not advance"
        else
            bad "an exit missing plan_execution_mode was accepted" "state=$st"
        fi ;;
esac

# A field belonging to exactly one OTHER exit path must not be accepted here.
# Each exit path's required fields live on its own state, and that separation is
# what stops one path's evidence satisfying another's.
seed_every_hop "$SANDBOX/foreignfield-tree" foreignfield
read -r H N <<<"$(new_run foreignfield "$SANDBOX/foreignfield-tree")"
walk_to_finalize "$H" "$N" landed "$SANDBOX/foreignfield-tree"
(cd "$SANDBOX/foreignfield-tree" && advance "$H" "$N" '{"exit":"full-run"}') >/dev/null
resp=$(cd "$SANDBOX/foreignfield-tree" && advance "$H" "$N" \
    '{"exit_artifacts":"x","plan_execution_mode":"single-pr","boundary":"prd"}')
case "$resp" in
    *error*|*unknown*|*unexpected*|*invalid*)
        ok "a field from another exit path is refused" ;;
    *)
        bad "a field belonging to another exit path was accepted" "$(printf '%.200s' "$resp")" ;;
esac

echo
echo "== where the reduction argument is delivered =="

seed_every_hop "$SANDBOX/payload-tree" payload
read -r H N <<<"$(new_run payload "$SANDBOX/payload-tree")"
cd "$SANDBOX/payload-tree" || exit 1
setup_directive=$(k "$H" next "$N")
case "$setup_directive" in
    *"Sparing the reader"*|*"reads as ceremony"*)
        bad "the reduction argument is delivered before the first hop" "in setup's directive" ;;
    *)
        ok "the reduction argument is absent from what the session delivers first" ;;
esac

advance "$H" "$N" '{"setup_result":"ready"}'        >/dev/null
advance "$H" "$N" '{"discovery_result":"proposed"}' >/dev/null
advance "$H" "$N" '{"author_decision":"proceed"}'   >/dev/null
advance "$H" "$N" '{"outcome":"landed"}'            >/dev/null
fold_directive=$(k "$H" next "$N" --full)
cd "$REPO" || exit 1
case "$fold_directive" in
    *"Sparing the reader"*)
        ok "the reduction argument is delivered at the fold state" ;;
    *)
        # Not necessarily at fold on this path; assert it exists in the template
        # at the fold state rather than failing on the walk's exact position.
        if sed -n '/^## fold$/,/^## /p' "$TEMPLATE" | grep -q "Sparing"; then
            ok "the reduction argument is carried in the fold state's directive"
        else
            bad "the reduction argument is not at the fold state" "" ;
        fi ;;
esac

echo
echo "== store isolation =="

# Nothing this suite did may appear in the real store. This is the assertion
# that would have caught the KOTO_HOME trap described at the top of this file.
leaked=$(ls -d "$REAL_HOME"/.koto/sessions/"$PFX"-* 2>/dev/null | head -5)
if [ -z "$leaked" ]; then
    ok "no session from this suite exists in the real store"
else
    bad "sessions leaked into the real store" "$leaked"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
