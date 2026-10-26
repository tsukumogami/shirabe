#!/usr/bin/env bash
# run-record-pin_test.sh -- scripts/run-record-pin.sh, which pins the koto
# sessions holding a finished run's evidence
#
# Against the stand-in koto (scripts/testdata/record-koto/koto) reporting
# koto 0.24.0:
#
#   single-pr     a run's root, each step session that is the root's koto
#                 child (not the superseded one) and the index session of its
#                 home PR are pinned, one pin call each, with the reason
#                 `record of plan <topic>: <owner>/<repo>#<n>`; a trail/step
#                 name that is neither a child nor dispatched by the root, and
#                 an index session holding no entry for this run, are skipped
#                 and reported; `record` is pinned, `record_unpinned` empty,
#                 no trail/unpinned, and the call log holds no unpin
#   coordinated   the root, a work item whose dispatched-by link names the
#                 root (in its node's worktree) and every PR's index session,
#                 the reason naming the coordination PR; a work item without
#                 the link is skipped; one whose workspace isn't on this host
#                 is unpinned `other-workspace`
#   multi-pr      --item on a plan root: the plan root (from the shared
#                 address), the item's session and its PR's index session,
#                 the reason naming the item's PR; another item's session and
#                 index are not pinned; the result keys land in the item's
#                 own session
#   refused       pins koto refuses (2) or can't confirm (3) are written to
#                 trail/unpinned with koto's code, `record` is unpinned with
#                 the names, and the run still ends 0; --retry pins only the
#                 listed names, keeps one koto still refuses, and removes
#                 trail/unpinned once none is left; --retry with nothing
#                 listed makes no pin call (retry=none)
#   floor         below RECORD_PIN_FLOOR (a stub reporting 0.23.0) no pin call
#                 is made and `record` is unpinned (below-floor)
#   usage         a missing --root, a bad name, --item on a root that isn't a
#                 plan root: 64, no pin call
#
# And against a real koto at or above 0.24.0, in a scratch HOME on the local
# backend (skipped, loudly, when there is none): a fixture run whose
# record_keep state runs the command execute.md's record_keep declares pins
# its root, its step session and its home PR's index session; with the
# retention set to its smallest value (1s; koto refuses 0) `koto session
# prune --apply --all` keeps each of them with kept_by_pin and the reason and
# removes a finished sibling holding no pin; `koto session cleanup` of the
# pinned root exits 2 and removes nothing. Before its first koto command that
# part clears KOTO_SESSION_* and KOTO_SESSIONS_BASE, gives koto the scratch
# HOME, and asserts `koto session dir` resolves under the scratch directory,
# exiting 1 otherwise. Nothing runs against a real store.
#
# The shared address is a directory of this suite's own, through
# record-store.sh's test-only SHIRABE_RUN_RECORD_TEST_ROOT. Before the first
# stub case the suite checks that the koto on PATH is the stand-in, and stops
# when it isn't.
#
# Usage: run-record-pin_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
PIN="$SCRIPT_DIR/run-record-pin.sh"
TRAIL="$SCRIPT_DIR/run-trail.sh"
STUB_DIR="$SCRIPT_DIR/testdata/record-koto"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-record-pin-test.XXXXXX") || exit 1
WORK=$(cd "$WORK" && pwd -P) || exit 1
trap 'rm -rf "$WORK"' EXIT
export SHIRABE_RUN_RECORD_TEST_ROOT="$WORK/shared"
ORIG_PATH=$PATH
export PATH="$STUB_DIR:$PATH"
export RECORD_KOTO_STORE="$WORK/store"
A="$WORK/a"; N="$WORK/node"; B="$WORK/b"
mkdir -p "$A" "$N" "$B"
RID=00112233445566778899aabbccddeeff
RID2=ffeeddccbbaa99887766554433221100

# The koto on PATH must be the stand-in: these cases write and pin sessions,
# and a real koto would do it in a real store.
if [ "$(command -v koto)" != "$STUB_DIR/koto" ] \
    || [ "$(RECORD_KOTO_STORE="$WORK/stub-probe" koto version </dev/null)" != "koto 0.0.0-record-stub" ]; then
    echo "FAIL: the koto on PATH is not the stand-in at $STUB_DIR/koto; no case ran" >&2
    exit 1
fi
export RECORD_KOTO_VERSION=0.24.0

new_store() {
    rm -rf "$RECORD_KOTO_STORE" "$SHIRABE_RUN_RECORD_TEST_ROOT"
    mkdir -p "$RECORD_KOTO_STORE"
    unset RECORD_KOTO_PIN_FAIL
}
in_dir() { local d=$1; shift; (cd "$d" && "$@" </dev/null); }
trail() { local d=$1; shift; (cd "$d" && bash "$TRAIL" "$@" </dev/null >/dev/null) || echo "fixture: run-trail $* failed in $d" >&2; }
run_pin() { # run_pin <dir> <args>
    local d=$1
    shift
    : > "$RECORD_KOTO_STORE/calls.log"
    OUT=$(cd "$d" && bash "$PIN" "$@" </dev/null 2>"$WORK/stderr")
    RC=$?
}
# pinned_names: the names the last run's pin calls named, sorted.
pinned_names() {
    awk -F'\t' '$2 ~ /^session pin / { n = split($2, a, " "); print a[n] }' "$RECORD_KOTO_STORE/calls.log" | LC_ALL=C sort | tr '\n' ' '
}
reasons() {
    awk -F'\t' '$2 ~ /^session pin / { sub(/^session pin --reason /, "", $2); sub(/ [^ ]*$/, "", $2); print $2 }' "$RECORD_KOTO_STORE/calls.log" | LC_ALL=C sort -u
}
no_unpin() { ! awk -F'\t' '$2 ~ /^session unpin/ { found = 1 } END { exit !found }' "$RECORD_KOTO_STORE/calls.log"; }
pin_calls() { awk -F'\t' '$2 ~ /^session pin / { n++ } END { print n + 0 }' "$RECORD_KOTO_STORE/calls.log"; }
get_in() { (cd "$1" && koto context get "$2" "$3" 2>/dev/null); }
has_key() { (cd "$1" && koto context exists "$2" "$3" 2>/dev/null); }

# --- single-pr ----------------------------------------------------------------------

single_pr_fixture() {
    new_store
    in_dir "$A" koto init execute-t --template t >/dev/null
    printf '%s' "$RID" | (cd "$A" && koto context add execute-t run_id)
    trail "$A" self --session execute-t
    in_dir "$A" koto init execute-t.step-1 --parent execute-t --template t >/dev/null
    in_dir "$A" koto init execute-t.step-2-old --parent execute-t --template t >/dev/null
    in_dir "$A" koto init execute-t.step-2 --parent execute-t --template t >/dev/null
    in_dir "$A" koto init stray --template t >/dev/null
    trail "$A" step --session execute-t --step step-1 --child execute-t.step-1
    trail "$A" step --session execute-t --step step-2 --child execute-t.step-2-old
    trail "$A" step --session execute-t --step step-2 --child execute-t.step-2 --supersede
    trail "$A" step --session execute-t --step step-3 --child stray
    trail "$A" pr --session execute-t --repo acme/widgets --number 7 --role home --state ready
    trail "$A" index --repo acme/widgets --number 7 --session execute-t --mode single-pr --topic t
    # PR 8 is in the root's trail, but its index entry is another run's.
    trail "$A" pr --session execute-t --repo acme/widgets --number 8 --role follow-up --state open
    in_dir "$A" koto init execute-o --template t >/dev/null
    printf '%s' "$RID2" | (cd "$A" && koto context add execute-o run_id)
    trail "$A" index --repo acme/widgets --number 8 --session execute-o --mode single-pr --topic o
}

single_pr_fixture
run_pin "$A" --root execute-t --result execute-t
WANT="execute-t execute-t.step-1 execute-t.step-2 pr.acme.widgets.7 "
if [ "$RC" -eq 0 ] && [ "$(pinned_names)" = "$WANT" ] \
    && [ "$(pin_calls)" -eq 4 ] \
    && [ "$(reasons)" = "record of plan t: acme/widgets#7" ] && no_unpin; then
    pass "single-pr: the root, each non-superseded child step session and the home PR's index session, one pin each, reason 'record of plan t: acme/widgets#7', no unpin"
else
    fail "single-pr: exit $RC, pinned [$(pinned_names)], reasons [$(reasons)], out [$OUT], stderr [$(cat "$WORK/stderr")]"
fi
if grep -qx 'skipped=stray:not-dispatched-by-root' <<<"$OUT" && grep -qx 'skipped=pr.acme.widgets.8:no-entry' <<<"$OUT" \
    && ! grep -q 'step-2-old' <<<"$(pinned_names)"; then
    pass "single-pr: a trail/step name that is neither a child nor dispatched by the root, and an index session with no entry for this run, are skipped and reported; the superseded session is never tried"
else
    fail "single-pr skips: out [$OUT]"
fi
if [ "$(get_in "$A" execute-t record)" = pinned ] && [ -z "$(get_in "$A" execute-t record_unpinned)" ] \
    && has_key "$A" execute-t record_unpinned && ! has_key "$A" execute-t trail/unpinned \
    && grep -qx 'record=pinned' <<<"$OUT"; then
    pass "single-pr: record=pinned, record_unpinned empty, no trail/unpinned"
else
    fail "single-pr result: record [$(get_in "$A" execute-t record)], out [$OUT]"
fi
PIN7=$(get_in "$SHIRABE_RUN_RECORD_TEST_ROOT/acme" pr.acme.widgets.7 koto/links/pin)
[ "$(jq -r '.reason' <<<"$PIN7" 2>/dev/null)" = "record of plan t: acme/widgets#7" ] \
    && pass "single-pr: the index session's pin was written at the shared address" \
    || fail "single-pr: index pin [$PIN7]"

# A second run pins nothing new: koto's pin is idempotent, one call each again.
run_pin "$A" --root execute-t --result execute-t
[ "$RC" -eq 0 ] && [ "$(pinned_names)" = "$WANT" ] && grep -qx 'record=pinned' <<<"$OUT" \
    && pass "single-pr: a repeat pins the same four, idempotently" \
    || fail "single-pr repeat: [$(pinned_names)] [$OUT]"

# --- refused and retried ------------------------------------------------------------

single_pr_fixture
export RECORD_KOTO_PIN_FAIL="execute-t.step-1:2 pr.acme.widgets.7:3"
run_pin "$A" --root execute-t --result execute-t
UNP=$(get_in "$A" execute-t trail/unpinned)
if [ "$RC" -eq 0 ] && grep -qx 'unpinned=execute-t.step-1:2' <<<"$OUT" && grep -qx 'unpinned=pr.acme.widgets.7:3' <<<"$OUT" \
    && [ "$(jq -c '[.names[] | [.session, .code]]' <<<"$UNP")" = '[["execute-t.step-1","2"],["pr.acme.widgets.7","3"]]' ] \
    && [ "$(get_in "$A" execute-t record)" = unpinned ] \
    && [ "$(get_in "$A" execute-t record_unpinned)" = "execute-t.step-1 pr.acme.widgets.7" ]; then
    pass "refused: exit 2 and 3 are recorded in trail/unpinned with koto's code, record=unpinned with the names, and the run still exits 0"
else
    fail "refused: exit $RC, out [$OUT], trail/unpinned [$UNP], record [$(get_in "$A" execute-t record)]"
fi

export RECORD_KOTO_PIN_FAIL="pr.acme.widgets.7:2"
run_pin "$A" --root execute-t --retry
UNP=$(get_in "$A" execute-t trail/unpinned)
if [ "$RC" -eq 0 ] && [ "$(pinned_names)" = "execute-t.step-1 pr.acme.widgets.7 " ] \
    && [ "$(jq -c '[.names[].session]' <<<"$UNP")" = '["pr.acme.widgets.7"]' ]; then
    pass "retry: only the listed names are tried; the one koto now accepts is pinned and the one it still refuses stays listed"
else
    fail "retry 1: exit $RC, pinned [$(pinned_names)], trail/unpinned [$UNP], out [$OUT]"
fi
unset RECORD_KOTO_PIN_FAIL
run_pin "$A" --root execute-t --retry
if [ "$RC" -eq 0 ] && [ "$(pinned_names)" = "pr.acme.widgets.7 " ] && ! has_key "$A" execute-t trail/unpinned; then
    pass "retry: once koto accepts the last one, trail/unpinned is removed"
else
    fail "retry 2: exit $RC, pinned [$(pinned_names)], out [$OUT]"
fi
run_pin "$A" --root execute-t --retry
[ "$RC" -eq 0 ] && [ "$OUT" = "retry=none" ] && [ -z "$(pinned_names)" ] \
    && pass "retry with nothing listed: retry=none, no pin call" \
    || fail "retry none: exit $RC, out [$OUT], pinned [$(pinned_names)]"

# A listed name that no longer passes its check is dropped, not pinned.
single_pr_fixture
printf '%s' '{"names":[{"session":"stray","workspace":"'"$A"'","code":"2"}],"at":"2026-01-01T00:00:00Z"}' \
    | (cd "$A" && koto context add execute-t trail/unpinned)
run_pin "$A" --root execute-t --retry
if [ "$RC" -eq 0 ] && [ -z "$(pinned_names)" ] && grep -q '^skipped=stray:' <<<"$OUT" && ! has_key "$A" execute-t trail/unpinned; then
    pass "retry: a listed name that fails the provenance check is skipped, never pinned, and the list is cleared"
else
    fail "retry provenance: exit $RC, pinned [$(pinned_names)], out [$OUT]"
fi

# --- below the floor ----------------------------------------------------------------

single_pr_fixture
RECORD_KOTO_VERSION=0.23.0 run_pin "$A" --root execute-t --result execute-t
if [ "$RC" -eq 0 ] && [ -z "$(pinned_names)" ] && grep -qx 'record=unpinned' <<<"$OUT" \
    && grep -qx 'unpinned=execute-t:below-floor' <<<"$OUT" && [ "$(get_in "$A" execute-t record)" = unpinned ]; then
    pass "floor: below koto 0.24.0 no pin call is made and the result says record: unpinned (below-floor)"
else
    fail "floor: exit $RC, pinned [$(pinned_names)], out [$OUT]"
fi

# --- coordinated --------------------------------------------------------------------

new_store
in_dir "$A" koto init execute-c --template t >/dev/null
printf '%s' "$RID" | (cd "$A" && koto context add execute-c run_id)
trail "$A" self --session execute-c
in_dir "$N" koto init work-on-c-n1-1 --dispatched-by execute-c --template t >/dev/null
in_dir "$N" koto init work-on-c-n1-2 --template t >/dev/null
trail "$A" step --session execute-c --step work-on-c-n1-1 --child work-on-c-n1-1 --child-workspace "$N"
trail "$A" step --session execute-c --step work-on-c-n1-2 --child work-on-c-n1-2 --child-workspace "$N"
trail "$A" pr --session execute-c --repo acme/coord --number 10 --role coordination --state ready
trail "$A" pr --session execute-c --repo acme/widgets --number 11 --role node --state merged
trail "$A" index --repo acme/coord --number 10 --session execute-c --mode coordinated --topic c
trail "$A" index --repo acme/widgets --number 11 --session execute-c --mode coordinated --topic c
run_pin "$A" --root execute-c --result execute-c
if [ "$RC" -eq 0 ] && [ "$(pinned_names)" = "execute-c pr.acme.coord.10 pr.acme.widgets.11 work-on-c-n1-1 " ] \
    && grep -qx 'skipped=work-on-c-n1-2:not-dispatched-by-root' <<<"$OUT" \
    && [ "$(reasons | tr '\n' '|')" = "record of plan c: acme/coord#10|record of plan c: acme/widgets#11|" ] && no_unpin; then
    pass "coordinated: the root, the work item whose dispatched-by link names the root, and every PR's index session; a work item without the link is skipped; the reason names the coordination PR"
else
    fail "coordinated: exit $RC, pinned [$(pinned_names)], reasons [$(reasons)], out [$OUT]"
fi
W1=$(get_in "$N" work-on-c-n1-1 koto/links/pin)
[ "$(jq -r '.reason' <<<"$W1" 2>/dev/null)" = "record of plan c: acme/coord#10" ] \
    && pass "coordinated: the work item was pinned in its node's worktree" \
    || fail "coordinated: work item pin [$W1]"

# A work item whose recorded workspace isn't on this host.
printf '%s' '{"session":"work-on-c-n2-1","workspace":"/nonexistent-shirabe-host/node2","superseded":[]}' \
    | (cd "$A" && koto context add execute-c trail/step/work-on-c-n2-1)
run_pin "$A" --root execute-c --result execute-c
if grep -qx 'unpinned=work-on-c-n2-1:other-workspace' <<<"$OUT" && ! grep -q 'work-on-c-n2-1' <<<"$(pinned_names)" \
    && [ "$(get_in "$A" execute-c record)" = unpinned ] \
    && [ "$(jq -r '.names[0].code' <<<"$(get_in "$A" execute-c trail/unpinned)")" = other-workspace ]; then
    pass "coordinated: a session whose workspace isn't on this host is recorded unpinned (other-workspace), not skipped silently, with no pin call"
else
    fail "coordinated other-workspace: out [$OUT]"
fi

# --- multi-pr item ------------------------------------------------------------------

new_store
PR_ROOT=plan.acme.widgets.t.0123456789ab
SH="$SHIRABE_RUN_RECORD_TEST_ROOT/acme"
mkdir -p "$SH"
in_dir "$SH" koto init "$PR_ROOT" --template t >/dev/null
printf '%s' "$RID" | (cd "$SH" && koto context add "$PR_ROOT" run_id)
trail "$B" self --session "$PR_ROOT"
in_dir "$B" koto init issue_5 --template t >/dev/null
in_dir "$B" koto init issue_6 --template t >/dev/null
trail "$B" item --session "$PR_ROOT" --step issue_5 --child issue_5 --repo acme/widgets --number 21
trail "$B" pr --session "$PR_ROOT" --repo acme/widgets --number 21 --role item --state ready
trail "$B" index --repo acme/widgets --number 21 --session "$PR_ROOT" --mode multi-pr --topic t
trail "$B" item --session "$PR_ROOT" --step issue_6 --child issue_6 --repo acme/widgets --number 22
trail "$B" pr --session "$PR_ROOT" --repo acme/widgets --number 22 --role item --state open
trail "$B" index --repo acme/widgets --number 22 --session "$PR_ROOT" --mode multi-pr --topic t
run_pin "$B" --root "$PR_ROOT" --item issue_5 --result issue_5
if [ "$RC" -eq 0 ] && [ "$(pinned_names)" = "issue_5 $PR_ROOT pr.acme.widgets.21 " ] \
    && [ "$(reasons)" = "record of plan t: acme/widgets#21" ] && no_unpin \
    && [ "$(get_in "$B" issue_5 record)" = pinned ] \
    && [ "$(jq -r '.reason' <<<"$(get_in "$SH" "$PR_ROOT" koto/links/pin)")" = "record of plan t: acme/widgets#21" ]; then
    pass "multi-pr: the plan root (at the shared address), the item's session and its PR's index session, reason naming the item's PR; the other item is not pinned; record lands in the item's session"
else
    fail "multi-pr: exit $RC, pinned [$(pinned_names)], reasons [$(reasons)], out [$OUT], stderr [$(cat "$WORK/stderr")]"
fi
# A repeat pin of the plan root by the next item is idempotent.
run_pin "$B" --root "$PR_ROOT" --item issue_6 --result issue_6
[ "$RC" -eq 0 ] && [ "$(pinned_names)" = "issue_6 $PR_ROOT pr.acme.widgets.22 " ] \
    && [ "$(jq -r '.reason' <<<"$(get_in "$SH" "$PR_ROOT" koto/links/pin)")" = "record of plan t: acme/widgets#21" ] \
    && pass "multi-pr: the next item pins the plan root again, which keeps its first pin" \
    || fail "multi-pr second item: [$(pinned_names)] [$OUT]"

# --- usage --------------------------------------------------------------------------

for args in "" "--root" "--root bad/name" "--root execute-t --item issue_5" "--root execute-t --bogus x" "--root execute-t --root execute-t"; do
    # shellcheck disable=SC2086
    run_pin "$A" $args
    if [ "$RC" -eq 64 ] && [ -z "$(pinned_names)" ]; then
        pass "usage: [$args] is 64 with no pin call"
    else
        fail "usage: [$args] exit $RC, pinned [$(pinned_names)]"
    fi
done

# --- a real koto, in a scratch store ------------------------------------------------

real_koto_case() {
    local real_dir rk json cmd fixture plain guard r out unp rc
    export PATH=$ORIG_PATH
    unset RECORD_KOTO_STORE RECORD_KOTO_VERSION RECORD_KOTO_PIN_FAIL KOTO_SESSIONS_BASE KOTO_TICK_SESSION
    for v in $(env | sed -n 's/^\(KOTO_SESSION_[A-Za-z0-9_]*\)=.*/\1/p'); do
        unset "$v"
    done
    rk=$(command -v koto) || { echo "SKIP: no real koto on PATH; the real-koto case did not run"; return 0; }
    case "$rk" in "$STUB_DIR"/*) echo "SKIP: only the stand-in koto is on PATH; the real-koto case did not run"; return 0 ;; esac
    real_dir="$WORK/real"
    mkdir -p "$real_dir/home" "$real_dir/r" "$real_dir/sibling"
    export HOME="$real_dir/home"
    export SHIRABE_RUN_RECORD_TEST_ROOT="$real_dir/shared"
    guard=$(koto session dir pin-test-guard </dev/null 2>/dev/null) || guard=""
    case "$guard" in
        "$WORK"/*) ;;
        *)
            echo "FAIL: koto's session directory [$guard] is not under this suite's scratch directory; the real-koto case did not run" >&2
            exit 1
            ;;
    esac
    if ! koto version </dev/null | grep -qE '^koto (0\.(2[4-9]|[3-9][0-9])|[1-9][0-9]*)\.'; then
        echo "SKIP: the real koto is below 0.24.0 (RECORD_PIN_FLOOR); the real-koto case did not run"
        return 0
    fi
    # The command execute.md's record_keep runs, with its two variables
    # written in as koto renders them.
    json=$(koto template compile "$REPO_ROOT/skills/execute/koto-templates/execute.md" 2>/dev/null | tail -1)
    cmd=$(jq -r '.states.record_keep.default_action.command // empty' "$json" 2>/dev/null)
    if [ -z "$cmd" ]; then
        fail "real koto: execute.md declares no record_keep default action"
        return 0
    fi
    cmd=${cmd//\{\{PLUGIN_ROOT\}\}/$REPO_ROOT}
    cmd=${cmd//\{\{PLAN_SLUG\}\}/fix}
    case "$cmd" in *"'"*) fail "real koto: the record_keep command holds a quote this fixture can't carry"; return 0 ;; esac
    fixture="$real_dir/fixture.md"
    {
        printf -- '---\nname: pin-fixture\nversion: "1.0"\ninitial_state: work\n'
        printf 'pass_env: [SHIRABE_RUN_RECORD_TEST_ROOT]\n'
        printf 'states:\n  work:\n    accepts:\n      go:\n        type: enum\n        values: [yes]\n        required: true\n'
        printf '    transitions:\n      - target: record_keep\n        when:\n          go: yes\n'
        printf '  record_keep:\n    default_action:\n      command: '"'"'%s'"'"'\n    transitions:\n      - target: fin\n' "$cmd"
        printf '  fin:\n    terminal: true\n---\n## work\nWork.\n## record_keep\nPin.\n## fin\nDone.\n'
    } > "$fixture"
    # The step session and the sibling are plain runs with no pin step.
    plain="$real_dir/plain.md"
    {
        printf -- '---\nname: plain-fixture\nversion: "1.0"\ninitial_state: work\n'
        printf 'states:\n  work:\n    accepts:\n      go:\n        type: enum\n        values: [yes]\n        required: true\n'
        printf '    transitions:\n      - target: fin\n        when:\n          go: yes\n'
        printf '  fin:\n    terminal: true\n---\n## work\nWork.\n## fin\nDone.\n'
    } > "$plain"
    printf '{"go": "yes"}' > "$real_dir/go.json"
    r="$real_dir/r"
    r=$(cd "$r" && pwd -P)
    (
        cd "$r" || exit 1
        koto init execute-fix --template "$fixture" >/dev/null || exit 1
        printf '%s' "$RID" | koto context add execute-fix run_id || exit 1
        bash "$TRAIL" self --session execute-fix >/dev/null || exit 1
        koto init execute-fix.step-1 --parent execute-fix --template "$plain" >/dev/null || exit 1
        bash "$TRAIL" step --session execute-fix --step step-1 --child execute-fix.step-1 >/dev/null || exit 1
        bash "$TRAIL" pr --session execute-fix --repo acme/widgets --number 7 --role home --state ready >/dev/null || exit 1
        bash "$TRAIL" index --repo acme/widgets --number 7 --session execute-fix --mode single-pr --topic fix >/dev/null || exit 1
        # The step session finishes first, then the root goes through
        # record_keep to its terminal.
        koto next execute-fix.step-1 --with-data @"$real_dir/go.json" --no-cleanup >/dev/null || exit 1
        koto next execute-fix --with-data @"$real_dir/go.json" --no-cleanup >/dev/null || exit 1
    ) || { fail "real koto: the fixture run could not be built"; return 0; }
    (cd "$real_dir/sibling" && koto init sibling --template "$plain" >/dev/null \
        && koto next sibling --with-data @"$real_dir/go.json" --no-cleanup >/dev/null) \
        || { fail "real koto: the sibling run could not be built"; return 0; }

    if [ "$(cd "$r" && koto context get execute-fix record 2>/dev/null)" = pinned ] \
        && [ "$(cd "$r" && koto status execute-fix | jq -r '.current_state')" = fin ]; then
        pass "real koto: the fixture run reached its terminal through record_keep, which recorded record=pinned"
    else
        fail "real koto: record [$(cd "$r" && koto context get execute-fix record 2>&1)], state [$(cd "$r" && koto status execute-fix 2>&1)]"
    fi
    # Every session but the index is finished; the smallest retention koto
    # takes (it refuses 0) lets every one holding no pin go.
    koto config set --user retention.keep 1s >/dev/null 2>&1 || { fail "real koto: could not set the scratch retention"; return 0; }
    sleep 2
    out=$(cd "$r" && koto session prune --apply --all </dev/null 2>/dev/null)
    unp=$(jq -c --arg reason "record of plan fix: acme/widgets#7" '
        [.kept[] | select(.kept_by_pin == true and .pin.reason == $reason) | .name] | sort' <<<"$out" 2>/dev/null)
    if [ "$unp" = '["execute-fix","execute-fix.step-1","pr.acme.widgets.7"]' ]; then
        pass "real koto: prune --apply --all keeps the root, its step session and the index session with kept_by_pin and the reason"
    else
        fail "real koto: kept by pin [$unp], prune output [$(head -c 600 <<<"$out")]"
    fi
    if jq -e '[.removed[] | if type == "string" then . else (.name // .id // "") end] | index("sibling") != null' <<<"$out" >/dev/null 2>&1 \
        && ! (cd "$real_dir/sibling" && koto status sibling >/dev/null 2>&1); then
        pass "real koto: the finished sibling holding no pin is removed"
    else
        fail "real koto: removed [$(jq -c '.removed' <<<"$out" 2>/dev/null)]"
    fi
    (cd "$r" && koto session cleanup execute-fix </dev/null >/dev/null 2>&1)
    rc=$?
    if [ "$rc" -eq 2 ] && [ "$(cd "$r" && koto context get execute-fix record 2>/dev/null)" = pinned ]; then
        pass "real koto: koto session cleanup of the pinned root exits 2 and removes nothing"
    else
        fail "real koto: cleanup exit $rc"
    fi
}
# In a subshell, so its PATH, HOME and override end with it; its counts come
# back through a file.
(
    real_koto_case
    printf '%s %s\n' "$PASS_COUNT" "$FAIL_COUNT" > "$WORK/real.counts"
)
RC=$?
[ "$RC" -eq 0 ] || exit "$RC"
read -r PASS_COUNT FAIL_COUNT < "$WORK/real.counts"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
