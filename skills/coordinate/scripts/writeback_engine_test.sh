#!/usr/bin/env bash
# writeback_engine_test.sh -- a landed feature's Status and Outcome written
# back to the roadmap, the shipped coordinate.md driven through real koto
# against the testdata/gh stand-in
# (docs/designs/current/DESIGN-coordinate-record-container.md, Decision 4;
# tsukumogami/shirabe#497).
#
# Proves, one line per case:
#   1. a run whose Feature 1 merged (its holding's merge confirmed, waiting
#      for teardown) sends `landed`: roadmap_status, where roadmap-status.sh
#      opens the roadmap pull request with Feature 1's Status, Outcome and
#      Needs changed and nothing else, then record confirms its row and the
#      run reaches pick;
#   2. that pick doesn't offer Feature 1: it is landed, no brief renders for
#      it, and Feature 2, which depends on it, is still blocked;
#   3. once the roadmap on the default branch reads Feature 1 Done,
#      roadmap-status.sh --confirm clears the row, and the next pick sees
#      Feature 1 Done and Feature 2 unblocked;
#   4. the skill never merged the roadmap pull request.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/writeback_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
ORIG_PATH=$PATH
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P)
unset KOTO_STORE KOTO_COMPILED_HASH
mkdir -p "$T/bin"
ln -sf "$HERE/testdata/gh" "$T/bin/gh"
ln -sf "$HERE/testdata/board/stand-in-shirabe" "$T/bin/shirabe"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
WD="$T/work"
mkdir -p "$WD/.niwa" "$WD/.claude"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
echo '{}' > "$WD/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$WD/.claude/settings.json"

tick() { (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"); }
at() { tick "$@" | jq -r '.state // empty'; }
as_agent() { local s=$1; shift; (cd "$WD" && bash "$PS/$s" --session "$S" "$@" >"$T/w.out" 2>"$T/w.err"); }
pick_json() { (cd "$WD" && koto context get "$S" coord/pick.json 2>/dev/null); }
RM=docs/roadmaps/ROADMAP-writeback.md
roadmap_text() { # roadmap_text <feature 1 status>
    printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Needs:** `needs-design` -- the shape\n**Dependencies:** None\n**Status:** %s\n\nThe first.\n\n### Feature 2: second\n**Dependencies:** Feature 1\n**Status:** Not started\n\nThe second.\n' "$1"
}

db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-writeback.md"] = $t' --arg t "$(roadmap_text "In progress")"
# Feature 1's worker: its pull request merged and the merge confirmed (a
# Verified head, the Pull request cell cleared), waiting for its teardown.
F1=$(holding feat-1 "$(jq -nc --arg h "$SHA_HEAD" '{unit: "Feature 1", dispatch_status: "dispatched", branch: "feat/first", verified_head: $h, pull_request: ""}')")
RECORD=$(record_json roadmap writeback | jq -c --argjson a "$F1" '
    .holdings = [$a]
    | .run = [{key: "arguments", value: "--roadmap docs/roadmaps/ROADMAP-writeback.md", set_by: "the human", set: "2026-10-07T10:00Z"},
              {key: "cap", value: "2", set_by: "the human", set: "2026-10-07T10:00Z"},
              {key: "coordinator", value: "lane-coord", set_by: "lane-coord", set: "2026-10-07T10:00Z"}]')
db '.issues += [{repo: "acme/widgets", number: 7, title: "Coordinator record: ROADMAP-writeback", body: $b, state: "open", author: "coord", editor: null}]' \
    --arg b "$(render "$RECORD" issue 2026-10-07T10:00:00Z)"

printf '["%s"]' "$RM" > "$T/args.json"
S=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
[ -n "$S" ] || { bad "the run opens" "$(cat "$T/open.err")"; done_tests writeback-engine; exit 1; }
eq "the run reaches reconcile" reconcile "$(at)"
eq "and pick" pick "$(at --with-data '{"reconciled":"reported"}')"
eq "it holds to wait" wait "$(at --with-data '{"choice":"hold"}')"

echo "== 1. landed: the roadmap pull request =="
eq "landed goes to roadmap_status" roadmap_status "$(at --with-data '{"event":"landed","unit":"Feature 1"}')"
eq "opened without the script holds there, refused for no unit" roadmap_status "$(at --with-data '{"status":"opened"}')"
# Written: times are to the second, and a write in the second the step
# became due doesn't count for it.
sleep 1
as_agent roadmap-status.sh --unit "Feature 1" --outcome "acme/widgets#12, the first"; eq "roadmap-status.sh (agent-run) opens the pull request" 0 $?
PRN=$(jq -r '[.prs[] | select(.title == "docs(roadmap): record Feature 1, first, as done")][0].number // empty' "$GH_DB")
[ -n "$PRN" ] && ok "  ... titled for the feature" || bad "  ... titled for the feature" "$(jq -c '.prs' "$GH_DB")"
BR=$(jq -r --argjson n "${PRN:-0}" '.prs[] | select(.number == $n) | .headRefName' "$GH_DB")
diff <(roadmap_text "In progress") <(jq -r --arg b "$BR" '.files["acme/widgets"][$b + ":docs/roadmaps/ROADMAP-writeback.md"]' "$GH_DB") > "$T/d"
eq "  ... changing Feature 1's Needs, Status and Outcome lines and nothing else" \
    "$(printf '%s\n' '10d9' '< **Needs:** `needs-design` -- the shape' '12c11,12' '< **Status:** In progress' '---' '> **Status:** Done' '> **Outcome:** acme/widgets#12, the first')" "$(cat "$T/d")"
eq "record confirms the row and the run reaches pick" pick "$(at --with-data '{"status":"opened","unit":"Feature 1"}')"

echo "== 2. pick doesn't offer the landed feature =="
eq "Feature 1 is landed, with its roadmap pull request" "[#$PRN](https://github.com/acme/widgets/pull/$PRN)" \
    "$(pick_json | jq -r '.units[] | select(.unit == "Feature 1") | .landed')"
eq "Feature 2 is still blocked on it" "true" "$(pick_json | jq -r '.units[] | select(.unit == "Feature 2") | .blocked')"
. "$PS/dispatch-common.sh"
pick_json > "$T/pick.json"
dc_unit_forms "$T/pick.json" | grep -q '^Feature 1' && bad "no brief renders for Feature 1" "$(dc_unit_forms "$T/pick.json")" || ok "no brief renders for Feature 1"

echo "== 3. once the roadmap reads Done =="
eq "it holds to wait" wait "$(at --with-data '{"choice":"hold"}')"
as_agent roadmap-status.sh --confirm "Feature 1"; eq "--confirm before the merge is 1" 1 $?
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-writeback.md"] = $t' --arg t "$(jq -r --arg b "$BR" '.files["acme/widgets"][$b + ":docs/roadmaps/ROADMAP-writeback.md"]' "$GH_DB")"
as_agent roadmap-status.sh --confirm "Feature 1"; eq "--confirm once main reads Done clears the row" 0 $?
eq "the next pick is reached" pick "$(tick --with-data '{"event":"decision"}' >/dev/null; at --with-data '{"change":"none"}')"
eq "Feature 1 is Done and no longer landed" "true null" "$(pick_json | jq -r '.units[] | select(.unit == "Feature 1") | "\(.done) \(.landed)"')"
eq "Feature 2 is unblocked" "false" "$(pick_json | jq -r '.units[] | select(.unit == "Feature 2") | .blocked')"

echo "== 4. never merged by the skill =="
grep -qE 'pr merge|pulls/[0-9]+/merge' "$GH_DB.calls" && bad "the roadmap pull request was never merged by the skill" "$(grep -E 'merge' "$GH_DB.calls")" \
    || ok "the roadmap pull request was never merged by the skill"

done_tests writeback-engine
