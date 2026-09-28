#!/usr/bin/env bash
# board-land_engine_test.sh -- the board, land and merge scripts as check
# actions in real koto: a skeleton template with start_posture, verify,
# verify_board, land, land_merge and merge_confirm, driven against the
# gh-board stand-in, with coord-verdict.sh as every gate.
#
# Proves: a verified board routes verify_board to land in the same advance,
# and a permitted land to land_merge; land-merge.sh, run by the agent, merges
# the verified sha through a stand-in merge-exec.sh, and merge_confirm routes
# merged to done; an unverified board routes to failure and a pending one to
# wait; a refused check rollup green from the Actions jobs routes to surface
# and never to land, even when a check only isRequired names is unseen; an
# unreadable board routes to wait, which then takes the next event, and a pull
# request merged outside the run routes to surface, so verify_board never holds
# the run; a denied posture routes land to surface; `koto next --to verify_board`
# without a prediction leaves no VERIFIED capture (board-record.sh refuses);
# and a `--to` anywhere in the run makes land-merge.sh refuse.
#
# Needs koto and jq; SKIPs (exit 0) without koto.
# Usage: bash skills/coordinate/scripts/board-land_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
for bin in koto jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
T=$(mktemp -d "${TMPDIR:-/tmp}/board-land-engine.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
unset KOTO_BIN KOTO_BOARD_DIR KOTO_BOARD_HASH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME" "$T/work"
PR="$T/plugin"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"

# The skeleton stands in for coordinate.md at the plugin root, so
# coord-log.sh provenance holds for the sessions created from it.
cat > "$TPL" <<'TPLEOF'
---
name: coordinate
version: "1.0"
description: a board and land skeleton for board-land_engine_test.sh
initial_state: start_posture
variables:
  PLUGIN_ROOT:
    description: plugin root
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
  start_posture:
    default_action:
      command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-log.sh" seal --session "{{SESSION_NAME}}" --state start_posture --token "$(bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/posture-read.sh" --no-seal)"'
      capture_stdout_as: POSTURE
      fallback: tick again
    gates:
      verdict:
        type: command
        command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-verdict.sh" --session "{{SESSION_NAME}}" --state start_posture --capture "{{POSTURE}}"'
        overridable: false
    transitions:
      - target: verify
        when:
          gates.verdict.exit_code: 25
      - target: verify
        when:
          gates.verdict.exit_code: 26
  verify:
    accepts:
      prediction:
        type: string
        required: true
      predicted:
        type: enum
        values: [yes]
        required: true
    transitions:
      - target: verify_board
        when:
          predicted: yes
  verify_board:
    default_action:
      command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/board-record.sh" --session "{{SESSION_NAME}}" --pr 12 --repo acme/widgets'
      capture_stdout_as: VERIFIED
      fallback: tick again
    gates:
      verdict:
        type: command
        command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-verdict.sh" --session "{{SESSION_NAME}}" --state verify_board --capture "{{VERIFIED}}"'
        overridable: false
    transitions:
      - target: land
        when:
          gates.verdict.exit_code: 70
      - target: failure
        when:
          gates.verdict.exit_code: 71
      - target: wait
        when:
          gates.verdict.exit_code: 72
      - target: wait
        when:
          gates.verdict.exit_code: 73
      - target: surface
        when:
          gates.verdict.exit_code: 74
      - target: surface
        when:
          gates.verdict.exit_code: 75
      - target: surface
        when:
          gates.verdict.exit_code: 76
  wait:
    accepts:
      go:
        type: enum
        values: [verify]
        required: true
    transitions:
      - target: verify
        when:
          go: verify
  land:
    default_action:
      command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/land-check.sh" --session "{{SESSION_NAME}}" --repo acme/widgets'
      capture_stdout_as: LAND
      fallback: tick again
    gates:
      verdict:
        type: command
        command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-verdict.sh" --session "{{SESSION_NAME}}" --state land --capture "{{LAND}}"'
        overridable: false
    transitions:
      - target: land_merge
        when:
          gates.verdict.exit_code: 80
      - target: surface
        when:
          gates.verdict.exit_code: 81
      - target: surface
        when:
          gates.verdict.exit_code: 82
      - target: verify
        when:
          gates.verdict.exit_code: 53
      - target: failure
        when:
          gates.verdict.exit_code: 84
  land_merge:
    accepts:
      outcome:
        type: enum
        values: [attempted, failed]
        required: true
    transitions:
      - target: merge_confirm
        when:
          outcome: attempted
      - target: failure
        when:
          outcome: failed
  merge_confirm:
    default_action:
      command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/merge-confirm.sh" --session "{{SESSION_NAME}}" --repo acme/widgets'
      capture_stdout_as: MERGE_CONFIRM
      fallback: tick again
    gates:
      verdict:
        type: command
        command: 'bash "{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-verdict.sh" --session "{{SESSION_NAME}}" --state merge_confirm --capture "{{MERGE_CONFIRM}}"'
        overridable: false
    transitions:
      - target: done
        when:
          gates.verdict.exit_code: 90
      - target: done
        when:
          gates.verdict.exit_code: 91
  surface:
    terminal: true
  failure:
    terminal: true
    failure: true
  done:
    terminal: true
---

## start_posture

Posture.

## verify

Predict.

## verify_board

Board.

## wait

Wait.

## land

Land.

## land_merge

Run land-merge.sh.

## merge_confirm

Confirm.

## surface

Surface.

## failure

Failure.

## done

Done.
TPLEOF

# koto refuses a capture holding `=`, so the posture tokens captured here use
# `:` between a step and its value; land-check.sh reads either.
PERMIT="readable merge:permit close:permit teardown:permit"
CL="$PS/coord-log.sh"
state() { printf '%s' "$1" | jq -r .state; }
start() { # start <session> <board case> [posture]
    S=$1
    printf '%s\n' "${3:-$PERMIT}" > "$BT_STATE/posture"
    bt_board "$2"
    printf '{"mergeStateStatus":"CLEAN"}\n' > "$GH_BOARD_DIR/prview-12.out"
    rm -f "$BT_STATE/merge-exec.calls"
    (cd "$T/work" && koto init "$S" --template "$TPL" --var PLUGIN_ROOT="$PR" >/dev/null 2>"$T/init.err") || { cat "$T/init.err"; return 1; }
    eq "$S: start_posture routes to verify" verify "$(state "$(cd "$T/work" && koto next "$S" --no-cleanup 2>/dev/null)")"
}
tick() { (cd "$T/work" && koto next "$@" --no-cleanup 2>/dev/null); }

echo "== verified, permitted, merged =="
start coordinate-demo-20260926T150001Z complete-board || { echo "FAIL: koto init"; exit 1; }
eq "a verified board and a permitted merge reach land_merge in one advance" land_merge "$(state "$(tick "$S" --with-data '{"prediction":"every job green","predicted":"yes"}')")"
case "$(bash "$CL" capture --session "$S" --name VERIFIED)" in "verified 12 $H sealed:"*) ok "VERIFIED is the sealed verified head" ;; *) bad "VERIFIED is the sealed verified head" ;; esac
case "$(bash "$CL" capture --session "$S" --name LAND)" in "permit 12 $H sealed:"*) ok "LAND is the sealed permit" ;; *) bad "LAND is the sealed permit" ;; esac
OUT=$(cd "$T/work" && bash "$PS/land-merge.sh" --session "$S" --repo acme/widgets 2>"$T/err"); rc=$?
eq "land-merge.sh passes provenance and merges" 0 $rc
eq "merge-exec gets the verified sha" "acme/widgets 12 $H" "$(cat "$BT_STATE/merge-exec.calls" 2>/dev/null)"
bt_merged MERGED '["src/main.go"]'; bt_blob main src/main.go aaaa; bt_blob "$H" src/main.go aaaa
eq "merge_confirm routes merged to done" done "$(state "$(tick "$S" --with-data '{"outcome":"attempted"}')")"

echo "== unverified, pending, denied =="
start coordinate-demo-20260926T150002Z dirty
eq "an unverified board routes to failure" failure "$(state "$(tick "$S" --with-data '{"prediction":"green","predicted":"yes"}')")"
start coordinate-demo-20260926T150003Z queued-run
eq "a pending board routes to wait" wait "$(state "$(tick "$S" --with-data '{"prediction":"green","predicted":"yes"}')")"
start coordinate-demo-20260926T150004Z complete-board "readable merge:deny close:permit teardown:permit"
eq "a denied merge routes land to surface" surface "$(state "$(tick "$S" --with-data '{"prediction":"green","predicted":"yes"}')")"

echo "== a board that can't be judged leaves verify_board =="
start coordinate-demo-20260926T150007Z checks-refused
eq "a refused check rollup, green from the Actions jobs, routes to surface" surface "$(state "$(tick "$S" --with-data '{"prediction":"green","predicted":"yes"}')")"
bash "$CL" capture --session "$S" --name LAND >/dev/null 2>&1; eq "and never reaches land" 1 $?
start coordinate-demo-20260926T150010Z checks-refused-rollup-only-required
eq "a check only isRequired names, unseen under the fallback: surface, not land" surface "$(state "$(tick "$S" --with-data '{"prediction":"green","predicted":"yes"}')")"
bash "$CL" capture --session "$S" --name LAND >/dev/null 2>&1; eq "and the run doesn't land it" 1 $?
start coordinate-demo-20260926T150008Z rules-unreadable
eq "an unreadable board routes to wait" wait "$(state "$(tick "$S" --with-data '{"prediction":"green","predicted":"yes"}')")"
eq "and wait takes the next event" verify "$(state "$(tick "$S" --with-data '{"go":"verify"}')")"
start coordinate-demo-20260926T150009Z pr-merged
eq "a pull request merged outside the run routes to surface" surface "$(state "$(tick "$S" --with-data '{"prediction":"green","predicted":"yes"}')")"
case "$(bash "$CL" capture --session "$S" --name VERIFIED)" in "not-open 12 none sealed:"*) ok "VERIFIED is the sealed not-open" ;; *) bad "VERIFIED is the sealed not-open" ;; esac

echo "== --to =="
start coordinate-demo-20260926T150005Z complete-board
eq "--to verify_board without a prediction stays there, the read refused" verify_board "$(state "$(tick "$S" --to verify_board)")"
bash "$CL" capture --session "$S" --name VERIFIED >/dev/null 2>&1; eq "--to verify_board without a prediction leaves no VERIFIED capture" 1 $?
start coordinate-demo-20260926T150006Z complete-board
tick "$S" --with-data '{"prediction":"green","predicted":"yes"}' >/dev/null
tick "$S" --to failure >/dev/null
(cd "$T/work" && bash "$PS/land-merge.sh" --session "$S" --repo acme/widgets >/dev/null 2>&1); rc=$?
eq "a --to in the run makes land-merge.sh refuse" 10 $rc
[ ! -s "$BT_STATE/merge-exec.calls" ] && ok "and merge-exec is never called" || bad "and merge-exec is never called"

echo
echo "board-land engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
