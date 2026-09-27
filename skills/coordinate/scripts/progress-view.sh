#!/usr/bin/env bash
# progress-view.sh -- the progress table: the one table the coordinator puts
# on screen for the human in a report, a status message or a surface.
#
# Input is the pick facts, context key coord/pick.json as pick_facts wrote it
# ({units, holdings: [{worker, unit, phase, dispatch_status, parked,
# pull_request}], ...}), from a file or stdin:
#   koto context get <session> coord/pick.json | progress-view.sh [flags]
#
# One table, columns Kind | Unit | Session | PR | Status | Next or needs, with
# four kinds of row in this order:
#   1. Ready to merge   parked holdings (a verified head, the pull request open
#                       and not a draft), in the merge order --merge-order gives
#   2. Blocked on you   holdings --blocked names, with what each needs
#   3. Ongoing          every other holding, its status and what's next
#   4. Waiting to be assigned
#                       units no holding covers and not done, in the order
#                       they'll be assigned as the cap frees: pick's order,
#                       unblocked first
# A cell that doesn't apply reads N/A. A pull request is a clickable link,
# `[#<n>](https://github.com/<owner>/<repo>/pull/<n>)`, never a bare number; a
# session is inline code; no commit hash is shown, and a cell holding a
# hash-shaped word (7 to 40 hex characters with a digit and a letter) is
# refused. A `|` in a cell is escaped and a newline becomes a space.
#
# Flags (the coordinator's judgment; each is checked against the facts):
#   --merge-order T1,T2,...  the ready sessions in merge order: required when
#                            two or more are ready, and must name each exactly
#                            once
#   --blocked T=NEED         a holding blocked on the human and what it needs
#                            (repeatable; a ready session is not blocked)
#   --next KEY=TEXT          what's next for a session or queued unit, keyed
#                            by session name or unit (repeatable)
#
# Exit codes: 0 the table was printed; 65 refused (nothing is printed; stderr
# says why); 64 usage.
set -uo pipefail

PROG=progress-view
usage() { sed -n '/^# Flags/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
IN=/dev/stdin ORDER='' BLOCKED='{}' NEXT='{}'
pair() { # pair <json-object> <KEY=TEXT>: the object with KEY set to TEXT
    case "$2" in *=*) ;; *) usage ;; esac
    [ -n "${2%%=*}" ] || usage
    jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '. + {($k): $v}' <<< "$1"
}
while [ $# -gt 0 ]; do
    case "$1" in
        --merge-order) [ $# -ge 2 ] || usage; ORDER=$2; shift 2 ;;
        --blocked) [ $# -ge 2 ] || usage; BLOCKED=$(pair "$BLOCKED" "$2") || exit 64; shift 2 ;;
        --next) [ $# -ge 2 ] || usage; NEXT=$(pair "$NEXT" "$2") || exit 64; shift 2 ;;
        -*) usage ;;
        *) [ "$IN" = /dev/stdin ] && [ -r "$1" ] || usage; IN=$1; shift ;;
    esac
done

T=$(mktemp "${TMPDIR:-/tmp}/progress-view.XXXXXX")
trap 'rm -f "$T"' EXIT
OUT=$(jq -r --arg order "$ORDER" --argjson blocked "$BLOCKED" --argjson next "$NEXT" '
    def cell: tostring | gsub("\n"; " ") | gsub("\\|"; "\\|");
    def hashy: [scan("(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])")]
        | any(.[]; test("[0-9]") and test("[a-f]"));
    def link($w):
        if . == "" or . == null then "none yet"
        elif (test("^\\[#[0-9]+\\]\\(https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+\\)$")
              and (capture("^\\[#(?<a>[0-9]+)\\]\\(https://github\\.com/[^/]+/[^/]+/pull/(?<b>[0-9]+)\\)$") | .a == .b))
        then .
        else error("\($w): the pull request cell is not a link to one pull request")
        end;
    def code($w): if ($w | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) then "`\($w)`"
        else error("\($w): not a session name") end;
    def row($kind; $unit; $session; $pr; $status; $next):
        [$kind, $unit, $status, $next] as $plain
        | if any($plain[]; tostring | hashy) then error("\($session): a cell holds a commit hash") else . end
        | "| \($kind) | \($unit | cell) | \($session) | \($pr) | \($status | cell) | \($next | cell) |";
    def unitname: if (.title // "") == "" then .unit else "\(.unit): \(.title)" end;

    if (type != "object") or ((.holdings | type) != "array") or ((.units | type) != "array")
    then error("input: not the pick facts") else . end
    | .holdings as $h
    | [$h[] | select(.parked == true)] as $ready
    | ($order | if . == "" then [] else split(",") end) as $o
    | (if ($ready | length) > 1 and ($o | length) == 0 then error("two or more pull requests are ready: --merge-order is required")
       elif ($o | length) > 0 and (($o | sort) != ([$ready[].worker] | sort) or ($o | unique | length) != ($o | length))
       then error("--merge-order must name each ready session exactly once") else . end)
    | (if ($o | length) == 0 then [$ready[].worker] else $o end) as $mo
    | ($blocked | keys) as $bk
    | (if any($bk[]; . as $k | ([$h[].worker] | index($k)) == null) then error("--blocked names a session with no holding")
       elif any($bk[]; . as $k | ([$ready[].worker] | index($k)) != null) then error("--blocked names a ready session")
       else . end)
    | [.units[] | select(.holding == null and (.done | not))] as $free
    | ([$free[] | select(.blocked | not)] + [$free[] | select(.blocked)]) as $queue
    | "| Kind | Unit | Session | PR | Status | Next or needs |",
      "|---|---|---|---|---|---|",
      ($mo | to_entries[] | .key as $i | .value as $w | [$ready[] | select(.worker == $w)][0]
        | row("Ready to merge"; .unit; code($w); (.pull_request | link($w));
              (if .phase == "held" then "verified; merge held by your direction" else "verified, ready to merge" end);
              ($next[$w] // "merge \($i + 1) of \($mo | length)"))),
      ($h[] | select(.worker as $w | $bk | index($w) != null) | .worker as $w
        | row("Blocked on you"; .unit; code($w); (.pull_request | link($w)); "blocked"; $blocked[$w])),
      ($h[] | select((.parked != true) and (.worker as $w | $bk | index($w) == null)) | .worker as $w
        | row("Ongoing"; .unit; code($w); (.pull_request | link($w));
              ({"dispatching": "dispatching", "dispatch-failed": "dispatch failed"}[.dispatch_status]
               // {"scoping-ahead": "scoping ahead", "executing": "executing", "held": "held"}[.phase] // (.phase // "N/A"));
              ($next[$w] // (if .dispatch_status == "dispatch-failed" then "redispatch or escalate"
                             elif .phase == "scoping-ahead" then "its execution is sent when its blocker lands"
                             else "report at its next checkpoint" end)))),
      ($queue | to_entries[] | .key as $i | .value
        | row("Waiting to be assigned"; unitname; "N/A"; "N/A";
              (if .blocked then "waits on \(.blocked_by | map("feature \(.)") | join(", "))" else "ready to assign" end);
              ($next[.unit] // "assigned as the cap frees, \($i + 1) of \($queue | length) in line")))
' "$IN" 2> "$T") || {
    WHY=$(sed -n 's/^jq: error ([^)]*): //p' "$T" | head -1)
    echo "$PROG: refused: ${WHY:-the input is not the pick facts}" >&2; exit 65
}
printf '%s\n' "$OUT"
