#!/usr/bin/env bash
# predecessor-handoff.sh -- the check action of state predecessor_handoff:
# render the previous rotation's handoff from its record, as it stands.
#
# The predecessor is the pull request the run's latest RECORD_FIND capture
# names with the verdict `predecessor <n>` (sealed at the latest entry into
# record_find). Its title and body are read live; the body must be a canonical
# record for this discipline and the title a rotation title with real dates.
# The handoff is rendered with record-render.sh --format handoff and
# predecessor_copy {written: <the body's Written: time>}, which writes the
# "As written by the previous rotation at <time>; not re-checked." line over
# the predecessor's tables and the fixed sentence saying its reasoning was not
# recorded: a predecessor's reasoning is never written on its behalf. The
# header date is the title's end date, which a successor never changes.
#
# The file goes to a per-session path outside any repository,
# `$(koto session dir S)/predecessor-handoff.md`, and that path to context key
# coord/predecessor_handoff_path as data. rotation-close.sh --step handoff
# commits it unedited; closeout-read.sh --predecessor re-renders it the same
# way (through --out) to check what was committed.
#
# Verdict tokens: rendered <n> | unparseable <n> (the body isn't a canonical
# record for this discipline, the title isn't a rotation title, or the render
# refused it; a stop for the human).
#
# Usage:
#   predecessor-handoff.sh --session S
#   predecessor-handoff.sh [--session S] --scope discipline --name N --repo O/R
#                          --ref N [--out F] [--no-seal]          (tests, closeout-read.sh)
#
# --out writes the handoff to F instead of the session directory; with the
# override flags and no session it is required.
#
# Exit codes: 0 a verdict was printed; 2 a read failed, or the run has no
# `predecessor` find; 64 usage.
#
# GitHub reads: gh pr view <n> --repo R --json title,body,headRefOid
set -uo pipefail

PROG=predecessor-handoff
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= OUT=
NO_SEAL=0

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
        --no-seal) NO_SEAL=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/record-common.sh"
lib_facts
[ "$SCOPE" = discipline ] || { echo "$PROG: only a discipline has a predecessor" >&2; exit 64; }
if [ "$OVERRIDE" = 1 ]; then
    [ -n "$REF" ] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
    [ -n "$OUT$SESSION" ] || { echo "$PROG: --out or --session is needed for the file" >&2; exit 64; }
else
    [ -z "$REF$OUT" ] || { echo "$PROG: --ref and --out are only for the override flags" >&2; exit 64; }
    CAP=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name RECORD_FIND --state record_find 2>/dev/null)
    case $? in
        0) ;;
        1) lib_die2 "the run has no sealed record_find capture" ;;
        *) lib_die2 "cannot read the session log" ;;
    esac
    set -f; set -- $CAP; set +f
    [ "${1-}" = predecessor ] || lib_die2 "the latest find is not a predecessor verdict"
    REF=${2-}
fi
[[ $REF =~ $RE_NUM ]] || { echo "$PROG: the predecessor's number is not a number" >&2; exit 64; }
if [ -z "$OUT" ]; then
    SDIR=$("$KOTO" session dir "$SESSION") || lib_die2 "cannot find the session directory"
    [ -d "$SDIR" ] || lib_die2 "the session directory $SDIR does not exist"
    OUT="$SDIR/predecessor-handoff.md"
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/predecessor-handoff.XXXXXX")
trap 'rm -rf "$T"' EXIT

gh pr view "$REF" --repo "$REPO" --json title,body,headRefOid > "$T/pr.json" 2> "$T/pr.err" < /dev/null \
    || lib_die2 "cannot read pull request #$REF: $(lib_scrub < "$T/pr.err")"
jq -r '.body // ""' "$T/pr.json" > "$T/body.md" || lib_die2 "jq failed"
TITLE=$(jq -r '.title // ""' "$T/pr.json")

unparseable() {
    echo "$PROG: #$REF: $1" >&2
    lib_emit predecessor_handoff "unparseable $REF" "" ""
}

lib_parse "$T/body.md" "$T/parsed.json"
case $? in
    0) ;;
    3|65) unparseable "not a canonical record for $NAME: $(lib_scrub < "$T/parsed.json.err" | head -1)" ;;
    *) lib_die2 "record-parse.sh failed" ;;
esac
lib_rotation_dates "$TITLE" || unparseable "the title is not a rotation title with real dates"

jq -c --arg s "$ROT_START" --arg e "$ROT_END" --arg r "$REPO" --arg u "https://github.com/$REPO/pull/$REF" '
    {scope, rotation: {start: $s, end: $e, date: $e, host_repo: $r, record_url: $u},
     holdings, deferrals, side_effects, reversals, predecessor_copy: {written: .written}}' \
    "$T/parsed.json" > "$T/handoff.json" || lib_die2 "jq failed"
bash "$HERE/record-render.sh" --format handoff "$T/handoff.json" > "$T/handoff.md" 2> "$T/render.err" \
    || unparseable "the handoff render refused it: $(lib_scrub < "$T/render.err" | head -1)"
cp "$T/handoff.md" "$OUT" 2> /dev/null || lib_die2 "cannot write $OUT"
printf '%s' "$OUT" > "$T/path"
lib_emit predecessor_handoff "rendered $REF" coord/predecessor_handoff_path "$T/path"
