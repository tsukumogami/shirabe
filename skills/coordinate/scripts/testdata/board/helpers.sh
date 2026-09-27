# helpers.sh -- shared by the board, land and merge tests. Sourced after the
# test sets HERE (the scripts directory) and T (its temporary directory).
#
# bt_setup: a localized plugin tree at $T/plugin holding copies of the scripts
# under test, coord-log.sh and the record codec, with stand-ins for
# posture-read.sh and record-holding.sh beside them (so no test depends on the
# real ones, and no script needs an override to find them); gh-board as `gh`
# on PATH; the koto stand-in as KOTO_BIN.
# bt_materialize <case.json> <dir>: gh-board response files from one case.
# bt_session / bt_enter / bt_evidence / bt_capture / bt_sealed: hand-written
# session logs in the koto stand-in's store.
TD="$HERE/testdata"
H=0123456789abcdef0123456789abcdef01234567
MOVED=1111111111111111111111111111111111111111
HASH=feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface

bt_setup() {
    local f S="$T/plugin/skills/coordinate/scripts"
    mkdir -p "$S" "$T/plugin/skills/coordinate/koto-templates" "$T/bin" "$T/koto/sessions" "$T/koto/cache" "$T/state"
    for f in board-lib.sh board-verdict.sh board-record.sh land-check.sh land-merge.sh merge-confirm.sh \
             merged-facts.sh coord-log.sh record-parse.sh record-render.sh record-codec.jq; do
        cp "$HERE/$f" "$S/$f"
    done
    cp "$TD/board/stand-in-posture-read.sh" "$S/posture-read.sh"
    cp "$TD/board/stand-in-record-holding.sh" "$S/record-holding.sh"
    : > "$T/plugin/skills/coordinate/koto-templates/coordinate.md"
    ln -sf "$TD/gh-board" "$T/bin/gh"
    PATH="$T/bin:$PATH"
    PS="$S"
    export PATH KOTO_BIN="$TD/board/koto" KOTO_BOARD_DIR="$T/koto" KOTO_BOARD_HASH="$HASH" BT_STATE="$T/state"
    export GH_BOARD_DIR="$T/gh"
    mkdir -p "$GH_BOARD_DIR"
}

# bt_case <name>: the case's board JSON from base.jq and cases/<name>.jq.
bt_case() {
    jq -n -L "$TD/board" -f "$TD/board/base.jq" | jq -L "$TD/board" -f "$TD/board/cases/$1.jq"
}

bt_materialize() {
    local f=$1 d=$2 k n i suffix
    rm -rf "$d"; mkdir -p "$d"
    for k in $(jq -r 'keys[] | select(startswith("__") | not)' "$f"); do
        n=$(jq -r --arg k "$k" '.[$k] | if type == "object" and has("__seq") then (.__seq | length) else 1 end' "$f")
        i=1
        while [ "$i" -le "$n" ]; do
            suffix=; [ "$i" -gt 1 ] && suffix=".$i"
            jq -c --arg k "$k" --argjson i $((i - 1)) '.[$k]
                | (if type == "object" and has("__seq") then .__seq[$i] else . end)
                | if type == "object" and has("__pages") then .__pages[] else . end' "$f" > "$d/$k.out$suffix"
            i=$((i + 1))
        done
    done
    for k in rc err sleep; do
        jq -r --arg k "__$k" '(.[$k] // {}) | to_entries[] | "\(.key)\t\(.value)"' "$f" | while IFS='	' read -r key val; do
            printf '%s\n' "$val" > "$d/$key.$k"
        done
    done
}

# bt_board <name>: materialize a case into $GH_BOARD_DIR.
bt_board() { bt_case "$1" > "$T/case.json" && bt_materialize "$T/case.json" "$GH_BOARD_DIR"; }

bt_logf() { printf '%s\n' "$KOTO_BOARD_DIR/sessions/$1/koto-$1.state.jsonl"; }
bt_append() { # bt_append <S> <type> <payload-json>
    local f seq
    f=$(bt_logf "$1")
    seq=$(wc -l < "$f" | tr -d ' ')
    jq -nc --argjson s "$seq" --arg t "$2" --argjson p "$3" \
        '{seq: $s, timestamp: "2026-09-26T12:00:00.000Z", type: $t, payload: $p}' >> "$f"
}
# bt_session <S> [plugin-root] [hash] [host] [scope]
bt_session() {
    local s=$1 root=${2:-$T/plugin} hash=${3:-$HASH} host=${4:-acme/widgets} scope=${5:-roadmap}
    mkdir -p "$KOTO_BOARD_DIR/sessions/$s"
    jq -nc --arg w "$s" --arg h "$hash" '{schema_version: 1, workflow: $w, template_hash: $h, created_at: "2026-09-26T10:00:00.000Z"}' > "$(bt_logf "$s")"
    bt_append "$s" workflow_initialized "$(jq -nc --arg r "$root" --arg host "$host" --arg sc "$scope" \
        '{template_path: "x", variables: {PLUGIN_ROOT: $r, SCOPE: $sc, ROADMAP: "docs/roadmaps/ROADMAP-demo.md", DISCIPLINE: "", HOST_REPO: $host}}')"
}
bt_enter() { bt_append "$1" "${3:-transitioned}" "$(jq -nc --arg t "$2" '{from: "x", to: $t, condition_type: "auto"}')"; }
bt_evidence() { bt_append "$1" evidence_submitted "$(jq -nc --arg s "$2" --argjson f "$3" '{state: $s, fields: $f}')"; }
bt_capture() { bt_append "$1" variable_captured "$(jq -nc --arg k "$2" --arg v "$3" '{key: $k, value: $v}')"; }
# bt_sealed <S> <state> <NAME> <token>: a capture sealed to the latest entry into <state>.
bt_sealed() {
    local v
    v=$(bash "$PS/coord-log.sh" seal --session "$1" --state "$2" --token "$4") || return 1
    bt_capture "$1" "$3" "$v"
}

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
