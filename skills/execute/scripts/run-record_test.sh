#!/usr/bin/env bash
# run-record_test.sh — the coordinated run record's writer and reader
# Part of the execute skill
#
# run-record.sh is the one writer of a coordinated run's `run/` keys and holds
# the verb-to-field table; run-record-lib.sh is the one reader. Both run here
# on the koto context stub from coord-test-helpers.sh, whose store is a
# directory, so every write (or its absence) is observable.
#
# Cases:
#   not-owner table     for every key kind and field, each verb outside the
#                       field's owners exits 65 `refused=not-owner key= field=`,
#                       makes no `context add`, and leaves the store's bytes
#                       as they were
#   layout              a key outside the layout, the node id `coordination`,
#                       and a field no verb owns exit 66
#   values              a bad head, repo, pr, store, step, node name, run line
#                       and a setup node outside repos exit 66
#   merge and replace   a push keeps a recorded merged_head; a cascade
#                       replaces (pushed clears a failed step)
#   required fields     a node without repo, a pushed cascade without head, a
#                       failed one with a head exit 66 `incomplete`
#   preconditions       push and cascade with no run/setup, a push repo
#                       outside repos, observe on an absent key: 66; setup,
#                       recover and adopt over a record: 67, nothing written;
#                       adopt then recover where there is none: written,
#                       run/setup last
#   koto failure        a failed `context add` exits 70
#   carry               into an empty session (every key, run/setup last);
#                       over equal keys (an interrupted carry); over a
#                       differing key (67, nothing written)
#   reader              rr_cascade not-run / pushed / failed; rr_record `{}`;
#                       rr_setup absent (1) vs a failing exists (2); rr_keys
#                       ignoring keys outside the layout; rr_record refusing a
#                       value that is not an object; rr_follow_ups sorted
#   usage               an unknown verb, a missing document
#
# Usage: run-record_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
RR="$SCRIPT_DIR/run-record.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"
PROG=run-record_test
# shellcheck source=run-record-lib.sh
. "$SCRIPT_DIR/run-record-lib.sh"

S=execute-t

# rec <verb> <json> -- run run-record.sh; sets OUT and RC.
rec() {
    printf '%s' "$2" > "$CASE/doc.json"
    OUT=$(bash "$RR" "$1" --session "$S" --json "$CASE/doc.json" 2>"$CASE/stderr")
    RC=$?
}

# store_sum -- the case's whole context store, names and bytes.
store_sum() {
    (cd "$CASE/ctx" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s\n' "$f"; cat "$f"; printf '\n'
    done) | cksum
}

val() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }
adds() { grep -c '^context add ' "$CASE/koto-calls.log"; }

# expect_rc <label> <rc> <first stdout line>
expect() {
    if [ "$RC" -eq "$2" ] && [ "$(head -1 <<<"$OUT")" = "$3" ]; then
        pass "$1"
    else
        fail "$1: rc=$RC out=[$OUT] (want $2 [$3]) stderr=[$(tail -1 "$CASE/stderr")]"
    fi
}

URL10="https://github.com/acme/repo-a/pull/10"
RUNID=0123456789abcdef0123456789abcdef
SETUP_V='{"store":"github","coordination_pr":10,"repos":["acme/repo-a"],"mode":"coordinated","nodes":'"$CT_NODES_DEFAULT"',"run_lines":{}}'

# --- the not-owner table -----------------------------------------------------------
#
# One row per key kind and field: <key> <field> <a valid value> <owning verbs>.
# The owners are restated here from the design's table, so a change to the
# script's table that this test doesn't make shows up as a failure.

ct_case not-owner
ct_record_setup
ct_record_node pr-repo-a-core acme/repo-a 11
SUM0=$(store_sum)
: > "$CASE/koto-calls.log"
VERBS="setup push observe cascade follow-up recover adopt carry"
FU=run/follow-up/pr-repo-a-core/12
TABLE="run/setup|store|\"github\"|setup recover carry
run/setup|coordination_pr|10|setup recover carry
run/setup|repos|[\"acme/repo-a\"]|setup recover carry
run/setup|mode|\"coordinated\"|setup recover carry
run/setup|nodes|$CT_NODES_DEFAULT|setup recover carry
run/setup|run_lines|{}|setup recover carry
run/node/pr-repo-a-core|repo|\"acme/repo-a\"|push recover carry
run/node/pr-repo-a-core|pr|11|push recover carry
run/node/pr-repo-a-core|head|\"$CT_HEAD\"|push recover carry
run/node/pr-repo-a-core|merged_head|\"$CT_HEAD\"|observe recover carry
$FU|repo|\"acme/repo-a\"|follow-up recover carry
$FU|pr|12|follow-up recover carry
$FU|head|\"$CT_HEAD\"|follow-up recover carry
$FU|removed|false|follow-up recover carry
$FU|merged_head|\"$CT_HEAD\"|observe recover carry
run/cascade|verdict|\"pushed\"|cascade recover carry
run/cascade|head|\"$CT_HEAD\"|cascade recover carry
run/cascade|step|\"execute:cascade\"|cascade recover carry
run/recovered|pr|\"$URL10\"|recover carry
run/recovered|source|\"carried\"|recover carry
run/adopted|id|\"$RUNID\"|adopt carry
run/adopted|login|\"eval-user\"|adopt carry
run/adopted|at|\"2026-10-20T00:00:00Z\"|adopt carry"
while IFS='|' read -r key field value owners; do
    [ -n "$key" ] || continue
    bad=""
    for verb in $VERBS; do
        case " $owners " in *" $verb "*) continue ;; esac
        rec "$verb" "{\"$key\":{\"$field\":$value}}"
        if [ "$RC" -ne 65 ] || [ "$OUT" != "refused=not-owner key=$key field=$field" ]; then
            bad="$bad $verb(rc=$RC out=[$OUT])"
        fi
    done
    if [ -z "$bad" ]; then
        pass "$key.$field: every verb but [$owners] is refused not-owner"
    else
        fail "$key.$field:$bad"
    fi
done <<EOF
$TABLE
EOF
[ "$(adds)" -eq 0 ] && pass "no not-owner refusal made a context add" || fail "a refusal wrote: $(grep '^context add' "$CASE/koto-calls.log" | head -1)"
[ "$(store_sum)" = "$SUM0" ] && pass "the store's bytes are unchanged after every refusal" || fail "a refusal changed the store"

# A document mixing an owned field with one the verb doesn't own writes neither.
rec push "{\"run/node/pr-repo-a-core\":{\"head\":\"$CT_OTHER\",\"merged_head\":\"$CT_OTHER\"}}"
expect "a push carrying merged_head beside head is refused whole" 65 "refused=not-owner key=run/node/pr-repo-a-core field=merged_head"
[ "$(store_sum)" = "$SUM0" ] && pass "the partly-owned document wrote nothing" || fail "the partly-owned document wrote"

# --- layout and values ---------------------------------------------------------------

ct_case layout
ct_record_setup
SUM0=$(store_sum)
for k in run/other run/node/Bad run/node/coordination run/follow-up/pr-x/0 run/setup/x; do
    rec push "{\"$k\":{\"repo\":\"acme/repo-a\"}}"
    expect "a key outside the layout [$k] exits 66" 66 "refused=layout key=$k"
done
rec push '{"run/node/pr-repo-a-core":{"repo":"acme/repo-a","pr":11,"head":"'"$CT_HEAD"'","colour":"red"}}'
expect "a field no verb owns exits 66" 66 "refused=unknown-field key=run/node/pr-repo-a-core field=colour"
rec push '{"run/node/pr-repo-a-core":{"repo":"acme/repo-a","pr":11,"head":"abc"}}'
expect "a head that is not 40 hex" 66 "refused=invalid key=run/node/pr-repo-a-core field=head"
rec push '{"run/node/pr-repo-a-core":{"repo":"acme/../x","pr":11,"head":"'"$CT_HEAD"'"}}'
expect "a repo with a .. segment" 66 "refused=invalid key=run/node/pr-repo-a-core field=repo"
rec push '{"run/node/pr-repo-a-core":{"repo":"acme/repo-a","pr":0,"head":"'"$CT_HEAD"'"}}'
expect "a pr of 0" 66 "refused=invalid key=run/node/pr-repo-a-core field=pr"
rec push '{"run/node/pr-repo-a-core":{"repo":"acme/repo-a","pr":"11","head":"'"$CT_HEAD"'"}}'
expect "a pr given as a string" 66 "refused=invalid key=run/node/pr-repo-a-core field=pr"
rec cascade '{"run/cascade":{"verdict":"failed","step":"deploy"}}'
expect "a step outside ^execute:[a-z-]+\$" 66 "refused=invalid key=run/cascade field=step"
[ "$(store_sum)" = "$SUM0" ] && pass "no layout or value refusal changed the store" || fail "a refusal changed the store"

ct_case setup-values
rec setup "{\"run/setup\":$(printf '%s' "$SETUP_V" | jq -c '.store = "s3"')}"
expect "a store other than github or session" 66 "refused=invalid key=run/setup field=store"
rec setup "{\"run/setup\":$(printf '%s' "$SETUP_V" | jq -c '.nodes[0].name = "coordination"')}"
expect "a node named coordination" 66 "refused=invalid key=run/setup field=nodes"
rec setup "{\"run/setup\":$(printf '%s' "$SETUP_V" | jq -c '.repos = ["acme/repo-b", "acme/repo-a"]')}"
expect "repos not sorted" 66 "refused=invalid key=run/setup field=repos"
rec setup "{\"run/setup\":$(printf '%s' "$SETUP_V" | jq -c '.run_lines = {"topic": "a b"}')}"
expect "a run line outside its pattern" 66 "refused=invalid key=run/setup field=run_lines"
rec setup "{\"run/setup\":$(printf '%s' "$SETUP_V" | jq -c '.run_lines = {"owner": "x"}')}"
expect "a run line other than topic, exit, outcome, intent, mode" 66 "refused=invalid key=run/setup field=run_lines"
rec setup "{\"run/setup\":$(printf '%s' "$SETUP_V" | jq -c '.nodes[1].repo = "acme/repo-b"')}"
expect "a PR node whose repository is not in repos" 66 "refused=repo-outside key=run/setup field=nodes"
rec setup "{\"run/setup\":$(printf '%s' "$SETUP_V" | jq -c 'del(.mode)')}"
expect "a run/setup without mode" 66 "refused=incomplete key=run/setup field=mode"
[ -z "$(ls "$CASE/ctx/$S" | grep -vx -e run_id -e pr_content)" ] && pass "no refused setup wrote a key" || fail "a refused setup wrote"
rec setup "{\"run/setup\":$SETUP_V}"
expect "a valid setup" 0 "written=run/setup"
[ "$(val run/setup)" = "$(printf '%s' "$SETUP_V" | jq -cS .)" ] && pass "run/setup is stored as canonical JSON" || fail "run/setup stored as [$(val run/setup)]"
rec setup "{\"run/setup\":$SETUP_V}"
expect "a second setup over the record" 67 "refused=conflict key=run/setup"
SUM0=$(store_sum)
REC_DOC="{\"run/setup\":$SETUP_V,\"run/node/pr-repo-a-core\":{\"repo\":\"acme/repo-a\",\"pr\":11,\"head\":\"$CT_HEAD\"},\"run/cascade\":{\"verdict\":\"not-run\"},\"run/recovered\":{\"pr\":\"$URL10\",\"source\":\"run-line\"}}"
rec recover "$REC_DOC"
expect "a recover over an existing run/setup" 67 "refused=conflict key=run/setup"
rec adopt "{\"run/adopted\":{\"id\":\"$RUNID\",\"login\":\"eval-user\",\"at\":\"2026-10-20T00:00:00Z\"}}"
expect "an adopt over an existing run/setup" 67 "refused=conflict key=run/setup"
[ "$(store_sum)" = "$SUM0" ] && pass "the refused recover and adopt wrote nothing" || fail "a refused recover or adopt wrote"

# recover and adopt where there is no record: the recovery's own writes.
ct_case recover
rec adopt "{\"run/adopted\":{\"id\":\"$RUNID\",\"login\":\"eval-user\",\"at\":\"2026-10-20T00:00:00Z\"}}"
expect "an adopt with no run/setup" 0 "written=run/adopted"
rec recover "$REC_DOC"
if [ "$RC" -eq 0 ] && [ "$(tail -1 <<<"$OUT")" = "written=run/setup" ] \
    && [ "$(val run/recovered)" = "{\"pr\":\"$URL10\",\"source\":\"run-line\"}" ] \
    && [ "$(val run/cascade)" = '{"verdict":"not-run"}' ]; then
    pass "a recover with no run/setup writes the whole record, run/setup last"
else
    fail "recover: rc=$RC out=[$OUT]"
fi

# --- merge, replace, required fields -------------------------------------------------

ct_case merge
ct_record_setup
rec push "{\"run/node/pr-repo-a-core\":{\"repo\":\"acme/repo-a\",\"pr\":11}}"
expect "a first push without a head" 66 "refused=incomplete key=run/node/pr-repo-a-core field=head"
rec observe "{\"run/node/pr-repo-a-core\":{\"merged_head\":\"$CT_HEAD\"}}"
expect "observe on a node with no record yet" 66 "refused=absent key=run/node/pr-repo-a-core"
ct_record_node pr-repo-a-core acme/repo-a 11 "$CT_HEAD"
rec observe "{\"run/node/pr-repo-a-core\":{\"merged_head\":\"$CT_HEAD\"}}"
expect "observe records merged_head" 0 "written=run/node/pr-repo-a-core"
rec push "{\"run/node/pr-repo-a-core\":{\"head\":\"$CT_OTHER\"}}"
expect "a later push of a new head" 0 "written=run/node/pr-repo-a-core"
got=$(val run/node/pr-repo-a-core | jq -c '[.repo, .pr, .head, .merged_head]')
want=$(jq -cn --arg h "$CT_OTHER" --arg m "$CT_HEAD" '["acme/repo-a", 11, $h, $m]')
[ "$got" = "$want" ] && pass "the push merged: the new head, and merged_head kept" || fail "after the push: $got"
rec push '{"run/node/pr-repo-a-cli":{"repo":"acme/repo-b","pr":21,"head":"'"$CT_HEAD"'"}}'
expect "a push to a repository outside run/setup's repos" 66 "refused=repo-outside key=run/node/pr-repo-a-cli field=repo"

ct_case cascade
rec cascade "{\"run/cascade\":{\"verdict\":\"pushed\",\"head\":\"$CT_HEAD\"}}"
expect "a cascade with no run/setup" 66 "refused=no-setup key=run/setup"
rec push "{\"run/node/pr-repo-a-core\":{\"repo\":\"acme/repo-a\",\"pr\":11,\"head\":\"$CT_HEAD\"}}"
expect "a push with no run/setup" 66 "refused=no-setup key=run/setup"
ct_record_setup
rec cascade '{"run/cascade":{"verdict":"pushed"}}'
expect "a pushed cascade without its head" 66 "refused=incomplete key=run/cascade field=head"
rec cascade "{\"run/cascade\":{\"verdict\":\"failed\",\"step\":\"execute:cascade\",\"head\":\"$CT_HEAD\"}}"
expect "a failed cascade carrying a head" 66 "refused=incomplete key=run/cascade field=head"
ct_record_cascade failed execute:cascade
[ "$(val run/cascade)" = '{"step":"execute:cascade","verdict":"failed"}' ] && pass "a failed cascade records its step" || fail "failed: [$(val run/cascade)]"
ct_record_cascade pushed "$CT_HEAD"
[ "$(val run/cascade)" = "{\"head\":\"$CT_HEAD\",\"verdict\":\"pushed\"}" ] \
    && pass "a pushed cascade replaces the key: the failed step is gone" || fail "pushed: [$(val run/cascade)]"

ct_case follow-up-number
ct_record_setup
rec follow-up "{\"run/follow-up/pr-repo-a-core/12\":{\"repo\":\"acme/repo-a\",\"pr\":13,\"head\":\"$CT_HEAD\",\"removed\":false}}"
expect "a follow-up whose pr differs from its key" 66 "refused=invalid key=run/follow-up/pr-repo-a-core/12 field=pr"

ct_case koto-fails
ct_record_setup
export KOTO_FAIL_ADD=run/node/pr-repo-a-core
rec push "{\"run/node/pr-repo-a-core\":{\"repo\":\"acme/repo-a\",\"pr\":11,\"head\":\"$CT_HEAD\"}}"
expect "a failed context add exits 70" 70 "failed=koto-write key=run/node/pr-repo-a-core"
unset KOTO_FAIL_ADD
export KOTO_FAIL_LIST=1
rec push "{\"run/node/pr-repo-a-core\":{\"repo\":\"acme/repo-a\",\"pr\":11,\"head\":\"$CT_HEAD\"}}"
expect "a failed record read exits 70" 70 "failed=koto-read"
unset KOTO_FAIL_LIST

# --- carry ---------------------------------------------------------------------------

CARRY=$(jq -cn --argjson s "$SETUP_V" --arg h "$CT_HEAD" '{
    "run/setup": $s,
    "run/node/pr-repo-a-core": {repo: "acme/repo-a", pr: 11, head: $h, merged_head: $h},
    "run/node/pr-repo-a-cli": {repo: "acme/repo-a", pr: 12, head: $h},
    "run/cascade": {verdict: "not-run"}}')

ct_case carry-empty
: > "$CASE/koto-calls.log"
rec carry "$CARRY"
order=$(grep '^context add' "$CASE/koto-calls.log" | awk '{print $4}' | tr '\n' ' ')
if [ "$RC" -eq 0 ] && [ "$order" = "run/cascade run/node/pr-repo-a-cli run/node/pr-repo-a-core run/setup " ]; then
    pass "a carry into an empty session writes every key, run/setup last"
else
    fail "carry-empty: rc=$RC order=[$order] out=[$OUT]"
fi
[ "$(rr_record "$S")" = "$(printf '%s' "$CARRY" | jq -cS .)" ] && pass "the carried record reads back equal" || fail "carried record differs"

ct_case carry-interrupted
ct_record setup "{\"run/setup\":$SETUP_V}"
ct_record push "{\"run/node/pr-repo-a-cli\":{\"repo\":\"acme/repo-a\",\"pr\":12,\"head\":\"$CT_HEAD\"}}"
rec carry "$CARRY"
[ "$RC" -eq 0 ] && [ "$(rr_record "$S")" = "$(printf '%s' "$CARRY" | jq -cS .)" ] \
    && pass "a carry over keys equal to the document completes (an interrupted carry re-run)" \
    || fail "carry-interrupted: rc=$RC out=[$OUT]"

ct_case carry-conflict
ct_record setup "{\"run/setup\":$SETUP_V}"
ct_record push "{\"run/node/pr-repo-a-cli\":{\"repo\":\"acme/repo-a\",\"pr\":99,\"head\":\"$CT_HEAD\"}}"
SUM0=$(store_sum)
rec carry "$CARRY"
expect "a carry over a differing key exits 67" 67 "refused=conflict key=run/node/pr-repo-a-cli"
[ "$(store_sum)" = "$SUM0" ] && pass "the conflicting carry wrote nothing" || fail "the conflicting carry wrote"

# --- the reader ----------------------------------------------------------------------

ct_case reader
got=$(rr_record "$S"); rc=$?
[ "$rc" -eq 0 ] && [ "$got" = "{}" ] && pass "rr_record prints {} with no record" || fail "rr_record empty: rc=$rc [$got]"
got=$(rr_cascade "$S")
[ "$(printf '%s' "$got" | jq -r .verdict)" = not-run ] && pass "rr_cascade reads not-run with no key" || fail "rr_cascade absent: [$got]"
rr_setup "$S" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "rr_setup returns 1 when run/setup is absent" || fail "rr_setup absent rc=$rc"
rr_node "$S" pr-repo-a-core >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "rr_node returns 1 when the node has no record" || fail "rr_node absent rc=$rc"
ct_record_setup
KOTO_FAIL_EXISTS=run/setup rr_setup "$S" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && pass "rr_setup returns 2 when the existence check fails" || fail "rr_setup failing exists rc=$rc"
got=$(rr_nodes "$S" | jq -r 'map(.name) | join(",")')
[ "$got" = "pr-repo-a-core,pr-repo-a-cli" ] && pass "rr_nodes reads the sealed node list in order" || fail "rr_nodes: [$got]"
ct_record_cascade pushed "$CT_HEAD"
got=$(rr_cascade "$S" | jq -r '"\(.verdict) \(.head)"')
[ "$got" = "pushed $CT_HEAD" ] && pass "rr_cascade reads pushed with the head" || fail "rr_cascade pushed: [$got]"
ct_record_cascade failed execute:cascade
got=$(rr_cascade "$S" | jq -r '"\(.verdict) \(.step)"')
[ "$got" = "failed execute:cascade" ] && pass "rr_cascade reads failed with the step" || fail "rr_cascade failed: [$got]"
mkdir -p "$CASE/ctx/$S/run/node"
printf 'stray' > "$CASE/ctx/$S/run/other"
printf '{}' > "$CASE/ctx/$S/run/node/coordination"
got=$(rr_keys "$S" 2>"$CASE/stderr" | tr '\n' ' ')
if [ "$got" = "run/cascade run/setup " ] && grep -q 'run/other' "$CASE/stderr"; then
    pass "rr_keys ignores keys outside the layout, naming them on stderr"
else
    fail "rr_keys: [$got] stderr=[$(cat "$CASE/stderr")]"
fi
got=$(rr_record "$S" 2>/dev/null | jq -r 'keys | join(",")')
[ "$got" = "run/cascade,run/setup" ] && pass "rr_record reads only layout keys" || fail "rr_record keys: [$got]"
printf 'not json' > "$CASE/ctx/$S/run/node/pr-repo-a-core"
rr_record "$S" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && pass "rr_record returns 2 on a value that is not a JSON object" || fail "rr_record bad value rc=$rc"
rm -f "$CASE/ctx/$S/run/node/pr-repo-a-core" "$CASE/ctx/$S/run/other" "$CASE/ctx/$S/run/node/coordination"
ct_record follow-up "{\"run/follow-up/pr-repo-a-core/30\":{\"repo\":\"acme/repo-a\",\"pr\":30,\"head\":\"$CT_HEAD\",\"removed\":false}}"
ct_record follow-up "{\"run/follow-up/pr-repo-a-core/4\":{\"repo\":\"acme/repo-a\",\"pr\":4,\"head\":\"$CT_HEAD\",\"removed\":true}}"
got=$(rr_follow_ups "$S" pr-repo-a-core 2>/dev/null | jq -c 'map(.pr)')
[ "$got" = "[4,30]" ] && pass "rr_follow_ups lists a node's follow-ups sorted by pr" || fail "rr_follow_ups: [$got]"
got=$(rr_follow_ups "$S" pr-repo-a-cli 2>/dev/null)
[ "$got" = "[]" ] && pass "rr_follow_ups prints [] for a node with none" || fail "rr_follow_ups none: [$got]"

# --- usage ---------------------------------------------------------------------------

ct_case usage
rec frobnicate '{}'
expect "an unknown verb exits 64" 64 "refused=usage"
OUT=$(bash "$RR" push --session "$S" 2>/dev/null); RC=$?
expect "a missing --json exits 64" 64 "refused=usage"
rec push '[]'
expect "a document that is not an object of key objects exits 66" 66 "refused=invalid"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
