#!/usr/bin/env bash
# coord-log_engine_test.sh -- the koto behaviour /coordinate's check states rely
# on, proven against a three-state skeleton template driven by real koto, and
# coord-log.sh and coord-verdict.sh exercised against the logs it writes.
#
# Proves: a default action's sealed token is captured and reaches the same
# state's command gate in one advance; a verdict routes by coord-verdict.sh's
# exit code; a verdict with no arm leaves the state blocked; a token sealed at
# one visit fails `check` after a later entry into the state; an edited hash,
# another session's seal, and an unsealed token fail; `seal --file` stores the
# bytes and `check --key` verifies them and refuses an edited value; `capture`
# and `run-facts` read engine-written captures; `koto next --to` leaves a
# directed_transition that `directed-since 0` reports; `provenance` passes for
# the template the session was created from and fails for an edited copy;
# `live-session` finds the live run and drops it once it ends.
#
# Needs koto and jq; SKIPs (exit 0) without koto, which CI asserts first.
# Usage: bash skills/coordinate/scripts/coord-log_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/coord-log-engine.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }

# koto refuses a --var value outside its allowlist (a '+' in this checkout's
# path, for one), so PLUGIN_ROOT points at a symlink to the repository.
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
CL="$PR/skills/coordinate/scripts/coord-log.sh"
CV="$PR/skills/coordinate/scripts/coord-verdict.sh"

mkdir -p "$T/work"
cd "$T/work" && git init -q && git commit -q --allow-empty -m init 2>/dev/null

TPL="$T/skeleton.md"
cat > "$TPL" <<'TPLEOF'
---
name: coord-skeleton
version: "1.0"
description: a skeleton for coord-log_engine_test.sh
initial_state: record_find
variables:
  PLUGIN_ROOT:
    description: plugin root
    required: true
  TOKFILE:
    description: the file holding the token the action prints
    required: true
  SCOPE:
    description: scope kind
    default: roadmap
  ROADMAP:
    description: roadmap path
    default: docs/roadmaps/ROADMAP-demo.md
  DISCIPLINE:
    description: discipline
    default: ""
  HOST_REPO:
    description: host
    default: acme/widgets
states:
  record_find:
    default_action:
      command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-log.sh" seal --session "{{SESSION_NAME}}" --state record_find --token "$(cat "{{TOKFILE}}")"'
      capture_stdout_as: RECORD_FIND
      fallback: tick again
    gates:
      verdict:
        type: command
        command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-verdict.sh" --session "{{SESSION_NAME}}" --state record_find --capture "{{RECORD_FIND}}"'
        overridable: false
    transitions:
      - target: hold
        when:
          gates.verdict.exit_code: 10
      - target: done
        when:
          gates.verdict.exit_code: 11
  hold:
    accepts:
      go:
        type: enum
        values: [again, finish]
        required: true
    transitions:
      - target: record_find
        when:
          go: again
      - target: done
        when:
          go: finish
  done:
    terminal: true
---

## record_find

Find.

## hold

Hold.

## done

Done.
TPLEOF

S=coordinate-demo-20260101T000000Z
LOG=
start() { # start <session> <template> <token>
    printf '%s' "$3" > "$T/tok.$1"
    koto init "$1" --template "$2" --var PLUGIN_ROOT="$PR" --var TOKFILE="$T/tok.$1" >/dev/null 2>"$T/init.err" || { cat "$T/init.err"; return 1; }
}
tick() { koto next "$@" --no-cleanup 2>/dev/null; }

echo "== capture reaches the gate in one advance =="
start "$S" "$TPL" "found 7" || { echo "FAIL: koto init"; exit 1; }
R=$(tick "$S")
eq "found routes to hold" hold "$(printf '%s' "$R" | jq -r .state)"
LOG="$(koto session dir "$S")/koto-$S.state.jsonl"
CAP1=$(bash "$CL" capture --session "$S" --name RECORD_FIND)
case "$CAP1" in "found 7 sealed:"*) pass "the capture is the sealed token" ;; *) fail "the capture is the sealed token" "$CAP1" ;; esac
bash "$CL" check --session "$S" --state record_find --sealed "$CAP1" && pass "check accepts the latest visit's seal" || fail "check accepts the latest visit's seal"
eq "run-facts reads the scope and the found record" '{"scope":"roadmap","name":"demo","repo":"acme/widgets","ref":"7"}' "$(bash "$CL" run-facts --session "$S")"
case "$(bash "$CL" run-start --session "$S")" in 20*T*Z) pass "run-start is the header's created_at" ;; *) fail "run-start is the header's created_at" ;; esac

echo "== seal failures =="
case "$CAP1" in *0) FLIP=1 ;; *) FLIP=0 ;; esac
bash "$CV" --session "$S" --state record_find --capture "${CAP1%?}$FLIP" >/dev/null 2>&1; eq "an edited hash exits the non-routing code" 1 $?
bash "$CV" --session "$S" --state record_find --capture "found 7" >/dev/null 2>&1; eq "an unsealed token exits the non-routing code" 1 $?
bash "$CV" --session "$S" --state record_find --capture "found 8 ${CAP1#found 7 }" >/dev/null 2>&1; eq "a token edited under its seal exits the non-routing code" 1 $?
bash "$CV" --session "$S" --state hold --capture "$CAP1" >/dev/null 2>&1; eq "a seal from another state exits the non-routing code" 1 $?

echo "== a later visit supersedes the seal =="
printf 'found 9' > "$T/tok.$S"
R=$(tick "$S" --with-data '{"go":"again"}')
eq "found again returns to hold" hold "$(printf '%s' "$R" | jq -r .state)"
bash "$CL" check --session "$S" --state record_find --sealed "$CAP1" 2>/dev/null; eq "the first visit's seal is no longer valid" 1 $?
bash "$CL" check --session "$S" --state record_find --sealed "$CAP1" --any-visit && pass "--any-visit still accepts a real earlier visit" || fail "--any-visit still accepts a real earlier visit"
eq "capture reads the latest value" "found 9" "$(bash "$CL" capture --session "$S" --name RECORD_FIND | cut -d' ' -f1-2)"
eq "capture --for picks by the second word" "found 7" "$(bash "$CL" capture --session "$S" --name RECORD_FIND --for 7 | cut -d' ' -f1-2)"
bash "$CL" capture --session "$S" --name NOPE >/dev/null; eq "an absent capture exits 1" 1 $?

echo "== an unrouted verdict blocks =="
printf 'bogus' > "$T/tok.$S"
R=$(tick "$S" --with-data '{"go":"again"}')
eq "an unknown verdict leaves the state blocked in record_find" record_find "$(printf '%s' "$R" | jq -r .state)"
printf 'none' > "$T/tok.$S"
R=$(tick "$S")
eq "a routed verdict on the next tick moves on" done "$(printf '%s' "$R" | jq -r .state)"

echo "== seal --file and check --key =="
S2=coordinate-demo-20260101T000001Z
start "$S2" "$TPL" "found 3" && tick "$S2" >/dev/null
printf '{"verdict":"durable"}' > "$T/v.json"
SEALF=$(bash "$CL" seal --session "$S2" --state record_find --file "$T/v.json" --key coord/v)
case "$SEALF" in sealed:*) pass "seal --file prints a bare seal" ;; *) fail "seal --file prints a bare seal" "$SEALF" ;; esac
eq "check --key prints the verified bytes" '{"verdict":"durable"}' "$(bash "$CL" check --session "$S2" --state record_find --sealed "$SEALF" --key coord/v)"
printf '{"verdict":"forged"}' > "$T/f.json"
koto context add "$S2" coord/v --from-file "$T/f.json" >/dev/null 2>&1
bash "$CL" check --session "$S2" --state record_find --sealed "$SEALF" --key coord/v >/dev/null 2>&1; eq "an edited context value fails its seal" 1 $?
bash "$CL" check --session "$S" --state record_find --sealed "$(bash "$CL" capture --session "$S2" --name RECORD_FIND)" --any-visit >/dev/null 2>&1; eq "another session's seal fails" 1 $?

echo "== directed transitions =="
bash "$CL" directed-since --session "$S2" --from 0 >/dev/null; eq "no directed transition yet" 0 $?
koto next "$S2" --to done --no-cleanup >/dev/null 2>&1
OUT=$(bash "$CL" directed-since --session "$S2" --from 0); rc=$?
eq "a --to is reported" 1 $rc
case "$OUT" in *"hold->done"*) pass "the report names the edge" ;; *) fail "the report names the edge" "$OUT" ;; esac

echo "== provenance and live session =="
S3=coordinate-demo-20260101T000002Z
start "$S3" "$TPL" "found 1" && tick "$S3" >/dev/null
bash "$CL" provenance --session "$S3" --template "$TPL" && pass "provenance passes for the template the session came from" || fail "provenance passes for the template the session came from"
sed 's/^description: a skeleton/description: an edited skeleton/' "$TPL" > "$T/edited.md"
S4=coordinate-other-20260101T000003Z
start "$S4" "$T/edited.md" "found 1" && tick "$S4" >/dev/null
bash "$CL" provenance --session "$S4" --template "$TPL" 2>/dev/null; eq "provenance fails for an edited copy" 1 $?
eq "live-session finds the one live run" "$S3" "$(bash "$CL" live-session --scope-slug demo)"
tick "$S3" --with-data '{"go":"finish"}' >/dev/null
bash "$CL" live-session --scope-slug demo >/dev/null 2>&1; eq "no live run once it ends" 1 $?

echo
echo "coord-log engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
