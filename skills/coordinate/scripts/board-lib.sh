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
# The deadline: a check state's default action has 30 seconds. Every read
# checks bash's SECONDS against BL_DEADLINE (24) before it starts, and a
# watchdog kills a read still running at the deadline, so a hung gh can't hold
# the action past its limit. BOARD_DEADLINE_SECS may lower it (1..24) for the
# deadline test; it can never raise it.
#
# Requires: bash 3.2+, jq, gh, and coord-log.sh beside the caller.

BL_RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
BL_RE_PR='^[1-9][0-9]*$'
BL_RE_SHA='^[0-9a-f]{40}$'
BL_RE_BRANCH='^[A-Za-z0-9._/-]+$'
BL_RE_SESSION='^[A-Za-z0-9._-]+$'
BL_RE_TOPIC='^[A-Za-z0-9][A-Za-z0-9._-]*$'
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
bl_topic_ok() { [[ $1 =~ $BL_RE_TOPIC ]]; }

BL_DEADLINE=24
case "${BOARD_DEADLINE_SECS-}" in
    [1-9]|1[0-9]|2[0-4]) BL_DEADLINE=$BOARD_DEADLINE_SECS ;;
esac
BL_START=$SECONDS
bl_left() { echo $((BL_DEADLINE - (SECONDS - BL_START))); }

# bl_scrub: cap gh's error text and replace anything shaped like a GitHub
# token, so a relayed diagnostic can never carry a credential.
bl_scrub() {
    sed -e 's/gh[pousr]_[A-Za-z0-9_]\{6,\}/[redacted]/g' -e 's/github_pat_[A-Za-z0-9_]\{6,\}/[redacted]/g' \
        | tr -d '\000-\010\013\014\016-\037' | head -20 | cut -c1-300
}

# bl_gh <out> <gh args...>: one read, stdin from /dev/null, stdout to <out>,
# stderr to <out>.err. At most two attempts, 1 s apart; a 404 isn't retried.
# Returns 0 read; 1 failed, with <out>.fail holding `deadline`, `notfound` or
# `read`.
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
        if [ "$attempt" -ge 2 ]; then echo read > "$out.fail"; return 1; fi
        attempt=2
        sleep 1
    done
}

# bl_log <session>: the session's state log path.
bl_log() {
    local dir f
    dir=$("$KOTO" session dir "$1" 2>/dev/null) || return 1
    f="$dir/koto-$1.state.jsonl"
    [ -r "$f" ] || return 1
    printf '%s\n' "$f"
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
# failure rather than a guess. Returns 0 printed; 2 otherwise.
bl_unit_repo() {
    local rows repos n
    rows=$(bash "$HERE/record-holding.sh" --session "$1" --list) || {
        echo "$PROG: the record's holdings could not be read" >&2; return 2; }
    repos=$(printf '%s' "$rows" | jq -r --arg n "$2" '
        [.[]? | .pull_request // "" | capture("^\\[#(?<a>[0-9]+)\\]\\(https://github\\.com/(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?<b>[0-9]+)\\)$")?
         | select(.a == $n and .b == $n) | .r] | unique | .[]') || {
        echo "$PROG: the holdings list is not JSON" >&2; return 2; }
    n=$(printf '%s' "$repos" | grep -c . )
    if [ "$n" -ne 1 ]; then
        echo "$PROG: $n holdings link pull request #$2; can't tell its repository" >&2
        return 2
    fi
    bl_repo_ok "$repos" || return 2
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

# bl_human_holds_merge <session>: 0 when the live record carries a Reversals
# row, dated at or after the run's start, whose From is `the human`, which
# mentions the posture, and whose Now says the coordinator holds the merge
# (and doesn't negate it). That row is how an unreadable posture's answer
# reaches the workflow; it must be on GitHub now, not only in the
# coordinator's word. 1 absent; 2 read failure.
bl_human_holds_merge() {
    local s=$1 facts vars repo ref scope name start since body
    facts=$(bash "$HERE/coord-log.sh" run-facts --session "$s" 2>/dev/null) || return 2
    repo=$(printf '%s' "$facts" | jq -r '.repo // ""')
    ref=$(printf '%s' "$facts" | jq -r '.ref // ""')
    scope=$(printf '%s' "$facts" | jq -r '.scope // ""')
    name=$(printf '%s' "$facts" | jq -r '.name // ""')
    bl_repo_ok "$repo" && bl_pr_ok "$ref" || return 2
    case "$scope" in roadmap|discipline) ;; *) return 2 ;; esac
    start=$(bash "$HERE/coord-log.sh" run-start --session "$s" 2>/dev/null) || return 2
    since="$(printf '%s' "$start" | cut -c1-16)Z"
    local t
    t=$(mktemp "${TMPDIR:-/tmp}/board-lib.XXXXXX") || return 2
    if ! bl_gh "$t" api --method GET "repos/$repo/issues/$ref"; then rm -f "$t" "$t.err" "$t.fail"; return 2; fi
    body=$(jq -r '.body // ""' "$t" 2>/dev/null)
    rm -f "$t" "$t.err" "$t.fail"
    local cont=issue
    [ "$scope" = discipline ] && cont=pr
    printf '%s' "$body" | bash "$HERE/record-parse.sh" --container "$cont" --expect-scope "$scope:$name" - 2>/dev/null \
        | jq -e --arg since "$since" '
            [.reversals[]? | select(.from == "the human"
                and (((.reversed // "") + " " + (.now // "")) | test("posture"; "i"))
                and ((.now // "") | test("merge"; "i"))
                and ((.now // "") | test("\\b(hold|holds|held)\\b"; "i"))
                and (((.now // "") | test("\\b(not|never)\\b|n\\x27t\\b"; "i")) | not)
                and ((.date // "") >= $since))] | length > 0' >/dev/null
}

# bl_merge_posture <session>: the merge step's effective posture, printed as
# permit, deny or confirm. The start's read (the POSTURE capture, sealed at
# start_posture) and a fresh posture-read.sh can only narrow each other: the
# stricter wins (deny > confirm > unread > permit). An unread result becomes
# permit only when the start read was unread for merge and the human's answer
# holding the merge is on GitHub now, and confirm otherwise. A missing or
# invalid start capture counts as unread with no recorded answer. Returns 0
# printed; 2 the fresh read failed.
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
    state=$(jq -r '.state // ""' "$d/pr" 2>/dev/null)
    case "$state" in
        MERGED) ;;
        OPEN|CLOSED) rm -rf "$d"; echo not-merged; return 0 ;;
        *) echo "$PROG: pull request state [$state]" >&2; rm -rf "$d"; return 2 ;;
    esac
    jq -r '.files[]?.path' "$d/pr" > "$d/paths" 2>/dev/null || { rm -rf "$d"; return 2; }
    if ! bl_gh "$d/repo" api --method GET "repos/$repo"; then rm -rf "$d"; return 2; fi
    def=$(jq -r '.default_branch // ""' "$d/repo" 2>/dev/null)
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
                jq -r 'if type == "object" and .type == "file" and (.sha | type) == "string" then .sha else "not-a-file" end' "$d/blob.$i.$k" > "$d/sha.$i.$k" 2>/dev/null || { rm -rf "$d"; return 2; }
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
