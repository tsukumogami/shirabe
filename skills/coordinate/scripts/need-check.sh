#!/usr/bin/env bash
# need-check.sh -- the check action of state surface_check: what a blocked
# worker needs from a person, in one of the closed need kinds, never a
# decision in free text.
#
# Usage: need-check.sh --session S
#
# Reads the `need` field of the latest evidence submitted at surface
# (coord-log.sh evidence), never an argument. A need is one of:
#   credential <name>                            a secret or login a person holds
#   reserved-step <merge|release|close|teardown> <link>
#                                                a step the workspace reserves for
#                                                a person, on a pull request or an
#                                                issue (a github.com link,
#                                                <owner>/<repo>#<n> or #<n>)
#   access <owner>/<repo>                        access to a repository
# It is refused when it is none of these, when its argument is anything but
# the one token the kind takes, or when its argument matches the decision
# phrasing list (phrasing-lib.sh): a choice goes to decision_raise, never into
# a need. An accepted need is worded for the progress table's cell and stored
# in the context key coord/need.json ({kind, argument, cell}) with coord-log.sh
# seal --file --key.
#
# Who a reserved merge, close or release goes to follows the coordinator's own
# grant, as posture-read.sh stored its `niwa authority check` answer in
# coord/posture.json (grant_check). A coordinator bound to its dispatch hands
# the step to the coordinator that dispatched it: the cell names that
# dispatcher's instance (grant_check.parent.instance, `<step> <link>, for
# dispatcher <instance>`), or `for the dispatcher` when the answer names no
# instance. Any other coordinator (not dispatched, no usable answer, no
# coord/posture.json) is a root coordinator, and the step is reserved for a
# person as before. A teardown is the workspace's, not the grant's, and stays
# reserved for a person.
#
# Verdicts (sealed to this visit): `accepted <kind> keyseal:<seq>:<sha256>`,
# or `refused`. Exit codes: 0 a verdict was printed; 2 a read failed; 64 usage.
set -uo pipefail

PROG=need-check
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO=${KOTO_BIN:-koto}
SESSION=
usage() { sed -n '/^# Usage:/,/^# Reads the/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$SESSION" ] || usage
. "$HERE/phrasing-lib.sh"
die2() { echo "$PROG: $*" >&2; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/need-check.XXXXXX") || die2 "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT
seal() { bash "$HERE/coord-log.sh" seal --session "$SESSION" --state surface_check --token "$1" || die2 "cannot seal the verdict"; exit 0; }
refuse() { echo "$PROG: refused: $*" >&2; seal refused; }

EV=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state surface)
case $? in 0) ;; 1) refuse "no evidence was submitted at surface" ;; *) die2 "cannot read the session log" ;; esac
NEED=$(printf '%s' "$EV" | jq -r '.fields.need // ""') || die2 "the surface evidence is not JSON"
case "$NEED" in *$'\n'*|*$'\r'*) refuse "a need is one line" ;; esac
set -f; set -- $NEED; set +f
KIND=${1-}
RE_NAME='^[A-Za-z0-9][A-Za-z0-9_.-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_DOTS='(^|/)\.\.?(/|$)'
RE_LINK='^(https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(pull|issues)/[1-9][0-9]*|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*|#[1-9][0-9]*)$'
case "$KIND" in
    credential)
        [ $# -eq 2 ] && [[ $2 =~ $RE_NAME ]] || refuse "credential takes one name"
        ARG=$2 CELL="credential: $2" ;;
    reserved-step)
        [ $# -eq 3 ] || refuse "reserved-step takes a step and a link"
        case "$2" in merge|release|close|teardown) ;; *) refuse "reserved-step is merge, release, close or teardown" ;; esac
        [[ $3 =~ $RE_LINK ]] || refuse "reserved-step names a pull request or an issue"
        ARG="$2 $3" CELL="$2 $3, reserved for a person"
        if [ "$2" != teardown ]; then
            # A missing or unreadable posture leaves koto's or jq's own
            # message on stderr and the step a person's, as before.
            GC=$("$KOTO" context get "$SESSION" coord/posture.json | jq -c '.grant_check | objects') || GC=""
            if [ "$(printf '%s' "$GC" | jq -r '.state // "" | strings')" = bound ]; then
                DISP=$(printf '%s' "$GC" | jq -r '(.parent | objects | .instance) // "" | strings') || DISP=""
                if [[ $DISP =~ ^[A-Za-z0-9][A-Za-z0-9+_.-]{0,127}$ ]]; then
                    CELL="$2 $3, for dispatcher $DISP"
                else
                    CELL="$2 $3, for the dispatcher"
                fi
            fi
        fi
        ;;
    access)
        [ $# -eq 2 ] && [[ $2 =~ $RE_REPO ]] && ! [[ $2 =~ $RE_DOTS ]] || refuse "access takes one owner/repo"
        ARG=$2 CELL="access to $2" ;;
    *) refuse "a need is credential, reserved-step or access; a decision goes to decision_raise" ;;
esac
# The argument is a token by now, but the list is the backstop behind that.
# Its patterns are phrases, so the token is read with its separators as
# spaces: `should-we-ship` is checked as `should we ship`.
phrase_match decision "$(printf '%s' "$ARG" | tr '_.-' '   ')"
case $? in 0) refuse "the need reads as a decision; raise it instead" ;; 1) ;; *) die2 "the phrasing list can't be read" ;; esac

jq -nc --arg k "$KIND" --arg a "$ARG" --arg c "$CELL" '{kind: $k, argument: $a, cell: $c}' > "$T/need.json" || die2 "cannot build the need"
KS=$(bash "$HERE/coord-log.sh" seal --session "$SESSION" --state surface_check --file "$T/need.json" --key coord/need.json) || die2 "cannot store the need"
[[ $KS =~ ^sealed:[0-9]+:[0-9a-f]{64}$ ]] || die2 "the need's seal is malformed"
seal "accepted $KIND keyseal:${KS#sealed:}"
