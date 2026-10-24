#!/usr/bin/env bash
# run-record-lookup_test.sh -- from a PR's repository and number to the
# session that ran its plan (scripts/run-record-lookup.sh)
#
# The skeleton case is the whole path: a single-pr run's root is opened in
# workspace A (its run_id and trail/self as execute-open.sh leaves them), its
# home PR is adopted and recorded through
# skills/execute/scripts/adopt-or-create-pr.sh against the stand-in koto
# (scripts/testdata/record-koto/koto) and a stub gh, and the lookup runs from a
# different directory B. Then:
#
#   the answer      exit 0, JSON naming execute-<topic>, workspace A, the
#                   run_id, complete: true and exactly the one PR with its state
#   unconfirmed     an index entry naming a root whose trail/pr doesn't hold
#                   the PR: not returned, exit 3
#   exit codes      3 no index entry, 2 a failed store read, 64 for an owner
#                   without a repository, PR number 0 and a non-numeric one,
#                   each with its message on stderr
#   read-only       the lookup's calls are reads only: no write, no import,
#                   no migration marker
#   both modes      option absent: the lookup reads from the addressed
#                   directories and no call carries --workspace; option
#                   present: the stub refuses any write given it, the
#                   skeleton still passes, and the lookup's reads carry it
#   no GitHub       with a gh that fails every call, the same JSON and exit
#   --steps         a three-step run whose PLAN is committed between steps 1
#                   and 2: three plan snapshots, step 1 included, steps 1 and
#                   2 with different SHAs and texts, each step's session, and
#                   a step with a new step agent listing the earlier name as
#                   superseded; following each step's session from the
#                   answer, the four departure kinds each against its own
#                   step with a non-empty why, an agent's decision with actor
#                   agent:<name> and an approved deferral with actor person
#   the forms       option present: a PR indexed only under the second form
#                   is found after the first answers "not found"; one form
#                   unreadable and the other holding the entry still answers,
#                   naming the unreadable form in missing; every form
#                   unreadable, or one unreadable and the other not found,
#                   is exit 2
#
# The shared address is the real fixed directory, under an owner unique to
# this run, removed at exit. Before the first case the suite checks that the
# koto on PATH is the stand-in, and stops when it isn't.
#
# Usage: run-record-lookup_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
ROOT=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
LOOKUP="$SCRIPT_DIR/run-record-lookup.sh"
TRAIL="$SCRIPT_DIR/run-trail.sh"
ADOPT="$ROOT/skills/execute/scripts/adopt-or-create-pr.sh"
STUB_DIR="$SCRIPT_DIR/testdata/record-koto"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-record-lookup-test.XXXXXX") || exit 1
OWNER="rrtest-$$-$(od -An -tx1 -N4 /dev/urandom | tr -d ' \n')"
trap 'rm -rf "$WORK" "/tmp/shirabe-run-record/$OWNER"' EXIT
export RECORD_KOTO_STORE="$WORK/store"
TOPIC=skel
S="execute-$TOPIC"
RID=0123456789abcdef0123456789abcdef

# The koto on PATH must be the stand-in: these cases write sessions, and a
# real koto would write them to a real store. Each case also puts the
# stand-in first on its own PATH.
export PATH="$STUB_DIR:$PATH"
if [ "$(command -v koto)" != "$STUB_DIR/koto" ] \
    || [ "$(RECORD_KOTO_STORE="$WORK/stub-probe" koto version </dev/null)" != "koto 0.0.0-record-stub" ]; then
    echo "FAIL: the koto on PATH is not the stand-in at $STUB_DIR/koto; no case ran" >&2
    exit 1
fi

# A gh that answers owned-pr.sh's three reads with one owned PR, number 7, on
# impl/skel; and one that fails every call.
GH_OK="$WORK/gh-ok"
GH_BAD="$WORK/gh-bad"
mkdir -p "$GH_OK" "$GH_BAD"
cat > "$GH_OK/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \${2:-}" in
    "api user") echo '{"login":"octo"}' ;;
    "api repos/"*) echo '{"default_branch":"main"}' ;;
    "pr list") echo '[{"url":"https://github.com/$OWNER/r/pull/7","state":"OPEN","isCrossRepository":false,"author":{"login":"octo"},"baseRefName":"main","headRefName":"impl/$TOPIC","body":"A draft."}]' ;;
    *) echo "gh stub: unexpected [\$*]" >&2; exit 1 ;;
esac
STUB
printf '#!/usr/bin/env bash\necho "gh: no network" >&2\nexit 1\n' > "$GH_BAD/gh"
chmod +x "$GH_OK/gh" "$GH_BAD/gh"

TAB=$(printf '\t')
calls_since() { tail -n "+$(($1 + 1))" "$RECORD_KOTO_STORE/calls.log"; }
log_len() { wc -l < "$RECORD_KOTO_STORE/calls.log" | tr -d ' '; }

# skeleton <mode>: a fresh store and workspaces A and B; the run's root opened
# in A as execute-open.sh leaves it, then its home PR adopted and recorded
# through adopt-or-create-pr.sh. Sets A, B and ADOPT_RC.
skeleton() {
    rm -rf "$RECORD_KOTO_STORE" "$WORK/a" "$WORK/b" "/tmp/shirabe-run-record/$OWNER"
    mkdir -p "$RECORD_KOTO_STORE" "$WORK/a" "$WORK/b"
    A=$(cd "$WORK/a" && pwd -P)
    B=$(cd "$WORK/b" && pwd -P)
    export RECORD_KOTO_WORKSPACE_OPTION=$1
    (
        cd "$A" || exit 1
        export PATH="$STUB_DIR:$GH_OK:$PATH"
        koto init "$S" --template execute.md >/dev/null || exit 1
        printf '%s' "$RID" | koto context add "$S" run_id || exit 1
        bash "$TRAIL" self --session "$S" </dev/null || exit 1
        bash "$ADOPT" --session "$S" --repo "$OWNER/r" --head "impl/$TOPIC" </dev/null >"$WORK/adopt.out" 2>"$WORK/adopt.err"
    )
    ADOPT_RC=$?
}

lookup() { # lookup <gh dir> <args>: from B
    local gh=$1
    shift
    OUT=$(cd "$B" && PATH="$STUB_DIR:$gh:$PATH" bash "$LOOKUP" "$@" </dev/null 2>"$WORK/stderr")
    RC=$?
    ERR=$(cat "$WORK/stderr")
}

expect_answer() { # expect_answer <label>
    local want
    want=$(jq -nc --arg ws "$A" --arg s "$S" --arg r "$RID" --arg repo "$OWNER/r" \
        '{record_root: {workspace: $ws, session: $s}, run_id: $r, complete: true, unique: true,
          missing: [], prs: [{repo: $repo, number: 7, state: "open"}], others: [], steps: []}')
    if [ "$RC" -eq 0 ] && [ "$(jq -c . <<<"$OUT")" = "$want" ]; then
        pass "$1"
    else
        fail "$1: exit $RC, out [$OUT], stderr [$ERR]"
    fi
}

# --- the skeleton, option absent ------------------------------------------------------

skeleton absent
[ "$ADOPT_RC" -eq 0 ] && [ "$(cat "$WORK/adopt.out")" = "https://github.com/$OWNER/r/pull/7" ] \
    && pass "the run records its home PR in workspace A through adopt-or-create-pr.sh" \
    || fail "adopt: exit $ADOPT_RC [$(cat "$WORK/adopt.err")]"

MARK=$(log_len)
lookup "$GH_OK" "$OWNER/r" 7
expect_answer "from directory B: execute-$TOPIC, workspace A, the run_id, complete, exactly that one PR"
GOOD_OUT=$OUT
GOOD_RC=$RC

LOOKUP_CALLS=$(calls_since "$MARK")
if [ -n "$LOOKUP_CALLS" ] \
    && ! grep -qE "${TAB}(init|next|cancel|context add|context remove|session import|session cleanup|session prune|decisions) " <<<"$LOOKUP_CALLS" \
    && [ -z "$(find "$RECORD_KOTO_STORE" -name migrated)" ]; then
    pass "the lookup made reads only: no write, no import, no migration marker"
else
    fail "lookup calls: [$LOOKUP_CALLS]"
fi
if ! grep -q -- '--workspace' "$RECORD_KOTO_STORE/calls.log"; then
    pass "option absent: no call carries --workspace, the run's or the lookup's"
else
    fail "option absent, --workspace seen: [$(grep -- '--workspace' "$RECORD_KOTO_STORE/calls.log")]"
fi
OUTSIDE=$(grep "${TAB}context " <<<"$LOOKUP_CALLS" | grep -v -- '--help' | cut -f1 \
    | grep -vxF -e "$A" -e "$(cd "/tmp/shirabe-run-record/$OWNER" && pwd -P)")
if [ -n "$OUTSIDE" ]; then
    fail "option absent: a read ran outside the addressed directories: [$LOOKUP_CALLS]"
else
    pass "option absent: every read ran from an addressed directory, the shared one or A"
fi

lookup "$GH_BAD" "$OWNER/r" 7
if [ "$RC" -eq "$GOOD_RC" ] && [ "$OUT" = "$GOOD_OUT" ]; then
    pass "with a gh that fails every call: the same JSON and exit code"
else
    fail "failing gh: exit $RC, out [$OUT]"
fi

lookup "$GH_OK" "$(printf '%s' "$OWNER" | tr '[:lower:]' '[:upper:]')/R" 7
expect_answer "the repository is matched without regard to case"

# --- an entry its root doesn't confirm ---------------------------------------------------

# The root's index entry for PR 8, which its own trail/pr list doesn't hold.
(cd "$A" && PATH="$STUB_DIR:$PATH" bash "$TRAIL" index --repo "$OWNER/r" --number 8 --session "$S" \
    --mode single-pr --topic "$TOPIC" </dev/null)
lookup "$GH_OK" "$OWNER/r" 8
if [ "$RC" -eq 3 ] && [ -z "$OUT" ] && grep -q 'lists the PR' <<<"$ERR"; then
    pass "an index entry whose root doesn't list the PR: not returned, exit 3"
else
    fail "unconfirmed: exit $RC, out [$OUT], stderr [$ERR]"
fi

# --- --steps: a three-step run ------------------------------------------------------------
#
# The run's checkout A holds the PLAN. Before each step agent starts, the
# owning session records the PLAN as committed and the step session
# (run-trail.sh plan and step); the PLAN is committed again between steps 1
# and 2, as the owner details step 2. Step 3 gets a new step agent whose
# session has another name. Each step session records what happened in it.

trail() { (cd "$A" && bash "$TRAIL" "$@"); }
trail_doc() { # trail_doc <json> <args>: the JSON on stdin
    local j=$1
    shift
    printf '%s' "$j" | (cd "$A" && bash "$TRAIL" "$@")
}
(
    cd "$A" || exit 1
    git init -q . && git config user.email t@example.com && git config user.name t || exit 1
    mkdir -p docs/plans
    printf '# PLAN\n\n### Step 1: one\n\nDetailed.\n\n### Step 2: two\n\n### Step 3: three\n' > docs/plans/PLAN-skel.md
    git add docs/plans/PLAN-skel.md && git commit -q -m plan
) || fail "could not make the run's checkout a repository"
STEPS_OK=1
for n in 1 2 3; do
    if [ "$n" -eq 2 ]; then
        (cd "$A" && printf '# PLAN\n\n### Step 1: one\n\nDetailed.\n\n### Step 2: two, detailed\n\nNow detailed.\n\n### Step 3: three\n' > docs/plans/PLAN-skel.md \
            && git commit -q -am "detail step 2") || STEPS_OK=0
    fi
    trail plan --session "$S" --step "step-$n" --plan docs/plans/PLAN-skel.md </dev/null || STEPS_OK=0
    (cd "$A" && koto init "$S.step-$n" --template work-on.md >/dev/null) || STEPS_OK=0
    trail step --session "$S" --step "step-$n" --child "$S.step-$n" </dev/null || STEPS_OK=0
done
# Step 3's new step agent, in a session of its own.
(cd "$A" && koto init "$S.step-3_r2" --template work-on.md >/dev/null) || STEPS_OK=0
trail step --session "$S" --step step-3 --child "$S.step-3_r2" --supersede </dev/null || STEPS_OK=0
# What happened in each step session, and the entry rewrite in the root.
trail_doc '{"what": "criterion 2 reads the cache", "why": "the cache has no reader yet"}' \
    departure --session "$S.step-1" --step step-1 --kind deviated || STEPS_OK=0
trail_doc '{"choice": "keep the bound at 20", "rationale": "the design says so"}' \
    decision --session "$S.step-1" --step step-1 --actor "agent:$S.step-1" || STEPS_OK=0
trail_doc '{"what": "the export criterion", "why": "approved: it needs the new API"}' \
    departure --session "$S.step-2" --step step-2 --kind deferral || STEPS_OK=0
trail_doc '{"choice": "defer the export criterion", "rationale": "it needs the new API"}' \
    decision --session "$S.step-2" --step step-2 --actor person || STEPS_OK=0
trail_doc '{"what": "the plan grew a migration", "why": "the schema changed under it"}' \
    departure --session "$S.step-3_r2" --step step-3 --kind scope-change || STEPS_OK=0
trail_doc '{"what": "step 2 rewritten", "why": "step 1 moved the reader"}' \
    departure --session "$S" --step step-2 --kind entry-rewritten || STEPS_OK=0
[ "$STEPS_OK" -eq 1 ] && pass "the three-step run records its plan snapshots, step sessions, departures and decisions" \
    || fail "the three-step run's writes did not all succeed"

lookup "$GH_OK" "$OWNER/r" 7 --steps
SHA1=$(jq -r '.steps[0].plan.sha' <<<"$OUT" 2>/dev/null)
SHA2=$(jq -r '.steps[1].plan.sha' <<<"$OUT" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$(jq -c '[.steps[].step]' <<<"$OUT")" = '["step-1","step-2","step-3"]' ] \
    && [ "$(jq -c '[.steps[].plan | select(. != null) | .text_key]' <<<"$OUT")" = '["trail/plan/step-1.md","trail/plan/step-2.md","trail/plan/step-3.md"]' ] \
    && [[ $SHA1 =~ ^[0-9a-f]{40}$ ]] && [[ $SHA2 =~ ^[0-9a-f]{40}$ ]] && [ "$SHA1" != "$SHA2" ] \
    && [ "$(jq -r '.steps[1].plan.entry' <<<"$OUT")" = "### Step 2: two, detailed" ]; then
    pass "--steps: three plan snapshots, step 1 included, steps 1 and 2 at different SHAs"
else
    fail "--steps snapshots: exit $RC, out [$OUT], stderr [$ERR]"
fi
TEXT1=$(cd "$A" && koto context get "$S" "$(jq -r '.steps[0].plan.text_key' <<<"$OUT")")
TEXT2=$(cd "$A" && koto context get "$S" "$(jq -r '.steps[1].plan.text_key' <<<"$OUT")")
if [ -n "$TEXT1" ] && [ "$TEXT1" != "$TEXT2" ] && grep -q 'Now detailed' <<<"$TEXT2" && ! grep -q 'Now detailed' <<<"$TEXT1"; then
    pass "--steps: koto context get on each text key shows the PLAN as that step began, steps 1 and 2 different"
else
    fail "plan texts: [$TEXT1] / [$TEXT2]"
fi
if [ "$(jq -c '[.steps[] | {session, workspace, superseded}]' <<<"$OUT")" = "$(jq -nc --arg s "$S" --arg a "$A" \
        '[{session: ($s + ".step-1"), workspace: $a, superseded: []},
          {session: ($s + ".step-2"), workspace: $a, superseded: []},
          {session: ($s + ".step-3_r2"), workspace: $a, superseded: [($s + ".step-3")]}]')" ]; then
    pass "--steps: each step names its session, and step 3 lists its earlier step agent's session as superseded"
else
    fail "--steps sessions: [$(jq -c '[.steps[] | {session, superseded}]' <<<"$OUT")]"
fi
# Following the answer into each step session (and the root), as a reader
# would: every departure and decision, read where the lookup says it is.
FOLLOW=""
for sess in $(jq -r '.steps[].session' <<<"$OUT") "$(jq -r '.record_root.session' <<<"$OUT")"; do
    ws=$(jq -r --arg s "$sess" '[.steps[] | select(.session == $s) | .workspace][0] // .record_root.workspace' <<<"$OUT")
    for key in $(cd "$ws" && koto context list "$sess" --prefix trail/ | jq -r '.[] | select(test("^trail/(departure|decision)/"))'); do
        FOLLOW="$FOLLOW$(cd "$ws" && koto context get "$sess" "$key" | jq -c --arg s "$sess" '{in: $s, step, kind, actor, why_set: ((.why // "") != "")}')
"
    done
done
WANT=$(jq -nc --arg s "$S" '[
    {in: ($s + ".step-1"), step: "step-1", kind: "deviated", actor: null, why_set: true},
    {in: ($s + ".step-1"), step: "step-1", kind: null, actor: ("agent:" + $s + ".step-1"), why_set: false},
    {in: ($s + ".step-2"), step: "step-2", kind: "deferral", actor: null, why_set: true},
    {in: ($s + ".step-2"), step: "step-2", kind: null, actor: "person", why_set: false},
    {in: ($s + ".step-3_r2"), step: "step-3", kind: "scope-change", actor: null, why_set: true},
    {in: $s, step: "step-2", kind: "entry-rewritten", actor: null, why_set: true}] | sort')
if [ "$(printf '%s' "$FOLLOW" | jq -sc 'sort')" = "$WANT" ]; then
    pass "--steps, followed: the four departure kinds each against its own step with a why; actors agent:<name> and person"
else
    fail "followed: [$(printf '%s' "$FOLLOW" | jq -sc 'sort')]"
fi
lookup "$GH_OK" "$OWNER/r" 7
[ "$RC" -eq 0 ] && [ "$(jq -c .steps <<<"$OUT")" = '[]' ] && pass "without --steps, steps is [] and no step record is read" \
    || fail "no --steps: [$(jq -c .steps <<<"$OUT")]"
check_steps_usage() { # check_steps_usage <label> <args...>
    local label=$1
    shift
    lookup "$GH_OK" "$@"
    [ "$RC" -eq 64 ] && [ -z "$OUT" ] && pass "$label: exit 64" || fail "$label: exit $RC [$ERR]"
}
check_steps_usage "--steps twice" "$OWNER/r" 7 --steps --steps
check_steps_usage "an unknown flag" "$OWNER/r" 7 --all

# --- exit codes -----------------------------------------------------------------------------

lookup "$GH_OK" "$OWNER/r" 99
[ "$RC" -eq 3 ] && [ -z "$OUT" ] && grep -q 'no index entry' <<<"$ERR" \
    && pass "a PR with no index entry: exit 3, said on stderr" \
    || fail "no entry: exit $RC, stderr [$ERR]"

export RECORD_KOTO_FAIL_READS=1
lookup "$GH_OK" "$OWNER/r" 7
unset RECORD_KOTO_FAIL_READS
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && grep -q 'could not read' <<<"$ERR" \
    && pass "a failed store read: exit 2, said on stderr" \
    || fail "read failure: exit $RC, stderr [$ERR]"

check_usage() { # check_usage <label> <stderr pattern> <args...>
    local label=$1 pattern=$2
    shift 2
    MARK=$(log_len)
    lookup "$GH_OK" "$@"
    if [ "$RC" -eq 64 ] && [ -z "$OUT" ] && grep -q -- "$pattern" <<<"$ERR" && [ -z "$(calls_since "$MARK")" ]; then
        pass "$label: exit 64, said on stderr, no koto call"
    else
        fail "$label: exit $RC, stderr [$ERR]"
    fi
}
check_usage "an owner without a repository" "owner without a repository" "$OWNER" 7
check_usage "an owner with an empty repository" "owner without a repository" "$OWNER/" 7
check_usage "PR number 0" "not a positive integer" "$OWNER/r" 0
check_usage "a non-numeric PR number" "not a positive integer" "$OWNER/r" seven
check_usage "an owner outside GitHub's grammar" "not a GitHub owner name" "-x/r" 7
check_usage "a missing PR number" "expected" "$OWNER/r"

# --- the skeleton, option present -------------------------------------------------------------

skeleton present
[ "$ADOPT_RC" -eq 0 ] && pass "option present: the run still records its home PR (no write carries --workspace)" \
    || fail "option present, adopt: exit $ADOPT_RC [$(cat "$WORK/adopt.err")]"
if ! grep -E "${TAB}(init|context add|context remove) " "$RECORD_KOTO_STORE/calls.log" | grep -q -- '--workspace'; then
    pass "option present: none of the run's writes carries --workspace"
else
    fail "option present: a write carried --workspace"
fi

MARK=$(log_len)
lookup "$GH_OK" "$OWNER/r" 7
expect_answer "option present: from directory B, the same answer"
READS=$(calls_since "$MARK" | grep -E "${TAB}context (get|list) " | grep -v -- '--help')
if [ -n "$READS" ] && ! grep -qv -- '--workspace=' <<<"$READS" \
    && grep -qF -- "--workspace=$A " <<<"$READS" \
    && [ "$(cut -f1 <<<"$READS" | LC_ALL=C sort -u)" = "$B" ]; then
    pass "option present: the lookup's reads carry --workspace and run from B itself"
else
    fail "option present reads: [$READS]"
fi

# --- the forms, option present -----------------------------------------------------------------
#
# PR 11's index entry sits only under the second form, /private/tmp/...: on
# Linux no writer canonicalizes there, so the stand-in is told to file the
# session at that form. The first form holds no pr.<owner>.r.11 and answers
# "not found".

FORM1="/tmp/shirabe-run-record/$OWNER"
FORM2="/private$FORM1"
(cd "$A" && bash "$TRAIL" pr --session "$S" --repo "$OWNER/r" --number 11 --role home --state open </dev/null) \
    || fail "could not record PR 11 in the root"
SID=$(cd "$A" && koto session list | jq -r --arg s "$S" '.[] | select(.id == $s) | .session_id')
ENTRY=$(jq -nc --arg w "$A" --arg s "$S" --arg i "$SID" '{workspace: $w, session: $s, session_id: $i, mode: "single-pr", topic: "skel", written_at: "2026-01-02T03:04:05Z"}')
(cd "$WORK" && RECORD_KOTO_AS_CWD="$FORM2" koto init "pr.$OWNER.r.11" --template t >/dev/null \
    && printf '%s' "$ENTRY" | RECORD_KOTO_AS_CWD="$FORM2" koto context add "pr.$OWNER.r.11" "run/$RID") \
    || fail "could not place PR 11's index entry at the second form"

MARK=$(log_len)
lookup "$GH_OK" "$OWNER/r" 11
CALLS=$(calls_since "$MARK")
if [ "$RC" -eq 0 ] && [ "$(jq -r '.record_root.session' <<<"$OUT")" = "$S" ] && [ "$(jq -r .complete <<<"$OUT")" = true ] \
    && grep -qF -- "context list --workspace=$FORM1 pr.$OWNER.r.11" <<<"$CALLS" \
    && grep -qF -- "context list --workspace=$FORM2 pr.$OWNER.r.11" <<<"$CALLS"; then
    pass "the first form answers not found, the read goes on to the second, and the PR indexed there is found (exit 0)"
else
    fail "fall-through: exit $RC, out [$OUT], stderr [$ERR]"
fi

export RECORD_KOTO_FAIL_READS_IN="$FORM1"
lookup "$GH_OK" "$OWNER/r" 11
if [ "$RC" -eq 0 ] && [ "$(jq -r .complete <<<"$OUT")" = false ] \
    && [ "$(jq -c .missing <<<"$OUT")" = '["index: a form of the shared address could not be read"]' ]; then
    pass "one form unreadable, the other holding the entry: still answered, the unreadable form named in missing"
else
    fail "one unreadable form: exit $RC, out [$OUT], stderr [$ERR]"
fi
export RECORD_KOTO_FAIL_READS_IN="$FORM2"
lookup "$GH_OK" "$OWNER/r" 11
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && grep -q 'could not read the index' <<<"$ERR" \
    && pass "one form not found and the other unreadable: exit 2, not 3" \
    || fail "not found + unreadable: exit $RC, stderr [$ERR]"
unset RECORD_KOTO_FAIL_READS_IN
lookup "$GH_OK" "$OWNER/r" 99
[ "$RC" -eq 3 ] && grep -q 'no index entry' <<<"$ERR" \
    && pass "option present, not found under every form: exit 3" \
    || fail "present, no entry: exit $RC, stderr [$ERR]"
export RECORD_KOTO_FAIL_READS=1
lookup "$GH_OK" "$OWNER/r" 11
unset RECORD_KOTO_FAIL_READS
[ "$RC" -eq 2 ] && grep -q 'could not read' <<<"$ERR" \
    && pass "option present, unreadable under every form: exit 2" \
    || fail "present, all unreadable: exit $RC, stderr [$ERR]"

# --- a re-run, and more than one run per PR, in both modes -----------------------------------
#
# Run 1 records PRs 7 (its home PR, through adopt-or-create-pr.sh), 9 and 10,
# and three step sessions, step 3's superseded by a new step agent's. A
# re-run of the topic then replaces the root: the stand-in moves it and its
# `.`-children to `_r1` the way koto does, and run 2 takes the name. Run 2
# records PR 8 and also carries PR 9. Index entries written by hand give the
# cases their timestamps.

RID2=abcdef0123456789abcdef0123456789

session_id_of() { # session_id_of <name>: its id, from A's session list
    (cd "$A" && koto session list </dev/null) | jq -r --arg s "$1" '.[] | select(.id == $s) | .session_id'
}

put_entry() { # put_entry <pr> <run_id> <session> <session_id> <written_at>
    local entry
    entry=$(jq -nc --arg w "$A" --arg s "$3" --arg i "$4" --arg at "$5" \
        '{workspace: $w, session: $s, session_id: $i, mode: "single-pr", topic: "skel", written_at: $at}')
    (cd "/tmp/shirabe-run-record/$OWNER" && koto init "pr.$OWNER.r.$1" --attach-live --template t >/dev/null \
        && printf '%s' "$entry" | koto context add "pr.$OWNER.r.$1" "run/$2")
}

trail_pr() { # trail_pr <session> <pr>
    (cd "$A" && bash "$TRAIL" pr --session "$1" --repo "$OWNER/r" --number "$2" --role follow-up --state open </dev/null)
}

rerun_cases() {
    local mode=$1 ok=1 sid1 sid2 sid10 sid11 want calls budget
    skeleton "$mode"
    [ "$ADOPT_RC" -eq 0 ] || ok=0
    for n in 1 2 3; do
        (cd "$A" && koto init "$S.step-$n" --template work-on.md >/dev/null) || ok=0
        trail step --session "$S" --step "step-$n" --child "$S.step-$n" </dev/null || ok=0
    done
    (cd "$A" && koto init "$S.step-3_r2" --template work-on.md >/dev/null) || ok=0
    trail step --session "$S" --step step-3 --child "$S.step-3_r2" --supersede </dev/null || ok=0
    trail_pr "$S" 9 || ok=0
    trail_pr "$S" 10 || ok=0
    sid1=$(session_id_of "$S")
    put_entry 9 "$RID" "$S" "$sid1" 2026-01-01T00:00:00Z || ok=0
    put_entry 10 "$RID" "$S" "$sid1" 2026-01-01T00:00:00Z || ok=0
    # The re-run.
    (cd "$A" && koto init "$S" --replace-terminal --template execute.md >/dev/null \
        && printf '%s' "$RID2" | koto context add "$S" run_id) || ok=0
    trail self --session "$S" </dev/null || ok=0
    trail_pr "$S" 8 || ok=0
    (cd "$A" && bash "$TRAIL" index --repo "$OWNER/r" --number 8 --session "$S" --mode single-pr --topic "$TOPIC" </dev/null) || ok=0
    trail_pr "$S" 9 || ok=0
    sid2=$(session_id_of "$S")
    put_entry 9 "$RID2" "$S" "$sid2" 2026-01-02T00:00:00Z || ok=0
    put_entry 10 "$RID2" "$S" "$sid2" 2026-01-02T00:00:00Z || ok=0
    if [ "$ok" -eq 1 ] && [ -n "$sid1" ] && [ -n "$sid2" ] && [ "$sid1" != "$sid2" ] \
        && [ "$(session_id_of "${S}_r1")" = "$sid1" ] && [ "$(session_id_of "${S}_r1.step-3_r2")" != "" ]; then
        pass "option $mode: the re-run moves run 1's root and step sessions to _r1, keeping run 1's id"
    else
        fail "option $mode: the re-run's setup did not complete (ok=$ok)"
    fi

    lookup "$GH_OK" "$OWNER/r" 7 --steps
    want=$(jq -nc --arg s "$S" --arg a "$A" --arg r "$RID" '{root: ($s + "_r1"), ws: $a, run: $r, unique: true, others: [],
        steps: [{session: ($s + "_r1.step-1"), superseded: []}, {session: ($s + "_r1.step-2"), superseded: []},
                {session: ($s + "_r1.step-3_r2"), superseded: [($s + "_r1.step-3")]}]}')
    if [ "$RC" -eq 0 ] && [ "$(jq -c '{root: .record_root.session, ws: .record_root.workspace, run: .run_id, unique, others,
            steps: [.steps[] | {session, superseded}]}' <<<"$OUT")" = "$want" ]; then
        pass "option $mode: run 1's PR leads to execute-$TOPIC""_r1, run 1's run_id, and each step session under its _r1 name"
    else
        fail "option $mode, re-run PR 7: exit $RC, out [$OUT], stderr [$ERR]"
    fi
    if [ "$RC" -eq 0 ]; then
        ok=1
        for sess in $(jq -r '.steps[] | .session, .superseded[]' <<<"$OUT"); do
            [ -n "$(session_id_of "$sess")" ] || ok=0
        done
        [ "$ok" -eq 1 ] && pass "option $mode: every step session the answer names exists under that name" \
            || fail "option $mode: a named step session does not exist: [$(jq -c .steps <<<"$OUT")]"
    fi
    lookup "$GH_OK" "$OWNER/r" 8
    if [ "$RC" -eq 0 ] && [ "$(jq -r '.record_root.session' <<<"$OUT")" = "$S" ] && [ "$(jq -r .run_id <<<"$OUT")" = "$RID2" ]; then
        pass "option $mode: run 2's PR leads to execute-$TOPIC and run 2's run_id"
    else
        fail "option $mode, run 2's PR 8: exit $RC, out [$OUT], stderr [$ERR]"
    fi

    # Both runs list PR 9: the later entry answers, the other is in others.
    lookup "$GH_OK" "$OWNER/r" 9
    if [ "$RC" -eq 0 ] && [ "$(jq -c '[.record_root.session, .run_id, .unique, .others]' <<<"$OUT")" \
            = "$(jq -nc --arg s "$S" --arg r2 "$RID2" --arg r1 "$RID" '[$s, $r2, false, [$r1]]')" ]; then
        pass "option $mode: two runs list PR 9: the latest written_at answers, unique false, the other run_id in others"
    else
        fail "option $mode, two runs: exit $RC, out [$OUT], stderr [$ERR]"
    fi
    # Equal written_at: the tie goes by run_id.
    put_entry 9 "$RID2" "$S" "$sid2" 2026-01-01T00:00:00Z
    lookup "$GH_OK" "$OWNER/r" 9
    [ "$RC" -eq 0 ] && [ "$(jq -c '[.run_id, .others]' <<<"$OUT")" = "$(jq -nc --arg a "$RID2" --arg b "$RID" '[$a, [$b]]')" ] \
        && pass "option $mode: two entries with one written_at: the tie broken by run_id" \
        || fail "option $mode, tie: exit $RC, out [$OUT]"
    # Run 2's entry for PR 10 is the latest, but run 2 never listed PR 10.
    lookup "$GH_OK" "$OWNER/r" 10
    if [ "$RC" -eq 0 ] && [ "$(jq -c '[.record_root.session, .run_id, .unique, .others, .complete]' <<<"$OUT")" \
            = "$(jq -nc --arg s "${S}_r1" --arg r1 "$RID" '[$s, $r1, true, [], true]')" ]; then
        pass "option $mode: a later entry whose root doesn't list the PR is neither returned nor in others"
    else
        fail "option $mode, unlisted later entry: exit $RC, out [$OUT], stderr [$ERR]"
    fi

    # An id held by no session under the name or _r1 to _r10.
    put_entry 12 "$RID" "$S" no-such-session-id 2026-01-01T00:00:00Z
    lookup "$GH_OK" "$OWNER/r" 12
    [ "$RC" -eq 3 ] && [ -z "$OUT" ] && grep -q "wasn't found under its name or any moved-aside name" <<<"$ERR" \
        && pass "option $mode: a recorded id no session holds under the name or a moved-aside name: exit 3, said on stderr" \
        || fail "option $mode, id not found: exit $RC, out [$OUT], stderr [$ERR]"
    # _r10 is the last moved-aside name looked under; _r11 is past it.
    (cd "$A" && koto init "${S}_r10" --template execute.md >/dev/null && koto init "${S}_r11" --template execute.md >/dev/null)
    trail_pr "${S}_r10" 15
    trail_pr "${S}_r11" 14
    sid10=$(session_id_of "${S}_r10")
    sid11=$(session_id_of "${S}_r11")
    put_entry 15 "$RID" "$S" "$sid10" 2026-01-01T00:00:00Z
    put_entry 14 "$RID" "$S" "$sid11" 2026-01-01T00:00:00Z
    lookup "$GH_OK" "$OWNER/r" 15
    [ "$RC" -eq 0 ] && [ "$(jq -r .record_root.session <<<"$OUT")" = "${S}_r10" ] \
        && pass "option $mode: a root moved to _r10 is found" \
        || fail "option $mode, _r10: exit $RC, out [$OUT], stderr [$ERR]"
    lookup "$GH_OK" "$OWNER/r" 14
    [ "$RC" -eq 3 ] && grep -q "moved-aside name" <<<"$ERR" \
        && pass "option $mode: a root under _r11 is past the search: exit 3" \
        || fail "option $mode, _r11: exit $RC, out [$OUT], stderr [$ERR]"

    # Values read back that fail their patterns: named in missing, never used.
    trail_pr "$S" 17
    put_entry 17 "$RID2" "$S" "$sid2" 2026-01-02T00:00:00Z
    put_entry 17 11111111111111111111111111111111 "$S" 'not an id!' 2026-01-03T00:00:00Z
    put_entry 17 22222222222222222222222222222222 "$S" "$sid2" yesterday
    put_entry 17 33333333333333333333333333333333 '../x' "$sid2" 2026-01-03T00:00:00Z
    lookup "$GH_OK" "$OWNER/r" 17
    if [ "$RC" -eq 0 ] && [ "$(jq -c '[.record_root.session, .run_id, .unique, .others, .complete]' <<<"$OUT")" \
            = "$(jq -nc --arg s "$S" --arg r "$RID2" '[$s, $r, true, [], false]')" ] \
        && [ "$(jq '[.missing[] | select(test("^index: run/[0-9a-f]{32} fails its pattern$"))] | length' <<<"$OUT")" = 3 ]; then
        pass "option $mode: entries whose session_id, written_at or session fails its pattern are named in missing and not used"
    else
        fail "option $mode, entry patterns: exit $RC, out [$OUT], stderr [$ERR]"
    fi
    export RECORD_KOTO_LIST_EXTRA
    RECORD_KOTO_LIST_EXTRA=$(jq -nc --arg s "${S}_r2" --arg i "$sid1" \
        '[{id: $s, session_id: "bad id!", execution_dir: "/x", parent_workflow: null},
          {id: "bad name!", session_id: $i, execution_dir: "/x", parent_workflow: null}]')
    lookup "$GH_OK" "$OWNER/r" 7
    unset RECORD_KOTO_LIST_EXTRA
    if [ "$RC" -eq 0 ] && [ "$(jq -r .record_root.session <<<"$OUT")" = "${S}_r1" ] \
        && [ "$(jq '[.missing[] | select(startswith("session list: "))] | length' <<<"$OUT")" = 2 ]; then
        pass "option $mode: session list rows whose name or id fails its pattern are named in missing and not used"
    else
        fail "option $mode, row patterns: exit $RC, out [$OUT], stderr [$ERR]"
    fi

    # The call count for one PR: run 1 has P=3 PRs (7, 9, 10) and S=3 steps.
    MARK=$(log_len)
    lookup "$GH_OK" "$OWNER/r" 7
    calls=$(calls_since "$MARK")
    budget=$((2 + 3 + 3 + 1))
    if [ "$RC" -eq 0 ] && [ "$(wc -l <<<"$calls" | tr -d ' ')" -le "$budget" ] \
        && [ "$(grep -c "${TAB}session list" <<<"$calls")" -eq 1 ] \
        && ! grep -qE "${TAB}(status|init|next|cancel|context add|context remove|session import|session cleanup|session prune|decisions) " <<<"$calls"; then
        pass "option $mode: the lookup made $(wc -l <<<"$calls" | tr -d ' ') koto calls (budget $budget), one session list, no write"
    else
        fail "option $mode, call count: exit $RC, calls [$calls]"
    fi
}

rerun_cases absent
rerun_cases present

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
