#!/usr/bin/env python3
"""Tests for scripts/scheduled-evals.py.

Usage: python3 scripts/scheduled-evals_test.py

No model, no network. Each case copies the script into a throwaway git
repository with a skills/ tree and calls it with a stub harness
(SCHEDULED_EVALS_HARNESS) that logs its arguments and EVAL_MODEL, and writes a
run-evals-summary/v1 file from $STUB_DIR/result.<skill>:
"<exit> <passed> <graded> <cost or -> <cost runs>".
"""

import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scheduled-evals.py")

STUB = r"""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
stub = os.environ["STUB_DIR"]
with open(os.path.join(stub, "log"), "a") as fh:
    fh.write("%s model=%s\n" % (" ".join(args), os.environ.get("EVAL_MODEL", "")))
runs = int(args[args.index("--runs") + 1])
out = args[args.index("--summary-out") + 1]
skill = args[-1]
spec = "0 9 10 1.0 1"
path = os.path.join(stub, "result." + skill)
if os.path.exists(path):
    spec = open(path).read().strip()
code, passed, graded, cost, cost_runs = spec.split()
entry = {"runs": runs, "runs_passed": runs if code == "0" else 0,
         "assertions_passed": int(passed), "assertions_graded": int(graded),
         "models": ["sonnet"], "session_model": os.environ.get("EVAL_MODEL", "default"),
         "exit_code": int(code), "cost_runs": int(cost_runs)}
if cost != "-":
    entry["cost_usd"] = float(cost) * runs
if not os.path.exists(os.path.join(stub, "nosummary." + skill)):
    with open(out, "w") as fh:
        json.dump({"schema": "run-evals-summary/v1", "skills": {skill: entry}}, fh)
sys.exit(int(code))
"""


def ago(**delta):
    moment = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(**delta)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


class Case(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="scheduled-evals-test.")
        self.repo = os.path.join(self.tmp, "repo")
        self.stub = os.path.join(self.tmp, "stub")
        os.makedirs(os.path.join(self.repo, "scripts"))
        os.makedirs(self.stub)
        shutil.copy(SCRIPT, os.path.join(self.repo, "scripts", "scheduled-evals.py"))
        self.harness = os.path.join(self.tmp, "run-evals")
        with open(self.harness, "w") as fh:
            fh.write(STUB)
        os.chmod(self.harness, 0o755)
        self.ledger = os.path.join(self.tmp, "state", "ledger.jsonl")
        self.git("init", "-q")
        self.add_skill("brief", tier1=2)
        self.add_skill("execute", tier1=1, tier2=2)
        self.commit()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def git(self, *args):
        return subprocess.run(["git", "-C", self.repo, "-c", "user.name=t",
                               "-c", "user.email=t@example.com"] + list(args),
                              capture_output=True, text=True, check=True).stdout.strip()

    def add_skill(self, name, tier1=1, tier2=0, note=""):
        evals = [{"id": i, "name": "t1-%d" % i} for i in range(tier1)]
        evals += [{"id": 100 + i, "name": "t2-%d" % i, "tier": 2} for i in range(tier2)]
        directory = os.path.join(self.repo, "skills", name, "evals")
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, "evals.json"), "w") as fh:
            json.dump({"skill_name": name, "evals": evals, "note": note}, fh)

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "c")

    def tree(self, name):
        return self.git("rev-parse", "HEAD:skills/%s" % name)

    def ledger_lines(self):
        if not os.path.exists(self.ledger):
            return []
        with open(self.ledger) as fh:
            return [json.loads(line) for line in fh if line.strip()]

    def seed(self, *entries):
        os.makedirs(os.path.dirname(self.ledger), exist_ok=True)
        with open(self.ledger, "a") as fh:
            for entry in entries:
                fh.write(json.dumps(entry) + "\n")

    def result(self, skill, spec):
        with open(os.path.join(self.stub, "result." + skill), "w") as fh:
            fh.write(spec)

    def calls(self):
        path = os.path.join(self.stub, "log")
        if not os.path.exists(path):
            return []
        with open(path) as fh:
            return [line.strip() for line in fh]

    def run_tool(self, *args, env=None):
        environ = dict(os.environ, SCHEDULED_EVALS_HARNESS=self.harness, STUB_DIR=self.stub)
        environ.pop("SHIRABE_EVAL_WEEKLY_CAP_USD", None)
        environ.update(env or {})
        proc = subprocess.run([sys.executable, os.path.join(self.repo, "scripts", "scheduled-evals.py"),
                               "--ledger", self.ledger] + list(args),
                              capture_output=True, text=True, env=environ)
        return proc.returncode, proc.stdout + proc.stderr


class SelectionTest(Case):
    def test_first_run_measures_every_skill_and_ledgers_its_cost(self):
        self.result("brief", "0 9 10 1.5 1")
        rc, out = self.run_tool("--runs", "2", "brief")
        self.assertEqual(rc, 0, out)
        self.assertEqual(len(self.calls()), 1)
        self.assertRegex(self.calls()[0], r"^--runs 2 --summary-out \S+ brief model=sonnet$")
        (entry,) = self.ledger_lines()
        self.assertEqual(entry["kind"], "run")
        self.assertEqual(entry["skill"], "brief")
        self.assertEqual(entry["tree"], self.tree("brief"))
        self.assertEqual(entry["cost_usd"], 3.0)
        self.assertIs(entry["cost_measured"], True)
        self.assertEqual(entry["runs"], 2)
        self.assertEqual(entry["model"], "sonnet")
        self.assertEqual((entry["assertions_passed"], entry["assertions_graded"]), (9, 10))

    def test_unchanged_skill_is_skipped(self):
        self.seed({"kind": "run", "at": ago(days=1), "skill": "brief", "tree": self.tree("brief"),
                   "runs": 3, "model": "sonnet", "cost_usd": 3, "cost_measured": True,
                   "exit_code": 0})
        rc, out = self.run_tool("brief")
        self.assertEqual(rc, 0, out)
        self.assertIn("unchanged: brief", out)
        self.assertEqual(self.calls(), [])

    def test_changed_skill_runs_again(self):
        old = self.tree("brief")
        self.seed({"kind": "run", "at": ago(days=1), "skill": "brief", "tree": old, "runs": 3,
                   "model": "sonnet", "cost_usd": 3, "cost_measured": True, "exit_code": 0})
        self.add_skill("brief", tier1=3)
        self.commit()
        rc, out = self.run_tool("brief")
        self.assertEqual(rc, 0, out)
        self.assertEqual(len(self.calls()), 1)
        self.assertNotEqual(self.ledger_lines()[-1]["tree"], old)

    def test_an_infrastructure_failure_is_retried_next_time(self):
        self.seed({"kind": "run", "at": ago(days=1), "skill": "brief", "tree": self.tree("brief"),
                   "runs": 3, "model": "sonnet", "cost_usd": 1, "cost_measured": True,
                   "exit_code": 2})
        rc, out = self.run_tool("brief")
        self.assertEqual(rc, 0, out)
        self.assertEqual(len(self.calls()), 1)

    def test_never_measured_first_then_oldest(self):
        self.add_skill("zeta", tier1=1)
        self.add_skill("alpha", tier1=1)
        self.commit()
        self.seed({"kind": "run", "at": ago(days=9), "skill": "alpha", "tree": "old", "runs": 1,
                   "model": "sonnet", "cost_usd": 1, "cost_measured": True, "exit_code": 0},
                  {"kind": "run", "at": ago(days=20), "skill": "zeta", "tree": "old", "runs": 1,
                   "model": "sonnet", "cost_usd": 1, "cost_measured": True, "exit_code": 0})
        rc, out = self.run_tool("--runs", "1")
        self.assertEqual(rc, 0, out)
        order = [line.split()[4] for line in self.calls()]
        self.assertEqual(order, ["brief", "execute", "zeta", "alpha"])

    def test_harness_failure_exits_1_and_is_ledgered(self):
        self.result("brief", "1 5 10 1.0 1")
        rc, out = self.run_tool("brief")
        self.assertEqual(rc, 1, out)
        self.assertEqual(self.ledger_lines()[-1]["exit_code"], 1)

    def test_model_reaches_the_harness(self):
        rc, out = self.run_tool("--model", "opus", "--runs", "1", "brief")
        self.assertEqual(rc, 0, out)
        self.assertTrue(self.calls()[0].endswith("model=opus"))


class CapTest(Case):
    def test_cap_reached_stops_reports_and_ledgers(self):
        self.seed({"kind": "run", "at": ago(days=2), "skill": "other", "tree": "x", "runs": 3,
                   "model": "sonnet", "cost_usd": 49.5, "cost_measured": True, "exit_code": 0})
        rc, out = self.run_tool()
        self.assertEqual(rc, 6, out)
        self.assertEqual(self.calls(), [])
        self.assertIn("cap: $49.50 of $50.00 spent in the last 7 days", out)
        self.assertIn("not run: brief, execute", out)
        stop = self.ledger_lines()[-1]
        self.assertEqual(stop["kind"], "cap_stop")
        self.assertEqual(stop["unrun"], ["brief", "execute"])
        self.assertEqual(stop["cap_usd"], 50.0)

    def test_spend_older_than_a_week_doesnt_count(self):
        self.seed({"kind": "run", "at": ago(days=8), "skill": "other", "tree": "x", "runs": 3,
                   "model": "sonnet", "cost_usd": 500, "cost_measured": True, "exit_code": 0})
        rc, out = self.run_tool("--runs", "1")
        self.assertEqual(rc, 0, out)
        self.assertEqual(len(self.calls()), 2)

    def test_fewer_runs_when_only_some_fit(self):
        # brief's estimate: 2 tier-1 scenarios at $0.46 + $2.50 session = $3.42 a run.
        rc, out = self.run_tool("--cap-usd", "7", "--runs", "3", "brief")
        self.assertEqual(rc, 0, out)
        self.assertRegex(self.calls()[0], r"^--runs 2 ")

    def test_measured_cost_per_run_is_the_next_estimate(self):
        self.seed({"kind": "run", "at": ago(days=10), "skill": "brief", "tree": "old", "runs": 2,
                   "model": "sonnet", "cost_usd": 20, "cost_measured": True, "exit_code": 0})
        rc, out = self.run_tool("--cap-usd", "25", "--runs", "3", "brief")
        self.assertEqual(rc, 0, out)
        self.assertIn("about $10.00 a run (its last measured run)", out)
        self.assertRegex(self.calls()[0], r"^--runs 2 ")

    def test_cost_spent_during_the_run_stops_the_next_skill(self):
        self.result("brief", "0 9 10 45 1")
        rc, out = self.run_tool("--runs", "1")
        self.assertEqual(rc, 6, out)
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.ledger_lines()[-1]["unrun"], ["execute"])

    def test_cap_from_the_environment(self):
        rc, out = self.run_tool("--runs", "1", env={"SHIRABE_EVAL_WEEKLY_CAP_USD": "1"})
        self.assertEqual(rc, 6, out)
        self.assertIn("of $1.00", out)

    def test_unmeasured_cost_is_ledgered_at_the_estimate(self):
        self.result("brief", "0 9 10 - 0")
        rc, out = self.run_tool("--runs", "1", "brief")
        self.assertEqual(rc, 0, out)
        entry = self.ledger_lines()[-1]
        self.assertIs(entry["cost_measured"], False)
        self.assertEqual(entry["cost_usd"], 3.42)

    def test_dry_run_runs_and_writes_nothing(self):
        rc, out = self.run_tool("--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertIn("would run brief: 3 run(s)", out)
        self.assertEqual(self.calls(), [])
        self.assertFalse(os.path.exists(self.ledger))


class GuardTest(Case):
    def test_lock_held_exits_3(self):
        os.makedirs(self.ledger + ".lock")
        rc, out = self.run_tool("brief")
        self.assertEqual(rc, 3, out)
        self.assertEqual(self.calls(), [])

    def test_lock_released_after_a_run(self):
        rc, out = self.run_tool("--runs", "1", "brief")
        self.assertEqual(rc, 0, out)
        self.assertFalse(os.path.exists(self.ledger + ".lock"))

    def test_unparseable_ledger_line_is_skipped(self):
        os.makedirs(os.path.dirname(self.ledger), exist_ok=True)
        with open(self.ledger, "w") as fh:
            fh.write("not json\n")
        rc, out = self.run_tool("--runs", "1", "brief")
        self.assertEqual(rc, 0, out)
        self.assertIn("ledger line 1 doesn't parse", out)

    def test_usage_errors(self):
        for args in (["--runs", "0"], ["--runs", "10"], ["--model", "-x"],
                     ["--cap-usd", "-1"], ["Bad"], ["absent"]):
            with self.subTest(args=args):
                rc, out = self.run_tool(*args)
                self.assertEqual(rc, 2, out)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
