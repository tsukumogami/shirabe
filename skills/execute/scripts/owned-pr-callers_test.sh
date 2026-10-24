#!/usr/bin/env bash
# owned-pr-callers_test.sh — every owned-PR lookup carries the run's identity
# Part of the execute skill
#
# owned-pr.sh decides ownership by the run that opened a PR only when its
# caller passes --run-id. A caller that forgets it silently falls back to the
# login-and-branch match, which is the defect the index exists to close, and
# no behavioural test of the caller would notice. So this reads the call
# sites themselves:
#
#   scripts    every non-test script under skills/ that runs owned-pr.sh passes
#              --run-id (or coord_owned, which does) on that line. The one
#              exception is coord_owned's own hand-run branch, for a caller
#              that has no identity at all.
#   templates  every owned-pr.sh invocation in a koto template or SKILL.md
#              (the command line and its backslash continuations) carries
#              --run-id
#   sessionless scripts: every coordinated-next.sh and node-push.sh call in
#              execute-coordinated.md carries --run-id; record-coordination-
#              verdict.sh hands one to coordination-verdict.sh; deliver-probe.sh
#              hands one to publish-scoping-pr.sh --verify; scope.md's verify
#              gates pass --session so the script can read the session's id
#   rewrites   execute.md's pr_finalization reads the run's record reference
#              (`pr-workflow-content.sh --reference`) and chains it to its
#              full-body `gh pr edit`, and no template or script calls a
#              run-id.sh verb that wrote a marker into a body
#   takeover   --take-over appears in no script or template call except the
#              exit-6 re-entry instruction and adopt-or-create-pr.sh's
#              pass-through (check-pr-output.sh names it only to refuse it)
#
# Usage: owned-pr-callers_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
cd "$REPO_ROOT" || exit 1

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

HAND_RUN_LINE='"$BASH" "$COORD_SELF_DIR/owned-pr.sh" --repo "$1" --head "$2" --state "$3" </dev/null'

# invocations <file> -- each owned-pr.sh command (by name, or through a
# variable named OWNED), continuation lines joined, one per line; comments
# skipped.
invocations() {
    awk '
        cont { buf = buf " " $0; if ($0 !~ /\\[[:space:]]*$/) { print buf; cont = 0 }; next }
        /(owned-pr\.sh"?|\$OWNED"?)[[:space:]]+(--repo|\\[[:space:]]*$)/ && !/^[[:space:]]*#/ {
            if ($0 ~ /\\[[:space:]]*$/) { buf = $0; cont = 1 } else print
        }
    ' "$1"
}

# --- scripts ------------------------------------------------------------------

SCRIPTS=$(find skills -name '*.sh' ! -name '*_test.sh' ! -path '*/testdata/*' ! -path '*/evals/*' | sort)
N=0
for f in $SCRIPTS; do
    [ "$f" = skills/execute/scripts/owned-pr.sh ] && continue
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        N=$((N + 1))
        body=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')
        case "$body" in
            *--run-id*|*OWNED_RUN*) pass "$f: [${body:0:70}...] carries the run identity" ;;
            "$HAND_RUN_LINE")
                if [ "$f" = skills/execute/scripts/coord-common.sh ]; then
                    pass "$f: coord_owned's hand-run branch (no identity to pass)"
                else
                    fail "$f: a lookup with no --run-id: [$body]"
                fi
                ;;
            *) fail "$f: a lookup with no --run-id: [$body]" ;;
        esac
    done < <(invocations "$f")
done
[ "$N" -ge 10 ] && pass "found $N script call sites" || fail "found only $N script call sites; the extractor is broken"

if grep -q -- '--run-id "$COORD_RUN_ID"' skills/execute/scripts/coord-common.sh; then
    pass "coord_owned passes COORD_RUN_ID when it is set"
else
    fail "coord_owned does not pass COORD_RUN_ID"
fi
if grep -qE '"\$BASH" "\$COORD_SELF_DIR/owned-pr.sh"' skills/execute/scripts/node-push.sh skills/execute/scripts/coord-merge.sh; then
    fail "node-push.sh or coord-merge.sh calls owned-pr.sh directly instead of coord_owned"
else
    pass "node-push.sh and coord-merge.sh look up through coord_owned"
fi

# --- templates and SKILL.md ------------------------------------------------------

M=0
for f in skills/*/koto-templates/*.md skills/*/SKILL.md; do
    while IFS= read -r inv; do
        [ -n "$inv" ] || continue
        case "$inv" in *'--repo'*) ;; *) continue ;; esac
        M=$((M + 1))
        case "$inv" in
            *--run-id*) pass "$f: an owned-pr.sh call carries --run-id" ;;
            *) fail "$f: an owned-pr.sh call with no --run-id: [${inv:0:160}]" ;;
        esac
    done < <(invocations "$f")
done
[ "$M" -ge 5 ] && pass "found $M template and SKILL.md call sites" || fail "found only $M template call sites; the extractor is broken"

# --- sessionless scripts --------------------------------------------------------

CT=skills/execute/koto-templates/execute-coordinated.md
for s in coordinated-next.sh node-push.sh; do
    total=$(grep -c "scripts/$s " "$CT")
    with=$(grep "scripts/$s " "$CT" | grep -c -- '--run-id')
    # coordinated-next.sh's call continues onto the next lines.
    [ "$s" = coordinated-next.sh ] && with=$(awk '/scripts\/coordinated-next.sh /{f=1} f{b=b $0} f && !/\\$/{print b; f=0; b=""}' "$CT" | grep -c -- '--run-id')
    if [ "$total" -ge 1 ] && [ "$with" -eq "$total" ]; then
        pass "execute-coordinated.md: all $total $s calls carry --run-id"
    else
        fail "execute-coordinated.md: $with of $total $s calls carry --run-id"
    fi
done
grep -q -- '--run-id "$RUN_ID"' skills/execute/scripts/record-coordination-verdict.sh \
    && pass "record-coordination-verdict.sh hands its identity to coordination-verdict.sh" \
    || fail "record-coordination-verdict.sh does not pass --run-id"
grep -q -- '--verify --run-id "$RUN_ID"' skills/deliver/scripts/deliver-probe.sh \
    && pass "deliver-probe.sh hands its identity to publish-scoping-pr.sh --verify" \
    || fail "deliver-probe.sh's --verify call carries no --run-id"
VG=$(grep -c -- '--verify --expect-intent "{{RUN_INTENT}}"' skills/scope/koto-templates/scope.md)
VS=$(grep -- '--verify --expect-intent "{{RUN_INTENT}}"' skills/scope/koto-templates/scope.md | grep -c -- '--session "scope-{{TOPIC}}"')
[ "$VG" -ge 1 ] && [ "$VG" -eq "$VS" ] \
    && pass "scope.md: all $VG verify gates pass --session" \
    || fail "scope.md: $VS of $VG verify gates pass --session"

# --- the full-body rewrite carries nothing of the run but the reference ------

E=skills/execute/koto-templates/execute.md
REFL=$(grep -n 'pr-workflow-content.sh --reference {{SESSION_NAME}})' "$E" | head -1 | cut -d: -f1)
EDIT=$(grep -n 'gh pr edit "$PR_NUMBER"' "$E" | head -1 | cut -d: -f1)
if [ -n "$REFL" ] && [ -n "$EDIT" ] && [ "$REFL" -lt "$EDIT" ] \
    && sed -n "${REFL},${EDIT}p" "$E" | grep -q '&& \[ -n "$PR_NUMBER" \]'; then
    pass "pr_finalization reads the record reference and chains it to its gh pr edit, guarded on an empty lookup"
else
    fail "pr_finalization: reference at [$REFL], gh pr edit at [$EDIT]"
fi
USES=$(grep -rnE 'run-id\.sh"? +(stamp|restamp|carry|marker)' skills scripts --include='*.sh' --include='*.md' | grep -v '_test\.sh:' || true)
if [ -z "$USES" ]; then
    pass "no template or script calls a run-id.sh verb that wrote a marker into a body"
else
    fail "a marker verb is still called: $USES"
fi

# --- an empty lookup never reaches gh -----------------------------------------

# gh falls back to the checked-out branch's PR when handed an empty selector,
# so every site that feeds owned-pr.sh's output to gh guards against empty.
# owned_ci_passing feeds it to work-on's pr-checks.sh, which hands it to
# `gh pr checks`, so the same guard stands in front of it.
for g in owned_ci_passing owned_merge_state_clean owned_pr_merged; do
    cmd=$(awk -v g="$g" '$0 ~ "^      " g ":" {f=1} f && /command:/ {print; exit}' "$E")
    case "$cmd" in
        *'| xargs -r -I{} gh pr '*) pass "$g fails before gh runs when the lookup is empty" ;;
        *'| xargs -r -I{} \"{{PLUGIN_ROOT}}/skills/work-on/scripts/pr-checks.sh\" {} '*)
            pass "$g fails before pr-checks.sh runs when the lookup is empty" ;;
        *) fail "$g has no empty-lookup guard: [${cmd:0:120}]" ;;
    esac
done
grep -qF '[ -n "$PR" ] && gh pr ready "$PR"' "$E" \
    && pass "plan_completion's gh pr ready is guarded against an empty lookup" \
    || fail "plan_completion's gh pr ready is not guarded"
grep -qF '[ -n "$PR_NUMBER" ] \' "$E" \
    && pass "pr_finalization's chain starts with an empty-lookup guard" \
    || fail "pr_finalization's chain has no empty-lookup guard"

# --- ownership is checked before the shared branch is pushed ------------------

# Step 2 of orchestrator_setup: the first adopt-or-create-pr.sh call on
# impl/<slug> (without --create) comes before the push.
LOOK=$(awk '/\*\*2\. The shared branch/{f=1} f && /adopt-or-create-pr\.sh/{print NR; exit}' "$E")
PUSH=$(awk '/\*\*2\. The shared branch/{f=1} f && /push-and-record\.sh \{\{SESSION_NAME\}\}/{print NR; exit}' "$E")
if [ -n "$LOOK" ] && [ -n "$PUSH" ] && [ "$LOOK" -lt "$PUSH" ]; then
    pass "orchestrator_setup looks up impl/<slug>'s PR before pushing it"
else
    fail "orchestrator_setup: lookup at [$LOOK], push at [$PUSH]"
fi
NP=skills/execute/scripts/node-push.sh
OWN=$(grep -n '^    OWNED_NOW=$(coord_owned "$REPO" "$BRANCH" open)' "$NP" | head -1 | cut -d: -f1)
GP=$(grep -n '^[[:space:]]*if ! git push' "$NP" | head -1 | cut -d: -f1)
if [ -n "$OWN" ] && [ -n "$GP" ] && [ "$OWN" -lt "$GP" ]; then
    pass "node-push.sh checks the node branch's PR before it pushes"
else
    fail "node-push.sh: ownership check at [$OWN], push at [$GP]"
fi

# --- the run identity is minted only where a session or a run record is born --

MINTERS=$(grep -rln --include='*.sh' --include='*.md' --exclude-dir=workspace -e 'run-id.sh" mint\|run-id.sh mint' skills \
    | grep -v '_test.sh$' | grep -vx skills/execute/scripts/run-id.sh | sort | tr '\n' ' ')
# record-coord-setup.sh mints a coordinated run's identity when it seals the
# run record; execute-open.sh mints only a single-pr session's.
WANT_MINTERS="skills/deliver/scripts/deliver-open.sh skills/execute/scripts/execute-open.sh skills/execute/scripts/record-coord-setup.sh skills/scope/scripts/scope-open.sh "
if [ "$MINTERS" = "$WANT_MINTERS" ]; then
    pass "run-id.sh mint is called only by the three session-opening scripts and the coordinated setup"
else
    fail "run-id.sh mint callers: [$MINTERS], want [$WANT_MINTERS]"
fi

# --- --take-over is never passed silently -------------------------------------

TAKE=$(grep -rn --include='*.sh' --include='*.md' --exclude-dir=workspace -e '--take-over' skills \
    | grep -v '_test.sh:' | grep -v 'skills/execute/scripts/owned-pr.sh:' \
    | grep -v 'skills/execute/scripts/adopt-or-create-pr.sh:' \
    | grep -v 'skills/work-on/scripts/check-pr-output.sh:.*--take-over is refused' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')
BAD=$(printf '%s\n' "$TAKE" | grep -v '^$' \
    | grep -v 'skills/execute/SKILL.md:' | grep -v 'skills/execute/koto-templates/execute.md:')
if [ -z "$BAD" ]; then
    pass "--take-over is named only by owned-pr.sh, adopt-or-create-pr.sh, execute.md, and SKILL.md"
else
    fail "--take-over appears elsewhere: $BAD"
fi
TAKE_EXEC=$(grep 'execute.md:' <<<"$TAKE")
if grep -qE 'adopt-or-create-pr\.sh .*--take-over' <<<"$TAKE_EXEC"; then
    fail "execute.md runs --take-over in a command block; it must be the exit-6 decision's re-run only"
else
    pass "execute.md passes --take-over only through the exit-6 decision"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
