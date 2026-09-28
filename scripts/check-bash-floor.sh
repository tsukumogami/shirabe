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
#   --suites                       the CI suite names, one per line
#   --scripts <suite>              that suite's scripts, one per line
#   --require-rootless             docker backend: refuse a rootful daemon
#   -h, --help                     this message
#
# Backends:
#   system   /bin/bash is already 3.2 (macOS). Runs the suite directly, with a
#            shim directory ahead of PATH so a nested `bash` stays on the floor.
#   docker   builds a bash:3.2 image carrying the tools the suites shell out to
#            and runs the suite inside it. Every bash in that container is 3.2.
#   auto     system when /bin/bash is 3.2, otherwise docker.
#
# The docker backend's container:
#   - sees the checkout read-only, at the same path it has on the host, so a
#     suite cannot change a file in it; suites write under the container's
#     /tmp, and HOME is a tmpfs.
#   - resolves a linked worktree: the git directories its .git file points to
#     are mounted read-only at their host paths too. A .git file whose git
#     directory the host cannot resolve is refused before anything runs.
#   - runs on whatever daemon docker reaches (DOCKER_HOST's choice). On a
#     rootless daemon the container's root is the invoking user. On a rootful
#     one the container runs as --user "$(id -u):$(id -g)", which with the
#     read-only mount keeps a suite from changing the checkout; a notice
#     recommends a rootless daemon, which also keeps the daemon's own work
#     off the host's root. --require-rootless refuses a rootful daemon, for
#     hosts that allow only rootless containers. CI's hosted runners have a
#     rootful daemon, so CI exercises the --user path; a rootless host
#     exercises the other.
#   - has GNU coreutils, grep, sed, findutils, gawk, diffutils and procps next
#     to bash 3.2, so its userland matches a Linux host's. It still does not
#     match macOS, whose tools are BSD: a GNU-only flag passes here and fails
#     there, which only the system backend on macOS catches.
#
# Environment:
#   SHIRABE_FLOOR_IMAGE             override the container image tag that gets
#                                   built
#   SHIRABE_BIN                     a shirabe binary to inject instead of
#                                   building one (docker backend only; must be
#                                   static/musl)
#   SHIRABE_FLOOR_REQUIRE_ROOTLESS  any value but empty or 0 is the same as
#                                   --require-rootless (docker backend only)
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

# Mount points inside the container. The checkout is mounted at $REPO_ROOT,
# its own host path, and must stay there: the gitdir link in a linked
# worktree's .git file only resolves at that path. /floor holds what the floor
# run injects and the checkout must not see; HOME is a tmpfs, since the
# checkout is read-only and on a rootful daemon the container user has no home
# of its own.
INJECT_DIR=/floor
FLOOR_HOME=/home/floor

BACKEND=auto
# A policy switch fails closed: anything but empty or 0 turns it on.
case "${SHIRABE_FLOOR_REQUIRE_ROOTLESS:-0}" in
    ""|0) REQUIRE_ROOTLESS=0 ;;
    *)    REQUIRE_ROOTLESS=1 ;;
esac
# Set by check_docker_daemon: 1 when the daemon is rootless, 0 when rootful.
DAEMON_ROOTLESS=""
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
#   scripts/run-evals_test.sh, scripts/run-evals/fixtures/ (check-run-evals.yml)
#       The runner's own suite, run offline against a stub claude on ubuntu
#       runners. It tests an operator tool that never reaches a user's macOS
#       /bin/bash, so it stays off the floor with the runner.
#   scripts/ablation/ (offload-ablation.yml)
#       The runner's ablation mode and its checks: an operator tool that
#       starts model sessions, plus repository lint over pull requests. No
#       skill invokes any of it, so it stays off the floor with the runner.
#   .release/set-version.sh, .release/post-release.sh (release.yml,
#   finalize-release.yml)
#       Release automation. Runs only on ubuntu runners, from a workflow,
#       against a checkout it mutates. Not shipped to adopters.
#   scripts/release-workflow-inputs_test.sh (check-release-workflows.yml)
#       Runs the step scripts of release.yml and finalize-release.yml, which
#       only ever run under an ubuntu runner's bash, so it runs them there.
#   scripts/check-evals-exist.sh, scripts/check-no-duplicate-rule-list.sh,
#   scripts/check-no-fixture-design-leak.sh, scripts/check-sentinel.sh,
#   scripts/check-macos-floor-legs.sh, scripts/check-macos-floor-legs_test.sh
#   (check-macos-floor-legs.yml)
#       Repository lint over this repository's own tree, on ubuntu runners
#       only. None of them belongs to a skill, so none reaches a macOS
#       /bin/bash. Three also shell out to python3, so a floor run would
#       mostly exercise that rather than bash.
#   scripts/check-koto-release.sh (check-koto-entry-floor.yml)
#       The decider check on the koto minimum. It runs for real only on the
#       ubuntu runner that installs exactly that release, and no skill invokes
#       it, so it never reaches a macOS /bin/bash on a user's machine. Its
#       test, scripts/check-koto-release_test.sh, drives it against a stand-in
#       koto in the koto-open suite, wherever yq is present.
#
# Backend limit, not an exemption: the `preflight` suite fails one case on the
# docker backend for a non-bash reason (the image has no koto, gh or shirabe,
# so the shipped declarations are not silent there, as they are on a
# provisioned host), so `all` on Linux reports it red; its floor run is the
# macOS leg, on the system backend.

SUITES="plan execute work-on preflight templates template-consistency koto-open deliver scope coordinate coordinate-reconcile offload-baseline"

suite_scripts() {
    case "$1" in
        plan)
            echo "skills/plan/scripts/plan-to-tasks_test.sh"
            # Needs no binary.
            echo "skills/plan/scripts/resolve-split-mode_test.sh"
            ;;
        execute)
            echo "skills/work-on/scripts/run-cascade_test.sh"
            echo "skills/execute/scripts/assert-child-template_test.sh"
            # Skips cleanly when koto is absent, which it is on the macOS
            # runner. It is here for the floor's own sake: a developer running
            # this suite on macOS has koto, so the cases execute on 3.2 there.
            echo "skills/execute/scripts/settled-branch-record_test.sh"
            # Same koto-absent contract: its static cases still run on the
            # macOS leg, and the engine-backed ones skip there.
            echo "skills/execute/scripts/terminal-retention_test.sh"
            # Need no engine and no network: both drive the merge scripts
            # through a test-local gh stub, so every case executes on 3.2.
            echo "skills/execute/scripts/merge-verdict_test.sh"
            echo "skills/execute/scripts/merge-exec_test.sh"
            # The single-pr merge step's scripts, each driven through test-local
            # gh and koto stubs (and real git), so every case runs on 3.2.
            echo "skills/execute/scripts/owned-pr_test.sh"
            echo "skills/execute/scripts/run-id_test.sh"
            # Reads the call sites with grep, awk and find only.
            echo "skills/execute/scripts/owned-pr-callers_test.sh"
            echo "skills/execute/scripts/push-and-record_test.sh"
            echo "skills/execute/scripts/record-merge-verdict_test.sh"
            echo "skills/execute/scripts/adopt-or-create-pr_test.sh"
            echo "skills/execute/scripts/print-exit_test.sh"
            echo "skills/execute/scripts/eval-gh-shim_test.sh"
            # The eval koto shim on an execute session; needs only jq.
            echo "skills/execute/scripts/eval-koto-shim_test.sh"
            # Its own refusals run on a koto stub; its engine cases, like the
            # structure test's compile, skip without koto.
            echo "skills/execute/scripts/execute-open_test.sh"
            echo "skills/execute/scripts/execute-template-structure_test.sh"
            # Its script cases write through a koto stand-in and need only git
            # and jq, so they run on the macOS leg; its engine cases skip there.
            echo "skills/execute/scripts/drift-facts_test.sh"
            # The coordinated loop's scripts. Each drives the eval gh shim's
            # repository model, a koto context stub, and real git, so every
            # case runs on 3.2; the envelope's structure test compiles with
            # koto and its engine test runs it, each skipping without koto.
            echo "skills/execute/scripts/coordinated-next_test.sh"
            echo "skills/execute/scripts/coordination-verdict_test.sh"
            echo "skills/execute/scripts/record-coordination-verdict_test.sh"
            echo "skills/execute/scripts/record-coord-setup_test.sh"
            echo "skills/execute/scripts/node-cut_test.sh"
            echo "skills/execute/scripts/node-push_test.sh"
            echo "skills/execute/scripts/coord-merge_test.sh"
            echo "skills/execute/scripts/execute-coordinated-structure_test.sh"
            echo "skills/execute/scripts/execute-coordinated-engine_test.sh"
            # The "merged" wording check and its test: text only, so every
            # case runs on 3.2.
            echo "scripts/check-merged-wording_test.sh"
            echo "scripts/check-merged-wording.sh"
            ;;
        work-on)
            # Drives real koto sessions to assert that a cleared context key
            # holds its phase, which cannot be checked without the engine that
            # evaluates the gate. Skips cleanly when koto is absent, which it is
            # on the macOS runner; it is in this suite for the floor's own sake,
            # since a developer running it locally has koto and the cases
            # genuinely execute on 3.2 there.
            echo "skills/work-on/scripts/retry-clearing_test.sh"
            # Also drives real koto sessions, and skips cleanly without them
            # for the same reason retry-clearing_test.sh does.
            echo "skills/work-on/scripts/cascade-chaining_test.sh"
            # Needs no engine at all: it builds repositories and reads commits,
            # so every case genuinely executes on the floor.
            echo "skills/work-on/scripts/verify-cascade-commit_test.sh"
            # Drives real koto sessions, and skips cleanly without them. Its
            # engine-free case invokes the discriminator it carries.
            echo "skills/work-on/scripts/ci-monitor-role_test.sh"
            # Needs no engine: it runs the gate expression against stubbed gh.
            echo "skills/work-on/scripts/closing-keyword-gate_test.sh"
            # Drives real koto sessions, and skips cleanly without them.
            echo "skills/work-on/scripts/pre-pr-evidence_test.sh"
            # Drives real koto sessions, and skips cleanly without them.
            echo "skills/work-on/scripts/finalization-shape_test.sh"
            # Holds pre_pr.md in a real koto session, and skips cleanly
            # without one.
            echo "skills/work-on/scripts/check-pre-pr-referents_test.sh"
            # Its rule-text cases need no engine; its engine cases skip without
            # koto.
            echo "skills/work-on/scripts/terminal-retention_test.sh"
            # Its script cases write through a koto stand-in and need only git,
            # so they run on the floor; its engine cases skip without koto.
            echo "skills/work-on/scripts/record-changed-paths_test.sh"
            # Same shape: its script cases run real clones through a koto
            # stand-in; its engine cases skip without koto.
            echo "skills/work-on/scripts/has-commits_test.sh"
            # Its script cases need only jq, git and a stubbed gh, so they run
            # on the floor; its engine cases skip without koto.
            echo "skills/work-on/scripts/check-staleness_test.sh"
            # The --koto-leg entry: its own refusals run on a koto stub, so they
            # execute on the floor; its engine cases skip without koto.
            echo "skills/work-on/scripts/work-on-open_test.sh"
            # Preflight against a stand-in koto; the at-floor case skips
            # without a real one.
            echo "skills/work-on/scripts/work-on-requires_test.sh"
            # session-role.sh is deliberately NOT listed. Every entry here is
            # run with no arguments and a nonzero status is a failure, and the
            # discriminator exits 2 on a missing session name by design. It
            # reaches the floor through ci-monitor-role_test.sh, whose
            # engine-free case runs without koto and invokes it.
            ;;
        preflight)
            # Runs on the system backend only. In the docker container one
            # case fails for a reason unrelated to bash: the image carries no
            # koto, gh or shirabe to satisfy the shipped declarations. Its
            # floor run is the macOS leg.
            echo "scripts/skill-preflight_test.sh"
            echo "scripts/lib/preflight-probe_test.sh"
            echo "scripts/lib/preflight-report_test.sh"
            echo "scripts/lib/preflight-minimum_test.sh"
            echo "scripts/check-skill-requires_test.sh"
            # The scan on its own, against the committed tree: the verdict the
            # macOS leg reports, not only a case inside the harness above.
            echo "scripts/check-skill-requires.sh"
            echo "scripts/check-skill-injection_test.sh"
            echo "scripts/check-tool-diagnostic-discards_test.sh"
            ;;
        templates)
            echo "scripts/check-template-interpolation_test.sh"
            echo "scripts/check-template-interpolation.sh"
            echo "scripts/check-template-directives_test.sh"
            echo "scripts/check-template-directives.sh"
            echo "scripts/check-directive-invocations_test.sh"
            echo "scripts/check-directive-invocations.sh"
            echo "scripts/check-init-site-vars_test.sh"
            echo "scripts/check-init-site-vars.sh"
            # Read the templates' front matter with yq, which the floor image
            # carries for them (see build_floor_image).
            echo "scripts/check-decider-declarations_test.sh"
            echo "scripts/check-decider-declarations.sh"
            ;;
        template-consistency)
            echo "scripts/validate-template-mermaid.sh"
            echo "scripts/validate-template-mermaid_test.sh"
            echo "scripts/ci-gate-expression_test.sh"
            # The gate reader both of those depend on. Its regression only
            # reproduces on the floor: newer bash does not make the writer's
            # SIGPIPE fatal, so this leg is where the pin actually bites.
            echo "scripts/lib/koto-gates_test.sh"
            # The settled-branch read used to be listed here, because it
            # extracted twenty-five lines of shell straight out of
            # skills/execute/koto-templates/execute.md. That read is gone: the
            # branch now arrives in spawn_and_await as a capture from
            # settled_branch_record, whose gate has already verified it. What is
            # left to check lives with the script that does the recording, in
            # the `execute` suite.
            ;;
        koto-open)
            # The shared koto entry. Its stand-in cases need only jq and git,
            # so they execute on the floor wherever it runs; its engine cases
            # skip without koto, which the macOS runner lacks, and a developer
            # running this locally with koto gets them on 3.2 as well.
            echo "scripts/koto-open_test.sh"
            # A stub koto answers every case, so all of them run on 3.2.
            echo "scripts/assert-koto-floor_test.sh"
            # Reads files and greps them; no koto, so every case runs on 3.2.
            echo "scripts/koto-minimum-consistency_test.sh"
            # The decider check against a stand-in koto; needs yq, and skips
            # loudly without it.
            echo "scripts/check-koto-release_test.sh"
            ;;
        coordinate)
            # /coordinate's script tests. They drive test-local gh and koto
            # stand-ins and need only jq and git, so every case runs on 3.2.
            # Its engine suites (*_engine_test.sh) need real koto and run on
            # ubuntu only.
            echo "skills/coordinate/scripts/record-codec_test.sh"
            echo "skills/coordinate/scripts/coord-log_test.sh"
            echo "skills/coordinate/scripts/coordinate-report_test.sh"
            echo "skills/coordinate/scripts/rule-coverage_test.sh"
            echo "skills/coordinate/scripts/record-find_test.sh"
            echo "skills/coordinate/scripts/record-open_test.sh"
            echo "skills/coordinate/scripts/record-write_test.sh"
            echo "skills/coordinate/scripts/record-holding_test.sh"
            echo "skills/coordinate/scripts/record-confirm_test.sh"
            echo "skills/coordinate/scripts/start-check_test.sh"
            echo "skills/coordinate/scripts/posture-read_test.sh"
            # The board, land and merge scripts: a localized plugin tree with
            # the gh-board and koto stand-ins, so every case runs on 3.2.
            echo "skills/coordinate/scripts/board-verdict_test.sh"
            echo "skills/coordinate/scripts/board-record_test.sh"
            echo "skills/coordinate/scripts/land-check_test.sh"
            echo "skills/coordinate/scripts/land-merge_test.sh"
            echo "skills/coordinate/scripts/merge-confirm_test.sh"
            echo "skills/coordinate/scripts/merged-facts_test.sh"
            # The close-outs and the turn's checks: the gh and koto stand-ins
            # (closeout-read's in a localized tree with a stand-in board), so
            # every case runs on 3.2.
            echo "skills/coordinate/scripts/predecessor-handoff_test.sh"
            echo "skills/coordinate/scripts/closeout-read_test.sh"
            echo "skills/coordinate/scripts/rotation-close_test.sh"
            echo "skills/coordinate/scripts/deferral-check_test.sh"
            echo "skills/coordinate/scripts/pick-facts_test.sh"
            echo "skills/coordinate/scripts/report-facts_test.sh"
            echo "skills/coordinate/scripts/quiet-check_test.sh"
            echo "skills/coordinate/scripts/skill-hygiene_test.sh"
            echo "skills/coordinate/scripts/progress-view_test.sh"
            echo "skills/coordinate/scripts/coord-verdict-table_test.sh"
            # The dispatch path's scripts: test-local niwa, koto, gh and record
            # stand-ins, so every case runs on 3.2.
            echo "skills/coordinate/scripts/dispatch-common_test.sh"
            echo "skills/coordinate/scripts/render-brief_test.sh"
            echo "skills/coordinate/scripts/dispatch-worker_test.sh"
            echo "skills/coordinate/scripts/wait-target_test.sh"
            echo "skills/coordinate/scripts/teardown-inventory_test.sh"
            # The decision-phrasing list's reader: bash, awk and grep only.
            echo "skills/coordinate/scripts/decision-phrasings_test.sh"
            echo "skills/coordinate/scripts/decision-render_test.sh"
            echo "skills/coordinate/scripts/report-questions_test.sh"
            echo "skills/coordinate/scripts/record-decision_test.sh"
            echo "skills/coordinate/scripts/decision-next_test.sh"
            echo "skills/coordinate/scripts/need-check_test.sh"
            echo "skills/coordinate/scripts/skill-states_test.sh"
            ;;
        deliver)
            # The report, the probes, the binding check, the mode map, and the
            # eval gh shim. They drive test-local gh and koto stand-ins and need
            # only bash, git and jq, so every case runs on 3.2. The engine
            # suites stay on the Linux job that installs koto.
            echo "scripts/plan-mode_test.sh"
            echo "skills/deliver/scripts/deliver-report_test.sh"
            echo "skills/deliver/scripts/deliver-probe_test.sh"
            echo "skills/deliver/scripts/deliver-preflight_test.sh"
            echo "skills/deliver/scripts/eval-gh-shim_test.sh"
            echo "skills/deliver/scripts/deliver-requires_test.sh"
            ;;
        scope)
            # Citations, intake, the /plan hop's consistency check, resume
            # routing, publish, and the exit records. A gh stub and a local bare
            # origin stand in for GitHub; the koto and shirabe cases skip here
            # and run on the Linux jobs that install both.
            echo "skills/scope/scripts/check-citations_test.sh"
            echo "skills/scope/scripts/resolve-intent_test.sh"
            echo "skills/scope/scripts/check-recorded-intent_test.sh"
            echo "skills/scope/scripts/check-upstream_test.sh"
            echo "skills/scope/scripts/check-plan-mode_test.sh"
            echo "skills/scope/scripts/run-intake_test.sh"
            echo "skills/scope/scripts/scope-template_test.sh"
            echo "skills/scope/scripts/resume-probe_test.sh"
            echo "skills/scope/scripts/startable-issues_test.sh"
            echo "skills/scope/scripts/record-executed-report_test.sh"
            echo "skills/scope/scripts/record-scope-exit_test.sh"
            echo "skills/scope/scripts/publish-scoping-pr_test.sh"
            echo "skills/scope/scripts/print-scope-exit_test.sh"
            ;;
        offload-baseline)
            # The instruction-offload baseline's pin check and token count.
            # Its suite builds a throwaway repository and a koto stand-in and
            # needs only bash, git and jq, so every case runs on 3.2.
            echo "scripts/offload-baseline_test.sh"
            ;;
        canary)
            # Not a suite: the #283 regression kept as a fixture. It is
            # expected to FAIL on the floor and to pass under bash 4+, which is
            # what check-bash-floor_test.sh asserts. Listing it here runs the
            # self-test through the same code path as a real suite.
            echo "scripts/bash-floor-canary.sh"
            ;;
        coordinate-reconcile)
            # /coordinate's reconcile scripts: bash, jq and git only, with
            # stand-ins for gh, niwa and koto, so every case runs on 3.2.
            echo "skills/coordinate/scripts/reconcile-report_test.sh"
            echo "skills/coordinate/scripts/reconcile-check_test.sh"
            echo "skills/coordinate/scripts/reconcile-read_test.sh"
            echo "skills/coordinate/scripts/reconcile-pass_test.sh"
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
        koto-open)            echo ".github/workflows/check-koto-open.yml" ;;
        deliver)              echo ".github/workflows/check-deliver-scripts.yml" ;;
        scope)                echo ".github/workflows/check-scope-scripts.yml" ;;
        coordinate)           echo ".github/workflows/check-coordinate-scripts.yml" ;;
        coordinate-reconcile) echo ".github/workflows/check-coordinate-reconcile-scripts.yml" ;;
        offload-baseline)     echo ".github/workflows/check-offload-baseline.yml" ;;
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
        # Absolute, because it becomes a --mount source.
        SHIRABE_FLOOR_BIN="$(CDPATH= cd "$(dirname "$SHIRABE_BIN")" && pwd)/$(basename "$SHIRABE_BIN")"
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
#
# The GNU packages replace busybox's applets of the same names. No host shirabe
# supports has a busybox userland, so without them a suite using a GNU or BSD
# flag (grep --include, ps -o pgid=) fails here for a reason that says nothing
# about bash 3.2. They go on top of bash:3.2 rather than a rebase onto a glibc
# distribution: that image is the maintained bash 3.2 build, it is Alpine
# only, and the static musl shirabe the plan and execute suites need already
# runs on it. The base image keeps its bash in /usr/local/bin only, while
# every supported host has a /bin/bash that a #!/bin/bash stub or a
# PATH=/usr/bin:/bin run relies on, so the 3.2 binary is linked there too.
# None of the packages pulls in Alpine's own bash, and the last step
# fails the build if any bash on PATH is not 3.2, since a floor image that
# quietly carried a newer one would pass everything.
#
# yq is the mikefarah v4 release binary, the same version check-templates.yml
# pins, checked against the SHA-256 that release's checksums file records.
# Alpine's own package is not used: its name and version move with the base
# image, and the decider-declarations check needs mikefarah's v4 syntax.
FLOOR_YQ_VERSION="v4.47.1"
FLOOR_YQ_SHA256_AMD64="0fb28c6680193c41b364193d0c0fc4a03177aecde51cfc04d506b1517158c2fb"
FLOOR_YQ_SHA256_ARM64="b7f7c991abe262b0c6f96bbcb362f8b35429cefd59c8b4c2daa4811f1e9df599"

FLOOR_PACKAGES="jq git python3 coreutils grep sed findutils gawk diffutils procps-ng"

# The floor runs whatever test code the branch under check carries. On a
# rootful daemon everything the daemon does for a container - creating a
# missing mount point, writing through a mount, the container's own root - is
# done as the host's root, which is how #413's root-owned files got into a
# checkout. The read-only mount and --user close the paths #413 names, so a
# rootful daemon, the one stock Docker installs and CI's hosted runners have,
# is used by default. A rootless daemon closes the class, since nothing it does
# can reach past the invoking user, so a rootful run recommends it, and
# --require-rootless turns the recommendation into a refusal on hosts whose
# rule is rootless containers only.
#
# Which daemon is reached is DOCKER_HOST's (or the docker context's) choice,
# not this script's.
check_docker_daemon() {
    local opts
    command -v docker >/dev/null 2>&1 || die "docker is required for the docker backend (on macOS use --backend system: /bin/bash is already 3.2)"
    opts=$(docker info --format '{{json .SecurityOptions}}' 2>/dev/null) \
        || die "cannot reach a docker daemon (DOCKER_HOST=${DOCKER_HOST:-unset})"
    case "$opts" in
        *name=rootless*)
            DAEMON_ROOTLESS=1
            ;;
        *)
            DAEMON_ROOTLESS=0
            if [ "$REQUIRE_ROOTLESS" = 1 ]; then
                die "refusing a rootful docker daemon (DOCKER_HOST=${DOCKER_HOST:-unset}): --require-rootless (or SHIRABE_FLOOR_REQUIRE_ROOTLESS=1) is set; point DOCKER_HOST at a rootless daemon's socket"
            fi
            echo "check-bash-floor: rootful docker daemon; the container runs as $(id -u):$(id -g) over a read-only checkout (a rootless daemon also keeps the daemon's own work off the host's root)" >&2
            ;;
    esac
}

# Besides building the image, this settles what every run_suite_docker call
# relies on: DAEMON_ROOTLESS (check_docker_daemon) and GIT_MOUNT_DIRS
# (resolve_git_mounts). A change that skips the build, for a cached image say,
# must still run these, or the #413 worktree failure comes back silently.
build_floor_image() {
    check_docker_daemon
    # The container's user is the invoking user on either daemon, and git
    # refuses a repository that user doesn't own, which would fail every git
    # call in the suites or leave a check silently checking nothing. So
    # ownership is checked here, before anything runs.
    [ -O "$REPO_ROOT" ] || die "$REPO_ROOT is not owned by the invoking user ($(id -un)); git inside the floor container would refuse it. Run the floor as the checkout's owner"
    # Before the build, so a checkout the container could not resolve is
    # refused before anything is pulled or built.
    resolve_git_mounts
    echo "check-bash-floor: building $FLOOR_IMAGE" >&2
    docker build -q -t "$FLOOR_IMAGE" - >/dev/null <<EOF || die "could not build $FLOOR_IMAGE from $BASE_IMAGE"
FROM $BASE_IMAGE
RUN apk add --no-cache $FLOOR_PACKAGES
RUN ln -s /usr/local/bin/bash /bin/bash
RUN case "\$(uname -m)" in \\
        x86_64) a=amd64; s=$FLOOR_YQ_SHA256_AMD64 ;; \\
        aarch64) a=arm64; s=$FLOOR_YQ_SHA256_ARM64 ;; \\
        *) echo "no pinned yq for \$(uname -m)" >&2; exit 1 ;; \\
    esac \\
    && wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/$FLOOR_YQ_VERSION/yq_linux_\$a" \\
    && echo "\$s  /usr/local/bin/yq" | sha256sum -c - \\
    && chmod +x /usr/local/bin/yq \\
    && yq --version
RUN for b in \$(which -a bash) /bin/bash /usr/bin/bash; do \\
        [ -x "\$b" ] || continue; \\
        "\$b" -c 'case "\$BASH_VERSION" in 3.2*) exit 0;; *) exit 1;; esac' \\
            || { echo "\$b is not bash 3.2" >&2; exit 1; }; \\
    done \\
    && for t in ls grep sed find awk diff; do \\
        "\$t" --version 2>&1 | head -n 1 | grep -q GNU \\
            || { echo "\$t is not the GNU one" >&2; exit 1; }; \\
    done \\
    && ps --version | grep -q procps
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

# A linked worktree's .git is a file naming its git directory, which lives in
# the main checkout's .git and so outside the mount; git inside the container
# then fails with "not a git repository" and a suite that reads the checkout's
# history fails for a reason unrelated to bash. So the directories that file
# leads to are mounted read-only at the paths it names. The paths are taken
# from the files themselves, not from `git rev-parse`, because the container
# has to find exactly what the file says, relative links included. A
# submodule's .git file works the same way, minus the commondir.
#
# Refusing linked worktrees outright (#413's first suggestion) would be
# simpler, but it would put the docker floor out of reach for anyone who works
# in worktrees, which is the usual way to run several changes side by side.
#
# Sets GIT_MOUNT_DIRS, one directory per line. A .git file that does not lead
# to a git directory on the host is refused here: the container could not
# resolve it either.
GIT_MOUNT_DIRS=""
resolve_git_mounts() {
    local dotgit="$REPO_ROOT/.git" link gitdir common d

    GIT_MOUNT_DIRS=""
    # A plain checkout's git directory is inside the mount already.
    [ -f "$dotgit" ] || return 0

    link=$(sed -n 's/^gitdir: //p' "$dotgit" | head -n 1)
    [ -n "$link" ] || die "$dotgit is a file with no 'gitdir:' line, so git inside the container cannot find this checkout's repository"
    case "$link" in
        /*) ;;
        *) link="$REPO_ROOT/$link" ;;
    esac
    gitdir=$(CDPATH= cd "$link" 2>/dev/null && pwd) && [ -f "$gitdir/HEAD" ] \
        || die "$dotgit points at $link, which is not a git directory on this host (a moved or pruned worktree?); run 'git worktree repair' from the main checkout, or run the floor from a checkout whose .git resolves"

    common="$gitdir"
    if [ -f "$gitdir/commondir" ]; then
        link=$(head -n 1 "$gitdir/commondir")
        case "$link" in
            /*) ;;
            *) link="$gitdir/$link" ;;
        esac
        common=$(CDPATH= cd "$link" 2>/dev/null && pwd) && [ -d "$common/objects" ] \
            || die "$gitdir/commondir points at $link, which is not a git directory on this host; run 'git worktree repair' from the main checkout"
    fi

    for d in "$common" "$gitdir"; do
        case "$d/" in
            "$REPO_ROOT"/*) continue ;;
        esac
        if [ "$d" != "$common" ]; then
            case "$d/" in
                "$common"/*) continue ;;
            esac
        fi
        GIT_MOUNT_DIRS="$GIT_MOUNT_DIRS$d
"
    done
}

# bind_ro <source> [<target>]: sets BIND_RO_RESULT to a --mount value binding
# <source> read-only at <target> (default: the same path). The checkout
# sits at its host path, which may hold a colon that -v and --tmpfs would split
# on; --mount only splits on commas, so a comma is refused rather than
# misparsed.
BIND_RO_RESULT=""
bind_ro() {
    local src="$1" dst="${2:-$1}"
    case "$src$dst" in
        *,*) die "cannot mount a path containing a comma into the floor container: $src" ;;
    esac
    BIND_RO_RESULT="type=bind,source=$src,target=$dst,readonly"
}

run_suite_docker() {
    local suite="$1"
    local script status shirabe_bin stub_dir d
    # Always non-empty, so `set -u` never meets an empty array expansion -
    # which is itself a bash 3.2 trap, and this script runs on the floor too.
    local args

    [ -n "$DAEMON_ROOTLESS" ] || die "internal: run_suite_docker ran before build_floor_image checked the daemon and the git mounts"

    # Read-only: whatever user the container runs as, no suite can change a
    # file in the checkout. They write under /tmp, which is the container's
    # own and goes with it.
    bind_ro "$REPO_ROOT"
    args=(--rm --mount "$BIND_RO_RESULT")
    # GIT_MOUNT_DIRS was resolved by build_floor_image, before the build.
    while read -r d; do
        [ -n "$d" ] || continue
        bind_ro "$d"
        args=("${args[@]}" --mount "$BIND_RO_RESULT")
    done <<EOF
$GIT_MOUNT_DIRS
EOF

    # On a rootless daemon the container's root is the invoking user on the
    # host, and a --user uid would map to one of that user's subordinate ids
    # instead. On a rootful daemon root is the host's root, so the container
    # runs as the invoking user. Either way the checkout's owner is the
    # container's user, so git needs no safe.directory exception to read it.
    if [ "$DAEMON_ROOTLESS" != 1 ]; then
        args=("${args[@]}" --user "$(id -u):$(id -g)")
    fi
    # exec because suites write stand-in binaries under $HOME and run them;
    # 1777 because on a rootful daemon the container user owns nothing here.
    args=("${args[@]}" --tmpfs "$FLOOR_HOME:rw,exec,mode=1777" -e "HOME=$FLOOR_HOME" -e TMPDIR=/tmp)

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
        # The mkdir is not redundant. The checkout is mounted read-only, so
        # docker cannot create a missing mount point in it; and were it
        # writable, docker would create the directory as the daemon's root
        # on the host, leaving a target/ the next `cargo build` cannot write.
        mkdir -p "$REPO_ROOT/target"
        args=("${args[@]}" --mount "type=tmpfs,target=$REPO_ROOT/target")
        bind_ro "$shirabe_bin" "$INJECT_DIR/shirabe"
        args=("${args[@]}" --mount "$BIND_RO_RESULT")
        bind_ro "$shirabe_bin" "$REPO_ROOT/target/release/shirabe"
        args=("${args[@]}" --mount "$BIND_RO_RESULT")
        bind_ro "$stub_dir" "$INJECT_DIR/bin"
        args=("${args[@]}" --mount "$BIND_RO_RESULT")
        args=("${args[@]}" -e "SHIRABE_BIN=$INJECT_DIR/shirabe")
        args=("${args[@]}" -e "PATH=$INJECT_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    fi

    args=("${args[@]}" -w "$REPO_ROOT" "$FLOOR_IMAGE")

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
    # The full version, once, so a leg that goes red later shows at a glance
    # which bash it actually ran on.
    echo "check-bash-floor: /bin/bash is bash $(/bin/bash -c 'echo "$BASH_VERSION"')"

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
        # Machine-readable forms of --list, for tools that need the registry
        # (scripts/check-macos-floor-legs.sh). --list is for people and may
        # change shape; these print one name per line and nothing else.
        --suites)
            for suite in $SUITES; do echo "$suite"; done
            exit 0
            ;;
        --scripts)
            [ $# -ge 2 ] || die "--scripts needs a suite name (try --suites)"
            suite_scripts "$2" || die "unknown suite: $2 (try --suites)"
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
        --require-rootless)
            REQUIRE_ROOTLESS=1
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
