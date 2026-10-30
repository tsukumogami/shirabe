#!/usr/bin/env python3
"""make-doc.py -- write a synthetic document with an exact number of units
for one document criterion, for scripts/doc-criteria_test.sh.

Usage: make-doc.py <format> <rule> <units> [--unit-bytes <n>] [--sentinel <s>]

Prints the document. <units> units for <rule> on <format>, and none for any
other criterion of the format. With --unit-bytes, the first unit is padded so
the text slice.py prints for it is exactly <n> bytes. With --sentinel, the
string is planted in the first unit. The unit count and size are checked with
slice.py's own functions before anything is printed; exit 2 when they don't
hold.

Standard library only.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "doc-criteria"))
import slice as sl  # noqa: E402


def words(n):
    """Filler of exactly n bytes, words of letters only (no digits, no
    backticks), so rs-009 finds no key in it."""
    base = " plain words fill this unit"
    out = (base * (n // len(base) + 1))[:n]
    # Never end on a space: the slicer trims trailing space off a unit.
    return out[:-1] + "x" if out.endswith(" ") else out


def build(fmt, rule, n, pad, sentinel):
    first = (" " + sentinel) if sentinel else ""
    fill = words(pad) if pad else ""
    if (fmt, rule) == ("brief", "rs-073"):
        items = ["- Covers area %s.%s%s" % (chr(97 + i % 26), first if i == 0 else "", fill if i == 0 else "")
                 for i in range(n)]
        return "# BRIEF\n\n## Scope Boundary\n\n" + "\n".join(items) + "\n"
    if (fmt, rule) == ("brief", "rs-011"):
        parts = ["### Journey %s\n\nA person does the thing.%s%s\n" % (
            chr(65 + i % 26), first if i == 0 else "", fill if i == 0 else "") for i in range(n)]
        return "# BRIEF\n\n## User Journeys\n\n" + "\n".join(parts)
    if (fmt, rule) == ("brief", "rs-012"):
        fm = ["schema: brief/v1"]
        body = ["# BRIEF\n"]
        names = (("problem", "Problem Statement"), ("outcome", "User Outcome"))
        for i, (field, heading) in enumerate(names[:n]):
            fm.append("%s: The %s in brief%s" % (field, field, first if i == 0 else ""))
            body.append("## %s\n\nThe %s, in a paragraph.\n" % (heading, field))
        return "---\n" + "\n".join(fm) + "\n---\n\n" + "\n".join(body)
    if (fmt, rule) == ("prd", "rs-013"):
        items = ["- [ ] The export holds case %s.%s%s" % (chr(97 + i % 26), first if i == 0 else "", fill if i == 0 else "")
                 for i in range(n)]
        return "# PRD\n\n## Acceptance Criteria\n\n" + "\n".join(items) + "\n"
    if rule == "rs-009" and fmt in ("prd", "design"):
        paras = []
        for i in range(n):
            term = "`term-%d`" % i
            paras.append("Alpha uses %s here.%s" % (term, first if i == 0 else ""))
            paras.append("Beta uses %s there." % term)
        return "# DOC\n\n## Overview\n\n" + "\n\n".join(paras) + "\n"
    if (fmt, rule) == ("roadmap", "rs-073"):
        ms = ["### Milestone %s\n\n**Evidence:**\n- The evidence holds.%s%s\n" % (
            chr(65 + i % 26), first if i == 0 else "", fill if i == 0 else "") for i in range(n)]
        return "# ROADMAP\n\n## Milestones\n\n" + "\n".join(ms)
    if (fmt, rule) == ("strategy", "rs-074"):
        items = ["- If claim 1 stops holding, we stop.%s" % (first if i == 0 else "") for i in range(n)]
        return ("# STRATEGY\n\n## Defensibility Thesis\n\n1. The one claim.\n\n"
                "## Bet-Specific Falsifiability\n\n" + "\n".join(items) + "\n")
    raise SystemExit("no generator for %s %s" % (fmt, rule))


def units(fmt, rule, text):
    _, fn, _ = sl.PAIRS[(rule, fmt)]
    return [u for _, u in fn(text)]


def main():
    args = sys.argv[1:]
    unit_bytes = None
    sentinel = ""
    if "--unit-bytes" in args:
        i = args.index("--unit-bytes")
        unit_bytes = int(args[i + 1])
        del args[i:i + 2]
    if "--sentinel" in args:
        i = args.index("--sentinel")
        sentinel = args[i + 1]
        del args[i:i + 2]
    fmt, rule, n = args[0], args[1], int(args[2])
    text = build(fmt, rule, n, 0, sentinel)
    if unit_bytes is not None:
        have = sl.utf8_len(units(fmt, rule, text)[0])
        text = build(fmt, rule, n, unit_bytes - have, sentinel)
    got = units(fmt, rule, text)
    if len(got) != n:
        sys.stderr.write("make-doc: %d units, wanted %d\n" % (len(got), n))
        sys.exit(2)
    if unit_bytes is not None and sl.utf8_len(got[0]) != unit_bytes:
        sys.stderr.write("make-doc: first unit is %d bytes, wanted %d\n" % (sl.utf8_len(got[0]), unit_bytes))
        sys.exit(2)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
