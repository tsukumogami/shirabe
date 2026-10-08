#!/usr/bin/env bash
# teardown-handoff.sh -- the one verdict a teardown pass acts on.
#
# The teardown_handoff state runs this after the inventory read durable. It
# reads, before anything is removed, every fact the pass needs, and seals them
# as one verdict, so the local agent that runs the pass (teardown-pass.sh) is
# handed a target it can check rather than one it is told:
#
#   topic <t>                      teardown_topic, as the sealed inventory has it
#   instance <name> <path>         from `niwa list --json`, matched by the
#                                  inventory's instance path
#   job <id> <session id>          from `claude agents --json --all`: the one
#                                  job whose cwd is the instance path, in a
#                                  state known to be finished (done, stopped,
#                                  failed); any other state, a missing one
#                                  included, refuses
#   transcript <path>              <claude home>/projects/*/<session id>.jsonl
#   pr <owner/repo>#<n> <sha>      each pull request GitHub lists as merged
#                                  from the holding's branch, with its merge
#                                  commit; one line per pull request
#   handoff <url>                  the comment link submitted with `teardown:
#                                  stopped` at the latest visit to teardown,
#                                  read back from GitHub: a comment on one of
#                                  those pull requests or on the holding's
#                                  issue, with a body
#   inventory <sealed:...>         the sealed inventory the verdict stands on
#
# Nothing here comes from an argument: the topic and the inventory from the
# session, the handoff link from the session's own log of the evidence, the
# rest from niwa, Claude Code and GitHub.
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
# TEARDOWN_CLAUDE_HOME is Claude Code's home (default ~/.claude);
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
    KS=$(printf '%s' "$CAP" | grep -Eo 'keyseal:[0-9]+:[0-9a-f]{64}' | head -1)
    [ -n "$STATE_SEAL" ] && [ -n "$KS" ] || { printf '%s: the capture is not sealed\n' "$PROG" >&2; exit 3; }
    # The capture is this visit's: the engine wrote it, and its seal names the
    # latest entry into teardown_handoff.
    bash "$DC_COORD_LOG" check --session "$SESSION" --state teardown_handoff --sealed "$CAP" >/dev/null
    case $? in 0) ;; 1) printf '%s: the capture is not this visit'"'"'s\n' "$PROG" >&2; exit 3 ;; *) die2 "the session log can't be read" ;; esac
    VERDICT=$(dc_seal_check "$SESSION" teardown_handoff "sealed:${KS#keyseal:}" teardown_handoff)
    case $? in 0) ;; 1) printf '%s: the stored verdict does not match its key seal\n' "$PROG" >&2; exit 3 ;; *) die2 "the stored verdict can't be read" ;; esac
    [ "$(printf '%s\n' "$VERDICT" | sed -n 1p)" = ready ] || { printf '%s: the stored verdict is not ready\n' "$PROG" >&2; exit 3; }
    VT=$(printf '%s\n' "$VERDICT" | sed -n 's/^topic //p' | head -1)
    NOW=$("$KOTO" context get "$SESSION" teardown_topic 2>/dev/null) || die2 "cannot read teardown_topic"
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

# The topic and the sealed inventory.
TOPIC=$("$KOTO" context get "$SESSION" teardown_topic 2>/dev/null) || die2 "cannot read teardown_topic"
dc_valid_topic "$TOPIC" || refuse "teardown_topic is not a dispatch topic"
line "topic $TOPIC"
INV=$(bash "$HERE/teardown-verdict.sh" read --session "$SESSION" 2>"$T/inv.err")
case $? in
    0) ;;
    2) die2 "the sealed inventory can't be read: $(tail -1 "$T/inv.err")" ;;
    *) refuse "the sealed inventory doesn't stand: $(tail -1 "$T/inv.err")" ;;
esac
INV_TOKEN=$(dc_capture "$SESSION" TEARDOWN_SEAL | grep -Eo 'sealed:[0-9]+:[0-9a-f]{64}' | tail -1)
[ -n "$INV_TOKEN" ] || refuse "the inventory's seal is missing"
IPATH=$(printf '%s\n' "$INV" | sed -n 's/^instance //p' | head -1)
case "$IPATH" in /*) ;; *) refuse "the sealed inventory names no instance path" ;; esac

# The instance, by its path, in niwa's listing.
ROOT=$(dc_workspace_root) || refuse "no workspace root found"
NL=$(cd "$ROOT" && "$NIWA" list --json 2>/dev/null) || die2 "niwa list could not be read"
printf '%s' "$NL" | jq -e 'type == "array"' >/dev/null 2>&1 || die2 "niwa list is not a JSON array"
MATCH=$(printf '%s' "$NL" | jq -c --arg p "$IPATH" '[.[] | select(.path == $p)]')
[ "$(printf '%s' "$MATCH" | jq length)" = 1 ] || refuse "niwa lists $(printf '%s' "$MATCH" | jq length) instances at $IPATH, not one"
INAME=$(printf '%s' "$MATCH" | jq -r '.[0].name // ""')
NSESS=$(printf '%s' "$MATCH" | jq -r '.[0].session_name // ""')
printf '%s' "$INAME" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._+-]*$' || refuse "niwa's name for the instance is not a plain instance name"
line "instance $INAME $IPATH"

# The job: the one Claude Code background job whose cwd is the instance.
AG=$("$CLAUDE_CLI" agents --json --all 2>/dev/null) || die2 "claude agents could not be read"
printf '%s' "$AG" | jq -e 'type == "array"' >/dev/null 2>&1 || die2 "claude agents is not a JSON array"
JOBS=$(printf '%s' "$AG" | jq -c --arg p "$IPATH" '[.[] | select(.cwd == $p)]')
NJ=$(printf '%s' "$JOBS" | jq length)
case "$NJ" in
    1) ;;
    0) refuse "no Claude Code job runs in $IPATH" ;;
    *) refuse "$NJ Claude Code jobs ran in $IPATH ($(printf '%s' "$JOBS" | jq -r '[.[].id] | join(", ")')); name one by hand" ;;
esac
JOB=$(printf '%s' "$JOBS" | jq -r '.[0].id // ""')
SID=$(printf '%s' "$JOBS" | jq -r '.[0].sessionId // ""')
JSTATE=$(printf '%s' "$JOBS" | jq -r '.[0].state // ""')
JNAME=$(printf '%s' "$JOBS" | jq -r '.[0].name // ""')
printf '%s' "$JOB" | grep -Eq '^[0-9a-f]{6,64}$' || refuse "the job id [$JOB] is not a job id"
printf '%s' "$SID" | grep -Eq '^[0-9a-f][0-9a-f-]{7,63}$' || refuse "the job's session id is not a session id"
# Only a state known to be finished passes: a job whose state is missing,
# renamed or new to this script is treated as possibly running, because
# `claude rm` on a running job is the one thing this must never set up.
# Claude Code 2.1.293 was seen to list a running job as `working` and a
# finished or stopped one as `done`; `stopped` and `failed` are its other
# finished names. A wrong name here only refuses, leaving the teardown to a
# person.
case "$JSTATE" in
    done | stopped | failed) ;;
    working) refuse "job $JOB is still working; stop it before the inventory" ;;
    *) refuse "job $JOB is in state [$JSTATE], which isn't known to be finished" ;;
esac
if [ -n "$NSESS" ] && [ -n "$JNAME" ] && [ "$NSESS" != "$JNAME" ]; then
    refuse "niwa maps the instance to session $NSESS, but job $JOB is $JNAME"
fi
line "job $JOB $SID"
find "$CLAUDE_HOME/projects" -mindepth 2 -maxdepth 2 -name "$SID.jsonl" -type f >"$T/tr" 2>/dev/null
[ "$(wc -l <"$T/tr" | tr -d ' ')" = 1 ] || refuse "found $(wc -l <"$T/tr" | tr -d ' ') transcripts for session $SID, not one"
line "transcript $(cat "$T/tr")"

# The holding's merged pull requests.
ROW=$(dc_record_read "$SESSION" "$TOPIC")
case $? in 0) ;; 1) refuse "the record has no holding for $TOPIC" ;; *) die2 "the record could not be read" ;; esac
REPO=$(printf '%s' "$ROW" | jq -r '.repo // ""')
BRANCH=$(printf '%s' "$ROW" | jq -r '.branch // ""')
UNIT=$(printf '%s' "$ROW" | jq -r '.unit // ""')
printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || refuse "the holding names no repository"
[ -n "$BRANCH" ] || refuse "the holding names no branch"
dc_with_deadline "$FETCH_SECS" "$GH" pr list --repo "$REPO" --head "$BRANCH" --state merged --limit 100 \
    --json number,mergeCommit,headRepositoryOwner >"$T/prs" 2>"$T/gh.err" || die2 "the merged pull requests could not be read: $(tail -1 "$T/gh.err")"
# --head matches a branch name in any fork; only the holding's own
# repository's branch is the unit's.
jq -r --arg o "${REPO%%/*}" '.[] | select((.headRepositoryOwner.login // "" | ascii_downcase) == ($o | ascii_downcase))
    | select((.mergeCommit.oid // "") | test("^[0-9a-f]{40}$")) | "\(.number) \(.mergeCommit.oid)"' "$T/prs" >"$T/merged" 2>/dev/null \
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
ENT=$(bash "$DC_COORD_LOG" entry --session "$SESSION" --state teardown) || die2 "the session log has no entry into teardown"
EV=$(bash "$DC_COORD_LOG" evidence --session "$SESSION" --state teardown --after "${ENT%% *}" --where teardown=stopped)
case $? in 0) ;; 1) refuse "no teardown: stopped evidence at the latest visit to teardown" ;; *) die2 "the session log can't be read" ;; esac
URL=$(printf '%s' "$EV" | jq -r '.fields.handoff // ""')
[ -n "$URL" ] || refuse "teardown: stopped carried no handoff link"
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
jq -e --arg n "$U_NUM" '(.issue_url // "" | endswith("/issues/" + $n)) and ((.body // "") | test("[^[:space:]]"))' "$T/comment" >/dev/null 2>&1 \
    || refuse "the handoff comment is empty or not on #$U_NUM"
line "handoff $URL"
line "inventory $INV_TOKEN"
emit ready
