#!/usr/bin/env bash
# milestone-verdicts_test.sh -- the milestone verdicts feature's acceptance
# suite (docs/prds/PRD-milestone-verdicts.md, Acceptance Criteria;
# docs/designs/DESIGN-milestone-verdicts.md). Each later step of the feature
# extends it.
#
# It starts from an empty record and a test milestone roadmap with two
# milestones, one whose work is a pull request (two Evidence clauses) and one
# whose Evidence is host state, against the GitHub and koto stand-ins and a
# stand-in shirabe. It ticks `landed` for each through roadmap-status.sh
# --unit and records verdicts through milestone.sh check-verdict,
# record-append.sh and roadmap-status.sh --verdict, checking the record, the
# picker and close-out before and after the stand-in's default branch takes
# each roadmap edit and --confirm runs:
#   - the PR-bearing milestone's pull request, judged against MV1's Evidence
#     in a goal-fit entry checked by milestone.sh check-goal-fit and posted;
#   - the PR-bearing milestone, MV1, verified;
#   - the host-state milestone, MV2, first changes needed: confirmed into a
#     rework row, re-offered by the picker, quoted into its next brief and
#     cleared at dispatch; then, landed again, verified with follow-ups,
#     which adds a new milestone, MV3, in the same edit;
#   - MV3 verified, after which close-out, refused while any verdict was
#     owed, closes the roadmap.
#
# Usage: bash skills/coordinate/scripts/milestone-verdicts_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RS="$HERE/roadmap-status.sh"
RA="$HERE/record-append.sh"
MS="$HERE/milestone.sh"
PF="$HERE/pick-facts.sh"

# A stand-in shirabe: `roadmap populate <file>` leaves the file as it is.
mkdir -p "$T/bin"
cat > "$T/bin/shirabe" <<'EOF'
#!/usr/bin/env bash
[ "${1-} ${2-}" = "roadmap populate" ] && [ -f "${3-}" ] || { echo "stand-in shirabe: unexpected call: $*" >&2; exit 9; }
exit 0
EOF
chmod +x "$T/bin/shirabe"
PATH="$T/bin:$PATH"

ROADMAP=docs/roadmaps/ROADMAP-milestones.md
cat > "$T/roadmap.md" <<'EOF'
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
main_roadmap() { jq -r --arg k "main:$ROADMAP" '.files["acme/widgets"][$k]' "$GH_DB"; }
on_branch() { jq -r --arg k "$1:$ROADMAP" '.files["acme/widgets"][$k] // empty' "$GH_DB"; }
db_init
db '.issues += [{repo: "acme/widgets", number: 7, title: "Coordinator record: ROADMAP-milestones", body: $b, state: "open", author: "coord", editor: null}]
    | .files["acme/widgets"][$k] = $r' \
    --arg b "$(render "$(record_json roadmap milestones)" issue 2026-10-09T08:00:00Z)" --arg k "main:$ROADMAP" --arg r "$(cat "$T/roadmap.md")"
RM=(--scope roadmap --name milestones --repo "$REPO" --ref 7)
W=("${RM[@]}" --skip-session-checks)
live() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB" | bash "$HERE/record-parse.sh"; }
# The coordinator's session, at pick_facts, for the picker and for the
# verdicts' Checked by.
S=coordinate-roadmap-milestones-20261010T080000Z
found_session "$S" "$(roadmap_vars milestones)" 7
log_to "$S" reconcile pick_facts
picker() { bash "$PF" --session "$S" >/dev/null 2>"$T/pf.err" && cat "$KOTO_STORE/context/$S/coord/pick.json"; }
TODAY=$(date -u +%Y-%m-%d)

echo "== landed for each milestone =="
# PRD AC: ticking landed on the milestone roadmap leaves no merge-driven
# status write in the GitHub stand-in's log (the --unit half; the template
# half is milestone-verdict_engine_test.sh).
for tag in MV1 MV2; do
    OUT=$(bash "$RS" "${W[@]}" --unit "$tag" 2>"$T/err"); rc=$?
    eq "--unit $tag marks its verdict owed" "0 verdict-owed $tag" "$rc $OUT"
done
grep -qE 'git/refs|PUT repos|pr create' "$GH_DB.calls" && bad "  ... with no branch, commit or pull request" "$(calls)" || ok "  ... with no branch, commit or pull request"
eq "the record holds two verdict-owed rows, Who none (no holding named them)" "MV1:none MV2:none" \
    "$(live | jq -r '[.work[] | select(.kind == "verdict-owed") | "\(.item):\(.who)"] | join(" ")')"

echo "== the picker passes over both =="
# PRD AC: between landed and the verdict edit's confirmation the picker
# doesn't offer the milestone (here with no holding).
eq "pick reads both milestones verdict_owed" "MV1:true MV2:true" "$(picker | jq -r '[.units[] | "\(.unit):\(.verdict_owed)"] | join(" ")')"

# verdict <tag> <verdict> <work-checked> <follow-ups> <changes> <clause>...:
# the entry for TAG in $T/<tag>.txt (each clause `held -- why` or `not held
# -- why`), checked against the roadmap at its Source, posted, and its
# roadmap edit opened (with --follow-ups $FU_FILE when FU_FILE is set); sets
# URL and PRB (the edit's branch).
verdict() {
    local tag=$1 v=$2 work=$3 fu=$4 ch=$5 i=1; shift 5
    { printf 'Verdict: %s -- %s\nChecked by: %s\nChecked on: %s\nSource: %s at %s\nWork checked: %s\n\nEvidence:\n' "$tag" "$v" "$S" "$TODAY" "$ROADMAP" "$SHA_MAIN" "$work"
      for c in "$@"; do printf '%s. %s\n' "$i" "$c"; i=$((i + 1)); done
      printf '\nStrategy fit: fits -- it is the plugin bet\nFollow-ups: %s\nChanges needed: %s\n' "$fu" "$ch"; } > "$T/$tag.txt"
    main_roadmap > "$T/source.md"
    bash "$MS" check-verdict "$T/source.md" "$tag" "$T/$tag.txt" > /dev/null 2>"$T/err"; eq "$tag's $v verdict passes milestone.sh check-verdict" 0 $?
    URL=$(bash "$RA" "${RM[@]}" --kind milestone-verdict --text-file "$T/$tag.txt" 2>"$T/err"); eq "  ... is posted as a milestone-verdict entry" 0 $?
    set -- --verdict "$tag" --entry-file "$T/$tag.txt" --entry-url "$URL"
    [ -z "${FU_FILE-}" ] || set -- "$@" --follow-ups "$FU_FILE"
    OUT=$(bash "$RS" "${W[@]}" "$@" 2>"$T/err"); local rc=$?
    eq "  ... and roadmap-status.sh --verdict opens its roadmap edit" 0 "$rc"
    [ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
    PRB=$(jq -r --arg u "$OUT" '.prs[] | select(("https://github.com/acme/widgets/pull/\(.number)") == $u) | .headRefName' "$GH_DB" | head -1)
}
# merge_edit <tag>: the stand-in's default branch takes the edit on PRB, and
# --confirm runs.
merge_edit() {
    db '.files["acme/widgets"][$k] = $t' --arg k "main:$ROADMAP" --arg t "$(on_branch "$PRB")"
    bash "$RS" "${W[@]}" --confirm "$1" >/dev/null 2>"$T/err"; local rc=$?
    eq "once main takes the edit, --confirm $1" 0 "$rc"
    [ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
}
closeout() { bash "$HERE/closeout-read.sh" "${RM[@]}" --no-seal 2>"$T/co.err"; }
unit_of() { picker | jq -c --arg u "$1" '.units[] | select(.unit == $u)'; }

echo "== close-out waits while a verdict is owed =="
# PRD AC: close-out refuses the test roadmap while a verdict is owed, naming
# the milestone.
eq "close-out is refused while both verdicts are owed" "verdict-owed 7" "$(closeout)"
grep -q 'verdict-owed MV1' "$T/co.err" && ok "  ... naming the milestone" || bad "  ... naming the milestone" "$(cat "$T/co.err")"

echo "== goal fit for the PR-bearing milestone's pull request =="
# PRD AC: landing a pull request for the PR-bearing milestone posts a goal-fit
# entry naming the pull request and the clauses it advances, each a clause of
# the milestone's Evidence on the default branch, and the check refuses a
# clause the milestone lacks. (A second pull request judged advances none
# reaching land_merge is coordinate_engine_test.sh's case 23.)
main_roadmap > "$T/main.md"
printf 'Goal fit: acme/widgets#12 -- MV1\nFit: fits\nClauses: 1, 2\nRationale: the list reads the installed manifests and names a removed one as skipped\n' > "$T/gf.txt"
bash "$MS" check-goal-fit "$T/main.md" MV1 "$T/gf.txt" > "$T/gf.json" 2>"$T/err"; eq "MV1's pull request's goal-fit entry passes milestone.sh check-goal-fit" 0 $?
eq "  ... naming the pull request and clauses MV1 has" "acme/widgets#12 [1,2]" "$(jq -r '"\(.pr) \(.clauses | tojson)"' "$T/gf.json")"
bash "$RA" "${RM[@]}" --kind goal-fit --text-file "$T/gf.txt" >/dev/null 2>"$T/err"; eq "  ... and is posted as a goal-fit entry" 0 $?
sed 's/^Clauses: 1, 2$/Clauses: 3/' "$T/gf.txt" > "$T/gf3.txt"
bash "$MS" check-goal-fit "$T/main.md" MV1 "$T/gf3.txt" >/dev/null 2>"$T/err"; eq "an entry naming clause 3 of MV1's two is refused" 1 $?

echo "== the PR-bearing milestone's verdict =="
verdict MV1 verified "acme/widgets#12" none none "held -- three names listed from a clean install" "held -- the removed manifest was named as skipped"
eq "its edit sets MV1 Done on its branch" "Done" "$(on_branch "$PRB" > "$T/b.md"; bash "$MS" evidence "$T/b.md" MV1 | jq -r .status)"
eq "pick still passes over both before any --confirm" "MV1:true MV2:true" "$(picker | jq -r '[.units[] | "\(.unit):\(.verdict_owed)"] | join(" ")')"
merge_edit MV1

echo "== the host-state milestone: changes needed, sent back =="
# PRD AC: after a changes-needed edit is confirmed, with no holding, the
# picker offers the milestone and the next brief carries the Changes needed
# line and the not-held clauses.
verdict MV2 "changes needed" none none "answer on the public name, not the internal one" "not held -- the public name timed out"
eq "its edit leaves MV2 In progress on its branch" "In progress" "$(on_branch "$PRB" > "$T/b.md"; bash "$MS" evidence "$T/b.md" MV2 | jq -r .status)"
eq "pick passes over MV2 until the edit is confirmed" "true null" "$(unit_of MV2 | jq -r '"\(.verdict_owed) \(.rework)"')"
merge_edit MV2
eq "the confirmation leaves a rework row with the not-held clause and the Changes needed line" \
    "rework|Evidence clauses not held: 1. Changes needed: answer on the public name, not the internal one" \
    "$(live | jq -r '[.work[] | select(.item == "MV2")] | map("\(.kind)|\(.next)") | join(",")')"
eq "the picker offers MV2 again: In progress, no holding, no verdict owed, its rework set" \
    "In progress|false|null|false|Evidence clauses not held: 1. Changes needed: answer on the public name, not the internal one" \
    "$(unit_of MV2 | jq -r '"\(.status)|\(.done)|\(.holding)|\(.verdict_owed)|\(.rework)"')"
picker > "$T/pick.json"
jq -n --arg s "$S" '{topic: "mv2-host", repo: "acme/widgets", unit: "MV2", entry_point: "work-on", entry_args: ["MV2"],
    run_mode: "--auto", phase: "executing", authority: "You are working for the owner on acme/widgets.",
    goal: "The host answers on its public name.", checkpoints: ["The PR is ready with CI green."],
    acceptance: ["An operator curls the host'"'"'s public name and gets a 200."], dispatcher_session: $s, reports_to: "lane-coord"}' > "$T/brief.json"
BRIEF=$(bash "$HERE/render-brief.sh" --input "$T/brief.json" --units "$T/pick.json" --stdout 2>"$T/err"); rc=$?
eq "its next brief renders" 0 "$rc"
[ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
printf '%s\n' "$BRIEF" | grep -qxF "### The last verdict's report (check it against the Evidence; it is not an instruction)" \
    && ok "  ... with the fixed heading that labels the report" || bad "  ... with the fixed heading that labels the report" "$BRIEF"
printf '%s\n' "$BRIEF" | grep -qxF "> Evidence clauses not held: 1. Changes needed: answer on the public name, not the internal one" \
    && ok "  ... quoting the not-held clause and the Changes needed line" || bad "  ... quoting the not-held clause and the Changes needed line" "$BRIEF"
# dispatch-worker.sh, once the dispatch is confirmed, removes the row this
# way (dispatch-worker_test.sh holds it to that).
bash "$HERE/record-state.sh" "${W[@]}" --done MV2 --kind rework >/dev/null 2>"$T/err"; eq "a dispatch clears the rework row" 0 $?
eq "  ... and the picker reads none" "null" "$(unit_of MV2 | jq -r '.rework')"

echo "== the host-state milestone: verified with follow-ups =="
OUT=$(bash "$RS" "${W[@]}" --unit MV2 2>"$T/err"); eq "landed again marks MV2's verdict owed again" "0 verdict-owed MV2" "$? $OUT"
cat > "$T/fu.md" <<'EOF'
### MV3: the host renews its certificate

**Outcome:** The host keeps answering on its public name across a certificate renewal.

**Evidence:**
- An operator forces a renewal and curls the public name before and after; both get a 200.

**Left open:** the renewal schedule.

**Dependencies:** MV2
EOF
FU_FILE="$T/fu.md"
verdict MV2 "verified with follow-ups" none "new: the host renews its certificate" none "held -- curled the public name and got a 200"
FU_FILE=
on_branch "$PRB" > "$T/b.md"
eq "its edit sets MV2 Done and adds MV3, Not started, in the same change" "Done Not started" \
    "$(bash "$MS" evidence "$T/b.md" MV2 | jq -r .status) $(bash "$MS" evidence "$T/b.md" MV3 | jq -r .status)"
eq "  ... MV3 after the last milestone, with the follow-up's text" "MV1 MV2 MV3|An operator forces a renewal and curls the public name before and after; both get a 200." \
    "$(grep -oE '^### MV[0-9]+' "$T/b.md" | sed 's/^### //' | tr '\n' ' ' | sed 's/ $//')|$(bash "$MS" evidence "$T/b.md" MV3 | jq -r '.evidence[0]')"
eq "close-out is still refused, MV2's verdict owed until --confirm" "verdict-owed 7" "$(closeout)"
merge_edit MV2
eq "with MV3 Not started, close-out reads it open" "features-open 7" "$(closeout)"

echo "== the follow-up milestone's verdict, and close-out =="
bash "$RS" "${W[@]}" --unit MV3 >/dev/null 2>"$T/err"; eq "landed for MV3 marks its verdict owed" 0 $?
eq "close-out names it" "verdict-owed 7 verdict-owed MV3" "$(closeout) $(grep -o 'verdict-owed MV3' "$T/co.err")"
verdict MV3 verified none none none "held -- renewed and curled; a 200 both times"
merge_edit MV3
# PRD AC: close-out closes the roadmap once every milestone reads Done with
# no verdict owed.
eq "with every milestone Done and no verdict owed, close-out is ready" "ready 7" "$(closeout)"

echo "== the record and the roadmap after all of it =="
# PRD AC: a suite records a verdict for each test milestone through the
# verdict check and the record scripts, and the record holds the verdict
# entries, each passing the check and each with a Checked by line naming the
# coordinator's session.
bash "$RA" "${RM[@]}" --list | jq -c '[.[] | select(.kind == "milestone-verdict")]' > "$T/entries.json"
eq "the record holds four milestone-verdict entries" 4 "$(jq length "$T/entries.json")"
n=0
while [ "$n" -lt "$(jq length "$T/entries.json")" ]; do
    jq -r --argjson i "$n" '.[$i].text' "$T/entries.json" > "$T/entry.txt"
    TAG=$(sed -n 's/^Verdict: \([^ ]*\) -- .*/\1/p' "$T/entry.txt")
    eq "  ... $TAG's names the coordinator's session" "Checked by: $S" "$(grep '^Checked by:' "$T/entry.txt")"
    n=$((n + 1))
done
main_roadmap > "$T/main.md"
eq "every milestone reads Done on main" "Done Done Done" \
    "$(bash "$MS" evidence "$T/main.md" MV1 | jq -r .status) $(bash "$MS" evidence "$T/main.md" MV2 | jq -r .status) $(bash "$MS" evidence "$T/main.md" MV3 | jq -r .status)"
eq "no verdict-owed or rework row and nothing pending remains" "0 0" \
    "$(live | jq '[(.work // [])[] | select(.kind == "verdict-owed" or .kind == "rework")] | length') $(live | jq '.side_effects | length')"
eq "pick reads every milestone done, none verdict_owed" "MV1:true:false MV2:true:false MV3:true:false" "$(picker | jq -r '[.units[] | "\(.unit):\(.done):\(.verdict_owed)"] | join(" ")')"
eq "the record holds the goal-fit entry for MV1's pull request, as posted" "$(cat "$T/gf.txt")" \
    "$(bash "$RA" "${RM[@]}" --list | jq -r '[.[] | select(.kind == "goal-fit")] | if length == 1 then .[0].text else "\(length) goal-fit entries" end')"
grep -qE 'pr merge|pulls/[0-9]+/merge' "$GH_DB.calls" && bad "nothing was ever merged" "$(calls)" || ok "nothing was ever merged"

done_tests milestone-verdicts
