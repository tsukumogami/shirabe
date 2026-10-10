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
# --unit, records a verified verdict for each through milestone.sh
# check-verdict, record-append.sh and roadmap-status.sh --verdict, and checks
# the record and the picker before and after the stand-in's default branch
# takes each roadmap edit and --confirm runs.
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

# verdict <tag> <work-checked> <clause>...: the entry for TAG in $T/<tag>.txt,
# checked against the roadmap at its Source, posted, and its roadmap edit
# opened; sets URL and PRB (the edit's branch).
verdict() {
    local tag=$1 work=$2 i=1; shift 2
    { printf 'Verdict: %s -- verified\nChecked by: %s\nChecked on: %s\nSource: %s at %s\nWork checked: %s\n\nEvidence:\n' "$tag" "$S" "$TODAY" "$ROADMAP" "$SHA_MAIN" "$work"
      for c in "$@"; do printf '%s. held -- %s\n' "$i" "$c"; i=$((i + 1)); done
      printf '\nStrategy fit: fits -- it is the plugin bet\nFollow-ups: none\nChanges needed: none\n'; } > "$T/$tag.txt"
    bash "$MS" check-verdict "$T/roadmap.md" "$tag" "$T/$tag.txt" > /dev/null 2>"$T/err"; eq "$tag's verdict passes milestone.sh check-verdict" 0 $?
    URL=$(bash "$RA" "${RM[@]}" --kind milestone-verdict --text-file "$T/$tag.txt" 2>"$T/err"); eq "  ... is posted as a milestone-verdict entry" 0 $?
    OUT=$(bash "$RS" "${W[@]}" --verdict "$tag" --entry-file "$T/$tag.txt" --entry-url "$URL" 2>"$T/err"); local rc=$?
    eq "  ... and roadmap-status.sh --verdict opens its roadmap edit" 0 "$rc"
    [ $rc = 0 ] || printf '     %s\n' "$(cat "$T/err")"
    PRB=$(jq -r --arg u "$OUT" '.prs[] | select(.url == $u or ("https://github.com/acme/widgets/pull/\(.number)" == $u)) | .headRefName' "$GH_DB" | head -1)
}

echo "== the PR-bearing milestone's verdict =="
verdict MV1 "acme/widgets#12" "three names listed from a clean install" "the removed manifest was named as skipped"
eq "its edit sets MV1 Done on its branch" "Done" "$(on_branch "$PRB" > "$T/b.md"; bash "$MS" evidence "$T/b.md" MV1 | jq -r .status)"
eq "pick still passes over both before any --confirm" "MV1:true MV2:true" "$(picker | jq -r '[.units[] | "\(.unit):\(.verdict_owed)"] | join(" ")')"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$ROADMAP" --arg t "$(on_branch "$PRB")"
bash "$RS" "${W[@]}" --confirm MV1 >/dev/null 2>"$T/err"; eq "once main takes the edit, --confirm MV1" 0 $?

echo "== the host-state milestone's verdict =="
verdict MV2 none "curled the public name and got a 200"
db '.files["acme/widgets"][$k] = $t' --arg k "main:$ROADMAP" --arg t "$(on_branch "$PRB")"
bash "$RS" "${W[@]}" --confirm MV2 >/dev/null 2>"$T/err"; eq "once main takes the edit, --confirm MV2" 0 $?

echo "== the record and the roadmap after both =="
# PRD AC: a suite records a verdict for each test milestone through the
# verdict check and the record scripts, and the record holds two verdict
# entries, each passing the check and each with a Checked by line naming the
# coordinator's session.
bash "$RA" "${RM[@]}" --list | jq -c '[.[] | select(.kind == "milestone-verdict")]' > "$T/entries.json"
eq "the record holds two milestone-verdict entries" 2 "$(jq length "$T/entries.json")"
n=0
while [ "$n" -lt "$(jq length "$T/entries.json")" ]; do
    jq -r --argjson i "$n" '.[$i].text' "$T/entries.json" > "$T/entry.txt"
    TAG=$(sed -n 's/^Verdict: \([^ ]*\) -- .*/\1/p' "$T/entry.txt")
    bash "$MS" check-verdict "$T/roadmap.md" "$TAG" "$T/entry.txt" > /dev/null 2>"$T/err"; eq "  ... $TAG's passes the check" 0 $?
    eq "  ... and its Checked by names the coordinator's session" "Checked by: $S" "$(grep '^Checked by:' "$T/entry.txt")"
    n=$((n + 1))
done
main_roadmap > "$T/main.md"
eq "both milestones read Done on main" "Done Done" "$(bash "$MS" evidence "$T/main.md" MV1 | jq -r .status) $(bash "$MS" evidence "$T/main.md" MV2 | jq -r .status)"
eq "no verdict-owed row and nothing pending remains" "0 0" \
    "$(live | jq '[(.work // [])[] | select(.kind == "verdict-owed")] | length') $(live | jq '.side_effects | length')"
eq "pick reads both done, neither verdict_owed" "MV1:true:false MV2:true:false" "$(picker | jq -r '[.units[] | "\(.unit):\(.done):\(.verdict_owed)"] | join(" ")')"
grep -qE 'pr merge|pulls/[0-9]+/merge' "$GH_DB.calls" && bad "nothing was ever merged" "$(calls)" || ok "nothing was ever merged"

done_tests milestone-verdicts
