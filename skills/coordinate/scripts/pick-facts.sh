#!/usr/bin/env bash
# pick-facts.sh -- the check action of state pick_facts: the facts pick
# decides on, and whether the scope is over.
#
# Units, in order. Roadmap scope: the features under `## Features` of the
# roadmap on the host's default branch (record-common.sh lib_roadmap_features:
# `### Feature N: title` or `### <PREFIX><N>: title`, `**Dependencies:**`,
# `**Status:**`), in the roadmap's order. A unit is blocked while a feature it
# depends on doesn't read Done; blocked_by lists those feature numbers;
# blocker_landed is true when it has dependencies and every one reads Done.
# Discipline scope: the host's open issues labelled with the discipline's name
# (gh issue list --label, never a search), in issue-number order, none blocked.
# A roadmap unit carries `landed`, the pull request link of its pending
# roadmap pull request (roadmap-status.sh --list), or null: a landed unit is
# never dispatched, and once the roadmap reads it Done its row is confirmed
# with roadmap-status.sh --confirm. A discipline's units carry null.
# Each unit carries the holding that covers it, {worker, phase}, or null: a
# holding covers a roadmap unit when its Unit cell is the feature's heading tag
# ("Feature 2", "ED1") or "<tag>: <title>", and an issue when it is "#<n>" or
# "<owner/repo>#<n>". dispatch-common.sh dc_unit_forms lists the same forms
# from coord/pick.json for the dispatch path's check of a brief's unit;
# pick-facts_test.sh holds the two to each other.
#
# Then, at either scope, the units a person assigned outside it: one per
# Standing row of kind assignment (record-state.sh), its On the unit's id
# (`#<n>` or `<owner/repo>#<n>`, an issue, read for its title and state and
# done once closed; or `release <owner/repo> <tag>`, done when its row
# ends), each carrying `assigned`, the row's id. One the scope already lists
# isn't added again, and while any is open the roadmap isn't complete. A
# holding covers one when its Unit cell is the id, or `<host><id>` for `#<n>`.
#
# Holdings come from the record (record-holding.sh --list), each marked
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
# The record's Work rows that keep a unit's later work (record-state.sh):
# each unit carries `awaiting`, the number of the unsettled decision entry a
# `decision` row parks it on (pick's await_decision), or null; `answered`,
# {decision, outcome} once that entry is settled or gone, when the unit is
# dispatchable again with the answer; and `follow_up`, {after, next} from a
# `follow-up` row (the pull request that landed its scoping alone, and its
# execution), or null. A Work row matches a unit as a pause's On does. None
# of the three holds a slot.
#
# Verdict tokens:
#   decisions        decision-next.sh --owed pick names a rule: an unrecorded
#                    write, an owed message, a carry, a proposed entry or one
#                    waiting for a verdict (a held entry and an escalation that
#                    owes nothing never count). It comes first, so owed work
#                    is done before a close is attempted. Needs the session
#   scope-complete   roadmap: the roadmap lists features and every one reads
#                    Done or Dropped
#   rotation-over    discipline: today UTC is after the record title's end date
#   pick             anything else
# The facts go to context key coord/pick.json as data (pick's decider input):
#   {scope, name, host (the repository an issue's `<host>#<n>` names),
#    units: [{unit, number, title, status, done, blocked,
#    blocked_by, blocker_landed, holding, landed, paused, awaiting, answered,
#    follow_up, assigned?}], holdings: [{worker, unit, phase,
#    dispatch_status, parked, merged, pull_request, paused}], decisions: [{decision, question,
#    state, round, verdict, reason, recommendation, target, owed}], active,
#    parked, cap, parked_bound, pauses, go_aheads, paused_all}
# decisions is the record's unsettled entries (record-decision.sh --list),
# the rows the progress table renders.
#
# Usage:
#   pick-facts.sh --session S
#   pick-facts.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                 --ref N [--roadmap PATH] [--today YYYY-MM-DD] [--no-seal]   (tests)
#
# Exit codes: 0 a verdict was printed; 2 a read failed (the roadmap missing
# from the default branch included); 64 usage.
#
# GitHub reads: gh api --method GET repos/R --jq .default_branch;
# gh api --method GET "repos/R/contents/<roadmap>?ref=<default>";
# gh issue list --repo R --state open --label <name> --json number,title --limit 200;
# gh issue view <n> --repo <repo> --json number,title,state per assigned issue;
# gh pr view <n> --repo R --json title; record-holding.sh --list (gh issue|pr view);
# gh pr view <n> --repo <repo> --json state,isDraft per verified holding.
set -uo pipefail

PROG=pick-facts
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= TODAY= ARG_ROADMAP=
NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --roadmap) [ $# -ge 2 ] || usage; ARG_ROADMAP=$2; shift 2 ;;
        --today) [ $# -ge 2 ] || usage; TODAY=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
ROADMAP=$ARG_ROADMAP
lib_facts
[ -z "$ARG_ROADMAP" ] || [ "$OVERRIDE" = 1 ] || usage
if [ -n "$TODAY" ]; then lib_valid_date "$TODAY" || usage; else TODAY=$(date -u +%Y-%m-%d); fi
lib_run_ref || lib_die2 "the run has no found record"
lib_bounds

T=$(mktemp -d "${TMPDIR:-/tmp}/pick-facts.XXXXXX")
trap 'rm -rf "$T"' EXIT

# The holdings, through record-holding.sh (the one reader of Holdings rows).
set -- --list
if [ "$OVERRIDE" = 1 ]; then set -- "$@" --scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF"
else set -- "$@" --session "$SESSION"; fi
bash "$HERE/record-holding.sh" "$@" > "$T/holdings.json" 2> "$T/holdings.err" \
    || lib_die2 "record-holding.sh --list failed: $(lib_scrub < "$T/holdings.err")"
lib_parked "$T/holdings.json" "$T/counted.json" || lib_die2 "a holding's pull request read failed"
# The cap a person set in the record's Run section wins over the session's
# (record-state.sh, the one reader of the stored set).
bash "$HERE/record-state.sh" "$@" > "$T/state.json" 2> "$T/state.err" \
    || lib_die2 "record-state.sh --list failed: $(lib_scrub < "$T/state.err")"
lib_bounds "$T/state.json"
# The unsettled decision entries, through record-decision.sh, the one reader of the section.
set -- --list
if [ "$OVERRIDE" = 1 ]; then set -- "$@" --scope "$SCOPE" --name "$NAME" --repo "$REPO" --ref "$REF"
else set -- "$@" --session "$SESSION"; fi
bash "$HERE/record-decision.sh" "$@" > "$T/decisions.json" 2> "$T/decisions.err" \
    || lib_die2 "record-decision.sh --list failed: $(lib_scrub < "$T/decisions.err")"

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
    # The roadmap pull requests the record holds as pending (roadmap-status.sh,
    # the one reader of those rows): a unit named by one has landed and is
    # never offered again, though it isn't Done for its dependents until the
    # roadmap says so.
    # "$@" is still `--list` and the record's addressing, as set for
    # record-decision.sh above.
    bash "$HERE/roadmap-status.sh" "$@" > "$T/landed.json" 2> "$T/landed.err" \
        || lib_die2 "roadmap-status.sh --list failed: $(lib_scrub < "$T/landed.err")"
    jq -c --slurpfile h "$T/counted.json" --slurpfile l "$T/landed.json" '. as $f | map(. as $u
        | ([$u.dependencies[] as $d | select(([$f[] | select(.number == $d and (.status | test("^Done\\.?$")))] | length) == 0) | $d]) as $by
        | {unit: $u.id, number: $u.number, title: $u.title, status: $u.status, done: $u.done,
           blocked: (($by | length) > 0), blocked_by: $by,
           blocker_landed: ((($u.dependencies | length) > 0) and (($by | length) == 0)),
           holding: ([$h[0][] | select(.unit == $u.id or .unit == ($u.id + ": " + $u.title))][0]
                     | if . == null then null else {worker, phase} end),
           landed: ([$l[0][] | select(.unit == $u.id) | .pull_request][0] // null)})' "$T/features.json" > "$T/units.json" \
        || lib_die2 "jq failed"
    if [ "$(jq length "$T/units.json")" -gt 0 ] && jq -e 'all(.done)' "$T/units.json" > /dev/null; then
        VERDICT=scope-complete
    fi
else
    gh pr view "$REF" --repo "$REPO" --json title > "$T/pr.json" 2> "$T/pr.err" < /dev/null \
        || lib_die2 "cannot read pull request #$REF: $(lib_scrub < "$T/pr.err")"
    lib_rotation_dates "$(jq -r '.title // ""' "$T/pr.json")" || lib_die2 "the record's title is not a rotation title"
    [ "$ROT_END" \< "$TODAY" ] && VERDICT=rotation-over
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
# done once closed; a release is done when its row ends.
jq -c '[(.standing // [])[] | select(.kind == "assignment") | {id: .on, standing}]' "$T/state.json" > "$T/assigned.json" || lib_die2 "jq failed"
: > "$T/assigned.lines"
n=$(jq length "$T/assigned.json"); i=0
while [ "$i" -lt "$n" ]; do
    ID=$(jq -r --argjson i "$i" '.[$i].id' "$T/assigned.json")
    SID=$(jq -r --argjson i "$i" '.[$i].standing' "$T/assigned.json")
    i=$((i + 1))
    jq -e --arg u "$ID" --arg h "$REPO" 'any(.[]; .unit == $u or ($h + .unit) == $u)' "$T/units.json" > /dev/null && continue
    case "$ID" in
        release\ *)
            jq -nc --arg u "$ID" --arg s "$SID" '{unit: $u, number: null, title: "", status: "to release", done: false,
                blocked: false, blocked_by: [], blocker_landed: false, landed: null, assigned: $s}' >> "$T/assigned.lines" ;;
        *)
            IREPO=${ID%%#*}; [ -n "$IREPO" ] || IREPO=$REPO
            gh issue view "${ID##*#}" --repo "$IREPO" --json number,title,state > "$T/issue.json" 2> "$T/issue.err" < /dev/null \
                || lib_die2 "cannot read assigned issue $ID: $(lib_scrub < "$T/issue.err")"
            jq -c --arg u "$ID" --arg s "$SID" '{unit: $u, number, title: (.title | .[0:120]), status: (.state | ascii_downcase),
                done: ((.state | ascii_downcase) == "closed"), blocked: false, blocked_by: [], blocker_landed: false,
                landed: null, assigned: $s}' "$T/issue.json" >> "$T/assigned.lines" || lib_die2 "jq failed" ;;
    esac
done
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
    OWED_RULE=$(bash "$HERE/decision-next.sh" --session "$SESSION" --owed pick) || lib_die2 "cannot read what the decisions are owed"
    [ "$OWED_RULE" = none ] || VERDICT="decisions $OWED_RULE"
fi

jq -n --arg scope "$SCOPE" --arg name "$NAME" --arg host "$REPO" --slurpfile u "$T/units.json" --slurpfile h "$T/counted.json" --slurpfile d "$T/decisions.json" \
    --slurpfile pz "$T/pauses.json" --slurpfile st "$T/state.json" --argjson cap "$CAP" --argjson pb "$PARKED_BOUND" '
    $pz[0] as $p
    | ($st[0].work // []) as $w
    | def row($k; $x): [$w[] | select(.kind == $k and (.item == $x or .item == ($host + $x)))][0];
      def parked_on($x): (row("decision"; $x) | if . == null then null else (.who | ltrimstr("decision ")) end) as $n
        | ([($d[0].entries // [])[] | select(.decision == $n)][0]) as $e
        | if $n == null then {awaiting: null, answered: null}
          elif $e != null and $e.state != "settled" then {awaiting: $n, answered: null}
          else {awaiting: null, answered: {decision: $n, outcome: ($e.outcome // "")}} end;
    {scope: $scope, name: $name, host: $host,
     units: [$u[0][] | . + {paused: ($p.covers[.unit] // null)} + parked_on(.unit)
                     + {follow_up: (row("follow-up"; .unit) | if . == null then null else {after: .who, next: .next} end)}],
     holdings: [$h[0][] | {worker, unit, phase, dispatch_status, parked, merged, pull_request, paused: ($p.covers[.unit] // null)}],
     decisions: [$d[0].entries[] | select(.state != "settled")
                 | {decision, question, state, round, verdict: (.verdict // ""), reason: (.reason // ""),
                    recommendation: (.recommendation // ""), target: (.target // ""), owed: (.owed // "")}],
     active: ([$h[0][] | select((.parked | not) and (.merged | not))] | length), parked: ([$h[0][] | select(.parked)] | length),
     cap: $cap, parked_bound: $pb, pauses: $p.pauses, go_aheads: $p.go_aheads, paused_all: $p.all}' > "$T/pick.json" || lib_die2 "jq failed"
lib_emit pick_facts "$VERDICT" coord/pick.json "$T/pick.json"
