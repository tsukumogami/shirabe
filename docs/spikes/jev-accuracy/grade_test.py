#!/usr/bin/env python3
"""Offline tests for grade.py: request shape, answer mapping, and scoring.

Run: python3 docs/spikes/jev-accuracy/grade_test.py
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True  # keep __pycache__ out of the docs tree

import grade  # noqa: E402


def fixture(label="good", criterion="ac_binary", fid="t-1"):
    inputs = {name: "text for " + name for name in grade.CRITERIA[criterion]["inputs"]}
    return {"id": fid, "criterion": criterion, "label": label, "inputs": inputs, "source": "test"}


class RequestShape(unittest.TestCase):
    def test_noul_matches_koto_encoding(self):
        # koto sends a boolean field as a noul question with instructions
        # only, and the state keys in declared input order.
        body = grade.build_request(fixture(criterion="comment_reason"), "noul")
        self.assertEqual(list(body), ["model", "state", "questions"])
        self.assertEqual(body["model"], "jev-latest")
        self.assertEqual(list(body["state"]), ["comment", "code"])
        q = body["questions"]["comment_reason"]
        self.assertEqual(q, {"type": "noul", "instructions": grade.CRITERIA["comment_reason"]["proposition"]})

    def test_choice_puts_escape_last(self):
        body = grade.build_request(fixture(), "choice")
        q = body["questions"]["ac_binary"]
        self.assertEqual(q["type"], "choice")
        self.assertEqual(list(q["criteria"]), ["pass", "fail", "unclear"])


class Outcome(unittest.TestCase):
    def noul(self, p):
        return {"model": "jev-1.13.0", "answers": {"f": {"type": "noul", "noul": p}}}

    def test_noul_thresholds_are_inclusive(self):
        self.assertEqual(grade.outcome("f", "noul", self.noul(0.9), 0.9)[0], "pass")
        self.assertEqual(grade.outcome("f", "noul", self.noul(0.1), 0.9)[0], "fail")
        self.assertEqual(grade.outcome("f", "noul", self.noul(0.5), 0.9)[0], "escape")
        self.assertEqual(grade.outcome("f", "noul", self.noul(0.89), 0.9)[0], "escape")

    def test_choice_winner_under_threshold_escapes(self):
        resp = {"answers": {"f": {"type": "choice", "choice": "pass",
                                  "probabilities": {"pass": 0.8, "fail": 0.15, "unclear": 0.05}}}}
        self.assertEqual(grade.outcome("f", "choice", resp, 0.9)[0], "escape")
        resp["answers"]["f"]["probabilities"] = {"pass": 0.02, "fail": 0.95, "unclear": 0.03}
        self.assertEqual(grade.outcome("f", "choice", resp, 0.9)[0], "fail")

    def test_malformed_answers_are_errors(self):
        for resp in ({"error": "http 429"}, {"answers": {}}, self.noul(1.5), self.noul("0.9")):
            self.assertEqual(grade.outcome("f", "noul", resp, 0.9)[0], "error", resp)
        missing_keys = {"answers": {"f": {"type": "choice", "probabilities": {"pass": 1.0}}}}
        self.assertEqual(grade.outcome("f", "choice", missing_keys, 0.9)[0], "error")


class WorstCase(unittest.TestCase):
    def test_good_needs_every_pass_bad_needs_one(self):
        run1 = [{"label": "good", "outcome": "pass"}, {"label": "bad", "outcome": "fail"}]
        run2 = [{"label": "good", "outcome": "escape"}, {"label": "bad", "outcome": "pass"}]
        merged = grade.worst_case([run1, run2])
        self.assertEqual([r["outcome"] for r in merged], ["escape", "pass"])
        self.assertEqual(merged[1]["outcomes"], ["fail", "pass"])


class EndToEnd(unittest.TestCase):
    def run_grade(self, *args):
        return subprocess.run([sys.executable, str(HERE / "grade.py"), *args],
                              capture_output=True, text=True, check=False)

    def test_stub_record_then_replay_agree(self):
        with tempfile.TemporaryDirectory() as tmp:
            fx = Path(tmp) / "fx.jsonl"
            rows = [fixture("good", fid="g-1"), fixture("bad", fid="b-1"),
                    fixture("adversarial", fid="a-1"), fixture("bad", fid="b-2-escape")]
            fx.write_text("".join(json.dumps(r) + "\n" for r in rows))
            rec = Path(tmp) / "rec.jsonl"
            stub = self.run_grade("--stub", "--fixtures", str(fx), "--record", str(rec))
            self.assertEqual(stub.returncode, 0, stub.stderr)
            replay = self.run_grade("--replay", str(rec), "--fixtures", str(fx))
            self.assertEqual(replay.returncode, 0, replay.stderr)
            table = lambda out: [l for l in out.splitlines() if l.startswith("| ac_binary")]
            self.assertEqual(table(stub.stdout), table(replay.stdout))
            # good passes, one bad fails and one escapes, adversarial passes.
            self.assertIn("| ac_binary | 1/1 (100%) | 0/1 (0%) | 0/2 (0%) | 1/2 (50%) | 1/1 (100%) | 0/1/0 | 0 |",
                          stub.stdout)

    def test_live_needs_a_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            fx = Path(tmp) / "fx.jsonl"
            fx.write_text(json.dumps(fixture()) + "\n")
            env = {"PATH": "/usr/bin:/bin"}
            res = subprocess.run([sys.executable, str(HERE / "grade.py"), "--live", "--fixtures", str(fx)],
                                 capture_output=True, text=True, env=env, check=False)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("needs JEV_API_KEY", res.stderr)

    def test_label_and_expected_must_agree(self):
        with tempfile.TemporaryDirectory() as tmp:
            fx = Path(tmp) / "fx.jsonl"
            bad = fixture("bad")
            bad["expected"] = True
            fx.write_text(json.dumps(bad) + "\n")
            res = self.run_grade("--stub", "--fixtures", str(fx))
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("expected must be False", res.stderr)


if __name__ == "__main__":
    unittest.main()
