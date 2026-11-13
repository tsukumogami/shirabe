#!/usr/bin/env python3
"""Tests for scripts/lib/check-evals-shape.py: the tier-2 release-subset rule,
the script-graded case shape, and the hand-off targets.

Usage: python3 scripts/lib/check-evals-shape_test.py

Writes throwaway evals.json files and fixture repositories (each its own
`git init`) and runs the checker on them. Copies of the real tree, made once
into a temporary repository, take the case deletions and the template
mutations, so the checkout is never changed. Every check runs with no koto on
PATH: the shape check reads templates as text. The older rules (names,
prompts, criteria, the reference-only exemption) are covered by
scripts/check-skill_test.sh.

Needs git. koto is needed only by test_verdicts_are_the_same_with_koto_on_path,
which runs the checker again with koto on PATH and fails without it.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check-evals-shape.py")
RUNNER = os.path.join(HERE, "script-cases.py")
ROOT = os.path.dirname(os.path.dirname(HERE))
_TMP = tempfile.TemporaryDirectory()

# A PATH with python3 and git but no koto, so no verdict can lean on it.
NOKOTO_BIN = os.path.join(_TMP.name, "nokoto-bin")
os.mkdir(NOKOTO_BIN)
os.symlink(sys.executable, os.path.join(NOKOTO_BIN, "python3"))
_GIT = shutil.which("git")
if _GIT:
    os.symlink(_GIT, os.path.join(NOKOTO_BIN, "git"))
NOKOTO_PATH = NOKOTO_BIN + os.pathsep + "/usr/bin" + os.pathsep + "/bin"


def env(koto=False):
    out = dict(os.environ)
    if not koto:
        out["PATH"] = NOKOTO_PATH
    return out


def shape(evals_path, skill_md, koto=False):
    proc = subprocess.run([sys.executable, SCRIPT, evals_path, skill_md],
                          capture_output=True, text=True, env=env(koto))
    return proc.returncode, proc.stdout + proc.stderr


def git(repo, *args):
    subprocess.run(["git", "-C", repo] + list(args), check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    if mode is not None:
        os.chmod(path, mode)


def scenario(name, tier=1, **extra):
    entry = {"name": name, "prompt": "do " + name, "expectations": ["it works"]}
    if tier != 1:
        entry["tier"] = tier
    entry.update(extra)
    return entry


class ShapeCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.skill_md = os.path.join(self.tmp.name, "SKILL.md")
        with open(self.skill_md, "w") as fh:
            fh.write("# skill\n")

    def tearDown(self):
        self.tmp.cleanup()

    def check(self, evals):
        path = os.path.join(self.tmp.name, "evals.json")
        with open(path, "w") as fh:
            json.dump({"evals": evals}, fh)
        return shape(path, self.skill_md)


class ReleaseSubsetTest(ShapeCase):
    def test_one_release_per_behaviour_passes(self):
        rc, out = self.check([
            scenario("plan-a"),
            scenario("merge-a", tier=2, behaviour="merge-refused", release=True),
            scenario("merge-b", tier=2, behaviour="merge-refused"),
            scenario("resume-a", tier=2, behaviour="resume", release=True),
        ])
        self.assertEqual(rc, 0, out)
        self.assertIn("shape ok", out)

    def test_tier1_only_suite_needs_nothing(self):
        rc, out = self.check([scenario("plan-a"), scenario("plan-b")])
        self.assertEqual(rc, 0, out)

    def test_tier2_without_behaviour_fails(self):
        rc, out = self.check([scenario("merge-a", tier=2, release=True)])
        self.assertEqual(rc, 1, out)
        self.assertIn("eval 'merge-a' (#1): a tier-2 entry needs a kebab-case `behaviour`", out)

    def test_behaviour_with_no_release_fails(self):
        rc, out = self.check([scenario("merge-a", tier=2, behaviour="merge-refused"),
                              scenario("merge-b", tier=2, behaviour="merge-refused")])
        self.assertEqual(rc, 1, out)
        self.assertIn("behaviour 'merge-refused' needs exactly one `\"release\": true` entry, has 0",
                      out)

    def test_behaviour_with_two_releases_fails_naming_both(self):
        rc, out = self.check([
            scenario("merge-a", tier=2, behaviour="merge-refused", release=True),
            scenario("merge-b", tier=2, behaviour="merge-refused", release=True),
        ])
        self.assertEqual(rc, 1, out)
        self.assertIn("has 2: eval 'merge-a' (#1), eval 'merge-b' (#2)", out)

    def test_release_must_be_true(self):
        rc, out = self.check([scenario("merge-a", tier=2, behaviour="m", release=True),
                              scenario("merge-b", tier=2, behaviour="m", release=False)])
        self.assertEqual(rc, 1, out)
        self.assertIn("eval 'merge-b' (#2): `release` is only ever `true`", out)

    def test_tier1_entry_with_behaviour_or_release_fails(self):
        for extra in ({"behaviour": "x"}, {"release": True}):
            with self.subTest(extra=extra):
                rc, out = self.check([scenario("plan-a", **extra)])
                self.assertEqual(rc, 1, out)
                self.assertIn("belong on tier-2 entries", out)

    def test_name_with_a_comma_fails(self):
        rc, out = self.check([scenario("plan,a")])
        self.assertEqual(rc, 1, out)
        self.assertIn("`name` can't contain a comma", out)

    def test_tier_outside_one_and_two_fails(self):
        # Every reader takes tier-2 as `tier` other than 1; a 3, a "2" or a
        # boolean would read differently to different readers (shirabe#880).
        for bad in (3, 0, "2", True, None):
            entry = scenario("merge-a", tier=2, behaviour="merge-refused", release=True)
            entry["tier"] = bad
            rc, out = self.check([entry])
            self.assertEqual(rc, 1, (bad, out))
            self.assertIn("`tier` is 1 or 2 (absent means 1), not %s" % json.dumps(bad), out)
            self.assertNotIn("behaviour", out, (bad, out))

    def test_tier_one_and_two_pass(self):
        rc, out = self.check([scenario("plan-a", tier=1),
                              scenario("merge-a", tier=2, behaviour="merge-refused", release=True)])
        self.assertEqual(rc, 0, out)

    def test_behaviour_must_be_kebab_case(self):
        rc, out = self.check([scenario("merge-a", tier=2, behaviour="Merge Refused", release=True)])
        self.assertEqual(rc, 1, out)
        self.assertIn("needs a kebab-case `behaviour`", out)


def script_case(name="handoff-execute-contract", **extra):
    entry = {"id": 34, "name": name, "grader": "script", "handoff": "execute",
             "run": "scripts/check-handoff.sh deliver execute"}
    entry.update(extra)
    return entry


class Fixture:
    """A fixture repository: its own `git init`, a stand-in check-handoff.sh,
    scripts/lib/script-cases.py copied in, and the skills a case names."""

    def __init__(self, skill="deliver", others=("execute",)):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.realpath(self.tmp.name)
        self.skill = skill
        write(self.path("scripts/check-handoff.sh"), "#!/bin/sh\nexit 0\n", 0o755)
        write(self.path("scripts/release-eval-check.sh"), "#!/bin/sh\nexit 0\n", 0o755)
        os.makedirs(self.path("scripts/lib"))
        shutil.copy(RUNNER, self.path("scripts/lib/script-cases.py"))
        write(self.path("skills/%s/SKILL.md" % skill), "# %s\n" % skill)
        for other in others:
            os.makedirs(self.path("skills/%s" % other), exist_ok=True)
        git(self.root, "init", "-q")
        self.commit()

    def path(self, rel):
        return os.path.join(self.root, rel)

    def commit(self):
        git(self.root, "add", "-A")

    def template(self, name, text):
        write(self.path("skills/%s/koto-templates/%s" % (self.skill, name)), text)

    def evals(self, evals):
        write(self.path("skills/%s/evals/evals.json" % self.skill), json.dumps({"evals": evals}))

    def check(self, evals=None):
        if evals is not None:
            self.evals(evals)
        return shape(self.path("skills/%s/evals/evals.json" % self.skill),
                     self.path("skills/%s/SKILL.md" % self.skill))

    def runner(self):
        proc = subprocess.run([sys.executable, self.path("scripts/lib/script-cases.py"),
                               self.skill], capture_output=True, text=True, env=env())
        return proc.returncode, proc.stdout + proc.stderr

    def close(self):
        self.tmp.cleanup()


class ScriptCaseTest(unittest.TestCase):
    """A `grader: script` case needs name, run and handoff, and no prompt or criteria."""

    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.close()

    def check(self, evals):
        return self.fx.check(evals)

    def test_script_case_without_prompt_or_expectations_passes(self):
        rc, out = self.check([scenario("plan-a"), script_case()])
        self.assertEqual(rc, 0, out)
        self.assertIn("shape ok", out)

    def test_script_case_needs_run_handoff_and_name(self):
        for key in ("run", "handoff", "name"):
            for bad in (None, "", "  "):
                with self.subTest(key=key, bad=bad):
                    entry = script_case()
                    if bad is None:
                        del entry[key]
                    else:
                        entry[key] = bad
                    rc, out = self.check([entry])
                    self.assertEqual(rc, 1, out)
                    if key == "name":
                        self.assertIn("missing or empty `name`", out)
                    else:
                        self.assertIn("a `grader: script` case needs a non-empty `%s`" % key, out)

    def test_script_case_carrying_prompt_or_expectations_fails(self):
        for key, value in (("prompt", "do it"), ("expectations", ["it works"])):
            with self.subTest(key=key):
                rc, out = self.check([script_case(**{key: value})])
                self.assertEqual(rc, 1, out)
                self.assertIn("eval 'handoff-execute-contract' (#1): a `grader: script` case "
                              "runs a command, so it carries no `%s`" % key, out)

    def test_graded_case_still_needs_prompt_and_expectations(self):
        no_prompt = scenario("plan-a")
        del no_prompt["prompt"]
        no_criteria = scenario("plan-b")
        del no_criteria["expectations"]
        rc, out = self.check([script_case(), no_prompt, no_criteria])
        self.assertEqual(rc, 1, out)
        self.assertIn("eval 'plan-a' (#2): missing or empty `prompt`", out)
        self.assertIn("eval 'plan-b' (#3): needs a non-empty `expectations` or `assertions` list",
                      out)

    def test_unknown_grader_keeps_graded_rules(self):
        entry = script_case(grader="scripted")
        rc, out = self.check([entry])
        self.assertEqual(rc, 1, out)
        self.assertIn("missing or empty `prompt`", out)

    def test_handoff_and_run_disagree(self):
        rc, out = self.check([script_case(handoff="scope")])
        self.assertEqual(rc, 1, out)
        self.assertIn("its `handoff` is `scope`, but its `run` checks the hand-off to `execute`",
                      out)

    def test_run_from_another_skill(self):
        os.makedirs(self.fx.path("skills/work-on"))
        rc, out = self.check([script_case(handoff="work-on",
                                          run="scripts/check-handoff.sh execute work-on")])
        self.assertEqual(rc, 1, out)
        self.assertIn("its `run` checks the hand-off from `execute`, a skill other than "
                      "`deliver`, whose file holds the case", out)


class ContainmentTest(unittest.TestCase):
    """The shape check refuses every `run` the runner refuses, with the same rule."""

    @classmethod
    def setUpClass(cls):
        cls.fx = Fixture()
        fx = cls.fx
        write(fx.path("scripts/cases/untracked.sh"), "#!/bin/sh\nexit 0\n", 0o755)
        os.makedirs(fx.path("scripts/cases"), exist_ok=True)
        os.symlink("../check-handoff.sh", fx.path("scripts/cases/link.sh"))
        git(fx.root, "add", "scripts/cases/link.sh")

    @classmethod
    def tearDownClass(cls):
        cls.fx.close()

    def test_each_break_is_refused_by_both_with_one_rule(self):
        runs = [
            "scripts/release-eval-check.sh deliver execute",
            "scripts/cases/untracked.sh",
            "scripts/cases/link.sh deliver execute",
            "scripts/check-handoff.sh .. execute",
            "scripts/check-handoff.sh --all execute",
            "scripts/check-handoff.sh deliver;id execute",
            "scripts/check-handoff.sh deliver nosuchskill",
        ]
        for run in runs:
            with self.subTest(run=run):
                handoff = run.split(" ")[-1] if run.startswith("scripts/check-handoff.sh") \
                    else "execute"
                rc, out = self.fx.check([script_case(handoff=handoff, run=run)])
                self.assertEqual(rc, 1, out)
                rrc, rout = self.fx.runner()
                self.assertEqual(rrc, 1, rout)
                m = re.search(r"^FAIL 34 handoff-execute-contract: refused: (.*)$", rout, re.M)
                self.assertIsNotNone(m, rout)
                rule = m.group(1)
                self.assertIn("handoff-execute-contract' (#1): %s" % rule, out)

    def test_a_contained_run_passes_both(self):
        rc, out = self.fx.check([script_case()])
        self.assertEqual(rc, 0, out)


DIRECTIVE_BODY = "\n## work\n\nRun `/shirabe:review --koto-leg={{REQ}}:review`.\n"
SOURCES = {
    "gate": ("---\nname: demo\ninitial_state: work\nstates:\n  work:\n    gates:\n"
             "      review_leg:\n        type: request-leg\n        request: \"{{REQ}}\"\n"
             "        leg: review\n    transitions:\n      - target: done\n"
             "  done:\n    terminal: true\n---\n\n## work\n\nWait.\n",
             ["request-leg gate review_leg in state work"]),
    "directive": ("---\nname: demo\ninitial_state: work\nstates:\n  work:\n"
                  "    transitions:\n      - target: done\n  done:\n    terminal: true\n---\n"
                  + DIRECTIVE_BODY,
                  ["--koto-leg=<req>:review in the directive of state work"]),
    "default_template": ("---\nname: demo\ninitial_state: work\nstates:\n  work:\n"
                         "    materialize_children:\n      from_field: tasks\n"
                         "      default_template: ../../review/koto-templates/review.md\n"
                         "  done:\n    terminal: true\n---\n\n## work\n\nSpawn.\n",
                         ["`default_template: ../../review/koto-templates/review.md` "
                          "reference in state work"]),
}
REVIEW_CASE = {"name": "handoff-review", "grader": "script", "handoff": "review",
               "run": "scripts/check-handoff.sh demo review"}


class DerivationTest(unittest.TestCase):
    """Targets come from the templates, one source at a time."""

    def setUp(self):
        self.fx = Fixture(skill="demo", others=("review",))

    def tearDown(self):
        self.fx.close()

    def test_each_source_needs_a_case(self):
        for kind, (text, needles) in sorted(SOURCES.items()):
            with self.subTest(source=kind):
                self.fx.template("demo.md", text)
                rc, out = self.fx.check([scenario("plan-a")])
                self.assertEqual(rc, 1, out)
                self.assertIn("hand-off target `review`", out)
                self.assertIn("skills/demo/koto-templates/demo.md", out)
                for needle in needles:
                    self.assertIn(needle, out)
                rc, out = self.fx.check([scenario("plan-a"), REVIEW_CASE])
                self.assertEqual(rc, 0, out)
                self.assertIn("hand-off targets: review", out)
                os.remove(self.fx.path("skills/demo/koto-templates/demo.md"))

    def test_a_mermaid_file_derives_nothing(self):
        for kind, (text, _) in sorted(SOURCES.items()):
            with self.subTest(source=kind):
                self.fx.template("demo.mermaid.md", text)
                rc, out = self.fx.check([scenario("plan-a")])
                self.assertEqual(rc, 0, out)
                self.assertIn("hand-off targets: none", out)

    def test_a_templated_directive_leg_needs_a_declaration(self):
        self.fx.template("demo.md", SOURCES["directive"][0].replace(":review`", ":{{LEG}}`"))
        rc, out = self.fx.check([scenario("plan-a")])
        self.assertEqual(rc, 1, out)
        self.assertIn("is a templated leg (`{{LEG}}`) with no declared target", out)
        self.assertIn("directive of state work of skills/demo/koto-templates/demo.md", out)
        # A declared target must answer a leg.
        write(self.fx.path("skills/review/SKILL.md"), "# review\n")
        rc, out = self.fx.check([scenario("plan-a"), REVIEW_CASE])
        self.assertEqual(rc, 1, out)
        self.assertIn("declares `review` for the templated leg, but skills/review/SKILL.md "
                      "doesn't declare --koto-leg", out)
        write(self.fx.path("skills/review/SKILL.md"), "# review\n\nTakes --koto-leg.\n")
        rc, out = self.fx.check([scenario("plan-a"), REVIEW_CASE])
        self.assertEqual(rc, 0, out)
        self.assertIn("hand-off targets: review (declared for the templated leg)", out)

    def test_a_templated_gate_leg_needs_a_declaration(self):
        self.fx.template("demo.md", SOURCES["gate"][0].replace("leg: review", 'leg: "{{LEG}}"'))
        rc, out = self.fx.check([scenario("plan-a")])
        self.assertEqual(rc, 1, out)
        self.assertIn("The request-leg gate review_leg in state work of "
                      "skills/demo/koto-templates/demo.md is a templated leg (`{{LEG}}`) "
                      "with no declared target", out)


class RealTreeTest(unittest.TestCase):
    """The real tree, and copies of it in a temporary repository."""

    @classmethod
    def setUpClass(cls):
        cls.copy = os.path.join(_TMP.name, "tree")
        os.mkdir(cls.copy)
        files = subprocess.run(["git", "-C", ROOT, "ls-files", "-co", "--exclude-standard", "-z"],
                               check=True, capture_output=True).stdout
        pack = subprocess.Popen(["tar", "-cf", "-", "--null", "-T", "-"], cwd=ROOT,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        unpack = subprocess.Popen(["tar", "-xf", "-", "-C", cls.copy], stdin=pack.stdout)
        pack.stdout.close()
        pack.stdin.write(files)
        pack.stdin.close()
        if pack.wait() != 0 or unpack.wait() != 0:
            raise RuntimeError("could not copy the tree")
        git(cls.copy, "init", "-q")
        git(cls.copy, "add", "-A")
        cls.saved = {}

    def tearDown(self):
        for path, text in self.saved.items():
            write(path, text)
        self.saved.clear()

    def edit(self, rel, change):
        path = os.path.join(self.copy, rel)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        self.saved.setdefault(path, text)
        new = change(text)
        self.assertNotEqual(new, text, "the mutation of %s changed nothing" % rel)
        write(path, new)

    def edit_evals(self, skill, change):
        def apply(text):
            data = json.loads(text)
            data["evals"] = change(data["evals"])
            return json.dumps(data, indent=2) + "\n"
        self.edit("skills/%s/evals/evals.json" % skill, apply)

    def check_copy(self, skill, koto=False):
        return shape(os.path.join(self.copy, "skills", skill, "evals", "evals.json"),
                     os.path.join(self.copy, "skills", skill, "SKILL.md"), koto)

    def test_every_skill_passes_and_lists_its_targets(self):
        want = {"deliver": "execute, scope", "execute": "work-on",
                "coordinate": "deliver, execute, scope, work-on (declared for the templated leg)"}
        seen = 0
        for skill in sorted(os.listdir(os.path.join(ROOT, "skills"))):
            evals = os.path.join(ROOT, "skills", skill, "evals", "evals.json")
            if not os.path.isfile(evals):
                continue
            seen += 1
            with self.subTest(skill=skill):
                rc, out = shape(evals, os.path.join(ROOT, "skills", skill, "SKILL.md"))
                self.assertEqual(rc, 0, out)
                self.assertIn("shape ok; hand-off targets: %s\n" % want.get(skill, "none"), out)
        self.assertGreater(seen, 3)

    def test_verdicts_are_the_same_with_koto_on_path(self):
        if shutil.which("koto") is None:
            self.fail("koto is not on PATH, so the with-koto half can't run")
        self.assertIsNone(shutil.which("koto", path=NOKOTO_PATH))
        for skill in ("coordinate", "deliver", "execute", "scope"):
            with self.subTest(skill=skill):
                self.assertEqual(self.check_copy(skill), self.check_copy(skill, koto=True))
        self.edit_evals("deliver", lambda e: [c for c in e if c.get("id") != 35])
        self.assertEqual(self.check_copy("deliver"), self.check_copy("deliver", koto=True))

    def test_deleting_a_case_names_its_target(self):
        for skill, cid, needles in (
                ("deliver", 35, ["`scope`", "skills/deliver/koto-templates/deliver.md",
                                 "gate scope_leg in state scope_run"]),
                ("deliver", 34, ["`execute`", "skills/deliver/koto-templates/deliver.md",
                                 "gate exec_leg in state execute_run"]),
                ("execute", 86, ["`work-on`", "`default_template: ../../work-on/koto-templates/"
                                 "work-on.md` reference in state spawn_and_await of "
                                 "skills/execute/koto-templates/execute.md"])):
            with self.subTest(case=cid):
                self.edit_evals(skill, lambda e: [c for c in e if c.get("id") != cid])
                rc, out = self.check_copy(skill)
                self.assertEqual(rc, 1, out)
                self.assertIn("has no `grader: script` case naming it in `handoff`", out)
                for needle in needles:
                    self.assertIn(needle, out)
                self.tearDown()

    def test_a_new_gate_needs_a_case(self):
        gate = ("      work_on_leg:\n        type: request-leg\n        request: \"{{REQ}}\"\n"
                "        leg: work-on\n")
        self.edit("skills/deliver/koto-templates/deliver.md",
                  lambda t: t.replace("    gates:\n      exec_leg:\n",
                                      "    gates:\n" + gate + "      exec_leg:\n", 1))
        rc, out = self.check_copy("deliver")
        self.assertEqual(rc, 1, out)
        self.assertIn("hand-off target `work-on` (from the request-leg gate work_on_leg in "
                      "state execute_run of skills/deliver/koto-templates/deliver.md)", out)
        self.edit_evals("deliver", lambda e: e + [{
            "id": 99, "name": "handoff-work-on-contract", "grader": "script",
            "handoff": "work-on", "run": "scripts/check-handoff.sh deliver work-on"}])
        rc, out = self.check_copy("deliver")
        self.assertEqual(rc, 0, out)
        self.assertIn("hand-off targets: execute, scope, work-on", out)

    def test_coordinate_without_its_cases_names_the_templated_leg(self):
        self.edit_evals("coordinate", lambda e: [c for c in e if c.get("grader") != "script"])
        rc, out = self.check_copy("coordinate")
        self.assertEqual(rc, 1, out)
        self.assertIn("The request-leg gate leg_result in state wait_leg of "
                      "skills/coordinate/koto-templates/coordinate.md is a templated leg "
                      "(`{{WAIT_LEG}}`) with no declared target", out)

    def test_a_declared_target_must_take_a_leg(self):
        self.edit_evals("coordinate", lambda e: e + [{
            "id": 99, "name": "handoff-explore-contract", "grader": "script",
            "handoff": "explore", "run": "scripts/check-handoff.sh coordinate explore"}])
        rc, out = self.check_copy("coordinate")
        self.assertEqual(rc, 1, out)
        self.assertIn("declares `explore` for the templated leg, but skills/explore/SKILL.md "
                      "doesn't declare --koto-leg", out)

    def test_handoff_and_run_agree_on_the_real_cases(self):
        def retarget(evals):
            for c in evals:
                if c.get("id") == 35:
                    c["handoff"] = "execute"
            return evals
        self.edit_evals("deliver", retarget)
        rc, out = self.check_copy("deliver")
        self.assertEqual(rc, 1, out)
        self.assertIn("its `handoff` is `execute`, but its `run` checks the hand-off to `scope`",
                      out)
        self.tearDown()
        self.edit_evals("deliver", lambda e: e + [{
            "id": 99, "name": "other-skill", "grader": "script", "handoff": "work-on",
            "run": "scripts/check-handoff.sh execute work-on"}])
        rc, out = self.check_copy("deliver")
        self.assertEqual(rc, 1, out)
        self.assertIn("its `run` checks the hand-off from `execute`, a skill other than "
                      "`deliver`", out)


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        _TMP.cleanup()
