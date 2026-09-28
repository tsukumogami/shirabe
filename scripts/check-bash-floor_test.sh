#!/usr/bin/env bash
set -euo pipefail

# Tests for check-bash-floor.sh.
#
# The load-bearing case is the canary: scripts/bash-floor-canary.sh must fail
# when the runner puts it on the floor and pass under the bash running this
# harness. If that asymmetry ever stops holding, the runner has stopped
# reaching bash 3.2 and every green floor check it reports is worthless.
#
# Usage:
#   bash scripts/check-bash-floor_test.sh
#
# Requires a reachable floor: a docker daemon on Linux, or a macOS /bin/bash.
# Set FLOOR_BACKEND to pin one (docker or system); the default lets the runner
# choose. The container-shape cases run against a stub docker and need neither.
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/check-bash-floor.sh"
CANARY="$SCRIPT_DIR/bash-floor-canary.sh"
PASS_COUNT=0
FAIL_COUNT=0

BACKEND_ARGS=""
if [ -n "${FLOOR_BACKEND:-}" ]; then
    BACKEND_ARGS="--backend $FLOOR_BACKEND"
fi

fail() {
    echo "FAIL: $1 - $2" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "PASS: $1" >&2
    PASS_COUNT=$((PASS_COUNT + 1))
}

# The bash running this harness is whatever the developer or the CI runner
# ships, which everywhere CI runs it is 4 or newer. The canary passing here and
# failing on the floor is the whole assertion.
test_canary_passes_under_this_bash() {
    local name="canary passes under this bash (${BASH_VERSION})"
    local out rc=0

    case "$BASH_VERSION" in
        3.*)
            echo "SKIP: $name - this harness is itself on the floor" >&2
            return
            ;;
    esac

    out=$(bash "$CANARY" 2>&1) || rc=$?
    if [ $rc -ne 0 ]; then
        fail "$name" "expected exit 0, got $rc: $out"
        return
    fi
    case "$out" in
        *"split into 3 fields"*) pass "$name" ;;
        *) fail "$name" "unexpected output: $out" ;;
    esac
}

# The runner's reason to exist: put that same canary on the floor and it fails.
test_canary_fails_on_the_floor() {
    local name="canary fails on the bash 3.2 floor"
    local out rc=0

    out=$($RUNNER $BACKEND_ARGS canary 2>&1) || rc=$?
    if [ $rc -eq 0 ]; then
        fail "$name" "the runner reported a pass; it is not reaching bash 3.2: $out"
        return
    fi
    if [ $rc -ne 1 ]; then
        fail "$name" "expected exit 1 (suite failed), got $rc: $out"
        return
    fi
    case "$out" in
        *"U+0001 record did not split"*) ;;
        *) fail "$name" "the failure does not name the U+0001 split: $out"; return ;;
    esac
    # The diagnostic has to show where the fields ended up, with the invisible
    # separators made visible, or the next reader has no way to recognise the
    # defect when it turns up in a real script.
    case "$out" in
        *"number=[1<U+0001>plan-to-tasks<U+0001>Make the floor checkable]"*) ;;
        *) fail "$name" "the failure does not show the concatenated field: $out"; return ;;
    esac
    case "$out" in
        *"check-bash-floor: FAIL"*) pass "$name" ;;
        *) fail "$name" "the runner did not report the suite as failed: $out" ;;
    esac
}

# The floor a run reached has to be visible in its own output, otherwise a
# green result cannot be told apart from a run that never left bash 5.
test_floor_run_names_the_version() {
    local name="a floor run reports bash 3.2 in the canary's own output"
    local out rc=0

    out=$($RUNNER $BACKEND_ARGS canary 2>&1) || rc=$?
    case "$out" in
        *"(bash 3.2"*) pass "$name" ;;
        *) fail "$name" "no bash 3.2 banner in the output: $out" ;;
    esac
}

# --list is the discovery surface: it has to name every CI suite, so a
# developer can find the one covering the script they just changed.
test_list_names_every_suite() {
    local name="--list names every CI suite and its workflow"
    local out rc=0
    local suite

    out=$($RUNNER --list 2>&1) || rc=$?
    if [ $rc -ne 0 ]; then
        fail "$name" "expected exit 0, got $rc"
        return
    fi
    for suite in plan execute templates template-consistency deliver scope; do
        case "$out" in
            *"$suite"*) ;;
            *) fail "$name" "suite $suite missing from --list"; return ;;
        esac
    done
    case "$out" in
        *"check-plan-scripts.yml"*) pass "$name" ;;
        *) fail "$name" "--list does not name the workflow a suite comes from" ;;
    esac
}

# Every script the registry claims to run has to exist, or a suite silently
# stops covering something when a script is renamed.
test_registry_scripts_exist() {
    local name="every script in the registry exists"
    local out script missing=""

    out=$($RUNNER --list 2>&1)
    for script in $(echo "$out" | grep -E '^ +(skills|scripts)/.*\.sh$'); do
        [ -f "$SCRIPT_DIR/../$script" ] || missing="$missing $script"
    done
    if [ -n "$missing" ]; then
        fail "$name" "missing:$missing"
    else
        pass "$name"
    fi
}

# --suites and --scripts are the machine-readable registry that
# check-macos-floor-legs.sh reads; they have to agree with --list and print
# nothing but names.
test_machine_readable_registry() {
    local name="--suites and --scripts print the registry one name per line"
    local suites scripts rc=0

    suites=$($RUNNER --suites 2>&1) || rc=$?
    if [ $rc -ne 0 ] || ! printf '%s\n' "$suites" | grep -qx deliver \
        || printf '%s\n' "$suites" | grep -q ' '; then
        fail "$name" "--suites (rc=$rc): $suites"
        return
    fi
    scripts=$($RUNNER --scripts plan 2>&1) || rc=$?
    if [ $rc -ne 0 ] || ! printf '%s\n' "$scripts" | grep -qx 'skills/plan/scripts/plan-to-tasks_test.sh'; then
        fail "$name" "--scripts plan (rc=$rc): $scripts"
        return
    fi
    rc=0
    $RUNNER --scripts no-such-suite >/dev/null 2>&1 || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "--scripts on an unknown suite: expected exit 2, got $rc"
        return
    fi
    pass "$name"
}

test_unknown_suite_is_refused() {
    local name="an unknown suite is refused with exit 2"
    local out rc=0

    out=$($RUNNER $BACKEND_ARGS no-such-suite 2>&1) || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"unknown suite"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

test_no_suite_is_refused() {
    local name="naming no suite is refused with exit 2"
    local out rc=0

    out=$($RUNNER $BACKEND_ARGS 2>&1) || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"name at least one suite"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

# "the floor could not be reached" and "your code fails on the floor" are
# different answers and must not share an exit code. A missing shirabe binary
# is the first kind: the suite never ran.
test_unreachable_floor_is_not_reported_as_a_suite_failure() {
    local name="a shirabe binary that cannot be produced exits 2, not 1"
    local out rc=0

    out=$(SHIRABE_BIN=/nonexistent/shirabe $RUNNER --backend docker plan 2>&1) || rc=$?
    if [ $rc -eq 1 ]; then
        fail "$name" "reported the suite as failing on the floor; it never ran: $out"
        return
    fi
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"not executable"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

test_unknown_backend_is_refused() {
    local name="an unknown backend is refused with exit 2"
    local out rc=0

    out=$($RUNNER --backend nonsense canary 2>&1) || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"unknown backend"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

# The system backend must refuse a bash that is not 3.2 rather than run the
# suite and report a green that means nothing.
test_system_backend_refuses_a_newer_bin_bash() {
    local name="the system backend refuses a /bin/bash that is not 3.2"
    local out rc=0

    if /bin/bash -c 'case "$BASH_VERSION" in 3.2*) exit 0;; *) exit 1;; esac'; then
        echo "SKIP: $name - /bin/bash here is 3.2" >&2
        return
    fi

    out=$($RUNNER --backend system canary 2>&1) || rc=$?
    if [ $rc -ne 2 ]; then
        fail "$name" "expected exit 2, got $rc: $out"
        return
    fi
    case "$out" in
        *"/bin/bash is not 3.2"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $out" ;;
    esac
}

# -- the docker backend's container, against a stub docker ---------------------
#
# These cases never reach a daemon. A stub docker on PATH answers `docker info`
# as a rootless or rootful daemon (or fails, as an unreachable one does),
# swallows `docker build`, and records each `docker run` argument on its own
# line. The runner is copied into a scratch repository, because the mounts it
# asks for depend on what kind of checkout it sits in.

STUB_ROOT=""
cleanup_stub() {
    [ -n "$STUB_ROOT" ] && rm -rf "$STUB_ROOT"
    return 0
}
trap cleanup_stub EXIT

STUB_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/check-bash-floor-test.XXXXXX")
STUB_ROOT=$(cd "$STUB_ROOT" && pwd)
STUB_BIN="$STUB_ROOT/bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/docker" <<'STUB'
#!/usr/bin/env bash
# Stand-in docker for check-bash-floor_test.sh.
case "${1:-}" in
    info)
        case "${STUB_DAEMON:-rootless}" in
            rootless) echo '["name=seccomp,profile=builtin","name=rootless","name=cgroupns"]' ;;
            rootful)  echo '["name=apparmor","name=seccomp,profile=builtin","name=cgroupns"]' ;;
            *)        echo "Cannot connect to the Docker daemon" >&2; exit 1 ;;
        esac
        ;;
    build)
        cat >"$STUB_LOG.build"
        ;;
    run)
        shift
        for a in "$@"; do printf '%s\n' "$a"; done >>"$STUB_LOG.run"
        ;;
    *)
        echo "stub docker: unexpected $*" >&2
        exit 127
        ;;
esac
STUB
chmod +x "$STUB_BIN/docker"

# A repository holding a copy of the runner, and a linked worktree of it.
FIX_MAIN="$STUB_ROOT/main"
FIX_WT="$STUB_ROOT/wt"
mkdir -p "$FIX_MAIN/scripts"
cp "$RUNNER" "$FIX_MAIN/scripts/check-bash-floor.sh"
git -C "$FIX_MAIN" init -q
git -C "$FIX_MAIN" add scripts
git -C "$FIX_MAIN" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
    commit -q -m fixture
git -C "$FIX_MAIN" worktree add -q "$FIX_WT" 2>/dev/null
# The main checkout's git directory, as the worktree's .git file names it.
FIX_COMMON=$(sed -n 's/^gitdir: //p' "$FIX_WT/.git")
FIX_COMMON=$(cd "$FIX_COMMON/../.." && pwd)

STUB_OUT=""
STUB_RC=0
# run_stubbed <checkout> <daemon> [runner args...]: runs the runner copy in
# <checkout> on the canary suite against the stub, leaving its output in
# STUB_OUT, its exit status in STUB_RC and what docker was asked in
# $STUB_ROOT/log.run and log.build.
run_stubbed() {
    local checkout="$1" daemon="$2"
    shift 2
    rm -f "$STUB_ROOT/log.run" "$STUB_ROOT/log.build"
    STUB_RC=0
    STUB_OUT=$(env -u SHIRABE_FLOOR_REQUIRE_ROOTLESS PATH="$STUB_BIN:$PATH" \
        STUB_DAEMON="$daemon" STUB_LOG="$STUB_ROOT/log" \
        "$checkout/scripts/check-bash-floor.sh" --backend docker "$@" canary 2>&1) || STUB_RC=$?
}

# Whether the recorded `docker run` arguments hold this exact line.
run_has() {
    [ -f "$STUB_ROOT/log.run" ] && grep -qxF -- "$1" "$STUB_ROOT/log.run"
}

# Stock Docker and CI's hosted runners are rootful, so that is the default
# path: the container runs as the invoking user over the read-only checkout,
# and one notice line recommends a rootless daemon.
test_rootful_daemon_runs_as_the_invoking_user() {
    local name="a rootful daemon runs by default, as the invoking user, with a notice"

    run_stubbed "$FIX_MAIN" rootful
    if [ $STUB_RC -ne 0 ]; then
        fail "$name" "expected exit 0, got $STUB_RC: $STUB_OUT"
        return
    fi
    if ! run_has "--user" || ! run_has "$(id -u):$(id -g)"; then
        fail "$name" "no --user $(id -u):$(id -g) in: $(cat "$STUB_ROOT/log.run")"
        return
    fi
    if ! run_has "type=bind,source=$FIX_MAIN,target=$FIX_MAIN,readonly"; then
        fail "$name" "the checkout is not mounted read-only"
        return
    fi
    case "$STUB_OUT" in
        *"rootful docker daemon"*"a rootless daemon"*) pass "$name" ;;
        *) fail "$name" "no notice recommending a rootless daemon: $STUB_OUT" ;;
    esac
}

# Strict mode, for hosts whose rule is rootless containers only: a rootful
# daemon is refused before anything is built or run, by flag or by env.
test_require_rootless_refuses_a_rootful_daemon() {
    local name="--require-rootless refuses a rootful daemon with exit 2 and nothing runs"
    local via

    for via in flag env=1 env=true; do
        if [ "$via" = flag ]; then
            run_stubbed "$FIX_MAIN" rootful --require-rootless
        else
            # Inline rather than run_stubbed, which unsets this variable so a
            # caller's setting can't mask the default; here it is the subject.
            # "true" as well as "1": a policy switch must fail closed.
            rm -f "$STUB_ROOT/log.run" "$STUB_ROOT/log.build"
            STUB_RC=0
            STUB_OUT=$(PATH="$STUB_BIN:$PATH" STUB_DAEMON=rootful STUB_LOG="$STUB_ROOT/log" \
                SHIRABE_FLOOR_REQUIRE_ROOTLESS="${via#env=}" \
                "$FIX_MAIN/scripts/check-bash-floor.sh" --backend docker canary 2>&1) || STUB_RC=$?
        fi
        if [ $STUB_RC -ne 2 ]; then
            fail "$name" "($via) expected exit 2, got $STUB_RC: $STUB_OUT"
            return
        fi
        if [ -f "$STUB_ROOT/log.run" ] || [ -f "$STUB_ROOT/log.build" ]; then
            fail "$name" "($via) docker build or run was called against the refused daemon"
            return
        fi
        case "$STUB_OUT" in
            *"refusing a rootful docker daemon"*"--require-rootless"*) ;;
            *) fail "$name" "($via) the refusal does not name itself and its switch: $STUB_OUT"; return ;;
        esac
    done
    pass "$name"
}

test_require_rootless_accepts_a_rootless_daemon() {
    local name="--require-rootless runs on a rootless daemon, without --user"

    run_stubbed "$FIX_MAIN" rootless --require-rootless
    if [ $STUB_RC -ne 0 ]; then
        fail "$name" "expected exit 0, got $STUB_RC: $STUB_OUT"
        return
    fi
    if run_has "--user"; then
        fail "$name" "--user passed on a rootless daemon"
        return
    fi
    pass "$name"
}

test_unreachable_daemon_exits_2() {
    local name="an unreachable daemon exits 2, not 1"

    run_stubbed "$FIX_MAIN" down
    if [ $STUB_RC -ne 2 ]; then
        fail "$name" "expected exit 2, got $STUB_RC: $STUB_OUT"
        return
    fi
    case "$STUB_OUT" in
        *"cannot reach a docker daemon"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $STUB_OUT" ;;
    esac
}

# On a rootless daemon the container's root already is the invoking user, and a
# --user would map to a subordinate id. The checkout is read-only at its own
# path and HOME is scratch. No safe.directory exception is passed: the
# checkout's owner is the container's user, which the runner checks up front.
test_rootless_container_shape() {
    local name="rootless: read-only checkout at its host path, no --user, scratch HOME"

    run_stubbed "$FIX_MAIN" rootless
    if [ $STUB_RC -ne 0 ]; then
        fail "$name" "expected exit 0, got $STUB_RC: $STUB_OUT"
        return
    fi
    if ! run_has "type=bind,source=$FIX_MAIN,target=$FIX_MAIN,readonly"; then
        fail "$name" "the checkout is not mounted read-only at $FIX_MAIN: $(cat "$STUB_ROOT/log.run")"
        return
    fi
    if run_has "--user"; then
        fail "$name" "--user passed on a rootless daemon"
        return
    fi
    if ! run_has "-w" || ! run_has "$FIX_MAIN"; then
        fail "$name" "the working directory is not the checkout's host path"
        return
    fi
    if ! run_has "HOME=/home/floor" || ! grep -q '^/home/floor:' "$STUB_ROOT/log.run"; then
        fail "$name" "HOME is not the scratch tmpfs"
        return
    fi
    if grep -q 'safe.directory' "$STUB_ROOT/log.run"; then
        fail "$name" "a safe.directory exception is passed"
        return
    fi
    # A plain checkout's git directory is inside the mount: nothing else is.
    if [ "$(grep -c '^type=bind' "$STUB_ROOT/log.run")" -ne 1 ]; then
        fail "$name" "a plain checkout got extra mounts: $(grep '^type=bind' "$STUB_ROOT/log.run")"
        return
    fi
    pass "$name"
}

test_linked_worktree_mounts_its_git_directory() {
    local name="a linked worktree gets the main checkout's git directory, read-only, at its path"

    run_stubbed "$FIX_WT" rootless
    if [ $STUB_RC -ne 0 ]; then
        fail "$name" "expected exit 0, got $STUB_RC: $STUB_OUT"
        return
    fi
    if ! run_has "type=bind,source=$FIX_COMMON,target=$FIX_COMMON,readonly"; then
        fail "$name" "no read-only mount of $FIX_COMMON: $(grep '^type=bind' "$STUB_ROOT/log.run")"
        return
    fi
    # The worktree's own git directory sits inside the common one, which
    # already covers it.
    if [ "$(grep -c '^type=bind' "$STUB_ROOT/log.run")" -ne 2 ]; then
        fail "$name" "expected the checkout and one git mount: $(grep '^type=bind' "$STUB_ROOT/log.run")"
        return
    fi
    pass "$name"
}

# git can write the link relative (worktree.useRelativePaths); the container
# must still find what it names, so the mount is at the resolved path.
test_relative_gitdir_link_resolves() {
    local name="a relative gitdir link is mounted where it resolves"
    local saved

    saved=$(cat "$FIX_WT/.git")
    printf 'gitdir: ../main/.git/worktrees/wt\n' >"$FIX_WT/.git"
    run_stubbed "$FIX_WT" rootless
    printf '%s\n' "$saved" >"$FIX_WT/.git"
    if [ $STUB_RC -ne 0 ]; then
        fail "$name" "expected exit 0, got $STUB_RC: $STUB_OUT"
        return
    fi
    if run_has "type=bind,source=$FIX_MAIN/.git,target=$FIX_MAIN/.git,readonly"; then
        pass "$name"
    else
        fail "$name" "no mount of $FIX_MAIN/.git: $(grep '^type=bind' "$STUB_ROOT/log.run")"
    fi
}

test_unresolvable_git_file_is_refused() {
    local name="a .git file naming no git directory is refused up front"
    local saved

    saved=$(cat "$FIX_WT/.git")
    printf 'gitdir: %s/gone/.git/worktrees/wt\n' "$STUB_ROOT" >"$FIX_WT/.git"
    run_stubbed "$FIX_WT" rootless
    printf '%s\n' "$saved" >"$FIX_WT/.git"
    if [ $STUB_RC -ne 2 ]; then
        fail "$name" "expected exit 2, got $STUB_RC: $STUB_OUT"
        return
    fi
    if [ -f "$STUB_ROOT/log.run" ] || [ -f "$STUB_ROOT/log.build" ]; then
        fail "$name" "the image was built or a suite ran before the refusal"
        return
    fi
    case "$STUB_OUT" in
        *"not a git directory on this host"*"git worktree repair"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $STUB_OUT" ;;
    esac
}

test_git_file_without_gitdir_is_refused() {
    local name="a .git file with no gitdir: line is refused up front"
    local saved

    saved=$(cat "$FIX_WT/.git")
    printf 'not a link\n' >"$FIX_WT/.git"
    run_stubbed "$FIX_WT" rootless
    printf '%s\n' "$saved" >"$FIX_WT/.git"
    if [ $STUB_RC -ne 2 ] || [ -f "$STUB_ROOT/log.build" ]; then
        fail "$name" "expected exit 2 before any build, got $STUB_RC: $STUB_OUT"
        return
    fi
    case "$STUB_OUT" in
        *"no 'gitdir:' line"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $STUB_OUT" ;;
    esac
}

test_broken_commondir_is_refused() {
    local name="a worktree whose commondir resolves nowhere is refused up front"
    local cd_file saved

    cd_file="$FIX_COMMON/worktrees/wt/commondir"
    saved=$(cat "$cd_file")
    printf '../../../gone\n' >"$cd_file"
    run_stubbed "$FIX_WT" rootless
    printf '%s\n' "$saved" >"$cd_file"
    if [ $STUB_RC -ne 2 ] || [ -f "$STUB_ROOT/log.build" ]; then
        fail "$name" "expected exit 2 before any build, got $STUB_RC: $STUB_OUT"
        return
    fi
    case "$STUB_OUT" in
        *"commondir points at"*) pass "$name" ;;
        *) fail "$name" "unhelpful message: $STUB_OUT" ;;
    esac
}

# The same shape, on a real daemon. From a linked worktree the container used
# to see no repository at all, so every `git ls-files` came back empty and
# check-directive-invocations.sh reported "OK (0 directive file(s) checked)":
# the templates suite passed while checking nothing. A probe put where the
# canary would be runs through the runner's own docker path, from a scratch
# worktree, and has to see the tracked files and fail to write the checkout.
test_real_container_reads_a_worktree_and_cannot_write_it() {
    local name="on a real daemon, a linked worktree's git resolves and the checkout is read-only"
    local out rc=0

    if [ "${FLOOR_BACKEND:-}" = system ]; then
        echo "SKIP: $name - the system backend has no container" >&2
        return
    fi
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        echo "SKIP: $name - no reachable docker daemon" >&2
        return
    fi

    cat >"$FIX_WT/scripts/bash-floor-canary.sh" <<'PROBE'
#!/usr/bin/env bash
# Probe written by check-bash-floor_test.sh in place of the canary.
tracked=$(git ls-files | wc -l | tr -d ' ')
echo "tracked=$tracked"
if touch ./floor-write-probe 2>/dev/null; then
    echo "checkout=writable"
else
    echo "checkout=read-only"
fi
PROBE
    # Whatever daemon the harness reaches, rootful included: this case is
    # about the mounts, and strict mode has its own cases above.
    out=$(env -u SHIRABE_FLOOR_REQUIRE_ROOTLESS \
        "$FIX_WT/scripts/check-bash-floor.sh" --backend docker canary 2>&1) || rc=$?
    rm -f "$FIX_WT/scripts/bash-floor-canary.sh" "$FIX_WT/floor-write-probe"
    if [ $rc -ne 0 ]; then
        fail "$name" "expected exit 0, got $rc: $out"
        return
    fi
    case "$out" in
        *"not a git repository"*) fail "$name" "git inside the container cannot resolve the worktree: $out"; return ;;
    esac
    case "$out" in
        *"tracked=1
"*|*"tracked=1") ;;
        *) fail "$name" "git ls-files did not see the worktree's one tracked file: $out"; return ;;
    esac
    case "$out" in
        *"checkout=read-only"*) pass "$name" ;;
        *) fail "$name" "the container could write the checkout: $out" ;;
    esac
}

# The image is what makes the docker floor a bash 3.2 floor with a GNU
# userland; its recipe has to say both.
test_image_recipe() {
    local name="the image adds a GNU userland and fails on any bash that is not 3.2"
    local pkg

    run_stubbed "$FIX_MAIN" rootless
    if [ ! -f "$STUB_ROOT/log.build" ]; then
        fail "$name" "no docker build was requested: $STUB_OUT"
        return
    fi
    for pkg in coreutils grep sed findutils gawk diffutils procps-ng; do
        if ! grep -q "apk add .* $pkg" "$STUB_ROOT/log.build"; then
            fail "$name" "the image does not install $pkg"
            return
        fi
    done
    if ! grep -q 'is not bash 3.2' "$STUB_ROOT/log.build"; then
        fail "$name" "the image does not check its bash version"
        return
    fi
    if ! grep -q 'is not the GNU one' "$STUB_ROOT/log.build"; then
        fail "$name" "the image does not check that its tools are the GNU ones"
        return
    fi
    pass "$name"
}

echo "Running check-bash-floor.sh tests..."
echo ""

test_canary_passes_under_this_bash
test_canary_fails_on_the_floor
test_floor_run_names_the_version
test_list_names_every_suite
test_registry_scripts_exist
test_machine_readable_registry
test_unknown_suite_is_refused
test_no_suite_is_refused
test_unreachable_floor_is_not_reported_as_a_suite_failure
test_unknown_backend_is_refused
test_system_backend_refuses_a_newer_bin_bash
test_rootful_daemon_runs_as_the_invoking_user
test_require_rootless_refuses_a_rootful_daemon
test_require_rootless_accepts_a_rootless_daemon
test_unreachable_daemon_exits_2
test_rootless_container_shape
test_linked_worktree_mounts_its_git_directory
test_relative_gitdir_link_resolves
test_unresolvable_git_file_is_refused
test_git_file_without_gitdir_is_refused
test_broken_commondir_is_refused
test_real_container_reads_a_worktree_and_cannot_write_it
test_image_recipe

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

[ "$FAIL_COUNT" -eq 0 ]
