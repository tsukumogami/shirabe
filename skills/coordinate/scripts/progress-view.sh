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
#   2. Blocked on you   holdings --blocked names, with what each needs; then
#                       each decision entry escalated to a person: its
#                       question, status `decide`, and "recommended: <option>,
#                       because <reason>", refused when either is empty
#   3. Ongoing          every other holding, its status and what's next; then
#                       each entry escalated to a coordinator ("with `<topic>`
#                       for a decision") and each proposed or unjudged entry
#                       ("with me for a verdict", and when held, what it waits
#                       on). A decision reaches "Blocked on you" only from an
#                       escalated entry, never from a flag
#   4. Waiting to be assigned
#                       units no holding covers and not done, in the order
#                       they'll be assigned as the cap frees: pick's order,
#                       unblocked first. A unit parked on a decision reads
#                       `waits on decision <n>`, and one whose scoping alone
#                       landed names that pull request and its execution
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
#                            (repeatable; a ready session is not blocked), one
#                            of: credential <name>, reserved-step
#                            <merge|release|close|teardown> <pull request or
#                            issue link>, access <owner/repo>. The cell is
#                            worded from the kind; anything else is refused
#   --next KEY=TEXT          what's next for a session or queued unit, keyed
#                            by session name or unit (repeatable); refused
#                            when it reads as a decision (phrasing-lib.sh)
#
# The decision rows come from the facts' `decisions`, the record's unsettled
# entries that pick-facts.sh adds.
#
# The pauses come from the facts' `pauses` (pause-read.sh, through
# pick-facts.sh). When any stands, one line goes above the table, `Paused:`
# and a clause per pause: its id and scope, since when, until what, who set
# it and who relayed it, and `met, to end` for one whose condition is met
# but whose row the coordinator hasn't ended. A holding a pause holds reads
# `paused (<id>)` in its Status cell (a ready one `verified; held by pause
# <id>`), and a queued unit's Next cell reads `held by pause <id>`. The
# table keeps its columns and kinds (docs/designs/current/DESIGN-coordinate-paused-state.md,
# Decision 5).
#
# Exit codes: 0 the table was printed; 65 refused (nothing is printed; stderr
# says why); 64 usage.
set -uo pipefail

PROG=progress-view
HERE=$(cd "$(dirname "$0")" && pwd)
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
. "$HERE/phrasing-lib.sh"
refuse() { echo "$PROG: refused: $*" >&2; exit 65; }
# not_a_decision <what> <text>: the phrasing list's backstop on free text.
not_a_decision() {
    phrase_match decision "$2"
    case $? in 0) refuse "$1 reads as a decision; raise it as a decision entry instead" ;; 1) ;; *) refuse "the phrasing list can't be read" ;; esac
}
# A need is one of the closed kinds, worded here for its cell, so there is
# no free sentence left to put a decision in.
RE_NAME='^[A-Za-z0-9][A-Za-z0-9_.-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_DOTS='(^|/)\.\.?(/|$)'
RE_LINK='^(https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(pull|issues)/[1-9][0-9]*|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*|#[1-9][0-9]*)$'
WORDED='{}'
while IFS= read -r k; do
    [ -n "$k" ] || continue
    NEED=$(jq -r --arg k "$k" '.[$k]' <<< "$BLOCKED")
    case "$NEED" in *$'\n'*|*$'\r'*) refuse "$k: a need is one line" ;; esac
    set -f; set -- $NEED; set +f
    case "${1-}" in
        credential) [ $# -eq 2 ] && [[ $2 =~ $RE_NAME ]] || refuse "$k: credential takes one name"
            CELL="credential: $2" ARG=$2 ;;
        reserved-step) [ $# -eq 3 ] || refuse "$k: reserved-step takes a step and a link"
            case "$2" in merge|release|close|teardown) ;; *) refuse "$k: reserved-step is merge, release, close or teardown" ;; esac
            [[ $3 =~ $RE_LINK ]] || refuse "$k: reserved-step names a pull request or an issue"
            CELL="$2 $3, reserved for a person" ARG="$2 $3" ;;
        access) [ $# -eq 2 ] && [[ $2 =~ $RE_REPO ]] && ! [[ $2 =~ $RE_DOTS ]] || refuse "$k: access takes one owner/repo"
            CELL="access to $2" ARG=$2 ;;
        *) refuse "$k: a need is credential <name>, reserved-step <step> <link> or access <owner/repo>; a decision is raised as an entry" ;;
    esac
    # The list's patterns are phrases: read the token's separators as spaces.
    not_a_decision "$k's need" "$(printf '%s' "$ARG" | tr '_.-' '   ')"
    WORDED=$(jq -c --arg k "$k" --arg v "$CELL" '. + {($k): $v}' <<< "$WORDED")
done < <(jq -r 'keys[]' <<< "$BLOCKED")
BLOCKED=$WORDED
while IFS= read -r k; do
    [ -n "$k" ] || continue
    not_a_decision "--next for $k" "$(jq -r --arg k "$k" '.[$k]' <<< "$NEXT")"
done < <(jq -r 'keys[]' <<< "$NEXT")
OUT=$(jq -r -L "$HERE" --arg order "$ORDER" --argjson blocked "$BLOCKED" --argjson next "$NEXT" '
    include "record-codec";
    def cell: tostring | gsub("\n"; " ") | gsub("\\|"; "\\|");
    def hashy: [scan("(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])")]
        | any(.[]; test("[0-9]") and test("[a-f]"));
    def link($w):
        if . == "" or . == null then "none yet"
        elif ([pr_link] | length) > 0 then .
        else error("\($w): the pull request cell is not a link to one pull request")
        end;
    def code($w): if ($w | test(re_topic)) then "`\($w)`"
        else error("\($w): not a session name") end;
    def row($kind; $unit; $session; $pr; $status; $next):
        [$kind, $unit, $status, $next] as $plain
        | if any($plain[]; tostring | hashy) then error("\($session): a cell holds a commit hash") else . end
        | "| \($kind) | \($unit | cell) | \($session) | \($pr) | \($status | cell) | \($next | cell) |";
    def unitname: if (.title // "") == "" then .unit else "\(.unit): \(.title)" end;
    def stamp: sub("T"; " ") | sub("Z$"; " UTC");
    def until_words: if . == "lifted" then "until a person resumes it"
        elif startswith("time ") then "until \(.[5:] | stamp)"
        elif startswith("merged ") then "until \(.[7:]) merges"
        elif startswith("tag ") then (split(" ") | "until \(.[1]) is tagged \(.[2])")
        else "until \(.)" end;
    def pause_clause: "\(.standing) on \(.on), since \(.set | stamp), \(.until | until_words) (\(.owner)"
        + (if (.relayed_by // "") == "" then "" else ", relayed by \(.relayed_by)" end) + ")"
        + (if .state == "met" then ", met, to end" elif .state == "unreadable" then ", its condition unreadable, held" else "" end);

    if (type != "object") or ((.holdings | type) != "array") or ((.units | type) != "array")
    then error("input: not the pick facts") else . end
    | .holdings as $h
    | (.decisions // []) as $dec
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
    | (.pauses // []) as $pz
    | (if ($pz | length) > 0 then "Paused: " + ([$pz[] | pause_clause] | join("; ")), "" else empty end),
      "| Kind | Unit | Session | PR | Status | Next or needs |",
      "|---|---|---|---|---|---|",
      ($mo | to_entries[] | .key as $i | .value as $w | [$ready[] | select(.worker == $w)][0]
        | row("Ready to merge"; .unit; code($w); (.pull_request | link($w));
              (if (.paused // null) != null then "verified; held by pause \(.paused)"
               elif .phase == "held" then "verified; merge held by your direction" else "verified, ready to merge" end);
              ($next[$w] // "merge \($i + 1) of \($mo | length)"))),
      ($h[] | select(.worker as $w | $bk | index($w) != null) | .worker as $w
        | row("Blocked on you"; .unit; code($w); (.pull_request | link($w)); "blocked"; $blocked[$w])),
      ($dec[] | select(.state == "escalated" and .target == "a person")
        | if ((.recommendation // "") | test("^\\s*$")) or ((.reason // "") | test("^\\s*$"))
          then error("decision \(.decision): a decision row needs its recommendation and reason") else . end
        | row("Blocked on you"; .question; "N/A"; "N/A"; "decide"; "recommended: \(.recommendation), because \(.reason)")),
      ($h[] | select((.parked != true) and (.worker as $w | $bk | index($w) == null)) | .worker as $w
        | row("Ongoing"; .unit; code($w); (.pull_request | link($w));
              ({"dispatching": "dispatching", "dispatch-failed": "dispatch failed"}[.dispatch_status]
               // (if .merged == true then "merged" else null end)
               // (if (.paused // null) != null then "paused (\(.paused))" else null end)
               // {"scoping": "scoping", "scoping-ahead": "scoping ahead", "executing": "executing", "held": "held"}[.phase] // (.phase // "N/A"));
              ($next[$w] // (if .dispatch_status == "dispatch-failed" then "redispatch or escalate"
                             elif .merged == true then "tear down its worker"
                             elif .phase == "scoping-ahead" then "its execution is sent when its blocker lands"
                             else "report at its next checkpoint" end)))),
      # Decisions nobody but a coordinator is asked: the reader is asked nothing.
      ($dec[] | select(.state == "escalated" and .target != "a person")
        | row("Ongoing"; .question; "N/A"; "N/A"; "with `\(.target | sub("^coordinator "; ""))` for a decision"; "N/A")),
      ($dec[] | select(.state == "proposed" or .state == "coordinator-verdict")
        | row("Ongoing"; .question; "N/A"; "N/A";
              (if .verdict == "hold" then "with me for a verdict, waiting on \(.reason)" else "with me for a verdict" end); "N/A")),
      ($queue | to_entries[] | .key as $i | .value
        | row("Waiting to be assigned"; unitname; "N/A"; "N/A";
              (if .blocked then "waits on \(.blocked_by | map("feature \(.)") | join(", "))"
               elif (.awaiting // null) != null then "waits on decision \(.awaiting)"
               elif (.follow_up // null) != null then "scoping landed in \(.follow_up.after)"
               else "ready to assign" end);
              ($next[.unit] // (if (.paused // null) != null then "held by pause \(.paused)"
                                elif (.awaiting // null) != null then "parked until the decision is settled"
                                elif (.follow_up // null) != null then "its execution: \(.follow_up.next)"
                                else "assigned as the cap frees, \($i + 1) of \($queue | length) in line" end))))
' "$IN" 2> "$T") || {
    WHY=$(sed -n 's/^jq: error ([^)]*): //p' "$T" | head -1)
    echo "$PROG: refused: ${WHY:-the input is not the pick facts}" >&2; exit 65
}
printf '%s\n' "$OUT"
