#!/usr/bin/env bash
# cloud-hosts-start_test.sh -- s3_start's wait for the fake S3 server, from
# testdata/cloud-hosts.sh, with stub servers in place of testdata/fake-s3.py.
#
# The engine suites start the real server through s3_start, which waits for it
# to write its port file. On a loaded host the server can take well over ten
# seconds to start, so the wait is a deadline in seconds, not a count of polls
# (shirabe#1817). These cases check that a slow server is waited for, that a
# server that exits fails at once with its log, that one that never writes its
# port fails at the deadline CLOUD_HOSTS_S3_WAIT sets, and that a deadline that
# isn't a whole number of seconds is refused before any server starts.
#
# No host is laid out and nothing else is run: each stub is a python3 file that
# s3_start launches through CLOUD_HOSTS_S3.
#
# Usage: bash skills/coordinate/scripts/cloud-hosts-start_test.sh
# Requires: bash 3.2+, python3.

HERE=$(cd "$(dirname "$0")" && pwd)

T=$(mktemp -d "${TMPDIR:-/tmp}/cloud-hosts-start-test.XXXXXX") || { echo "FAIL: no temporary directory"; exit 1; }
T=$(cd -P "$T" && pwd -P) || exit 1

. "$HERE/testdata/cloud-hosts.sh"
trap 's3_stop; rm -rf "$T"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL $1"
    shift
    while [ $# -gt 0 ]; do echo "       $1"; shift; done
}

mkdir -p "$T/stubs" || exit 1

# A server that writes its port file only after 12 seconds, through a
# temporary name and a rename as fake-s3.py does, then stays up.
cat > "$T/stubs/slow.py" <<'EOF'
import os, sys, time
time.sleep(12)
with open(sys.argv[2] + ".tmp", "w") as f:
    f.write("54321\n")
os.rename(sys.argv[2] + ".tmp", sys.argv[2])
time.sleep(3600)
EOF

# A server that fails at once, saying why on stderr.
cat > "$T/stubs/exits.py" <<'EOF'
import sys
sys.stderr.write("stub server: cannot bind\n")
sys.exit(3)
EOF

# A server that stays up and never writes its port file.
cat > "$T/stubs/never.py" <<'EOF'
import time
time.sleep(3600)
EOF

# start <stub> [<wait>]: run s3_start against a stub with CLOUD_HOSTS_S3_WAIT
# set to <wait> (unset when omitted), from a clean $T/s3. Sets RC, SECS (the
# whole seconds it took) and ERR (its stderr).
start() {
    s3_stop
    rm -rf "$T/s3"
    S3_ENDPOINT=
    local t0=$SECONDS
    if [ $# -ge 2 ]; then
        CLOUD_HOSTS_S3="$T/stubs/$1" CLOUD_HOSTS_S3_WAIT="$2" s3_start 2> "$T/err"
    else
        CLOUD_HOSTS_S3="$T/stubs/$1" s3_start 2> "$T/err"
    fi
    RC=$?
    SECS=$((SECONDS - t0))
    ERR=$(cat "$T/err")
}

echo "== a server that takes 12 s to write its port is waited for =="
start slow.py
if [ "$RC" = 0 ] && [ "$S3_ENDPOINT" = "http://127.0.0.1:54321" ]; then
    ok "s3_start returns 0 with the stub's endpoint"
else
    fail "s3_start returns 0 with the stub's endpoint" \
        "rc [$RC] after ${SECS}s, endpoint [$S3_ENDPOINT]" "stderr: $ERR"
fi

echo "== a server that exits fails at once, with its log =="
start exits.py
case "$RC:$ERR" in
    1:*"the fake S3 server exited"*"stub server: cannot bind"*) ok "s3_start returns 1 naming the exit and the server's log" ;;
    *) fail "s3_start returns 1 naming the exit and the server's log" "rc [$RC]" "stderr: $ERR" ;;
esac
if [ "$SECS" -lt 10 ]; then
    ok "  ... well inside the deadline (${SECS}s)"
else
    fail "  ... well inside the deadline" "took ${SECS}s"
fi

echo "== a server that never writes its port fails at the deadline =="
start never.py 2
case "$RC:$ERR" in
    1:*"the fake S3 server didn't start within 2s"*) ok "s3_start returns 1 naming the deadline" ;;
    *) fail "s3_start returns 1 naming the deadline" "rc [$RC]" "stderr: $ERR" ;;
esac
if [ "$SECS" -ge 1 ] && [ "$SECS" -le 5 ]; then
    ok "  ... after about CLOUD_HOSTS_S3_WAIT seconds (${SECS}s)"
else
    fail "  ... after about CLOUD_HOSTS_S3_WAIT seconds" "took ${SECS}s"
fi

echo "== a deadline that isn't a whole number of seconds is refused =="
for bad in abc 0 -1 2.5; do
    start never.py "$bad"
    case "$RC:$ERR:$S3_PID" in
        1:*"CLOUD_HOSTS_S3_WAIT"*:) ok "CLOUD_HOSTS_S3_WAIT=[$bad]: refused, no server started" ;;
        *) fail "CLOUD_HOSTS_S3_WAIT=[$bad]: refused, no server started" \
               "rc [$RC] after ${SECS}s, server pid [$S3_PID]" "stderr: $ERR" ;;
    esac
done

echo
echo "cloud-hosts-start: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
