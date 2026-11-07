#!/usr/bin/env bash
# alignment-read.sh -- what a director's run recorded and what merged in its
# lanes: every alignment call, the merges owed one and whether each was
# reviewed, the recommendations, the `align-` holds, the open lane pull
# requests with the call standing for each live head, the gate's refusals and
# the lineage sessions it couldn't read
# (docs/designs/DESIGN-director-alignment-review.md, Decision 4 and Key
# Interfaces). Read-only: it writes nothing to the record, any session or
# GitHub, and prints one JSON object or nothing.
#
# Usage:
#   alignment-read.sh --session S [--since <YYYY-MM-DDTHH:MM:SSZ>]
#
# The session gives the scope, name and host (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts).
#
# It prints, on stdout, one object with exactly these keys:
#
#   calls            every `alignment` entry, oldest first, as {entry, stamp,
#                    pull_request, head, call, read, sources, reason, evidence,
#                    follow_ups, action, standing}: entry the entry's number,
#                    the next three from its first line, the rest from its
#                    lines, each split once on `: `. sources, evidence and
#                    follow_ups are arrays, the line split on `; `, [] for
#                    `none`. standing is true only for the latest call on its
#                    pull request and head, so a call on an older head never
#                    stands for a newer one.
#   merges           each merged lane pull request owed a call, and each a
#                    `worker=` line names, as {pull_request, merged_head,
#                    merged_at, call, review} (below), by merge time
#   recommendations  each call whose Action is `recommend`, the call as listed
#                    in calls
#   holds            each `align-` hold in the record, as {hold, pull_request,
#                    placed_head, call_entry, reason, state, needs_re_read,
#                    report} (below)
#   open             each open lane pull request, as {pull_request, head,
#                    call}: head its live head, call the standing call's value
#                    for that head or "none"
#   refusals         how many refusal entries the record holds: `entry`
#                    entries whose first line is `Refused: no-alignment-call
#                    <owner/repo#n> at <40-hex head>`
#   gaps             the names of the lineage's earlier sessions whose log
#                    couldn't be read
#
# With --since, calls, merges, recommendations and refusals hold only what is
# stamped or merged after it; holds and open stay whole, and every judgment
# below is made against every call, event and merge, not the window's.
#
# The lineage is the session and the runs it continues, walked back through
# state-read.sh --predecessors; a predecessor whose log can't be read is
# listed in gaps, and the walk doesn't go past it. The calls and refusals are
# the session's own entries (a carry copies a predecessor's). The events are
# the `wait` evidence whose event is `report` or `progress`, from every
# session of the lineage, each read with coord-log.sh evidence. Of each event
# it reads the `unit`, the `pull_request`, every github.com pull request link
# in its `report`, and, from the result block of that report (the last
# `=== RESULT ===` line through the next `=== END RESULT ===`, each line
# trimmed, as coord-log.sh result-line reads it), only these lines:
#
#   unit=<topic> <done|reopened|dropped> <owner/repo#n>
#   open=<owner/repo#n>
#   worker=<owner/repo#n>
#
# A line of any other shape counts for nothing, and no other text of a report
# decides anything except the hold report below.
#
# The lane pull requests are every pull request a call names, every pull
# request a Holdings row's Pull request cell links, every pull request an
# `align-` hold is on, and every pull request an event names as its
# `pull_request`, as a link in its report, or in a `unit=`, `open=` or
# `worker=` line. An event's are kept to the host and the Holdings rows'
# repositories, since a message may name anything; the record's are taken as
# they stand, since a call was admitted when it was written. Each is read on
# GitHub once: its state, merge time, live (or merged) head and head branch,
# and a merged one's changed files. Lists are ordered by repository and
# number where nothing else orders them.
#
# A merged lane pull request:
#   is a worker's when a `worker=` line names it;
#   is manager-authored when it isn't a worker's and either an event whose
#     unit is a Holdings row's Worker named it as its `pull_request`, or a
#     Holdings row's Verified head is its merged head (a confirmed merge
#     clears the row's Pull request cell and keeps that head);
#   finishes a unit when a `unit=` line names it, it is a milestone verdict
#     pull request (its head branch starts `coordinate/roadmap-verdict-` in
#     the host, or a milestone-done or milestone-verdict Side effects row
#     names it), or it changes a roadmap or strategy document
#     (docs/roadmaps/.../ROADMAP-<name>.md, docs/strategies/.../STRATEGY-<name>.md).
# It is owed a call when it is manager-authored or finishes a unit. Its
# review is `reviewed` when a call for its merged head was stamped at or
# before the merge; otherwise, when it is owed a call, `after merge` when a
# call for that head came later and `unreviewed` when none exists; and a
# worker's pull request that finishes no unit is `manager-reviewed`. call is
# the latest call's value for the merged head, or "none".
#
# A hold's call_entry and reason are the latest `diverges` call at the head
# its name carries (the call the guarded lift keys it to), null when there is
# none. Its state: `lifted` when its Lifted cell is filled; otherwise `merged
# while held` or `closed while held` from GitHub; `releasable` when the
# guarded lift's three conditions hold (the live head isn't the placed-on
# head, the latest call for the live head is `fits` or `fits with
# follow-ups`, and its entry number is above call_entry); otherwise
# `standing`, with needs_re_read true when the live head has no call. A
# standing or releasable hold's report is the latest event whose report names
# the hold as a whole word, {session, seq, timestamp, unit}, or "unconfirmed"
# when none does; any other hold's is null.
#
# Exit codes: 0 printed; 2 a read failed (the record, its entries, the
# session's own log, a lineage link, or a lane pull request on GitHub), with
# nothing on stdout; 10 refused (no found record); 64 usage.
#
# GitHub reads: gh pr view <n> --repo R --json state,mergedAt,headRefOid,headRefName;
# gh api --method GET "repos/R/pulls/<n>/files?per_page=100" --paginate (a
# merged one). koto reads: the record (state-read.sh), its entries
# (state-entry.sh --list), each lineage session's predecessors
# (state-read.sh --predecessors) and log (coord-log.sh evidence).
set -uo pipefail

PROG=alignment-read
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= SINCE=

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --since) [ $# -ge 2 ] || usage; SINCE=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
if [ -n "$SINCE" ]; then
    [[ $SINCE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
        || { echo "$PROG: --since is a stamp, YYYY-MM-DDTHH:MM:SSZ" >&2; exit 64; }
fi

. "$HERE/state-common.sh"
lib_facts
lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

T=$(mktemp -d "${TMPDIR:-/tmp}/alignment-read.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

# ---- the record and its entries ---------------------------------------------
rs_record "$T/rec.json" "holdings holds side_effects"
case $? in
    0) ;;
    *) lib_die2 "cannot read the record in $(lib_record_name): $(lib_scrub < "$T/rec.json.err" | head -1)" ;;
esac
bash "$HERE/state-entry.sh" --session "$SESSION" --list > "$T/entries.json" 2> "$T/entries.err" \
    || lib_die2 "cannot list the entries: $(lib_scrub < "$T/entries.err" | head -1)"
jq -e 'type == "array"' "$T/entries.json" > /dev/null 2>&1 || lib_die2 "the entries are not a JSON array"

# ---- the lineage and its events ---------------------------------------------
# events_of <session>: append every report and progress event of <session>'s
# log to $T/events.jsonl, newest first, each tagged with the session; a log
# that fails part way adds none of its events. Returns 0 read, 2 the log
# couldn't be read.
events_of() {
    local out before= rc
    : > "$T/session-events.jsonl"
    while :; do
        if [ -n "$before" ]; then
            out=$(bash "$HERE/coord-log.sh" evidence --session "$1" --state wait --where 'event=report|progress' --before "$before" 2> /dev/null)
        else
            out=$(bash "$HERE/coord-log.sh" evidence --session "$1" --state wait --where 'event=report|progress' 2> /dev/null)
        fi
        rc=$?
        case $rc in 0) ;; 1) break ;; *) return 2 ;; esac
        printf '%s' "$out" | jq -c --arg s "$1" '. + {session: $s}' >> "$T/session-events.jsonl" 2> /dev/null || return 2
        before=$(printf '%s' "$out" | jq -r '.seq' 2> /dev/null)
        [[ $before =~ $RE_NUM ]] || return 2
    done
    cat "$T/session-events.jsonl" >> "$T/events.jsonl"
}
: > "$T/events.jsonl"
: > "$T/gaps"
events_of "$SESSION" || lib_die2 "cannot read the session log"
QUEUE=("$SESSION") SEEN=" $SESSION " I=0
while [ "$I" -lt "${#QUEUE[@]}" ] && [ "$I" -lt 256 ]; do
    M=${QUEUE[$I]}
    I=$((I + 1))
    bash "$HERE/state-read.sh" --predecessors --session "$M" > "$T/preds" 2> "$T/preds.err" \
        || lib_die2 "cannot read the runs $M continues: $(lib_scrub < "$T/preds.err" | head -1)"
    while IFS= read -r P; do
        [[ $P =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
        case "$SEEN" in *" $P "*) continue ;; esac
        SEEN="$SEEN$P "
        if events_of "$P"; then
            QUEUE+=("$P")
        else
            printf '%s\n' "$P" >> "$T/gaps"
        fi
    done < "$T/preds"
done
jq -R -s -c 'split("\n") | map(select(. != ""))' "$T/gaps" > "$T/gaps.json" || lib_die2 "jq failed"

JQ_DEFS='
def lc: ascii_downcase;
def ref_re: "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*";
def prref: if type != "string" then null else (sub("^\\s+"; "") | sub("\\s+$"; "")) as $s
    | ([($s | capture("^https://github\\.com/(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?<n>[1-9][0-9]*)/?$")),
        ($s | capture("^(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#(?<n>[1-9][0-9]*)$"))][0])
    | if . == null then null else "\(.r)#\(.n)" end end;
def trim: sub("^[ \t]+"; "") | sub("[ \t\r]+$"; "");
def block: (split("\n") | map(trim)) as $l
    | ([range(0; $l | length) | select($l[.] == "=== RESULT ===")] | last) as $o
    | if $o == null then [] else
        ([range($o + 1; $l | length) | select($l[.] == "=== END RESULT ===")] | first) as $c
        | if $c == null then [] else $l[$o + 1:$c] end end;
def items: if . == "none" then [] else split("; ") end;
def prkey: .pull_request | [(split("#")[0] | lc), (split("#")[1] | tonumber)];
'

# The events, oldest first: {session, seq, timestamp, unit, pr, links, units,
# opens, workers, report}.
jq -s -c "$JQ_DEFS"'
    sort_by(.timestamp // "", .seq)
    | map((.fields // {}) as $f
        | (($f.report // "") | if type == "string" then . else tostring end) as $text
        | ($text | block) as $b
        | {session, seq, timestamp: (.timestamp // ""), unit: (($f.unit // "") | tostring), pr: ($f.pull_request | prref),
           links: [$text | scan("https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*") | prref],
           units: [$b[] | select(startswith("unit=")) | ltrimstr("unit=")
                   | capture("^(?<topic>[A-Za-z0-9][A-Za-z0-9._-]*) (?<status>done|reopened|dropped) (?<pr>" + ref_re + ")$")],
           opens: [$b[] | select(startswith("open=")) | ltrimstr("open=") | select(test("^" + ref_re + "$"))],
           workers: [$b[] | select(startswith("worker=")) | ltrimstr("worker=") | select(test("^" + ref_re + "$"))],
           report: $text})' "$T/events.jsonl" > "$T/events.json" || lib_die2 "the session log's evidence is not JSON"

# The calls, oldest first, and the refusal entries' stamps.
jq -c "$JQ_DEFS"'
    sort_by(.id)
    | [.[] | select(.kind == "alignment") | (.text | split("\n")) as $l
        | ($l[0] | capture("^Alignment: (?<pr>" + ref_re + ") at (?<head>[0-9a-f]{40}) -- (?<call>fits|fits with follow-ups|diverges)$")) as $f
        | select($f != null)
        | (reduce $l[1:][] as $x ({}; ($x | index(": ")) as $i | if $i == null then . else .[$x[0:$i]] = $x[$i + 2:] end)) as $v
        | {entry: .id, stamp, pull_request: $f.pr, head: $f.head, call: $f.call, read: ($v.Read // ""),
           sources: (($v.Sources // "none") | items), reason: ($v.Reason // ""), evidence: (($v.Evidence // "none") | items),
           follow_ups: (($v["Follow-ups"] // "none") | items), action: ($v.Action // "")}]
    | . as $c
    | map(. as $x | .standing = ([$c[] | select((.pull_request | lc) == ($x.pull_request | lc) and .head == $x.head) | .entry] | max) == $x.entry)' \
    "$T/entries.json" > "$T/calls.json" || lib_die2 "the entries are not JSON"
jq -c '[.[] | select(.kind == "entry" and ((.text | split("\n")[0])
    | test("^Refused: no-alignment-call [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]* at [0-9a-f]{40}$"))) | .stamp]' \
    "$T/entries.json" > "$T/refusals.json" || lib_die2 "the entries are not JSON"

# ---- the lane pull requests on GitHub ---------------------------------------
jq -r -L "$HERE" --arg host "$REPO" --slurpfile c "$T/calls.json" --slurpfile e "$T/events.json" 'include "state-schema";
    def refs: map(select(type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$")));
    ([$host | ascii_downcase] + [(.holdings // [])[] | .repo | ascii_downcase]) as $scope
    | ([$c[0][].pull_request]
       + [(.holdings // [])[] | (.pull_request // "" | pr_link) | "\(.repo)#\(.number)"]
       + [(.holds // [])[] | select(.hold | startswith("align-")) | .on] | refs)
      + ([$e[0][] | (.pr // empty), .links[], (.units[] | .pr), .opens[], .workers[]] | refs
         | map(select((split("#")[0] | ascii_downcase) as $r | $scope | index([$r]) != null)))
    | unique_by(ascii_downcase) | .[]' "$T/rec.json" > "$T/lane" || lib_die2 "jq failed"
: > "$T/prs.jsonl"
while IFS= read -r REF; do
    R=${REF%#*} N=${REF##*#}
    gh pr view "$N" --repo "$R" --json state,mergedAt,headRefOid,headRefName > "$T/pr.json" 2> "$T/gh.err" < /dev/null \
        || lib_die2 "cannot read $REF on GitHub: $(lib_scrub < "$T/gh.err")"
    ST=$(jq -r '.state // ""' "$T/pr.json" 2> /dev/null)
    case "$ST" in OPEN|CLOSED|MERGED) ;; *) lib_die2 "$REF's state reads [$ST]" ;; esac
    jq -r '.headRefOid // ""' "$T/pr.json" | grep -Eq '^[0-9a-f]{40}$' || lib_die2 "$REF's head isn't 40 hex"
    echo '[]' > "$T/files.json"
    if [ "$ST" = MERGED ]; then
        jq -r '.mergedAt // ""' "$T/pr.json" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$' \
            || lib_die2 "$REF merged at no time GitHub gives"
        gh api --method GET "repos/$R/pulls/$N/files?per_page=100" --paginate --jq '.[].filename' > "$T/files" 2> "$T/gh.err" < /dev/null \
            || lib_die2 "cannot read $REF's changed files: $(lib_scrub < "$T/gh.err")"
        jq -R -s -c 'split("\n") | map(select(. != ""))' "$T/files" > "$T/files.json" || lib_die2 "jq failed"
    fi
    jq -c --arg k "$REF" --slurpfile f "$T/files.json" '{key: ($k | ascii_downcase), value: {ref: $k, state,
        merged_at: ((.mergedAt // "") | sub("\\.[0-9]+Z$"; "Z")), head: .headRefOid, branch: (.headRefName // ""), files: $f[0]}}' \
        "$T/pr.json" >> "$T/prs.jsonl" || lib_die2 "$REF's facts are not JSON"
done < "$T/lane"
jq -s -c 'from_entries' "$T/prs.jsonl" > "$T/prs.json" || lib_die2 "jq failed"

# ---- the read ----------------------------------------------------------------
jq -c -L "$HERE" --arg host "$REPO" --arg since "$SINCE" \
    --slurpfile c "$T/calls.json" --slurpfile e "$T/events.json" --slurpfile p "$T/prs.json" \
    --slurpfile rf "$T/refusals.json" --slurpfile g "$T/gaps.json" 'include "state-schema"; '"$JQ_DEFS"'
    def after: $since == "" or . > $since;
    def wordin($t): . as $n | $t | test("(^|[^A-Za-z0-9_-])" + ($n | gsub("(?<x>[.*+?^${}()|\\[\\]\\\\/-])"; "\\\(.x)")) + "($|[^A-Za-z0-9_-])");
    $c[0] as $C | $e[0] as $E | $p[0] as $P | . as $rec
    | def calls_at($k; $h): [$C[] | select((.pull_request | lc) == $k and .head == $h)];
    ([$rec.holdings[]? | .worker]) as $topics
    | ([$rec.holdings[]? | .verified_head // "" | select(. != "")]) as $verified
    | ([$E[] | .workers[] | lc] | unique) as $workers
    | ([$E[] | .units[] | .pr | lc] | unique) as $finished
    | ([$E[] | select(.pr != null and (.unit as $u | $topics | index([$u]) != null)) | .pr | lc] | unique) as $mgr_named
    | ([pending_rows[] | select(.action == "milestone-done" or .action == "milestone-verdict")
        | .pull_request | pr_link | "\(.repo)#\(.number)" | lc]) as $verdict_rows
    | ([$P | to_entries[] | .key as $k | .value | select(.state == "MERGED") | . as $pr
        | (($workers | index([$k])) != null) as $worker
        | ((($worker | not) and (($mgr_named | index([$k])) != null or ($verified | index([$pr.head])) != null))) as $mgr
        | ((($finished | index([$k])) != null)
            or (($pr.branch | startswith("coordinate/roadmap-verdict-")) and ($k | split("#")[0]) == ($host | lc))
            or (($verdict_rows | index([$k])) != null)
            or any($pr.files[]; test("^docs/roadmaps/([A-Za-z0-9._-]+/)*ROADMAP-[A-Za-z0-9._-]+\\.md$")
                or test("^docs/strategies/([A-Za-z0-9._-]+/)*STRATEGY-[A-Za-z0-9._-]+\\.md$"))) as $fin
        | select($mgr or $fin or $worker)
        | calls_at($k; $pr.head) as $at
        | {pull_request: $pr.ref, merged_head: $pr.head, merged_at: $pr.merged_at,
           call: (($at | last | .call) // "none"),
           review: (if any($at[]; .stamp <= $pr.merged_at) then "reviewed"
                    elif ($mgr or $fin) then (if ($at | length) > 0 then "after merge" else "unreviewed" end)
                    else "manager-reviewed" end)}]
      | sort_by(.merged_at, prkey)) as $merges
    | ([$rec.holds[]? | select(.hold | startswith("align-"))
        | . as $h | ($h.on | lc) as $k
        | (($h.hold | capture("-(?<s>[0-9a-f]{40})(-[1-9][0-9]*)?$").s) // "") as $placed
        | ([calls_at($k; $placed)[] | select(.call == "diverges")] | max_by(.entry)) as $keyed
        | $P[$k] as $pr
        | (if $pr == null then null else (calls_at($k; $pr.head) | max_by(.entry)) end) as $latest
        | (if ($h.lifted // "") != "" then "lifted"
           elif $pr == null then "standing"
           elif $pr.state == "MERGED" then "merged while held"
           elif $pr.state == "CLOSED" then "closed while held"
           elif $pr.head != $placed and $latest != null and ($latest.call == "fits" or $latest.call == "fits with follow-ups")
                and $keyed != null and $latest.entry > $keyed.entry then "releasable"
           else "standing" end) as $state
        | {hold: $h.hold, pull_request: $h.on, placed_head: $placed,
           call_entry: ($keyed.entry // null), reason: ($keyed.reason // null), state: $state,
           needs_re_read: ($state == "standing" and $latest == null),
           report: (if $state == "standing" or $state == "releasable" then
                ([$E[] | select(. as $ev | $h.hold | wordin($ev.report))] | last
                 | if . == null then "unconfirmed" else {session, seq, timestamp, unit} end)
                else null end)}]) as $holds
    | {calls: [$C[] | select(.stamp | after)],
       merges: [$merges[] | select(.merged_at | after)],
       recommendations: [$C[] | select(.action == "recommend" and (.stamp | after))],
       holds: $holds,
       open: [$P | to_entries[] | select(.value.state == "OPEN") | .key as $k | .value
           | {pull_request: .ref, head, call: (([calls_at($k; .head)[] | select(.standing)] | last | .call) // "none")}]
           | sort_by(prkey),
       refusals: ([$rf[0][] | select(after)] | length),
       gaps: $g[0]}' "$T/rec.json" || lib_die2 "jq failed"
