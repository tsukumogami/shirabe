#!/usr/bin/env python3
"""slice.py -- print the units one Jev document criterion grades.

Usage:
  slice.py <criterion> <format> --doc <path> --commit <sha>

Reads the document's committed blob at <sha> from the repository the document
lives in, and nothing else: not the working tree, not a file beside it, not
the directory the command runs from. It prints one JSON line per unit,
{"key", "text", "document", "section"}, where `document` is the format,
`section` the criterion's section key and `key` `<section>/<ordinal>`. Units
come in the order they start in the document; a contradiction pair is ordered
by its first passage, then its second. Every line is built here, so text in
the document can't add a unit, change a key or print a line of its own.

The eight criterion and format pairs, and what each unit is, are in PAIRS
below and in references/jev-criteria.md, which holds each pair's written case.
A whole unit is printed whole, whatever its size: koto records one over the
byte budget as `over_budget`. A cut unit is cut here, so it never goes over
BUDGET. The cap is the template's `max_units`: this script prints every unit
and koto grades the first `max_units` of them.

The text functions are importable: scripts/jev-criteria/jev_criteria.py
measures documents and checks fixture cases with the same code.

Exit codes: 0 printed (possibly nothing), 2 refused or could not read. A
refusal prints one fixed line on stderr and nothing on stdout.

Standard library only.
"""

import json
import os
import re
import subprocess
import sys

PROG = "slice.py"
BUDGET = 2560
COMMIT = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?$")
REL_PATH = re.compile(r"^docs/[A-Za-z0-9._/+@-]+\.md$")

FENCE = re.compile(r"^\s*(```|~~~)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
ITEM = re.compile(r"^([-*+]|\d+[.)])[ \t]+\S")
ANY_ITEM = re.compile(r"^(\s*)([-*+]|\d+[.)])[ \t]+\S")
NUMBERED = re.compile(r"^(\d+)[.)][ \t]+")
FIELD_LINE = re.compile(r"^\*\*[^*\n]+:\*\*")
TABLE_ROW = re.compile(r"^\s*\|")
TABLE_RULE = re.compile(r"^\s*\|?[\s:|-]+\|?\s*$")
TERM = re.compile(r"`([^`\n]+)`")
NUMBER = re.compile(r"(?<![\w.,/-])\d+(?:[.,]\d+)*(?![\w/-])")
# A claim number is at most four digits, so the label that echoes it stays
# inside the budget whatever a bullet writes.
CLAIM_REF = re.compile(r"\bclaims?\s*#?\s*(\d{1,4})\b", re.IGNORECASE)
CLAIM_PARA = re.compile(r"^(?:\*\*)?claim\s+(\d+)\b", re.IGNORECASE)

CUT = " [cut]"
SECTION_CONTINUES = "[section continues]"
NO_CLAIM = "[no claim named]"
# A contradiction pair's passages are each clipped to this; a falsifier and its
# claim to the next two. With the labels they stay under BUDGET.
PAIR_SIDE = 1200
FALSIFIER_SIDE = 1500
CLAIM_SIDE = 1000
HEADING_SIDE = 72
SUMMARY_SIDE = 1024


def utf8_len(text):
    return len(text.encode("utf-8"))


def clip(text, limit, marker=CUT):
    """`text` cut to at most `limit` bytes, ending with `marker` when cut.
    The cut falls on a character boundary, and back on a space when one is
    near, so a word isn't split."""
    if utf8_len(text) <= limit:
        return text
    room = max(0, limit - utf8_len(marker))
    cut = text.encode("utf-8")[:room].decode("utf-8", "ignore")
    sp = cut.rfind(" ")
    if sp > 0 and len(cut) - sp <= 80:
        cut = cut[:sp]
    return cut.rstrip() + marker


# --- Document structure --------------------------------------------------------

def split_frontmatter(text):
    """(frontmatter lines, body lines, the body's first line index). A document
    with no frontmatter has none, and its body starts at line 0."""
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[1:i], lines[i + 1:], i + 1
    return [], lines, 0


def frontmatter_scalars(fm):
    """{key: (value, line)} for each top-level key holding a plain scalar or a
    block scalar (`key: |` and its indented lines)."""
    out, key, start, block = {}, None, 0, []
    for i, line in enumerate(fm):
        if key is not None:
            if line.startswith((" ", "\t")) or not line.strip():
                block.append(line.strip())
                continue
            out[key] = ("\n".join(block).strip(), start)
            key = None
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if not m:
            continue
        if m.group(2) in ("|", "|-", "|+", ">", ">-", ">+"):
            key, start, block = m.group(1), i, []
        else:
            v = m.group(2).strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            out[m.group(1)] = (v, i)
    if key is not None:
        out[key] = ("\n".join(block).strip(), start)
    return out


def headings(lines):
    """(index, level, text) for each heading outside fenced code."""
    out, fenced = [], False
    for i, line in enumerate(lines):
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        m = HEADING.match(line)
        if m:
            out.append((i, len(m.group(1)), m.group(2).strip()))
    return out


def section(lines, names, level=2):
    """(start, end) of the first heading at `level` whose text is one of
    `names` (case aside): the lines after the heading up to the next heading at
    that level or above. None when there is no such heading."""
    hs = headings(lines)
    wanted = {n.lower() for n in names}
    for k, (i, lv, title) in enumerate(hs):
        if lv == level and title.lower() in wanted:
            end = len(lines)
            for j, lv2, _ in hs[k + 1:]:
                if lv2 <= level:
                    end = j
                    break
            return i + 1, end
    return None


def subsections(lines, start, end, level=3):
    """(heading index, title, body start, body end) for each heading at
    `level` between start and end."""
    hs = [(i, lv, t) for i, lv, t in headings(lines) if start <= i < end]
    out = []
    for k, (i, lv, title) in enumerate(hs):
        if lv != level:
            continue
        stop = end
        for j, lv2, _ in hs[k + 1:]:
            if lv2 <= level:
                stop = j
                break
        out.append((i, title, i + 1, stop))
    return out


def tidy(lines):
    """Lines joined, each with trailing space removed, and no leading or
    trailing blank lines."""
    xs = [x.rstrip() for x in lines]
    while xs and not xs[0].strip():
        xs.pop(0)
    while xs and not xs[-1].strip():
        xs.pop()
    return "\n".join(xs)


def top_items(lines, start, end, stop_at_field=False):
    """(start index, text) for each top-level list item between start and end:
    a line at column 0 that starts a list item, with the lines that continue
    it (indented lines, a lazy continuation line, and paragraphs indented under
    it after a blank line). A heading, a fence at column 0, the next top-level
    item, or a line at column 0 after a blank line ends it; with
    `stop_at_field`, so does a `**Name:**` field line."""
    items, cur, cur_start, fenced, blank = [], None, 0, False, False

    def close():
        if cur is not None:
            items.append((cur_start, tidy(cur)))

    for i in range(start, end):
        line = lines[i]
        if FENCE.match(line):
            if not line.startswith((" ", "\t")):
                close()
                cur = None
            elif cur is not None:
                cur.append(line)
            fenced = not fenced
            blank = False
            continue
        if fenced:
            if cur is not None:
                cur.append(line)
            continue
        if not line.strip():
            if cur is not None:
                cur.append(line)
            blank = True
            continue
        if HEADING.match(line) or (stop_at_field and FIELD_LINE.match(line)):
            close()
            cur = None
        elif ITEM.match(line):
            close()
            cur, cur_start = [line], i
        elif cur is not None and (line.startswith((" ", "\t")) or not blank):
            cur.append(line)
        else:
            close()
            cur = None
        blank = False
    close()
    return items


# --- The units -----------------------------------------------------------------

def units_scope_boundary(text):
    """rs-073, BRIEF: each top-level item under Scope Boundary, prefixed by the
    `###` heading it sits under (the section's own heading when none)."""
    _, lines, _ = split_frontmatter(text)
    sec = section(lines, ["Scope Boundary"])
    if not sec:
        return []
    start, end = sec
    subs = subsections(lines, start, end)
    out = []
    for i, item in top_items(lines, start, end):
        head = "## Scope Boundary"
        for hi, title, _, _ in subs:
            if hi < i:
                head = "### " + title
        out.append((i, head + "\n" + item))
    return out


def units_milestone_evidence(text):
    """rs-073, ROADMAP: each Evidence clause of each milestone under Milestones
    (Features on a roadmap/v2), prefixed by the milestone's heading. Evidence
    runs from its field line to the first blank line, the next field line or
    the next heading."""
    _, lines, _ = split_frontmatter(text)
    sec = section(lines, ["Milestones", "Features"])
    if not sec:
        return []
    out = []
    for hi, title, start, end in subsections(lines, *sec):
        for i in range(start, end):
            if not lines[i].startswith("**Evidence:**"):
                continue
            stop = end
            for j in range(i + 1, end):
                if not lines[j].strip() or FIELD_LINE.match(lines[j]) or HEADING.match(lines[j]):
                    stop = j
                    break
            for k, item in top_items(lines, i + 1, stop, stop_at_field=True):
                out.append((k, "### " + title + "\n" + item))
            break
    return out


def units_acceptance_criteria(text):
    """rs-013, PRD: each top-level item under Acceptance Criteria."""
    _, lines, _ = split_frontmatter(text)
    sec = section(lines, ["Acceptance Criteria"])
    return top_items(lines, *sec) if sec else []


def units_user_journeys(text):
    """rs-011, BRIEF: each `###` subsection of User Journeys, whole."""
    _, lines, _ = split_frontmatter(text)
    sec = section(lines, ["User Journeys"])
    if not sec:
        return []
    return [(hi, tidy(lines[hi:stop])) for hi, _, _, stop in subsections(lines, *sec)]


def paragraphs(lines, start, end):
    """Blank-line-separated blocks between start and end, fenced code kept
    inside its block."""
    blocks, cur, fenced = [], [], False
    for i in range(start, end):
        line = lines[i]
        if FENCE.match(line):
            fenced = not fenced
        if not fenced and not line.strip():
            if cur:
                blocks.append(tidy(cur))
                cur = []
            continue
        cur.append(line)
    if cur:
        blocks.append(tidy(cur))
    return [b for b in blocks if b]


SUMMARIES = (("problem", "Problem Statement"), ("outcome", "User Outcome"))


def units_frontmatter(text):
    """rs-012, BRIEF: the `problem` and `outcome` summaries, each beside the
    leading paragraphs of the section it summarizes that fit the budget, then
    `[section continues]` when any is left out. A summary or a section that's
    missing gives no unit."""
    fm, lines, _ = split_frontmatter(text)
    scalars = frontmatter_scalars(fm)
    out = []
    for field, heading in SUMMARIES:
        summary, at = scalars.get(field, ("", 0))
        sec = section(lines, [heading])
        if not summary or not sec:
            continue
        paras = paragraphs(lines, *sec)
        if not paras:
            continue
        head = "%s (frontmatter summary):\n%s\n\n## %s\n" % (field, clip(summary, SUMMARY_SIDE), heading)
        room = BUDGET - utf8_len(head)
        tail = "\n\n" + SECTION_CONTINUES
        kept = []
        for p in paras:
            if utf8_len("\n\n".join(kept + [p])) > room:
                break
            kept.append(p)
        if len(kept) < len(paras):
            while kept and utf8_len("\n\n".join(kept) + tail) > room:
                kept.pop()
            body = "\n\n".join(kept) if kept else clip(paras[0], room - utf8_len(tail))
            kept = [body + tail]
        # The summary's line in the frontmatter orders the two units.
        out.append((at, head + "\n\n".join(kept)))
    return out


def passages(lines):
    """(start index, heading, text, whole) for each passage of the body: a list
    item (any depth, with its continuation lines), a table row, or a prose
    paragraph. `whole` is true for an item or a row, which is clipped whole
    rather than to a sentence. Headings and fenced code are not passages."""
    out, cur, cur_start, kind, fenced, heading = [], None, 0, "", False, ""
    item_indent = 0

    def close():
        if cur:
            out.append((cur_start, heading, tidy(cur), kind != "prose"))

    for i, line in enumerate(lines):
        if FENCE.match(line):
            close()
            cur = None
            fenced = not fenced
            continue
        if fenced:
            continue
        h = HEADING.match(line)
        if h:
            close()
            cur, heading = None, h.group(2).strip()
            continue
        if not line.strip():
            close()
            cur = None
            continue
        m = ANY_ITEM.match(line)
        if TABLE_ROW.match(line):
            close()
            cur = None
            if not TABLE_RULE.match(line):
                out.append((i, heading, line.strip(), True))
            continue
        if m:
            close()
            cur, cur_start, kind, item_indent = [line.strip()], i, "item", len(m.group(1))
            continue
        if cur is not None and kind == "item":
            # An item runs on through lines indented under its marker, and
            # through a line at column 0 straight after it, which Markdown
            # reads as the item's lazy continuation; a line indented less than
            # the marker belongs to an outer item and starts a paragraph.
            indent = len(line) - len(line.lstrip())
            if indent > item_indent or not line.startswith((" ", "\t")):
                cur.append(line.strip())
                continue
        if cur is None or kind != "prose":
            close()
            cur, cur_start, kind = [], i, "prose"
        cur.append(line.strip())
    close()
    return out


def keys_of(text):
    """The keys a passage shares by: its backticked terms and its numbers
    (thousands separators dropped), numbers inside backticks left to the term.
    A list marker's own number is not a key."""
    terms = ["`%s`" % t.strip() for t in TERM.findall(text) if t.strip()]
    rest = TERM.sub(" ", re.sub(r"^\s*(\d+[.)]|[-*+])\s+", "", text))
    nums = [n.replace(",", "") for n in NUMBER.findall(rest)]
    seen, out = set(), []
    for k in terms + nums:
        if k not in seen:
            seen.add(k)
            out.append(k)
    return out


SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


def holding(text, whole, key):
    """The sentence of `text` holding `key`, or `text` whole for an item."""
    if whole:
        return text
    flat = " ".join(text.split())
    for s in SENTENCE_END.split(flat):
        if contains_key(s, key):
            return s
    return flat


def contains_key(text, key):
    if key.startswith("`"):
        return key in text
    return key in [n.replace(",", "") for n in NUMBER.findall(TERM.sub(" ", text))]


def units_contradiction_pairs(text):
    """rs-009, PRD and DESIGN: two passages sharing a backticked term or a
    number that occurs in two or three passages, each clipped to the sentence
    or list item holding it and to PAIR_SIDE bytes, under its section heading.
    A key in more than three passages forms no pair."""
    _, lines, _ = split_frontmatter(text)
    ps = passages(lines)
    keyed = [keys_of(t) for _, _, t, _ in ps]
    where = {}
    for n, ks in enumerate(keyed):
        for k in ks:
            where.setdefault(k, []).append(n)
    pairs = {}
    for k, ns in where.items():
        if not 2 <= len(ns) <= 3:
            continue
        for a in range(len(ns)):
            for b in range(a + 1, len(ns)):
                i, j = ns[a], ns[b]
                pos = keyed[i].index(k)
                if (i, j) not in pairs or pos < pairs[(i, j)][0]:
                    pairs[(i, j)] = (pos, k)
    out = []
    for (i, j) in sorted(pairs, key=lambda p: (ps[p[0]][0], ps[p[1]][0])):
        k = pairs[(i, j)][1]
        sides = []
        for n in (i, j):
            _, head, t, whole = ps[n]
            head = clip(head or "(before any heading)", HEADING_SIDE)
            sides.append("## %s\n%s" % (head, clip(holding(t, whole, k), PAIR_SIDE)))
        out.append((ps[i][0], "\n\n".join(sides)))
    return out


def thesis_claims(lines):
    """{number: text} for the Defensibility Thesis's numbered claims: its
    top-level numbered list items, and paragraphs that open `Claim <n>`."""
    sec = section(lines, ["Defensibility Thesis"])
    if not sec:
        return {}
    claims = {}
    for _, item in top_items(lines, *sec):
        m = NUMBERED.match(item)
        if m:
            claims.setdefault(m.group(1), item)
    for p in paragraphs(lines, *sec):
        m = CLAIM_PARA.match(p)
        if m:
            claims.setdefault(m.group(1), p)
    return claims


def units_falsifiers(text):
    """rs-074, STRATEGY: each Bet-Specific Falsifiability item (its corrective
    included) clipped to FALSIFIER_SIDE, beside the Defensibility Thesis claim
    it names clipped to CLAIM_SIDE. An item naming no claim number is sent with
    `[no claim named]`; one naming a number the thesis has no claim for says so."""
    _, lines, _ = split_frontmatter(text)
    sec = section(lines, ["Bet-Specific Falsifiability"])
    if not sec:
        return []
    claims = thesis_claims(lines)
    out = []
    for i, item in top_items(lines, *sec):
        m = CLAIM_REF.search(item)
        if not m:
            claim = "claim: " + NO_CLAIM
        elif m.group(1) not in claims:
            claim = "claim %s: [not in the Defensibility Thesis]" % m.group(1)
        else:
            claim = "claim %s:\n%s" % (m.group(1), clip(claims[m.group(1)], CLAIM_SIDE))
        out.append((i, "falsifier:\n%s\n\n%s" % (clip(item, FALSIFIER_SIDE), claim)))
    return out


# (criterion, format) -> (section key, units function, whether it cuts).
PAIRS = {
    ("rs-073", "brief"): ("scope-boundary", units_scope_boundary, False),
    ("rs-073", "roadmap"): ("milestones", units_milestone_evidence, False),
    ("rs-013", "prd"): ("acceptance-criteria", units_acceptance_criteria, False),
    ("rs-011", "brief"): ("user-journeys", units_user_journeys, False),
    ("rs-012", "brief"): ("frontmatter", units_frontmatter, True),
    ("rs-009", "prd"): ("document", units_contradiction_pairs, True),
    ("rs-009", "design"): ("document", units_contradiction_pairs, True),
    ("rs-074", "strategy"): ("bet-specific-falsifiability", units_falsifiers, True),
}


def units(criterion, fmt, text):
    """[(key, text)] for one document's text, in document order. An empty
    unit is left out: koto doesn't grade one."""
    sec, fn, _ = PAIRS[(criterion, fmt)]
    found = [(start, n, t) for n, (start, t) in enumerate(fn(text)) if t.strip()]
    found.sort(key=lambda u: (u[0], u[1]))
    return [("%s/%d" % (sec, n), t) for n, (_, _, t) in enumerate(found, 1)]


def lines_for(criterion, fmt, text):
    sec = PAIRS[(criterion, fmt)][0]
    return [json.dumps({"key": k, "text": t, "document": fmt, "section": sec}, ensure_ascii=False)
            for k, t in units(criterion, fmt, text)]


# --- Reading the committed document --------------------------------------------

def refuse(msg):
    print("%s: %s" % (PROG, msg), file=sys.stderr)
    sys.exit(2)


def git(args):
    return subprocess.run(["git"] + args, capture_output=True)


def committed_text(doc, commit):
    """The document's blob at `commit`, from the repository it lives in. The
    path must resolve, symlinks followed, to a file under that repository's
    docs/."""
    if not COMMIT.match(commit or ""):
        refuse("--commit is not a full hex commit id")
    real = os.path.realpath(doc)
    r = git(["-C", os.path.dirname(real), "rev-parse", "--show-toplevel"])
    if r.returncode != 0:
        refuse("the document is not in a git repository")
    top = os.path.realpath(r.stdout.decode("utf-8", "replace").strip())
    rel = os.path.relpath(real, top).replace(os.sep, "/")
    if not REL_PATH.match(rel) or any(p in (".", "..") for p in rel.split("/")):
        refuse("the document is not under the repository's docs/")
    r = git(["-C", top, "cat-file", "blob", "%s:%s" % (commit, rel)])
    if r.returncode != 0:
        refuse("the document has no blob at that commit")
    return r.stdout.decode("utf-8", "replace")


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(prog=PROG, description="Print the units a Jev document criterion grades.")
    ap.add_argument("criterion")
    ap.add_argument("format")
    ap.add_argument("--doc", required=True)
    ap.add_argument("--commit", required=True)
    args = ap.parse_args(argv)
    if (args.criterion, args.format) not in PAIRS:
        refuse("no such criterion and format pair")
    text = committed_text(args.doc, args.commit)
    out = sys.stdout
    for line in lines_for(args.criterion, args.format, text):
        out.write(line + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
