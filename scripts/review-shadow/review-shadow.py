#!/usr/bin/env python3
"""Shadow trial: grade a pull request with closed criteria beside its review panel.

The trial only records. Nothing here approves, skips or shortens a panel; a
unanimous pass is a line in a local file.
docs/designs/current/DESIGN-jev-review-shadow.md is the design this implements,
and docs/guides/review-shadow.md says how to run it.

Subcommands:
  grade    grade one pull request at one head and write a record
  outcome  record a panel's outcome for the same pull request and head
  report   print agreement between grader and panels
  scan     run the script criteria over a local branch; writes nothing
  check    load the criteria and category files and report problems

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
ARTIFACT_KINDS = ("pull-request", "brief", "prd", "plan", "local-change")
# Which slicers can feed a criterion of each artifact kind. A site criterion
# names the artifact it judges, so a pull-request criterion can never be asked
# of a brief, or a brief criterion of a pull request.
SLICE_KINDS_BY_ARTIFACT = {
    "pull-request": ("pr-text", "pr-summary", "code-hunks", "doc-pairs"),
    "brief": ("brief-journey", "summary-pair"),
    "prd": ("prd-ac",),
    "plan": ("plan-ac-block",),
    "local-change": ("ac-hunks", "code-hunks"),
}
SLICE_KINDS = tuple(dict.fromkeys(k for kinds in SLICE_KINDS_BY_ARTIFACT.values() for k in kinds))
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
    """The criteria a run grades: every criterion of the artifact kind being
    graded that isn't shipped off, plus any the caller turned on with --enable
    (recorded on the criteria object by grade)."""
    on = set(criteria.get("_enabled", ()))
    return [c for c in criteria["criteria"]
            if c["artifact_kind"] == artifact_kind and (c.get("enabled", True) or c["rule_id"] in on)]


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


def gh_hint(endpoint, stderr):
    """A fixed cause-and-fix line for a failed gh call. stderr is only classified,
    never echoed: some servers put request headers in an error body."""
    err = (stderr or "").lower()
    if "gh auth login" in err or "not logged" in err or "authentication" in err or "http 401" in err:
        return "gh is not logged in; run `gh auth status` and `gh auth login`"
    if "rate limit" in err or "http 429" in err or ("http 403" in err and "limit" in err):
        return "GitHub's rate limit was hit; wait and run it again"
    if "/compare/" in endpoint and ("http 404" in err or "not found" in err or "http 422" in err):
        return "--head isn't a commit this pull request had; pass its full 40-character sha"
    if "/contents/" in endpoint or "/git/trees/" in endpoint:
        return "a file or the tree at --head couldn't be read; check --head"
    if "http 404" in err or "not found" in err:
        return "no such repository or pull request; check --repo and --pr, and that your login can read it"
    return "gh returned an error; check `gh auth status`, --repo, --pr and --head"


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
            endpoint = next((a for a in args if a.startswith("repos/") or a == "graphql"), "?").split("?")[0]
            raise FetchError(f"gh api {endpoint} failed: {gh_hint(endpoint, out.stderr)}")
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
    """docs, code, mixed, or none for a head that changes nothing.

    Only Markdown under docs/ and the top-level README.md count as documentation.
    Every other Markdown file (CLAUDE.md, AGENTS.md, a changelog, a nested
    README) is code, because shirabe's skills, references and agent instructions
    are Markdown that drives workflows, and a script kept under docs/ is still
    code. Callers pass both paths of a rename, so moving a file out of docs/ is
    never docs."""
    if not paths:
        return "none"
    docs = [p == "README.md" or (p.startswith("docs/") and p.endswith(".md")) for p in paths]
    if all(docs):
        return "docs"
    if not any(docs):
        return "code"
    return "mixed"


def fetch_pr(fetcher, repo, number, head, body_at=None, body_file=None):
    """Everything the slicers and script checks read, for one pull request at one head."""
    pull = fetcher.pull(repo, number)
    base_ref = pull["base"]["ref"]
    # Only an explicit private flag skips the private-name check: an unknown
    # visibility is treated as public, so the leak guard never turns itself off.
    public = pull["base"]["repo"].get("private") is not True
    cmp = fetcher.compare(repo, pull["base"].get("sha") or base_ref, head)
    files = []
    for f in cmp.get("files", []):
        files.append({"path": f["filename"], "previous_path": f.get("previous_filename"),
                      "status": f.get("status", "modified"),
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
            "diff_kind": diff_kind(changed_paths(files))}


def changed_paths(files):
    """Every path a change touches, both sides of a rename included."""
    out = []
    for f in files:
        out.append(f["path"])
        if f.get("previous_path"):
            out.append(f["previous_path"])
    return out


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
    import http.client
    if not endpoint.startswith("https://"):
        raise ConfigError("the Jev endpoint must be https")
    key = key.strip()
    if not key or any(ord(ch) < 33 or ord(ch) == 127 for ch in key):
        # The message names no part of the key: an error text reaches stderr.
        raise ConfigError("the Jev key is empty or holds whitespace or control characters")
    opener = []  # built on first use

    def send(body):
        if not opener:
            opener.append(urllib.request.build_opener(_NoRedirect))
        req = urllib.request.Request(endpoint, data=json.dumps(body).encode("utf-8"), method="POST",
                                     headers={"Content-Type": "application/json"})
        req.add_unredirected_header("Authorization", "Bearer " + key)
        try:
            with opener[0].open(req, timeout=timeout) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            return e.code, b""  # an error body can echo request headers, so it's dropped
        except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException, ValueError):
            # Nothing from the exception is kept: some carry the request headers.
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
            not all(isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 1
                    for v in probs.values()):
        return "unanswered", None, "unreadable-answer"
    win = max(probs, key=probs.get)
    if win in c["escape"] or probs[win] < c["threshold"]:
        return "escape", probs, None
    return win, probs, None


VERDICT_ORDER = ("fail", "unanswered", "escape", "pass")


def worst(verdicts):
    return min(verdicts, key=VERDICT_ORDER.index) if verdicts else "pass"


# --- Grade -------------------------------------------------------------------

def run_jev(criteria, slices, send, batched, artifact_kind="pull-request"):
    """Every Jev criterion of one artifact kind over its slices. One request per
    slice carries every criterion of that slice kind, or one per criterion when
    unbatched."""
    verdicts, rounds, unread = [], [], 0
    by_kind = {}
    for c in active(criteria, artifact_kind):
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


def run_status(criterion_verdicts, rounds, jev_slices, no_key, jev_verdicts):
    """unanimous-pass, dissent, inconclusive, or not-graded when Jev had slices to
    grade and never answered, so an outage is never counted as agreement. A
    head whose every Jev slice was over the bound is not-graded too: nothing
    was ever sent, so it has no verdict to count as open."""
    if jev_slices and not any(r["answered"] for r in rounds):
        if no_key:
            return "not-graded", "no-key"
        if rounds:
            reasons = {r["reason"] for r in rounds}
            return "not-graded", "transport" if "transport" in reasons else "provider"
        if jev_verdicts and all(v["reason"] == "over-bound" for v in jev_verdicts):
            return "not-graded", "over-bound"
    vs = [c["verdict"] for c in criterion_verdicts]
    if "fail" in vs:
        return "dissent", None
    if any(v != "pass" for v in vs):
        return "inconclusive", None
    return "unanimous-pass", None


TOOL_VERSION = 3  # bump when grading behaviour changes; the hashes below catch the rest


def tool_version():
    """Which tool produced a record: the version, a hash of every file that
    shapes a verdict, and the commit it came from when git can say."""
    files = {"script": Path(__file__).resolve(), "categories": CATEGORIES_FILE, "wording": UNFINISHED_FILE}
    out = {"version": TOOL_VERSION}
    for name, path in files.items():
        out[f"{name}_sha256"] = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    try:
        git = subprocess.run(["git", "-C", str(HERE), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=10)
        dirty = subprocess.run(["git", "-C", str(HERE), "status", "--porcelain", "--", "."],
                               capture_output=True, text=True, timeout=10)
        out["git_sha"] = git.stdout.strip() if git.returncode == 0 else None
        out["git_dirty"] = bool(dirty.stdout.strip()) if dirty.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        out["git_sha"], out["git_dirty"] = None, None
    return out


def criteria_version(path=CRITERIA_FILE):
    data = Path(path).read_bytes()
    return {"version": json.loads(data)["version"], "sha256": hashlib.sha256(data).hexdigest()}


def grade(criteria, pr, terms, send, batched=True):
    """Scripts first, then Jev. Returns the record body (no identity fields yet).
    A head that changes nothing is not graded: a pass over nothing isn't agreement."""
    if not pr["files"]:
        return {"mode": "batched" if batched else "unbatched", "slices": [], "verdicts": [], "criteria": [],
                "rounds": [], "models": [], "unread_usage_attempts": 0, "tokens": {"input": 0, "output": 0},
                "status": "not-graded", "not_graded_reason": "no-changed-paths"}
    pt = slice_pr_text(pr)
    verdicts = run_scripts(criteria, pt, terms)
    slices, pair_meta = build_slices(pr)
    jev_verdicts, rounds, unread = run_jev(criteria, slices, send, batched)
    for v in verdicts:
        v.pop("where", None)  # paths and lines stay in scan output; records hold counts
    verdicts += jev_verdicts
    crit_rows = []
    for c in active(criteria):
        vs = [v["verdict"] for v in verdicts if v["rule_id"] == c["rule_id"]]
        row = {"rule_id": c["rule_id"], "verdict": worst(vs), "slices": len(vs)}
        if c["slice_kind"] == "doc-pairs":
            row.update(pair_meta)
        crit_rows.append(row)
    jev_slices = sum(len(slices.get(c["slice_kind"], [])) for c in active(criteria) if c["observer"] == "jev")
    status, why = run_status(crit_rows, rounds, jev_slices, send is None, jev_verdicts)
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


def write_private(path, data, home=None):
    """Write JSON with every directory from the store home down made 0700 and the
    file 0600, through a temporary file and a rename so an archiver never reads
    half a record."""
    home = Path(home) if home else store_home()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    rel = path.parent.relative_to(home)
    os.chmod(home, 0o700)
    for i in range(1, len(rel.parts) + 1):
        os.chmod(home.joinpath(*rel.parts[:i]), 0o700)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def head_dir(home, kind, repo, pr, head):
    owner, name = repo.split("/", 1)
    return home / kind / owner / name / str(pr) / head


def write_record(home, record):
    stamp = record["recorded_at"].replace("-", "").replace(":", "")
    path = head_dir(home, "records", record["repo"], record["pr"], record["head_sha"]) / \
        f"{stamp}-{record['run_id']}.json"
    write_private(path, record, home)
    return path


def new_record(repo, pr, head, **fields):
    import socket
    import uuid
    rec = {"schema": "review-shadow/record/v1", "trial": "jev-review-shadow", "run_id": uuid.uuid4().hex[:16],
           "recorded_at": now_iso(), "repo": repo, "pr": pr, "head_sha": head, "panel_run_id": None,
           "panel_kind": None, "session_id": os.environ.get("CLAUDE_CODE_SESSION_ID") or None,
           "host": socket.gethostname(), "criteria_version": criteria_version(), "tool": tool_version()}
    rec.update(fields)
    return rec


# --- Site records ------------------------------------------------------------
#
# A site record pairs the verdicts of a review site's seats (a jury in the scope
# chain, a /work-on panel) with the decider's verdicts on the same artifact.
# docs/designs/DESIGN-jev-closed-criteria.md is the design. Its identity is the
# site, the subject (a topic slug or an issue) and a hash of the graded inputs,
# which plays the part a head sha plays for a pull request.

SITES = ("brief", "prd", "review-plan", "work-on")
SITE_RECORD_SCHEMA = "review-shadow/record/v2"
SUBJECT_ARG = re.compile(r"[a-z0-9][a-z0-9-]{0,79}")
ARTIFACT_SHA_ARG = re.compile(r"[0-9a-f]{64}")


def check_site(value):
    if value not in SITES:
        raise ValueError(f"site must be one of {SITES}")
    return value


def check_subject(value):
    """A topic slug, or issue-<n> for /work-on: one path segment, never a path."""
    if not SUBJECT_ARG.fullmatch(value or ""):
        raise ValueError("a site subject must match [a-z0-9][a-z0-9-]*")
    return value


def is_site_record(rec):
    return (rec.get("subject") or {}).get("kind") == "site"


def new_site_record(repo, site, subject_id, artifact_sha, **fields):
    """A v2 record for one shadow run of one site. `seats` holds every shadowed
    seat's verdict; the caller adds the decider's verdicts beside it."""
    import socket
    import uuid
    check_repo(repo)
    check_site(site)
    check_subject(subject_id)
    if not ARTIFACT_SHA_ARG.fullmatch(artifact_sha or ""):
        raise ValueError("artifact_sha must be a sha256 hex digest")
    rec = {"schema": SITE_RECORD_SCHEMA, "trial": "jev-review-shadow", "run_id": uuid.uuid4().hex[:16],
           "recorded_at": now_iso(), "repo": repo,
           "subject": {"kind": "site", "site": site, "subject_id": subject_id, "artifact_sha": artifact_sha},
           "seats": [], "in_sample": False,
           "session_id": os.environ.get("CLAUDE_CODE_SESSION_ID") or None,
           "host": socket.gethostname(), "criteria_version": criteria_version(), "tool": tool_version()}
    rec.update(fields)
    return rec


def site_record_path(home, rec):
    owner, name = rec["repo"].split("/", 1)
    s = rec["subject"]
    stamp = rec["recorded_at"].replace("-", "").replace(":", "")
    return (home / "records" / owner / name / "site" / s["site"] / s["subject_id"] / s["artifact_sha"][:12]
            / f"{stamp}-{rec['run_id']}.json")


def write_site_record(home, rec):
    path = site_record_path(home, rec)
    write_private(path, rec, home)
    return path


# --- Site inputs ---------------------------------------------------------------
#
# Every site's decider input is cut by a script from files on disk (and, for
# /work-on, the run's koto context and git history). The commands take
# identifiers only; nothing an agent writes reaches a slice.

# The artifact kind each site grades. A site name is where a review happens; an
# artifact kind is what is read, so /review-plan reads a plan and /work-on a
# local change.
SITE_ARTIFACT = {"brief": "brief", "prd": "prd", "review-plan": "plan", "work-on": "local-change"}
WORK_ON_PANELS = ("scrutiny", "review", "light")
TOPIC_ARG = re.compile(r"[a-z0-9][a-z0-9-]{0,79}")
SESSION_ARG = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}")
MAX_SITE_FILES = 64
MAX_SITE_BYTES = 4 * 1024 * 1024
# A path that looks like it holds a secret is never read into a slice.
SECRET_PATH = re.compile(
    r"(?:^|/)(?:\.env[^/]*|[^/]*\.(?:pem|key|p12|pfx|tfvars)|id_rsa[^/]*|id_ed25519[^/]*|\.npmrc|\.netrc"
    r"|[^/]*credentials[^/]*|[^/]*secret[^/]*)$", re.I)
# The diff options every site diff carries: a repository's own diff drivers
# (diff.external, a textconv filter) must not run a command during assembly.
GIT_DIFF = ("diff", "--no-ext-diff", "--no-textconv", "--no-color")
# The workflows' scratch directory, where seats leave their verdict files. Built
# from a constant so this file names no path inside it (the scratch-path check).
SCRATCH_DIR = "wip"


def check_identifier(value, name, pattern):
    """An identifier argument: never empty, never option-shaped, and matching its grammar."""
    if not value or value.startswith("-") or not pattern.fullmatch(value):
        raise ValueError(f"{name} is not a valid identifier")
    return value


class SiteFiles:
    """Reads files under one repository root and nothing outside it. A path is
    joined to the root and resolved with symlinks followed; one that lands
    outside the root, or that is itself a symlink, is refused. The number of
    files and bytes read is capped, so a manifest can't make a run read the disk."""

    def __init__(self, root):
        self.root = Path(os.path.realpath(root))
        self.read_files = {}
        self.total = 0

    def resolve(self, rel):
        if not rel or rel.startswith("/") or ".." in rel.split("/"):
            raise ValueError(f"path {rel!r} must be relative to the repository and stay inside it")
        joined = self.root / rel
        if joined.is_symlink():
            raise ValueError(f"path {rel!r} is a symlink, which a site never reads")
        real = Path(os.path.realpath(joined))
        if os.path.commonpath([str(real), str(self.root)]) != str(self.root):
            raise ValueError(f"path {rel!r} resolves outside the repository")
        return real

    def read(self, rel):
        """The file's text, or None when it doesn't exist."""
        path = self.resolve(rel)
        if not path.is_file():
            return None
        if len(self.read_files) >= MAX_SITE_FILES:
            raise ValueError("a site read more files than its cap allows")
        data = path.read_bytes()
        self.total += len(data)
        if self.total > MAX_SITE_BYTES:
            raise ValueError("a site read more bytes than its cap allows")
        text = data.decode("utf-8", "replace").replace("\r\n", "\n")
        self.read_files[rel] = text
        return text


def git_in(root, *args):
    out = subprocess.run(["git", "-C", str(root), "-c", "core.quotepath=off", *args], capture_output=True,
                         text=True, errors="replace", timeout=60)
    if out.returncode != 0:
        raise FetchError(f"git {args[0]} failed")
    return out.stdout


def work_tree_root(path):
    """The repository root a site reads from: `path` must be the top of a git work tree."""
    real = os.path.realpath(path)
    try:
        top = git_in(real, "rev-parse", "--show-toplevel").strip()
    except (FetchError, OSError, subprocess.TimeoutExpired):
        raise ValueError("--repo-path is not a git work tree")
    if os.path.realpath(top) != real:
        raise ValueError("--repo-path must be the top of its git work tree")
    return Path(real)


def repo_identity(root):
    """owner/name from the origin remote, or local/<directory> when there is none."""
    try:
        url = git_in(root, "remote", "get-url", "origin").strip()
    except (FetchError, OSError, subprocess.TimeoutExpired):
        url = ""
    m = re.search(r"[:/]([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+?)(?:\.git)?/?$", url)
    if m and REPO_ARG.fullmatch(f"{m.group(1)}/{m.group(2)}") and not {m.group(1), m.group(2)} & {".", ".."}:
        return f"{m.group(1)}/{m.group(2)}"
    name = re.sub(r"[^A-Za-z0-9._-]", "-", root.name) or "repo"
    return f"local/{name.strip('.') or 'repo'}"


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
            # Room for the criterion and the path header beside each hunk unit, so a
            # unit that fits on its own also fits in the slice it is sent in.
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


def koto_context(session, key):
    try:
        out = subprocess.run(["koto", "context", "get", session, key], capture_output=True, text=True,
                             errors="replace", timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout if out.returncode == 0 else None


def local_change_files(root, base, head):
    """Changed files between two commits with their patches, secret-looking paths
    left out. Every diff carries --no-ext-diff --no-textconv."""
    fields = git_in(root, *GIT_DIFF, "--name-status", "-z", "-M", base, head).split("\0")
    files, i = [], 0
    status_word = {"A": "added", "D": "removed", "M": "modified", "R": "renamed", "C": "copied", "T": "modified"}
    while i < len(fields) and fields[i]:
        code = fields[i]
        if code[0] in "RC":
            old, path, i = fields[i + 1], fields[i + 2], i + 3
        else:
            old, path, i = None, fields[i + 1], i + 2
        if SECRET_PATH.search(path) or (old and SECRET_PATH.search(old)):
            continue
        files.append({"path": path, "previous_path": old, "status": status_word.get(code[0], "modified"),
                      "additions": 0, "deletions": 0, "patch": None})
    for f in files[:MAX_SITE_FILES * 4]:
        if f["status"] == "removed":
            continue
        diff = git_in(root, *GIT_DIFF, "-U3", "-M", base, head, "--", f["path"])
        f["patch"] = (diff[diff.find("\n@@") + 1:] if "\n@@" in diff else "").rstrip("\n")
    return files


def resolve_commit(root, ref):
    sha = git_in(root, "rev-parse", "--verify", "--end-of-options", f"{ref}^{{commit}}").strip()
    if not HEAD_ARG.fullmatch(sha):
        raise FetchError("a commit could not be resolved")
    return sha


def assemble_site(args):
    """Read one site's artifact from disk into the dict its slicers cut. Raises
    ValueError for a bad argument and FetchError when an input can't be read."""
    site = check_site(args.site)
    root = work_tree_root(args.repo_path or ".")
    files = SiteFiles(root)
    art = {"site": site, "artifact_kind": SITE_ARTIFACT[site], "root": root, "repo": repo_identity(root)}
    if site in ("brief", "prd", "review-plan"):
        topic = check_identifier(args.topic, "--topic", TOPIC_ARG)
        art["subject_id"] = topic
    if site == "brief":
        text = files.read(f"docs/briefs/BRIEF-{topic}.md")
        if text is None:
            raise FetchError("the brief isn't on disk")
        art.update(frontmatter=frontmatter(text), sections=sections(text))
    elif site == "prd":
        text = files.read(f"docs/prds/PRD-{topic}.md")
        if text is None:
            raise FetchError("the PRD isn't on disk")
        art.update(frontmatter=frontmatter(text), sections=sections(text))
    elif site == "review-plan":
        manifest = files.read(f"{SCRATCH_DIR}/plan_{topic}_manifest.json")
        if manifest is None:
            raise FetchError("the plan manifest isn't on disk")
        try:
            data = json.loads(manifest)
        except ValueError:
            raise FetchError("the plan manifest isn't JSON")
        entries = data if isinstance(data, list) else (data.get("issues") or data.get("results") or [])
        pattern = re.compile(rf"{SCRATCH_DIR}/plan_{re.escape(topic)}_issue_[A-Za-z0-9_-]+\.md")
        art["issues"] = []
        for e in entries[:MAX_SITE_FILES]:
            rel = e.get("file") if isinstance(e, dict) else None
            if not isinstance(rel, str) or not pattern.fullmatch(rel):
                continue  # only the plan's own issue outlines are read
            body = files.read(rel)
            if body is None:
                continue
            title = e.get("title") if isinstance(e.get("title"), str) else rel
            issue_id = str(e.get("issue_id")) if e.get("issue_id") is not None else None
            art["issues"].append({"title": title, "issue_id": issue_id, "file": rel,
                                  "criteria": sections(body).get("Acceptance Criteria", "")})
    else:
        session = check_identifier(args.session, "--session", SESSION_ARG)
        if args.panel not in WORK_ON_PANELS:
            raise ValueError(f"--panel must be one of {WORK_ON_PANELS}")
        if args.issue:
            check_pr(args.issue)
        head = check_head(args.head) if args.head else resolve_commit(root, "HEAD")
        base = (koto_context(session, "impl_base") or "").strip()
        if not HEAD_ARG.fullmatch(base):
            raise FetchError("the session has no impl_base")
        if args.issue:
            out = subprocess.run(["gh", "issue", "view", str(int(args.issue)), "--json", "body", "-q", ".body"],
                                 capture_output=True, text=True, errors="replace", timeout=60, cwd=str(root))
            if out.returncode != 0:
                raise FetchError(f"gh issue view failed: {gh_hint('issues', out.stderr)}")
            criteria_text = out.stdout
            art["subject_id"] = f"issue-{int(args.issue)}"
        else:
            criteria_text = koto_context(session, "context.md") or ""
            art["subject_id"] = re.sub(r"[^a-z0-9-]", "-", session.lower()).strip("-")[-80:].lstrip("-") or "session"
        acs = sections(criteria_text).get("Acceptance Criteria") or criteria_text
        art.update(session=session, panel=args.panel, base=base, head=head, criteria=checklist(acs),
                   criteria_text=criteria_text, files=local_change_files(root, base, head))
    art["read_files"] = files.read_files
    return art


def artifact_sha(art, slices):
    """A hash of what was graded: every slice's hash, in order, and the files read."""
    h = hashlib.sha256()
    for kind in sorted(slices):
        for s in slices[kind]:
            h.update(s["sha256"].encode())
    for rel in sorted(art.get("read_files", {})):
        h.update(rel.encode() + b"\0" + hashlib.sha256(art["read_files"][rel].encode()).hexdigest().encode())
    return h.hexdigest()


PACKET_SCRIPT = REPO_ROOT / "scripts" / "review-packet.sh"


def seat_packet_args(art):
    """The review-packet.sh arguments the site's seats are commissioned with."""
    site, topic = art["site"], art.get("subject_id")
    if site == "brief":
        return ["doc", "--doc", f"docs/briefs/BRIEF-{topic}.md", "--format", "skills/brief/references/brief-format.md",
                "--extra", f"{SCRATCH_DIR}/brief_{topic}_context.md"]
    if site == "prd":
        return ["doc", "--doc", f"docs/prds/PRD-{topic}.md", "--format", "skills/prd/references/prd-format.md",
                "--extra", f"{SCRATCH_DIR}/prd_{topic}_scope.md"]
    if site == "review-plan":
        extras = [f"{SCRATCH_DIR}/plan_{topic}_analysis.md", f"{SCRATCH_DIR}/plan_{topic}_dependencies.md"]
        analysis = art.get("read_files", {}).get(f"{SCRATCH_DIR}/plan_{topic}_analysis.md") or ""
        m = re.search(r"^Path:\s*(docs/\S+\.md)\s*$", analysis, re.M)
        if m:
            extras.append(m.group(1))
        # The category seats also read every issue body, as the commissioning line says.
        extras += [issue["file"] for issue in art.get("issues", [])]
        out = ["doc", "--doc", f"{SCRATCH_DIR}/plan_{topic}_decomposition.md",
               "--format", "skills/review-plan/references/phases/phase-3-ac-discriminability.md"]
        for e in extras:
            out += ["--extra", e]
        return out
    return None  # work-on: built in seat_packet_bytes, which needs a criteria file


def seat_packet_bytes(art):
    """The byte size of the packet the site's seats read, or (None, reason)."""
    import tempfile
    if not PACKET_SCRIPT.is_file():
        return None, "no-packet-script"
    tmp = None
    try:
        args = seat_packet_args(art)
        if args is None:
            fd, tmp = tempfile.mkstemp(prefix="review-shadow-criteria.")
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(art.get("criteria_text") or "")
            args = ["code", "--session", art["session"], "--criteria", tmp]
        out = subprocess.run([str(PACKET_SCRIPT), *args], capture_output=True, text=True, errors="replace",
                             timeout=120, cwd=str(art["root"]))
        if out.returncode != 0:
            return None, f"packet-exit-{out.returncode}"
        path = Path(out.stdout.strip().splitlines()[-1]) if out.stdout.strip() else None
        if path is None or not path.is_file():
            return None, "packet-missing"
        size = path.stat().st_size
        path.unlink()
        return size, None
    except (OSError, subprocess.TimeoutExpired):
        return None, "packet-unavailable"
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


# --- Site grading ---------------------------------------------------------------
#
# Each shadowed seat and the decider criteria it is compared with. A seat
# verdict covers its whole checklist and a criterion one closed question, so the
# report compares them directionally; see the design's Decision 2.
SITE_SEATS = {
    "brief": {"content-quality": ("rs-011",), "structural-format": ("rs-012",)},
    "prd": {"clarity": ("rs-013",), "testability": ("rs-013",)},
    "review-plan": {"category-c": ("rs-014",)},
    "work-on:scrutiny": {"completeness": ("rs-015",)},
    "work-on:review": {"maintainer": ("rs-016", "rs-017")},
    "work-on:light": {"reviewer": ("rs-015", "rs-016", "rs-017")},
}
# Slices sent per run; the rest are unanswered with run-cap. 32 rather than 16
# because one slice per acceptance criterion is the PRD site's unit and a large
# PRD has more than 16 (this repository's own PRD for this feature has 19); at
# 16, rs-013 could never reach a verdict on it. The time cap still bounds a run.
SITE_SLICE_CAP = 32
# Slice meta that ties a slice to its source for attribution and never reaches a
# record (an issue id names what a private plan is about).
UNRECORDED_META = ("issue_id",)
SITE_TIME_CAP = 60.0  # seconds from the first send; later slices are run-cap
SEAT_MARKER = {"brief": re.compile(r"^\*\*Verdict:\*\*\s*(PASS|FAIL)\b", re.M),
               "prd": re.compile(r"^##\s*Verdict:\s*(PASS|FAIL)\b", re.M)}
SEAT_FILE = {"content-quality": "brief_{t}_phase4_content-quality.md",
             "structural-format": "brief_{t}_phase4_structural-format.md",
             "clarity": "prd_{t}_phase4_clarity.md", "testability": "prd_{t}_phase4_testability.md"}


def site_key(art):
    return f"work-on:{art['panel']}" if art["site"] == "work-on" else art["site"]


def seat_entry(seat, rule_ids, verdict, reason=None, attributed=None, blocking=0):
    return {"seat": seat, "rule_ids": list(rule_ids), "verdict": verdict, "reason": reason,
            "blocking_findings": blocking, "attributed": attributed or {}}


def hunk_spans(text):
    """(path, first new line, last new line) for each hunk in an ac-hunks or code-hunks
    slice, so a seat's finding can be tied to a slice without keeping its path."""
    spans, path = [], None
    for line in text.split("\n"):
        if line.startswith("--- "):
            path = line[4:].strip()
            continue
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
        if m and path:
            start = int(m.group(1))
            spans.append((path, start, start + max(int(m.group(2) or 1), 1) - 1))
    return spans


def slice_spans(s):
    if s["kind"] == "ac-hunks":
        return hunk_spans(s["inputs"]["hunks"])
    if s["kind"] == "code-hunks":
        return hunk_spans(f"--- {s['inputs']['path']}\n{s['inputs']['hunks']}")
    return []


def finding_in_slice(finding, s):
    path, lines = finding.get("path"), str(finding.get("lines") or "")
    m = re.match(r"^(\d+)(?:-(\d+))?$", lines)
    for p, a, b in slice_spans(s):
        if p != path:
            continue
        if not m:
            return True
        lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
        if lo <= b and hi >= a:
            return True
    return False


def read_doc_seats(art, files, slices):
    """The brief or PRD jury's verdicts, from the pinned verdict files its seats
    write. A verdict file older than the document it judged is stale."""
    seats, topic = [], art["subject_id"]
    doc = files.resolve(f"docs/briefs/BRIEF-{topic}.md" if art["site"] == "brief" else f"docs/prds/PRD-{topic}.md")
    for seat, rule_ids in SITE_SEATS[art["site"]].items():
        rel = f"{SCRATCH_DIR}/research/" + SEAT_FILE[seat].format(t=topic)
        text = files.read(rel)
        if text is None:
            seats.append(seat_entry(seat, rule_ids, "unreadable", "seat-verdict-missing"))
            continue
        m = SEAT_MARKER[art["site"]].search(text)
        if not m:
            seats.append(seat_entry(seat, rule_ids, "unreadable", "seat-verdict-unparsed"))
        elif files.resolve(rel).stat().st_mtime < doc.stat().st_mtime:
            seats.append(seat_entry(seat, rule_ids, "unreadable", "seat-verdict-stale"))
        else:
            seats.append(seat_entry(seat, rule_ids, "pass" if m.group(1) == "PASS" else "fail"))
    return seats


def read_plan_seat(art, files, slices):
    """/review-plan's category C verdict: fail when its review_result holds a
    category C finding. Each finding's affected_issue_ids tie it to the issue slices."""
    topic, rule_ids = art["subject_id"], SITE_SEATS["review-plan"]["category-c"]
    # Both files can exist when a loop-back round was followed by a proceed round
    # (or the reverse). The verdict on the plan as it stands carries the higher
    # review_result round; when the rounds are equal or absent, the proceed file.
    candidates = []
    for order, name in enumerate((f"plan_{topic}_review.md", f"plan_{topic}_review_loopback.md")):
        body = files.read(f"{SCRATCH_DIR}/{name}")
        if body is not None:
            m = re.search(r"^\s*round:\s*(\d+)\s*$", body, re.M)
            candidates.append((int(m.group(1)) if m else -1, -order, body))
    text = max(candidates)[2] if candidates else None
    if text is None:
        return [seat_entry("category-c", rule_ids, "unreadable", "seat-verdict-missing")]
    if not re.search(r"^\s*verdict:\s*\"?(proceed|loop-back)\"?\s*$", text, re.M):
        return [seat_entry("category-c", rule_ids, "unreadable", "seat-verdict-unparsed")]
    findings = re.split(r"^\s*-\s+(?=category:)", text, flags=re.M)[1:]
    c_findings = [f for f in findings if re.match(r"category:\s*\"?C\"?\s*$", f.split("\n", 1)[0].strip())]
    affected = set()
    for f in c_findings:
        m = re.search(r"affected_issue_ids:\s*\[([^\]]*)\]", f)
        if m:
            affected |= {x.strip().strip("\"'#") for x in m.group(1).split(",") if x.strip()}
    attributed = {s["id"]: (str(s["meta"].get("issue_id")) in affected) for s in slices.get("plan-ac-block", [])}
    verdict = "fail" if c_findings else "pass"
    return [seat_entry("category-c", rule_ids, verdict, attributed=attributed, blocking=len(c_findings))]


def criteria_hash(session):
    """The hash panel-scope.sh stamps as a verdict's ac_sha: context.md, a fixed
    separator, then plan.md, hashed as a git blob."""
    blob = (koto_context(session, "context.md") or "") + "\n--- plan ---\n" + (koto_context(session, "plan.md") or "")
    data = blob.encode("utf-8")
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def read_ledger_seats(art, slices, slice_kind_of):
    """The /work-on panel's verdicts from the session's verdict ledger, for the
    seats spawned this round (a full or rerun decision); a kept seat was paired
    when it ran, and a re-check judged only its own findings."""
    panel, session = art["panel"], art["session"]
    try:
        ledger = json.loads(koto_context(session, "verdict_ledger.json") or "")
        scope = json.loads(koto_context(session, f"{panel}_scope.json") or "")
    except ValueError:
        ledger, scope = None, None
    decisions = {d.get("seat"): d.get("decision") for d in (scope or {}).get("decisions", []) if isinstance(d, dict)}
    seats, ac_sha = [], None
    for seat, rule_ids in SITE_SEATS[f"work-on:{panel}"].items():
        if decisions.get(seat) not in ("full", "rerun"):
            continue
        entry = ((ledger or {}).get("seats") or {}).get(f"{panel}/{seat}")
        if ledger is None or entry is None:
            seats.append(seat_entry(seat, rule_ids, "unreadable", "seat-verdict-missing"))
            continue
        if entry.get("verdict") not in ("passed", "blocking"):
            seats.append(seat_entry(seat, rule_ids, "unreadable", "seat-verdict-unparsed"))
            continue
        if ac_sha is None:
            ac_sha = criteria_hash(session)
        # A ledger entry written before panel-scope.sh stamped ac_sha has none; its
        # judged_at still pins it to a commit, so it is compared on that alone.
        if entry.get("judged_at") != art["head"] or (entry.get("ac_sha") and entry["ac_sha"] != ac_sha):
            seats.append(seat_entry(seat, rule_ids, "unreadable", "seat-verdict-stale"))
            continue
        findings = [f for f in entry.get("findings") or [] if isinstance(f, dict)]
        kinds = sorted({slice_kind_of[r] for r in rule_ids if r in slice_kind_of})
        attributed = {s["id"]: any(finding_in_slice(f, s) for f in findings)
                      for kind in kinds for s in slices.get(kind, [])}
        seats.append(seat_entry(seat, rule_ids, "pass" if entry["verdict"] == "passed" else "fail",
                                attributed=attributed, blocking=len(findings)))
    return seats


def read_site_seats(art, slices, criteria):
    files = SiteFiles(art["root"])
    if art["site"] in ("brief", "prd"):
        return read_doc_seats(art, files, slices)
    if art["site"] == "review-plan":
        return read_plan_seat(art, files, slices)
    return read_ledger_seats(art, slices, {c["rule_id"]: c["slice_kind"] for c in criteria["criteria"]})


def declared_public(root):
    """True only when the repository's CLAUDE.md declares itself public: a site
    sends drafts and local commits, so an undeclared repository counts as private."""
    p = Path(root) / "CLAUDE.md"
    text = p.read_text(encoding="utf-8", errors="replace") if p.is_file() and not p.is_symlink() else ""
    return bool(re.search(r"^##\s*Repo Visibility:\s*Public\b", text, re.M | re.I))


def slice_has_private_term(s, terms):
    if not terms:
        return False
    text = "\n".join(s["inputs"].values())
    low = text.lower()
    for t in terms:
        folded, exact = term_forms(t)
        if any(f in low for f in folded) or any(e in text for e in exact):
            return True
    return False


def grade_site(criteria, art, slices, unmatched, send, terms, gate_reason=None, clock=None):
    """Every site criterion over its slices, one slice at a time so the caps hold.
    `gate_reason` (private-repo, not-opted-in, no-key) marks everything unanswered
    without sending. Returns the record body."""
    import time
    clock = clock or time.monotonic
    kind = art["artifact_kind"]
    wanted = {r for rids in SITE_SEATS[site_key(art)].values() for r in rids}
    crit = [c for c in active(criteria, kind) if c["rule_id"] in wanted]
    one = dict(criteria, criteria=crit)
    verdicts, rounds, unread, sent, started = [], [], 0, 0, None
    for sk in sorted({c["slice_kind"] for c in crit}):
        rule_ids = [c["rule_id"] for c in crit if c["slice_kind"] == sk]
        for s in slices.get(sk, []):
            reason = gate_reason
            if reason is None and slice_has_private_term(s, terms):
                reason = "private-term"  # after redaction (in make_slice), before the bound
            if reason is None and not s["over_bound"]:
                if sent >= SITE_SLICE_CAP or (started is not None and clock() - started > SITE_TIME_CAP):
                    reason = "run-cap"
            if reason is not None:
                verdicts += [{"rule_id": r, "slice": s["id"], "verdict": "unanswered", "observer": "jev",
                              "probabilities": None, "reason": reason} for r in rule_ids]
                continue
            if started is None:
                started = clock()
            if not s["over_bound"]:
                sent += 1
            v, r, u = run_jev(one, {sk: [s]}, send, True, kind)
            verdicts += v
            rounds += r
            unread += u
    for u in unmatched:
        verdicts += [{"rule_id": c["rule_id"], "slice": u["unit"], "verdict": "unanswered", "observer": "jev",
                      "probabilities": None, "reason": u["reason"]} for c in crit if c["slice_kind"] == "ac-hunks"]
    rows = []
    for c in crit:
        vs = [v["verdict"] for v in verdicts if v["rule_id"] == c["rule_id"]]
        rows.append({"rule_id": c["rule_id"], "verdict": worst(vs), "slices": len(vs)})
    if gate_reason:
        status, why = "not-graded", gate_reason
    else:
        jev_slices = sum(len(slices.get(sk, [])) for sk in {c["slice_kind"] for c in crit})
        status, why = run_status(rows, rounds, jev_slices, False, verdicts)
    all_slices = [dict({k: s[k] for k in ("id", "kind", "bytes", "sha256", "over_bound")},
                       **{k: v for k, v in s["meta"].items() if k not in UNRECORDED_META})
                  for sk in sorted(slices) for s in slices[sk]]
    return {"mode": "batched", "slices": all_slices, "verdicts": verdicts, "criteria": rows, "rounds": rounds,
            "models": sorted({r["model"] for r in rounds if r["model"]}), "unread_usage_attempts": unread,
            "tokens": {"input": sum(r["input_tokens"] or 0 for r in rounds),
                       "output": sum(r["output_tokens"] or 0 for r in rounds)},
            "status": status, "not_graded_reason": why, "unanswered_units": unmatched}


def site_gate(root):
    """(reason, transport). The reason nothing may be sent, or None with a
    transport when the run may send. Checked in this order, so the most
    fundamental refusal is the one recorded: the repository isn't declared public,
    the user hasn't opted in with REVIEW_SHADOW_SITES=1, or there is no key."""
    if not declared_public(root):
        return "private-repo", None
    if os.environ.get("REVIEW_SHADOW_SITES") != "1":
        return "not-opted-in", None
    key = os.environ.get("JEV_API_KEY") or os.environ.get("KOTO_DECIDER_API_KEY")
    if not key:
        return "no-key", None
    return None, https_transport(JEV_ENDPOINT, key, 20.0)


def cmd_site(args, criteria):
    """Shadow one site. Every failure after the arguments are checked prints a
    reason and exits 0: the caller never reads this command's result."""
    try:
        art = assemble_site(args)
        slices, unmatched = build_site_slices(art)
    except (FetchError, OSError, subprocess.TimeoutExpired) as e:
        print(f"review-shadow: site {args.site}: nothing graded: {e}", file=sys.stderr)
        return 0
    if args.measure:
        wanted = {r for rids in SITE_SEATS[site_key(art)].values() for r in rids}
        kinds = {c["slice_kind"] for c in criteria["criteria"] if c["rule_id"] in wanted}
        for kind in (k for k in slices if k in kinds):
            for s in slices[kind]:
                extra = " over-bound" if s["over_bound"] else ""
                dropped = s["meta"].get("dropped")
                print(f"slice {s['id']} {s['bytes']}{extra}" + (f" dropped={dropped}" if dropped else ""))
        for u in unmatched:
            print(f"unit {u['unit']} unanswered {u['reason']}")
        size, why = seat_packet_bytes(art)
        print(f"seat-packet {size}" if size is not None else f"seat-packet unavailable {why}")
        return 0
    try:
        seats = read_site_seats(art, slices, criteria)
        if not seats:
            print(f"review-shadow: site {args.site}: no seat ran this round; nothing recorded")
            return 0
        gate, send = site_gate(art["root"])
        terms = load_private_terms(os.environ.get("REVIEW_SHADOW_PRIVATE_TERMS"))
        body = grade_site(criteria, art, slices, unmatched, send, terms, gate)
        rec = new_site_record(art["repo"], art["site"], art["subject_id"], artifact_sha(art, slices),
                              panel=art.get("panel"), in_sample=bool(args.in_sample), seats=seats, **body)
        path = write_site_record(store_home(), rec)
    except (ConfigError, FetchError, OSError, ValueError, subprocess.TimeoutExpired) as e:
        print(f"review-shadow: site {args.site}: nothing recorded: {e}", file=sys.stderr)
        return 0
    line = f"{path} status={rec['status']}"
    if rec.get("not_graded_reason"):
        line += f" reason={rec['not_graded_reason']}"
    if rec.get("not_graded_reason") == "not-opted-in":
        line += " (decider not asked: set REVIEW_SHADOW_SITES=1 to collect decider verdicts)"
    print(line)
    return 0


def cmd_grade(args, criteria):
    repo, pr, head = check_repo(args.repo), check_pr(args.pr), check_head(args.head)
    panel_run = check_panel_run(args.panel_run)
    if args.body_at:
        try:
            parse_time(args.body_at)
        except ValueError:
            raise ValueError("--body-at must be a UTC time like 2026-09-28T07:25:00Z")
    known = {c["rule_id"] for c in criteria["criteria"]}
    unknown = [r for r in args.enable or [] if r not in known]
    if unknown:
        raise ValueError(f"--enable names unknown criteria: {', '.join(unknown)}")
    criteria = dict(criteria, _enabled=list(args.enable or []))
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
                     criteria_enabled=[c["rule_id"] for c in active(criteria)],
                     reasons=pr_data["reasons"] + (["files-truncated"] if pr_data["files_truncated"] else []),
                     **body)
    path = write_record(home, rec)
    reasons = ",".join(rec["reasons"] + ([rec["not_graded_reason"]] if rec.get("not_graded_reason") else []))
    print(f"{path} status={rec['status']} in_sample={str(rec['in_sample']).lower()} "
          f"tokens={rec['tokens']['input']}+{rec['tokens']['output']}" + (f" reasons={reasons}" if reasons else ""))
    return 0


# --- Panel outcomes ----------------------------------------------------------

DISPOSITIONS = ("upheld", "narrowed", "dismissed", "unknown")
FINDING_CODE = re.compile(r"[a-z0-9-]{1,32}")


def parse_finding(text, categories):
    """category:disposition[:inferred][:code] -> a finding. No free text: the store
    is archived, and a note about a private pull request would leave the host."""
    parts = text.split(":")
    if len(parts) < 2 or len(parts) > 4:
        raise ValueError("--finding is category:disposition[:inferred][:code]")
    cat, disp, rest = parts[0], parts[1], parts[2:]
    if cat not in categories["categories"]:
        raise ValueError(f"unknown finding category {cat!r}")
    if disp not in DISPOSITIONS:
        raise ValueError(f"disposition must be one of {DISPOSITIONS}")
    source = "recorded"
    if rest and rest[0] == "inferred":
        source, rest = "inferred", rest[1:]
    code = None
    if rest:
        if not FINDING_CODE.fullmatch(rest[0]):
            raise ValueError("a finding code is at most 32 characters from [a-z0-9-]")
        code = rest[0]
    return {"category": cat, "disposition": disp, "disposition_source": source, "code": code}


def outcome_path(home, repo, pr, head, panel_run):
    return head_dir(home, "outcomes", repo, pr, head) / (panel_run.replace(":", "_") + ".json")


def record_outcome(home, repo, pr, head, panel_kind, panel_run, findings):
    """Write (or replace) the outcome of one panel run on one head. A head with no
    grade record gets a not-graded one, so a per-head count sees heads the grader
    never saw; grade records still waiting for a panel run id get this one."""
    out = {"schema": "review-shadow/outcome/v1", "repo": repo, "pr": pr, "head_sha": head,
           "panel_kind": panel_kind, "panel_run_id": panel_run, "recorded_at": now_iso(),
           "driver_session_id": os.environ.get("CLAUDE_CODE_SESSION_ID") or None,
           "result": "blocked" if findings else "clean", "findings": findings}
    write_private(outcome_path(home, repo, pr, head, panel_run), out, home)
    rdir = head_dir(home, "records", repo, pr, head)
    records = sorted(rdir.glob("*.json")) if rdir.exists() else []
    if not records:
        write_record(home, new_record(repo, pr, head, panel_run_id=panel_run, panel_kind=panel_kind,
                                      in_sample=False, diff_kind=None, mode=None, status="not-graded",
                                      not_graded_reason="outcome-without-grade", tokens={"input": 0, "output": 0},
                                      verdicts=[], criteria=[], rounds=[], unread_usage_attempts=0))
    for path in records:
        rec = json.loads(path.read_text(encoding="utf-8"))
        if rec.get("panel_run_id") is None:
            rec["panel_run_id"] = panel_run
            rec["panel_kind"] = rec.get("panel_kind") or panel_kind
            write_private(path, rec, home)
    return out


def cmd_outcome(args, criteria):
    repo, pr, head = check_repo(args.repo), check_pr(args.pr), check_head(args.head)
    if not args.panel_run or not check_panel_run(args.panel_run):
        raise ValueError("--panel-run is required")
    categories = load_categories(criteria)
    findings = [parse_finding(f, categories) for f in args.finding or []]
    home = store_home()
    out = record_outcome(home, repo, pr, head, args.panel_kind, args.panel_run, findings)
    print(f"{outcome_path(home, repo, pr, head, args.panel_run)} result={out['result']} findings={len(findings)}")
    return 0


# --- Report ------------------------------------------------------------------

def binom_upper(k, n, alpha=0.05):
    """Exact one-sided upper bound for a binomial proportion (Clopper-Pearson)."""
    from math import comb
    if n == 0:
        return None
    if k >= n:
        return 1.0
    lo, hi = 0.0, 1.0
    for _ in range(60):
        mid = (lo + hi) / 2
        cdf = sum(comb(n, i) * mid ** i * (1 - mid) ** (n - i) for i in range(k + 1))
        lo, hi = (mid, hi) if cdf > alpha else (lo, mid)
    return lo


def load_store(home):
    records, outcomes = [], []
    for sub, dest in (("records", records), ("outcomes", outcomes)):
        root = home / sub
        if root.exists():
            for p in sorted(root.rglob("*.json")):
                dest.append(json.loads(p.read_text(encoding="utf-8")))
    return records, outcomes


def panel_state(outcomes):
    """blocked, clean or undetermined, and the upheld categories, over every outcome
    of one panel kind on one head."""
    upheld, unknown = [], False
    for o in outcomes:
        for f in o["findings"]:
            if f["disposition"] in ("upheld", "narrowed"):
                upheld.append(f["category"])
            elif f["disposition"] == "unknown":
                unknown = True
    if upheld:
        return "blocked", upheld
    return ("undetermined" if unknown else "clean"), []


def rates(rows):
    """Agreement figures over scored rows of (outcome, blocked, zero_slice_pass).

    outcome is pass, fail or none (escape or unanswered). No verdict counts as a
    fail, so it agrees with a blocked panel and dissents from a clean one, but it
    is counted in its own columns and never folded into fail."""
    n = len(rows)
    passes = sum(1 for o, b, z in rows if o == "pass")
    blocked = sum(1 for o, b, z in rows if b)
    clean = n - blocked
    fp = sum(1 for o, b, z in rows if o == "pass" and b)
    agree = sum(1 for o, b, z in rows if (o == "pass") != b)
    fail_clean = sum(1 for o, b, z in rows if o == "fail" and not b)
    none_clean = sum(1 for o, b, z in rows if o == "none" and not b)
    none_all = sum(1 for o, b, z in rows if o == "none")

    def ratio(a, d):
        return None if d == 0 else a / d
    return {"n": n, "agreement": ratio(agree, n), "unanimous_passes": passes, "false_passes": fp,
            "false_pass_rate": ratio(fp, passes), "false_pass_upper95": binom_upper(fp, passes),
            "blocked": blocked, "miss_rate": ratio(fp, blocked), "clean": clean,
            "fail_on_clean": fail_clean, "no_verdict_on_clean": none_clean,
            "no_verdict": none_all, "no_verdict_rate": ratio(none_all, n),
            "zero_slice_passes": sum(1 for o, b, z in rows if o == "pass" and z)}


STATUS_OUTCOME = {"unanimous-pass": "pass", "dissent": "fail", "inconclusive": "none"}
VERDICT_OUTCOME = {"pass": "pass", "fail": "fail", "escape": "none", "unanswered": "none"}


def rollups(kind, dk):
    """The four groups a head counts in: its panel kind and diff kind, each rolled up."""
    return ((kind, dk), (kind, "all"), ("all", dk), ("all", "all"))


def site_rates(rows):
    """Figures over rows of (decider outcome, seat verdict, attributed) for one site
    seat or criterion. The comparison is directional: a seat verdict covers its
    whole checklist and a criterion one closed question, so a seat block the
    decider passed is a false pass only when a seat finding falls in a graded
    slice; the rest are unattributed and count only toward the upper bound."""
    n = len(rows)
    passes = sum(1 for o, s, a in rows if o == "pass")
    agree = sum(1 for o, s, a in rows if (o, s) in (("pass", "pass"), ("fail", "fail")))
    attributed = sum(1 for o, s, a in rows if o == "pass" and s == "fail" and a)
    unattributed = sum(1 for o, s, a in rows if o == "pass" and s == "fail" and not a)
    return {"n": n, "agreement": None if n == 0 else agree / n, "decider_passes": passes,
            "decider_only_fails": sum(1 for o, s, a in rows if o == "fail" and s == "pass"),
            "attributed_false_passes": attributed, "unattributed_seat_blocks": unattributed,
            "false_pass_upper95": binom_upper(attributed + unattributed, passes),
            "no_verdict": sum(1 for o, s, a in rows if o == "none")}


def site_report_data(site_records, criteria):
    """Per-site and per-criterion agreement between seats and the decider, out-of-sample
    and in-sample apart, from the latest record per site, subject and artifact."""
    latest = {}
    for r in site_records:
        s = r["subject"]
        key = (r["repo"], s["site"], r.get("panel"), s["subject_id"], s["artifact_sha"], bool(r.get("in_sample")))
        if key not in latest or r["recorded_at"] > latest[key]["recorded_at"]:
            latest[key] = r
    slice_kind_of = {c["rule_id"]: c["slice_kind"] for c in criteria["criteria"]}

    def attributed_in(seat, kinds):
        # Attribution is per slice; a criterion is charged only with findings in
        # the slices it graded (an ac-hunks criterion never with a code-hunks one).
        return any(v for k, v in seat.get("attributed", {}).items()
                   if any(k.startswith(f"{kind}-") for kind in kinds))

    out = {}
    for pop, in_sample in (("out-of-sample", False), ("in-sample", True)):
        seats, crits, not_graded, unreadable = {}, {}, {}, {}
        for key, r in sorted(latest.items()):
            if key[5] != in_sample:
                continue
            site = r["subject"]["site"] + (f":{r['panel']}" if r.get("panel") else "")
            if r.get("status") == "not-graded":
                not_graded[site] = not_graded.get(site, 0) + 1
                continue
            verdict_of = {c["rule_id"]: VERDICT_OUTCOME[c["verdict"]] for c in r.get("criteria", [])}
            for seat in r.get("seats", []):
                if seat["verdict"] not in ("pass", "fail"):
                    per_site = unreadable.setdefault(site, {})
                    per_site[seat["seat"]] = per_site.get(seat["seat"], 0) + 1
                    continue
                outs = [verdict_of[rid] for rid in seat["rule_ids"] if rid in verdict_of]
                if not outs:
                    continue
                o = "fail" if "fail" in outs else ("pass" if all(x == "pass" for x in outs) else "none")
                kinds = {slice_kind_of.get(rid) for rid in seat["rule_ids"]}
                seats.setdefault(site, {}).setdefault(seat["seat"], []).append(
                    (o, seat["verdict"], attributed_in(seat, kinds)))
                for rid in seat["rule_ids"]:
                    if rid in verdict_of:
                        crits.setdefault(site, {}).setdefault(rid, []).append(
                            (verdict_of[rid], seat["verdict"], attributed_in(seat, {slice_kind_of.get(rid)})))
        out[pop] = {"seats": {site: {k: site_rates(v) for k, v in by.items()} for site, by in seats.items()},
                    "criteria": {site: {k: site_rates(v) for k, v in by.items()} for site, by in crits.items()},
                    "not_graded": not_graded, "seat_unreadable": unreadable}
    out["tokens"] = {"input": sum(r.get("tokens", {}).get("input", 0) for r in site_records),
                     "output": sum(r.get("tokens", {}).get("output", 0) for r in site_records),
                     "records": len(site_records)}
    return out


def report_data(home, criteria, categories, mode="batched"):
    records, outcomes = load_store(home)
    # Site records have no pull request or head; the pull-request tables, the
    # mode comparison and the spend line read pull-request records only, and
    # the site tables read the rest.
    site_records = [r for r in records if is_site_record(r)]
    records = [r for r in records if not is_site_record(r)]
    by_head_kind = {}
    for o in outcomes:
        by_head_kind.setdefault((o["repo"], o["pr"], o["head_sha"], o["panel_kind"]), []).append(o)
    # A head graded after its outcome was recorded also has the placeholder the
    # outcome wrote; the grade supersedes it in every population.
    graded = {(r["repo"], r["pr"], r["head_sha"]) for r in records if r.get("status") != "not-graded"}
    latest = {}
    for r in records:
        if r.get("not_graded_reason") == "outcome-without-grade" and (r["repo"], r["pr"], r["head_sha"]) in graded:
            continue
        key = (r["repo"], r["pr"], r["head_sha"], bool(r.get("in_sample")))
        if r.get("status") != "not-graded" and r.get("mode") != mode:
            continue
        if key not in latest or r["recorded_at"] > latest[key]["recorded_at"]:
            latest[key] = r
    cats = categories["categories"]
    observer = {c["rule_id"]: c["observer"] for c in criteria["criteria"]}
    result = {"mode": mode, "populations": {}}
    for pop, in_sample in (("out-of-sample", False), ("in-sample", True)):
        groups, per_crit, not_graded, undetermined, false_passes, coverage = {}, {}, {}, {}, [], {}
        for (repo, pr, head, kind), outs in sorted(by_head_kind.items()):
            rec = latest.get((repo, pr, head, in_sample))
            if rec is None:
                continue
            dk = rec.get("diff_kind") or "unknown"
            state, upheld = panel_state(outs)
            ran = {c["rule_id"] for c in rec.get("criteria", [])}
            for cat in upheld:
                entry = cats.get(cat, {"class": "open-judgment"})
                cls = entry["class"]
                if cls == "covered" and not ran & set(entry.get("rule_ids", [])):
                    cls = "closed-uncovered"  # its criteria didn't run on this head
                for g in rollups(kind, dk):
                    coverage.setdefault(g, {"covered": 0, "closed-uncovered": 0, "open-judgment": 0})[cls] += 1
            if rec["status"] == "not-graded":
                for g in rollups(kind, dk):
                    not_graded[g] = not_graded.get(g, 0) + 1
                continue
            if state == "undetermined":
                for g in rollups(kind, dk):
                    undetermined[g] = undetermined.get(g, 0) + 1
                continue
            outcome = STATUS_OUTCOME[rec["status"]]
            zero = any(c["slices"] == 0 and observer.get(c["rule_id"]) == "jev" for c in rec["criteria"])
            for g in rollups(kind, dk):
                groups.setdefault(g, []).append((outcome, state == "blocked", zero))
            if outcome == "pass" and state == "blocked":
                false_passes.append({"repo": repo, "pr": pr, "head": head, "panel_kind": kind, "upheld": upheld})
            for crow in rec["criteria"]:
                blocked_c = any(crow["rule_id"] in cats.get(cat, {}).get("rule_ids", []) for cat in upheld)
                row = (VERDICT_OUTCOME[crow["verdict"]], blocked_c, crow["slices"] == 0)
                for k, d in rollups(kind, dk):
                    per_crit.setdefault((k, d, crow["rule_id"]), []).append(row)
        result["populations"][pop] = {
            "groups": {f"{k}|{d}": rates(rows) for (k, d), rows in groups.items()},
            "criteria": {f"{k}|{d}|{r}": rates(rows) for (k, d, r), rows in per_crit.items()},
            "not_graded": {f"{k}|{d}": v for (k, d), v in not_graded.items()},
            "undetermined": {f"{k}|{d}": v for (k, d), v in undetermined.items()},
            "coverage": {f"{k}|{d}": v for (k, d), v in coverage.items()},
            "false_passes": false_passes}
    result["tokens"] = {"input": sum(r.get("tokens", {}).get("input", 0) for r in records),
                        "output": sum(r.get("tokens", {}).get("output", 0) for r in records),
                        "records": len(records)}
    diffs = []
    both = {}
    for r in records:
        if r.get("mode") in ("batched", "unbatched"):
            both.setdefault((r["repo"], r["pr"], r["head_sha"]), {})[r["mode"]] = r
    for (repo, pr, head), modes in sorted(both.items()):
        if len(modes) == 2:
            a = {c["rule_id"]: c["verdict"] for c in modes["batched"]["criteria"]}
            b = {c["rule_id"]: c["verdict"] for c in modes["unbatched"]["criteria"]}
            for rid in sorted(set(a) | set(b)):
                if a.get(rid) != b.get(rid):
                    diffs.append({"repo": repo, "pr": pr, "head": head, "rule_id": rid,
                                  "batched": a.get(rid), "unbatched": b.get(rid)})
    result["mode_differences"] = diffs
    result["sites"] = site_report_data(site_records, criteria)
    return result


def print_site_report(sites):
    print("\n# Review sites in decider shadow\n")
    print("A seat verdict covers the seat's whole checklist and a decider verdict one closed criterion, so a "
          "seat block the decider passed is counted as a false pass only when a seat finding falls in a "
          "graded slice; the 95% upper bound counts every such block.\n")
    cols = ("| {} | runs | agreement | decider passes | decider-only fails | attributed false passes "
            "| unattributed seat blocks | false-pass 95% upper bound | no verdict |")
    for pop in ("out-of-sample", "in-sample"):
        p = sites[pop]
        label = "the test" if pop == "out-of-sample" else "manual re-grades; not the test"
        print(f"## {pop} ({label})\n")
        if not p["seats"] and not p["not_graded"] and not p["seat_unreadable"]:
            print("No site runs.\n")
            continue
        for title, key, name in (("Per seat", "seats", "site | seat"), ("Per criterion", "criteria", "site | criterion")):
            print(f"{title}:\n")
            print(cols.format(name))
            print("|---|---|---|---|---|---|---|---|---|---|")
            for a, b, g in ((a, b, g) for a in sorted(p[key]) for b, g in sorted(p[key][a].items())):
                print(f"| {a} | {b} | {g['n']} | {_pct(g['agreement'])} | {g['decider_passes']} "
                      f"| {g['decider_only_fails']} | {g['attributed_false_passes']} | {g['unattributed_seat_blocks']} "
                      f"| {_pct(g['false_pass_upper95'])} | {g['no_verdict']}/{g['n']} |")
            print()
        not_graded = ", ".join(f"{k} {v}" for k, v in sorted(p["not_graded"].items())) or "none"
        unreadable = ", ".join(f"{site} {seat} {v}" for site in sorted(p["seat_unreadable"])
                               for seat, v in sorted(p["seat_unreadable"][site].items())) or "none"
        print(f"Runs not graded (no decider verdict), by site: {not_graded}.")
        print(f"Seat verdicts unreadable, by seat: {unreadable}.\n")
    t = sites["tokens"]
    print(f"Site Jev spend: {t['input']} input and {t['output']} output tokens over {t['records']} records.")


def _pct(x):
    return "n/a" if x is None else f"{100 * x:.0f}%"


def print_report(data):
    print(f"Review shadow trial report (Jev mode: {data['mode']}). Nothing here approves a panel.")
    print("No verdict (an escape or an unanswered question) counts as a fail and has its own columns.\n")
    for pop, p in data["populations"].items():
        label = "the test" if pop == "out-of-sample" else "graded after the panel's outcome was known; not the test"
        print(f"## {pop} ({label})\n")
        if not p["groups"] and not p["not_graded"] and not p["undetermined"]:
            print("No heads.\n")
            continue
        print("| panel kind | diff kind | heads | agreement | unanimous passes | false passes | false-pass rate "
              "| 95% upper bound | miss rate | fail on clean | no verdict on clean | no verdict (all heads) "
              "| passes on zero slices | not graded | undetermined |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        keys = sorted(set(p["groups"]) | set(p["not_graded"]) | set(p["undetermined"]))
        for key in keys:
            k, d = key.split("|")
            g = p["groups"].get(key) or rates([])
            print(f"| {k} | {d} | {g['n']} | {_pct(g['agreement'])} | {g['unanimous_passes']} | {g['false_passes']} "
                  f"| {_pct(g['false_pass_rate'])} | {_pct(g['false_pass_upper95'])} | {_pct(g['miss_rate'])} "
                  f"| {g['fail_on_clean']}/{g['clean']} | {g['no_verdict_on_clean']}/{g['clean']} "
                  f"| {g['no_verdict']}/{g['n']} | {g['zero_slice_passes']} "
                  f"| {p['not_graded'].get(key, 0)} | {p['undetermined'].get(key, 0)} |")
        print("\nPer criterion (the panel counts as blocked for a criterion only on an upheld finding in its group):\n")
        print("| panel kind | diff kind | criterion | heads | agreement | passes | false passes | 95% upper bound "
              "| miss rate | fail on clean | no verdict on clean | no verdict (all heads) | passes on zero slices |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for key in sorted(p["criteria"]):
            k, d, r = key.split("|")
            g = p["criteria"][key]
            print(f"| {k} | {d} | {r} | {g['n']} | {_pct(g['agreement'])} | {g['unanimous_passes']} "
                  f"| {g['false_passes']} | {_pct(g['false_pass_upper95'])} | {_pct(g['miss_rate'])} "
                  f"| {g['fail_on_clean']}/{g['clean']} | {g['no_verdict_on_clean']}/{g['clean']} "
                  f"| {g['no_verdict']}/{g['n']} | {g['zero_slice_passes']} |")
        print("\nCoverage of upheld blocking findings (a flip can only ever be safe for the covered share):\n")
        print("| panel kind | diff kind | covered | closed, uncovered | open judgment |")
        print("|---|---|---|---|---|")
        for key in sorted(p["coverage"]):
            k, d = key.split("|")
            c = p["coverage"][key]
            total = sum(c.values())
            print(f"| {k} | {d} | " + " | ".join(f"{c[x]} ({_pct(c[x] / total if total else None)})"
                                                  for x in ("covered", "closed-uncovered", "open-judgment")) + " |")
        if p["false_passes"]:
            print("\nFalse passes:\n")
            for fp in p["false_passes"]:
                print(f"- {fp['repo']}#{fp['pr']} at {fp['head'][:12]} ({fp['panel_kind']}): "
                      f"upheld {', '.join(fp['upheld'])}")
        print()
    if data["mode_differences"]:
        print("## Verdicts that differ between batched and unbatched runs\n")
        for d in data["mode_differences"]:
            print(f"- {d['repo']}#{d['pr']} {d['rule_id']}: batched {d['batched']}, unbatched {d['unbatched']}")
        print()
    t = data["tokens"]
    print(f"Trial Jev spend: {t['input']} input and {t['output']} output tokens over {t['records']} records.")
    if "sites" in data:
        print_site_report(data["sites"])


def cmd_report(args, criteria):
    data = report_data(store_home(), criteria, load_categories(criteria), mode=args.mode)
    if args.json:
        print(json.dumps(data, indent=1, sort_keys=True))
    else:
        print_report(data)
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
    gp.add_argument("--enable", action="append", metavar="RULE_ID",
                    help="also grade a criterion shipped off (rs-009, rs-010); repeatable")
    op = sub.add_parser("outcome", help="record a panel's outcome for one pull request and head")
    op.add_argument("--repo", required=True)
    op.add_argument("--pr", required=True)
    op.add_argument("--head", required=True)
    op.add_argument("--panel-kind", required=True, choices=PANEL_KINDS)
    op.add_argument("--panel-run", required=True)
    op.add_argument("--finding", action="append",
                    help="category:disposition[:inferred][:code]; repeat per blocking finding; none means clean")
    rp = sub.add_parser("report", help="print agreement between the grader and the panels")
    rp.add_argument("--mode", choices=("batched", "unbatched"), default="batched")
    rp.add_argument("--json", action="store_true")
    sp = sub.add_parser("scan", help="run the script criteria over the current branch; writes nothing")
    sp.add_argument("--base", default="origin/main")
    sp.add_argument("--body-file")
    sp.add_argument("--private-terms")
    st = sub.add_parser("site", help="shadow one review site's seats with the decider (--measure: sizes only)")
    st.add_argument("site", choices=SITES)
    st.add_argument("--topic", help="the topic slug (brief, prd, review-plan)")
    st.add_argument("--session", help="the /work-on koto session (work-on)")
    st.add_argument("--panel", choices=WORK_ON_PANELS, help="the /work-on panel (work-on)")
    st.add_argument("--head", help="the commit the /work-on diff ends at (default HEAD)")
    st.add_argument("--issue", help="read /work-on's acceptance criteria from this issue")
    st.add_argument("--repo-path", help="the repository root (default: the current directory)")
    st.add_argument("--measure", action="store_true", help="print slice and seat-packet sizes; send and write nothing")
    st.add_argument("--in-sample", action="store_true", help="mark the record in-sample (a manual re-grade)")
    args = ap.parse_args(argv)
    commands = {"scan": cmd_scan, "grade": cmd_grade, "outcome": cmd_outcome, "report": cmd_report,
                "site": cmd_site}
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
