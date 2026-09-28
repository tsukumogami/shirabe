"""records.py - turn an ablation run's raw outputs into its record, and
summarise committed records.

A run's raw outputs are the files the harness and the koto wrapper leave in the
run directory: productions.jsonl (every production the wrapper saw, graded or
not, and the delivery), koto-calls.jsonl (every koto call the agent made, with
the session's state at each `koto next`), transcript.jsonl (the model session's
stream-json, each line stamped with the same monotonic clock) and
koto-state.jsonl (the koto session's state file). The record carries the
offload baseline's attribute names (provisional-1) and nothing that could
identify a machine: no path, no prompt text, no transcript excerpt, and reason
codes only from a closed pattern.

The summary is plain text, deterministic for given records, and is what
`check-figures` compares with the committed summary.txt.
"""

import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import tempfile

DEFINITION_VERSION = "provisional-1"
REASON_RE = re.compile(r"^[a-z0-9-]{1,40}$")
POINTS = ("first", "second", "after-one-delivery")
ARMS = ("full", "withheld", "without_skill")

# Decision thresholds from the PRD: (row, byte ceiling, break-even low, high).
THRESHOLD_ROWS = (
    ("single rule", 1024, 1.5, 3.0),
    ("4 KB section", 8192, 10.0, 20.0),
    ("16 KB reference", None, 40.0, 90.0),
)


# -- derivation -----------------------------------------------------------------

def read_jsonl(path):
    if not os.path.isfile(path):
        return []
    out = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except ValueError:
                continue
    return out


def transcript_events(run_dir):
    """(t, event) pairs from the stamped stream-json transcript."""
    events = []
    for entry in read_jsonl(os.path.join(run_dir, "transcript.jsonl")):
        try:
            events.append((entry["t"], json.loads(entry["line"])))
        except (KeyError, ValueError, TypeError):
            continue
    return events


def tool_uses(events):
    for t, ev in events:
        if ev.get("type") != "assistant":
            continue
        for block in (ev.get("message") or {}).get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                yield t, block


def tool_results(events, include_errors=True):
    for t, ev in events:
        if ev.get("type") != "user":
            continue
        content = (ev.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                if block.get("is_error") and not include_errors:
                    continue
                yield t, block.get("tool_use_id"), result_text(block.get("content"))


def result_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(c.get("text", "") for c in content if isinstance(c, dict))
    return ""


def user_texts(events):
    for t, ev in events:
        if ev.get("type") != "user":
            continue
        content = (ev.get("message") or {}).get("content")
        if isinstance(content, str):
            yield t, content
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    yield t, block.get("text", "")


def norm(text):
    return " ".join(text.split())


def observations(productions, suspect_reason):
    """The first and second observation points, and the effective outcome
    after at most one delivery, from the wrapper's production log."""
    first = next((p for p in productions if p.get("point") == "first"), None)
    second = next((p for p in productions if p.get("point") == "second"), None)
    delivered = any(p.get("delivered") for p in productions)
    obs = []

    def point(name, index, prod, status):
        entry = {"point": name, "point.status": status, "observed_by": "script"}
        if status == "observed":
            entry["opportunity.index"] = index
            entry["opportunity.outcome"] = prod.get("outcome", "not-checkable")
            reason = prod.get("reason", "")
            entry["reason"] = reason if REASON_RE.match(reason or "") else "check-error"
            if suspect_reason:
                entry["opportunity.outcome"] = "not-checkable"
                entry["reason"] = suspect_reason
        return entry

    obs.append(point("first", 1, first, "observed" if first else "not-produced"))
    if not first or not delivered:
        obs.append(point("second", 2, None, "not-reached" if first else "not-produced"))
    else:
        obs.append(point("second", 2, second, "observed" if second else "not-produced"))
    # The outcome a deployed gate would leave after at most one delivery.
    effective = dict(obs[1] if delivered else obs[0])
    effective["point"] = "after-one-delivery"
    obs.append(effective)
    return obs, delivered


def detect_leak(events, span_text, delivery_t):
    """Did the withheld text reach the agent before the delivery? Judged on
    content: any line of the span over 20 characters, whitespace-normalised,
    in a tool result or user text. Naming the file (a `find` for it, say) is
    not a leak; reading it anywhere, the checkout or an installed plugin
    included, is."""
    lines = [norm(l) for l in span_text.splitlines() if len(norm(l)) > 20]
    for t, text in list((t, x) for t, _, x in tool_results(events)) + list(user_texts(events)):
        if delivery_t is not None and t >= delivery_t:
            continue
        flat = norm(text)
        if any(l in flat for l in lines):
            return True
    return False


KOTO_NEXT_RE = re.compile(r"(^|[\s;&|(])(\S*/)?koto\s+next\s+\S+[^\n]*--with-data")


def detect_bypass(events, calls, real_koto):
    """A submission the transcript shows but the wrapper never logged."""
    submitted = 0
    for _, block in tool_uses(events):
        cmd = (block.get("input") or {}).get("command")
        if not isinstance(cmd, str):
            continue
        if real_koto and real_koto in cmd:
            return True
        submitted += len(KOTO_NEXT_RE.findall(cmd))
    logged = sum(1 for c in calls if (c.get("argv") or [])[:1] == ["next"]
                 and any(a == "--with-data" or a.startswith("--with-data=") for a in c.get("argv") or []))
    return submitted > logged


def usage_total(u):
    return sum(int(u.get(k, 0) or 0) for k in ("input_tokens", "cache_read_input_tokens",
                                                 "cache_creation_input_tokens", "output_tokens"))


def token_figures(events, calls):
    result = next((ev for _, ev in reversed(events) if ev.get("type") == "result"), None)
    per_msg = {}
    order = []
    for t, ev in events:
        if ev.get("type") != "assistant":
            continue
        msg = ev.get("message") or {}
        mid = msg.get("id")
        if mid is None or not isinstance(msg.get("usage"), dict):
            continue
        if mid not in per_msg:
            order.append(mid)
        per_msg[mid] = (t, msg["usage"])
    session = {"input": 0, "cache_read": 0, "cache_creation": 0, "output": 0}
    keys = {"input": "input_tokens", "cache_read": "cache_read_input_tokens",
            "cache_creation": "cache_creation_input_tokens", "output": "output_tokens"}
    if result and isinstance(result.get("usage"), dict):
        for k, src in keys.items():
            session[k] = int(result["usage"].get(src, 0) or 0)
        session["partial"] = False
    else:
        for mid in order:
            for k, src in keys.items():
                session[k] += int(per_msg[mid][1].get(src, 0) or 0)
        session["partial"] = True
    session["total"] = sum(session[k] for k in keys)
    model_usage = (result or {}).get("modelUsage") if isinstance((result or {}).get("modelUsage"), dict) else {}
    cost = (result or {}).get("total_cost_usd")
    cost = round(float(cost), 6) if isinstance(cost, (int, float)) else None

    ticks = [(c["t"], c.get("state")) for c in calls
             if "state" in c and isinstance(c.get("t"), int)]
    per_state = {}
    pre_first = 0
    for mid in order:
        t, u = per_msg[mid]
        # Input-side only: Claude Code streams each content block with the
        # usage from the start of the message, so a message's output tokens
        # are only right in the result event's total.
        inside = usage_total(u) - int(u.get("output_tokens", 0) or 0)
        later = [s for ts, s in ticks if ts >= t]
        if not ticks or t < ticks[0][0]:
            pre_first += inside
            continue
        state = later[0] if later else "after-last-tick"
        state = state if isinstance(state, str) and re.match(r"^[a-z0-9_-]{1,64}$", state) else "unknown"
        per_state[state] = per_state.get(state, 0) + inside
    return session, model_usage, cost, per_state, pre_first


def skill_body_bytes(plugin, skill):
    """The bytes the skill's SKILL.md puts in front of the agent when the
    prompt invokes it: the file after its frontmatter. Claude Code does not
    echo the expanded skill into stream-json, so it is read from the copy."""
    path = os.path.join(plugin, "skills", skill, "SKILL.md")
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return 0
    if lines and lines[0] == "---" and "---" in lines[1:]:
        lines = lines[lines.index("---", 1) + 1:]
    return len("\n".join(lines).encode())


def observed_instruction(events, plugin, first_tick, skill_bytes=0):
    ids = {}
    for t, block in tool_uses(events):
        inp = block.get("input") or {}
        path = inp.get("file_path") if block.get("name") == "Read" else None
        cmd = inp.get("command") if block.get("name") == "Bash" else None
        if (isinstance(path, str) and path.startswith(plugin + "/")) or \
                (isinstance(cmd, str) and plugin + "/" in cmd):
            ids[block.get("id")] = t
    # The skill body is loaded with the prompt, before any tick.
    total = pre = skill_bytes
    for t, tid, text in tool_results(events, include_errors=False):
        if tid in ids:
            n = len(text.encode())
            total += n
            if first_tick is None or t < first_tick:
                pre += n
    for t, text in user_texts(events):
        if plugin in text:
            n = len(text.encode())
            total += n
            if first_tick is None or t < first_tick:
                pre += n
    return {"total": int(total / 4 + 0.5), "pre_first_state": int(pre / 4 + 0.5)}


def static_instruction(repo_root, plugin, profile, arm):
    """The baseline's count over what the arm loads, so it sits beside the
    pinned figure. The manifest also lists files outside the plugin tree (the
    repository's own .claude/shirabe-extensions/), which a fixture run does
    not load but the baseline counts; the count tree links the arm's copy and
    adds those from the checkout, so the only difference from the pinned
    figure is what the arm changed."""
    if arm == "without_skill":
        return {"raw": 0, "weighted": 0}
    overlay = tempfile.mkdtemp(prefix="ablation-count-")
    try:
        for part in os.listdir(plugin):
            os.symlink(os.path.join(plugin, part), os.path.join(overlay, part))
        ext = os.path.join(repo_root, ".claude", "shirabe-extensions")
        if os.path.isdir(ext):
            shutil.copytree(ext, os.path.join(overlay, ".claude", "shirabe-extensions"))
        out = subprocess.run([os.path.join(repo_root, "scripts", "offload-baseline.sh"), "count", "--tree", overlay],
                             cwd=repo_root, capture_output=True, text=True)
    finally:
        shutil.rmtree(overlay, ignore_errors=True)
    for line in out.stdout.splitlines():
        parts = line.split("\t")
        if parts[0] == profile and len(parts) == 3:
            return {"raw": int(parts[1]), "weighted": int(parts[2])}
    return {"raw": None, "weighted": None}


def template_fields(repo_root, plugin, template, run_dir, classify):
    fields = {"template.path": template}
    blob = subprocess.run(["git", "hash-object", "--", os.path.join(plugin, template)], cwd=repo_root,
                          capture_output=True, text=True).stdout.strip()
    fields["template.git_blob"] = blob
    try:
        with open(os.path.join(repo_root, "docs", "measurement", "offload-baseline", "template-pin.json")) as fh:
            pin = json.load(fh)
        pinned = {t["path"]: t for t in pin.get("templates", [])}
        fields["template.pin_blob_match"] = pinned.get(template, {}).get("git_blob") == blob
    except (OSError, ValueError, KeyError):
        fields["template.pin_blob_match"] = False
    header = {}
    state = os.path.join(run_dir, "koto-state.jsonl")
    if os.path.isfile(state):
        with open(state) as fh:
            try:
                header = json.loads(fh.readline())
            except ValueError:
                header = {}
    koto_hash = header.get("template_hash")
    fields["template.koto_hash"] = koto_hash if isinstance(koto_hash, str) and re.match(r"^[0-9a-f]{64}$", koto_hash) else None
    fields["template.fixture"] = classify(header) == "fixture"
    return fields


def derive(raw, repo_root, real_koto, koto_version, classify):
    case = raw["case"]
    run_dir = raw["run_dir"]
    productions = read_jsonl(os.path.join(run_dir, "productions.jsonl"))
    calls = read_jsonl(os.path.join(run_dir, "koto-calls.jsonl"))
    events = transcript_events(run_dir)
    delivery_t = next((p["t"] for p in productions if p.get("delivered")), None)

    leak = raw["arm"] == "withheld" and detect_leak(events, raw["span"].decode("utf-8", "replace"), delivery_t)
    bypass = detect_bypass(events, calls, real_koto)
    suspect = ("harness-tampered" if raw["tampered"] else
               "wrapper-bypassed" if bypass else
               "section-leaked" if leak else None)
    obs, delivered = observations(productions, suspect)

    session, model_usage, cost, per_state, pre_first = token_figures(events, calls)
    first_tick = next((c["t"] for c in calls if "state" in c), None)
    model = next((ev.get("model") for _, ev in events
                  if ev.get("type") == "system" and ev.get("subtype") == "init"), None)

    record = {
        "definition.version": DEFINITION_VERSION,
        "case.id": case["id"],
        "arm": raw["arm"],
        "repetition": raw["repetition"],
        "arm_order": raw["arm_order"],
        "run.id": f"{case['id']}/r{raw['repetition']}/{raw['arm']}",
        "skill": case["skill"],
        "state": case["target_state"],
        "model": model if isinstance(model, str) and re.match(r"^[A-Za-z0-9.:_-]{1,80}$", model) else None,
        "rule.source": case["withhold"]["source"],
        "rule.source_commit": case["withhold"]["source_commit"],
        "koto.version": koto_version,
        "delivery.shape": raw["delivery_shape"],
        "rule.span_bytes": len(raw["span"]),
        "delivered": delivered,
        "leak": leak,
        "wrapper_bypassed": bypass,
        "harness_tampered": raw["tampered"],
        "session_killed": bool(raw["agent"].get("killed")),
        "observations": obs,
        "tokens": {
            "session": session,
            "model_usage": {k: {kk: vv for kk, vv in v.items() if isinstance(vv, (int, float))}
                            for k, v in model_usage.items() if isinstance(v, dict)
                            and re.match(r"^[A-Za-z0-9.:_-]{1,80}$", k)},
            "per_state_input": per_state,
            "pre_first_state_input": pre_first,
            "instruction_static": static_instruction(repo_root, raw["plugin"], case["profile"], raw["arm"]),
            "instruction_observed": observed_instruction(
                events, raw["plugin"], first_tick,
                skill_body_bytes(raw["plugin"], case["skill"])
                if raw["arm"] != "without_skill" and case["prompt"]["with_skill"].startswith("/") else 0),
        },
        "cost_usd": cost,
        "audit": {"sample_rate": raw["audit_rate"], "rules": [
            {"rule.source": a["rule.source"], "rule.source_commit": a["rule.source_commit"],
             "opportunity.outcome": a["opportunity.outcome"],
             "reason": a["reason"] if REASON_RE.match(a["reason"] or "") else "check-error"}
            for a in raw["audits"]]},
    }
    record.update(template_fields(repo_root, raw["plugin"], case["setup"]["template"], run_dir, classify))
    return record


# -- statistics -------------------------------------------------------------------

def binom_cdf(x, n, p):
    return sum(math.comb(n, k) * p ** k * (1 - p) ** (n - k) for k in range(0, x + 1))


def clopper_pearson_upper(x, n, alpha=0.05):
    """Two-sided (1 - alpha) exact upper bound for x successes in n trials."""
    if n == 0:
        return None
    if x >= n:
        return 1.0
    lo, hi = 0.0, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2
        if binom_cdf(x, n, mid) > alpha / 2:
            lo = mid
        else:
            hi = mid
    return hi


def detection_limit(n):
    """Smallest k/n distinguishable from 0/n: one-sided Fisher exact p < 0.05."""
    if n <= 0:
        return None, None
    for k in range(1, n + 1):
        if math.comb(n, k) / math.comb(2 * n, k) < 0.05:
            return k, k / n
    return None, None


# -- summary ----------------------------------------------------------------------

def pct(x):
    return "n/a" if x is None else f"{100 * x:.1f}%"


def mean(values):
    values = [v for v in values if isinstance(v, (int, float))]
    return None if not values else sum(values) / len(values)


def fmt(v):
    return "n/a" if v is None else f"{v:.1f}"


def baseline_row(repo_root, profile, commit):
    path = os.path.join(repo_root, "docs", "measurement", "offload-baseline", "token-baseline.tsv")
    try:
        with open(path) as fh:
            for line in fh:
                if line.startswith("#"):
                    continue
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 5 and parts[0] == commit and parts[1] == profile \
                        and parts[4] == "recount":
                    return int(parts[2]), int(parts[3])
    except OSError:
        pass
    return None


def summarize(records, case, repo_root):
    recs = sorted(records, key=lambda r: (r["repetition"], ARMS.index(r["arm"])))
    span_bytes = recs[0]["rule.span_bytes"] if recs else 0
    out = []
    w = out.append
    w(f"# Ablation summary: {case['id']}")
    w("")
    w(f"withheld: {case['withhold']['source']} at {case['withhold']['source_commit']} ({span_bytes} bytes)")
    w(f"deployed check: {case['deployed_check']}; delivery shape: "
      f"{', '.join(sorted({r.get('delivery.shape') or 'unknown' for r in recs}))}")
    w(f"definition: {DEFINITION_VERSION}; model: {', '.join(sorted({str(r.get('model')) for r in recs}))}; "
      f"koto: {', '.join(sorted({str(r.get('koto.version')) for r in recs}))}")
    reps = sorted({r["repetition"] for r in recs})
    w(f"repetitions: {len(reps)}; runs: {len(recs)}")
    w("")
    w("## Violations of the withheld rule, by arm and observation point")
    w("")
    w("arm            point               runs  viol  checkable  not-checkable  not-produced  not-reached  rate    95% upper")
    counts = {}
    for arm in ARMS:
        ar = [r for r in recs if r["arm"] == arm]
        for pt in POINTS:
            obs = [o for r in ar for o in r["observations"] if o["point"] == pt]
            observed = [o for o in obs if o["point.status"] == "observed"]
            viol = sum(1 for o in observed if o.get("opportunity.outcome") == "violated")
            chk = sum(1 for o in observed if o.get("opportunity.outcome") in ("violated", "complied"))
            nc = sum(1 for o in observed if o.get("opportunity.outcome") == "not-checkable")
            npd = sum(1 for o in obs if o["point.status"] == "not-produced")
            nr = sum(1 for o in obs if o["point.status"] == "not-reached")
            rate = viol / chk if chk else None
            upper = clopper_pearson_upper(viol, chk)
            counts[(arm, pt)] = (viol, chk)
            w(f"{arm:<14} {pt:<19} {len(ar):>4}  {viol:>4}  {chk:>9}  {nc:>13}  {npd:>12}  {nr:>11}  "
              f"{pct(rate):<7} {pct(upper)}")
    w("")
    w("leaks (withheld text reached the agent before delivery): " +
      ", ".join(f"{arm} {sum(1 for r in recs if r['arm'] == arm and r.get('leak'))}" for arm in ARMS))
    w("wrapper bypassed: " + ", ".join(f"{arm} {sum(1 for r in recs if r['arm'] == arm and r.get('wrapper_bypassed'))}"
                                        for arm in ARMS))
    w("harness tampered: " + ", ".join(f"{arm} {sum(1 for r in recs if r['arm'] == arm and r.get('harness_tampered'))}"
                                        for arm in ARMS))
    w("")
    w("## Tokens (means per run)")
    w("")
    w("arm            input     cache read  cache create  output    session total  delta vs full  static raw  static weighted  observed instr  observed pre-state")
    full_total = mean([r["tokens"]["session"].get("total") for r in recs if r["arm"] == "full"])
    for arm in ARMS:
        ar = [r for r in recs if r["arm"] == arm]
        tot = mean([r["tokens"]["session"].get("total") for r in ar])
        delta = None if tot is None or full_total is None else tot - full_total
        w(f"{arm:<14} {fmt(mean([r['tokens']['session'].get('input') for r in ar])):>8}  "
          f"{fmt(mean([r['tokens']['session'].get('cache_read') for r in ar])):>10}  "
          f"{fmt(mean([r['tokens']['session'].get('cache_creation') for r in ar])):>12}  "
          f"{fmt(mean([r['tokens']['session'].get('output') for r in ar])):>8}  "
          f"{fmt(tot):>13}  {fmt(delta):>13}  "
          f"{fmt(mean([r['tokens']['instruction_static']['raw'] for r in ar])):>10}  "
          f"{fmt(mean([r['tokens']['instruction_static']['weighted'] for r in ar])):>15}  "
          f"{fmt(mean([r['tokens']['instruction_observed']['total'] for r in ar])):>14}  "
          f"{fmt(mean([r['tokens']['instruction_observed']['pre_first_state'] for r in ar])):>18}")
    pinned = baseline_row(repo_root, case["profile"], "2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10")
    w(f"pinned baseline ({case['profile']}, 2a3719e): " +
      ("n/a" if pinned is None else f"raw {pinned[0]}, weighted {pinned[1]}"))
    partial = sum(1 for r in recs if r["tokens"]["session"].get("partial"))
    w(f"runs with partial token figures (no result event): {partial}")
    spend = [r.get("cost_usd") for r in recs if isinstance(r.get("cost_usd"), (int, float))]
    w(f"model spend reported by the sessions: {len(spend)} of {len(recs)} runs, total ${sum(spend):.2f}")
    w("")
    w("## Audit of rules left unchecked in normal runs (withheld rate minus full rate)")
    w("")
    rules = sorted({a["rule.source"] for r in recs for a in r["audit"]["rules"]})
    if not rules:
        w("no audit rules sampled")
    for rule in rules:
        rates = {}
        for arm in ARMS:
            outs = [a["opportunity.outcome"] for r in recs if r["arm"] == arm
                    for a in r["audit"]["rules"] if a["rule.source"] == rule]
            chk = [o for o in outs if o in ("violated", "complied")]
            rates[arm] = (sum(1 for o in chk if o == "violated"), len(chk))
        def r_(arm):
            v, n = rates[arm]
            return None if not n else v / n
        erosion = None if r_("withheld") is None or r_("full") is None else 100 * (r_("withheld") - r_("full"))
        w(f"{rule}: " + ", ".join(f"{arm} {rates[arm][0]}/{rates[arm][1]}" for arm in ARMS) +
          f"; erosion {'n/a' if erosion is None else f'{erosion:+.1f} points'}")
    rates_note = sorted({r["audit"]["sample_rate"] for r in recs})
    w(f"audit sample rate: {', '.join(str(x) for x in rates_note)}")
    w("")
    w("## Prompts")
    w("")
    w(f"full and withheld: {case['prompt']['with_skill']}")
    w(f"without_skill: {case['prompt']['without_skill']}")
    w("")
    w("## What this result can decide")
    w("")
    row = next(r for r in THRESHOLD_ROWS if r[1] is None or span_bytes < r[1])
    n = min(counts[("full", "after-one-delivery")][1], counts[("withheld", "after-one-delivery")][1])
    k, limit = detection_limit(n)
    w(f"thresholds row: {row[0]} (break-even uplift about {row[2]:g} to {row[3]:g} points)")
    if limit is None:
        w(f"detection limit at {n} checkable run(s) per arm: none; no uplift is distinguishable from zero")
    else:
        w(f"detection limit at {n} checkable run(s) per arm: {k} of {n}, {100 * limit:.1f} points "
          f"(one-sided Fisher exact, p < 0.05, against 0 of {n})")
    if limit is not None and 100 * limit <= row[2]:
        w("the detection limit is below this row's break-even uplift: an offline result at this count "
          "can support a decision on this section")
    else:
        w("the detection limit is not below this row's break-even uplift, so this result cannot support "
          "withholding the section; 'no difference seen' here is not evidence that withholding is safe. "
          "The decision needs the zero-violation rule over 15 to 30 runs per arm (after one delivery), "
          "or a live canary.")
    return "\n".join(out) + "\n"
