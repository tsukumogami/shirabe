# test-lib.sh -- shared setup for /coordinate's record script tests. Sourced by
# a *_test.sh after it sets HERE (the scripts directory). Not shipped behaviour.
#
# It makes a scratch directory, puts the gh and koto stand-ins first on PATH,
# and gives each test: a GitHub DB ($GH_DB) with helpers to seed and edit it,
# record bodies rendered by the real codec, and prepared koto session logs in
# the shape real koto writes.

T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-test.XXXXXX") || exit 1
trap 'case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac' EXIT
export GH_DB="$T/db.json" KOTO_STORE="$T/koto" KOTO_COMPILED_HASH=feedface
mkdir -p "$KOTO_STORE/sessions"
PATH="$HERE/testdata:$PATH"
export PATH
PLUGIN_ROOT_REAL=$(cd "$HERE/../../.." && pwd -P)

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
done_tests() { echo; echo "$1: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }

SHA_MAIN=1111111111111111111111111111111111111111
SHA_HEAD=2222222222222222222222222222222222222222
SHA_OTHER=3333333333333333333333333333333333333333
REPO=acme/widgets

db_init() {
    jq -n --arg m "$SHA_MAIN" '{login: "coord",
        repos: {"acme/widgets": {private: false, default_branch: "main"},
                "acme/gadgets": {private: false, default_branch: "main"},
                "acme/secret": {private: true, default_branch: "main"}},
        issues: [], prs: [],
        branches: {"acme/widgets": {main: $m}},
        commits: {($m): {tree: "4444444444444444444444444444444444444444"}},
        permissions: {"acme/widgets": {alice: "admin", carol: "write", dave: "maintain", bob: "read", coord: "admin"}},
        files: {}, fail: []}' > "$GH_DB"
    : > "$GH_DB.calls"
}
db() { # db <jq program> [jq args...]: edit the DB
    local p=$1; shift
    jq "$@" "$p" "$GH_DB" > "$GH_DB.new" && mv "$GH_DB.new" "$GH_DB"
}
calls() { cat "$GH_DB.calls"; }
reset_calls() { : > "$GH_DB.calls"; }

holding() { # holding <worker> [jq object to merge]
    local extra=${2-}
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg w "$1" --argjson x "$extra" '{unit: "Feature 2", entry_point: "/shirabe:deliver", mode: "--auto",
        phase: "executing", dispatch_status: "dispatched", return_path: "message", worker: $w,
        repo: "acme/widgets", branch: "feat/x", verified_head: "", dispatched: "2026-09-26",
        pull_request: "[#12](https://github.com/acme/widgets/pull/12)"} + $x'
}
# session_keys <session> <parsed-record-file> [pending]: a record's state as the
# session store holds it, record/meta and one key per section the record has,
# written straight into the koto stand-in for a reader's test. A writer's test
# seeds the store this way and then writes through the write core.
session_keys() {
    local s=$1 f=$2 p=${3:-false} pair field key
    jq -c --argjson p "$p" '{scope, store: "session", written, pending: $p}' "$f" | koto context add "$s" record/meta
    for pair in holdings:holdings deferrals:deferrals side_effects:side-effects reversals:reversals decisions:decisions holds:holds run:run standing:standing work:work; do
        field=${pair%%:*} key=${pair#*:}
        jq -e --arg f "$field" 'has($f)' "$f" > /dev/null || continue
        jq -c --arg f "$field" '.[$f]' "$f" | koto context add "$s" "record/$key"
    done
}
# seed_session <session> <record-json> [written]: a record as the session
# holds it, the session's record/ keys replaced: the JSON in state-schema.jq's
# normal form, so the keys hold the state a write would leave, then written
# with session_keys. written defaults to state_json's, 2026-09-26T09:00:00Z, so
# a state built from the same JSON reads as edited from this version.
seed_session() {
    local s=$1 w=${3:-2026-09-26T09:00:00Z}
    rm -rf "$KOTO_STORE/context/$s/record"
    state_json "$2" "$w" > "$T/seed-session.json" || return 1
    session_keys "$s" "$T/seed-session.json"
}
# state_json <json> [written]: the record JSON as a writer hands it to the
# write core (--state-file): state-schema.jq's normal form, carrying the
# written time of the version it was edited from (2026-09-26T09:00:00Z unless
# given). A state that breaks a rule fails, with the module's reason on stderr.
state_json() {
    printf '%s' "$1" | jq -c -L "$HERE" --arg w "${2:-2026-09-26T09:00:00Z}" 'include "state-schema"; normalize_state([]) | .written = $w'
}
# session_state <session>: the record the session's keys hold, as one JSON
# object in record-parse.sh's shape, `written` from record/meta; pushed heads
# are left beside their rows.
session_state() {
    local d="$KOTO_STORE/context/$1/record" pair
    jq -c '{scope, written}' "$d/meta" > "$T/ss.json" || return 1
    for pair in holdings:holdings deferrals:deferrals side_effects:side-effects reversals:reversals decisions:decisions holds:holds run:run standing:standing work:work; do
        [ -f "$d/${pair#*:}" ] || continue
        jq -c --arg f "${pair%%:*}" --slurpfile v "$d/${pair#*:}" '.[$f] = $v[0]' "$T/ss.json" > "$T/ss.new" && mv "$T/ss.new" "$T/ss.json"
    done
    cat "$T/ss.json"
}
# session_snapshot <session>: one line per record/ key, its name and its
# content as hex bytes, so a test can show a refused write changed no key.
# Hex from od, not a cksum digest: run-tests.sh's PATH has no cksum, and an
# empty digest would make every snapshot compare equal.
session_snapshot() {
    local d="$KOTO_STORE/context/$1/record"
    [ -d "$d" ] || { echo none; return; }
    (cd "$d" && find . -type f | LC_ALL=C sort | while read -r f; do printf '%s %s\n' "$f" "$(od -An -tx1 < "$f" | tr -d ' \n')"; done)
}

record_json() { # record_json <roadmap|discipline> <name>: an empty record
    jq -nc --arg k "$1" --arg n "$2" '{scope: {kind: $k, name: $n}, holdings: [], deferrals: [], side_effects: [], reversals: []}'
}
render() { # render <json> <issue|pr> [written]: a canonical body on stdout
    # Suites render the same fixture many times over, so each distinct
    # (json, container, written) is rendered once and kept under $T; a render
    # that fails is never kept, so it fails again the same way. The key holds
    # the inputs, not the renderer: a suite that swaps record-render.sh for a
    # copy needs its own $T. The body comes back with one trailing newline,
    # as record-render.sh prints it.
    local w=${3:-2026-09-26T09:00:00Z} k f rc
    k=$(printf '%s\n%s\n%s' "$2" "$w" "$1" | $SHA256)
    f="$T/render-cache/${k%% *}"
    if [ ! -f "$f" ]; then
        mkdir -p "$T/render-cache"
        printf '%s' "$1" | bash "$HERE/record-render.sh" --container "$2" --written "$w" > "$f.new"
        rc=$?
        [ "$rc" = 0 ] || { rm -f "$f.new"; return "$rc"; }
        mv "$f.new" "$f"
    fi
    printf '%s\n' "$(< "$f")"
}
if command -v sha256sum >/dev/null 2>&1; then SHA256=sha256sum; else SHA256='shasum -a 256'; fi

# Session logs. log_new <session> <vars-json> writes the header and init; each
# log_ev appends one event with the next seq.
log_new() {
    local d="$KOTO_STORE/sessions/$1"
    mkdir -p "$d"
    if _plain "$1" && _plain "${3:-feedface}"; then
        printf '{"schema_version":1,"workflow":"%s","template_hash":"%s","created_at":"2026-09-26T08:00:00.000Z","template_name":"coordinate"}\n' \
            "$1" "${3:-feedface}" > "$d/koto-$1.state.jsonl"
    else
        jq -nc --arg s "$1" --arg h "${3:-feedface}" '{schema_version: 1, workflow: $s, template_hash: $h,
            created_at: "2026-09-26T08:00:00.000Z", template_name: "coordinate"}' > "$d/koto-$1.state.jsonl"
    fi
    printf '0' > "$d/.seq"
    if _compact "$2"; then
        _log_put "$1" workflow_initialized "{\"template_path\":\"x\",\"variables\":$2}" 2026-09-26T08:00:00.000Z 1
    else
        log_ev "$1" workflow_initialized "$(jq -nc --argjson v "$2" '{template_path: "x", variables: $v}')" 2026-09-26T08:00:00.000Z
    fi
    log_ev "$1" transitioned '{"from":null,"to":"start","condition_type":"auto"}' 2026-09-26T08:00:00.000Z
}
# The log writers below run hundreds of times a suite, so they write each line
# without starting jq when they can: a value with nothing JSON would escape (no
# quote, backslash or control character) is quoted as it stands, and a payload
# with no whitespace or backslash is taken as already compact. Anything else
# goes through jq as before. For the payloads the suites pass, the line is the
# one `jq -c` wrote; a payload on the fast path is not validated, so a
# malformed one shows up when a reader parses the log, not here.
_plain() { case "$1" in *'"'*|*'\'*|*[[:cntrl:]]*) return 1 ;; esac; }
_compact() { case "$1" in *[[:space:]]*|*'\'*|'') return 1 ;; esac; }
# _log_put <session> <type> <payload> <timestamp> <compact:0|1>: append one
# event with the next seq. With <compact> 1 the payload is taken as compact
# (built here from plain values, or a caller's with no whitespace or
# backslash) and written as it stands, unvalidated; it then differs from what
# jq -c would write only in number literals jq rewrites, such as 1.0 or 1e2.
_log_put() {
    local d="$KOTO_STORE/sessions/$1" n=
    # .seq holds no trailing newline, so read reports end of file; n is set.
    read -r n < "$d/.seq" || true
    n=$((n + 1))
    printf '%s' "$n" > "$d/.seq"
    if [ "$5" = 1 ] && _plain "$2" && _plain "$4"; then
        printf '{"seq":%s,"timestamp":"%s","type":"%s","payload":%s}\n' "$n" "$4" "$2" "$3" >> "$d/koto-$1.state.jsonl"
    else
        jq -nc --argjson q "$n" --arg ts "$4" --arg t "$2" --argjson p "$3" \
            '{seq: $q, timestamp: $ts, type: $t, payload: $p}' >> "$d/koto-$1.state.jsonl"
    fi
}
log_ev() { # log_ev <session> <type> <payload-json> [timestamp]
    local c=0
    _compact "$3" && c=1
    _log_put "$1" "$2" "$3" "${4:-2026-09-26T10:00:00.000Z}" "$c"
}
log_to() { # log_to <session> <from> <to> [timestamp]
    if _plain "$2" && _plain "$3"; then
        _log_put "$1" transitioned "{\"from\":\"$2\",\"to\":\"$3\",\"condition_type\":\"gate\"}" "${4:-2026-09-26T10:00:00.000Z}" 1
    else
        log_ev "$1" transitioned "$(jq -nc --arg f "$2" --arg t "$3" '{from: $f, to: $t, condition_type: "gate"}')" "${4:-2026-09-26T10:00:00.000Z}"
    fi
}
log_evidence() { # log_evidence <session> <state> <fields-json> [timestamp]
    if _plain "$2" && _compact "$3"; then
        _log_put "$1" evidence_submitted "{\"state\":\"$2\",\"fields\":$3}" "${4:-2026-09-26T10:00:00.000Z}" 1
    else
        log_ev "$1" evidence_submitted "$(jq -nc --arg s "$2" --argjson f "$3" '{state: $s, fields: $f}')" "${4:-2026-09-26T10:00:00.000Z}"
    fi
}
log_capture() { # log_capture <session> <key> <value> [timestamp]
    if _plain "$2" && _plain "$3"; then
        _log_put "$1" variable_captured "{\"key\":\"$2\",\"value\":\"$3\"}" "${4:-2026-09-26T10:00:00.000Z}" 1
    else
        log_ev "$1" variable_captured "$(jq -nc --arg k "$2" --arg v "$3" '{key: $k, value: $v}')" "${4:-2026-09-26T10:00:00.000Z}"
    fi
}
# Verdict tokens. koto refuses to capture a value holding = , + # ( [ | or ;
# so a token may use only letters, digits, spaces and : / _ . - @. A test
# records every token it sees with `seen`; tokens_ok checks them all.
RE_TOKEN='^[A-Za-z0-9 :/_.@-]*$'
seen() { printf '%s\n' "$1" >> "$T/tokens"; printf '%s\n' "$1"; }
tokens_ok() { # tokens_ok <script>: every token seen fits a koto capture
    local n=0 badt=
    while IFS= read -r t; do
        n=$((n + 1))
        [[ $t =~ $RE_TOKEN ]] || { badt=$t; break; }
    done < "$T/tokens"
    if [ -n "$badt" ]; then bad "every $1 token fits a koto capture" "[$badt]"
    elif [ "$n" -eq 0 ]; then bad "every $1 token fits a koto capture" "no token was seen"
    else ok "every $1 token fits a koto capture ($n seen)"; fi
}
# opened_from <session> <template-path> <compiled-content>: rewrite the
# session's header and init event as koto records a session opened from that
# template: the source path in the header, and a compiled copy in the stand-in's
# cache, named by its sha256, which becomes the header's template_hash. Pair it
# with a KOTO_COMPILED_HASH other than that hash (any value that differs) to
# model the plugin rewritten in place since the run opened.
opened_from() {
    local f="$KOTO_STORE/sessions/$1/koto-$1.state.jsonl" c h
    mkdir -p "$KOTO_STORE/cache"
    printf '%s' "$3" > "$KOTO_STORE/cache/opened.json"
    if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum < "$KOTO_STORE/cache/opened.json" | cut -d' ' -f1)
    else h=$(shasum -a 256 < "$KOTO_STORE/cache/opened.json" | cut -d' ' -f1); fi
    c="$KOTO_STORE/cache/$h.json"
    mv "$KOTO_STORE/cache/opened.json" "$c"
    jq -c --arg h "$h" --arg d "$(dirname "$2")" --arg n "$(basename "$2")" --arg c "$c" '
        if .type == null then .template_hash = $h | .template_source_dir = $d | .template_source_file = $n
        elif .type == "workflow_initialized" then .payload.template_path = $c
        else . end' "$f" > "$f.new" && mv "$f.new" "$f"
    printf '%s\n' "$h"
}
log_end() { # log_end <session>: cancel the run, so coord-log.sh live-session skips it
    log_ev "$1" workflow_cancelled '{}'
}
roadmap_vars() { jq -nc --arg p "$PLUGIN_ROOT_REAL" --arg n "$1" '{SCOPE: "roadmap", ROADMAP: "docs/roadmaps/ROADMAP-\($n).md", DISCIPLINE: "", HOST_REPO: "acme/widgets", PLUGIN_ROOT: $p}'; }
discipline_vars() { jq -nc --arg p "$PLUGIN_ROOT_REAL" --arg n "$1" '{SCOPE: "discipline", ROADMAP: "", DISCIPLINE: $n, HOST_REPO: "acme/widgets", PLUGIN_ROOT: $p}'; }

# found_session <session> <vars-json> [template-hash]: a run whose
# record_find captured a sealed `found` (its own session holds the record), so
# run-facts has a record. The session's record itself is the suite's to seed
# (seed_session).
found_session() {
    log_new "$1" "$2" "${3:-feedface}"
    log_to "$1" start_posture record_find 2026-09-26T08:01:00.000Z
    log_capture "$1" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$1" --state record_find --token found)" 2026-09-26T08:01:00.000Z
    log_to "$1" record_find reconcile 2026-09-26T08:01:00.000Z
}
