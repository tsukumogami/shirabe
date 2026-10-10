#!/usr/bin/env bash
# milestone.sh -- read a milestone roadmap's schema and a milestone's
# Evidence, and check a milestone verdict entry against them. Files only: no
# network, no git, no koto. The coordinator, roadmap-status.sh and the suites
# call it on a roadmap they have already fetched
# (docs/designs/DESIGN-milestone-verdicts.md, Decisions 2 and 4).
#
# Usage:
#   milestone.sh schema ROADMAP
#   milestone.sh evidence ROADMAP TAG
#   milestone.sh check-verdict ROADMAP TAG ENTRY [--worker TOPIC] [--today YYYY-MM-DD]
#   milestone.sh progress-has ROADMAP TEXT
#   milestone.sh check-goal-fit ROADMAP TAG ENTRY
#   milestone.sh check-failure ROADMAP TAG ENTRY [--today YYYY-MM-DD]
#
# schema prints the frontmatter's `schema:` value, or roadmap/v1 when the
# frontmatter names none (a roadmap with no schema line is a version 1 one).
#
# evidence prints {tag, title, status, schema, evidence: [clause, ...]} for
# the milestone whose heading is `### TAG: <title>` under `## Features`: each
# clause is a `- ` line at column 0 below `**Evidence:**`, its indented
# wrapped lines joined with one space, and the field ends at a blank line, the
# next field line, a heading or a column-0 line that isn't a clause, as the
# validator reads it. It exits 2 when TAG isn't a milestone with Evidence: the
# roadmap isn't roadmap/v2, no heading carries TAG, its block has no clause,
# or the block holds something the reader can't classify (a tab or a code
# fence).
#
# check-verdict checks ENTRY, a verdict entry, against TAG's milestone in
# ROADMAP, the roadmap at the commit the entry's Source line names. The entry
# is these lines, in this order, with one blank line before `Evidence:` and
# one before `Strategy fit:`:
#
#   Verdict: <tag> -- <changes needed|verified with follow-ups|verified>
#   Checked by: <a login, a session name or a plain name, 60 characters at most>
#   Checked on: <YYYY-MM-DD, no later than today>
#   Source: <docs/roadmaps/.../ROADMAP-<name>.md> at <40-character commit>
#   Work checked: <owner/repo#n, owner/repo#n | none>
#
#   Evidence:
#   1. <held|not held> -- <what showed it>
#   ... one line per clause, numbered in the roadmap's order
#
#   Strategy fit: <fits|does not fit> -- <why>
#   Follow-ups: <none | new: <title>; amend <tag>: <what>>
#   Changes needed: <none | what must change>
#
# and the verdict must follow its rules: verified needs every clause held,
# fits, no follow-up and no change; verified with follow-ups the same with at
# least one follow-up; changes needed a clause not held or `does not fit`,
# and a change named. A Checked by containing --worker's topic, in any letter
# case, is refused: the session that did the work never checks it. A refusal
# names the line (`line 3: ...`) on stderr. On success it prints the entry as
# JSON: {tag, verdict, checked_by, checked_on, source: {path, commit},
# work_checked, clauses: [{n, held, why}], strategy_fit, follow_ups,
# changes_needed}.
#
# progress-has exits 0 when the `## Progress` section holds TEXT, as written.
#
# check-goal-fit checks ENTRY, the goal-fit judgment of one pull request for
# TAG's milestone, against TAG's Evidence in ROADMAP (the roadmap on the
# default branch, which coord/land.json's `milestone.evidence` was read from).
# The entry is these four lines, in this order:
#
#   Goal fit: <owner/repo#n> -- <tag>
#   Fit: <fits|fits with follow-ups|gap>
#   Clauses: <n, n, ... | advances none>
#   Rationale: <text>
#
# Each clause number must be one of TAG's Evidence clauses, named once;
# `advances none` says the pull request advances none of them, which is
# recorded, not refused. The same 16 KiB cap and plain-lines rule as a verdict
# entry apply. A refusal names the line on stderr; on success it prints
# {pr, tag, fit, clauses: [n, ...], rationale} ([] for advances none).
#
# check-failure checks ENTRY, a failure reported against TAG's milestone after
# it read Done, against ROADMAP, the roadmap on the default branch: TAG must
# read Done there, and the clause must be one of its Evidence clauses. The
# entry is these five lines, in this order:
#
#   Failure: <tag>
#   Reported by: <a login, a session name or a plain name, 60 characters at most>
#   Seen on: <YYYY-MM-DD, no later than today>
#   Clause: <n>
#   What was seen: <text>
#
# Reported by has Checked by's closed shape (no backtick, slash or control
# character, so no path either). What was seen is one paragraph of at most
# 600 bytes with no URL or markdown link: it is the first report text that
# reaches a worker's brief, quoted under the rework heading, so it gets the
# rework row's shape (record-codec.jq rework_problem). The same 16 KiB cap and
# plain-lines rule as a verdict entry apply. A refusal names the line on
# stderr; on success it prints {tag, reported_by, seen_on, clause, clause_text,
# what_was_seen}.
#
# Exit codes: 0 pass (or found); 1 the check failed (the entry checks: the
# entry; progress-has: TEXT is not there); 2 a file
# couldn't be read, or TAG isn't a milestone with Evidence; 64 usage.
set -uo pipefail

PROG=milestone
HERE=$(cd "$(dirname "$0")" && pwd)
usage() { sed -n '/^# Usage:/,/^# schema prints/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 64; }
die2() { echo "$PROG: $*" >&2; exit 2; }
# An entry is at most this many bytes (roadmap-status.sh --verdict holds the
# entry file to the same cap).
ENTRY_MAX=16384
RE_TAG='^(Feature [0-9]+|[A-Za-z]+[0-9]+[a-z]?)$'
RE_ROADMAP_PATH='^docs/roadmaps/([A-Za-z0-9._-]+/)*ROADMAP-[A-Za-z0-9._-]+\.md$'

# schema_of <file>: the frontmatter's schema value, or roadmap/v1.
schema_of() {
    tr -d '\r' < "$1" | awk '
        NR == 1 { if ($0 != "---") exit; fm = 1; next }
        fm && $0 == "---" { exit }
        fm && /^schema:/ { s = $0; sub(/^schema:[ \t]*/, "", s); sub(/[ \t]+$/, "", s); gsub(/^["\x27]|["\x27]$/, "", s); print s; exit }'
}

# block_of <file> <tag>: TAG's milestone as tab-separated lines, `title`,
# `status` and one `evidence` line per clause; exit 3 when the block holds a
# tab or a code fence, 4 when no heading carries TAG.
block_of() {
    tr -d '\r' < "$1" | MS_TAG="$2" LC_ALL=C awk '
        BEGIN { tag = ENVIRON["MS_TAG"]; head = "### " tag ": " }
        # flush: the clause being read, if any, and the Evidence field ends.
        function flush() { if (have) print "evidence\t" clause; have = 0; inev = 0 }
        /^## / { infeat = ($0 ~ /^## Features[ \t]*$/); if (inblock) { flush(); inblock = 0; done = 1 } next }
        !infeat || done { next }
        /^### / {
            if (inblock) { flush(); inblock = 0; done = 1; next }
            if (index($0, head) == 1 && length($0) > length(head)) { inblock = 1; found = 1; print "title\t" substr($0, length(head) + 1) }
            next
        }
        !inblock { next }
        /\t/ || /^[ \t]*(```|~~~)/ { bad = 1; exit }
        /^\*\*[A-Z][A-Za-z ]*:\*\*/ {
            flush()
            field = $0; sub(/:\*\*.*/, "", field); sub(/^\*\*/, "", field)
            if (field == "Status") { s = $0; sub(/^\*\*Status:\*\*[ \t]*/, "", s); sub(/[ \t]+$/, "", s); print "status\t" s }
            inev = (field == "Evidence")
            next
        }
        /^[ \t]*$/ { flush(); next }
        inev && /^- / {
            if (have) print "evidence\t" clause
            clause = substr($0, 3); sub(/^[ \t]+/, "", clause); sub(/[ \t]+$/, "", clause)
            have = (clause != ""); next
        }
        inev && /^ / && have { s = $0; sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); clause = clause " " s; next }
        inev { flush(); next }
        END {
            if (bad) exit 3
            flush()
            if (!found) exit 4
        }'
}

# milestone_json <file> <tag>: the evidence subcommand's JSON, or exit 2.
milestone_json() {
    local sch lines rc
    [ -r "$1" ] || die2 "cannot read $1"
    sch=$(schema_of "$1")
    [ -n "$sch" ] || sch=roadmap/v1
    [ "$sch" = roadmap/v2 ] || die2 "$1 is a $sch roadmap; only a roadmap/v2 roadmap has milestones"
    lines=$(block_of "$1" "$2"); rc=$?
    case $rc in
        0) ;;
        3) die2 "$2's block holds a tab or a code fence, which the Evidence reader can't classify" ;;
        4) die2 "no milestone heading carries $2 under ## Features" ;;
        *) die2 "cannot read $1" ;;
    esac
    printf '%s\n' "$lines" | jq -R -s -c --arg t "$2" --arg s "$sch" '
        split("\n") | map(select(. != "") | (index("\t")) as $i | {k: .[0:$i], v: .[$i + 1:]})
        | {tag: $t, title: ([.[] | select(.k == "title") | .v][0] // ""),
           status: ([.[] | select(.k == "status") | .v][0] // ""), schema: $s,
           evidence: [.[] | select(.k == "evidence") | .v]}' || die2 "jq failed"
}

[ $# -ge 1 ] || usage
CMD=$1; shift
case "$CMD" in
schema)
    [ $# -eq 1 ] || usage
    [ -r "$1" ] || die2 "cannot read $1"
    S=$(schema_of "$1")
    printf '%s\n' "${S:-roadmap/v1}"
    exit 0
    ;;
evidence)
    [ $# -eq 2 ] || usage
    J=$(milestone_json "$1" "$2") || exit 2
    [ "$(printf '%s' "$J" | jq '.evidence | length')" -gt 0 ] || die2 "$2 has no Evidence clause"
    printf '%s\n' "$J"
    exit 0
    ;;
progress-has)
    [ $# -eq 2 ] && [ -n "$2" ] || usage
    [ -r "$1" ] || die2 "cannot read $1"
    tr -d '\r' < "$1" | MS_TEXT="$2" awk '
        BEGIN { t = ENVIRON["MS_TEXT"] }
        /^## / { inp = ($0 ~ /^## Progress[ \t]*$/); next }
        inp && index($0, t) { found = 1 }
        END { exit(found ? 0 : 1) }'
    exit $?
    ;;
check-verdict|check-goal-fit|check-failure) ;;
*) usage ;;
esac

# ---- the entry checks: their arguments and the entry's lines ----------------
[ $# -ge 3 ] || usage
ROADMAP_FILE=$1 TAG=$2 ENTRY=$3; shift 3
WORKER= TODAY=
[ "$CMD" != check-goal-fit ] || [ $# -eq 0 ] || usage
while [ $# -gt 0 ]; do
    case "$1" in
        --worker) [ $# -ge 2 ] && [ "$CMD" = check-verdict ] || usage; WORKER=$2; shift 2 ;;
        --today) [ $# -ge 2 ] || usage; TODAY=$2; shift 2 ;;
        *) usage ;;
    esac
done
[[ $TAG =~ $RE_TAG ]] || { echo "$PROG: $TAG is not a milestone's heading tag (Feature 7, ED1, AB10b)" >&2; exit 64; }
if [ "$CMD" != check-goal-fit ]; then
    [ -n "$TODAY" ] || TODAY=$(date -u +%Y-%m-%d)
    [[ $TODAY =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
fi
[ -r "$ENTRY" ] || die2 "cannot read $ENTRY"
MS=$(milestone_json "$ROADMAP_FILE" "$TAG") || exit 2
NCLAUSES=$(printf '%s' "$MS" | jq '.evidence | length')
[ "$NCLAUSES" -gt 0 ] || die2 "$TAG has no Evidence clause"

fail() { echo "$PROG: refused: $*" >&2; exit 1; }
SIZE=$(wc -c < "$ENTRY" | tr -d ' ')
[ "$SIZE" -le "$ENTRY_MAX" ] || fail "the entry is $SIZE bytes, over $ENTRY_MAX"
# Control characters other than the line break, and a carriage return: an
# entry is plain lines.
LC_ALL=C grep -q $'[\001-\010\011\013-\037\177]' "$ENTRY" && fail "the entry holds a control character or a tab"

# The entry's lines, a trailing blank line or two allowed.
LINES=()
while IFS= read -r L || [ -n "$L" ]; do LINES[${#LINES[@]}]=$L; done < "$ENTRY"
while [ "${#LINES[@]}" -gt 0 ] && [ -z "${LINES[${#LINES[@]}-1]}" ]; do unset "LINES[${#LINES[@]}-1]"; done
N=${#LINES[@]}
# line <i>: the i-th line (1-based), or empty past the end.
line() { if [ "$1" -le "$N" ]; then printf '%s' "${LINES[$1-1]}"; fi; }
# shape <i> <label> <regex>: line i must match, else a refusal naming it.
shape() {
    local l
    l=$(line "$1")
    [ "$1" -le "$N" ] || fail "line $1: missing; expected \`$2\`"
    [[ $l =~ $3 ]] || fail "line $1: expected \`$2\`, read [${l:0:80}]"
}

# ---- check-goal-fit ----------------------------------------------------------
if [ "$CMD" = check-goal-fit ]; then
    shape 1 "Goal fit: <owner/repo#n> -- <tag>" '^Goal fit: ([^ ]+) -- (.+)$'
    GF_PR=${BASH_REMATCH[1]} GF_TAG=${BASH_REMATCH[2]}
    RE_PR_REF='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$'
    [[ $GF_PR =~ $RE_PR_REF ]] || fail "line 1: the pull request is owner/repo#n, read [${GF_PR:0:80}]"
    [ "$GF_TAG" = "$TAG" ] || fail "line 1: the entry names ${GF_TAG:0:80}, not $TAG"
    shape 2 "Fit: <fits|fits with follow-ups|gap>" '^Fit: (fits|fits with follow-ups|gap)$'
    GF_FIT=${BASH_REMATCH[1]}
    shape 3 "Clauses: <n, n | advances none>" '^Clauses: (.+)$'
    GF_CLAUSES=${BASH_REMATCH[1]}
    CL_JSON='[]'
    if [ "$GF_CLAUSES" != "advances none" ]; then
        # At most four digits a number: a milestone never has a thousand
        # clauses, and jq's tonumber never sees a value it would round.
        RE_NUMS='^[1-9][0-9]{0,3}(, [1-9][0-9]{0,3})*$'
        [[ $GF_CLAUSES =~ $RE_NUMS ]] \
            || fail "line 3: Clauses is \`advances none\` or clause numbers separated by \", \", read [${GF_CLAUSES:0:80}]"
        CL_JSON=$(printf '%s' "$GF_CLAUSES" | jq -R -c 'split(", ") | map(tonumber)') || die2 "jq failed"
        printf '%s' "$CL_JSON" | jq -e '(unique | length) == length' > /dev/null || fail "line 3: a clause is named twice"
        BIG=$(printf '%s' "$CL_JSON" | jq --argjson n "$NCLAUSES" '[.[] | select(. > $n)][0] // empty')
        [ -z "$BIG" ] || fail "line 3: clause $BIG is not one of $TAG's Evidence clauses; it has $NCLAUSES"
    fi
    shape 4 "Rationale: <text>" '^Rationale: (.*[^ ].*)$'
    GF_WHY=${BASH_REMATCH[1]}
    [ "$N" -le 4 ] || fail "line 5: nothing follows Rationale"
    jq -n -c --arg pr "$GF_PR" --arg tag "$TAG" --arg fit "$GF_FIT" --argjson cl "$CL_JSON" --arg why "$GF_WHY" \
        '{pr: $pr, tag: $tag, fit: $fit, clauses: $cl, rationale: $why}' || die2 "jq failed"
    exit 0
fi

# ---- check-failure -----------------------------------------------------------
if [ "$CMD" = check-failure ]; then
    shape 1 "Failure: <tag>" '^Failure: (.+)$'
    F_TAG=${BASH_REMATCH[1]}
    [ "$F_TAG" = "$TAG" ] || fail "line 1: the entry names ${F_TAG:0:80}, not $TAG"
    F_STATUS=$(printf '%s' "$MS" | jq -r .status)
    case "$F_STATUS" in
        Done*) ;;
        *) fail "line 1: $TAG reads ${F_STATUS:-no status}, not Done; a failure reopens only a Done milestone" ;;
    esac
    shape 2 "Reported by: <who>" '^Reported by: (.+)$'
    F_BY=${BASH_REMATCH[1]}
    RE_BY='^[A-Za-z0-9][A-Za-z0-9 ._-]{0,59}$'
    [[ $F_BY =~ $RE_BY ]] || fail "line 2: Reported by is a login, a session name or a plain name: letters, digits, spaces, . _ -, 60 characters at most"
    shape 3 "Seen on: <YYYY-MM-DD>" '^Seen on: ([0-9]{4})-([0-9]{2})-([0-9]{2})$'
    F_ON="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    M=${BASH_REMATCH[2]#0} D=${BASH_REMATCH[3]#0}
    [ "$M" -ge 1 ] && [ "$M" -le 12 ] && [ "$D" -ge 1 ] && [ "$D" -le 31 ] || fail "line 3: $F_ON is not a date"
    [[ $F_ON > $TODAY ]] && fail "line 3: Seen on $F_ON is later than today, $TODAY"
    # At most four digits, as Clauses in a goal-fit entry.
    shape 4 "Clause: <n>" '^Clause: ([1-9][0-9]{0,3})$'
    F_CLAUSE=${BASH_REMATCH[1]}
    [ "$F_CLAUSE" -le "$NCLAUSES" ] || fail "line 4: clause $F_CLAUSE is not one of $TAG's Evidence clauses; it has $NCLAUSES"
    shape 5 "What was seen: <text>" '^What was seen: (.*[^ ].*)$'
    F_WHAT=${BASH_REMATCH[1]}
    WHY=$(printf '%s' "$F_WHAT" | jq -R -s -r -L "$HERE" 'include "record-codec"; rework_problem // empty') || die2 "jq failed"
    [ -z "$WHY" ] || fail "line 5: What was seen is one paragraph of at most 600 bytes with no URL or markdown link; this one has $WHY"
    [ "$N" -le 5 ] || fail "line 6: nothing follows What was seen"
    printf '%s' "$MS" | jq -c --arg by "$F_BY" --arg on "$F_ON" --argjson n "$F_CLAUSE" --arg what "$F_WHAT" \
        '{tag, reported_by: $by, seen_on: $on, clause: $n, clause_text: .evidence[$n - 1], what_was_seen: $what}' || die2 "jq failed"
    exit 0
fi

# ---- check-verdict -----------------------------------------------------------

shape 1 "Verdict: <tag> -- <verdict>" '^Verdict: (.+) -- (changes needed|verified with follow-ups|verified)$'
V_TAG=${BASH_REMATCH[1]} VERDICT=${BASH_REMATCH[2]}
[ "$V_TAG" = "$TAG" ] || fail "line 1: the verdict names $V_TAG, not $TAG"
shape 2 "Checked by: <who>" '^Checked by: (.+)$'
BY=${BASH_REMATCH[1]}
RE_BY='^[A-Za-z0-9][A-Za-z0-9 ._-]{0,59}$'
[[ $BY =~ $RE_BY ]] || fail "line 2: Checked by is a login, a session name or a plain name: letters, digits, spaces, . _ -, 60 characters at most"
if [ -n "$WORKER" ]; then
    LBY=$(printf '%s' "$BY" | tr 'A-Z' 'a-z'); LW=$(printf '%s' "$WORKER" | tr 'A-Z' 'a-z')
    case "$LBY" in *"$LW"*) fail "line 2: Checked by names $WORKER, the worker that holds $TAG; the session that did the work never checks it" ;; esac
fi
shape 3 "Checked on: <YYYY-MM-DD>" '^Checked on: ([0-9]{4})-([0-9]{2})-([0-9]{2})$'
ON="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
M=${BASH_REMATCH[2]#0} D=${BASH_REMATCH[3]#0}
[ "$M" -ge 1 ] && [ "$M" -le 12 ] && [ "$D" -ge 1 ] && [ "$D" -le 31 ] || fail "line 3: $ON is not a date"
[[ $ON > $TODAY ]] && fail "line 3: Checked on $ON is later than today, $TODAY"
shape 4 "Source: <roadmap path> at <40-character commit>" '^Source: ([^ ]+) at ([0-9a-f]{40})$'
SRC_PATH=${BASH_REMATCH[1]} SRC_COMMIT=${BASH_REMATCH[2]}
[[ $SRC_PATH =~ $RE_ROADMAP_PATH ]] || fail "line 4: $SRC_PATH is not docs/roadmaps/.../ROADMAP-<name>.md"
case "$SRC_PATH" in *..*) fail "line 4: the Source path holds .." ;; esac
shape 5 "Work checked: <owner/repo#n, ... | none>" '^Work checked: (.+)$'
WORK=${BASH_REMATCH[1]}
WORK_JSON='[]'
if [ "$WORK" != none ]; then
    WORK_JSON=$(printf '%s' "$WORK" | jq -R -c 'split(", ")') || die2 "jq failed"
    printf '%s' "$WORK_JSON" | jq -e 'all(.[]; test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$")) and (unique | length) == length' > /dev/null \
        || fail "line 5: Work checked is \`none\` or pull requests as owner/repo#n, each once, separated by \", \""
fi
shape 6 "(a blank line)" '^$'
shape 7 "Evidence:" '^Evidence:$'
CLAUSES=
RE_CLAUSE='^([0-9]+)\. (held|not held) -- (.+)$'
i=1
while :; do
    l=$(line $((7 + i)))
    [[ $l =~ $RE_CLAUSE ]] || break
    [ "${BASH_REMATCH[1]}" = "$i" ] || fail "line $((7 + i)): clause ${BASH_REMATCH[1]} where clause $i belongs; number the clauses in the roadmap's order"
    CLAUSES="$CLAUSES${BASH_REMATCH[2]}"$'\t'"${BASH_REMATCH[3]}"$'\n'
    i=$((i + 1))
done
NC=$((i - 1))
[ "$NC" -gt 0 ] || fail "line 8: expected \`1. <held|not held> -- <what showed it>\`, read [$(line 8 | cut -c1-80)]"
[ "$NC" = "$NCLAUSES" ] || fail "line 8: the entry judges $NC clause(s); $TAG's Evidence at Source has $NCLAUSES"
P=$((8 + NC))
shape "$P" "(a blank line)" '^$'
shape $((P + 1)) "Strategy fit: <fits|does not fit> -- <why>" '^Strategy fit: (fits|does not fit) -- (.+)$'
FIT=${BASH_REMATCH[1]} FIT_WHY=${BASH_REMATCH[2]}
shape $((P + 2)) "Follow-ups: <none | new: <title>; amend <tag>: <what>>" '^Follow-ups: (.+)$'
FU=${BASH_REMATCH[1]}
shape $((P + 3)) "Changes needed: <none | what must change>" '^Changes needed: (.+)$'
CHANGES=${BASH_REMATCH[1]}
[ "$N" -le $((P + 3)) ] || fail "line $((P + 4)): nothing follows Changes needed"

# The follow-ups: `none`, or items separated by `; `.
FU_JSON='[]'
if [ "$FU" != none ]; then
    FU_JSON='[]'
    RE_NEW='^new: (.+)$' RE_AMEND='^amend ([^:]+): (.+)$'
    REST="$FU; "
    while [ -n "$REST" ]; do
        ITEM=${REST%%; *}; REST=${REST#*; }
        if [[ $ITEM =~ $RE_NEW ]]; then
            T=${BASH_REMATCH[1]}
            [ "${#T}" -le 120 ] || fail "line $((P + 2)): a new follow-up's title is over 120 bytes"
            printf '%s' "$T" | grep -q '[][`*()<>|#\\@]' \
                && fail "line $((P + 2)): a new follow-up's title holds a markdown or HTML character, or an @: [${T:0:80}]"
            FU_JSON=$(printf '%s' "$FU_JSON" | jq -c --arg t "$T" '. + [{kind: "new", title: $t}]')
        elif [[ $ITEM =~ $RE_AMEND ]]; then
            AT=${BASH_REMATCH[1]} AW=${BASH_REMATCH[2]}
            [[ $AT =~ $RE_TAG ]] || fail "line $((P + 2)): amend names $AT, not a milestone's heading tag"
            FU_JSON=$(printf '%s' "$FU_JSON" | jq -c --arg t "$AT" --arg w "$AW" '. + [{kind: "amend", tag: $t, what: $w}]')
        else
            fail "line $((P + 2)): a follow-up is \`new: <title>\` or \`amend <tag>: <what>\`, separated by \"; \"; read [${ITEM:0:80}]"
        fi
    done
fi

# The verdict's rules.
NOT_HELD=$(printf '%s' "$CLAUSES" | awk -F'\t' '$1 == "not held" { n++ } END { print n + 0 }')
case "$VERDICT" in
    verified|"verified with follow-ups")
        [ "$NOT_HELD" = 0 ] || fail "line 1: $VERDICT needs every clause held; $NOT_HELD isn't"
        [ "$FIT" = fits ] || fail "line $((P + 1)): $VERDICT needs the work to fit the strategy"
        [ "$CHANGES" = none ] || fail "line $((P + 3)): $VERDICT names no change; a change needed is a changes needed verdict"
        if [ "$VERDICT" = verified ]; then
            [ "$FU" = none ] || fail "line $((P + 2)): verified names no follow-up; one with follow-ups is verified with follow-ups"
        else
            [ "$FU" != none ] || fail "line $((P + 2)): verified with follow-ups names at least one follow-up"
        fi ;;
    "changes needed")
        { [ "$NOT_HELD" -gt 0 ] || [ "$FIT" = "does not fit" ]; } \
            || fail "line 1: changes needed needs a clause not held or the work not fitting the strategy; every clause is held and it fits"
        [ "$CHANGES" != none ] || fail "line $((P + 3)): changes needed names what must change" ;;
esac

printf '%s' "$CLAUSES" | jq -R -s -c --arg tag "$TAG" --arg v "$VERDICT" --arg by "$BY" --arg on "$ON" \
    --arg sp "$SRC_PATH" --arg sc "$SRC_COMMIT" --argjson work "$WORK_JSON" --arg fit "$FIT" --arg why "$FIT_WHY" \
    --argjson fu "$FU_JSON" --arg ch "$CHANGES" '
    split("\n") | map(select(. != "") | (index("\t")) as $i | {held: (.[0:$i] == "held"), why: .[$i + 1:]})
    | to_entries | map({n: (.key + 1)} + .value) as $c
    | {tag: $tag, verdict: $v, checked_by: $by, checked_on: $on, source: {path: $sp, commit: $sc},
       work_checked: $work, clauses: $c, strategy_fit: $fit, strategy_why: $why,
       follow_ups: $fu, changes_needed: $ch}' || die2 "jq failed"
