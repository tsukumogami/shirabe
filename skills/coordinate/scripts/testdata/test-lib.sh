# test-lib.sh -- shared setup for /coordinate's record script tests. Sourced by
# a *_test.sh after it sets HERE (the scripts directory). Not shipped behaviour.
#
# It makes a scratch directory, puts the gh and koto stand-ins first on PATH,
# and gives each test: a GitHub DB ($GH_DB) with helpers to seed and edit it,
# record bodies rendered by the real codec, and prepared koto session logs in
# the shape real koto writes.

T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
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
record_json() { # record_json <roadmap|discipline> <name>: an empty record
    jq -nc --arg k "$1" --arg n "$2" '{scope: {kind: $k, name: $n}, holdings: [], deferrals: [], side_effects: [], reversals: []}'
}
render() { # render <json> <issue|pr> [written]: a canonical body on stdout
    printf '%s' "$1" | bash "$HERE/record-render.sh" --container "$2" --written "${3:-2026-09-26T09:00:00Z}"
}

# Session logs. log_new <session> <vars-json> writes the header and init; each
# log_ev appends one event with the next seq.
log_new() {
    local d="$KOTO_STORE/sessions/$1"
    mkdir -p "$d"
    jq -nc --arg s "$1" --arg h "${3:-feedface}" '{schema_version: 1, workflow: $s, template_hash: $h,
        created_at: "2026-09-26T08:00:00.000Z", template_name: "coordinate"}' > "$d/koto-$1.state.jsonl"
    printf '0' > "$d/.seq"
    log_ev "$1" workflow_initialized "$(jq -nc --argjson v "$2" '{template_path: "x", variables: $v}')" 2026-09-26T08:00:00.000Z
    log_ev "$1" transitioned '{"from":null,"to":"start","condition_type":"auto"}' 2026-09-26T08:00:00.000Z
}
log_ev() { # log_ev <session> <type> <payload-json> [timestamp]
    local d="$KOTO_STORE/sessions/$1" n
    n=$(($(cat "$d/.seq") + 1))
    printf '%s' "$n" > "$d/.seq"
    jq -nc --argjson q "$n" --arg ts "${4:-2026-09-26T10:00:00.000Z}" --arg t "$2" --argjson p "$3" \
        '{seq: $q, timestamp: $ts, type: $t, payload: $p}' >> "$d/koto-$1.state.jsonl"
}
log_to() { # log_to <session> <from> <to> [timestamp]
    log_ev "$1" transitioned "$(jq -nc --arg f "$2" --arg t "$3" '{from: $f, to: $t, condition_type: "gate"}')" "${4:-2026-09-26T10:00:00.000Z}"
}
log_evidence() { # log_evidence <session> <state> <fields-json> [timestamp]
    log_ev "$1" evidence_submitted "$(jq -nc --arg s "$2" --argjson f "$3" '{state: $s, fields: $f}')" "${4:-2026-09-26T10:00:00.000Z}"
}
log_capture() { # log_capture <session> <key> <value> [timestamp]
    log_ev "$1" variable_captured "$(jq -nc --arg k "$2" --arg v "$3" '{key: $k, value: $v}')" "${4:-2026-09-26T10:00:00.000Z}"
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

# found_session <session> <vars-json> <ref> [template-hash]: a run whose
# record_find captured a sealed `found <ref>`, so run-facts has a record.
found_session() {
    log_new "$1" "$2" "${4:-feedface}"
    log_to "$1" start_posture record_find 2026-09-26T08:01:00.000Z
    log_capture "$1" RECORD_FIND "$(bash "$HERE/coord-log.sh" seal --session "$1" --state record_find --token "found $3")" 2026-09-26T08:01:00.000Z
    log_to "$1" record_find reconcile 2026-09-26T08:01:00.000Z
}
