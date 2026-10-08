#!/usr/bin/env bash
# teardown-pass.sh -- one teardown pass over one sealed target, and the check
# that reads its result.
#
# The coordinator's local teardown agent (references/teardown-agent.md) runs
# `run` with the session and the key seal it was handed. Its target is read
# from the session itself, through `teardown-handoff.sh read`, never taken from
# the message or an argument: the key seal it was handed is only compared with
# the one that read prints, so a stale or edited hand-off refuses.
#
# Usage:
#   teardown-pass.sh run --session <s> --keyseal <keyseal:seq:sha256>
#       In order, stopping at the first failure:
#         1. read the verdict (seal, topic, no directed transition) and match
#            the key seal;
#         2. re-read every fact: each pull request still merged at its merge
#            commit, the handoff comment still there, the job still listed
#            with the same cwd and session in a finished state (done,
#            stopped or failed), niwa still
#            listing the instance by that name and path;
#         3. re-inventory the instance (teardown-inventory.sh, unsealed);
#            anything but durable refuses;
#         4. preserve, into <archive>/<UTC date>-<topic>-<job id>/: the
#            transcript and its sibling subagent directory, the job's
#            state.json, timeline.jsonl and tmp/, and every koto session
#            whose header's execution_dir is at or under the instance path or
#            the job's tmp/; each copy checked against its source's hash, a
#            MANIFEST (`<sha256> <bytes> <path>` per file) and a README;
#         5. `niwa destroy --force <name>` at the workspace root, the name
#            checked before the command is built;
#         6. `claude rm <job id>`;
#         7. confirm `niwa list --json` no longer shows the instance and
#            `claude agents --json --all` no longer shows the job.
#       RESULT in the archive says `done`, or why the pass stopped once the
#       archive exists. A rerun on the same UTC day reuses the day's archive
#       directory; one on a later day makes a second, and `confirm` then
#       reports that it can't find a single archive.
#       Steps 1 to 4 remove nothing, so a failure there is `refused`; a
#       failure from step 5 on is `incomplete`, naming the step.
#   teardown-pass.sh confirm --session <s>
#       The teardown_confirm state's default action: reads the verdict the
#       same way, both listings, and the archive (RESULT says done, every
#       MANIFEST file present at its size; the full hash check is run's), and
#       prints, sealed to this visit, `teardown-confirmed` or
#       `teardown-incomplete`, the reason in context key
#       coord/teardown_confirm.json and on stderr.
#
# Output (run): progress lines, then one last line `teardown-pass: done
# <archive>`, `teardown-pass: refused: <why>` or `teardown-pass: incomplete at
# <step>: <why>`. File contents are never printed, only paths and hashes.
#
# Exit codes (run): 0 done; 1 refused, nothing removed; 2 incomplete, after
# the destroy began; 64 usage. (confirm): 0 a verdict printed; 2 a read or
# the seal failed; 64 usage.
#
# Environment: NIWA, CLAUDE_CLI, GH and KOTO name the tools (tests);
# TEARDOWN_CLAUDE_HOME (default ~/.claude), TEARDOWN_KOTO_SESSIONS (default
# ~/.koto/sessions), TEARDOWN_ARCHIVE_DIR (default
# ${XDG_DATA_HOME:-~/.local/share}/teardown-archive), TEARDOWN_FETCH_SECS
# (each GitHub read's bound, default 8). bash 3.2.
set -uo pipefail

PROG=teardown-pass
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

KOTO="${KOTO:-koto}"
GH="${GH:-gh}"
NIWA="${NIWA:-niwa}"
CLAUDE_CLI="${CLAUDE_CLI:-claude}"
CLAUDE_HOME="${TEARDOWN_CLAUDE_HOME:-$HOME/.claude}"
KOTO_SESSIONS="${TEARDOWN_KOTO_SESSIONS:-$HOME/.koto/sessions}"
ARCHIVE_ROOT="${TEARDOWN_ARCHIVE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/teardown-archive}"
FETCH_SECS="${TEARDOWN_FETCH_SECS:-8}"

usage() { sed -n '/^# Usage:/,/^# Output (run)/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

MODE="${1:-}"
[ $# -gt 0 ] && shift
SESSION="" WANT_KS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION="$2"; shift 2 ;;
        --keyseal) [ $# -ge 2 ] || usage; WANT_KS="$2"; shift 2 ;;
        *) usage ;;
    esac
done
case "$MODE" in run) [ -n "$WANT_KS" ] || usage ;; confirm) [ -z "$WANT_KS" ] || usage ;; *) usage ;; esac
[ -n "$SESSION" ] || usage

T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-pass.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
say() { printf '%s: %s\n' "$PROG" "$*"; }
STEP=read
ARCH=""
refused() { say "refused: $*"; [ -n "$ARCH" ] && [ -d "$ARCH" ] && printf 'refused at %s: %s\n' "$STEP" "$*" >"$ARCH/RESULT"; exit 1; }
incomplete() { say "incomplete at $STEP: $*"; [ -n "$ARCH" ] && printf 'incomplete at %s: %s\n' "$STEP" "$*" >"$ARCH/RESULT"; exit 2; }

# ---------------------------------------------------------------------------
# The verdict, through the one reader; sets TOPIC, INAME, IPATH, JOB, SID, TR,
# HANDOFF, PRS (one `owner/repo#n sha` per line) and KS. Returns 1 with the
# reason in $T/why when it doesn't stand.
read_verdict() {
    local v rc
    v=$(bash "$HERE/teardown-handoff.sh" read --session "$SESSION" 2>"$T/why")
    rc=$?
    [ "$rc" = 0 ] || { [ -s "$T/why" ] || echo "the verdict can't be read" >"$T/why"; return 1; }
    TOPIC=$(printf '%s\n' "$v" | sed -n 's/^topic //p' | head -1)
    INAME=$(printf '%s\n' "$v" | sed -n 's/^instance \([^ ]*\) .*/\1/p' | head -1)
    IPATH=$(printf '%s\n' "$v" | sed -n 's/^instance [^ ]* //p' | head -1)
    JOB=$(printf '%s\n' "$v" | sed -n 's/^job \([^ ]*\) .*/\1/p' | head -1)
    SID=$(printf '%s\n' "$v" | sed -n 's/^job [^ ]* //p' | head -1)
    TR=$(printf '%s\n' "$v" | sed -n 's/^transcript //p' | head -1)
    HANDOFF=$(printf '%s\n' "$v" | sed -n 's/^handoff //p' | head -1)
    PRS=$(printf '%s\n' "$v" | sed -n 's/^pr //p')
    KS=$(printf '%s\n' "$v" | sed -n 's/^keyseal //p' | tail -1)
    # The fields the commands are built from are checked here, whatever the
    # verdict says: an empty or odd name never reaches niwa or claude.
    dc_valid_topic "$TOPIC" || { echo "the verdict's topic is not a dispatch topic" >"$T/why"; return 1; }
    printf '%s' "$INAME" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._+-]*$' || { echo "the verdict's instance name is not a plain name" >"$T/why"; return 1; }
    case "$IPATH" in /*) ;; *) echo "the verdict's instance path is not absolute" >"$T/why"; return 1 ;; esac
    printf '%s' "$JOB" | grep -Eq '^[0-9a-f]{6,64}$' || { echo "the verdict's job id is not a job id" >"$T/why"; return 1; }
    printf '%s' "$SID" | grep -Eq '^[0-9a-f][0-9a-f-]{7,63}$' || { echo "the verdict's session id is not a session id" >"$T/why"; return 1; }
    [ -n "$PRS" ] || { echo "the verdict names no merged pull request" >"$T/why"; return 1; }
    return 0
}

niwa_list() { (cd "$ROOT" && "$NIWA" list --json) 2>/dev/null; }
agents() { "$CLAUDE_CLI" agents --json --all 2>/dev/null; }

# ---------------------------------------------------------------------------
if [ "$MODE" = confirm ]; then
    verdict() {
        local word=$1 why=$2
        jq -nc --arg v "$word" --arg w "$why" --arg a "${ARCH:-}" '{verdict: $v, reason: $w, archive: $a}' >"$T/detail.json"
        "$KOTO" context add "$SESSION" coord/teardown_confirm.json --from-file "$T/detail.json" >/dev/null 2>&1 \
            || { say "cannot store the detail"; exit 2; }
        [ "$word" = teardown-confirmed ] || say "$why" >&2
        bash "$DC_COORD_LOG" seal --session "$SESSION" --state teardown_confirm --token "$word" || { say "cannot seal the verdict"; exit 2; }
        exit 0
    }
    read_verdict || verdict teardown-incomplete "$(cat "$T/why")"
    ROOT=$(dc_workspace_root) || verdict teardown-incomplete "no workspace root found"
    NL=$(niwa_list) || { say "niwa list could not be read"; exit 2; }
    printf '%s' "$NL" | jq -e --arg n "$INAME" --arg p "$IPATH" 'type == "array" and (any(.[]; .name == $n or .path == $p) | not)' >/dev/null 2>&1 \
        || verdict teardown-incomplete "niwa still lists $INAME"
    AG=$(agents) || { say "claude agents could not be read"; exit 2; }
    printf '%s' "$AG" | jq -e --arg j "$JOB" 'type == "array" and (any(.[]; .id == $j) | not)' >/dev/null 2>&1 \
        || verdict teardown-incomplete "claude agents still lists job $JOB"
    ls -d "$ARCHIVE_ROOT"/*-"$TOPIC-$JOB" >"$T/arch" 2>/dev/null
    [ "$(wc -l <"$T/arch" | tr -d ' ')" = 1 ] || verdict teardown-incomplete "no single archive for $TOPIC and job $JOB under $ARCHIVE_ROOT"
    ARCH=$(cat "$T/arch")
    case "$(head -1 "$ARCH/RESULT" 2>/dev/null)" in done*) ;; *) verdict teardown-incomplete "the archive's RESULT doesn't say done" ;; esac
    [ -s "$ARCH/MANIFEST" ] || verdict teardown-incomplete "the archive has no MANIFEST"
    while read -r h size rel; do
        [ -n "$rel" ] || continue
        [ -f "$ARCH/$rel" ] || verdict teardown-incomplete "$rel is missing from the archive"
        [ "$(wc -c <"$ARCH/$rel" | tr -d ' ')" = "$size" ] || verdict teardown-incomplete "$rel in the archive is not the size the MANIFEST records"
    done <"$ARCH/MANIFEST"
    verdict teardown-confirmed "the instance and the job are gone and the archive is whole"
fi

# ---------------------------------------------------------------------------
# run
say "reading the verdict"
read_verdict || refused "$(cat "$T/why")"
[ "$KS" = "$WANT_KS" ] || refused "the key seal handed over is not the session's current verdict"
ROOT=$(dc_workspace_root) || refused "no workspace root found"

STEP=facts
say "re-reading the facts for $TOPIC"
while read -r ref sha; do
    [ -n "$ref" ] || continue
    repo=${ref%#*} n=${ref##*#}
    out=$(dc_with_deadline "$FETCH_SECS" "$GH" pr view "$n" --repo "$repo" --json state,mergeCommit 2>"$T/gh.err") \
        || refused "$ref could not be read: $(tail -1 "$T/gh.err")"
    printf '%s' "$out" | jq -e --arg s "$sha" '.state == "MERGED" and (.mergeCommit.oid // "") == $s' >/dev/null 2>&1 \
        || refused "$ref is not merged at $sha"
done <<EOF
$PRS
EOF
cid=${HANDOFF##*#issuecomment-}
hrepo=${HANDOFF#https://github.com/}; hrepo=$(printf '%s' "$hrepo" | cut -d/ -f1-2)
printf '%s' "$cid" | grep -Eq '^[1-9][0-9]*$' || refused "the handoff link is not a comment link"
out=$(dc_with_deadline "$FETCH_SECS" "$GH" api "repos/$hrepo/issues/comments/$cid" 2>"$T/gh.err") \
    || refused "the handoff comment could not be read: $(tail -1 "$T/gh.err")"
printf '%s' "$out" | jq -e '(.body // "") | test("[^[:space:]]")' >/dev/null 2>&1 || refused "the handoff comment is gone or empty"
AG=$(agents) || refused "claude agents could not be read"
printf '%s' "$AG" | jq -e --arg j "$JOB" --arg p "$IPATH" --arg s "$SID" \
    '[.[] | select(.id == $j)] | length == 1 and .[0].cwd == $p and .[0].sessionId == $s and (.[0].state | IN("done", "stopped", "failed"))' >/dev/null 2>&1 \
    || refused "job $JOB is no longer the finished job of $IPATH with session $SID"
NL=$(niwa_list) || refused "niwa list could not be read"
printf '%s' "$NL" | jq -e --arg n "$INAME" --arg p "$IPATH" '[.[] | select(.name == $n or .path == $p)] | length == 1 and .[0].name == $n and .[0].path == $p' >/dev/null 2>&1 \
    || refused "niwa no longer lists $INAME at $IPATH"

STEP=inventory
say "re-inventorying $IPATH"
bash "$HERE/teardown-inventory.sh" --topic "$TOPIC" --instance "$IPATH" >"$T/inv" 2>&1
case $? in
    0) ;;
    1) refused "the instance holds unique material now: $(grep -m1 '^unique' "$T/inv")" ;;
    *) refused "the inventory reads an error: $(grep -m1 '^error' "$T/inv" || tail -1 "$T/inv")" ;;
esac

STEP=preserve
ARCH="$ARCHIVE_ROOT/$(date -u +%Y-%m-%d)-$TOPIC-$JOB"
# The archive holds transcripts, which hold whatever the worker saw: only
# the user reads it.
mkdir -p "$ARCH" && chmod 700 "$ARCHIVE_ROOT" "$ARCH" || { ARCH=""; refused "cannot create the archive directory"; }
say "preserving into $ARCH"
: >"$T/copies"
# copy_file <src> <rel>: one file into the archive, listed for the check.
copy_file() {
    mkdir -p "$ARCH/$(dirname "$2")" && cp -p "$1" "$ARCH/$2" || refused "cannot copy $1"
    printf '%s\t%s\n' "$2" "$1" >>"$T/copies"
}
# copy_tree <src dir> <rel dir>: every regular file under it.
copy_tree() {
    local f
    (cd "$1" && find . -type f) >"$T/tree" 2>/dev/null || refused "cannot list $1"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        copy_file "$1/${f#./}" "$2/${f#./}"
    done <"$T/tree"
}
[ -f "$TR" ] || refused "the transcript $TR is missing"
copy_file "$TR" "transcript/$SID.jsonl"
[ -d "$(dirname "$TR")/$SID" ] && copy_tree "$(dirname "$TR")/$SID" "transcript/$SID"
J="$CLAUDE_HOME/jobs/$JOB"
[ -f "$J/state.json" ] || refused "the job's state.json is missing"
copy_file "$J/state.json" job/state.json
[ -f "$J/timeline.jsonl" ] && copy_file "$J/timeline.jsonl" job/timeline.jsonl
[ -d "$J/tmp" ] && copy_tree "$J/tmp" job/tmp
JTMP=$(cd "$J/tmp" 2>/dev/null && pwd -P) || JTMP="$J/tmp"
NK=0
for d in "$KOTO_SESSIONS"/*/; do
    [ -d "$d" ] || continue
    for f in "$d"koto-*.state.jsonl; do
        [ -f "$f" ] || continue
        ed=$(head -1 "$f" | jq -r '.execution_dir // ""' 2>/dev/null) || ed=""
        case "$ed/" in
            "$IPATH"/* | "$JTMP"/* | "$J/tmp"/*)
                copy_tree "${d%/}" "koto/$(basename "$d")"
                NK=$((NK + 1))
                break ;;
        esac
    done
done
say "copied $(wc -l <"$T/copies" | tr -d ' ') files, $NK koto sessions"
: >"$ARCH/MANIFEST.new"
while IFS='	' read -r rel src; do
    h=$(sha256 <"$ARCH/$rel") || refused "cannot hash $rel"
    [ "$(sha256 <"$src")" = "$h" ] || refused "$rel doesn't match its source"
    printf '%s %s %s\n' "$h" "$(wc -c <"$ARCH/$rel" | tr -d ' ')" "$rel" >>"$ARCH/MANIFEST.new"
done <"$T/copies"
mv "$ARCH/MANIFEST.new" "$ARCH/MANIFEST"
{
    printf '# Teardown of %s\n\n' "$TOPIC"
    printf 'Taken %s by the coordinator'"'"'s teardown pass, before anything was removed.\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
    printf -- '- Instance: %s (%s)\n' "$INAME" "$IPATH"
    printf -- '- Claude Code job: %s, session %s\n' "$JOB" "$SID"
    printf '%s\n' "$PRS" | sed 's/^/- Merged pull request: /'
    printf -- '- Handoff: %s\n\n' "$HANDOFF"
    printf 'MANIFEST lists every copied file as `<sha256> <bytes> <path>`; each was checked against its source.\n'
} >"$ARCH/README.md"

STEP=destroy
say "destroying $INAME"
(cd "$ROOT" && "$NIWA" destroy --force "$INAME") >"$T/destroy" 2>&1 || incomplete "niwa destroy failed: $(tail -1 "$T/destroy")"
STEP=remove
say "removing job $JOB"
"$CLAUDE_CLI" rm "$JOB" >"$T/rm" 2>&1 || incomplete "claude rm failed: $(tail -1 "$T/rm")"
STEP=confirm
NL=$(niwa_list) || incomplete "niwa list could not be read"
printf '%s' "$NL" | jq -e --arg n "$INAME" --arg p "$IPATH" 'any(.[]; .name == $n or .path == $p) | not' >/dev/null 2>&1 \
    || incomplete "niwa still lists $INAME"
AG=$(agents) || incomplete "claude agents could not be read"
printf '%s' "$AG" | jq -e --arg j "$JOB" 'any(.[]; .id == $j) | not' >/dev/null 2>&1 || incomplete "claude agents still lists job $JOB"
printf 'done %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$ARCH/RESULT"
say "done $ARCH"
exit 0
