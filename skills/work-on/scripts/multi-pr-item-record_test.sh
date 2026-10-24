#!/usr/bin/env bash
# multi-pr-item-record_test.sh -- a multi-pr plan's item records itself in the
# plan's record root (multi-pr-item-record.sh), through the hooks the work-on
# template carries.
#
#   the hooks       the template's `analysis` directive runs `start` and its
#                   `pr_creation` directive runs `pr`, each passing the run's
#                   own SESSION_NAME, PLAN_DOC, ARTIFACT_PREFIX, SHARED_BRANCH
#                   and ISSUE_SOURCE
#   plan-backed     each hook line, rendered as koto renders it for a
#                   plan-backed child of /execute (SHARED_BRANCH or
#                   ISSUE_SOURCE set), prints skipped=plan-backed-child, exits
#                   0 and makes no koto call: the child's parent records it
#   an item         the same two lines, rendered for a top-level item of a
#                   multi-pr PLAN, record the item (session, workspace, PR),
#                   the PLAN as the item began, the PR in the root's list
#                   (role item) and the PR's index entry naming the root
#   keep            record_keep's default action, as the template declares it
#                   (the run's own variables, ending `|| true`): for the item,
#                   start's record_root is read back, the item's PR is
#                   recorded ready and the plan root, the item's session and
#                   its index session are pinned, record=pinned in the item's
#                   session; a plan-backed child is skipped with no koto
#                   call, and a run with no record_root pins nothing
#   not an item     no PLAN_DOC, or a PLAN that isn't multi-pr: skipped, no
#                   koto call
#   refusals        a PLAN path outside docs/plans/PLAN-<topic>.md is 65; an
#                   unknown subcommand or flag, a flag given twice, a missing
#                   one: 64, no koto call
#
# Every case runs against the stand-in koto, scripts/testdata/record-koto/koto;
# the suite checks that the koto on PATH is the stand-in before the first
# case, and stops when it isn't. The shared address is a directory of this
# suite's own, through record-store.sh's test-only
# SHIRABE_RUN_RECORD_TEST_ROOT. The multi-pr lookups (three items, a later
# workspace, a reused topic) are in scripts/run-record-lookup_test.sh.
#
# Usage: multi-pr-item-record_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
ITEMREC="$SCRIPT_DIR/multi-pr-item-record.sh"
TEMPLATE="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
STUB_DIR="$REPO_ROOT/scripts/testdata/record-koto"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/multi-pr-item-record-test.XXXXXX") || exit 1
WORK=$(cd "$WORK" && pwd -P) || exit 1
trap 'rm -rf "$WORK"' EXIT
export SHIRABE_RUN_RECORD_TEST_ROOT="$WORK/shared"
export RECORD_KOTO_STORE="$WORK/store"
export PATH="$STUB_DIR:$PATH"
OWNER="mptest-$$"

if [ "$(command -v koto)" != "$STUB_DIR/koto" ] \
    || [ "$(RECORD_KOTO_STORE="$WORK/stub-probe" koto version </dev/null)" != "koto 0.0.0-record-stub" ]; then
    echo "FAIL: the koto on PATH is not the stand-in at $STUB_DIR/koto; no case ran" >&2
    exit 1
fi

log_len() { if [ -f "$RECORD_KOTO_STORE/calls.log" ]; then wc -l < "$RECORD_KOTO_STORE/calls.log" | tr -d ' '; else echo 0; fi; }

# section <name>: a state's directive section of the template's body.
section() {
    awk -v h="## $1" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$TEMPLATE"
}
# hook <state> <subcommand>: the hook's command line in that state's directive.
hook() {
    local text line
    text=$(section "$1")
    line=$(grep -o "\`\"{{PLUGIN_ROOT}}/skills/work-on/scripts/multi-pr-item-record.sh\" $2 [^\`]*\`" <<<"$text")
    line=${line#\`}
    printf '%s\n' "${line%\`}"
}

# --- the hooks ------------------------------------------------------------------------

START_LINE=$(hook analysis start)
PR_LINE=$(hook pr_creation pr)
for pair in "analysis:$START_LINE" "pr_creation:$PR_LINE"; do
    state=${pair%%:*}
    line=${pair#*:}
    case "$line" in
        *'--session {{SESSION_NAME}} --plan "{{PLAN_DOC}}" --step {{ARTIFACT_PREFIX}} --repo <owner/repo> '*'--shared-branch "{{SHARED_BRANCH}}" --issue-source "{{ISSUE_SOURCE}}"')
            pass "$state runs multi-pr-item-record.sh with the run's own session, PLAN_DOC, ARTIFACT_PREFIX, SHARED_BRANCH and ISSUE_SOURCE"
            ;;
        *) fail "$state's hook line: [$line]" ;;
    esac
done
case "$PR_LINE" in
    *'--repo <owner/repo> --number <N> '*) pass "pr_creation's hook passes the pull request's repository and number" ;;
    *) fail "pr_creation's hook: [$PR_LINE]" ;;
esac

# render <line> <session> <plan_doc> <prefix> <shared_branch> <issue_source>:
# the hook line as koto renders it, with the agent's own values for the
# repository and number.
render() {
    local l=$1
    l=${l//\{\{PLUGIN_ROOT\}\}/$REPO_ROOT}
    l=${l//\{\{SESSION_NAME\}\}/$2}
    l=${l//\{\{PLAN_DOC\}\}/$3}
    l=${l//\{\{ARTIFACT_PREFIX\}\}/$4}
    l=${l//\{\{SHARED_BRANCH\}\}/$5}
    l=${l//\{\{ISSUE_SOURCE\}\}/$6}
    l=${l//<owner\/repo>/$OWNER/r}
    l=${l//<N>/71}
    printf '%s\n' "$l"
}
# run_line <dir> <rendered line>: run it as the agent would, from <dir>.
run_line() {
    OUT=$(cd "$1" && bash -c "$2" </dev/null 2>"$WORK/stderr")
    RC=$?
}

# A multi-pr PLAN on origin's main, and an item's checkout cloned from it.
O="$WORK/origin"
mkdir -p "$O"
(cd "$O" && git init -q . && git checkout -q -b main && git config user.email t@example.com && git config user.name t \
    && mkdir -p docs/plans && printf -- '---\nschema: plan/v1\nexecution_mode: multi-pr\n---\n# PLAN\n' > docs/plans/PLAN-mp.md \
    && printf -- '---\nschema: plan/v1\nexecution_mode: single-pr\n---\n# PLAN\n' > docs/plans/PLAN-single.md \
    && git add docs/plans && git commit -q -m plans) || { echo "FAIL: could not make the fixture" >&2; exit 1; }
git clone -q "$O" "$WORK/item" || { echo "FAIL: could not clone the fixture" >&2; exit 1; }
W=$(cd "$WORK/item" && pwd -P)
mkdir -p "$RECORD_KOTO_STORE"

# --- plan-backed: the parent records it ----------------------------------------------

for case_vars in "impl/x:plan_outline" "impl/x:" ":github"; do
    sb=${case_vars%%:*}
    src=${case_vars#*:}
    for which in start pr; do
        line=$START_LINE
        [ "$which" = pr ] && line=$PR_LINE
        MARK=$(log_len)
        run_line "$W" "$(render "$line" execute-p.step-1 docs/plans/PLAN-mp.md step-1 "$sb" "$src")"
        if [ "$RC" -eq 0 ] && [ "$OUT" = skipped=plan-backed-child ] && [ "$(log_len)" -eq "$MARK" ]; then
            pass "plan-backed child (SHARED_BRANCH [$sb], ISSUE_SOURCE [$src]): the $which hook writes nothing, no koto call"
        else
            fail "plan-backed $which [$sb/$src]: exit $RC, out [$OUT], stderr [$(cat "$WORK/stderr")]"
        fi
    done
done

# --- an item ------------------------------------------------------------------------------

(cd "$W" && koto init work-on-item-1 --template work-on.md >/dev/null)
run_line "$W" "$(render "$START_LINE" work-on-item-1 docs/plans/PLAN-mp.md issue_1 "" "")"
START_RC=$RC
ROOT=$(sed -n 's/^plan_root=//p' <<<"$OUT")
run_line "$W" "$(render "$PR_LINE" work-on-item-1 docs/plans/PLAN-mp.md issue_1 "" "")"
SHARED=$(cd "$SHIRABE_RUN_RECORD_TEST_ROOT/$OWNER" 2>/dev/null && pwd -P)
get() { (cd "$SHARED" && koto context get "$1" "$2" 2>/dev/null); }
ITEM=$(get "$ROOT" trail/item/issue_1)
TRAIL_PR=$(get "$ROOT" "trail/pr/$OWNER.r.71")
RID=$(get "$ROOT" run_id)
ENTRY=$(get "pr.$OWNER.r.71" "run/$RID")
if [ "$START_RC" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$(sed -n 's/^plan_root=//p' <<<"$OUT")" = "$ROOT" ] \
    && [[ $ROOT =~ ^plan\.$OWNER\.r\.mp\.[0-9a-f]{12}$ ]]; then
    pass "an item: both hooks open the same plan root, $ROOT"
else
    fail "item hooks: exits $START_RC/$RC, root [$ROOT], out [$OUT], stderr [$(cat "$WORK/stderr")]"
fi
if [ "$(jq -c . <<<"$ITEM")" = "$(jq -nc --arg w "$W" --arg r "$OWNER/r" '{session: "work-on-item-1", workspace: $w, pr: {repo: $r, number: 71}}')" ]; then
    pass "an item: trail/item names its own session, its checkout and its PR"
else
    fail "trail/item/issue_1: [$ITEM]"
fi
if [ "$(get "$ROOT" trail/plan/issue_1.md)" = "$(git -C "$W" show HEAD:docs/plans/PLAN-mp.md)" ] \
    && [ "$(jq -r .sha <<<"$(get "$ROOT" trail/plan/issue_1.json)")" = "$(git -C "$W" rev-parse HEAD)" ]; then
    pass "an item: the root holds the PLAN as the item began, with its commit"
else
    fail "plan snapshot: [$(get "$ROOT" trail/plan/issue_1.json)]"
fi
if [ "$(jq -r '[.role, .state] | join(" ")' <<<"$TRAIL_PR")" = "item open" ] \
    && [ "$(jq -r '[.session, .mode, .topic, .workspace] | join(" ")' <<<"$ENTRY")" = "$ROOT multi-pr mp $SHARED" ]; then
    pass "an item: the PR is in the root's list as role item, and its index entry names the root at the shared address"
else
    fail "trail/pr [$TRAIL_PR], index entry [$ENTRY]"
fi

# --- record_keep: keep ------------------------------------------------------------------------

# The default action record_keep declares, as the template carries it.
KEEP_LINE=$(sed -n "s/^      command: '\(.*multi-pr-item-record\.sh\" keep .*\)'\$/\1/p" "$TEMPLATE")
case "$KEEP_LINE" in
    *'keep --session "{{SESSION_NAME}}" --plan "{{PLAN_DOC}}" --step "{{ARTIFACT_PREFIX}}" --shared-branch "{{SHARED_BRANCH}}" --issue-source "{{ISSUE_SOURCE}}" || true')
        pass "record_keep runs keep with the run's own session, PLAN_DOC, ARTIFACT_PREFIX, SHARED_BRANCH and ISSUE_SOURCE, ending || true"
        ;;
    *) fail "record_keep's command: [$KEEP_LINE]" ;;
esac
if [ "$(cd "$W" && koto context get work-on-item-1 record_root 2>/dev/null)" = "$ROOT" ]; then
    pass "an item: start recorded the plan root in the run's own session (record_root)"
else
    fail "record_root in work-on-item-1: [$(cd "$W" && koto context get work-on-item-1 record_root 2>&1)]"
fi
MARK=$(log_len)
RECORD_KOTO_VERSION=0.24.0 run_line "$W" "$(render "$KEEP_LINE" work-on-item-1 docs/plans/PLAN-mp.md issue_1 "" "")"
PINS=$(tail -n +"$((MARK + 1))" "$RECORD_KOTO_STORE/calls.log" | awk -F'\t' '$2 ~ /^session pin / { n = split($2, a, " "); print a[n] }' | LC_ALL=C sort | tr '\n' ' ')
if [ "$RC" -eq 0 ] && [ "$PINS" = "$ROOT pr.$OWNER.r.71 work-on-item-1 " ] \
    && [ "$(cd "$W" && koto context get work-on-item-1 record 2>/dev/null)" = pinned ] \
    && [ "$(jq -r .state <<<"$(get "$ROOT" "trail/pr/$OWNER.r.71")")" = ready ]; then
    pass "keep: the item's PR is recorded ready, and the plan root, the item's session and its index session are pinned; record=pinned in the item's session"
else
    fail "keep: exit $RC, pins [$PINS], out [$OUT], stderr [$(cat "$WORK/stderr")]"
fi
MARK=$(log_len)
run_line "$W" "$(render "$KEEP_LINE" execute-p.step-1 docs/plans/PLAN-mp.md step-1 impl/x plan_outline)"
[ "$RC" -eq 0 ] && [ "$OUT" = skipped=plan-backed-child ] && [ "$(log_len)" -eq "$MARK" ] \
    && pass "keep, plan-backed child: skipped=plan-backed-child, no koto call (its parent pins it)" \
    || fail "keep plan-backed: exit $RC, out [$OUT]"
(cd "$W" && koto init work-on-solo --template work-on.md >/dev/null)
run_line "$W" "$(render "$KEEP_LINE" work-on-solo "" issue_9 "" "")"
[ "$RC" -eq 0 ] && [ "$OUT" = skipped=no-record-root ] \
    && pass "keep, a run that never recorded itself as an item: skipped=no-record-root, nothing pinned" \
    || fail "keep solo: exit $RC, out [$OUT]"

# --- not an item ---------------------------------------------------------------------------

for c in ":skipped=no-plan" "docs/plans/PLAN-single.md:skipped=not-multi-pr"; do
    plan=${c%%:*}
    want=${c#*:}
    MARK=$(log_len)
    run_line "$W" "$(render "$START_LINE" work-on-x "$plan" issue_2 "" "")"
    [ "$RC" -eq 0 ] && [ "$OUT" = "$want" ] && [ "$(log_len)" -eq "$MARK" ] \
        && pass "PLAN_DOC [$plan]: $want, no koto call" \
        || fail "PLAN_DOC [$plan]: exit $RC, out [$OUT]"
done

# --- refusals --------------------------------------------------------------------------------

(cd "$W" && mkdir -p notes && printf -- '---\nexecution_mode: multi-pr\n---\n' > notes/PLAN-mp.md)
MARK=$(log_len)
run_line "$W" "$(render "$START_LINE" work-on-x notes/PLAN-mp.md issue_3 "" "")"
[ "$RC" -eq 65 ] && [ "$(log_len)" -eq "$MARK" ] \
    && pass "a PLAN outside docs/plans is refused (65), no koto call" \
    || fail "notes/PLAN-mp.md: exit $RC, out [$OUT], calls $(( $(log_len) - MARK ))"

for args in "" "stop --session s" "start --session s --plan p --step x --repo o/r --shared-branch '' --issue-source '' --extra y" \
            "start --session s --session s --plan p --step x --repo o/r --shared-branch '' --issue-source ''" \
            "pr --session s --plan p --step x --repo o/r --shared-branch '' --issue-source ''" \
            "start --session s --plan p --step x --repo o/r --shared-branch"; do
    MARK=$(log_len)
    run_line "$W" "bash '$ITEMREC' $args"
    [ "$RC" -eq 64 ] && [ "$(log_len)" -eq "$MARK" ] && pass "usage [$args]: 64, no koto call" \
        || fail "usage [$args]: exit $RC"
done

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
