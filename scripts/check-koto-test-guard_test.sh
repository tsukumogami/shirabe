#!/usr/bin/env bash
# check-koto-test-guard_test.sh -- scripts/check-koto-test-guard.sh, and the
# guard it holds every suite to, scripts/lib/koto-test-guard.sh (shirabe#1288).
#
# Covers the check: the repository's own suites pass; a suite that names koto
# (a koto call, or a script named for it) with no guard line, with the line
# after its first koto, with the line naming a file that isn't there, or with
# the line in another shape is refused at its first koto; one that names koto
# only in a comment, or not at all, is not; only *_test.sh is read; a missing
# path is 2. A suite that holds the guard line and sets its own EXIT trap
# (`trap cmd EXIT`, signal 0, EXIT in a list, a quoted command over several
# lines, a trap after `;`, `&&` or `then`, one after a comment holding a quote
# or an arithmetic shift) is refused at the trap, with or without koto in it,
# and so is one whose guard line names a missing file; one that uses
# ktg_on_exit, sets a trap only for other signals, prints its traps, drops
# them with `trap - EXIT`, or sets an EXIT trap indented (a subshell's),
# inside a heredoc or inside a quoted string is not, nor is a suite without
# the guard line.
#
# And the guard, sourced by a fixture suite run under `env -i` with a stub koto
# that only answers `koto session dir` and records what it was called with, so
# no case can reach a real store or bucket: the session-backend variables,
# pointed at dummy paths and a dummy bucket, are gone before koto is first
# called; a suite without the guard hands them straight to koto; one that
# can't be cleared (readonly), a session directory outside the guard's own, a
# failing `koto session dir`, a missing guard file and a directory that can't
# be made each stop the suite before its cases, the first of them before any
# koto call; no koto on PATH and a failing mktemp don't; the guard's directory
# is gone after a suite that sets no trap; a suite that hands its cleanup to
# ktg_on_exit leaves TMPDIR empty, runs its cleanup and keeps its exit status,
# a second call replaces the first command, a call with two arguments stops
# the suite, and under set -e a failing command exits as the suite's own trap
# did; a suite that sets its own EXIT trap leaves the guard's
# directory behind, which is why the check refuses one; and
# deliver-open_test.sh, the suite
# that pushed sessions to a real bucket, stops before its first case when koto
# resolves its store anywhere else.
#
# Usage: bash scripts/check-koto-test-guard_test.sh
set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
CHECK="$HERE/check-koto-test-guard.sh"
GUARD="$HERE/lib/koto-test-guard.sh"
BASH_BIN=$(command -v bash)
T=$(mktemp -d "${TMPDIR:-/tmp}/check-koto-test-guard-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */check-koto-test-guard-test.*) rm -rf "$T" ;; esac'
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

NL=$'\n'
# put <file> <text>: a script holding the text, each <NL> a newline.
put() { mkdir -p "$(dirname "$1")"; printf '#!/usr/bin/env bash\n%s\n' "${2//<NL>/$NL}" > "$1"; }
LINE3='. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1'

echo "== the repository =="
if OUT=$(bash "$CHECK" 2>&1); then ok "every suite that names koto sources the guard first"; else bad "every suite that names koto sources the guard first" "$OUT"; fi

echo "== the check =="
L="$T/lint"
mkdir -p "$L/scripts/lib"
: > "$L/scripts/lib/koto-test-guard.sh"
S="$L/skills/x/scripts"
# lint <label> <want rc> <want text> <suite text>
lint() {
    put "$S/a_test.sh" "$4"
    OUT=$(bash "$CHECK" "$S/a_test.sh" 2>&1); rc=$?
    case "$rc:$OUT" in "$2":*"$3"*) ok "$1" ;; *) bad "$1" "rc=$rc out=$OUT" ;; esac
}
lint "no guard line: refused at the first koto" 1 "a_test.sh:3: names koto without" \
    'set -u<NL>koto next s'
lint "a script named for koto counts as koto" 1 "a_test.sh:3: names koto without" \
    'set -u<NL>bash "$HERE/koto-open.sh" s'
lint "the guard line after the first koto: refused" 1 "names koto before the koto-test-guard.sh line" \
    "set -u<NL>command -v koto<NL>$LINE3"
lint "the guard line naming a file that isn't there: refused" 1 "which is not there" \
    'set -u<NL>. "$(dirname "$0")/../../scripts/lib/koto-test-guard.sh" || exit 1<NL>koto next s'
lint "the guard line without || exit 1: refused" 1 "names koto without" \
    'set -u<NL>. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh"<NL>koto next s'
lint "the guard line inside a condition: refused" 1 "names koto without" \
    "set -u<NL>if true; then $LINE3; fi<NL>koto next s"
lint "the guard line before the first koto: passes" 0 "" \
    "set -u<NL>$LINE3<NL>koto next s"
lint "koto named only in a comment: passes" 0 "" \
    'set -u<NL># this suite never runs koto<NL>echo hi'
lint "KOTO_ variables alone are not koto: passes" 0 "" \
    'set -u<NL>echo "${KOTO_BIN:-none}"'
lint "the guard and its own trap ... EXIT: refused at the trap" 1 "a_test.sh:4: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>trap cleanup EXIT<NL>koto next s"
lint "the guard and an EXIT trap after ; on the mktemp line: refused" 1 "a_test.sh:4: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>T=\$(mktemp -d) || exit 1; trap 'rm -rf \"\$T\"' EXIT<NL>koto next s"
lint "the guard and an EXIT trap after &&: refused" 1 "a_test.sh:4: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>[ -n \"\$T\" ] && trap cleanup EXIT<NL>koto next s"
lint "the guard and an EXIT trap after then: refused" 1 "a_test.sh:4: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>if true; then trap cleanup EXIT; fi<NL>koto next s"
lint "the guard and an EXIT trap after a comment with a quote: refused" 1 "a_test.sh:5: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>echo hi # it's here<NL>trap cleanup EXIT<NL>koto next s"
lint "the guard and an EXIT trap after a shift in arithmetic: refused" 1 "a_test.sh:5: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>n=\$((1<<x))<NL>trap cleanup EXIT<NL>koto next s"
lint "the guard and trap - EXIT, which keeps every directory: passes" 0 "" \
    "set -u<NL>$LINE3<NL>if [ -n \"\${KEEP_T-}\" ]; then trap - EXIT; fi<NL>koto next s"
lint "the guard and trap ... EXIT inside a quoted string: passes" 0 "" \
    "set -u<NL>$LINE3<NL>echo \"trap cleanup EXIT\"<NL>koto next s"
lint "the guard line naming a missing file, no koto in the suite: refused" 1 "which is not there" \
    'set -u<NL>. "$(dirname "$0")/../../scripts/lib/koto-test-guard.sh" || exit 1<NL>echo hi'
lint "the guard and a trap on signal 0: refused" 1 "a_test.sh:4: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>trap 'rm -rf \"\$T\"' 0<NL>koto next s"
lint "the guard and EXIT in a list of signals: refused" 1 "a_test.sh:4: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>trap 'rm -rf \"\$T\"' INT EXIT<NL>koto next s"
lint "the guard and a quoted trap over two lines: refused at its first line" 1 "a_test.sh:4: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>trap 'rm -rf \"\$T\"<NL>    echo done' EXIT<NL>koto next s"
lint "the guard and an EXIT trap, no koto in the suite: refused" 1 "a_test.sh:4: sets its own EXIT trap" \
    "set -u<NL>$LINE3<NL>trap cleanup EXIT<NL>echo hi"
lint "the guard and ktg_on_exit: passes" 0 "" \
    "set -u<NL>$LINE3<NL>ktg_on_exit 'rm -rf \"\$T\"'<NL>koto next s"
lint "the guard and a trap on INT and TERM only: passes" 0 "" \
    "set -u<NL>$LINE3<NL>trap 'exit 130' INT<NL>trap 'exit 143' TERM<NL>koto next s"
lint "the guard and trap -p EXIT: passes" 0 "" \
    "set -u<NL>$LINE3<NL>trap -p EXIT<NL>koto next s"
lint "the guard and a subshell's indented EXIT trap: passes" 0 "" \
    "set -u<NL>$LINE3<NL>(<NL>    trap 'echo exit' EXIT<NL>    koto next s<NL>)"
lint "the guard and an EXIT trap in a heredoc fixture: passes" 0 "" \
    "set -u<NL>$LINE3<NL>cat > \"\$T/f.sh\" <<'EOF'<NL>trap cleanup EXIT<NL>EOF<NL>koto next s"
lint "no guard line, no koto, its own EXIT trap: passes" 0 "" \
    'set -u<NL>trap cleanup EXIT<NL>echo hi'
put "$S/helper.sh" 'koto next s'
OUT=$(bash "$CHECK" "$S" 2>&1); rc=$?
case "$OUT" in *helper.sh*) bad "a directory: only *_test.sh is read" "$OUT" ;; *) ok "a directory: only *_test.sh is read" ;; esac
bash "$CHECK" "$T/none" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "a missing path: exit 2" || bad "a missing path: exit 2" "rc=$rc"

echo "== the guard =="
# The tools a fixture suite and the guard need, without the developer's koto.
SYS="$T/sys"
mkdir -p "$SYS"
for tool in env sed mkdir rm cat dirname; do
    p=$(command -v "$tool") || { bad "$tool on PATH" "not found"; continue; }
    ln -s "$p" "$SYS/$tool"
done
# A stub koto: it records its argv and the names of the KOTO_ and AWS_
# variables it was handed, and answers `koto session dir <name>` as
# STUB_MODE says: honest resolves the store the way koto does, outside always
# names a store under $STUB_OUTSIDE, fail fails.
BIN="$T/bin"
mkdir -p "$BIN"
cat > "$BIN/koto" <<'EOF'
#!/bin/sh
{
    printf 'argv:'; printf ' %s' "$@"; printf '\n'
    env | sed -n -E 's/^((KOTO|AWS)_[A-Za-z0-9_]*)=.*/env: \1/p'
} >> "$STUB_LOG"
[ "$1 $2" = "session dir" ] || exit 0
case "$STUB_MODE" in
    honest)
        if [ -n "${KOTO_SESSIONS_BASE:-}" ]; then echo "$KOTO_SESSIONS_BASE/$3"
        elif [ -n "${KOTO_HOME:-}" ]; then echo "$KOTO_HOME/sessions/$3"
        else echo "$HOME/.koto/sessions/$3"; fi ;;
    outside) echo "$STUB_OUTSIDE/$3" ;;
    *) echo "koto: session dir failed on purpose" >&2; exit 2 ;;
esac
EOF
chmod +x "$BIN/koto"
printf '#!/bin/sh\necho "mktemp: failing on purpose" >&2\nexit 1\n' > "$BIN/mktemp"
chmod +x "$BIN/mktemp"

# A fixture repository whose suite sources a copy of the guard, then reports
# what it was left with: the KOTO_ and AWS_ names still set, HOME, and the
# guard's directory.
G="$T/g"
mkdir -p "$G/scripts/lib"
cp "$GUARD" "$G/scripts/lib/koto-test-guard.sh"
REPORT='echo CASES RAN<NL>env | sed -n -E "s/^((KOTO|AWS)_[A-Za-z0-9_]*)=.*/still set: \1/p"<NL>echo "HOME=$HOME"<NL>echo "DIR=$KOTO_TEST_GUARD_DIR"'
put "$G/scripts/s_test.sh" "set -uo pipefail<NL>. \"\$(dirname \"\$0\")/lib/koto-test-guard.sh\" || exit 1<NL>$REPORT"
put "$G/scripts/unguarded_test.sh" 'set -uo pipefail<NL>koto session dir probe'
put "$G/scripts/gone_test.sh" "set -uo pipefail<NL>. \"\$(dirname \"\$0\")/lib/missing-guard.sh\" || exit 1<NL>$REPORT"

LOG="$T/koto.log"
mkdir -p "$T/caller-home" "$T/tmp"
# run <stub mode> <PATH> <TMPDIR> <suite> [NAME=VALUE...]: the suite under
# env -i, its HOME a stand-in for the caller's, with the backend variables
# pointed at dummy paths and a dummy bucket. Sets RC and OUT.
run() {
    local mode=$1 path=$2 tmp=$3 suite=$4
    shift 4
    : > "$LOG"
    OUT=$(cd "$T" && env -i PATH="$path" HOME="$T/caller-home" TMPDIR="$tmp" \
        STUB_MODE="$mode" STUB_LOG="$LOG" STUB_OUTSIDE="$T/dummy-store" \
        KOTO_SESSIONS_BASE="$T/dummy-store" KOTO_TICK_SESSION=dummy-session \
        KOTO_HOME="$T/dummy-root" KOTO_SESSION_BACKEND=cloud \
        KOTO_SESSION_CLOUD_BUCKET=dummy-bucket KOTO_SESSION_CLOUD_ENDPOINT=http://127.0.0.1:9 \
        AWS_ACCESS_KEY_ID=dummy-key "$@" "$BASH_BIN" "$suite" 2>&1)
    RC=$?
}
# stopped <label> [<text>]: the suite exited non-zero, ran no case, and said
# why: the text given, or the guard's own FAIL line.
stopped() {
    case "$RC:$OUT" in
        0:*) bad "$1" "exit 0: $OUT" ;;
        *"CASES RAN"*) bad "$1" "a case ran: $OUT" ;;
        *"${2:-FAIL: koto-test-guard: }"*) ok "$1" ;;
        *) bad "$1" "stopped for another reason: $OUT" ;;
    esac
}

run honest "$BIN:$SYS" "$T/tmp" "$G/scripts/s_test.sh"
case "$RC:$OUT" in 0:*"CASES RAN"*) ok "dummy backend settings: the suite runs" ;; *) bad "dummy backend settings: the suite runs" "rc=$RC out=$OUT" ;; esac
case "$OUT" in *"still set:"*) bad "dummy backend settings: none is left in the suite" "$OUT" ;; *) ok "dummy backend settings: none is left in the suite" ;; esac
case "$(cat "$LOG")" in
    *"env: "*) bad "dummy backend settings: koto's first call sees none of them" "$(cat "$LOG")" ;;
    "argv: session dir koto-test-guard-probe") ok "dummy backend settings: koto's first call sees none of them" ;;
    *) bad "dummy backend settings: koto's first call is the probe" "$(cat "$LOG")" ;;
esac
DIR=$(sed -n 's/^DIR=//p' <<<"$OUT")
case "$DIR" in "$T/tmp/suite-scratch."*) ok "the guard's directory is under TMPDIR" ;; *) bad "the guard's directory is under TMPDIR" "$DIR" ;; esac
case "$OUT" in *"HOME=$DIR/home"*) ok "HOME is under the guard's directory" ;; *) bad "HOME is under the guard's directory" "$OUT" ;; esac
[ -n "$DIR" ] && [ ! -e "$DIR" ] && ok "the guard's directory is gone after a suite that sets no trap" \
    || bad "the guard's directory is gone after a suite that sets no trap" "$DIR"

run honest "$BIN:$SYS" "$T/tmp" "$G/scripts/unguarded_test.sh"
case "$(cat "$LOG")" in
    *"env: KOTO_SESSIONS_BASE"*"env: KOTO_SESSION_BACKEND"*) ok "without the guard, koto is handed the caller's backend settings" ;;
    *) bad "without the guard, koto is handed the caller's backend settings" "$(cat "$LOG")" ;;
esac

for v in KOTO_SESSIONS_BASE KOTO_SESSION_BACKEND; do
    put "$G/scripts/ro_test.sh" "set -uo pipefail<NL>readonly $v<NL>. \"\$(dirname \"\$0\")/lib/koto-test-guard.sh\" || exit 1<NL>$REPORT"
    run honest "$BIN:$SYS" "$T/tmp" "$G/scripts/ro_test.sh"
    stopped "$v that can't be unset: the suite stops"
    [ ! -s "$LOG" ] && ok "$v that can't be unset: koto is never called" || bad "$v that can't be unset: koto is never called" "$(cat "$LOG")"
    case "$OUT" in *"$v could not be unset"*) ok "$v that can't be unset: named" ;; *) bad "$v that can't be unset: named" "$OUT" ;; esac
done

run outside "$BIN:$SYS" "$T/tmp" "$G/scripts/s_test.sh"
stopped "a session directory outside the guard's: the suite stops"
case "$OUT" in *"not under"*"$T/dummy-store/koto-test-guard-probe"*) ok "a session directory outside the guard's: named" ;; *) bad "a session directory outside the guard's: named" "$OUT" ;; esac

run fail "$BIN:$SYS" "$T/tmp" "$G/scripts/s_test.sh"
stopped "koto session dir failing: the suite stops"

run honest "$BIN:$SYS" "$T/tmp" "$G/scripts/gone_test.sh"
stopped "a missing guard file: the suite stops" "missing-guard.sh"
[ ! -s "$LOG" ] && ok "a missing guard file: koto is never called" || bad "a missing guard file: koto is never called" "$(cat "$LOG")"

run honest "$BIN:$SYS" "$T/no/such/dir" "$G/scripts/s_test.sh"
stopped "a TMPDIR the guard can't make its directory in: the suite stops"
[ ! -s "$LOG" ] && ok "a TMPDIR the guard can't make its directory in: koto is never called" \
    || bad "a TMPDIR the guard can't make its directory in: koto is never called" "$(cat "$LOG")"

run honest "$SYS" "$T/tmp" "$G/scripts/s_test.sh"
case "$RC:$OUT" in 0:*"CASES RAN"*) ok "no koto on PATH: the suite runs" ;; *) bad "no koto on PATH: the suite runs" "rc=$RC out=$OUT" ;; esac
case "$OUT" in *"still set:"*) bad "no koto on PATH: the settings are cleared all the same" "$OUT" ;; *) ok "no koto on PATH: the settings are cleared all the same" ;; esac

# The guard makes its directory with mkdir, so a suite run under a failing
# mktemp (scripts/mktemp-failure_test.sh) still reaches its own mktemp check.
run honest "$BIN:$SYS" "$T/tmp" "$G/scripts/s_test.sh"
case "$RC:$OUT" in 0:*"CASES RAN"*) ok "a failing mktemp doesn't stop the guard" ;; *) bad "a failing mktemp doesn't stop the guard" "rc=$RC out=$OUT" ;; esac

# A suite with its own cleanup, run in an empty TMPDIR: it makes a directory
# there and hands its removal, and a line written outside TMPDIR, to
# ktg_on_exit, then exits 3.
GUARDED=". \"\$(dirname \"\$0\")/lib/koto-test-guard.sh\" || exit 1"
MARK="$T/mark"
CT="$T/tmp-chain"
mkdir "$CT"
put "$G/scripts/chain_test.sh" "set -uo pipefail<NL>$GUARDED<NL>mkdir \"\$TMPDIR/own\"<NL>ktg_on_exit 'rm -rf \"\$TMPDIR/own\"; echo own-ran >\"\$MARK\"'<NL>echo CASES RAN<NL>exit 3"
: > "$MARK"
run honest "$BIN:$SYS" "$CT" "$G/scripts/chain_test.sh" MARK="$MARK"
case "$RC:$OUT" in 3:*"CASES RAN"*) ok "ktg_on_exit: the suite runs and keeps its exit status" ;; *) bad "ktg_on_exit: the suite runs and keeps its exit status" "rc=$RC out=$OUT" ;; esac
[ "$(cat "$MARK")" = own-ran ] && ok "ktg_on_exit: the suite's own cleanup ran" || bad "ktg_on_exit: the suite's own cleanup ran" "$(cat "$MARK")"
LEFT=$(ls -A "$CT")
[ -z "$LEFT" ] && ok "ktg_on_exit: TMPDIR is empty after the suite" || bad "ktg_on_exit: TMPDIR is empty after the suite" "$LEFT"

put "$G/scripts/chain2_test.sh" "set -uo pipefail<NL>$GUARDED<NL>ktg_on_exit 'echo first >>\"\$MARK\"'<NL>ktg_on_exit 'echo second >>\"\$MARK\"'<NL>echo CASES RAN"
: > "$MARK"
run honest "$BIN:$SYS" "$CT" "$G/scripts/chain2_test.sh" MARK="$MARK"
[ "$(cat "$MARK")" = second ] && ok "ktg_on_exit twice: only the second command runs" || bad "ktg_on_exit twice: only the second command runs" "$(cat "$MARK")"
LEFT=$(ls -A "$CT")
[ -z "$LEFT" ] && ok "ktg_on_exit twice: TMPDIR is empty after the suite" || bad "ktg_on_exit twice: TMPDIR is empty after the suite" "$LEFT"

put "$G/scripts/chain3_test.sh" "set -uo pipefail<NL>$GUARDED<NL>ktg_on_exit 'echo a' 'echo b'<NL>echo CASES RAN"
run honest "$BIN:$SYS" "$CT" "$G/scripts/chain3_test.sh"
stopped "ktg_on_exit with two arguments: the suite stops" "ktg_on_exit takes one command, got 2"

# Under set -e a command that fails ends the trap with its status, with
# ktg_on_exit as with the suite's own trap: the helper changes no exit status.
put "$G/scripts/fail-own_test.sh" "set -euo pipefail<NL>$GUARDED<NL>trap false EXIT<NL>echo CASES RAN"
put "$G/scripts/fail-chain_test.sh" "set -euo pipefail<NL>$GUARDED<NL>ktg_on_exit false<NL>echo CASES RAN"
run honest "$BIN:$SYS" "$CT" "$G/scripts/fail-own_test.sh"
OWN_RC=$RC
run honest "$BIN:$SYS" "$CT" "$G/scripts/fail-chain_test.sh"
[ "$RC" = "$OWN_RC" ] && [ "$RC" != 0 ] && ok "ktg_on_exit under set -e: a failing command exits as the suite's own trap did" \
    || bad "ktg_on_exit under set -e: a failing command exits as the suite's own trap did" "own=$OWN_RC chain=$RC"
rm -rf "$CT"/suite-scratch.*

put "$G/scripts/own-trap_test.sh" "set -uo pipefail<NL>$GUARDED<NL>trap 'echo own-ran >\"\$MARK\"' EXIT<NL>echo CASES RAN"
: > "$MARK"
run honest "$BIN:$SYS" "$CT" "$G/scripts/own-trap_test.sh" MARK="$MARK"
LEFT=$(ls -A "$CT")
case "$(cat "$MARK"):$LEFT" in
    own-ran:suite-scratch.*) ok "its own trap ... EXIT: the guard's directory is left in TMPDIR" ;;
    *) bad "its own trap ... EXIT: the guard's directory is left in TMPDIR" "mark=$(cat "$MARK") left=$LEFT" ;;
esac

echo "== deliver-open_test.sh =="
run outside "$BIN:$SYS" "$T/tmp" "$REPO/skills/deliver/scripts/deliver-open_test.sh"
stopped "koto resolving its store elsewhere: deliver-open_test.sh stops"
case "$OUT" in *"ok "*) bad "deliver-open_test.sh: no case ran" "$OUT" ;; *) ok "deliver-open_test.sh: no case ran" ;; esac
[ "$(cat "$LOG")" = "argv: session dir koto-test-guard-probe" ] && ok "deliver-open_test.sh: koto was asked only for the session directory" \
    || bad "deliver-open_test.sh: koto was asked only for the session directory" "$(cat "$LOG")"

echo
echo "check-koto-test-guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
