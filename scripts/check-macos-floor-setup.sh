#!/usr/bin/env bash
# check-macos-floor-setup.sh -- keep macos-floor.yml's per-suite setup the
# same as each suite's own workflow, and list the suites it runs.
#
# macos-floor.yml runs every macOS floor suite on main once a day, and on any
# ref when dispatched, because pull requests merge without waiting for their
# macOS legs (shirabe#940). It runs each suite in a matrix job, so it has to
# give each one the setup its own workflow's macOS leg gives it: the preflight
# suite needs a shirabe build, koto and niwa, the plan suite a Rust toolchain.
# Those steps are copies, and a copy drifts when someone changes the original.
# This check fails the pull request that lets them drift.
#
# A floor workflow is any workflow but macos-floor.yml with a job that can run
# on macOS and a step that can run there calling
# scripts/check-bash-floor.sh --backend system <suite>. The rules for "can run
# on macOS" are check-macos-floor-legs.sh's. A suite's setup is the steps of
# that job that can run on macOS and come before its floor call, less any
# actions/checkout step, compared by everything but their name and condition.
#
# In macos-floor.yml's floor job (the one whose floor call names its suite at
# run time), a setup step with no `if` applies to every suite, and a step whose
# `if` is `matrix.suite == '<suite>'` clauses joined by `||` applies to those
# suites. Any other condition fails the check, since it can't be mapped to
# suites. For every suite, the steps that apply to it must equal its own
# setup, in order; the env macos-floor.yml's floor step sees (its own, the
# job's and the workflow's) must hold every variable the suite's own floor
# step sees; and the two floor steps must set the same shell,
# working-directory and timeout. macos-floor.yml checks out the commit it
# resolved, with full history for every suite, which covers a suite whose own
# checkout asks for it, so a checkout's ref and fetch-depth are left out and
# its other inputs must match.
#
# A floor call that names its suite at run time is allowed only in
# macos-floor.yml, the one workflow whose suites this checks;
# check-macos-floor-legs.sh can't read such a suite either.
#
# The same parse gives macos-floor.yml its matrix (--suites), so the suites
# it runs and the suites this checks can't disagree, and gives
# cancel-closed-pr-macos-runs.yml the workflows whose runs it cancels when a
# pull request closes (--workflows), so a new floor workflow is covered there
# without an edit too.
#
# Usage:
#   scripts/check-macos-floor-setup.sh            check macos-floor.yml
#   scripts/check-macos-floor-setup.sh --suites   print the floor suites as a
#                                                 JSON array (macos-floor.yml's
#                                                 matrix)
#   scripts/check-macos-floor-setup.sh --workflows
#                                                 print the file names of the
#                                                 workflows that run them, as a
#                                                 JSON array (macos-floor.yml
#                                                 itself is never one)
#
# Environment:
#   CHECK_MACOS_FLOOR_SETUP_DIR   the workflows directory to read (the tests);
#                                 default .github/workflows
#
# Requires mikefarah yq v4 (to read the YAML) and python3.
#
# Exit codes:
#   0 -- the setups match (or, with --suites or --workflows, the list was
#        printed)
#   1 -- one or more mismatches, each printed with the suite and the steps
#   2 -- a workflow could not be read, no floor suite was found, or a
#        prerequisite is missing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WF_DIR="${CHECK_MACOS_FLOOR_SETUP_DIR:-$REPO_ROOT/.github/workflows}"

MODE=check
case "${1:-}" in
    "") ;;
    --suites) MODE=suites ;;
    --workflows) MODE=workflows ;;
    *) echo "usage: check-macos-floor-setup.sh [--suites|--workflows]" >&2; exit 2 ;;
esac

command -v yq >/dev/null 2>&1 || { echo "check-macos-floor-setup: yq (mikefarah v4) is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "check-macos-floor-setup: python3 is required" >&2; exit 2; }
[ -d "$WF_DIR" ] || { echo "check-macos-floor-setup: no workflows directory: $WF_DIR" >&2; exit 2; }

T=$(mktemp -d "${TMPDIR:-/tmp}/check-macos-floor-setup.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

mkdir "$T/json" || exit 2
for wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
    [ -f "$wf" ] || continue
    base=$(basename "$wf")
    if ! yq -o=json '.' "$wf" >"$T/json/$base.json" 2>"$T/yq.err"; then
        echo "check-macos-floor-setup: could not read $wf: $(cat "$T/yq.err")" >&2
        exit 2
    fi
done

python3 - "$MODE" "$T/json" <<'PY'
import json, os, re, sys

mode, json_dir = sys.argv[1], sys.argv[2]
# The safety net: the one workflow that runs every floor suite after merge.
NET = "macos-floor.yml"

workflows = {}
for name in sorted(os.listdir(json_dir)):
    with open(os.path.join(json_dir, name)) as fh:
        workflows[name[: -len(".json")]] = json.load(fh) or {}

# The same reading of "can run on macOS", and of a floor call, as
# check-macos-floor-legs.sh; a change to either file's rules belongs in both.
LINUX_ONLY = re.compile(
    r"^\s*(?:\$\{\{\s*)?(?:"
    r"runner\.os\s*==\s*['\"]Linux['\"]"
    r"|runner\.os\s*!=\s*['\"]macOS['\"]"
    r"|matrix\.os\s*==\s*['\"]ubuntu[\w.-]*['\"]"
    r"|startsWith\(\s*matrix\.os\s*,\s*['\"]ubuntu['\"]\s*\)"
    r")(?:\s*\}\})?\s*$")
FLOOR = re.compile(r"(?:^|&&|\|\||;)\s*(?:\./)?scripts/check-bash-floor\.sh\b([^#;&|]*)")
FLOOR_SYSTEM = re.compile(r"--backend(?:\s+|=)system\b")
SUITE_CLAUSE = r"matrix\.suite\s*==\s*'([a-z0-9-]+)'"
SUITE_IF = re.compile(r"^\s*(?:\$\{\{\s*)?" + SUITE_CLAUSE
                      + r"(?:\s*\|\|\s*" + SUITE_CLAUSE + r")*(?:\s*\}\})?\s*$")
COMPARED = ("uses", "run", "with", "env", "shell", "working-directory",
            "continue-on-error", "timeout-minutes")
FLOOR_STEP_KEYS = ("shell", "working-directory", "timeout-minutes")
# macos-floor.yml checks out the commit it resolved, with full history.
CHECKOUT_IGNORED = ("ref", "fetch-depth")


def macos_job(job):
    where = json.dumps([job.get("runs-on"), (job.get("strategy") or {}).get("matrix")]).lower()
    return "macos" in where


def can_run_on_macos(step):
    cond = str(step.get("if") or "")
    return not (cond and LINUX_ONLY.match(cond))


def floor_suites(step):
    """The suites a step's floor calls name, or None when it makes none. A
    suite named at run time comes back as "$"."""
    if not step.get("run") or step.get("continue-on-error"):
        return None
    found = None
    for line in re.sub(r"\\\n", " ", str(step["run"])).splitlines():
        m = FLOOR.search(line.strip())
        if not m or not FLOOR_SYSTEM.search(m.group(1)):
            continue
        found = found or []
        for a in re.sub(r"\$\{\{.*?\}\}", "$", m.group(1)).split():
            if a.startswith("-") or a == "system":
                continue
            found.append("$" if "$" in a else a)
    return found


def is_checkout(step):
    return str(step.get("uses") or "").startswith("actions/checkout@")


def norm(step):
    return {k: step[k] for k in COMPARED if k in step}


def floor_extras(step):
    """What the floor step itself sets, besides its command and env."""
    return {k: step[k] for k in FLOOR_STEP_KEYS if k in step}


def checkout_with(step):
    return {k: v for k, v in (step.get("with") or {}).items() if k not in CHECKOUT_IGNORED}


def env_of(wf, job, step):
    """The env the floor step sees: the workflow's, the job's and its own."""
    env = dict(wf.get("env") or {})
    env.update(job.get("env") or {})
    env.update(step.get("env") or {})
    return env


# Every floor suite outside macos-floor.yml, with the setup its own job gives it.
suites = {}
# The workflows those suites run in.
floor_workflows = set()
problems = []
for wf_name, wf in workflows.items():
    if wf_name == NET:
        continue
    for job_name, job in (wf.get("jobs") or {}).items():
        if not isinstance(job, dict) or not macos_job(job):
            continue
        setup = []
        checkout = {}
        for step in job.get("steps") or []:
            if not isinstance(step, dict) or not can_run_on_macos(step):
                continue
            named = floor_suites(step)
            if named is None:
                if is_checkout(step):
                    checkout = checkout_with(step)
                else:
                    setup.append(norm(step))
                continue
            for suite in named:
                if suite == "$":
                    # check-macos-floor-legs.sh can't read such a suite either,
                    # so only macos-floor.yml, whose suites this checks, may.
                    problems.append(("(run time)", f"{wf_name} job {job_name} names its floor "
                                     f"suite at run time; only {NET} may"))
                    continue
                if suite == "all":
                    continue
                entry = {"where": f"{wf_name} job {job_name}", "setup": list(setup),
                         "env": env_of(wf, job, step), "floor": floor_extras(step),
                         "checkout": checkout}
                key = ("setup", "env", "floor", "checkout")
                prior = suites.get(suite)
                if prior and [prior[k] for k in key] != [entry[k] for k in key]:
                    problems.append((suite, f"runs in {prior['where']} and in {entry['where']} "
                                     "with different setups; macos-floor.yml can copy only one"))
                suites.setdefault(suite, entry)
                floor_workflows.add(wf_name)

if not suites:
    print("check-macos-floor-setup: no workflow runs a macOS floor suite", file=sys.stderr)
    sys.exit(2)

if mode == "suites":
    print(json.dumps(sorted(suites)))
    sys.exit(0)
if mode == "workflows":
    print(json.dumps(sorted(floor_workflows)))
    sys.exit(0)

net = workflows.get(NET)
if net is None:
    print(f"check-macos-floor-setup: {NET} is missing, so no suite runs after merge")
    sys.exit(1)

floor_jobs = []
for job_name, job in (net.get("jobs") or {}).items():
    if not isinstance(job, dict):
        continue
    for i, step in enumerate(job.get("steps") or []):
        if isinstance(step, dict) and "$" in (floor_suites(step) or []):
            floor_jobs.append((job_name, job, i))
            break
if len(floor_jobs) != 1:
    print(f"check-macos-floor-setup: {NET} must have exactly one job whose floor call "
          f"names its suite at run time; found {len(floor_jobs)}")
    sys.exit(1)
job_name, job, floor_at = floor_jobs[0]

# Which suites each of the floor job's setup steps applies to.
net_steps = []
net_checkout = {}
for step in (job.get("steps") or [])[:floor_at]:
    if not isinstance(step, dict):
        continue
    if is_checkout(step):
        net_checkout = checkout_with(step)
        continue
    label = step.get("name") or json.dumps(norm(step))[:60]
    cond = step.get("if")
    if cond is None:
        applies = set(suites)
    else:
        m = SUITE_IF.match(str(cond))
        if not m:
            problems.append(("(any)", f"step \"{label}\": condition {cond!r} is not "
                             "matrix.suite == '<suite>' clauses joined by ||; write it as "
                             "matrix.suite == 'a' || matrix.suite == 'b'"))
            continue
        applies = set(re.findall(SUITE_CLAUSE, str(cond)))
        for stale in sorted(applies - set(suites)):
            problems.append((stale, f"step \"{label}\" names a suite no workflow runs on "
                             "the macOS floor"))
    net_steps.append((applies, norm(step)))

net_floor = job["steps"][floor_at]
net_env = env_of(net, job, net_floor)
for suite in sorted(suites):
    own = suites[suite]
    have = [s for applies, s in net_steps if suite in applies]
    if have != own["setup"]:
        problems.append((suite, f"setup differs from {own['where']}\n"
                         f"      own:         {json.dumps(own['setup'])}\n"
                         f"      macos-floor: {json.dumps(have)}\n"
                         f"      fix: make the floor job's steps whose `if` names '{suite}' "
                         "(and those with no `if`) match the own list, in the same order; "
                         "names and conditions aren't compared"))
    for key, value in sorted(own["env"].items()):
        if net_env.get(key) != value:
            problems.append((suite, f"{own['where']} sets env {key}={value!r}; "
                             f"{NET} job {job_name} does not"))
    if own["floor"] != floor_extras(net_floor):
        problems.append((suite, f"the floor step in {own['where']} sets "
                         f"{json.dumps(own['floor'])}; {NET}'s sets "
                         f"{json.dumps(floor_extras(net_floor))}"))
    if own["checkout"] != net_checkout:
        problems.append((suite, f"the checkout in {own['where']} has "
                         f"{json.dumps(own['checkout'])}; {NET}'s has "
                         f"{json.dumps(net_checkout)} (ref and fetch-depth aside)"))

for suite, why in problems:
    print(f"{NET}: suite {suite}: {why}")
if problems:
    sys.exit(1)
print(f"check-macos-floor-setup: {NET} gives all {len(suites)} floor suites their own setup")
PY
