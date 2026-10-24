#!/usr/bin/env bash
# coord-render_test.sh — coord-render.sh keeps the coordination PR's body the
# rendering of the run's record, records the merges it sees, and posts only
# on a difference
# Part of the execute skill
#
# Each case runs coord-render.sh against the eval gh shim's repository model,
# the koto stub and the shirabe stub (coord-test-helpers.sh), over a run
# record seeded through run-record.sh. Cases:
#
#   a body behind the record          posted once; a second render, and a
#                                     render after a live-state change alone
#                                     (checks finishing, a ready toggle), are
#                                     unchanged: one pr edit in all
#   /scope's body (no top-level ---)  gets exactly the composed Part 1
#   a person's Part 1 holding a list  kept byte for byte
#   a follow-up recorded              rendered after its node
#   a state read that fails           renders unknown
#   a post that fails                 body=stale, the record unchanged; the
#                                     next render posts
#   Part 1 edited before the post     body=stale, no pr edit
#   a node newly merged               run/node gains merged_head (the
#                                     shim's merge commit), and its koto
#                                     write comes before the pr edit showing it;
#                                     its trail/pr record becomes merged,
#                                     role kept
#   an observe the record can't take  body=stale, nothing posted
#   a body over 60,000 bytes          body=full, no pr edit
#   --before-coordination             a stale or full body records
#                                     coordination:body-stale|body-full and
#                                     prints merge-refused:body-stale|body-full
#   a private node under a public home  body=refused:execute:visibility,
#                                     exit 77, no edit, the repository unnamed
#   a failed visibility read          body=stale
#   --rendered-out                    writes the bytes posted on body=posted,
#                                     the live bytes found equal on
#                                     body=unchanged, nothing on body=stale;
#                                     a directory, or no --before-coordination,
#                                     is a usage error
#   a MERGED coordination PR          merges observed, nothing posted
#   the coordination PR on another branch  body=stale, no edit
#   no run/setup                      body=stale
#   no output line names a path or a token
#
# Usage: coord-render_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
RENDER="$SCRIPT_DIR/coord-render.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

S=execute-t

run_render() { # run_render [--before-coordination]
    OUT=$(cd "$CASE" && bash "$RENDER" --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" "$@" 2>"$CASE/stderr")
    RC=$?
}
edits() { ct_calls | grep -c '^pr edit 10 '; }
live_body() { jq -j '.prs[] | select(.number == 10) | .body' "$GH_CALL_LOG.d/db.json"; }
node_rec() { cat "$CASE/ctx/$S/run/node/$1" 2>/dev/null; }
merge_sha() { printf 'merge %s#%s' "$1" "$2" | git hash-object --stdin; }

# base_case <name> -- run/setup over the default two nodes, core pushed as
# #11 and cli as #12, both open, under /scope's body.
base_case() {
    ct_case "$1"
    ct_record_setup
    ct_record_node "$CT_CORE" "$CT_REPO" 11
    ct_record_node "$CT_CLI" "$CT_REPO" 12 "$CT_OTHER"
    ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
    ct_pr "$CT_REPO" 12 "impl/t-$CT_CLI"
}

# --- a body behind the record posts once ------------------------------------------

base_case behind
ct_write_db
run_render
FIRST="$OUT"
live_body > "$CASE/after1.md"
run_render
SECOND="$OUT"
# A live change the body doesn't show: the checks finish and the PR is readied.
jq '(.prs[] | select(.number == 11)) |= (.checks = [{name: "build", bucket: "pass"}, {name: "lint", bucket: "pass"}] | .isDraft = true)' \
    "$GH_CALL_LOG.d/db.json" > "$CASE/db.tmp" && mv "$CASE/db.tmp" "$GH_CALL_LOG.d/db.json"
run_render
THIRD="$OUT"
if [ "$FIRST" = "body=posted" ] && [ "$SECOND" = "body=unchanged" ] && [ "$THIRD" = "body=unchanged" ] && [ "$(edits)" = 1 ]; then
    pass "a body behind the record posts once; a second render and a live-state change alone post nothing"
else
    fail "posts once [$FIRST] [$SECOND] [$THIRD], $(edits) edits: $(cat "$CASE/stderr")"
fi
if grep -qxF -- "- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#11 | open | head=$CT_HEAD" "$CASE/after1.md" \
    && grep -qxF -- "- $CT_CLI | $CT_REPO:docs/plans/PLAN-t.md#12 | open | head=$CT_OTHER" "$CASE/after1.md" \
    && grep -qxF 'run=00112233445566778899aabbccddeeff' "$CASE/after1.md" \
    && ! grep -Eq '#10([^0-9]|$)|^- coordination ' "$CASE/after1.md"; then
    pass "the posted body indexes each node at its recorded head, carries run=, and no self row"
else
    fail "the posted body: $(cat "$CASE/after1.md")"
fi
WANT="Coordination pull request for t. It carries the planning documents for 2 node pull requests and merges after all of them.

---"
if [ "$(head -3 "$CASE/after1.md")" = "$WANT" ]; then
    pass "/scope's body (no top-level ---) gets exactly the composed Part 1"
else
    fail "the composed Part 1: $(head -3 "$CASE/after1.md")"
fi
if grep -q 'Artifact Chain\|# Coordination PR:' "$CASE/after1.md"; then
    fail "the composed body drops /scope's heading and artifact chain"
else
    pass "the composed body replaces /scope's heading and artifact chain"
fi

# --- a person's Part 1 holding a list is kept ---------------------------------------

base_case part1
printf 'Ships the parser.\n\n- parser\n- its CLI\n\n```text\n---\n```\n\n---\n\nold index\n' > "$CASE/seed.md"
printf 'Ships the parser.\n\n- parser\n- its CLI\n\n```text\n---\n```\n\n' > "$CASE/want-p1.md"
ct_write_db "$CASE/seed.md"
run_render
live_body > "$CASE/after.md"
head -c "$(wc -c < "$CASE/want-p1.md")" "$CASE/after.md" > "$CASE/got-p1.md"
if [ "$OUT" = "body=posted" ] && cmp -s "$CASE/want-p1.md" "$CASE/got-p1.md" \
    && [ "$(sed -n "$(($(wc -l < "$CASE/want-p1.md") + 1))p" "$CASE/after.md")" = "---" ]; then
    pass "a person's Part 1 holding a list (and a fenced ---) is kept byte for byte"
else
    fail "Part 1 kept [$OUT]: $(head -12 "$CASE/after.md")"
fi
if ! grep -q 'old index' "$CASE/after.md"; then
    pass "everything below Part 1 is the record's rendering"
else
    fail "the old Part 2 survived the render"
fi

# --- a run marker the live body carries -----------------------------------------------

base_case marker
MARK='<!-- shirabe-run: 0123456789abcdef0123456789abcdef -->'
printf 'Ships the parser.\n\n---\n\nold index\n\n%s\n' "$MARK" > "$CASE/seed.md"
ct_write_db "$CASE/seed.md"
run_render
live_body > "$CASE/after.md"
FIRST_MARK="$OUT"
run_render
if [ "$FIRST_MARK" = "body=posted" ] && [ "$(tail -1 "$CASE/after.md")" = "$MARK" ] \
    && [ "$(grep -c 'shirabe-run:' "$CASE/after.md")" = 1 ] && [ "$OUT" = "body=unchanged" ]; then
    pass "a run marker the live body carries is kept, at the end, and a second render leaves it"
else
    fail "the run marker [$FIRST_MARK] [$OUT]: $(tail -3 "$CASE/after.md")"
fi
if grep -q 'shirabe-run:' "$CT_WORK/cases/behind/after1.md"; then
    fail "a render forged a run marker into a body that carried none"
else
    pass "a body that carried no run marker gets none"
fi

# --- a follow-up -----------------------------------------------------------------------

base_case follow-up
ct_record_follow_up "$CT_CORE" "$CT_REPO" 21 "$CT_OTHER"
ct_record_follow_up "$CT_CORE" "$CT_REPO" 22 "$CT_OTHER" true
ct_pr "$CT_REPO" 21 "fix/core-x"
ct_write_db
run_render
live_body > "$CASE/after.md"
IDX=$(awk '/^## PR Index/ { s = 1; next } /^## / { s = 0 } s && /^- / { print }' "$CASE/after.md")
if [ "$OUT" = "body=posted" ] && [ "$IDX" = "- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#11 | open | head=$CT_HEAD
- $CT_CORE/follow-up-21 | $CT_REPO:docs/plans/PLAN-t.md#21 | open | head=$CT_OTHER
- $CT_CLI | $CT_REPO:docs/plans/PLAN-t.md#12 | open | head=$CT_OTHER" ]; then
    pass "a follow-up renders after its node, a removed one not at all"
else
    fail "follow-up lines [$OUT]: $IDX"
fi

# --- a state read that fails renders unknown -----------------------------------------

base_case state-fails
ct_write_db
GH_SHIM_FAIL='^pr view 12 ' run_render
live_body > "$CASE/after.md"
if [ "$OUT" = "body=posted" ] && grep -qxF -- "- $CT_CLI | $CT_REPO:docs/plans/PLAN-t.md#12 | unknown | head=$CT_OTHER" "$CASE/after.md"; then
    pass "a state read the stub fails renders unknown"
else
    fail "a failed state read [$OUT]: $(grep "$CT_CLI |" "$CASE/after.md")"
fi

# --- a post that fails ------------------------------------------------------------------

base_case post-fails
ct_write_db
REC_BEFORE=$(cd "$CASE/ctx/$S" && find run -type f | LC_ALL=C sort | while IFS= read -r k; do printf '%s %s\n' "$k" "$(cat "$k")"; done)
GH_SHIM_FAIL='^pr edit ' run_render
STALE_OUT="$OUT"; STALE_RC="$RC"
REC_AFTER=$(cd "$CASE/ctx/$S" && find run -type f | LC_ALL=C sort | while IFS= read -r k; do printf '%s %s\n' "$k" "$(cat "$k")"; done)
run_render
if [ "$STALE_OUT" = "body=stale" ] && [ "$STALE_RC" -eq 0 ] && [ "$REC_BEFORE" = "$REC_AFTER" ] && [ "$OUT" = "body=posted" ]; then
    pass "a post the stub fails reports body=stale (exit 0), leaves the record unchanged, and the next render posts"
else
    fail "a failed post [$STALE_OUT/$STALE_RC] then [$OUT]"
fi

# --- Part 1 edited between the render and the post ---------------------------------------

base_case part1-edited
ct_write_db
cat > "$CASE/hook.sh" <<'HOOK'
case "$1 $2 $3" in "pr view 10") ;; *) exit 0 ;; esac
n=$(cat "$KOTO_STORE/hook.n" 2>/dev/null || echo 0)
n=$((n + 1)); echo "$n" > "$KOTO_STORE/hook.n"
[ "$n" -eq 2 ] || exit 0
db="$GH_CALL_LOG.d/db.json"
jq '(.prs[] | select(.number == 10) | .body) = "A person wrote this.\n\n---\n\n" + (.prs[] | select(.number == 10) | .body)' "$db" > "$db.hook" && mv "$db.hook" "$db"
HOOK
CT_GH_HOOK="$CASE/hook.sh" run_render
if [ "$OUT" = "body=stale" ] && [ "$(edits)" = 0 ]; then
    pass "a Part 1 edited between the render and the post skips the post with body=stale"
else
    fail "Part 1 edited [$OUT], $(edits) edits"
fi

# --- a node newly merged is observed, recorded before the post ---------------------------

base_case observe
ct_write_db
# The node PR as node-push.sh recorded it in the run's trail, readied since.
TRAIL_KEY="trail/pr/$(printf '%s' "$CT_REPO" | tr '[:upper:]/' '[:lower:].').11"
mkdir -p "$(dirname "$CASE/ctx/$S/$TRAIL_KEY")"
jq -cn --arg r "$(printf '%s' "$CT_REPO" | tr '[:upper:]' '[:lower:]')" \
    '{repo: $r, number: 11, role: "node", state: "ready", recorded_at: "2026-01-01T00:00:00Z"}' > "$CASE/ctx/$S/$TRAIL_KEY"
run_render
gh shim-mark-merged "$CT_REPO" 11
WANT_SHA=$(merge_sha "$CT_REPO" 11)
: > "$CASE/order.log"
run_render
live_body > "$CASE/after.md"
MH=$(node_rec "$CT_CORE" | jq -r '.merged_head // ""')
ORDER=$(ct_order)
ADD_AT=$(awk -v k="koto context add $S run/node/$CT_CORE" '$0 == k && !n { n = NR } END { print n }' <<<"$ORDER")
EDIT_AT=$(awk '/^gh pr edit 10 / && !n { n = NR } END { print n }' <<<"$ORDER")
if [ "$OUT" = "observed=$CT_CORE:$WANT_SHA
body=posted" ] && [ "$MH" = "$WANT_SHA" ] \
    && grep -qxF -- "- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#11 | merged | head=$WANT_SHA" "$CASE/after.md"; then
    pass "a newly merged node is observed: run/node gains the merge commit as merged_head, and the body shows it"
else
    fail "observe [$OUT] merged_head [$MH]: $(grep "$CT_CORE |" "$CASE/after.md")"
fi
if [ -n "$ADD_AT" ] && [ -n "$EDIT_AT" ] && [ "$ADD_AT" -lt "$EDIT_AT" ]; then
    pass "in the request log, the koto write of run/node/$CT_CORE comes before the pr edit that shows it"
else
    fail "order: add at [$ADD_AT], edit at [$EDIT_AT]: $ORDER"
fi
if [ "$(jq -r '.state + " " + .role' "$CASE/ctx/$S/$TRAIL_KEY" 2>/dev/null)" = "merged node" ]; then
    pass "the newly merged node is also recorded merged in the run's trail, its role kept"
else
    fail "trail after the observe: [$(cat "$CASE/ctx/$S/$TRAIL_KEY" 2>/dev/null)]"
fi
run_render
if [ "$OUT" = "body=unchanged" ]; then
    pass "a merge already recorded is not observed again"
else
    fail "a second render after the observe [$OUT]"
fi

base_case observe-fails
ct_write_db
run_render
gh shim-mark-merged "$CT_REPO" 11
KOTO_FAIL_ADD="run/node/$CT_CORE" run_render
if [ "$OUT" = "body=stale" ] && [ "$(edits)" = 1 ] && [ -z "$(node_rec "$CT_CORE" | jq -r '.merged_head // ""')" ]; then
    pass "an observe the record can't take posts nothing (body=stale)"
else
    fail "a failed observe [$OUT], $(edits) edits"
fi

# --- over the cap --------------------------------------------------------------------------

base_case full
awk 'BEGIN { s = ""; while (length(s) < 60000) s = s "x"; printf "%s\n\n---\n", s }' > "$CASE/seed.md"
ct_write_db "$CASE/seed.md"
run_render
if [ "$OUT" = "body=full" ] && [ "$RC" -eq 0 ] && [ "$(edits)" = 0 ]; then
    pass "a body over 60,000 bytes reports body=full and posts nothing"
else
    fail "an oversize body [$OUT/$RC], $(edits) edits"
fi
run_render --before-coordination
if [ "$OUT" = "body=full
merge-refused:body-full" ] && [ "$(cat "$CASE/ctx/$S/merge_attempts")" = "coordination:body-full" ]; then
    pass "--before-coordination: a full body records coordination:body-full and prints merge-refused:body-full"
else
    fail "--before-coordination full [$OUT] [$(cat "$CASE/ctx/$S/merge_attempts" 2>/dev/null)]"
fi

base_case before-stale
ct_write_db
printf '%s' "$CT_CORE:merge-call-failed" > "$CASE/ctx/$S/merge_attempts"
GH_SHIM_FAIL='^pr edit ' run_render --before-coordination
if [ "$OUT" = "body=stale
merge-refused:body-stale" ] && [ "$RC" -eq 0 ] \
    && [ "$(cat "$CASE/ctx/$S/merge_attempts")" = "$CT_CORE:merge-call-failed,coordination:body-stale" ]; then
    pass "--before-coordination: a stale body records coordination:body-stale beside the other attempts and prints merge-refused:body-stale"
else
    fail "--before-coordination stale [$OUT/$RC] [$(cat "$CASE/ctx/$S/merge_attempts" 2>/dev/null)]"
fi
run_render --before-coordination
if [ "$OUT" = "body=posted" ]; then
    pass "--before-coordination: a body that posts prints no merge-refused line"
else
    fail "--before-coordination posted [$OUT]"
fi

# --- --rendered-out hands back the body posted or found equal ----------------------------

base_case rendered-out
ct_write_db
# A hook keeps the --body-file the post carried, byte for byte (the shim's
# model drops its trailing newlines, as GitHub may).
cat > "$CASE/keep-post.sh" <<'HOOK'
[ "$1 $2" = "pr edit" ] || exit 0
prev=""
for a in "$@"; do
    if [ "$prev" = --body-file ]; then cp "$a" "$KOTO_STORE/sent-body.md"; fi
    prev="$a"
done
exit 0
HOOK
CT_GH_HOOK="$CASE/keep-post.sh" run_render --before-coordination --rendered-out "$CASE/posted.md"
live_body > "$CASE/live-after-post.md"
if [ "$OUT" = "body=posted" ] && [ -f "$CASE/posted.md" ] && cmp -s "$CASE/posted.md" "$CASE/sent-body.md" \
    && grep -qxF -- "- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#11 | open | head=$CT_HEAD" "$CASE/posted.md"; then
    pass "--rendered-out: on body=posted it writes the exact bytes posted"
else
    fail "--rendered-out posted [$OUT] [$(sed -n 1,3p "$CASE/posted.md" 2>/dev/null)]"
fi
# The live body with a trailing newline GitHub kept: the render finds it equal
# and hands back the live bytes, not its own.
printf '\n\n' >> "$CASE/live-after-post.md"
jq --rawfile b "$CASE/live-after-post.md" '(.prs[] | select(.number == 10) | .body) = $b' \
    "$GH_CALL_LOG.d/db.json" > "$CASE/db.tmp" && mv "$CASE/db.tmp" "$GH_CALL_LOG.d/db.json"
EDITS_BEFORE=$(edits)
run_render --before-coordination --rendered-out "$CASE/unchanged.md"
if [ "$OUT" = "body=unchanged" ] && cmp -s "$CASE/unchanged.md" "$CASE/live-after-post.md" && [ "$(edits)" = "$EDITS_BEFORE" ]; then
    pass "--rendered-out: on body=unchanged it writes the live body it found equal, with no post"
else
    fail "--rendered-out unchanged [$OUT], $(edits) edits, file [$(wc -c < "$CASE/unchanged.md" 2>/dev/null)] bytes"
fi

base_case rendered-out-stale
ct_write_db
GH_SHIM_FAIL='^pr edit ' run_render --before-coordination --rendered-out "$CASE/stale.md"
if [ "$OUT" = "body=stale
merge-refused:body-stale" ] && ! [ -e "$CASE/stale.md" ]; then
    pass "--rendered-out: on body=stale nothing is written"
else
    fail "--rendered-out stale [$OUT], file present: $([ -e "$CASE/stale.md" ] && echo yes || echo no)"
fi

mkdir -p "$CASE/a-dir"
run_render --before-coordination --rendered-out "$CASE/a-dir"
if [ "$RC" -eq 64 ]; then
    pass "--rendered-out naming a directory is a usage error (64)"
else
    fail "--rendered-out a directory [$RC] [$OUT]"
fi
run_render --rendered-out "$CASE/no-before.md"
if [ "$RC" -eq 64 ] && ! [ -e "$CASE/no-before.md" ]; then
    pass "--rendered-out without --before-coordination is a usage error (64)"
else
    fail "--rendered-out without --before-coordination [$RC] [$OUT]"
fi

# --- visibility ------------------------------------------------------------------------------

ct_case private-node
CT_RECORD_REPOS="acme/repo-a,acme/repo-b" ct_record_setup github 10 \
    '[{"name":"pr-repo-a-core","kind":"pr","repo":"acme/repo-a","waits_on":[]},{"name":"pr-repo-b-cli","kind":"pr","repo":"acme/repo-b","waits_on":["pr-repo-a-core"]}]'
ct_record_node "$CT_CORE" "$CT_REPO" 11
ct_record_node pr-repo-b-cli acme/repo-b 5
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_pr acme/repo-b 5 "impl/t-pr-repo-b-cli"
CT_VIS_B=private
ct_write_db
run_render
if [ "$OUT" = "body=refused:execute:visibility" ] && [ "$RC" -eq 77 ] && [ "$(edits)" = 0 ] \
    && grep -q 'pr-repo-b-cli' "$CASE/stderr" && ! grep -q 'acme/repo-b' "$CASE/stderr"; then
    pass "a private node under a public home: body=refused:execute:visibility, exit 77, no edit, the repository unnamed"
else
    fail "a private node [$OUT/$RC], $(edits) edits: $(cat "$CASE/stderr")"
fi
CT_VIS_B=none
ct_write_db
rm -rf "$GH_CALL_LOG.d"
run_render
if [ "$OUT" = "body=stale" ] && [ "$(edits)" = 0 ]; then
    pass "a failed visibility read is body=stale"
else
    fail "a failed visibility read [$OUT]"
fi
CT_VIS_B=public
ct_write_db
rm -rf "$GH_CALL_LOG.d"
run_render
if [ "$OUT" = "body=posted" ]; then
    pass "a public node in another repository under a public home is indexed"
else
    fail "a public second repository [$OUT]: $(cat "$CASE/stderr")"
fi

# --- a merged coordination PR ------------------------------------------------------------------

base_case coord-merged
CT_COORD_STATE=MERGED
ct_write_db
gh shim-mark-merged "$CT_REPO" 11
run_render
if [ "$OUT" = "observed=$CT_CORE:$(merge_sha "$CT_REPO" 11)
body=unchanged" ] && [ "$(edits)" = 0 ] && [ -n "$(node_rec "$CT_CORE" | jq -r '.merged_head // ""')" ]; then
    pass "a MERGED coordination PR: merges observed and recorded, nothing posted"
else
    fail "a merged coordination PR [$OUT], $(edits) edits"
fi

# --- the wrong branch, and no record ------------------------------------------------------------

base_case wrong-branch
ct_write_db
OUT=$(cd "$CASE" && bash "$RENDER" --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch docs/other 2>"$CASE/stderr")
if [ "$OUT" = "body=stale" ] && [ "$(edits)" = 0 ]; then
    pass "a coordination PR on another branch than --coord-branch: body=stale, no edit"
else
    fail "the wrong branch [$OUT]"
fi

ct_case no-setup
ct_write_db
run_render
if [ "$OUT" = "body=stale" ] && [ "$RC" -eq 0 ] && [ "$(ct_calls | wc -l | tr -d ' ')" = 0 ]; then
    pass "a session with no run/setup: body=stale, no gh call"
else
    fail "no run/setup [$OUT/$RC]"
fi

run_render_usage() { OUT=$(bash "$RENDER" "$@" 2>/dev/null); RC=$?; }
run_render_usage --session "$S" --slug t --home-repo "$CT_REPO"
if [ "$RC" -eq 64 ] && [ -z "$OUT" ]; then pass "a missing --coord-branch is a usage error (64)"; else fail "usage [$RC] [$OUT]"; fi

# --- no output line names a path or a token ----------------------------------------------------

ALL=$(for d in "$CT_WORK"/cases/*; do [ -f "$d/stderr" ] && cat "$d/stderr"; done)
LINES=$(printf '%s\n' "$FIRST" "$SECOND" "$STALE_OUT" "$OUT")
if grep -q -e "$CT_WORK" -e token -e /tmp/ -e /var/ <<<"$LINES"; then
    fail "an output line names a path or a token"
else
    pass "no output line names a workspace path or a token"
fi
if grep -q -e ghp_ -e github_pat_ <<<"$ALL"; then fail "a diagnostic carries a token"; else pass "no diagnostic carries a token"; fi

echo
echo "coord-render: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
