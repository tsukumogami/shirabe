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
SET_A = "sha256:" + "a" * 64
SET_B = "sha256:" + "b" * 64


def entry(passed=9, graded=10, runs=1, runs_passed=1, rate="auto", measured_at="0.23.0",
          models=("sonnet",), session_model=None, scenario_set=None):
    out = {"runs": runs, "runs_passed": runs_passed, "assertions_passed": passed,
           "assertions_graded": graded, "models": list(models), "measured_at": measured_at}
    if session_model is not None:
        out["session_model"] = session_model
    if scenario_set is not None:
        out["scenario_set"] = scenario_set
    if rate == "auto":
        out["pass_rate"] = round(passed / graded, 4)
    elif rate is not None:
        out["pass_rate"] = rate
    return out


def record(skills, version="0.23.0", last_tag="v0.22.0"):
    return {"schema": "eval-pass-rates/v1", "version": version, "last_tag": last_tag,
            "skills": skills}


def summary_entry(passed=9, graded=10, code=0, runs=1, runs_passed=None, models=("sonnet",),
                  session_model=None, scenario_set=None):
    if runs_passed is None:
        runs_passed = runs if code == 0 else 0
    out = {"runs": runs, "runs_passed": runs_passed, "assertions_passed": passed,
           "assertions_graded": graded, "models": list(models), "exit_code": code}
    if session_model is not None:
        out["session_model"] = session_model
    if scenario_set is not None:
        out["scenario_set"] = scenario_set
    return out


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
              version="0.24.0", reason="", tolerance=None):
        args = ["merge", "--version", version,
                "--last-tag", last_tag, "--out", self.out, "--confirmed", confirmed]
        if tolerance is not None:
            args += ["--tolerance", tolerance]
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
            "pass_rate": 0.9333, "models": ["haiku", "sonnet"], "session_model": "default",
            "measured_at": "0.24.0"})

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



class ReferenceTest(Case):
    """A rate is compared only with one measured on the same models, session model,
    scenarios and run count."""

    def test_session_model_change_is_a_new_reference_not_a_drop(self):
        prev = self.write(record({"brief": entry(10, 10, models=("sonnet",))}))
        summ = self.summary({"brief": summary_entry(5, 10, code=1, session_model="sonnet")})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("new reference: brief (no earlier measurement on models sonnet, "
                      "session model sonnet, 1 run(s))", out)
        self.assertNotIn("confirm:", out)
        self.assertEqual(self.result()["skills"]["brief"]["session_model"], "sonnet")

    def test_scenario_model_change_is_a_new_reference(self):
        prev = self.write(record({"execute": entry(10, 10, models=("inherit", "sonnet"))}))
        summ = self.summary({"execute": summary_entry(5, 10, code=1)})
        rc, out = self.merge(prev, [summ], ["execute"])
        self.assertEqual(rc, 0, out)
        self.assertIn("new reference: execute", out)

    def test_record_without_session_model_reads_as_default(self):
        prev = self.write(record({"brief": entry(10, 10)}))
        summ = self.summary({"brief": summary_entry(5, 10, code=1, session_model="default")})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 5, out)
        self.assertNotIn("new reference", out)

    def test_later_release_compares_with_the_new_reference(self):
        prev = self.write(record({"brief": entry(8, 10, session_model="sonnet",
                                                 measured_at="0.27.0")}, version="0.27.0"))
        summ = self.summary({"brief": summary_entry(7, 10, code=1, session_model="sonnet")})
        rc, out = self.merge(prev, [summ], ["brief"], last_tag="v0.27.0", version="0.28.0")
        self.assertEqual(rc, 5, out)
        self.assertIn("drop: brief", out)

    def test_older_matching_entry_behind_a_newer_other_one(self):
        newer = self.write(record({"brief": entry(10, 10, measured_at="0.25.0")},
                                  version="0.25.0", last_tag="v0.24.0"))
        older = self.write(record({"brief": entry(9, 10, session_model="sonnet",
                                                  measured_at="0.24.0")},
                                  version="0.24.0", last_tag="v0.23.0"))
        summ = self.summary({"brief": summary_entry(8, 10, code=1, session_model="sonnet")})
        rc, out = self.merge([newer, older], [summ], ["brief"], last_tag="v0.25.0",
                             version="0.26.0")
        self.assertEqual(rc, 5, out)  # 0.8 against 0.24.0's 0.9, not 0.25.0's 1.0
        self.assertIn("0.9000     0.24.0", out)

    def test_run_count_change_is_a_new_reference(self):
        prev = self.write(record({"brief": entry(29, 30, runs=3, runs_passed=3,
                                                 session_model="sonnet")}))
        summ = self.summary({"brief": summary_entry(5, 10, code=1, runs=1,
                                                    session_model="sonnet")})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("new reference: brief (no earlier measurement on models sonnet, "
                      "session model sonnet, 1 run(s))", out)

    def test_same_run_count_is_compared(self):
        prev = self.write(record({"brief": entry(29, 30, runs=3, runs_passed=3,
                                                 session_model="sonnet")}))
        summ = self.summary({"brief": summary_entry(20, 30, code=1, runs=3,
                                                    session_model="sonnet")})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 5, out)

    def test_scenario_set_change_is_a_new_reference(self):
        prev = self.write(record({"brief": entry(10, 10, scenario_set=SET_A)}))
        summ = self.summary({"brief": summary_entry(5, 10, code=1, scenario_set=SET_B)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("new reference: brief (no earlier measurement on models sonnet, "
                      "session model default, 1 run(s), scenario set %s)" % SET_B[:19], out)
        self.assertEqual(self.result()["skills"]["brief"]["scenario_set"], SET_B)

    def test_same_scenario_set_is_compared(self):
        prev = self.write(record({"brief": entry(10, 10, scenario_set=SET_A)}))
        summ = self.summary({"brief": summary_entry(5, 10, code=1, scenario_set=SET_A)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 5, out)
        self.assertIn("drop: brief", out)

    def test_entry_without_scenario_set_matches_only_one_without(self):
        prev = self.write(record({"brief": entry(10, 10)}))
        summ = self.summary({"brief": summary_entry(5, 10, code=1, scenario_set=SET_A)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("new reference: brief", out)
        summ = self.summary({"brief": summary_entry(5, 10, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 5, out)

    def test_invalid_scenario_set(self):
        prev = self.write(record({"brief": entry(10, 10, scenario_set="sha256:XYZ")}))
        summ = self.summary({"brief": summary_entry(5, 10, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("scenario_set is not a sha256: digest", out)
        self.assertNotIn("XYZ", out)
        summ = self.summary({"brief": summary_entry(5, 10, code=1, scenario_set=7)})
        rc, out = self.merge("-", [summ], ["brief"])
        self.assertNotEqual(rc, 0, out)

    def test_invalid_session_model_in_a_record_drops_the_record(self):
        prev = self.write(record({"brief": entry(10, 10, session_model="-x")}))
        summ = self.summary({"brief": summary_entry(5, 10, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 0, out)
        self.assertIn("session_model is not a model name", out)


class ToleranceTest(Case):
    def test_drop_within_tolerance_passes(self):
        prev = self.write(record({"brief": entry(97, 100)}))
        summ = self.summary({"brief": summary_entry(92, 100, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"], tolerance="0.05")
        self.assertEqual(rc, 0, out)

    def test_drop_beyond_tolerance_fails(self):
        prev = self.write(record({"brief": entry(97, 100)}))
        summ = self.summary({"brief": summary_entry(91, 100, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"], tolerance="0.05")
        self.assertEqual(rc, 5, out)

    def test_default_tolerance_flags_any_lower_rate(self):
        prev = self.write(record({"brief": entry(97, 100)}))
        summ = self.summary({"brief": summary_entry(96, 100, code=1)})
        rc, out = self.merge(prev, [summ], ["brief"])
        self.assertEqual(rc, 5, out)

    def test_invalid_tolerance_is_usage(self):
        for value in ("x", "-0.1", "1.5", "nan"):
            with self.subTest(value=value):
                rc, out = self.merge("-", [], [], tolerance=value)
                self.assertEqual(rc, 2, out)


def script_summary_entry(cases, scenario_set=SET_A):
    """A script-cases.py summary entry, runner-only fields included; cases is
    [(name, verdict)]."""
    run = len(cases)
    passed = sum(1 for _, verdict in cases if verdict == "pass")
    items = []
    for index, (name, verdict) in enumerate(cases):
        item = {"id": index + 1, "name": name, "verdict": verdict}
        if verdict == "fail":
            item["reason"] = "exit 1\nFAIL something"
        items.append(item)
    return {"cases_run": run, "cases_passed": passed,
            "pass_rate": passed / run if run else None,
            "assertions": {"passed": passed, "graded": run},
            "scenario_set": scenario_set, "cases": items,
            "refused": [{"id": 99, "name": "graded-one"}]}


def script_record_entry(cases, scenario_set=SET_A, measured_at="0.40.0"):
    """A record entry a script run wrote; cases is [(name, verdict)]."""
    run = len(cases)
    passed = sum(1 for _, verdict in cases if verdict == "pass")
    out = {"runs": 1, "runs_passed": 1 if passed == run else 0,
           "assertions_passed": passed, "assertions_graded": run, "models": ["script"],
           "scenario_set": scenario_set,
           "cases": [{"name": n, "verdict": v} for n, v in cases],
           "measured_at": measured_at}
    if run:
        out["pass_rate"] = round(passed / run, 4)
    return out


class ScriptRunTest(Case):
    """A run whose summaries are script-cases-summary/v1."""

    THIS_RUN = [("a", "fail"), ("b", "pass")]

    def script_summary(self, skills):
        return self.write({"schema": "script-cases-summary/v1", "skills": skills})

    def deliver_run(self, previous, confirmed="", tolerance=None):
        summ = self.script_summary({"deliver": script_summary_entry(self.THIS_RUN)})
        return self.merge(previous, [summ], ["deliver"], confirmed=confirmed,
                          tolerance=tolerance, last_tag="v0.40.0", version="0.41.0")

    def baseline(self, cases, **kwargs):
        return self.write(record({"deliver": script_record_entry(cases, **kwargs)},
                                 version="0.40.0", last_tag="v0.39.0"))

    def test_record_built_from_this_run_alone(self):
        summ = self.script_summary({
            "deliver": script_summary_entry([("handoff-execute-contract", "pass"),
                                             ("handoff-scope-contract", "pass")]),
            "brief": script_summary_entry([])})
        prev = self.write(record({"scope": script_record_entry([("x", "pass")]),
                                  "deliver": script_record_entry([("y", "pass")])},
                                 version="0.40.0", last_tag="v0.39.0"))
        rc, out = self.merge(prev, [summ], ["deliver", "brief"], last_tag="v0.40.0",
                             version="0.41.0")
        self.assertEqual(rc, 0, out)
        self.assertNotIn("case ", out)
        data = self.result()
        self.assertEqual(sorted(data["skills"]), ["brief", "deliver"])
        self.assertEqual(data["skills"]["deliver"], {
            "runs": 1, "runs_passed": 1, "assertions_passed": 2, "assertions_graded": 2,
            "pass_rate": 1.0, "models": ["script"], "scenario_set": SET_A,
            "cases": [{"name": "handoff-execute-contract", "verdict": "pass"},
                      {"name": "handoff-scope-contract", "verdict": "pass"}],
            "measured_at": "0.41.0"})
        self.assertEqual(data["skills"]["brief"], {
            "runs": 1, "runs_passed": 1, "assertions_passed": 0, "assertions_graded": 0,
            "models": ["script"], "scenario_set": SET_A, "cases": [],
            "measured_at": "0.41.0"})

    def test_rate_is_rounded_and_failing_run_has_runs_passed_0(self):
        summ = self.script_summary({"deliver": script_summary_entry(
            [("a", "pass"), ("b", "pass"), ("c", "fail")])})
        rc, out = self.merge("-", [summ], ["deliver"], version="0.41.0")
        self.assertEqual(rc, 5, out)
        entry = self.result()["skills"]["deliver"]
        self.assertEqual(entry["pass_rate"], 0.6667)
        self.assertEqual(entry["runs_passed"], 0)

    def test_labels(self):
        cases = [
            ("a pass b pass", [("a", "pass"), ("b", "pass")], {}, "regressed"),
            ("a fail b pass", [("a", "fail"), ("b", "pass")], {}, "still failing"),
            ("a fail b fail", [("a", "fail"), ("b", "fail")], {}, "still failing"),
            ("higher rate", [("a", "fail"), ("b", "pass"), ("c", "pass")], {}, "regressed"),
            ("no a, equal rate", [("b", "pass"), ("c", "fail")], {}, "failing, no baseline"),
            ("no a, higher rate", [("b", "pass")], {}, "regressed"),
            ("other scenario set", [("a", "pass")], {"scenario_set": SET_B}, "regressed"),
        ]
        for label, base, kwargs, expected in cases:
            with self.subTest(label=label):
                rc, out = self.deliver_run(self.baseline(base, **kwargs))
                self.assertIn("case deliver/a: %s\n" % expected, out)
                self.assertNotIn("case deliver/b", out)
        with self.subTest(label="no previous record"):
            rc, out = self.deliver_run("-")
            self.assertIn("case deliver/a: failing, no baseline\n", out)
        with self.subTest(label="graded entry only"):
            prev = self.write(record({"deliver": entry(10, 10)}))
            rc, out = self.deliver_run(prev)
            self.assertIn("case deliver/a: failing, no baseline\n", out)

    def test_label_uses_newest_script_entry(self):
        newest = self.write(record({"deliver": entry(10, 10, measured_at="0.40.0")},
                                   version="0.40.0", last_tag="v0.39.0"))
        middle = self.baseline([("a", "fail"), ("b", "pass")], measured_at="0.39.0")
        oldest = self.baseline([("a", "pass"), ("b", "pass")], measured_at="0.38.0")
        rc, out = self.deliver_run([newest, middle, oldest])
        self.assertIn("case deliver/a: still failing\n", out)
        self.assertRegex(out, r"deliver\s+0\.5000\s+0\.5000\s+0\.39\.0")

    def test_exit_never_depends_on_baseline(self):
        failed = script_record_entry([])
        failed["exit_code"] = 2
        bad = script_record_entry([("a", "pass")])
        bad["cases"][0]["name"] = "a b"
        baselines = {
            "no previous record": "-",
            "a passed": self.baseline([("a", "pass"), ("b", "pass")]),
            "a failed": self.baseline([("a", "fail"), ("b", "pass")]),
            "no a": self.baseline([("b", "pass")]),
            "exit_code 2": self.write(record({"deliver": failed})),
            "unusable": self.write(record({"deliver": bad})),
            "other scenario set": self.baseline([("a", "pass")], scenario_set=SET_B),
            "graded models": self.write(record({"deliver": entry(10, 10)})),
        }
        for label, prev in baselines.items():
            with self.subTest(label=label):
                rc, out = self.deliver_run(prev)
                self.assertEqual(rc, 5, out)
                self.assertEqual(out.strip().splitlines()[-1],
                                 "confirm: RELEASE_CONFIRMED_DROPS=deliver")

    def test_confirmation_names_skills(self):
        summ = self.script_summary({"deliver": script_summary_entry(self.THIS_RUN),
                                    "scope": script_summary_entry([("s", "fail")]),
                                    "brief": script_summary_entry([("k", "pass")])})
        selected = ["scope", "deliver", "brief"]
        rc, out = self.merge("-", [summ], selected)
        self.assertEqual(rc, 5, out)
        self.assertEqual(out.strip().splitlines()[-1],
                         "confirm: RELEASE_CONFIRMED_DROPS=deliver,scope")
        rc, out = self.merge("-", [summ], selected, confirmed="deliver")
        self.assertEqual(rc, 5, out)
        self.assertEqual(out.strip().splitlines()[-1],
                         "confirm: RELEASE_CONFIRMED_DROPS=deliver,scope")
        rc, out = self.merge("-", [summ], selected, confirmed="deliver,scope")
        self.assertEqual(rc, 0, out)
        self.assertIn("confirmed: deliver\n", out)
        self.assertIn("confirmed: scope\n", out)
        self.assertNotIn("confirm: RELEASE", out)
        clean = self.script_summary({"brief": script_summary_entry([("k", "pass")])})
        rc, out = self.merge("-", [clean], ["brief"], confirmed="brief")
        self.assertEqual(rc, 0, out)
        self.assertNotIn("confirmed:", out)

    def test_missing_summary_is_infrastructure_failure(self):
        summ = self.script_summary({"deliver": script_summary_entry(self.THIS_RUN)})
        rc, out = self.merge("-", [summ], ["deliver", "brief"])
        self.assertEqual(rc, 1, out)
        self.assertIn("infrastructure failure: brief (no summary, recorded as exit 2)", out)
        self.assertNotIn("confirm:", out)
        brief = self.result()["skills"]["brief"]
        self.assertEqual(brief["exit_code"], 2)
        self.assertNotIn("pass_rate", brief)

    def test_tolerance_changes_nothing(self):
        prev = self.baseline([("a", "pass"), ("b", "pass")])
        rc, out = self.deliver_run(prev)
        rc1, out1 = self.deliver_run(prev, tolerance="1")
        self.assertEqual((rc, rc1), (5, 5), out1)
        self.assertIn("case deliver/a: regressed\n", out1)
        self.assertEqual(out1.strip().splitlines()[-1],
                         "confirm: RELEASE_CONFIRMED_DROPS=deliver")

    def bad_cases(self):
        secret = "SECRETVALUE"
        good = script_record_entry([("a", "pass")])

        def with_cases(cases):
            out = copy.deepcopy(good)
            out["cases"] = cases
            return out
        return secret, [
            ("space", with_cases([{"name": secret + " b", "verdict": "pass"}])),
            ("slash", with_cases([{"name": secret + "/b", "verdict": "pass"}])),
            ("newline", with_cases([{"name": secret + "\n", "verdict": "pass"}])),
            ("escape", with_cases([{"name": secret + "\x1b[31m", "verdict": "pass"}])),
            ("empty", with_cases([{"name": "", "verdict": "pass"}])),
            ("non-string", with_cases([{"name": 7, "verdict": "pass"}])),
            ("verdict", with_cases([{"name": "a", "verdict": secret}])),
            ("non-object item", with_cases([secret])),
            ("not a list", with_cases(secret)),
        ]

    def test_case_names_in_records(self):
        secret, cases = self.bad_cases()
        for label, bad in cases:
            with self.subTest(label=label, alone=True):
                prev = self.write(record({"deliver": bad}))
                rc, out = self.deliver_run(prev)
                self.assertEqual(rc, 5, out)
                self.assertIn("warning: no baseline: skills.deliver.cases ", out)
                self.assertIn("case deliver/a: failing, no baseline\n", out)
                self.assertNotIn(secret, out)
            with self.subTest(label=label, alone=False):
                prev = self.write(record({"deliver": bad}))
                older = self.baseline([("a", "fail"), ("b", "pass")], measured_at="0.39.0")
                rc, out = self.deliver_run([prev, older])
                self.assertIn("warning: previous record 1 ignored: skills.deliver.cases ", out)
                self.assertIn("case deliver/a: still failing\n", out)
                self.assertNotIn(secret, out)

    def test_stamp_checks_and_keeps_cases(self):
        secret, cases = self.bad_cases()
        for label, bad in cases:
            with self.subTest(label=label):
                path = self.write(record({"deliver": bad}))
                with open(path) as fh:
                    before = fh.read()
                rc, out = self.run_tool("stamp", "--record", path, "--version", "0.41.0")
                self.assertEqual(rc, 1, out)
                self.assertNotIn(secret, out)
                with open(path) as fh:
                    self.assertEqual(fh.read(), before)
        kept = {"deliver": script_record_entry([("a", "pass"), ("b", "fail")]),
                "scope": script_record_entry([("s", "pass")])}
        path = self.write(record(copy.deepcopy(kept)))
        rc, out = self.run_tool("stamp", "--record", path, "--version", "0.41.0",
                                "--measured", "deliver")
        self.assertEqual(rc, 0, out)
        with open(path) as fh:
            data = json.load(fh)
        for name in kept:
            self.assertEqual(data["skills"][name]["cases"], kept[name]["cases"])

    def test_carried_entry_keeps_cases_in_a_graded_run(self):
        scripted = script_record_entry([("a", "pass")])
        prev = self.write(record({"deliver": scripted}))
        rc, out = self.merge(prev, [], [])
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.result()["skills"]["deliver"], scripted)

    def test_bad_script_summary_is_ignored(self):
        secret = "SECRETVALUE"

        def summary_with(mutate):
            data = script_summary_entry(self.THIS_RUN)
            mutate(data)
            return data
        cases = [
            ("case name", lambda d: d["cases"][0].__setitem__("name", secret + " x")),
            ("verdict", lambda d: d["cases"][0].__setitem__("verdict", secret)),
            ("passed over run", lambda d: d.__setitem__("cases_passed", 3)),
            ("cases_run disagrees", lambda d: d.__setitem__("cases_run", 3)),
            ("cases_passed disagrees", lambda d: d.__setitem__("cases_passed", 0)),
            ("cases missing", lambda d: d.pop("cases")),
            ("bad count", lambda d: d.__setitem__("cases_run", "2")),
            ("bad scenario_set", lambda d: d.__setitem__("scenario_set", secret)),
        ]
        for label, mutate in cases:
            with self.subTest(label=label):
                summ = self.script_summary({"deliver": summary_with(mutate)})
                rc, out = self.merge("-", [summ], ["deliver"])
                self.assertEqual(rc, 1, out)
                self.assertIn("warning: summary 1 ignored: skills.deliver.", out)
                self.assertIn("infrastructure failure: deliver (no summary, recorded as exit 2)",
                              out)
                self.assertNotIn(secret, out)


if __name__ == "__main__":
    unittest.main()
