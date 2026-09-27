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
#     Linux -- fails the check when it runs `bash <script>`, `/bin/bash
#     <script>`, or a `*_test.sh` suite by path;
#   - a job that runs any `*_test.sh` suite must run check-bash-floor.sh
#     --backend system in a step that can run on macOS. A floor step limited
#     to Linux by mistake leaves the macOS leg proving nothing while it reports
#     green, and this is what catches it.
#
# Not suite runs, so not checked: `bash -c`, and an installer piped into
# `| bash`.
#
# Usage: scripts/check-macos-floor-legs.sh [<workflow.yml>...]
#        (default: every workflow under .github/workflows/)
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

status=0
for wf in "$@"; do
    [ -f "$wf" ] || continue
    if ! yq -o=json '.' "$wf" >"$T/wf.json" 2>"$T/yq.err"; then
        echo "check-macos-floor-legs: could not read $wf: $(cat "$T/yq.err")" >&2
        status=2
        continue
    fi
    rc=0
    python3 - "${wf#"$REPO_ROOT"/}" "$T/wf.json" <<'PY' || rc=$?
import json, re, sys

label, path = sys.argv[1], sys.argv[2]
with open(path) as fh:
    wf = json.load(fh) or {}

# A command position: the start of a line, or after &&, ||, ;, a subshell or
# group opener, or a then/do/else. A single | is deliberately absent, so an
# installer piped into `| bash` is not read as a suite run. Leading variable
# assignments (and `env` with them) are allowed before the command.
POS = r"(?:^|&&|\|\||;|\(|\{|\bthen\b|\bdo\b|\belse\b)\s*(?:env\s+)?(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*"
PLAIN_BASH = re.compile(POS + r"bash\s+(?!-)(\S+)")
SYSTEM_BASH = re.compile(POS + r"/bin/bash\s+(?!-)(\S+)")
SUITE_BY_PATH = re.compile(POS + r"((?:\./)?[\w./-]*_test\.sh)\b")
FLOOR = re.compile(POS + r"(?:\./)?scripts/check-bash-floor\.sh\b.*--backend(?:\s+|=)system\b")
ANY_SUITE = re.compile(r"[\w./-]*_test\.sh\b")

LINUX_ONLY = re.compile(
    r"runner\.os\s*==\s*['\"]Linux['\"]"
    r"|runner\.os\s*!=\s*['\"]macOS['\"]"
    r"|matrix\.os\s*==\s*['\"]ubuntu"
    r"|startsWith\(\s*matrix\.os\s*,\s*['\"]ubuntu")
NAMES_MACOS = re.compile(r"==\s*['\"]macOS['\"]|matrix\.os\s*==\s*['\"]macos", re.I)

BASH5 = ("on a macOS runner that is Homebrew's bash 5; reach the floor with "
         "scripts/check-bash-floor.sh --backend system <suite>")


def can_run_on_macos(step):
    cond = str(step.get("if") or "")
    if not cond:
        return True
    return not LINUX_ONLY.search(cond) or bool(NAMES_MACOS.search(cond))


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
    reaches_floor = False
    for index, step in enumerate(job.get("steps") or []):
        if not isinstance(step, dict) or not step.get("run"):
            continue
        run = str(step["run"])
        if ANY_SUITE.search(run):
            runs_suites = True
        if not can_run_on_macos(step):
            continue
        name = step.get("name") or f"step {index + 1}"
        for line in logical_lines(run):
            if FLOOR.search(line):
                reaches_floor = True
                continue
            for m in PLAIN_BASH.finditer(line):
                violations.append((job_name, name, f"bash {m.group(1)}",
                    "plain bash " + BASH5))
            for m in SYSTEM_BASH.finditer(line):
                violations.append((job_name, name, f"/bin/bash {m.group(1)}",
                    "/bin/bash puts only this script on 3.2; a nested bash inside it is "
                    "still Homebrew's bash 5 on a macOS runner; reach the floor with "
                    "scripts/check-bash-floor.sh --backend system <suite>"))
            for m in SUITE_BY_PATH.finditer(line):
                violations.append((job_name, name, m.group(1),
                    "a suite run by path gets its shebang's bash, and " + BASH5))
    if runs_suites and not reaches_floor:
        violations.append((job_name, "(whole job)", "no floor step",
            "the job runs shell suites and has a macOS leg, but no step that can run "
            "on macOS runs scripts/check-bash-floor.sh --backend system"))

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
