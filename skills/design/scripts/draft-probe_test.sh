#!/usr/bin/env bash
# draft-probe_test.sh -- the Phase 0 validator probe, draft-probe.sh.
#
# Stub cases put a stand-in `shirabe` first on PATH that exits with a chosen
# status, so they run anywhere, the bash 3.2 floor included: the probe's exit
# code and message for a validator that accepts a Draft design, one that
# refuses it, one that can't run, and no validator at all; and that a probe
# run leaves the calling work tree clean and its temporary directory gone.
#
# One real case runs the probe against the `shirabe` on PATH. Without one it
# SKIPs with a notice; with DESIGN_REQUIRE_SHIRABE=1 (the Linux job that
# builds it) a missing validator, or one that refuses a Draft design, is a
# failure, so CI can't report green having asserted nothing.
#
# Usage: draft-probe_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
PROBE="$SCRIPT_DIR/draft-probe.sh"
NEED=v0.47.0

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
show() {
    printf '  %s:\n' "$1"
    if [ -s "$2" ]; then sed 's/^/    /' "$2"; else echo "    (empty)"; fi
}

for tool in git mktemp; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -f "$PROBE" ] || { echo "$PROBE is missing" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/draft-probe-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */draft-probe-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

REAL_PATH=$PATH
OUT="$WORKDIR/out"
ERR="$WORKDIR/err"
CALLS="$WORKDIR/calls"
RC=0

# A PATH with the tools the probe runs but no shirabe: each tool linked by
# name into its own directory.
BARE="$WORKDIR/bare-bin"
mkdir -p "$BARE"
for tool in bash mktemp cat rm; do
    p=$(command -v "$tool") || { echo "$tool is required to run this suite" >&2; exit 2; }
    ln -s "$p" "$BARE/$tool"
done

# The stand-in validator: records the path it was given and whether that file
# existed, then exits with $STUB_RC.
STUB="$WORKDIR/stub-bin"
mkdir -p "$STUB"
printf '%s\n' \
    '#!/bin/sh' \
    'last=' \
    'for a in "$@"; do last=$a; done' \
    'if [ -f "$last" ]; then state=present; else state=missing; fi' \
    'printf "%s %s %s\n" "$1" "$last" "$state" >> "$STUB_CALLS"' \
    'exit "${STUB_RC:-0}"' > "$STUB/shirabe"
chmod 0755 "$STUB/shirabe"

# A git work tree to call the probe from, with one commit so status is clean.
CALLER="$WORKDIR/caller"
mkdir -p "$CALLER"
git -C "$CALLER" init -q
printf 'x\n' > "$CALLER/README.md"
git -C "$CALLER" add README.md
git -C "$CALLER" -c user.name=t -c user.email=t@example.com commit -qm init

# The probe's own temporary directories land here, so a leftover is visible.
PROBE_TMP="$WORKDIR/probe-tmp"
mkdir -p "$PROBE_TMP"

# run_stub <rc>: the probe with the stand-in validator exiting <rc>.
run_stub() {
    : > "$CALLS"
    (cd "$CALLER" && STUB_RC=$1 STUB_CALLS="$CALLS" TMPDIR="$PROBE_TMP" PATH="$STUB:$BARE" \
        bash "$PROBE") > "$OUT" 2> "$ERR"
    RC=$?
}

# --- stub cases --------------------------------------------------------------------

label="probe: a shirabe that accepts Draft exits 0 and prints draft-probe: ok"
run_stub 0
if [ "$RC" -eq 0 ] && grep -qx 'draft-probe: ok' "$OUT" && grep -q '^validate .* present$' "$CALLS"; then
    pass "$label"
else
    fail "$label (exit $RC)"
    show stdout "$OUT"; show stderr "$ERR"; show "validator calls" "$CALLS"
fi

label="probe: a shirabe that refuses Draft exits 1 and names $NEED"
run_stub 2
if [ "$RC" -eq 1 ] && grep -qF "shirabe $NEED or later" "$ERR" && [ ! -s "$OUT" ]; then
    pass "$label"
else
    fail "$label (exit $RC)"
    show stdout "$OUT"; show stderr "$ERR"
fi

label="probe: a shirabe that cannot run (exit 1) exits 2"
run_stub 1
if [ "$RC" -eq 2 ] && grep -qF 'could not run the probe' "$ERR"; then
    pass "$label"
else
    fail "$label (exit $RC)"
    show stdout "$OUT"; show stderr "$ERR"
fi

label="probe: no shirabe on PATH exits 1 and names $NEED"
: > "$CALLS"
(cd "$CALLER" && TMPDIR="$PROBE_TMP" PATH="$BARE" bash "$PROBE") > "$OUT" 2> "$ERR"
RC=$?
if [ "$RC" -eq 1 ] && grep -qF "shirabe $NEED or later" "$ERR" && grep -qF 'no shirabe on PATH' "$ERR"; then
    pass "$label"
else
    fail "$label (exit $RC)"
    show stdout "$OUT"; show stderr "$ERR"
fi

label="probe: git status --porcelain in the calling work tree is empty afterwards, and its temp directory is gone"
run_stub 0
given=""
if [ -s "$CALLS" ]; then
    read -r _ given _ < "$CALLS"
fi
git -C "$CALLER" status --porcelain > "$WORKDIR/status" 2>&1
leftover=$(cd "$PROBE_TMP" && ls -A)
case "$given" in
    "$PROBE_TMP"/design-draft-probe.*/DESIGN-draft-probe.md) under_tmp=1 ;;
    *) under_tmp=0 ;;
esac
if [ "$RC" -eq 0 ] && [ "$under_tmp" -eq 1 ] && [ ! -e "$given" ] && [ ! -e "${given%/*}" ] \
    && [ ! -s "$WORKDIR/status" ] && [ -z "$leftover" ]; then
    pass "$label"
else
    fail "$label (exit $RC, validator given '$given', left in TMPDIR: '$leftover')"
    show "git status --porcelain" "$WORKDIR/status"
    show stderr "$ERR"
fi

# --- real case ---------------------------------------------------------------------

label="probe: the real shirabe on PATH accepts the probe document"
if ! PATH="$REAL_PATH" command -v shirabe >/dev/null 2>&1; then
    if [ "${DESIGN_REQUIRE_SHIRABE:-}" = 1 ]; then
        fail "$label: no shirabe on PATH, and DESIGN_REQUIRE_SHIRABE=1"
    else
        echo "SKIP: shirabe not on PATH -- the real-validator case did not run"
    fi
else
    (cd "$CALLER" && PATH="$REAL_PATH" bash "$PROBE") > "$OUT" 2> "$ERR"
    RC=$?
    if [ "$RC" -eq 0 ] && grep -qx 'draft-probe: ok' "$OUT"; then
        pass "$label"
    elif [ "$RC" -eq 1 ] && [ "${DESIGN_REQUIRE_SHIRABE:-}" != 1 ]; then
        echo "SKIP: the shirabe on PATH refuses a design at status Draft -- the real-validator case did not run"
    else
        fail "$label (exit $RC)"
        show stdout "$OUT"; show stderr "$ERR"
    fi
fi

echo
echo "draft-probe_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
