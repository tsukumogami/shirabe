#!/usr/bin/env python3
"""Tests for the ablation harness (scripts/ablation/).

The run tests drive the real koto against the fixture, with the model session
replaced by testdata/stub-agent, so they need koto on PATH and no model, no
network and no secret. They read the repository's history at the case's
source commit, so a CI checkout needs fetch-depth 0.

Usage: python3 scripts/ablation/ablation_test.py [-v]
"""

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import ablation  # noqa: E402

CASE_FILE = os.path.join(HERE, "cases", "work-on-introspection-evidence.json")
STUB = os.path.join(HERE, "testdata", "stub-agent")
PIN = "2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10"
KEY = "skills/work-on/references/phases/phase-2-introspection.md#L20-L24"
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
        self.assertEqual(len(a), 257)

    def test_heading_ignores_fenced_code(self):
        content = b"# Top\n```bash\n# Not a heading\n```\n## Part\nbody\n```\n## inside fence\n```\nmore\n## Next\n"
        span = ablation.span_from_bytes("x.md#Part", content)
        self.assertEqual(span, b"## Part\nbody\n```\n## inside fence\n```\nmore\n")
        with self.assertRaisesRegex(ablation.Refusal, "heading not found"):
            ablation.span_from_bytes("x.md#Not a heading", content)

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
            ({"introspection_outcome": "issue_superseded"}, 0, "ok"),
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
class Runs(unittest.TestCase):
    """Stub-agent runs against the real koto and the fixture."""

    def setUp(self):
        self.keep = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.keep)
        self.script = os.path.join(self.keep, "script.json")
        home = os.environ.get("HOME", "")
        self.real_koto_home = os.path.join(home, ".koto")
        self.koto_home_before = self.listing(self.real_koto_home)

    @staticmethod
    def listing(path):
        out = []
        for dirpath, dirnames, filenames in os.walk(path):
            for name in filenames:
                full = os.path.join(dirpath, name)
                try:
                    out.append((full, os.stat(full).st_mtime_ns))
                except OSError:
                    pass
        return sorted(out)

    def run_case(self, steps, arms=("full",), case=None, **env):
        with open(self.script, "w") as fh:
            json.dump(steps, fh)
        case = case or ablation.validate_case(load_case())
        span = ablation.resolve_span(case["withhold"]["source"], case["withhold"]["source_commit"])
        real = os.path.realpath(shutil.which("koto"))
        with Env(ABLATION_TEST="1", ABLATION_AGENT_CMD=STUB, ABLATION_STUB_SCRIPT=self.script, **env):
            for i, arm in enumerate(arms):
                ablation.run_one(case, arm, 1, i + 1, span, real, self.keep)
        self.assertEqual(self.listing(self.real_koto_home), self.koto_home_before,
                         "a run touched the real home's koto directory")

    def out(self, arm, name):
        path = os.path.join(self.keep, f"r1-{arm}", name)
        with open(path) as fh:
            if name.endswith(".jsonl"):
                return [json.loads(l) for l in fh if l.strip()]
            return json.load(fh)

    def next_with(self, evidence, *extra):
        return {"koto": ["next", WF, "--no-cleanup", "--with-data", ev(evidence)] + list(extra)}

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
        _, span = ablation.resolve_span(KEY, PIN)
        prompts = {}
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
        self.assertEqual(prompts["full"], prompts["withheld"])
        self.assertNotEqual(prompts["full"], prompts["without_skill"])

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

    def test_tampering_is_detected_and_run_root_removed(self):
        marker = os.path.join(HERE, "testdata", "tamper-marker")
        self.addCleanup(lambda: os.path.exists(marker) and os.remove(marker))
        roots_before = set(os.listdir(tempfile.gettempdir()))
        self.run_case([{"touch": marker}])
        self.assertTrue(self.out("full", "raw.json")["tampered"])
        leftover = {n for n in os.listdir(tempfile.gettempdir()) if n.startswith("shirabe-ablation.")} - roots_before
        self.assertEqual(leftover, set())

    def test_wall_clock_limit_kills_the_session(self):
        case = load_case()
        case["limits"]["session_seconds"] = 2
        self.run_case([{"sleep": 30}], case=ablation.validate_case(case))
        self.assertTrue(self.out("full", "raw.json")["agent"]["killed"])

    def test_agent_cmd_needs_test_mode(self):
        case = ablation.validate_case(load_case())
        with Env(ABLATION_TEST=None, ABLATION_AGENT_CMD=STUB):
            with self.assertRaisesRegex(ablation.Refusal, "ABLATION_TEST=1"):
                ablation.agent_argv(case, "full", "/x")


if __name__ == "__main__":
    unittest.main()
