# cloud-hosts.sh -- simulated hosts sharing koto's cloud session backend, for
# /coordinate's engine suites and the move suites of /execute and /deliver.
# Sourced by a suite after it sets HERE (a scripts directory holding
# testdata/fake-s3.py, or CLOUD_HOSTS_S3 naming that server) and T (its
# scratch directory). Not shipped behaviour.
#
# One fake S3 server (testdata/fake-s3.py, python3) plays the bucket. Each host
# is a directory under $T/hosts/<label> with its own HOME, cache and workspace,
# as koto's own migration tests lay hosts out: the workspace's
# .koto/config.toml points the session backend at the bucket, and the host's
# user config ($HOME/.koto/config.toml) holds test-only credentials, the one
# place koto reads them from besides the environment. The user config also
# sets session.cloud.check_window_secs to 0, as koto's own migration tests do:
# by default a read reuses another koto process's check of the bucket on the
# same host for a few seconds, so host A's read just after B's import could
# miss the move and not refuse as session_migrated. Every command runs with
# the AWS_* variables and CLAUDE_CODE_SESSION_ID removed, so neither a real
# credential nor this session's identity reaches koto, and with every
# KOTO_SESSION_* variable, KOTO_SESSIONS_BASE and XDG_CONFIG_HOME removed, so
# each host reads only its own configuration: a KOTO_SESSION_* variable
# overrides the workspace's config, and the shell running a suite may point
# koto at a real bucket. ws_make checks what a workspace resolves before any
# session is written, and exits the suite when it isn't the fake server.
#
#   s3_start            start the server; sets S3_ENDPOINT and S3_PID
#   s3_stop             stop it (only the server this suite started)
#   host_make <label>   lay a host out, with its workspace `work`; prints nothing
#   host_ws <label>     the host's workspace, canonical (the path --from takes)
#   host_on <label> <command...>
#                       run a command in the host's workspace, as that host
#   ws_make <label> <ws>
#                       lay out a second workspace <ws> on a host host_make made
#   ws_path <label> <ws>
#                       that workspace, canonical
#   ws_on <label> <ws> <command...>
#                       run a command in that workspace, as that host
#
# Two workspaces on one host share HOME, the koto cache and the request store,
# as two checkouts on one machine do; each has its own .koto/config.toml, so
# koto keeps its sessions under its own prefix in the bucket. host_on is
# ws_on in the workspace `work`.
#
# Requires: bash 3.2+, python3.

S3_BUCKET=coordinate-test
S3_ENDPOINT=
S3_PID=

s3_start() {
    local i port
    mkdir -p "$T/s3"
    python3 -I "${CLOUD_HOSTS_S3:-$HERE/testdata/fake-s3.py}" "$S3_BUCKET" "$T/s3/port" > "$T/s3/log" 2>&1 &
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
    mkdir -p "$b/userhome/.koto" "$b/cache"
    ws_make "$1" work
    # Test-only credentials the fake server ignores; never a real one. Every
    # read checks the bucket itself (check_window_secs = 0).
    printf '[session.cloud]\naccess_key = "test-access"\nsecret_key = "test-secret"\ncheck_window_secs = 0\n' > "$b/userhome/.koto/config.toml"
}

ws_make() {
    local w="$T/hosts/$1/$2"
    mkdir -p "$w/.koto"
    printf '[session]\nbackend = "cloud"\n\n[session.cloud]\nendpoint = "%s"\nbucket = "%s"\nregion = "us-east-1"\npath_style = true\n' \
        "$S3_ENDPOINT" "$S3_BUCKET" > "$w/.koto/config.toml"
    # Fail closed: a workspace that resolves any other backend, endpoint or
    # bucket would write the suite's sessions somewhere real.
    local got
    got="$(ws_on "$1" "$2" koto config get session.backend 2>&1) $(ws_on "$1" "$2" koto config get session.cloud.endpoint 2>&1) $(ws_on "$1" "$2" koto config get session.cloud.bucket 2>&1)"
    if [ "$got" != "cloud $S3_ENDPOINT $S3_BUCKET" ]; then
        echo "cloud-hosts: workspace $2 on host $1 doesn't resolve the fake S3 server; stopping before koto writes a session" >&2
        exit 1
    fi
}

host_ws() { ws_path "$1" work; }

ws_path() { (cd "$T/hosts/$1/$2" && pwd -P); }

host_on() {
    local h="$1"
    shift
    ws_on "$h" work "$@"
}

ws_on() {
    local b w
    b=$(cd "$T/hosts/$1" && pwd -P) || return 1
    w="$2"
    shift 2
    (cd "$b/$w" || exit 1
        for v in $(env | sed -n 's/^\(KOTO_SESSION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
        exec env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_PROFILE \
            -u CLAUDE_CODE_SESSION_ID -u XDG_CONFIG_HOME -u KOTO_SESSIONS_BASE \
            HOME="$b/userhome" XDG_CACHE_HOME="$b/cache" "$@")
}
