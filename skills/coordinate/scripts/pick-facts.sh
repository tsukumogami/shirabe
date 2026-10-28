#!/usr/bin/env bash
# pick-facts.sh -- the check action of state pick_facts: the facts pick
# decides on, and whether the scope is over.
#
# Where this header names a lister (state-holding.sh --list, state-stored-set.sh,
# state-decision.sh --list, roadmap-status.sh --list), the rows are that
# lister's --list projection in state-schema.jq, taken from the one read and
# parse of the record this script makes; the listers themselves aren't run.
#
# Units, in order. Roadmap scope: the items under the items section of the
# roadmap on the host's default branch (`## Milestones` on a roadmap/v3
# roadmap, `## Features` otherwise), in the roadmap's order, as
# state-common.sh lib_roadmap_features reads them: `### Feature N: title`
# (`### Milestone N: title` on v3) or `### <PREFIX><N>[a-z]: title`, the
# `**Status:**` value, and the dependencies
# its `**Dependencies:**` paragraph names, soft mentions and parenthesised
# text aside. A dependency is satisfied only when the feature it names is
# finished (its Status opens Done or Shipped); a Dropped one never satisfies
# it. A unit that is done (finished, or Dropped) is never blocked; any other
# is blocked while a dependency is unsatisfied, and blocked_by lists those
# features' positions (1-based, in heading order, which differ from the N of
# `Feature N` only when headings are out of order), ascending. blocker_landed is true when it has dependencies
# and none is unsatisfied.
# Discipline scope: the host's open issues labelled with the discipline's name
# (gh issue list --label, never a search), in issue-number order, none blocked.
# A roadmap unit carries `landed`, the pull request link of its pending
# roadmap pull request (roadmap-status.sh --list), or null: a landed unit is
# never dispatched, and once the roadmap reads it Done its row is confirmed
# with roadmap-status.sh --confirm. A discipline's units carry null.
# Each unit carries the holding that covers it, {worker, phase}, or null: a
# holding covers a roadmap unit when its Unit cell is the feature's heading tag
# ("Feature 2", "ED1") or "<tag>: <title>", and an issue when it is "#<n>" or
# "<owner/repo>#<n>". A tag and a unit compare by state-common.sh tag_key,
# here and for landed rows and Work rows, so a holding or a row written under
# `Feature 2` still covers the heading `Milestone 2` of a v3 roadmap, and one
# naming `Milestone 2` covers a v2 `Feature 2`. dispatch-common.sh
# dc_unit_forms lists, from coord/pick.json, the forms the dispatch path
# accepts for a brief's unit: the unit's own tag and `<tag>: <title>`, never
# its Feature/Milestone twin. Each is one this rule reads as covering, so a
# holding written through dispatch is never invisible here, while this rule
# also reads the twin a record written before a rename names.
# pick-facts_test.sh holds dispatch's forms to this rule.
#
# Then, at either scope, the units a person assigned outside it: one per
# Standing row of kind assignment (state-stored-set.sh), its On the unit's id
# (`#<n>` or `<owner/repo>#<n>`, an issue or a pull request, read for its
# title and state and done once closed or merged; or `release <owner/repo>
# <tag>`, done when its row ends), each carrying `assigned`, the row's id.
# One the scope already lists isn't added again, and while any is open the
# roadmap isn't complete. A holding covers one when its Unit cell is the id,
# or `<host><id>` for `#<n>`.
#
# Holdings come from the record (state-holding.sh --list), each marked
# parked (a Verified head, and its pull request open and not a draft), merged
# (a Verified head and its Pull request cell cleared by a confirmed merge,
# waiting for its worker's teardown) or active; only active ones count
# against the cap. Local agents have no holding and are never counted. The counts sit
# beside CAP and PARKED_BOUND from the session's variables, the cap from the
# record's Run section when it has one.
#
# The record's pauses (Standing rows of kind pause, evaluated by
# pause-read.sh): each unit and holding carries `paused`, the id of the pause
# that holds it, or null; the facts carry every pause with its state
# (in-force, met, unreadable), the go-aheads, and `paused_all`, the id of the
# pause on `all` that holds the whole coordinator, or null. A paused unit is
# never chosen, and while `paused_all` is set pick holds
# (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1).
#
# The record's Work rows that keep a unit's later work (state-stored-set.sh):
# each unit carries `awaiting`, the number of the unsettled decision entry a
# `decision` row parks it on (pick's await_decision), or null; `answered`,
# {decision, outcome} once that entry is settled or gone, when the unit is
# dispatchable again with the answer; and `follow_up`, {after, next} from a
# `follow-up` row (the pull request that landed its scoping alone, and its
# execution), or null. A Work row matches a unit by its Item, compared by
# tag key (`Feature 2` covers `Milestone 2`), or as `<host><unit>` for an
# issue; a pause's On (pause-read.sh) matches by the same key, so a pause
# written on `Feature 3` holds a v3 roadmap's `Milestone 3`. None
# of the three holds a slot. Each unit also carries `verdict_owed`, true while
# a `verdict-owed` row names it (a milestone whose work the coordinator
# judged finished and whose verdict's roadmap edit isn't confirmed yet,
# roadmap-status.sh), with or without its holding: such a unit is never
# dispatched (docs/designs/DESIGN-milestone-verdicts.md, Decision 1). And
# each carries `rework`, the Next step of a `rework` row that names it (the
# not-held clauses and Changes needed line a confirmed changes-needed verdict
# left, or the failed clause and what was seen a confirmed reopen left,
# roadmap-status.sh --confirm), or null: such a milestone reads In
# progress and is offered like any other once no holding covers it, and its
# next brief quotes the text (render-brief.sh), which dispatch clears.
#
# Verdict tokens:
#   decisions        decision-next.sh --owed pick names a rule: an unrecorded
#                    write, an owed message, a carry, a proposed entry or one
#                    waiting for a verdict (a held entry and an escalation that
#                    owes nothing never count). It comes first, so owed work
#                    is done before a close is attempted. Needs the session
#   scope-complete   roadmap: the roadmap lists features and every one is
#                    done (its Status opens Done, Shipped or Dropped)
#   rotation-over    discipline: today UTC is after the rotation's end date
#                    (record/rotation's), or the rotation's reasoning is written
#   pick             anything else
# The facts go to context key coord/pick.json as data (what the agent reads at
# pick):
#   {scope, name, host (the repository an issue's `<host>#<n>` names),
#    units: [{unit, number, title, status, done, blocked,
#    blocked_by, blocker_landed, holding, landed, paused, awaiting, answered,
#    follow_up, verdict_owed, rework, assigned?}], holdings: [{worker, unit, phase,
#    dispatch_status, parked, merged, pull_request, paused}], decisions: [{decision, question,
#    state, round, verdict, reason, recommendation, target, owed}], active,
#    parked, cap, parked_bound, pauses, go_aheads, paused_all}
# decisions is the record's unsettled entries (state-decision.sh --list),
# the rows the progress table renders.
# Their slice goes to context key coord/pick_slice.json, pick's decider input:
# pick-slice.jq's pick_slice of the facts this visit built, done units
# collapsed to their tags and null, false and empty-list fields left out. The
# slice is stored first and the facts second (lib_emit), and only then is the
# verdict sealed, so a sealed verdict means both keys were written on this
# visit; the context-exists gates on them can't tell a stale key from a fresh
# one, and the seal can. Under --no-seal neither key is stored.
#
# Usage:
#   pick-facts.sh --session S
#   pick-facts.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                 [--roadmap PATH] [--today YYYY-MM-DD] [--no-seal]   (tests)
#
# Exit codes: 0 a verdict was printed; 2 a read failed (the roadmap missing
# from the default branch included); 64 usage.
#
# The record is read once, through state-read.sh's rs_record.
# GitHub reads: gh api --method GET repos/R --jq .default_branch;
# gh api --method GET "repos/R/contents/<roadmap>?ref=<default>";
# gh issue list --repo R --state open --label <name> --json number,title --limit 200;
# one gh api graphql (query pickAssigned) for every assigned issue's number,
# title and state; gh pr view <n> --repo <repo> --json state,isDraft per
# verified holding.
set -uo pipefail

PROG=pick-facts
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= TODAY= ARG_ROADMAP=
NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --roadmap) [ $# -ge 2 ] || usage; ARG_ROADMAP=$2; shift 2 ;;
        --today) [ $# -ge 2 ] || usage; TODAY=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/state-common.sh"
ROADMAP=$ARG_ROADMAP
lib_facts
[ -z "$ARG_ROADMAP" ] || [ "$OVERRIDE" = 1 ] || usage
if [ -n "$TODAY" ]; then lib_valid_date "$TODAY" || usage; else TODAY=$(date -u +%Y-%m-%d); fi
lib_run_found || lib_die2 "the run has no found record"
lib_bounds

T=$(mktemp -d "${TMPDIR:-/tmp}/pick-facts.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

# The record, read and parsed once, as the listers read it (state-read.sh
# rs_record). The holdings, the Run,
# Standing and Work rows, the decision entries and the pending roadmap pull
# requests are the listers' own --list projections (state-schema.jq), taken
# from this one parse: running state-holding.sh, state-stored-set.sh,
# state-decision.sh and roadmap-status.sh would read and parse the record once
# apiece (shirabe#840).
rs_record "$T/rec.json" "holdings side_effects decisions run standing work"
case $? in
    0) ;;
    2) lib_die2 "cannot read the record: $(lib_scrub < "$T/rec.json.err")" ;;
    *) lib_die2 "$(lib_record_name) holds no record pick can read: $(lib_scrub < "$T/rec.json.err")" ;;
esac
jq -c -L "$HERE" --arg s "$SCOPE" 'include "state-schema";
    holdings_list, state_list, decisions_list, (if $s == "roadmap" then pending_list else [] end)' "$T/rec.json" > "$T/lists" \
    || lib_die2 "jq failed"
# One compact line each, in this order: holdings, Run/Standing/Work, decisions,
# pending roadmap pull requests ([] outside roadmap scope).
{ IFS= read -r l1 && IFS= read -r l2 && IFS= read -r l3 && IFS= read -r l4; } < "$T/lists" || lib_die2 "jq failed"
printf '%s\n' "$l1" > "$T/holdings.json"
printf '%s\n' "$l2" > "$T/state.json"
printf '%s\n' "$l3" > "$T/decisions.json"
printf '%s\n' "$l4" > "$T/landed.json"
lib_parked "$T/holdings.json" "$T/counted.json" || lib_die2 "a holding's pull request read failed"
# The cap a person set in the record's Run section wins over the session's.
lib_bounds "$T/state.json"

VERDICT=pick
if [ "$SCOPE" = roadmap ]; then
    lib_roadmap_path
    lib_default_branch || lib_die2 "cannot read $REPO's default branch"
    lib_file_at "$ROADMAP" "$DEFAULT_BRANCH" "$T/roadmap.md"
    case $? in
        0) ;;
        1) lib_die2 "$ROADMAP is not on $DEFAULT_BRANCH" ;;
        *) lib_die2 "cannot read $ROADMAP: $(lib_scrub < "$T/roadmap.md.err")" ;;
    esac
    lib_roadmap_features "$T/roadmap.md" > "$T/features.json" || lib_die2 "cannot parse the roadmap's features"
    # The roadmap pull requests the record holds as pending (landed.json, as
    # roadmap-status.sh --list reads them): a unit named by one has landed and
    # is never offered again, though it isn't finished for its dependents until
    # the roadmap says so.
    # covers($id; $title): a Unit cell naming the item, as its tag or as
    # `<tag>: <title>`, the tag compared by key.
    jq -c --slurpfile h "$T/counted.json" --slurpfile l "$T/landed.json" "$JQ_TAG_KEY"'
        def covers($id; $title): (tag_key == ($id | tag_key))
            or (index(": ") as $i | $i != null and (.[0:$i] | tag_key) == ($id | tag_key) and .[$i + 2:] == $title);
        . as $f | map(. as $u
        | (if $u.done then [] else [$u.dependencies[] as $d | select(([$f[] | select(.number == $d and .finished)] | length) == 0) | $d] end) as $by
        | {unit: $u.id, number: $u.number, title: $u.title, status: $u.status, done: $u.done,
           blocked: (($by | length) > 0), blocked_by: $by,
           blocker_landed: ((($u.dependencies | length) > 0) and (($by | length) == 0)),
           holding: ([$h[0][] | select(.unit | covers($u.id; $u.title))][0]
                     | if . == null then null else {worker, phase} end),
           landed: ([$l[0][] | select((.unit | tag_key) == ($u.id | tag_key)) | .pull_request][0] // null)})' "$T/features.json" > "$T/units.json" \
        || lib_die2 "jq failed"
    if [ "$(jq length "$T/units.json")" -gt 0 ] && jq -e 'all(.done)' "$T/units.json" > /dev/null; then
        VERDICT=scope-complete
    fi
else
    # A rotation keeps its window in record/rotation and is over by the window
    # rule: past its end date, or closed early (its record/reasoning written).
    rs_rotation_open "${RS_SESSION:-$SESSION}" "$TODAY"
    case $? in
        0) ;;
        1) VERDICT=rotation-over ;;
        3) lib_die2 "the rotation's session holds no record/rotation" ;;
        *) lib_die2 "cannot read the rotation's window (record/rotation)" ;;
    esac
    gh issue list --repo "$REPO" --state open --label "$NAME" --json number,title --limit 200 > "$T/issues.json" 2> "$T/issues.err" < /dev/null \
        || lib_die2 "cannot list $REPO's $NAME issues: $(lib_scrub < "$T/issues.err")"
    jq -c --slurpfile h "$T/counted.json" --arg r "$REPO" 'sort_by(.number) | map(. as $i
        | ("#\($i.number)") as $id
        | {unit: $id, number: $i.number, title: ($i.title | .[0:120]), status: "open", done: false,
           blocked: false, blocked_by: [], blocker_landed: false, landed: null,
           holding: ([$h[0][] | select(.unit == $id or .unit == ($r + $id))][0]
                     | if . == null then null else {worker, phase} end)})' "$T/issues.json" > "$T/units.json" \
        || lib_die2 "jq failed"
fi

# The units a person assigned (Standing rows of kind assignment), after the
# scope's own, each once: an issue is read for its title and state, and is
# done once closed; a release is done when its row ends. An issue is `#<n>`
# in the host or `<owner/repo>#<n>`; issue is {repo, number} for one, null for
# a release.
jq -c --slurpfile u "$T/units.json" --arg h "$REPO" '[(.standing // [])[] | select(.kind == "assignment") | {id: .on, standing}
    | select(.id as $i | any($u[0][]; .unit == $i or ($h + .unit) == $i) | not)
    | . + {issue: (if (.id | startswith("release ")) then null
                   else (.id | capture("^(?<repo>[^#]*)#(?<number>.*)$")) // {repo: "", number: ""}
                        | .repo |= (if . == "" then $h else . end) end)}]' "$T/state.json" > "$T/assigned.json" \
    || lib_die2 "jq failed"
jq -r '.[] | select(.issue != null) | [.id, .issue.repo, .issue.number] | @tsv' "$T/assigned.json" > "$T/assigned.tsv" || lib_die2 "jq failed"
# Every assigned issue in one GraphQL read rather than a gh issue view each
# (shirabe#840): field i<k> is the k-th issue, its owner, name and number
# passed as variables. A failed read, or an answer short of any issue (an
# error, a null node, a number other than the one asked for), fails as a
# failed gh issue view did: no unit is dropped, or read closed, for an issue
# that didn't come back. Only number, title and state are asked for, through
# issueOrPullRequest, so a row naming a pull request reads too: OPEN is open,
# CLOSED or MERGED done.
# k numbers the issues only (releases are skipped here and in assigned.tsv),
# and the jq below advances its own .k on the same rows, so field i<k> is the
# k-th issue on both sides.
GQ=() VARS= FIELDS= k=0
while IFS=$'\t' read -r id r num; do
    [[ $r =~ $RE_REPO ]] && [[ $num =~ $RE_NUM ]] || lib_die2 "cannot read assigned issue $id: it names no issue"
    VARS="$VARS, \$o$k: String!, \$r$k: String!, \$n$k: Int!"
    FIELDS="$FIELDS i$k: repository(owner: \$o$k, name: \$r$k) { issueOrPullRequest(number: \$n$k) { ... on Issue { number title state } ... on PullRequest { number title state } } }"
    GQ+=(-f "o$k=${r%%/*}" -f "r$k=${r#*/}" -F "n$k=$num")
    k=$((k + 1))
done < "$T/assigned.tsv"
if [ "$k" -gt 0 ]; then
    gh api graphql -f query="query pickAssigned(${VARS#, }) {$FIELDS }" "${GQ[@]}" > "$T/issues-read.json" 2> "$T/issues-read.err" < /dev/null \
        || lib_die2 "cannot read the assigned units: $(lib_scrub < "$T/issues-read.err")"
else
    echo '{"data": {}}' > "$T/issues-read.json"
fi
jq -c --slurpfile r "$T/issues-read.json" '
    if (($r[0].errors // []) | length) > 0 then error("the read answered with errors") else . end
    | reduce .[] as $a ({k: 0, out: []};
        if $a.issue == null then
            .out += [{unit: $a.id, number: null, title: "", status: "to release", done: false,
                      blocked: false, blocked_by: [], blocker_landed: false, landed: null, assigned: $a.standing}]
        else (($r[0].data // {})["i\(.k)"].issueOrPullRequest // null) as $n
            | if $n == null or ($n.number | tostring) != $a.issue.number or ($n.title | type) != "string"
                 or (($n.state | IN("OPEN", "CLOSED", "MERGED")) | not)
              then error("assigned unit \($a.id) did not come back") else . end
            | .out += [{unit: $a.id, number: $n.number, title: ($n.title | .[0:120]), status: ($n.state | ascii_downcase),
                        done: ($n.state == "CLOSED" or $n.state == "MERGED"), blocked: false, blocked_by: [], blocker_landed: false,
                        landed: null, assigned: $a.standing}]
            | .k += 1
        end)
    | .out[]' "$T/assigned.json" > "$T/assigned.lines" 2> "$T/assigned.err" \
    || lib_die2 "cannot read the assigned units: $(lib_scrub < "$T/assigned.err")"
jq -c -s --slurpfile u "$T/units.json" --slurpfile h "$T/counted.json" --arg r "$REPO" '$u[0] + map(. as $a
    | . + {holding: ([$h[0][] | select(.unit == $a.unit or .unit == ($r + $a.unit))][0]
                     | if . == null then null else {worker, phase} end)})' "$T/assigned.lines" > "$T/units2.json" \
    && mv "$T/units2.json" "$T/units.json" || lib_die2 "jq failed"
# Assigned work still open keeps a roadmap from reading complete.
[ "$VERDICT" = scope-complete ] && ! jq -e 'all(.done)' "$T/units.json" > /dev/null && VERDICT=pick

# The pauses, read live, for every unit and holding listed.
jq -c --slurpfile h "$T/counted.json" '[.[].unit] + [$h[0][].unit] | unique' "$T/units.json" > "$T/punits.json" || lib_die2 "jq failed"
bash "$HERE/pause-read.sh" --standing "$T/state.json" --units "$T/punits.json" > "$T/pauses.json" 2> "$T/pauses.err" \
    || lib_die2 "pause-read.sh failed: $(lib_scrub < "$T/pauses.err")"

# Owed decision work comes before any other verdict.
if [ -n "$SESSION" ]; then
    OWED_RULE=$(bash "$HERE/decision-next.sh" --session "$SESSION" --owed pick --parsed "$T/rec.json") || lib_die2 "cannot read what the decisions are owed"
    [ "$OWED_RULE" = none ] || VERDICT="decisions $OWED_RULE"
fi

jq -n --arg scope "$SCOPE" --arg name "$NAME" --arg host "$REPO" --slurpfile u "$T/units.json" --slurpfile h "$T/counted.json" --slurpfile d "$T/decisions.json" \
    --slurpfile pz "$T/pauses.json" --slurpfile st "$T/state.json" --argjson cap "$CAP" --argjson pb "$PARKED_BOUND" "$JQ_TAG_KEY"'
    $pz[0] as $p
    | ($st[0].work // []) as $w
    | def row($k; $x): [$w[] | select(.kind == $k and ((.item | tag_key) == ($x | tag_key) or .item == ($host + $x)))][0];
      def parked_on($x): (row("decision"; $x) | if . == null then null else (.who | ltrimstr("decision ")) end) as $n
        | ([($d[0].entries // [])[] | select(.decision == $n)][0]) as $e
        | if $n == null then {awaiting: null, answered: null}
          elif $e != null and $e.state != "settled" then {awaiting: $n, answered: null}
          else {awaiting: null, answered: {decision: $n, outcome: ($e.outcome // "")}} end;
    {scope: $scope, name: $name, host: $host,
     units: [$u[0][] | . + {paused: ($p.covers[.unit] // null)} + parked_on(.unit)
                     + {follow_up: (row("follow-up"; .unit) | if . == null then null else {after: .who, next: .next} end)}
                     + {verdict_owed: (row("verdict-owed"; .unit) != null)}
                     + {rework: (row("rework"; .unit) | if . == null then null else .next end)}],
     holdings: [$h[0][] | {worker, unit, phase, dispatch_status, parked, merged, pull_request, paused: ($p.covers[.unit] // null)}],
     decisions: [$d[0].entries[] | select(.state != "settled")
                 | {decision, question, state, round, verdict: (.verdict // ""), reason: (.reason // ""),
                    recommendation: (.recommendation // ""), target: (.target // ""), owed: (.owed // "")}],
     active: ([$h[0][] | select((.parked | not) and (.merged | not))] | length), parked: ([$h[0][] | select(.parked)] | length),
     cap: $cap, parked_bound: $pb, pauses: $p.pauses, go_aheads: $p.go_aheads, paused_all: $p.all}' > "$T/pick.json" || lib_die2 "jq failed"
jq -c -L "$HERE" 'include "pick-slice"; pick_slice' "$T/pick.json" > "$T/pick_slice.json" || lib_die2 "jq failed"
if [ "$NO_SEAL" != 1 ] && [ -n "$SESSION" ]; then
    "$KOTO" context add "$SESSION" coord/pick_slice.json --from-file "$T/pick_slice.json" >/dev/null \
        || lib_die2 "koto context add coord/pick_slice.json failed"
fi
lib_emit pick_facts "$VERDICT" coord/pick.json "$T/pick.json"
