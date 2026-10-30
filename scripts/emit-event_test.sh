#!/usr/bin/env bash
# emit-event_test.sh -- scripts/emit-event.sh sends nothing before the cutoff,
# with the off switch set, or to a sender that fails a discovery check; sends
# only the allowed fields, mapped and shape-checked, under a scrubbed
# environment; and never holds its caller past its deadline or leaves anything
# running.
#
# The cases source the helper and call ee_run with chosen times, against a
# scratch HOME holding a fake sender that records its arguments and its
# environment. The scratch HOME has to pass the same discovery checks a real
# one does, so it is made under the first of $TMPDIR and this checkout's git
# directory whose every directory up to / is owned by this user or root and
# not writable by group or others (a sticky /tmp is writable by others).
#
# Usage: bash scripts/emit-event_test.sh
#        /bin/bash scripts/emit-event_test.sh     # the bash 3.2 floor
set -uo pipefail
. "$(dirname "$0")/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd -P)
HELPER="$HERE/emit-event.sh"
BASH_BIN=$(command -v "${BASH:-bash}")
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
umask 022

PASS=0
FAIL=0
ok() { echo "ok   $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1${2:+: $2}"; FAIL=$((FAIL + 1)); }

# shellcheck source=emit-event.sh
. "$HELPER"

CUT=1794189600
AFTER=$((CUT + 60))

# chain_ok <dir>: every directory from <dir> up to / passes the helper's check.
chain_ok() {
    local d
    d=$(cd -P -- "$1" && pwd -P) || return 1
    while :; do
        ee_mode_ok "$d" dir || return 1
        [ "$d" = / ] && return 0
        d=${d%/*}
        [ -n "$d" ] || d=/
    done
}

T=""
for base in "${TMPDIR:-/tmp}" "$(git -C "$HERE" rev-parse --absolute-git-dir 2>/dev/null)"; do
    [ -n "$base" ] && [ -d "$base" ] || continue
    cand=$(mktemp -d "$base/emit-event-test.XXXXXX") || continue
    cand=$(cd -P -- "$cand" && pwd -P)
    chmod 0755 "$cand"
    if chain_ok "$cand"; then T="$cand"; break; fi
    rm -rf "$cand"
done
if [ -z "$T" ]; then
    echo "FAIL no scratch directory whose path passes the discovery checks"
    exit 1
fi
cleanup() { pkill -f 'sleep 47' 2>/dev/null; rm -rf "$T"; }
ktg_on_exit cleanup

# Tools for the cases: jq and the helpers' needs, plus a koto stub. A run with
# NOTIMEOUT=1 gets a PATH without `timeout`, so the helper's own deadline runs.
BIN="$T/bin"
mkdir -p "$BIN"
for tool in jq sleep cat printf env kill pgrep timeout; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    case "$p" in /*) ln -s "$p" "$BIN/$tool" ;; esac
done
cat >"$BIN/koto" <<'EOF'
#!/bin/sh
# koto stub: answers `session list --execution-dir <dir>` from $KOTO_STUB_MODE.
case "${KOTO_STUB_MODE:-ok}" in
    hang) sleep 47; exit 0 ;;
    fail) exit 1 ;;
esac
cat <<JSON
{"excluded_remote_only":0,"sessions":[
 {"id":"other","session_id":"0000-other","parent_workflow":null},
 {"id":"issue_7","session_id":"sess.issue7.0001","parent_workflow":"coordinate-x"}]}
JSON
EOF
chmod 0755 "$BIN/koto"
NOTO="$T/bin-notimeout"
mkdir -p "$NOTO"
for f in "$BIN"/*; do
    [ "$(basename "$f")" = timeout ] || ln -s "$f" "$NOTO/$(basename "$f")"
done

# new_home: a fresh scratch HOME with a fake sender that records its argv, one
# argument per line, and its environment's names and values.
new_home() {
    H="$T/home.$RANDOM$RANDOM"
    mkdir -p "$H/.local/libexec/fleet"
    SINK="$H/.local/libexec/fleet/event-sink"
    cat >"$SINK" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >"$HOME/sent.args"
/usr/bin/env >"$HOME/sent.env"
case "$(cat "$HOME/mode" 2>/dev/null)" in
    slow) sleep 47 & sleep 47 ;;
    fail) exit 3 ;;
esac
exit 0
EOF
    chmod 0755 "$SINK"
}

# run <now> [args...]: ee_run in a subshell with HOME=$H and the stub PATH.
run() {
    local now="$1"
    shift
    (
        export HOME="$H"
        if [ "${NOTIMEOUT:-0}" = 1 ]; then PATH="$NOTO"; else PATH="$BIN"; fi
        export PATH
        ee_run "$now" "$@"
    )
}
sent() { [ -f "$H/sent.args" ]; }
has_arg() { grep -qxF -- "$1" "$H/sent.args"; }

EV=(event --scope unit-cost --kind landed unit.request=req-1 unit.pr=github.com/acme/widgets#12)

echo "== the date gate =="
new_home
run $((CUT - 1)) "${EV[@]}"
sent && bad "one second before the cutoff sends nothing" || ok "one second before the cutoff sends nothing"
new_home
run "$CUT" "${EV[@]}"
sent && ok "at the cutoff it sends" || bad "at the cutoff it sends"
for clock in "" "abc" "-5" "1794189600.5" "$(printf '1794189700\n1')"; do
    new_home
    run "$clock" "${EV[@]}"
    sent && bad "an unreadable clock [$clock] counts as before" || ok "an unreadable clock [$clock] counts as before"
done

echo "== the command line takes /bin/date's reading =="
new_home
NOW=$(/bin/date -u +%s)
( export HOME="$H" PATH="$BIN"; "$BASH_BIN" "$HELPER" "${EV[@]}" ); rc=$?
[ "$rc" = 0 ] && ok "the command line exits 0" || bad "the command line exits 0" "rc=$rc"
if [ "$NOW" -lt "$CUT" ]; then
    sent && bad "before 2026-11-09T02:00Z the command line sends nothing" || ok "before 2026-11-09T02:00Z the command line sends nothing"
else
    sent && ok "after the cutoff the command line sends" || bad "after the cutoff the command line sends"
fi
new_home
( export HOME="$H" PATH="$BIN" EE_NOT_BEFORE=0; "$BASH_BIN" "$HELPER" "${EV[@]}" )
if [ "$NOW" -lt "$CUT" ]; then
    sent && bad "no variable moves the cutoff" || ok "no variable moves the cutoff"
fi
( export HOME="$H" PATH="$BIN"; "$BASH_BIN" "$HELPER" --now "$AFTER" "${EV[@]}"; "$BASH_BIN" "$HELPER" "$AFTER" "${EV[@]}" )
if [ "$NOW" -lt "$CUT" ]; then
    sent && bad "no argument moves the cutoff" || ok "no argument moves the cutoff"
fi
STUBDATE="$T/datebin"
mkdir -p "$STUBDATE"
printf '#!/bin/sh\necho %s\n' "$AFTER" >"$STUBDATE/date"
chmod 0755 "$STUBDATE/date"
new_home
( export HOME="$H" PATH="$STUBDATE:$BIN"; "$BASH_BIN" "$HELPER" "${EV[@]}" )
if [ "$NOW" -lt "$CUT" ]; then
    sent && bad "a date earlier on PATH does not lift the gate" || ok "a date earlier on PATH does not lift the gate"
fi
( export HOME="$H" PATH="$BIN"; "$BASH_BIN" "$HELPER" ); rc=$?
[ "$rc" = 0 ] && ok "a usage error exits 0" || bad "a usage error exits 0" "rc=$rc"

echo "== the off switch =="
new_home
( export FLEET_EVENT_SINK=off; run "$AFTER" "${EV[@]}" )
sent && bad "FLEET_EVENT_SINK=off sends nothing" || ok "FLEET_EVENT_SINK=off sends nothing"
for v in on OFF 0 "$T/elsewhere" ""; do
    new_home
    ( export FLEET_EVENT_SINK="$v"; run "$AFTER" "${EV[@]}" )
    sent && ok "FLEET_EVENT_SINK=[$v] is not the off switch and points nowhere" || bad "FLEET_EVENT_SINK=[$v] is not the off switch"
done

echo "== discovery =="
new_home
rm -f "$SINK"
run "$AFTER" "${EV[@]}"; rc=$?
[ "$rc" = 0 ] && ok "no sender: nothing runs, exit 0" || bad "no sender: exit 0" "rc=$rc"
new_home
mv "$SINK" "$H/real-sink"
ln -s "$H/real-sink" "$SINK"
run "$AFTER" "${EV[@]}"
sent && bad "a symlinked sender is refused" || ok "a symlinked sender is refused"
new_home
chmod 0644 "$SINK"
run "$AFTER" "${EV[@]}"
sent && bad "a sender that isn't executable is refused" || ok "a sender that isn't executable is refused"
new_home
chmod 0775 "$SINK"
run "$AFTER" "${EV[@]}"
sent && bad "a group-writable sender is refused" || ok "a group-writable sender is refused"
new_home
chmod 0757 "$SINK"
run "$AFTER" "${EV[@]}"
sent && bad "an other-writable sender is refused" || ok "an other-writable sender is refused"
for d in .local/libexec/fleet .local/libexec .local ""; do
    new_home
    chmod 0775 "$H/$d"
    run "$AFTER" "${EV[@]}"
    sent && bad "a group-writable directory [~/$d] above it is refused" || ok "a group-writable directory [~/$d] above it is refused"
    chmod 0755 "$H/$d"
    new_home
    chmod 0757 "$H/$d"
    run "$AFTER" "${EV[@]}"
    sent && bad "an other-writable directory [~/$d] above it is refused" || ok "an other-writable directory [~/$d] above it is refused"
    chmod 0755 "$H/$d"
done
new_home
mkdir "$SINK.d"
rm -f "$SINK"
mv "$SINK.d" "$SINK"
run "$AFTER" "${EV[@]}"
sent && bad "a directory at the sender's path is refused" || ok "a directory at the sender's path is refused"
new_home
mkdir -p "$T/shared"
chmod 0777 "$T/shared"
mv "$H/.local/libexec/fleet" "$T/shared/fleet"
ln -s "$T/shared/fleet" "$H/.local/libexec/fleet"
run "$AFTER" "${EV[@]}"
sent && bad "a symlinked directory is checked on its physical path" || ok "a symlinked directory is checked on its physical path"
chmod 0755 "$T/shared"
new_home
H_SAVED="$H"
( export HOME="${H#/}"; PATH="$BIN"; ee_run "$AFTER" "${EV[@]}" )
[ -f "$H_SAVED/sent.args" ] && bad "a relative HOME is refused" || ok "a relative HOME is refused"
# Ownership by another uid can't be arranged without root; these pin the two
# owners that pass, read from /bin/ls -ldn as the helper reads them.
ee_mode_ok "$SINK" file && ok "a sender owned by this uid passes" || bad "a sender owned by this uid passes"
ee_mode_ok / dir && ok "/ (owned by root) passes" || bad "/ (owned by root) passes"
ee_mode_ok "$SINK" dir && bad "a file is not taken for a directory" || ok "a file is not taken for a directory"

echo "== the fields =="
new_home
run "$AFTER" event --scope unit-cost --kind dispatched \
    "unit.topic=Fix: the queue's  worker (#12)" "unit.milestone=Feature 4" "unit.leg=work-on" \
    "unit.roadmap=ROADMAP-plugin system" unit.request=req-dddfb324 unit.requested_at=1794189000 \
    unit.repo=acme/widgets unit.entry_point=work-on unit.mode=plan_backed \
    unit.worker_session=0b1c2d3e-aaaa unit.worker_dispatch=d-77 unit.scope_slug=devex
for want in "event" "--scope" "unit-cost" "--kind" "dispatched" \
    "unit.topic=Fix:_the_queue_s__worker___12_" "unit.milestone=Feature_4" "unit.leg=work-on" \
    "unit.roadmap=ROADMAP-plugin_system" "unit.request=req-dddfb324" "unit.requested_at=1794189000" \
    "unit.repo=acme/widgets" "unit.entry_point=work-on" "unit.mode=plan_backed" \
    "unit.worker_session=0b1c2d3e-aaaa" "unit.worker_dispatch=d-77" "unit.scope_slug=devex"; do
    has_arg "$want" && ok "sends [$want]" || bad "sends [$want]" "$(tr '\n' ' ' <"$H/sent.args" 2>/dev/null)"
done
[ "$(wc -l <"$H/sent.args" | tr -d ' ')" = 17 ] && ok "sends nothing else" || bad "sends nothing else" "$(cat "$H/sent.args")"
grep -q -e '^--at' -e '^--carry' "$H/sent.args" && bad "passes no --at or --carry" || ok "passes no --at or --carry"

LONG=$(printf 'x%.0s' $(seq 1 300))
new_home
run "$AFTER" event --scope unit-cost --kind landed "unit.topic=$LONG" "unit.request=$LONG"
has_arg "unit.topic=$(printf 'x%.0s' $(seq 1 128))" && ok "a long topic is cut at 128" || bad "a long topic is cut at 128"
grep -q '^unit.request=' "$H/sent.args" && bad "a long id is dropped, not cut" || ok "a long id is dropped, not cut"

new_home
run "$AFTER" event --scope unit-cost --kind landed \
    "unit.request=$(printf 'req-1\nunit.pr=github.com/evil/x#1')" "unit.koto_session=--kind" \
    "unit.repo=--scope" "unit.pr=https://github.com/acme/widgets/pull/12" "unit.pr=github.com/acme/widgets#0" \
    "unit.requested_at=9223372036854775808" "unit.requested_at=-1" "unit.secret=abc" "GH_TOKEN=abc" \
    "unit.outcome=merged ok" "other.unit=x" "unit.mode=" "plain" "unit.worker_dispatch=d-1"
for gone in "unit.request=" "unit.koto_session=" "unit.repo=" "unit.pr=" "unit.requested_at=" \
    "unit.secret=" "GH_TOKEN=" "unit.outcome=" "other.unit=" "unit.mode=" "plain"; do
    grep -q "^$gone" "$H/sent.args" && bad "drops [$gone...]" "$(cat "$H/sent.args")" || ok "drops [$gone...]"
done
has_arg "unit.worker_dispatch=d-1" && ok "keeps the fields that pass" || bad "keeps the fields that pass"
new_home
run "$AFTER" event --scope unit-cost --kind landed unit.requested_at=9223372036854775807 unit.pr=github.com/acme/widgets#12
has_arg "unit.requested_at=9223372036854775807" && ok "2^63-1 is an int" || bad "2^63-1 is an int"
has_arg "unit.pr=github.com/acme/widgets#12" && ok "a pull request reference passes" || bad "a pull request reference passes"
for k in "unit-cost:merged" "unit_cost:landed" "workflow:landed" "unit-cost:"; do
    new_home
    run "$AFTER" event --scope "${k%%:*}" --kind "${k#*:}" unit.request=req-1
    sent && bad "scope and kind [$k] outside the table send nothing" || ok "scope and kind [$k] outside the table send nothing"
done
new_home
run "$AFTER" send --scope unit-cost unit.request=req-1
sent && bad "only the event form is taken" || ok "only the event form is taken"

echo "== the scrubbed environment =="
new_home
(
    export GH_TOKEN=ghp_fake GITHUB_TOKEN=x ANTHROPIC_API_KEY=x KOTO_SESSION_CLOUD_SECRET_KEY=x FOO=bar
    export CLAUDE_CODE_SESSION_ID=sess-1 NIWA_DISPATCH_ID=disp-1 NIWA_WORKSPACE=ws-1 NIWA_OTHER=x
    export LANG=en_US.UTF-8 LC_ALL='bad locale;x' FLEET_EVENT_SINK=on
    run "$AFTER" "${EV[@]}"
)
names=$(sed 's/=.*//' "$H/sent.env" | grep -v -x -e PWD -e SHLVL -e _ -e OLDPWD | sort | tr '\n' ' ')
[ "$names" = "CLAUDE_CODE_SESSION_ID HOME LANG NIWA_DISPATCH_ID NIWA_WORKSPACE PATH " ] \
    && ok "the sender gets only the allow-list" || bad "the sender gets only the allow-list" "$names"
grep -qx "PATH=/usr/bin:/bin:/usr/sbin:/sbin" "$H/sent.env" && ok "PATH is the fixed one" || bad "PATH is the fixed one"
grep -qx "HOME=$H" "$H/sent.env" && ok "HOME is passed" || bad "HOME is passed"
grep -qx "LANG=en_US.UTF-8" "$H/sent.env" && ok "a locale name is passed" || bad "a locale name is passed"

echo "== the koto session id =="
new_home
run "$AFTER" event --scope unit-cost --kind session_opened --koto-dir "$T" unit.koto_session=issue_7 unit.outcome=new
has_arg "unit.koto_session_id=sess.issue7.0001" && ok "--koto-dir adds the session's id" || bad "--koto-dir adds the session's id" "$(cat "$H/sent.args" 2>/dev/null)"
has_arg "unit.parent_session=coordinate-x" && ok "and its koto parent" || bad "and its koto parent"
new_home
run "$AFTER" event --scope unit-cost --kind session_opened --koto-dir "$T" unit.koto_session=issue_7 unit.parent_session=given unit.koto_session_id=forged
has_arg "unit.parent_session=given" && ! grep -q '^unit.parent_session=coordinate-x' "$H/sent.args" && ok "a passed parent wins" || bad "a passed parent wins"
grep -q '^unit.koto_session_id=forged' "$H/sent.args" && bad "a passed session id is never sent" || ok "a passed session id is never sent"
new_home
run "$AFTER" event --scope unit-cost --kind session_opened --koto-dir "$T" unit.koto_session=issue_99
grep -q '^unit.koto_session_id=' "$H/sent.args" && bad "an unknown session sends no id" || ok "an unknown session sends no id"
for dir in "relative/dir" "$T/../x" "-x" ""; do
    new_home
    ( export KOTO_STUB_MODE=ok; run "$AFTER" event --scope unit-cost --kind session_opened --koto-dir "$dir" unit.koto_session=issue_7 )
    grep -q '^unit.koto_session_id=' "$H/sent.args" && bad "--koto-dir [$dir] is not read" || ok "--koto-dir [$dir] is not read"
    sent && ok "and the rest is still sent [$dir]" || bad "and the rest is still sent [$dir]"
done
new_home
( export KOTO_STUB_MODE=fail; run "$AFTER" event --scope unit-cost --kind session_opened --koto-dir "$T" unit.koto_session=issue_7 )
sent && ! grep -q '^unit.koto_session_id=' "$H/sent.args" && ok "a failed koto read leaves the id out and sends the rest" || bad "a failed koto read"
new_home
start=$(date +%s)
( export KOTO_STUB_MODE=hang; NOTIMEOUT=1 run "$AFTER" event --scope unit-cost --kind session_opened --koto-dir "$T" unit.koto_session=issue_7 )
took=$(( $(date +%s) - start ))
[ "$took" -le 5 ] && ok "a hung koto read is cut at its deadline (${took}s)" || bad "a hung koto read is cut at its deadline" "${took}s"
sent && ok "and the event still goes" || bad "and the event still goes"
new_home
rm -f "$SINK"
( export KOTO_STUB_MODE=hang; run "$AFTER" event --scope unit-cost --kind session_opened --koto-dir "$T" unit.koto_session=issue_7 ) &
wait $!
pgrep -f 'sleep 47' >/dev/null && bad "with no sender koto is never read" || ok "with no sender koto is never read"
( export KOTO_STUB_MODE=hang; run $((CUT - 1)) event --scope unit-cost --kind session_opened --koto-dir "$T" unit.koto_session=issue_7 )
pgrep -f 'sleep 47' >/dev/null && bad "before the cutoff koto is never read" || ok "before the cutoff koto is never read"

echo "== the deadline =="
for nt in 0 1; do
    if [ "$nt" = 0 ] && [ ! -e "$BIN/timeout" ]; then
        echo "skip the timeout(1) path: no timeout on this host"
        continue
    fi
    label=$([ "$nt" = 1 ] && echo "the helper's own deadline" || echo "timeout(1)")
    new_home
    echo slow >"$H/mode"
    start=$(date +%s)
    ( NOTIMEOUT=$nt run "$AFTER" "${EV[@]}" ); rc=$?
    took=$(( $(date +%s) - start ))
    [ "$rc" = 0 ] && [ "$took" -le 5 ] && ok "$label: a hanging sender returns within the bound (${took}s), exit 0" || bad "$label: a hanging sender" "rc=$rc took=${took}s"
    sleep 1
    pgrep -f 'sleep 47' >/dev/null && bad "$label: nothing the sender started is left running" || ok "$label: nothing the sender started is left running"
    pkill -f 'sleep 47' 2>/dev/null
    new_home
    echo fail >"$H/mode"
    ( NOTIMEOUT=$nt run "$AFTER" "${EV[@]}" ); rc=$?
    [ "$rc" = 0 ] && sent && ok "$label: a failing sender still exits 0" || bad "$label: a failing sender" "rc=$rc"
done
new_home
printf 'not a script\n' >"$SINK"
( export HOME="$H" PATH="$BIN"; "$BASH_BIN" "$HELPER" "${EV[@]}" ); rc=$?
[ "$rc" = 0 ] && ok "a broken sender never fails the command line" || bad "a broken sender" "rc=$rc"

echo
echo "emit-event: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
