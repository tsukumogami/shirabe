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
# Verdicts (sealed to this visit): `accepted <kind> keyseal:<seq>:<sha256>`,
# or `refused`. Exit codes: 0 a verdict was printed; 2 a read failed; 64 usage.
set -uo pipefail

PROG=need-check
HERE=$(cd "$(dirname "$0")" && pwd)
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
T=$(mktemp -d "${TMPDIR:-/tmp}/need-check.XXXXXX")
trap 'rm -rf "$T"' EXIT
die2() { echo "$PROG: $*" >&2; exit 2; }
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
RE_LINK='^(https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(pull|issues)/[1-9][0-9]*|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*|#[1-9][0-9]*)$'
case "$KIND" in
    credential)
        [ $# -eq 2 ] && [[ $2 =~ $RE_NAME ]] || refuse "credential takes one name"
        ARG=$2 CELL="credential: $2" ;;
    reserved-step)
        [ $# -eq 3 ] || refuse "reserved-step takes a step and a link"
        case "$2" in merge|release|close|teardown) ;; *) refuse "reserved-step is merge, release, close or teardown" ;; esac
        [[ $3 =~ $RE_LINK ]] || refuse "reserved-step names a pull request or an issue"
        ARG="$2 $3" CELL="$2 $3, reserved for a person" ;;
    access)
        [ $# -eq 2 ] && [[ $2 =~ $RE_REPO ]] || refuse "access takes one owner/repo"
        ARG=$2 CELL="access to $2" ;;
    *) refuse "a need is credential, reserved-step or access; a decision goes to decision_raise" ;;
esac
# The argument is a token by now, but the list is the backstop behind that.
phrase_match decision "$ARG"
case $? in 0) refuse "the need reads as a decision; raise it instead" ;; 1) ;; *) die2 "the phrasing list can't be read" ;; esac

jq -nc --arg k "$KIND" --arg a "$ARG" --arg c "$CELL" '{kind: $k, argument: $a, cell: $c}' > "$T/need.json" || die2 "cannot build the need"
KS=$(bash "$HERE/coord-log.sh" seal --session "$SESSION" --state surface_check --file "$T/need.json" --key coord/need.json) || die2 "cannot store the need"
[[ $KS =~ ^sealed:[0-9]+:[0-9a-f]{64}$ ]] || die2 "the need's seal is malformed"
seal "accepted $KIND keyseal:${KS#sealed:}"
