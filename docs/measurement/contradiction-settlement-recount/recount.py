#!/usr/bin/env python3
"""Re-count the offload baseline's profiles after contradiction settlement.

Run from the repository root:

    python3 docs/measurement/contradiction-settlement-recount/recount.py           # print the figures
    python3 docs/measurement/contradiction-settlement-recount/recount.py --check   # compare with README.md
    python3 docs/measurement/contradiction-settlement-recount/recount.py --write   # rewrite README.md's figures

and, only to re-derive the copied inventory data from the commit it names:

    python3 docs/measurement/contradiction-settlement-recount/recount.py extract <commit>

Inputs, all committed beside this script or read from git objects:

- spans.json: the contradiction-settlement inventory's dead-prose entries,
  withholding candidates and held-for-policy spans, with each span's excerpt as
  the DESIGN prints it, copied from the commit named in it. It also names the
  commits measured and the settlement pull requests.
- dropped-rows.tsv: the load-manifest rows for files a profile no longer loads.
- scripts/offload-baseline.sh count, with the load manifest read from git at
  the measured commit, so the figures don't move when the manifest does.

Every read of a measured file goes through `git show <commit>:<path>`, so the
output is the same from any checkout. Standard library only. Exits 1 when a
check fails, or with --check when README.md's figures differ.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
README = os.path.join(HERE, "README.md")
SPANS = os.path.join(HERE, "spans.json")
DROPPED = os.path.join(HERE, "dropped-rows.tsv")
COUNT = os.path.join(HERE, "..", "..", "..", "scripts", "offload-baseline.sh")
MANIFEST = "docs/measurement/offload-baseline/load-manifest.tsv"
PROFILES = ["work-on", "execute-single-pr", "execute-coordinated", "deliver", "scope"]
LOC = re.compile(r"^(\S+)#L(\d+)-L(\d+)$")
BEGIN, END = "<!-- recount:begin -->", "<!-- recount:end -->"

_cache = {}


def git(*args):
    out = subprocess.run(["git"] + list(args), capture_output=True)
    if out.returncode != 0:
        raise SystemExit("git %s failed: %s" % (" ".join(args), out.stderr.decode().strip()))
    return out.stdout.decode("utf-8")


def show(commit, path):
    key = (commit, path)
    if key not in _cache:
        _cache[key] = git("show", "%s:%s" % (commit, path))
    return _cache[key]


def parse(loc):
    m = LOC.match(loc)
    if not m:
        raise SystemExit("bad location: " + loc)
    return m.group(1), int(m.group(2)), int(m.group(3))


def line_bytes(text):
    return [len(s.encode("utf-8")) + 1 for s in text.split("\n")]


def fmt(n):
    return format(n, ",")


# ---------------------------------------------------------------- extract

def extract(commit):
    """Rebuild spans.json's inventory part from the coordination commit."""
    inv = json.loads(show(commit, "docs/designs/contradiction-settlement/inventory.json"))
    design = show(commit, "docs/designs/DESIGN-contradiction-settlement.md")
    # The DESIGN prints one line per span: "- `<loc>`, N bytes, excerpt `x`" or
    # "- pointer `<loc>` (excerpt `x`) loads the whole of ...". Excerpts holding
    # a backtick are printed as `` x ``.
    span_line = re.compile(r"^- (?:pointer )?`([^`]+#L[0-9-L]+)`.*?excerpt (``\s.*?\s``|`[^`]*`)")
    excerpts = {}
    cur = None
    for ln in design.split("\n"):
        m = re.match(r"^##### `(dp-[a-z0-9-]+)`$", ln)
        if m:
            cur = m.group(1)
            continue
        if ln.startswith("#") and not ln.startswith("#####"):
            cur = None
        m = span_line.match(ln)
        if cur and m:
            loc = m.group(1)
            if "-L" not in loc:
                loc = "%s-L%s" % (loc, loc.split("#L")[1])
            ex = m.group(2)
            ex = ex[3:-3] if ex.startswith("`` ") else ex[1:-1]
            excerpts[(cur, loc)] = ex
    entries = []
    for it in inv["deadprose"]:
        spans = []
        for sp in it["spans"]:
            ex = excerpts.get((it["id"], sp["loc"]))
            if ex is None:
                raise SystemExit("no excerpt in the DESIGN for %s %s" % (it["id"], sp["loc"]))
            # An excerpt quoting a wip/ path template would trip the
            # repository's public-content check, which refuses a wip/ file
            # path in added text; such an excerpt is stored as its sha256 and
            # length, and found by hash.
            if "wip/" in ex:
                above = ex.startswith("above: ")
                raw = ex[len("above: "):] if above else ex
                s = {"loc": sp["loc"], "excerpt_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
                     "excerpt_length": len(raw), "excerpt_above": above}
            else:
                s = {"loc": sp["loc"], "excerpt": ex}
            if sp.get("whole"):
                s["whole"] = sp["whole"]
            spans.append(s)
        entries.append({"id": it["id"], "category": it["category"], "profiles": it["profiles"], "spans": spans})
    est = {}
    for p in PROFILES:
        m = re.search(r"^\| `%s` \| [0-9,]+ \| ([0-9,]+) \| ([0-9,]+) \|" % re.escape(p), design, re.M)
        if not m:
            raise SystemExit("no estimate row for %s in the DESIGN" % p)
        est[p] = int(m.group(1).replace(",", ""))
    data = json.load(open(SPANS, encoding="utf-8")) if os.path.exists(SPANS) else {}
    data.update({
        "source_commit": git("rev-parse", commit).strip(),
        "inventory_commit": git("rev-parse", inv["inventory_commit"]).strip(),
        "estimate_bytes": est,
        "withholding": [{"id": w["id"], "profiles": w["profiles"], "spans": w["spans"]} for w in inv["withholding"]],
        "held_for_policy": inv["held_for_policy"],
        "parent_references": inv["parent_references"],
        "contradictions": [{"id": c["id"], "class": c["class"]} for c in inv["contradictions"]],
        "deadprose": entries,
    })
    with open(SPANS, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    print("wrote " + SPANS)


# ---------------------------------------------------------------- count

def manifest_rows(commit):
    rows, header = [], False
    for ln in show(commit, MANIFEST).split("\n"):
        if not ln or ln.startswith("#"):
            continue
        if not header:
            header = True
            continue
        rows.append(ln)
    return rows


def run_count(commit, rows):
    with tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False) as f:
        f.write("profile\tpath\tselector\tweight\tnote\n")
        f.write("\n".join(rows) + "\n")
        name = f.name
    try:
        out = subprocess.run([COUNT, "count", commit, "--manifest", name], capture_output=True)
        if out.returncode != 0:
            raise SystemExit("count failed at %s: %s" % (commit, out.stderr.decode().strip()))
    finally:
        os.unlink(name)
    res = {}
    for ln in out.stdout.decode().strip().split("\n"):
        p, raw, w = ln.split("\t")
        res[p] = (int(raw), int(w))
    return res


def span_text(commit, path, selector):
    t = show(commit, path)
    if selector == "file":
        return t
    lines = t.split("\n")
    if lines and lines[0] == "---":
        try:
            lines = lines[lines.index("---", 1) + 1:]
        except ValueError:
            lines = []
    if selector == "body":
        return "\n".join(lines)
    want = "## " + selector.split(":", 1)[1]
    out, on = [], False
    for ln in lines:
        if ln == want:
            on = True
        elif on and ln.startswith("## "):
            break
        if on:
            out.append(ln)
    return "\n".join(out)


# ---------------------------------------------------------------- reverse blame

def removers(start, end, path):
    """Map each line of path at start to the first-parent commit that removed it (None if kept)."""
    chain = git("rev-list", "--first-parent", "--reverse", "%s..%s" % (start, end)).split()
    nxt = {start: chain[0]}
    for a, b in zip(chain, chain[1:]):
        nxt[a] = b
    out = git("blame", "--reverse", "--first-parent", "--porcelain", "%s..%s" % (start, end), "--", path)
    res = {}
    for ln in out.split("\n"):
        m = re.match(r"^([0-9a-f]{40}) (\d+) (\d+)", ln)
        if m:
            last = m.group(1)
            if last == end:
                res[int(m.group(3))] = None
            elif last in nxt:
                res[int(m.group(3))] = nxt[last]
            else:
                raise SystemExit("%s line %s last seen at %s, off the first-parent chain" % (path, m.group(3), last))
    return res


# ---------------------------------------------------------------- main

def main():
    D = json.load(open(SPANS, encoding="utf-8"))
    INV, PIN, AFTER = D["inventory_commit"], D["pin_commit"], D["measured_commit"]
    settle = {git("rev-parse", p["commit"]).strip(): p["pr"] for p in D["settlement_prs"]}
    problems = []

    # Contradiction count, stated once in the README.
    C = D["contradictions"]
    n_mech = sum(1 for c in C if c["class"] == "mechanical")
    ids = [c["id"] for c in C]
    pos = {i: ids.index(i) + 1 for i in ("prd-complexity-routing", "prd-upstream-roadmap")}

    # 1. Every span found by its excerpt, once, at the inventory commit. An
    #    excerpt stored as a hash (see extract) is found by hashing every
    #    substring of its length.
    for it in D["deadprose"]:
        for sp in it["spans"]:
            path, a, b = parse(sp["loc"])
            t = show(INV, path)
            if "excerpt_sha256" in sp:
                above, size = sp["excerpt_above"], sp["excerpt_length"]
                hits = [i for i in range(len(t) - size + 1)
                        if hashlib.sha256(t[i:i + size].encode("utf-8")).hexdigest() == sp["excerpt_sha256"]]
                ex = "sha256:" + sp["excerpt_sha256"]
            else:
                ex = sp["excerpt"]
                above = ex.startswith("above: ")
                if above:
                    ex = ex[len("above: "):]
                hits = [m.start() for m in re.finditer(re.escape(ex), t)]
            if len(hits) != 1:
                problems.append("%s: excerpt found %d times in %s: %s" % (it["id"], len(hits), path, ex))
                continue
            line = t[:hits[0]].count("\n") + 1
            if (above and not line < a) or (not above and not a <= line <= b):
                problems.append("%s: excerpt at line %d, outside %s" % (it["id"], line, sp["loc"]))

    # 2. The DESIGN's estimate, recomputed (overlaps once per profile, a
    #    pointer-loaded file in full) and checked against the copied figure.
    whole_by = {p: {} for p in PROFILES}
    lines_by = {p: {} for p in PROFILES}
    for it in D["deadprose"]:
        for sp in it["spans"]:
            path, a, b = parse(sp["loc"])
            for p in it["profiles"]:
                if sp.get("whole"):
                    whole_by[p][sp["whole"]] = it["id"]
                else:
                    lines_by[p].setdefault(path, set()).update(range(a, b + 1))
    est = {}
    for p in PROFILES:
        b = sum(len(show(INV, f).encode("utf-8")) for f in whole_by[p])
        for path, lns in lines_by[p].items():
            if path in whole_by[p]:
                continue
            lb = line_bytes(show(INV, path))
            b += sum(lb[i - 1] for i in lns)
        est[p] = b
        if b != D["estimate_bytes"][p]:
            problems.append("estimate for %s recomputes to %d bytes, the DESIGN says %d" % (p, b, D["estimate_bytes"][p]))
    wh = {}
    for w in D["withholding"]:
        for loc in w["spans"]:
            path, a, b = parse(loc)
            wh.setdefault(path, set()).update(range(a, b + 1))
    for p in PROFILES:
        for path, lns in lines_by[p].items():
            if lns & wh.get(path, set()):
                problems.append("estimate overlaps a withholding candidate in " + path)

    # 3. Which commit removed each line the estimate counts.
    paths = sorted({parse(sp["loc"])[0] for it in D["deadprose"] for sp in it["spans"]}
                   | {parse(l)[0] for w in D["withholding"] for l in w["spans"]}
                   | {parse(l)[0] for l in D["held_for_policy"]})
    rem = {path: removers(INV, AFTER, path) for path in paths}

    def split(path, lns):
        lb = line_bytes(show(INV, path))
        s = o = k = 0
        for i in lns:
            r = rem[path][i]
            if r is None:
                k += lb[i - 1]
            elif r in settle:
                s += lb[i - 1]
            else:
                o += lb[i - 1]
        return s, o, k

    # 4. Dropped rows: each must be in the manifest, and a pointer-removed row's
    #    file must be named by no span the profile still loads. A name counts
    #    only as a whole file name (phase-2.5-worktree-discipline.md does not
    #    name worktree-discipline.md); the row's fourth column, when present, is
    #    a literal mention that is not a pointer, removed before the search.
    rows = manifest_rows(AFTER)
    dropped = []
    for ln in open(DROPPED, encoding="utf-8"):
        if ln.startswith("#") or not ln.strip() or ln.startswith("profile\t"):
            continue
        f = ln.rstrip("\n").split("\t")
        dropped.append((f[0], f[1], f[2], f[3] if len(f) > 3 else ""))
    reduced = list(rows)
    for prof, path, reason, _ in dropped:
        match = [r for r in rows if r.split("\t")[0] == prof and r.split("\t")[1] == path]
        if not match:
            problems.append("dropped row not in the manifest: %s %s" % (prof, path))
            continue
        reduced = [r for r in reduced if r not in match]
    for prof, path, reason, not_pointer in dropped:
        base = os.path.basename(path)
        named = re.compile(r"(?<![\w.-])" + re.escape(base))
        if reason == "pointer-removed":
            for r in reduced:
                f = r.split("\t")
                if f[0] != prof:
                    continue
                t = span_text(AFTER, f[1], f[2])
                if not_pointer:
                    t = t.replace(not_pointer, "")
                if named.search(t):
                    problems.append("%s still loads a span naming %s: %s %s" % (prof, base, f[1], f[2]))
        elif reason == "reference-table":
            if "nothing here is read" not in show(AFTER, "skills/scope/SKILL.md"):
                problems.append("the /scope reference table no longer says nothing is read up front")
        else:
            problems.append("unknown reason %s for %s" % (reason, path))
    dropped_by = {p: {d[1] for d in dropped if d[0] == p} for p in PROFILES}

    # 5. Counts: pin and measured commit, both manifests, and per settlement PR.
    pin = run_count(PIN, rows)
    after_a = run_count(AFTER, rows)
    after_b = run_count(AFTER, reduced)
    per_pr = []
    for pr in D["settlement_prs"]:
        c = git("rev-parse", pr["commit"]).strip()
        before = run_count(c + "^", rows)
        at = run_count(c, rows)
        per_pr.append((pr["pr"], pr["group"], c, {p: at[p][0] - before[p][0] for p in PROFILES}))
    attributed = {p: sum(d[p] for _, _, _, d in per_pr) for p in PROFILES}

    # 6. Realized removal against the estimate, per profile and per entry.
    real = {}
    for p in PROFILES:
        s = o = k = 0
        for path, lns in lines_by[p].items():
            if path in whole_by[p]:
                continue
            a_, b_, c_ = split(path, lns)
            s, o, k = s + a_, o + b_, k + c_
        unloaded = sum(len(show(INV, f).encode("utf-8")) for f in whole_by[p] if f in dropped_by[p])
        still = sum(len(show(INV, f).encode("utf-8")) for f in whole_by[p] if f not in dropped_by[p])
        real[p] = (s, unloaded, o, k + still)

    def entry_row(it):
        s = o = k = unl = 0
        seen = {}
        for sp in it["spans"]:
            path, a, b = parse(sp["loc"])
            if sp.get("whole"):
                size = len(show(INV, sp["whole"]).encode("utf-8"))
                if all(sp["whole"] in dropped_by[p] for p in it["profiles"]):
                    unl += size
                else:
                    k += size
            else:
                seen.setdefault(path, set()).update(range(a, b + 1))
        for path, lns in seen.items():
            a_, b_, c_ = split(path, lns)
            s, o, k = s + a_, o + b_, k + c_
        total = s + o + k + unl
        return total, s, unl, o, k

    # ---- render
    out = []
    w = out.append
    w("Commits: pin `%s`, inventory `%s`, measured `%s`; inventory data copied from `%s`." % (PIN[:7], INV[:7], AFTER[:7], D["source_commit"][:7]))
    w("")
    w("Contradictions in the inventory: %d (%d mechanical, %d policy). `prd-complexity-routing` is item %d and `prd-upstream-roadmap` item %d in file order." % (
        len(C), n_mech, len(C) - n_mech, pos["prd-complexity-routing"], pos["prd-upstream-roadmap"]))
    w("")
    w("#### Raw tokens, before and after")
    w("")
    w("| Profile | Pin | Main, manifest as is | Main, dropped rows removed | Change, as is | Change, rows removed |")
    w("|---|---:|---:|---:|---:|---:|")
    for p in PROFILES:
        w("| `%s` | %s | %s | %s | %s | %s |" % (p, fmt(pin[p][0]), fmt(after_a[p][0]), fmt(after_b[p][0]),
                                              fmt(after_a[p][0] - pin[p][0]), fmt(after_b[p][0] - pin[p][0])))
    w("")
    w("#### Change the settlement pull requests made (raw tokens, manifest as is)")
    w("")
    w("| PR | Group | Commit | " + " | ".join("`%s`" % p for p in PROFILES) + " |")
    w("|---|---|---|" + "---:|" * len(PROFILES))
    for pr, grp, c, d in per_pr:
        w("| #%d | %s | `%s` | %s |" % (pr, grp, c[:7], " | ".join(fmt(d[p]) for p in PROFILES)))
    w("| | **Sum** | | %s |" % " | ".join("**%s**" % fmt(attributed[p]) for p in PROFILES))
    w("| | Every other commit, pin to main | | %s |" % " | ".join(fmt(after_a[p][0] - pin[p][0] - attributed[p]) for p in PROFILES))
    w("")
    w("#### Against the DESIGN's dead-prose estimate (tokens are bytes divided by 4, rounded down)")
    w("")
    w("| Profile | Estimate | Removed by the settlement PRs | Files no longer loaded | Removed by other commits | Still present | Realized, as is | Realized, rows removed | Settlement PRs' net change, as is | Net change, rows removed |")
    w("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for p in PROFILES:
        s, unl, o, k = real[p]
        e = est[p]
        ra = 100.0 * s / e if e else 0.0
        rb = 100.0 * (s + unl) / e if e else 0.0
        dropped_tokens = after_a[p][0] - after_b[p][0]
        w("| `%s` | %s | %s | %s | %s | %s | %.1f%% | %.1f%% | %s | %s |" % (
            p, fmt(e // 4), fmt(s // 4), fmt(unl // 4), fmt(o // 4), fmt(k // 4), ra, rb,
            fmt(attributed[p]), fmt(attributed[p] - dropped_tokens)))
    w("")
    w("#### Per entry (bytes)")
    w("")
    w("| Entry | Profiles | Estimate | Removed by the settlement PRs | Files no longer loaded | Removed by other commits | Still present | Realized | Over 10% short |")
    w("|---|---|---:|---:|---:|---:|---:|---:|---|")
    for it in D["deadprose"]:
        total, s, unl, o, k = entry_row(it)
        r = 100.0 * (s + unl) / total if total else 0.0
        w("| `%s` | %s | %s | %s | %s | %s | %s | %.1f%% | %s |" % (
            it["id"], ", ".join("`%s`" % p for p in it["profiles"]), fmt(total), fmt(s), fmt(unl), fmt(o), fmt(k), r,
            "yes" if r < 90.0 else "no"))
    w("")
    w("#### Spans outside the estimate (bytes)")
    w("")
    w("| Set | Size | Removed by the settlement PRs | Removed by other commits | Still present |")
    w("|---|---:|---:|---:|---:|")
    for name, locs in [("Withholding candidates", [l for x in D["withholding"] for l in x["spans"]]),
                       ("Held for policy items", D["held_for_policy"])]:
        s = o = k = 0
        per = {}
        for l in locs:
            path, a, b = parse(l)
            per.setdefault(path, set()).update(range(a, b + 1))
        for path, lns in per.items():
            a_, b_, c_ = split(path, lns)
            s, o, k = s + a_, o + b_, k + c_
        w("| %s | %s | %s | %s | %s |" % (name, fmt(s + o + k), fmt(s), fmt(o), fmt(k)))
    w("")
    w("#### Manifest rows removed, and the DESIGN's parent-reference files (bytes)")
    w("")
    w("| Profile | File | Reason | At the pin | At main |")
    w("|---|---|---|---:|---:|")

    def size(commit, path):
        try:
            return fmt(len(show(commit, path).encode("utf-8")))
        except SystemExit:
            return "gone"
    listed = set()
    for prof, path, reason, _ in dropped:
        listed.add((prof, path))
        w("| `%s` | `%s` | %s | %s | %s |" % (prof, path, reason, size(PIN, path), size(AFTER, path)))
    for path in D["parent_references"]:
        if ("scope", path) not in listed:
            w("| `scope` | `%s` | kept: a directive still names it | %s | %s |" % (path, size(PIN, path), size(AFTER, path)))
    block = "\n".join(out)

    if problems:
        for p in problems:
            print("FAIL: " + p)
        sys.exit(1)
    if "--write" in sys.argv or "--check" in sys.argv:
        doc = open(README, encoding="utf-8").read()
        i, j = doc.find(BEGIN), doc.find(END)
        if i < 0 or j < i:
            raise SystemExit("README.md has no %s ... %s block" % (BEGIN, END))
        new = doc[:i + len(BEGIN)] + "\n" + block + "\n" + doc[j:]
        if "--write" in sys.argv:
            open(README, "w", encoding="utf-8").write(new)
            print("wrote " + README)
        elif new != doc:
            print("FAIL: README.md's figures differ from this run; re-run with --write and review the diff")
            sys.exit(1)
        else:
            print("OK: every check passed and README.md's figures match")
    else:
        print(block)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "extract":
        extract(sys.argv[2])
    else:
        main()
