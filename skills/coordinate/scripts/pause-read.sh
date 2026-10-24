#!/usr/bin/env bash
# pause-read.sh -- which of the record's pauses are in force, and which units
# each covers. Read-only; the one evaluator pick, the dispatch check, the land
# check, the merge, the leg pick and the quiet check share
# (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1).
#
# Usage:
#   pause-read.sh --standing FILE [--units FILE]
#
# FILE is JSON holding a `standing` array of Standing rows, as a record's state
# and state-stored-set.sh --list print them. --units names a JSON array of unit
# strings (a feature's tag, `<tag>: <title>`, `#<n>` or `<owner/repo>#<n>`, as
# a Holdings row's Unit cell or pick's unit carries them) to say coverage for.
#
# Prints one JSON object:
#   {pauses:    [<pause row> + {state}],   every pause row, with its state:
#                                          in-force (its condition unmet),
#                                          met, or unreadable (a condition
#                                          that couldn't be read holds, as an
#                                          unreadable hold does)
#    go_aheads: [<go-ahead row>],          every go-ahead naming a unit
#    all:       "<id>" | null,             the first in-force or unreadable
#                                          pause on `all`
#    covers:    {"<unit>": "<id>" | null}, for each --units entry, the pause
#                                          that holds it, or null
#    through:   {"<unit>": "<id>"}}       for each --units entry a go-ahead
#                                          names, that go-ahead's id: the one
#                                          match readers print, never their own
# A unit is covered by the first in-force or unreadable pause on `all` or on
# that unit, unless a go-ahead names it: a go-ahead lets its unit through any
# pause, `all` or its own. A pause's On, and a go-ahead's, matches a unit
# when they are equal or share a tag key (state-common.sh tag_key), when the
# unit is `<tag>: <title>` and its tag matches the On either way, or when one
# is `#<n>` and the other `<owner/repo>#<n>`. The key makes `Feature 3` and
# `Milestone 3` one unit, so a pause written before a roadmap moved to
# roadmap/v3 still holds its milestone, while `Feature 2` never matches
# `Milestone 12`.
#
# Conditions are read live through board-lib.sh's bl_condition_state, under
# its deadline. BL_NOW (YYYY-MM-DDTHH:MMZ) stands in for the clock in tests.
#
# Exit codes: 0 printed; 2 a file couldn't be read, or a condition's read ran
# out of time; 64 usage.
#
# GitHub reads: gh pr view <n> --repo R --json state (a `merged` condition);
# gh api --method GET repos/R/git/ref/tags/T (a `tag` condition).
set -uo pipefail

PROG=pause-read
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/board-lib.sh"

usage() { sed -n '/^# Usage:/,/^# FILE is/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
STANDING= UNITS=
while [ $# -gt 0 ]; do
    case "$1" in
        --standing) [ $# -ge 2 ] || usage; STANDING=$2; shift 2 ;;
        --units) [ $# -ge 2 ] || usage; UNITS=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$STANDING" ] || usage

D=$(mktemp -d "${TMPDIR:-/tmp}/pause-read.XXXXXX") || exit 2
trap 'rm -rf "$D"' EXIT
jq -c '[(.standing // [])[] | select(.kind == "pause")]' "$STANDING" > "$D/pauses" 2> /dev/null \
    || { echo "$PROG: $STANDING holds no Standing rows it can read" >&2; exit 2; }
if [ -n "$UNITS" ]; then
    jq -e 'type == "array" and all(.[]; type == "string")' "$UNITS" > /dev/null 2>&1 \
        || { echo "$PROG: $UNITS is not a JSON array of units" >&2; exit 2; }
    cp "$UNITS" "$D/units"
else
    echo '[]' > "$D/units"
fi

n=$(jq length "$D/pauses")
: > "$D/states"
i=0
while [ "$i" -lt "$n" ]; do
    until=$(jq -r --argjson i "$i" '.[$i].until // ""' "$D/pauses")
    case "$until" in
        lifted|time\ *|merged\ *|tag\ *)
            st=$(bl_condition_state "$until" "$D") || { echo "$PROG: a condition's read ran out of time" >&2; exit 2; } ;;
        *) st=unreadable ;;
    esac
    case "$st" in unmet) st=in-force ;; esac
    printf '%s\n' "$st" >> "$D/states"
    i=$((i + 1))
done

jq -R -s 'split("\n") | map(select(. != ""))' "$D/states" > "$D/states.json" || exit 2
jq -c -n --slurpfile p "$D/pauses" --slurpfile s "$D/states.json" --slurpfile u "$D/units" --slurpfile all "$STANDING" "$JQ_TAG_KEY"'
    def matches($on; $u):
        $on == $u or ($u | startswith($on + ": "))
        or ($on | tag_key) == ($u | tag_key)
        or ($u | index(": ") as $i | $i != null and (.[0:$i] | tag_key) == ($on | tag_key))
        or (($on | startswith("#")) and ($u | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+" + $on + "$")))
        or (($u | startswith("#")) and ($on | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+" + $u + "$")));
    ($p[0] | to_entries | map(.value + {state: $s[0][.key]})) as $pauses
    | [($all[0].standing // [])[] | select(.kind == "go-ahead" and (.on // "") != "")] as $go
    | [$pauses[] | select(.state != "met")] as $holding
    | {pauses: $pauses,
       go_aheads: $go,
       all: ([$holding[] | select(.on == "all") | .standing][0] // null),
       covers: (reduce $u[0][] as $unit ({};
           .[$unit] = (if any($go[]; matches(.on; $unit)) then null
                       else ([$holding[] | select(.on == "all" or matches(.on; $unit)) | .standing][0] // null) end))),
       through: (reduce $u[0][] as $unit ({};
           ([$go[] | select(matches(.on; $unit)) | .standing][0] // null) as $g
           | if $g == null then . else .[$unit] = $g end))}'
