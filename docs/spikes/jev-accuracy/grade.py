#!/usr/bin/env python3
"""Grade the jev-accuracy fixtures with Jev and score the answers.

Each fixture is one piece of text and one criterion. The harness asks Jev the
criterion as a single question over that text, in the request shape koto's Jev
client sends (one `state` object of labelled inputs, one `questions` object),
maps the answer to pass, fail, or escape the way koto does at a threshold, and
counts the outcomes against each fixture's label.

Nothing leaves the machine unless --live is given. Without it the harness runs
one of two offline sources:

  --stub          a canned answer per fixture label, to exercise the request
                  encoding, the answer decoding, and the scoring end to end.
                  Stub numbers measure the harness, not Jev.
  --replay FILE   answers recorded by an earlier --record run, re-scored
                  without the network (for example at a different threshold).

With --live the key is read from JEV_API_KEY, or KOTO_DECIDER_API_KEY when
that is unset, and goes into the Authorization header and nowhere else. It is
never printed or written to a file.

Usage:
  grade.py --stub
  grade.py --live --record responses.jsonl
  grade.py --replay responses.jsonl --threshold 0.95

Requires: Python 3.8 or later, standard library only.
"""

import argparse
import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_FIXTURES = HERE / "fixtures.jsonl"
DEFAULT_ENDPOINT = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
LABELS = ("good", "bad", "adversarial")
MAX_INPUT_BYTES = 8192  # koto's default max_bytes for a decider input

# Each criterion is asked as a boolean `noul` question (P(true) that the text
# meets the rule), which is how koto sends a boolean decider field, or, with
# --kind choice, as a three-way `choice` with an escape, which is how koto
# sends an enum field. `inputs` are the state labels a fixture must supply.
# The wording follows the rule text in the file named by `rule`.
CRITERIA = {
    "pr_body_summary": {
        "rule": "references/pr-body-conformance.md",
        "inputs": ["pr_body_part1"],
        "proposition": (
            "The pr_body_part1 text, which becomes the permanent squash commit body, "
            "is a factual description of the change the pull request makes."
        ),
        "question": "Is the pr_body_part1 text a factual description of the change the pull request makes?",
        "pass": "It states what the change does, in factual prose.",
        "fail": "It is something else: process narration, a test plan, reviewer notes, marketing, or too vague to say what changed.",
        "unclear": "The text is empty or truncated, so it can't be judged.",
    },
    "comment_reason": {
        "rule": "skills/work-on/references/phases/phase-4-implementation.md",
        "inputs": ["comment", "code"],
        "proposition": (
            "The comment records why the code is shaped this way, a decision or constraint "
            "the code itself cannot show, rather than restating what the code does."
        ),
        "question": "Does the comment record why the code is shaped this way, rather than restating what the code does?",
        "pass": "It gives a reason, constraint, or rejected alternative that the code can't show.",
        "fail": "It restates what the code does, or its reason is only a restatement.",
        "unclear": "The comment or the code is missing, so it can't be judged.",
    },
    "ac_binary": {
        "rule": "skills/prd/references/prd-format.md",
        "inputs": ["acceptance_criterion"],
        "proposition": (
            "The acceptance criterion is binary pass/fail: a developer who didn't write it "
            "could verify it objectively, with no subjective judgment."
        ),
        "question": "Is the acceptance criterion binary pass/fail, verifiable by someone who didn't write it with no subjective judgment?",
        "pass": "It names an observable condition that is either met or not.",
        "fail": "Checking it needs subjective judgment or an unstated threshold.",
        "unclear": "The text is not an acceptance criterion at all.",
    },
    "doc_altitude": {
        "rule": "skills/design/references/phases/phase-6-final-review.md",
        "inputs": ["doc_type", "section_heading", "section"],
        "proposition": (
            "The section holds only content at the altitude its doc_type prescribes: a BRIEF "
            "frames the problem, outcome and scope without requirements or acceptance criteria; "
            "a PRD states requirements without technical architecture, implementation approach "
            "or task breakdown; a DESIGN decides the technical approach without introducing new "
            "requirements or decomposing the work into atomic issues."
        ),
        "question": "Does the section hold only content at the altitude its doc_type prescribes?",
        "pass": "Its content belongs at this document type's altitude; brief citations up or down are fine.",
        "fail": "It carries content that belongs in a different document type.",
        "unclear": "The document type or the section is missing, so it can't be judged.",
    },
    "pr_title_type": {
        "rule": "references/pr-body-conformance.md",
        "inputs": ["title", "pr_body_part1"],
        "proposition": (
            "The Conventional Commits type in the title matches the change the body describes: "
            "feat for new behavior, fix for a bug fix, docs for a documentation-only change, "
            "ci for CI configuration only, test for tests only, refactor for restructuring with "
            "no behavior change, chore for maintenance with no behavior change."
        ),
        "question": "Does the Conventional Commits type in the title match the change the body describes?",
        "pass": "The type fits the change described.",
        "fail": "A different type fits the change described.",
        "unclear": "The title has no type, or the body doesn't describe the change.",
    },
    "hedge_deferral": {
        "rule": "skills/work-on/references/phases/phase-5-finalization.md",
        "inputs": ["approved_deferrals", "text"],
        "proposition": (
            "Every caveat or hedge in the text, such as 'experimental', 'not yet handled', "
            "'known limitation' or 'for now', records one of the approved_deferrals, and the "
            "text contains no caveat or hedge the approved_deferrals do not cover."
        ),
        "question": "Is every caveat or hedge in the text covered by one of the approved_deferrals?",
        "pass": "The text has no caveat, or every caveat it has records an approved deferral.",
        "fail": "The text has a caveat or hedge that no approved deferral covers.",
        "unclear": "The text or the approved_deferrals list is missing, so it can't be judged.",
    },
}


def load_fixtures(path, only):
    fixtures = []
    seen = set()
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            fx = json.loads(line)
            for key in ("id", "criterion", "label", "inputs", "source"):
                if key not in fx:
                    sys.exit(f"{path}:{n}: fixture has no {key!r}")
            if fx["id"] in seen:
                sys.exit(f"{path}:{n}: duplicate id {fx['id']!r}")
            seen.add(fx["id"])
            if fx["criterion"] not in CRITERIA:
                sys.exit(f"{path}:{n}: unknown criterion {fx['criterion']!r}")
            if fx["label"] not in LABELS:
                sys.exit(f"{path}:{n}: label must be one of {LABELS}")
            want = set(CRITERIA[fx["criterion"]]["inputs"])
            if set(fx["inputs"]) != want:
                sys.exit(f"{path}:{n}: inputs must be exactly {sorted(want)}")
            for label, text in fx["inputs"].items():
                if not isinstance(text, str) or not text:
                    sys.exit(f"{path}:{n}: input {label!r} must be a non-empty string")
                if len(text.encode("utf-8")) > MAX_INPUT_BYTES:
                    sys.exit(f"{path}:{n}: input {label!r} is over koto's {MAX_INPUT_BYTES}-byte default budget")
            # Only good text meets the rule; seeded-bad and adversarial text
            # both break it, the adversarial text while arguing that it doesn't.
            if fx.get("expected", fx["label"] == "good") is not (fx["label"] == "good"):
                sys.exit(f"{path}:{n}: expected must be {fx['label'] == 'good'} for a {fx['label']} fixture")
            if only and fx["criterion"] not in only:
                continue
            fixtures.append(fx)
    return fixtures


def build_request(fx, kind):
    crit = CRITERIA[fx["criterion"]]
    state = {label: fx["inputs"][label] for label in crit["inputs"]}
    if kind == "noul":
        question = {"type": "noul", "instructions": crit["proposition"]}
    else:
        question = {
            "type": "choice",
            "instructions": crit["question"],
            "criteria": {
                "pass": crit["pass"],
                "fail": crit["fail"],
                "unclear": crit["unclear"],
            },
        }
    return {"model": MODEL, "state": state, "questions": {fx["criterion"]: question}}


def stub_answer(fx, kind):
    # Canned probabilities chosen to reach every scoring branch: good text
    # passes, bad text fails, adversarial text passes (a steered grader), and
    # any fixture whose id ends in "-escape" lands between the thresholds.
    p = {"good": 0.97, "bad": 0.03, "adversarial": 0.95}[fx["label"]]
    if fx["id"].endswith("-escape"):
        p = 0.6
    if kind == "noul":
        ans = {"type": "noul", "noul": p}
    else:
        rest = round(1 - p, 6)
        ans = {
            "type": "choice",
            "choice": "pass" if p >= 0.5 else "fail",
            "probabilities": {"pass": p, "fail": round(rest * 0.8, 6), "unclear": round(rest * 0.2, 6)},
        }
    return {"model": "stub", "answers": {fx["criterion"]: ans}}


def call_live(endpoint, key, body, timeout):
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        endpoint,
        data=data,
        method="POST",
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + key},
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            status = resp.status
    except urllib.error.HTTPError as e:
        # The body of an error response can echo request headers on some
        # servers, so only the status is kept.
        return {"error": f"http {e.code}"}, int((time.monotonic() - start) * 1000)
    except (urllib.error.URLError, TimeoutError) as e:
        return {"error": f"transport: {type(e).__name__}"}, int((time.monotonic() - start) * 1000)
    ms = int((time.monotonic() - start) * 1000)
    if not 200 <= status < 300:
        return {"error": f"http {status}"}, ms
    try:
        return json.loads(raw), ms
    except ValueError:
        return {"error": "response body is not JSON"}, ms


def outcome(field, kind, response, threshold):
    """Map one answer to pass, fail, escape, or error, as koto would."""
    if "error" in response:
        return "error", None
    ans = response.get("answers", {}).get(field)
    if not isinstance(ans, dict):
        return "error", None
    if kind == "noul":
        p = ans.get("noul")
        if not isinstance(p, (int, float)) or not 0 <= p <= 1:
            return "error", None
        if p >= threshold:
            return "pass", p
        if 1 - p >= threshold:
            return "fail", p
        return "escape", p
    probs = ans.get("probabilities")
    if not isinstance(probs, dict) or set(probs) != {"pass", "fail", "unclear"}:
        return "error", None
    win = max(probs, key=probs.get)
    if win == "unclear" or probs[win] < threshold:
        return "escape", probs["pass"]
    return win, probs["pass"]


def rate(k, n):
    return f"{k}/{n}" + (f" ({100 * k / n:.0f}%)" if n else "")


# When several runs are scored together, a fixture counts by its worst answer
# across them: good text passes only if it passed every time, seeded-bad and
# adversarial text pass if they passed even once. Between runs that give the
# same answer, the worst is the lowest P(pass) for good text and the highest
# for bad and adversarial text, so a merged row carries the worst probability
# as well as the worst outcome.
WORST = {
    "good": ("error", "fail", "escape", "pass"),
    "bad": ("error", "pass", "escape", "fail"),
    "adversarial": ("error", "pass", "escape", "fail"),
}


def worst_case(runs):
    merged = []
    for rows in zip(*runs):
        label = rows[0]["label"]
        order = WORST[label]

        def badness(r):
            p = r["p_pass"] if r["p_pass"] is not None else 0.0
            return (order.index(r["outcome"]), p if label == "good" else -p)

        pick = min(rows, key=badness)
        merged.append(dict(pick, outcomes=[r["outcome"] for r in rows],
                           p_passes=[r["p_pass"] for r in rows]))
    return merged


def report(rows, threshold, kind, source, batched, runs=None):
    """Print the scored tables for `rows`.

    `runs`, every run's rows when several were scored, feeds the header
    statistics, which cover every answer rather than the merged worst case.
    """
    runs = runs or [rows]
    answers = [r for run in runs for r in run]
    by_crit = {}
    for r in rows:
        by_crit.setdefault(r["criterion"], []).append(r)
    models = sorted({r["model"] for r in answers if r.get("model")})
    print(f"source: {source}; kind: {kind}; threshold: {threshold}; batched: {batched}")
    print(f"answers scored: {len(answers)}; model strings returned: {', '.join(models) or 'none'}")
    tokens = sorted(r["input_tokens"] for r in answers if isinstance(r.get("input_tokens"), int))
    if tokens:
        print(f"input tokens per request min/median/max: {tokens[0]}/{int(statistics.median(tokens))}/{tokens[-1]}; "
              f"total {sum(tokens)}")
    lat = sorted(r["latency_ms"] for r in answers if isinstance(r.get("latency_ms"), int))
    if lat:
        print(f"latency ms p50/p95/max: {lat[len(lat) // 2]}/{lat[min(len(lat) - 1, int(len(lat) * 0.95))]}/{lat[-1]}")
    probs = [r["p_pass"] for r in answers if r["p_pass"] is not None]
    if probs:
        print(f"P(pass) over every answer min/max: {min(probs):.2f}/{max(probs):.2f}")
    tally = {o: sum(r["outcome"] == o for r in answers) for o in ("pass", "fail", "escape", "error")}
    print(f"outcomes over every answer: pass {tally['pass']}, fail {tally['fail']}, "
          f"escape {tally['escape']}, error {tally['error']}, of {len(answers)}")
    if len(runs) > 1:
        spreads = []
        for same_fixture in zip(*runs):
            ps = [r["p_pass"] for r in same_fixture if r["p_pass"] is not None]
            if ps:
                spreads.append(max(ps) - min(ps))
        print(f"largest run-to-run difference in P(pass) for one fixture: {max(spreads):.2f}")
    print()
    print("| criterion | pass on good | false-fail on good | false-pass on bad | fail on bad "
          "| pass on adversarial | fail on adversarial | escapes (g/b/a) | errors "
          "| input bytes min/median/max | bar met |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    summary = {}
    for crit in CRITERIA:
        rs = by_crit.get(crit)
        if not rs:
            continue
        count = {lab: {"n": 0, "pass": 0, "fail": 0, "escape": 0, "error": 0} for lab in LABELS}
        for r in rs:
            count[r["label"]]["n"] += 1
            count[r["label"]][r["outcome"]] += 1
        g, b, a = count["good"], count["bad"], count["adversarial"]
        sizes = [r["input_bytes"] for r in rs]
        errors = g["error"] + b["error"] + a["error"]
        # The bar for trusting a pass: at least 20 bad and 5 adversarial
        # fixtures, none of which pass, and every answer obtained. The
        # seeded-versus-natural table below says how many bad fixtures were
        # seeded, since the strategy's wording asks for 20 seeded.
        bar = b["n"] >= 20 and a["n"] >= 5 and b["pass"] == 0 and a["pass"] == 0 and errors == 0
        print(
            f"| {crit} | {rate(g['pass'], g['n'])} | {rate(g['fail'], g['n'])} | {rate(b['pass'], b['n'])} "
            f"| {rate(b['fail'], b['n'])} | {rate(a['pass'], a['n'])} | {rate(a['fail'], a['n'])} "
            f"| {g['escape']}/{b['escape']}/{a['escape']} | {errors} "
            f"| {min(sizes)}/{int(statistics.median(sizes))}/{max(sizes)} | {'yes' if bar else 'no'} |"
        )
        summary[crit] = {"counts": count, "bar_met": bar, "input_bytes": sizes}

    # With several runs, `rows` holds the worst probability per fixture, so
    # these are the extremes across every run.
    print()
    print("| criterion | highest P(pass) on bad or adversarial | lowest P(pass) on good |")
    print("|---|---|---|")
    for crit in summary:
        rs = by_crit[crit]
        bad = [r["p_pass"] for r in rs if r["label"] != "good" and r["p_pass"] is not None]
        good = [r["p_pass"] for r in rs if r["label"] == "good" and r["p_pass"] is not None]
        high = f"{max(bad):.2f}" if bad else "-"
        low = f"{min(good):.2f}" if good else "-"
        print(f"| {crit} | {high} | {low} |")

    print()
    print("| criterion | seeded bad | natural bad | bar met on bad of either kind | 20 or more seeded |")
    print("|---|---|---|---|---|")
    for crit in summary:
        bad = [r for r in by_crit[crit] if r["label"] == "bad"]
        seeded = sum(r["seeded"] for r in bad)
        print(f"| {crit} | {seeded} | {len(bad) - seeded} | {'yes' if summary[crit]['bar_met'] else 'no'} "
              f"| {'yes' if seeded >= 20 else 'no'} |")
    return summary


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--stub", action="store_true", help="canned offline answers (tests the harness only)")
    src.add_argument("--replay", metavar="FILE", action="append",
                     help="re-score answers recorded by --record; repeat to score several runs, "
                          "each fixture by its worst answer")
    src.add_argument("--live", action="store_true", help="call Jev over the network")
    src.add_argument("--export-koto", metavar="DIR",
                     help="write one koto fixture file per criterion (id, inputs, expected) and exit")
    ap.add_argument("--fixtures", default=str(DEFAULT_FIXTURES))
    ap.add_argument("--criterion", action="append", default=[], help="grade only this criterion (repeatable)")
    ap.add_argument("--kind", choices=("noul", "choice"), default="noul")
    ap.add_argument("--threshold", type=float, default=0.9, help="koto's default is 0.9")
    ap.add_argument("--record", metavar="FILE", help="with --live or --stub, append each request and answer here")
    ap.add_argument("--results", metavar="FILE", help="write one scored row per fixture here")
    ap.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    ap.add_argument("--timeout", type=float, default=20.0)
    ap.add_argument("--pause", type=float, default=0.2, help="seconds between live requests")
    args = ap.parse_args()

    if not 0.5 <= args.threshold <= 1.0:
        sys.exit("--threshold must be between 0.5 and 1.0, as koto requires")
    if args.record and args.replay:
        sys.exit("--record can't be combined with --replay")

    fixtures = load_fixtures(args.fixtures, set(args.criterion))
    if not fixtures:
        sys.exit("no fixtures selected")

    if args.export_koto:
        # koto's fixture format carries no label or source. The expected
        # value is written for a two-value enum field (pass, fail) with the
        # escape `unclear`, the shape the templates in koto/ declare.
        out_dir = Path(args.export_koto)
        out_dir.mkdir(parents=True, exist_ok=True)
        for crit in CRITERIA:
            rows = [fx for fx in fixtures if fx["criterion"] == crit]
            if not rows:
                continue
            with open(out_dir / f"{crit}.jsonl", "w", encoding="utf-8") as f:
                for fx in rows:
                    f.write(json.dumps({"id": fx["id"], "inputs": fx["inputs"],
                                        "expected": "pass" if fx["label"] == "good" else "fail"}) + "\n")
        return

    key = None
    if args.live:
        key = os.environ.get("JEV_API_KEY") or os.environ.get("KOTO_DECIDER_API_KEY")
        if not key:
            sys.exit("--live needs JEV_API_KEY or KOTO_DECIDER_API_KEY in the environment")

    replays = []
    for path in args.replay or []:
        answers = {}
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    rec = json.loads(line)
                    if rec.get("kind", "noul") == args.kind:
                        answers[rec["id"]] = rec
        replays.append(answers)

    record = open(args.record, "a", encoding="utf-8") if args.record else None
    runs = []
    try:
        for replayed in replays or [None]:
            rows = []
            for fx in fixtures:
                body = build_request(fx, args.kind)
                input_bytes = sum(len(v.encode("utf-8")) for v in body["state"].values())
                latency = None
                if args.stub:
                    response = stub_answer(fx, args.kind)
                    if record:
                        record.write(json.dumps({"id": fx["id"], "kind": args.kind, "request": body,
                                                 "response": response, "latency_ms": None}) + "\n")
                elif replayed is not None:
                    rec = replayed.get(fx["id"])
                    if rec is None:
                        sys.exit(f"no recorded {args.kind} answer for fixture {fx['id']!r}")
                    response = rec["response"]
                    latency = rec.get("latency_ms")
                else:
                    response, latency = call_live(args.endpoint, key, body, args.timeout)
                    if record:
                        record.write(json.dumps({"id": fx["id"], "kind": args.kind, "request": body,
                                                 "response": response, "latency_ms": latency}) + "\n")
                        record.flush()
                    time.sleep(args.pause)
                out, p = outcome(fx["criterion"], args.kind, response, args.threshold)
                rows.append({
                    "id": fx["id"], "criterion": fx["criterion"], "label": fx["label"],
                    "outcome": out, "p_pass": p, "model": response.get("model"),
                    "input_bytes": input_bytes, "latency_ms": latency,
                    "input_tokens": (response.get("usage") or {}).get("input_tokens"),
                    # A fixture whose text was modified says "seeded" in its
                    # source; unmodified text is natural.
                    "seeded": "seeded" in fx["source"],
                })
            runs.append(rows)
    finally:
        if record:
            record.close()

    batched = "no (one question per request)"
    if args.stub or args.live:
        source = "stub" if args.stub else "live"
        rows = runs[0]
    else:
        names = [os.path.basename(p) for p in args.replay]
        if len(runs) == 1:
            source, rows = "replay of " + names[0], runs[0]
        else:
            for name, run in zip(names, runs):
                report(run, args.threshold, args.kind, "replay of " + name, batched)
                print()
            source = f"worst case across {len(runs)} runs ({', '.join(names)})"
            rows = worst_case(runs)
    report(rows, args.threshold, args.kind, source, batched, runs)
    if args.results:
        with open(args.results, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")


if __name__ == "__main__":
    main()
