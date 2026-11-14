#!/usr/bin/env bash
# skill-session-koto-contract_test.sh -- runs scripts/skill-session.sh's reply
# table and parent_state against real koto 0.37.0, 0.37.1 and 0.37.2, on a
# scratch S3 bucket, through a local proxy that can fail chosen listings.
#
# Usage: bash scripts/skill-session-koto-contract_test.sh
#
# .github/workflows/check-skill-session-koto-contract.yml provisions the
# releases and a MinIO bucket on 127.0.0.1 and runs this. Run by hand, it
# skips unless every input below is set.
#
# Inputs, read after the guard line above (the guard clears KOTO_SESSION_*
# and AWS_*, not these):
#   CONTRACT_KOTO_0_37_0, CONTRACT_KOTO_0_37_1, CONTRACT_KOTO_0_37_2
#                           absolute paths of the three release binaries
#   CONTRACT_KOTO_PREINDEX  the 0.34.0 binary, the last release before the
#                           bucket's name index; it writes the parent sessions
#   CONTRACT_S3_ENDPOINT    the bucket's endpoint, http://127.0.0.1:<port> only
#   CONTRACT_S3_BUCKET, CONTRACT_S3_ACCESS_KEY, CONTRACT_S3_SECRET_KEY
#
# How it runs. A Python 3 reverse proxy on 127.0.0.1 forwards every request to
# the endpoint unchanged (the Host header included, since SigV4 signs it) and
# logs one line per request: `<METHOD> <path>?<query> <status> <mode>`. Before
# each request it reads a mode file:
#   pass      forward everything
#   sweep     answer 503 SlowDown to the root listing (delimiter=/ and an
#             empty prefix), which koto's sweep of other workspace prefixes
#             needs; forward the rest
#   own:<p>   answer 503 to any listing whose prefix starts with <p>/
#   all       answer 503 to everything
# A host is a HOME. Per release, host A (a HOME and a git repository) runs
# koto and skill-session.sh; host B (another HOME and repository) only holds
# a parent session. The 0.34.0 binary writes scope-h<r> as host A and
# scope-e<r> as host B, each with chain/dispatch for design and session/branch
# main, so neither has a name-index entry. The release then opens design-h<r>
# and design-e<r> on host A. Topics: n (never opened), h (parent held on this
# host), e (parent held only under host B's prefix); <r> is the release with
# the dots dropped (0370 for 0.37.0).
#
# The cases, per release, each counted once:
#   setup, then
#   never-opened, sweep finishes      koto's exact not-found reply; absent;
#                                     has-work exit 1
#   never-opened, sweep can't finish  exit 3 session_lookup_failed (0.37.1 on),
#                                     another exit 2 (0.37.0); has-work exit 7
#                                     with koto's line; never absent
#   context exists                    0 and 1 on a held session; 2 or 3, never
#                                     1, on a never-opened one with the sweep
#                                     failing
#   held here, sweep can't finish     dispatch read and adopt find scope-h<r>;
#                                     koto status exits 0
#   held elsewhere, sweep finishes    a KNOWN GAP: printed, not failed (koto
#                                     refuses where the plan expects a state)
#   held elsewhere, sweep can't finish  not a parent here: adopted=none
#   own prefix failing, whole bucket failing (0.37.1 and 0.37.2), on both
#                                     parents
#   reads write nothing               no PUT, POST or DELETE from a read-only
#                                     call, adopt's writes to its own child
#                                     excepted
# and one line per release: release=<version> cases=<n> failed=<m>.
#
# Every koto and skill-session.sh call runs under a 90 s bound; a call that
# outlasts it is killed with everything it started, and fails its case naming
# the release and the session.
#
# Exit codes:
#   0 -- every case passed on every release, or an input or tool is missing
#        and the suite skipped
#   1 -- a case failed; or the endpoint is not on 127.0.0.1, a binary is not
#        the release it is named for, or the proxy did not start
#
# Requires: bash 3.2+, python3, jq, git, pgrep, shasum or sha256sum. No
# associative arrays, no mapfile, no namerefs, no `wait -n`.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

KNOWN_GAP_ISSUE="ISSUE_PENDING"
BOUND=90

SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd -P)
SS="$SCRIPT_DIR/skill-session.sh"
TEMPLATE="$(cd -P "$SCRIPT_DIR/.." && pwd -P)/koto-templates/skill-session.md"
BASH_BIN=$(command -v "${BASH:-bash}")

skip() {
    echo "SKIP: $*; no case ran"
    exit 0
}
die() {
    echo "FAIL: $*" >&2
    exit 1
}

for _v in CONTRACT_KOTO_0_37_0 CONTRACT_KOTO_0_37_1 CONTRACT_KOTO_0_37_2 CONTRACT_KOTO_PREINDEX \
    CONTRACT_S3_ENDPOINT CONTRACT_S3_BUCKET CONTRACT_S3_ACCESS_KEY CONTRACT_S3_SECRET_KEY; do
    [ -n "${!_v:-}" ] || skip "$_v is not set"
done
for _t in python3 jq git pgrep; do
    command -v "$_t" >/dev/null 2>&1 || skip "$_t is not on PATH"
done
if command -v shasum >/dev/null 2>&1; then
    sha256() { shasum -a 256; }
elif command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum; }
else
    skip "neither shasum nor sha256sum is on PATH"
fi
unset _v _t

# The suite must never reach a real bucket.
grep -Eq '^http://127\.0\.0\.1:[0-9]+$' <<<"$CONTRACT_S3_ENDPOINT" \
    || die "CONTRACT_S3_ENDPOINT is [$CONTRACT_S3_ENDPOINT], not http://127.0.0.1:<port>; nothing ran"

[ -f "$SS" ] || die "skill-session.sh not found at $SS"
[ -f "$TEMPLATE" ] || die "the store template not found at $TEMPLATE"

# The no-copy text parent_state reads, taken from the script itself.
PARENT_NO_COPY_HERE=$(sed -n '/^PARENT_NO_COPY_HERE="/{s/^PARENT_NO_COPY_HERE="\(.*\)"$/\1/p;q;}' "$SS")
[ -n "$PARENT_NO_COPY_HERE" ] || die "cannot read PARENT_NO_COPY_HERE from $SS"

T=$(mktemp -d "${TMPDIR:-/tmp}/koto-contract-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
PROXY_PID=""
cleanup() {
    if [ -n "$PROXY_PID" ]; then
        kill "$PROXY_PID" 2>/dev/null
        wait "$PROXY_PID" 2>/dev/null
    fi
    case "${T:-}" in */koto-contract-test.*) chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" ;; esac
    return 0
}
ktg_on_exit cleanup

# skill-session.sh's scratch directories go under the suite's directory,
# outside every repository it makes.
mkdir -p "$T/tmp"
export TMPDIR="$T/tmp"

# --- the bound -----------------------------------------------------------------

# stop_tree <pid>: stop <pid>, then its descendants, then kill them deepest
# first. skill-session.sh runs koto two levels below the call, where pkill -P
# on the call alone would not reach, so this walks the tree with pgrep -P.
stop_tree() {
    local p=$1 c
    kill -STOP "$p" 2>/dev/null
    for c in $(pgrep -P "$p" 2>/dev/null); do
        stop_tree "$c"
    done
    kill -KILL "$p" 2>/dev/null
}

# bounded <stdin-file> <command...>: run the command in the background with
# stdout and stderr to files, and a watchdog that stops and kills it after
# BOUND seconds. Sets RC, OUT, ERR and TIMED (1 when the watchdog fired).
RC=0; OUT=""; ERR=""; TIMED=0
bounded() {
    local in=$1 pid wd
    shift
    rm -f "$T/timed-out"
    "$@" <"$in" >"$T/out" 2>"$T/err" &
    pid=$!
    (
        i=0
        while [ "$i" -lt "$BOUND" ]; do
            sleep 1
            kill -0 "$pid" 2>/dev/null || exit 0
            i=$((i + 1))
        done
        : >"$T/timed-out"
        stop_tree "$pid"
    ) </dev/null >/dev/null 2>&1 &
    wd=$!
    RC=0
    wait "$pid" || RC=$?
    TIMED=0
    if [ -e "$T/timed-out" ]; then
        TIMED=1
        wait "$wd" 2>/dev/null
        wait "$pid" 2>/dev/null
    else
        kill "$wd" 2>/dev/null
        wait "$wd" 2>/dev/null
    fi
    OUT=$(cat "$T/out")
    ERR=$(cat "$T/err")
}

# --- the releases ----------------------------------------------------------------

# check_version <bin> <version>: the binary's `version` names exactly <version>.
check_version() {
    local got
    [ -x "$1" ] || die "$1 is not an executable file"
    bounded /dev/null "$1" version
    got=$(sed -n '1s/^koto v\{0,1\}\([0-9][0-9.]*\).*$/\1/p' <<<"$OUT")
    if [ "$TIMED" -eq 1 ] || [ "$RC" -ne 0 ] || [ "$got" != "$2" ]; then
        die "$1 version printed [$OUT] (exit $RC), expected exactly $2; nothing ran"
    fi
}
check_version "$CONTRACT_KOTO_PREINDEX" 0.34.0
check_version "$CONTRACT_KOTO_0_37_0" 0.37.0
check_version "$CONTRACT_KOTO_0_37_1" 0.37.1
check_version "$CONTRACT_KOTO_0_37_2" 0.37.2

# --- the proxy -------------------------------------------------------------------

MODE_FILE="$T/proxy.mode"
PLOG="$T/proxy.log"
: >"$PLOG"
printf 'pass\n' >"$MODE_FILE"

cat >"$T/proxy.py" <<'PY'
"""A reverse proxy in front of an S3 endpoint that can fail chosen listings.

argv: <upstream http://host:port> <mode file> <log file> <port file>
"""
import http.client
import http.server
import os
import sys
import threading
import urllib.parse

UPSTREAM = urllib.parse.urlsplit(sys.argv[1])
MODE_FILE, LOG_FILE, PORT_FILE = sys.argv[2], sys.argv[3], sys.argv[4]
LOG_LOCK = threading.Lock()

# A GET on the bucket carrying one of these asks for something other than a
# listing.
SUBRESOURCES = frozenset([
    "accelerate", "acl", "analytics", "cors", "encryption", "intelligent-tiering",
    "inventory", "lifecycle", "location", "logging", "metrics", "notification",
    "object-lock", "ownershipControls", "policy", "policyStatus", "publicAccessBlock",
    "replication", "requestPayment", "tagging", "uploads", "versioning", "website",
])
# Headers that describe one connection, or the body's length as relayed;
# the reply sets its own.
HOP = frozenset([
    "connection", "keep-alive", "proxy-connection", "transfer-encoding", "te",
    "trailer", "upgrade", "content-length",
])
SLOWDOWN = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    "<Error><Code>SlowDown</Code><Message>Please reduce your request rate.</Message>"
    "<Resource>%s</Resource><RequestId>contract-proxy</RequestId></Error>"
)


def current_mode():
    try:
        with open(MODE_FILE, "r") as fh:
            value = fh.read().strip()
    except OSError:
        value = ""
    return value or "pass"


def record(method, path, query, status, mode):
    with LOG_LOCK:
        with open(LOG_FILE, "a") as fh:
            fh.write("%s %s?%s %s %s\n" % (method, path, query, status, mode))


def is_listing(method, path, params):
    if method != "GET":
        return False
    if len([p for p in path.split("/") if p]) != 1:
        return False
    return not any(k in SUBRESOURCES for k in params)


def faulted(method, path, query, mode):
    if mode == "all":
        return True
    params = urllib.parse.parse_qs(query, keep_blank_values=True)
    if not is_listing(method, path, params):
        return False
    prefix = params.get("prefix", [""])[0]
    if mode == "sweep":
        return params.get("delimiter", [""])[0] == "/" and prefix == ""
    if mode.startswith("own:"):
        return prefix.startswith(mode[4:] + "/")
    return False


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def body(self):
        """Yield the request body's bytes exactly as they arrived.

        A chunked body is passed through raw, chunk-size lines, data, CRLFs
        and trailer included, so the upstream reads the same framing the
        client sent. Any other body is read to its Content-Length.
        """
        if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
            while True:
                line = self.rfile.readline(65537)
                if not line.endswith(b"\n"):
                    raise ConnectionError("chunked body cut short")
                yield line
                size = int(line.split(b";", 1)[0].strip(), 16)
                if size == 0:
                    break
                left = size + 2
                while left > 0:
                    piece = self.rfile.read(min(left, 65536))
                    if not piece:
                        raise ConnectionError("chunked body cut short")
                    left -= len(piece)
                    yield piece
            while True:
                line = self.rfile.readline(65537)
                if not line.endswith(b"\n"):
                    raise ConnectionError("chunked trailer cut short")
                yield line
                if line in (b"\r\n", b"\n"):
                    return
        left = int(self.headers.get("Content-Length") or "0")
        while left > 0:
            piece = self.rfile.read(min(left, 65536))
            if not piece:
                raise ConnectionError("body cut short")
            left -= len(piece)
            yield piece

    def reply(self, status, reason, headers, data, head):
        self.send_response_only(status, reason)
        for name, value in headers:
            self.send_header(name, value)
        if status >= 200 and status not in (204, 304) and not head:
            self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if data and not head:
            self.wfile.write(data)
        self.wfile.flush()

    def handle_any(self):
        mode = current_mode()
        method = self.command
        path, _, query = self.path.partition("?")
        head = method == "HEAD"
        try:
            if faulted(method, path, query, mode):
                for _ in self.body():
                    pass
                record(method, path, query, 503, mode)
                data = (SLOWDOWN % path).encode()
                self.reply(503, "Slow Down", [("Content-Type", "application/xml")], data, head)
                return
            conn = http.client.HTTPConnection(UPSTREAM.hostname, UPSTREAM.port, timeout=60)
            try:
                conn.putrequest(method, self.path, skip_host=True, skip_accept_encoding=True)
                for name, value in self.headers.items():
                    conn.putheader(name, value)
                conn.endheaders()
                for piece in self.body():
                    conn.send(piece)
                resp = conn.getresponse()
                data = resp.read()
                status, reason = resp.status, resp.reason
                headers = [(k, v) for k, v in resp.getheaders() if k.lower() not in HOP]
                if head and resp.getheader("Content-Length") is not None:
                    headers.append(("Content-Length", resp.getheader("Content-Length")))
            finally:
                conn.close()
        except (OSError, ValueError, http.client.HTTPException) as e:
            record(method, path, query, 502, mode)
            self.close_connection = True
            try:
                self.reply(502, "Bad Gateway", [("Content-Type", "text/plain")],
                           ("proxy: %s\n" % e).encode(), head)
            except OSError:
                pass
            return
        record(method, path, query, status, mode)
        self.reply(status, reason, headers, data, head)

    do_GET = do_PUT = do_POST = do_DELETE = do_HEAD = handle_any


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


server = Server(("127.0.0.1", 0), Proxy)
with open(PORT_FILE + ".tmp", "w") as fh:
    fh.write("%d\n" % server.server_address[1])
os.replace(PORT_FILE + ".tmp", PORT_FILE)
server.serve_forever()
PY

python3 -I "$T/proxy.py" "$CONTRACT_S3_ENDPOINT" "$MODE_FILE" "$PLOG" "$T/proxy.port" \
    </dev/null >"$T/proxy.err" 2>&1 &
PROXY_PID=$!
_i=0
while [ ! -s "$T/proxy.port" ] && [ "$_i" -lt 100 ]; do
    kill -0 "$PROXY_PID" 2>/dev/null || break
    sleep 0.1
    _i=$((_i + 1))
done
PROXY_PORT=$(head -n 1 "$T/proxy.port" 2>/dev/null)
case "$PROXY_PORT" in
    ''|*[!0-9]*) die "the proxy did not start: $(cat "$T/proxy.err" 2>/dev/null)" ;;
esac
unset _i

set_mode() {
    printf '%s\n' "$1" >"$MODE_FILE.tmp" && mv "$MODE_FILE.tmp" "$MODE_FILE"
}

# --- hosts -----------------------------------------------------------------------

# kh <bin> <home> <dir> <args...>: run a koto binary as the host <home>, from
# <dir>, on the bucket behind the proxy. KOTO_HOME stays unset: with it set,
# koto ignores a backend chosen from the environment.
kh() {
    local bin=$1 home=$2 dir=$3
    shift 3
    (cd "$dir" && HOME="$home" KOTO_SESSION_BACKEND=cloud \
        KOTO_SESSION_CLOUD_ENDPOINT="http://127.0.0.1:$PROXY_PORT" \
        KOTO_SESSION_CLOUD_BUCKET="$CONTRACT_S3_BUCKET" \
        KOTO_SESSION_CLOUD_REGION=us-east-1 \
        KOTO_SESSION_CLOUD_PATH_STYLE=true \
        KOTO_SESSION_CLOUD_ACCESS_KEY="$CONTRACT_S3_ACCESS_KEY" \
        KOTO_SESSION_CLOUD_SECRET_KEY="$CONTRACT_S3_SECRET_KEY" \
        "$bin" "$@")
}

# ss_a <bin> <args...>: run skill-session.sh as host A, from repo A, with
# KOTO_BIN=<bin> and the same backend.
ss_a() {
    local bin=$1
    shift
    (cd "$REPO_A" && HOME="$HOME_A" KOTO_BIN="$bin" KOTO_SESSION_BACKEND=cloud \
        KOTO_SESSION_CLOUD_ENDPOINT="http://127.0.0.1:$PROXY_PORT" \
        KOTO_SESSION_CLOUD_BUCKET="$CONTRACT_S3_BUCKET" \
        KOTO_SESSION_CLOUD_REGION=us-east-1 \
        KOTO_SESSION_CLOUD_PATH_STYLE=true \
        KOTO_SESSION_CLOUD_ACCESS_KEY="$CONTRACT_S3_ACCESS_KEY" \
        KOTO_SESSION_CLOUD_SECRET_KEY="$CONTRACT_S3_SECRET_KEY" \
        "$BASH_BIN" "$SS" "$@")
}

# prefix_of <dir>: koto's bucket prefix for <dir>, the first 16 hex characters
# of the SHA-256 of its canonical path (koto src/session/local.rs, repo_id).
prefix_of() {
    local p
    p=$(cd -P "$1" && pwd -P) || return 1
    printf '%s' "$p" | sha256 | cut -c1-16
}

# --- cases -----------------------------------------------------------------------

VER=""; R=""; BIN=""; NEW=0
CASES=0; FAILED=0; CASE=""; CASE_BAD=0
WRITES=0; WRITE_LOG=""
ANY_FAILED=0

oneline() { printf '%s' "$1" | tr '\n' ' ' | cut -c1-400; }

case_start() { CASE="$1"; CASE_BAD=0; }
bad() {
    CASE_BAD=1
    printf 'FAIL: %s %s: %s\n' "$VER" "$CASE" "$*"
}
case_end() {
    CASES=$((CASES + 1))
    if [ "$CASE_BAD" -eq 0 ]; then
        printf 'PASS: %s %s\n' "$VER" "$CASE"
    else
        FAILED=$((FAILED + 1))
    fi
}

has_line() { grep -qxF -- "$2" <<<"$1"; }
# jget <json> <field>: the field of the last stdout line that is a JSON object.
jget() {
    printf '%s\n' "$1" | jq -R -r --arg f "$2" \
        'fromjson? | select(type == "object") | .[$f] | select(. != null) | if type == "string" then . else tojson end' \
        2>/dev/null | tail -n 1
}
jhas() {
    printf '%s\n' "$1" | jq -R -r --arg f "$2" 'fromjson? | select(type == "object") | has($f)' 2>/dev/null | tail -n 1
}
is_slf() { [ "$RC" = 3 ] && [ "$(jget "$OUT" code)" = session_lookup_failed ]; }

expect_rc() {
    [ "$RC" = "$1" ] || bad "$2: exit $RC, want $1; stdout [$(oneline "$OUT")] stderr [$(oneline "$ERR")]"
}
expect_line() {
    has_line "$OUT" "$1" || bad "$2: no line [$1]; exit $RC, stdout [$(oneline "$OUT")] stderr [$(oneline "$ERR")]"
}
expect_empty() {
    [ -z "$OUT" ] || bad "$1: printed [$(oneline "$OUT")], want nothing"
}
expect_not_absent() {
    if has_line "$OUT" absent; then bad "$1: printed absent (exit $RC)"; fi
}

log_lines() { wc -l <"$PLOG" | tr -d ' '; }

# adopt_writes <child>: the objects `skill-session.sh adopt` writes into its own
# child session by design, one bucket path per line; the only writes the
# "reads write nothing" count leaves out, and only from an adopt call. Each sits
# under the child's own session on this host's prefix, /<bucket>/<PREFIX_A>/
# <child>/, and nothing else is excluded: another key in the child, the parent
# session, another prefix and the name index all count.
#   ctx/chain/parent          adopt writes it on a match and removes it on none
#                             (scripts/skill-session.sh cmd_adopt)
#   ctx/koto/links/dispatched-by/scope-<topic>
#                             the link step after a match, `koto session link
#                             <child> --dispatched-by <parent>` (dl_link in
#                             scripts/lib/dispatch-link.sh)
#   ctx/session/link-warning  dl_link removes it after a link that took
#   ctx/manifest.json, koto-<child>.state.jsonl, version.json
#                             what koto pushes beside every context write: the
#                             manifest after the key (koto src/session/sync.rs,
#                             try_push_context_key), then the state file and
#                             the version (src/session/cloud.rs, state_key and
#                             version_key)
adopt_writes() {
    local s="/$CONTRACT_S3_BUCKET/$PREFIX_A/$1/" topic=${1#design-}
    printf '%s\n' \
        "${s}ctx/chain/parent" \
        "${s}ctx/koto/links/dispatched-by/scope-$topic" \
        "${s}ctx/session/link-warning" \
        "${s}ctx/manifest.json" \
        "${s}koto-$1.state.jsonl" \
        "${s}version.json"
}

# note_writes <mark> <adopt-child> <label>: add the PUT, POST and DELETE lines
# logged since <mark> to WRITES. With <adopt-child> set (an adopt call), a line
# whose path, query left off, is exactly one of adopt_writes <adopt-child> is
# left out.
note_writes() {
    local lines n allowed=""
    [ -z "$2" ] || allowed=$(adopt_writes "$2")
    # The list goes in through the environment: a newline in an awk -v value
    # isn't portable.
    lines=$(tail -n +"$(($1 + 1))" "$PLOG" | CONTRACT_ADOPT_WRITES="$allowed" awk '
        BEGIN { n = split(ENVIRON["CONTRACT_ADOPT_WRITES"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") ok[a[i]] = 1 }
        $1 == "PUT" || $1 == "POST" || $1 == "DELETE" {
            p = $2
            sub(/\?.*$/, "", p)
            if (p in ok) next
            print
        }')
    [ -n "$lines" ] || return 0
    n=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
    WRITES=$((WRITES + n))
    WRITE_LOG="$WRITE_LOG
  $3 ($CASE):
$(printf '%s\n' "$lines" | sed 's/^/    /')"
}

# after_call <session> <label>: fail the case when the call hit the bound.
after_call() {
    if [ "$TIMED" -eq 1 ]; then
        bad "$2 gave no answer within ${BOUND}s (release $VER, session $1); killed"
        # A request the killed call left in flight logs when it ends.
        sleep 2
    fi
}

# kread <session> <koto args...>: a read-only koto call with the release as
# host A in repo A. Its writes count.
kread() {
    local sess=$1 mark
    shift
    mark=$(log_lines)
    bounded /dev/null kh "$BIN" "$HOME_A" "$REPO_A" "$@"
    after_call "$sess" "koto $*"
    note_writes "$mark" "" "koto $*"
}

# sread <adopt-child> <session> <skill-session.sh args...>: a read-only
# skill-session.sh call as host A. Its writes count; for an adopt call,
# <adopt-child> names the child session whose adopt_writes are left out, and
# it is empty for every other call.
sread() {
    local excl=$1 sess=$2 mark
    shift 2
    mark=$(log_lines)
    bounded /dev/null ss_a "$BIN" "$@"
    after_call "$sess" "skill-session.sh $*"
    note_writes "$mark" "$excl" "skill-session.sh $*"
}

# kset <session> <bin> <home> <dir> <stdin-file> <koto args...>: a setup call
# that must exit 0.
kset() {
    local sess=$1 bin=$2 home=$3 dir=$4 in=$5
    shift 5
    bounded "$in" kh "$bin" "$home" "$dir" "$@"
    after_call "$sess" "koto $*"
    expect_rc 0 "koto $* ($(basename "$home"))"
}

make_repo() {
    mkdir -p "$1" &&
        git -C "$1" init -q &&
        git -C "$1" symbolic-ref HEAD refs/heads/main &&
        git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
            commit -q --allow-empty -m init
}

setup_release() {
    local base="$T/$R" since
    case_start "setup"
    set_mode pass
    HOME_A="$base/home-a"; HOME_B="$base/home-b"
    REPO_A="$base/repo-a"; REPO_B="$base/repo-b"
    if ! mkdir -p "$HOME_A" "$HOME_B" || ! make_repo "$REPO_A" || ! make_repo "$REPO_B"; then
        bad "could not make the hosts' directories and repositories under $base"
        case_end
        return 1
    fi
    PREFIX_A=$(prefix_of "$REPO_A")
    PREFIX_B=$(prefix_of "$REPO_B")
    # Exactly the three lines dispatch write stores, ending in one newline,
    # and the branch with none, as kput writes it.
    printf 'child: design\nsuppress_status_aware_prompt: true\nrationale: fresh-chain\n' >"$base/dispatch.in"
    printf 'main' >"$base/branch.in"

    local mark
    mark=$(log_lines)
    kset "scope-$TH" "$CONTRACT_KOTO_PREINDEX" "$HOME_A" "$REPO_A" /dev/null init "scope-$TH" --template "$TEMPLATE"
    kset "scope-$TH" "$CONTRACT_KOTO_PREINDEX" "$HOME_A" "$REPO_A" "$base/dispatch.in" context add "scope-$TH" chain/dispatch
    kset "scope-$TH" "$CONTRACT_KOTO_PREINDEX" "$HOME_A" "$REPO_A" "$base/branch.in" context add "scope-$TH" session/branch
    kset "scope-$TE" "$CONTRACT_KOTO_PREINDEX" "$HOME_B" "$REPO_B" /dev/null init "scope-$TE" --template "$TEMPLATE"
    kset "scope-$TE" "$CONTRACT_KOTO_PREINDEX" "$HOME_B" "$REPO_B" "$base/dispatch.in" context add "scope-$TE" chain/dispatch
    kset "scope-$TE" "$CONTRACT_KOTO_PREINDEX" "$HOME_B" "$REPO_B" "$base/branch.in" context add "scope-$TE" session/branch

    # The topics and prefixes are [a-z0-9], so they stand in a pattern as
    # themselves.
    since="$base/setup.log"
    tail -n +"$((mark + 1))" "$PLOG" >"$since"
    if grep -qE "^PUT [^ ]*/koto-names/scope-($TH|$TE)/" "$since"; then
        bad "the pre-index binary wrote a name-index entry: $(grep -E '^PUT [^ ]*/koto-names/' "$since" | tr '\n' ';')"
    fi
    grep -qE "^PUT [^ ]*/$PREFIX_A/scope-$TH/" "$since" \
        || bad "scope-$TH never reached the bucket under repo A's prefix $PREFIX_A"
    grep -qE "^PUT [^ ]*/$PREFIX_B/scope-$TE/" "$since" \
        || bad "scope-$TE never reached the bucket under repo B's prefix $PREFIX_B"

    local t
    for t in "$TH" "$TE"; do
        bounded /dev/null ss_a "$BIN" open design "$t"
        after_call "design-$t" "skill-session.sh open design $t"
        expect_rc 0 "skill-session.sh open design $t"
        expect_line "session=design-$t" "skill-session.sh open design $t"
    done
    local was_bad=$CASE_BAD
    case_end
    [ "$was_bad" -eq 0 ]
}

case_never_opened_pass() {
    local want="workflow 'design-$TN' not found"
    case_start "never-opened, sweep finishes"
    set_mode pass
    kread "design-$TN" status "design-$TN"
    expect_rc 2 "koto status design-$TN"
    [ "$(jhas "$OUT" code)" = false ] || bad "koto status design-$TN: the reply carries a code or isn't JSON: [$(oneline "$OUT")]"
    [ "$(jget "$OUT" error)" = "$want" ] || bad "koto status design-$TN: error is [$(jget "$OUT" error)], want [$want]"
    sread "" "design-$TN" status "design-$TN"
    expect_rc 0 "skill-session.sh status design-$TN"
    [ "$OUT" = absent ] || bad "skill-session.sh status design-$TN printed [$(oneline "$OUT")], want absent"
    sread "" "design-$TN" has-work design "$TN"
    expect_rc 1 "skill-session.sh has-work design $TN"
    case_end
}

case_never_opened_sweep() {
    local want="workflow 'design-$TN' not found" krc kout field lines
    case_start "never-opened, sweep can't finish"
    set_mode sweep
    kread "design-$TN" status "design-$TN"
    krc=$RC; kout=$OUT
    if [ "$NEW" -eq 1 ]; then
        is_slf || bad "koto status design-$TN: exit $RC code [$(jget "$OUT" code)], want 3 session_lookup_failed; stdout [$(oneline "$OUT")]"
        field=code
    else
        expect_rc 2 "koto status design-$TN"
        if [ -z "$(jget "$OUT" error)" ] || [ "$(jget "$OUT" error)" = "$want" ]; then
            bad "koto status design-$TN: error is [$(jget "$OUT" error)], want one that isn't the not-found reply"
        fi
        field=error
    fi
    if [ "$VER" = 0.37.2 ]; then
        printf 'NOTE: %s koto status design-%s, sweep failing: reason %s, index %s\n' "$VER" "$TN" \
            "$( [ "$(jhas "$kout" reason)" = true ] && echo "present ($(jget "$kout" reason))" || echo absent)" \
            "$( [ "$(jhas "$kout" index)" = true ] && echo "present ($(jget "$kout" index))" || echo absent)"
    fi
    sread "" "design-$TN" has-work design "$TN"
    expect_rc 7 "skill-session.sh has-work design $TN"
    lines=$(printf '%s\n' "$OUT" | grep -c .)
    [ "$lines" = 1 ] || bad "skill-session.sh has-work design $TN: $lines stdout lines, want koto's one line: [$(oneline "$OUT")]"
    [ -n "$(jget "$OUT" "$field")" ] && [ "$(jget "$OUT" "$field")" = "$(jget "$kout" "$field")" ] \
        || bad "skill-session.sh has-work design $TN: .$field [$(jget "$OUT" "$field")] is not koto's [$(jget "$kout" "$field")] (koto exit $krc)"
    sread "" "design-$TN" status "design-$TN"
    expect_not_absent "skill-session.sh status design-$TN"
    set_mode pass
    case_end
}

case_context_exists() {
    case_start "context exists"
    set_mode pass
    kread "scope-$TH" context exists "scope-$TH" session/branch
    expect_rc 0 "koto context exists scope-$TH session/branch"
    kread "scope-$TH" context exists "scope-$TH" work/none
    expect_rc 1 "koto context exists scope-$TH work/none"
    set_mode sweep
    kread "design-$TN" context exists "design-$TN" session/branch
    if [ "$RC" = 2 ] || is_slf; then
        :
    else
        bad "koto context exists design-$TN session/branch, sweep failing: exit $RC code [$(jget "$OUT" code)], want 2 or 3 session_lookup_failed"
    fi
    set_mode pass
    case_end
}

case_held_here_sweep() {
    case_start "held here, sweep can't finish"
    set_mode sweep
    sread "" "scope-$TH" dispatch read design "$TH"
    expect_line "parent=scope-$TH" "skill-session.sh dispatch read design $TH"
    kread "scope-$TH" status "scope-$TH"
    if is_slf; then
        bad "koto status scope-$TH: exit 3 session_lookup_failed for a session held on this host"
    fi
    expect_rc 0 "koto status scope-$TH"
    sread "design-$TH" "design-$TH" adopt design "$TH"
    expect_rc 0 "skill-session.sh adopt design $TH"
    expect_line "adopted=scope-$TH" "skill-session.sh adopt design $TH"
    set_mode pass
    case_end
}

case_held_elsewhere_pass() {
    local krc kcode src sout
    case_start "held elsewhere, sweep finishes"
    set_mode pass
    kread "scope-$TE" status "scope-$TE"
    krc=$RC; kcode=$(jget "$OUT" code)
    sread "" "scope-$TE" status "scope-$TE"
    src=$RC; sout=$OUT
    expect_not_absent "skill-session.sh status scope-$TE"
    sread "" "scope-$TE" dispatch read design "$TE"
    expect_rc 0 "skill-session.sh dispatch read design $TE"
    expect_empty "skill-session.sh dispatch read design $TE"
    sread "design-$TE" "design-$TE" adopt design "$TE"
    expect_rc 0 "skill-session.sh adopt design $TE"
    expect_line "adopted=none" "skill-session.sh adopt design $TE"
    printf 'KNOWN GAP: %s (%s): scope-%s held only under another prefix, sweep finishing: koto status exit %s code %s, skill-session.sh status exit %s printing [%s]; the plan expects live or finished here\n' \
        "$VER" "$KNOWN_GAP_ISSUE" "$TE" "$krc" "${kcode:-none}" "$src" "$(oneline "$sout")"
    case_end
}

case_held_elsewhere_sweep() {
    case_start "held elsewhere, sweep can't finish"
    set_mode sweep
    kread "scope-$TE" status "scope-$TE"
    if [ "$NEW" -eq 1 ]; then
        is_slf || bad "koto status scope-$TE: exit $RC code [$(jget "$OUT" code)], want 3 session_lookup_failed; stdout [$(oneline "$OUT")]"
    else
        case "$OUT" in
            *"$PARENT_NO_COPY_HERE"*) printf 'NOTE: %s koto status scope-%s (exit %s) carries the PARENT_NO_COPY_HERE text\n' "$VER" "$TE" "$RC" ;;
            *) printf 'NOTE: %s koto status scope-%s (exit %s) does not carry the PARENT_NO_COPY_HERE text: [%s]\n' "$VER" "$TE" "$RC" "$(oneline "$OUT")" ;;
        esac
    fi
    sread "design-$TE" "design-$TE" adopt design "$TE"
    expect_rc 0 "skill-session.sh adopt design $TE"
    expect_line "adopted=none" "skill-session.sh adopt design $TE"
    sread "" "scope-$TE" dispatch read design "$TE"
    expect_rc 0 "skill-session.sh dispatch read design $TE"
    expect_empty "skill-session.sh dispatch read design $TE"
    sread "" "scope-$TE" status "scope-$TE"
    expect_not_absent "skill-session.sh status scope-$TE"
    set_mode pass
    case_end
}

# case_widened <mode> <label>: the two shapes 0.37.1 and 0.37.2 refuse with
# session_lookup_failed, on the parent held elsewhere and the one held here.
case_widened() {
    case_start "$2, held elsewhere"
    set_mode "$1"
    kread "scope-$TE" status "scope-$TE"
    is_slf || bad "koto status scope-$TE: exit $RC code [$(jget "$OUT" code)], want 3 session_lookup_failed; stdout [$(oneline "$OUT")]"
    sread "design-$TE" "design-$TE" adopt design "$TE"
    expect_rc 0 "skill-session.sh adopt design $TE"
    expect_line "adopted=none" "skill-session.sh adopt design $TE"
    sread "" "scope-$TE" status "scope-$TE"
    expect_not_absent "skill-session.sh status scope-$TE"
    set_mode pass
    case_end

    case_start "$2, held here"
    set_mode "$1"
    kread "scope-$TH" status "scope-$TH"
    if is_slf; then
        bad "koto status scope-$TH: exit 3 session_lookup_failed for a session held on this host"
    fi
    expect_rc 0 "koto status scope-$TH"
    sread "design-$TH" "design-$TH" adopt design "$TH"
    expect_rc 0 "skill-session.sh adopt design $TH"
    expect_line "adopted=scope-$TH" "skill-session.sh adopt design $TH"
    sread "" "scope-$TH" status "scope-$TH"
    expect_not_absent "skill-session.sh status scope-$TH"
    set_mode pass
    case_end
}

case_writes() {
    case_start "reads write nothing"
    [ "$WRITES" -eq 0 ] || bad "$WRITES write request(s) from read-only calls:$WRITE_LOG"
    case_end
}

run_release() {
    R=$(printf '%s' "$VER" | tr -d .)
    TN="n$R"; TH="h$R"; TE="e$R"
    CASES=0; FAILED=0; WRITES=0; WRITE_LOG=""
    case "$VER" in 0.37.0) NEW=0 ;; *) NEW=1 ;; esac
    echo "== koto $VER ($BIN) =="
    if setup_release; then
        case_never_opened_pass
        case_never_opened_sweep
        case_context_exists
        case_held_here_sweep
        case_held_elsewhere_pass
        case_held_elsewhere_sweep
        if [ "$NEW" -eq 1 ]; then
            case_widened "own:$PREFIX_A" "this directory's prefix failing"
            case_widened all "the whole bucket failing"
        fi
        case_writes
    else
        echo "NOTE: $VER setup failed; the release's other cases did not run"
    fi
    set_mode pass
    echo "release=$VER cases=$CASES failed=$FAILED"
    [ "$FAILED" -eq 0 ] || ANY_FAILED=1
}

for VER in 0.37.0 0.37.1 0.37.2; do
    case "$VER" in
        0.37.0) BIN=$CONTRACT_KOTO_0_37_0 ;;
        0.37.1) BIN=$CONTRACT_KOTO_0_37_1 ;;
        0.37.2) BIN=$CONTRACT_KOTO_0_37_2 ;;
    esac
    run_release
done

[ "$ANY_FAILED" -eq 0 ]
