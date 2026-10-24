#!/usr/bin/env bash
# teardown-handoff.sh -- the one verdict a teardown pass acts on.
#
# The teardown_handoff state runs this after the inventory read durable (or
# absent, for a unit removed outside the pass; see Removed mode below). It
# reads, before anything is removed, every fact the pass needs, and seals them
# as one verdict, so the local agent that runs the pass (teardown-pass.sh) is
# handed a target it can check rather than one it is told:
#
#   topic <t>                      teardown_topic, as the sealed inventory has it
#   instance <name> <path>         from `niwa list --json`, matched by the
#                                  inventory's instance path
#   job <id> <session id>          from `claude agents --json --all`: the one
#                                  job whose cwd is the instance path,
#                                  finished as dc_job_finished reads it: its
#                                  own jobs/<id>/state.json reads done,
#                                  stopped or failed, and the listing shows
#                                  no live pid for it. The listing's state
#                                  is activity and isn't read; a live pid, a
#                                  state file reading working or any other
#                                  state, or no state file, refuses
#   transcript <path>              <claude home>/projects/*/<session id>.jsonl
#   pr <owner/repo>#<n> <sha>      each pull request GitHub lists as merged
#                                  from the holding's branch, with its merge
#                                  commit; one line per pull request
#   handoff <url>                  the comment link submitted with `teardown:
#                                  stopped` at the latest visit to teardown,
#                                  read back from GitHub: a comment on one of
#                                  those pull requests or on the holding's
#                                  issue, with a body
#   dispatch <id>|-|invalid        niwa's dispatch_id on the matched listing
#                                  row: `-` when the row has none, `invalid`
#                                  when it isn't ^[A-Za-z0-9._:-]{1,128}$
#   inventory <sealed:...>         the sealed inventory the verdict stands on
#
# Removed mode. When the sealed inventory is `absent` (niwa lists no instance
# for the topic; teardown-verdict.sh read answers 5) and the latest teardown
# evidence is `teardown: removed`, the unit was torn down outside the pass,
# and the verdict describes what is left of it instead:
#
#   removed yes
#   instance - <path>              the instance's path, recovered: from koto
#                                  session headers whose execution_dir is at
#                                  or under a path whose last component is
#                                  `<anything>+<niwa slug of the topic>-<8
#                                  hex>`, else from transcript `cwd` values
#                                  in Claude Code project directories named
#                                  for such a path. It must be absolute, hold
#                                  no `..`, and sit directly under the
#                                  workspace root; no candidate, or two
#                                  distinct ones, refuses
#   job <id> <session id> | job -  the worker's session: of the main session
#                                  transcripts (`<session id>.jsonl` directly
#                                  in the project directory named for the
#                                  path), the one whose first timestamp is
#                                  latest; the job id is its first eight hex
#                                  digits. `job -` when there is none
#   transcript <path>              that transcript, when there is one
#   pr, handoff                    as for a stopped unit
#   dispatch -                     niwa's row is gone with the instance
#   inventory <sealed:...>
#
# It fails closed: a niwa or Claude Code listing that can't be read or parsed
# stops the seal (exit 2), and it refuses when niwa lists an instance for the
# topic or at the path, or Claude Code lists a job whose cwd is the path. The
# path is only ever compared and used to name directories to read; nothing
# here or in the pass removes anything in removed mode.
#
# Nothing here comes from an argument: the topic and the inventory from the
# session, the handoff link from the session's own log of the evidence, the
# rest from niwa, Claude Code, koto's session headers, the transcripts and
# GitHub.
#
# Usage:
#   teardown-handoff.sh --seal --session <s>
#       The state's default action. Seals the verdict in the context key
#       `teardown_handoff` and prints, sealed to this visit, `handoff-ready
#       keyseal:<seq>:<sha256>` or `handoff-refused`; a refusal's reason is the
#       sealed verdict's second line (`reason <why>`) and goes to stderr.
#   teardown-handoff.sh read --session <s>
#       For the destroy state's directive: checks the capture's seal, the
#       stored verdict against its key seal, that the verdict covers
#       teardown_topic, and that no directed transition moved the run since;
#       then prints the verdict followed by `keyseal <keyseal:...>`, the line
#       the coordinator hands the agent.
#
# Exit codes: 0 a verdict printed (--seal, whatever it says; read, a ready
# verdict); 1 (read) the verdict is a refusal; 2 a read failed (--seal: tick
# again); 3 (read) a seal doesn't hold or the verdict covers another topic;
# 4 (read) a directed transition since the seal; 64 usage.
#
# Environment: NIWA, CLAUDE_CLI, GH and KOTO name the tools (tests);
# TEARDOWN_CLAUDE_HOME is Claude Code's home (default $HOME/.claude);
# TEARDOWN_KOTO_SESSIONS is koto's session store (default $HOME/.koto/sessions);
# TEARDOWN_FETCH_SECS bounds each GitHub read (default 8).
# Read-only apart from the seal. bash 3.2.
set -uo pipefail

PROG=teardown-handoff
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

KOTO="${KOTO:-koto}"
GH="${GH:-gh}"
CLAUDE_CLI="${CLAUDE_CLI:-claude}"
NIWA="${NIWA:-niwa}"
CLAUDE_HOME="${TEARDOWN_CLAUDE_HOME:-$HOME/.claude}"
KOTO_SESSIONS="${TEARDOWN_KOTO_SESSIONS:-$HOME/.koto/sessions}"
FETCH_SECS="${TEARDOWN_FETCH_SECS:-8}"

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

MODE=""
SESSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --seal) MODE=seal; shift ;;
        read) MODE=read; shift ;;
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$MODE" ] && [ -n "$SESSION" ] || usage

die2() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# read: the verdict as sealed, for the hand-off. teardown-pass.sh reads the
# verdict through this mode too, so there is one reader of it.
if [ "$MODE" = read ]; then
    CAP=$(dc_capture "$SESSION" TEARDOWN_HANDOFF) || die2 "cannot read the TEARDOWN_HANDOFF capture"
    case "$CAP" in
        handoff-ready\ keyseal:*) ;;
        handoff-refused*) printf '%s: the teardown verdict is a refusal\n' "$PROG" >&2; exit 1 ;;
        *) printf '%s: the TEARDOWN_HANDOFF capture holds no verdict\n' "$PROG" >&2; exit 3 ;;
    esac
    STATE_SEAL=$(printf '%s' "$CAP" | grep -Eo 'sealed:[0-9]+:[0-9a-f]{64}' | tail -1)
    KSALL=$(printf '%s' "$CAP" | grep -Eo 'keyseal:[0-9]+:[0-9a-f]{64}')
    KS=${KSALL%%$'\n'*}
    [ -n "$STATE_SEAL" ] && [ -n "$KS" ] || { printf '%s: the capture is not sealed\n' "$PROG" >&2; exit 3; }
    # The capture is this visit's: the engine wrote it, and its seal names the
    # latest entry into teardown_handoff.
    bash "$DC_COORD_LOG" check --session "$SESSION" --state teardown_handoff --sealed "$CAP" >/dev/null
    case $? in 0) ;; 1) printf '%s: the capture is not this visit'"'"'s\n' "$PROG" >&2; exit 3 ;; *) die2 "the session log can't be read" ;; esac
    VERDICT=$(dc_seal_check "$SESSION" teardown_handoff "sealed:${KS#keyseal:}" teardown_handoff)
    case $? in 0) ;; 1) printf '%s: the stored verdict does not match its key seal\n' "$PROG" >&2; exit 3 ;; *) die2 "the stored verdict can't be read" ;; esac
    [ "$(printf '%s\n' "$VERDICT" | sed -n 1p)" = ready ] || { printf '%s: the stored verdict is not ready\n' "$PROG" >&2; exit 3; }
    VT=$(sed -n '/^topic /{s///p;q;}' <<<"$VERDICT")
    NOW=$("$KOTO" context get "$SESSION" teardown_topic) || die2 "cannot read teardown_topic"
    if [ -z "$VT" ] || [ "$VT" != "$NOW" ]; then
        printf '%s: the verdict covers [%s], but teardown_topic is [%s]\n' "$PROG" "$VT" "$NOW" >&2
        exit 3
    fi
    dc_directed_since "$SESSION" "$(printf '%s' "${KS#keyseal:}" | cut -d: -f1)"
    case $? in 0) ;; 1) printf '%s: a directed transition moved this run since the verdict; refusing\n' "$PROG" >&2; exit 4 ;; *) die2 "the session log can't be read" ;; esac
    printf '%s\n' "$VERDICT" | sed 1d
    printf 'keyseal %s\n' "$KS"
    exit 0
fi

# ---------------------------------------------------------------------------
# --seal: gather, then seal one verdict.
T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-handoff.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
: >"$T/lines"
line() { printf '%s\n' "$*" >>"$T/lines"; }

emit() {
    # emit ready|refused [reason]: seal the verdict file under the key, then
    # the token under the state.
    local word=$1 reason=${2-} ks
    if [ "$word" = ready ]; then
        { printf 'ready\n'; cat "$T/lines"; } >"$T/verdict"
    else
        reason=$(printf '%s' "$reason" | tr '\n\r' '  ' | cut -c1-300)
        { printf 'refused\nreason %s\n' "$reason"; cat "$T/lines"; } >"$T/verdict"
        printf '%s: refused: %s\n' "$PROG" "$reason" >&2
    fi
    ks=$(dc_seal "$SESSION" teardown_handoff "$T/verdict" teardown_handoff) || die2 "cannot store the verdict"
    if [ "$word" = ready ]; then
        bash "$DC_COORD_LOG" seal --session "$SESSION" --state teardown_handoff --token "handoff-ready keyseal:${ks#sealed:}" || die2 "cannot seal the verdict"
    else
        bash "$DC_COORD_LOG" seal --session "$SESSION" --state teardown_handoff --token "handoff-refused" || die2 "cannot seal the verdict"
    fi
    exit 0
}
refuse() { emit refused "$1"; }

# niwa_list: niwa's listing at the workspace root, into NL; a listing that
# can't be read or isn't a JSON array stops the seal (exit 2, tick again).
niwa_list() {
    ROOT=$(dc_workspace_root) || refuse "no workspace root found"
    NL=$(cd "$ROOT" && "$NIWA" list --json) || die2 "niwa list could not be read"
    printf '%s' "$NL" | jq -e 'type == "array"' >/dev/null || die2 "niwa list is not a JSON array"
}
# agents_list: Claude Code's job listing, into AG, the same way.
agents_list() {
    AG=$("$CLAUDE_CLI" agents --json --all) || die2 "claude agents could not be read"
    printf '%s' "$AG" | jq -e 'type == "array"' >/dev/null || die2 "claude agents is not a JSON array"
}

# stopped_mode: the instance by the inventory's path in niwa's listing, and
# the one finished Claude Code job in it, with its transcript.
stopped_mode() {
    IPATH=$(sed -n '/^instance /{s///p;q;}' <<<"$INV")
    case "$IPATH" in /*) ;; *) refuse "the sealed inventory names no instance path" ;; esac

    # The instance, by its path, in niwa's listing.
    niwa_list
    MATCH=$(printf '%s' "$NL" | jq -c --arg p "$IPATH" '[.[] | select(.path == $p)]')
    [ "$(printf '%s' "$MATCH" | jq length)" = 1 ] || refuse "niwa lists $(printf '%s' "$MATCH" | jq length) instances at $IPATH, not one"
    INAME=$(printf '%s' "$MATCH" | jq -r '.[0].name // ""')
    NSESS=$(printf '%s' "$MATCH" | jq -r '.[0].session_name // ""')
    grep -Eq '^[A-Za-z0-9][A-Za-z0-9._+-]*$' <<<"$INAME" || refuse "niwa's name for the instance is not a plain instance name"
    line "instance $INAME $IPATH"
    # niwa's dispatch id for the instance, for the cost entry: the value only
    # when it has the shape of an id, so nothing else reaches the archive.
    DISPATCH=$(printf '%s' "$MATCH" | jq -r '.[0].dispatch_id
        | if . == null then "-"
          elif type == "string" and length >= 1 and length <= 128 and (gsub("[A-Za-z0-9._:-]"; "") == "") then .
          else "invalid" end')

    # The job: the one Claude Code background job whose cwd is the instance.
    agents_list
    JOBS=$(printf '%s' "$AG" | jq -c --arg p "$IPATH" '[.[] | select(.cwd == $p)]')
    NJ=$(printf '%s' "$JOBS" | jq length)
    case "$NJ" in
        1) ;;
        0) refuse "no Claude Code job runs in $IPATH" ;;
        *) refuse "$NJ Claude Code jobs ran in $IPATH ($(printf '%s' "$JOBS" | jq -r '[.[].id] | join(", ")')); name one by hand" ;;
    esac
    JOB=$(printf '%s' "$JOBS" | jq -r '.[0].id // ""')
    SID=$(printf '%s' "$JOBS" | jq -r '.[0].sessionId // ""')
    JNAME=$(printf '%s' "$JOBS" | jq -r '.[0].name // ""')
    grep -Eq '^[0-9a-f]{6,64}$' <<<"$JOB" || refuse "the job id [$JOB] is not a job id"
    grep -Eq '^[0-9a-f][0-9a-f-]{7,63}$' <<<"$SID" || refuse "the job's session id is not a session id"
    # Only a job known to be finished passes, because `claude rm` on a running
    # job is the one thing this must never set up. The listing's state can't
    # say so: Claude Code 2.1.293 listed a stopped job as `done`, but 2.1.309
    # lists every job as `working`. The job's own state file and the
    # listing's pid still can, and a disagreement in the running direction (a
    # live pid, a state file reading working) refuses. A wrong answer here
    # only refuses, leaving the teardown to a person.
    WHY=$(dc_job_finished "$CLAUDE_HOME" "$JOB" "$(printf '%s' "$JOBS" | jq -c '.[0]')") || refuse "$WHY"
    if [ -n "$NSESS" ] && [ -n "$JNAME" ] && [ "$NSESS" != "$JNAME" ]; then
        refuse "niwa maps the instance to session $NSESS, but job $JOB is $JNAME"
    fi
    line "job $JOB $SID"
    find "$CLAUDE_HOME/projects" -mindepth 2 -maxdepth 2 -name "$SID.jsonl" -type f >"$T/tr" 2>/dev/null
    [ "$(wc -l <"$T/tr" | tr -d ' ')" = 1 ] || refuse "found $(wc -l <"$T/tr" | tr -d ' ') transcripts for session $SID, not one"
    line "transcript $(cat "$T/tr")"
}

# project_dir_name <path>: the name Claude Code gives the project directory
# for a working directory, every character outside [A-Za-z0-9] made `-`.
project_dir_name() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

# instance_of <path>: the shortest prefix of an absolute path whose last
# component is `<anything>+<slug>-<8 hex>`, the shape of a niwa instance
# directory for the topic; 1 when there is none.
instance_of() {
    local rest=${1#/} acc="" c
    case "$1" in /*) ;; *) return 1 ;; esac
    while [ -n "$rest" ]; do
        c=${rest%%/*}
        acc="$acc/$c"
        if [[ $c =~ $RE_INSTANCE ]]; then
            printf '%s\n' "$acc"
            return 0
        fi
        case "$rest" in */*) rest=${rest#*/} ;; *) rest="" ;; esac
    done
    return 1
}

# candidate <path>: print the instance path a recorded path points at, when
# it is absolute, holds no `..` and sits directly under the workspace root.
candidate() {
    local c
    c=$(instance_of "$1") || return 1
    case "/$c/" in */../* | */./*) return 1 ;; esac
    [ "$(dirname "$c")" = "$ROOT" ] || return 1
    printf '%s\n' "$c"
}

# sort_key <timestamp>: a UTC `YYYY-MM-DDTHH:MM:SS[.f]Z` timestamp as a key
# that compares as a string in time order: the seconds, then the fraction
# padded or cut to nine digits. Compared raw, `...:05.1Z` would sort before
# `...:05Z`, since `.` sorts before `Z`. Returns 1 for any other shape.
sort_key() {
    local base frac
    grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$' <<<"$1" || return 1
    base=${1%Z} frac=""
    case "$base" in *.*) frac=${base#*.} base=${base%%.*} ;; esac
    printf '%s.%s\n' "$base" "$(printf '%-9.9s' "$frac" | tr ' ' 0)"
}

# removed_mode: the unit was torn down outside the pass. Read what is left of
# it, refusing on any sign that it isn't gone.
removed_mode() {
    local slug enc re_dir f ed c n d name ts key best_ts="" best="" sid
    line "removed yes"
    niwa_list
    # niwa lists nothing for the topic: no session named for it.
    printf '%s' "$NL" | jq -r '.[] | .session_name | strings' >"$T/niwa-sessions"
    while IFS= read -r n; do
        dc_session_matches "$TOPIC" "$n" && refuse "niwa lists an instance for $TOPIC (session $n); it was not removed"
    done <"$T/niwa-sessions"

    slug=$(dc_niwa_slug "$TOPIC")
    [ -n "$slug" ] || refuse "the topic has no niwa slug"
    RE_INSTANCE="^[^/]+\\+${slug}-[0-9a-f]{8}\$"
    # The instance's path. koto's session headers first: a worker's sessions
    # record the directory they ran in.
    : >"$T/cands"
    # Only a session file holding `+<slug>-` can record a path candidate()
    # accepts, so one grep picks the files whose header is worth opening; a
    # koto home with a thousand sessions would otherwise cost a head and a jq
    # for each of them. grep reads every session file whole, not only its
    # header: about 1.3 s on a store of 990 files and 151 MB, well inside the
    # action's limit, so the one grep stays rather than a per-file read of
    # first lines. A hit is no candidate by itself: the coordinator's own
    # sessions always pass, since their later lines name worker paths, and
    # candidate() still decides on the header's execution_dir. grep answers
    # 1 when nothing holds the string, and a file it can't read is skipped,
    # as the head below would skip it; neither stops the seal.
    : >"$T/headers"
    set -- "$KOTO_SESSIONS"/*/koto-*.state.jsonl
    if [ -e "$1" ] || [ -L "$1" ]; then
        printf '%s\0' "$@" | xargs -0 grep -lsF --null -e "+${slug}-" -- >"$T/headers" 2>>"$T/grep.err"
    fi
    while IFS= read -r -d '' f; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        # A header that isn't JSON names no candidate; jq's complaint about it
        # is kept in the run's scratch directory, not shown.
        ed=$(head -n 1 "$f" | jq -r '.execution_dir // "" | strings' 2>>"$T/jq.err") || continue
        candidate "$ed" >>"$T/cands"
    done <"$T/headers"
    sort -u "$T/cands" >"$T/cands.u"
    # Else the transcripts' cwd values, in the project directories named for
    # such a path (the instance itself, or a directory under it).
    if [ ! -s "$T/cands.u" ]; then
        enc=$(project_dir_name "$slug")
        re_dir="-${enc}-[0-9a-f]{8}(-|\$)"
        for d in "$CLAUDE_HOME/projects"/*/; do
            [ -d "$d" ] && [ ! -L "${d%/}" ] || continue
            name=$(basename "$d")
            [[ $name =~ $re_dir ]] || continue
            for f in "$d"*.jsonl; do
                [ -f "$f" ] && [ ! -L "$f" ] || continue
                grep -Eo '"cwd" *: *"[^"]*"' "$f" 2>/dev/null | sed -E 's/^"cwd" *: *"//; s/"$//'
            done | sort -u | while IFS= read -r ed; do
                c=$(candidate "$ed") || continue
                case "$name" in "$(project_dir_name "$c")" | "$(project_dir_name "$c")"-*) printf '%s\n' "$c" ;; esac
            done >>"$T/cands"
        done
        sort -u "$T/cands" >"$T/cands.u"
    fi
    n=$(wc -l <"$T/cands.u" | tr -d ' ')
    case "$n" in
        1) ;;
        0) refuse "no instance path for $TOPIC could be recovered from koto sessions or transcripts" ;;
        *) refuse "$n instance paths for $TOPIC were recovered ($(tr '\n' ' ' <"$T/cands.u" | sed 's/ $//')), not one" ;;
    esac
    IPATH=$(cat "$T/cands.u")
    printf '%s' "$NL" | jq -e --arg p "$IPATH" 'any(.[]; .path == $p) | not' >/dev/null \
        || refuse "niwa lists an instance at $IPATH; it was not removed"
    agents_list
    printf '%s' "$AG" | jq -e --arg p "$IPATH" 'any(.[]; .cwd == $p) | not' >/dev/null \
        || refuse "Claude Code lists job $(printf '%s' "$AG" | jq -r --arg p "$IPATH" '[.[] | select(.cwd == $p) | .id] | join(", ")') in $IPATH; it was not removed"
    line "instance - $IPATH"

    # The worker's session: the main session transcript in the instance's own
    # project directory whose first event is latest. The id names the
    # archive; with none, nothing is archived.
    d="$CLAUDE_HOME/projects/$(project_dir_name "$IPATH")"
    for f in "$d"/*.jsonl; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        sid=$(basename "$f" .jsonl)
        grep -Eq '^[0-9a-f]{8}[0-9a-f-]{0,56}$' <<<"$sid" || continue
        ts=$(jq -R -r 'fromjson? | objects | .timestamp | strings' "$f" 2>>"$T/jq.err" | head -n 1)
        key=$(sort_key "$ts") || continue
        if [ -z "$best" ] || [[ $key > $best_ts ]]; then
            best=$f best_ts=$key
        fi
    done
    if [ -n "$best" ]; then
        SID=$(basename "$best" .jsonl)
        JOB=$(printf '%s' "$SID" | cut -c1-8)
        line "job $JOB $SID"
        line "transcript $best"
    else
        line "job -"
    fi
    # niwa's row, and its dispatch id, went with the instance.
    DISPATCH=-
}

# The topic and the sealed inventory.
TOPIC=$("$KOTO" context get "$SESSION" teardown_topic) || die2 "cannot read teardown_topic"
dc_valid_topic "$TOPIC" || refuse "teardown_topic is not a dispatch topic"
line "topic $TOPIC"
INV=$(bash "$HERE/teardown-verdict.sh" read --session "$SESSION" 2>"$T/inv.err")
case $? in
    0) REMOVED=0 ;;
    2) die2 "the sealed inventory can't be read: $(tail -1 "$T/inv.err")" ;;
    # 5: the sealed inventory stands and says absent (niwa lists no instance
    # for the topic); only this seal, in removed mode, can admit it.
    5) REMOVED=1 ;;
    *) refuse "the sealed inventory doesn't stand: $(tail -1 "$T/inv.err")" ;;
esac
INV_TOKEN=$(dc_capture "$SESSION" TEARDOWN_SEAL | grep -Eo 'sealed:[0-9]+:[0-9a-f]{64}' | tail -1)
[ -n "$INV_TOKEN" ] || refuse "the inventory's seal is missing"

# The evidence submitted at the latest visit to teardown: its word picks the
# mode, and its link is the handoff, checked below.
ENT=$(bash "$DC_COORD_LOG" entry --session "$SESSION" --state teardown) || die2 "the session log has no entry into teardown"
EV=$(bash "$DC_COORD_LOG" evidence --session "$SESSION" --state teardown --after "${ENT%% *}" --where 'teardown=stopped|removed')
case $? in 0) ;; 1) refuse "no teardown: stopped or removed evidence at the latest visit to teardown" ;; *) die2 "the session log can't be read" ;; esac
EVWORD=$(printf '%s' "$EV" | jq -r '.fields.teardown // ""')

if [ "$REMOVED" = 1 ]; then
    [ "$EVWORD" = removed ] || refuse "niwa lists no instance for $TOPIC, but the latest teardown evidence is $EVWORD, not removed"
    removed_mode
else
    # A `removed` that finds the instance still listed is refused here: the
    # unit wasn't torn down, and nothing it claimed is acted on.
    [ "$EVWORD" = stopped ] || refuse "teardown: $EVWORD, but niwa still lists the instance the inventory read; it was not removed"
    stopped_mode
fi

# The holding's merged pull requests.
ROW=$(dc_record_read "$SESSION" "$TOPIC")
case $? in 0) ;; 1) refuse "the record has no holding for $TOPIC" ;; *) die2 "the record could not be read" ;; esac
REPO=$(printf '%s' "$ROW" | jq -r '.repo // ""')
BRANCH=$(printf '%s' "$ROW" | jq -r '.branch // ""')
UNIT=$(printf '%s' "$ROW" | jq -r '.unit // ""')
grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' <<<"$REPO" || refuse "the holding names no repository"
[ -n "$BRANCH" ] || refuse "the holding names no branch"
dc_with_deadline "$FETCH_SECS" "$GH" pr list --repo "$REPO" --head "$BRANCH" --state merged --limit 100 \
    --json number,mergeCommit,headRepositoryOwner >"$T/prs" 2>"$T/gh.err" || die2 "the merged pull requests could not be read: $(tail -1 "$T/gh.err")"
# --head matches a branch name in any fork; only the holding's own
# repository's branch is the unit's.
jq -r --arg o "${REPO%%/*}" '.[] | select((.headRepositoryOwner.login // "" | ascii_downcase) == ($o | ascii_downcase))
    | select((.mergeCommit.oid // "") | test("^[0-9a-f]{40}$")) | "\(.number) \(.mergeCommit.oid)"' "$T/prs" >"$T/merged" \
    || die2 "the merged pull requests are not readable JSON"
[ -s "$T/merged" ] || refuse "no pull request from $BRANCH in $REPO is merged"
NUMS=""
while read -r n sha; do
    line "pr $REPO#$n $sha"
    NUMS="$NUMS $n"
done <"$T/merged"
# The holding's issue, when its unit names one in the same repository.
case "$UNIT" in
    \#[0-9]*) NUMS="$NUMS ${UNIT#\#}" ;;
    "$REPO#"[0-9]*) NUMS="$NUMS ${UNIT#"$REPO#"}" ;;
esac

# The handoff: the link submitted at the latest visit to teardown.
URL=$(printf '%s' "$EV" | jq -r '.fields.handoff // ""')
[ -n "$URL" ] || refuse "teardown: $EVWORD carried no handoff link"
RE_URL='^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/(pull|issues)/([1-9][0-9]*)#issuecomment-([1-9][0-9]*)$'
[[ $URL =~ $RE_URL ]] || refuse "the handoff link is not a GitHub comment link"
U_REPO=${BASH_REMATCH[1]} U_NUM=${BASH_REMATCH[3]} U_ID=${BASH_REMATCH[4]}
[ "$U_REPO" = "$REPO" ] || refuse "the handoff comment is in $U_REPO, not the holding's $REPO"
case " $NUMS " in *" $U_NUM "*) ;; *) refuse "the handoff comment is on #$U_NUM, which is neither a merged pull request of the unit nor its issue" ;; esac
dc_with_deadline "$FETCH_SECS" "$GH" api "repos/$REPO/issues/comments/$U_ID" >"$T/comment" 2>"$T/gh.err"
case $? in
    0) ;;
    *) grep -q 'HTTP 404' "$T/gh.err" && refuse "the handoff comment doesn't exist"
       die2 "the handoff comment could not be read: $(tail -1 "$T/gh.err")" ;;
esac
jq -e --arg n "$U_NUM" '(.issue_url // "" | endswith("/issues/" + $n)) and ((.body // "") | test("[^[:space:]]"))' "$T/comment" >/dev/null \
    || refuse "the handoff comment is empty or not on #$U_NUM"
line "handoff $URL"
line "dispatch $DISPATCH"
line "inventory $INV_TOKEN"
emit ready
