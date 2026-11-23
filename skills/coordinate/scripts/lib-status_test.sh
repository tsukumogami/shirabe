#!/usr/bin/env bash
# lib-status_test.sh -- state-common.sh lib_status, the coordinate scripts'
# reading of the milestone status table
# (skills/roadmap/references/milestone-statuses.json), and the picker and the
# close-out read on it.
#
# Covers: the table's properties for every status word, the same values
# crates/shirabe-validate/src/statuses.rs's tests assert (satisfies, closes,
# takes_work, and renders' struck and class), on v1 to v3 and on roadmap/v4,
# with the schema line choosing the family. The Rust reader matches a whole
# cell ignoring case; this one matches a Status that opens the word, case
# kept, as the picker always has, so `Done -- shipped in #12` is Done here
# and `done` is open. On a roadmap/v4 roadmap pick-facts.sh offers a
# milestone whose dependency is Completed, gives the Completed one
# takes_work false and doesn't offer it, and holds a dependent of a Dropped
# one; the roadmap isn't scope-complete while a milestone is Completed, and
# the close-out read holds it open, naming the milestone. On roadmap/v3,
# Shipped and Closed both satisfy their dependents and neither is offered,
# and a dependent of a Dropped milestone is held. With the table removed,
# unparseable, of another version or of the wrong shape, pick-facts.sh and
# closeout-read.sh exit 2 naming the file, print nothing on stdout and make
# no GitHub call, and lib_roadmap_features (roadmap-status.sh's and
# alignment-sources.sh's reader) fails naming it too.
#
# Usage: bash skills/coordinate/scripts/lib-status_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
PF="$HERE/pick-facts.sh"
CR="$HERE/closeout-read.sh"

# prop <schema> <status> <property>: lib_status_prop, in a subshell.
prop() { (PROG=lib-status; . "$HERE/state-common.sh"; lib_status_prop "$1" "$2" "$3"); }
# props <schema> <status>: `satisfies closes takes_work struck class`.
props() {
    printf '%s %s %s %s\n' "$(prop "$1" "$2" satisfies)" "$(prop "$1" "$2" closes)" "$(prop "$1" "$2" takes_work)" \
        "$(prop "$1" "$2" renders | jq -r '"\(.struck) \(.class)"')"
}

echo "== the table's properties, as the Rust reader asserts them =="
for schema in roadmap/v1 roadmap/v2 roadmap/v3 ""; do
    for w in Done Shipped Closed "Done -- shipped in #12"; do
        eq "${schema:-no schema}: $w satisfies, closes, takes no work, struck done" "true true false true done" "$(props "$schema" "$w")"
    done
    eq "${schema:-no schema}: Dropped closes only, unstruck" "false true false false null" "$(props "$schema" Dropped)"
    for w in "Not started" "In progress" needs-design "" Completed Verified Doneness done; do
        eq "${schema:-no schema}: [$w] is open" "false false true false null" "$(props "$schema" "$w")"
    done
done
eq "roadmap/v4: Completed satisfies, takes no work, doesn't close, unstruck completed" "true false false false completed" "$(props roadmap/v4 Completed)"
eq "roadmap/v4: Verified satisfies and closes, struck done" "true true false true done" "$(props roadmap/v4 Verified)"
eq "roadmap/v4: Dropped closes only, struck dropped" "false true false true dropped" "$(props roadmap/v4 Dropped)"
for w in "Not started" "In progress" Done Shipped Closed; do
    eq "roadmap/v4: $w is open" "false false true false null" "$(props roadmap/v4 "$w")"
done
fam() { (PROG=lib-status; . "$HERE/state-common.sh"; lib_status_family "$1"); }
eq "the family follows the schema line" "v4 v1-v3 v1-v3 v1-v3 v1-v3" "$(fam roadmap/v4) $(fam roadmap/v3) $(fam roadmap/v2) $(fam roadmap/v1) $(fam '')"
(PROG=lib-status; . "$HERE/state-common.sh"; lib_status_prop roadmap/v4 Completed colour) > /dev/null 2>&1
eq "a property outside the four is refused" 64 $?

N=0
# picked <name> <roadmap.md>: pick-facts.sh's facts for a roadmap run whose
# roadmap on the default branch is that file, in $T/pick.json; PICK_OUT its
# sealed verdict.
picked() {
    N=$((N + 1))
    S="coordinate-roadmap-$1-20260926T08$(printf %02d "$N")00Z"
    db_init
    db '.files["acme/widgets"][$k] = $t' --arg k "main:docs/roadmaps/ROADMAP-$1.md" --rawfile t "$2"
    found_session "$S" "$(roadmap_vars "$1")"
    seed_session "$S" "$(record_json roadmap "$1")"
    log_to "$S" reconcile pick_facts
    PICK_OUT=$(bash "$PF" --session "$S" 2> "$T/pick.err")
    PICK_RC=$?
    cp "$KOTO_STORE/context/$S/coord/pick.json" "$T/pick.json" 2> /dev/null || echo '{}' > "$T/pick.json"
}
# pickable: the units the pick may offer (not done, not blocked), by tag.
pickable() { jq -r '[.units[] | select((.done | not) and (.blocked | not)) | .unit] | join(",")' "$T/pick.json"; }
unit() { jq -c --arg u "$1" '.units[] | select(.unit == $u) | {done, takes_work, blocked}' "$T/pick.json"; }
# roadmap <schema> <status1> <status2> [<status3> <status4>]: Milestone 2
# depends on Milestone 1 and, given four, Milestone 4 on Milestone 3.
roadmap() {
    printf -- '---\nschema: %s\nstatus: Active\n---\n\n# ROADMAP: statuses\n\n## Milestones\n\n' "$1"
    printf '### Milestone 1: Loader\n**Dependencies:** None\n**Status:** %s\n\n' "$2"
    printf '### Milestone 2: Registry\n**Dependencies:** Milestone 1\n**Status:** %s\n\n' "$3"
    if [ $# -ge 5 ]; then
        printf '### Milestone 3: Search\n**Dependencies:** None\n**Status:** %s\n\n' "$4"
        printf '### Milestone 4: Index\n**Dependencies:** Milestone 3\n**Status:** %s\n\n' "$5"
    fi
    printf '## Sequencing Rationale\n\nIn order.\n'
}

echo "== roadmap/v4 in the picker =="
roadmap roadmap/v4 Completed "Not started" > "$T/v4.md"
picked v4 "$T/v4.md"
eq "pick-facts.sh reads a roadmap/v4 roadmap" 0 "$PICK_RC"
eq "Milestone 2 is pickable over a Completed Milestone 1, which isn't" "Milestone 2" "$(pickable)"
eq "  ... Milestone 1 takes no work" '{"done":true,"takes_work":false,"blocked":false}' "$(unit "Milestone 1")"
eq "  ... Milestone 2 takes work" '{"done":false,"takes_work":true,"blocked":false}' "$(unit "Milestone 2")"
case "$PICK_OUT" in scope-complete*) bad "  ... and the scope isn't complete while a milestone is Completed" "$PICK_OUT" ;; *) ok "  ... and the scope isn't complete while a milestone is Completed" ;; esac
roadmap roadmap/v4 Dropped "Not started" > "$T/v4d.md"
picked v4d "$T/v4d.md"
eq "a dependent of a Dropped Milestone 1 isn't pickable" "" "$(pickable)"
eq "  ... it is blocked by it" '[1]' "$(jq -c '.units[] | select(.unit == "Milestone 2") | .blocked_by' "$T/pick.json")"
roadmap roadmap/v4 Verified Dropped > "$T/v4v.md"
picked v4v "$T/v4v.md"
case "$PICK_OUT" in scope-complete*) ok "Verified and Dropped are scope-complete" ;; *) bad "Verified and Dropped are scope-complete" "$PICK_OUT" ;; esac

echo "== roadmap/v3 in the picker =="
roadmap roadmap/v3 Shipped "Not started" Closed "Not started" > "$T/v3.md"
picked v3 "$T/v3.md"
eq "pick-facts.sh reads it" 0 "$PICK_RC"
eq "the dependents of Shipped and Closed are pickable, and neither is" "Milestone 2,Milestone 4" "$(pickable)"
eq "  ... a unit carries no takes_work on v3" "false" "$(jq -c '[.units[] | has("takes_work")] | any' "$T/pick.json")"
roadmap roadmap/v3 Dropped "Not started" > "$T/v3d.md"
picked v3d "$T/v3d.md"
eq "a dependent of a Dropped Milestone 1 isn't pickable" "" "$(pickable)"

echo "== roadmap/v4 at close-out =="
RP=docs/roadmaps/ROADMAP-statuses.md
SR=coordinate-roadmap-statuses-20260926T070000Z
cr() { # cr <roadmap.md>: closeout-read.sh's token on that roadmap, a clear record
    db_init; seed_session "$SR" "$(record_json roadmap statuses)"
    db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --rawfile t "$1"
    RS_SESSION=$SR bash "$CR" --scope roadmap --name statuses --repo "$REPO" --roadmap "$RP" --no-seal 2> "$T/cr.err"
}
roadmap roadmap/v4 Completed Verified > "$T/c1.md"
eq "a Completed milestone keeps a v4 roadmap open" features-open "$(cr "$T/c1.md")"
grep -q '1 milestone(s) not Verified or Dropped' "$T/cr.err" && ok "  ... the reason names the closing statuses" || bad "  ... the reason names the closing statuses" "$(cat "$T/cr.err")"
roadmap roadmap/v4 Verified Dropped > "$T/c2.md"
eq "Verified and Dropped close a v4 roadmap" ready "$(cr "$T/c2.md")"
roadmap roadmap/v3 Closed Shipped > "$T/c3.md"
eq "Closed and Shipped close a v3 roadmap" ready "$(cr "$T/c3.md")"

echo "== a table the scripts can't read =="
# A copy of the scripts beside a table of the case's making, so the shipped
# table is never touched.
C="$T/copy"
mkdir -p "$C/skills/coordinate" "$C/skills/roadmap/references"
cp -R "$HERE" "$C/skills/coordinate/scripts"
TBL="$C/skills/roadmap/references/milestone-statuses.json"
TBL_REAL=$(cd "${TBL%/*}" && pwd)/milestone-statuses.json
SHIPPED="$HERE/../../roadmap/references/milestone-statuses.json"
roadmap roadmap/v4 Completed "Not started" > "$T/fc.md"
fail_closed() { # fail_closed <case>: both scripts refuse, naming the table, writing nothing
    local s out rc
    for s in pick-facts closeout-read; do
        db_init
        db '.files["acme/widgets"][$k] = $t' --arg k "main:$RP" --rawfile t "$T/fc.md"
        out=$(RS_SESSION=$SR bash "$C/skills/coordinate/scripts/$s.sh" --scope roadmap --name statuses --repo "$REPO" --roadmap "$RP" --no-seal 2> "$T/fc.err")
        rc=$?
        eq "$1: $s exits 2" 2 "$rc"
        grep -qF "$TBL_REAL" "$T/fc.err" && ok "  ... naming the table's path" || bad "  ... naming the table's path" "$(cat "$T/fc.err")"
        eq "  ... printing nothing" "" "$out"
        eq "  ... and making no GitHub call" "" "$(calls)"
    done
    (HERE="$C/skills/coordinate/scripts" PROG=lib-status; . "$HERE/state-common.sh"; lib_roadmap_features "$T/fc.md") > /dev/null 2> "$T/rf.err"
    [ $? -ne 0 ] && grep -qF "$TBL_REAL" "$T/rf.err" && ok "$1: lib_roadmap_features fails naming the table" \
        || bad "$1: lib_roadmap_features fails naming the table" "$(cat "$T/rf.err")"
}
rm -f "$TBL"
fail_closed "the table removed"
printf '{"version": 1, "schemas": ' > "$TBL"
fail_closed "the table unparseable"
jq '.version = 2' "$SHIPPED" > "$TBL"
fail_closed "an unknown version"
grep -q 'version 2' "$T/fc.err" && ok "  ... the message names the version" || bad "  ... the message names the version" "$(cat "$T/fc.err")"
jq 'del(.open)' "$SHIPPED" > "$TBL"
fail_closed "a table without open"
cp "$SHIPPED" "$TBL"
(HERE="$C/skills/coordinate/scripts" PROG=lib-status; . "$HERE/state-common.sh"; lib_status_prop roadmap/v4 Completed satisfies) > "$T/ok.out" 2>&1
eq "the shipped table, copied back, reads" true "$(cat "$T/ok.out")"

done_tests lib-status
