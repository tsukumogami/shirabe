# board-lib.sh -- shared by /coordinate's board, land and merge scripts
# (board-verdict.sh, board-record.sh, land-check.sh, land-merge.sh,
# merge-confirm.sh, merged-facts.sh). Sourced, never run: the caller sets HERE
# (its own directory) and PROG first.
#
# It holds the closed argument patterns, one bounded GitHub read (bl_gh), the
# session-log reads these scripts share (a sealed capture, the unit's
# repository, the merge posture), and the merged-blob comparison. Every GitHub
# read here is `gh api --method GET`, a GraphQL query, or `gh pr view`; there
# is no write in this file, so a lint over a check script and this file finds
# only reads.
#
# It sources record-common.sh beside it for what every /coordinate script
# shares: the topic grammar (RE_TOPIC), the pull request link (lib_pr_link),
# and the token scrub. The session log is read only through coord-log.sh.
#
# The deadline: a check state's default action has 30 seconds. Every read
# checks bash's SECONDS against BL_DEADLINE (24) before it starts, and a
# watchdog kills a read still running at the deadline, so a hung gh can't hold
# the action past its limit. BOARD_DEADLINE_SECS may lower it (1..24) for the
# deadline test; it can never raise it.
#
# Requires: bash 3.2+, jq, gh, and coord-log.sh and record-common.sh beside
# the caller.

. "$HERE/record-common.sh" || { echo "${PROG:-board-lib}: cannot source record-common.sh" >&2; exit 2; }

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
# redacted by record-common.sh's lib_redact, the same token rule lib_scrub
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
    local out=$1 attempt=1 rc remain pid wd
    shift
    rm -f "$out.fail"
    while :; do
        remain=$(bl_left)
        if [ "$remain" -le 0 ]; then echo deadline > "$out.fail"; return 1; fi
        gh "$@" </dev/null >"$out" 2>"$out.err" &
        pid=$!
        # The watchdog: kills the read at the deadline. Its own sleep is killed
        # with it (the TERM trap), so no timer outlives the script.
        ( trap 'kill $sp 2>/dev/null; exit 0' TERM
          sleep "$remain" & sp=$!
          wait $sp
          kill "$pid" 2>/dev/null ) >/dev/null 2>&1 </dev/null &
        wd=$!
        wait "$pid"; rc=$?
        kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
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
# through record-holding.sh). A token carries only the number, so the record
# says where it lives; no row, or rows naming #<pr> in two repositories, is a
# failure rather than a guess. Returns 0 printed; 1 no row links #<pr>; 3
# rows link #<pr> in two or more repositories; 4 the one row's repository
# isn't owner/repo; 2 the holdings couldn't be read.
bl_unit_repo() {
    local rows repos n
    rows=$(bash "$HERE/record-holding.sh" --session "$1" --list) || {
        echo "$PROG: the record's holdings could not be read" >&2; return 2; }
    repos=$(printf '%s' "$rows" | jq -r -L "$HERE" --arg n "$2" 'include "record-codec";
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
# record-confirm.sh applies after posture_ask. 1 no permitted answer, or no such
# row; 2 read failure.
bl_human_holds_merge() {
    local s=$1 ev facts repo ref scope name min body
    ev=$(bash "$HERE/coord-log.sh" evidence --session "$s" --state posture_ask 2>/dev/null)
    case $? in 0) ;; 1) return 1 ;; *) return 2 ;; esac
    [ "$(printf '%s' "$ev" | jq -r '.fields.merge // ""')" = permitted ] || return 1
    min=$(printf '%s' "$ev" | jq -r '.timestamp' | cut -c1-16)
    [[ $min =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$ ]] || return 1
    facts=$(bash "$HERE/coord-log.sh" run-facts --session "$s" 2>/dev/null) || return 2
    repo=$(printf '%s' "$facts" | jq -r '.repo // ""')
    ref=$(printf '%s' "$facts" | jq -r '.ref // ""')
    scope=$(printf '%s' "$facts" | jq -r '.scope // ""')
    name=$(printf '%s' "$facts" | jq -r '.name // ""')
    bl_repo_ok "$repo" && bl_pr_ok "$ref" || return 2
    case "$scope" in roadmap|discipline) ;; *) return 2 ;; esac
    local t
    t=$(mktemp "${TMPDIR:-/tmp}/board-lib.XXXXXX") || return 2
    if ! bl_gh "$t" api --method GET "repos/$repo/issues/$ref"; then rm -f "$t" "$t.err" "$t.fail"; return 2; fi
    body=$(jq -r '.body // ""' "$t")
    rm -f "$t" "$t.err" "$t.fail"
    local cont=issue
    [ "$scope" = discipline ] && cont=pr
    printf '%s' "$body" | bash "$HERE/record-parse.sh" --container "$cont" --expect-scope "$scope:$name" - 2>/dev/null \
        | jq -e --arg min "$min" '
            [.reversals[]? | select(.from == "the human"
                and (((.reversed // "") + " " + (.now // "")) | ascii_downcase | contains("posture"))
                and ((.date // "")[0:16] >= $min))] | length > 0' >/dev/null
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

# bl_path_uri <path>: URL-encode each segment of a repository path.
bl_path_uri() { jq -rn --arg p "$1" '$p | split("/") | map(@uri) | join("/")'; }

# bl_merge_compare <repo> <pr> <sha>: prints merged, unconfirmed or
# not-merged. merged needs the pull request MERGED and every file it changed
# to have the same blob on the default branch as at <sha> (a file absent at
# <sha>, deleted by the pull request, must be absent there too). Blob reads
# run in parallel, six at a time. Returns 0 printed; 2 a read failed.
bl_merge_compare() {
    local repo=$1 pr=$2 sha=$3 d state def n i p ref k a b
    d=$(mktemp -d "${TMPDIR:-/tmp}/board-merge.XXXXXX") || return 2
    if ! bl_gh "$d/pr" pr view "$pr" --repo "$repo" --json state,files; then rm -rf "$d"; return 2; fi
    state=$(jq -r '.state // ""' "$d/pr")
    case "$state" in
        MERGED) ;;
        OPEN|CLOSED) rm -rf "$d"; echo not-merged; return 0 ;;
        *) echo "$PROG: pull request state [$state]" >&2; rm -rf "$d"; return 2 ;;
    esac
    jq -r '.files[]?.path' "$d/pr" > "$d/paths" || { rm -rf "$d"; return 2; }
    if ! bl_gh "$d/repo" api --method GET "repos/$repo"; then rm -rf "$d"; return 2; fi
    def=$(jq -r '.default_branch // ""' "$d/repo")
    bl_branch_ok "$def" || { echo "$PROG: default branch [$def]" >&2; rm -rf "$d"; return 2; }
    n=0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        n=$((n + 1))
        printf '%s\n' "$p" > "$d/path.$n"
        for ref in "$def" "$sha"; do
            [ "$ref" = "$def" ] && k=def || k=sha
            ( bl_gh "$d/blob.$n.$k" api --method GET "repos/$repo/contents/$(bl_path_uri "$p")?ref=$(jq -rn --arg r "$ref" '$r | @uri')" ) &
        done
        [ $((n % 3)) -eq 0 ] && wait
    done < "$d/paths"
    wait
    local result=merged
    i=1
    while [ "$i" -le "$n" ]; do
        for k in def sha; do
            if [ -f "$d/blob.$i.$k.fail" ]; then
                if [ "$(cat "$d/blob.$i.$k.fail")" = notfound ]; then
                    printf 'absent' > "$d/sha.$i.$k"
                else
                    rm -rf "$d"; return 2
                fi
            else
                jq -r 'if type == "object" and .type == "file" and (.sha | type) == "string" then .sha else "not-a-file" end' "$d/blob.$i.$k" > "$d/sha.$i.$k" || { rm -rf "$d"; return 2; }
            fi
        done
        a=$(cat "$d/sha.$i.def"); b=$(cat "$d/sha.$i.sha")
        if [ "$a" != "$b" ] || [ "$a" = not-a-file ]; then
            echo "$PROG: $(cat "$d/path.$i") differs on $def ($a) from $sha ($b)" >&2
            result=unconfirmed
        fi
        i=$((i + 1))
    done
    rm -rf "$d"
    echo "$result"
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
