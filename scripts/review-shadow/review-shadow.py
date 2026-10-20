#!/usr/bin/env python3
"""Closed criteria for pull requests: the script criteria and the Jev slicers.

The six script criteria (rs-001 to rs-006) run locally over a branch with
`scan`, which writes nothing. The slicers cut the bounded slices that the Jev
criteria's contracts in references/rule-registry.json name this script for;
references/jev-criteria.md describes those contracts and pass trust, and
scripts/jev-criteria/jev_criteria.py measures slices with these functions.
The review-shadow trial's local store, its grader and the decider shadow at
review sites are retired; docs/guides/review-shadow.md says what is left.

Subcommands:
  scan     run the script criteria over a local branch; writes nothing
  check    load the criteria and category files and report problems

Requires: Python 3.8 or later, standard library only.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
CRITERIA_FILE = HERE / "criteria.json"
CATEGORIES_FILE = HERE / "categories.json"

VALUE_KEYS = ("pass", "fail")
OBSERVERS = ("script", "jev")
ARTIFACT_KINDS = ("pull-request", "brief", "prd", "plan", "local-change")
# Which slicers can feed a criterion of each artifact kind. A site criterion
# names the artifact it judges, so a pull-request criterion can never be asked
# of a brief, or a brief criterion of a pull request.
SLICE_KINDS_BY_ARTIFACT = {
    "pull-request": ("pr-text", "pr-summary", "code-hunks", "doc-pairs"),
    "brief": ("brief-journey", "summary-pair"),
    "prd": ("prd-ac",),
    "plan": ("plan-ac-block",),
    # ac-claims, plan-hunks and design-hunks name the slices the scrutiny
    # seats' questions would need (rs-018 to rs-020). No slicer builds them:
    # their contracts are rejected and the rows ship with `enabled: false`
    # (references/jev-criteria.md).
    "local-change": ("ac-hunks", "code-hunks", "ac-claims", "plan-hunks", "design-hunks"),
}
SLICE_KINDS = tuple(dict.fromkeys(k for kinds in SLICE_KINDS_BY_ARTIFACT.values() for k in kinds))
CLASSES = ("covered", "closed-uncovered", "open-judgment")
RULE_ID = re.compile(r"rs-[0-9]{3}")
CRITERION_FIELDS = ("rule_id", "rule_ref", "group", "artifact_kind", "slice_kind", "observer",
                    "question", "values", "escape", "threshold")


class ConfigError(Exception):
    """A criteria or category file that the tool refuses to run with."""


def _read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        raise ConfigError(f"{path}: not found")
    except ValueError as e:
        raise ConfigError(f"{path}: not valid JSON ({e})")


def load_criteria(path=CRITERIA_FILE, repo_root=REPO_ROOT):
    """Load and check the criteria file; raise ConfigError on anything malformed.

    A criterion must be a two-value choice with one escape value. A boolean
    declaration is refused outright, because the accuracy spike found the
    boolean form compresses Jev's probabilities too far to decide on.
    """
    data = _read_json(path)
    if not isinstance(data, dict) or not isinstance(data.get("criteria"), list) or "version" not in data:
        raise ConfigError(f"{path}: needs a version and a criteria list")
    seen = set()
    for n, c in enumerate(data["criteria"], 1):
        where = f"{path}: criterion {n}"
        if not isinstance(c, dict):
            raise ConfigError(f"{where}: not an object")
        if c.get("type") == "boolean" or isinstance(c.get("values"), bool):
            raise ConfigError(f"{where}: boolean criteria are not allowed; declare a two-value choice")
        for field in CRITERION_FIELDS:
            if field not in c:
                raise ConfigError(f"{where}: missing {field!r}")
        rid = c["rule_id"]
        if not isinstance(rid, str) or not RULE_ID.fullmatch(rid):
            raise ConfigError(f"{where}: rule_id must look like rs-NNN")
        if rid in seen:
            raise ConfigError(f"{where}: duplicate rule_id {rid}")
        seen.add(rid)
        values, escape = c["values"], c["escape"]
        if not isinstance(values, dict) or tuple(sorted(values)) != tuple(sorted(VALUE_KEYS)):
            raise ConfigError(f"{where}: values must be exactly pass and fail")
        if not isinstance(escape, dict) or len(escape) != 1 or set(escape) & set(VALUE_KEYS):
            raise ConfigError(f"{where}: escape must be exactly one value other than pass and fail")
        if not all(isinstance(v, str) and v for v in list(values.values()) + list(escape.values())):
            raise ConfigError(f"{where}: every value needs a description")
        if c["artifact_kind"] not in ARTIFACT_KINDS:
            raise ConfigError(f"{where}: unknown artifact_kind {c['artifact_kind']!r}")
        if c["slice_kind"] not in SLICE_KINDS:
            raise ConfigError(f"{where}: unknown slice_kind {c['slice_kind']!r}")
        if c["slice_kind"] not in SLICE_KINDS_BY_ARTIFACT[c["artifact_kind"]]:
            raise ConfigError(f"{where}: slice_kind {c['slice_kind']!r} doesn't read a {c['artifact_kind']} artifact")
        if c["observer"] not in OBSERVERS:
            raise ConfigError(f"{where}: observer must be script or jev")
        if c["observer"] == "script":
            if c.get("check") not in CHECKS:  # the dispatch table is the one list of checks
                raise ConfigError(f"{where}: unknown check {c.get('check')!r}")
            if c["slice_kind"] != "pr-text":
                raise ConfigError(f"{where}: script criteria read the pr-text slice")
        elif c["slice_kind"] == "pr-text":
            raise ConfigError(f"{where}: Jev criteria can't read the unbounded pr-text slice")
        if "enabled" in c and not isinstance(c["enabled"], bool):
            raise ConfigError(f"{where}: enabled must be true or false")
        if c.get("applies_to") not in (None, "public"):
            raise ConfigError(f"{where}: applies_to may only be public")
        t = c["threshold"]
        if isinstance(t, bool) or not isinstance(t, (int, float)) or not 0.5 <= t <= 1.0:
            raise ConfigError(f"{where}: threshold must be between 0.5 and 1.0")
        ref = c["rule_ref"]
        if not isinstance(ref, str) or ref.startswith("/") or ".." in ref.split("/") \
                or not (Path(repo_root) / ref).is_file():
            raise ConfigError(f"{where}: rule_ref {ref!r} doesn't name a file in the repository")
    if not seen:
        raise ConfigError(f"{path}: no criteria")
    return data


def active(criteria, artifact_kind="pull-request"):
    """Every criterion of one artifact kind that isn't shipped off."""
    return [c for c in criteria["criteria"] if c["artifact_kind"] == artifact_kind and c.get("enabled", True)]


def load_categories(criteria, path=CATEGORIES_FILE):
    """Load the finding-category map and check it against the criteria."""
    data = _read_json(path)
    cats = data.get("categories") if isinstance(data, dict) else None
    if not isinstance(cats, dict) or not cats:
        raise ConfigError(f"{path}: needs a categories object")
    ids = {c["rule_id"] for c in criteria["criteria"]}
    for name, entry in cats.items():
        if not re.match(r"^[a-z0-9-]{1,40}$", name):
            raise ConfigError(f"{path}: bad category name {name!r}")
        if not isinstance(entry, dict) or entry.get("class") not in CLASSES:
            raise ConfigError(f"{path}: category {name!r} needs a class from {CLASSES}")
        rule_ids = entry.get("rule_ids", [])
        if entry["class"] == "covered" and not rule_ids:
            raise ConfigError(f"{path}: covered category {name!r} names no rule id")
        if entry["class"] != "covered" and rule_ids:
            raise ConfigError(f"{path}: only a covered category names rule ids ({name!r})")
        unknown = [r for r in rule_ids if r not in ids]
        if unknown:
            raise ConfigError(f"{path}: category {name!r} names unknown rule ids {unknown}")
    for c in criteria["criteria"]:
        if c["group"] not in cats:
            raise ConfigError(f"{path}: criterion {c['rule_id']} has group {c['group']!r}, which isn't a category")
    return data


class FetchError(Exception):
    """A git command `scan` runs failed."""


# --- Slices ------------------------------------------------------------------

DOC_SUFFIXES = (".md",)
NON_CODE_SUFFIXES = (".md", ".json", ".yaml", ".yml", ".lock")
BOUND = 2560  # bytes: the budget koto's decider check uses, within what the spike measured
MAX_DOC_PAIRS = 8
COMMENT_START = re.compile(r"^\s*(#|//|/\*|\*|--)")
TERM = re.compile(r"`[^`\n]{2,80}`|\b\d+(?:[.,]\d+)+\b|\b\d{2,}\b")


def utf8_len(text):
    return len(text.encode("utf-8"))


def part1(body):
    """The body up to its first `---` line: the part that becomes the squash message."""
    lines = body.replace("\r\n", "\n").split("\n")
    for i, line in enumerate(lines):
        if line.strip() == "---":
            return "\n".join(lines[:i]).strip()
    return body.strip()


CREDENTIAL = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|"
    r"AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,})\b|-----BEGIN [A-Z ]*PRIVATE KEY-----")


def redact(text):
    """Replace strings shaped like common credentials before any text leaves the machine."""
    return CREDENTIAL.sub("[redacted]", text)


def make_slice(kind, n, inputs, meta=None):
    inputs = {k: redact(v) for k, v in inputs.items()}
    blob = json.dumps(inputs, sort_keys=True, ensure_ascii=False)
    size = sum(utf8_len(v) for v in inputs.values())
    return {"id": f"{kind}-{n}", "kind": kind, "inputs": inputs, "bytes": size,
            "sha256": hashlib.sha256(blob.encode("utf-8")).hexdigest(),
            "over_bound": size > BOUND, "meta": meta or {}}


STATUS_LETTER = {"added": "A", "removed": "D", "modified": "M", "renamed": "R", "copied": "C", "changed": "M"}


def diffstat(files, depth=None):
    """One line per file, or with `depth`, one line per directory at that depth."""
    if depth is None:
        return "\n".join(f"{STATUS_LETTER.get(f['status'], 'M')} {f['path']} +{f['additions']} -{f['deletions']}"
                         for f in files)
    groups = {}
    for f in files:
        parts = f["path"].split("/")
        key = "/".join(parts[:min(depth, len(parts) - 1)]) or "."
        g = groups.setdefault(key, [0, 0, 0])
        g[0] += 1
        g[1] += f["additions"]
        g[2] += f["deletions"]
    return "\n".join(f"{k}/ {n} files +{a} -{d}" for k, (n, a, d) in sorted(groups.items()))


BODY_CUT_MARKER = "\n\n[Part 1 cut here to fit the size bound; the rest is not shown]"
MIN_BODY_KEPT = 512  # bytes: a shorter cut says too little to judge against the file list


def cut_body(body, room):
    """The longest head of `body` that fits `room` bytes with the cut marker
    appended, ending at a paragraph break, else a sentence end, else a word."""
    keep = room - utf8_len(BODY_CUT_MARKER)
    head = body.encode("utf-8")[:max(keep, 0)].decode("utf-8", "ignore")
    for pattern in (r"\n\s*\n", r"[.!?](?=\s)", r"\s"):
        ends = [m.start() + (1 if pattern.startswith("[") else 0) for m in re.finditer(pattern, head)]
        if ends and ends[-1] > 0:
            head = head[:ends[-1]]
            break
    return head.rstrip() + BODY_CUT_MARKER


def slice_pr_summary(pr):
    """Part 1 with the file list. The list is summarized by directory before it
    is ever cut: an "omits a change" question over part of the list is wrong.
    When no summary level fits the whole body, the body is cut instead, at the
    most detailed level that leaves MIN_BODY_KEPT bytes of it, and the slice
    says so. If even that can't fit, the slice stays over the bound."""
    # Redact before cutting: a cut can split a credential so it no longer matches.
    body = redact(part1(pr["body"]))
    levels = (("files", None), ("dir3", 3), ("dir2", 2), ("dir1", 1))
    for level, depth in levels:
        s = make_slice("pr-summary", 1, {"pr_body_part1": body, "diff_summary": diffstat(pr["files"], depth)},
                       {"summary_level": level})
        if not s["over_bound"]:
            return [s]
    for level, depth in levels:
        summary = diffstat(pr["files"], depth)
        room = BOUND - utf8_len(summary)
        if room >= MIN_BODY_KEPT + utf8_len(BODY_CUT_MARKER):
            cut = cut_body(body, room)
            s = make_slice("pr-summary", 1, {"pr_body_part1": cut, "diff_summary": summary},
                           {"summary_level": level, "body_cut": True})
            if not s["over_bound"]:
                return [s]
    return [make_slice("pr-summary", 1, {"pr_body_part1": body, "diff_summary": diffstat(pr["files"], 1)},
                       {"summary_level": "dir1"})]


def split_hunks(patch):
    hunks, cur = [], []
    for line in (patch or "").split("\n"):
        if line.startswith("@@") and cur:
            hunks.append("\n".join(cur))
            cur = []
        cur.append(line)
    if cur and any(cur):
        hunks.append("\n".join(cur))
    return hunks


def hunk_has_comment(hunk):
    return any(COMMENT_START.match(line[1:]) for line in hunk.split("\n") if line[:1] in "+- ")


def comment_windows(header, block, path_len):
    """An over-bound block as windows that each start at a comment line and run
    on through the code after it, up to the bound. Code before the first comment
    has no comment to check and is left out; a single line over the bound stays
    one over-bound unit."""
    starts = [i for i, line in enumerate(block) if line[:1] in "+- " and COMMENT_START.match(line[1:])]
    windows = []
    for i in starts:
        if windows and i < windows[-1][1]:
            continue  # this comment is already inside the previous window
        j = i + 1
        while j < len(block) and path_len + utf8_len("\n".join([header] + block[i:j + 1])) <= BOUND:
            j += 1
        windows.append((i, j))
    return ["\n".join([header] + block[a:b]) for a, b in windows]


def hunk_units(hunk, path_len):
    """A hunk as whole units within the bound. A hunk over the bound, such as a
    whole new file, is split at blank lines into blocks, each headed by the
    hunk's @@ line so the reader keeps its position; a block still over the
    bound is cut into comment-anchored windows."""
    if path_len + utf8_len(hunk) <= BOUND:
        return [hunk]
    lines = hunk.split("\n")
    header, body = lines[0], lines[1:]
    blocks, cur = [], []
    for line in body:
        cur.append(line)
        if not line[1:].strip() and len(cur) > 1:
            blocks.append(cur)
            cur = []
    if cur:
        blocks.append(cur)
    units, pack = [], []
    for block in blocks:
        if path_len + utf8_len("\n".join([header] + block)) > BOUND:
            if pack:
                units.append("\n".join([header] + pack))
                pack = []
            units += comment_windows(header, block, path_len)
            continue
        if pack and path_len + utf8_len("\n".join([header] + pack + block)) > BOUND:
            units.append("\n".join([header] + pack))
            pack = []
        pack += block
    if pack:
        units.append("\n".join([header] + pack))
    return units


def slice_code_hunks(pr):
    """Hunks that add, remove or border a comment, packed whole per file up to the bound."""
    slices, n = [], 0
    for f in pr["files"]:
        if f["status"] == "removed" or f["path"].endswith(NON_CODE_SUFFIXES) or not f["patch"]:
            continue
        plen = utf8_len(f["path"])
        pack = []
        units = [u for h in split_hunks(f["patch"]) for u in hunk_units(h, plen)]
        for h in (u for u in units if hunk_has_comment(u)):
            candidate = "\n".join(pack + [h])
            if pack and utf8_len(f["path"]) + utf8_len(candidate) > BOUND:
                n += 1
                slices.append(make_slice("code-hunks", n, {"path": f["path"], "hunks": "\n".join(pack)}))
                pack = [h]
            else:
                pack.append(h)
        if pack:
            n += 1
            slices.append(make_slice("code-hunks", n, {"path": f["path"], "hunks": "\n".join(pack)}))
    return slices


def added_lines(patch):
    """(new-file line number, text) for every added line of a unified diff."""
    out, new = [], 0
    for line in (patch or "").split("\n"):
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
        if m:
            new = int(m.group(1))
            continue
        if line.startswith("+"):
            out.append((new, line[1:]))
            new += 1
        elif line.startswith(" "):
            new += 1
    return out


LINE_UNIT = re.compile(r"^\s*(\||[-*+] |\d+\. )")


def paragraphs(text):
    """(first line number, text) for each passage: a blank-line-separated prose
    block, or a single table row or list item, which is where a count or a status
    usually sits. Fenced code is skipped."""
    out, cur, start, fenced = [], [], 1, False

    def flush():
        if cur:
            out.append((start, "\n".join(cur)))
            cur.clear()

    for i, line in enumerate(text.split("\n"), 1):
        if line.lstrip().startswith("```"):
            flush()
            fenced = not fenced
            continue
        if fenced:
            continue
        if not line.strip():
            flush()
        elif LINE_UNIT.match(line):
            flush()
            out.append((i, line))
        else:
            if not cur:
                start = i
            cur.append(line)
    flush()
    return out


def slice_doc_pairs(pr):
    """Pairs an added paragraph with each paragraph in the same file that shares a
    number or a backticked term, strongest first, capped at MAX_DOC_PAIRS."""
    candidates = []
    for f in pr["files"]:
        text = pr["texts"].get(f["path"])
        if not text or not f["patch"]:
            continue
        added = {ln for ln, _ in added_lines(f["patch"])}
        paras = paragraphs(text)
        terms = [set(TERM.findall(p)) for _, p in paras]
        for i, (start, p) in enumerate(paras):
            end = start + p.count("\n")
            if not terms[i] or not any(start <= ln <= end for ln in added):
                continue
            for j, (_, q) in enumerate(paras):
                if j == i:
                    continue
                shared = terms[i] & terms[j]
                if shared:
                    candidates.append((len(shared), f["path"], min(i, j), max(i, j), paras))
    seen, pairs = set(), []
    for score, path, i, j, paras in sorted(candidates, key=lambda c: -c[0]):
        if (path, i, j) in seen:
            continue
        seen.add((path, i, j))
        pairs.append({"path": path, "location_a": paras[i][1], "location_b": paras[j][1]})
    # A kept pair over the bound becomes an over-bound slice: never sent or cut,
    # and graded unanswered, so the criterion can't pass without looking at it.
    kept, dropped = pairs[:MAX_DOC_PAIRS], max(0, len(pairs) - MAX_DOC_PAIRS)
    slices = [make_slice("doc-pairs", n, inputs) for n, inputs in enumerate(kept, 1)]
    meta = {"pairs_dropped": dropped, "pairs_over_bound": sum(s["over_bound"] for s in slices)}
    for sl in slices:
        sl["meta"] = dict(meta)
    return slices, meta


def slice_pr_text(pr):
    """Everything the script criteria read. Scripts run locally, so this has no bound."""
    added = []
    for f in pr["files"]:
        for ln, text in added_lines(f["patch"]):
            added.append((f["path"], ln, text))
    return {"body": pr["body"], "part1": part1(pr["body"]), "added": added,
            "texts": pr["texts"], "tree": pr["tree"], "public": pr["public"],
            "paths": [f["path"] for f in pr["files"]]}


def build_slices(pr):
    """Slices per slice kind, plus the doc-pair counts: dropped by the cap, and
    candidate pairs left out because the two passages together exceed the bound."""
    doc, pair_meta = slice_doc_pairs(pr)
    return {"pr-summary": slice_pr_summary(pr), "code-hunks": slice_code_hunks(pr),
            "doc-pairs": doc}, pair_meta


# --- Local files that must stay out of every repository ----------------------

def inside_work_tree(path):
    """True when `path`, or the nearest existing directory above it, is inside a
    git work tree. Any answer other than a clean "no" counts as inside, so a git
    failure refuses rather than lets a term list land in a repository."""
    p = Path(os.path.realpath(path))
    while not p.exists():
        if p.parent == p:
            return True
        p = p.parent
    if p.is_file():
        p = p.parent
    try:
        out = subprocess.run(["git", "-C", str(p), "rev-parse", "--is-inside-work-tree"],
                             capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return True
    if out.returncode == 0:
        return out.stdout.strip() != "false"
    return "not a git repository" not in out.stderr


def load_private_terms(path):
    """The local private-term list: one term per line, # for comments. None when no
    list was given. The list is never committed, sent or recorded."""
    if not path:
        return None
    if inside_work_tree(path):
        raise ConfigError("the private-term list must live outside every git work tree")
    try:
        with open(path, encoding="utf-8") as f:
            terms = [ln.strip() for ln in f if ln.strip() and not ln.lstrip().startswith("#")]
    except OSError:
        raise ConfigError("the private-term list could not be read")
    return terms


# --- Script criteria ---------------------------------------------------------
#
# Each check reads the pr-text slice and returns (verdict, findings, reason).
# A finding is (path, line): where, never what. The private-name check in
# particular must not print the term it matched.
#
# Some patterns below are written so that the source doesn't contain the
# literal text they look for (`(?:ed)`, `\/`): otherwise this file would fail
# its own checks, and every pre-merge grep that looks for the same text.

ATTRIBUTION = re.compile(
    r"co-author(?:ed)-by\s*:|generated\s+with\s+\[?claude|claude-sess(?:ion)\b|"
    r"https?://(?:www\.)?claude\.a(?:i)\b", re.I)
SCRATCH_PATH = re.compile(r"(?<![A-Za-z0-9_.-])wip\/[A-Za-z0-9_.]")
HOME_PATH = re.compile(r"/(?:home|Users)/([A-Za-z_][A-Za-z0-9._-]*)/")
PATH_TOKEN = re.compile(r"`(?:\./)?([A-Za-z0-9_.][A-Za-z0-9_./-]*/[A-Za-z0-9_./-]*?)(?::\d+(?:-\d+)?)?`")
PATH_SUFFIXES = (".md", ".sh", ".py", ".rs", ".json", ".jsonl", ".yml", ".yaml", ".toml", ".txt", "/")
UNFINISHED_FILE = HERE / "unfinished-wording.txt"


def _lines(pt):
    """(path, line, text) for the body and every added line."""
    for i, text in enumerate(pt["body"].split("\n"), 1):
        yield ("(body)", i, text)
    yield from pt["added"]


def check_attribution(pt, _terms):
    hits = [(p, ln) for p, ln, t in _lines(pt) if ATTRIBUTION.search(t)]
    return ("fail" if hits else "pass"), hits, None


def term_forms(term):
    """Every committed form of a term the private-name check looks for, as two
    sets: forms matched case-insensitively (the plain term, hex, and SHA-1,
    SHA-256 and MD5 digests of the term and its lower case), and base64 at all
    three byte alignments, which is case-sensitive."""
    import base64
    raw = term.encode("utf-8")
    folded = {term.lower(), raw.hex()}
    exact = set()
    for off in range(3):
        enc = base64.b64encode(b"\0" * off + raw).decode().rstrip("=")
        start = (off * 4 + 2) // 3 if off else 0
        end = len(enc) - (1 if (off + len(raw)) % 3 else 0)
        if end - start >= 4:
            exact.add(enc[start:end])
    for t in {term, term.lower()}:
        b = t.encode("utf-8")
        folded |= {hashlib.sha1(b).hexdigest(), hashlib.sha256(b).hexdigest(), hashlib.md5(b).hexdigest()}
    return folded, exact


def check_private_terms(pt, terms):
    if not terms:
        return "unanswered", [], "no-denylist"  # an empty list checks nothing, so it isn't a pass
    folded, exact = set(), set()
    for t in terms:
        f, e = term_forms(t)
        folded |= f
        exact |= e
    # A home-directory path is a leak only when it names a real account: this
    # machine's user, or a name on the list. Example paths in docs and tests
    # (a made-up account under /home or /Users) are not.
    import getpass
    users = {t.lower() for t in terms}
    try:
        users.add(getpass.getuser().lower())
    except (KeyError, OSError):
        pass
    hits = []
    for p, ln, text in _lines(pt):
        low = text.lower()
        home = any(m.group(1).lower() in users for m in HOME_PATH.finditer(text))
        if home or any(f in low for f in folded) or any(e in text for e in exact):
            hits.append((p, ln))
    return ("fail" if hits else "pass"), hits, None


def check_scratch_path(pt, _terms):
    hits = [(p, ln) for p, ln, t in _lines(pt) if not p.startswith("wip" + "/") and SCRATCH_PATH.search(t)]
    return ("fail" if hits else "pass"), hits, None


def _strip_code(text):
    return re.sub(r"`[^`]*`", "", text)


def load_unfinished_phrases(path=UNFINISHED_FILE):
    with open(path, encoding="utf-8") as f:
        return [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]


def check_unfinished_wording(pt, _terms):
    phrases = [re.compile(r"(?<![A-Za-z0-9])" + re.escape(p) + r"(?![A-Za-z0-9])", re.I)
               for p in load_unfinished_phrases()]
    hits = []
    for i, line in enumerate(pt["part1"].split("\n"), 1):
        plain = _strip_code(line)
        if any(rx.search(plain) for rx in phrases):
            hits.append(("(body)", i))
    return ("fail" if hits else "pass"), hits, None


def check_pasted_paragraph(pt, _terms):
    """A prose paragraph over 60 characters that appears twice in one changed
    Markdown file, where at least one copy was added by this change."""
    added_by_path = {}
    for p, ln, _ in pt["added"]:
        added_by_path.setdefault(p, set()).add(ln)
    hits, unreadable = [], False
    for path, text in pt["texts"].items():
        if text is None:
            unreadable = True
            continue
        seen = {}
        for start, para in paragraphs(text):
            key = " ".join(para.split())
            if len(key) <= 60 or LINE_UNIT.match(para):
                continue
            seen.setdefault(key, []).append((start, start + para.count("\n")))
        added = added_by_path.get(path, set())
        for spans in seen.values():
            if len(spans) > 1 and any(a <= ln <= b for a, b in spans for ln in added):
                hits.append((path, spans[-1][0]))
    if hits:
        return "fail", hits, None
    if unreadable:
        return "unanswered", [], "file-unreadable"
    return "pass", [], None


def check_dangling_path(pt, _terms):
    if pt["tree"] is None:
        return "unanswered", [], "tree-unreadable"
    tree = pt["tree"]
    top = {t.split("/", 1)[0] for t in tree}
    tails = {}
    for t in tree:
        parts = t.split("/")
        for i in range(1, len(parts)):
            tails.setdefault("/".join(parts[i:]), True)
    hits = []
    for p, ln, text in pt["added"]:
        if not p.endswith(".md"):
            continue
        for tok in PATH_TOKEN.findall(text):
            if tok.startswith(("http", "wip" + "/")) or ".." in tok.split("/") or not tok.endswith(PATH_SUFFIXES):
                continue
            target = tok.rstrip("/")
            if target.endswith(".local.md"):
                continue  # a per-machine file, untracked by convention
            if target in tree or target in tails or any(f"{a}/{target}" in tree for a in _ancestors(p)):
                continue
            if target.split("/", 1)[0] not in top:
                continue  # names something outside this repository: a workspace, runtime or other-repo path
            hits.append((p, ln))
    return ("fail" if hits else "pass"), hits, None


def _ancestors(path):
    """Every directory above a repository path, nearest first."""
    parts = path.split("/")[:-1]
    return ["/".join(parts[:i]) for i in range(len(parts), 0, -1)]


CHECKS = {"attribution": check_attribution, "private_terms": check_private_terms,
          "scratch_path": check_scratch_path, "unfinished_wording": check_unfinished_wording,
          "pasted_paragraph": check_pasted_paragraph, "dangling_path": check_dangling_path}


def run_scripts(criteria, pt, terms):
    """Every script criterion over the pr-text slice, in file order. Script
    criteria exist only for pull requests (the loader refuses any other)."""
    out = []
    for c in active(criteria, "pull-request"):
        if c["observer"] != "script":
            continue
        if c.get("applies_to") == "public" and not pt["public"]:
            out.append({"rule_id": c["rule_id"], "slice": "pr-text", "verdict": "pass", "observer": "script",
                        "probabilities": None, "reason": "not-applicable", "findings": 0, "where": []})
            continue
        verdict, hits, reason = CHECKS[c["check"]](pt, terms)
        out.append({"rule_id": c["rule_id"], "slice": "pr-text", "verdict": verdict, "observer": "script",
                    "probabilities": None, "reason": reason, "findings": len(hits), "where": hits})
    return out


# --- Site slicers ------------------------------------------------------------
#
# The slicers for a review site's artifact: a brief, a PRD, a plan's issue
# outlines, or a local change beside its acceptance criteria. Each reads an
# artifact dict holding `artifact_kind` and the parts its slicers cut, and
# returns slices in the shape the pull-request slicers return.

def frontmatter(text):
    """Top-level keys of a document's YAML frontmatter that hold a plain scalar or a
    literal block (`key: |` followed by indented lines). Anything else is skipped."""
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}
    out, key, block = {}, None, []
    for line in text[4:end].split("\n"):
        if key is not None:
            if line.startswith((" ", "\t")) or not line.strip():
                block.append(line)
                continue
            out[key] = "\n".join(b.strip() for b in block).strip()
            key, block = None, []
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if not m:
            continue
        if m.group(2) in ("|", "|-", ">", ">-"):
            key, block = m.group(1), []
        else:
            out[m.group(1)] = m.group(2).strip()
    if key is not None:
        out[key] = "\n".join(b.strip() for b in block).strip()
    return out


def sections(text, level="## "):
    """{heading: body} for each heading at `level` outside fenced code."""
    out, cur, body, fenced = {}, None, [], False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if not fenced and line.startswith(level) and not line.startswith(level + "#"):
            if cur is not None:
                out[cur] = "\n".join(body).strip()
            cur, body = line[len(level):].strip(), []
        elif cur is not None:
            body.append(line)
    if cur is not None:
        out[cur] = "\n".join(body).strip()
    return out


def prose_blocks(text):
    """Blank-line-separated blocks: the whole sub-units a section is cut at."""
    return [b.strip() for b in re.split(r"\n\s*\n", text) if b.strip()]


CHECKBOX = re.compile(r"^\s*[-*] \[[ xX]\] ")


def checklist(text):
    """(group label, item) for each checkbox item. An item runs on through its
    indented continuation lines; its group is the nearest heading or plain line
    above it (such as "Input assembly (R4, R9):")."""
    items, group, cur = [], "", None
    for line in text.split("\n"):
        if CHECKBOX.match(line):
            if cur is not None:
                items.append((group, "\n".join(cur)))
            cur = [line.rstrip()]
        elif cur is not None and line.strip() and line.startswith((" ", "\t")):
            cur.append(line.rstrip())
        else:
            if cur is not None:
                items.append((group, "\n".join(cur)))
                cur = None
            if line.strip() and not line.lstrip().startswith(("- ", "* ", "```")):
                group = line.strip().lstrip("#").strip()
    if cur is not None:
        items.append((group, "\n".join(cur)))
    return items


def pack_unit(kind, n, fixed, label, head, parts, joiner="\n\n"):
    """One unit as one slice: `fixed` inputs, plus `label` holding `head` and the
    whole `parts`, in order, that fit the bound. A part that doesn't fit is
    dropped and counted, and the next is still tried, so one large hunk or
    paragraph doesn't cost the unit everything after it. A unit none of whose
    parts fits stays one over-bound slice holding all of it, which is never sent."""
    def body(ps):
        return joiner.join(x for x in [head] + ps if x)
    whole = make_slice(kind, n, dict(fixed, **{label: body(parts)}), {"dropped": 0})
    if not whole["over_bound"]:
        return whole
    kept, dropped = [], 0
    for part in parts:
        if make_slice(kind, n, dict(fixed, **{label: body(kept + [part])}))["over_bound"]:
            dropped += 1
        else:
            kept.append(part)
    if not kept:
        return whole
    return make_slice(kind, n, dict(fixed, **{label: body(kept)}), {"dropped": dropped})


def slice_brief_journeys(art):
    """One slice per ### journey under User Journeys, cut at its paragraphs."""
    journeys = sections(art["sections"].get("User Journeys", ""), "### ")
    out = []
    for n, (title, text) in enumerate(journeys.items(), 1):
        out.append(pack_unit("brief-journey", n, {}, "journey", f"### {title}", prose_blocks(text)))
    return out


def slice_summary_pairs(art):
    """Each frontmatter summary beside the section it summarizes, the section cut at
    its paragraphs. A pair missing either half sends nothing."""
    out = []
    for field, heading in (("problem", "Problem Statement"), ("outcome", "User Outcome")):
        summary, section = art["frontmatter"].get(field, ""), art["sections"].get(heading, "")
        if summary and section:
            out.append(pack_unit("summary-pair", len(out) + 1, {"summary": summary}, "section", "",
                                 prose_blocks(section)))
    return out


def slice_prd_acs(art):
    """One slice per acceptance criterion, with its group label."""
    out = []
    for n, (group, item) in enumerate(checklist(art["sections"].get("Acceptance Criteria", "")), 1):
        fixed = {"group": group} if group else {}
        out.append(pack_unit("prd-ac", n, fixed, "criterion", "", [item]))
    return out


def slice_plan_ac_blocks(art):
    """One slice per issue outline: its title and its criteria, cut at whole items."""
    out = []
    for n, issue in enumerate(art["issues"], 1):
        items = [item for _, item in checklist(issue["criteria"])]
        s = pack_unit("plan-ac-block", n, {"issue": issue["title"]}, "criteria", "", items, "\n")
        s["meta"]["issue_id"] = issue.get("issue_id")  # ties a category C finding to this slice; not recorded
        out.append(s)
    return out


ANCHOR = re.compile(r"`([^`\n]{3,120})`|(?<![\w/.-])(--[a-z][a-z0-9-]{2,})|"
                    r"(?<![\w-])([A-Za-z0-9_.-]*/[A-Za-z0-9_./-]+|[A-Za-z0-9_-]+\.[A-Za-z][A-Za-z0-9]{0,5})\b")


def anchor_terms(text):
    """The literal terms a criterion is matched to hunks by: backticked tokens,
    --flags, and tokens holding a / or a file extension."""
    terms = set()
    for m in ANCHOR.finditer(text):
        t = next(g for g in m.groups() if g)
        t = t.strip().rstrip(".,;:)")
        if len(t) >= 3:
            terms.add(t)
    return terms


def slice_ac_hunks(art):
    """Each acceptance criterion with the hunks that mention one of its anchor
    terms (in the path or a changed line), packed whole up to the bound. A
    criterion with no anchor term or no matching hunk sends nothing and is listed
    as unanswered with reason no-anchor."""
    out, unmatched = [], []
    for n, (_, item) in enumerate(art["criteria"], 1):
        terms = anchor_terms(item)
        units = []
        for f in art["files"]:
            if not f["patch"]:
                continue
            # Room for the criterion and the "--- <path>\n" header beside each hunk
            # unit, so a unit that fits on its own also fits in the slice it is
            # sent in. hunk_units adds its own path length again, and the 8 covers
            # the header's "--- " and newline plus the joiner, with a little to
            # spare: a conservative bound only splits a hunk sooner.
            plen = utf8_len(item) + 2 * utf8_len(f["path"]) + 8
            for h in split_hunks(f["patch"]):
                changed = "\n".join(line[1:] for line in h.split("\n")[1:] if line[:1] in "+-")
                if terms and any(t in f["path"] or t in changed for t in terms):
                    units += [f"--- {f['path']}\n{u}" for u in hunk_units(h, plen)]
        if not units:
            unmatched.append({"unit": f"ac-hunks-{n}", "reason": "no-anchor"})
            continue
        out.append(pack_unit("ac-hunks", n, {"criterion": item}, "hunks", "", units, "\n"))
    return out, unmatched


def build_site_slices(art):
    """Slices per slice kind for one site artifact, plus units that sent nothing."""
    kind = art["artifact_kind"]
    if kind == "brief":
        return {"brief-journey": slice_brief_journeys(art), "summary-pair": slice_summary_pairs(art)}, []
    if kind == "prd":
        return {"prd-ac": slice_prd_acs(art)}, []
    if kind == "plan":
        return {"plan-ac-block": slice_plan_ac_blocks(art)}, []
    ac, unmatched = slice_ac_hunks(art)
    return {"ac-hunks": ac, "code-hunks": slice_code_hunks({"files": art["files"]})}, unmatched


# --- Local branch scan -------------------------------------------------------

def _git(*args):
    out = subprocess.run(["git", "-c", "core.quotepath=off", *args], capture_output=True, text=True,
                         errors="replace")
    if out.returncode != 0:
        raise FetchError(f"git {args[0]} failed")
    return out.stdout


def local_pr(base, body):
    """A pr-text slice for the current branch against `base`, for `scan`."""
    # The file list comes NUL-separated, so no path is ever quoted or escaped;
    # each file's patch is then read on its own, by pathspec.
    fields = _git("diff", "--name-status", "-z", "-M", f"{base}...HEAD").split("\0")
    files, i = [], 0
    status_word = {"A": "added", "D": "removed", "M": "modified", "R": "renamed", "C": "copied", "T": "modified"}
    while i < len(fields) and fields[i]:
        code = fields[i]
        if code[0] in "RC":
            old, path, i = fields[i + 1], fields[i + 2], i + 3
        else:
            old, path, i = None, fields[i + 1], i + 2
        files.append({"path": path, "previous_path": old, "status": status_word.get(code[0], "modified"),
                      "additions": 0, "deletions": 0, "patch": None})
    for f in files:
        if f["status"] == "removed":
            continue
        diff = _git("diff", "--no-color", "-U3", "-M", f"{base}...HEAD", "--", f["path"])
        hunks = diff[diff.find("\n@@") + 1:] if "\n@@" in diff else ""
        f["patch"] = hunks.rstrip("\n")
    tree_paths = _git("ls-tree", "-r", "-z", "--full-tree", "--name-only", "HEAD").split("\0")
    tree = set(p for p in tree_paths if p)
    for p in list(tree):
        parts = p.split("/")
        for i in range(1, len(parts)):
            tree.add("/".join(parts[:i]))
    texts = {}
    for f in files:
        if f["path"].endswith(DOC_SUFFIXES) and f["status"] != "removed":
            texts[f["path"]] = _git("show", f"HEAD:{f['path']}")
    # Public unless CLAUDE.md explicitly declares the repository private.
    claude_md = REPO_ROOT / "CLAUDE.md"
    declared = claude_md.read_text(encoding="utf-8", errors="replace") if claude_md.exists() else ""
    public = not re.search(r"^##\s*Repo Visibility:\s*Private\b", declared, re.M | re.I)
    pr = {"body": body, "files": files, "texts": texts, "tree": tree, "public": public}
    return slice_pr_text(pr)


def cmd_scan(args, criteria):
    body = ""
    if args.body_file:
        body = Path(args.body_file).read_text(encoding="utf-8").replace("\r\n", "\n")
    terms = load_private_terms(args.private_terms or os.environ.get("REVIEW_SHADOW_PRIVATE_TERMS"))
    pt = local_pr(args.base, body)
    bad = 0
    for v in run_scripts(criteria, pt, terms):
        if v["verdict"] == "pass":
            continue
        bad += 1
        if v["verdict"] == "unanswered":
            print(f"{v['rule_id']}: not checked ({v['reason']})")
        for path, line in v["where"]:
            print(f"{v['rule_id']}: {path}:{line}")
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="review-shadow.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="load the criteria and category files and report problems")
    sp = sub.add_parser("scan", help="run the script criteria over the current branch; writes nothing")
    sp.add_argument("--base", default="origin/main")
    sp.add_argument("--body-file")
    sp.add_argument("--private-terms")
    args = ap.parse_args(argv)
    try:
        criteria = load_criteria()
        load_categories(criteria)
        if args.command == "scan":
            return cmd_scan(args, criteria)
    except (ConfigError, FetchError, ValueError) as e:
        print(f"review-shadow: {e}", file=sys.stderr)
        return 2
    print(f"criteria: {len(criteria['criteria'])} loaded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
