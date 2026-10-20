#!/usr/bin/env bash
# teardown-handoff_test.sh -- the handoff seal's refusals for a stopped unit.
#
# Runs `teardown-handoff.sh --seal` in a plugin tree whose inventory reader
# (teardown-verdict.sh) is a stand-in printing a durable verdict, with the
# koto stand-in (testdata/koto) holding teardown_topic, a coord-log.sh
# stand-in for the seals and the teardown evidence, and stand-ins for
# record-holding.sh, niwa, claude and gh. A durable, merged, handed-off
# worker seals a ready verdict naming its instance, job, transcript, pull
# request, handoff and dispatch id. Each refusal seals `refused` with its
# reason, prints `handoff-refused`, and runs nothing but the listings: a
# pull request merged only from a fork's branch of the same name; no handoff
# link; a handoff on another unit's pull request; a handoff comment that
# doesn't exist; a job still working; two jobs in the instance; a job whose
# state is missing or not known to be finished; and an instance name that
# isn't a plain name.
#
# teardown-pass_engine_test.sh keeps one refusal (an unmerged pull request)
# to prove the refused arm reaches surface in real koto, and drives the
# removed mode.
#
# Usage: bash skills/coordinate/scripts/teardown-handoff_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs jq. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-handoff-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */teardown-handoff-test.*) rm -rf "$T" ;; esac' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$2]" ;; esac; }

# --- the plugin tree and its stand-ins --------------------------------------------------------

S="$T/plugin/skills/coordinate/scripts"
BIN="$T/bin"
mkdir -p "$S" "$BIN"
cp "$HERE/teardown-handoff.sh" "$HERE/dispatch-common.sh" "$S/"

# teardown-verdict.sh read: the sealed inventory, durable, for the instance.
cat >"$S/teardown-verdict.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = read ] || exit 64
cat "$ST/inventory"
EOF
# coord-log.sh: a file seal stores the file under ctx/<key> and prints a
# token over it; a token seal is logged and printed back sealed; the
# inventory's capture is a sealed token; the latest entry into teardown and
# the evidence there come from $ST/teardown-ev.
cat >"$S/coord-log.sh" <<'EOF'
#!/usr/bin/env bash
sha() { if command -v sha256sum >/dev/null; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
cmd="$1"; shift
A_file="" A_key="" A_token="" A_state="" A_after=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--name|--where) shift 2 ;;
        --key) A_key=$2; shift 2 ;;
        --state) A_state=$2; shift 2 ;;
        --file) A_file=$2; shift 2 ;;
        --token) A_token=$2; shift 2 ;;
        --after) A_after=$2; shift 2 ;;
        *) exit 64 ;;
    esac
done
case "$cmd" in
    seal)
        if [ -n "$A_file" ]; then
            cp "$A_file" "$ST/ctx/$A_key"
            printf 'sealed:7:%s\n' "$(sha <"$A_file")"
        else
            printf '%s\n' "$A_token" >>"$ST/tokens"
            printf '%s sealed:8:%064d\n' "$A_token" 0
        fi ;;
    capture) printf 'sealed:6:%064d\n' 0 ;;
    entry) [ "$A_state" = teardown ] || exit 1; echo "4 wait" ;;
    evidence)
        [ "$A_state" = teardown ] && [ "$A_after" = 4 ] || exit 64
        printf '{"seq":5,"timestamp":"t","fields":%s}\n' "$(cat "$ST/teardown-ev")" ;;
    *) exit 64 ;;
esac
EOF
# record-holding.sh --read: the holding's row.
cat >"$S/record-holding.sh" <<'EOF'
#!/usr/bin/env bash
cat "$ST/row.json"
EOF
# niwa list and claude agents read their listings; any other call is logged.
cat >"$BIN/niwa" <<'EOF'
#!/usr/bin/env bash
[ "$1" = list ] && { cat "$ST/niwa.json"; exit 0; }
printf 'niwa %s\n' "$*" >>"$ST/calls"; exit 64
EOF
cat >"$BIN/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1" = agents ] && { cat "$ST/agents.json"; exit 0; }
printf 'claude %s\n' "$*" >>"$ST/calls"; exit 64
EOF
# gh: merged pull requests by branch, and a comment by id.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "pr list" ]; then cat "$ST/merged.json"; exit 0; fi
case "$1 ${2-}" in
    "api repos/"*/issues/comments/*)
        f="$ST/comment-${2##*/}.json"
        [ -f "$f" ] && { cat "$f"; exit 0; }
        echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
printf 'gh %s\n' "$*" >>"$ST/calls"; exit 64
EOF
chmod +x "$S"/*.sh "$BIN"/*

W="$T/ws"
mkdir -p "$W/.niwa"
: >"$W/.niwa/workspace.toml"
: >"$W/.niwa/instance.json"
export KOTO_STORE="$T/koto" KOTO="$HERE/testdata/koto" NIWA="$BIN/niwa" CLAUDE_CLI="$BIN/claude" GH="$BIN/gh"
export TEARDOWN_CLAUDE_HOME="$T/claude" HOME="$T/home"
mkdir -p "$KOTO_STORE/context/coord" "$HOME"

# --- the worker w5 ----------------------------------------------------------------------------

INST="$W/tsuku+w5"
JOB=4b3597d2
SID=4b3597d2-6184-4a48-ab7f-802b6a29
TR="$TEARDOWN_CLAUDE_HOME/projects/$(printf '%s' "$INST" | sed 's/[^A-Za-z0-9]/-/g')/$SID.jsonl"
URL="https://github.com/acme/widgets/pull/600#issuecomment-1001"
MERGE=0123456789abcdef0123456789abcdef01234567
mkdir -p "$(dirname "$TR")"
printf '{"type":"user"}\n' >"$TR"
printf 'w5' >"$KOTO_STORE/context/coord/teardown_topic"
N=0
# fixture [state]: a durable, merged, handed-off w5 whose job is in that state
# (done unless given), in a fresh state directory.
fixture() {
    N=$((N + 1))
    export ST="$T/state-$N"
    mkdir -p "$ST/ctx"
    printf 'durable\ninstance %s\ntopic w5\n' "$INST" >"$ST/inventory"
    printf '{"teardown":"stopped","handoff":"%s"}' "$URL" >"$ST/teardown-ev"
    printf '{"worker":"w5","unit":"#591","repo":"acme/widgets","branch":"feat/w5"}\n' >"$ST/row.json"
    printf '[{"name":"tsuku+w5","path":"%s","session_name":"w5-1a2b3c4d","dispatch_id":"dsp-01"}]\n' "$INST" >"$ST/niwa.json"
    printf '[{"id":"%s","cwd":"%s","sessionId":"%s","name":"w5-1a2b3c4d","state":"%s"}]\n' "$JOB" "$INST" "$SID" "${1:-done}" >"$ST/agents.json"
    printf '[{"number":600,"mergeCommit":{"oid":"%s"},"headRepositoryOwner":{"login":"acme"}}]\n' "$MERGE" >"$ST/merged.json"
    printf '{"issue_url":"https://api.github.com/repos/acme/widgets/issues/600","body":"what only the worker knew"}\n' >"$ST/comment-1001.json"
    printf '{"issue_url":"https://api.github.com/repos/acme/widgets/issues/599","body":"another unit"}\n' >"$ST/comment-1002.json"
    : >"$ST/calls"
}
seal() { (cd "$W" && bash "$S/teardown-handoff.sh" --seal --session coord 2>"$T/seal.err"); }
verdict() { cat "$ST/ctx/teardown_handoff" 2>/dev/null; }
# refused <label> <reason>: the seal refuses with the reason, sealed, running
# nothing beyond the listings and reads.
refused() {
    local out rc
    out=$(seal); rc=$?
    eq  "$1: exit 0" 0 "$rc"
    case "$out" in "handoff-refused sealed:"*) ok "$1: prints handoff-refused" ;; *) bad "$1: prints handoff-refused" "$out $(cat "$T/seal.err")" ;; esac
    eq  "$1: the verdict is refused" refused "$(verdict | sed -n 1p)"
    has "$1: the verdict says why" "$(verdict | sed -n 2p)" "$2"
    eq  "$1: nothing else ran" "" "$(cat "$ST/calls")"
}

# --- ready: the control the refusals are measured against --------------------------------------

fixture
OUT=$(seal); RC=$?
eq  "ready: exit 0" 0 "$RC"
case "$OUT" in "handoff-ready keyseal:7:"*) ok "ready: prints handoff-ready with the verdict's key seal" ;; *) bad "ready: prints handoff-ready with the verdict's key seal" "$OUT $(cat "$T/seal.err")" ;; esac
eq  "ready: the verdict names the topic, instance, job, transcript, pull request, handoff, dispatch id and inventory" \
    "ready|topic w5|instance tsuku+w5 $INST|job $JOB $SID|transcript $TR|pr acme/widgets#600 $MERGE|handoff $URL|dispatch dsp-01|inventory sealed:6:$(printf '%064d' 0)" \
    "$(verdict | tr '\n' '|' | sed 's/|$//')"
eq  "ready: nothing else ran" "" "$(cat "$ST/calls")"

# --- refusals --------------------------------------------------------------------------------

fixture
printf '[{"number":601,"mergeCommit":{"oid":"%s"},"headRepositoryOwner":{"login":"someone"}}]\n' "$MERGE" >"$ST/merged.json"
refused "a merged pull request from a fork's branch of the same name" "no pull request from feat/w5 in acme/widgets is merged"

fixture
printf '{"teardown":"stopped"}' >"$ST/teardown-ev"
refused "no handoff link" "no handoff link"

fixture
printf '{"teardown":"stopped","handoff":"https://github.com/acme/widgets/pull/599#issuecomment-1002"}' >"$ST/teardown-ev"
refused "a handoff on another unit's pull request" "neither a merged pull request of the unit nor its issue"

fixture
printf '{"teardown":"stopped","handoff":"https://github.com/acme/widgets/pull/600#issuecomment-9999"}' >"$ST/teardown-ev"
refused "a handoff comment that doesn't exist" "doesn't exist"

fixture working
refused "a job still working" "still working"

fixture
jq -c '. + [.[0] | .id = "9c9c9c9c" | .sessionId = "9c9c9c9c-0000-4000-8000-00000000"]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"
refused "two jobs in the instance" "$JOB, 9c9c9c9c"

# Only a state known to be finished passes: a missing state, or one the
# script doesn't know, is treated as possibly running.
fixture
jq -c '[.[] | del(.state)]' "$ST/agents.json" >"$ST/a.tmp" && mv "$ST/a.tmp" "$ST/agents.json"
refused "a job whose state is missing" "isn't known to be finished"
fixture waiting
refused "a job whose state is waiting" "isn't known to be finished"

# An instance name niwa lists that isn't a plain name never reaches a command.
fixture
jq -c '[.[] | .name = "--workspace"]' "$ST/niwa.json" >"$ST/n.tmp" && mv "$ST/n.tmp" "$ST/niwa.json"
refused "an instance name that isn't a plain name" "not a plain instance name"

printf '\nteardown-handoff: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
