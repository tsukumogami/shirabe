#!/usr/bin/env bash
# teardown-pass_test.sh -- the pass's own checks on the fields it builds
# commands from.
#
# A sealed verdict can't carry a bad instance name: teardown-handoff.sh
# refuses one when it seals (teardown-handoff_test.sh covers that). The
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
# And what the pass archives: the instance's own Claude Code project
# directory and a worktree's (the worker's main transcript, three subagent
# transcripts across the two, and a relocated copy repeating two of the
# worker's message ids) are copied whole into claude-projects/ and listed in
# the README; a sibling instance's directory sharing the name's prefix is not
# archived and is listed `cwd outside the instance`; a symbolic link is
# never followed and is listed; nothing is written to transcript/; a file
# that can't be copied refuses the pass before any destroy; an unreadable
# linked pull request leaves the pass done (credit never gates); and a
# capture whose credit reads hang still ends inside TEARDOWN_CAPTURE_SECS.
#
# And the remove step after niwa destroy took the job itself: `claude rm`
# printing No job matching for a job with no directory and no row ends the
# pass done, RESULT saying destroy already removed it; the same rm while the
# job's directory or its row is still there, or niwa still lists the
# instance, or any other rm failure, ends it incomplete at remove.
#
# And `confirm` over an archive of 3,000 files: it confirms inside its
# archive read's bound, reading sizes with a few wc runs rather than one
# process per file; a file cut short, gone or replaced by a link, a MANIFEST
# cut short or added to after the pass, a missing MANIFEST.sha256, a RESULT
# that isn't done, and either listing still naming the unit are each
# incomplete with the reason; a listing that fails is incomplete with its
# cause; a size read held past its deadline is incomplete at the deadline
# and leaves nothing running. A whole pass writes
# MANIFEST.sha256 with the MANIFEST's digest.
#
# And build trees in the job's tmp/: a cargo target dir under another name
# (CACHEDIR.TAG) holding a node_modules, a repo's target/ (.rustc_info.json),
# a node_modules holding another, a cargo home (.package-cache) and, with
# tmp/ itself marked as a target dir, a build profile directory at its top
# (.cargo-lock) are left out, each outermost tree listed once in SKIPPED and
# the README with its bytes, a link to one not followed; the scratch beside
# them and the near misses (a target/ with no marker, a CACHEDIR.TAG without
# the signature, a .rustc_info.json without rustc_fingerprint, a marker in
# tmp/ itself) are archived; SKIPPED is in the MANIFEST and confirm passes the archive. A
# tmp/ with no build tree writes no SKIPPED and no README line, archives
# every file in find's order, and confirms.
#
# Usage: bash skills/coordinate/scripts/teardown-pass_test.sh
# Exit codes: 0 all pass; 1 a failure. bash 3.2.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/teardown-pass-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */teardown-pass-test.*) rm -rf "$T" ;; esac'

PASS=0
FAIL=0
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

# The plugin tree: the pass and its libraries, with a stand-in reader that
# prints whatever verdict the case put in $T/verdict.
S="$T/plugin/skills/coordinate/scripts"
mkdir -p "$S" "$T/bin" "$T/ws/.niwa"
cp "$HERE/teardown-pass.sh" "$HERE/dispatch-common.sh" "$HERE/archive-common.sh" "$S/"
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
# Its own HOME and koto home, inside the scratch directory, so suites run
# side by side share no path.
export VERDICT_FILE="$T/verdict" PATH="$T/bin:$PATH" HOME="$T/home" KOTO_SESSIONS_BASE="$T/koto-home"
mkdir -p "$HOME" "$KOTO_SESSIONS_BASE"

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

# Removed mode's two forms, `instance - <path>` and `job -`, stand only beside
# `removed yes`, and beside it the instance name must be `-`.
verdict - /i/w5 4b3597d2 4b3597d2-6184-4a48
refused "instance - without removed yes" "instance name is not a plain name"
verdict tsuku+w5 /i/w5 4b3597d2 4b3597d2-6184-4a48
sed -i.bak 's/^job .*/job -/' "$VERDICT_FILE"
refused "job - without removed yes" "job id is not a job id"
verdict tsuku+w5 /i/w5 4b3597d2 4b3597d2-6184-4a48
printf 'removed yes\n' >>"$VERDICT_FILE"
refused "removed yes beside a named instance" "must be -"
verdict - relative/w5 4b3597d2 4b3597d2-6184-4a48
printf 'removed yes\n' >>"$VERDICT_FILE"
refused "removed yes with a relative path" "instance path is not absolute"
verdict - /i/w5 ';rm' 4b3597d2-6184-4a48
printf 'removed yes\n' >>"$VERDICT_FILE"
refused "removed yes with a job id that isn't one" "job id is not a job id"

# ---------------------------------------------------------------------------
# Whole passes, and the cost capture inside them.
#
# A second plugin tree with the real pass, its libraries and
# unit-cost.sh; stand-ins for the verdict reader, the inventory and the record
# scripts the capture calls (run facts, the Holdings row, the entry list and
# the post, which goes through the stand-in gh). niwa, claude and gh log every
# call to one file, so the order of the POST and the destroy can be read.
export ST="$T/st"
mkdir -p "$ST"
P2="$T/plugin2/skills/coordinate/scripts"
B2="$T/bin2"
mkdir -p "$P2" "$B2"
cp "$HERE/teardown-pass.sh" "$HERE/dispatch-common.sh" "$HERE/archive-common.sh" "$HERE/unit-cost.sh" "$P2/"
cp "$S/teardown-handoff.sh" "$P2/"
printf '#!/usr/bin/env bash\nexit 0\n' >"$P2/teardown-inventory.sh"
cat >"$P2/coord-log.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = run-facts ] || exit 64
echo '{"scope":"roadmap","name":"x","repo":"acme/widgets","ref":"7"}'
EOF
cat >"$P2/state-holding.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"unit":"Feature 4: The example","worker":"w5"}'
EOF
cat >"$P2/state-entry.sh" <<'EOF'
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
    "pr view 600 --repo acme/widgets --json mergedAt,headRefName") hang; echo '{"mergedAt":"2026-10-01T11:30:00Z","headRefName":"feat/w5"}' ;;
    "api --method GET repos/acme/widgets/pulls/600/commits --paginate") echo '[{"sha":"0123456789012345678901234567890123456789"}]' ;;
    "api --method GET repos/acme/widgets/actions/runs?head_sha=0123456789012345678901234567890123456789&per_page=100&page=1")
        echo '{"total_count":1,"workflow_runs":[{"id":7,"head_sha":"0123456789012345678901234567890123456789","run_attempt":1,"status":"completed","conclusion":"success","updated_at":"2026-10-01T11:00:00Z"}]}' ;;
    "api --method GET repos/acme/widgets --jq .private") echo false ;;
    "pr view 601 --repo acme/widgets --json state,createdAt,mergedAt,mergeCommit,headRefName,baseRefName,headRepositoryOwner")
        hang; echo "HTTP 502" >&2; exit 1 ;;
    "pr view 6"[0-9][0-9]" --repo acme/widgets --json state,createdAt,mergedAt,mergeCommit,headRefName,baseRefName,headRepositoryOwner")
        hang
        [ -f "$ST/slow" ] && { echo $$ >>"$ST/pids"; exec sleep 30; }
        echo '{"state":"MERGED","createdAt":"2026-10-01T10:00:00Z","mergedAt":"2026-10-01T10:30:00Z","mergeCommit":{"oid":"0123456789012345678901234567890123456789"},"headRefName":"feat/w5-b","baseRefName":"main","headRepositoryOwner":{"login":"acme"}}' ;;
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
    destroy)
        echo "niwa $*" >>"$ST/log"; echo '[]' >"$ST/niwa.json"
        # niwa 0.34.1 on: destroy removes the instance's owning job too, its
        # directory and its row; a case can leave the row behind.
        [ -f "$ST/destroy-takes-job" ] && [ ! -f "$ST/dir-stays" ] && rm -rf "$HOME/.claude/jobs/$JID"
        [ -f "$ST/destroy-takes-job" ] && [ ! -f "$ST/row-stays" ] && echo '[]' >"$ST/agents.json"
        # And a case can have the instance outlive its destroy: the
        # listing it saved there is put back.
        [ -f "$ST/instance-stays" ] && cp "$ST/instance-stays" "$ST/niwa.json"
        : ;;
    *) exit 64 ;;
esac
EOF
cat >"$B2/claude" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    agents) cat "$ST/agents.json" ;;
    rm)
        echo "claude $*" >>"$ST/log"
        [ -f "$ST/rm-says" ] && { cat "$ST/rm-says" >&2; exit 1; }
        echo '[]' >"$ST/agents.json" ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$P2"/*.sh "$B2"/*

IP="$T/inst/w5"
# Exported: the niwa stand-in's destroy removes this job's directory.
export JID=4b3597d2
SID=$JID-6184-4a48
# Claude Code's project directories: the instance's own (ENC), a worktree's
# under it, and a sibling instance's whose name extends this one's.
ENC=$(printf '%s' "$IP" | sed 's/[^A-Za-z0-9]/-/g')
PJ="$HOME/.claude/projects"
TR="$PJ/$ENC/$SID.jsonl"
COPY=$JID-aaaa-bbbb
export TEARDOWN_CLAUDE_HOME="$HOME/.claude" TEARDOWN_KOTO_SESSIONS="$T/ksess" TEARDOWN_ARCHIVE_DIR="$T/archive" \
    KOTO_REQUESTS="$T/requests" UNIT_COST_FETCH_SECS=1 UNIT_COST_LIST_SECS=2 UNIT_COST_POST_SECS=2
# The sweep a run starts as it ends: a stand-in that logs its arguments.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$T/sweep.calls" >"$T/sweep-stub"
export TEARDOWN_SWEEP="$T/sweep-stub"
# msg <id> <output tokens> <cwd>: one assistant line.
msg() { printf '{"type":"assistant","cwd":"%s","timestamp":"2026-10-01T09:00:30.000Z","message":{"id":"%s","usage":{"input_tokens":1,"output_tokens":%s}}}\n' "$3" "$1" "$2"; }
# setup_run: a fresh instance, job, transcripts, worker session and request,
# both listings, an empty log, and the real unit-cost.sh. The worker's
# transcript links pull request 601 (unreadable) and 602 (created at 10:00,
# linked 20 seconds later: credited).
setup_run() {
    rm -rf "$T/archive" "$T/ksess" "$T/requests" "$TEARDOWN_CLAUDE_HOME" "$IP" "$ST" "$T/outside"
    mkdir -p "$ST" "$IP" "$PJ/$ENC/$SID/subagents" "$PJ/$ENC-wt/$SID/subagents" "$PJ/$ENC-2" "$T/outside" \
        "$TEARDOWN_CLAUDE_HOME/jobs/$JID" "$T/ksess/issue_7" "$T/requests/r_w5"
    : >"$ST/log"
    : >"$ST/pids"
    { msg m1 7 "$IP"; msg m2 3 "$IP"
      printf '{"type":"pr-link","prNumber":601,"prRepository":"acme/widgets","timestamp":"2026-10-01T10:00:20.000Z"}\n'
      printf '{"type":"pr-link","prNumber":602,"prRepository":"acme/widgets","timestamp":"2026-10-01T10:00:20.000Z"}\n'; } >"$TR"
    msg s1 1 "$IP" >"$PJ/$ENC/$SID/subagents/agent-1.jsonl"
    msg s2 2 "$IP/wt" >"$PJ/$ENC-wt/$SID/subagents/agent-2.jsonl"
    msg s3 4 "$IP/wt" >"$PJ/$ENC-wt/$SID/subagents/agent-3.jsonl"
    { msg m1 7 "$IP"; msg m2 3 "$IP"; msg r1 5 "$IP/wt"; } >"$PJ/$ENC-wt/$COPY.jsonl"
    msg x1 900 "$IP-2" >"$PJ/$ENC-2/$JID-cccc-dddd.jsonl"
    msg far 800 "$IP" >"$T/outside/far.jsonl"
    ln -s "$T/outside/far.jsonl" "$PJ/$ENC/linked.jsonl"
    printf '{"state":"done","createdAt":"2026-10-01T09:00:00.000Z","sessionId":"%s"}\n' "$SID" >"$TEARDOWN_CLAUDE_HOME/jobs/$JID/state.json"
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
[ "$(cat "$T/sweep.calls" 2>/dev/null)" = start ] && ok "the run starts the host's sweep once, as it ends" \
    || bad "the run starts the host's sweep once, as it ends" "$(cat "$T/sweep.calls" 2>&1)"
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
eq_ "MANIFEST.sha256 records the MANIFEST's digest" "$(sha256 <"$ARCHD/MANIFEST")  MANIFEST" "$(cat "$ARCHD/MANIFEST.sha256" 2>&1)"
grep -q '^`MANIFEST.sha256` holds the MANIFEST' "$ARCHD/README.md" \
    && ok "the README says what MANIFEST.sha256 is" || bad "the README says what MANIFEST.sha256 is" "$(cat "$ARCHD/README.md")"
eq_ "the posted text opens with the summary line" "Cost of w5 (${ARCHD##*/}): 1 sessions, 17 output tokens, dispatch to merge 151.0 min." \
    "$(head -n 1 "$ST/posted.txt")"
for f in "$ENC/$SID.jsonl" "$ENC/$SID/subagents/agent-1.jsonl" "$ENC-wt/$SID/subagents/agent-2.jsonl" "$ENC-wt/$SID/subagents/agent-3.jsonl" "$ENC-wt/$COPY.jsonl"; do
    [ -f "$ARCHD/claude-projects/$f" ] && ok "archived: claude-projects/$f" || bad "archived: claude-projects/$f" "$(cd "$ARCHD" && find . | sort)"
done
grep -q " claude-projects/$ENC-wt/$COPY.jsonl\$" "$ARCHD/MANIFEST" && ok "  ... each in the MANIFEST" || bad "  ... each in the MANIFEST" "$(cat "$ARCHD/MANIFEST")"
[ -e "$ARCHD/claude-projects/$ENC-2" ] && bad "a sibling instance's directory sharing the name's prefix is not archived" || ok "a sibling instance's directory sharing the name's prefix is not archived"
[ -e "$ARCHD/claude-projects/$ENC/linked.jsonl" ] && bad "a symbolic link is never followed or copied" || ok "a symbolic link is never followed or copied"
[ -e "$ARCHD/transcript" ] && bad "nothing is written to transcript/" || ok "nothing is written to transcript/"
eq_ "the README lists the directories taken and skipped, and the link" \
    "- Project directory taken: $ENC|- Project directory taken: $ENC-wt|- Project directory skipped (cwd outside the instance): $ENC-2|- Symbolic link skipped: claude-projects/$ENC/linked.jsonl" \
    "$(grep -e '^- Project directory' -e '^- Symbolic link' "$ARCHD/README.md" | tr '\n' '|' | sed 's/|$//')"
eq_ "only the user can read what the pass wrote" "drwx------|drwx------" \
    "$(ls -ld "$ARCHD/claude-projects" | cut -c1-10)|$(ls -ld "$ARCHD/claude-projects/$ENC-wt/$SID" | cut -c1-10)"
eq_ "the worker row: its transcript and three subagents in two directories; nested only the copy's own message" "5 17|1 5" \
    "$(jq -r '"\(.tokens.worker.messages) \(.tokens.worker.output)|\(.tokens.nested.messages) \(.tokens.nested.output)"' "$ARCHD/unit-cost.json" 2>&1)"
eq_ "an unreadable linked pull request is left out and the pass is done: credit never gates" "acme/widgets#600 holding|acme/widgets#602 session|read failed|0 done" \
    "$(jq -r '"\([.pulls[] | "\(.repo)#\(.number) \(.via)"] | join("|"))|\([.missing[] | select(.figure == "pulls") | .reason] | join(","))"' "$ARCHD/unit-cost.json" 2>&1)|$RC $RES"
eq_ "  ... green read from the run on the pull request's head, the pull request named" "121 measured|acme/widgets#600" \
    "$(jq -r '"\(.figures.dispatch_to_green_min.value) \(.figures.dispatch_to_green_min.state)|\(.pulls[0].repo)#\(.pulls[0].number)"' "$ARCHD/unit-cost.json" 2>&1)"

echo "== a job niwa destroy already removed =="
setup_run
: >"$ST/destroy-takes-job"
printf "No job matching '%s'\n" "$JID" >"$ST/rm-says"
run_pass
[ "$RC" = 0 ] && [ "$LAST" = "teardown-pass: done $ARCHD" ] && [ "$RES" = "done" ] && ok "rm finds no job after destroy took it: the pass is done" \
    || bad "rm finds no job after destroy took it: the pass is done" "exit $RC: $OUT $ERR"
[ -n "$(line_of "claude rm $JID")" ] && ok "  ... rm did run" || bad "  ... rm did run" "$(cat "$ST/log")"
case "$(cat "$ARCHD/RESULT" 2>&1)" in
    "done "*" (remove: job $JID was already removed by niwa destroy)") ok "  ... RESULT says the remove step was already done by destroy" ;;
    *) bad "  ... RESULT says the remove step was already done by destroy" "$(cat "$ARCHD/RESULT" 2>&1)" ;;
esac
# rm_fails <label> <reason>: rm printed No job matching, but the job isn't
# gone everywhere (or rm said something else): the pass stays incomplete.
rm_fails() {
    run_pass
    [ "$RC" = 2 ] && ok "$1: incomplete, exit 2" || bad "$1: incomplete, exit 2" "exit $RC: $OUT $ERR"
    case "$LAST" in "teardown-pass: incomplete at remove: claude rm failed: "*"$2") ok "  ... at remove, naming why" ;; *) bad "  ... at remove, naming why" "$LAST" ;; esac
    case "$(cat "$ARCHD/RESULT" 2>&1)" in "incomplete at remove: "*) ok "  ... RESULT says incomplete" ;; *) bad "  ... RESULT says incomplete" "$(cat "$ARCHD/RESULT" 2>&1)" ;; esac
}
setup_run
printf "No job matching '%s'\n" "$JID" >"$ST/rm-says"
rm_fails "rm finds no job while its directory and row are still there" "jobs/$JID is still there"
setup_run
printf "No job matching '%s'\n" "$JID" >"$ST/rm-says"
: >"$ST/destroy-takes-job"
: >"$ST/row-stays"
rm_fails "rm finds no job while the agents listing still has it" "claude agents still lists job $JID"
setup_run
printf "No job matching '%s'\n" "$JID" >"$ST/rm-says"
: >"$ST/destroy-takes-job"
: >"$ST/dir-stays"
rm_fails "rm finds no job while its directory is still there, its row gone" "jobs/$JID is still there"
setup_run
printf "No job matching '%s'\n" "$JID" >"$ST/rm-says"
: >"$ST/destroy-takes-job"
cp "$ST/niwa.json" "$ST/instance-stays"
rm_fails "rm finds no job while niwa still lists the instance" "niwa still lists tsuku+w5"
setup_run
: >"$ST/destroy-takes-job"
printf 'permission denied\n' >"$ST/rm-says"
rm_fails "any other rm failure, the job gone" "permission denied"

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

echo "== a file that can't be copied =="
if [ "$(id -u)" = 0 ]; then
    echo "skip: root reads a file of any mode"
else
    setup_run
    printf 'memory\n' >"$PJ/$ENC/memory.md"
    chmod 000 "$PJ/$ENC/memory.md"
    run_pass
    chmod 600 "$PJ/$ENC/memory.md"
    [ "$RC" = 1 ] && ok "the pass refuses, exit 1" || bad "the pass refuses, exit 1" "exit $RC: $OUT"
    case "$LAST" in "teardown-pass: refused: cannot copy $PJ/$ENC/memory.md") ok "  ... naming the file" ;; *) bad "  ... naming the file" "$LAST" ;; esac
    case "$(cat "$ARCHD/RESULT" 2>&1)" in "refused at preserve: "*) ok "  ... RESULT says refused" ;; *) bad "  ... RESULT says refused" "$(cat "$ARCHD/RESULT" 2>&1)" ;; esac
    [ -z "$(line_of 'niwa destroy')" ] && [ -z "$(line_of 'claude rm')" ] && ok "  ... and no niwa destroy or claude rm runs" || bad "  ... and no niwa destroy or claude rm runs" "$(cat "$ST/log")"
fi

echo "== credit reads that hang =="
setup_run
for n in 610 611 612 613 614 615 616 617 618 619 620 621 622 623 624 625 626 627 628 629; do
    printf '{"type":"pr-link","prNumber":%s,"prRepository":"acme/widgets","timestamp":"2026-10-01T10:00:20.000Z"}\n' "$n" >>"$TR"
done
: >"$ST/slow"
START=$(date +%s)
TEARDOWN_CAPTURE_SECS=12 UNIT_COST_BUDGET_SECS=5 run_pass
ELAPSED=$(($(date +%s) - START))
[ "$RC" = 0 ] && [ "$RES" = done ] && ok "twenty hung credit reads: the pass is done" || bad "twenty hung credit reads: the pass is done" "exit $RC: $OUT $ERR"
[ -z "$ERR" ] && ok "  ... the capture ended inside TEARDOWN_CAPTURE_SECS: no warning" || bad "  ... the capture ended inside TEARDOWN_CAPTURE_SECS: no warning" "$ERR"
[ "$ELAPSED" -lt 12 ] && ok "  ... in ${ELAPSED}s" || bad "  ... the capture ended inside TEARDOWN_CAPTURE_SECS" "${ELAPSED}s"
# The first linked pull request (601) is unreadable, so its reason comes
# first; each hung read is cut at its own bound, and the budget stops the rest.
eq_ "  ... the entry keeps one pulls reason, the first: read failed" "read failed" \
    "$(jq -r '[.missing[] | select(.figure == "pulls") | .reason] | join(",")' "$ARCHD/unit-cost.json" 2>&1)"
STARTED=$(grep -c . "$ST/pids")
[ "$STARTED" -lt 21 ] && ok "  ... the budget stopped the credit reads ($STARTED of 21 hung reads began)" \
    || bad "  ... the budget stopped the credit reads" "$STARTED of 21 began"
[ -s "$ST/posted.txt" ] && ok "  ... and posted" || bad "  ... and posted" ""
tries=0
while :; do
    left=""
    for p in $(cat "$ST/pids"); do kill -0 "$p" 2>/dev/null && left="$left $p"; done
    [ -z "$left" ] || [ "$tries" -ge 20 ] && break
    tries=$((tries + 1))
    sleep 0.1
done
[ -z "$left" ] && ok "  ... no read left running" || { bad "  ... no read left running" "$left"; for p in $left; do kill "$p" 2>/dev/null; done; }

echo "== a capture past the pass's capture deadline =="
setup_run
printf '#!/usr/bin/env bash\necho $$ >>"$ST/pids"\nexec sleep 30\n' >"$P2/unit-cost.sh"
START=$(date +%s)
TEARDOWN_CAPTURE_SECS=2 run_pass
unchanged "a capture past the deadline"
case "$ERR" in *"(status 124)"*) ok "  ... the warning names the deadline" ;; *) bad "  ... the warning names the deadline" "$ERR" ;; esac
[ $(($(date +%s) - START)) -lt 15 ] && ok "  ... the pass returns at the deadline" || bad "  ... the pass returns at the deadline" "$(($(date +%s) - START))s"

# ---------------------------------------------------------------------------
# confirm over an archive of a few thousand files (shirabe#999: a per-file
# check outran koto's 30-second action bound). The real pass and library;
# stand-ins for the verdict reader, coord-log's seal (it prints the token),
# koto's context add (it keeps the detail), the two listings, and a wc
# that logs each run and can be made slow, so a case can count the processes
# the size check starts and hold it past its deadline.
echo "== confirm over a large archive =="
P3="$T/plugin3/skills/coordinate/scripts"
B3="$T/bin3"
C3="$T/c3"
mkdir -p "$P3" "$B3" "$C3"
cp "$HERE/teardown-pass.sh" "$HERE/dispatch-common.sh" "$HERE/archive-common.sh" "$S/teardown-handoff.sh" "$P3/"
cat >"$P3/coord-log.sh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = --token ] && echo "$2"; shift; done
EOF
cat >"$B3/koto" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "context add" ] && [ "$5" = --from-file ] || exit 64
cp "$6" "$C3/detail.json"
EOF
printf '#!/bin/sh\ncat "$C3/niwa.json"\n' >"$B3/niwa"
printf '#!/bin/sh\ncat "$C3/agents.json"\n' >"$B3/claude"
REALWC=$(command -v wc)
cat >"$B3/wc" <<EOF
#!/bin/sh
# A wc -c run over more than one file is the size listing; any other passes.
if [ "\$1" = -c ] && [ \$# -gt 2 ]; then
    echo \$\$ >>"\$C3/wc.log"
    [ -f "\$C3/slow" ] && exec sleep 30
    [ -f "\$C3/fails" ] && { echo "wc: ./x: Input/output error" >&2; exit 1; }
fi
exec "$REALWC" "\$@"
EOF
chmod +x "$P3"/*.sh "$B3"/*
export C3
CA="$T/carchive/2026-10-21-w5-4b3597d2"
NFILES=3000
# setup_confirm: a done archive of NFILES files, with the MANIFEST and the
# digest the pass writes, both listings without the unit, and a fresh log.
setup_confirm() {
    rm -rf "$T/carchive" "$C3/slow" "$C3/fails" "$C3/detail.json"
    mkdir -p "$CA/job/tmp"
    : >"$C3/wc.log"
    echo '[]' >"$C3/niwa.json"
    echo '[]' >"$C3/agents.json"
    printf 'topic w5\ninstance tsuku+w5 /i/w5\njob 4b3597d2 4b3597d2-6184-4a48\ntranscript /t/x.jsonl\npr acme/widgets#600 0123456789012345678901234567890123456789\nhandoff https://github.com/acme/widgets/pull/600#issuecomment-1\nkeyseal %s\n' \
        "$KS" >"$T/cverdict"
    local i=0 d=""
    : >"$CA/MANIFEST"
    while [ "$i" -lt "$NFILES" ]; do
        [ $((i % 500)) = 0 ] && { d="job/tmp/d$((i / 500))"; mkdir -p "$CA/$d"; }
        printf 'file %05d\n' "$i" >"$CA/$d/f $i"
        printf '%064d 11 %s\n' 0 "$d/f $i" >>"$CA/MANIFEST"
        i=$((i + 1))
    done
    printf '%s  MANIFEST\n' "$(sha256 <"$CA/MANIFEST")" >"$CA/MANIFEST.sha256"
    printf 'done 2026-10-21T00:00:00Z\n' >"$CA/RESULT"
}
# run_confirm: one confirm; CRC, COUT (the sealed word), CWHY (the reason
# stored), CSECS.
run_confirm() {
    local s
    s=$(date +%s)
    COUT=$(cd "$T/ws" && PATH="$B3:$PATH" VERDICT_FILE="$T/cverdict" TEARDOWN_ARCHIVE_DIR="$T/carchive" \
        DC_COORD_LOG="$P3/coord-log.sh" bash "$P3/teardown-pass.sh" confirm --session s 2>/dev/null)
    CRC=$?
    CSECS=$(($(date +%s) - s))
    CWHY=$(jq -r '.reason' "$C3/detail.json" 2>&1)
}
# refuses <label> <reason>: confirm says incomplete with the reason.
refuses() {
    run_confirm
    [ "$CRC" = 0 ] && [ "$COUT" = teardown-incomplete ] && ok "$1: incomplete" || bad "$1: incomplete" "exit $CRC: $COUT"
    case "$CWHY" in *"$2"*) ok "  ... says why" ;; *) bad "  ... says why" "$CWHY" ;; esac
}

setup_confirm
run_confirm
[ "$CRC" = 0 ] && [ "$COUT" = teardown-confirmed ] && ok "$NFILES files, the unit gone: confirmed" || bad "$NFILES files, the unit gone: confirmed" "exit $CRC: $COUT ($CWHY)"
[ "$CSECS" -lt 15 ] && ok "  ... within the archive read's own bound (${CSECS}s)" || bad "  ... within the archive read's own bound" "${CSECS}s"
NWC=$(grep -c . "$C3/wc.log")
[ "$NWC" -ge 1 ] && [ "$NWC" -le 40 ] && ok "  ... the sizes come from a listing, not a process per file ($NWC wc runs)" \
    || bad "  ... the sizes come from a listing, not a process per file" "$NWC wc runs for $NFILES files"

setup_confirm
printf 'file\n' >"$CA/job/tmp/d3/f 1700"
refuses "a file cut short" "job/tmp/d3/f 1700 in the archive is not the size the MANIFEST records"
setup_confirm
rm "$CA/job/tmp/d5/f 2999"
refuses "a file gone" "job/tmp/d5/f 2999 is missing from the archive"
setup_confirm
rm "$CA/job/tmp/d0/f 7"
ln -s "$CA/job/tmp/d0/f 8" "$CA/job/tmp/d0/f 7"
refuses "a file replaced by a link to one of its size" "job/tmp/d0/f 7 is missing from the archive"
setup_confirm
sed -i.bak '$d' "$CA/MANIFEST" && rm -f "$CA/MANIFEST.bak"
refuses "a MANIFEST cut short after the pass" "the archive's MANIFEST is not the one the pass recorded"
setup_confirm
printf '%064d 5 job/tmp/d0/f 1\n' 0 >>"$CA/MANIFEST"
refuses "a MANIFEST line added after the pass" "the archive's MANIFEST is not the one the pass recorded"
setup_confirm
rm "$CA/MANIFEST.sha256"
refuses "no MANIFEST.sha256" "the archive has no MANIFEST.sha256"
setup_confirm
printf 'refused at preserve: x\n' >"$CA/RESULT"
refuses "a RESULT that isn't done" "RESULT doesn't say done"
setup_confirm
echo '[{"name":"tsuku+w5","path":"/i/w5"}]' >"$C3/niwa.json"
refuses "niwa still lists the instance" "niwa still lists tsuku+w5"
setup_confirm
echo '[{"id":"4b3597d2"}]' >"$C3/agents.json"
refuses "claude still lists the job" "claude agents still lists job 4b3597d2"

setup_confirm
: >"$C3/fails"
refuses "a listing that fails" "the archive's files could not be listed: wc: ./x: Input/output error"

setup_confirm
: >"$C3/slow"
TEARDOWN_CONFIRM_SECS=1 refuses "a size read past its deadline" "could not be checked within 1 seconds"
[ "$CSECS" -lt 10 ] && ok "  ... returns at the deadline (${CSECS}s)" || bad "  ... returns at the deadline" "${CSECS}s"
tries=0
while :; do
    left=""
    for p in $(cat "$C3/wc.log"); do kill -0 "$p" 2>/dev/null && left="$left $p"; done
    [ -z "$left" ] || [ "$tries" -ge 20 ] && break
    tries=$((tries + 1))
    sleep 0.1
done
[ -z "$left" ] && ok "  ... and leaves no read running" || { bad "  ... and leaves no read running" "$left"; for p in $left; do kill "$p" 2>/dev/null; done; }

# ---------------------------------------------------------------------------
# Build trees in the job's tmp/ (shirabe#1106): a whole pass with the real
# pass, then confirm over the archive it made.
JT="$TEARDOWN_CLAUDE_HOME/jobs/$JID/tmp"
SIG='Signature: 8a477f597d28d172789f06886806bc55'
# scratch_tmp: scratch files and the near misses a build tree's rule must
# keep: a target/ with no marker, a CACHEDIR.TAG without the signature, a
# .rustc_info.json with no rustc_fingerprint, and a marker in tmp/ itself.
scratch_tmp() {
    mkdir -p "$JT/sub" "$JT/repo/src" "$JT/web/src" "$JT/notes/target" "$JT/tag" "$JT/ri"
    printf 'notes\n' >"$JT/notes.md"
    printf 'scratch\n' >"$JT/sub/scratch file.txt"
    printf 'fn main() {}\n' >"$JT/repo/src/main.rs"
    printf 'app\n' >"$JT/web/src/app.js"
    printf 'plan\n' >"$JT/notes/target/plan.md"
    printf 'not a tag\n' >"$JT/tag/CACHEDIR.TAG"
    printf '{"other":1}\n' >"$JT/ri/.rustc_info.json"
    printf '%s\n' "$SIG" >"$JT/CACHEDIR.TAG"
}
# confirm_archive: confirm over the archive run_pass made, both listings
# without the unit; CRC, COUT, CWHY.
confirm_archive() {
    rm -f "$C3/slow" "$C3/fails" "$C3/detail.json"
    echo '[]' >"$C3/niwa.json"
    echo '[]' >"$C3/agents.json"
    COUT=$(cd "$T/ws" && PATH="$B3:$PATH" TEARDOWN_ARCHIVE_DIR="$T/archive" DC_COORD_LOG="$P3/coord-log.sh" \
        bash "$P3/teardown-pass.sh" confirm --session s 2>/dev/null)
    CRC=$?
    CWHY=$(jq -r '.reason' "$C3/detail.json" 2>&1)
}

echo "== build trees in the job's tmp/ =="
setup_run
scratch_tmp
# A cargo target dir under another name, its marker CACHEDIR.TAG, holding a
# node_modules of its own; a repo's target/, marked by .rustc_info.json;
# node_modules nested in node_modules; a cargo home; a link to a tree; and,
# with scratch_tmp's CACHEDIR.TAG making tmp/ itself a target dir, a build
# profile directory at its top, marked by .cargo-lock.
mkdir -p "$JT/ct/debug" "$JT/ct/inner/node_modules" "$JT/repo/target/release" \
    "$JT/web/node_modules/a/node_modules/b" "$JT/ch/registry/cache" "$JT/debug/deps"
printf '%s\n# cargo\n' "$SIG" >"$JT/ct/CACHEDIR.TAG"
printf '%0100d' 0 >"$JT/ct/debug/big"
: >"$JT/ct/debug/.cargo-lock"
: >"$JT/debug/.cargo-lock"
printf '%040d' 0 >"$JT/debug/deps/libx.rlib"
printf 'x\n' >"$JT/ct/inner/node_modules/y"
printf '{"rustc_fingerprint":1,"outputs":{}}\n' >"$JT/repo/target/.rustc_info.json"
printf '%0200d' 0 >"$JT/repo/target/release/app"
printf '%050d' 0 >"$JT/web/node_modules/a/index.js"
printf '%025d' 0 >"$JT/web/node_modules/a/node_modules/b/index.js"
: >"$JT/ch/.package-cache"
printf '%0300d' 0 >"$JT/ch/registry/cache/x.crate"
ln -s "$JT/web/node_modules" "$JT/nm-link"
run_pass
[ "$RC" = 0 ] && [ "$RES" = done ] && ok "build trees in tmp/: the pass is done" || bad "build trees in tmp/: the pass is done" "exit $RC: $OUT $ERR"
eq_ "SKIPPED lists each outermost tree, its marker and its bytes" \
    "300 .package-cache job/tmp/ch|154 CACHEDIR.TAG job/tmp/ct|40 .cargo-lock job/tmp/debug|237 .rustc_info.json job/tmp/repo/target|75 node_modules job/tmp/web/node_modules" \
    "$(tr '\n' '|' <"$ARCHD/SKIPPED" 2>&1 | sed 's/|$//')"
for d in ch ct debug repo/target web/node_modules nm-link; do
    [ -e "$ARCHD/job/tmp/$d" ] && bad "left out of the archive: job/tmp/$d" "$(cd "$ARCHD" && find job | sort)" || ok "left out of the archive: job/tmp/$d"
done
for f in notes.md "sub/scratch file.txt" repo/src/main.rs web/src/app.js notes/target/plan.md tag/CACHEDIR.TAG ri/.rustc_info.json CACHEDIR.TAG; do
    [ -f "$ARCHD/job/tmp/$f" ] && ok "kept: job/tmp/$f" || bad "kept: job/tmp/$f" "$(cd "$ARCHD" && find job | sort)"
done
grep -q ' SKIPPED$' "$ARCHD/MANIFEST" && ok "SKIPPED is in the MANIFEST" || bad "SKIPPED is in the MANIFEST" "$(cat "$ARCHD/MANIFEST")"
eq_ "the MANIFEST lists the 8 kept tmp/ files and nothing under a tree" 8 "$(grep -c ' job/tmp/' "$ARCHD/MANIFEST")"
eq_ "MANIFEST.sha256 records the MANIFEST's digest" "$(sha256 <"$ARCHD/MANIFEST")  MANIFEST" "$(cat "$ARCHD/MANIFEST.sha256" 2>&1)"
eq_ "the README lists each tree left out" \
    "- Build tree skipped (.package-cache, 300 bytes): job/tmp/ch|- Build tree skipped (CACHEDIR.TAG, 154 bytes): job/tmp/ct|- Build tree skipped (.cargo-lock, 40 bytes): job/tmp/debug|- Build tree skipped (.rustc_info.json, 237 bytes): job/tmp/repo/target|- Build tree skipped (node_modules, 75 bytes): job/tmp/web/node_modules" \
    "$(grep '^- Build tree skipped' "$ARCHD/README.md" | tr '\n' '|' | sed 's/|$//')"
grep -q '^`SKIPPED`, in the MANIFEST, lists each build tree' "$ARCHD/README.md" \
    && ok "the README says what SKIPPED is" || bad "the README says what SKIPPED is" "$(cat "$ARCHD/README.md")"
confirm_archive
[ "$CRC" = 0 ] && [ "$COUT" = teardown-confirmed ] && ok "confirm passes an archive with trees left out" \
    || bad "confirm passes an archive with trees left out" "exit $CRC: $COUT ($CWHY)"

echo "== a tmp/ with no build tree =="
setup_run
scratch_tmp
run_pass
[ "$RC" = 0 ] && [ "$RES" = done ] && ok "no build tree: the pass is done" || bad "no build tree: the pass is done" "exit $RC: $OUT $ERR"
[ -e "$ARCHD/SKIPPED" ] && bad "no SKIPPED is written" "$(cat "$ARCHD/SKIPPED")" || ok "no SKIPPED is written"
grep -q -e 'SKIPPED' -e 'Build tree' "$ARCHD/README.md" "$ARCHD/MANIFEST" && bad "neither the README nor the MANIFEST mentions one" "$(cat "$ARCHD/README.md")" \
    || ok "neither the README nor the MANIFEST mentions one"
eq_ "every tmp/ file is archived and in the MANIFEST, in find's order" \
    "$(cd "$JT" && find . -type f | sed 's|^\./|job/tmp/|')" "$(sed -n 's/^[^ ]* [^ ]* \(job\/tmp\/.*\)/\1/p' "$ARCHD/MANIFEST")"
eq_ "the archive holds what a pass held before trees were left out" \
    "MANIFEST|MANIFEST.sha256|README.md|RESULT|claude-projects|job|koto|teardown.json|unit-cost.json" "$(LC_ALL=C ls "$ARCHD" | tr '\n' '|' | sed 's/|$//')"
confirm_archive
[ "$CRC" = 0 ] && [ "$COUT" = teardown-confirmed ] && ok "and confirm passes it" || bad "and confirm passes it" "exit $CRC: $COUT ($CWHY)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
