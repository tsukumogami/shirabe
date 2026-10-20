#!/usr/bin/env bash
# mktemp-failure_test.sh -- the test suites leave the caller's directory and
# repository alone when mktemp fails.
#
# Covers the two classes of shirabe#924 and #925, each run with a mktemp that
# always fails ahead of the real one on PATH:
#   - every suite that makes its directory with mktemp -d and then resolves it
#     with `X=$(cd "$X" && pwd -P)`: run from a throwaway directory, which must
#     survive with its file in it (an unchecked failure made X that directory,
#     and the suite's cleanup removed it);
#   - the suites that build a fixture repository in a mktemp directory: run
#     from a throwaway repository, whose HEAD, branch, commit count, user.email
#     and working tree must be unchanged (an unchecked failure ran their git
#     init, config, add, commit, checkout and rm there).
# The suites run from a copy of the tree in this suite's own directory, never
# from the checkout, so a suite that falls back to "the repository" when its
# directory is empty acts on the copy.
#
# MKTEMP_FAILURE_SRC names another tree to copy (default: this repository),
# which is how the old code is shown to fail.
#
# Usage: bash scripts/mktemp-failure_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${MKTEMP_FAILURE_SRC:-$(cd "$HERE/.." && pwd)}
REAL_MKTEMP=$(command -v mktemp) || { echo "FAIL: no mktemp on PATH" >&2; exit 1; }
T=$("$REAL_MKTEMP" -d "${TMPDIR:-/tmp}/mktemp-failure-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */mktemp-failure-test.*) chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" ;; esac' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

mkdir -p "$T/stub"
printf '#!/bin/sh\necho "mktemp: failing on purpose" >&2\nexit 1\n' > "$T/stub/mktemp"
chmod +x "$T/stub/mktemp"

# copy <dir>: the source tree's files (its tracked ones, when it is a work
# tree) into <dir>.
copy() {
    mkdir -p "$1"
    if git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        (cd "$SRC" && git ls-files -z | tar --null -T - -cf -) | tar -C "$1" -xf -
    else
        tar -C "$SRC" --exclude=.git -cf - . | tar -C "$1" -xf -
    fi
}

# run_from <dir> <suite>: the suite, from <dir>, with the failing mktemp.
run_from() {
    (cd "$1" && PATH="$T/stub:$PATH" bash "$2" >"$T/last.log" 2>&1)
}

echo "== a suite that resolves its directory with cd and pwd (#924) =="
copy "$T/tree924"
SHAPE='^[A-Za-z_]+=\$\(cd (-P )?"\$[A-Za-z_]+" && pwd -P\)'
# The suites with the shape, and every suite that sources a shared test
# library making a directory at its top level or resolving it the same way
# (coordinate's testdata/test-lib.sh and coordinate-engine-lib.sh, which hand
# $T to the suite).
SUITES=$(
    cd "$T/tree924" || exit 1
    grep -l -E "$SHAPE" $(find . -name '*_test.sh')
    for lib in $(grep -l -E "$SHAPE|^[A-Za-z_]+=\\\$\\(mktemp " $(find . \( -path '*/testdata/*.sh' -o -name '*-lib.sh' -o -name '*-helpers.sh' \) ! -name '*_test.sh')); do
        grep -l -E "^[[:space:]]*(\\.|source)[[:space:]].*/${lib##*/}\"?\$" $(find . -name '*_test.sh')
    done
)
SUITES=$(printf '%s\n' "$SUITES" | LC_ALL=C sort -u)
n=0
for s in $SUITES; do
    n=$((n + 1))
    v="$T/v924/$n"
    mkdir -p "$v"
    : > "$v/keep-me"
    run_from "$v" "$T/tree924/$s"
    if [ -f "$v/keep-me" ]; then ok "${s#./} leaves its caller's directory"; else bad "${s#./} leaves its caller's directory" "$(tail -3 "$T/last.log")"; fi
done
[ "$n" -ge 30 ] && ok "every such suite was run ($n)" || bad "every such suite was run" "only $n"

echo "== a suite that builds a fixture repository (#925) =="
copy "$T/tree925"
for s in \
    skills/scope/scripts/check-citations_test.sh \
    skills/work-on/scripts/verify-cascade-commit_test.sh \
    skills/work-on/scripts/pre-pr-evidence_test.sh \
    scripts/check-skill_test.sh \
    skills/scope/scripts/record-executed-report_test.sh \
    skills/scope/scripts/record-scope-exit_test.sh; do
    v="$T/v925/${s##*/}"
    mkdir -p "$v"
    git -C "$v" init -q -b main . \
        && git -C "$v" config user.email victim@example.invalid \
        && git -C "$v" config user.name victim \
        && printf 'mine\n' > "$v/keep-me" \
        && git -C "$v" add keep-me \
        && git -C "$v" commit -qm mine \
        || { bad "$s: a repository to run from" "git failed"; continue; }
    before="$(git -C "$v" rev-parse HEAD) $(git -C "$v" rev-list --count HEAD) $(git -C "$v" symbolic-ref --short HEAD)"
    run_from "$v" "$T/tree925/$s"
    after="$(git -C "$v" rev-parse HEAD) $(git -C "$v" rev-list --count HEAD) $(git -C "$v" symbolic-ref --short HEAD)"
    email=$(git -C "$v" config --local user.email)
    status=$(git -C "$v" status --porcelain --untracked-files=all)
    if [ "$before" = "$after" ] && [ "$email" = victim@example.invalid ] && [ -z "$status" ]; then
        ok "$s leaves its caller's repository"
    else
        bad "$s leaves its caller's repository" "head/count/branch $before -> $after; user.email $email; status: $(head -3 <<<"$status" | tr '\n' ' ')"
    fi
done

echo
echo "mktemp-failure: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
