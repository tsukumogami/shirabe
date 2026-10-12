# record-source.sh -- the one reader of a coordinator record's state. Sourced,
# never run as a library: `. "$HERE/record-source.sh"` after record-common.sh
# (it needs lib_parse and the facts lib_facts sets). Run as a script, it prints
# one read (see Usage).
#
# Every script that needs the record's state reads it here, whichever store the
# run is on (docs/designs/DESIGN-coordinator-session-record.md, Decision 1). A
# record's store is `github` (the issue or pull request body, as before) or
# `session` (keys in the coordinator's own koto session). This release reads the
# GitHub store only: a run whose store reads `session` stops with
# `store-unavailable` before anything is written, until the session store ships.
#
# The GitHub reads keep each caller's own call shape, because what a caller
# reads beside the body (the container's state, its title, its head branch) is
# GitHub's and stays its own:
#
#   rs_record <out> <mode> <gh view args...>
#       Runs `gh issue view <REF> --repo <REPO> <args>` at roadmap scope and
#       `gh pr view <REF> --repo <REPO> <args>` at discipline scope, exactly as
#       given, with stdin from /dev/null. <mode> says what the args print:
#       `body` (the body text, e.g. `--json body --jq .body`) or `json` (a JSON
#       object with .body, e.g. `--json state,body`). Writes <out> (the parsed
#       record, record-parse.sh's JSON), <out>.raw (what gh printed), <out>.md
#       (the body) and <out>.err (gh's stderr, or the parser's refusal).
#       Returns 0 parsed; 2 the read failed; 3 or 65 the body isn't a canonical
#       record of this scope (record-parse.sh's codes); 4 the store is session;
#       5 the parser itself failed.
#   rs_record_api <out> [<session>]
#       The same record through `gh api --method GET repos/<repo>/issues/<ref>`,
#       read with board-lib.sh's bl_gh (its retry and deadline) when the caller
#       sourced board-lib.sh. The repository, number and scope come from the
#       run's facts (coord-log.sh run-facts) of <session>, $SESSION when not
#       given. Writes <out> and <out>.md. Returns 0 parsed; 2 the read or the
#       parse failed, or the store is session.
#   rs_facts <parsed-record> <topic>
#       Prints one holding's facts, from a record rs_record or rs_record_api
#       parsed: {topic, unit, repo, pull_request, number, branch, verified_head,
#       phase, dispatch_status, return_path, holds, pauses}. holds are the Holds
#       rows on the holding's pull request; pauses the Standing pause and
#       go-ahead rows pause-read.sh reads. Returns 0 printed; 1 no holding has
#       that topic; 2 the record couldn't be read.
#   rs_source
#       Prints the run's store, `github` or `session`: the one record-find.sh
#       sealed in its RECORD_FIND token (coord-log.sh run-store), else `github`
#       (nothing reads the record before the find). Under the test override
#       flags it is `github` unless RS_SOURCE names another.
#   rs_probe
#       Prints what this koto offers the session store, by feature:
#       {"context_list_prefix": bool, "session_import": bool}.
#
# Usage (as a script):
#   record-source.sh --session S --source
#   record-source.sh --session S --probe
#   record-source.sh --session S --facts <topic>
#   record-source.sh --scope roadmap|discipline --name N --repo O/R --ref N --facts <topic>   (tests)
#
# Exit codes (as a script): 0 printed; 1 no holding has that topic; 2 a read
# failed; 4 the store is session; 64 usage.
#
# Requires: bash 3.2+, jq, gh, koto, and record-common.sh, record-parse.sh,
# coord-log.sh and pause-read.sh beside this file.

RS_LOADED=1
RS_STORE_UNAVAILABLE="store-unavailable: this release reads the record only from GitHub; the session store ships in the next change"

# rs_source: the run's store.
rs_source() {
    if [ "${OVERRIDE:-0}" = 1 ] || [ -z "${SESSION:-}" ]; then
        case "${RS_SOURCE:-github}" in session) RS_SOURCE_READ=session ;; *) RS_SOURCE_READ=github ;; esac
        printf '%s\n' "$RS_SOURCE_READ"
        return 0
    fi
    if [ -z "${RS_SOURCE_READ:-}" ]; then
        local s
        s=$(bash "$HERE/coord-log.sh" run-store --session "$SESSION" 2>/dev/null)
        case "$s" in session) RS_SOURCE_READ=session ;; *) RS_SOURCE_READ=github ;; esac
    fi
    printf '%s\n' "$RS_SOURCE_READ"
}

# rs_probe: the koto features the session store needs, read by feature.
rs_probe() {
    local prefix=false import=false
    "$KOTO" context list --help < /dev/null 2>/dev/null | grep -q -- '--prefix' && prefix=true
    "$KOTO" session import --help < /dev/null > /dev/null 2>&1 && import=true
    jq -nc --argjson p "$prefix" --argjson i "$import" '{context_list_prefix: $p, session_import: $i}'
}

# rs_record <out> <body|json> <gh view args...>
rs_record() {
    local out=$1 mode=$2 rc
    shift 2
    case "$mode" in body|json) ;; *) echo "$PROG: rs_record: mode is body or json" >&2; return 2 ;; esac
    rs_source > /dev/null
    if [ "$RS_SOURCE_READ" = session ]; then
        echo "$PROG: $RS_STORE_UNAVAILABLE" > "$out.err"
        return 4
    fi
    if [ "$CONTAINER" = issue ]; then
        gh issue view "$REF" --repo "$REPO" "$@" > "$out.raw" 2> "$out.err" < /dev/null
    else
        gh pr view "$REF" --repo "$REPO" "$@" > "$out.raw" 2> "$out.err" < /dev/null
    fi
    rc=$?
    [ $rc -eq 0 ] || return 2
    # Line endings as the write core reads them, so a body GitHub serves with
    # CRLF parses the same in every reader.
    if [ "$mode" = body ]; then
        tr -d '\r' < "$out.raw" > "$out.md"
    else
        jq -r '.body // ""' "$out.raw" 2>> "$out.err" | tr -d '\r' > "$out.md" || return 2
    fi
    # lib_parse writes its refusal to <out>.err, in place of gh's stderr, which
    # is where a caller that parsed the body itself read it before.
    lib_parse "$out.md" "$out"
    rc=$?
    case $rc in
        0|3|65) return $rc ;;
        *) return 5 ;;
    esac
}

# rs_record_api <out>: the run's record through the issues API, under
# board-lib.sh's bl_gh when it is loaded.
rs_record_api() {
    local out=$1 facts rrepo ref scope name c
    local SESSION=${2:-${SESSION:-}}
    rs_source > /dev/null
    if [ "$RS_SOURCE_READ" = session ]; then
        echo "$PROG: $RS_STORE_UNAVAILABLE" >&2
        return 2
    fi
    facts=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION") || return 2
    rrepo=$(printf '%s' "$facts" | jq -r '.repo // ""')
    ref=$(printf '%s' "$facts" | jq -r '.ref // ""')
    scope=$(printf '%s' "$facts" | jq -r '.scope // ""')
    name=$(printf '%s' "$facts" | jq -r '.name // ""')
    [[ $rrepo =~ $RE_REPO ]] && [[ $ref =~ $RE_NUM ]] || return 2
    case "$scope" in roadmap) c=issue ;; discipline) c=pr ;; *) return 2 ;; esac
    if declare -F bl_gh > /dev/null; then
        bl_gh "$out.rec" api --method GET "repos/$rrepo/issues/$ref" || return 2
    else
        gh api --method GET "repos/$rrepo/issues/$ref" > "$out.rec" 2> "$out.rec.err" < /dev/null || return 2
    fi
    jq -r '.body // ""' "$out.rec" > "$out.md" || return 2
    bash "$HERE/record-parse.sh" --container "$c" --expect-scope "$scope:$name" "$out.md" > "$out" \
        || { echo "$PROG: the record couldn't be parsed" >&2; return 2; }
}

# rs_facts <parsed-record> <topic>
rs_facts() {
    local f=$1 topic=$2 row unit d
    jq -e --arg t "$topic" 'any(.holdings[]?; .worker == $t)' "$f" > /dev/null 2>&1 || {
        jq -e . "$f" > /dev/null 2>&1 || return 2
        return 1
    }
    row=$(jq -c --arg t "$topic" '[.holdings[] | select(.worker == $t)][0]' "$f") || return 2
    unit=$(printf '%s' "$row" | jq -r '.unit')
    d=$(mktemp -d "${TMPDIR:-/tmp}/record-source.XXXXXX") || return 2
    jq '{standing: (.standing // [])}' "$f" > "$d/standing" || { rm -rf "$d"; return 2; }
    jq -nc --arg u "$unit" '[$u]' > "$d/units"
    if ! bash "$HERE/pause-read.sh" --standing "$d/standing" --units "$d/units" > "$d/pauses" 2> /dev/null; then
        rm -rf "$d"; return 2
    fi
    jq -c --argjson row "$row" --slurpfile p "$d/pauses" '
        ($row.pull_request | capture("^\\[#(?<n>[0-9]+)\\]\\(https://github\\.com/(?<r>[^/]+/[^/]+)/pull/[0-9]+\\)$") // {n: "", r: ""}) as $pr
        | (if $pr.r == "" then "" else ($pr.r + "#" + $pr.n) end) as $on
        | {topic: $row.worker, unit: $row.unit, repo: $row.repo, pull_request: $row.pull_request,
           number: $pr.n, branch: $row.branch, verified_head: $row.verified_head, phase: $row.phase,
           dispatch_status: $row.dispatch_status, return_path: $row.return_path,
           holds: (if $on == "" then [] else [(.holds // [])[] | select((.on | ascii_downcase) == ($on | ascii_downcase))] end),
           pauses: {rows: [(.standing // [])[] | select(.kind == "pause" or .kind == "go-ahead")],
                    read: $p[0], paused: ($p[0].covers[$row.unit] // $p[0].all // null)}}' "$f"
    local rc=$?
    rm -rf "$d"
    [ $rc -eq 0 ] || return 2
}

# ---- run as a script --------------------------------------------------------

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -uo pipefail
    PROG=record-source
    HERE=$(cd "$(dirname "$0")" && pwd)
    SESSION= SCOPE= NAME= REPO= REF= ACTION= TOPIC=
    rs_usage() { sed -n '/^# Usage (as a script):/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
    while [ $# -gt 0 ]; do
        case "$1" in
            --session) [ $# -ge 2 ] || rs_usage; SESSION=$2; shift 2 ;;
            --scope) [ $# -ge 2 ] || rs_usage; SCOPE=$2; shift 2 ;;
            --name) [ $# -ge 2 ] || rs_usage; NAME=$2; shift 2 ;;
            --repo) [ $# -ge 2 ] || rs_usage; REPO=$2; shift 2 ;;
            --ref) [ $# -ge 2 ] || rs_usage; REF=$2; shift 2 ;;
            --source) ACTION=source; shift ;;
            --probe) ACTION=probe; shift ;;
            --facts) [ $# -ge 2 ] || rs_usage; ACTION=facts; TOPIC=$2; shift 2 ;;
            *) rs_usage ;;
        esac
    done
    [ -n "$ACTION" ] || rs_usage
    . "$HERE/record-common.sh"
    case "$ACTION" in
        probe) rs_probe; exit 0 ;;
    esac
    lib_facts
    case "$ACTION" in
        source) rs_source; exit 0 ;;
    esac
    [[ $TOPIC =~ $RE_TOPIC ]] || { echo "$PROG: the topic is not a dispatch topic" >&2; exit 64; }
    lib_run_ref || { echo "$PROG: the run has no record yet" >&2; exit 2; }
    RS_T=$(mktemp -d "${TMPDIR:-/tmp}/record-source.XXXXXX")
    trap 'rm -rf "$RS_T"' EXIT
    rs_record "$RS_T/rec" body --json body --jq .body
    case $? in
        0) ;;
        4) cat "$RS_T/rec.err" >&2; exit 4 ;;
        *) echo "$PROG: the record couldn't be read: $(lib_scrub < "$RS_T/rec.err" | head -3)" >&2; exit 2 ;;
    esac
    rs_facts "$RS_T/rec" "$TOPIC"
    exit $?
fi
