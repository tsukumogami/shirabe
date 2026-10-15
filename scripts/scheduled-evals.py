#!/usr/bin/env python3
"""scheduled-evals.py - the scheduled eval measurement, off the release path.

The release eval check (scripts/release-eval-check.sh) runs each changed skill
once, on Sonnet, and of its tier-2 scenarios only the release subset: the one
each behaviour marks "release": true. What it no longer runs happens here, on a
schedule the operator sets up (cron or a scheduled agent), within a weekly
budget: repeat runs of the release subset, which measure the noise a single
run carries, and a rotation through the other tier-2 scenarios, so none goes
permanently unrun. See docs/spikes/SPIKE-release-eval-cost.md.

Usage:
  scripts/scheduled-evals.py [--runs <N>] [--rotation-size <K>] [--model <name>]
      [--cap-usd <amount>] [--ledger <file>] [--dry-run] [<skill>...]

A run:
  1. Takes the named skills, or every skill with skills/<name>/evals/evals.json.
     Run it from an up-to-date checkout of the default branch.
  2. Plans two kinds of job. A repeat job runs a skill's release subset
     (scripts/run-evals.sh --release-subset) --runs times. It is due when the
     skill has no graded repeat on this model, or the last one measured another
     skills/<name>/ tree: something in the skill changed since. A rotation job
     runs up to --rotation-size of the skill's tier-2 scenarios outside the
     release subset, once. A scenario is due when no graded rotation on this
     model ran it at the current tree; never-run scenarios go first, then the
     longest since run. "Graded" means harness exit 0 or 1.
  3. Takes the jobs longest-waiting first, both kinds in one queue: never run,
     then the oldest last run (a rotation waits as long as its longest-waiting
     scenario). Since a stop at the cap ends the run, this is what keeps a
     run of skill changes from holding the rotation off indefinitely.
  4. Before each job, adds up what the ledger's runs cost over the last seven
     days and estimates the job: the skill's last measured cost per run (a
     repeat) or per scenario (a rotation) on the same model, or, with none,
     the per-scenario rates below. It shrinks the job to what the budget
     allows (fewer runs, fewer scenarios); when not even one fits under
     --cap-usd it stops, writes a cap_stop line naming the jobs left, and
     exits 6. A job's real cost can exceed its estimate, so the last job can
     carry the week past the cap; the next run sees that and stops sooner.
  5. Runs the harness with EVAL_MODEL=<model> and --summary-out, and appends a
     line to the ledger with the cost the summary reports (the nested
     sessions' own total_cost_usd). A job that reported no cost is ledgered at
     its estimate, marked "cost_measured": false, so the budget still counts it.

The ledger is JSON Lines, one object per line, read by the next run:
  {"kind": "run", "at": <UTC ISO-8601>, "skill", "tree", "head", "runs",
   "model", "cost_usd", "cost_measured", "estimate_usd", "exit_code",
   "assertions_passed", "assertions_graded"}
  {"kind": "rotation", the same fields, plus "scenarios": [<name>...]}
  {"kind": "cap_stop", "at", "spent_usd", "cap_usd", "next_job",
   "estimate_usd", "unrun": [<skill> or <skill>:rotation...]}
The ledger is read strictly, since a line it can't account for could hide
spend. Any of these stops the run with exit 3 before another job starts:
  - a file that isn't UTF-8 text;
  - a last line with no newline (a write cut off);
  - a line that doesn't parse as JSON, or isn't an object;
  - a "kind" other than "run", "rotation" or "cap_stop";
  - a line, of any kind, without a valid "at";
  - a run or rotation line without a valid "cost_usd" (a non-negative finite
    number).
Blank lines are skipped. The run stays stopped until a person repairs the
ledger: find what the line's job cost and correct the line, or replace it with
a line carrying that cost. Deleting it would count that spend as nothing.
A dry run reads the ledger without the lock, so a real run appending at that
moment can show it a partial last line; run it again. Default location:
$XDG_STATE_HOME/shirabe/scheduled-evals.jsonl, else
$HOME/.local/state/shirabe/scheduled-evals.jsonl. A lock directory next to it
(<ledger>.lock) keeps two runs from overlapping.

Options:
  --runs <N>           repeat runs per changed skill, 1 to 9 (default 3)
  --rotation-size <K>  rotation scenarios per skill per run, 0 to 20 (default
                       3); 0 turns the rotation off
  --model <name>       EVAL_MODEL for the harness (default sonnet, the release
                       check's model, so the repeats measure the noise of what
                       a release runs)
  --cap-usd <n>        weekly budget in US dollars at list price (default 50,
                       or SHIRABE_EVAL_WEEKLY_CAP_USD)
  --ledger <file>      the ledger to read and append to
  --dry-run            print what would run, with estimates; run and write
                       nothing

Environment:
  SHIRABE_EVAL_WEEKLY_CAP_USD  the default for --cap-usd
  SCHEDULED_EVALS_HARNESS      TEST-ONLY: the harness to call instead of
                               scripts/run-evals.sh

Exit codes:
  0  every planned job ran with harness exit 0, or nothing was due
  1  at least one harness run exited non-zero; each is in the ledger
  2  usage
  3  another run holds the lock, the ledger can't be trusted, or the checkout
     can't be read
  6  stopped at the weekly cap with jobs left to run
"""

import argparse
import datetime
import glob
import json
import math
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILL_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
# The pattern scripts/run-evals.sh holds EVAL_MODEL to.
MODEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")
WEEK = datetime.timedelta(days=7)
GRADED = (0, 1)

# What a job costs before a skill has a measured one of its own, at list price
# with the no-skill baseline and grading, from the spike report's measurements
# moved to Sonnet (half of Opus on every token class): a tier-1 scenario $0.29
# with the skill + $0.10 baseline + half of $0.145 grading; a tier-2 one
# ($2.96 + $1.35) / 2 + half of $0.24; the orchestrating session about $2.50 a
# run. Any other model is taken at Opus's rates, twice these: an overestimate
# for a smaller model, which errs toward stopping early.
SONNET_RATES = {"tier1": 0.46, "tier2": 2.28, "session": 2.50}


class UsageError(Exception):
    pass


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def iso(moment):
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(text):
    try:
        return datetime.datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc)
    except (TypeError, ValueError):
        return None


def default_ledger():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "shirabe", "scheduled-evals.jsonl")


class LedgerError(Exception):
    """The ledger can't be trusted to say what the week has cost."""


def read_ledger(path):
    """Every entry, or LedgerError. Fails closed: a line it can't account for
    could be spend, and counting it as nothing would let the cap through."""
    entries = []
    if not os.path.exists(path):
        return entries
    with open(path, "rb") as fh:
        raw = fh.read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise LedgerError("%s is not UTF-8 text" % path)
    lines = text.split("\n")
    # A file that doesn't end in a newline ends in a line cut off mid-append:
    # a job that crashed while ledgering its cost. Its cost isn't knowable, so
    # it is refused rather than read as $0.
    if lines and lines[-1] != "":
        raise LedgerError("%s ends in a partial line (line %d, no newline): a ledger "
                          "write was cut off" % (path, len(lines)))
    for number, line in enumerate(lines[:-1], 1):
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            raise LedgerError("%s line %d doesn't parse" % (path, number))
        if not isinstance(entry, dict) or entry.get("kind") not in ("run", "rotation", "cap_stop"):
            raise LedgerError("%s line %d is not a run, rotation or cap_stop entry" % (path, number))
        if parse_iso(entry.get("at")) is None:
            raise LedgerError("%s line %d has no valid `at` time" % (path, number))
        if entry["kind"] in ("run", "rotation") and not is_cost(entry.get("cost_usd")):
            raise LedgerError("%s line %d has no valid `cost_usd`" % (path, number))
        entries.append(entry)
    return entries


def append_ledger(path, entry):
    # The whole line to an O_APPEND descriptor, looping until every byte is
    # written. If the process dies part-way, the ledger ends in a partial line
    # with no newline, which read_ledger refuses rather than reads as $0.
    data = (json.dumps(entry, sort_keys=True) + "\n").encode("utf-8")
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        while data:
            data = data[os.write(fd, data):]
    finally:
        os.close(fd)


def is_cost(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value >= 0)


def spent_this_week(entries, moment):
    total = 0.0
    for entry in entries:
        if entry.get("kind") not in ("run", "rotation") or not is_cost(entry.get("cost_usd")):
            continue
        at = parse_iso(entry.get("at"))
        if at is not None and moment - at < WEEK:
            total += entry["cost_usd"]
    return total


def git(*args):
    proc = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


class Suite:
    """A skill's scenarios, split the way the release check splits them."""

    def __init__(self, skill):
        with open(os.path.join(ROOT, "skills", skill, "evals", "evals.json")) as fh:
            evals = json.load(fh)["evals"]
        self.tier1 = []
        self.release = []
        self.rest = []
        for entry in evals:
            name = entry.get("name", "eval-%s" % entry.get("id"))
            if entry.get("tier", 1) == 1:
                self.tier1.append(name)
            elif entry.get("release") is True:
                self.release.append(name)
            else:
                self.rest.append(name)


def factor(model):
    return 1.0 if model == "sonnet" else 2.0


def measured_entries(entries, kind, model):
    return [e for e in entries if e.get("kind") == kind and e.get("model") == model]


def repeat_estimate(suite, entries, model):
    """(dollars per run, what the figure rests on)

    The skill's last measured cost per run on this model, but never less than
    the default-rate figure: a measured $0 would otherwise grant every run
    whatever the week has spent.
    """
    floor = factor(model) * (len(suite.tier1) * SONNET_RATES["tier1"]
                             + len(suite.release) * SONNET_RATES["tier2"] + SONNET_RATES["session"])
    basis = "%d tier-1 and %d release tier-2 scenarios at the default rates" % (
        len(suite.tier1), len(suite.release))
    for entry in reversed(measured_entries(entries, "run", model)):
        runs = entry.get("runs")
        if entry.get("cost_measured") is True and is_cost(entry.get("cost_usd")) \
                and isinstance(runs, int) and runs > 0:
            measured = entry["cost_usd"] / runs
            if measured >= floor:
                return measured, "its last measured run"
            return floor, basis + ", above its last measured run"
    return floor, basis


def rotation_estimate(entries, model, size):
    """(dollars for a rotation of `size` scenarios, what the figure rests on)

    The skill's last measured cost per rotated scenario on this model, but
    never less than the default figure (a session plus the tier-2 rate per
    scenario), for the same reason as repeat_estimate.
    """
    floor = factor(model) * (SONNET_RATES["session"] + size * SONNET_RATES["tier2"])
    for entry in reversed(measured_entries(entries, "rotation", model)):
        names = entry.get("scenarios")
        if entry.get("cost_measured") is True and is_cost(entry.get("cost_usd")) \
                and isinstance(names, list) and names:
            measured = size * entry["cost_usd"] / len(names)
            if measured >= floor:
                return measured, "its last measured rotation"
            return floor, "the default tier-2 rate, above its last measured rotation"
    return floor, "the default tier-2 rate"


def selected_skills(names):
    if names:
        for name in names:
            if not SKILL_RE.match(name):
                raise UsageError("invalid skill name")
            if not os.path.isfile(os.path.join(ROOT, "skills", name, "evals", "evals.json")):
                raise UsageError("skills/%s has no evals/evals.json" % name)
        return sorted(set(names))
    found = glob.glob(os.path.join(ROOT, "skills", "*", "evals", "evals.json"))
    return sorted(n for n in (p.split(os.sep)[-3] for p in found) if SKILL_RE.match(n))


def read_summary(path, skill):
    try:
        with open(path) as fh:
            entry = json.load(fh)["skills"][skill]
        return entry if isinstance(entry, dict) else None
    except (OSError, ValueError, KeyError, TypeError):
        return None


def run(args):
    if not 1 <= args.runs <= 9:
        raise UsageError("--runs must be 1 to 9")
    if not 0 <= args.rotation_size <= 20:
        raise UsageError("--rotation-size must be 0 to 20")
    if not MODEL_RE.match(args.model):
        raise UsageError("--model must match ^[A-Za-z0-9][A-Za-z0-9._:-]*$")
    if not is_cost(args.cap_usd):
        raise UsageError("--cap-usd must be a non-negative amount")
    skills = selected_skills(args.skills)
    head = git("rev-parse", "HEAD")
    if head is None:
        print("error: %s is not a git checkout" % ROOT, file=sys.stderr)
        return 3
    ledger = args.ledger
    if args.dry_run:
        return measure_or_refuse(args, skills, head, ledger)
    os.makedirs(os.path.dirname(os.path.abspath(ledger)), exist_ok=True)
    lock = ledger + ".lock"
    try:
        os.mkdir(lock)
    except FileExistsError:
        print("error: another scheduled run holds %s; if none is running, remove it" % lock,
              file=sys.stderr)
        return 3
    try:
        return measure_or_refuse(args, skills, head, ledger)
    finally:
        os.rmdir(lock)


def measure_or_refuse(args, skills, head, ledger):
    try:
        return measure(args, skills, head, ledger)
    except LedgerError as exc:
        print("error: %s. No further job was run, and scheduled runs stay stopped until "
              "the ledger reads. Find what that line's run cost and correct the line, or "
              "replace it with a run line carrying that cost; deleting it would count the "
              "spend as nothing." % exc, file=sys.stderr)
        return 3


def plan_jobs(args, skills, entries):
    """[(kind, sort key, skill, tree, suite, scenarios)] in the order they run."""
    repeats = []
    rotations = []
    for name in skills:
        tree = git("rev-parse", "HEAD:skills/%s" % name)
        if tree is None:
            raise RuntimeError("cannot read the tree of skills/%s at HEAD" % name)
        suite = Suite(name)
        mine = [e for e in entries if e.get("skill") == name and e.get("model") == args.model
                and e.get("exit_code") in GRADED]
        graded = [e for e in mine if e.get("kind") == "run"]
        if graded and graded[-1].get("tree") == tree:
            print("unchanged: %s (measured %s on %s)" % (name, graded[-1].get("at", "?"), args.model))
        else:
            last_at = parse_iso(graded[-1].get("at")) if graded else None
            repeats.append(("run", (last_at is not None, last_at or now_utc(), 0, name), name,
                            tree, suite, None))
        if args.rotation_size == 0 or not suite.rest:
            continue
        last_run = {}
        for entry in mine:
            if entry.get("kind") != "rotation" or not isinstance(entry.get("scenarios"), list):
                continue
            for scenario in entry["scenarios"]:
                last_run[scenario] = entry
        due = [s for s in suite.rest
               if s not in last_run or last_run[s].get("tree") != tree]
        if not due:
            continue
        order = {s: i for i, s in enumerate(suite.rest)}

        def last_rotated(scenario):
            return parse_iso(last_run[scenario].get("at")) if scenario in last_run else None

        due.sort(key=lambda s: (last_rotated(s) is not None, last_rotated(s) or now_utc(), order[s]))
        picked = due[:args.rotation_size]
        at = last_rotated(picked[0])
        rotations.append(("rotation", (at is not None, at or now_utc(), 1, name), name, tree,
                          suite, picked))
    # One queue, longest-waiting first: a job never run before, then the one
    # whose last run is oldest, a repeat ahead of a rotation on a tie. A stop at
    # the cap ends the run, so ordering repeats ahead of every rotation would
    # let a week of skill changes keep the rotation from ever running.
    return sorted(repeats + rotations, key=lambda job: job[1])


def measure(args, skills, head, ledger):
    entries = read_ledger(ledger)
    try:
        jobs = plan_jobs(args, skills, entries)
    except RuntimeError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 3
    spent = spent_this_week(entries, now_utc())
    print("spent in the last 7 days: $%.2f of $%.2f" % (spent, args.cap_usd))
    worst = 0
    for index, (kind, _, name, tree, suite, scenarios) in enumerate(jobs):
        mine = [e for e in entries if e.get("skill") == name]
        room = args.cap_usd - spent
        if kind == "run":
            per, basis = repeat_estimate(suite, mine, args.model)
            size = min(args.runs, int(room // per))
            label, cost = name, per
            what = "%d run(s) of the release subset, about $%.2f a run (%s)" % (size, per, basis)
        else:
            size, cost, basis = len(scenarios), 0.0, ""
            while size >= 1:
                cost, basis = rotation_estimate(mine, args.model, size)
                if cost <= room:
                    break
                size -= 1
            if size < 1:
                cost, basis = rotation_estimate(mine, args.model, 1)
            label = name + ":rotation"
            scenarios = scenarios[:max(size, 0)]
            what = "rotation of %s, about $%.2f (%s)" % (", ".join(scenarios), cost, basis)
        if size < 1:
            unrun = [job[2] + (":rotation" if job[0] == "rotation" else "") for job in jobs[index:]]
            print("cap: $%.2f of $%.2f spent in the last 7 days; %s needs about $%.2f. "
                  "Stopping; not run: %s" % (spent, args.cap_usd, label, cost, ", ".join(unrun)))
            if not args.dry_run:
                append_ledger(ledger, {"kind": "cap_stop", "at": iso(now_utc()),
                                       "spent_usd": round(spent, 4), "cap_usd": args.cap_usd,
                                       "next_job": label, "estimate_usd": round(cost, 4),
                                       "unrun": unrun})
            return 6
        print("%s %s: %s" % ("would run" if args.dry_run else "running", name, what))
        estimate = size * per if kind == "run" else cost
        if args.dry_run:
            spent += estimate
            continue
        if kind == "run":
            harness_args = ["--runs", str(size), "--release-subset"]
        else:
            harness_args = ["--runs", "1", "--scenario", ",".join(scenarios)]
        if run_harness(args, ledger, kind, name, tree, head, harness_args, size, estimate,
                       scenarios) != 0:
            worst = 1
        entries = read_ledger(ledger)
        spent = spent_this_week(entries, now_utc())
    return worst


def run_harness(args, ledger, kind, name, tree, head, harness_args, size, estimate, scenarios):
    harness = (os.environ.get("SCHEDULED_EVALS_HARNESS")
               or os.path.join(ROOT, "scripts", "run-evals.sh"))
    workdir = tempfile.mkdtemp(prefix="scheduled-evals.")
    summary_path = os.path.join(workdir, "summary.json")
    env = dict(os.environ, EVAL_MODEL=args.model)
    try:
        rc = subprocess.run([harness] + harness_args + ["--summary-out", summary_path, name],
                            cwd=ROOT, env=env).returncode
        summary = read_summary(summary_path, name) or {}
    finally:
        if os.path.exists(summary_path):
            os.unlink(summary_path)
        os.rmdir(workdir)
    cost = summary.get("cost_usd")
    cost_runs = summary.get("cost_runs")
    measured = (is_cost(cost) and isinstance(cost_runs, int) and not isinstance(cost_runs, bool)
                and cost_runs > 0)
    if not measured:
        cost = estimate
    attempted = summary.get("runs")
    runs = size if kind == "run" else 1
    entry = {
        "kind": kind, "at": iso(now_utc()), "skill": name, "tree": tree, "head": head,
        "runs": attempted if isinstance(attempted, int) and attempted > 0 else runs,
        "model": args.model, "cost_usd": round(cost, 4), "cost_measured": measured,
        "estimate_usd": round(estimate, 4), "exit_code": rc,
        "assertions_passed": summary.get("assertions_passed"),
        "assertions_graded": summary.get("assertions_graded"),
    }
    if kind == "rotation":
        entry["scenarios"] = list(scenarios)
    append_ledger(ledger, entry)
    print("ledgered %s %s: harness exit %d, $%.2f%s" % (
        kind, name, rc, cost, "" if measured else " (estimated: the harness reported no cost)"))
    return rc


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError(message)


def main(argv):
    parser = Parser(prog="scheduled-evals.py")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--rotation-size", type=int, default=3)
    parser.add_argument("--model", default="sonnet")
    parser.add_argument("--cap-usd", type=float, default=None)
    parser.add_argument("--ledger", default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("skills", nargs="*")
    try:
        args = parser.parse_args(argv)
        if args.cap_usd is None:
            try:
                args.cap_usd = float(os.environ.get("SHIRABE_EVAL_WEEKLY_CAP_USD") or "50")
            except ValueError:
                raise UsageError("SHIRABE_EVAL_WEEKLY_CAP_USD is not an amount")
        args.ledger = args.ledger or default_ledger()
        return run(args)
    except UsageError as exc:
        print("usage error: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
