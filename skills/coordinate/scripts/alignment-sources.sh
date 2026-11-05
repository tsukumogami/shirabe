#!/usr/bin/env bash
# alignment-sources.sh -- the mechanical half of finding a lane pull
# request's plan sources, for a director's alignment call
# (docs/designs/DESIGN-director-alignment-review.md, Decision 3 and Key
# Interfaces). Read-only: it writes nothing to the record, the session or
# GitHub, and prints one JSON object or nothing.
#
# Usage:
#   alignment-sources.sh --session S --on <owner/repo#n> [--unit <roadmap unit>]
#
# The session gives the scope, the roadmap path and the host (coord-log.sh
# vars) and must have a found record. Only a roadmap run has plan sources: any
# other scope is refused (65). --on must be in the host or a Holdings row's
# repository (state-common.sh lib_in_scope), or it is refused (65).
#
# It prints, on stdout, one object with exactly these keys:
#
#   unit           --unit as given; otherwise the roadmap item the own lane's
#                  Holdings Unit cell names; otherwise "none"
#   clauses        [{n, field, text}]: the unit's `**<Field>:**` paragraphs in
#                  its roadmap block, Status, Dependencies and Evidence left
#                  out, numbered from 1 in document order. A paragraph runs from
#                  its field line to a blank line, the next field line or a
#                  heading, its lines joined with one space. [] when unit is none
#   evidence       [{n, text}]: the unit's Evidence clauses as milestone.sh
#                  evidence reads them, numbered from 1, on a roadmap/v2 or
#                  roadmap/v3 roadmap; [] on any other version or when unit is none
#   commit         the 40-hex head of the host's default branch the roadmap
#                  was read at
#   strategy       {path, repo, commit}: the roadmap's `upstream:`, read at
#                  `commit` when it is a path in the host, or at the head of
#                  its own repository's default branch when it is written
#                  `<owner/repo>:<path>`, so a call can cite `strategy <path>
#                  at <commit> ...`; "none" when the roadmap has no `upstream:`
#   changed_files  --on's changed paths, a rename's old path included, sorted
#   other_lanes    [{lane, repo, report, open, out_of_scope, units, paths}]
#   triggers       [{reason, ...}]
#   candidates     [{source, matched, ...}]
#
# The roadmap is read with the reader pick-facts.sh uses (state-common.sh
# lib_default_branch, lib_file_at, lib_roadmap_features), at the default
# branch's head commit, read first, so every clause is from that one commit.
#
# The record is read once (state-read.sh rs_record) for its Holdings, Side
# effects, Standing, Work and Decisions sections; the Run section is never
# read. The director's `report` and `progress` events are the `wait` evidence
# coord-log.sh evidence prints, walked back from the latest; of each, only the
# result block of its `report` field is read (the last `=== RESULT ===` line
# through the next `=== END RESULT ===`, each line trimmed, as coord-log.sh
# result-line reads it), and of the block only these lines:
#
#   unit=<topic> <done|reopened|dropped> <owner/repo#n>
#   open=<owner/repo#n>
#
# A pull request a message names anywhere else isn't read. Only the current
# run's log is read: a successor's first run sees none of its predecessor's
# reports until each lane reports again. The walk costs one log read per
# report or progress event.
#
# The own lane is the Holdings row whose Pull request cell links --on; failing
# that, the rows whose Worker is the `unit` of an event whose `pull_request`,
# or one of whose `open=` or `unit=` lines, names --on. When more than one row
# claims it, no row is the own lane: unit is none unless --unit gives it, and
# every row is listed in other_lanes. A cell names a roadmap item when it is
# the item's tag, or `<tag>: <anything>`, compared by tag key (`Feature 2` and
# `Milestone 2` are one).
#
# other_lanes holds one entry per Holdings row other than the own lane:
#   lane          the row's Worker topic
#   repo          its Repo
#   report        the seq of the latest report or progress event whose unit
#                 is that topic, or null
#   open          [{pull_request, changed_files}] for each `open=` line of that
#                 event in the host or a Holdings row's repository
#   out_of_scope  the `open=` pull requests in any other repository, never read
#   units         the roadmap items the row's Unit cell and its Work rows'
#                 Items name
#   paths         the paths the row's Unit cell and its Work rows' Item and
#                 Next cells name
# A lane's Work rows are those whose Who is its Worker or whose Item names its
# Unit. A cell names a path through a whitespace-separated token, stripped of
# leading quotes, backticks and brackets and of trailing quotes, backticks,
# brackets and `.,;:!?`, that holds a `/`, holds only letters, digits and
# `._/-`, doesn't start with `/` or hold `..`, and either ends in `/` (a
# directory) or has an extension on its last segment. A path matches a changed
# file that equals it or lies under it.
#
# triggers, each with a fixed reason:
#   {reason: "unit-finished", status, topic, event}  an event's `unit=` line
#       names --on as finishing its unit done, reopened or dropped
#   {reason: "milestone-verdict"}  --on is a milestone verdict pull request:
#       its head branch starts `coordinate/roadmap-verdict-` (roadmap-status.sh
#       --verdict's) in the host, or a milestone-done or milestone-verdict Side
#       effects row of the record names it
#   {reason: "roadmap-change", path}  a changed file is a roadmap document
#       (docs/roadmaps/.../ROADMAP-<name>.md)
#   {reason: "strategy-change", path}  a changed file is the strategy, or a
#       strategy document (docs/strategies/.../STRATEGY-<name>.md)
#   {reason: "other-lane", lane, open_work, files}  per lane whose open work
#       --on touches: an open pull request of that lane that changes a file
#       --on changes, a path its rows name that matches a changed file, or the
#       run's roadmap when --on (in the host) changes it and the lane's rows
#       name a unit of it. Each open_work item is written as a call's
#       `lane <lane> <item>` source takes it (`owner/repo#n` or a path);
#       files are the changed files that matched.
#
# candidates are every Standing row and settled Decisions entry that names the
# unit or a changed path: a Standing row through its On or What, a decision
# through its Question, Outcome or Context. A text names the unit when it is
# the unit's tag (or `<tag>: ...`) or holds it as a whole word; it names a
# changed path when one of its tokens (as above) equals it, or holds a `/`
# and the path lies under it. Each is {source: "standing s<n>", kind, on,
# what, owner, matched} or {source: "decision <n>", question, outcome,
# matched}, source written as a call's Sources line takes it, and matched
# lists "unit" and each changed path it names. Which of them covers the pull
# request is the director's judgment.
#
# A plan source in a repository that can't be read exits 3, nothing on stdout,
# its last stderr line:
#
#   alignment-sources: cannot read <owner/repo> <path> <repository|file>
#
# `repository` when the repository, its default branch or its head can't be
# read (GitHub answers a repository it hides with a 404 there too) or the
# file read fails for any reason but absence; `file` when the repository reads
# and the file doesn't (absent at the commit read), or the part the helper
# needs isn't there: the roadmap's items can't be parsed, the unit isn't one
# of them, the milestone has no Evidence the reader can read, or `upstream:`
# names no path. An `upstream:` sequence of more than one entry names no one
# strategy and is refused the same way, naming the roadmap; a scalar or a
# one-entry sequence is read.
#
# Exit codes: 0 printed; 2 a read failed that is no plan source in a
# repository: the record (its message names the session holding it), the log,
# --on's facts or changed files, or an open lane pull request's changed files;
# 3 a plan source couldn't be read (above); 64 usage; 65 refused.
#
# GitHub reads: gh api --method GET repos/R --jq .default_branch;
# gh api --method GET repos/R/git/ref/heads/<branch> --jq .object.sha;
# gh api --method GET "repos/R/contents/<path>?ref=<sha>" --jq .content;
# gh pr view <n> --repo R --json headRefName,baseRefName;
# gh api --method GET "repos/R/pulls/<n>/files?per_page=100" --paginate.
set -uo pipefail

PROG=alignment-sources
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= ON= UNIT_ARG= HAVE_UNIT=0

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --on) [ $# -ge 2 ] || usage; ON=$2; shift 2 ;;
        --unit) [ $# -ge 2 ] || usage; UNIT_ARG=$2; HAVE_UNIT=1; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
[[ $ON =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$ ]] || { echo "$PROG: --on is owner/repo#n" >&2; exit 64; }
if [ "$HAVE_UNIT" = 1 ]; then
    case "$UNIT_ARG" in ''|none|*[[:cntrl:]]*) echo "$PROG: --unit is a roadmap unit's tag" >&2; exit 64 ;; esac
    [ "${#UNIT_ARG}" -le 60 ] || { echo "$PROG: --unit is a roadmap unit's tag, 60 characters at most" >&2; exit 64; }
fi
. "$HERE/state-common.sh"
lib_facts
[ "$SCOPE" = roadmap ] || { echo "$PROG: refused: only a roadmap run has plan sources" >&2; exit 65; }
lib_roadmap_path
lib_run_found || lib_die2 "the run has no found record"
lib_log_readable || lib_die2 "cannot read the session log"

ON_REPO=${ON%#*} ON_NUM=${ON##*#}
T=$(mktemp -d "${TMPDIR:-/tmp}/alignment-sources.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT

# src_fail <owner/repo> <path> <repository|file>: a plan source unreadable.
src_fail() { echo "$PROG: cannot read $1 $2 $3" >&2; exit 3; }

# The jq both the lane and the final reads share.
JQ_DEFS="$JQ_TAG_KEY"'
def lc: ascii_downcase;
def unitkey: (if index(": ") then .[0:index(": ")] else . end) | tag_key;
def prref: if type != "string" then null else (sub("^\\s+"; "") | sub("\\s+$"; "")) as $s
    | ([($s | capture("^https://github\\.com/(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?<n>[1-9][0-9]*)/?$")),
        ($s | capture("^(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#(?<n>[1-9][0-9]*)$"))][0])
    | if . == null then null else "\(.r)#\(.n)" end end;
def tokens: [splits("\\s+") | sub("^[`'"'"'\"(\\[{<]+"; "") | sub("[`'"'"'\")\\]}>.,;:!?]+$"; "") | select(. != "")];
def pathlike: test("^[A-Za-z0-9._/-]+$") and test("/") and (startswith("/") | not) and (test("\\.\\.") | not)
    and (endswith("/") or test("\\.[A-Za-z0-9]+$"));
def under($p): . as $f | if ($p | endswith("/")) then ($f | startswith($p)) else ($f == $p or ($f | startswith($p + "/"))) end;
def pathtoks: [tokens[] | select(pathlike)];
def names_path($f): any(tokens[]; . == $f or (test("/") and ($f | under(.))));
def rx: gsub("(?<c>[.*+?^${}()|\\[\\]\\\\/-])"; "\\\(.c)");
def names_unit($u): $u != "none" and (
    (unitkey == ($u | tag_key))
    or test("(^|[^A-Za-z0-9])" + (if ($u | test("^(Feature|Milestone) [0-9]+$")) then "(Feature|Milestone) " + ($u | sub("^[A-Za-z]+ "; "")) else ($u | rx) end) + "($|[^A-Za-z0-9])"));
'

# ---- the record and the director's events ----------------------------------
rs_record "$T/rec.json" "holdings side_effects decisions standing work"
case $? in
    0) ;;
    *) lib_die2 "cannot read the record in $(lib_record_name): $(lib_scrub < "$T/rec.json.err")" ;;
esac
jq -c -L "$HERE" 'include "state-schema"; holdings_list' "$T/rec.json" > "$T/holdings.json" || lib_die2 "jq failed"
jq -c -L "$HERE" 'include "state-schema"; state_list as $s | {standing: $s.standing, work: $s.work,
    decisions: (decisions_list.entries // []), pending: pending_list}' "$T/rec.json" > "$T/lists.json" || lib_die2 "jq failed"
lib_in_scope "$ON_REPO" "$T/holdings.json" || { echo "$PROG: refused: $ON is in neither the host nor a Holdings row's repository" >&2; exit 65; }

# Every report and progress event, newest first.
: > "$T/events.jsonl"
EVARGS=(--session "$SESSION" --state wait --where 'event=report|progress')
BEFORE=
while :; do
    if [ -n "$BEFORE" ]; then
        OUT=$(bash "$HERE/coord-log.sh" evidence "${EVARGS[@]}" --before "$BEFORE" 2> /dev/null)
    else
        OUT=$(bash "$HERE/coord-log.sh" evidence "${EVARGS[@]}" 2> /dev/null)
    fi
    case $? in 0) ;; 1) break ;; *) lib_die2 "cannot read the session log" ;; esac
    printf '%s\n' "$OUT" >> "$T/events.jsonl"
    BEFORE=$(printf '%s' "$OUT" | jq -r '.seq') || lib_die2 "the session log's evidence is not JSON"
    [[ $BEFORE =~ $RE_NUM ]] || lib_die2 "the session log's evidence has no seq"
done
jq -s -c "$JQ_DEFS"'
    def trim: sub("^[ \t]+"; "") | sub("[ \t\r]+$"; "");
    def block: (split("\n") | map(trim)) as $l
        | ([range(0; $l | length) | select($l[.] == "=== RESULT ===")] | last) as $o
        | if $o == null then [] else
            ([range($o + 1; $l | length) | select($l[.] == "=== END RESULT ===")] | first) as $c
            | if $c == null then [] else $l[$o + 1:$c] end end;
    map((.fields // {}) as $f
        | (($f.report // "") | if type == "string" then . else tostring end | block) as $b
        | {seq, unit: (($f.unit // "") | tostring), pr: ($f.pull_request | prref),
           opens: [$b[] | select(startswith("open=")) | ltrimstr("open=")
                   | select(test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$"))],
           units: [$b[] | select(startswith("unit=")) | ltrimstr("unit=")
                   | capture("^(?<topic>[A-Za-z0-9][A-Za-z0-9._-]*) (?<status>done|reopened|dropped) (?<pr>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*)$")]})' \
    "$T/events.jsonl" > "$T/events.json" || lib_die2 "the session log's evidence is not JSON"

# The own lane: the row linking --on, else the rows an event names it under.
jq -r -L "$HERE" --arg on "$ON" --slurpfile ev "$T/events.json" 'include "state-schema"; '"$JQ_DEFS"'
    . as $h | ($on | lc) as $o
    | [$h[] | select((.pull_request // "" | pr_link) as $p | ("\($p.repo)#\($p.number)" | lc) == $o) | .worker] as $a
    | (if ($a | length) > 0 then $a
       else [$ev[0][] | select(((.pr // "") | lc) == $o or any(.opens[]; lc == $o) or any(.units[]; .pr | lc == $o)) | .unit] as $u
           | [$h[] | select(.worker as $w | $u | index([$w]) != null) | .worker] end)
    | unique | .[]' "$T/holdings.json" > "$T/own" || lib_die2 "jq failed"
OWN=
[ "$(awk 'END { print NR }' "$T/own")" = 1 ] && OWN=$(cat "$T/own")

# ---- the roadmap, at one commit ----------------------------------------------
HOST=$REPO
lib_default_branch || src_fail "$HOST" "$ROADMAP" repository
SHA=$(gh api --method GET "repos/$HOST/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha 2> /dev/null < /dev/null) \
    || src_fail "$HOST" "$ROADMAP" repository
[[ $SHA =~ $RE_SHA ]] || src_fail "$HOST" "$ROADMAP" repository
lib_file_at "$ROADMAP" "$SHA" "$T/roadmap.md"
case $? in 0) ;; 1) src_fail "$HOST" "$ROADMAP" file ;; *) src_fail "$HOST" "$ROADMAP" repository ;; esac
lib_roadmap_features "$T/roadmap.md" > "$T/features.json" 2> /dev/null || src_fail "$HOST" "$ROADMAP" file
jq -e 'type == "array"' "$T/features.json" > /dev/null 2>&1 || src_fail "$HOST" "$ROADMAP" file

# The unit: --unit, which must be an item; else the own lane's Unit cell.
UNIT_OUT=none UNIT_ID=
if [ "$HAVE_UNIT" = 1 ]; then
    UNIT_ID=$(jq -r --arg u "$UNIT_ARG" "$JQ_DEFS"'[.[] | select((.id | tag_key) == ($u | unitkey))][0].id // empty' "$T/features.json") \
        || lib_die2 "jq failed"
    [ -n "$UNIT_ID" ] || src_fail "$HOST" "$ROADMAP" file
    UNIT_OUT=$UNIT_ARG
elif [ -n "$OWN" ]; then
    UNIT_ID=$(jq -r --arg w "$OWN" --slurpfile f "$T/features.json" "$JQ_DEFS"'
        ([.[] | select(.worker == $w)][0].unit // "") as $c
        | [$f[0][] | select((.id | tag_key) == ($c | unitkey))][0].id // empty' "$T/holdings.json") || lib_die2 "jq failed"
    [ -z "$UNIT_ID" ] || UNIT_OUT=$UNIT_ID
fi

# The unit's clauses: its block's field paragraphs.
echo '[]' > "$T/clauses.json"
echo '[]' > "$T/evidence.json"
if [ -n "$UNIT_ID" ]; then
    lib_roadmap_words "$T/roadmap.md"
    tr -d '\r' < "$T/roadmap.md" | CL_SECTION="$RM_SECTION" CL_ID="$UNIT_ID" LC_ALL=C awk '
        BEGIN { sect = "## " ENVIRON["CL_SECTION"]; head = "### " ENVIRON["CL_ID"] ":" }
        function flush() { if (field != "") { gsub(/\t/, " ", text); print field "\t" text } field = ""; text = "" }
        /^## / { if (inb) { flush(); exit } s = $0; sub(/[ \t]+$/, "", s); insect = (s == sect); next }
        !insect { next }
        /^#+([ \t]|$)/ { if (inb) { flush(); exit } if (index($0, head) == 1) inb = 1; next }
        !inb { next }
        /^[ \t]*$/ { flush(); next }
        /^\*\*[A-Z][A-Za-z ]*:\*\*/ {
            flush()
            f = $0; sub(/^\*\*/, "", f); sub(/:\*\*.*$/, "", f)
            t = $0; sub(/^\*\*[A-Z][A-Za-z ]*:\*\*[ \t]*/, "", t); sub(/[ \t]+$/, "", t)
            field = f; text = t; next
        }
        field != "" { s = $0; sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); text = (text == "" ? s : text " " s); next }
        END { if (inb) flush() }' > "$T/clauses.tsv" || src_fail "$HOST" "$ROADMAP" file
    jq -R -s -c 'split("\n") | map(select(. != "") | split("\t"))
        | map(select(.[0] as $f | ["Status", "Dependencies", "Evidence"] | index([$f]) | not))
        | to_entries | map({n: (.key + 1), field: .value[0], text: (.value[1:] | join(" ") | .[0:4096])})' \
        "$T/clauses.tsv" > "$T/clauses.json" || lib_die2 "jq failed"
    if bash "$HERE/milestone.sh" is-milestone "$T/roadmap.md"; then
        bash "$HERE/milestone.sh" evidence "$T/roadmap.md" "$UNIT_ID" > "$T/ms.json" 2> /dev/null || src_fail "$HOST" "$ROADMAP" file
        jq -c '.evidence | to_entries | map({n: (.key + 1), text: .value})' "$T/ms.json" > "$T/evidence.json" 2> /dev/null \
            || src_fail "$HOST" "$ROADMAP" file
    fi
fi

# ---- the strategy: the roadmap's upstream: ----------------------------------
tr -d '\r' < "$T/roadmap.md" | awk '
    NR == 1 { if ($0 != "---") exit; fm = 1; next }
    $0 == "---" { exit }
    inseq { if ($0 ~ /^[ \t]*- /) { s = $0; sub(/^[ \t]*- [ \t]*/, "", s); sub(/[ \t]+$/, "", s); print "item\t" s; next } inseq = 0 }
    /^upstream:/ {
        s = $0; sub(/^upstream:[ \t]*/, "", s); sub(/[ \t]+$/, "", s); print "key"
        if (s == "") inseq = 1
        else if (s ~ /^\[.*\]$/) {
            n = split(substr(s, 2, length(s) - 2), a, ",")
            for (i = 1; i <= n; i++) { t = a[i]; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t != "") print "item\t" t }
        } else print "item\t" s
        next
    }' > "$T/upstream.tsv"
STRATEGY_JSON='"none"' SREPO= SPATH=
if grep -qx key "$T/upstream.tsv"; then
    sed -n 's/^item	//p' "$T/upstream.tsv" | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//' > "$T/upstream.items"
    [ "$(awk 'END { print NR }' "$T/upstream.items")" = 1 ] || src_fail "$HOST" "$ROADMAP" file
    UP=$(cat "$T/upstream.items")
    if [[ $UP =~ ^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+):(.+)$ ]]; then
        SREPO=${BASH_REMATCH[1]} SPATH=${BASH_REMATCH[2]}
    else
        SREPO=$HOST SPATH=$UP
    fi
    [[ $SPATH =~ ^[A-Za-z0-9._/-]+$ ]] || src_fail "$HOST" "$ROADMAP" file
    case "$SPATH" in /*|*..*) src_fail "$HOST" "$ROADMAP" file ;; esac
    SSHA=$SHA
    if [ "$(printf '%s' "$SREPO" | tr 'A-Z' 'a-z')" != "$(printf '%s' "$HOST" | tr 'A-Z' 'a-z')" ]; then
        REPO=$SREPO
        lib_default_branch || src_fail "$SREPO" "$SPATH" repository
        SSHA=$(gh api --method GET "repos/$SREPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha 2> /dev/null < /dev/null) \
            || src_fail "$SREPO" "$SPATH" repository
        [[ $SSHA =~ $RE_SHA ]] || src_fail "$SREPO" "$SPATH" repository
    fi
    REPO=$SREPO
    lib_file_at "$SPATH" "$SSHA" "$T/strategy.md"
    case $? in 0) ;; 1) src_fail "$SREPO" "$SPATH" file ;; *) src_fail "$SREPO" "$SPATH" repository ;; esac
    REPO=$HOST
    STRATEGY_JSON=$(jq -nc --arg p "$SPATH" --arg r "$SREPO" --arg c "$SSHA" '{path: $p, repo: $r, commit: $c}')
fi

# ---- the pull request and the other lanes' open pull requests ---------------
# pr_files <owner/repo> <n> <out>: the changed paths, a rename's old one too.
pr_files() {
    gh api --method GET "repos/$1/pulls/$2/files?per_page=100" --paginate \
        --jq '.[] | .filename, (.previous_filename // empty) | tojson' > "$3.raw" 2> "$3.err" < /dev/null || return 1
    jq -sc 'map(select(type == "string")) | unique' "$3.raw" > "$3" 2> /dev/null
}
gh pr view "$ON_NUM" --repo "$ON_REPO" --json headRefName,baseRefName > "$T/pr.json" 2> "$T/pr.err" < /dev/null \
    || lib_die2 "cannot read $ON: $(lib_scrub < "$T/pr.err")"
pr_files "$ON_REPO" "$ON_NUM" "$T/changed.json" || lib_die2 "cannot read $ON's changed files: $(lib_scrub < "$T/changed.json.err")"

# The other lanes' open= pull requests, in scope and not --on, each read once.
jq -r --arg own "$OWN" --arg on "$ON" --arg host "$HOST" --slurpfile ev "$T/events.json" "$JQ_DEFS"'
    . as $h | ([$host] + [$h[].repo] | map(lc)) as $scope
    | [$h[] | select(.worker != $own) | .worker as $w | ([$ev[0][] | select(.unit == $w)] | first) | (.opens // [])[]]
    | map(select((split("#")[0] | lc) as $r | $scope | index([$r]) != null) | select(lc != ($on | lc)))
    | unique_by(lc) | .[]' "$T/holdings.json" > "$T/open.list" || lib_die2 "jq failed"
echo '{}' > "$T/prfiles.json"
mkdir -p "$T/pf" || lib_die2 "cannot make a temporary directory"
K=0
while IFS= read -r P; do
    [ -n "$P" ] || continue
    K=$((K + 1))
    pr_files "${P%#*}" "${P##*#}" "$T/pf/$K" || lib_die2 "cannot read $P's changed files: $(lib_scrub < "$T/pf/$K.err")"
    jq -c --arg p "$P" --slurpfile f "$T/pf/$K" '. + {($p | ascii_downcase): $f[0]}' "$T/prfiles.json" > "$T/prfiles.new" \
        && mv "$T/prfiles.new" "$T/prfiles.json" || lib_die2 "jq failed"
done < "$T/open.list"

# ---- the object --------------------------------------------------------------
jq -n -c -L "$HERE" --arg on "$ON" --arg own "$OWN" --arg host "$HOST" --arg roadmap "$ROADMAP" --arg commit "$SHA" \
    --arg unit "$UNIT_OUT" --arg srepo "$SREPO" --arg spath "$SPATH" --argjson strategy "$STRATEGY_JSON" \
    --slurpfile h "$T/holdings.json" --slurpfile l "$T/lists.json" --slurpfile ev "$T/events.json" \
    --slurpfile f "$T/features.json" --slurpfile c "$T/changed.json" --slurpfile pf "$T/prfiles.json" \
    --slurpfile pr "$T/pr.json" --slurpfile cl "$T/clauses.json" --slurpfile evi "$T/evidence.json" \
    'include "state-schema"; '"$JQ_DEFS"'
    $h[0] as $H | $l[0] as $L | $ev[0] as $E | $f[0] as $F | $c[0] as $C | $pf[0] as $PF
    | ($on | lc) as $o | ($on | split("#")[0] | lc) as $onrepo
    | ([$host] + [$H[].repo] | map(lc)) as $scope
    | def items($texts): [$texts[] | . as $t | $F[] | select((.id | tag_key) == ($t | unitkey)) | .id] | unique;
      def lane($row): ([$L.work[] | select(.who == $row.worker or ((.item | unitkey) == ($row.unit | unitkey)))]) as $w
        | ([$E[] | select(.unit == $row.worker)] | first) as $last
        | (($last.opens // []) | reduce .[] as $x ([]; if any(.[]; lc == ($x | lc)) then . else . + [$x] end)) as $opens
        | {lane: $row.worker, repo: $row.repo, report: ($last.seq // null),
           open: [$opens[] | select((split("#")[0] | lc) as $r | $scope | index([$r]) != null)
                  | {pull_request: ., changed_files: ($PF[lc] // [])}],
           out_of_scope: [$opens[] | select((split("#")[0] | lc) as $r | $scope | index([$r]) == null)],
           units: items([$row.unit] + [$w[].item]),
           paths: ([([$row.unit] + [$w[].item] + [$w[].next])[] | pathtoks[]] | unique)};
    [$H[] | select(.worker != $own) | lane(.)] as $lanes
    | ((($pr[0].headRefName // "") | startswith("coordinate/roadmap-verdict-")) and $onrepo == ($host | lc)
       or any($L.pending[]; (.action == "milestone-done" or .action == "milestone-verdict")
              and ((.pull_request | pr_link | "\(.repo)#\(.number)" | lc) == $o))) as $verdict
    | ([$E[] | . as $e | .units[] | select((.pr | lc) == $o) | {reason: "unit-finished", status, topic, event: $e.seq}]
        | unique_by([.event, .topic, .status])) as $finished
    | ([$C[] | select(test("^docs/roadmaps/([A-Za-z0-9._-]+/)*ROADMAP-[A-Za-z0-9._-]+\\.md$")) | {reason: "roadmap-change", path: .}]) as $rm
    | ([$C[] | select(test("^docs/strategies/([A-Za-z0-9._-]+/)*STRATEGY-[A-Za-z0-9._-]+\\.md$")
                      or ($srepo != "" and ($srepo | lc) == $onrepo and . == $spath)) | {reason: "strategy-change", path: .}]) as $st
    | [$lanes[] | . as $ln
        | [$ln.open[] | . as $op | select(any($op.changed_files[]; . as $x | $C | index([$x]) != null))] as $oh
        | [$ln.paths[] | . as $p | select(any($C[]; under($p)))] as $ph
        | (if ($ln.units | length) > 0 and $onrepo == ($host | lc) and ($C | index([$roadmap]) != null) then [$roadmap] else [] end) as $rh
        | ([$oh[].pull_request] + $ph + $rh | reduce .[] as $x ([]; if index([$x]) != null then . else . + [$x] end)) as $work
        | select(($work | length) > 0)
        | {reason: "other-lane", lane: $ln.lane, open_work: $work,
           files: ([$C[] | . as $x | select(any($oh[].changed_files[]; . == $x) or any($ph[]; . as $p | $x | under($p))
                     or ($rh | index([$x]) != null))] | unique)}] as $other
    | def matched($texts): ([if any($texts[]; names_unit($unit)) then "unit" else empty end]
        + [$C[] as $x | select(any($texts[]; names_path($x))) | $x]);
    {unit: $unit, clauses: $cl[0], evidence: $evi[0], commit: $commit, strategy: $strategy,
     changed_files: $C, other_lanes: $lanes,
     triggers: ($finished + (if $verdict then [{reason: "milestone-verdict"}] else [] end) + $rm + $st + $other),
     candidates: ([$L.standing[] | matched([.on // "", .what // ""]) as $m | select(($m | length) > 0)
                   | {source: "standing \(.standing)", kind, on, what, owner, matched: $m}]
                  + [$L.decisions[] | select(.state == "settled")
                     | matched([.question // "", .outcome // "", .context // ""]) as $m | select(($m | length) > 0)
                     | {source: "decision \(.decision)", question, outcome: (.outcome // ""), matched: $m}])}' \
    > "$T/out.json" || lib_die2 "jq failed"
cat "$T/out.json"
