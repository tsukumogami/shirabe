#!/usr/bin/env bash
# unit-removed.sh -- the cost capture for a unit niwa removes outside the
# teardown pass: the on-reap step that records the removal, and the sweep
# that captures what survives.
#
# niwa runs a workspace's `[session.on_reap]` command once for each session it
# removes (`niwa destroy`, `niwa reap`, and the reaps `niwa dispatch`, `niwa
# create` and `niwa watch` run first), from the workspace root, with
# NIWA_REAP_KEY (the dispatch id), NIWA_SESSION_ID and NIWA_INSTANCE_PATH, in
# a 10-second run. A capture takes up to 120, so the step only records the
# removal and starts the sweep detached; the sweep does the slow part with the
# pass's own collection code (archive-common.sh) and the pass's own capture
# (unit-cost.sh).
#
# Usage:
#   unit-removed.sh record
#       The on-reap step. Refuses, with one line, no record and exit 0, when
#       its own script or a library it sources is writable by group or
#       others; NIWA_REAP_KEY is unset, outside
#       ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ or equal to NIWA_SESSION_ID;
#       NIWA_SESSION_ID isn't a session id (unit-cost.sh's pattern, its
#       first 8 characters hex digits, since they name the archive);
#       NIWA_INSTANCE_PATH isn't absolute, holds `..`, isn't a plain path
#       (a trailing `/`, `//` or a control character) or isn't strictly
#       under the directory the step runs in; or the removals directory R
#       (${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/removals) is a
#       symbolic link, isn't the user's or isn't mode 0700. Otherwise it
#       writes R/<dispatch id>.json, {schema: "unit-removal/1", dispatch_id,
#       session_id, instance_path, removed_at, attempts: 0, last: null},
#       through a temporary name in R and mv; a record already there for the
#       same instance path keeps its removed_at, one for another path is
#       replaced. Then it starts `sweep` in a new session (perl's
#       POSIX::setsid, else nohup, else a plain background job), by its
#       absolute path, stdin empty, output nowhere, its environment PATH,
#       HOME and TMPDIR, plus XDG_STATE_HOME, XDG_DATA_HOME,
#       TEARDOWN_ARCHIVE_DIR and KOTO_REQUESTS when they are set, since they
#       place R, the archive root and the request store, and GH_TOKEN,
#       GITHUB_TOKEN and GH_HOST unchanged when they are set, since the
#       capture reads and posts with them. It prints one line
#       and exits 0 in every case, never waiting for the sweep.
#   unit-removed.sh start
#       Starts `sweep` as record does (detached, by absolute path, with the
#       environment record names) and exits 0 at once. The teardown pass runs
#       it as it ends, and the coordinator at each wake, so a sweep holding
#       the coordinator's token finishes what a token-less one left pending.
#   unit-removed.sh sweep
#       With no record in R it does nothing at all. Otherwise every record,
#       one at a time, under its own lock, R/.<dispatch id>.lock (a directory
#       holding `<pid> <epoch secs>`, archive-common.sh ac_lock): a record
#       whose lock a live sweep holds is passed over (`<dispatch id>: held by
#       another sweep`, nothing logged), and a lock whose holder is gone, or
#       older than three minutes (the capture's 120-second bound and a minute
#       for the archive before it), is taken over. Under it:
#         - a record outside its shape (the patterns above, its file named
#           for its dispatch id, a session id starting with 8 hex digits) is
#           deleted: invalid input;
#         - the unit's koto sessions are the ones whose execution_dir is at or
#           under its instance path (TEARDOWN_KOTO_SESSIONS, default
#           $HOME/.koto/sessions); the dispatch is the earliest coordinator
#           request their request-leg.toml files name (archive-common.sh
#           ac_dispatch_request); none keeps the record: no coordinator;
#         - the topic is that request's coordinator_of_record without
#           `coordinate-`, matched to ^[a-z0-9][a-z0-9-]{0,62}$, else the
#           record is deleted: invalid input;
#         - requested_by's session must hold the leg key its dispatch wrote,
#           legs/<request>/<leg>, naming that request and that topic, else
#           the record is kept: no coordinator. So a request a worker forged
#           names no coordinator;
#         - the target is the newest member of requested_by's chain when a
#           takeover superseded it (dispatch-common.sh dc_newest_member
#           follows its session_superseded events forward), whatever the
#           members' names; else requested_by while coord-log.sh
#           live-session lists it for its scope slug, else that slug's one
#           live run (also when the chain can't be read); none or several
#           keeps the record: no coordinator, several coordinators. The
#           record's `last` names the run charged, as `coordinator`;
#         - what survives goes into the pass's removed-mode archive,
#           <archive root>/<UTC date>-<topic>-<session id's first 8>
#           (TEARDOWN_ARCHIVE_DIR, default
#           ${XDG_DATA_HOME:-$HOME/.local/share}/teardown-archive, a real
#           directory of the user's at mode 0700): the project directories
#           (TEARDOWN_CLAUDE_HOME, default $HOME/.claude) and koto sessions as
#           the pass collects them, teardown.json {topic, instance: {name:
#           null, path}, job: {id, session}, removed: true, niwa:
#           {dispatch_id, reason: null}}, the MANIFEST, MANIFEST.sha256, a
#           README and RESULT;
#         - with GH_TOKEN unset or empty the sweep makes no GitHub call at
#           all (a bare gh would fall back to a stored login): the record is
#           kept, pending github, and nothing is posted;
#         - otherwise `unit-cost.sh capture --session <target> --archive
#           <archive> --topic <topic> --prs-file <empty file>` runs under a
#           120-second deadline, with GH_CONFIG_DIR an empty directory of its
#           own, so gh authenticates with the token and never with a stored
#           login; a last line saying the entry was posted, kept in the
#           session or already on the record deletes the record (captured,
#           already recorded); a failed post keeps it (post failed), and so
#           does anything else (read failed) or the deadline (timed out).
#       A record kept after its shape check gets attempts counted up and last
#       set to {at, outcome}, and every later sweep tries it again; none is
#       deleted for its age. One line per record on stdout, `<dispatch id>:
#       <outcome>`, and the same in R/removals.log, `<UTC time> <dispatch id>
#       <outcome>`. A record kept more than 24 hours after its removed_at is
#       followed by one more line in each, `stale`, so a person sees it.
#       Past 1 MiB the log keeps its last 1,000 lines.
#       Before it exits the sweep reads R again and handles any record
#       written since it started. Exit 0.
#
# Exit codes: record and sweep always 0; 64 usage.
#
# Environment: the sweep the step starts sees only the names listed under
# record. Run by hand, the sweep also honours TEARDOWN_KOTO_SESSIONS,
# TEARDOWN_CLAUDE_HOME, and KOTO and GH (the tools, through the scripts it
# runs). GITHUB_TOKEN and GH_HOST are passed for gh's own use; the sweep's
# no-token rule reads GH_TOKEN alone, the token the coordinator's sessions
# carry. bash 3.2.
set -uo pipefail

PROG=unit-removed
say() { printf '%s: %s\n' "$PROG" "$*"; }
usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

MODE="${1:-}"
case "$MODE" in record | sweep | start) ;; *) usage ;; esac
[ $# -eq 1 ] || { [ "$MODE" = record ] && { say "record takes no arguments; nothing recorded"; exit 0; }; usage; }

HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || { say "cannot find its own directory; nothing done"; exit 0; }
SELF="$HERE/$(basename "$0")"
umask 077

# writable_by_others <file>: 0 when the file's mode lets group or others write
# it, or its mode can't be read.
writable_by_others() {
    local m
    m=$(ls -l -- "$1" 2>/dev/null) || return 0
    case "${m%% *}" in ?????w* | ????????w* | '') return 0 ;; esac
    return 1
}

# The on-reap step runs from a hook, and start from the pass and every wake,
# so neither reads anything it hasn't checked.
if [ "$MODE" != sweep ]; then
    for f in "$SELF" "$HERE/archive-common.sh" "$HERE/dispatch-common.sh"; do
        writable_by_others "$f" && { say "${f##*/} is writable by group or others; nothing recorded"; exit 0; }
    done
fi
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh" && . "$HERE/archive-common.sh" || { say "cannot load its libraries; nothing done"; exit 0; }

# ---------------------------------------------------------------------------
# record

skip() { say "$*; nothing recorded"; exit 0; }

# start_sweep: the sweep, detached, by absolute path, with the scrubbed
# environment the header names.
start_sweep() {
    local v p
    set -- PATH="${PATH:-/usr/bin:/bin}" HOME="${HOME:-}" TMPDIR="${TMPDIR:-/tmp}"
    for v in XDG_STATE_HOME XDG_DATA_HOME TEARDOWN_ARCHIVE_DIR KOTO_REQUESTS GH_TOKEN GITHUB_TOKEN GH_HOST; do
        [ -n "${!v:-}" ] && set -- "$@" "$v=${!v}"
    done
    # A new session takes the sweep out of niwa's process group and out of
    # the shell that ran niwa; without perl, nohup at least keeps it past a
    # hangup.
    if p=$(command -v perl 2>/dev/null) && [ -n "$p" ]; then
        env -i "$@" "$p" -MPOSIX -e 'POSIX::setsid(); exec @ARGV' -- "$SELF" sweep </dev/null >/dev/null 2>&1 &
    elif p=$(command -v nohup 2>/dev/null) && [ -n "$p" ]; then
        env -i "$@" "$p" "$SELF" sweep </dev/null >/dev/null 2>&1 &
    else
        env -i "$@" "$SELF" sweep </dev/null >/dev/null 2>&1 &
    fi
}

if [ "$MODE" = start ]; then
    start_sweep
    say "the sweep runs in the background"
    exit 0
fi

if [ "$MODE" = record ]; then
    KEY="${NIWA_REAP_KEY:-}" SID="${NIWA_SESSION_ID:-}" IP="${NIWA_INSTANCE_PATH:-}"
    [ -n "$KEY" ] || skip "no reap key (NIWA_REAP_KEY)"
    [[ $KEY =~ $AC_RE_REAP ]] || skip "the reap key is not a dispatch id"
    [ "$KEY" != "$SID" ] || skip "the reap key is the session id, not a dispatch id"
    # The archive is named for its first 8 characters, as the pass names a
    # removed unit's, so they must be hex digits too.
    [[ $SID =~ $AC_RE_SID ]] && [[ $SID =~ ^[0-9a-f]{8} ]] || skip "the session id (NIWA_SESSION_ID) is not a session id"
    case "$IP" in /*) ;; *) skip "the instance path (NIWA_INSTANCE_PATH) is not absolute" ;; esac
    case "$IP" in *..*) skip "the instance path holds .." ;; esac
    # niwa names an instance as a plain path: no trailing `/`, no `//`, no
    # control character, so the workspace root itself (`<root>/`) is never
    # taken for one.
    case "$IP" in */ | *//* | *[[:cntrl:]]*) skip "the instance path is not a plain path" ;; esac
    # niwa runs the step from the workspace root, and every instance is
    # under it.
    WS=$(pwd) WSP=$(pwd -P)
    case "$IP" in "$WS"/?* | "$WSP"/?*) ;; *) skip "the instance path is not under $WS" ;; esac
    ac_removals_dir --create || skip "$AC_WHY"
    F="$AC_R/$KEY.json"
    AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ -f "$F" ] && [ ! -L "$F" ]; then
        # jq's own message, on a record it can't parse, lands in PREV and fails
        # the timestamp shape below, so the new removal keeps the new time.
        PREV=$(jq -r --arg p "$IP" 'select(type == "object" and .instance_path == $p) | .removed_at | strings' "$F" 2>&1) || PREV=""
        PREV=${PREV%%$'\n'*}
        [[ $PREV =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && AT=$PREV
    fi
    TMPF=$(mktemp "$AC_R/.record.XXXXXX" 2>/dev/null) || skip "cannot write in $AC_R"
    if ! jq -n -c --arg d "$KEY" --arg s "$SID" --arg p "$IP" --arg at "$AT" \
        '{schema: "unit-removal/1", dispatch_id: $d, session_id: $s, instance_path: $p, removed_at: $at, attempts: 0, last: null}' >"$TMPF" \
        || ! mv -f "$TMPF" "$F"; then
        rm -f "$TMPF"
        skip "cannot write the removal record"
    fi
    start_sweep
    say "recorded the removal of $KEY; the sweep runs in the background"
    exit 0
fi

# ---------------------------------------------------------------------------
# sweep

KOTO_SESSIONS="${TEARDOWN_KOTO_SESSIONS:-$HOME/.koto/sessions}"
CLAUDE_HOME="${TEARDOWN_CLAUDE_HOME:-$HOME/.claude}"
ARCHIVE_ROOT="${TEARDOWN_ARCHIVE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/teardown-archive}"
CAPTURE_SECS=120
# A record's lock covers the archive and the capture, so a live holder is taken
# over only past both: the capture's bound and a minute for the archive.
LOCK_SECS=$((CAPTURE_SECS + 60))
RE_TOPIC='^[a-z0-9][a-z0-9-]{0,62}$'
STALE_SECS=86400

ac_removals_dir || { say "$AC_WHY"; exit 0; }
LOG="$AC_R/removals.log"
# Nothing pending is nothing to do: no scratch, no read, no call.
set -- "$AC_R"/*.json
[ -e "$1" ] || [ -L "$1" ] || exit 0

T=$(mktemp -d "${TMPDIR:-/tmp}/unit-removed.XXXXXX") || exit 0
trap 'rm -rf "$T"' EXIT
# The run a record's outcome charged, once sweep_record resolves it.
CHARGED=
# gh finds no stored login here, whatever the host holds: it reads with the
# token or not at all.
mkdir -p "$T/gh-config" || exit 0
export GH_CONFIG_DIR="$T/gh-config"

# logline <dispatch id> <outcome>: one line on stdout and in removals.log.
logline() {
    local n
    printf '%s: %s\n' "$1" "$2"
    printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >>"$LOG" || say "cannot write $LOG"
    # A record kept for weeks adds a line at every sweep, and one runs at every
    # wake, so past 1 MiB the log keeps its last 1,000 lines.
    n=$(wc -c <"$LOG" 2>&1) || n=0
    n=${n//[!0-9]/}
    if [ "${n:-0}" -gt 1048576 ]; then
        tail -n 1000 "$LOG" >"$LOG.trim" && mv -f "$LOG.trim" "$LOG" || say "cannot trim $LOG"
    fi
}

# outcome <record file> <dispatch id> <outcome> [delete]: the record's line,
# and the record deleted when asked; a record kept gets attempts counted up
# and last set, through a temporary name in R and mv, and is listed stale
# once it has waited more than STALE_SECS since its removal.
outcome() {
    local tmp at
    if [ "${4:-}" = delete ]; then
        rm -f "$1"
    elif tmp=$(mktemp "$AC_R/.record.XXXXXX" 2>/dev/null); then
        if jq -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg o "$3" --arg c "$CHARGED" '
            .attempts = (.attempts | if type == "number" and . >= 0 then . + 1 else 1 end)
            | .last = ({at: $at, outcome: $o} + (if $c == "" then {} else {coordinator: $c} end))' "$1" >"$tmp" 2>/dev/null; then
            mv -f "$tmp" "$1" || rm -f "$tmp"
        else
            rm -f "$tmp"
        fi
    fi
    logline "${2:-?}" "$3"
    [ "${4:-}" != delete ] || return 0
    # jq's own message, on a record it can't read, isn't a number, so the
    # record is not listed stale for it.
    at=$(jq -r '.removed_at | strings | fromdateiso8601' "$1" 2>&1) || at=""
    [[ $at =~ ^[0-9]+$ ]] && [ $(($(date +%s) - at)) -gt "$STALE_SECS" ] && logline "${2:-?}" stale
    return 0
}

# sweep_one <record file>: the record under its own lock. The lock is named
# from the file's name, matched first, since the record isn't read yet; a
# record another sweep finished while this one waited is gone, and passed by.
sweep_one() {
    local f=$1 id lock
    id=${f##*/}
    id=${id%.json}
    [[ $id =~ $AC_RE_REAP ]] || { outcome "$f" "${f##*/}" "invalid input" delete; return 0; }
    lock="$AC_R/.$id.lock"
    ac_lock "$lock" "$LOCK_SECS" 0 || { printf '%s: held by another sweep\n' "$id"; return 0; }
    [ -f "$f" ] && [ ! -L "$f" ] && sweep_record "$f"
    ac_unlock "$lock"
}

# sweep_record <record file>
sweep_record() {
    local f=$1 row did sid ip d topic slug leg live n target job arch rc last nm
    CHARGED=
    row=$(jq -r --arg reap "$AC_RE_REAP" --arg sid "$AC_RE_SID" --arg name "${f##*/}" '
        if type == "object" and .schema == "unit-removal/1"
           and (.dispatch_id | type) == "string" and (.dispatch_id | test($reap)) and $name == .dispatch_id + ".json"
           and (.session_id | type) == "string" and (.session_id | test($sid)) and (.session_id | test("^[0-9a-f]{8}"))
           and (.instance_path | type) == "string" and (.instance_path | startswith("/"))
           and (.instance_path | contains("..") | not) and (.instance_path | test("[[:cntrl:]]") | not)
        then [.dispatch_id, .session_id, .instance_path] | @tsv else empty end' "$f" 2>/dev/null)
    if [ -z "$row" ]; then
        outcome "$f" "${f##*/}" "invalid input" delete
        return 0
    fi
    IFS='	' read -r did sid ip <<<"$row"

    # The dispatching coordinator, from the unit's koto request.
    ac_koto_find "$T" "$KOTO_SESSIONS" "$ip"
    set --
    while IFS= read -r d; do [ -n "$d" ] && set -- "$@" "$d"; done <"$T/koto.dirs"
    ac_dispatch_request "$@" || { outcome "$f" "$did" "no coordinator"; return 0; }
    topic=${AC_COR#coordinate-}
    if [ "$topic" = "$AC_COR" ] || ! [[ $topic =~ $RE_TOPIC ]]; then
        outcome "$f" "$did" "invalid input" delete
        return 0
    fi
    # The leg key the dispatch wrote in requested_by's own session.
    leg=$(dc_leg_get "$AC_BY" "$AC_REQ" "$AC_LEG" 2>/dev/null) \
        && [ "$(jq -r --arg r "$AC_REQ" --arg t "$topic" '.request == $r and .topic == $t' <<<"$leg" 2>&1)" = true ] \
        || { outcome "$f" "$did" "no coordinator"; return 0; }
    # A run taken over since it dispatched the unit is fenced, and its newest
    # member holds the run: the supersede events lead there, whatever the
    # members' names say. A chain that can't be read, or that runs past the
    # hop cap, leaves the lookup by name below.
    nm=$(dc_newest_member "$AC_BY") || nm=
    slug=${AC_BY#coordinate-}
    slug=${slug%-*}
    live=
    case "$nm" in *"	"0 | "") live=$(dc_with_deadline 15 bash "$DC_COORD_LOG" live-session --scope-slug "$slug" --all </dev/null 2>/dev/null) ;; esac
    n=$(printf '%s\n' "$live" | grep -c .)
    if [ -n "$nm" ] && [ "${nm#*	}" != 0 ]; then
        target=${nm%%	*}
    elif grep -qxF -- "$AC_BY" <<<"$live"; then
        target=$AC_BY
    elif [ "$n" = 1 ]; then
        target=$live
    elif [ "$n" = 0 ]; then
        outcome "$f" "$did" "no coordinator"
        return 0
    else
        outcome "$f" "$did" "several coordinators"
        return 0
    fi
    [[ $target =~ $AC_RE_COORD ]] || { outcome "$f" "$did" "no coordinator"; return 0; }
    CHARGED=$target

    # The pass's removed-mode archive of what survives.
    job=${sid:0:8}
    if [ ! -e "$ARCHIVE_ROOT" ] && [ ! -L "$ARCHIVE_ROOT" ]; then
        mkdir -p -- "$ARCHIVE_ROOT" 2>/dev/null && chmod 700 "$ARCHIVE_ROOT"
    fi
    ac_dir_private "$ARCHIVE_ROOT" || { outcome "$f" "$did" "read failed"; return 0; }
    arch="$ARCHIVE_ROOT/$(date -u +%Y-%m-%d)-$topic-$job"
    mkdir -p "$arch" && chmod 700 "$arch" || { outcome "$f" "$did" "read failed"; return 0; }
    : >"$T/copies"
    ac_projects "$arch" "$T" "$CLAUDE_HOME" "$ip" \
        && ac_koto_copy "$arch" "$T" \
        || { outcome "$f" "$did" "read failed"; return 0; }
    jq -n -c --arg topic "$topic" --arg path "$ip" --arg job "$job" --arg sid "$sid" --arg d "$did" '
        {topic: $topic, instance: {name: null, path: $path}, job: {id: $job, session: $sid},
         removed: true, niwa: {dispatch_id: $d, reason: null}}' >"$T/teardown.json" \
        && ac_copy_file "$arch" "$T" "$T/teardown.json" teardown.json \
        && ac_manifest "$arch" "$T" \
        || { outcome "$f" "$did" "read failed"; return 0; }
    {
        printf '# Teardown of %s\n\n' "$topic"
        printf 'Taken %s by unit-removed.sh'"'"'s sweep, after niwa removed the unit (dispatch %s): this is what survived.\n\n' \
            "$(date -u +%Y-%m-%dT%H:%MZ)" "$did"
        printf -- '- Instance: removed (%s)\n' "$ip"
        printf -- '- Claude Code job: removed; session %s (job id %s, from the session id)\n\n' "$sid" "$job"
    } >"$T/readme.head"
    ac_readme "$arch" "$T" "$T/readme.head"

    # Without a token, no GitHub call at all: the capture reads and posts
    # through gh, so it waits for a sweep that has one.
    [ -n "${GH_TOKEN:-}" ] || { outcome "$f" "$did" "pending github"; return 0; }

    # The capture, as the pass runs it: no stream of the sweep's, under its
    # own deadline, with no pull request a verdict sealed.
    : >"$T/prs"
    dc_with_deadline "$CAPTURE_SECS" bash "$HERE/unit-cost.sh" capture --session "$target" \
        --archive "$arch" --topic "$topic" --prs-file "$T/prs" </dev/null >/dev/null 2>"$T/capture.err"
    rc=$?
    printf 'done %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$arch/RESULT"
    [ "$rc" = 124 ] && { outcome "$f" "$did" "timed out"; return 0; }
    last=$(grep . "$T/capture.err" | tail -n 1)
    case "$last" in
        "unit-cost: posted the cost entry"* | "unit-cost: kept the cost entry in the session"*)
            outcome "$f" "$did" captured delete ;;
        "unit-cost: the record already holds this unit's cost entry")
            outcome "$f" "$did" "already recorded" delete ;;
        "unit-cost: the post failed"* | "unit-cost: the post did not finish in time")
            outcome "$f" "$did" "post failed" ;;
        *) outcome "$f" "$did" "read failed" ;;
    esac
}

# Every record once, then R again for any written meanwhile, until a read
# finds nothing new.
: >"$T/handled"
while :; do
    NEW=0
    for REC in "$AC_R"/*.json; do
        [ -f "$REC" ] && [ ! -L "$REC" ] || continue
        grep -qxF -- "${REC##*/}" "$T/handled" && continue
        printf '%s\n' "${REC##*/}" >>"$T/handled"
        NEW=1
        sweep_one "$REC"
    done
    [ "$NEW" = 1 ] || break
done
exit 0
