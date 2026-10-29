# board-lib.sh -- shared by /coordinate's board, land and merge scripts
# (board-verdict.sh, board-record.sh, land-check.sh, land-merge.sh,
# merge-confirm.sh, merged-facts.sh). Sourced, never run: the caller sets HERE
# (its own directory) and PROG first.
#
# It holds the closed argument patterns, one bounded GitHub read (bl_gh), the
# session-log reads these scripts share (a sealed capture, the unit's
# repository, the merge posture), and the merge confirmation. Every GitHub
# read here is `gh api --method GET`, a GraphQL query, or `gh pr view`; there
# is no write in this file, so a lint over a check script and this file finds
# only reads.
#
# It sources state-common.sh beside it for what every /coordinate script
# shares: the topic grammar (RE_TOPIC), the pull request link (lib_pr_link),
# and the token scrub. The session log is read only through coord-log.sh.
#
# The deadline: a check state's default action has 30 seconds. Every read
# checks bash's SECONDS against BL_DEADLINE (24) before it starts, and
# dispatch-common.sh's dc_with_deadline kills a read still running at the
# deadline, so a hung gh can't hold the action past its limit.
# BOARD_DEADLINE_SECS may lower it (1..24) for the deadline test; it can never
# raise it.
#
# Requires: bash 3.2+, jq, gh, and coord-log.sh, state-common.sh and
# dispatch-common.sh beside the caller.

. "$HERE/state-common.sh" || { echo "${PROG:-board-lib}: cannot source state-common.sh" >&2; exit 2; }
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh" || { echo "${PROG:-board-lib}: cannot source dispatch-common.sh" >&2; exit 2; }

BL_RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
BL_RE_PR='^[1-9][0-9]*$'
BL_RE_SHA='^[0-9a-f]{40}$'
BL_RE_BRANCH='^[A-Za-z0-9._/-]+$'
BL_RE_SESSION='^[A-Za-z0-9._-]+$'
KOTO=${KOTO_BIN:-koto}

bl_repo_ok() {
    [[ $1 =~ $BL_RE_REPO ]] || return 1
    case "/$1/" in */./*|*/../*) return 1 ;; esac
    return 0
}
bl_pr_ok() { [[ $1 =~ $BL_RE_PR ]] && [ ${#1} -le 9 ]; }
bl_sha_ok() { [[ $1 =~ $BL_RE_SHA ]]; }
bl_branch_ok() {
    [[ $1 =~ $BL_RE_BRANCH ]] || return 1
    case "$1" in *..*|/*|*/|*//*|.*) return 1 ;; esac
    return 0
}
bl_session_ok() { [[ $1 =~ $BL_RE_SESSION ]]; }
bl_topic_ok() { [[ $1 =~ $RE_TOPIC ]]; }

BL_DEADLINE=24
case "${BOARD_DEADLINE_SECS-}" in
    [1-9]|1[0-9]|2[0-4]) BL_DEADLINE=$BOARD_DEADLINE_SECS ;;
esac
BL_START=$SECONDS
bl_left() { echo $((BL_DEADLINE - (SECONDS - BL_START))); }

# bl_scrub: gh's error text relayed line by line (bl_gh prefixes each line),
# redacted by state-common.sh's lib_redact, the same token rule lib_scrub
# uses. It keeps more than lib_scrub because it relays the whole error rather
# than quoting it inside one line: up to 20 lines of 300 characters each.
bl_scrub() {
    lib_redact | head -20 | cut -c1-300
}

# bl_gh <out> <gh args...>: one read, stdin from /dev/null, stdout to <out>,
# stderr to <out>.err. At most two attempts, 1 s apart; a 404 isn't retried,
# and neither is a refusal (HTTP 403, or GraphQL's "Resource not accessible",
# which gh reports without a status): the token can't read that source, and a
# second attempt won't change it. Returns 0 read; 1 failed, with <out>.fail
# holding `deadline`, `notfound`, `refused` or `read`.
bl_gh() {
    local out=$1 attempt=1 rc remain
    shift
    rm -f "$out.fail"
    while :; do
        remain=$(bl_left)
        if [ "$remain" -le 0 ]; then echo deadline > "$out.fail"; return 1; fi
        dc_with_deadline "$remain" gh "$@" </dev/null >"$out" 2>"$out.err"; rc=$?
        [ "$rc" -eq 0 ] && return 0
        if [ "$(bl_left)" -le 0 ]; then echo deadline > "$out.fail"; return 1; fi
        bl_scrub < "$out.err" | sed "s/^/$PROG: gh: /" >&2
        if grep -q 'HTTP 404' "$out.err" 2>/dev/null; then echo notfound > "$out.fail"; return 1; fi
        if grep -Eq 'HTTP 403|Resource not accessible' "$out.err" 2>/dev/null; then echo refused > "$out.fail"; return 1; fi
        if [ "$attempt" -ge 2 ]; then echo read > "$out.fail"; return 1; fi
        attempt=2
        sleep 1
    done
}

# bl_capture <session> <NAME> <state> [--any-visit] [--for KEY]: the latest
# engine-written capture NAME (with --for, the latest naming KEY), printed
# without its seal, only when coord-log.sh finds that seal valid for <state>
# (sealed at the latest entry into it, or with --any-visit at any real
# entry). Returns 0 found and valid; 1 absent or invalid; 2 read failure.
bl_capture() {
    local s=$1 name=$2 state=$3 cap rc
    shift 3
    local extra=
    while [ $# -gt 0 ]; do
        case "$1" in
            --any-visit) extra="$extra --any-visit"; shift ;;
            --for) [ $# -ge 2 ] || return 2; bl_pr_ok "$2" || bl_topic_ok "$2" || return 2; extra="$extra --for $2"; shift 2 ;;
            *) return 2 ;;
        esac
    done
    # $extra holds only fixed flags and a value held to its pattern above.
    cap=$(bash "$HERE/coord-log.sh" capture --session "$s" --name "$name" --state "$state" $extra); rc=$?
    [ $rc -eq 0 ] || return $rc
    case "$cap" in *' sealed:'*) ;; *) return 1 ;; esac
    printf '%s\n' "${cap% sealed:*}"
}

# bl_seal <session> <state> <token> <no-seal>: print the check's verdict,
# sealed to the latest entry into <state> unless <no-seal> is 1 (tests).
bl_seal() {
    if [ "$4" = 1 ]; then printf '%s\n' "$3"; return 0; fi
    local out
    out=$(bash "$HERE/coord-log.sh" seal --session "$1" --state "$2" --token "$3") || {
        echo "$PROG: could not seal the verdict" >&2; return 2; }
    printf '%s\n' "$out"
}

# bl_unit_repo <session> <pr>: the repository of the unit whose pull request
# is #<pr>, from the Holdings row whose Pull request cell links it (read live
# through state-holding.sh). A token carries only the number, so the record
# says where it lives; no row, or rows naming #<pr> in two repositories, is a
# failure rather than a guess. Returns 0 printed; 1 no row links #<pr>; 3
# rows link #<pr> in two or more repositories; 4 the one row's repository
# isn't owner/repo; 2 the holdings couldn't be read.
bl_unit_repo() {
    local rows repos n
    rows=$(bash "$HERE/state-holding.sh" --session "$1" --list) || {
        echo "$PROG: the record's holdings could not be read" >&2; return 2; }
    repos=$(printf '%s' "$rows" | jq -r -L "$HERE" --arg n "$2" 'include "state-schema";
        [.[]? | .pull_request // "" | pr_link | select(.number == $n) | .repo] | unique | .[]') || {
        echo "$PROG: the holdings list is not JSON" >&2; return 2; }
    n=$(printf '%s' "$repos" | grep -c . )
    if [ "$n" -eq 0 ]; then
        echo "$PROG: no holding links pull request #$2; can't tell its repository" >&2
        return 1
    fi
    if [ "$n" -gt 1 ]; then
        echo "$PROG: holdings link pull request #$2 in $n repositories; can't tell which" >&2
        return 3
    fi
    bl_repo_ok "$repos" || { echo "$PROG: the holding for #$2 links [$repos], not owner/repo" >&2; return 4; }
    printf '%s\n' "$repos"
}

# bl_posture_rank <v>: permit 0, unread 1, confirm 2, deny 3 (stricter is higher).
bl_posture_rank() {
    case "$1" in permit) echo 0 ;; unread) echo 1 ;; confirm) echo 2 ;; deny) echo 3 ;; *) echo 9 ;; esac
}
# bl_posture_merge <token>: the merge step's value in a posture token
# (`readable|unread merge<sep><v> ...`). The separator may be `=` or `:`:
# koto refuses a capture holding `=`, so the captured form may use `:`.
bl_posture_merge() {
    local w
    case "$1" in readable\ *|unread\ *) ;; *) return 0 ;; esac
    set -f
    for w in $1; do
        case "$w" in merge=*|merge:*) set +f; printf '%s\n' "${w#merge?}"; return 0 ;; esac
    done
    set +f
}

# bl_human_holds_merge <session>: 0 when the human's answer to posture_ask
# permits the merge, and that answer is on GitHub now. The answer is the
# session log's latest evidence_submitted in state posture_ask; only its
# `merge` field reading `permitted` counts (never Reversals prose, which fixes no
# phrasing and can't tell who holds which step). It must also be on the live
# record: a Reversals row from `the human`, whose Reversed or Now mentions the
# posture, dated at or after that evidence (to the minute) -- the test
# state-confirm.sh applies after posture_ask. 1 no permitted answer, or no such
# row; 2 read failure.
bl_human_holds_merge() {
    local s=$1 ev min
    ev=$(bash "$HERE/coord-log.sh" evidence --session "$s" --state posture_ask 2>/dev/null)
    case $? in 0) ;; 1) return 1 ;; *) return 2 ;; esac
    [ "$(printf '%s' "$ev" | jq -r '.fields.merge // ""')" = permitted ] || return 1
    min=$(printf '%s' "$ev" | jq -r '.timestamp' | cut -c1-16)
    [[ $min =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$ ]] || return 1
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/board-posture.XXXXXX") || return 2
    rs_record_api "$d/parsed" "$s" reversals 2>/dev/null || { rm -rf "$d"; return 2; }
    jq -e --arg min "$min" '
            [.reversals[]? | select(.from == "the human"
                and (((.reversed // "") + " " + (.now // "")) | ascii_downcase | contains("posture"))
                and ((.date // "")[0:16] >= $min))] | length > 0' "$d/parsed" >/dev/null
    local rc=$?
    rm -rf "$d"
    return $rc
}

# bl_merge_posture <session>: the merge step's effective posture, printed as
# permit, deny or confirm. The start's read (the POSTURE capture, sealed at
# start_posture) and a fresh posture-read.sh can only narrow each other: the
# stricter wins (deny > confirm > unread > permit). An unread result becomes
# permit only when the start read was unread for merge and the human's answer
# at posture_ask permitted the merge and is on GitHub now (bl_human_holds_merge),
# and confirm otherwise. A missing or invalid start capture counts as unread
# with no recorded answer. Returns 0 printed; 2 the fresh read failed.
bl_merge_posture() {
    local s=$1 start start_v start_known=1 now now_v eff rs rn
    start=$(bl_capture "$s" POSTURE start_posture 2>/dev/null)
    start_v=$(bl_posture_merge "$start")
    case "$start_v" in permit|deny|confirm|unread) ;; *) start_v=unread; start_known=0 ;; esac
    now=$(bash "$HERE/posture-read.sh" --session "$s" --no-seal) || { echo "$PROG: the posture re-read failed" >&2; return 2; }
    now_v=$(bl_posture_merge "$now")
    case "$now_v" in permit|deny|confirm|unread) ;; *) echo "$PROG: the posture re-read printed [$now]" >&2; return 2 ;; esac
    rs=$(bl_posture_rank "$start_v"); rn=$(bl_posture_rank "$now_v")
    eff=$start_v
    [ "$rn" -gt "$rs" ] && eff=$now_v
    if [ "$eff" = unread ]; then
        eff=confirm
        if [ "$start_known" = 1 ] && [ "$start_v" = unread ]; then
            bl_human_holds_merge "$s" && eff=permit
        fi
    fi
    printf '%s\n' "$eff"
}

# bl_merge_compare <repo> <pr> <sha>: prints merged, unconfirmed or
# not-merged, from GitHub's own record of the merge, in three reads whatever
# the pull request's size (each bl_gh, which tries a failed read once more
# under the same deadline): the pull request (its state, the head it merged
# and its merge commit), the repository (its default branch), and one
# comparison of the default branch with the merge commit. merged needs the
# pull request MERGED, the head GitHub merged to be <sha>, and the merge
# commit reachable from the default branch (the comparison reads behind or
# identical). A merged head other than <sha>, or a merge commit not on the
# default branch, is unconfirmed; an open or closed pull request is
# not-merged. It relies on headRefOid to pin the content: GitHub builds the
# squash commit from the head it records (a plain merge commit has that head
# as a parent, and a rebase replays its commits), so what GitHub merged is the
# verified head's change, whatever the method. It confirms the merge event,
# not what the default branch holds now: a later change to the same files
# doesn't bear on it, and a revert after the merge still reads merged. It
# makes no per-file check (the issue's squash file-coverage check included),
# since a file list would tie the call count to the pull request's size.
# The comparison is with the default branch, as before, so a pull request
# merged into another base reads unconfirmed. A comparison GitHub answers
# with not found is a read failure, not unconfirmed: from here it can't be
# told from a merge commit GitHub hasn't indexed yet. Returns 0 printed; 2 a
# read failed, or the record is malformed (no merge commit on a merged pull
# request, a head or status that isn't one).
bl_merge_compare() {
    local repo=$1 pr=$2 sha=$3 d rec state head mc def st
    d=$(mktemp -d "${TMPDIR:-/tmp}/board-merge.XXXXXX") || return 2
    if ! bl_gh "$d/pr" pr view "$pr" --repo "$repo" --json state,headRefOid,mergeCommit; then rm -rf "$d"; return 2; fi
    # One jq for the three fields, joined by `|` rather than a tab, so an
    # empty field stays in place (read collapses runs of whitespace IFS).
    rec=$(jq -r '[(.state // ""), (.headRefOid // ""), ((.mergeCommit // {}) | .oid? // "")] | map(tostring) | join("|")' "$d/pr") \
        || { echo "$PROG: the pull request's record isn't JSON" >&2; rm -rf "$d"; return 2; }
    IFS='|' read -r state head mc <<EOF
$rec
EOF
    case "$state" in
        MERGED) ;;
        OPEN|CLOSED) rm -rf "$d"; echo not-merged; return 0 ;;
        *) echo "$PROG: pull request state [$state]" >&2; rm -rf "$d"; return 2 ;;
    esac
    bl_sha_ok "$head" || { echo "$PROG: #$pr merged head [$head] is not a sha" >&2; rm -rf "$d"; return 2; }
    bl_sha_ok "$mc" || { echo "$PROG: #$pr is merged with no merge commit [$mc]" >&2; rm -rf "$d"; return 2; }
    if [ "$head" != "$sha" ]; then
        echo "$PROG: #$pr merged head $head, not the verified $sha" >&2
        rm -rf "$d"; echo unconfirmed; return 0
    fi
    if ! bl_gh "$d/repo" api --method GET "repos/$repo"; then rm -rf "$d"; return 2; fi
    def=$(jq -r '.default_branch // ""' "$d/repo")
    bl_branch_ok "$def" || { echo "$PROG: default branch [$def]" >&2; rm -rf "$d"; return 2; }
    if ! bl_gh "$d/cmp" api --method GET "repos/$repo/compare/$def...$mc"; then rm -rf "$d"; return 2; fi
    st=$(jq -r '.status // ""' "$d/cmp")
    rm -rf "$d"
    case "$st" in
        behind|identical) echo merged ;;
        ahead|diverged) echo "$PROG: #$pr's merge commit $mc is not on $def ($st)" >&2; echo unconfirmed ;;
        *) echo "$PROG: comparison status [$st]" >&2; return 2 ;;
    esac
}

# bl_reviewed_fresh <repo> <base-branch> <reviewed> <head>: is the head the
# reviewed head, or that head plus merge-ins of the base branch and nothing
# else? (docs/designs/current/DESIGN-coordinate-merge-policy.md, Decision 2.)
# Walks the head's first-parent chain toward <reviewed>; at each commit C it
# needs two parents P1 and P2, P2 already on the base branch (the comparison
# of the base with P2 reads behind or identical), and the files C changed
# against P1 among the files the base changed from its merge base with P1 to
# P2. Prints `fresh` or `stale <reason>`, the reason one of not-a-merge,
# not-on-base, files, too-many-merges or too-many-files. Returns 0 printed;
# 2 a read failed.
BL_MAX_MERGEINS=10
bl_reviewed_fresh() {
    local repo=$1 base=$2 r=$3 c=$4 d n=0 p1 p2 st
    if [ "$r" = "$c" ]; then echo fresh; return 0; fi
    d=$(mktemp -d "${TMPDIR:-/tmp}/board-fresh.XXXXXX") || return 2
    while [ "$c" != "$r" ]; do
        n=$((n + 1))
        if [ "$n" -gt "$BL_MAX_MERGEINS" ]; then rm -rf "$d"; echo "stale too-many-merges"; return 0; fi
        bl_gh "$d/c" api --method GET "repos/$repo/commits/$c" || { rm -rf "$d"; return 2; }
        if [ "$(jq -r '.parents | length' "$d/c")" != 2 ]; then rm -rf "$d"; echo "stale not-a-merge"; return 0; fi
        p1=$(jq -r '.parents[0].sha' "$d/c")
        p2=$(jq -r '.parents[1].sha' "$d/c")
        if ! bl_sha_ok "$p1" || ! bl_sha_ok "$p2"; then
            echo "$PROG: commit $c has malformed parents" >&2; rm -rf "$d"; return 2
        fi
        bl_gh "$d/b" api --method GET "repos/$repo/compare/$base...$p2" || { rm -rf "$d"; return 2; }
        st=$(jq -r '.status // ""' "$d/b")
        case "$st" in behind|identical) ;; *) rm -rf "$d"; echo "stale not-on-base"; return 0 ;; esac
        bl_gh "$d/m" api --method GET "repos/$repo/compare/$p1...$p2" || { rm -rf "$d"; return 2; }
        bl_gh "$d/x" api --method GET "repos/$repo/compare/$p1...$c" || { rm -rf "$d"; return 2; }
        if [ "$(jq '.files // [] | length' "$d/m")" -ge 300 ] || [ "$(jq '.files // [] | length' "$d/x")" -ge 300 ]; then
            rm -rf "$d"; echo "stale too-many-files"; return 0
        fi
        if [ "$(jq -n --slurpfile m "$d/m" --slurpfile x "$d/x" \
                '([$x[0].files[]?.filename] - [$m[0].files[]?.filename]) | length')" != 0 ]; then
            rm -rf "$d"; echo "stale files"; return 0
        fi
        c=$p1
    done
    rm -rf "$d"
    echo fresh
}

# bl_review_evidence <session> <repo> <pr>: the worker's review round for
# <repo>#<pr>, as panel-evidence.sh --round's JSON plus `source`. For each
# Holdings row linking the pull request, latest row first (state-holding.sh
# --list prints rows in the record's order, oldest first, so the list is
# reversed), two places are read, in this order:
#   1. When the row returns on a leg (`leg <request>:<leg>`): the leg's bound
#      child from `koto request get`, and that session's review_round.json
#      (review-round.sh writes it). `source` is `session`, and `session`
#      names it.
#   2. The round the worker's own report carried: the `review_round=` line of
#      the result block render-result.sh prints, in the latest report or
#      progress message from the row's Worker that has one, as the
#      coordinator submitted it at `wait` (coord-log.sh result-line, over
#      <session>'s own log). `source` is `report`; `session` is the block's
#      `session=` value and `reported` the message's log sequence. This is
#      how a worker with no leg, or whose session this host's store can't
#      read, gives the land step its round: the coordinator's own session is
#      the one record it can read wherever it runs.
# Neither (no leg, no bound child, a request this host's store doesn't hold,
# no key, no report carrying a round) is `{"status":"absent","source":"none"}`.
# The pull request body is never read: a Review panel table there is not a
# round. Returns 0 printed; 2 the holdings, a request, a session or the log
# couldn't be read, or the round couldn't be judged, so the tick reads again
# rather than call the round missing.
bl_review_evidence() {
    local s=$1 repo=$2 pr=$3 rows rws rp worker rc ev d line
    rows=$(bash "$HERE/state-holding.sh" --session "$s" --list) || {
        echo "$PROG: the record's holdings could not be read" >&2; return 2; }
    # One line per row: its return path (or `-`) and its Worker, tab-separated.
    rws=$(printf '%s' "$rows" | jq -r -L "$HERE" --arg n "$pr" --arg r "$repo" 'include "state-schema";
        [.[]? | select(any(.pull_request // "" | pr_link; .number == $n and (.repo | ascii_downcase) == ($r | ascii_downcase)))
         | [(.return_path // "" | strings | select(test("^leg [^: ]+:[^: ]+$")) | ltrimstr("leg ")) // "-",
            (.worker // "" | strings)] | join("\t")]
        | reverse | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end) | .[]') || {
        echo "$PROG: the holdings list is not JSON" >&2; return 2; }
    d=$(mktemp -d "${TMPDIR:-/tmp}/board-round.XXXXXX") || return 2
    while IFS='	' read -r rp worker; do
        [ -n "$rp" ] || continue
        ev=$(bl_leg_round "$rp" "$d")
        rc=$?
        case "$rc" in
            0) rm -rf "$d"; printf '%s\n' "$ev"; return 0 ;;
            1) ;;
            *) rm -rf "$d"; return 2 ;;
        esac
        [ -n "$worker" ] && bl_topic_ok "$worker" || continue
        line=$(bash "$HERE/coord-log.sh" result-line --session "$s" --unit "$worker" --line review_round 2>"$d/err")
        case $? in
            0) ;;
            1) continue ;;
            *) echo "$PROG: $worker's reports couldn't be read: $(head -1 "$d/err")" >&2; rm -rf "$d"; return 2 ;;
        esac
        printf '%s' "$line" | jq -r '.value' > "$d/round" || { rm -rf "$d"; return 2; }
        ev=$(bash "$HERE/panel-evidence.sh" --round "$d/round") || { rm -rf "$d"; return 2; }
        rm -rf "$d"
        printf '%s' "$ev" | jq -c --argjson l "$line" '. + {source: "report", session: $l.session, reported: $l.seq}'
        return 0
    done <<EOF
$rws
EOF
    rm -rf "$d"
    echo '{"status":"absent","source":"none"}'
}

# bl_leg_round <request>:<leg> <scratch-dir>: the review round in the session
# a leg is bound to, printed as bl_review_evidence's JSON with `source:
# "session"`. Returns 0 printed; 1 no round there (`-` for no leg, a malformed
# leg, no bound child, a request this host's store doesn't hold, or no key);
# 2 a read failed or the round couldn't be judged.
bl_leg_round() {
    local rp=$1 d=$2 req leg view child rc ev
    [ "$rp" != - ] || return 1
    req=${rp%%:*} leg=${rp#*:}
    [[ $req =~ $DC_RE_REQ ]] && [[ $leg =~ $DC_RE_LEG ]] || return 1
    view=$("$KOTO" request get "$req" </dev/null 2>"$d/err")
    rc=$?
    case "$rc" in
        0) ;;
        # koto's 2 is a request this host's store doesn't hold: the worker
        # ran elsewhere, so its session isn't here to read.
        2) return 1 ;;
        *) echo "$PROG: request $req couldn't be read: $(head -1 "$d/err")" >&2; return 2 ;;
    esac
    child=$(printf '%s' "$view" | jq -r --arg l "$leg" '(.request // .) | .legs[$l].bound_child // "" | strings') || {
        echo "$PROG: request $req is not JSON" >&2; return 2; }
    [ -n "$child" ] && bl_session_ok "$child" || return 1
    # koto's 1 is no such key: the worker recorded no round there. Any other
    # failure is a read that didn't happen.
    rc=0
    "$KOTO" context exists "$child" review_round.json </dev/null >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) ;;
        1) return 1 ;;
        *) echo "$PROG: $child's review_round.json couldn't be checked (koto exited $rc)" >&2; return 2 ;;
    esac
    "$KOTO" context get "$child" review_round.json </dev/null > "$d/round" 2>"$d/err" || {
        echo "$PROG: $child's review_round.json couldn't be read: $(head -1 "$d/err")" >&2; return 2; }
    ev=$(bash "$HERE/panel-evidence.sh" --round "$d/round") || return 2
    printf '%s' "$ev" | jq -c --arg c "$child" '. + {source: "session", session: $c}'
}

# bl_holds_on <session> <repo> <pr>: the record's holds on <repo>#<pr>, each
# evaluated live (docs/designs/current/DESIGN-coordinate-merge-policy.md,
# Decision 6), printed as a JSON array of the hold's row plus `state`:
#   met         `lifted` with a Lifted cell; `merged R#m` with R#m MERGED;
#               `tag R T` with the tag on R
#   unmet       otherwise
#   unreadable  the condition's read failed (a refusal, a server error, a
#               missing pull request), other than a missing tag
# The record is read live, as bl_human_holds_merge reads it. Returns 0
# printed; 2 the record couldn't be read or parsed, or a read ran out of the
# check's time (the tick re-runs it rather than call the hold unreadable).
bl_holds_on() {
    local s=$1 repo=$2 pr=$3 d
    d=$(mktemp -d "${TMPDIR:-/tmp}/board-holds.XXXXXX") || return 2
    rs_record_api "$d/parsed" "$s" holds || { rm -rf "$d"; return 2; }
    bl_holds_eval "$d/parsed" "$repo" "$pr"
    local rc=$?
    rm -rf "$d"
    return $rc
}

# bl_pauses_on <parsed-record-file> <repo> <pr>: the record's pauses as
# pause-read.sh evaluates them, for the unit of the Holdings row whose pull
# request is <repo>#<pr>, printed as pause-read.sh's JSON plus `unit` and
# `paused` (the id of the pause that holds that unit, or null)
# (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1). Returns 0
# printed; 2 the file couldn't be read or a condition's read ran out of time.
bl_pauses_on() {
    local f=$1 repo=$2 pr=$3 unit
    unit=$(jq -r --arg r "$repo" --arg n "$pr" \
        '[.holdings[] | select(.pull_request | test("^\\[#" + $n + "\\]\\(https://github\\.com/" + ($r | gsub("\\."; "\\.")) + "/pull/" + $n + "\\)$"; "i")) | .unit][0] // ""' "$f") || return 2
    jq '{standing: (.standing // [])}' "$f" > "$f.standing" || return 2
    jq -nc --arg u "$unit" 'if $u == "" then [] else [$u] end' > "$f.units" || return 2
    bash "$HERE/pause-read.sh" --standing "$f.standing" --units "$f.units" > "$f.pauses" || return 2
    jq -c --arg u "$unit" '. + {unit: $u, paused: (if $u == "" then .all else .covers[$u] end)}' "$f.pauses"
}

# bl_condition_state <until> <scratch-dir>: one hold or pause condition, read
# live, printed as `met`, `unmet` or `unreadable`:
#   lifted          unmet: only the row's own state (a Lifted cell, or a
#                   Standing row ended) ends it, and the caller reads that
#   time <T>        met once the host clock in UTC reaches minute T (BL_NOW,
#                   YYYY-MM-DDTHH:MMZ, stands in for the clock in tests)
#   merged R#m      met when R#m reads MERGED
#   tag R T         met when the tag exists on R
# A read that fails (a refusal, a server error, a missing pull request),
# other than a missing tag, is `unreadable`. Returns 0 printed; 2 a read ran
# out of the check's time (the tick re-runs it rather than call it
# unreadable). Shared by the holds and the pauses
# (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1).
bl_condition_state() {
    local until=$1 d=$2 now
    case "$until" in
        lifted) echo unmet ;;
        time\ *)
            # A malformed time can't be compared; it holds, as an unreadable
            # condition does.
            [[ ${until#time } =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$ ]] || { echo unreadable; return 0; }
            now=${BL_NOW:-$(date -u +%Y-%m-%dT%H:%MZ)}
            if [ "$now" \< "${until#time }" ]; then echo unmet; else echo met; fi ;;
        merged\ *)
            set -f; set -- $until; set +f
            if bl_gh "$d/m" pr view "${2##*#}" --repo "${2%#*}" --json state; then
                if [ "$(jq -r '.state // ""' "$d/m")" = MERGED ]; then echo met; else echo unmet; fi
            elif [ "$(cat "$d/m.fail")" = deadline ]; then return 2
            else echo unreadable; fi ;;
        tag\ *)
            set -f; set -- $until; set +f
            if bl_gh "$d/t" api --method GET "repos/$2/git/ref/tags/$3"; then echo met
            else
                case "$(cat "$d/t.fail")" in
                    notfound) echo unmet ;;
                    deadline) return 2 ;;
                    *) echo unreadable ;;
                esac
            fi ;;
        *) echo unreadable ;;
    esac
}

# bl_holds_eval <parsed-record-file> <repo> <pr>: bl_holds_on's evaluation,
# over a record already read (rs_record's JSON). Returns 0
# printed; 2 the file couldn't be read.
bl_holds_eval() {
    local f=$1 repo=$2 pr=$3 d n i until st
    d=$(mktemp -d "${TMPDIR:-/tmp}/board-holds.XXXXXX") || return 2
    jq -c --arg on "$repo#$pr" '[.holds[]? | select((.on | ascii_downcase) == ($on | ascii_downcase))]' "$f" > "$d/holds" \
        || { rm -rf "$d"; return 2; }
    n=$(jq 'length' "$d/holds")
    : > "$d/states"
    i=0
    while [ "$i" -lt "$n" ]; do
        until=$(jq -r --argjson i "$i" '.[$i].until' "$d/holds")
        case "$until" in
            lifted)
                if [ -n "$(jq -r --argjson i "$i" '.[$i].lifted' "$d/holds")" ]; then st=met; else st=unmet; fi ;;
            merged\ *|tag\ *)
                st=$(bl_condition_state "$until" "$d") || { rm -rf "$d"; return 2; } ;;
            *) st=unreadable ;;
        esac
        printf '%s\n' "$st" >> "$d/states"
        i=$((i + 1))
    done
    jq -c --slurpfile h "$d/holds" -R -s 'split("\n") | map(select(. != "")) as $s
        | [$h[0] | to_entries[] | .value + {state: $s[.key]}]' "$d/states"
    rm -rf "$d"
}
