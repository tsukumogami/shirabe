#!/usr/bin/env bash
# check-macos-floor-legs.sh -- fail a workflow whose macOS leg runs a shell
# suite anywhere but on the bash 3.2 floor.
#
# The macOS legs of the script-check workflows exist to prove the bash 3.2
# floor, and on GitHub's macOS runners only /bin/bash is 3.2: plain `bash`, and
# a script run by path through `#!/usr/bin/env bash`, both resolve to Homebrew's
# bash 5. Legs written that way passed while a suite was broken on 3.2
# (shirabe#416). Calling /bin/bash on a harness is not enough either: a nested
# `bash` inside it still finds bash 5.
#
# The one way onto the floor is scripts/check-bash-floor.sh --backend system
# <suite>. It refuses a /bin/bash that is not 3.2, logs the version it ran on,
# and puts a shim first on PATH so every nested `bash` is 3.2 too. So, for every
# job that can run on macOS (its runs-on or its matrix names macOS):
#
#   - a step that can run on macOS -- any step whose `if` does not limit it to
#     Linux -- fails the check when it runs `bash <script>` or `/bin/bash
#     <script>`, or names a `*_test.sh` suite on any line that is not a floor
#     call (so `sudo`, `timeout`, `bash -x` and `if bash ...` forms are caught
#     too);
#   - a job that runs any `*_test.sh` suite must run check-bash-floor.sh
#     --backend system in a step that can run on macOS. A floor step limited
#     to Linux by mistake leaves the macOS leg proving nothing while it reports
#     green, and this is what catches it;
#   - every `*_test.sh` a job's Linux-only steps run must be in a suite its
#     floor step names, read from `check-bash-floor.sh --list`. The Linux
#     steps and the registry each list the scripts, and without this a harness
#     added to a Linux step would silently never reach the macOS floor.
#
# Not suite runs, so not checked: `bash -c`, and an installer piped into
# `| bash`.
#
# Usage: scripts/check-macos-floor-legs.sh [<workflow.yml>...]
#        (default: every workflow under .github/workflows/)
#
# Environment:
#   CHECK_MACOS_FLOOR_REGISTRY   a file in `check-bash-floor.sh --list` format
#                                to read instead of running it (the tests)
#
# Requires mikefarah yq v4 (to read the YAML) and python3.
#
# Exit codes:
#   0 -- no violations
#   1 -- one or more violations, each printed as file, job, step and command
#   2 -- a workflow could not be read, or a prerequisite is missing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

command -v yq >/dev/null 2>&1 || { echo "check-macos-floor-legs: yq (mikefarah v4) is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "check-macos-floor-legs: python3 is required" >&2; exit 2; }

if [ $# -eq 0 ]; then
    set -- "$REPO_ROOT"/.github/workflows/*.yml "$REPO_ROOT"/.github/workflows/*.yaml
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/check-macos-floor-legs.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

if [ -n "${CHECK_MACOS_FLOOR_REGISTRY:-}" ]; then
    cp "$CHECK_MACOS_FLOOR_REGISTRY" "$T/registry.txt" || exit 2
elif ! "$SCRIPT_DIR/check-bash-floor.sh" --list >"$T/registry.txt" 2>&1; then
    echo "check-macos-floor-legs: could not read the floor registry: $(cat "$T/registry.txt")" >&2
    exit 2
fi

status=0
for wf in "$@"; do
    # The default glob leaves a literal pattern when nothing matches it; a
    # file named on the command line that is not there is an error.
    case "$wf" in
        *'/*.yml'|*'/*.yaml') continue ;;
    esac
    if [ ! -f "$wf" ]; then
        echo "check-macos-floor-legs: no such workflow: $wf" >&2
        status=2
        continue
    fi
    if ! yq -o=json '.' "$wf" >"$T/wf.json" 2>"$T/yq.err"; then
        echo "check-macos-floor-legs: could not read $wf: $(cat "$T/yq.err")" >&2
        status=2
        continue
    fi
    rc=0
    python3 - "${wf#"$REPO_ROOT"/}" "$T/wf.json" "$T/registry.txt" <<'PY' || rc=$?
import json, re, sys

label, path, registry_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    wf = json.load(fh) or {}

# `check-bash-floor.sh --list`: a suite name indented two spaces, then its
# workflow, then its scripts indented six.
registry, current = {}, None
with open(registry_path) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if re.match(r"^  \S+$", line):
            current = line.strip()
            registry[current] = set()
        elif current and re.match(r"^      \S", line):
            registry[current].add(line.strip())
        elif not line.strip():
            current = None

# A command position: the start of a line, or after &&, ||, ;, a subshell or
# group opener, or a then/do/else. A single | is deliberately absent, so an
# installer piped into `| bash` is not read as a suite run. Leading variable
# assignments (and `env` with them) are allowed before the command.
POS = r"(?:^|&&|\|\||;|\(|\{|\bthen\b|\bdo\b|\belse\b)\s*(?:env\s+)?(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*"
# `bash -c '...'` is not a script run; any other flag still runs one (bash -e
# x.sh), so only -c is exempt.
PLAIN_BASH = re.compile(POS + r"bash\s+(?!-c\b)((?:-\S+\s+)*[^-\s]\S*)")
SYSTEM_BASH = re.compile(POS + r"/bin/bash\s+(?!-c\b)((?:-\S+\s+)*[^-\s]\S*)")
FLOOR = re.compile(POS + r"(?:\./)?scripts/check-bash-floor\.sh\b(.*)")
FLOOR_SYSTEM = re.compile(r"--backend(?:\s+|=)system\b")
ANY_SUITE = re.compile(r"(?:\./)?[\w./-]*_test\.sh\b")

# A condition limits a step to Linux only in these simple forms. Anything
# compound or negated is read as able to run on macOS: a false alarm on an odd
# condition is cheap, a missed macOS step is the defect this check exists for.
LINUX_ONLY = re.compile(
    r"^\s*(?:\$\{\{\s*)?(?:"
    r"runner\.os\s*==\s*['\"]Linux['\"]"
    r"|runner\.os\s*!=\s*['\"]macOS['\"]"
    r"|matrix\.os\s*==\s*['\"]ubuntu[\w.-]*['\"]"
    r"|startsWith\(\s*matrix\.os\s*,\s*['\"]ubuntu['\"]\s*\)"
    r")(?:\s*\}\})?\s*$")

BASH5 = ("on a macOS runner that is Homebrew's bash 5; reach the floor with "
         "scripts/check-bash-floor.sh --backend system <suite>")


def can_run_on_macos(step):
    cond = str(step.get("if") or "")
    return not (cond and LINUX_ONLY.match(cond))


def logical_lines(script):
    joined = re.sub(r"\\\n", " ", script)
    for line in joined.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            yield line


violations = []
for job_name, job in (wf.get("jobs") or {}).items():
    if not isinstance(job, dict):
        continue
    where = json.dumps([job.get("runs-on"), (job.get("strategy") or {}).get("matrix")]).lower()
    if "macos" not in where:
        continue
    runs_suites = False
    floor_suites = set()
    linux_suites = []  # (step name, script) run by Linux-only steps
    for index, step in enumerate(job.get("steps") or []):
        if not isinstance(step, dict) or not step.get("run"):
            continue
        run = str(step["run"])
        name = step.get("name") or f"step {index + 1}"
        if ANY_SUITE.search(run):
            runs_suites = True
        if not can_run_on_macos(step):
            for line in logical_lines(run):
                for m in ANY_SUITE.finditer(line):
                    script = m.group(0)
                    if script.startswith("./"):
                        script = script[2:]
                    linux_suites.append((name, script))
            continue
        for line in logical_lines(run):
            floor = FLOOR.search(line)
            if floor:
                args = floor.group(1)
                # A floor step allowed to fail proves nothing when it does.
                if FLOOR_SYSTEM.search(args) and not step.get("continue-on-error"):
                    floor_suites.update(
                        a for a in args.split()
                        if not a.startswith("-") and a != "system")
                continue
            reported = set()
            for m in PLAIN_BASH.finditer(line):
                reported.add(m.group(1).split()[-1])
                violations.append((job_name, name, f"bash {m.group(1)}",
                    "plain bash " + BASH5))
            for m in SYSTEM_BASH.finditer(line):
                reported.add(m.group(1).split()[-1])
                violations.append((job_name, name, f"/bin/bash {m.group(1)}",
                    "/bin/bash puts only this script on 3.2; a nested bash inside it is "
                    "still Homebrew's bash 5 on a macOS runner; reach the floor with "
                    "scripts/check-bash-floor.sh --backend system <suite>"))
            for m in ANY_SUITE.finditer(line):
                if m.group(0) not in reported:
                    violations.append((job_name, name, m.group(0),
                        "a suite run outside the floor runner gets whatever bash runs it, "
                        "and " + BASH5))
    if runs_suites and not floor_suites:
        violations.append((job_name, "(whole job)", "no floor step",
            "the job runs shell suites and has a macOS leg, but no step that can run "
            "on macOS runs scripts/check-bash-floor.sh --backend system <suite> "
            "(a floor step with continue-on-error does not count)"))
        continue
    for suite in sorted(floor_suites):
        if suite not in registry:
            violations.append((job_name, "(whole job)", f"floor suite {suite}",
                "check-bash-floor.sh --list has no such suite"))
    covered = set()
    for suite in floor_suites:
        covered |= registry.get(suite, set())
    for name, script in linux_suites:
        if script not in covered:
            violations.append((job_name, name, script,
                "runs on Linux in this job but is in none of its floor suites ("
                + ", ".join(sorted(floor_suites)) + "), so the macOS leg never runs it "
                "on 3.2; add it to the suite in scripts/check-bash-floor.sh"))

for job_name, name, command, why in violations:
    print(f"{label}: job {job_name}: step \"{name}\": {command}")
    print(f"    {why}")
sys.exit(1 if violations else 0)
PY
    if [ "$rc" -eq 1 ] && [ "$status" -eq 0 ]; then
        status=1
    elif [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
        status=2
    fi
done

if [ "$status" -eq 0 ]; then
    echo "check-macos-floor-legs: every macOS leg runs its suites on the bash 3.2 floor"
fi
exit "$status"
