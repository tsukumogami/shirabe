#!/usr/bin/env bash
# cloud-hosts_engine_test.sh -- testdata/cloud-hosts.sh, the fixture the cloud
# engine suites share, against real koto and the fake S3 server
# (testdata/fake-s3.py). koto 0.34.0 applies a workspace's .koto/config.toml
# only once `koto config trust` has granted it (shirabe#1510), so the fixture
# trusts each workspace config it writes, inside the host's own HOME; its
# fail-closed check, ws_check, must still stop any workspace that resolves
# something other than the fake server.
#
# Proves, one line per case:
#   1. host_make lays out a host whose workspace resolves the fake server's
#      backend, endpoint and bucket, and ws_check passes it;
#   2. on koto 0.34.0 and later the grant is in that host's own
#      userhome/.koto/trust.toml, and none is written under the suite's HOME
#      or under a KOTO_HOME the suite's shell sets;
#   3. a trusted workspace config naming another bucket stops ws_check, exit 1
#      and the guard line;
#   4. one naming another endpoint stops it the same way;
#   5. one naming the local backend stops it the same way;
#   6. on koto 0.34.0 and later, the fixture's own config once untrusted stops
#      it the same way (an older koto applies the file untrusted, so the case
#      is not run there).
#
# Needs koto and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/cloud-hosts_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
for bin in koto python3; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
T=$(mktemp -d "${TMPDIR:-/tmp}/cloud-hosts-test.XXXXXX") || { echo "FAIL: no temporary directory"; exit 1; }
T=$(cd -P "$T" && pwd -P) || exit 1
export HOME="$T/home"
# A KOTO_HOME in the shell running the suite would move koto's root, and with
# it the trust grants, out of the host; ws_on must clear it.
export KOTO_HOME="$T/shell-koto-home"
mkdir -p "$HOME" "$KOTO_HOME"
. "$HERE/testdata/cloud-hosts.sh"
ktg_on_exit 's3_stop; rm -rf "$T"'

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

GUARD="doesn't resolve the fake S3 server; stopping before koto writes a session"

# expect_stopped <case> <label> <ws>: ws_check exits 1 with the guard line.
expect_stopped() {
    local out rc
    out=$(ws_check "$2" "$3" 2>&1)
    rc=$?
    if [ "$rc" = 1 ] && grep -qF "$GUARD" <<< "$out"; then
        pass "$1"
    else
        fail "$1 (exit $rc): $out"
    fi
}

s3_start || { echo "FAIL: the fake S3 server didn't start"; exit 1; }

# --- 1. a host's workspace resolves the fake server ---------------------------
host_make a
got="$(host_on a koto config get session.backend 2>&1) $(host_on a koto config get session.cloud.endpoint 2>&1) $(host_on a koto config get session.cloud.bucket 2>&1)"
if [ "$got" = "cloud $S3_ENDPOINT $S3_BUCKET" ] && (ws_check a work); then
    pass "host_make: workspace work on host a resolves the fake server and ws_check passes it"
else
    fail "host_make: workspace work on host a resolves [$got], want [cloud $S3_ENDPOINT $S3_BUCKET]"
fi

# --- 2. the grant stays in the host's own HOME ---------------------------------
if koto_trusts_config; then
    if [ -s "$T/hosts/a/userhome/.koto/trust.toml" ] && [ ! -e "$HOME/.koto/trust.toml" ] && [ ! -e "$KOTO_HOME/trust.toml" ]; then
        pass "trust: the grant is in host a's userhome only"
    else
        fail "trust: want a grant in host a's userhome only; found: $(cd "$T" && find . -name trust.toml | tr '\n' ' ')"
    fi
else
    pass "trust: koto $(koto version | head -n 1) applies project config untrusted; no grant to place"
fi

# --- 3-5. a trusted config naming anything else is stopped ---------------------
ws_mkdir() { mkdir -p "$T/hosts/$1/$2/.koto"; }
ws_mkdir a other-bucket
ws_config a other-bucket cloud "$S3_ENDPOINT" not-the-fake-bucket
expect_stopped "guard: a trusted config naming another bucket is stopped" a other-bucket

ws_mkdir a other-endpoint
ws_config a other-endpoint cloud "http://127.0.0.1:1" "$S3_BUCKET"
expect_stopped "guard: a trusted config naming another endpoint is stopped" a other-endpoint

ws_mkdir a local-backend
ws_config a local-backend local "$S3_ENDPOINT" "$S3_BUCKET"
expect_stopped "guard: a trusted config naming the local backend is stopped" a local-backend

# --- 6. an untrusted config is stopped -----------------------------------------
if koto_trusts_config; then
    host_on a koto config untrust > /dev/null 2>&1
    expect_stopped "guard: the fixture's config, untrusted, is stopped" a work
else
    pass "guard: koto $(koto version | head -n 1) has no trust gate; the untrusted case does not apply"
fi

echo
echo "cloud-hosts_engine_test: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
