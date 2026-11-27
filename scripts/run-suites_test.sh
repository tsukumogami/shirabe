#!/usr/bin/env bash
# run-suites_test.sh -- scripts/run-suites.sh fails a run on a suite that
# failed or printed "command not found", names that suite, and runs every
# suite before it fails.
#
# The suites here are fixtures written to a scratch directory; none of the
# repository's own suites run.
#
# The runner slices its list when SUITE_SLICE is set, and a developer or a CI
# job may have it set in the environment that launches this test. Every
# fixture run below starts from neither variable; a case that wants a slice
# names it.
#
# Usage: bash scripts/run-suites_test.sh
set -uo pipefail
unset SUITE_SLICE SUITE_SLICE_COSTS

HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER="$HERE/run-suites.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/run-suites-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

# Suites that pass and leave a mark naming themselves, so a case can tell
# which suites ran.
mkdir -p "$T/suites" "$T/marks"
for n in first last s1 s2 s3 s4; do
    printf '#!/usr/bin/env bash\necho "%s ran"\ntouch "%s/%s"\n' "$n" "$T/marks" "$n" > "$T/suites/$n.sh"
done
# Exits 0 having called a command that doesn't exist.
printf '#!/usr/bin/env bash\nrun-suites-no-such-command --check\necho "all cases passed"\n' > "$T/suites/missing-command.sh"
printf '#!/usr/bin/env bash\necho "a case failed"\nexit 3\n' > "$T/suites/fails.sh"

# run <suite>...: the runner on the named fixture suites, its output in
# $T/out and its exit status in $RC. The runner gets SUITE_SLICE only when
# SLICE names one, so a variable left in the caller's environment never
# reaches it.
SLICE=
run() {
    local s args=()
    rm -f "$T/marks"/*
    for s in "$@"; do args+=("$T/suites/$s.sh"); done
    if [ -n "$SLICE" ]; then
        env -u SUITE_SLICE_COSTS SUITE_SLICE="$SLICE" bash "$RUNNER" ${args[@]+"${args[@]}"} >"$T/out" 2>&1
    else
        env -u SUITE_SLICE -u SUITE_SLICE_COSTS bash "$RUNNER" ${args[@]+"${args[@]}"} >"$T/out" 2>&1
    fi
    RC=$?
}

# The marks left by the suites that ran, on one line in name order.
marks() {
    (cd "$T/marks" && ls | LC_ALL=C sort | tr '\n' ' ')
}

echo "== passing suites =="
run first last
if [ $RC -eq 0 ] && [ -e "$T/marks/first" ] && [ -e "$T/marks/last" ]; then
    ok "every suite passing passes the run"
else
    bad "every suite passing passes the run" "exit $RC; $(cat "$T/out")"
fi

echo "== a suite that printed command not found =="
run first missing-command last
if [ $RC -ne 1 ]; then
    bad "command not found fails the run" "expected exit 1, got $RC"
elif ! grep -q "^run-suites: $T/suites/missing-command.sh ran a command that isn't on PATH" "$T/out"; then
    bad "command not found fails the run" "no line naming the suite in: $(cat "$T/out")"
else
    ok "command not found fails the run, naming the suite, though it exited 0"
fi
if grep -q '^    .*run-suites-no-such-command: command not found' "$T/out" &&
    grep -q "^run-suites: failed: $T/suites/missing-command.sh$" "$T/out"; then
    ok "the run quotes the missing command and lists the suite as failed"
else
    bad "the run quotes the missing command and lists the suite as failed" "$(cat "$T/out")"
fi

echo "== failing suites don't hide the ones after them =="
run fails missing-command last
if [ $RC -ne 1 ]; then
    bad "every suite runs before the run fails" "expected exit 1, got $RC"
elif [ ! -e "$T/marks/last" ]; then
    bad "every suite runs before the run fails" "the last suite never ran"
elif ! grep -q "^run-suites: $T/suites/fails.sh exited 3$" "$T/out"; then
    bad "every suite runs before the run fails" "no line naming the failing suite in: $(cat "$T/out")"
elif ! grep -q "^run-suites: failed: $T/suites/fails.sh $T/suites/missing-command.sh$" "$T/out"; then
    bad "every suite runs before the run fails" "the failed list doesn't name both suites: $(cat "$T/out")"
else
    ok "every suite runs before the run fails, and the run names each failure"
fi

echo "== a slice =="
# Four suites of equal (unknown) cost go one to a slice in name order, so
# slice 2 of 4 is s2.
SLICE=2/4 run s1 s2 s3 s4
if [ $RC -eq 0 ] && [ "$(marks)" = "s2 " ] &&
    grep -q '^run-suites: 1 of 4 suites (slice 2/4)$' "$T/out"; then
    ok "SUITE_SLICE=2/4 runs only that slice's suite and the count line names the slice"
else
    bad "SUITE_SLICE=2/4 runs only that slice's suite and the count line names the slice" "exit $RC; ran: $(marks); $(cat "$T/out")"
fi
all=""
for i in 1 2 3 4; do
    SLICE=$i/4 run s1 s2 s3 s4
    all="$all$(marks)"
done
if [ "$all" = "s1 s2 s3 s4 " ]; then
    ok "the four slices together run every suite once"
else
    bad "the four slices together run every suite once" "ran: $all"
fi
run s1 s2 s3 s4
if [ $RC -eq 0 ] && [ "$(marks)" = "s1 s2 s3 s4 " ] && grep -q '^run-suites: 4 suites$' "$T/out"; then
    ok "with no slice every suite runs and the count line names none"
else
    bad "with no slice every suite runs and the count line names none" "exit $RC; ran: $(marks); $(cat "$T/out")"
fi
printf '#!/usr/bin/env bash\necho "child sees slice=${SUITE_SLICE:-none}"\n' > "$T/suites/sees.sh"
SLICE=1/1 run sees
if grep -q '^child sees slice=none$' "$T/out"; then
    ok "a suite the runner runs doesn't see the runner's slice"
else
    bad "a suite the runner runs doesn't see the runner's slice" "$(cat "$T/out")"
fi
SLICE=5/4 run s1
if [ $RC -eq 2 ] && grep -q 'SUITE_SLICE=5/4' "$T/out"; then
    ok "a malformed SUITE_SLICE exits 2, naming the value"
else
    bad "a malformed SUITE_SLICE exits 2, naming the value" "exit $RC; $(cat "$T/out")"
fi

echo "== a slice in the environment that launched this test =="
# The test unset the variables at its top, so a slice exported around a
# fixture run doesn't reach it.
( export SUITE_SLICE=2/4 SUITE_SLICE_COSTS=/nonexistent; run s1 s2 s3 s4
  [ $RC -eq 0 ] && [ "$(marks)" = "s1 s2 s3 s4 " ] ) &&
    ok "an ambient SUITE_SLICE doesn't slice a fixture run" ||
    bad "an ambient SUITE_SLICE doesn't slice a fixture run" "$(cat "$T/out")"

echo "== usage =="
run
if [ $RC -eq 2 ]; then
    ok "no suites is a usage error"
else
    bad "no suites is a usage error" "expected exit 2, got $RC"
fi
run no-such-suite
if [ $RC -eq 1 ] && grep -q "^run-suites: failed: $T/suites/no-such-suite.sh$" "$T/out"; then
    ok "a suite that doesn't exist fails the run"
else
    bad "a suite that doesn't exist fails the run" "exit $RC; $(cat "$T/out")"
fi

echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
