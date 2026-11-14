#!/usr/bin/env python3
"""Tests for scripts/scheduled-evals.py, which is retired and runs nothing.

Usage: python3 scripts/scheduled-evals_test.py

No model, no network, no koto. Each case copies the script into a throwaway git
repository holding skills/deliver/evals/evals.json with one graded case and a
scripts/run-evals.sh that records its arguments, and runs it with the failing
claude stub (scripts/run-evals/fixtures/bin/claude) first on PATH and every
billing variable set. Whatever the arguments, and whether or not
SCHEDULED_EVALS_HARNESS names a second recording script, the script must print
its one refusal line, exit 3, start nothing and touch no ledger or state
directory.
"""

import ast
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "scheduled-evals.py")
STUB_BIN = os.path.join(HERE, "run-evals", "fixtures", "bin")

REFUSAL = (
    "scheduled-evals.py: scheduled eval runs are retired, and graded cases "
    "don't run; scripts/run-evals.sh <skill> runs a skill's script cases\n"
)

# A recording script: appends its arguments as one line to the record file
# filled in below, and exits 0.
RECORDER = """#!/bin/sh
printf '%s\\n' "$*" >> "{record}"
exit 0
"""

EVALS = """{"skill_name": "deliver", "evals": [
  {"id": 1, "name": "graded-case", "prompt": "do it", "expectations": ["it is done"]}
]}
"""

LEDGER = (
    '{"kind": "run", "at": "2026-01-01T00:00:00Z", "skill": "deliver", "cost_usd": 1.0}\n'
    '{"kind": "run", "at": "2026-01-02T00:00:00Z", "skill": "deliver", "cost_usd": 2.0}\n'
)


def arg_lists(ledger):
    return [
        [],
        ["--dry-run"],
        ["--help"],
        ["deliver"],
        ["--runs", "9", "--rotation-size", "20", "--model", "opus",
         "--cap-usd", "1000", "--ledger", ledger, "deliver"],
        ["--bogus"],
    ]


class Case(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="scheduled-evals-test.")
        self.repo = os.path.join(self.tmp, "repo")
        os.makedirs(os.path.join(self.repo, "scripts"))
        os.makedirs(os.path.join(self.repo, "skills", "deliver", "evals"))
        shutil.copy(SCRIPT, os.path.join(self.repo, "scripts", "scheduled-evals.py"))
        with open(os.path.join(self.repo, "skills", "deliver", "evals", "evals.json"), "w") as fh:
            fh.write(EVALS)
        self.runner_record = os.path.join(self.tmp, "run-evals-record")
        self.harness_record = os.path.join(self.tmp, "harness-record")
        self.claude_record = os.path.join(self.tmp, "claude-record")
        self.write_recorder(os.path.join(self.repo, "scripts", "run-evals.sh"), self.runner_record)
        self.harness = os.path.join(self.tmp, "harness.sh")
        self.write_recorder(self.harness, self.harness_record)
        self.ledger = os.path.join(self.tmp, "ledger", "ledger.jsonl")
        os.makedirs(os.path.dirname(self.ledger))
        self.git("init", "-q")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "fixture")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write_recorder(self, path, record):
        with open(path, "w") as fh:
            fh.write(RECORDER.format(record=record))
        os.chmod(path, 0o755)

    def git(self, *args):
        subprocess.run(
            ["git", "-c", "user.email=test@example.invalid", "-c", "user.name=test"] + list(args),
            cwd=self.repo, check=True, stdout=subprocess.DEVNULL)

    def env(self, harness=False, **extra):
        env = dict(os.environ)
        for name in ("SCHEDULED_EVALS_HARNESS", "XDG_STATE_HOME"):
            env.pop(name, None)
        env.update({
            "PATH": STUB_BIN + os.pathsep + env.get("PATH", ""),
            "STUB_CLAUDE_RECORD": self.claude_record,
            "SHIRABE_EVAL_WEEKLY_CAP_USD": "1000",
            "EVAL_MODEL": "opus",
            "ANTHROPIC_API_KEY": "sk-test",
            "ANTHROPIC_AUTH_TOKEN": "tok-test",
            "ANTHROPIC_BASE_URL": "https://example.invalid",
            "CLAUDE_CODE_USE_BEDROCK": "1",
            "CLAUDE_CODE_USE_VERTEX": "1",
        })
        if harness:
            env["SCHEDULED_EVALS_HARNESS"] = self.harness
        for name, value in extra.items():
            if value is None:
                env.pop(name, None)
            else:
                env[name] = value
        return env

    def run_script(self, args, env):
        return subprocess.run(
            [sys.executable, os.path.join(self.repo, "scripts", "scheduled-evals.py")] + args,
            cwd=self.repo, env=env, capture_output=True, text=True)

    def assert_refused(self, proc, label):
        self.assertEqual(proc.returncode, 3, label)
        self.assertEqual(proc.stdout, "", label)
        self.assertEqual(proc.stderr, REFUSAL, label)

    def assert_nothing_started(self, label):
        for record in (self.claude_record, self.runner_record, self.harness_record):
            if os.path.exists(record):
                with open(record) as fh:
                    self.assertEqual(fh.read(), "", "%s: %s" % (label, record))

    def test_every_argument_list_refuses_with_and_without_a_harness(self):
        for harness in (True, False):
            for args in arg_lists(self.ledger):
                label = "args=%r harness=%s" % (args, harness)
                with self.subTest(label):
                    proc = self.run_script(args, self.env(harness=harness))
                    self.assert_refused(proc, label)
                    self.assert_nothing_started(label)

    def test_an_existing_ledger_is_not_read_written_or_locked(self):
        with open(self.ledger, "wb") as fh:
            fh.write(LEDGER.encode())
        args = ["--cap-usd", "1000", "--ledger", self.ledger, "deliver"]
        proc = self.run_script(args, self.env(harness=True))
        self.assert_refused(proc, "ledger")
        with open(self.ledger, "rb") as fh:
            self.assertEqual(fh.read(), LEDGER.encode())
        self.assertFalse(os.path.exists(self.ledger + ".lock"))
        self.assert_nothing_started("ledger")

    def test_a_stale_lock_is_left_in_place(self):
        with open(self.ledger, "wb") as fh:
            fh.write(LEDGER.encode())
        lock = self.ledger + ".lock"
        os.mkdir(lock)
        proc = self.run_script(["--ledger", self.ledger, "deliver"], self.env(harness=True))
        self.assert_refused(proc, "stale lock")
        self.assertTrue(os.path.isdir(lock))
        with open(self.ledger, "rb") as fh:
            self.assertEqual(fh.read(), LEDGER.encode())

    def test_xdg_state_home_is_left_empty(self):
        state = tempfile.mkdtemp(dir=self.tmp)
        proc = self.run_script(["deliver"], self.env(harness=True, XDG_STATE_HOME=state))
        self.assert_refused(proc, "XDG_STATE_HOME")
        self.assertEqual(os.listdir(state), [])

    def test_home_gets_no_state_directory(self):
        home = tempfile.mkdtemp(dir=self.tmp)
        proc = self.run_script(["deliver"], self.env(harness=True, XDG_STATE_HOME=None, HOME=home))
        self.assert_refused(proc, "HOME")
        self.assertFalse(os.path.exists(os.path.join(home, ".local", "state", "shirabe")))
        self.assertEqual(os.listdir(home), [])


class Source(unittest.TestCase):
    """The cap and the harness call are gone from the code, not only unreachable."""

    def setUp(self):
        with open(SCRIPT) as fh:
            self.tree = ast.parse(fh.read())
        self.docstring = ast.get_docstring(self.tree, clean=False)
        body = self.tree.body
        self.doc_node = body[0].value if body and isinstance(body[0], ast.Expr) else None
        self.strings = [
            node.value for node in ast.walk(self.tree)
            if isinstance(node, ast.Constant) and isinstance(node.value, str)
            and node is not self.doc_node
        ]

    def test_imports_sys_only(self):
        imported = []
        for node in ast.walk(self.tree):
            if isinstance(node, ast.Import):
                imported.extend(alias.name for alias in node.names)
            elif isinstance(node, ast.ImportFrom):
                imported.append(node.module or "")
        self.assertEqual(imported, ["sys"])

    def test_no_cap_or_harness_strings(self):
        for word in ("SCHEDULED_EVALS_HARNESS", "SHIRABE_EVAL_WEEKLY_CAP_USD",
                     "--cap-usd", "--summary-out"):
            with self.subTest(word):
                self.assertEqual([s for s in self.strings if word in s], [])

    def test_run_evals_only_in_the_refusal(self):
        found = [s for s in self.strings if "run-evals" in s]
        self.assertEqual(found, [REFUSAL.rstrip("\n")])

    def test_docstring_says_retired_and_what_runs_now(self):
        self.assertIsNotNone(self.docstring)
        self.assertIn("retired", self.docstring)
        self.assertIn("Decision 1 of docs/designs/current/DESIGN-skill-regression-detection.md",
                      " ".join(self.docstring.split()))
        self.assertIn("scripts/run-evals.sh <skill>", self.docstring)


if __name__ == "__main__":
    unittest.main()
