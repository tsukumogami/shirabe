# koto-test-guard.sh -- sourced by every test suite that runs koto, so no
# suite can write to the caller's koto store or cloud bucket.
#
# A scratch HOME alone doesn't keep koto off the caller's sessions:
# KOTO_SESSIONS_BASE names a store outright, a run under a koto session
# inherits it and KOTO_TICK_SESSION, KOTO_HOME moves koto's whole root, the
# KOTO_SESSION_* settings choose a cloud backend and its bucket, and the AWS_*
# credentials are the backend's fallback. A review seat that ran a suite from
# a session with those set pushed the suite's sessions to the real bucket
# (shirabe#1288).
#
# Usage, as the line after the suite's `set` line, with the path to this file
# written relative to the suite's own directory:
#
#     . "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
#
# The `|| exit 1` stops the suite when this file is missing. Once sourced:
#
#   - KOTO_SESSIONS_BASE, KOTO_TICK_SESSION, KOTO_HOME, KOTO_WORKFLOWS_DIR,
#     KOTO_WORKFLOWS_HOST_SESSION, KOTO_ANCHOR, KOTO_DISPATCHER_ANCHOR, every
#     KOTO_SESSION_* variable and every AWS_* variable are unset;
#   - HOME is a new directory under KOTO_TEST_GUARD_DIR, a directory made
#     here with mkdir under TMPDIR (not with mktemp, so a suite run under a
#     failing mktemp still reaches its own mktemp check);
#   - when koto is on PATH, `koto session dir`, run from the suite's current
#     directory so a .koto/config.toml there counts, printed a path under
#     KOTO_TEST_GUARD_DIR. With no koto on PATH there is nothing to ask, and
#     the cleared environment and HOME are what a koto found later sees.
#
# Anything else exits the suite 1 with a FAIL line, before the suite's own
# code runs: a variable that can't be unset (readonly), a directory that
# can't be made, a `koto session dir` that fails or points anywhere else.
# A suite may set HOME or KOTO_SESSIONS_BASE to its own directory afterwards.
#
# KOTO_TEST_GUARD_DIR is removed on exit by the trap set here, unless the
# suite sets its own EXIT trap, which replaces it; the directory then stays
# under TMPDIR.
#
# scripts/check-koto-test-guard.sh fails when a suite that names koto doesn't
# source this file before it does; scripts/check-koto-test-guard_test.sh
# covers both.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

_ktg_fail() {
    echo "FAIL: koto-test-guard: $*; no case ran" >&2
    exit 1
}

for _ktg_v in KOTO_SESSIONS_BASE KOTO_TICK_SESSION KOTO_HOME KOTO_WORKFLOWS_DIR \
    KOTO_WORKFLOWS_HOST_SESSION KOTO_ANCHOR KOTO_DISPATCHER_ANCHOR \
    $(env | sed -n 's/^\(KOTO_SESSION_[A-Za-z0-9_]*\)=.*/\1/p; s/^\(AWS_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$_ktg_v" || _ktg_fail "$_ktg_v could not be unset"
done
_ktg_left=$(env | sed -n -E 's/^(KOTO_SESSIONS_BASE|KOTO_TICK_SESSION|KOTO_HOME|KOTO_SESSION_[A-Za-z0-9_]*|AWS_[A-Za-z0-9_]*)=.*/\1/p')
[ -z "$_ktg_left" ] || _ktg_fail "still set after unset: $(printf '%s ' $_ktg_left)"

_ktg_tmp=${TMPDIR:-/tmp}
_ktg_tmp=${_ktg_tmp%/}
_ktg_dir=""
for _ktg_try in 1 2 3 4 5; do
    _ktg_dir="$_ktg_tmp/koto-test-guard.$$.$RANDOM"
    mkdir -m 700 "$_ktg_dir" && break
    _ktg_dir=""
done
[ -n "$_ktg_dir" ] || _ktg_fail "could not make a directory under $_ktg_tmp"
KOTO_TEST_GUARD_DIR=$(cd -P "$_ktg_dir" && pwd -P)
case "$KOTO_TEST_GUARD_DIR" in
    */koto-test-guard.*) ;;
    *) _ktg_fail "could not resolve $_ktg_dir" ;;
esac
trap 'case "${KOTO_TEST_GUARD_DIR:-}" in */koto-test-guard.*) rm -rf "$KOTO_TEST_GUARD_DIR" ;; esac' EXIT
export HOME="$KOTO_TEST_GUARD_DIR/home"
mkdir "$HOME" || _ktg_fail "could not make $HOME"

if command -v koto >/dev/null; then
    _ktg_out=$(koto session dir koto-test-guard-probe 2>&1) \
        || _ktg_fail "koto session dir failed: [$_ktg_out]"
    case "$_ktg_out" in
        "$KOTO_TEST_GUARD_DIR"/*) ;;
        *) _ktg_fail "koto's session directory is not under $KOTO_TEST_GUARD_DIR: [$_ktg_out]" ;;
    esac
fi

unset _ktg_v _ktg_left _ktg_tmp _ktg_dir _ktg_try _ktg_out
