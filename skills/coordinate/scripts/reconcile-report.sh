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
#   reconcile-report.sh md   < facts.json    the report rendered as text; md
#                                            also takes a report document,
#                                            which is how the pass renders
#                                            the report it sealed
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
#     source       optional: record|handoff, for a discipline start that
#                  mixes its predecessor's rows with its own
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
#       files      paths[] (the pull request's changed paths, both sides of
#                  a rename), truncated (bool); classified here, see phase
#                  below
#       host       state found|missed|ambiguous, reads (count)
#       inventory  taken (bool), items[] {clone, kind: commit|change|file,
#                  path}, truncated (bool)
#       leg        disposition (open|resolved|abandoned), result: a short
#                  token -- a result map's outcome, or the engine's own
#                  terminal status and final state, or "refused:<reason>"
#   side_effects[] {row: {action, target, verified_head, attempted},
#                   fact: {kind: merge|close|teardown|other,
#                          verdict: confirmed|not_confirmed|not_rechecked,
#                          reason, status, read_at}}
#   deferrals[]    {row: {deferral, reason, raised}, disposed (bool), how,
#                   status: ok|not_verified, reason}; a deferral whose
#                   disposal check failed is not reported either way
#   reasoning      present|absent|not_recorded, or null at roadmap scope
#   unparseable[]  {raw, reason}: rows the reader couldn't parse
#
# Output: coordinate-reconcile-report/v1
#
#   header         {scope, written, reconciled_at, source, handoff_date}
#   changes[]      {topic, what, recorded, live, written, grade}
#   holdings[]     {topic, unit, phase, phase_flag, state, merge_state,
#                   board, leg, next, next_code, source, read_at,
#                   grade: {state, board, leg, phase, next}}
#                  next_code is the token a reader routes on: drop, decide,
#                  fix_ci, land, wait, read_again, refused. source is
#                  record or handoff, per row when a holding carries
#                  `source`, else the document's.
#   waiting[]      {topic, why, grade}
#   nowhere_else[] {topic, why, inventory, grade}
#   side_effects[] {action, target, code, verdict, reason, grade}
#                  code: confirmed, not_confirmed, not_rechecked, or
#                  not_verified when the re-check itself failed
#   deferrals[]    {deferral, reason, raised, grade}: undisposed only
#   reasoning      {status, key} or null
#   not_verified[] {what, reason, raw}
#
# Phase. A row's `phase` value decides it, matched whole and ignoring case:
# "scoping" or "scoping-ahead" is scoping ahead, "executing" is executing.
# An empty `phase` falls back to the entry point and mode: the scoping entry
# point (".../scope"), or a mode carrying `--intent=stop` or `--intent stop`,
# is scoping ahead; anything else is executing. Any other `phase` value is
# not guessed at: the holding is marked executing and the value is listed
# under "not verified". A scoping-ahead holding is flagged when its pull
# request changes a path outside docs/: a path is inside docs/ only when it
# starts with "docs/" exactly, so "docsx/a" is outside.
#
# Grades: "measured" for a value read live (pull request state, branch tip,
# a listing read, an inventory, a leg); "verified by reading" for a
# conclusion drawn by comparing reads (a board judged by its property, a side
# effect confirmed, a deferral's disposal); "inferred" for anything taken
# from the record's text without a live read (a phase mark, a next line, the
# waiting list). A claim whose read failed is graded "not verified", never
# with the grade a successful read would have earned.
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
SCHEMA=$(printf '%s' "$INPUT" | jq -r '.schema? // empty' 2>/dev/null)
case "$MODE:$SCHEMA" in
    *:coordinate-reconcile-facts/v1) ;;
    # md also renders a report the pass already wrote, so the text the agent
    # reads comes from the same bytes the seal covers.
    md:coordinate-reconcile-report/v1) ;;
    *)
        echo "$PROG: input is not a coordinate-reconcile-facts/v1 document" >&2
        exit 65 ;;
esac

# The report, computed once. Everything the rendering prints comes from here.
REPORT_JQ='
def fact($k): (.facts // []) | map(select(.kind == $k)) | .[0];
def ok($f): $f != null and $f.status == "ok";
def safe_path: if type == "string" and startswith("/") then "(absolute path withheld)" else . end;
def topic: .row.worker // "(no worker)";

def phase_key: (.row.phase // "") | ascii_downcase;
def phase_known: phase_key | . == "" or . == "scoping" or . == "scoping-ahead" or . == "executing";
def phase_of:
  phase_key as $p
  | if $p == "scoping" or $p == "scoping-ahead" then "scoping ahead"
    elif $p == "executing" then "executing"
    elif $p != "" then "executing"
    elif ((.row.entry_point // "") | test("(^|:|/)scope$"))
      or ((.row.mode // "") | test("--intent(=| +)stop( |$)")) then "scoping ahead"
    else "executing" end;
def outside_docs: fact("files") as $f | ok($f) and ((($f.paths // []) | map(select(startswith("docs/") | not)) | length) > 0);

def state_of:
  if .refused != null then "refused"
  else fact("pr") as $pr
  | fact("host") as $h
  | if ok($pr) then ($pr.state | ascii_downcase)
    elif ok($h) then ("no pull request; worker " + (if $h.state == "found" then "found"
                      elif $h.state == "ambiguous" then "ambiguous" else "not found on this read" end))
    else "not verified" end
  end;

def leg_of:
  fact("leg") as $l
  | if ok($l) then (($l.disposition // "") + (if ($l.result // "") != "" then ": " + $l.result else "" end)) else null end;
def grade_of($f): if ok($f) then "measured" elif $f == null then null else "not verified" end;

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

# Stable tokens for readers that route on the next line of a holding (the pick
# side counts and routes on these; the prose is for the agent).
def next_code:
  {"drop from holdings": "drop", "decide: re-dispatch or drop": "decide",
   "worker fixes CI": "fix_ci", "ready to land": "land", "wait on worker": "wait",
   "read again, then decide": "read_again", "refused by the record reader": "refused"}[.];

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
        phase_flag: ($ph == "scoping ahead" and outside_docs),
        state: state_of,
        merge_state: (fact("pr") as $pr | if ok($pr) then ($pr.merge_state // null) else null end),
        board: board_of, leg: leg_of, next: next_of, next_code: (next_of | next_code),
        source: (.source // $in.record.source // "record"),
        read_at: ([.facts // [] | .[].read_at // empty] | max),
        grade: {
          state: (fact("pr") as $pr | fact("host") as $h
                  | if .refused != null then "not verified"
                    elif ok($pr) or ok($h) then "measured" else "not verified" end),
          board: (if board_of == null then null else "verified by reading" end),
          leg: grade_of(fact("leg")),
          phase: "inferred", next: "inferred"}
      }],
    nowhere_else: [$in.holdings[]? | select(.refused == null)
      | fact("pr") as $pr | fact("host") as $h | fact("inventory") as $inv
      | fact("appeared") as $ap
      # "No pull request" means the record says none yet and none appeared
      # since. A pull request whose read failed is not that: it is listed
      # under not_verified, and saying "no pull request" here would
      # contradict the state line of the holding.
      | (((.row.pull_request // "") | test("^(none yet|none|)$"; "i"))
         and ((ok($ap) and (($ap.prs // []) | length) > 0) | not)) as $nopr
      | (ok($inv) and (($inv.items // []) | length) > 0) as $unique
      | select($nopr or $unique)
      | {topic: topic,
         why: (if $nopr and ok($h) and $h.state == "missed" then "no pull request; worker not found on this read"
               elif $nopr and ok($h) and $h.state == "ambiguous" then "no pull request; worker ambiguous in the listing"
               elif $nopr then "no pull request" else "unpushed work" end),
         grade: (if ok($inv) then "measured" else "not verified" end),
         inventory: (if ok($inv) and $inv.taken == true then
                       (if (($inv.items // []) | length) == 0 then "nothing unique found"
                        else ([$inv.items[] | "\(.clone // "." | safe_path): \(.kind) \(.path | safe_path)"] | join("; "))
                             + (if $inv.truncated == true then " (truncated)" else "" end) end)
                     else "inventory could not be taken" end)}],
    side_effects: [$in.side_effects[]? | ((.fact.status // "ok") == "ok") as $read
      | {action: (.row.action // ""), target: (.row.target // ""),
        code: (if $read then (.fact.verdict // "not_rechecked") else "not_verified" end),
        verdict: (if $read then (.fact.verdict // "not_rechecked" | gsub("_"; " ")) else "not verified" end),
        reason: (.fact.reason // ""),
        grade: (if ($read | not) then "not verified"
                elif (.fact.verdict // "") == "not_rechecked" then "inferred"
                else "verified by reading" end)}],
    deferrals: [$in.deferrals[]? | select((.status // "ok") == "ok" and .disposed != true)
      | {deferral: (.row.deferral // ""), reason: (.row.reason // ""), raised: (.row.raised // ""), grade: "verified by reading"}],
    reasoning: (if $in.reasoning == null then null
                else {status: $in.reasoning, key: (if $in.reasoning == "present" then "reconcile/reasoning.md" else null end)} end),
    # the report as a whole says which scope the phase marks are counted in
    not_verified: (
      [$in.unparseable[]? | {what: "unparseable record row", reason: (.reason // ""), raw: (.raw // "")}]
      + [$in.holdings[]? | select(.refused != null) | {what: ("holding " + topic), reason: ("refused: " + .refused), raw: null}]
      + [$in.holdings[]? | topic as $t | (.facts // [])[] | select(.status != "ok")
          | {what: ($t + ": " + .kind), reason: (.reason // "read failed"), raw: null}]
      + [$in.holdings[]? | select(phase_known | not)
          | {what: ("holding " + topic + ": phase"), reason: ("unrecognised phase value; marked executing"), raw: null}]
      + [$in.deferrals[]? | select((.status // "ok") != "ok")
          | {what: ("deferral " + (.row.deferral // "")), reason: (.reason // "disposal check failed"), raw: null}]
      + [$in.side_effects[]? | select((.fact.status // "ok") != "ok")
          | {what: ((.row.action // "") + " " + (.row.target // "")), reason: (.fact.reason // "read failed"), raw: null}])
  }
| .waiting = (
    [.holdings[] | select(.next_code == "land" or .next_code == "decide") | {topic, why: .next, grade: "inferred"}]
    + [.side_effects[] | select(.action == "merge" and .code == "not_confirmed") | {topic: .target, why: "merge not confirmed", grade: "inferred"}])
'

if [ "$SCHEMA" = coordinate-reconcile-report/v1 ]; then
    REPORT=$INPUT
else
    # A facts document that passes the schema check but can't be built is
    # malformed input too, so it shares exit 65.
    REPORT=$(printf '%s' "$INPUT" | jq -c "$REPORT_JQ") || { echo "$PROG: could not build the report" >&2; exit 65; }
fi

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
    + "; \(.state) (\(.grade.state))"
    + (if .merge_state != null then ", merge state \(.merge_state)" else "" end)
    + (if .leg != null then "; leg \(.leg) (\(.grade.leg))" else "" end)
    + (if .board != null then "; board \(.board) (\(.grade.board))" else "" end)
    + ". Next: \(.next) (inferred). Read \(.read_at // "not read")"
    + (if .source == "handoff" then "; row as written by the previous rotation" else "" end) + "."]),
section("Waiting on a person"; [.waiting[] | "- \(.topic): \(.why) (\(.grade))."]),
section("Exists nowhere else"; [.nowhere_else[] | "- \(.topic): \(.why); \(.inventory) (\(.grade))."]),
section("Side effects"; [.side_effects[] | "- \(.action) \(.target): \(.verdict)" + (if .reason != "" then " (\(.reason))" else "" end) + " (\(.grade))."]),
section("Undisposed deferrals"; [.deferrals[] | "- \(.deferral) (raised \(.raised)): \(.reason) (\(.grade))."]),
(if .reasoning != null then
  section("Predecessor'"'"'s reasoning";
    [if .reasoning.status == "present" then "The previous rotation'"'"'s reasoning is in \(.reasoning.key), as its view; nothing here re-checked it."
     else "No reasoning was received from the previous rotation." end])
 else empty end),
section("Not verified"; [.not_verified[] | "- \(.what): \(.reason)"
    + (if (.raw // "") != "" then "\n\n  ```\n  \(.raw)\n  ```" else "" end)])
'
