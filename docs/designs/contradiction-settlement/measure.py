#!/usr/bin/env python3
"""Regenerate every figure in DESIGN-contradiction-settlement.md.

Run from the repository root:

    python3 docs/designs/contradiction-settlement/measure.py

Reads inventory.json and design.md.tmpl next to this file, reads every cited
file as it is at the inventory commit (git show <commit>:<path>), checks each
location and excerpt, recomputes byte counts, totals and shares, rebuilds the
DESIGN and compares it with the committed file. Prints the summary figures.
Exits 1 when a check fails or the rebuild differs; pass --write to overwrite
the DESIGN with the rebuild instead of comparing. Standard library only. Needs the repository's full history, since it reads
files with `git show` at the inventory commit; a shallow clone fails there.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Paths below are relative to the repository root, so run from there whatever
# directory the caller is in.
os.chdir(os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
DESIGN = "docs/designs/current/DESIGN-contradiction-settlement.md"
PROFILES = ["work-on", "execute-single-pr", "execute-coordinated", "deliver", "scope"]
LOC = re.compile(r"^(\S+)#L(\d+)-L(\d+)$")
# A quoted excerpt never spells out a work-in-progress file path: the
# repository's public-content check refuses one on any changed line, quoted
# or not, so such candidates are skipped and another unique line is used.
WIP = re.compile(r"(^|[^A-Za-z0-9_])wip/[A-Za-z0-9_]")

D = json.load(open(os.path.join(HERE, "inventory.json"), encoding="utf-8"))
COMMIT = D["inventory_commit"]
RAW = D["baseline_pin"]["raw"]
_cache = {}


def text(path):
    if path not in _cache:
        out = subprocess.run(["git", "show", "%s:%s" % (COMMIT, path)],
                             capture_output=True, check=True)
        _cache[path] = out.stdout.decode("utf-8")
    return _cache[path]


def parse(loc):
    m = LOC.match(loc)
    if not m:
        raise SystemExit("bad location: " + loc)
    return m.group(1), int(m.group(2)), int(m.group(3))


def is_loc(s):
    return bool(s) and bool(LOC.match(s))


def excerpt(loc):
    path, a, b = parse(loc)
    t = text(path)
    ls = t.split("\n")
    if not (1 <= a <= b <= len(ls)):
        raise SystemExit("range outside file: " + loc)
    for i in range(a - 1, b):
        s = ls[i].strip()
        if len(s) < 12:
            continue
        for n in (40, 55, 70, 90):
            for off in range(0, max(1, len(s) - n + 1), 5):
                c = s[off:off + n].strip()
                if len(c) >= 12 and "``" not in c and t.count(c) == 1 and not WIP.search(c):
                    end = off + n
                    while end < len(s) and s[end] != " " and end - off < n + 20:
                        end += 1
                    st = off
                    while st > 0 and s[st - 1] != " " and off - st < 20:
                        st -= 1
                    c2 = s[st:end].strip()
                    return c2 if "``" not in c2 and t.count(c2) == 1 and not WIP.search(c2) else c
        if len(s) <= 120 and t.count(s) == 1 and not WIP.search(s):
            return s
    for i in range(a - 2, max(-1, a - 12), -1):
        s = ls[i].strip()
        if 12 <= len(s) <= 120 and t.count(s) == 1 and not WIP.search(s):
            return "above: " + s
        for n in (40, 55, 70):
            for off in range(0, max(1, len(s) - n + 1), 5):
                c = s[off:off + n].strip()
                if len(c) >= 12 and "``" not in c and t.count(c) == 1 and not WIP.search(c):
                    return "above: " + c
    raise SystemExit("no unique excerpt: " + loc)


def span_bytes(path, a, b):
    ls = text(path).split("\n")
    return sum(len(ls[i - 1].encode("utf-8")) + 1 for i in range(a, b + 1))


def file_bytes(path):
    return len(text(path).encode("utf-8"))


def code(s):
    return "`` " + s + " ``" if "`" in s else "`" + s + "`"


def link(loc):
    path, a, b = parse(loc)
    return code("%s#L%d" % (path, a) if a == b else "%s#L%d-L%d" % (path, a, b))


def pct(x):
    return "%.1f%%" % x


def fmt(n):
    return format(n, ",")


C = D["contradictions"]
DP = D["deadprose"]
WH = D["withholding"]
pol = [c for c in C if c["class"] == "policy"]
mech = [c for c in C if c["class"] == "mechanical"]
policy_ids = {c["id"] for c in pol}

# ---- checks: protected spans ----
problems = []
wh_lines = {}
for w in WH:
    for loc in w["spans"]:
        p, a, b = parse(loc)
        wh_lines.setdefault(p, set()).update(range(a, b + 1))
protect = {}
for c in C:
    locs = [s["loc"] for s in c["sides"]] if c["class"] == "policy" else [c["winner"]]
    for l in locs:
        p, a, b = parse(l)
        protect.setdefault(p, []).append((set(range(a, b + 1)), c["id"]))
dead_lines = {}
for it in DP:
    for sp in it["spans"]:
        p, a, b = parse(sp["loc"])
        dead_lines.setdefault(p, set()).update(range(a, b + 1))
for it in DP:
    for sp in it["spans"]:
        p, a, b = parse(sp["loc"])
        rng = set(range(a, b + 1))
        if rng & wh_lines.get(p, set()):
            problems.append("withholding overlap: %s %s" % (it["id"], sp["loc"]))
        if it.get("blocked_on"):
            continue
        for r, cid in protect.get(p, []):
            if r & rng:
                problems.append("protected overlap: %s %s %s" % (it["id"], sp["loc"], cid))
        if sp.get("whole"):
            for r, cid in protect.get(sp["whole"], []):
                if cid in policy_ids:
                    problems.append("pointer unloads policy: %s %s %s" % (it["id"], sp["whole"], cid))
    for sv in [sp.get("survivor") for sp in it["spans"]] + [it.get("survivor")]:
        if is_loc(sv):
            p, a, b = parse(sv)
            if set(range(a, b + 1)) <= dead_lines.get(p, set()):
                problems.append("survivor deleted: %s %s" % (it["id"], sv))
missing_r2 = [k for k in range(1, 20) if not any(c.get("r2") == k for c in C)]
if missing_r2:
    problems.append("PRD R2 items without an identifier: %r" % missing_r2)
ids = [c["id"] for c in C] + [d["id"] for d in DP]
if len(ids) != len(set(ids)):
    problems.append("duplicate identifiers")

# ---- totals ----
lines_by = {p: {} for p in PROFILES}
whole_by = {p: set() for p in PROFILES}
for it in DP:
    for sp in it["spans"]:
        p, a, b = parse(sp["loc"])
        excerpt(sp["loc"])
        for prof in it["profiles"]:
            if sp.get("whole"):
                whole_by[prof].add(sp["whole"])
            else:
                lines_by[prof].setdefault(p, set()).update(range(a, b + 1))
tot = {}
for prof in PROFILES:
    b = 0
    for path, lns in lines_by[prof].items():
        if path in whole_by[prof]:
            continue
        ls = text(path).split("\n")
        b += sum(len(ls[i - 1].encode("utf-8")) + 1 for i in lns)
    b += sum(file_bytes(f) for f in whole_by[prof])
    tot[prof] = b
share = {p: 100.0 * (tot[p] / 4.0) / RAW[p] for p in PROFILES}
parent_bytes = sum(file_bytes(f) for f in D["parent_references"])
parent_share = 100.0 * (parent_bytes / 4.0) / RAW["scope"]
held_bytes = sum(span_bytes(*parse(l)) for l in D["held_for_policy"])


def item_bytes(it):
    b = 0
    for sp in it["spans"]:
        if sp.get("whole"):
            b += file_bytes(sp["whole"])
        else:
            b += span_bytes(*parse(sp["loc"]))
    return b


# ---- sections ----
def render_item(c, w):
    w("#### `%s`" % c["id"])
    w("")
    meta = "%s. Class: **%s**. Profiles: %s." % (c["title"], c["class"], ", ".join("`%s`" % p for p in c["profiles"]))
    if c.get("r2"):
        meta += " PRD R2 item %d." % c["r2"]
    w(meta)
    w("")
    w("Statements:")
    w("")
    for s in c["sides"]:
        w("- %s: %s. Excerpt: %s" % (link(s["loc"]), s["says"], code(excerpt(s["loc"]))))
    if c.get("code"):
        w("")
        w("What runs:")
        w("")
        for s in c["code"]:
            w("- %s: %s. Excerpt: %s" % (link(s["loc"]), s["says"], code(excerpt(s["loc"]))))
    w("")
    if c["class"] == "mechanical":
        excerpt(c["winner"])
        w("Winner: %s. %s" % (link(c["winner"]), c["reason"]))
    else:
        d = c["decision"]
        rec = "docs/decisions/DECISION-contradiction-%s-2026-09-28.md" % c["id"]
        if not os.path.exists(rec):
            raise SystemExit("decision record missing: " + rec)
        r = d["options"][d["recommended"]]["name"]
        w("Winner: decided by the policy owner (record linked below). Recommended: option %d, %s." % (d["recommended"] + 1, r[0].lower() + r[1:]))
        w("")
        w("- **Context.** " + d["context"])
        w("- **Problem.** " + d["problem"])
        for i, o in enumerate(d["options"]):
            tag = " (recommended)" if i == d["recommended"] else ""
            w("- **Option %d%s: %s.** %s" % (i + 1, tag, o["name"], o["why"]))
        w("- **Why the recommendation.** " + d["reason"])
        w("- **Decided.** See [`%s`](../../decisions/%s)." % (rec, os.path.basename(rec)))
    w("")


def section(fn):
    out = []
    fn(out.append)
    return "\n".join(out).strip("\n")


def contr(w):
    w("### Policy calls")
    w("")
    w("Each was open when the inventory was taken, and each has since been decided by the policy owner and recorded under `docs/decisions/`; every item below links its record. The options and recommendations are as they were put to the policy owner.")
    w("")
    for c in pol:
        render_item(c, w)
    w("### Mechanical items")
    w("")
    for c in mech:
        render_item(c, w)


def r2(w):
    w("| PRD R2 item | Identifier(s) |")
    w("|---|---|")
    for k in range(1, 20):
        w("| %d | %s |" % (k, ", ".join("`%s`" % c["id"] for c in C if c.get("r2") == k) or "missing"))


CAT = [("rationale", "Design rationale shipped as a prompt"), ("duplicate", "Duplicated blocks"),
       ("missing-file", "Steps naming files or mechanisms that no longer exist"),
       ("koto-does-it", "Text describing what koto or a script already does")]


def dead(w):
    for cat, name in CAT:
        items = [i for i in DP if i["category"] == cat]
        w("#### %s" % name)
        w("")
        if not items:
            w("None found.")
            w("")
            continue
        for it in items:
            w("##### `%s`" % it["id"])
            w("")
            ib = item_bytes(it)
            head = "Profiles: %s. Size: %d bytes (about %d tokens)." % (", ".join("`%s`" % p for p in it["profiles"]), ib, ib // 4)
            sv = it.get("survivor")
            if sv and sv != "none":
                head += " Surviving statement: %s." % (link(sv) if is_loc(sv) else sv)
            else:
                head += " Only statement of a rule in force: no."
            w(head)
            if it.get("blocked_on"):
                w("")
                w("Blocked on: %s." % ", ".join("`%s`" % x for x in it["blocked_on"]))
            if it.get("note"):
                w("")
                w(it["note"])
            w("")
            for sp in it["spans"]:
                p, a, b = parse(sp["loc"])
                if sp.get("whole"):
                    line = "- pointer %s (excerpt %s) loads the whole of `%s`, %d bytes" % (link(sp["loc"]), code(excerpt(sp["loc"])), sp["whole"], file_bytes(sp["whole"]))
                else:
                    line = "- %s, %d bytes, excerpt %s" % (link(sp["loc"]), span_bytes(p, a, b), code(excerpt(sp["loc"])))
                s2 = sp.get("survivor")
                if s2:
                    line += "; survivor %s" % (link(s2) if is_loc(s2) else s2)
                w(line)
            w("")


def totals(w):
    w("| Profile | Raw load at the pin (tokens) | Dead prose (bytes) | Dead prose (tokens) | Share of raw |")
    w("|---|---:|---:|---:|---:|")
    for p in PROFILES:
        w("| `%s` | %s | %s | %s | %s |" % (p, fmt(RAW[p]), fmt(tot[p]), fmt(tot[p] // 4), pct(share[p])))


def withholding(w):
    for wv in WH:
        b = sum(span_bytes(*parse(l)) for l in wv["spans"])
        w("- `%s` (%s; %d bytes). %s Spans: %s." % (wv["id"], ", ".join("`%s`" % p for p in wv["profiles"]), b, wv["reason"], ", ".join(link(l) for l in wv["spans"])))


def files(w):
    man = D["baseline_pin"]["manifest_files"]
    for p in PROFILES:
        fs = [D["templates"][p]] + sorted(set(man[p]))
        w("- `%s`, %d files from the load manifest plus the template: %s. Also read because a directive or SKILL.md names it or it enforces a side: %s." % (
            p, len(set(man[p])), ", ".join("`%s`" % f for f in fs), ", ".join("`%s`" % f for f in D["files_extra"][p])))


values = {
    "FILES": section(files), "R2": section(r2), "CONTR": section(contr), "DEAD": section(dead),
    "TOT": section(totals), "WH": section(withholding),
}
tmpl = open(os.path.join(HERE, "design.md.tmpl"), encoding="utf-8").read()
for k, v in values.items():
    tmpl = tmpl.replace("<!-- %s -->" % k, v)
nums = {
    "N_ITEMS": str(len(C)), "N_MECH": str(len(mech)), "N_POL": str(len(pol)),
    "PARENT_BYTES": fmt(parent_bytes), "PARENT_TOKENS": fmt(parent_bytes // 4), "PARENT_SHARE": pct(parent_share),
    "SCOPE_WITH_PARENT": pct(share["scope"] + parent_share),
    "HELD_BYTES": fmt(held_bytes), "HELD_SPANS": str(len(D["held_for_policy"])),
}
for p in PROFILES:
    nums["SHARE_" + p] = pct(share[p])
for k, v in nums.items():
    tmpl = tmpl.replace("{{%s}}" % k, v)
left = [k for k in list(nums) + ["SHARE_" + p for p in PROFILES] if "{{%s}}" % k in tmpl]
left += re.findall(r"<!-- [A-Z]+ -->", tmpl)
if left:
    problems.append("unfilled placeholders: %r" % left)

print("inventory commit: %s" % COMMIT)
print("contradictions: %d (mechanical %d, policy %d)" % (len(C), len(mech), len(pol)))
print("dead-prose entries: %d, spans: %d" % (len(DP), sum(len(i["spans"]) for i in DP)))
for p in PROFILES:
    print("dead prose %-20s %8d bytes %7d tokens %6s of raw %d" % (p, tot[p], tot[p] // 4, pct(share[p]), RAW[p]))
print("parent-skill references: %d bytes, %d tokens, %s of scope raw" % (parent_bytes, parent_bytes // 4, pct(parent_share)))
print("scope with parent references: %s" % pct(share["scope"] + parent_share))
print("held for policy items: %d bytes over %d spans" % (held_bytes, len(D["held_for_policy"])))

if "--write" in sys.argv:
    open(DESIGN, "w", encoding="utf-8").write(tmpl)
    print("wrote " + DESIGN)
else:
    current = open(DESIGN, encoding="utf-8").read()
    if current != tmpl:
        problems.append("rebuild differs from " + DESIGN)
if problems:
    for p in problems:
        print("FAIL: " + p)
    sys.exit(1)
print("OK: every check passed and the rebuild matches")
