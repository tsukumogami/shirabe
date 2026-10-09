#!/usr/bin/env bash
# teardown-pass_test.sh -- the pass's own checks on the fields it builds
# commands from.
#
# A sealed verdict can't carry a bad instance name: teardown-handoff.sh
# refuses one when it seals (teardown-pass_engine_test.sh covers that). The
# pass still checks every field it builds a command from, so a verdict that
# somehow carried one would stop there. This feeds such verdicts straight to
# `teardown-pass.sh run` through a stand-in for `teardown-handoff.sh read`,
# and asserts each is refused before any niwa, claude or gh command runs.
#
# It also runs whole passes over a stand-in instance, job and workspace, with
# the real unit-cost.sh and stand-ins for the record scripts it calls, to pin
# the cost capture's place and its guard: the capture's comment POST comes
# before `niwa destroy`; and a crashing capture, a gh that hangs past every
# read's and the post's deadline, a failing post, and a capture hung past the
# pass's own capture deadline each leave the exit code, the last line and
# RESULT as a capturing pass leaves them, add exactly one warning line on
# stderr, and leave no capture process running.
#
# Usage: bash skills/coordinate/scripts/teardown-pass_test.sh
# Exit codes: 0 all pass; 1 a failure. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-pass-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

# The plugin tree: the pass and its library, with a stand-in reader that
# prints whatever verdict the case put in $T/verdict.
S="$T/plugin/skills/coordinate/scripts"
mkdir -p "$S" "$T/bin" "$T/ws/.niwa"
cp "$HERE/teardown-pass.sh" "$HERE/dispatch-common.sh" "$S/"
cat >"$S/teardown-handoff.sh" <<'EOF'
#!/usr/bin/env bash
cat "$VERDICT_FILE"
EOF
# Every tool the pass could run past its checks logs and fails.
for tool in niwa claude gh koto; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit 97\n' "$tool" "$T" >"$T/bin/$tool"
done
chmod +x "$S"/*.sh "$T/bin"/*
: >"$T/ws/.niwa/workspace.toml"
: >"$T/ws/.niwa/instance.json"
export VERDICT_FILE="$T/verdict" PATH="$T/bin:$PATH" HOME="$T/home"
mkdir -p "$HOME"

KS=keyseal:7:0000000000000000000000000000000000000000000000000000000000000000
# verdict <name> <path> <job> <session>: a ready verdict with those fields.
verdict() {
    printf 'topic w5\ninstance %s %s\njob %s %s\ntranscript /t/x.jsonl\npr acme/widgets#600 %s\nhandoff https://github.com/acme/widgets/pull/600#issuecomment-1\ninventory sealed:1:%s\nkeyseal %s\n' \
        "$1" "$2" "$3" "$4" 0123456789012345678901234567890123456789 "${KS#keyseal:7:}" "$KS" >"$VERDICT_FILE"
}
# refused <label> <reason>: the pass refuses the verdict with the reason and runs nothing.
refused() {
    : >"$T/calls"
    out=$(cd "$T/ws" && bash "$S/teardown-pass.sh" run --session s --keyseal "$KS" 2>&1)
    rc=$?
    [ "$rc" = 1 ] && ok "$1: refused" || bad "$1: refused" "exit $rc: $out"
    case "$out" in *"$2"*) ok "$1: says why" ;; *) bad "$1: says why" "$out" ;; esac
    [ -s "$T/calls" ] && bad "$1: no tool runs" "$(cat "$T/calls")" || ok "$1: no tool runs"
}

verdict --workspace /i/w5 4b3597d2 4b3597d2-6184-4a48
refused "an instance name that starts with a dash" "instance name is not a plain name"
verdict '' /i/w5 4b3597d2 4b3597d2-6184-4a48
refused "an empty instance name" "instance name is not a plain name"
verdict 'tsuku w5' /i/w5 4b3597d2 4b3597d2-6184-4a48
refused "a name holding a space, which splits the line into a relative path" "instance path is not absolute"
verdict tsuku+w5 relative/w5 4b3597d2 4b3597d2-6184-4a48
refused "a relative instance path" "instance path is not absolute"
verdict tsuku+w5 /i/w5 ';rm' 4b3597d2-6184-4a48
refused "a job id that isn't one" "job id is not a job id"
verdict tsuku+w5 /i/w5 4b3597d2 'x y'
refused "a session id that isn't one" "session id is not a session id"

# ---------------------------------------------------------------------------
# Whole passes, and the cost capture inside them.
#
# A second plugin tree with the real pass, dispatch-common.sh and
# unit-cost.sh; stand-ins for the verdict reader, the inventory and the record
# scripts the capture calls (run facts, the Holdings row, the entry list and
# the post, which goes through the stand-in gh). niwa, claude and gh log every
# call to one file, so the order of the POST and the destroy can be read.
export ST="$T/st"
mkdir -p "$ST"
P2="$T/plugin2/skills/coordinate/scripts"
B2="$T/bin2"
mkdir -p "$P2" "$B2"
cp "$HERE/teardown-pass.sh" "$HERE/dispatch-common.sh" "$HERE/unit-cost.sh" "$P2/"
cp "$S/teardown-handoff.sh" "$P2/"
printf '#!/usr/bin/env bash\nexit 0\n' >"$P2/teardown-inventory.sh"
cat >"$P2/coord-log.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = run-facts ] || exit 64
echo '{"scope":"roadmap","name":"x","repo":"acme/widgets","ref":"7"}'
EOF
cat >"$P2/record-holding.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"unit":"Feature 4: The example","worker":"w5"}'
EOF
cat >"$P2/record-append.sh" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" --list "*) echo '[]'; exit 0 ;;
esac
f=""
while [ $# -gt 0 ]; do [ "$1" = --text-file ] && f=$2; shift; done
cp "$f" "$ST/posted.txt"
gh api --method POST repos/acme/widgets/issues/7/comments --input "$f" --jq .html_url
EOF
cp "$P2/unit-cost.sh" "$T/unit-cost.real"
# A gh that hangs: it records its pid and becomes a sleep, so a deadline that
# stops it leaves nothing behind and a test can ask whether it is gone.
cat >"$B2/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$ST/log"
hang() { [ -f "$ST/hang" ] || return 0; echo $$ >>"$ST/pids"; exec sleep 30; }
case "$*" in
    "pr view 600 --repo acme/widgets --json state,mergeCommit")
        echo '{"state":"MERGED","mergeCommit":{"oid":"0123456789012345678901234567890123456789"}}' ;;
    "api repos/acme/widgets/issues/comments/1") echo '{"body":"handed off"}' ;;
    "pr view 600 --repo acme/widgets --json mergedAt") hang; echo '{"mergedAt":"2026-10-01T11:30:00Z"}' ;;
    "api --method POST "*)
        hang
        [ -f "$ST/post-fails" ] && { echo "HTTP 502" >&2; exit 1; }
        echo "https://github.com/acme/widgets/issues/7#issuecomment-5" ;;
    *) echo "gh stand-in: unexpected $*" >&2; exit 9 ;;
esac
EOF
cat >"$B2/niwa" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list) cat "$ST/niwa.json" ;;
    destroy) echo "niwa $*" >>"$ST/log"; echo '[]' >"$ST/niwa.json" ;;
    *) exit 64 ;;
esac
EOF
cat >"$B2/claude" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    agents) cat "$ST/agents.json" ;;
    rm) echo "claude $*" >>"$ST/log"; echo '[]' >"$ST/agents.json" ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$P2"/*.sh "$B2"/*

IP="$T/inst/w5"
SID=4b3597d2-6184-4a48
TR="$T/home/.claude/projects/p/$SID.jsonl"
export TEARDOWN_CLAUDE_HOME="$T/home/.claude" TEARDOWN_KOTO_SESSIONS="$T/ksess" TEARDOWN_ARCHIVE_DIR="$T/archive" \
    KOTO_REQUESTS="$T/requests" UNIT_COST_FETCH_SECS=1 UNIT_COST_LIST_SECS=2 UNIT_COST_POST_SECS=2
# setup_run: a fresh instance, job, transcript, worker session and request,
# both listings, an empty log, and the real unit-cost.sh.
setup_run() {
    rm -rf "$T/archive" "$T/ksess" "$T/requests" "$T/home/.claude" "$IP" "$ST"
    mkdir -p "$ST" "$IP" "$(dirname "$TR")" "$TEARDOWN_CLAUDE_HOME/jobs/4b3597d2" "$T/ksess/issue_7" "$T/requests/r_w5"
    : >"$ST/log"
    : >"$ST/pids"
    printf '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":1,"output_tokens":7}}}\n' >"$TR"
    printf '{"createdAt":"2026-10-01T09:00:00.000Z","sessionId":"%s"}\n' "$SID" >"$TEARDOWN_CLAUDE_HOME/jobs/4b3597d2/state.json"
    jq -nc --arg e "$IP" '{schema_version: 1, workflow: "issue_7", template_name: "work-on", template_source_file: "work-on.md", execution_dir: $e}' \
        >"$T/ksess/issue_7/koto-issue_7.state.jsonl"
    printf '{"seq":1,"timestamp":"2026-10-01T09:00:01.000Z","type":"evidence_submitted","payload":{"state":"entry","fields":{"mode":"issue_backed"}}}\n' \
        >>"$T/ksess/issue_7/koto-issue_7.state.jsonl"
    printf 'request_id = "r_w5"\n' >"$T/ksess/issue_7/request-leg.toml"
    printf '{"created_at":"2026-10-01T08:59:00.000Z","requested_by":"coordinator"}\n' >"$T/requests/r_w5/request.jsonl"
    jq -nc --arg p "$IP" '[{name: "tsuku+w5", path: $p}]' >"$ST/niwa.json"
    jq -nc --arg p "$IP" --arg s "$SID" '[{id: "4b3597d2", cwd: $p, sessionId: $s, state: "done"}]' >"$ST/agents.json"
    printf 'topic w5\ninstance tsuku+w5 %s\njob 4b3597d2 %s\ntranscript %s\npr acme/widgets#600 0123456789012345678901234567890123456789\nhandoff https://github.com/acme/widgets/pull/600#issuecomment-1\nkeyseal %s\n' \
        "$IP" "$SID" "$TR" "$KS" >"$VERDICT_FILE"
    cp "$T/unit-cost.real" "$P2/unit-cost.sh"
}
# run_pass: one pass; RC, OUT (stdout), ERR (stderr), LAST, ARCHD, RES.
run_pass() {
    OUT=$(cd "$T/ws" && PATH="$B2:$PATH" bash "$P2/teardown-pass.sh" run --session s --keyseal "$KS" 2>"$ST/err")
    RC=$?
    ERR=$(cat "$ST/err")
    LAST=$(printf '%s\n' "$OUT" | tail -n 1)
    ARCHD=$(ls -d "$T/archive"/*-w5-4b3597d2 2>/dev/null | head -n 1)
    RES=$(cut -d' ' -f1 "$ARCHD/RESULT" 2>/dev/null)
}
line_of() { grep -n -- "$1" "$ST/log" | head -n 1 | cut -d: -f1; }
# unchanged <label>: the pass ended as a capturing pass ends, with one warning.
unchanged() {
    [ "$RC" = 0 ] && ok "$1: exit 0" || bad "$1: exit 0" "exit $RC: $OUT $ERR"
    [ "$LAST" = "$BASE_LAST" ] && ok "$1: the same last line" || bad "$1: the same last line" "[$LAST] vs [$BASE_LAST]"
    [ "$RES" = "done" ] && ok "$1: RESULT says done" || bad "$1: RESULT says done" "$RES"
    [ -n "$(line_of 'niwa destroy')" ] && ok "$1: the instance is destroyed" || bad "$1: the instance is destroyed" "$(cat "$ST/log")"
    n=$(printf '%s\n' "$ERR" | grep -c .)
    w=$(printf '%s\n' "$ERR" | grep -c '^teardown-pass: capture: no cost entry (status [0-9]*): ')
    [ "$n" = 1 ] && [ "$w" = 1 ] && ok "$1: exactly one warning line" || bad "$1: exactly one warning line" "$ERR"
    # A TERM is delivered, not awaited: give a stopped process a moment to go.
    tries=0
    while :; do
        left=""
        for p in $(cat "$ST/pids"); do kill -0 "$p" 2>/dev/null && left="$left $p"; done
        [ -z "$left" ] || [ "$tries" -ge 20 ] && break
        tries=$((tries + 1))
        sleep 0.1
    done
    if [ -z "$left" ]; then
        ok "$1: no capture process left running"
    else
        bad "$1: no capture process left running" "$left"
        for p in $left; do kill "$p" 2>/dev/null; done
    fi
}

echo "== a pass with the cost capture =="
setup_run
run_pass
BASE_LAST="teardown-pass: done $ARCHD"
[ "$RC" = 0 ] && [ "$LAST" = "$BASE_LAST" ] && [ "$RES" = "done" ] && ok "the pass is done" || bad "the pass is done" "exit $RC: $OUT $ERR"
[ -z "$ERR" ] && ok "a capture that posts prints no warning" || bad "a capture that posts prints no warning" "$ERR"
POST=$(line_of 'gh api --method POST repos/acme/widgets/issues/7/comments')
DESTROY=$(line_of 'niwa destroy --force tsuku+w5')
[ -n "$POST" ] && [ -n "$DESTROY" ] && [ "$POST" -lt "$DESTROY" ] && ok "the comment POST comes before niwa destroy" \
    || bad "the comment POST comes before niwa destroy" "$(cat "$ST/log")"
eq_() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want [$2], got [$3]"; }
eq_ "the archive keeps unit-cost.json, keyed by its name" "unit-cost/1 ${ARCHD##*/} issue" \
    "$(jq -r '"\(.schema) \(.key) \(.plan_shape.value)"' "$ARCHD/unit-cost.json" 2>&1)"
grep -qxF '`unit-cost.json`, when present, is the cost capture'"'"'s derived summary and is not in the MANIFEST.' "$ARCHD/README.md" \
    && ok "the README says what unit-cost.json is" || bad "the README says what unit-cost.json is" "$(cat "$ARCHD/README.md")"
grep -q 'unit-cost.json' "$ARCHD/MANIFEST" && bad "unit-cost.json is not in the MANIFEST" || ok "unit-cost.json is not in the MANIFEST"
eq_ "the posted text opens with the summary line" "Cost of w5 (${ARCHD##*/}): 1 sessions, 7 output tokens, dispatch to merge not recoverable." \
    "$(head -n 1 "$ST/posted.txt")"

echo "== a crashing capture =="
setup_run
printf '#!/usr/bin/env bash\necho "unit-cost: crashed" >&2\nexit 3\n' >"$P2/unit-cost.sh"
run_pass
unchanged "a crashing capture"
case "$ERR" in *"(status 3): unit-cost: crashed"*) ok "  ... the warning names its status and last line" ;; *) bad "  ... the warning names its status and last line" "$ERR" ;; esac

echo "== a gh that hangs =="
setup_run
: >"$ST/hang"
START=$(date +%s)
run_pass
unchanged "a gh hung past every deadline"
[ $(($(date +%s) - START)) -lt 20 ] && ok "  ... the pass returns within the deadlines" || bad "  ... the pass returns within the deadlines" "$(($(date +%s) - START))s"
[ -s "$ST/pids" ] && ok "  ... the hung gh did run" || bad "  ... the hung gh did run" "$(cat "$ST/log")"

echo "== a failing post =="
setup_run
: >"$ST/post-fails"
run_pass
unchanged "a failing post"
[ -n "$(line_of 'gh api --method POST')" ] && ok "  ... the post was tried" || bad "  ... the post was tried" "$(cat "$ST/log")"

echo "== a capture past the pass's capture deadline =="
setup_run
printf '#!/usr/bin/env bash\necho $$ >>"$ST/pids"\nexec sleep 30\n' >"$P2/unit-cost.sh"
START=$(date +%s)
TEARDOWN_CAPTURE_SECS=2 run_pass
unchanged "a capture past the deadline"
case "$ERR" in *"(status 124)"*) ok "  ... the warning names the deadline" ;; *) bad "  ... the warning names the deadline" "$ERR" ;; esac
[ $(($(date +%s) - START)) -lt 15 ] && ok "  ... the pass returns at the deadline" || bad "  ... the pass returns at the deadline" "$(($(date +%s) - START))s"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
