# doc-check-testlib.sh -- the stand-ins and fixtures doc-check_test.sh and
# doc-events_test.sh share. Sourced by a suite, never run.
#
# dct_setup <workdir>   isolates HOME and git, writes a stub `shirabe` and a
#                       stub koto under <workdir>, and exports KOTO_BIN and
#                       STUB_* for them
# dct_repo <name>       a fresh repository in $REPO with one commit and a
#                       Public visibility header; the stub koto's store is
#                       emptied
# dct_session <name>    makes <name> a live session in the stub koto's store
# dct_key <session> <key>   prints a stored key's bytes
# dct_put <session> <key>   stores stdin under a key, byte for byte
# dct_commit <message>  commits every change in $REPO
# dct_head              HEAD's commit id in $REPO
#
# The stub shirabe answers the canary (canary.md) with a banned-word notice
# unless STUB_CANARY=none, and every other call with the contents of $STUB_JSON
# and the exit code $STUB_RC; it logs each call's arguments to $STUB_LOG.
#
# The stub koto keeps sessions as directories under $STUB_KOTO_DIR/s. It
# answers `status`, `context exists|get|add` and `review record`: a review call
# is logged to $STUB_KOTO_DIR/review.log as its arguments, then `file:` and
# the --file contents. STUB_KOTO_REVIEW=missing answers like a koto with no
# `review` verb, `refuse` refuses every call; a review call on a session that
# doesn't exist is refused too.

dct_setup() {
    DCT_DIR=$1
    export HOME="$DCT_DIR/home"
    mkdir -p "$HOME" "$DCT_DIR/stub-bin" "$DCT_DIR/koto"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CEILING_DIRECTORIES="$DCT_DIR"
    git config --global user.email t@example.invalid
    git config --global user.name t
    git config --global init.defaultBranch main

    cat > "$DCT_DIR/stub-bin/shirabe" <<'STUB'
#!/usr/bin/env bash
if [ "${1-}" = --version ]; then echo "shirabe stub"; exit 0; fi
printf '%s\n' "$*" >> "${STUB_LOG:-/dev/null}"
last=""
for a in "$@"; do last=$a; done
if [ "$last" = canary.md ]; then
    if [ "${STUB_CANARY:-ok}" = ok ]; then
        printf '%s\n' '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean","errors":0,"notices":1},"findings":[{"code":"FC10","severity":"notice","message":"[FC10] writing-style banned word \"tier\" -- see skills/writing-style/rules.yaml","file":"canary.md","line":1}]}'
    else
        printf '%s\n' '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean","errors":0,"notices":0},"findings":[]}'
    fi
    exit 0
fi
cat "$STUB_JSON"
exit "${STUB_RC:-0}"
STUB
    chmod +x "$DCT_DIR/stub-bin/shirabe"

    cat > "$DCT_DIR/stub-koto" <<'STUB'
#!/usr/bin/env bash
d=${STUB_KOTO_DIR:?}
keyfile() { printf '%s/s/%s/%s' "$d" "$1" "$(printf '%s' "$2" | tr '/' '_')"; }
cmd=${1-}
shift
case "$cmd" in
    status)
        if [ -d "$d/s/$1" ]; then echo '{"is_terminal":false}'; exit 0; fi
        echo "{\"error\":\"workflow '$1' not found\"}"
        exit 2 ;;
    context)
        sub=$1; s=$2; k=$3; f=$(keyfile "$s" "$k")
        case "$sub" in
            exists) [ -f "$f" ] ;;
            get) [ -f "$f" ] && cat "$f" ;;
            add)
                [ -d "$d/s/$s" ] || exit 2
                if [ "${4-}" = --from-file ]; then cp "$5" "$f"; else cat > "$f"; fi ;;
            *) exit 2 ;;
        esac ;;
    review)
        case "${STUB_KOTO_REVIEW:-ok}" in
            missing) echo "error: unrecognized subcommand 'review'" >&2; exit 2 ;;
            refuse) exit 1 ;;
        esac
        [ "${1-}" = record ] || exit 2
        shift
        [ -d "$d/s/${2-}" ] || exit 1
        printf '%s\n' "$*" >> "$d/review.log"
        prev=""
        for a in "$@"; do
            if [ "$prev" = --file ]; then { printf 'file:'; tr -d '\n' < "$a"; echo; } >> "$d/review.log"; fi
            prev=$a
        done ;;
    *) exit 2 ;;
esac
STUB
    chmod +x "$DCT_DIR/stub-koto"
    export KOTO_BIN="$DCT_DIR/stub-koto"
    export STUB_KOTO_DIR="$DCT_DIR/koto"
    export STUB_LOG="$DCT_DIR/stub.log"
    export STUB_JSON="$DCT_DIR/stub.json"
    export STUB_RC=0
    DCT_ORIG_PATH=$PATH
    export PATH="$DCT_DIR/stub-bin:$PATH"
}

REPO=""
DCT_N=0
dct_repo() {
    DCT_N=$((DCT_N + 1))
    REPO="$DCT_DIR/fx-$DCT_N-$1"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    printf '# repo\n\n## Repo Visibility: Public\n' > "$REPO/CLAUDE.md"
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm "chore: seed the repository"
    rm -rf "$STUB_KOTO_DIR"
    mkdir -p "$STUB_KOTO_DIR/s"
    : > "$STUB_KOTO_DIR/review.log"
    : > "$STUB_LOG"
}

dct_session() { mkdir -p "$STUB_KOTO_DIR/s/$1"; }
dct_key() { cat "$STUB_KOTO_DIR/s/$1/$(printf '%s' "$2" | tr '/' '_')" 2>/dev/null; }
dct_put() { cat > "$STUB_KOTO_DIR/s/$1/$(printf '%s' "$2" | tr '/' '_')"; }
dct_commit() { git -C "$REPO" add -A && git -C "$REPO" commit -qm "$1"; }
dct_head() { git -C "$REPO" rev-parse HEAD; }

# dct_envelope <rc> [<finding json>...]: the stub's next answer.
dct_envelope() {
    local rc=$1 outcome=clean
    shift
    [ "$rc" -eq 0 ] || outcome=violations
    jq -cn --arg o "$outcome" '{schema_version: "shirabe-validate/v1", summary: {outcome: $o}, findings: [$ARGS.positional[] | fromjson]}' \
        --args "$@" > "$STUB_JSON"
    STUB_RC=$rc
}
