#!/usr/bin/env bash
# probe_test.sh -- does probe.sh draw, record, print, check and search for its
# value the way docs/guides/probe.md says, with no koto?
#
#   A. The draw: the subcommand surface, each opt-in condition failing alone,
#      the always-exit-0 cases, the rejection-sampled mappings over every
#      byte, the value form over 1000 draws, the record's files (order, mode,
#      symlink refusal), the read-back on a second draw and after the opt-in
#      is switched off, the entropy source, far_shown, and the rule's text.
#   B. arm, near-text and the template's gate commands' exit mapping.
#   C. check against constructed session logs: every row of the exit table,
#      exact comparison, visit scoping, the re-delivery ladder, the delivery
#      marker, the time limit, no network, and what it never prints.
#   D. The leak gates against git fixtures and a stubbed gh, with a value
#      generated at run time and planted in each route.
#   E. The repository holds no value-shaped string and no runtime value.
#
# Every case needs bash, jq and git only, so the whole suite runs on the bash
# 3.2 floor. probe-routes_test.sh drives the same script through koto.
#
# Usage: probe_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

# The suite sources probe.sh in subshells for its mappings.
# shellcheck disable=SC1090
set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SUT="$SCRIPT_DIR/probe.sh"
REAL_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
TEMPLATE="$REAL_ROOT/skills/work-on/koto-templates/work-on.md"
GUIDE="$REAL_ROOT/docs/guides/probe.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got [$2], want [$3]"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required to run this suite" >&2; exit 2; }
[ -x "$SUT" ] || { echo "$SUT is missing or not executable" >&2; exit 2; }

T=$(mktemp -d "${TMPDIR:-/tmp}/probe-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */probe-test.*) chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" ;; esac; return 0; }
ktg_on_exit cleanup

export XDG_CONFIG_HOME="$T/xdg"
mkdir -p "$XDG_CONFIG_HOME/shirabe" "$T/s"
OPTIN="$XDG_CONFIG_HOME/shirabe/probe"
echo on > "$OPTIN"

fresh() { mktemp -d "$T/s/session.XXXXXX"; }
# draw <session-dir> [switch] [shared] [extra...]: stdout in OUT, exit in RC.
draw() {
    local d=$1 sw=${2-on} sh=${3-}
    shift; [ $# -gt 0 ] && shift; [ $# -gt 0 ] && shift
    OUT=$("$SUT" draw "$sw" "$sh" "$d" "$REAL_ROOT" "$@" 2>&1); RC=$?
}
arm_of() { "$SUT" arm "$1"; echo $?; }
empty_probe() { [ ! -e "$1/probe" ] || [ -z "$(ls -A "$1/probe" 2>/dev/null)" ]; }
perms() { ls -l "$1" | cut -c1-10; }

# runtime_value: a value the script itself draws, generated now, never stored
# in a tracked file.
runtime_value() { ( . "$SUT"; r=$(draw_arm_value) && printf '%s' "${r#* }" ); }

# record <session-dir> <arm> <value>: a record written the way draw writes it.
record() {
    mkdir -p "$1/probe" && printf '%s\n' "$3" > "$1/probe/value" && printf '%s\n' "$2" > "$1/probe/arm"
}

# The rule's text, as the design words it, with the value filled in.
full_text() { printf 'Rule probe/ack-value: when you submit pr_status: created at the pull request step also submit ack: %s in the same evidence. Write this value nowhere else: not in the pull request or its comments or a commit or a file.' "$1"; }
summary_text() { printf 'probe/ack-value: submit ack: %s with pr_status: created.' "$1"; }

# --- A. the draw ------------------------------------------------------------

"$SUT" frobnicate "$(fresh)" >"$T/unk.out" 2>"$T/unk.err"; rc=$?
if [ $rc -ne 0 ] && [ ! -s "$T/unk.out" ] && ! grep -qE '[a-z]{3}[0-9]{6}' "$T/unk.err"; then
    pass "an unknown subcommand exits $rc and prints no value"
else
    fail "an unknown subcommand: rc=$rc out=[$(cat "$T/unk.out")]"
fi
for sub in draw arm near-text check leak-branch leak-pr; do
    grep -qE "^#   probe.sh $sub " "$SUT" && grep -qE "^        $sub\)" "$SUT" \
        && pass "probe.sh documents and dispatches $sub" || fail "probe.sh lacks the $sub subcommand"
done

d=$(fresh); draw "$d"
if [ $RC -eq 0 ] && [ -f "$d/probe/arm" ] && [ -f "$d/probe/value" ]; then
    pass "control: with every condition holding, draw records an arm and a value"
else
    fail "control: rc=$RC, nothing recorded"
fi

# Each condition failing alone.
nothing() { # nothing <label> <session-dir>
    if [ $RC -eq 0 ] && [ -z "$OUT" ] && empty_probe "$2" && [ "$(arm_of "$2")" = 3 ]; then
        pass "$1: exit 0, nothing printed, nothing written, no arm"
    else
        fail "$1: rc=$RC out=[$OUT] files=[$(ls -A "$2/probe" 2>/dev/null | tr '\n' ' ')]"
    fi
}
d=$(fresh); draw "$d" off; nothing "PROBE off" "$d"
d=$(fresh); draw "$d" on impl/plan; nothing "a shared branch" "$d"
mv "$OPTIN" "$OPTIN.off"
d=$(fresh); draw "$d"; nothing "no opt-in file" "$d"
printf 'off\non\n' > "$OPTIN"
d=$(fresh); draw "$d"; nothing "an opt-in file whose first line is not on" "$d"
rm -f "$OPTIN"; ln -s "$OPTIN.off" "$OPTIN"
d=$(fresh); draw "$d"; nothing "an opt-in file that is a symlink" "$d"
rm -f "$OPTIN"; mkdir "$OPTIN"
d=$(fresh); draw "$d"; nothing "an opt-in path that is a directory" "$d"
rmdir "$OPTIN"; mv "$OPTIN.off" "$OPTIN"

# Always exit 0: no entropy, an unwritable session directory.
mkdir -p "$T/bin-od"
printf '#!/bin/sh\nexit 1\n' > "$T/bin-od/od"; chmod 755 "$T/bin-od/od"
d=$(fresh)
OUT=$(PATH="$T/bin-od:$PATH" "$SUT" draw on "" "$d" "$REAL_ROOT" 2>&1); RC=$?
nothing "/dev/urandom unreadable (od fails)" "$d"
d=$(fresh); chmod 500 "$d"
if [ -w "$d" ]; then
    pass "SKIP: running as a user who can write a mode-500 directory; the unwritable case can't be built"
else
    draw "$d"
    [ $RC -eq 0 ] && [ -z "$OUT" ] && [ ! -e "$d/probe" ] && pass "an unwritable session directory: exit 0, no arm" \
        || fail "an unwritable session directory: rc=$RC out=[$OUT]"
fi
chmod 700 "$d"
OUT=$("$SUT" draw on "" "$T/no-such-dir" "$REAL_ROOT" 2>&1); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] && pass "a missing session directory: exit 0, nothing printed" \
    || fail "a missing session directory: rc=$RC out=[$OUT]"
OUT=$("$SUT" draw on 2>&1); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] && pass "draw with too few arguments: exit 0, nothing printed" \
    || fail "draw with too few arguments: rc=$RC out=[$OUT]"

# The mappings, over every byte.
MAP=$( . "$SUT"
    n=0 f=0 r=0 rej="" b=0
    while [ $b -le 255 ]; do
        if arm_of_byte $b; then
            case $MAPPED in (near) n=$((n + 1)) ;; (far) f=$((f + 1)) ;; (far_redeliver) r=$((r + 1)) ;; esac
        else rej="$rej $b"; fi
        b=$((b + 1))
    done
    echo "$n $f $r$rej")
check "arm mapping over 256 bytes: 85 near, 85 far, 85 far_redeliver, only 255 rejected" "$MAP" "85 85 85 255"
MAP=$( . "$SUT"
    b=0 out="" rej=0
    while [ $b -le 255 ]; do
        if letter_of_byte $b; then out="$out$MAPPED"; else rej=$((rej + 1)); [ $b -ge 234 ] || rej=999; fi
        b=$((b + 1))
    done
    bad=0
    for l in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
        c=$(printf '%s' "$out" | tr -cd "$l" | wc -c | tr -d ' ')
        [ "$c" = 9 ] || bad=$((bad + 1))
    done
    echo "${#out} $rej $bad")
check "letter mapping: bytes below 234 map to each letter 9 times, the 22 above are rejected" "$MAP" "234 22 0"
MAP=$( . "$SUT"
    b=0 out="" rej=0
    while [ $b -le 255 ]; do
        if digit_of_byte $b; then out="$out$MAPPED"; else rej=$((rej + 1)); [ $b -ge 250 ] || rej=999; fi
        b=$((b + 1))
    done
    bad=0
    for g in 0 1 2 3 4 5 6 7 8 9; do
        c=$(printf '%s' "$out" | tr -cd "$g" | wc -c | tr -d ' ')
        [ "$c" = 25 ] || bad=$((bad + 1))
    done
    echo "${#out} $rej $bad")
check "digit mapping: bytes below 250 map to each digit 25 times, the 6 above are rejected" "$MAP" "250 6 0"

# The value's form over 1000 consecutive draws.
FORM=$( . "$SUT"
    i=0 bad=0
    while [ $i -lt 1000 ]; do
        r=$(draw_arm_value) || { bad=$((bad + 1)); i=$((i + 1)); continue; }
        grep -Eq '^[a-z]{3}[0-9]{6}$' <<<"${r#* }" || bad=$((bad + 1))
        case "${r% *}" in (near|far|far_redeliver) ;; (*) bad=$((bad + 1)) ;; esac
        i=$((i + 1))
    done
    echo $bad)
check "1000 consecutive draws: every value matches ^[a-z]{3}[0-9]{6}\$ and every arm is one of the three" "$FORM" 0

# The record: value first, then arm, through mv; mode 0600; no symlinks.
mkdir -p "$T/bin-mv"
REAL_MV=$(command -v mv)
printf '#!/bin/sh\nfor a; do last=$a; done\nprintf "%%s\\n" "${last##*/}" >> "%s"\nexec "%s" "$@"\n' "$T/mv.log" "$REAL_MV" > "$T/bin-mv/mv"
chmod 755 "$T/bin-mv/mv"
d=$(fresh); : > "$T/mv.log"
PATH="$T/bin-mv:$PATH" "$SUT" draw on "" "$d" "$REAL_ROOT" >/dev/null 2>&1
check "draw moves value into place, then arm (then far_shown for a far run)" \
    "$(head -n 2 "$T/mv.log" | tr '\n' ' ')" "value arm "
check "the value file is mode 0600" "$(perms "$d/probe/value")" "-rw-------"
check "the arm file is mode 0600" "$(perms "$d/probe/arm")" "-rw-------"
leftover=$(find "$d/probe" -name '.*' -type f)
[ -z "$leftover" ] && pass "no temporary file is left behind" \
    || fail "temporary files left: $(ls -A "$d/probe")"

d=$(fresh); mkdir "$T/elsewhere"; ln -s "$T/elsewhere" "$d/probe"
draw "$d"
[ $RC -eq 0 ] && [ -z "$OUT" ] && [ -z "$(ls -A "$T/elsewhere")" ] && [ "$(arm_of "$d")" = 3 ] \
    && pass "a symlinked probe/ directory: nothing written through it, no arm" || fail "draw wrote through a symlinked probe/"
d=$(fresh); mkdir "$d/probe"; : > "$T/target-v"; ln -s "$T/target-v" "$d/probe/value"
draw "$d"
[ ! -s "$T/target-v" ] && [ ! -e "$d/probe/arm" ] && [ -z "$OUT" ] \
    && pass "a symlink at probe/value: refused, its target untouched" || fail "draw wrote through probe/value"
d=$(fresh); mkdir "$d/probe"; : > "$T/target-a"; ln -s "$T/target-a" "$d/probe/arm"
draw "$d"
[ ! -s "$T/target-a" ] && [ -z "$OUT" ] && [ "$(arm_of "$d")" = 3 ] \
    && pass "a symlink at probe/arm: refused, its target untouched, no arm" || fail "draw wrote through probe/arm"

# One session per arm, for the read-back cases.
ND=""; FD=""; RD=""; tries=0
while { [ -z "$ND" ] || [ -z "$FD" ] || [ -z "$RD" ]; } && [ $tries -lt 300 ]; do
    d=$(fresh); draw "$d"
    case "$(arm_of "$d")" in
        0) [ -n "$ND" ] || { ND=$d; NOUT=$OUT; } ;;
        1) [ -n "$FD" ] || { FD=$d; FOUT=$OUT; } ;;
        4) [ -n "$RD" ] || { RD=$d; ROUT=$OUT; } ;;
    esac
    tries=$((tries + 1))
done
if [ -z "$ND" ] || [ -z "$FD" ] || [ -z "$RD" ]; then
    fail "no session in every arm after $tries draws"
    echo; echo "probe_test: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
fi
pass "draws land in all three arms within $tries draws"

# far_shown and the printed text.
for pair in "far:$FD:$FOUT" "far_redeliver:$RD:$ROUT"; do
    a=${pair%%:*}; rest=${pair#*:}; dd=${rest%%:*}; out=${rest#*:}
    v=$(cat "$dd/probe/value")
    check "$a: the first draw prints the full rule with the value" "$out" "$(full_text "$v")"
    [ -f "$dd/probe/far_shown" ] && pass "$a: far_shown is recorded" || fail "$a: no far_shown"
    draw "$dd"
    check "$a: a second draw (analysis looping back) prints nothing" "$OUT" ""
done
check "near: the draw prints nothing" "$NOUT" ""
draw "$ND"; check "near: a second draw prints nothing" "$OUT" ""
[ ! -e "$ND/probe/far_shown" ] && pass "near: no far_shown" || fail "near: far_shown written"
if LC_ALL=C grep -Eq '^[a-zA-Z0-9._/:@+ \-]*$' <<<"$FOUT"; then
    pass "the printed rule holds only characters a captured value may hold"
else
    fail "the printed rule holds a character a capture refuses"
fi
G=$(grep -F '> Rule probe/ack-value:' "$GUIDE" | sed 's/^> //')
check "the guide's wording (the registry's anchor) is the printed text with <value>" "$G" "$(full_text '<value>')"
G=$(grep -F '> probe/ack-value: submit' "$GUIDE" | sed 's/^> //')
check "the guide's summary is the re-delivery's text with <value>" "$G" "$(summary_text '<value>')"

# Rewind read-back: a second draw redraws nothing.
for dd in "$ND" "$FD" "$RD"; do
    cp "$dd/probe/arm" "$T/arm.before"; cp "$dd/probe/value" "$T/value.before"
    draw "$dd"
    cmp -s "$dd/probe/arm" "$T/arm.before" && cmp -s "$dd/probe/value" "$T/value.before" \
        && pass "a second draw in $(cat "$dd/probe/arm" ) leaves arm and value byte-identical" \
        || fail "a second draw changed the record"
done

# The opt-in switched off after the draw.
log_with_ack() { # log_with_ack <file> <ack-json>: one pr_creation visit, one created submission
    {
        echo '{"schema_version":1}'
        echo '{"seq":1,"type":"transitioned","payload":{"from":"probe_near","to":"pr_creation"}}'
        printf '{"seq":2,"type":"evidence_submitted","payload":{"state":"pr_creation","fields":{"pr_status":"created","ack":%s}}}\n' "$2"
    } > "$1"
}
off_case() { # off_case <label> <switch> <shared>
    local dd want_arm want_miss a v
    for dd in "$ND" "$FD" "$RD"; do
        a=$(cat "$dd/probe/arm"); v=$(cat "$dd/probe/value")
        cp "$dd/probe/arm" "$T/arm.before"; cp "$dd/probe/value" "$T/value.before"
        OUT=$("$SUT" draw "$2" "$3" "$dd" "$REAL_ROOT"); RC=$?
        case $a in near) want_arm=0; want_miss=4 ;; far) want_arm=1; want_miss=4 ;; far_redeliver) want_arm=4; want_miss=1 ;; esac
        log_with_ack "$T/off.log" "\"$v\""
        SHIRABE_GATE_LOG="$T/off.log" "$SUT" check "$dd" >/dev/null 2>&1; hit=$?
        log_with_ack "$T/off.log" '"nope"'
        SHIRABE_GATE_LOG="$T/off.log" "$SUT" check "$dd" >/dev/null 2>&1; miss=$?
        nt=$("$SUT" near-text "$dd")
        if [ $RC -eq 0 ] && [ -z "$OUT" ] && cmp -s "$dd/probe/arm" "$T/arm.before" && cmp -s "$dd/probe/value" "$T/value.before" \
            && [ "$(arm_of "$dd")" = $want_arm ] && [ $hit -eq 0 ] && [ $miss -eq $want_miss ]; then
            pass "$1, $a: record unchanged, arm still $want_arm, check still decides (0 / $want_miss), far text not printed again"
        else
            fail "$1, $a: rc=$RC out=[$OUT] arm=$(arm_of "$dd") hit=$hit miss=$miss"
        fi
        if [ "$a" = near ]; then check "$1, near: near-text still prints the rule" "$nt" "$(full_text "$v")"; fi
    done
}
mv "$OPTIN" "$OPTIN.off"; off_case "opt-in file removed" on ""; mv "$OPTIN.off" "$OPTIN"
off_case "PROBE off" off ""
off_case "a shared branch set" on impl/plan

# No seed: a seed-like environment and extra arguments change nothing.
N=0 F=0 R=0 BADFORM=0 i=0
while [ $i -lt 90 ]; do
    d=$(fresh)
    RANDOM=7 SEED=7 PROBE_SEED=7 SOURCE_DATE_EPOCH=0 SRANDOM=7 "$SUT" draw on "" "$d" "$REAL_ROOT" extra --seed 7 >/dev/null 2>&1
    case "$(arm_of "$d")" in 0) N=$((N + 1)) ;; 1) F=$((F + 1)) ;; 4) R=$((R + 1)) ;; esac
    grep -Eq '^[a-z]{3}[0-9]{6}$' "$d/probe/value" 2>/dev/null || BADFORM=$((BADFORM + 1))
    [ "$(perms "$d/probe/value")" = "-rw-------" ] || BADFORM=$((BADFORM + 1))
    i=$((i + 1))
done
if [ $N -ge 10 ] && [ $F -ge 10 ] && [ $R -ge 10 ] && [ $((N + F + R)) -eq 90 ] && [ $BADFORM -eq 0 ]; then
    pass "90 draws under a fixed seed-like environment and extra arguments: $N near, $F far, $R far_redeliver, every file in form"
else
    fail "seed-like environment: $N/$F/$R, bad form $BADFORM"
fi
ENTROPY='\$RANDOM|SRANDOM|(^|[^a-z_])date( |\)|$)|shuf|/dev/random|openssl|(^|[^a-z_])jot |srand|rand\('
ENTROPY_HITS=$(grep -nE "$ENTROPY" "$SUT" | grep -v '^[0-9]*:[[:space:]]*#')
if [ -n "$ENTROPY_HITS" ]; then
    fail "probe.sh reads another entropy source: $(sed -n '1,3p' <<<"$ENTROPY_HITS")"
else
    pass "probe.sh's code names no entropy source but /dev/urandom"
fi
check "probe.sh reads /dev/urandom on exactly one code line" \
    "$(grep -n '/dev/urandom' "$SUT" | grep -vc '^[0-9]*:#')" 1

# --- B. arm, near-text and the template's gate mappings ----------------------

d=$(fresh); check "arm: no record exits 3" "$(arm_of "$d")" 3
d=$(fresh); record "$d" far "$(runtime_value)"; chmod 000 "$d/probe/value"
check "arm: an unreadable value file exits 3" "$(arm_of "$d")" 3
chmod 600 "$d/probe/value"
d=$(fresh); record "$d" sideways "$(runtime_value)"; check "arm: an arm out of shape exits 3" "$(arm_of "$d")" 3
d=$(fresh); record "$d" near "ABC"; check "arm: a value out of shape exits 3" "$(arm_of "$d")" 3
for a in far far_redeliver; do
    d=$(fresh); record "$d" $a "$(runtime_value)"
    check "near-text: $a prints nothing" "$("$SUT" near-text "$d"; echo "rc=$?")" "rc=0"
done
d=$(fresh); check "near-text: no arm prints nothing" "$("$SUT" near-text "$d"; echo "rc=$?")" "rc=0"

# gate_command <state> <gate>: the shipped command, unquoted from its YAML
# single-quoted scalar.
gate_command() {
    awk -v want="  $1:" -v g="      $2:" '
        /^states:$/ { s = 1; next }
        s && $0 == want { on = 1; next }
        on && /^  [a-z_]+:$/ { exit }
        on && $0 == g { f = 1; next }
        on && f && /^        command:/ {
            sub(/^        command: /, ""); c = $0
            if (c ~ /^'\''/) { c = substr(c, 2, length(c) - 2); gsub(/'\'''\''/, "'\''", c) }
            print c; exit
        }' "$TEMPLATE"
}
# run_gate <state> <gate> <plugin-root> <session-dir>: the command with its
# koto variables filled in, run by sh, exit printed.
run_gate() {
    local c
    c=$(gate_command "$1" "$2")
    c=$(printf '%s' "$c" | sed -e "s#{{PLUGIN_ROOT}}#$3#g" -e "s#{{SESSION_DIR}}#$4#g" \
        -e 's#{{SESSION_NAME}}#none#g' -e 's#{{ISSUE_NUMBER}}##g' -e 's#{{ISSUE_REPO}}##g' -e 's#{{ISSUE_SOURCE}}##g')
    (cd "$T" && PATH="$T/bin-nokoto:$PATH" sh -c "$c" >/dev/null 2>&1); echo $?
}
mkdir -p "$T/bin-nokoto"; printf '#!/bin/sh\nexit 1\n' > "$T/bin-nokoto/koto"; chmod 755 "$T/bin-nokoto/koto"
mkdir -p "$T/root-missing/skills/work-on/scripts" "$T/root-7/skills/work-on/scripts"
printf '#!/bin/sh\nexit 7\n' > "$T/root-7/skills/work-on/scripts/probe.sh"; chmod 755 "$T/root-7/skills/work-on/scripts/probe.sh"
[ -n "$(gate_command probe_draw probe_arm)" ] && [ -n "$(gate_command pr_creation probe_ack)" ] \
    && [ -n "$(gate_command pr_precheck probe_value_absent)" ] && pass "the template's probe gate commands extract" \
    || fail "a probe gate command did not extract from the template"
d=$(fresh)
check "probe_arm: a missing script maps to 3" "$(run_gate probe_draw probe_arm "$T/root-missing" "$d")" 3
check "probe_arm: any other exit maps to 3" "$(run_gate probe_draw probe_arm "$T/root-7" "$d")" 3
for pair in "near:0" "far:1" "far_redeliver:4"; do
    d=$(fresh); record "$d" "${pair%%:*}" "$(runtime_value)"
    check "probe_arm: ${pair%%:*} exits ${pair#*:} through the template's command" \
        "$(run_gate probe_draw probe_arm "$REAL_ROOT" "$d")" "${pair#*:}"
done
check "probe_ack: a missing script maps to 6" "$(run_gate pr_creation probe_ack "$T/root-missing" "$d")" 6
check "probe_ack: any other exit maps to 6" "$(run_gate pr_creation probe_ack "$T/root-7" "$d")" 6
for st in pr_precheck pr_creation ci_monitor; do
    check "$st probe_value_absent: a missing script passes (the run can have no arm)" \
        "$(run_gate $st probe_value_absent "$T/root-missing" "$d")" 0
    check "$st probe_value_absent: any other exit maps to 2 (hold)" \
        "$(run_gate $st probe_value_absent "$T/root-7" "$d")" 2
done
d=$(fresh)
check "pr_precheck probe_value_absent: a run in no arm passes through the template's command" \
    "$(run_gate pr_precheck probe_value_absent "$REAL_ROOT" "$d")" 0

# --- C. check ---------------------------------------------------------------

V=$(runtime_value)
[ -n "$V" ] || { echo "could not draw a runtime value" >&2; exit 2; }

SEQ=0
log_start() { SEQ=0; LOG=$1; echo '{"schema_version":1}' > "$LOG"; }
ev() { SEQ=$((SEQ + 1)); printf '{"seq":%s,"type":"%s","payload":%s}\n' "$SEQ" "$1" "$2" >> "$LOG"; }
enter() { ev transitioned "{\"from\":\"probe_near\",\"to\":\"${1-pr_creation}\"}"; }
created() { # created [ack-json]: a pr_status: created submission, with ack when given
    if [ $# -gt 0 ]; then
        ev evidence_submitted "{\"state\":\"pr_creation\",\"fields\":{\"pr_status\":\"created\",\"pr_url\":\"https://github.com/o/r/pull/7\",\"ack\":$1}}"
    else
        ev evidence_submitted '{"state":"pr_creation","fields":{"pr_status":"created","pr_url":"https://github.com/o/r/pull/7"}}'
    fi
}
evaluated() { ev gate_evaluated '{"state":"pr_creation","gate":"probe_ack","outcome":"failed"}'; }

# run_check <label> <session-dir> <want-exit> [submitted-string]: runs check
# on LOG, asserts the exit, and that neither the submitted string nor the
# value appears in its output outside the rule text exit 1 hands back.
run_check() {
    local label=$1 dd=$2 want=$3 sub=${4-} out rc clean v
    out=$(SHIRABE_GATE_LOG="$LOG" "$SUT" check "$dd" 2>&1); rc=$?
    CHECK_OUT=$out
    check "$label: exit" "$rc" "$want"
    v=$(cat "$dd/probe/value" 2>/dev/null)
    clean=$(printf '%s' "$out" | sed -e "s#$(summary_text "$v" | sed 's/[.[\*^$/]/\\&/g')##g" \
        -e "s#$(full_text "$v" | sed 's/[.[\*^$/]/\\&/g')##g")
    if [ -n "$v" ] && grep -qiF -e "$v" <<<"$clean"; then
        fail "$label: the value is printed outside the rule text"
    elif [ -n "$sub" ] && [ ${#sub} -ge 4 ] && grep -qF -e "$sub" <<<"$out"; then
        fail "$label: the submitted string is printed"
    else
        pass "$label: prints neither the value (outside the rule text) nor the submitted string"
    fi
}
findings_of() { printf '%s\n' "$CHECK_OUT" | sed -n 's/^::koto-finding:://p'; }
marker_of() { printf '%s\n' "$CHECK_OUT" | sed -n 's/^::koto-rule-delivered:://p'; }

S_NEAR=$(fresh); record "$S_NEAR" near "$V"
S_FAR=$(fresh); record "$S_FAR" far "$V"
S_RED=$(fresh); record "$S_RED" far_redeliver "$V"
S_NONE=$(fresh)

log_start "$T/l.jsonl"; enter; created "\"$V\""
for s in "$S_NEAR" "$S_FAR" "$S_RED"; do
    run_check "a match in $(cat "$s/probe/arm")" "$s" 0 "$V"
    check "a match prints nothing" "$CHECK_OUT" ""
done
SHIRABE_GATE_LOG="$T/missing.jsonl" "$SUT" check "$S_NONE" >/dev/null 2>&1
check "a run in no arm exits 0, whatever the log" "$?" 0

log_start "$T/l.jsonl"; enter
run_check "no submission yet" "$S_RED" 0
check "no submission yet prints only the not-ready marker" "$CHECK_OUT" "::koto-not-ready::"
ev evidence_submitted '{"state":"pr_creation","fields":{"pr_status":"creation_failed_retry"}}'
run_check "no created submission in the visit" "$S_RED" 0
check "... still only the not-ready marker" "$CHECK_OUT" "::koto-not-ready::"
log_start "$T/l.jsonl"; enter; created '"wrong"'; enter
run_check "a created submission only in an earlier visit" "$S_NEAR" 0
check "... is not ready in this visit" "$CHECK_OUT" "::koto-not-ready::"

for s in "$S_NEAR" "$S_FAR"; do
    log_start "$T/l.jsonl"; enter; created '"wrong-value"'
    run_check "$(cat "$s/probe/arm") miss" "$s" 4 wrong-value
    check "$(cat "$s/probe/arm") miss: one finding, probe/ack-value, fixed message" \
        "$(findings_of | jq -r '"\(.rule_id)|\(.message)"')" "probe/ack-value|no matching value"
    check "$(cat "$s/probe/arm") miss: no delivery marker" "$(marker_of)" ""
done
log_start "$T/l.jsonl"; enter; created
run_check "near: a created submission with no ack" "$S_NEAR" 4

# far_redeliver's ladder: summary, full, then advance.
log_start "$T/l.jsonl"; enter; created '"miss-one"'
run_check "far_redeliver, first miss" "$S_RED" 1 miss-one
check "first miss: the finding's message is the summary" "$(findings_of | jq -r .message)" "$(summary_text "$V")"
check "first miss: a summary delivery marker" "$(marker_of | jq -c .)" '{"rule_id":"probe/ack-value","extent":"summary","delivery":"printed"}'
evaluated
run_check "far_redeliver, first miss evaluated again (a second tick)" "$S_RED" 1 miss-one
check "re-evaluation: the same finding" "$(findings_of | jq -r .message)" "$(summary_text "$V")"
check "re-evaluation: no second delivery marker" "$(marker_of)" ""
created '"miss-two"'
run_check "far_redeliver, second miss" "$S_RED" 1 miss-two
check "second miss: the finding's message is the full text" "$(findings_of | jq -r .message)" "$(full_text "$V")"
check "second miss: a full delivery marker" "$(marker_of | jq -r .extent)" full
evaluated
created '"miss-three"'
run_check "far_redeliver, third miss" "$S_RED" 5 miss-three
check "third miss: the fixed finding" "$(findings_of | jq -r .message)" "no matching value"
check "third miss: no delivery marker" "$(marker_of)" ""
log_start "$T/l.jsonl"; enter; created '"m1"'; evaluated; created '"m2"'; evaluated; created "\"$V\""
run_check "far_redeliver, a match on the third submission" "$S_RED" 0 "$V"

# A miss from an earlier visit doesn't count.
log_start "$T/l.jsonl"; enter; created '"old-1"'; evaluated; created '"old-2"'; evaluated
enter; created '"new-1"'
run_check "far_redeliver, two misses in an earlier visit, one in this" "$S_RED" 1 new-1
check "... is this visit's first miss: the summary" "$(findings_of | jq -r .message)" "$(summary_text "$V")"
log_start "$T/l.jsonl"; enter; created '"old-1"'; evaluated; created '"old-2"'; evaluated
ev rewound '{"from":"ci_monitor","to":"pr_creation"}'; created '"new-1"'
run_check "a rewind into pr_creation starts a new visit" "$S_RED" 1 new-1

# Exact comparison: each of these fails against the recorded value.
UPPER=$(printf '%s' "$V" | tr a-z A-Z)
LONGER="x${V}y"
for sub in "$UPPER" " $V" "$V " "$V<NL>" "${V%?}" "${V#?}" "$LONGER" '*' "${V:0:3}*" \
    "${V:0:1}[a-z]${V:2}" '.*' "^${V}\$"; do
    log_start "$T/l.jsonl"; enter
    # <NL> stands for a trailing newline, which a command substitution would drop.
    ev evidence_submitted "$(jq -cn --arg a "$sub" '{state: "pr_creation", fields: {pr_status: "created", ack: ($a | sub("<NL>$"; "\n"))}}')"
    out=$(SHIRABE_GATE_LOG="$LOG" "$SUT" check "$S_NEAR" 2>&1); rc=$?
    [ $rc -eq 4 ] && pass "exact comparison: [$(printf '%s' "$sub" | sed "s/$V/<value>/; s/$UPPER/<VALUE>/")] misses" \
        || fail "exact comparison: a variant of the value exited $rc"
done
log_start "$T/l.jsonl"; enter
ev evidence_submitted '{"state":"pr_creation","fields":{"pr_status":"created","ack":482913}}'
run_check "a non-string ack misses" "$S_NEAR" 4
log_start "$T/l.jsonl"; enter
ev evidence_submitted "$(jq -cn --arg b "Body with $V in it" '{state: "pr_creation", fields: {pr_status: "created", pr_url: "u", body: $b}}')"
run_check "the value only elsewhere in the evidence, not in ack, misses" "$S_NEAR" 4

# Exit 6: unreadable log, unreadable or broken probe files.
log_start "$T/l.jsonl"; enter; created '"x"'
out=$(SHIRABE_GATE_LOG="" "$SUT" check "$S_NEAR" 2>&1); check "no SHIRABE_GATE_LOG: exit 6" "$?" 6
check "... prints nothing" "$out" ""
out=$(SHIRABE_GATE_LOG="$T/absent.jsonl" "$SUT" check "$S_NEAR" 2>&1); check "a missing log: exit 6" "$?" 6
cp "$LOG" "$T/locked.jsonl"; chmod 000 "$T/locked.jsonl"
if [ -r "$T/locked.jsonl" ]; then
    pass "SKIP: a mode-000 file is readable to this user"
else
    out=$(SHIRABE_GATE_LOG="$T/locked.jsonl" "$SUT" check "$S_NEAR" 2>&1); check "an unreadable log: exit 6" "$?" 6
fi
printf 'not json\n' > "$T/garbage.jsonl"
out=$(SHIRABE_GATE_LOG="$T/garbage.jsonl" "$SUT" check "$S_NEAR" 2>&1); check "a log that isn't JSON: exit 6" "$?" 6
d=$(fresh); record "$d" near "$V"; chmod 000 "$d/probe/value"
if [ -r "$d/probe/value" ]; then pass "SKIP: mode-000 readable"; else
    out=$(SHIRABE_GATE_LOG="$LOG" "$SUT" check "$d" 2>&1); check "an unreadable value file: exit 6" "$?" 6
fi
chmod 600 "$d/probe/value"
d=$(fresh); record "$d" sideways "$V"
out=$(SHIRABE_GATE_LOG="$LOG" "$SUT" check "$d" 2>&1); check "an arm out of shape: exit 6" "$?" 6
d=$(fresh); mkdir "$d/probe"; printf 'near\n' > "$d/probe/arm"
out=$(SHIRABE_GATE_LOG="$LOG" "$SUT" check "$d" 2>&1); check "an arm without a value: exit 6" "$?" 6

# The time limit: a reader that never returns.
mkdir -p "$T/bin-slow"
printf '#!/bin/sh\nexec sleep 40\n' > "$T/bin-slow/jq"; chmod 755 "$T/bin-slow/jq"
start=$(date +%s)
out=$(PATH="$T/bin-slow:$PATH" SHIRABE_GATE_LOG="$LOG" "$SUT" check "$S_NEAR" 2>&1); rc=$?
took=$(( $(date +%s) - start ))
if [ $rc -eq 6 ] && [ $took -ge 9 ] && [ $took -le 16 ] && [ -z "$out" ]; then
    pass "a stalled reader: check stops itself with exit 6 after ${took}s, printing nothing"
else
    fail "a stalled reader: rc=$rc after ${took}s out=[$out]"
fi

# No network: no network tool is started, and the source names none in code.
mkdir -p "$T/bin-net"
for tool in gh curl wget nc ssh git; do
    printf '#!/bin/sh\necho %s >> "%s"\nexit 1\n' "$tool" "$T/net.log" > "$T/bin-net/$tool"; chmod 755 "$T/bin-net/$tool"
done
: > "$T/net.log"
log_start "$T/l.jsonl"; enter; created '"m"'
PATH="$T/bin-net:$PATH" SHIRABE_GATE_LOG="$LOG" "$SUT" check "$S_RED" >/dev/null 2>&1
check "check starts no network or git tool" "$(cat "$T/net.log")" ""
CHECK_BODY=$(awk '/^check_facts\(\)/,/^# --- leak gates/' "$SUT")
CHECK_CODE=$(grep -v '^[[:space:]]*#' <<<"$CHECK_BODY")
if grep -qE '(^|[^a-zA-Z_.-])(gh|curl|wget|nc|git) ' <<<"$CHECK_CODE"; then
    fail "check's code names a network tool"
else
    pass "check's code names no network tool"
fi
grep -q -- "--arg v \"\$2\"" "$SUT" && pass "check passes the recorded value to jq through --arg" \
    || fail "check does not pass the value through --arg"

# --- D. the leak gates ------------------------------------------------------

REPO="$T/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com; git -C "$REPO" config user.name t
echo base > "$REPO/README"; git -C "$REPO" add README; git -C "$REPO" commit -q -m "chore: base"
BASE=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -b feature/x
echo work > "$REPO/work.txt"; git -C "$REPO" add work.txt; git -C "$REPO" commit -q -m "feat: work"
CLEAN_HEAD=$(git -C "$REPO" rev-parse HEAD)

LV=$(runtime_value)
SL=$(fresh); record "$SL" far "$LV"
SN=$(fresh)
LUP=$(printf '%s' "$LV" | tr a-z A-Z)
PLANT="planted line carrying $LV for the route"

# The gh stub: answers from files in $GHD, or fails or hangs.
GHD="$T/gh"; mkdir -p "$GHD" "$T/bin-gh"
cat > "$T/bin-gh/gh" <<EOF
#!/bin/sh
echo "\$*" >> "$GHD/calls"
[ -f "$GHD/fail" ] && exit 1
[ -f "$GHD/hang" ] && exec sleep 60
case "\$1 \$2" in
    "pr view") cat "$GHD/pr.json" ;;
    "api --paginate")
        case "\$3" in
            */pulls/*/comments) cat "$GHD/inline1.json" "$GHD/inline2.json" ;;
            */issues/*/comments) cat "$GHD/issue.json" ;;
            *) exit 1 ;;
        esac ;;
    *) exit 1 ;;
esac
EOF
chmod 755 "$T/bin-gh/gh"
gh_clean() {
    rm -f "$GHD/fail" "$GHD/hang" "$GHD/calls"
    jq -n '{number: 7, url: "https://github.com/o/r/pull/7", title: "feat: work", body: "A body.",
            comments: [{body: "a comment"}], reviews: [{body: "a review"}]}' > "$GHD/pr.json"
    echo '[{"body":"first page"}]' > "$GHD/inline1.json"
    echo '[{"body":"second page"}]' > "$GHD/inline2.json"
    echo '[{"body":"an issue comment"}]' > "$GHD/issue.json"
}
gh_clean

PRLOG="$T/pr.jsonl"
log_start "$PRLOG"; enter; created '"x"'
NOPRLOG="$T/nopr.jsonl"
log_start "$NOPRLOG"; enter

# leak <subcommand> <session-dir> [<log>]: runs from the repository with the
# gh stub; output in LOUT, exit in LRC.
leak() {
    local sub=$1 dd=$2 lg=${3-$PRLOG}
    if [ "$sub" = leak-branch ]; then
        LOUT=$(cd "$REPO" && PATH="$T/bin-gh:$PATH" "$SUT" leak-branch "$dd" "$BASE" 2>&1); LRC=$?
    else
        LOUT=$(cd "$REPO" && PATH="$T/bin-gh:$PATH" SHIRABE_GATE_LOG="$lg" "$SUT" leak-pr "$dd" "$BASE" 42 o/r 2>&1); LRC=$?
    fi
}
# caught <label> <route-word>: exit 1, one probe/value-absent finding naming
# the route, and nothing of the value or the planted line in the output.
caught() {
    local msg
    msg=$(printf '%s\n' "$LOUT" | sed -n 's/^::koto-finding:://p' | jq -r 'select(.rule_id == "probe/value-absent") | .message' 2>/dev/null)
    if [ $LRC -eq 1 ] && grep -qF -- "$2" <<<"$msg" \
        && ! grep -qiF -e "$LV" <<<"$LOUT" && ! grep -qF -e "planted line" <<<"$LOUT"; then
        pass "$1: caught (exit 1), the finding names [$2], and neither the value nor the planted line is printed"
    else
        fail "$1: rc=$LRC out=[$(printf '%s' "$LOUT" | sed "s/$LV/<value>/g")]"
    fi
}
reset_branch() { git -C "$REPO" reset -q --hard "$CLEAN_HEAD"; }

d=$(cd "$T" && "$SUT" leak-branch "$SN" "$BASE" 2>&1; echo "rc=$?")
check "leak-branch: a run in no arm exits 0 at once, even outside a repository" "$d" "rc=0"
d=$(cd "$T" && SHIRABE_GATE_LOG="$T/absent" "$SUT" leak-pr "$SN" "$BASE" 2>&1; echo "rc=$?")
check "leak-pr: a run in no arm exits 0 at once" "$d" "rc=0"

leak leak-branch "$SL"; check "clean branch: leak-branch passes" "$LRC/$LOUT" "0/"
leak leak-pr "$SL"; check "clean branch and pull request: leak-pr passes" "$LRC/$LOUT" "0/"
rm -f "$GHD/calls"
leak leak-pr "$SL" "$NOPRLOG"
check "leak-pr before the pull request exists: passes with the not-ready marker" "$LRC/$LOUT" "0/::koto-not-ready::"
[ ! -s "$GHD/calls" ] && pass "... and calls gh not at all" || fail "leak-pr called gh before the pull request existed"

# The branch routes.
git -C "$REPO" commit -q --allow-empty -m "feat: note $LUP"
leak leak-branch "$SL"; caught "a commit message (upper case)" "commit message or patch"
leak leak-pr "$SL" "$NOPRLOG"; caught "leak-pr before the pull request: a commit message" "commit message or patch"
reset_branch; leak leak-branch "$SL"; check "... removed: passes" "$LRC" 0
printf '%s\n' "$PLANT" > "$REPO/notes.txt"; git -C "$REPO" add notes.txt; git -C "$REPO" commit -q -m "docs: notes"
leak leak-branch "$SL"; caught "a committed file" "commit message or patch"
reset_branch; leak leak-branch "$SL"; check "... removed: passes" "$LRC" 0
printf '%s\n' "$PLANT" > "$REPO/tmp.txt"; git -C "$REPO" add tmp.txt; git -C "$REPO" commit -q -m "chore: add"
git -C "$REPO" rm -q tmp.txt; git -C "$REPO" commit -q -m "chore: remove"
[ ! -e "$REPO/tmp.txt" ] && leak leak-branch "$SL"; caught "a file added then removed" "commit message or patch"
reset_branch; leak leak-branch "$SL"; check "... rewritten away: passes" "$LRC" 0

# The pull request routes, through the gh stub.
pr_route() { # pr_route <label> <route-word> <jq edit of pr.json | file:content>
    gh_clean
    case "$3" in
        inline2) jq -n --arg b "$PLANT" '[{body: $b}]' > "$GHD/inline2.json" ;;
        issue) jq -n --arg b "$PLANT" '[{body: "x"}, {body: $b}]' > "$GHD/issue.json" ;;
        *) jq --arg p "$PLANT" "$3" "$GHD/pr.json" > "$GHD/pr.new" && mv "$GHD/pr.new" "$GHD/pr.json" ;;
    esac
    leak leak-pr "$SL"; caught "$1" "$2"
    gh_clean; leak leak-pr "$SL"; check "$1, removed: passes" "$LRC" 0
}
pr_route "the pull request title" "title" '.title = "feat: " + $p'
pr_route "the pull request body" "body" '.body = "Intro.\n\n" + $p'
pr_route "a pull request comment" "pull request comment" '.comments += [{body: $p}]'
pr_route "a review body" "review" '.reviews += [{body: $p}]'
pr_route "an inline review comment on the second page" "inline review comment" inline2
pr_route "an issue comment" "issue comment" issue
gh_clean; leak leak-pr "$SL"
grep -q 'repos/o/r/pulls/7/comments' "$GHD/calls" && grep -q -- '--paginate repos/o/r/pulls/7/comments' "$GHD/calls" \
    && grep -q 'repos/o/r/issues/42/comments' "$GHD/calls" \
    && pass "leak-pr reads every page of the inline comments and the issue's comments" \
    || fail "leak-pr's gh calls: $(cat "$GHD/calls" | tr '\n' ';')"

# gh failing or hanging once the pull request exists holds.
gh_clean; : > "$GHD/fail"; leak leak-pr "$SL"; check "a gh failure once the pull request exists: exit 2" "$LRC" 2
gh_clean; : > "$GHD/hang"
start=$(date +%s); leak leak-pr "$SL"; took=$(( $(date +%s) - start ))
if [ $LRC -eq 2 ] && [ $took -ge 19 ] && [ $took -le 30 ]; then
    pass "a hanging gh: exit 2 after ${took}s, the 20-second limit"
else
    fail "a hanging gh: rc=$LRC after ${took}s"
fi
gh_clean

# The matching and the stderr discipline, read from the source.
grep -q 'grep -F -i -q -e "$LEAK_VALUE"' "$SUT" && pass "the leak gates match with grep -F -i -e" \
    || fail "the leak gates don't match as a case-insensitive fixed string"
grep -q -- '--end-of-options "$base..HEAD"' "$SUT" && grep -q -- '--end-of-options "$1^{commit}"' "$SUT" \
    && pass "the base reaches git after --end-of-options" || fail "the base reaches git before --end-of-options"
# Every tool's stderr goes to /dev/null: a gh that echoes the planted content
# on stderr, a git that can't resolve the base, and a jq that can't parse
# what gh printed all leave the output empty.
gh_clean
printf '#!/bin/sh\necho "%s" >&2\nexit 1\n' "$PLANT" > "$T/bin-noisy-gh"; chmod 755 "$T/bin-noisy-gh"
mkdir -p "$T/bin-noisy"; cp "$T/bin-noisy-gh" "$T/bin-noisy/gh"
LOUT=$(cd "$REPO" && PATH="$T/bin-noisy:$PATH" SHIRABE_GATE_LOG="$PRLOG" "$SUT" leak-pr "$SL" "$BASE" 2>&1); LRC=$?
check "a gh that fails noisily: exit 2 and nothing printed" "$LRC/$LOUT" "2/"
LOUT=$(cd "$T" && "$SUT" leak-branch "$SL" "--output=$T/x" 2>&1); LRC=$?
check "outside a repository, a base that looks like an option: exit 2, nothing printed" "$LRC/$LOUT" "2/"
[ ! -e "$T/x" ] && pass "... and git never took the base as an option" || fail "git took the base as an option"
LOUT=$(cd "$REPO" && "$SUT" leak-branch "$SL" "" 2>&1); LRC=$?
check "an empty base with no origin/HEAD to fall back on: exit 2 (hold), nothing printed" "$LRC/$LOUT" "2/"
gh_clean; echo 'not json' > "$GHD/pr.json"
leak leak-pr "$SL"; check "a pull request read that isn't JSON: exit 2, nothing printed" "$LRC/$LOUT" "2/"
gh_clean

# --- E. no value in the repository ------------------------------------------

if git -C "$REAL_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    HITS=$(cd "$REAL_ROOT" && git ls-files -z | xargs -0 grep -lE '(^|[^A-Za-z0-9])[a-z]{3}[0-9]{6}([^A-Za-z0-9]|$)' 2>/dev/null)
    check "no tracked file holds a value-shaped string (three letters, six digits)" "$HITS" ""
    # A control: the same search does find a planted one.
    printf 'x %s y\n' "$LV" > "$T/control.txt"
    grep -qE '(^|[^A-Za-z0-9])[a-z]{3}[0-9]{6}([^A-Za-z0-9]|$)' "$T/control.txt" \
        && pass "control: the search finds a planted value" || fail "control: the search missed a planted value"
    HITS=$(cd "$REAL_ROOT" && for v in "$V" "$LV"; do git grep -l -F -i -e "$v"; done 2>/dev/null)
    check "neither runtime value reached a tracked path" "$HITS" ""
else
    pass "SKIP: not a git checkout; the repository search did not run"
fi

echo
echo "probe_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
