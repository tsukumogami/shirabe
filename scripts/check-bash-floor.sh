#!/usr/bin/env bash
#
# check-bash-floor.sh - run a shell suite against the bash 3.2 floor
#
# The scripts under skills/ and scripts/ target bash 3.2, because that is what
# macOS ships as /bin/bash and always will. This runs a named suite on that
# floor so a portability regression is caught before a push rather than by CI,
# or by main.
#
# The failure mode this exists for is silent. Given IFS=$'\001' and the record
# "1\001foo\001bar", bash 3.2's `read` does not split it: the whole record
# lands in the first variable and the rest come back empty. No error, no
# diagnostic, and the next thing that breaks is three functions away.
# scripts/bash-floor-canary.sh is that case, kept as a fixture.
#
# Usage:
#   scripts/check-bash-floor.sh [options] <suite>...
#   scripts/check-bash-floor.sh --list
#
# Options:
#   --backend docker|system|auto   how to reach a bash 3.2 (default: auto)
#   --list                         list the suites and what each one runs
#   -h, --help                     this message
#
# Backends:
#   system   /bin/bash is already 3.2 (macOS). Runs the suite directly, with a
#            shim directory ahead of PATH so a nested `bash` stays on the floor.
#   docker   builds a bash:3.2 image carrying the tools the suites shell out to
#            and runs the suite inside it. Every bash in that container is 3.2.
#   auto     system when /bin/bash is 3.2, otherwise docker.
#
# Environment:
#   SHIRABE_FLOOR_IMAGE   override the container image tag that gets built
#   SHIRABE_BIN           a shirabe binary to inject instead of building one
#                         (docker backend only; must be static/musl-linked)
#
# Exit codes:
#   0 - the suite passed on the floor
#   1 - the suite failed on the floor
#   2 - usage error, or the floor could not be reached

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FLOOR_IMAGE="${SHIRABE_FLOOR_IMAGE:-shirabe-bash-floor:3.2}"
BASE_IMAGE="bash:3.2"

# Mount points inside the container. /w is the checkout; /floor holds what the
# floor run injects and the checkout must not see.
WORKDIR=/w
INJECT_DIR=/floor

BACKEND=auto
TMP_DIRS=""

cleanup() {
    local d
    for d in $TMP_DIRS; do
        [ -n "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

die() {
    echo "check-bash-floor: $*" >&2
    exit 2
}

# Sets MKTEMP_RESULT rather than echoing it. A command substitution runs in a
# subshell, so a function that echoes its result cannot also register the
# directory for cleanup, or exit the script when something goes wrong - both
# would be swallowed with the subshell.
MKTEMP_RESULT=""
mktempdir() {
    MKTEMP_RESULT=$(mktemp -d) || die "could not create a temporary directory"
    TMP_DIRS="$TMP_DIRS $MKTEMP_RESULT"
}

# -- Suite registry -----------------------------------------------------------
#
# One entry per shell suite CI runs, naming the same scripts the workflow runs
# so the local check and the CI check cannot drift apart.
#
# Exemptions - shell that CI runs and this deliberately does not floor-check:
#
#   scripts/run-evals.sh (run-evals.yml)
#       Drives the `claude` CLI against live models on workflow_dispatch. An
#       operator tool, never invoked by a skill on a user's machine, and it
#       cannot run offline or in a container.
#   .release/set-version.sh, .release/post-release.sh (release.yml,
#   finalize-release.yml)
#       Release automation. Runs only on ubuntu runners, from a workflow,
#       against a checkout it mutates. Not shipped to adopters.
#   scripts/check-evals-exist.sh, scripts/check-no-duplicate-rule-list.sh,
#   scripts/check-no-fixture-design-leak.sh, scripts/check-sentinel.sh
#       Repository lint over this repository's own tree, on ubuntu runners
#       only. None of them belongs to a skill, so none reaches a macOS
#       /bin/bash. Two also shell out to python3, so a floor run would mostly
#       exercise that rather than bash.

SUITES="plan execute work-on preflight templates template-consistency"

suite_scripts() {
    case "$1" in
        plan)
            echo "skills/plan/scripts/plan-to-tasks_test.sh"
            ;;
        execute)
            echo "skills/execute/scripts/run-cascade_test.sh"
            echo "skills/execute/scripts/assert-child-template_test.sh"
            # Skips cleanly when koto is absent, which it is on the macOS
            # runner. It is here for the floor's own sake: a developer running
            # this suite on macOS has koto, so the cases execute on 3.2 there.
            echo "skills/execute/scripts/settled-branch-record_test.sh"
            ;;
        work-on)
            # Drives real koto sessions to assert that a cleared context key
            # holds its phase, which cannot be checked without the engine that
            # evaluates the gate. Skips cleanly when koto is absent, which it is
            # on the macOS runner; it is in this suite for the floor's own sake,
            # since a developer running it locally has koto and the cases
            # genuinely execute on 3.2 there.
            echo "skills/work-on/scripts/retry-clearing_test.sh"
            ;;
        preflight)
            echo "scripts/skill-preflight_test.sh"
            echo "scripts/lib/preflight-probe_test.sh"
            echo "scripts/lib/preflight-report_test.sh"
            echo "scripts/check-skill-requires_test.sh"
            echo "scripts/check-skill-injection_test.sh"
            echo "scripts/check-tool-diagnostic-discards_test.sh"
            ;;
        templates)
            echo "scripts/check-template-interpolation_test.sh"
            echo "scripts/check-template-interpolation.sh"
            echo "scripts/check-template-directives_test.sh"
            echo "scripts/check-template-directives.sh"
            ;;
        template-consistency)
            echo "scripts/validate-template-mermaid.sh"
            echo "scripts/validate-template-mermaid_test.sh"
            echo "scripts/ci-gate-expression_test.sh"
            # Extracts and runs the settled-branch read straight out of
            # skills/execute/koto-templates/execute.md, which is what makes it a
            # template-consistency check rather than a preflight one -- and it is
            # check-template-consistency.yml that runs it in CI.
            echo "scripts/settled-branch-read_test.sh"
            ;;
        canary)
            # Not a suite: the #283 regression kept as a fixture. It is
            # expected to FAIL on the floor and to pass under bash 4+, which is
            # what check-bash-floor_test.sh asserts. Listing it here runs the
            # self-test through the same code path as a real suite.
            echo "scripts/bash-floor-canary.sh"
            ;;
        *)
            return 1
            ;;
    esac
}

suite_workflow() {
    case "$1" in
        plan)                 echo ".github/workflows/check-plan-scripts.yml" ;;
        execute)              echo ".github/workflows/check-execute-scripts.yml" ;;
        work-on)              echo ".github/workflows/check-work-on-scripts.yml" ;;
        preflight)            echo ".github/workflows/check-preflight-scripts.yml" ;;
        templates)            echo ".github/workflows/check-templates.yml" ;;
        template-consistency) echo ".github/workflows/check-template-consistency.yml" ;;
        canary)               echo "(fixture, not a CI suite)" ;;
    esac
}

# The plan and execute harnesses run `shirabe` for real rather than emulating
# it, so a floor run has to hand them a binary the floor container can execute.
suite_needs_shirabe() {
    case "$1" in
        plan|execute) return 0 ;;
        *)            return 1 ;;
    esac
}

list_suites() {
    local suite script
    echo "Suites (scripts/check-bash-floor.sh <suite>):"
    echo ""
    for suite in $SUITES; do
        echo "  $suite"
        echo "    from $(suite_workflow "$suite")"
        while read -r script; do
            [ -n "$script" ] && echo "      $script"
        done <<EOF
$(suite_scripts "$suite")
EOF
        echo ""
    done
    echo "  all"
    echo "    every suite above, in order"
    echo ""
    echo "  canary"
    echo "    scripts/bash-floor-canary.sh - the #283 regression as a fixture."
    echo "    Expected to FAIL on the floor and to pass under bash 4+."
}

# -- musl shirabe -------------------------------------------------------------

musl_triple() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64-unknown-linux-musl" ;;
        aarch64|arm64) echo "aarch64-unknown-linux-musl" ;;
        *) return 1 ;;
    esac
}

# The floor image is musl-based and a locally built shirabe is glibc-linked, so
# the host binary cannot execute inside it. Build (or reuse) a static musl one.
#
# Sets SHIRABE_FLOOR_BIN. Not being able to produce a binary is an exit 2 - the
# floor was never reached - and must not be reported as the suite failing on
# the floor, which is what echoing the path through a command substitution
# would have made of it.
SHIRABE_FLOOR_BIN=""
resolve_shirabe_bin() {
    local triple bin

    if [ -n "${SHIRABE_BIN:-}" ]; then
        [ -x "$SHIRABE_BIN" ] || die "SHIRABE_BIN is set but not executable: $SHIRABE_BIN"
        SHIRABE_FLOOR_BIN="$SHIRABE_BIN"
        return 0
    fi

    triple=$(musl_triple) || die "no musl target known for $(uname -m); build a static shirabe yourself and pass it in SHIRABE_BIN"
    bin="$REPO_ROOT/target/$triple/release/shirabe"

    if [ ! -x "$bin" ]; then
        echo "check-bash-floor: building a static shirabe for the floor container" >&2
        echo "check-bash-floor: cargo build --release --target $triple -p shirabe" >&2
        if ! ( cd "$REPO_ROOT" && cargo build --release --target "$triple" -p shirabe ) >&2; then
            echo "" >&2
            echo "check-bash-floor: that build is how the plan and execute harnesses get a" >&2
            echo "  binary the musl floor container can run. If the target is missing:" >&2
            echo "" >&2
            echo "    rustup target add $triple" >&2
            echo "" >&2
            echo "  Or pass one in directly: SHIRABE_BIN=/path/to/static/shirabe" >&2
            exit 2
        fi
    fi

    [ -x "$bin" ] || die "expected a built binary at $bin"
    SHIRABE_FLOOR_BIN="$bin"
}

# -- docker backend -----------------------------------------------------------

# The base image ships bash 3.2, busybox, and nothing else. jq, git and python3
# are what the suites shell out to; without them a floor run reports
# missing-tool failures that have nothing to do with the bash version.
build_floor_image() {
    command -v docker >/dev/null 2>&1 || die "docker is required for the docker backend (on macOS use --backend system: /bin/bash is already 3.2)"
    echo "check-bash-floor: building $FLOOR_IMAGE" >&2
    docker build -q -t "$FLOOR_IMAGE" - >/dev/null <<EOF || die "could not build $FLOOR_IMAGE from $BASE_IMAGE"
FROM $BASE_IMAGE
RUN apk add --no-cache jq git python3
EOF
}

# run-cascade_test.sh requires cargo and rebuilds the binary itself instead of
# honouring a pre-set SHIRABE_BIN the way plan-to-tasks_test.sh does. Rather
# than edit a test to suit its runner, the floor run answers that build with a
# stub: the binary is genuinely built, on the host, for the container's libc,
# and mounted where the harness expects to find it.
write_cargo_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
# Stub written by scripts/check-bash-floor.sh. See write_cargo_stub there.
if [ "${1:-}" = "build" ]; then
    echo "check-bash-floor: not running 'cargo $*' inside the floor container." >&2
    echo "check-bash-floor: shirabe was built on the host for this container's" >&2
    echo "  libc and is mounted at target/release/shirabe." >&2
    exit 0
fi
echo "check-bash-floor: unexpected 'cargo $*' inside the floor container." >&2
echo "  The stub only answers 'cargo build'; teach it this call or drop it." >&2
exit 127
EOF
    chmod +x "$path"
}

run_suite_docker() {
    local suite="$1"
    local script status shirabe_bin stub_dir
    # Always non-empty, so `set -u` never meets an empty array expansion -
    # which is itself a bash 3.2 trap, and this script runs on the floor too.
    local args
    args=(--rm -v "$REPO_ROOT:$WORKDIR")

    if suite_needs_shirabe "$suite"; then
        resolve_shirabe_bin
        shirabe_bin="$SHIRABE_FLOOR_BIN"
        mktempdir
        stub_dir="$MKTEMP_RESULT"
        write_cargo_stub "$stub_dir/cargo"

        # target/ is masked with a tmpfs so the container can neither read nor
        # write the host's glibc build artifacts, and the musl binary is placed
        # where each harness looks: plan-to-tasks_test.sh honours SHIRABE_BIN,
        # run-cascade_test.sh does not and reads target/release/shirabe.
        #
        # The mkdir is not redundant. Docker creates a missing mount point
        # itself, and it creates it as root - on the host, because the parent
        # is a bind mount of the checkout. A floor run would leave behind a
        # root-owned target/ that the next `cargo build` cannot write to.
        mkdir -p "$REPO_ROOT/target"
        args=("${args[@]}" --tmpfs "$WORKDIR/target")
        args=("${args[@]}" -v "$shirabe_bin:$INJECT_DIR/shirabe:ro")
        args=("${args[@]}" -v "$shirabe_bin:$WORKDIR/target/release/shirabe:ro")
        args=("${args[@]}" -v "$stub_dir:$INJECT_DIR/bin:ro")
        args=("${args[@]}" -e "SHIRABE_BIN=$INJECT_DIR/shirabe")
        args=("${args[@]}" -e "PATH=$INJECT_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    fi

    # The container runs as root over a checkout owned by someone else, which
    # git refuses to read without this.
    args=("${args[@]}" -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e "GIT_CONFIG_VALUE_0=*")
    args=("${args[@]}" -w "$WORKDIR" "$FLOOR_IMAGE")

    status=0
    while read -r script; do
        [ -n "$script" ] || continue
        echo "--- bash 3.2 (docker): $script"
        # Plain `bash` on purpose: inside this container every bash is 3.2, so
        # a nested `bash` or a /usr/bin/env bash shebang stays on the floor.
        if ! docker run "${args[@]}" bash "$script"; then
            status=1
        fi
    done <<EOF
$(suite_scripts "$suite")
EOF
    return $status
}

# -- system backend -----------------------------------------------------------

system_bash_is_floor() {
    [ -x /bin/bash ] || return 1
    /bin/bash -c 'case "$BASH_VERSION" in 3.2*) exit 0;; *) exit 1;; esac'
}

run_suite_system() {
    local suite="$1"
    local script status shim

    system_bash_is_floor || die "/bin/bash is not 3.2 here ($(/bin/bash -c 'echo $BASH_VERSION' 2>/dev/null || echo absent)); use --backend docker"

    # /bin/bash alone only puts the harness on the floor. The execute and
    # template harnesses re-enter through a bare `bash`, and every script here
    # carries a /usr/bin/env bash shebang, so both would resolve to whatever
    # newer bash is on PATH and hide the regression this run exists to catch.
    # The shim makes `bash` mean 3.2 for the whole process tree.
    mktempdir
    shim="$MKTEMP_RESULT"
    ln -s /bin/bash "$shim/bash"

    status=0
    while read -r script; do
        [ -n "$script" ] || continue
        echo "--- bash 3.2 (/bin/bash): $script"
        if ! ( cd "$REPO_ROOT" && PATH="$shim:$PATH" /bin/bash "$script" ); then
            status=1
        fi
    done <<EOF
$(suite_scripts "$suite")
EOF
    return $status
}

# -- main ---------------------------------------------------------------------

# The header comment is the help text. Print everything after the shebang up to
# the first line that is not a comment, rather than a line range that goes
# stale the first time someone edits the header.
usage() {
    sed -e '1d' -e '/^[^#]/,$d' "$0" | sed 's/^#\{1,\} \{0,1\}//'
}

REQUESTED=""

while [ $# -gt 0 ]; do
    case "$1" in
        --list)
            list_suites
            exit 0
            ;;
        --backend)
            [ $# -ge 2 ] || die "--backend needs a value (docker, system or auto)"
            BACKEND="$2"
            shift 2
            ;;
        --backend=*)
            BACKEND="${1#--backend=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "unknown option: $1 (try --help)"
            ;;
        all)
            REQUESTED="$REQUESTED $SUITES"
            shift
            ;;
        *)
            suite_scripts "$1" >/dev/null 2>&1 || die "unknown suite: $1 (try --list)"
            REQUESTED="$REQUESTED $1"
            shift
            ;;
    esac
done

case "$BACKEND" in
    auto)
        if system_bash_is_floor; then
            BACKEND=system
        else
            BACKEND=docker
        fi
        ;;
    docker|system) ;;
    *) die "unknown backend: $BACKEND (docker, system or auto)" ;;
esac

[ -n "$REQUESTED" ] || die "name at least one suite (try --list)"

if [ "$BACKEND" = docker ]; then
    build_floor_image
fi

EXIT_STATUS=0
FAILED=""

for suite in $REQUESTED; do
    echo ""
    echo "=== $suite on the bash 3.2 floor ($BACKEND) ==="
    if [ "$BACKEND" = docker ]; then
        run_suite_docker "$suite" || { EXIT_STATUS=1; FAILED="$FAILED $suite"; }
    else
        run_suite_system "$suite" || { EXIT_STATUS=1; FAILED="$FAILED $suite"; }
    fi
done

echo ""
if [ $EXIT_STATUS -eq 0 ]; then
    echo "check-bash-floor: PASS -$REQUESTED"
else
    echo "check-bash-floor: FAIL -$FAILED"
fi

exit $EXIT_STATUS
