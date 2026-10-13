# cloud-hosts.sh -- simulated hosts sharing koto's cloud session backend, for
# /coordinate's engine suites. Sourced by a suite after it sets HERE (the
# scripts directory) and T (its scratch directory). Not shipped behaviour.
#
# One fake S3 server (testdata/fake-s3.py, python3) plays the bucket. Each host
# is a directory under $T/hosts/<label> with its own HOME, cache and workspace,
# as koto's own migration tests lay hosts out: the workspace's
# .koto/config.toml points the session backend at the bucket, and the host's
# user config ($HOME/.koto/config.toml) holds test-only credentials, the one
# place koto reads them from besides the environment. Every command runs with
# the AWS_* variables and CLAUDE_CODE_SESSION_ID removed, so neither a real
# credential nor this session's identity reaches koto, and with
# XDG_CONFIG_HOME and KOTO_SESSIONS_BASE removed, so each host reads only its
# own configuration.
#
#   s3_start            start the server; sets S3_ENDPOINT and S3_PID
#   s3_stop             stop it (only the server this suite started)
#   host_make <label>   lay a host out; prints nothing
#   host_ws <label>     the host's workspace, canonical (the path --from takes)
#   host_on <label> <command...>
#                       run a command in the host's workspace, as that host
#
# Requires: bash 3.2+, python3.

S3_BUCKET=coordinate-test
S3_ENDPOINT=
S3_PID=

s3_start() {
    local i port
    mkdir -p "$T/s3"
    python3 -I "$HERE/testdata/fake-s3.py" "$S3_BUCKET" "$T/s3/port" > "$T/s3/log" 2>&1 &
    S3_PID=$!
    i=0
    while [ ! -s "$T/s3/port" ]; do
        i=$((i + 1))
        [ "$i" -le 100 ] || { echo "cloud-hosts: the fake S3 server didn't start: $(cat "$T/s3/log")" >&2; return 1; }
        kill -0 "$S3_PID" 2>/dev/null || { echo "cloud-hosts: the fake S3 server exited: $(cat "$T/s3/log")" >&2; return 1; }
        sleep 0.1
    done
    port=$(cat "$T/s3/port")
    case "$port" in ''|*[!0-9]*) echo "cloud-hosts: bad port [$port]" >&2; return 1 ;; esac
    S3_ENDPOINT="http://127.0.0.1:$port"
}

s3_stop() {
    [ -n "$S3_PID" ] || return 0
    kill "$S3_PID" 2>/dev/null
    wait "$S3_PID" 2>/dev/null
    S3_PID=
}

host_make() {
    local b="$T/hosts/$1"
    mkdir -p "$b/home/.koto" "$b/cache" "$b/work/.koto"
    printf '[session]\nbackend = "cloud"\n\n[session.cloud]\nendpoint = "%s"\nbucket = "%s"\nregion = "us-east-1"\npath_style = true\n' \
        "$S3_ENDPOINT" "$S3_BUCKET" > "$b/work/.koto/config.toml"
    # Test-only credentials the fake server ignores; never a real one.
    printf '[session.cloud]\naccess_key = "test-access"\nsecret_key = "test-secret"\n' > "$b/home/.koto/config.toml"
}

host_ws() { (cd "$T/hosts/$1/work" && pwd -P); }

host_on() {
    local b
    b=$(cd "$T/hosts/$1" && pwd -P) || return 1
    shift
    (cd "$b/work" && env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_PROFILE \
        -u CLAUDE_CODE_SESSION_ID -u XDG_CONFIG_HOME -u KOTO_SESSIONS_BASE \
        HOME="$b/home" XDG_CACHE_HOME="$b/cache" "$@")
}
