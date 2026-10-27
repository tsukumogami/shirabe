#!/usr/bin/env bash
# release-grant_test.sh -- test harness for release-grant.sh, /release's read
# of its own session's cut-release grant.
#
# Usage: bash skills/release/scripts/release-grant_test.sh
#        /bin/bash skills/release/scripts/release-grant_test.sh   # bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# Every case runs the script from a throwaway git repository inside a
# throwaway niwa instance root, against a stub niwa that logs each call and
# answers by STUB_MODE. PATH holds only a private directory of links to the
# tools the script and the stub use (no niwa, no koto), so nothing here runs
# the host's niwa or reads its instances. The sleeping stub runs once with
# `timeout` and once without it where the host has one, so both bounds run.
#
# Everything the suite creates lives under one mktemp -d directory, removed on
# exit.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd -P)
RG="$SCRIPT_DIR/release-grant.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { printf "${GREEN}PASS${NC}: %s\n" "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf "${RED}FAIL${NC}: %s\n" "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$RG" ] || { echo "FAIL: release-grant.sh not found at $RG" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/release-grant-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */release-grant-test.*) rm -rf "$T" ;; esac; return 0; }
trap cleanup EXIT

# Built at run time: a committed id-shaped literal reads as a real session id.
uuid() { printf "%s-%s-%s-%s-%s" "$@"; }
ID=$(uuid 3c803591 4c01 486f a927 f96ec399d6a7)
export GRANT_ID="$ID"
SID=$(uuid 0f1e2d3c 4b5a 4968 8776 a5b4c3d2e1f0)

# --- the tools on PATH ------------------------------------------------------------------

# tools/ holds links to what the script and the stub run; nothing else is on
# PATH. notimeout/ is the same without `timeout`.
mkdir -p "$T/tools" "$T/notimeout"
for tool in bash jq mktemp rm readlink sleep cat printf dirname sed tr; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    case "$p" in /*) ;; *) continue ;; esac
    ln -s "$p" "$T/tools/$tool"
    ln -s "$p" "$T/notimeout/$tool"
done
HOST_TIMEOUT=$(command -v timeout 2>/dev/null) || HOST_TIMEOUT=""
[ -n "$HOST_TIMEOUT" ] && ln -s "$HOST_TIMEOUT" "$T/tools/timeout"

# --- the stub niwa ----------------------------------------------------------------------

STUB_LOG="$T/niwa.log"
mkdir -p "$T/stubbin"
cat >"$T/stubbin/niwa" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
id=$GRANT_ID
doc() { # doc <grant authorities json> <decider> <author exclusion> [<dispatch id>]
    printf '{"schema":"niwa.authority.check/v1","state":"bound","binding":"mapping","dispatch_id":"%s","grant":%s,"level":"autonomous","points":[{"point":"cut-release","decider":"%s","author_exclusion":"%s"}]}\n' \
        "${4:-$id}" "$1" "$2" "$3"
}
held='[{"authority":"cut-release","sources":["role:coordinator"]}]'
case "$STUB_MODE" in
    holder) doc "$held" session off ;;
    not-held) doc '[{"authority":"merge-pr","sources":["dispatch"]},{"authority":"close-issue","sources":["dispatch"]}]' session off ;;
    decider-person) doc "$held" person off ;;
    decider-dispatcher) doc "$held" dispatcher off ;;
    author-exclusion) doc "$held" session on ;;
    record-unusable) printf '{"schema":"niwa.authority.check/v1","state":"record-unusable","reason":"x","dispatch_id":"%s","grant":[]}\n' "$id" ;;
    not-dispatched) printf '{"schema":"niwa.authority.check/v1","state":"not-dispatched","reason":"x","grant":[]}\n' ;;
    id-not-uuid) doc "$held" session off not-a-uuid ;;
    id-upper) doc "$held" session off "$(printf %s "$id" | tr a-f A-F)" ;;
    no-id) printf '{"schema":"niwa.authority.check/v1","state":"bound","grant":%s,"level":"autonomous","points":[{"point":"cut-release","decider":"session","author_exclusion":"off"}]}\n' "$held" ;;
    wrong-schema) doc "$held" session off | sed 's/check\/v1/check\/v2/' ;;
    two-docs) doc "$held" session off; doc "$held" session off ;;
    nothing) : ;;
    not-json) echo "go=grant dispatch=$id" ;;
    bad-state) printf '{"schema":"niwa.authority.check/v1","state":"bound-ish","grant":[]}\n' ;;
    bad-level) doc "$held" session off | sed 's/autonomous/reckless/' ;;
    bad-authority) doc '[{"authority":"cut-release"},{"authority":"deploy"}]' session off ;;
    no-point) doc "$held" session off | sed 's/"cut-release","decider"/"merge-pr","decider"/' ;;
    two-points) doc "$held" session off | sed 's/}]}$/},{"point":"cut-release","decider":"person","author_exclusion":"off"}]}/' ;;
    id-newline) doc "$held" session off "$id\\n" ;;
    exit-1) doc "$held" session off; exit 1 ;;
    no-check) [ "${2:-}" = check ] && { echo "unknown command \"check\" for \"niwa authority\"" >&2; exit 2; }; doc "$held" session off ;;
    sleep) sleep 30; doc "$held" session off ;;
    *) echo "stub: unknown STUB_MODE $STUB_MODE" >&2; exit 3 ;;
esac
STUB
chmod +x "$T/stubbin/niwa"

# --- the fixture: an instance root holding a repository ---------------------------------

g() { git -C "$1" -c user.name=t -c user.email=t@example.invalid "${@:2}"; }

INST="$T/inst"
REPO="$INST/repo"
mkdir -p "$INST/.niwa" "$REPO"
echo '{}' >"$INST/.niwa/instance.json"
g "$REPO" init -q
g "$REPO" commit -q --allow-empty -m init

# A repository with no instance root at or above it.
OUTSIDE="$T/outside/repo"
mkdir -p "$OUTSIDE"
g "$OUTSIDE" init -q
g "$OUTSIDE" commit -q --allow-empty -m init

# A niwa inside the repository's working tree, and a link outside it that
# points there.
mkdir -p "$REPO/bin" "$T/linkbin"
cp "$T/stubbin/niwa" "$REPO/bin/niwa"
ln -s "$REPO/bin/niwa" "$T/linkbin/niwa"

# A jq and a timeout planted inside the working tree, each forging a holder's
# answer: the jq prints the grant line itself, the timeout prints a holder's
# document in place of running niwa.
mkdir -p "$REPO/tools"
cat >"$REPO/tools/jq" <<'FAKE'
#!/bin/sh
echo "go=grant dispatch=$GRANT_ID"
FAKE
cat >"$REPO/tools/timeout" <<'FAKE'
#!/bin/sh
STUB_MODE=holder exec "$4" "$@"
FAKE
chmod +x "$REPO/tools/jq" "$REPO/tools/timeout"

# --- the runner -------------------------------------------------------------------------

OUT=""
ELAPSED=0
# grant <dir> <path> <mode> [session id] [NIWA_BIN]: run the script from <dir>
# with PATH=<path>; sets OUT (stdout) and ELAPSED (seconds). A session id of
# "-" leaves CLAUDE_CODE_SESSION_ID unset.
grant() {
    local dir="$1" path="$2" mode="$3" sid="${4-$SID}" nb="${5:-}" start rc
    : >"$STUB_LOG"
    start=$SECONDS
    OUT=$(
        cd "$dir" || exit 99
        unset NIWA_BIN NIWA_LOOKUP_SECONDS CLAUDE_CODE_SESSION_ID
        [ "$sid" = - ] || export CLAUDE_CODE_SESSION_ID="$sid"
        [ -z "$nb" ] || export NIWA_BIN="$nb"
        export STUB_MODE="$mode" STUB_LOG TMPDIR="$T"
        PATH="$path" "$BASH_BIN" "$RG"
    )
    rc=$?
    ELAPSED=$((SECONDS - start))
    [ "$rc" -eq 0 ] || OUT="exit=$rc $OUT"
}

calls() { grep -c . "$STUB_LOG" 2>/dev/null || true; }

expect() { # expect <label> <wanted line>
    if [ "$OUT" = "$2" ]; then pass "$1: $2"; else fail "$1: wanted '$2', got '$OUT'"; fi
}

WITH="$T/stubbin:$T/tools"

# --- cases ------------------------------------------------------------------------------

echo "--- holder ---"
grant "$REPO" "$WITH" holder
expect "holder" "go=grant dispatch=$ID"
if [ "$(cat "$STUB_LOG")" = "authority check --json --session $SID -C $INST --point cut-release" ] && [ "$(calls)" = 1 ]; then
    pass "holder: one check call, for this session, at the instance root, for cut-release"
else
    fail "holder: wanted one check call, log: $(cat "$STUB_LOG")"
fi

grant "$REPO/bin" "$T/tools" holder "$SID" "$T/stubbin/niwa"
expect "holder through an absolute NIWA_BIN, from a subdirectory" "go=grant dispatch=$ID"

grant "$REPO" "$T/notimeout" holder "$SID" "$T/stubbin/niwa"
expect "holder without timeout on PATH" "go=grant dispatch=$ID"

echo "--- answers that aren't a holder's ---"
for mode in not-held decider-person decider-dispatcher author-exclusion record-unusable not-dispatched; do
    grant "$REPO" "$WITH" "$mode"
    expect "$mode" "go=person reason=$mode"
done

echo "--- answers nobody can read ---"
for mode in id-not-uuid id-upper id-newline no-id wrong-schema two-docs nothing not-json bad-state bad-level bad-authority no-point two-points; do
    grant "$REPO" "$WITH" "$mode"
    expect "$mode" "go=person reason=unreadable-answer"
done

echo "--- lookups that fail ---"
for mode in exit-1 no-check; do
    grant "$REPO" "$WITH" "$mode"
    expect "$mode" "go=person reason=lookup-failed"
done

grant "$REPO" "$WITH" sleep
expect "sleeping 30 seconds" "go=person reason=lookup-failed"
if [ "$ELAPSED" -le 4 ]; then pass "sleeping 30 seconds: returned in ${ELAPSED}s"; else fail "sleeping 30 seconds: took ${ELAPSED}s"; fi
if [ -n "$HOST_TIMEOUT" ]; then
    grant "$REPO" "$T/notimeout" sleep "$SID" "$T/stubbin/niwa"
    expect "sleeping 30 seconds, no timeout on PATH" "go=person reason=lookup-failed"
    if [ "$ELAPSED" -le 4 ]; then pass "sleeping, no timeout: returned in ${ELAPSED}s"; else fail "sleeping, no timeout: took ${ELAPSED}s"; fi
fi

echo "--- no lookup made ---"
grant "$REPO" "$T/tools" holder
expect "no niwa on PATH or in NIWA_BIN" "go=person reason=no-niwa"
grant "$REPO" "$T/tools" holder "$SID" stubbin/niwa
expect "a relative NIWA_BIN" "go=person reason=no-niwa"
grant "$REPO" "$REPO/bin:$T/tools" holder
expect "the only niwa under the working tree" "go=person reason=no-niwa"
grant "$REPO" "$T/tools" holder "$SID" "$REPO/bin/niwa"
expect "NIWA_BIN under the working tree" "go=person reason=no-niwa"
grant "$REPO" "$T/linkbin:$T/tools" holder
expect "a link outside the tree to a niwa inside it" "go=person reason=no-niwa"
grant "$REPO" "$REPO/bin:$T/tools" holder "$SID" "$T/stubbin/niwa"
expect "PATH's niwa under the tree, NIWA_BIN outside it" "go=grant dispatch=$ID"

echo "--- nothing from the working tree runs ---"
grant "$REPO" "$REPO/tools:$WITH" not-held
expect "a jq and a timeout inside the tree, ahead on PATH, are passed over" "go=person reason=not-held"
grant "$REPO" "tools:$WITH" not-held
expect "a relative PATH entry is passed over" "go=person reason=not-held"
grant "$REPO/bin" "$REPO/tools:$WITH" not-held
expect "the same from a subdirectory of the tree" "go=person reason=not-held"

grant "$REPO" "$WITH" holder -
expect "CLAUDE_CODE_SESSION_ID unset" "go=person reason=no-session-id"
if [ "$(calls)" = 0 ]; then pass "no session id: niwa not called"; else fail "no session id: niwa called: $(cat "$STUB_LOG")"; fi
grant "$REPO" "$WITH" holder ""
expect "CLAUDE_CODE_SESSION_ID empty" "go=person reason=no-session-id"

grant "$OUTSIDE" "$WITH" holder
expect "no .niwa/instance.json at or above the repository" "go=person reason=no-instance-root"
if [ "$(calls)" = 0 ]; then pass "no instance root: niwa not called"; else fail "no instance root: niwa called: $(cat "$STUB_LOG")"; fi

echo "--- needs no koto ---"
if PATH="$WITH" command -v koto >/dev/null 2>&1; then
    fail "koto is reachable on the test PATH"
else
    pass "every case ran with no koto on PATH"
fi

echo "--- no temporary file left ---"
if ls "$T"/release-grant.* >/dev/null 2>&1; then
    fail "a release-grant.* temporary file was left in TMPDIR"
else
    pass "no release-grant.* temporary file left in TMPDIR"
fi

echo
echo "release-grant.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
