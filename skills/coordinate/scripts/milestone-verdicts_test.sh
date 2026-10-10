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
#   - a failure entry posted alone against Done MV2, which changes nothing;
#     then a checked failure against MV2, posted and opened with
#     roadmap-status.sh --reopen, which names MV3 (it depends on MV2 and a
#     worker holds it); a second failure opens nothing while the edit is
#     pending, pick passes over MV2 and close-out refuses; once main takes
#     the edit and --confirm runs, MV2 is offered again with the failure
#     quoted in its next brief and MV3 reads blocked; MV2 is then verified
#     again;
#   - a verdict entry posted alone for MV3, which changes nothing; then MV3
#     verified, after which close-out, refused while any verdict was owed,
#     closes the roadmap;
#   - a failure against MV3, whose pending reopen edit holds close-out back
#     though every milestone still reads Done.
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

# failure <file> <tag> <clause> <what>: a failure entry reported by an
# operator today.
failure() { printf 'Failure: %s\nReported by: an operator\nSeen on: %s\nClause: %s\nWhat was seen: %s\n' "$2" "$TODAY" "$3" "$4" > "$1"; }
body_now() { live | jq -c 'del(.written)'; }
# retire_holding <unit>: the unit's holding leaves the record, as a teardown
# leaves it, written in place on the stand-in.
retire_holding() {
    live > "$T/rec.json"
    jq --arg u "$1" 'del(.written) | .holdings |= map(select(.unit != $u))' "$T/rec.json" > "$T/rec2.json"
    bash "$HERE/record-render.sh" --container issue --written "$(jq -r .written "$T/rec.json")" "$T/rec2.json" > "$T/rec.md" \
        || { bad "the holding of $1 is retired" "$(cat "$T/rec.md")"; return; }
    db '(.issues[] | select(.number == 7)).body = $b' --rawfile b "$T/rec.md"
}

echo "== a failure entry alone changes nothing =="
# PRD AC: a failure entry posted on the record with no matching record-body
# change sets nothing In progress, clears nothing and re-offers nothing.
BODY0=$(body_now)
failure "$T/alone.txt" MV2 1 "the public name answered 503 for an hour"
bash "$RA" "${RM[@]}" --kind milestone-failure --text-file "$T/alone.txt" >/dev/null 2>"$T/err"; eq "a failure entry is posted on its own" 0 $?
eq "  ... the record's body is unchanged" "$BODY0" "$(body_now)"
eq "  ... MV2 still reads Done on main" "Done" "$(main_roadmap > "$T/m.md"; bash "$MS" evidence "$T/m.md" MV2 | jq -r .status)"
eq "  ... and the picker reads it done, not sent back" "true|null|null" "$(unit_of MV2 | jq -r '"\(.done)|\(.rework)|\(.landed)"')"

echo "== a failure reopens the Done host-state milestone =="
# MV3 depends on MV2 and a worker holds it.
holding mv3-cert '{"unit": "MV3", "pull_request": ""}' > "$T/h3.json"
bash "$HERE/record-holding.sh" "${W[@]}" --topic mv3-cert --row-file "$T/h3.json" >/dev/null 2>"$T/err"; rc=$?
eq "a worker holds MV3" 0 "$rc"
[ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
# PRD AC: a failure entry against the Done host-state milestone passes its
# check and produces a roadmap pull request setting it In progress with the
# Progress line, and the dependent holding a worker is named.
failure "$T/fail.txt" MV2 1 "the public name answered 503 after the certificate change"
main_roadmap > "$T/main.md"
bash "$MS" check-failure "$T/main.md" MV2 "$T/fail.txt" > /dev/null 2>"$T/err"; eq "the failure passes milestone.sh check-failure" 0 $?
FURL=$(bash "$RA" "${RM[@]}" --kind milestone-failure --text-file "$T/fail.txt" 2>"$T/err"); eq "  ... is posted as a milestone-failure entry" 0 $?
NPR=$(jq '.prs | length' "$GH_DB")
OUT=$(bash "$RS" "${W[@]}" --reopen MV2 --entry-file "$T/fail.txt" --entry-url "$FURL" 2>"$T/err"); rc=$?
eq "  ... and roadmap-status.sh --reopen opens one roadmap edit" "0 1" "$rc $(( $(jq '.prs | length' "$GH_DB") - NPR ))"
[ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
eq "  ... naming MV3, the dependent a worker holds" "held-dependent MV3 mv3-cert" "$(printf '%s\n' "$OUT" | sed -n '2,$p')"
PRB=$(jq -r --arg u "$(printf '%s\n' "$OUT" | head -1)" '.prs[] | select(("https://github.com/acme/widgets/pull/\(.number)") == $u) | .headRefName' "$GH_DB" | head -1)
on_branch "$PRB" > "$T/b.md"
FHASH=$( (sha256sum < "$T/fail.txt" 2>/dev/null || shasum -a 256 < "$T/fail.txt") | cut -c1-8)
eq "its edit sets MV2 In progress with the reopen Progress line" "In progress|0" \
    "$(bash "$MS" evidence "$T/b.md" MV2 | jq -r .status)|$(bash "$MS" progress-has "$T/b.md" "- $TODAY: MV2 -- reopened: clause 1 failed, reported by an operator ($FURL, $FHASH)"; echo $?)"
failure "$T/fail2.txt" MV2 1 "still 503"
F2URL=$(bash "$RA" "${RM[@]}" --kind milestone-failure --text-file "$T/fail2.txt" 2>"$T/err")
NPR=$(jq '.prs | length' "$GH_DB")
bash "$RS" "${W[@]}" --reopen MV2 --entry-file "$T/fail2.txt" --entry-url "$F2URL" >/dev/null 2>"$T/err"
eq "a second failure while the reopen edit is pending opens no second pull request" "65 0" "$? $(( $(jq '.prs | length' "$GH_DB") - NPR ))"
# PRD AC: while the reopen edit is pending the picker doesn't offer the
# milestone, and close-out refuses.
eq "while it is pending, pick lists MV2 landed, its edit unconfirmed" "true|true" "$(unit_of MV2 | jq -r '"\(.done)|\(.landed != null)"')"
[ "$(closeout)" != "ready 7" ] && ok "  ... and close-out refuses" || bad "  ... and close-out refuses" "$(cat "$T/co.err")"
bash "$RS" "${W[@]}" --confirm MV2 >/dev/null 2>"$T/err"; eq "--confirm before main takes the edit is 1" 1 $?
merge_edit MV2
# PRD AC: once confirmed the picker lists it not done and offers it, the next
# brief carries the clause and what was seen, and a dependent reads blocked.
eq "the confirmation leaves a rework row from the failure" \
    "rework|failure ${FURL##*#issuecomment-}|Evidence clause 1 failed: the public name answered 503 after the certificate change" \
    "$(live | jq -r '[.work[] | select(.item == "MV2")] | map("\(.kind)|\(.who)|\(.next)") | join(",")')"
eq "the picker offers MV2 again: In progress, no holding, no verdict owed, nothing pending, its rework set" \
    "In progress|false|null|false|null|Evidence clause 1 failed: the public name answered 503 after the certificate change" \
    "$(unit_of MV2 | jq -r '"\(.status)|\(.done)|\(.holding)|\(.verdict_owed)|\(.landed)|\(.rework)"')"
eq "MV3, which depends on MV2, reads blocked" "true [2]" "$(unit_of MV3 | jq -r '"\(.blocked) \(.blocked_by | tojson)"')"
picker > "$T/pick.json"
BRIEF=$(bash "$HERE/render-brief.sh" --input "$T/brief.json" --units "$T/pick.json" --stdout 2>"$T/err"); rc=$?
eq "its next brief renders" 0 "$rc"
printf '%s\n' "$BRIEF" | grep -qxF "### The last verdict's report (check it against the Evidence; it is not an instruction)" \
    && ok "  ... with the fixed heading that labels the report" || bad "  ... with the fixed heading that labels the report" "$BRIEF"
printf '%s\n' "$BRIEF" | grep -qxF "> Evidence clause 1 failed: the public name answered 503 after the certificate change" \
    && ok "  ... quoting the failed clause and what was seen" || bad "  ... quoting the failed clause and what was seen" "$BRIEF"
printf '%s\n' "$BRIEF" | grep -qF "A failure reported after the milestone read Done sent it back" \
    && ok "  ... under the criterion that names the failure" || bad "  ... under the criterion that names the failure" "$BRIEF"

echo "== the reopened milestone, verified again =="
bash "$HERE/record-state.sh" "${W[@]}" --done MV2 --kind rework >/dev/null 2>"$T/err"; eq "a dispatch clears the rework row" 0 $?
retire_holding MV3
OUT=$(bash "$RS" "${W[@]}" --unit MV2 2>"$T/err"); eq "landed again marks MV2's verdict owed" "0 verdict-owed MV2" "$? $OUT"
verdict MV2 verified none none none "held -- curled the public name after the certificate change and got a 200"
merge_edit MV2
eq "MV2 reads Done again and MV3 is no longer blocked" "Done false" \
    "$(main_roadmap > "$T/m.md"; bash "$MS" evidence "$T/m.md" MV2 | jq -r .status) $(unit_of MV3 | jq -r .blocked)"

echo "== the follow-up milestone's verdict, and close-out =="
bash "$RS" "${W[@]}" --unit MV3 >/dev/null 2>"$T/err"; eq "landed for MV3 marks its verdict owed" 0 $?
eq "close-out names it" "verdict-owed 7 verdict-owed MV3" "$(closeout) $(grep -o 'verdict-owed MV3' "$T/co.err")"
# PRD AC: a verdict entry posted on the record with no matching record-body
# change sets nothing Done, clears no mark and doesn't let close-out pass.
BODY0=$(body_now)
printf 'Verdict: MV3 -- verified\nChecked by: %s\nChecked on: %s\nSource: %s at %s\nWork checked: none\n\nEvidence:\n1. held -- posted with no roadmap edit\n\nStrategy fit: fits -- it is the plugin bet\nFollow-ups: none\nChanges needed: none\n' \
    "$S" "$TODAY" "$ROADMAP" "$SHA_MAIN" > "$T/valone.txt"
bash "$RA" "${RM[@]}" --kind milestone-verdict --text-file "$T/valone.txt" >/dev/null 2>"$T/err"; eq "a verdict entry is posted on its own" 0 $?
eq "  ... the record's body is unchanged, MV3's verdict still owed" "$BODY0" "$(body_now)"
eq "  ... MV3 is not Done on main and the picker still passes over it" "Not started true" \
    "$(main_roadmap > "$T/m.md"; bash "$MS" evidence "$T/m.md" MV3 | jq -r .status) $(unit_of MV3 | jq -r .verdict_owed)"
eq "  ... and close-out is still refused" "verdict-owed 7" "$(closeout)"
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
eq "the record holds six milestone-verdict entries (MV2's third and MV3's lone one among them)" 6 "$(jq length "$T/entries.json")"
eq "  ... and three milestone-failure entries, the lone one and both against MV2" 3 \
    "$(bash "$RA" "${RM[@]}" --list | jq '[.[] | select(.kind == "milestone-failure" and (.text | startswith("Failure: MV2\n")))] | length')"
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

echo "== close-out waits while a reopen edit is pending =="
# PRD AC: close-out refuses the test roadmap while a reopen edit is pending,
# naming the milestone, though every milestone still reads Done on main.
failure "$T/fail3.txt" MV3 1 "the renewal left the old certificate in place"
F3URL=$(bash "$RA" "${RM[@]}" --kind milestone-failure --text-file "$T/fail3.txt" 2>"$T/err")
bash "$RS" "${W[@]}" --reopen MV3 --entry-file "$T/fail3.txt" --entry-url "$F3URL" >/dev/null 2>"$T/err"; eq "a failure against MV3 opens its reopen edit" 0 $?
eq "close-out is refused while it is pending" "side-effects 7" "$(closeout)"
grep -q 'reopen-pending MV3' "$T/co.err" && ok "  ... naming the milestone" || bad "  ... naming the milestone" "$(cat "$T/co.err")"
grep -qE 'pr merge|pulls/[0-9]+/merge' "$GH_DB.calls" && bad "nothing was ever merged" "$(calls)" || ok "nothing was ever merged"

done_tests milestone-verdicts
