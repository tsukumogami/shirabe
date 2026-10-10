#!/usr/bin/env bash
# milestone-verdict_engine_test.sh -- a milestone roadmap's verdict step, the
# shipped coordinate.md driven through real koto against the testdata/gh
# stand-in (docs/designs/DESIGN-milestone-verdicts.md, Decision 1; the PLAN's
# step 1).
#
# Proves, on a roadmap/v2 run (its roadmap in the working tree, so the run
# opens with ROADMAP_FORM milestone) and a feature-roadmap run beside it:
#   1. a `done` report with no pull request for the host-state milestone,
#      through classify_report, lands at roadmap_status, not back at wait
#      with the name-your-pull-request route; on the feature run the same
#      report goes back to wait;
#   2. `landed` for the PR-bearing milestone reaches roadmap_status, where
#      roadmap-status.sh --unit prints `verdict-owed` and leaves no branch,
#      commit or pull request in the GitHub stand-in's log, and
#      `verdict_owed` reaches milestone_verdict; `deferred` goes back to
#      wait and the next `landed` reaches the verdict step again;
#   3. a checked verdict, posted and opened with roadmap-status.sh
#      --verdict, then `recorded`, is confirmed by the record step and the
#      run reaches pick, where both milestones read verdict_owed; nothing was
#      merged;
#   4. on the feature run `landed` still opens the Done pull request;
#   5. the rendered merged_facts directive on the milestone run names the
#      milestone landing guidance, which carries no status-line pull request
#      instruction, while the feature run's names the feature guidance, which
#      does; merge_confirm, a check that passes straight through, is rendered
#      from the compiled template the same way.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/milestone-verdict_engine_test.sh
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

tick() { (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"); }
at() { tick "$@" | jq -r '.state // empty'; }
as_agent() { local s=$1; shift; (cd "$WD" && bash "$PS/$s" --session "$S" "$@" >"$T/w.out" 2>"$T/w.err"); }
pick_json() { (cd "$WD" && koto context get "$S" coord/pick.json 2>/dev/null); }
writes() { grep -cE 'POST repos/[^ ]*/git/refs|PUT repos|pr create' "$GH_DB.calls"; }
merges() { grep -cE 'pr merge|pulls/[0-9]+/merge' "$GH_DB.calls"; }
run_rows() { # run_rows <active worker>: the Run rows, the worker told the address
    jq -nc --arg w "$1" '[{key: "arguments", value: "--roadmap", set_by: "the human", set: "2026-10-07T10:00Z"},
    {key: "cap", value: "2", set_by: "the human", set: "2026-10-07T10:00Z"},
    {key: "coordinator", value: "lane-coord", set_by: "lane-coord", set: "2026-10-07T10:00Z"},
    {key: "told", value: $w, set_by: "lane-coord", set: "2026-10-07T10:00Z"}]'; }
work_row() { # work_row <unit> <worker>: the active holding's next step
    jq -nc --arg u "$1" --arg w "$2" '[{item: $u, kind: "holding", who: $w, next: "report when finished", wakes: "0", updated: "2026-10-07T10:00Z"}]'; }

# open_run <name> <roadmap-text> <record-json> <local: yes|no>: a fresh GitHub
# stand-in with the record (issue #7) and the roadmap on main, a working tree
# that holds the roadmap only when asked, and a run opened there and held at
# wait. Sets WD, S and RM.
open_run() {
    RM="docs/roadmaps/ROADMAP-$1.md"
    WD="$T/work-$1"
    mkdir -p "$WD/.niwa" "$WD/.claude"
    (cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
    echo '{}' > "$WD/.niwa/instance.json"
    jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$WD/.claude/settings.json"
    if [ "$4" = yes ]; then mkdir -p "$WD/docs/roadmaps"; printf '%s\n' "$2" > "$WD/$RM"; fi
    db_init
    db '.files["acme/widgets"]["main:" + $p] = $t' --arg p "$RM" --arg t "$2"
    db '.issues += [{repo: "acme/widgets", number: 7, title: $n, body: $b, state: "open", author: "coord", editor: null}]' \
        --arg n "Coordinator record: ROADMAP-$1" --arg b "$(render "$3" issue 2026-10-07T10:00:00Z)"
    printf '["%s"]' "$RM" > "$T/args.json"
    S=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
    [ -n "$S" ] || { bad "the $1 run opens" "$(cat "$T/open.err")"; return 1; }
    local a b c
    a=$(at); b=$(tick --with-data '{"reconciled":"reported"}'); c=$(at --with-data '{"choice":"hold"}')
    [ "$a $(printf '%s' "$b" | jq -r '.state // empty') $c" = "reconcile pick wait" ] \
        || { bad "the $1 run reaches wait" "states [$a $c]: $(printf '%s' "$b" | jq -c '{state, blocking_conditions, error}' | cut -c1-1500) $(cat "$T/tick.err")"; return 1; }
}
# landing_file <directive-and-details>: the landing guidance file a rendered
# directive names, resolved in the plugin.
landing_file() { printf '%s' "$1" | grep -oE 'references/landing-[a-z]+-roadmap\.md' | head -1; }

# ---- the milestone run ------------------------------------------------------
cat > "$T/mv.md" <<'EOF'
---
schema: roadmap/v2
status: Active
---

# ROADMAP: milestones

## Features

### MV1: the plugin list

**Outcome:** A maintainer lists the plugins they installed.

**Evidence:**
- A reviewer, from a clean install with three sample plugins, runs
  `widgets list` and sees exactly those three names.
- The same reviewer removes one manifest and sees it named as skipped.

**Left open:** the output layout.

**Dependencies:** None
**Status:** In progress

### MV2: the host serves

**Outcome:** The host answers on its public name.

**Evidence:**
- An operator curls the host's public name and gets a 200.

**Left open:** None

**Dependencies:** None
**Status:** In progress

## Progress

- 2026-10-01: MV1 and MV2 started
EOF
MV=$(cat "$T/mv.md")
H1=$(holding mv1-worker "$(jq -nc --arg h "$SHA_HEAD" '{unit: "MV1", dispatch_status: "dispatched", branch: "feat/list", verified_head: $h, pull_request: ""}')")
H2=$(holding mv2-worker '{"unit": "MV2", "dispatch_status": "dispatched", "branch": "", "verified_head": "", "pull_request": ""}')
REC=$(record_json roadmap milestones | jq -c --argjson a "$H1" --argjson b "$H2" --argjson r "$(run_rows mv2-worker)" --argjson w "$(work_row MV2 mv2-worker)" '.holdings = [$a, $b] | .run = $r | .work = $w')

echo "== the milestone run =="
if open_run milestones "$MV" "$REC" yes; then
    MS_S=$S MS_WD=$WD
    echo "== 1. a finished report with no pull request =="
    eq "the host-state milestone's report reaches classify_report" classify_report \
        "$(at --with-data '{"event":"report","unit":"mv2-worker","report":"MV2 is done: the host answers on its public name. Nothing to merge."}')"
    eq "done with no pull request goes to roadmap_status, its landed handling, not back to wait" roadmap_status \
        "$(at --with-data '{"classification":"done"}')"
    sleep 1
    reset_calls
    as_agent roadmap-status.sh --unit MV2; eq "roadmap-status.sh --unit MV2 marks its verdict owed" "0 verdict-owed MV2" "$? $(cat "$T/w.out")"
    eq "it reaches the verdict step" milestone_verdict "$(at --with-data '{"status":"verdict_owed","unit":"MV2"}')"
    eq "deferred goes back to wait" wait "$(at --with-data '{"verdict":"deferred"}')"

    echo "== 2. landed reaches the verdict step =="
    eq "landed goes to roadmap_status" roadmap_status "$(at --with-data '{"event":"landed","unit":"MV1"}')"
    sleep 1
    reset_calls
    as_agent roadmap-status.sh --unit MV1 --outcome "acme/widgets#12"; eq "roadmap-status.sh --unit MV1 prints verdict-owed" "0 verdict-owed MV1" "$? $(cat "$T/w.out")"
    eq "  ... with no branch, commit or pull request in the stand-in's log" 0 "$(writes)"
    eq "verdict_owed reaches milestone_verdict" milestone_verdict "$(at --with-data '{"status":"verdict_owed","unit":"MV1"}')"
    eq "deferred goes back to wait" wait "$(at --with-data '{"verdict":"deferred"}')"
    eq "the next landed tick comes back to roadmap_status" roadmap_status "$(at --with-data '{"event":"landed","unit":"MV1"}')"
    as_agent roadmap-status.sh --unit MV1; eq "  ... where --unit prints the same and writes nothing" "0 verdict-owed MV1 0" "$? $(cat "$T/w.out") $(writes)"
    eq "  ... and the verdict step is reached again" milestone_verdict "$(at --with-data '{"status":"verdict_owed","unit":"MV1"}')"

    echo "== 3. a checked verdict, recorded =="
    TODAY=$(date -u +%Y-%m-%d)
    printf 'Verdict: MV1 -- verified\nChecked by: %s\nChecked on: %s\nSource: %s at %s\nWork checked: acme/widgets#12\n\nEvidence:\n1. held -- three names listed from a clean install\n2. held -- the removed manifest was named as skipped\n\nStrategy fit: fits -- it is the plugin bet\nFollow-ups: none\nChanges needed: none\n' \
        "$S" "$TODAY" "$RM" "$SHA_MAIN" > "$T/verdict.txt"
    bash "$PS/milestone.sh" check-verdict "$T/mv.md" MV1 "$T/verdict.txt" --worker mv1-worker > /dev/null 2>"$T/err"; eq "the entry passes milestone.sh check-verdict" 0 $?
    sleep 1
    as_agent record-append.sh --kind milestone-verdict --text-file "$T/verdict.txt"; eq "the entry is posted" 0 $?
    URL=$(cat "$T/w.out")
    as_agent roadmap-status.sh --verdict MV1 --entry-file "$T/verdict.txt" --entry-url "$URL"; eq "roadmap-status.sh --verdict opens the roadmap edit" 0 $?
    PRN=$(jq -r '[.prs[] | select(.title == "docs(roadmap): record MV1, the plugin list, as done on its verdict")][0].number // empty' "$GH_DB")
    [ -n "$PRN" ] && ok "  ... titled for the milestone" || bad "  ... titled for the milestone" "$(jq -c '.prs' "$GH_DB")"
    eq "recorded: the record confirms the row and the run reaches pick" pick "$(at --with-data '{"verdict":"recorded","unit":"MV1"}')"
    eq "pick reads both milestones verdict_owed" "true true" "$(pick_json | jq -r '[.units[] | .verdict_owed | tostring] | join(" ")')"
    eq "nothing was merged" 0 "$(merges)"
    eq "it holds to wait" wait "$(at --with-data '{"choice":"hold"}')"
fi

# ---- the feature run --------------------------------------------------------
FR=$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Dependencies:** None\n**Status:** In progress\n\nThe first.\n\n### Feature 2: second\n**Dependencies:** None\n**Status:** In progress\n\nThe second.\n')
F1=$(holding feat-1 "$(jq -nc --arg h "$SHA_HEAD" '{unit: "Feature 1", dispatch_status: "dispatched", branch: "feat/first", verified_head: $h, pull_request: ""}')")
F2=$(holding feat-2 '{"unit": "Feature 2", "dispatch_status": "dispatched", "branch": "", "verified_head": "", "pull_request": ""}')
FREC=$(record_json roadmap features | jq -c --argjson a "$F1" --argjson b "$F2" --argjson r "$(run_rows feat-2)" --argjson w "$(work_row "Feature 2" feat-2)" '.holdings = [$a, $b] | .run = $r | .work = $w')

echo "== the feature run =="
if open_run features "$FR" "$FREC" no; then
    FE_S=$S FE_WD=$WD
    eq "a report naming no pull request reaches classify_report" classify_report \
        "$(at --with-data '{"event":"report","unit":"feat-2","report":"all done"}')"
    eq "done with no pull request goes back to wait, to ask for one" wait "$(at --with-data '{"classification":"done"}')"
    echo "== 4. landed still opens the Done pull request =="
    eq "landed goes to roadmap_status" roadmap_status "$(at --with-data '{"event":"landed","unit":"Feature 1"}')"
    sleep 1
    as_agent roadmap-status.sh --unit "Feature 1" --outcome "acme/widgets#12, the first"; eq "roadmap-status.sh opens the Done pull request" 0 $?
    [ -n "$(jq -r '[.prs[] | select(.title == "docs(roadmap): record Feature 1, first, as done")][0].number // empty' "$GH_DB")" ] \
        && ok "  ... titled for the feature" || bad "  ... titled for the feature" "$(jq -c '.prs' "$GH_DB")"
    eq "record confirms the row and the run reaches pick" pick "$(at --with-data '{"status":"opened","unit":"Feature 1"}')"
    eq "it holds to wait" wait "$(at --with-data '{"choice":"hold"}')"
fi

# ---- 5. the merge directives -----------------------------------------------
echo "== 5. the merge directives =="
# merged_facts, held by a failed read so its directive is what the run shows.
# render_merged <session> <wd>: the directive and details koto renders there.
render_merged() {
    S=$1 WD=$2
    db '.fail = [{match: "issue view", rc: 1, stderr: "gh: Server Error (HTTP 502)"}]'
    tick --with-data '{"event":"merged","unit":"mv1-worker"}' > /dev/null
    (cd "$WD" && koto status "$S" 2>/dev/null) | jq -r '"\(.current_state)\n\(.directive // "")\n\(.details // "")"'
    db '.fail = []'
}
if [ -n "${MS_S-}" ]; then
    OUT=$(render_merged "$MS_S" "$MS_WD")
    eq "the milestone run holds at merged_facts" merged_facts "$(printf '%s\n' "$OUT" | head -1)"
    F=$(landing_file "$OUT")
    eq "  ... its rendered directive names the milestone guidance" references/landing-milestone-roadmap.md "$F"
    printf '%s\n' "$OUT" | grep -qi 'status line' && bad "  ... and carries no status-line instruction itself" || ok "  ... and carries no status-line instruction itself"
    grep -qi 'status line' "$PR/skills/coordinate/$F" && bad "  ... nor does the guidance it names" "$(grep -i 'status line' "$PR/skills/coordinate/$F")" \
        || ok "  ... nor does the guidance it names"
fi
if [ -n "${FE_S-}" ]; then
    OUT=$(render_merged "$FE_S" "$FE_WD")
    eq "the feature run holds at merged_facts" merged_facts "$(printf '%s\n' "$OUT" | head -1)"
    F=$(landing_file "$OUT")
    eq "  ... its rendered directive names the feature guidance" references/landing-feature-roadmap.md "$F"
    grep -q "sets the feature's status line" "$PR/skills/coordinate/$F" && ok "  ... which still says to dispatch the status-line pull request" \
        || bad "  ... which still says to dispatch the status-line pull request"
fi
# merge_confirm passes straight through on a confirmed merge; its text is the
# compiled template's with ROADMAP_FORM substituted, as koto renders it.
J=$(koto template compile "$PR/skills/coordinate/koto-templates/coordinate.md" 2>/dev/null)
TXT=$(jq -r '.states.merge_confirm | "\(.directive)\n\(.details // "")"' "$J")
for form in milestone feature; do
    F=$(landing_file "$(printf '%s' "$TXT" | sed "s/{{ROADMAP_FORM}}/$form/g")")
    eq "merge_confirm rendered for a $form roadmap names its guidance" "references/landing-$form-roadmap.md" "$F"
done
printf '%s' "$TXT" | grep -qi 'status line' && bad "merge_confirm carries no status-line instruction itself" || ok "merge_confirm carries no status-line instruction itself"

done_tests milestone-verdict-engine
