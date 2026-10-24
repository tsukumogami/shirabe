#!/usr/bin/env bash
# unit-removed_test.sh -- unit-removed.sh, the on-reap step and the sweep it
# starts, run with niwa's environment over a stub Claude home, koto sessions
# and a koto request on disk, the gh and koto stand-ins, the real record
# scripts and the real cost capture (unit-cost.sh). The sweep runs with a
# scrubbed environment, so the stand-ins are reached through wrappers on PATH
# that carry their stores.
#
# Covers: a unit niwa removed, whose koto work-on session ran in the instance
# and whose koto request names a live coordinator holding the leg key,
# captured end to end: record exits 0 at once, printing one line, while the
# sweep's capture is held on a fifo (the suite reads the removal record, then
# releases it); once the sweep ends the coordinator's session holds one cost
# entry whose "niwa.dispatch.id" is the reap key, with the worker's tokens and
# every session's state times measured, dispatch from the koto request, and
# the figures that needed the removed job or a pull request not recoverable,
# no source; the removed-mode archive and its teardown.json; the record
# deleted; the step passes the (dummy) GH_TOKEN, GITHUB_TOKEN and GH_HOST
# through its scrubbed environment, and every gh call the sweep makes runs
# with an empty GH_CONFIG_DIR of the sweep's own. requested_by
# ended: the entry goes to the scope slug's one live run. With no GH_TOKEN the
# sweep still archives, keeps the record pending github with its attempt
# counted, posts nothing, and the stub gh records no call. A request whose
# requested_by holds no leg key for it: the record kept, no coordinator,
# nothing posted, its removals.log line written, and, its removal more than
# 24 hours old, a stale line after it; restored, the next sweep captures it.
# A pending github record is captured by a later sweep with the token, and
# one whose unit is already recorded is deleted, already recorded. Two sweeps
# over one record capture it once, the second passing it over; a record
# written while a sweep runs is handled by it; a lock whose holder is gone is
# taken over; a sweep with no record makes no call and writes no log; start
# runs the sweep in the background. A record outside its shape deleted. Each
# refusal of record (no reap key, a key
# equal to the session id, a key starting with -, a path holding .., a path
# outside the directory record runs in, the workspace root itself with or
# without a trailing /, a path with a trailing / or a newline, a session id
# that isn't one, a removals directory that is a
# symbolic link or not mode 0700, the script writable by group or others):
# one line, no record, exit 0. A second removal of the same dispatch id at the
# same path keeps removed_at; one at another path replaces the record.
#
# Usage: bash skills/coordinate/scripts/unit-removed_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
export HOME="$T/home" XDG_STATE_HOME="$T/state" XDG_DATA_HOME="$T/data" KOTO_REQUESTS="$T/requests"
unset TEARDOWN_ARCHIVE_DIR TEARDOWN_KOTO_SESSIONS TEARDOWN_CLAUDE_HOME NIWA_REAP_KEY NIWA_SESSION_ID NIWA_INSTANCE_PATH
# A dummy token for the stub gh: the sweep makes GitHub calls only with one,
# and the step passes it through its scrubbed environment.
export GH_TOKEN=stub-token
mkdir -p "$HOME" "$KOTO_REQUESTS"
UR="$HERE/unit-removed.sh"
RA="$HERE/record-append.sh"
FX="$HERE/testdata/unit-cost"
KEY=2026-10-01-feat-x-0a1b2c3d
S=coordinate-roadmap-x-20261001T080000Z
S2=coordinate-roadmap-x-20261002T080000Z
# The workspace root as the shell names it (a TMPDIR ending in / would put
# // in a path built from $T), as niwa names an instance under it.
mkdir -p "$T/ws"
WS=$(cd "$T/ws" && pwd)
IP="$WS/inst-feat-x"
SID=0a1b2c3d-77aa
DID=dsp-feat-x.7
R="$XDG_STATE_HOME/shirabe/removals"

# The stand-ins with their stores, for the sweep's scrubbed environment. A
# fifo at $T/hold.<tool> holds that tool's next call until the suite writes
# to it. Each call logs the GitHub environment it was given, one
# `<GH_CONFIG_DIR>|<entries in it>|<GITHUB_TOKEN>|<GH_HOST>` line in
# $T/<tool>.env.
mkdir -p "$T/bin"
for tool in koto gh; do
    cat >"$T/bin/$tool" <<EOF
#!/bin/sh
if [ -p '$T/hold.$tool' ]; then cat '$T/hold.$tool' >/dev/null; rm -f '$T/hold.$tool'; fi
n=0
[ -n "\${GH_CONFIG_DIR:-}" ] && n=\$(ls -A "\$GH_CONFIG_DIR" 2>/dev/null | wc -l | tr -d ' ')
printf '%s|%s|%s|%s\n' "\${GH_CONFIG_DIR:-}" "\$n" "\${GITHUB_TOKEN:-}" "\${GH_HOST:-}" >>'$T/$tool.env'
GH_DB='$GH_DB' KOTO_STORE='$KOTO_STORE' KOTO_COMPILED_HASH=feedface
export GH_DB KOTO_STORE KOTO_COMPILED_HASH
exec '$HERE/testdata/$tool' "\$@"
EOF
    chmod +x "$T/bin/$tool"
done
PATH="$T/bin:$PATH"
export PATH

# rec <reap key> <session id> <instance path> [script]: the on-reap step as
# niwa runs it, from the workspace root; an empty value is left unset.
rec() {
    local s=${4:-$UR}
    set -- "${1:-}" "${2:-}" "${3:-}"
    (
        cd "$WS" || exit 9
        [ -n "$1" ] && export NIWA_REAP_KEY="$1"
        [ -n "$2" ] && export NIWA_SESSION_ID="$2"
        [ -n "$3" ] && export NIWA_INSTANCE_PATH="$3"
        bash "$s" record
    )
}
# wait_gone <file> <secs>: 0 once the file is gone.
wait_gone() {
    local i=0
    while [ -e "$1" ]; do
        [ "$i" -ge $(($2 * 5)) ] && return 1
        sleep 0.2
        i=$((i + 1))
    done
}
# count <path>...: how many of the paths exist (an unmatched glob stays a pattern).
count() {
    local n=0 p
    for p in "$@"; do [ -e "$p" ] && n=$((n + 1)); done
    echo "$n"
}
nrecords() { count "$R"/*.json; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
# manifest_ok <archive>: ok when every MANIFEST line's file has its hash and size.
manifest_ok() {
    local h b p
    [ -s "$1/MANIFEST" ] || { echo "no MANIFEST"; return; }
    while read -r h b p; do
        [ "$(sha <"$1/$p")" = "$h" ] && [ "$(wc -c <"$1/$p" | tr -d ' ')" = "$b" ] || { echo "bad $p"; return; }
    done <"$1/MANIFEST"
    echo ok
}
# costs <session>: the session's cost entries' objects, as a JSON array.
costs() {
    bash "$RA" --session "$1" --list 2>/dev/null | jq -c '[.[] | select(.kind == "cost") | .text
        | (capture("```json\n(?<j>[^\n]*)\n```") // empty) | .j | fromjson]'
}

# coordinator <session>: a live run for ROADMAP-x, its record in its session,
# holding nothing (the unit is already off Holdings).
coordinator() {
    rm -rf "$KOTO_STORE/context/$1" "$KOTO_STORE/sessions/$1"
    found_session "$1" "$(roadmap_vars x)"
    record_json roadmap x | jq -c '.written = "2026-10-01T08:00:00Z"' >"$T/rec.json"
    session_keys "$1" "$T/rec.json"
}
# seed: GitHub's side (no pull request), the coordinator $S holding the leg key
# its dispatch wrote, and the unit's surviving state: its transcripts under the
# Claude home, its koto sessions with their execution directory in the
# instance, and its koto request, requested by $S.
seed() {
    db_init
    rm -rf "$KOTO_STORE/sessions"/coordinate-* "$KOTO_STORE/context"/coordinate-*
    coordinator "$S"
    printf '%s' '{"request":"r_dispatch_x","leg":"deliver","topic":"feat-x","state":"taken"}' | koto context add "$S" legs/r_dispatch_x/deliver
    rm -rf "$HOME/.claude" "$HOME/.koto" "$KOTO_REQUESTS" "$XDG_DATA_HOME"
    ENC=$(printf '%s' "$IP" | sed 's/[^A-Za-z0-9]/-/g')
    mkdir -p "$HOME/.claude/projects/$ENC" "$HOME/.koto/sessions" "$KOTO_REQUESTS"
    cp -R "$FX/archive/$KEY/claude-projects/-work-inst-feat-x/." "$HOME/.claude/projects/$ENC/"
    for d in "$FX/archive/$KEY/koto"/*/; do
        n=$(basename "$d")
        cp -R "$d" "$HOME/.koto/sessions/$n"
        f="$HOME/.koto/sessions/$n/koto-$n.state.jsonl"
        { head -n 1 "$f" | jq -c --arg e "$IP" '.execution_dir = $e'; tail -n +2 "$f"; } >"$f.new" && mv "$f.new" "$f"
    done
    cp -R "$FX/requests/." "$KOTO_REQUESTS/"
    jq -c --arg s "$S" '.requested_by = $s' "$FX/requests/r_dispatch_x/request.jsonl" >"$KOTO_REQUESTS/r_dispatch_x/request.jsonl"
}

echo "== a removed unit, captured in its coordinator's session =="
seed
rm -rf "$R" "$T/gh.env"
mkfifo "$T/hold.gh"
OUT=$(export GITHUB_TOKEN=stub-token-2 GH_HOST=github.com; rec "$DID" "$SID" "$IP")
eq "record exits 0" 0 $?
eq "  ... printing one line" "unit-removed: recorded the removal of $DID; the sweep runs in the background" "$OUT"
eq "  ... with the removal record written while the sweep's capture is held" "unit-removal/1|$DID|$SID|$IP|0|null" \
    "$(jq -r '"\(.schema)|\(.dispatch_id)|\(.session_id)|\(.instance_path)|\(.attempts)|\(.last)"' "$R/$DID.json" 2>&1)"
eq "  ... removed_at a UTC time" ok "$(jq -r '.removed_at | if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") then "ok" else . end' "$R/$DID.json" 2>&1)"
# Read from the store directly: record-append.sh --list reads GitHub, which
# the fifo holds.
eq "  ... and nothing posted yet" 0 "$(count "$KOTO_STORE/context/$S/record/entries"/*)"
(printf 'go\n' >"$T/hold.gh") 2>/dev/null &
WP=$!
if wait_gone "$R/$DID.json" 120; then ok "  ... the sweep, released, ends with the record deleted"; else bad "  ... the sweep, released, ends with the record deleted" "$(cat "$R/$DID.json" 2>&1)"; fi
kill "$WP" 2>/dev/null
wait "$WP" 2>/dev/null
if [ -p "$T/hold.gh" ]; then
    rm -f "$T/hold.gh"
    bad "  ... the capture's first GitHub read was the one held" "the fifo was never read"
else
    ok "  ... the capture's first GitHub read was the one held"
fi
# Every gh call the sweep made ran with an empty GH_CONFIG_DIR of the sweep's
# own and with GITHUB_TOKEN and GH_HOST passed through.
eq "  ... each of the sweep's gh calls had an empty GH_CONFIG_DIR, GITHUB_TOKEN and GH_HOST" "yes|ok" \
    "$([ -s "$T/gh.env" ] && echo yes)|$(awk -F'|' '$1 !~ /\/unit-removed\.[^\/]*\/gh-config$/ || $2 != "0" || $3 != "stub-token-2" || $4 != "github.com" { print "bad: " $0; exit } END { if (NR) print "ok" }' "$T/gh.env" | head -n 1)"
E=$(costs "$S")
eq "the coordinator's session holds one cost entry" 1 "$(jq length <<<"$E")"
eq "  ... its niwa.dispatch.id the reap key" "$DID" "$(jq -r '.[0]["niwa.dispatch.id"]' <<<"$E")"
eq "  ... keyed by the removed-mode archive" "feat-x-0a1b2c3d" "$(jq -r '.[0].key | sub("^[0-9]{4}-[0-9]{2}-[0-9]{2}-"; "")' <<<"$E")"
eq "  ... the worker's tokens measured: its main transcript and subagent in the instance's directory" "measured 90" "$(jq -r '.[0].tokens.worker | "\(.state) \(.output)"' <<<"$E")"
eq "  ... every session's state times measured, the work-on sessions' among them" "5|true|2" \
    "$(jq -r '.[0].sessions | "\(length)|\(all(.[]; .figures.span_min.state == "measured" and (.states | type) == "object"))|\(map(select(.unit_session)) | length)"' <<<"$E")"
eq "  ... dispatch from the koto request" "2026-10-01T09:00:00.000Z measured koto-request" "$(jq -r '.[0].dispatch | "\(.value) \(.state) \(.source)"' <<<"$E")"
eq "  ... the figures that needed the job or a pull request not recoverable, no source" \
    "not recoverable no source|not recoverable no source|not recoverable no source" \
    "$(jq -r '.[0] | . as $e | ["dispatch_to_green_min", "dispatch_to_merge_min", "failing_heads"]
        | map(. as $k | "\($e.figures[$k].state) \([$e.missing[] | select(.figure == $k) | .reason][0])") | join("|")' <<<"$E")"
A=$(ls -d "$XDG_DATA_HOME/teardown-archive/"*-feat-x-0a1b2c3d 2>/dev/null)
eq "the archive is the pass's removed-mode one" '{"topic":"feat-x","instance":{"name":null,"path":"'"$IP"'"},"job":{"id":"0a1b2c3d","session":"'"$SID"'"},"removed":true,"niwa":{"dispatch_id":"'"$DID"'","reason":null}}' \
    "$(cat "$A/teardown.json" 2>&1)"
eq "  ... with the MANIFEST, its digest, the README, RESULT and the copies" "MANIFEST MANIFEST.sha256 README.md RESULT claude-projects koto teardown.json unit-cost.json" \
    "$(ls "$A" 2>&1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
eq "  ... the five koto sessions and the project directory" "5|$ENC" "$(count "$A/koto"/*)|$(ls "$A/claude-projects")"
eq "  ... and every MANIFEST line matches its file" ok "$(manifest_ok "$A")"

echo "== requested_by ended: the scope slug's one live run =="
seed
log_end "$S"
coordinator "$S2"
rm -rf "$R"
OUT=$(rec "$DID" "$SID" "$IP")
eq "record exits 0" 0 $?
if wait_gone "$R/$DID.json" 120; then ok "  ... the record is captured"; else bad "  ... the record is captured" "$(cat "$R/$DID.json" 2>&1)"; fi
eq "  ... the entry is in the live run, none in the ended one" "1|0" "$(costs "$S2" | jq length)|$(costs "$S" | jq length)"

echo "== no GitHub token: archived, kept pending github, no GitHub call =="
seed
unset GH_TOKEN
rm -rf "$R"
reset_calls
OUT=$(rec "$DID" "$SID" "$IP")
eq "record exits 0" 0 $?
i=0
until [ "$(jq -r '.last.outcome // ""' "$R/$DID.json" 2>/dev/null)" = "pending github" ] || [ "$i" -ge 300 ]; do
    sleep 0.2
    i=$((i + 1))
done
eq "  ... the sweep keeps the record, pending github, its attempt counted" "1|pending github" \
    "$(jq -r '"\(.attempts)|\(.last.outcome)"' "$R/$DID.json" 2>&1)"
eq "  ... the stub gh records no call" "" "$(calls)"
eq "  ... the archive is still made" ok "$(manifest_ok "$(ls -d "$XDG_DATA_HOME/teardown-archive/"*-feat-x-0a1b2c3d 2>/dev/null)")"
eq "  ... and nothing is posted" 0 "$(count "$KOTO_STORE/context/$S/record/entries"/*)"
export GH_TOKEN=stub-token
wait_gone "$R/.$DID.lock" 30
eq "a later sweep with the token captures it into the dispatch's coordinator and deletes the record" "$DID: captured|0|1" \
    "$(bash "$UR" sweep)|$(nrecords)|$(costs "$S" | jq length)"
jq -n -c --arg d "$DID" --arg s "$SID" --arg p "$IP" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema: "unit-removal/1", dispatch_id: $d, session_id: $s, instance_path: $p, removed_at: $at, attempts: 0, last: null}' >"$R/$DID.json"
eq "a record whose unit is already recorded is deleted, already recorded, with no second entry" "$DID: already recorded|0|1" \
    "$(bash "$UR" sweep)|$(nrecords)|$(costs "$S" | jq length)"

echo "== a request with no leg key: no coordinator =="
seed
koto context remove "$S" legs/r_dispatch_x/deliver
rm -rf "$R"
mkdir -p "$R" && chmod 700 "$R"
jq -n -c --arg d "$DID" --arg s "$SID" --arg p "$IP" \
    '{schema: "unit-removal/1", dispatch_id: $d, session_id: $s, instance_path: $p, removed_at: "2026-10-01T12:00:00Z", attempts: 0, last: null}' >"$R/$DID.json"
# Its removal is weeks old, so the sweep lists it stale as well.
eq "the sweep keeps the record, no coordinator, and lists it stale" "$DID: no coordinator
$DID: stale" "$(bash "$UR" sweep)"
eq "  ... the record is still there and nothing is posted" "1|0" "$(nrecords)|$(costs "$S" | jq length)"
eq "  ... removals.log holds a line for each, a UTC time first" "$DID no coordinator|$DID stale|ok" \
    "$(cut -d' ' -f2- "$R/removals.log" | paste -sd'|' -)|$(awk '$1 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/ { print "bad"; exit } END { print "ok" }' "$R/removals.log" | head -n 1)"
# A kept record is retried whatever its outcome: the sweep never branches on
# last.outcome, so no coordinator here and pending github above stand for the
# rest (a failed post, a read failure, a timeout), which the stubs can't cause.
printf '%s' '{"request":"r_dispatch_x","leg":"deliver","topic":"feat-x","state":"taken"}' | koto context add "$S" legs/r_dispatch_x/deliver
eq "  ... with the leg key back, the next sweep captures it and deletes the record" "$DID: captured|0|1" \
    "$(bash "$UR" sweep)|$(nrecords)|$(costs "$S" | jq length)"
printf '{"schema":"unit-removal/1","dispatch_id":"x y"}\n' >"$R/bad.json"
# The record above was captured, so none is left once bad.json goes.
eq "a record outside its shape is deleted, invalid input" "bad.json: invalid input|0" \
    "$(bash "$UR" sweep | grep '^bad.json'; [ -e "$R/bad.json" ] && echo kept)|$(nrecords)"

echo "== record refuses, with one line, no record and exit 0 =="
# refused <label> <reap key> <session id> <instance path> [script]
refused() {
    local out rc
    out=$(rec "$2" "$3" "$4" "${5:-}")
    rc=$?
    eq "$1: exit 0, one line, no record" "0|1|0" "$rc|$(printf '%s\n' "$out" | grep -c .)|$(nrecords)"
}
rm -rf "$R"
refused "no reap key" "" "$SID" "$IP"
refused "a reap key equal to the session id" "$SID" "$SID" "$IP"
refused "a reap key starting with -" "-x" "$SID" "$IP"
refused "an instance path holding .." "$DID" "$SID" "$WS/a/../inst-feat-x"
refused "an instance path outside the directory record runs in" "$DID" "$SID" "$T/elsewhere/inst-feat-x"
refused "the workspace root itself" "$DID" "$SID" "$WS"
refused "the workspace root with a trailing /" "$DID" "$SID" "$WS/"
refused "an instance path with a trailing /" "$DID" "$SID" "$IP/"
refused "an instance path holding a newline" "$DID" "$SID" "$WS/inst
x"
refused "a session id that isn't one" "$DID" "not-a-sid" "$IP"
mkdir -p "$T/real-removals" "$(dirname "$R")"
chmod 700 "$T/real-removals"
ln -s "$T/real-removals" "$R"
refused "a removals directory that is a symbolic link" "$DID" "$SID" "$IP"
eq "  ... nothing written through the link" 0 "$(count "$T/real-removals"/*)"
rm -f "$R"
mkdir -p "$R"
chmod 755 "$R"
refused "a removals directory not mode 0700" "$DID" "$SID" "$IP"
chmod 700 "$R"
mkdir -p "$T/copy"
cp "$UR" "$HERE/archive-common.sh" "$HERE/dispatch-common.sh" "$T/copy/"
chmod 775 "$T/copy/unit-removed.sh"
refused "the script writable by group" "$DID" "$SID" "$IP" "$T/copy/unit-removed.sh"
chmod 757 "$T/copy/unit-removed.sh"
refused "the script writable by others" "$DID" "$SID" "$IP" "$T/copy/unit-removed.sh"

echo "== a second removal of the same dispatch id =="
rm -rf "$R"
mkdir -p "$R"
chmod 700 "$R"
OTHER="$WS/inst-other"
jq -n -c --arg p "$OTHER" '{schema: "unit-removal/1", dispatch_id: "dsp-other.1", session_id: "0b0b0b0b-1111",
    instance_path: $p, removed_at: "2026-01-01T00:00:00Z", attempts: 0, last: null}' >"$R/dsp-other.1.json"
rec dsp-other.1 0b0b0b0b-1111 "$OTHER" >/dev/null
eq "at the same instance path keeps the first removed_at" "2026-01-01T00:00:00Z|$OTHER" \
    "$(jq -r '"\(.removed_at)|\(.instance_path)"' "$R/dsp-other.1.json")"
rec dsp-other.1 0b0b0b0b-1111 "$OTHER-2" >/dev/null
eq "at another instance path replaces the record" "new|$OTHER-2" \
    "$(jq -r '"\(if .removed_at == "2026-01-01T00:00:00Z" then "old" else "new" end)|\(.instance_path)"' "$R/dsp-other.1.json")"
# The sweep the last one started finds no koto session and keeps the record;
# the suite ends once it has.
i=0
until [ "$(jq -r '.last.outcome // ""' "$R/dsp-other.1.json" 2>/dev/null)" = "no coordinator" ] || [ "$i" -ge 150 ]; do
    sleep 0.2
    i=$((i + 1))
done
eq "  ... and its sweep keeps it, no coordinator" "no coordinator" "$(jq -r '.last.outcome' "$R/dsp-other.1.json")"

echo "== one capture per record: the record lock =="
# newrec <dispatch id> <session id> <instance path>: a record removed now.
newrec() {
    jq -n -c --arg d "$1" --arg s "$2" --arg p "$3" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schema: "unit-removal/1", dispatch_id: $d, session_id: $s, instance_path: $p, removed_at: $at, attempts: 0, last: null}' >"$R/$1.json"
}
seed
rm -rf "$R"
mkdir -p "$R" && chmod 700 "$R"
newrec "$DID" "$SID" "$IP"
mkfifo "$T/hold.gh"
bash "$UR" sweep >"$T/sweep1.out" 2>&1 &
SW1=$!
i=0
until [ -d "$R/.$DID.lock" ] || [ "$i" -ge 150 ]; do sleep 0.2; i=$((i + 1)); done
# Written while the first sweep runs, at a path no koto session ran in.
newrec dsp-late.1 0c0c0c0c-2222 "$WS/inst-late"
eq "a second sweep passes over the record the first holds, and handles the one written since" \
    "$DID: held by another sweep
dsp-late.1: no coordinator" "$(bash "$UR" sweep)"
(printf 'go\n' >"$T/hold.gh") 2>/dev/null &
WP=$!
wait "$SW1"
kill "$WP" 2>/dev/null
wait "$WP" 2>/dev/null
rm -f "$T/hold.gh"
eq "  ... the first captures it once" "1|0" "$(costs "$S" | jq length)|$(count "$R/$DID.json")"
eq "  ... and, reading the directory again before it exits, handles the record written meanwhile" \
    "$DID: captured
dsp-late.1: no coordinator" "$(cat "$T/sweep1.out")"
eq "  ... no lock is left behind" 0 "$(count "$R/.$DID.lock" "$R/.dsp-late.1.lock")"
seed
rm -rf "$R"
mkdir -p "$R" && chmod 700 "$R"
newrec "$DID" "$SID" "$IP"
sh -c 'exit 0' &
GONE=$!
wait "$GONE"
mkdir "$R/.$DID.lock"
printf '%s %s\n' "$GONE" "$(date +%s)" >"$R/.$DID.lock/owner"
eq "a record lock whose holder's pid is gone is taken over and the capture runs" "$DID: captured|1" \
    "$(bash "$UR" sweep)|$(costs "$S" | jq length)"

echo "== a sweep with no record does nothing =="
rm -rf "$R" "$T/gh.env" "$T/koto.env"
mkdir -p "$R" && chmod 700 "$R"
OUT=$(bash "$UR" sweep)
eq "exit 0, no output, no gh or koto call, no log" "0||0" "$?|$OUT|$(count "$T/gh.env" "$T/koto.env" "$R/removals.log")"

echo "== start: the sweep in the background =="
seed
rm -rf "$R"
mkdir -p "$R" && chmod 700 "$R"
newrec "$DID" "$SID" "$IP"
OUT=$(bash "$UR" start)
eq "start exits 0 at once, printing one line" "0|unit-removed: the sweep runs in the background" "$?|$OUT"
if wait_gone "$R/$DID.json" 120; then ok "  ... and the sweep it started captures the record"; else bad "  ... and the sweep it started captures the record" "$(cat "$R/$DID.json" 2>&1)"; fi
eq "  ... one entry in the coordinator's session" 1 "$(costs "$S" | jq length)"

done_tests unit-removed_test
