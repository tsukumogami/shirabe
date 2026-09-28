#!/usr/bin/env bash
# reconcile-pass_test.sh -- reconcile-pass.sh advances a visit's work file in
# bounded passes, prints exactly one capturable line, writes only reconcile/
# context keys, and seals a report only when every re-check is done;
# reconcile-report-get.sh accepts only the report the seal names.
#
# The scripts run from a copy of the tree. reconcile-read.sh,
# reconcile-check.sh and the record feature's coord-log.sh are stand-ins
# beside them; koto (a context store in a directory) and git are stand-ins on
# PATH. Every call is logged. The pass runs through its test entry with a
# clock file: a stand-in re-check adds its cost to the clock, and a wait adds
# to it instead of sleeping, so the 20-second cutoff and the 30-second re-read
# are tested without waiting. After each pass the test plays the engine: the
# printed line becomes the latest RECONCILE_SEAL capture.
#
# Usage: bash skills/coordinate/scripts/reconcile-pass_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n%s\n' "$1" "${2-}"; }
check() { if [ "$2" = 0 ]; then ok "$1"; else bad "$1" "${3-}"; fi; }

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-pass-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

SC="$T/tree/skills/coordinate/scripts"
mkdir -p "$SC" "$T/tree/skills/execute/scripts" "$T/bin"
for f in reconcile-pass.sh reconcile-deps.sh reconcile-report.sh reconcile-report-get.sh; do cp "$HERE/$f" "$SC/"; done
cp "$HERE/../../execute/scripts/coord-common.sh" "$T/tree/skills/execute/scripts/"
P="$SC/reconcile-pass.sh"
G="$SC/reconcile-report-get.sh"

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

# The record reader: serves <case>/read.out with exit <case>/read.rc, and
# writes <case>/reasoning.src to --reasoning-out when present.
cat > "$SC/reconcile-read.sh" <<'STUB'
#!/usr/bin/env bash
echo "read $*" >> "$STUB_DIR/log"
out=""
while [ $# -gt 0 ]; do [ "$1" = --reasoning-out ] && out=$2; shift; done
[ -n "$out" ] && [ -f "$STUB_DIR/reasoning.src" ] && cp "$STUB_DIR/reasoning.src" "$out"
[ -f "$STUB_DIR/read.sleep" ] && sleep "$(cat "$STUB_DIR/read.sleep")"
cat "$STUB_DIR/read.out" 2>/dev/null
exit "$(cat "$STUB_DIR/read.rc" 2>/dev/null || echo 0)"
STUB

# The re-checks: one fact per call, from <case>/check.<sub>.<ident>.<N> (the
# Nth call for that sub and identifying argument), else check.<sub>.<N>, else
# check.<sub>, else a default ok fact. Each call adds <case>/cost.<sub>
# seconds (default 1) to the clock and logs the clock, its deadline and the
# number of re-checks running at once.
cat > "$SC/reconcile-check.sh" <<'STUB'
#!/usr/bin/env bash
sub=$1; shift
ident=$(printf '%s' "${2-}" | tr -c 'A-Za-z0-9._-' '_')
# One marker file per running stand-in: the count of markers is how many run
# at once. A stand-in the pass stops takes its marker with it.
mark="$STUB_DIR/running.$$"; : > "$mark"; trap 'rm -f "$mark"' EXIT TERM
c=$(ls "$STUB_DIR"/running.* 2>/dev/null | wc -l | tr -d ' ')
m=$(cat "$STUB_DIR/max" 2>/dev/null || echo 0); [ "$c" -gt "$m" ] && echo "$c" > "$STUB_DIR/max"
# Up to four stand-ins run at once, so the clock's read-and-add holds a lock:
# without it two stand-ins read the same time and one cost is lost.
# Only tools run-tests.sh's restricted PATH carries (mkdir, rm, sleep, mktemp,
# mv), and a bounded wait: a lock left behind fails the case rather than
# hanging the job.
w=0
until mkdir "$CLOCK.lock" 2>/dev/null; do
    w=$((w + 1)); [ "$w" -gt 200 ] && { echo "stand-in: clock lock held past 10s" >&2; exit 98; }
    sleep 0.05
done
now=$(cat "$CLOCK")
# Written whole: a temp file of this writer's own, renamed into place. The pass
# reads the clock without the lock, and a truncate-then-write would let it read
# an empty file (#481).
tmp=$(mktemp "$CLOCK.XXXXXX") || { rm -rf "$CLOCK.lock"; echo "stand-in: can't write the clock" >&2; exit 98; }
echo $(( now + $(cat "$STUB_DIR/cost.$sub" 2>/dev/null || echo 1) )) > "$tmp" && mv "$tmp" "$CLOCK"
rm -rf "$CLOCK.lock"
key="$sub.$ident"; nf="$STUB_DIR/.n.$key"; n=$(( $(cat "$nf" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$nf"
echo "$now $sub $* D=${RECONCILE_READ_DEADLINE-} BD=${RECONCILE_BOARD_DEADLINE-}" >> "$STUB_DIR/checks"
[ -f "$STUB_DIR/hang.$sub" ] && sleep 60
if [ "$sub" = deferral ]; then
    rf=""; prev=""; for a in "$@"; do [ "$prev" = --row-file ] && rf=$a; prev=$a; done
    [ -n "$rf" ] && cat "$rf" >> "$STUB_DIR/rows-seen" && echo >> "$STUB_DIR/rows-seen"
fi
if [ -f "$STUB_DIR/inject.$sub" ] && [ -f "$WORKFILE" ]; then
    jq -c '.facts["h0.pr"] = {kind: "pr", status: "ok", state: "MERGED", draft: false, head: "x", merge_state: "UNKNOWN", base: "main", read_at: "t", t: 0}' "$WORKFILE" > "$WORKFILE.x" && mv "$WORKFILE.x" "$WORKFILE"
fi
[ -f "$STUB_DIR/reenter.$sub" ] && echo 99 > "$STUB_DIR/visit"
[ -f "$STUB_DIR/plant-on.$sub" ] && sh "$STUB_DIR/plant"
sleep 0.2
# A clock jq can't take, left just before this re-check ends: the pass's next
# fold of this fact then has a time it can't write.
# `0x10` is a number to bash's arithmetic and not to jq, so wherever the pass
# reads it next, the failure is a jq write the pass must refuse.
if [ -f "$STUB_DIR/garble.$sub" ]; then
    tmp=$(mktemp "$CLOCK.XXXXXX") || { echo "stand-in: can't write the clock" >&2; exit 98; }
    echo 0x10 > "$tmp" && mv "$tmp" "$CLOCK"
fi
for f in "$STUB_DIR/check.$key.$n" "$STUB_DIR/check.$sub.$n" "$STUB_DIR/check.$sub"; do
    [ -f "$f" ] && { cat "$f"; exit 0; }
done
case "$sub" in
    pr) echo '{"kind":"pr","status":"ok","state":"OPEN","draft":false,"head":"1111111111111111111111111111111111111111","merge_state":"CLEAN","base":"main","read_at":"t"}' ;;
    board) echo '{"kind":"board","status":"ok","verdict":"holds","at":"x","read_at":"t"}' ;;
    branch) echo '{"kind":"branch","status":"ok","state":"present","tip":"1111111111111111111111111111111111111111","read_at":"t"}' ;;
    appeared) echo '{"kind":"appeared","status":"ok","prs":[],"read_at":"t"}' ;;
    host) echo '{"kind":"host","status":"ok","state":"found","reads":1,"path":"/home/someone/ws/ws+w_topic-0123abc","read_at":"t"}' ;;
    inventory) echo '{"kind":"inventory","status":"ok","taken":true,"items":[],"truncated":false,"read_at":"t"}' ;;
    leg) echo '{"kind":"leg","status":"ok","disposition":"open","result":"","read_at":"t"}' ;;
    merge) echo '{"kind":"merge","status":"ok","verdict":"confirmed","reason":"","read_at":"t"}' ;;
    close) echo '{"kind":"close","status":"ok","verdict":"confirmed","reason":"","read_at":"t"}' ;;
    teardown) echo '{"kind":"teardown","status":"ok","verdict":"confirmed","reason":"","reads":1,"read_at":"t"}' ;;
    deferral) echo '{"kind":"deferral","status":"ok","disposed":false,"how":"no disposition","read_at":"t"}' ;;
    files) echo '{"kind":"files","status":"ok","paths":["docs/a.md"],"truncated":false,"read_at":"t"}' ;;
esac
STUB

# The record feature's session-log helper, for the calls the pass and the
# report reader make. The visit is <case>/visit; the latest capture is
# <case>/capture.
cat > "$SC/coord-log.sh" <<'STUB'
#!/usr/bin/env bash
echo "coord-log $*" >> "$STUB_DIR/log"
cmd=$1; shift
S="" ST="" TOK="" NAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) S=$2; shift 2 ;; --state) ST=$2; shift 2 ;; --token) TOK=$2; shift 2 ;;
        --name) NAME=$2; shift 2 ;; *) shift ;;
    esac
done
h() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
case "$cmd" in
    seal)
        [ -f "$STUB_DIR/visit" ] || exit 2
        v=$(cat "$STUB_DIR/visit")
        printf '%s sealed:%s:%s\n' "$TOK" "$v" "$(printf '%s|%s|%s|%s' "$S" "$ST" "$v" "$TOK" | h)" ;;
    capture)
        [ -s "$STUB_DIR/capture" ] || exit 1
        c=$(cat "$STUB_DIR/capture")
        if [ -n "$ST" ]; then
            case "$c" in *" sealed:"*) ;; *) exit 1 ;; esac
            seal=${c##* sealed:}; body=${c% sealed:*}; v=${seal%%:*}
            [ "$v" = "$(cat "$STUB_DIR/visit")" ] || exit 1
            [ "${seal#*:}" = "$(printf '%s|%s|%s|%s' "$S" "$ST" "$v" "$body" | h)" ] || exit 1
        fi
        printf '%s\n' "$c" ;;
    run-start) echo 2026-09-27T00:00:00Z ;;
    directed-since)
        if [ -s "$STUB_DIR/directed" ]; then cat "$STUB_DIR/directed"; exit 1; fi; exit 0 ;;
    *) exit 64 ;;
esac
STUB

# koto: a context store in <case>/ctx; every call logged.
cat > "$T/bin/koto" <<'STUB'
#!/usr/bin/env bash
echo "koto $*" >> "$STUB_DIR/log"
[ "$1" = context ] || exit 2
mkdir -p "$STUB_DIR/ctx"
k=$(printf '%s' "$4" | sed 's#/#%#g')
case "$2" in
    add) if [ "${5-}" = --from-file ]; then cp "$6" "$STUB_DIR/ctx/$k"; else cat > "$STUB_DIR/ctx/$k"; fi ;;
    remove) rm -f "$STUB_DIR/ctx/$k" ;;
    get) [ -f "$STUB_DIR/ctx/$k" ] || exit 1; cat "$STUB_DIR/ctx/$k" ;;
    exists) [ -f "$STUB_DIR/ctx/$k" ] ;;
    *) exit 2 ;;
esac
STUB
# git: only the pass's own repository read.
cat > "$T/bin/git" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "$STUB_DIR/log"
case " $* " in *" rev-parse --show-toplevel "*) [ -f "$STUB_DIR/top" ] && { cat "$STUB_DIR/top"; exit 0; }; exit 128 ;; esac
exit 99
STUB
chmod +x "$SC"/*.sh "$T/bin/koto" "$T/bin/git"

SESSION=coordinate-plugin-system-20260927T000000Z
CASES=0
new_case() {
    CASES=$((CASES + 1))
    CASE="$T/case-$CASES-$1"
    SDIR="$CASE/sessions/$SESSION"
    mkdir -p "$CASE/ctx" "$SDIR"
    : > "$CASE/log"; : > "$CASE/checks"
    echo 7 > "$CASE/visit"
    echo 1000 > "$CASE/clock"
}
# pass -- one pass through the test entry; the line goes to $LINE, and the
# engine's capture becomes it.
pass() {
    LINE=$(STUB_DIR="$CASE" CLOCK="$CASE/clock" WORKFILE="$SDIR/coordinate-reconcile/visit.json" PATH="$T/bin:$PATH" GH_TOKEN="${TOKEN-}" \
        bash "$P" --test-entry --clock-file "$CASE/clock" --session "$SESSION" --session-dir "$SDIR" 2> "$CASE/stderr")
    RC=$?
    printf '%s\n' "$LINE" > "$CASE/capture"
}
get() { STUB_DIR="$CASE" PATH="$T/bin:$PATH" bash "$G" --session "$SESSION" "$@" 2>/dev/null; }
ctx() { cat "$CASE/ctx/$(printf '%s' "$1" | sed 's#/#%#g')" 2>/dev/null; }
has_ctx() { [ -f "$CASE/ctx/$(printf '%s' "$1" | sed 's#/#%#g')" ]; }
tick() { echo $(( $(cat "$CASE/clock") + $1 )) > "$CASE/clock"; }
lines_ok() {  # every line the pass printed is one of the three grammars and capturable
    printf '%s\n' "$1" | grep -Eq '^(pending:[0-9]+:[0-9]+:[0-9a-f]{64}|blocked:(none|unreadable)|reconciled [0-9a-f]{64} sealed:[0-9]+:[0-9a-f]{64})$' \
        && printf '%s' "$1" | grep -Eq '^[A-Za-z0-9 :/_.@-]*$' && [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" = 1 ]
}

SHA1=1111111111111111111111111111111111111111
SHA2=2222222222222222222222222222222222222222
hold() {  # hold <worker> <pull_request> [extra jq]
    local extra=${3-}
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg w "$1" --arg pr "$2" --arg sha "$SHA1" "{unit: \"Feature\", entry_point: \"/shirabe:deliver\", mode: \"--auto\", phase: \"executing\", dispatch_status: \"dispatched\", return_path: \"message\", worker: \$w, repo: \"acme/widgets\", branch: (\"feat/\" + \$w), verified_head: \$sha, dispatched: \"2026-09-26\", pull_request: \$pr} + ($extra)"
}
record() {  # record <holdings-json-array> [side-effects] [deferrals]
    jq -nc --argjson h "$1" --argjson s "${2:-[]}" --argjson d "${3:-[]}" \
        '{status: "found", scope: {kind: "roadmap", name: "plugin-system", repo: "acme/widgets"},
          record: {written: "2026-09-26T12:00:00Z", source: "record", handoff_date: null},
          holdings: [$h[] | {row: ., source: "record"}], deferrals: [$d[] | {row: ., source: "record"}],
          side_effects: [$s[] | {row: ., source: "record"}], unparseable: [], reasoning: null}' > "$CASE/read.out"
}
PR12='[#12](https://github.com/acme/widgets/pull/12)'

echo "== a full reconcile =="
new_case full
record "[$(hold with-pr "$PR12"),$(hold no-pr "")]" \
    '[{"action":"merge","target":"#12","verified_head":"'$SHA1'","attempted":"2026-09-26T11:00Z","how_to_confirm":"compare"},{"action":"teardown","target":"old-worker","verified_head":"","attempted":"2026-09-26T11:00Z","how_to_confirm":"listing"},{"action":"notify","target":"someone","verified_head":"","attempted":"2026-09-26T11:00Z","how_to_confirm":"ask"}]' \
    '[{"deferral":"flaky test","reason":"later","raised":"2026-09-25T10:00Z","disposition":""}]'
echo "$CASE" > "$CASE/top"
pass
lines_ok "$LINE"; check "the first pass prints one capturable line" $? "$LINE"
case "$LINE" in pending:7:*) ok "a teardown's second listing read, 30 seconds on, leaves the first pass pending" ;; *) bad "a teardown's second listing read, 30 seconds on, leaves the first pass pending" "$LINE $(cat "$CASE/stderr")" ;; esac
has_ctx reconcile/progress; check "a pending pass says why in reconcile/progress" $?
has_ctx reconcile/report.json && bad "no report before every re-check is done" || ok "no report before every re-check is done"
tick 31
pass
lines_ok "$LINE"; check "the second pass prints one capturable line" $? "$LINE"
case "$LINE" in "reconciled "*" sealed:7:"*) ok "the visit's last re-check done, the report is sealed to the visit" ;; *) bad "the visit's last re-check done, the report is sealed to the visit" "$LINE $(cat "$CASE/stderr")" ;; esac
has_ctx reconcile/progress && bad "progress is cleared once the report is sealed" || ok "progress is cleared once the report is sealed"
[ "$(ctx reconcile/report.json | sha)" = "$(printf '%s' "$LINE" | cut -d' ' -f2)" ]; check "the seal names the stored report's sha256" $?
get --check; check "the report reader accepts the sealed report" $?
ctx reconcile/report.md | grep -q '^# Reconcile report'; check "the rendered report is stored beside it" $?
ctx reconcile/report.json | jq -e '[.side_effects[] | .code] == ["confirmed", "confirmed", "not_rechecked"]' >/dev/null; check "a merge and a teardown are confirmed; any other side effect is not re-checked" $? "$(ctx reconcile/report.json | jq -c .side_effects)"
[ "$(grep -c ' teardown ' "$CASE/checks")" = 2 ]; check "a teardown is confirmed by two listing reads" $? "$(cat "$CASE/checks")"
ctx reconcile/report.md | grep -q 'ran from outside the repository'; check "the report says where the scripts ran from" $?
bad_keys=$(grep '^koto context \(add\|remove\)' "$CASE/log" | awk '{print $5}' | grep -v '^reconcile/' || true)
[ -z "$bad_keys" ]; check "the pass writes and removes only reconcile/ keys" $? "$bad_keys"
leak=$(cat "$CASE"/ctx/* | grep -c -e "$SESSION" -e '/home/someone' -e 'ws+w_topic' -e '0123abc' || true)
[ "$leak" = 0 ]; check "no stored key carries the session id, an instance path or a job id" $?
pass
case "$LINE" in "reconciled "*" sealed:7:"*) ok "a later tick in the same visit says the same sealed line" ;; *) bad "a later tick in the same visit says the same sealed line" "$LINE" ;; esac

echo "== blocked =="
for c in "none 3" "unreadable 4" "unreadable 5"; do
    set -- $c
    new_case "blocked-$1-$2"
    echo "{\"status\":\"x\",\"reason\":\"the reader said so\"}" > "$CASE/read.out"; echo "$2" > "$CASE/read.rc"
    pass
    [ "$LINE" = "blocked:$1" ]; check "a record read exiting $2 prints blocked:$1" $? "$LINE"
    ctx reconcile/refusal | grep -q "case: $1"; check "reconcile/refusal names the case ($1, exit $2)" $?
    has_ctx reconcile/report.json && bad "no report when blocked (exit $2)" || ok "no report when blocked (exit $2)"
done
new_case blocked-late
record "[]"; echo 20 > "$CASE/read.sleep"
# The reader's deadline is the pass's own; this stand-in outlives it.
LINE=$(STUB_DIR="$CASE" CLOCK="$CASE/clock" PATH="$T/bin:$PATH" bash "$P" --test-entry --clock-file "$CASE/clock" --session "$SESSION" --session-dir "$SDIR" 2>/dev/null)
[ "$LINE" = blocked:unreadable ]; check "a record read that runs out its deadline is blocked" $? "$LINE"
ctx reconcile/refusal | grep -q 'timed out'; check "and the refusal says it timed out" $?

echo "== the budget =="
new_case budget
h="["; for i in 1 2 3 4 5 6 7 8 9 10; do h="$h$(hold "w$i" "[#$i](https://github.com/acme/widgets/pull/$i)"),"; done; h="${h%,}]"
record "$h"
echo 3 > "$CASE/cost.pr"; echo 3 > "$CASE/cost.board"; echo 3 > "$CASE/cost.branch"
pass
case "$LINE" in pending:*) ok "more re-checks than one pass fits leave it pending" ;; *) bad "more re-checks than one pass fits leave it pending" "$LINE" ;; esac
[ "$(cat "$CASE/max")" -le 4 ]; check "at most four re-checks run at once" $? "max $(cat "$CASE/max")"
# The pass logs each launch as "launch <id> at +<s>s with <budget>s".
launches=$(sed -n 's/^reconcile-pass: launch [^ ]* at +\([0-9]*\)s with \([0-9]*\)s$/\1 \2/p' "$CASE/stderr")
[ -n "$launches" ]; check "the pass logs its launches" $?
late=$(printf '%s\n' "$launches" | awk '$1 >= 20')
[ -z "$late" ]; check "no re-check starts at or after 20 seconds" $? "$late"
over=$(printf '%s\n' "$launches" | awk '$1 + $2 > 24')
[ -z "$over" ]; check "every re-check's budget is clipped to the time left before 24 seconds" $? "$over"
over=$(awk '{ split($NF, b, "="); split($(NF-1), d, "="); if (d[2] > 8 || b[2] > 26) print }' "$CASE/checks")
[ -z "$over" ]; check "no re-check is given more than its own deadline" $? "$over"
n=0; while [ "$n" -lt 8 ] && case "$LINE" in pending:*) true ;; *) false ;; esac; do tick 1; pass; n=$((n + 1)); done
case "$LINE" in "reconciled "*) ok "later passes finish the visit" ;; *) bad "later passes finish the visit" "$LINE" ;; esac
lines=$(ctx reconcile/report.md | wc -l | tr -d ' ')
[ "$lines" -le 100 ]; check "a 10-holding report stays within the line bound (40 + 6 per holding)" $? "$lines lines"
ctx reconcile/report.md | grep -q '"kind"' && bad "the report carries no raw read output" || ok "the report carries no raw read output"

new_case overrun
record "[$(hold slow "")]"
# The appeared read costs 40 seconds of the clock and then hangs for real:
# the pass stops it at its budget and doesn't wait on it for its own line.
echo 40 > "$CASE/cost.appeared"
: > "$CASE/hang.appeared"
start=$SECONDS
pass
elapsed=$((SECONDS - start))
[ "$elapsed" -lt 20 ]; check "a re-check past its budget is stopped, and the pass's line doesn't wait for it" $? "${elapsed}s: $LINE"
case "$LINE" in pending:*) ok "and the visit stays pending, to read it again" ;; *) bad "and the visit stays pending, to read it again" "$LINE" ;; esac

echo "== a worker not found =="
new_case missed-twice
record "[$(hold quiet-one "")]"
echo '{"kind":"host","status":"ok","state":"missed","reads":1,"read_at":"t"}' > "$CASE/check.host"
pass
case "$LINE" in pending:*) ok "a miss with its re-read 30 seconds away leaves the pass pending" ;; *) bad "a miss with its re-read 30 seconds away leaves the pass pending" "$LINE" ;; esac
tick 10; pass
[ "$(grep -c ' host ' "$CASE/checks")" = 1 ]; check "the listing is not read again sooner than 30 seconds" $? "$(cat "$CASE/checks")"
tick 25; pass
t1=$(awk '$2 == "host" {print $1}' "$CASE/checks" | sed -n 1p); t2=$(awk '$2 == "host" {print $1}' "$CASE/checks" | sed -n 2p)
[ -n "$t2" ] && [ $((t2 - t1)) -ge 30 ]; check "the second listing read comes at least 30 seconds after the first" $? "$t1 $t2"
ctx reconcile/report.md | grep -q 'not found on this read'; check "two misses read as not found on this read" $?
ctx reconcile/report.md | grep -A2 '^## Exists nowhere else' | grep -q 'quiet-one'; check "and the worker is listed under Exists nowhere else" $?
ctx reconcile/report.md | grep -q 'inventory could not be taken'; check "with an inventory that couldn't be taken" $?
ctx reconcile/report.md | grep -Eiq '\b(gone|dead|lost)\b.*worker|worker.*\b(gone|dead)\b' && bad "never gone, dead or lost" "$(ctx reconcile/report.md)" || ok "never gone, dead or lost"
new_case missed-then-found
record "[$(hold slow-one "")]"
echo 1015 > "$CASE/clock"; echo 995 > "$CASE/clock.start"
echo '{"kind":"host","status":"ok","state":"missed","reads":1,"read_at":"t"}' > "$CASE/check.host.1"
pass
tick 31; pass
ctx reconcile/report.md | grep -q 'worker found'; check "a miss then a match reads found" $? "$(ctx reconcile/report.md)"
grep -q ' inventory ' "$CASE/checks"; check "and the found instance's inventory is taken" $?
new_case miss-fits
record "[$(hold quick-one "")]"
echo '{"kind":"host","status":"ok","state":"missed","reads":1,"read_at":"t"}' > "$CASE/check.host.1"
# The first read happened in an earlier pass 15 seconds ago: the re-read is
# due 15 seconds into this one, before the cutoff, so this pass waits for it.
pass; tick 15; pass
[ "$(grep -c ' host ' "$CASE/checks")" = 2 ]; check "a re-read that falls before the cutoff is made within the pass" $? "$(cat "$CASE/checks")"

echo "== the work file =="
new_case edited
record "[$(hold with-pr "$PR12")]" '[{"action":"teardown","target":"x","verified_head":"","attempted":"2026-09-26T11:00Z","how_to_confirm":"l"}]'
pass
before=$(grep -c . "$CASE/checks")
jq -c '.facts["h0.pr"].state = "MERGED"' "$SDIR/coordinate-reconcile/visit.json" > "$CASE/w" && cp "$CASE/w" "$SDIR/coordinate-reconcile/visit.json"
tick 31; pass
after=$(grep -c ' pr ' "$CASE/checks")
[ "$after" = 2 ]; check "a work file edited between passes is discarded and the visit's reads start again" $? "$(cat "$CASE/checks")"
new_case killed
record "[$(hold with-pr "$PR12")]" '[{"action":"teardown","target":"x","verified_head":"","attempted":"2026-09-26T11:00Z","how_to_confirm":"l"}]'
pass
echo "pending:7:1:0000000000000000000000000000000000000000000000000000000000000000" > "$CASE/capture"
tick 31; pass
[ "$(grep -c ' pr ' "$CASE/checks")" = 2 ]; check "a work file the last logged pass doesn't name (a killed pass) is discarded" $?
new_case new-visit
record "[$(hold with-pr "$PR12")]"
pass
echo 9 > "$CASE/visit"
echo stale > "$CASE/ctx/reconcile%reasoning.md"
record "[]"
pass
case "$LINE" in "reconciled "*" sealed:9:"*) ok "a new visit starts its own reads" ;; *) bad "a new visit starts its own reads" "$LINE" ;; esac
has_ctx reconcile/reasoning.md && bad "a new visit removes the old visit's reconcile/ keys" || ok "a new visit removes the old visit's reconcile/ keys"
[ "$(grep -c '^read ' "$CASE/log")" = 2 ]; check "and reads the record again" $?
new_case planted
record "[$(hold with-pr "$PR12")]"
# Read results left in the session directory, as an earlier pass's layout
# kept them: never read.
mkdir -p "$SDIR/coordinate-reconcile/reads"
echo '{"kind":"pr","status":"ok","state":"MERGED","draft":false,"head":"x","merge_state":"UNKNOWN","base":"main","read_at":"t"}' > "$SDIR/coordinate-reconcile/reads/h0.pr.out"
echo 0 > "$SDIR/coordinate-reconcile/reads/h0.pr.rc"
pass
ctx reconcile/report.json | jq -e '.holdings[0].state == "open"' >/dev/null; check "read results planted in the session directory are never taken" $? "$(ctx reconcile/report.json | jq -c .holdings)"
grep -q ' pr ' "$CASE/checks"; check "the pull request is read" $?
new_case stale-own-reads
record "[$(hold with-pr "$PR12")]"
# A result for this read left in the pass's own reads directory before it
# launches: cleared at launch, so the real read decides.
cat > "$CASE/plant" <<'PLANT'
for d in "${TMPDIR:-/tmp}"/reconcile-pass.*/reads; do
    [ -d "$d" ] && printf '{"kind":"pr","status":"ok","state":"MERGED","draft":false,"head":"x","merge_state":"UNKNOWN","base":"main","read_at":"t"}' > "$d/h0.pr.out" && echo 0 > "$d/h0.pr.rc"
done
PLANT
: > "$CASE/plant-on.branch"
pass
ctx reconcile/report.json | jq -e '.holdings[0].state == "open"' >/dev/null; check "a result planted in the pass's own reads directory is not taken for a read" $? "$(ctx reconcile/report.json | jq -c .holdings)"

new_case deferral-row
record "[]" '[]' '[{"deferral":"flaky test","reason":"later","raised":"2026-09-25T10:00Z","disposition":""}]'
# A row file where an earlier layout kept them, saying the deferral is
# disposed: the check must see the work document's own row instead.
mkdir -p "$SDIR/coordinate-reconcile"
printf '{"deferral":"flaky test","reason":"later","raised":"2026-09-25T10:00Z","disposition":"closed: done"}' > "$SDIR/coordinate-reconcile/d0.row.json"
pass
jq -e -s 'length >= 1 and all(.disposition == "")' "$CASE/rows-seen" >/dev/null 2>&1; check "each deferral is checked from the work document's own row" $? "$(cat "$CASE/rows-seen" 2>&1)"
grep ' deferral ' "$CASE/checks" | grep -q -- "--row-file $SDIR" && bad "no deferral row is read from the session directory" || ok "no deferral row is read from the session directory"
new_case edited-mid-pass
record "[$(hold with-pr "$PR12")]"
: > "$CASE/inject.branch"
pass
case "$LINE" in "reconciled "*) ok "the pass seals" ;; *) bad "the pass seals" "$LINE $(cat "$CASE/stderr")" ;; esac
ctx reconcile/report.json | jq -e '.holdings[0].state == "open"' >/dev/null; check "a fact written into the work file while a pass runs never reaches the report" $? "$(ctx reconcile/report.json | jq -c .holdings)"
new_case reentered
record "[$(hold with-pr "$PR12")]"
: > "$CASE/reenter.branch"
pass
[ "$RC" != 0 ] && [ -z "$LINE" ]; check "a pass whose state was entered again while it ran seals nothing" $? "$RC $LINE"
new_case due-at-cutoff
record "[$(hold late-one "")]"
echo '{"kind":"host","status":"ok","state":"missed","reads":1,"read_at":"t"}' > "$CASE/check.host.1"
pass
t1=$(awk '$2 == "host" {print $1; exit}' "$CASE/checks")
# The next pass starts 10 seconds after the first read: the re-read is due
# exactly 20 seconds in, at the cutoff, where nothing is launched.
echo $((t1 + 10)) > "$CASE/clock"
start=$(cat "$CASE/clock")
pass
[ $(( $(cat "$CASE/clock") - start )) -lt 20 ]; check "a re-read due at the cutoff doesn't make the pass wait for nothing" $? "clock moved $(( $(cat "$CASE/clock") - start ))s: $LINE"
case "$LINE" in pending:*) ok "and it is left to the next pass" ;; *) bad "and it is left to the next pass" "$LINE" ;; esac
new_case blocked-fast
echo '{"status":"none","reason":"no record"}' > "$CASE/read.out"; echo 3 > "$CASE/read.rc"
start=$SECONDS
pass
[ $((SECONDS - start)) -lt 10 ]; check "a blocked pass returns without waiting on the record read's 12-second deadline" $? "$((SECONDS - start))s; $(cat "$CASE/stderr" | tail -3)"

new_case cleared
record "[]"
echo x > "$CASE/ctx/reconcile%refusal"; echo x > "$CASE/ctx/reconcile%progress"
pass
has_ctx reconcile/refusal || has_ctx reconcile/progress
[ $? != 0 ]; check "refusal and progress are cleared at the start of every pass" $?

echo "== the report reader =="
new_case getter
record "[$(hold with-pr "$PR12")]"
pass
get --check; check "the sealed report reads" $?
get | jq -e '.report.schema == "coordinate-reconcile-report/v1" and .directed_transitions == []' >/dev/null; check "with no directed transition in the run, none is named" $?
printf '12 record_find->pick_facts\n' > "$CASE/directed"
get | jq -e '.directed_transitions == ["12 record_find->pick_facts"]' >/dev/null; check "a directed transition anywhere in the run is named" $?
: > "$CASE/directed"
ctx reconcile/report.json | jq -c '.holdings = []' > "$CASE/agent.json"; cp "$CASE/agent.json" "$CASE/ctx/reconcile%report.json"
get --check; [ $? = 1 ]; check "a report the agent wrote is refused" $?
pass
get --check; check "the next tick in the same visit puts the sealed report back" $?
echo 8 > "$CASE/visit"
get --check; [ $? = 1 ]; check "a report sealed in an earlier visit is refused" $?
echo 7 > "$CASE/visit"; rm -f "$CASE/ctx/reconcile%report.json"
get --check; [ $? = 2 ]; check "an absent report can't be read" $?
echo "pending:7:1:$(printf x | sha)" > "$CASE/capture"
get --check; [ $? = 1 ]; check "a pending capture is no report" $?
if ! grep -v '^[[:space:]]*#' "$G" | grep -q -- '--sealed' && grep -q 'capture --session "$SESSION" --name RECONCILE_SEAL' "$G"; then
    ok "the reader takes no sealed token and reads the capture from the log itself"
else bad "the reader takes no sealed token and reads the capture from the log itself"; fi

echo "== the clock =="
# #481: the stand-ins advance the clock while the pass reads it. Four writers
# running the real stand-in re-check, against a reader that must never see
# the file empty.
new_case clock-hammer
: > "$CASE/empties"
WRITERS=""
for w in 1 2 3 4; do
    ( i=0; while [ "$i" -lt 12 ]; do
        STUB_DIR="$CASE" CLOCK="$CASE/clock" WORKFILE="$CASE/none" bash "$SC/reconcile-check.sh" pr --repo o/r >/dev/null 2>&1
        i=$((i + 1)); done ) &
    WRITERS="$WRITERS $!"
done
writing() { local p; for p in $WRITERS; do kill -0 "$p" 2>/dev/null && return 0; done; return 1; }
while writing; do
    [ -n "$(cat "$CASE/clock")" ] || echo empty >> "$CASE/empties"
done
wait
[ ! -s "$CASE/empties" ]; check "a reader never sees the clock empty while four re-checks advance it" $? "$(wc -l < "$CASE/empties") empty reads"
[ "$(cat "$CASE/clock")" = 1048 ]; check "and no advance is lost" $? "clock $(cat "$CASE/clock"), want 1048"
ls "$CASE"/clock.* >/dev/null 2>&1 && bad "no clock temp file is left behind" "$(ls "$CASE"/clock.*)" || ok "no clock temp file is left behind"

# An empty read is retried: a clock filled shortly after the pass starts is
# read, not taken for a time.
new_case clock-late
record "[$(hold with-pr "$PR12")]"
: > "$CASE/clock"
( sleep 0.3; echo 1000 > "$CASE/clock.late" && mv "$CASE/clock.late" "$CASE/clock" ) &
pass
wait
[ "$RC" = 0 ] && lines_ok "$LINE"; check "a clock that reads empty at first is read again, and the pass goes on" $? "$RC $LINE $(cat "$CASE/stderr")"
grep -q 'argjson' "$CASE/stderr" && bad "and no empty time reaches jq" "$(cat "$CASE/stderr")" || ok "and no empty time reaches jq"

# A clock that stays empty ends the pass, naming the clock.
new_case clock-empty
record "[$(hold with-pr "$PR12")]"
: > "$CASE/clock"
pass
[ "$RC" != 0 ] && [ -z "$LINE" ] && grep -q 'test clock .* read empty' "$CASE/stderr"; check "a clock that stays empty ends the pass with its own message" $? "$RC $LINE $(cat "$CASE/stderr")"
[ ! -e "$SDIR/coordinate-reconcile/visit.json" ]; check "and writes no work file" $? "$(cat "$SDIR/coordinate-reconcile/visit.json" 2>&1)"

# A jq write that fails never replaces the work file: a time jq can't take
# ends the pass, and the work file keeps the visit it held.
new_case clock-garbled
record "[$(hold with-pr "$PR12")]"
: > "$CASE/garble.pr"
pass
[ "$RC" != 0 ] && [ -z "$LINE" ]; check "a fact whose write fails ends the pass" $? "$RC $LINE $(cat "$CASE/stderr")"
jq -e '.visit == "7" and (.facts | type) == "object"' "$SDIR/coordinate-reconcile/visit.json" >/dev/null 2>&1
check "and the work file still holds the visit" $? "$(cat "$SDIR/coordinate-reconcile/visit.json" 2>&1)"
grep -q 'could not be written\|the plan could not be read' "$CASE/stderr"; check "and the pass says which write failed" $? "$(cat "$CASE/stderr")"
grep -v '^[[:space:]]*#' "$P" | grep -n 'save "\$(' && bad "every save takes a document whose jq status was checked" || ok "every save takes a document whose jq status was checked"

echo "== the token =="
SECRET=s3cr3t-token-value-for-the-test
new_case token
record "[$(hold with-pr "$PR12")]"
TOKEN=$SECRET pass
grep -rq "$SECRET" "$CASE" && bad "nothing the pass prints, logs or stores holds the token" "$(grep -rl "$SECRET" "$CASE")" || ok "nothing the pass prints, logs or stores holds the token"
grep -q 'CLOCK\|RECONCILE_.*CLOCK\|SLEEP' <(grep -o '\${[A-Z_]*' "$P" | sort -u) && bad "no environment variable sets the clock or the sleep" || ok "no environment variable sets the clock or the sleep"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
