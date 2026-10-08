#!/usr/bin/env python3
"""Tests for the ablation harness (scripts/ablation/).

The run tests drive the real koto against the fixture, with the model session
replaced by testdata/stub-agent, so they need koto on PATH and no model, no
network and no secret. They read the repository's history at the case's
source commit, so a CI checkout needs fetch-depth 0.

Usage: python3 scripts/ablation/ablation_test.py [-v]
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.realpath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import ablation  # noqa: E402
import records  # noqa: E402

CASE_FILE = os.path.join(HERE, "cases", "work-on-introspection-evidence.json")
STUB = os.path.join(HERE, "testdata", "stub-agent")
PIN = "3cc4c54b8afa95b62c544a0d4b99990ba08d8609"
KEY = "skills/work-on/references/phases/phase-2-introspection.md#L17-L21"
WF = "issue_1"


def load_case():
    with open(CASE_FILE) as fh:
        return json.load(fh)


def ev(obj):
    return json.dumps(obj)


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


def read_text(path):
    with open(path) as fh:
        return fh.read()


def write_bytes(path, data):
    with open(path, "wb") as fh:
        fh.write(data)


class Env:
    """Temporarily set environment variables."""

    def __init__(self, **values):
        self.values = values
        self.saved = {}

    def __enter__(self):
        for k, v in self.values.items():
            self.saved[k] = os.environ.get(k)
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def __exit__(self, *exc):
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


class CaseValidation(unittest.TestCase):
    def test_demonstration_case_is_valid(self):
        self.assertEqual(ablation.validate_case(load_case())["id"], "work-on-introspection-evidence")

    def refused(self, mutate, needle):
        case = load_case()
        mutate(case)
        with self.assertRaises(ablation.Refusal) as cm:
            ablation.validate_case(case)
        self.assertIn(needle, str(cm.exception))

    def test_each_field_is_checked(self):
        cases = [
            (lambda c: c.update(schema="other"), "schema"),
            (lambda c: c.update(id="../escape"), "id must match"),
            (lambda c: c["withhold"].update(source="no-anchor"), "malformed rule key"),
            (lambda c: c["withhold"].update(source="../x.md#L1-L2"), "malformed rule key"),
            (lambda c: c["withhold"].update(source="a.md#L5-L2"), "start after end"),
            (lambda c: c["withhold"].update(source_commit="--output=x"), "source_commit"),
            (lambda c: c.update(deployed_check="checks/work-on-introspection-evidence"), "deployed_check"),
            (lambda c: c.update(deployed_check="no-such-check"), "not an executable check"),
            (lambda c: c["audit"]["pool"][0].update(check="/bin/sh"), "audit check"),
            (lambda c: c["audit"].update(sample_rate=2), "sample_rate"),
            (lambda c: c.update(fixture="fixtures/greet-repo"), "fixture must name"),
            (lambda c: c.update(fixture="no-such-fixture"), "needs repo/"),
            (lambda c: c["setup"].update(workflow="Bad Name"), "setup.workflow"),
            (lambda c: c["setup"].update(template="/abs/koto.md"), "setup.template"),
            (lambda c: c["setup"]["vars"].update(ISSUE_NUMBER="1; rm"), "setup.vars"),
            (lambda c: c["setup"]["vars"].update(PLUGIN_ROOT="x"), "PLUGIN_ROOT"),
            (lambda c: c["setup"].update(evidence=[]), "setup.evidence"),
            (lambda c: c["prompt"].update(with_skill="-p rm"), "prompt.with_skill"),
            (lambda c: c.update(stop_instruction="x" * 3000), "stop_instruction"),
            (lambda c: c.update(model="Sonnet!"), "model"),
            (lambda c: c["limits"].update(max_turns=500), "limits.max_turns"),
        ]
        for mutate, needle in cases:
            with self.subTest(needle=needle):
                self.refused(mutate, needle)

    def test_fixture_with_symlink_or_git_is_refused(self):
        tmp = tempfile.mkdtemp()
        try:
            saved = ablation.FIXTURES_DIR
            ablation.FIXTURES_DIR = tmp
            os.makedirs(os.path.join(tmp, "f", "repo"))
            write_bytes(os.path.join(tmp, "f", "issue.json"), b"{}")
            os.symlink("/etc", os.path.join(tmp, "f", "repo", "link"))
            with self.assertRaisesRegex(ablation.Refusal, "symlink"):
                ablation.fixture_path("f", "t")
            os.remove(os.path.join(tmp, "f", "repo", "link"))
            os.makedirs(os.path.join(tmp, "f", "repo", ".git"))
            with self.assertRaisesRegex(ablation.Refusal, ".git"):
                ablation.fixture_path("f", "t")
        finally:
            ablation.FIXTURES_DIR = saved
            shutil.rmtree(tmp)

    def test_case_selection(self):
        self.assertEqual(ablation.select_case(withhold=KEY, skill="work-on")["id"],
                         "work-on-introspection-evidence")
        with self.assertRaisesRegex(ablation.Refusal, "does not match"):
            ablation.select_case(CASE_FILE, withhold="skills/x.md#L1-L2")
        with self.assertRaisesRegex(ablation.Refusal, "found 0"):
            ablation.select_case(withhold="skills/x.md#L1-L2", skill="work-on")


class Spans(unittest.TestCase):
    def test_line_range_and_heading_name_the_same_bytes(self):
        path, a = ablation.resolve_span(KEY, PIN)
        _, b = ablation.resolve_span("skills/work-on/references/phases/phase-2-introspection.md#Evidence", PIN)
        self.assertEqual(path, "skills/work-on/references/phases/phase-2-introspection.md")
        self.assertEqual(a, b)
        self.assertEqual(len(a), 164)

    def test_heading_ignores_fenced_code(self):
        content = b"# Top\n```bash\n# Not a heading\n```\n## Part\nbody\n```\n## inside fence\n```\nmore\n## Next\n"
        span = ablation.span_from_bytes("x.md#Part", content)
        self.assertEqual(span, b"## Part\nbody\n```\n## inside fence\n```\nmore\n")
        with self.assertRaisesRegex(ablation.Refusal, "heading not found"):
            ablation.span_from_bytes("x.md#Not a heading", content)
        with self.assertRaisesRegex(ablation.Refusal, "appears 2 times"):
            ablation.span_from_bytes("x.md#Part", content + b"## Part\nagain\n")

    def test_refusals_name_the_key_and_reason(self):
        tree = tempfile.mkdtemp()
        try:
            dest = os.path.join(tree, "skills/work-on/references/phases")
            os.makedirs(dest)
            _, span = ablation.resolve_span(KEY, PIN)
            target = os.path.join(dest, "phase-2-introspection.md")
            cases = [
                (lambda: ablation.resolve_span("nokey", PIN), "malformed rule key"),
                (lambda: ablation.resolve_span(KEY, "0" * 40), "unknown commit"),
                (lambda: ablation.resolve_span(KEY, "--output=x"), "7 to 40 hex"),
                (lambda: ablation.resolve_span("skills/nope.md#L1-L2", PIN), "does not exist at"),
                (lambda: ablation.resolve_span(KEY, PIN, tree), "does not exist in the tree"),
            ]
            for fn, needle in cases:
                with self.subTest(needle=needle):
                    with self.assertRaises(ablation.Refusal) as cm:
                        fn()
                    self.assertIn(needle, str(cm.exception))
            write_bytes(target, b"unrelated\n")
            with self.assertRaisesRegex(ablation.Refusal, "span not found"):
                ablation.resolve_span(KEY, PIN, tree)
            write_bytes(target, span + b"between\n" + span)
            with self.assertRaisesRegex(ablation.Refusal, "found 2 times"):
                ablation.resolve_span(KEY, PIN, tree)
        finally:
            shutil.rmtree(tree)

    def test_cut_removes_exactly_the_span(self):
        tree = tempfile.mkdtemp()
        try:
            rel = "skills/work-on/references/phases/phase-2-introspection.md"
            os.makedirs(os.path.join(tree, os.path.dirname(rel)))
            shutil.copyfile(os.path.join(ablation.REPO_ROOT, rel), os.path.join(tree, rel))
            path, span = ablation.resolve_span(KEY, PIN)
            before = read_bytes(os.path.join(tree, rel))
            ablation.cut_span(KEY, tree, path, span)
            after = read_bytes(os.path.join(tree, rel))
            self.assertEqual(len(before) - len(after), len(span))
            self.assertNotIn(span, after)
            self.assertEqual(before.replace(span, b""), after)
        finally:
            shutil.rmtree(tree)


class Checks(unittest.TestCase):
    def check(self, name, arg):
        out = subprocess.run([os.path.join(HERE, "checks", name), arg], capture_output=True, text=True)
        return out.returncode, out.stdout.splitlines()

    def production(self, evidence):
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as fh:
            json.dump({"workflow": WF, "state": "introspection", "evidence": evidence}, fh)
        self.addCleanup(os.remove, path)
        return path

    def test_deployed_check_reason_codes(self):
        cases = [
            ({"introspection_outcome": "approach_updated"}, 1, "rationale-missing"),
            ({"introspection_outcome": "approach_updated", "rationale": "  "}, 1, "rationale-missing"),
            ({"introspection_outcome": "approach_updated", "rationale": "flag landed"}, 0, "ok"),
            ({"introspection_outcome": "approach_unchanged"}, 0, "ok"),
            ({"introspection_outcome": "issue_superseded"}, 1, "rationale-missing"),
            ({"introspection_outcome": "issue_superseded", "rationale": "shipped in #9"}, 0, "ok"),
            ({"introspection_outcome": "bogus"}, 2, "enum-left-to-koto"),
            ("not an object", 2, "unreadable"),
        ]
        for evidence, code, reason in cases:
            with self.subTest(evidence=evidence):
                rc, lines = self.check("work-on-introspection-evidence", self.production(evidence))
                self.assertEqual((rc, lines[0]), (code, reason))
        rc, lines = self.check("work-on-introspection-evidence",
                               self.production({"introspection_outcome": "approach_updated"}))
        self.assertIn("approach_updated", "\n".join(lines[1:]))

    def run_dir(self, calls=None, events=None):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        if calls is not None:
            with open(os.path.join(d, "koto-calls.jsonl"), "w") as fh:
                for argv in calls:
                    fh.write(json.dumps({"t": 1, "argv": argv}) + "\n")
        if events is not None:
            with open(os.path.join(d, "koto-state.jsonl"), "w") as fh:
                fh.write(json.dumps({"schema_version": 1}) + "\n")
                for e in events:
                    fh.write(json.dumps(e) + "\n")
        return d

    def test_audit_no_cleanup(self):
        name = "audit-koto-next-no-cleanup"
        self.assertEqual(self.check(name, self.run_dir([["next", WF, "--no-cleanup"]]))[1][0], "ok")
        self.assertEqual(self.check(name, self.run_dir([["next", WF], ["next", WF, "--no-cleanup"]])),
                         (1, ["missing-no-cleanup"]))
        self.assertEqual(self.check(name, self.run_dir([["status", WF]])), (2, ["no-koto-next"]))
        self.assertEqual(self.check(name, self.run_dir())[0], 2)

    def gate(self, exists):
        return {"type": "gate_evaluated", "payload": {"state": "introspection", "gate": "introspection_artifact",
                                                      "output": {"exists": exists}}}

    def test_audit_context_stored(self):
        name = "audit-introspection-context-stored"
        submitted = {"type": "evidence_submitted", "payload": {"state": "introspection", "fields": {}}}
        self.assertEqual(self.check(name, self.run_dir(events=[self.gate(False), submitted, self.gate(True)])),
                         (0, ["ok"]))
        self.assertEqual(self.check(name, self.run_dir(events=[submitted, self.gate(False)])),
                         (1, ["context-missing"]))
        self.assertEqual(self.check(name, self.run_dir(events=[self.gate(False)])), (2, ["no-evidence"]))


class FixtureRule(unittest.TestCase):
    def classify(self, header):
        fd, path = tempfile.mkstemp()
        with os.fdopen(fd, "w") as fh:
            fh.write(json.dumps(header) + "\n")
        self.addCleanup(os.remove, path)
        out = subprocess.run([os.path.join(HERE, "is-fixture-session"), path], capture_output=True, text=True)
        return out.stdout.split("\t")[-1].strip()

    def test_rule(self):
        pinned = "d149614dd7047376910069298b0d668abab4271d734d9fdaf1be327862f5519b"
        self.assertEqual(self.classify({"template_source_dir": "/tmp/shirabe-ablation.a1b2/plugin/skills/work-on/koto-templates",
                                        "template_hash": pinned}), "fixture")
        self.assertEqual(self.classify({"template_source_dir": "/opt/plugins/shirabe/0.22.1/skills/work-on/koto-templates",
                                        "template_hash": pinned}), "not-fixture")
        self.assertEqual(self.classify({"template_source_dir": "/tmp/not-shirabe-ablation.x/skills/work-on/koto-templates"}),
                         "not-fixture")
        self.assertEqual(self.classify({}), "not-fixture")


class Fixture(unittest.TestCase):
    def test_greet_repo_makes_approach_updated_correct(self):
        repo = os.path.join(HERE, "fixtures", "greet-repo", "repo")
        issue = json.loads(read_text(os.path.join(HERE, "fixtures", "greet-repo", "issue.json")))
        self.assertIn("--name", issue["body"])
        self.assertIn("--name", read_text(os.path.join(repo, "src", "greet.sh")))
        self.assertNotIn("--name", read_text(os.path.join(repo, "README.md")))
        out = subprocess.run(["bash", os.path.join(repo, "src", "greet.sh"), "--name", "Ada"],
                             capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), "hello, Ada")


class Sampling(unittest.TestCase):
    def test_rate_one_takes_everything_and_samples_are_per_repetition(self):
        self.assertTrue(all(ablation.sampled("c", r, "rule", 1.0) for r in range(20)))
        picks = [ablation.sampled("c", r, "rule", 0.5) for r in range(200)]
        self.assertTrue(40 < sum(picks) < 160)
        self.assertEqual(picks, [ablation.sampled("c", r, "rule", 0.5) for r in range(200)])
        self.assertFalse(any(ablation.sampled("c", r, "rule", 0.0) for r in range(50)))


@unittest.skipUnless(shutil.which("koto"), "koto not on PATH")
class RunBase(unittest.TestCase):
    """Stub-agent runs against the real koto and the fixture."""

    def setUp(self):
        self.keep = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.keep)
        self.script = os.path.join(self.keep, "script.json")
        # A HOME of the test's own, so "koto never writes under the user's
        # home" is checked on a directory nothing else on the host touches.
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home)

    def run_case(self, steps, arms=("full",), case=None, **env):
        with open(self.script, "w") as fh:
            json.dump(steps, fh)
        case = case or ablation.validate_case(load_case())
        span = ablation.resolve_span(case["withhold"]["source"], case["withhold"]["source_commit"])
        real = os.path.realpath(shutil.which("koto"))
        baseline = ablation.harness_snapshot()
        with Env(ABLATION_TEST="1", ABLATION_AGENT_CMD=STUB, ABLATION_STUB_SCRIPT=self.script,
                 HOME=self.home, **env):
            for i, arm in enumerate(arms):
                ablation.run_one(case, arm, 1, i + 1, span, real, self.keep, baseline)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".koto")),
                         "a run wrote koto state under the user's home")
        status = subprocess.run(["git", "status", "--porcelain", "--", "skills", "references"],
                                cwd=ablation.REPO_ROOT, capture_output=True, text=True).stdout
        self.assertEqual(status, "", "a run changed files under skills/ or references/")

    def out(self, arm, name):
        path = os.path.join(self.keep, f"r1-{arm}", name)
        with open(path) as fh:
            if name.endswith(".jsonl"):
                return [json.loads(l) for l in fh if l.strip()]
            return json.load(fh)

    def next_with(self, evidence, *extra):
        return {"koto": ["next", WF, "--no-cleanup", "--with-data", ev(evidence)] + list(extra)}

class Runs(RunBase):
    def test_violated_then_complied(self):
        self.run_case([
            self.next_with({"introspection_outcome": "approach_updated"}),
            {"context": [WF, "introspection.md", "findings"]},
            self.next_with({"introspection_outcome": "approach_updated", "rationale": "flag already landed"}),
        ])
        prods = self.out("full", "productions.jsonl")
        self.assertEqual([(p["point"], p["outcome"], p["delivered"]) for p in prods],
                         [("first", "violated", True), ("second", "complied", False)])
        transcript = [json.loads(e["line"]) for e in self.out("full", "transcript.jsonl")]
        refusal = [c for m in transcript if m.get("type") == "user" for c in m["message"]["content"]][0]
        self.assertIn('"invalid_submission"', refusal["content"])
        self.assertIn("rationale", refusal["content"])
        state = self.out("full", "koto-state.jsonl")
        submitted = [e for e in state if e.get("type") == "evidence_submitted"
                     and e["payload"].get("state") == "introspection"]
        self.assertEqual(len(submitted), 1, "the refused production must never reach koto")
        raw = self.out("full", "raw.json")
        self.assertEqual({a["reason"] for a in raw["audits"]}, {"ok"})
        self.assertFalse(raw["tampered"])

    def test_complied_first_is_not_delivered(self):
        self.run_case([self.next_with({"introspection_outcome": "approach_unchanged"})])
        prods = self.out("full", "productions.jsonl")
        self.assertEqual([(p["point"], p["outcome"]) for p in prods], [("first", "complied")])
        self.assertFalse(any(p["delivered"] for p in prods))

    def test_stop_after_refusal_has_no_second_production(self):
        self.run_case([self.next_with({"introspection_outcome": "approach_updated"}, )])
        prods = self.out("full", "productions.jsonl")
        self.assertEqual([(p["point"], p["delivered"]) for p in prods], [("first", True)])

    def test_evidence_forms_and_tick_session_passthrough(self):
        evfile = os.path.join(self.keep, "ev.json")
        with open(evfile, "w") as fh:
            json.dump({"introspection_outcome": "approach_updated"}, fh)
        self.run_case([
            {"koto": ["next", WF, "--no-cleanup", f"--with-data=@{evfile}"]},
            {"koto": ["status", WF]},
        ])
        prods = self.out("full", "productions.jsonl")
        self.assertEqual(prods[0]["outcome"], "violated")
        calls = self.out("full", "koto-calls.jsonl")
        self.assertEqual([c["argv"][0] for c in calls], ["next", "status"])
        env = dict(os.environ, KOTO_TICK_SESSION="x", ABLATION_REAL_KOTO=shutil.which("koto"),
                   ABLATION_RUN_DIR=self.keep, ABLATION_KOTO_HOME=self.keep)
        subprocess.run([os.path.join(HERE, "koto-intercept"), "version"], env=env, capture_output=True)
        self.assertFalse(os.path.exists(os.path.join(self.keep, "koto-calls.jsonl")))

    def test_wrapper_refuses_without_or_with_itself_as_real_koto(self):
        wrapper = os.path.join(HERE, "koto-intercept")
        for real in ("", wrapper):
            env = {k: v for k, v in os.environ.items() if not k.startswith("ABLATION_")}
            env.update(ABLATION_RUN_DIR=self.keep, ABLATION_KOTO_HOME=self.keep)
            if real:
                env["ABLATION_REAL_KOTO"] = real
            out = subprocess.run([wrapper, "version"], env=env, capture_output=True, text=True)
            self.assertEqual(out.returncode, 3, out.stderr)

    def test_check_errors_and_timeouts_are_not_checkable(self):
        checks = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, checks)
        for name, body in (("exit-three", "echo weird\nexit 3"), ("bad-reason", "echo 'Not A Code'\nexit 0"),
                           ("slow", "sleep 5\necho ok")):
            path = os.path.join(checks, name)
            with open(path, "w") as fh:
                fh.write("#!/bin/sh\n" + body + "\n")
            os.chmod(path, 0o755)
        saved = ablation.CHECKS_DIR
        ablation.CHECKS_DIR = checks
        try:
            for name, reason in (("exit-three", "check-error"), ("bad-reason", "check-error"),
                                 ("slow", "check-timeout")):
                with self.subTest(check=name):
                    case = load_case()
                    case["deployed_check"] = name
                    case["audit"]["pool"] = []
                    case["limits"]["check_seconds"] = 1
                    shutil.rmtree(self.keep)
                    os.makedirs(self.keep)
                    self.run_case([self.next_with({"introspection_outcome": "approach_unchanged"})],
                                  case=ablation.validate_case(case))
                    prods = self.out("full", "productions.jsonl")
                    self.assertEqual((prods[0]["outcome"], prods[0]["reason"]), ("not-checkable", reason))
                    self.assertEqual(self.out("full", "raw.json")["audits"], [])
        finally:
            ablation.CHECKS_DIR = saved

    def test_arms_get_their_own_copy_and_the_allowlisted_env(self):
        with Env(GH_TOKEN="planted", SSH_AUTH_SOCK="/planted"):
            self.run_case([], arms=("full", "withheld", "without_skill"))
        prompts = {}
        plugins = set()
        for arm in ("full", "withheld", "without_skill"):
            dump = self.out(arm, "stub-dump.json")
            argv = dump["argv"]
            for flag in ("--strict-mcp-config", "--no-session-persistence"):
                self.assertIn(flag, argv)
            self.assertEqual(argv[argv.index("--setting-sources") + 1], "")
            self.assertNotIn("GH_TOKEN", dump["env"])
            self.assertNotIn("SSH_AUTH_SOCK", dump["env"])
            prompts[arm] = argv[-1]
            if arm == "without_skill":
                self.assertNotIn("--plugin-dir", argv)
            else:
                plugin = argv[argv.index("--plugin-dir") + 1]
                self.assertIn(os.path.basename(os.path.dirname(plugin))[:len(ablation.SCRATCH_PREFIX)],
                              ablation.SCRATCH_PREFIX)
                plugins.add(plugin)
                self.assertEqual(dump["plugin_parts"], sorted(ablation.PLUGIN_PARTS))
                self.assertFalse(dump["harness_copied"], "scripts/ablation/ must stay out of the copy")
        self.assertEqual(len(plugins), 2, "full and withheld must each load their own copy")
        self.assertEqual(prompts["full"], prompts["withheld"])
        self.assertNotEqual(prompts["full"], prompts["without_skill"])

    def test_without_skill_copy_has_no_instructions(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        dest = os.path.join(d, "plugin")
        ablation.copy_koto_only(dest, "work-on")
        self.assertTrue(os.path.isfile(os.path.join(dest, "skills/work-on/koto-templates/work-on.md")))
        self.assertFalse(os.path.exists(os.path.join(dest, "skills/work-on/SKILL.md")))
        self.assertFalse(os.path.exists(os.path.join(dest, "skills/work-on/references")))
        self.assertFalse(os.path.exists(os.path.join(dest, "references")))
        self.assertFalse(os.path.exists(os.path.join(dest, "scripts", "ablation")))

    def test_withheld_copy_lacks_the_span_only(self):
        self.run_case([{"read_plugin": "skills/work-on/references/phases/phase-2-introspection.md"}],
                      arms=("full", "withheld"))
        _, span = ablation.resolve_span(KEY, PIN)
        read = {}
        for arm in ("full", "withheld"):
            msgs = [json.loads(e["line"]) for e in self.out(arm, "transcript.jsonl")]
            read[arm] = [c["content"] for m in msgs if m.get("type") == "user" for c in m["message"]["content"]][0]
        self.assertIn(span.decode(), read["full"])
        self.assertNotIn(span.decode(), read["withheld"])
        self.assertEqual(read["full"].replace(span.decode(), ""), read["withheld"])

    def test_tampering_taints_the_run_and_every_later_one(self):
        marker = os.path.join(HERE, "testdata", "tamper-marker")
        self.addCleanup(lambda: os.path.exists(marker) and os.remove(marker))
        self.run_case([{"touch": marker}], arms=("full", "withheld"))
        self.assertTrue(self.out("full", "raw.json")["tampered"])
        self.assertTrue(self.out("withheld", "raw.json")["tampered"])

    def roots(self):
        return {n for n in os.listdir(tempfile.gettempdir()) if n.startswith(ablation.SCRATCH_PREFIX)}

    def test_wall_clock_limit_kills_the_session_and_removes_the_root(self):
        case = load_case()
        case["limits"]["session_seconds"] = 2
        before = self.roots()
        self.run_case([{"sleep": 30}], case=ablation.validate_case(case))
        self.assertTrue(self.out("full", "raw.json")["agent"]["killed"])
        self.assertEqual(self.roots() - before, set())

    def test_only_the_target_state_is_graded(self):
        self.run_case([
            self.next_with({"introspection_outcome": "approach_unchanged"}),
            {"context": [WF, "introspection.md", "findings"]},
            self.next_with({"introspection_outcome": "approach_unchanged"}),
            self.next_with({"plan_outcome": "blocked_missing_context"}),
        ])
        prods = self.out("full", "productions.jsonl")
        calls = self.out("full", "koto-calls.jsonl")
        self.assertEqual([c["state"] for c in calls if c["argv"][0] == "next"],
                         ["introspection", "introspection", "analysis"])
        self.assertEqual([(p["point"], p.get("graded")) for p in prods], [("first", True), (None, False)])

    def test_options_before_the_workflow_name_are_still_graded(self):
        self.run_case([{"koto": ["next", "--no-cleanup", "--with-data",
                                 ev({"introspection_outcome": "approach_updated"}), WF]}])
        prods = self.out("full", "productions.jsonl")
        self.assertEqual((prods[0]["point"], prods[0]["outcome"], prods[0]["delivered"]),
                         ("first", "violated", True))

    def test_agent_cmd_needs_test_mode(self):
        case = ablation.validate_case(load_case())
        with Env(ABLATION_TEST=None, ABLATION_AGENT_CMD=STUB):
            with self.assertRaisesRegex(ablation.Refusal, "ABLATION_TEST=1"):
                ablation.agent_argv(case, "full", "/x")


BASELINE_ATTRS = ("definition.version", "rule.source", "rule.source_commit", "skill", "template.path",
                  "template.git_blob", "template.koto_hash", "state", "run.id")


def manifest_bytes(tree, profile):
    """An oracle for the static count, independent of offload-baseline.sh: the
    raw bytes of every distinct span the manifest lists for the profile."""
    seen = set()
    total = 0
    path = os.path.join(ablation.REPO_ROOT, "docs", "measurement", "offload-baseline", "load-manifest.tsv")
    rows = [l.rstrip("\n").split("\t") for l in read_text(path).splitlines()
            if l.strip() and not l.startswith("#")][1:]
    for prof, rel, selector, _weight, *_ in rows:
        if prof != profile or (rel, selector) in seen:
            continue
        seen.add((rel, selector))
        text = read_bytes(os.path.join(tree, rel))
        if selector == "file":
            total += len(text)
            continue
        lines = text.decode().split("\n")
        body = lines
        if lines and lines[0] == "---":
            end = lines.index("---", 1)
            body = lines[end + 1:]
        if selector == "body":
            total += len(("\n".join(body)).encode())
            continue
        want = "## " + selector[len("state:"):]
        out, on = [], False
        for line in body:
            if line == want:
                on = True
                out.append(line)
                continue
            if on and line.startswith("## "):
                break
            if on:
                out.append(line)
        while out and out[-1] == "":
            out.pop()
        total += len(("\n".join(out) + "\n").encode())
    return total


class Records(RunBase):
    """Records derived from stub runs against the real koto."""

    def record(self, arm="full"):
        return self.out(arm, "record.json")

    def obs(self, rec):
        return {o["point"]: o for o in rec["observations"]}

    def test_violated_then_complied_record(self):
        self.run_case([
            self.next_with({"introspection_outcome": "approach_updated"}),
            {"context": [WF, "introspection.md", "findings"]},
            self.next_with({"introspection_outcome": "approach_updated", "rationale": "landed"}),
        ])
        rec = self.record()
        for attr in BASELINE_ATTRS:
            self.assertIn(attr, rec)
        self.assertEqual(rec["definition.version"], "provisional-1")
        self.assertEqual(rec["delivery.shape"], "harness-check-message")
        self.assertTrue(rec["template.fixture"])
        self.assertTrue(rec["delivered"])
        o = self.obs(rec)
        self.assertEqual((o["first"]["point.status"], o["first"]["opportunity.outcome"],
                          o["first"]["reason"], o["first"]["observed_by"]),
                         ("observed", "violated", "rationale-missing", "script"))
        self.assertEqual(o["second"]["opportunity.outcome"], "complied")
        self.assertEqual(o["after-one-delivery"]["opportunity.outcome"], "complied")
        self.assertEqual({a["opportunity.outcome"] for a in rec["audit"]["rules"]}, {"complied"})
        text = json.dumps(rec)
        for leak in (self.home, tempfile.gettempdir() + "/", os.environ.get("HOME", "/nonexistent") + "/"):
            self.assertNotIn(leak, text)

    def test_complied_first_second_not_reached(self):
        self.run_case([self.next_with({"introspection_outcome": "approach_unchanged"})])
        o = self.obs(self.record())
        self.assertEqual(o["second"]["point.status"], "not-reached")
        self.assertNotIn("opportunity.outcome", o["second"])
        self.assertEqual(o["after-one-delivery"]["opportunity.outcome"], "complied")

    def test_stop_after_refusal_second_not_produced(self):
        self.run_case([self.next_with({"introspection_outcome": "approach_updated"})])
        o = self.obs(self.record())
        self.assertEqual(o["second"]["point.status"], "not-produced")
        self.assertEqual(o["after-one-delivery"]["point.status"], "not-produced")

    def test_no_production_at_all(self):
        self.run_case([{"koto": ["status", WF]}])
        o = self.obs(self.record())
        self.assertEqual((o["first"]["point.status"], o["second"]["point.status"]),
                         ("not-produced", "not-produced"))

    def test_leak_before_delivery_makes_the_run_not_checkable(self):
        _, span = ablation.resolve_span(KEY, PIN)
        line = [l for l in span.decode().splitlines() if "approach_updated" in l][0]
        self.run_case([{"echo": "grep hit: " + line}, self.next_with({"introspection_outcome": "approach_unchanged"})],
                      arms=("withheld",))
        rec = self.record("withheld")
        self.assertTrue(rec["leak"])
        self.assertEqual(self.obs(rec)["first"]["opportunity.outcome"], "not-checkable")
        self.assertEqual(self.obs(rec)["first"]["reason"], "section-leaked")

    def test_naming_the_file_is_not_a_leak(self):
        self.run_case([{"echo": "./skills/work-on/references/phases/phase-2-introspection.md"},
                       self.next_with({"introspection_outcome": "approach_unchanged"})], arms=("withheld",))
        rec = self.record("withheld")
        self.assertFalse(rec["leak"])
        self.assertEqual(self.obs(rec)["first"]["opportunity.outcome"], "complied")

    def test_bypass_by_absolute_path(self):
        self.run_case([{"koto_abs": ["next", WF, "--no-cleanup", "--with-data",
                                     ev({"introspection_outcome": "approach_updated"})]}])
        rec = self.record()
        self.assertTrue(rec["wrapper_bypassed"])

    def test_tokens(self):
        self.run_case([
            {"read_plugin": "skills/work-on/references/phases/phase-2-introspection.md"},
            self.next_with({"introspection_outcome": "approach_unchanged"}),
            # No introspection.md in context, so the gate holds the session in
            # introspection; the turn before this second tick is spent there.
            self.next_with({"introspection_outcome": "approach_unchanged"}),
        ], arms=("full", "withheld", "without_skill"))
        full, withheld, without = self.record("full"), self.record("withheld"), self.record("without_skill")
        s = full["tokens"]["session"]
        self.assertEqual((s["input"], s["output"], s["cache_read"], s["cache_creation"], s["partial"]),
                         (300, 30, 150, 15, False))
        self.assertEqual(s["total"], 495)
        # Input-side tokens: turns before the first tick are pre-first-state,
        # the turn between the two ticks is spent in introspection.
        self.assertEqual(full["tokens"]["pre_first_state_input"], 310)
        self.assertEqual(full["tokens"]["per_state_input"], {"introspection": 155})
        _, span = ablation.resolve_span(KEY, PIN)
        read = len(read_bytes(os.path.join(ablation.REPO_ROOT, "skills/work-on/references/phases/phase-2-introspection.md")))
        body = records.skill_body_bytes(ablation.REPO_ROOT, "work-on")
        self.assertGreater(body, 1000)
        self.assertEqual(full["tokens"]["instruction_observed"]["total"], int((body + read) / 4 + 0.5))
        self.assertEqual(full["tokens"]["instruction_observed"]["pre_first_state"], int((body + read) / 4 + 0.5))
        self.assertEqual(withheld["tokens"]["instruction_observed"]["total"],
                         int((body + read - len(span)) / 4 + 0.5))
        self.assertEqual(without["tokens"]["instruction_observed"]["total"], 0)
        b = manifest_bytes(ablation.REPO_ROOT, "work-on")
        self.assertEqual(full["tokens"]["instruction_static"]["raw"], int(b / 4 + 0.5))
        self.assertEqual(withheld["tokens"]["instruction_static"]["raw"], int((b - len(span)) / 4 + 0.5))
        self.assertEqual(without["tokens"]["instruction_static"], {"raw": 0, "weighted": 0})
        self.assertEqual(full["cost_usd"], 0.003)

    def test_partial_tokens_without_a_result_event(self):
        self.run_case([self.next_with({"introspection_outcome": "approach_unchanged"}), {"no_result": True}])
        s = self.record()["tokens"]["session"]
        self.assertTrue(s["partial"])
        self.assertEqual((s["input"], s["output"]), (100, 10))


def rec(arm, rep, first, second=None, delivered=False, audit=(), leak=False, total=1000, cost=0.25,
        shape="harness-check-message"):
    def point(name, value):
        if value in ("not-reached", "not-produced"):
            return {"point": name, "point.status": value, "observed_by": "script"}
        return {"point": name, "point.status": "observed", "opportunity.outcome": value,
                "reason": "ok", "observed_by": "script"}
    second = second or ("not-reached" if not delivered else "not-produced")
    effective = second if delivered else first
    return {"case.id": "work-on-introspection-evidence", "arm": arm, "repetition": rep, "arm_order": 1,
            "run.id": f"work-on-introspection-evidence/r{rep}/{arm}/{shape}",
            "delivery.shape": shape, "rule.span_bytes": 257, "model": "m", "koto.version": "0.14.1",
            "leak": leak, "wrapper_bypassed": False, "harness_tampered": False, "delivered": delivered,
            "observations": [point("first", first), point("second", second),
                             point("after-one-delivery", effective)],
            "tokens": {"session": {"total": total, "partial": False},
                       "instruction_static": {"raw": 10, "weighted": 5},
                       "instruction_observed": {"total": 3, "pre_first_state": 1}},
            "cost_usd": cost,
            "audit": {"sample_rate": 1.0, "rules": [{"rule.source": r, "opportunity.outcome": o}
                                                    for r, o in audit]}}


class Summary(unittest.TestCase):
    def test_statistics(self):
        self.assertAlmostEqual(records.clopper_pearson_upper(0, 5), 1 - 0.025 ** (1 / 5), places=6)
        self.assertAlmostEqual(records.clopper_pearson_upper(1, 4), 0.8059, places=4)
        self.assertEqual(records.clopper_pearson_upper(3, 3), 1.0)
        self.assertIsNone(records.clopper_pearson_upper(0, 0))
        self.assertEqual(records.detection_limit(5), (4, 0.8))
        self.assertEqual(records.detection_limit(30)[0], 5)
        self.assertEqual(records.detection_limit(15)[0], 4)

    def summary(self, recs):
        return records.summarize(recs, ablation.case_by_id("work-on-introspection-evidence"), ablation.REPO_ROOT)

    def test_known_counts(self):
        rule = "skills/work-on/SKILL.md#L359-L362"
        recs = [
            rec("full", 1, "complied", audit=[(rule, "complied")], total=1000),
            rec("withheld", 1, "violated", "complied", delivered=True, audit=[(rule, "violated")], total=900),
            rec("without_skill", 1, "not-produced", audit=[(rule, "violated")], total=500),
            rec("full", 2, "complied", audit=[(rule, "complied")], total=1000),
            rec("withheld", 2, "complied", audit=[(rule, "complied")], total=800),
            rec("without_skill", 2, "not-produced", audit=[(rule, "violated")], total=500),
        ]
        out = self.summary(recs)
        self.assertIn("withheld       first                  2     1          2", out)
        self.assertIn("50.0%   98.7%", out)
        self.assertIn("without_skill  first                  2     0          0              0             2", out)
        self.assertIn("n/a     n/a", out)
        self.assertIn("-150.0", out)
        self.assertIn("raw 46671, weighted 36789", out)
        self.assertIn(f"{rule}: full 0/2, withheld 1/2, without_skill 2/2; erosion +50.0 points", out)
        self.assertIn("thresholds row: single rule (break-even uplift about 1.5 to 3 points)", out)
        self.assertIn("detection limit at 2 checkable run(s) per arm: none", out)
        self.assertIn("cannot support withholding the section", out)
        self.assertIn("model spend reported by the sessions: 6 of 6 runs, total $1.50", out)
        self.assertIn("/shirabe:work-on 1", out)

    def test_empty_pool(self):
        self.assertIn("no audit rules sampled", self.summary([rec("full", 1, "complied")]))

    def test_duplicate_run_ids_are_refused(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        path = os.path.join(d, "records.jsonl")
        with open(path, "w") as fh:
            for r in (rec("full", 1, "complied"), rec("full", 1, "complied")):
                r["run.id"] = "work-on-introspection-evidence/r1/full"
                fh.write(json.dumps(r) + "\n")
        with self.assertRaisesRegex(ablation.Refusal, "more than once"):
            ablation.summarize_file(path)

    def test_shapes_are_never_pooled(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        path = os.path.join(d, "records.jsonl")
        with open(path, "w") as fh:
            for r in (rec("full", 1, "complied"), rec("full", 2, "complied", shape="koto-payload")):
                fh.write(json.dumps(r) + "\n")
        with self.assertRaisesRegex(ablation.Refusal, "delivery shape"):
            ablation.summarize_file(path)

    def test_check_figures(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        case_dir = os.path.join(d, "work-on-introspection-evidence")
        os.makedirs(case_dir)
        path = os.path.join(case_dir, "records.jsonl")
        with open(path, "w") as fh:
            for r in (rec("full", 1, "complied"), rec("withheld", 1, "violated", "complied", delivered=True)):
                fh.write(json.dumps(r) + "\n")
        with open(os.path.join(case_dir, "summary.txt"), "w") as fh:
            fh.write(ablation.summarize_file(path))
        self.assertEqual(ablation.check_figures(d), 0)
        text = read_text(os.path.join(case_dir, "summary.txt")).replace("runs: 2", "runs: 3", 1)
        self.assertIn("runs: 3", text)
        with open(os.path.join(case_dir, "summary.txt"), "w") as fh:
            fh.write(text)
        self.assertEqual(ablation.check_figures(d), 1)
        self.assertEqual(ablation.check_figures(os.path.join(d, "empty")), 1)


if __name__ == "__main__":
    unittest.main()
