#!/usr/bin/env bash
# deliver-move-engine_test.sh -- a /deliver run moved between workspaces keeps
# its /execute leg (PRD R14), on real koto over simulated hosts sharing koto's
# cloud backend (skills/coordinate/scripts/testdata/cloud-hosts.sh over its
# fake-s3.py), with deliver.md shipped and the stand-in children of
# testdata/engine-lib.sh.
#
# Two workspaces on one host share the host's request store; two hosts have
# one each. Every case parks a /deliver run at execute_run with the stand-in
# /execute attached to the run's execute leg and left live, then moves:
#
#   1. new-after-import (one host, workspaces A and B): execute-<topic> is
#      imported into B, and a new /deliver run in B opens its own request,
#      which abandons A's (request_state closed, its execute leg abandoned);
#      the moved execute session re-inits with --attach-live on the new
#      execute leg, finishes, and the new run ends done with its result
#   2. resumed-in-place (one host): deliver-<topic> and execute-<topic> are
#      both imported into B; the execute stand-in finishes in B, and the
#      imported /deliver, ticked in B, reads the result on its original leg
#      and ends done
#   3. two hosts with separate request stores: both sessions imported from
#      host p to host q; a tick on q finds no such request there and ends
#      done_error with step deliver:child-absent, reason
#      execute-leg-lost:request_not_found and execute_state work (the
#      stand-in's state), in the result and in deliver-report.sh's lines;
#      then a new /deliver on q binds the moved execute session to its own
#      new leg and gets its result
#   4. the source: a tick of the moved /deliver session in its source
#      workspace answers koto's session_migrated
#
# The deliver session moves with `skill-session.sh import deliver`, which
# compiles the shipped deliver.md on the importing side itself; when this
# checkout's path is outside koto's --var allowlist the cases run a derived
# copy of deliver.md and move it with a raw compile and `koto session import`.
# The stand-in execute session always moves by a raw compile and import.
#
# Needs koto (with --koto-leg and `session import`), jq, git and python3; SKIPs
# (exit 0) without one.
# Usage: bash skills/deliver/scripts/deliver-move-engine_test.sh
# Exit codes: 0 all pass (or SKIP); 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
TEMPLATE="$REPO_ROOT/skills/deliver/koto-templates/deliver.md"
SS="$REPO_ROOT/scripts/skill-session.sh"

for bin in koto jq git python3; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine-backed cases did not run"; exit 0; }
done
if ! koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    echo "SKIP: this koto predates --koto-leg -- no case ran"
    exit 0
fi
if ! koto session import --help >/dev/null 2>&1; then
    echo "SKIP: this koto has no session import -- no case ran"
    exit 0
fi
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-move-engine-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CEILING_DIRECTORIES="$T"
export MERGE_CONFIRM_WAIT_SECS=0

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }

KOTO_ALLOW='^[a-zA-Z0-9._/:@ -]*$'
TPL="$TEMPLATE"
LOCALIZED=0
if [[ $REPO_ROOT =~ $KOTO_ALLOW ]]; then
    PLUGIN_ROOT_VAR="$REPO_ROOT"
else
    ln -s "$REPO_ROOT" "$T/plugin"
    if [[ $T/plugin =~ $KOTO_ALLOW ]]; then
        PLUGIN_ROOT_VAR="$T/plugin"
    else
        mkdir -p "$T/derived"
        TPL="$T/derived/deliver.md"
        sed "s#{{PLUGIN_ROOT}}#$REPO_ROOT#g" "$TEMPLATE" >"$TPL"
        PLUGIN_ROOT_VAR=/koto-probe
        LOCALIZED=1
        echo "  note: this checkout's path is outside koto's --var allowlist, so these cases run a"
        echo "        copy of deliver.md with the path written in for {{PLUGIN_ROOT}}, moved by a raw import"
    fi
fi

BIN="$T/bin"
mkdir -p "$BIN"
cp "$HERE/testdata/gh" "$BIN/gh"
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# shellcheck source=testdata/engine-lib.sh
. "$HERE/testdata/engine-lib.sh"

CLOUD_HOSTS_S3="$REPO_ROOT/skills/coordinate/scripts/testdata/fake-s3.py"
# shellcheck source=../../coordinate/scripts/testdata/cloud-hosts.sh
. "$REPO_ROOT/skills/coordinate/scripts/testdata/cloud-hosts.sh"
trap 's3_stop; case "$T" in */deliver-move-engine-test.*) rm -rf "$T" ;; esac' EXIT
if ! s3_start; then
    fail "the fake S3 server starts" "$(cat "$T/s3/log" 2>&1)"
    echo "Results: $PASS passed, $FAIL failed"
    exit 1
fi

# --- where koto runs ---------------------------------------------------------------

# on <host> <workspace> -- every helper below (k, through engine-lib.sh's start,
# tick, state, result, ctx and children) runs koto in that workspace, as that
# host. R is the workspace, a clone of the topic's origin.
ON_H=""; ON_W=""
on() { ON_H="$1"; ON_W="$2"; R=$(ws_path "$1" "$2"); }
k() { ws_on "$ON_H" "$ON_W" koto "$@"; }

# clone_into <host> <workspace> -- the workspace becomes a clone of this topic's
# origin on docs/<topic>, with .koto/ (koto's own configuration and sessions)
# kept out of git.
clone_into() {
    local w
    w=$(ws_path "$1" "$2") || { fail "$TOPIC: workspace $1/$2 exists"; return 1; }
    git -C "$w" init -q -b main
    git -C "$w" remote add origin "$T/origin-$TOPIC.git"
    git -C "$w" fetch -q origin
    git -C "$w" checkout -q -b "docs/$TOPIC" "origin/docs/$TOPIC"
    printf '.koto/\n' >> "$w/.git/info/exclude"
}

# move_fixture <topic> <host> <ws>... -- the topic's origin and gh model
# (engine-lib.sh's fixture), cloned into each workspace named.
move_fixture() {
    local topic="$1" h="$2"
    shift 2
    fixture "$topic" single-pr
    for w in "$@"; do clone_into "$h" "$w"; done
}

# import_deliver <from-host> <from-ws> -- deliver-<topic> into the current
# workspace: skill-session.sh import deliver, or a raw import of the derived copy.
import_deliver() {
    local from
    from=$(ws_path "$1" "$2")
    if [ "$LOCALIZED" -eq 0 ]; then
        IMPORT_OUT=$(ws_on "$ON_H" "$ON_W" bash "$SS" import deliver "$TOPIC" --from "$from" 2>"$T/imp.err")
        IMPORT_RC=$?
        eq "$TOPIC: skill-session.sh import deliver imports the deliver session" "0 imported=deliver-$TOPIC" "$IMPORT_RC $IMPORT_OUT"
        [ "$IMPORT_RC" -eq 0 ] || fail "$TOPIC: import deliver's diagnostic" "$(cat "$T/imp.err")"
    else
        k template compile "$TPL" >/dev/null 2>"$T/imp.err" || fail "$TOPIC: the derived deliver.md compiles here" "$(cat "$T/imp.err")"
        k session import "deliver-$TOPIC" --from "$from" >/dev/null 2>"$T/imp.err" \
            || fail "$TOPIC: the deliver session imports" "$(cat "$T/imp.err")"
    fi
}
# import_execute <from-host> <from-ws> -- the stand-in execute-<topic>, by a
# raw compile and import.
import_execute() {
    local from
    from=$(ws_path "$1" "$2")
    k template compile "$T/tpl/execute.md" >/dev/null 2>"$T/imp.err" \
        || fail "$TOPIC: the stand-in execute template compiles here" "$(cat "$T/imp.err")"
    k session import "execute-$TOPIC" --from "$from" >"$T/imp.out" 2>"$T/imp.err" \
        || fail "$TOPIC: the execute session imports" "$(cat "$T/imp.out" "$T/imp.err")"
}
# leg_of <request> <leg> <jq> -- a value of a leg of a request in this host's store.
leg_of() { k request get "$1" 2>/dev/null | jq -r --arg l "$2" "(.request // .) | .legs[\$l] | $3"; }
req_of() { k request get "$1" 2>/dev/null | jq -r "(.request // .) | $2"; }
READY='{"outcome":"ready-awaiting-merge","pr":"https://github.com/acme/widgets/pull/42","waiting":"https://github.com/acme/widgets/pull/42:human","reason":"merge-not-requested","repos":"acme/widgets"}'
# park -- a /deliver run here, at execute_run with the stand-in /execute
# attached to its execute leg and left live. Sets REQ_A.
park() {
    start auto && to_execute_run
    eq "$TOPIC: the run is parked at execute_run" execute_run "$(state)"
    child_attach execute
    REQ_A="$REQ"
    eq "$TOPIC: the stand-in /execute is bound to the execute leg" "execute-$TOPIC" "$(leg_of "$REQ_A" execute '.bound_child // "none"')"
}

host_make h
for w in a1 b1 a2 b2; do ws_make h "$w"; done
host_make p
host_make q

# --- 1. a new /deliver after the import ------------------------------------------------

echo "== 1. one host: a new /deliver after the import gets the result on its new leg =="
move_fixture mv-new h a1 b1
on h a1
park
on h b1
import_execute h a1
eq "mv-new: the moved execute session is live in B at its state" work "$(k status "execute-$TOPIC" 2>/dev/null | jq -r '.current_state // "gone"')"
start auto
REQ_B="$REQ"
if [ -n "$REQ_B" ] && [ "$REQ_B" != "$REQ_A" ]; then pass "mv-new: the new run opened its own request"; else fail "mv-new: the new run opened its own request" "[$REQ_A] [$REQ_B]"; fi
eq "mv-new: the old request is closed" closed "$(req_of "$REQ_A" '.request_state')"
eq "mv-new: the old request's execute leg reads abandoned" abandoned "$(leg_of "$REQ_A" execute '.disposition')"
to_execute_run
eq "mv-new: the new run reaches execute_run" execute_run "$(state)"
child_attach execute --attach-live
eq "mv-new: the moved execute session is bound to the new leg" "execute-$TOPIC" "$(leg_of "$REQ_B" execute '.bound_child // "none"')"
child_finish execute "$READY"
tick
expect "mv-new: the new run gets /execute's promoted result" done outcome=ready-awaiting-merge "pr=$URL"
eq "mv-new: the new leg reads resolved, promoted" "resolved promoted" "$(leg_of "$REQ_B" execute '"\(.disposition) \(.result_source // .source)"')"

# --- 2. resumed in place --------------------------------------------------------------------

echo "== 2. one host: the /deliver session resumed in place gets the result on its original leg =="
move_fixture mv-resume h a2 b2
on h a2
park
on h b2
import_deliver h a2
import_execute h a2
eq "mv-resume: the imported /deliver is at execute_run" execute_run "$(state)"
child_finish execute "$READY"
eq "mv-resume: the original leg reads resolved, promoted" "resolved promoted" "$(leg_of "$REQ_A" execute '"\(.disposition) \(.result_source // .source)"')"
tick
expect "mv-resume: the imported /deliver ends done with the result" done outcome=ready-awaiting-merge "pr=$URL"

# --- 4. the source answers session_migrated ----------------------------------------------------

echo "== 4. the source workspace's tick answers session_migrated =="
on h a2
SRC=$(k next "deliver-$TOPIC" --no-cleanup 2>&1)
SRC_RC=$?
if [ "$SRC_RC" -ne 0 ] && printf '%s' "$SRC" | grep -q session_migrated; then
    pass "mv-resume: the source's tick refuses with session_migrated"
else
    fail "mv-resume: the source's tick refuses with session_migrated" "rc=$SRC_RC $(printf '%s' "$SRC" | head -c 400)"
fi

# --- 3. two hosts ------------------------------------------------------------------------------

echo "== 3. two hosts: a store without the request loses the leg; a new /deliver there gets the result =="
move_fixture mv-hosts p work
clone_into q work
on p work
park
on q work
import_deliver p work
import_execute p work
tick
expect "mv-hosts: a request this host's store doesn't hold" done_error outcome=error step=deliver:child-absent \
    reason=execute-leg-lost:request_not_found execute_state=work
REPORT=$(k status "deliver-$TOPIC" 2>/dev/null | bash "$HERE/deliver-report.sh")
eq "mv-hosts: the report names the lost leg and the execute session's state" "outcome=error
step=deliver:child-absent
reason=execute-leg-lost:request_not_found
execute_state=work" "$REPORT"
eq "mv-hosts: the moved execute session is untouched" work "$(k status "execute-$TOPIC" 2>/dev/null | jq -r '.current_state // "gone"')"
# A new /deliver here: this host's store opens the run a request of its own,
# and the moved execute session, still live, is bound to that leg. If koto
# refuses the binding, the reason is in the failure below; nothing re-legs it.
k session cleanup "deliver-$TOPIC" >/dev/null 2>"$T/cleanup.err" || fail "mv-hosts: the finished /deliver is cleaned up" "$(cat "$T/cleanup.err")"
start auto && to_execute_run
eq "mv-hosts: the new run reaches execute_run on q" execute_run "$(state)"
REQ_Q="$REQ"
if child_attach execute --attach-live; then
    eq "mv-hosts: the moved execute session is bound to q's new leg" "execute-$TOPIC" "$(leg_of "$REQ_Q" execute '.bound_child // "none"')"
    child_finish execute "$READY"
    tick
    expect "mv-hosts: the new /deliver on q gets the result" done outcome=ready-awaiting-merge "pr=$URL"
else
    echo "  note: koto refused binding a session imported from another host's store to a new leg (above);"
    echo "        that binding is koto's to provide, and this suite adds no re-leg to work around it"
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
