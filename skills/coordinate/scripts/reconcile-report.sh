#!/usr/bin/env bash
# reconcile-report.sh -- turn a reconcile facts document into the reconcile
# report, as JSON or as the text the agent reads.
#
# A pure function. It reads one facts document on stdin and writes one result
# on stdout; it reads no file, calls no network and runs nothing but jq. The
# pass (reconcile-pass.sh) gathers the facts from GitHub and the host and
# calls this twice, once per output form, so the two forms always agree.
#
# Usage:
#   reconcile-report.sh json < facts.json    the report, schema
#                                            coordinate-reconcile-report/v1
#   reconcile-report.sh md   < facts.json    the report rendered as text
#
# Exit codes: 0 written; 64 usage error; 65 the input is not a facts document.
#
# Requires: bash 3.2+, jq.
#
# ---------------------------------------------------------------------------
# Input: coordinate-reconcile-facts/v1
#
#   schema         "coordinate-reconcile-facts/v1"
#   scope          {kind: roadmap|discipline, name, repo}
#   record         {written: <ISO time the record says it was written>,
#                   source: record|handoff, handoff_date: <date>|null}
#   reconciled_at  <ISO time the pass finished>
#   holdings[]     one per Holdings row:
#     row          the record's row keys: unit, entry_point, mode, phase,
#                  dispatch_status, return_path, worker, repo, branch,
#                  verified_head, dispatched, pull_request
#     refused      null, or why the record's reader refused the row (outside
#                  the scope's repositories, head branch differs); a refused
#                  row carries no facts
#     facts[]      {kind, status: ok|not_verified, read_at, reason, ...}:
#       pr         state OPEN|MERGED|CLOSED, draft, head, merge_state
#       board      at (sha), verdict holds|fails, detail (first failing job
#                  or missing run)
#       branch     state present|gone, tip
#       appeared   prs[] {number, url, state}
#       files      outside_docs (bool), truncated (bool)
#       host       state found|missed|ambiguous, reads (count)
#       inventory  taken (bool), items[] {clone, kind: commit|change|file,
#                  path}, truncated (bool)
#       leg        disposition, result
#   side_effects[] {row: {action, target, verified_head, attempted},
#                   fact: {kind: merge|close|teardown|other,
#                          verdict: confirmed|not_confirmed|not_rechecked,
#                          reason, status, read_at}}
#   deferrals[]    {row: {deferral, reason, raised}, disposed (bool), how}
#   reasoning      present|absent|not_recorded, or null at roadmap scope
#   unparseable[]  {raw, reason}: rows the reader couldn't parse
#
# Output: coordinate-reconcile-report/v1
#
#   header         {scope, written, reconciled_at, source, handoff_date}
#   changes[]      {topic, what, recorded, live, written, grade}
#   holdings[]     {topic, unit, phase, phase_flag, state, board, next,
#                   read_at, grade}
#   waiting[]      {topic|target, why}
#   nowhere_else[] {topic, why, inventory}
#   side_effects[] {action, target, verdict, reason, grade}
#   deferrals[]    {deferral, reason, raised}: undisposed only
#   reasoning      {status, key} or null
#   not_verified[] {what, reason, raw}
#
# Grades: "measured" for a value read live (pull request state, branch tip,
# a listing read, an inventory, a leg); "verified by reading" for a
# conclusion drawn by comparing reads (a board judged by its property, a side
# effect confirmed, a deferral's disposal); "inferred" for anything taken
# from the record's text without a live read (a phase mark, a next line).
# ---------------------------------------------------------------------------
set -uo pipefail

PROG=reconcile-report

usage() {
    echo "usage: $PROG json|md < facts.json" >&2
    exit 64
}

[ $# -eq 1 ] || usage
case "$1" in json|md) MODE=$1 ;; *) usage ;; esac

# A builtin read, so the script needs nothing but bash and jq.
INPUT=""
IFS= read -r -d '' INPUT || true
if ! printf '%s' "$INPUT" | jq -e '.schema == "coordinate-reconcile-facts/v1"' >/dev/null 2>&1; then
    echo "$PROG: input is not a coordinate-reconcile-facts/v1 document" >&2
    exit 65
fi

# The report, computed once. Everything the rendering prints comes from here.
REPORT_JQ='
def fact($k): (.facts // []) | map(select(.kind == $k)) | .[0];
def ok($f): $f != null and $f.status == "ok";
def safe_path: if type == "string" and startswith("/") then "(absolute path withheld)" else . end;
def topic: .row.worker // "(no worker)";

def phase_of:
  (.row.phase // "") as $p
  | if $p != "" then
      (if ($p | test("^scop")) then "scoping ahead" else "executing" end)
    elif ((.row.entry_point // "") | test("(^|:|/)scope$"))
      or ((.row.mode // "") | test("--intent=stop")) then "scoping ahead"
    else "executing" end;

def state_of:
  if .refused != null then "refused"
  else fact("pr") as $pr
  | fact("host") as $h
  | if ok($pr) then ($pr.state | ascii_downcase)
    elif ok($h) then ("no pull request; worker " + (if $h.state == "found" then "found"
                      elif $h.state == "ambiguous" then "ambiguous" else "not found on this read" end))
    else "not verified" end
  end;

def board_of:
  [.facts // [] | .[] | select(.kind == "board" and .status == "ok")]
  | if length == 0 then null
    elif any(.[]; .verdict == "fails") then "fails" + (map(select(.verdict == "fails"))[0].detail // "" | if . == "" then "" else ": " + . end)
    else "holds" end;

def next_of:
  fact("pr") as $pr | fact("host") as $h
  | if .refused != null then "refused by the record reader"
    elif ok($pr) then
      (if $pr.state == "MERGED" then "drop from holdings"
       elif $pr.state == "CLOSED" then "decide: re-dispatch or drop"
       elif ((board_of // "") | startswith("fails")) then "worker fixes CI"
       elif (board_of == "holds") and ((.row.verified_head // "") != "")
            and ($pr.head == .row.verified_head) then "ready to land"
       else "wait on worker" end)
    elif ok($h) then
      (if $h.state == "found" then "wait on worker" else "read again, then decide" end)
    else "read again, then decide" end;

def changes_of($written):
  topic as $t | fact("pr") as $pr | fact("branch") as $br | fact("appeared") as $ap
  | [
      (if ok($pr) and $pr.state != "OPEN" then
        {topic: $t, what: "pull request", recorded: "open", live: ($pr.state | ascii_downcase), written: $written, grade: "measured"}
       else empty end),
      (if ok($pr) and $pr.state == "OPEN" and $pr.draft == true and ((.row.verified_head // "") != "") then
        {topic: $t, what: "draft", recorded: "ready (parked)", live: "draft", written: $written, grade: "measured"}
       else empty end),
      (if ok($pr) and ((.row.verified_head // "") != "") and ($pr.head // "") != "" and $pr.head != .row.verified_head then
        {topic: $t, what: "head moved", recorded: .row.verified_head, live: $pr.head, written: $written, grade: "measured"}
       else empty end),
      (if ok($br) and $br.state == "gone" then
        {topic: $t, what: "branch", recorded: (.row.branch // ""), live: "branch gone", written: $written, grade: "measured"}
       elif ok($br) and ok($pr) and ($br.tip // "") != ($pr.head // "") then
        {topic: $t, what: "branch tip differs", recorded: ($pr.head // ""), live: ($br.tip // ""), written: $written, grade: "measured"}
       else empty end),
      (if ok($ap) and (($ap.prs // []) | length) == 1 then
        {topic: $t, what: "pull request appeared", recorded: "none yet", live: ($ap.prs[0].url // ""), written: $written, grade: "measured"}
       elif ok($ap) and (($ap.prs // []) | length) > 1 then
        {topic: $t, what: "pull request ambiguous", recorded: "none yet", live: ([$ap.prs[].url] | join(", ")), written: $written, grade: "measured"}
       else empty end)
    ];

. as $in
| $in.record.written as $w
| {
    schema: "coordinate-reconcile-report/v1",
    header: {scope: (($in.scope.kind // "") + " " + ($in.scope.name // "")), written: $w,
             reconciled_at: $in.reconciled_at, source: ($in.record.source // "record"),
             handoff_date: ($in.record.handoff_date // null)},
    changes: [$in.holdings[]? | select(.refused == null) | changes_of($w)[]],
    holdings: [$in.holdings[]? | phase_of as $ph | {
        topic: topic, unit: (.row.unit // ""), phase: $ph,
        phase_flag: ($ph == "scoping ahead" and (fact("files") as $f | ok($f) and $f.outside_docs == true)),
        state: state_of, board: board_of, next: next_of,
        read_at: ([.facts // [] | .[].read_at // empty] | max),
        grade: {state: "measured", board: "verified by reading", phase: "inferred", next: "inferred"}
      }],
    nowhere_else: [$in.holdings[]? | select(.refused == null)
      | fact("pr") as $pr | fact("host") as $h | fact("inventory") as $inv
      | (ok($pr) | not) as $nopr
      | (ok($inv) and (($inv.items // []) | length) > 0) as $unique
      | select($nopr or $unique)
      | {topic: topic,
         why: (if $nopr and ok($h) and $h.state != "found" then "no pull request; worker not found on this read"
               elif $nopr then "no pull request" else "unpushed work" end),
         inventory: (if ok($inv) and $inv.taken == true then
                       (if (($inv.items // []) | length) == 0 then "nothing unique found"
                        else ([$inv.items[] | "\(.clone // "."): \(.kind) \(.path | safe_path)"] | join("; "))
                             + (if $inv.truncated == true then " (truncated)" else "" end) end)
                     else "inventory could not be taken" end)}],
    side_effects: [$in.side_effects[]? | {action: (.row.action // ""), target: (.row.target // ""),
        verdict: (.fact.verdict // "not_rechecked" | gsub("_"; " ")),
        reason: (.fact.reason // ""),
        grade: (if (.fact.verdict // "") == "not_rechecked" then "inferred" else "verified by reading" end)}],
    deferrals: [$in.deferrals[]? | select(.disposed != true) | {deferral: (.row.deferral // ""), reason: (.row.reason // ""), raised: (.row.raised // "")}],
    reasoning: (if $in.reasoning == null then null
                else {status: $in.reasoning, key: (if $in.reasoning == "present" then "reconcile/reasoning.md" else null end)} end),
    not_verified: (
      [$in.unparseable[]? | {what: "unparseable record row", reason: (.reason // ""), raw: (.raw // "")}]
      + [$in.holdings[]? | select(.refused != null) | {what: ("holding " + topic), reason: ("refused: " + .refused), raw: null}]
      + [$in.holdings[]? | topic as $t | (.facts // [])[] | select(.status != "ok")
          | {what: ($t + ": " + .kind), reason: (.reason // "read failed"), raw: null}]
      + [$in.side_effects[]? | select((.fact.status // "ok") != "ok")
          | {what: ((.row.action // "") + " " + (.row.target // "")), reason: (.fact.reason // "read failed"), raw: null}])
  }
| .waiting = (
    [.holdings[] | select(.next == "ready to land" or .next == "decide: re-dispatch or drop") | {topic, why: .next}]
    + [.side_effects[] | select(.action == "merge" and .verdict == "not confirmed") | {topic: .target, why: "merge not confirmed"}])
'

REPORT=$(printf '%s' "$INPUT" | jq -c "$REPORT_JQ") || { echo "$PROG: could not build the report" >&2; exit 65; }

if [ "$MODE" = json ]; then
    printf '%s\n' "$REPORT"
    exit 0
fi

# The rendering. Section order is fixed; an empty section reads "None.".
printf '%s' "$REPORT" | jq -r '
def section($title; $lines): "## " + $title, (if ($lines | length) == 0 then "None." else $lines[] end), "";
"# Reconcile report",
"",
"Scope: \(.header.scope). Record written \(.header.written); reconciled \(.header.reconciled_at)."
  + (if .header.source == "handoff" then " Rows as written by the previous rotation on \(.header.handoff_date)." else "" end),
"",
section("Changed since then"; [.changes[] | "- \(.topic): \(.what): record said \(.recorded), now \(.live) (written \(.written); \(.grade))."]),
section("Holding"; [.holdings[] | "- \(.topic) (\(.unit)): \(.phase)"
    + (if .phase_flag then ", but its pull request changes paths outside docs/" else "" end)
    + "; \(.state)" + (if .board != null then "; board \(.board)" else "" end)
    + ". Next: \(.next). Read \(.read_at // "not read")."]),
section("Waiting on a person"; [.waiting[] | "- \(.topic): \(.why)."]),
section("Exists nowhere else"; [.nowhere_else[] | "- \(.topic): \(.why); \(.inventory)."]),
section("Side effects"; [.side_effects[] | "- \(.action) \(.target): \(.verdict)" + (if .reason != "" then " (\(.reason))" else "" end) + " (\(.grade))."]),
section("Undisposed deferrals"; [.deferrals[] | "- \(.deferral) (raised \(.raised)): \(.reason)."]),
(if .reasoning != null then
  section("Predecessor'"'"'s reasoning";
    [if .reasoning.status == "present" then "The previous rotation'"'"'s reasoning is in reconcile/reasoning.md, as its view; nothing here re-checked it."
     else "No reasoning was received from the previous rotation." end])
 else empty end),
section("Not verified"; [.not_verified[] | "- \(.what): \(.reason)"
    + (if (.raw // "") != "" then "\n\n  ```\n  \(.raw)\n  ```" else "" end)])
'
