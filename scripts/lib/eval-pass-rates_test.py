#!/usr/bin/env python3
"""Tests for scripts/lib/eval-pass-rates.py.

Usage: python3 scripts/lib/eval-pass-rates_test.py

Drives the script's command line in a temporary directory: merge's record,
exit codes and baseline validation, and stamp. No model, no network.
"""

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "eval-pass-rates.py")


def entry(passed=9, graded=10, runs=1, runs_passed=1, rate="auto", measured_at="0.23.0",
          models=("sonnet",)):
    out = {"runs": runs, "runs_passed": runs_passed, "assertions_passed": passed,
           "assertions_graded": graded, "models": list(models), "measured_at": measured_at}
    if rate == "auto":
        out["pass_rate"] = round(passed / graded, 4)
    elif rate is not None:
        out["pass_rate"] = rate
    return out


def record(skills, version="0.23.0", last_tag="v0.22.0"):
    return {"schema": "eval-pass-rates/v1", "version": version, "last_tag": last_tag,
            "skills": skills}


def summary_entry(passed=9, graded=10, code=0, runs=1, runs_passed=None, models=("sonnet",)):
    if runs_passed is None:
        runs_passed = runs if code == 0 else 0
    return {"runs": runs, "runs_passed": runs_passed, "assertions_passed": passed,
            "assertions_graded": graded, "models": list(models), "exit_code": code}


class Case(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.out = os.path.join(self.dir, "eval-pass-rates.json")
        self.n = 0

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, data, raw=None):
        self.n += 1
        path = os.path.join(self.dir, "f%d.json" % self.n)
        with open(path, "w") as fh:
            fh.write(raw if raw is not None else json.dumps(data))
        return path

    def summary(self, skills):
        return self.write({"schema": "run-evals-summary/v1", "skills": skills})

    def run_tool(self, *args):
        proc = subprocess.run([sys.executable, SCRIPT] + list(args),
                              capture_output=True, text=True)
        return proc.returncode, proc.stdout + proc.stderr

    def merge(self, previous, summaries, selected, confirmed="", last_tag="v0.23.0",
              version="0.24.0", reason=""):
        args = ["merge", "--version", version,
                "--last-tag", last_tag, "--out", self.out, "--confirmed", confirmed]
        for path in ([previous] if isinstance(previous, str) else previous):
            args += ["--previous", path]
        if reason:
            args += ["--no-baseline-reason", reason]
        for path in summaries:
            args += ["--summary", path]
        for name in selected:
            args += ["--selected", name]
        return self.run_tool(*args)

    def result(self):
        with open(self.out) as fh:
            return json.load(fh)


class MergeTest(Case):
    def test_drop_exits_5_with_confirm_line(self):
        prev = self.write(record({"brief": entry(9, 10), "scope": entry(5, 10)}))
        summ = self.summary({"brief": summary_entry(8, 10, code=1),
                             "scope": summary_entry(4, 10, code=1)})
        rc, out = self.merge(prev, [summ], ["brief", "scope"])
        self.assertEqual(rc, 5, out)
        self.assertEqual(out.strip().splitlines()[-1],
                         "confirm: RELEASE_CONFIRMED_DROPS=brief,scope")

    def test_equal_rate_is_not_a_drop(self):
        prev = self.write(record({"brief": entry(9, 10)}))
        summ = self.summary({"brief": summary_entry(18, 20)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)

    def test_drop_decided_on_rounded_values(self):
        prev = self.write(record({"brief": entry(2, 3)}))  # 0.6667
        summ = self.summary({"brief": summary_entry(20001, 30000)})  # 0.66670 -> 0.6667
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)

    def test_confirmed_drop_exits_0(self):
        prev = self.write(record({"brief": entry(9, 10)}))
        summ = self.summary({"brief": summary_entry(8, 10, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"], confirmed="brief")
        self.assertEqual(rc, 0, out)

    def test_drop_with_another_skill_confirmed_exits_5(self):
        prev = self.write(record({"brief": entry(9, 10)}))
        summ = self.summary({"brief": summary_entry(8, 10, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"], confirmed="scope")
        self.assertEqual(rc, 5, out)
        self.assertIn("confirm: RELEASE_CONFIRMED_DROPS=brief", out)

    def test_harness_exit_1_without_drop_exits_0(self):
        prev = self.write(record({"brief": entry(5, 10)}))
        summ = self.summary({"brief": summary_entry(6, 10, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.result()["skills"]["brief"]["pass_rate"], 0.6)

    def test_infrastructure_exits(self):
        for code in (2, 3, 4):
            with self.subTest(code=code):
                prev = self.write(record({"scope": entry(9, 10)}))
                summ = self.summary({"brief": summary_entry(0, 0, code=code),
                                     "scope": summary_entry(1, 10, code=1)})
                rc, out = self.merge(prev, [summ], ["brief", "scope"])
                self.assertEqual(rc, 1, out)  # outranks scope's drop
                self.assertIn("infrastructure failure: brief (harness exit %d)" % code, out)
                self.assertNotIn("confirm:", out)
                brief = self.result()["skills"]["brief"]
                self.assertEqual(brief["exit_code"], code)
                self.assertNotIn("pass_rate", brief)

    def test_missing_summary_is_infrastructure_failure(self):
        rc, out = self.merge("-", [os.path.join(self.dir, "absent.json")], ["brief"])
        self.assertEqual(rc, 1, out)
        brief = self.result()["skills"]["brief"]
        self.assertEqual(brief["exit_code"], 2)
        self.assertNotIn("pass_rate", brief)

    def test_graded_nothing_has_no_pass_rate(self):
        summ = self.summary({"brief": summary_entry(0, 0, code=0)})
        rc, out = self.merge("-", [summ], ["brief"])
        self.assertEqual(rc, 1, out)
        self.assertNotIn("pass_rate", self.result()["skills"]["brief"])

    def test_record_fields(self):
        summ = self.summary({"brief": dict(summary_entry(140, 150, runs=3, runs_passed=2,
                                                         models=("sonnet", "haiku", "sonnet")),
                                           extra="dropped")})
        rc, out = self.merge("-", [summ], ["brief"], last_tag="v0.23.0")
        self.assertEqual(rc, 0, out)
        data = self.result()
        self.assertEqual(data["schema"], "eval-pass-rates/v1")
        self.assertEqual(data["version"], "0.24.0")
        self.assertEqual(data["last_tag"], "v0.23.0")
        self.assertEqual(data["skills"]["brief"], {
            "runs": 3, "runs_passed": 2, "assertions_passed": 140, "assertions_graded": 150,
            "pass_rate": 0.9333, "models": ["haiku", "sonnet"], "measured_at": "0.24.0"})

    def test_carry_forward_unchanged(self):
        old = entry(7, 10, measured_at="0.21.0")
        prev = self.write(record({"brief": entry(9, 10), "plan": old}))
        summ = self.summary({"brief": summary_entry(9, 10)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.result()["skills"]["plan"], old)

    def test_carry_forward_drops_unknown_keys(self):
        old = dict(entry(7, 10), note="x")
        prev = self.write(dict(record({"plan": old}), extra="y"))
        rc, out = self.merge(prev, [], [])
        self.assertEqual(rc, 0, out)
        data = self.result()
        self.assertNotIn("note", data["skills"]["plan"])
        self.assertNotIn("extra", data)

    def test_empty_selection_carries_previous_forward(self):
        prev = self.write(record({"plan": entry(7, 10, measured_at="0.21.0")}))
        rc, out = self.merge(prev, [], [])
        self.assertEqual(rc, 0, out)
        data = self.result()
        self.assertEqual(data["version"], "0.24.0")
        self.assertEqual(data["skills"]["plan"]["measured_at"], "0.21.0")

    def test_no_asset(self):
        summ = self.summary({"brief": summary_entry(9, 10)})
        rc, out = self.merge("-", [summ], ["brief"], reason="no eval-pass-rates.json on v0.23.0")
        self.assertEqual(rc, 0, out)
        self.assertIn("warning: no baseline: no eval-pass-rates.json on v0.23.0", out)

    def test_empty_last_tag(self):
        summ = self.summary({"brief": summary_entry(9, 10)})
        rc, out = self.merge("-", [summ], ["brief"], last_tag="", reason="no last tag")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.result()["last_tag"], "")

    def test_unparseable_asset(self):
        prev = self.write(None, raw="{not json")
        summ = self.summary({"brief": summary_entry(1, 10)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("warning: no baseline: the file does not parse as JSON", out)

    def test_oversized_asset(self):
        prev = self.write(None, raw=" " * (1024 * 1024 + 1))
        rc, out = self.merge(prev, [], [])
        self.assertEqual(rc, 0, out)
        self.assertIn("size cap", out)

    def test_unknown_schema(self):
        data = record({"brief": entry(9, 10)})
        data["schema"] = "eval-pass-rates/v2"
        prev = self.write(data)
        summ = self.summary({"brief": summary_entry(1, 10)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("warning: no baseline: schema is not eval-pass-rates/v1", out)
        self.assertNotIn("v2", out)

    def test_field_validation_failures(self):
        secret = "SECRETVALUE"
        good = record({"brief": entry(9, 10)})
        cases = []

        def case(label, field, mutate):
            data = copy.deepcopy(good)
            mutate(data)
            cases.append((label, field, data))

        def set_top(key, value):
            return lambda d: d.__setitem__(key, value)

        def set_skill(key, value):
            return lambda d: d["skills"]["brief"].__setitem__(key, value)

        def del_skill(key):
            return lambda d: d["skills"]["brief"].pop(key)

        case("version not semver", "version", set_top("version", secret))
        case("version with v", "version", set_top("version", "v0.23.0"))
        case("last_tag not a tag", "last_tag", set_top("last_tag", secret))
        case("skills not an object", "skills", set_top("skills", [secret]))
        case("measured_at not semver", "skills.brief.measured_at", set_skill("measured_at", secret))
        case("skill name", "skill name",
             lambda d: d["skills"].__setitem__("Bad " + secret, d["skills"].pop("brief")))
        case("model pattern", "skills.brief.models", set_skill("models", ["-" + secret]))
        case("models not a list", "skills.brief.models", set_skill("models", secret))
        case("negative count", "skills.brief.runs", set_skill("runs", -1))
        case("float count", "skills.brief.assertions_graded", set_skill("assertions_graded", 10.0))
        case("bool count", "skills.brief.runs", set_skill("runs", True))
        case("missing count", "skills.brief.runs_passed", del_skill("runs_passed"))
        case("runs_passed over runs", "skills.brief.runs_passed", set_skill("runs_passed", 2))
        case("passed over graded", "skills.brief.assertions_passed",
             set_skill("assertions_passed", 11))
        case("pass_rate over 1", "skills.brief.pass_rate", set_skill("pass_rate", 1.5))
        case("pass_rate negative", "skills.brief.pass_rate", set_skill("pass_rate", -0.1))
        case("pass_rate not a number", "skills.brief.pass_rate", set_skill("pass_rate", secret))
        case("pass_rate disagrees", "skills.brief.pass_rate", set_skill("pass_rate", 0.5))
        case("missing measured_at", "skills.brief.measured_at", del_skill("measured_at"))
        case("bad exit_code", "skills.brief.exit_code",
             lambda d: (d["skills"]["brief"].pop("pass_rate"),
                        d["skills"]["brief"].__setitem__("exit_code", 7)))
        case("pass_rate and exit_code", "skills.brief",
             set_skill("exit_code", 2))
        for label, field, data in cases:
            with self.subTest(label=label):
                prev = self.write(data)
                summ = self.summary({"brief": summary_entry(1, 10, code=1)})
                rc, out = self.merge(prev, [summ], ["brief"])
                self.assertEqual(rc, 0, out)  # no baseline, so no drop
                self.assertIn("warning: no baseline:", out)
                self.assertIn(field, out)
                self.assertNotIn(secret, out)
                self.assertEqual(set(self.result()["skills"]), {"brief"})

        with self.subTest(label="non-finite pass_rate"):
            raw = json.dumps(good).replace('"pass_rate": 0.9', '"pass_rate": NaN')
            prev = self.write(None, raw=raw)
            rc, out = self.merge(prev, [], [])
            self.assertEqual(rc, 0, out)
            self.assertIn("skills.brief.pass_rate", out)

    def test_baseline_falls_back_per_skill(self):
        newest = self.write(record({"brief": entry(9, 10, measured_at="0.24.0")},
                                   version="0.24.0", last_tag="v0.23.0"))
        older = self.write(record({"brief": entry(5, 10, measured_at="0.22.0"),
                                   "scope": entry(9, 10, measured_at="0.22.0")},
                                  version="0.22.0", last_tag="v0.21.0"))
        summ = self.summary({"brief": summary_entry(9, 10), "scope": summary_entry(8, 10, code=1)})
        rc, out = self.merge([newest, older], [summ], ["brief", "scope"], last_tag="v0.24.0",
                             version="0.25.0")
        # brief compares with 0.24.0 (equal), scope falls back to 0.22.0 (a drop).
        self.assertEqual(rc, 5, out)
        self.assertEqual(out.strip().splitlines()[-1], "confirm: RELEASE_CONFIRMED_DROPS=scope")
        self.assertRegex(out, r"scope\s+0\.8000\s+0\.9000\s+0\.22\.0")
        self.assertRegex(out, r"brief\s+0\.9000\s+0\.9000\s+0\.24\.0")

    def test_fallback_entries_are_carried_forward(self):
        newest = self.write(record({"brief": entry(9, 10, measured_at="0.24.0")},
                                   version="0.24.0"))
        older = self.write(record({"brief": entry(5, 10, measured_at="0.22.0"),
                                   "scope": entry(9, 10, measured_at="0.22.0")},
                                  version="0.22.0"))
        rc, out = self.merge([newest, older], [], [])
        self.assertEqual(rc, 0, out)
        skills = self.result()["skills"]
        self.assertEqual(skills["brief"]["measured_at"], "0.24.0")
        self.assertEqual(skills["scope"]["measured_at"], "0.22.0")

    def test_newer_exit_code_entry_falls_back_to_older_rate(self):
        failed = entry(0, 0, rate=None, measured_at="0.24.0")
        failed["exit_code"] = 4
        newest = self.write(record({"scope": failed}, version="0.24.0"))
        older = self.write(record({"scope": entry(9, 10, measured_at="0.22.0")}, version="0.22.0"))
        summ = self.summary({"scope": summary_entry(8, 10, code=1)})
        rc, out = self.merge([newest, older], [summ], ["scope"])
        self.assertEqual(rc, 5, out)
        self.assertIn("confirm: RELEASE_CONFIRMED_DROPS=scope", out)

    def test_invalid_record_is_skipped_not_the_whole_baseline(self):
        bad = self.write(None, raw="{not json")
        older = self.write(record({"brief": entry(9, 10, measured_at="0.22.0")}, version="0.22.0"))
        summ = self.summary({"brief": summary_entry(8, 10, code=1)})
        rc, out = self.merge([bad, older], [summ], ["brief"])
        self.assertEqual(rc, 5, out)
        self.assertIn("warning: previous record 1 ignored: the file does not parse as JSON", out)
        self.assertNotIn("no baseline", out)

    def test_no_usable_record_among_several_is_no_baseline(self):
        bad = self.write(None, raw="{not json")
        summ = self.summary({"brief": summary_entry(1, 10, code=1)})
        rc, out = self.merge([bad, "-"], [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("warning: previous record 1 ignored", out)
        self.assertIn("warning: no baseline: no previous record was usable", out)

    def test_carried_entry_with_exit_code_is_valid(self):
        failed = entry(0, 0, rate=None)
        failed["exit_code"] = 3
        prev = self.write(record({"brief": failed}))
        rc, out = self.merge(prev, [], [])
        self.assertEqual(rc, 0, out)
        self.assertNotIn("warning", out)
        self.assertEqual(self.result()["skills"]["brief"], failed)

    def test_usage_errors(self):
        self.assertEqual(self.merge("-", [], [], version="v1")[0], 2)
        self.assertEqual(self.merge("-", [], [], last_tag="0.1.0")[0], 2)
        self.assertEqual(self.merge("-", [], ["Bad"])[0], 2)
        self.assertEqual(self.merge("-", [], [], confirmed="a;b")[0], 2)
        self.assertEqual(self.run_tool()[0], 2)


class StampTest(Case):
    def test_stamp_sets_version_and_measured_skills_only(self):
        path = self.write(record({"brief": entry(9, 10, measured_at="0.24.0"),
                                  "plan": entry(7, 10, measured_at="0.21.0")},
                                 version="0.24.0"))
        rc, out = self.run_tool("stamp", "--record", path, "--version", "0.24.1",
                                "--measured", "brief", "--measured", "absent")
        self.assertEqual(rc, 0, out)
        with open(path) as fh:
            data = json.load(fh)
        self.assertEqual(data["version"], "0.24.1")
        self.assertEqual(data["skills"]["brief"]["measured_at"], "0.24.1")
        self.assertEqual(data["skills"]["plan"]["measured_at"], "0.21.0")
        self.assertNotIn("absent", data["skills"])

    def test_stamp_refuses_invalid_record(self):
        path = self.write(None, raw="{")
        rc, out = self.run_tool("stamp", "--record", path, "--version", "0.24.1")
        self.assertEqual(rc, 1, out)
        rc, out = self.run_tool("stamp", "--record", os.path.join(self.dir, "none.json"),
                                "--version", "0.24.1")
        self.assertEqual(rc, 1, out)

    def test_stamp_usage(self):
        path = self.write(record({}))
        rc, _ = self.run_tool("stamp", "--record", path, "--version", "next")
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
