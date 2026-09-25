#!/usr/bin/env bash
# deliver-requires_test.sh -- /deliver's koto floor, as preflight reports it.
#
# skills/deliver/requires.tsv declares the koto init flags the floor release
# added (--vars-file, --attach-live, --replace-terminal, --koto-leg) and the
# `koto request` subcommands /deliver calls. This runs the load-time
# preflight (scripts/skill-preflight.sh deliver) against a stand-in koto that
# answers `--help` the way a koto from before that release does -- no entry
# flags, no request verbs -- and asserts the report names what is missing
# before any work starts. It also asserts the declaration itself carries
# every flag and verb, and, when a real koto at the floor is installed, that
# preflight prints nothing.
#
# Usage: bash skills/deliver/scripts/deliver-requires_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
REQ="$REPO/skills/deliver/requires.tsv"
PREFLIGHT="$REPO/scripts/skill-preflight.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-requires-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

record() { # record <subcommand path> <flag...> -- the record declares each flag
    local sub="$1" line
    shift
    line=$(awk -F'\t' -v s="$sub" '$1 == "koto" && $2 == s { print $3 }' "$REQ")
    [ -n "$line" ] || { bad "requires.tsv declares koto $sub"; return; }
    local f missing=""
    for f in "$@"; do
        case ",$line," in *",$f,"*) ;; *) missing="$missing $f" ;; esac
    done
    if [ -z "$missing" ]; then ok "requires.tsv: koto $sub declares $*"; else bad "requires.tsv: koto $sub lacks$missing"; fi
}
record init --vars-file --attach-live --replace-terminal --koto-leg
record next --no-cleanup --with-data
record "request create" --with-data --requested-by --coordinator-of-record
record "request list" --coordinator-of-record --state
record "request abandon-request" --rationale
record "request resolve" --with-data
record "request get" -
record "request close" -

# The init flags must match what /scope and /execute declare, so the three
# skills name one floor.
for other in scope execute; do
    ours=$(awk -F'\t' '$1 == "koto" && $2 == "init" { print $3 }' "$REQ")
    theirs=$(awk -F'\t' '$1 == "koto" && $2 == "init" { print $3 }' "$REPO/skills/$other/requires.tsv")
    if [ "$ours" = "$theirs" ]; then ok "the koto init record matches /$other's"; else bad "the koto init record differs from /$other's" "[$ours] vs [$theirs]"; fi
done

# A koto from before the floor: `init --help` without the entry flags, and no
# `request` verbs at all.
mkdir -p "$T/bin"
cat >"$T/bin/koto" <<'OLD'
#!/usr/bin/env bash
case "$*" in
    "--help"|"help") printf 'Usage: koto <COMMAND>\n\nCommands:\n  init\n  next\n  status\n  session\n  context\n' ;;
    "init --help") printf 'Usage: koto init <NAME> --template <T>\n\nOptions:\n      --template <T>\n      --var <K=V>\n  -h, --help\n' ;;
    "next --help") printf 'Usage: koto next <NAME>\n\nOptions:\n      --with-data <D>\n      --no-cleanup\n' ;;
    "status --help"|"session --help"|"session cleanup --help"|"context --help"|"context add --help"|"context remove --help")
        printf 'Usage: koto %s\n' "$1" ;;
    "version"|"--version") printf 'koto 0.12.2\n' ;;
    *) printf "error: unrecognized subcommand '%s'\n" "$1" >&2; exit 2 ;;
esac
OLD
chmod +x "$T/bin/koto"

mkdir -p "$T/cwd"
# From a directory the stand-in does not live under: preflight never runs a
# binary that resolves inside the directory it was invoked from.
OUT=$(cd "$T/cwd" && PATH="$T/bin:$PATH" bash "$PREFLIGHT" deliver 2>&1)
case "$OUT" in
    *--koto-leg*) ok "preflight on an older koto names --koto-leg" ;;
    *) bad "preflight on an older koto names --koto-leg" "$OUT" ;;
esac
case "$OUT" in
    *--vars-file*) ok "preflight on an older koto names --vars-file" ;;
    *) bad "preflight on an older koto names --vars-file" "$OUT" ;;
esac
case "$OUT" in
    *request*) ok "preflight on an older koto names the missing request verbs" ;;
    *) bad "preflight on an older koto names the missing request verbs" "$OUT" ;;
esac

if command -v koto >/dev/null 2>&1 && koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    OUT=$(bash "$PREFLIGHT" deliver 2>&1)
    if [ -z "$OUT" ]; then ok "preflight on the installed floor koto prints nothing"; else bad "preflight on the installed floor koto prints nothing" "$OUT"; fi
else
    echo "SKIP: no koto at the floor installed -- the satisfied case did not run"
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
