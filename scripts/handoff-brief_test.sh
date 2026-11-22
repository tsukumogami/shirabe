#!/usr/bin/env bash
# handoff-brief_test.sh -- scripts/handoff-brief.sh note, and the two
# `shirabe compaction` hooks reading what it writes.
#
# Covers: a note lands in koto under compaction/note.md (koto is a stub that
# records its arguments and the file it was given); the ledger entry's path,
# modes and lines, with one `skill:` line per --skill in order; the refusals
# (no reasoning, no koto session, a bad session id, a skill path that is
# relative, missing or holds `..`, a skill argument with shell characters, a
# linked entry), each writing nothing; and, when a `shirabe` binary is on PATH,
# both hooks reading the entry back: pre-compact names the koto session,
# branch, pull request, note key and SKILL.md path; re-anchor's JSON lists the
# SKILL.md read, then koto status, then the note, under 10,000 characters and
# without the note's text; and both print nothing and exit 0 with the entry
# deleted, with a bad session id, or with KOTO_SESSION naming another session.
#
# Usage: bash scripts/handoff-brief_test.sh
#   (put a built shirabe on PATH to run the hook cases, e.g.
#    PATH="$PWD/target/release:$PATH" bash scripts/handoff-brief_test.sh)
set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/handoff-brief.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/handoff-brief-test.XXXXXX") || exit 1
ktg_on_exit 'case "$T" in */handoff-brief-test.*) rm -rf "$T" ;; esac'
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$2"; fi; }

# A koto stub: records each call and copies --from-file's content.
mkdir -p "$T/bin" "$T/state" "$T/repo" "$T/plugin/skills/deliver" "$T/plugin/skills/scope" || exit 1
cat >"$T/bin/koto" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$KOTO_STUB_LOG"
prev=""
for a in "$@"; do
    [ "$prev" = --from-file ] && cat "$a" >"$KOTO_STUB_LOG.content"
    prev="$a"
done
exit "${KOTO_STUB_RC:-0}"
EOF
chmod +x "$T/bin/koto"
: >"$T/plugin/skills/deliver/SKILL.md"
: >"$T/plugin/skills/scope/SKILL.md"
git -C "$T/repo" init -q -b session/test1 || exit 1

SID=4f08fec0-0720-4fdd-ab29-5f0583eb2031
ENTRY="$T/state/shirabe/compaction/$SID"
printf 'I was halfway through step 3; the gate passed.\n' >"$T/reasoning.md"
DELIVER="$T/plugin/skills/deliver/SKILL.md"
SCOPE="$T/plugin/skills/scope/SKILL.md"

# run_note <args...> -- the script from inside the repo, with the stub koto.
run_note() {
    (cd "$T/repo" && PATH="$T/bin:$PATH" KOTO_STUB_LOG="$T/koto.log" XDG_STATE_HOME="$T/state" \
        CLAUDE_CODE_SESSION_ID="$SID" KOTO_SESSION="${RUN_KOTO_SESSION-}" \
        bash "$SCRIPT" note "$@")
}

echo "== note writes the note and the entry =="
rm -f "$T/koto.log"
OUT=$(RUN_KOTO_SESSION=probe-run run_note --reasoning "$T/reasoning.md" \
    --skill "shirabe:deliver handoff-brief --no-merge $DELIVER" \
    --skill "shirabe:scope handoff-brief $SCOPE" \
    --pr https://github.com/acme/widgets/pull/42 2>&1); rc=$?
check "exit 0" '[ "$rc" -eq 0 ]'
check "koto got compaction/note.md in the koto session" 'grep -q "^context add probe-run compaction/note.md --from-file " "$T/koto.log"'
check "koto got the reasoning text" 'grep -q "halfway through step 3" "$T/koto.log.content"'
check "entry exists" '[ -f "$ENTRY" ]'
# GNU stat first: there, -f means the file system and still exits 0.
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
check "entry is 0600" '[ "$(mode_of "$ENTRY")" = 600 ]'
check "directory is 0700" '[ "$(mode_of "$T/state/shirabe/compaction")" = 700 ]'
check "entry lines in order" '[ "$(cat "$ENTRY")" = "koto_session: probe-run
note_key: compaction/note.md
branch: session/test1
pr: https://github.com/acme/widgets/pull/42
skill: shirabe:deliver handoff-brief --no-merge $DELIVER
skill: shirabe:scope handoff-brief $SCOPE" ]'
check "prints the ledger path" 'grep -q "^ledger=$ENTRY$" <<<"$OUT"'
check "no stray temporary files" '[ "$(ls -A "$T/state/shirabe/compaction" | wc -l | tr -d " ")" = 1 ]'

echo "== --koto-session wins, --pr defaults to none =="
OUT=$(RUN_KOTO_SESSION=other run_note --reasoning "$T/reasoning.md" --koto-session probe-run \
    --skill "shirabe:scope $SCOPE" 2>&1); rc=$?
check "exit 0" '[ "$rc" -eq 0 ]'
check "pr: none" 'grep -qx "pr: none" "$ENTRY"'
check "skill with no arguments" 'grep -qx "skill: shirabe:scope $SCOPE" "$ENTRY"'

echo "== refusals write nothing =="
refused() {
    local label="$1"; shift
    rm -f "$ENTRY" "$T/koto.log"
    OUT=$("$@" 2>&1); rc=$?
    if [ "$rc" -eq 2 ] && [ ! -e "$ENTRY" ] && [ ! -e "$T/koto.log" ]; then ok "$label"; else bad "$label" "rc=$rc $OUT"; fi
}
refused "no --reasoning" run_note --koto-session probe-run
refused "no koto session" run_note --reasoning "$T/reasoning.md"
refused "relative skill path" run_note --reasoning "$T/reasoning.md" --koto-session k --skill "a skills/SKILL.md"
refused "missing skill path" run_note --reasoning "$T/reasoning.md" --koto-session k --skill "a /nope/SKILL.md"
refused "skill path with .." run_note --reasoning "$T/reasoning.md" --koto-session k --skill "a $T/plugin/skills/../skills/scope/SKILL.md"
refused "skill argument with shell characters" run_note --reasoning "$T/reasoning.md" --koto-session k --skill "a \$(id) $SCOPE"
refused "skill with double spaces" run_note --reasoning "$T/reasoning.md" --koto-session k --skill "a  $SCOPE"
refused "bad --pr" run_note --reasoning "$T/reasoning.md" --koto-session k --pr http://evil/pull/1
refused "bad koto session name" run_note --reasoning "$T/reasoning.md" --koto-session ../x
rm -f "$ENTRY" "$T/koto.log"
OUT=$(cd "$T/repo" && PATH="$T/bin:$PATH" KOTO_STUB_LOG="$T/koto.log" XDG_STATE_HOME="$T/state" \
    CLAUDE_CODE_SESSION_ID="a/b" bash "$SCRIPT" note --reasoning "$T/reasoning.md" --koto-session k 2>&1); rc=$?
check "bad session id refused, nothing written" '[ "$rc" -eq 2 ] && [ ! -e "$ENTRY" ] && [ ! -e "$T/koto.log" ]'
ln -s "$T/elsewhere" "$ENTRY"
OUT=$(run_note --reasoning "$T/reasoning.md" --koto-session k 2>&1); rc=$?
check "linked entry refused, link target untouched" '[ "$rc" -eq 2 ] && [ ! -e "$T/elsewhere" ]'
rm -f "$ENTRY"
OUT=$(KOTO_STUB_RC=1 run_note --reasoning "$T/reasoning.md" --koto-session k 2>&1); rc=$?
check "a failed koto write exits 1 and writes no entry" '[ "$rc" -eq 1 ] && [ ! -e "$ENTRY" ]'

# Entry size: 8 skills of 4 arguments of 200 characters stay within 8 KiB; 5
# arguments each go over it and are refused before anything is written.
A200=$(printf '%200s' '')
A200=${A200// /a}
BIG4="shirabe:deliver $A200 $A200 $A200 $A200 $DELIVER"
BIG5="shirabe:deliver $A200 $A200 $A200 $A200 $A200 $DELIVER"
BIG4_ARGS=() BIG5_ARGS=()
for i in 1 2 3 4 5 6 7 8; do BIG4_ARGS+=(--skill "$BIG4"); BIG5_ARGS+=(--skill "$BIG5"); done
rm -f "$ENTRY" "$T/koto.log"
OUT=$(run_note --reasoning "$T/reasoning.md" --koto-session k "${BIG5_ARGS[@]}" 2>&1); rc=$?
check "an entry over 8 KiB is refused, nothing written" '[ "$rc" -eq 2 ] && [ ! -e "$ENTRY" ] && [ ! -e "$T/koto.log" ]'
OUT=$(run_note --reasoning "$T/reasoning.md" --koto-session k "${BIG4_ARGS[@]}" 2>&1); rc=$?
check "an entry within 8 KiB is written" '[ "$rc" -eq 0 ] && [ "$(wc -c <"$ENTRY" | tr -d " ")" -le 8192 ]'

if command -v shirabe >/dev/null 2>&1 && shirabe compaction --help >/dev/null 2>&1; then
    echo "== the hooks read the entry back =="
    RUN_KOTO_SESSION=probe-run run_note --reasoning "$T/reasoning.md" \
        --skill "shirabe:deliver handoff-brief --no-merge $DELIVER" \
        --pr https://github.com/acme/widgets/pull/42 >/dev/null 2>&1
    IN="{\"session_id\":\"$SID\",\"hook_event_name\":\"PreCompact\"}"
    hook() { printf '%s' "$2" | XDG_STATE_HOME="$T/state" KOTO_SESSION="${HOOK_KS-}" shirabe compaction "$1"; }
    PC=$(hook pre-compact "$IN"); rc=$?
    check "pre-compact exit 0" '[ "$rc" -eq 0 ]'
    for want in probe-run session/test1 https://github.com/acme/widgets/pull/42 compaction/note.md "$DELIVER"; do
        check "pre-compact names $want" 'grep -qF "$want" <<<"$PC"'
    done
    RA=$(hook re-anchor "$IN"); rc=$?
    check "re-anchor exit 0" '[ "$rc" -eq 0 ]'
    CTX=$(printf '%s' "$RA" | jq -r '.hookSpecificOutput.additionalContext')
    check "re-anchor is a SessionStart hook JSON" '[ "$(printf "%s" "$RA" | jq -r .hookSpecificOutput.hookEventName)" = SessionStart ]'
    check "re-anchor under 10,000 characters" '[ "$(printf "%s" "$RA" | wc -c | tr -d " ")" -lt 10000 ]'
    check "re-anchor inlines no note text" '! grep -q "halfway through" <<<"$RA"'
    check "re-anchor order: SKILL.md, koto status, note" '
        a=$(grep -n -m 1 -F "$DELIVER" <<<"$CTX" | cut -d: -f1)
        b=$(grep -n -m 1 "koto status probe-run" <<<"$CTX" | cut -d: -f1)
        c=$(grep -n -m 1 "koto context get probe-run compaction/note.md" <<<"$CTX" | cut -d: -f1)
        [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]'
    for sub in pre-compact re-anchor; do
        OUT=$(HOOK_KS=someone-else hook "$sub" "$IN"); rc=$?
        check "$sub: KOTO_SESSION mismatch gives exit 0, no output" '[ "$rc" -eq 0 ] && [ -z "$OUT" ]'
        OUT=$(hook "$sub" '{"session_id":"../../etc/passwd"}'); rc=$?
        check "$sub: bad session id gives exit 0, no output" '[ "$rc" -eq 0 ] && [ -z "$OUT" ]'
        OUT=$(hook "$sub" 'not json'); rc=$?
        check "$sub: bad input gives exit 0, no output" '[ "$rc" -eq 0 ] && [ -z "$OUT" ]'
    done
    # The largest entry the writer allows comes back whole.
    run_note --reasoning "$T/reasoning.md" --koto-session k "${BIG4_ARGS[@]}" >/dev/null 2>&1
    RA=$(hook re-anchor "$IN")
    CTX=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$RA")
    check "re-anchor gives back all 8 skills of an entry at the size limit" \
        '[ "$(grep -c -F "$DELIVER again" <<<"$CTX")" -eq 8 ]'
    rm -f "$ENTRY"
    for sub in pre-compact re-anchor; do
        OUT=$(hook "$sub" "$IN"); rc=$?
        check "$sub: deleted entry gives exit 0, no output" '[ "$rc" -eq 0 ] && [ -z "$OUT" ]'
    done
    # A FIFO at the entry path: the hook must not wait for a writer.
    if mkfifo "$ENTRY" 2>/dev/null; then
        for sub in pre-compact re-anchor; do
            rm -f "$T/fifo.out" "$T/fifo.rc"
            ( hook "$sub" "$IN" >"$T/fifo.out"; echo "$?" >"$T/fifo.rc" ) &
            pid=$!
            i=0
            while [ ! -s "$T/fifo.rc" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
            if [ -s "$T/fifo.rc" ]; then
                wait "$pid" 2>/dev/null
                check "$sub: FIFO entry gives exit 0, no output, no wait" \
                    '[ "$(cat "$T/fifo.rc")" = 0 ] && [ ! -s "$T/fifo.out" ]'
            else
                # Open the write end once so the blocked reader returns.
                ( : >"$ENTRY" ) & w=$!
                sleep 0.2; kill "$w" 2>/dev/null; wait "$pid" 2>/dev/null
                bad "$sub: FIFO entry gives exit 0, no output, no wait" "still running after 5s"
            fi
        done
        rm -f "$ENTRY"
    fi
else
    echo "== hooks skipped: no shirabe with 'compaction' on PATH =="
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
