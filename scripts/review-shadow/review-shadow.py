#!/usr/bin/env python3
"""Shadow trial: grade a pull request with closed criteria beside its review panel.

The trial only records. Nothing here approves, skips or shortens a panel; a
unanimous pass is a line in a local file. docs/designs/DESIGN-jev-review-shadow.md
is the design this implements.

Subcommands:
  grade    grade one pull request at one head and write a record
  outcome  record a panel's outcome for the same pull request and head
  report   print agreement between grader and panels
  scan     run the script criteria over a local branch; writes nothing

Requires: Python 3.8 or later, standard library only, and `gh` for `grade`.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
CRITERIA_FILE = HERE / "criteria.json"
CATEGORIES_FILE = HERE / "categories.json"

VALUE_KEYS = ("pass", "fail")
OBSERVERS = ("script", "jev")
ARTIFACT_KINDS = ("pull-request",)
SLICE_KINDS = ("pr-text", "pr-summary", "code-hunks", "doc-pairs")
SCRIPT_CHECKS = ("attribution", "private_terms", "scratch_path", "unfinished_wording",
                 "pasted_paragraph", "dangling_path")
CLASSES = ("covered", "closed-uncovered", "open-judgment")
PANEL_KINDS = ("scrutiny", "review", "qa", "pre-merge")
RULE_ID = re.compile(r"rs-[0-9]{3}")
CRITERION_FIELDS = ("rule_id", "rule_ref", "group", "artifact_kind", "slice_kind", "observer",
                    "question", "values", "escape", "threshold")


class ConfigError(Exception):
    """A criteria or category file that the trial refuses to run with."""


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
        if c["observer"] not in OBSERVERS:
            raise ConfigError(f"{where}: observer must be script or jev")
        if c["observer"] == "script":
            if c.get("check") not in SCRIPT_CHECKS:
                raise ConfigError(f"{where}: unknown check {c.get('check')!r}")
            if c["slice_kind"] != "pr-text":
                raise ConfigError(f"{where}: script criteria read the pr-text slice")
        elif c["slice_kind"] == "pr-text":
            raise ConfigError(f"{where}: Jev criteria can't read the unbounded pr-text slice")
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


# --- Arguments -------------------------------------------------------------

# Every value that becomes a path segment or a `gh` endpoint is checked here
# first, so text from the command line never reaches either unvalidated.
REPO_ARG = re.compile(r"([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)")
HEAD_ARG = re.compile(r"[0-9a-f]{40}")
PANEL_RUN_ARG = re.compile(r"claude:[A-Za-z0-9._-]{1,80}|koto:[A-Za-z0-9._-]{1,80}:[A-Za-z0-9._-]{1,80}")


def check_repo(value):
    m = REPO_ARG.fullmatch(value or "")
    if not m or any(part in (".", "..") for part in m.groups()):
        raise ValueError("--repo must be owner/name")
    return value


def check_pr(value):
    if not re.fullmatch(r"[1-9][0-9]{0,8}", str(value)):
        raise ValueError("--pr must be a pull request number")
    return int(value)


def check_head(value):
    if not HEAD_ARG.fullmatch(value or ""):
        raise ValueError("--head must be a full 40-character lowercase commit sha")
    return value


def check_panel_run(value):
    if value is not None and not PANEL_RUN_ARG.fullmatch(value):
        raise ValueError("--panel-run must be claude:<session-id> or koto:<workflow>:<session-id>")
    return value


def parse_time(value):
    """Parse an ISO-8601 UTC time such as 2026-09-28T07:25:00Z."""
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --- Fetching a pull request at a head --------------------------------------

class FetchError(Exception):
    """GitHub data the grade needs could not be read."""


class GhFetcher:
    """Reads pull request data through `gh api`, with an argument list and no shell.

    Field values go through `-f`, never `-F`: `-F` reads a local file for a
    value starting with `@`, and a pull request's text must never choose what
    is read from this machine.
    """

    def _api(self, *args):
        cmd = ["gh", "api", *args]
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=60)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise FetchError(f"gh could not run: {type(e).__name__}")
        if out.returncode != 0:
            endpoint = next((a for a in args if a.startswith("repos/") or a == "graphql"), "?")
            raise FetchError(f"gh api {endpoint.split('?')[0]} failed")
        return out.stdout

    def pull(self, repo, number):
        return json.loads(self._api(f"repos/{repo}/pulls/{number}"))

    def compare(self, repo, base, head):
        """The compare API pages its file list; read up to three pages of 100,
        GitHub's limit of 300 files."""
        base = urllib.parse.quote(base, safe="")
        files, data = [], {}
        for page in (1, 2, 3):
            data = json.loads(self._api(f"repos/{repo}/compare/{base}...{head}?per_page=100&page={page}"))
            batch = data.get("files", [])
            files += batch
            if len(batch) < 100:
                break
        data["files"] = files
        return data

    def raw_file(self, repo, path, head):
        return self._api("-H", "Accept: application/vnd.github.raw",
                         f"repos/{repo}/contents/{urllib.parse.quote(path, safe='/')}?ref={head}")

    def tree(self, repo, head):
        data = json.loads(self._api(f"repos/{repo}/git/trees/{head}?recursive=1"))
        return [e["path"] for e in data.get("tree", [])], bool(data.get("truncated"))

    def body_edits(self, repo, number):
        owner, name = repo.split("/", 1)
        # number is validated digits, so it is safe inline; owner and name go
        # as GraphQL variables.
        query = ("query($o:String!,$r:String!){repository(owner:$o,name:$r){pullRequest(number:%d)"
                 "{userContentEdits(first:100){nodes{editedAt diff}}}}}" % number)
        data = json.loads(self._api("graphql", "-f", f"query={query}", "-f", f"o={owner}", "-f", f"r={name}"))
        nodes = data["data"]["repository"]["pullRequest"]["userContentEdits"]["nodes"]
        return [(n["editedAt"], n["diff"]) for n in nodes if n.get("editedAt") and isinstance(n.get("diff"), str)]


DOC_SUFFIXES = (".md",)
NON_CODE_SUFFIXES = (".md", ".json", ".yaml", ".yml", ".lock")


def body_as_of(edits, current_body, body_at):
    """The body text as it read at `body_at`, from the edit history.

    Each edit holds the full body after that edit. With no edit at or before
    `body_at`, the oldest version is used: it is the body the pull request
    was opened with.
    """
    if not edits:
        return current_body
    edits = sorted(edits, key=lambda e: e[0])
    chosen = edits[0][1]
    for at, text in edits:
        if parse_time(at) <= body_at:
            chosen = text
    return chosen


def diff_kind(paths):
    """docs, code or mixed. Only Markdown under docs/ and a top-level README count as
    documentation: shirabe's skills, references and templates are Markdown that drives
    workflows, and a script kept under docs/ is still code."""
    docs = [p == "README.md" or (p.startswith("docs/") and p.endswith(".md")) for p in paths]
    if docs and all(docs):
        return "docs"
    if not any(docs):
        return "code"
    return "mixed"


def fetch_pr(fetcher, repo, number, head, body_at=None, body_file=None):
    """Everything the slicers and script checks read, for one pull request at one head."""
    pull = fetcher.pull(repo, number)
    base_ref = pull["base"]["ref"]
    public = not pull["base"]["repo"].get("private", True)
    cmp = fetcher.compare(repo, pull["base"].get("sha") or base_ref, head)
    files = []
    for f in cmp.get("files", []):
        files.append({"path": f["filename"], "status": f.get("status", "modified"),
                      "additions": f.get("additions", 0), "deletions": f.get("deletions", 0),
                      "patch": f.get("patch")})
    reasons = []
    graded_body_at = body_at or now_iso()
    if body_file is not None:
        body, body_source = body_file, "file"
    else:
        try:
            body = body_as_of(fetcher.body_edits(repo, number), pull.get("body") or "", parse_time(graded_body_at))
            body_source = "history"
        except (FetchError, KeyError, TypeError, ValueError):
            body, body_source = pull.get("body") or "", "current"
            reasons.append("body-history-unreadable")
    texts = {}
    for f in files:
        if f["path"].endswith(DOC_SUFFIXES) and f["status"] != "removed":
            try:
                texts[f["path"]] = fetcher.raw_file(repo, f["path"], head)
            except FetchError:
                texts[f["path"]] = None
    try:
        tree_paths, tree_truncated = fetcher.tree(repo, head)
        tree = set(tree_paths)
        for p in tree_paths:
            parts = p.split("/")
            for i in range(1, len(parts)):
                tree.add("/".join(parts[:i]))
    except (FetchError, KeyError, TypeError, ValueError):
        tree, tree_truncated = None, False
    return {"repo": repo, "pr": number, "head": head, "base_ref": base_ref, "public": public,
            "body": (body or "").replace("\r\n", "\n"), "body_source": body_source,
            "graded_body_at": graded_body_at, "files": files,
            "files_truncated": len(files) >= 300, "texts": texts,
            "tree": tree, "tree_truncated": tree_truncated, "reasons": reasons,
            "diff_kind": diff_kind([f["path"] for f in files])}


# --- Slices ------------------------------------------------------------------

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


def slice_pr_summary(pr):
    """Part 1 with the file list. The list is summarized by directory before it
    is ever cut: an "omits a change" question over part of the list is wrong."""
    body = part1(pr["body"])
    for level, depth in (("files", None), ("dir3", 3), ("dir2", 2), ("dir1", 1)):
        s = make_slice("pr-summary", 1, {"pr_body_part1": body, "diff_summary": diffstat(pr["files"], depth)},
                       {"summary_level": level})
        if not s["over_bound"]:
            return [s]
    return [s]


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


def hunk_units(hunk, path_len):
    """A hunk as whole units within the bound. A hunk over the bound, such as a
    whole new file, is split at blank lines into blocks, each headed by the
    hunk's @@ line so the reader keeps its position; a block still over the
    bound stays one over-bound unit."""
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
    seen, pairs, over = set(), [], 0
    for score, path, i, j, paras in sorted(candidates, key=lambda c: -c[0]):
        if (path, i, j) in seen:
            continue
        seen.add((path, i, j))
        inputs = {"path": path, "location_a": paras[i][1], "location_b": paras[j][1]}
        if sum(utf8_len(v) for v in inputs.values()) > BOUND:
            over += 1  # logged in the record's pair counts, never sent or cut
            continue
        pairs.append(inputs)
    kept, dropped = pairs[:MAX_DOC_PAIRS], max(0, len(pairs) - MAX_DOC_PAIRS)
    meta = {"pairs_dropped": dropped, "pairs_over_bound": over}
    return [make_slice("doc-pairs", n, inputs, meta) for n, inputs in enumerate(kept, 1)], meta


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
    failure refuses rather than lets a record or a term list land in a repository."""
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
HOME_PATH = re.compile(r"/home/(?!(?:u|user|x)/)[a-z_][a-z0-9_-]*/|/Users/[A-Za-z][A-Za-z0-9._-]*/")
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
    if not pt["public"]:
        return "pass", [], None  # the rule governs public content only
    if not terms:
        return "unanswered", [], "no-denylist"  # an empty list checks nothing, so it isn't a pass
    folded, exact = set(), set()
    for t in terms:
        f, e = term_forms(t)
        folded |= f
        exact |= e
    hits = []
    for p, ln, text in _lines(pt):
        low = text.lower()
        if HOME_PATH.search(text) or any(f in low for f in folded) or any(e in text for e in exact):
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
    hits = []
    for path, text in pt["texts"].items():
        if not text:
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
    return ("fail" if hits else "pass"), hits, None


def check_dangling_path(pt, _terms):
    if pt["tree"] is None:
        return "unanswered", [], "tree-unreadable"
    hits = []
    for p, ln, text in pt["added"]:
        if not p.endswith(".md"):
            continue
        for tok in PATH_TOKEN.findall(text):
            if tok.startswith(("http", "wip" + "/")) or ".." in tok.split("/") or not tok.endswith(PATH_SUFFIXES):
                continue
            target = tok.rstrip("/")
            local = str(Path(p).parent / target) if "/" in p else target
            if target not in pt["tree"] and local not in pt["tree"]:
                hits.append((p, ln))
    return ("fail" if hits else "pass"), hits, None


CHECKS = {"attribution": check_attribution, "private_terms": check_private_terms,
          "scratch_path": check_scratch_path, "unfinished_wording": check_unfinished_wording,
          "pasted_paragraph": check_pasted_paragraph, "dangling_path": check_dangling_path}


def run_scripts(criteria, pt, terms):
    """Every script criterion over the pr-text slice, in file order."""
    out = []
    for c in criteria["criteria"]:
        if c["observer"] != "script":
            continue
        verdict, hits, reason = CHECKS[c["check"]](pt, terms)
        out.append({"rule_id": c["rule_id"], "slice": "pr-text", "verdict": verdict, "observer": "script",
                    "probabilities": None, "reason": reason, "findings": len(hits), "where": hits})
    return out


# --- Jev ---------------------------------------------------------------------

JEV_ENDPOINT = "https://api.typesafe.ai/v1/systemone"
JEV_MODEL = "jev-latest"


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse every redirect, so the key never reaches a second host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, "redirect refused", headers, fp)


def https_transport(endpoint, key, timeout):
    """POST a JSON body; return (status, raw body). The key goes in an
    unredirected Authorization header and nowhere else."""
    if not endpoint.startswith("https://"):
        raise ConfigError("the Jev endpoint must be https")
    opener = urllib.request.build_opener(_NoRedirect)

    def send(body):
        req = urllib.request.Request(endpoint, data=json.dumps(body).encode("utf-8"), method="POST",
                                     headers={"Content-Type": "application/json"})
        req.add_unredirected_header("Authorization", "Bearer " + key)
        try:
            with opener.open(req, timeout=timeout) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            return e.code, b""  # an error body can echo request headers, so it's dropped
        except (urllib.error.URLError, TimeoutError, OSError):
            return None, b""
    return send


def ask_jev(send, body):
    """One request, retried once on a transport failure, a 5xx or an unreadable
    answer, as koto's decider check does. Returns (answer, reason, attempts,
    latency_ms, billed_unread): `billed_unread` counts 200 answers whose usage
    couldn't be read."""
    import time
    reason, billed_unread, latency = None, 0, 0
    for attempt in (1, 2):
        start = time.monotonic()
        status, raw = send(body)
        latency = int((time.monotonic() - start) * 1000)
        if status is None:
            reason = "transport"
            continue
        if status != 200:
            reason = "provider"
            if status < 500:
                return None, reason, attempt, latency, billed_unread
            continue
        try:
            answer = json.loads(raw)
            if not isinstance(answer, dict) or not isinstance(answer.get("answers"), dict):
                raise ValueError
        except ValueError:
            reason = "unreadable-answer"
            billed_unread += 1
            continue
        usage = answer.get("usage")
        if not (isinstance(usage, dict) and isinstance(usage.get("input_tokens"), int)
                and isinstance(usage.get("output_tokens"), int)):
            billed_unread += 1
        return answer, None, attempt, latency, billed_unread
    return None, reason, 2, latency, billed_unread


def question(c):
    return {"type": "choice", "instructions": c["question"],
            "criteria": {**c["values"], **c["escape"]}}


def map_answer(c, answer):
    """(verdict, probabilities, reason) for one criterion, with koto's threshold rule:
    a value wins only if it has the highest probability and at least the threshold."""
    ans = (answer.get("answers") or {}).get(c["rule_id"])
    if ans is None:
        return "unanswered", None, "missing-answer"
    probs = ans.get("probabilities") if isinstance(ans, dict) else None
    keys = set(c["values"]) | set(c["escape"])
    if not isinstance(probs, dict) or set(probs) != keys or \
            not all(isinstance(v, (int, float)) and 0 <= v <= 1 for v in probs.values()):
        return "unanswered", None, "unreadable-answer"
    win = max(probs, key=probs.get)
    if win in c["escape"] or probs[win] < c["threshold"]:
        return "escape", probs, None
    return win, probs, None


VERDICT_ORDER = ("fail", "unanswered", "escape", "pass")


def worst(verdicts):
    return min(verdicts, key=VERDICT_ORDER.index) if verdicts else "pass"


# --- Grade -------------------------------------------------------------------

def run_jev(criteria, slices, send, batched):
    """Every Jev criterion over its slices. One request per slice carries every
    criterion of that slice kind, or one per criterion when unbatched."""
    verdicts, rounds, unread = [], [], 0
    by_kind = {}
    for c in criteria["criteria"]:
        if c["observer"] == "jev":
            by_kind.setdefault(c["slice_kind"], []).append(c)
    for kind, crits in by_kind.items():
        for s in slices.get(kind, []):
            if s["over_bound"] or send is None:
                reason = "over-bound" if s["over_bound"] else "no-key"
                verdicts += [{"rule_id": c["rule_id"], "slice": s["id"], "verdict": "unanswered", "observer": "jev",
                              "probabilities": None, "reason": reason} for c in crits]
                continue
            for group in ([crits] if batched else [[c] for c in crits]):
                body = {"model": JEV_MODEL, "state": s["inputs"],
                        "questions": {c["rule_id"]: question(c) for c in group}}
                answer, reason, attempts, latency, billed_unread = ask_jev(send, body)
                unread += billed_unread
                usage = (answer or {}).get("usage") or {}
                rounds.append({"slice": s["id"], "rule_ids": [c["rule_id"] for c in group],
                               "batched": len(group) > 1,
                               "model": (answer or {}).get("model"), "answered": answer is not None,
                               "input_tokens": usage.get("input_tokens") if isinstance(usage.get("input_tokens"), int) else None,
                               "output_tokens": usage.get("output_tokens") if isinstance(usage.get("output_tokens"), int) else None,
                               "attempts": attempts, "latency_ms": latency, "reason": reason})
                for c in group:
                    if answer is None:
                        v, probs, why = "unanswered", None, reason
                    else:
                        v, probs, why = map_answer(c, answer)
                    verdicts.append({"rule_id": c["rule_id"], "slice": s["id"], "verdict": v, "observer": "jev",
                                     "probabilities": probs, "reason": why})
    return verdicts, rounds, unread


def run_status(criterion_verdicts, rounds, jev_slices, no_key):
    """unanimous-pass, dissent, inconclusive, or not-graded when Jev had slices to
    grade and never answered, so an outage is never counted as agreement."""
    if jev_slices and not any(r["answered"] for r in rounds):
        if no_key:
            return "not-graded", "no-key"
        if rounds:
            reasons = {r["reason"] for r in rounds}
            return "not-graded", "transport" if "transport" in reasons else "provider"
    vs = [c["verdict"] for c in criterion_verdicts]
    if "fail" in vs:
        return "dissent", None
    if any(v != "pass" for v in vs):
        return "inconclusive", None
    return "unanimous-pass", None


def criteria_version(path=CRITERIA_FILE):
    data = Path(path).read_bytes()
    return {"version": json.loads(data)["version"], "sha256": hashlib.sha256(data).hexdigest()}


def grade(criteria, pr, terms, send, batched=True):
    """Scripts first, then Jev. Returns the record body (no identity fields yet)."""
    pt = slice_pr_text(pr)
    verdicts = run_scripts(criteria, pt, terms)
    slices, pair_meta = build_slices(pr)
    jev_verdicts, rounds, unread = run_jev(criteria, slices, send, batched)
    for v in verdicts:
        v.pop("where", None)  # paths and lines stay in scan output; records hold counts
    verdicts += jev_verdicts
    crit_rows = []
    for c in criteria["criteria"]:
        vs = [v["verdict"] for v in verdicts if v["rule_id"] == c["rule_id"]]
        row = {"rule_id": c["rule_id"], "verdict": worst(vs), "slices": len(vs)}
        if c["slice_kind"] == "doc-pairs":
            row.update(pair_meta)
        crit_rows.append(row)
    jev_slices = sum(len(slices.get(c["slice_kind"], [])) for c in criteria["criteria"] if c["observer"] == "jev")
    status, why = run_status(crit_rows, rounds, jev_slices, send is None)
    all_slices = [dict({k: s[k] for k in ("id", "kind", "bytes", "sha256", "over_bound")}, **s["meta"])
                  for kind in slices for s in slices[kind]]
    tokens = {"input": sum(r["input_tokens"] or 0 for r in rounds),
              "output": sum(r["output_tokens"] or 0 for r in rounds)}
    models = sorted({r["model"] for r in rounds if r["model"]})
    return {"mode": "batched" if batched else "unbatched", "slices": all_slices, "verdicts": verdicts,
            "criteria": crit_rows, "rounds": rounds, "models": models, "unread_usage_attempts": unread,
            "tokens": tokens, "status": status, "not_graded_reason": why}


# --- The local store ---------------------------------------------------------

def store_home():
    """The record store: a fixed directory under XDG_STATE_HOME. REVIEW_SHADOW_HOME
    overrides it for tests only. It must sit outside every git work tree."""
    home = os.environ.get("REVIEW_SHADOW_HOME") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state"),
        "shirabe", "review-shadow")
    home = os.path.realpath(home)
    if inside_work_tree(home):
        raise ConfigError("the record store must live outside every git work tree")
    return Path(home)


def write_private(path, data):
    """Write JSON with directories 0700 and the file 0600, through a temporary file
    and a rename so an archiver never reads half a record."""
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    for d in [path.parent, *path.parent.parents]:
        if d == store_home_root(path):
            break
        os.chmod(d, 0o700)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def store_home_root(path):
    """The store root above a record or outcome path."""
    for d in path.parents:
        if d.name in ("records", "outcomes"):
            return d.parent
    return path.parent


def head_dir(home, kind, repo, pr, head):
    owner, name = repo.split("/", 1)
    return home / kind / owner / name / str(pr) / head


def write_record(home, record):
    stamp = record["recorded_at"].replace("-", "").replace(":", "")
    path = head_dir(home, "records", record["repo"], record["pr"], record["head_sha"]) / \
        f"{stamp}-{record['run_id']}.json"
    write_private(path, record)
    return path


def new_record(repo, pr, head, **fields):
    import socket
    import uuid
    rec = {"schema": "review-shadow/record/v1", "trial": "jev-review-shadow", "run_id": uuid.uuid4().hex[:16],
           "recorded_at": now_iso(), "repo": repo, "pr": pr, "head_sha": head, "panel_run_id": None,
           "panel_kind": None, "session_id": os.environ.get("CLAUDE_CODE_SESSION_ID") or None,
           "host": socket.gethostname(), "criteria_version": criteria_version()}
    rec.update(fields)
    return rec


def cmd_grade(args, criteria):
    repo, pr, head = check_repo(args.repo), check_pr(args.pr), check_head(args.head)
    panel_run = check_panel_run(args.panel_run)
    if args.body_at:
        parse_time(args.body_at)
    if args.panel_kind and args.panel_kind not in PANEL_KINDS:
        raise ValueError(f"--panel-kind must be one of {PANEL_KINDS}")
    terms = load_private_terms(args.private_terms or os.environ.get("REVIEW_SHADOW_PRIVATE_TERMS"))
    home = store_home()
    body_file = Path(args.body_file).read_text(encoding="utf-8") if args.body_file else None
    in_sample = head_dir(home, "outcomes", repo, pr, head).exists()
    pr_data = fetch_pr(GhFetcher(), repo, pr, head, body_at=args.body_at, body_file=body_file)
    key = os.environ.get("JEV_API_KEY") or os.environ.get("KOTO_DECIDER_API_KEY")
    send = https_transport(JEV_ENDPOINT, key, 20.0) if key else None
    body = grade(criteria, pr_data, terms, send, batched=not args.unbatched)
    rec = new_record(repo, pr, head, panel_run_id=panel_run, panel_kind=args.panel_kind,
                     graded_body_at=pr_data["graded_body_at"], body_source=pr_data["body_source"],
                     diff_kind=pr_data["diff_kind"], in_sample=in_sample,
                     reasons=pr_data["reasons"] + (["files-truncated"] if pr_data["files_truncated"] else []),
                     **body)
    path = write_record(home, rec)
    print(f"{path} status={rec['status']} tokens={rec['tokens']['input']}+{rec['tokens']['output']}")
    return 0


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
    public = bool(re.search(r"^## Repo Visibility: Public", (REPO_ROOT / "CLAUDE.md").read_text(encoding="utf-8"),
                            re.M)) if (REPO_ROOT / "CLAUDE.md").exists() else True
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
    gp = sub.add_parser("grade", help="grade one pull request at one head and write a record")
    gp.add_argument("--repo", required=True)
    gp.add_argument("--pr", required=True)
    gp.add_argument("--head", required=True)
    gp.add_argument("--panel-kind", choices=PANEL_KINDS)
    gp.add_argument("--panel-run")
    gp.add_argument("--body-at", help="grade the body as it read at this UTC time (YYYY-MM-DDTHH:MM:SSZ)")
    gp.add_argument("--body-file")
    gp.add_argument("--private-terms")
    gp.add_argument("--unbatched", action="store_true", help="one Jev request per criterion per slice")
    sp = sub.add_parser("scan", help="run the script criteria over the current branch; writes nothing")
    sp.add_argument("--base", default="origin/main")
    sp.add_argument("--body-file")
    sp.add_argument("--private-terms")
    args = ap.parse_args(argv)
    commands = {"scan": cmd_scan, "grade": cmd_grade}
    if args.command in commands:
        try:
            criteria = load_criteria()
            load_categories(criteria)
            return commands[args.command](args, criteria)
        except (ConfigError, FetchError, ValueError) as e:
            print(f"review-shadow: {e}", file=sys.stderr)
            return 2
    try:
        criteria = load_criteria()
        load_categories(criteria)
    except ConfigError as e:
        print(f"review-shadow: {e}", file=sys.stderr)
        return 2
    if args.command == "check":
        print(f"criteria: {len(criteria['criteria'])} loaded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
