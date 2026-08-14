#!/usr/bin/env bash
# Fail when the writing-style rule list has been copied out of its source.
#
# The rules live in exactly one file. Three copies existed before
# DESIGN-vale-adoption: the skill prose, a constant in the validator, and a
# jury reviewer's instruction. They drifted, which is what the single source
# exists to end. A copy that reappears drifts again, so this check makes the
# reappearance fail rather than waiting for someone to notice.
#
# The heuristic is a word-list shape: three or more distinct terms from the
# rule source on one line, outside the source itself. That catches a
# transcribed table row or a Rust array, without flagging prose that uses one
# banned word while discussing it.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

RULES="skills/writing-style/rules.yaml"
if [[ ! -f "$RULES" ]]; then
  echo "FAIL: rule source not found at $RULES" >&2
  exit 1
fi

exec python3 - "$RULES" <<'PY'
import os
import re
import sys

rules_path = sys.argv[1]

# Single-word terms only. A multi-word term cannot be transcribed into an
# array without quoting this heuristic would not recognize anyway.
terms = []
in_words = False
for line in open(rules_path, encoding="utf-8"):
    if line.startswith("  - category:"):
        in_words = True
    elif line.startswith(("judgment_only:", "frequency:")):
        in_words = False
    elif in_words and line.startswith("      - "):
        term = line[8:].strip().lower()
        if term and " " not in term:
            terms.append(term)

if len(terms) < 10:
    print(
        f"FAIL: parsed only {len(terms)} terms from {rules_path}; "
        "the parser or the file shape changed",
        file=sys.stderr,
    )
    sys.exit(1)

pattern = re.compile(r"\b(" + "|".join(re.escape(t) for t in terms) + r")\b", re.I)

EXEMPT_PREFIXES = (
    rules_path,
    "skills/writing-style/evals/",
    "scripts/check-no-duplicate-rule-list.sh",
    "crates/shirabe/tests/fixtures/golden/",
)

THRESHOLD = 3
violations = 0

for root_dir in ("crates", "skills"):
    for dirpath, _dirnames, filenames in os.walk(root_dir):
        for name in filenames:
            if not name.endswith((".rs", ".md", ".yaml")):
                continue
            path = os.path.join(dirpath, name)
            if path.startswith(EXEMPT_PREFIXES):
                continue
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    for lineno, line in enumerate(fh, 1):
                        distinct = {m.group(1).lower() for m in pattern.finditer(line)}
                        if len(distinct) >= THRESHOLD:
                            print(
                                f"FAIL: {path}:{lineno} carries {len(distinct)} rule-source "
                                f"terms on one line ({', '.join(sorted(distinct))}); "
                                f"the rule list has one home ({rules_path})",
                                file=sys.stderr,
                            )
                            violations += 1
            except OSError:
                continue

if violations:
    print(
        f"\n{violations} line(s) restate the rule list. Reference {rules_path} instead.",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"check-no-duplicate-rule-list: OK ({len(terms)} terms, no duplicate lists)")
PY
