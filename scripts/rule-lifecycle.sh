#!/usr/bin/env bash
# rule-lifecycle.sh -- the reference reader for the check lifecycle's figures.
#
# This is a fixture-tested REFERENCE implementation of the figure definitions
# in references/check-lifecycle.md, for tests and for spot checks on one host.
# It is never the source of a stage decision. It sees one host's journal, so
# it misses every run elsewhere; the figures a stage-change pull request quotes
# come from log queries over the exported journal, written from the same
# definitions. Its fixtures pin every threshold boundary, which is how the
# definitions are tested.
#
# Usage:
#   rule-lifecycle.sh [--registry <file>] figures [--json] [<journal-file>...]
#
# It reads koto journal lines (koto's own line format: one flat JSON object per
# line, dotted keys) from the named files, or from standard input when none is
# named, and each script-checked rule's `stage`, `stage_since` and `gates` from
# the registry beside it (references/rule-registry.json; --registry exists for
# the tests). A line that isn't a JSON object, or has no `at` starting with a
# YYYY-MM-DD date, is skipped. For each rule, in registry order:
#
#   1. Window. Records whose `at` date is on or after the rule's `stage_since`
#      count; the window ends at the newest `at` among all input lines, of
#      any kind and any rule. Its length is the calendar days between the two
#      dates, counted from the date prefixes alone (no time zone, no
#      strptime, which differs between the jq builds on Linux and macOS), and
#      0 with no input. A rule with no `stage_since` has no window: every
#      figure is 0 and it holds.
#   2. Evaluations. `check_evaluated` records carrying
#      `koto.check.finding_count` (a koto that journals findings), whose
#      (`koto.state`, `koto.check`) is the state and gate of one of the rule's
#      `gates` (`<skill>:<state>:<gate>`; the skill isn't journaled), one per
#      (`koto.session.id`, `koto.seq`).
#   3. Fires. Those evaluations with a `check_finding` for the rule at the same
#      session and `koto.seq`, whose own `koto.state` and `koto.check.name` are
#      one of the rule's gates; once per evaluation, and once per evaluation
#      for each `koto.finding.level`. An evaluation with findings at two levels
#      counts in both level columns and once in the fires, and a level other
#      than error, warning or info counts in the fires only, so the fires are
#      evaluations minus passes, not the sum of the level columns. For
#      `panel/open-finding` a finding counts whatever `koto.rule.id` it
#      carries: panel-scope.sh prints every reviewer finding at that rule's
#      stage and at its gates, under the rule the finding cites, if any.
#   4. Disputes. `check_disputed` records naming the rule at one of its gates
#      (`koto.state`, `koto.check.name`; for `panel/open-finding`, any rule id,
#      as with fires), at most one per `koto.session.id`,
#      by `koto.dispute.source`. One session repeating a dispute moves the
#      figure once; the earliest by `at` is the one kept, so the split by
#      source doesn't depend on the order the lines arrive in. Only the two
#      sources koto writes, agent and person, count, and a record with no
#      session id is skipped, since it can't be counted once per session.
#   5. Unconverged visits. (`koto.session.id`, `koto.visit.seq`) pairs with an
#      `error` fire for the rule and no `passed` evaluation of the same gate in
#      that visit. Informational; no criterion reads it.
#   6. Criterion. The first of these the rule meets, or `hold`:
#        demote            warn or block; at least 7 days; at least 3 disputes;
#                          disputes more than 20% of fires
#        retire            shadow, warn or block; at least 300 evaluations and
#                          56 days; no fires. Evaluations whose findings were
#                          cut (koto.check.findings_truncated) are left out of
#                          this count, since a cut list may have dropped the
#                          rule's finding.
#        promote-to-warn   shadow; at least 100 evaluations and 14 days; at
#                          least 1 fire; fires at most 25% of evaluations
#        promote-to-block  warn; at least 100 evaluations and 14 days; at
#                          least 5 fires; disputes at most 5% of fires
#      Rates count agent and person disputes alike, and a rate with a zero
#      denominator meets no criterion that reads it. The arithmetic is integer.
#      No figures meet two criteria (the stages, the fires and the dispute
#      rates rule each pair out), so the order makes the answer definite
#      rather than choosing between rivals.
#
# Output: one tab-separated line per script-checked rule,
#   id stage days evaluations fires_error fires_warning fires_info passes
#   disputes_agent disputes_person unconverged criterion
# or, with --json, one JSON object per rule with those keys and values. The
# stage shown is the registry's, or block when an entry has none. The reader
# doesn't apply rule-registry.sh's backstop check for guarded rules, so it
# shows a guarded rule's registry stage as is; check-rule-registry.sh enforces
# that check in CI, so a guarded rule below block without backstops can't land.
#
# It writes no file and makes no network call.
#
# Exit codes:
#   0  printed
#   2  the registry or an input can't be read, jq is missing, or bad usage

set -u
set -o pipefail

PROG=rule-lifecycle

die2() {
    echo "$PROG: $*" >&2
    exit 2
}

usage() {
    echo "usage: $PROG [--registry <file>] figures [--json] [<journal-file>...]" >&2
    exit 2
}

SELF_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) \
    || die2 "cannot find its own directory"
REGISTRY="$SELF_DIR/../references/rule-registry.json"

while [ $# -gt 0 ]; do
    case "$1" in
        --registry)
            [ $# -ge 2 ] || die2 "--registry needs a file"
            REGISTRY=$2; shift 2 ;;
        -*) usage ;;
        *) break ;;
    esac
done
[ $# -ge 1 ] || usage
[ "$1" = figures ] || usage
shift

JSON=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON=1; shift ;;
        --) shift; break ;;
        -?*) usage ;;
        *) break ;;
    esac
done

command -v jq >/dev/null 2>&1 || die2 "jq is required"

[ -f "$REGISTRY" ] && [ -r "$REGISTRY" ] || die2 "cannot read $REGISTRY"
jq -e '.rules | type == "array"' "$REGISTRY" >/dev/null 2>&1 \
    || die2 "$REGISTRY does not parse as a registry"

for f in "$@"; do
    [ -f "$f" ] && [ -r "$f" ] || die2 "cannot read $f"
done

# The one jq program. Input is raw lines; $reg[0] is the registry.
# shellcheck disable=SC2016
PROGRAM='
def isdate: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}");
# Days since 0000-03-01 of a YYYY-MM-DD prefix (the civil-from-days inverse),
# so the window length needs no strptime and no time zone.
def civil:
  (.[0:4] | tonumber) as $y | (.[5:7] | tonumber) as $m | (.[8:10] | tonumber) as $d
  | (if $m <= 2 then $y - 1 else $y end) as $yy
  | (($yy / 400) | floor) as $era
  | ($yy - $era * 400) as $yoe
  | ((((153 * (if $m > 2 then $m - 3 else $m + 9 end)) + 2) / 5 | floor) + $d - 1) as $doy
  | ($yoe * 365 + (($yoe / 4) | floor) - (($yoe / 100) | floor) + $doy) as $doe
  | $era * 146097 + $doe;
def key2(a; b): "\(a)\u0000\(b)";
def count(f): map(select(f)) | length;
# panel-scope.sh --verdict prints every finding at the stage of this rule,
# and a finding that cites another rule is journaled under the cited id. So
# at the gates of this rule (the panel gates) every finding and dispute
# counts for it, whatever koto.rule.id it carries. A cited rule does not count
# it because it lists no panel gate: check-rule-registry.sh refuses a panel
# gate on any entry but this one. The same exception lives in panel-scope.sh
# (rf_emit ... panel/open-finding) and in check-rule-registry.sh
# (ANY_ACTIVE_ALLOWED, PANEL_RULE); change the three together.
def panel_rule: "panel/open-finding";
def for_rule($id): $id == panel_rule or .["koto.rule.id"] == $id;

[inputs | fromjson? | objects | select(.at | isdate)] as $lines
| ($lines | map(.at) | max) as $end
| ($lines | map(select(.kind == "check_evaluated" and has("koto.check.finding_count")))) as $evals_all
| ($lines | map(select(.kind == "check_finding"))) as $finds_all
| ($lines | map(select(.kind == "check_disputed"))) as $disps_all
| $reg[0].rules[]
| select((.check | type) == "object" and .check.kind == "script")
| .id as $id
| (if (.stage | type) == "string" then .stage else "block" end) as $stage
| (if (.stage_since | isdate) then .stage_since[0:10] else null end) as $since
| ([.gates[]? | select(type == "string") | split(":") | select(length == 3)
    | {key: key2(.[1]; .[2]), value: true}] | from_entries) as $gk
| (if $since == null or $end == null then 0
   else ([($end | civil) - ($since | civil), 0] | max) end) as $days
| (if $since == null then [] else
    $evals_all
    | map(select(.at[0:10] >= $since
                 and $gk[key2(.["koto.state"]; .["koto.check"])] == true))
    | unique_by([.["koto.session.id"], .["koto.seq"]])
   end) as $evals
| (if $since == null then {} else
    $finds_all
    | map(select(for_rule($id) and .at[0:10] >= $since
                 and $gk[key2(.["koto.state"]; .["koto.check.name"])] == true))
    | reduce .[] as $f ({};
        .[key2($f["koto.session.id"]; $f["koto.seq"])] += [$f["koto.finding.level"]])
   end) as $fk
| ($evals | map(. + {levels: ($fk[key2(.["koto.session.id"]; .["koto.seq"])] // [])})) as $ev
| ($ev | count(.levels | length > 0)) as $fires
| ($ev | count(.levels | any(.[]; . == "error"))) as $fires_error
| ($ev | count(.levels | any(.[]; . == "warning"))) as $fires_warning
| ($ev | count(.levels | any(.[]; . == "info"))) as $fires_info
| ($ev | count(.["koto.check.findings_truncated"] != true)) as $retire_evals
| ($ev | map(select(.["koto.check.outcome"] == "passed")
             | {key: "\(.["koto.session.id"])\u0000\(.["koto.visit.seq"])\u0000\(.["koto.state"])\u0000\(.["koto.check"])",
                value: true}) | from_entries) as $passed
| ($ev | map(select(.levels | any(.[]; . == "error"))
             | select($passed["\(.["koto.session.id"])\u0000\(.["koto.visit.seq"])\u0000\(.["koto.state"])\u0000\(.["koto.check"])"] != true)
             | key2(.["koto.session.id"]; .["koto.visit.seq"]))
       | unique | length) as $unconverged
| (if $since == null then [] else
    $disps_all
    | map(select(for_rule($id) and .at[0:10] >= $since
                 and $gk[key2(.["koto.state"]; .["koto.check.name"])] == true
                 and has("koto.session.id")
                 and (.["koto.dispute.source"] == "agent" or .["koto.dispute.source"] == "person")))
    | sort_by(.at) | group_by(.["koto.session.id"]) | map(.[0])
   end) as $disps
| ($disps | count(.["koto.dispute.source"] == "agent")) as $d_agent
| ($disps | count(.["koto.dispute.source"] == "person")) as $d_person
| ($d_agent + $d_person) as $disputes
| ($ev | length) as $n
| (if ($stage == "warn" or $stage == "block") and $days >= 7 and $disputes >= 3
        and $fires > 0 and $disputes * 5 > $fires then "demote"
   elif ($stage == "shadow" or $stage == "warn" or $stage == "block")
        and $retire_evals >= 300 and $days >= 56 and $fires == 0 then "retire"
   elif $stage == "shadow" and $n >= 100 and $days >= 14 and $fires >= 1
        and $fires * 4 <= $n then "promote-to-warn"
   elif $stage == "warn" and $n >= 100 and $days >= 14 and $fires >= 5
        and $disputes * 20 <= $fires then "promote-to-block"
   else "hold" end) as $criterion
| {id: $id, stage: $stage, days: $days, evaluations: $n,
   fires_error: $fires_error, fires_warning: $fires_warning, fires_info: $fires_info,
   passes: ($n - $fires), disputes_agent: $d_agent, disputes_person: $d_person,
   unconverged: $unconverged, criterion: $criterion}
| if $json then tojson
  else [.id, .stage, .days, .evaluations, .fires_error, .fires_warning, .fires_info,
        .passes, .disputes_agent, .disputes_person, .unconverged, .criterion] | @tsv
  end
'

if [ -n "$JSON" ]; then json=true; else json=false; fi

if [ $# -gt 0 ]; then
    cat -- "$@" | jq -n -R -r --slurpfile reg "$REGISTRY" --argjson json "$json" "$PROGRAM"
else
    jq -n -R -r --slurpfile reg "$REGISTRY" --argjson json "$json" "$PROGRAM"
fi || die2 "could not read the journal"
exit 0
