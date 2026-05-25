---
complexity: testable
complexity_rationale: New behavioral prose in a phase reference file with grep-checkable literal-phrasing assertions; no security-sensitive surfaces, but the discovery prelude carries load-bearing semantics for downstream invocation logic and resume drift detection.
---

## Goal

Author `skills/charter/references/phases/phase-1-discovery.md` with the Phase 1 entry-router prelude: repository-visibility detection with default-Private warning, the manual-fallback non-interference rule, and the thesis-shift signal prompt — establishing the prose surface that <<ISSUE:4>> extends with child-invocation logic and that <<ISSUE:6>> cites from the resume ladder.

## Context

`/charter` is the first parent skill against the parent-skill pattern committed in DESIGN-shirabe-progression-authoring. Phase 1 of `/charter` is the entry-router that converts a freeform topic and author conversation into a concrete chain proposal. Before the chain-shape decisions land (owned by <<ISSUE:4>>), three foundational behaviors must be in prose:

1. **Visibility detection (PRD R12)** — `/charter` reads CLAUDE.md's `## Repo Visibility:` header to set the chain-shape governance gate (e.g., whether `/comp` is a candidate, owned by <<ISSUE:4>>). The shipped `/strategy` skill already establishes the detection idiom; `/charter` ratifies the same idiom verbatim and inherits the shipped warning phrasing.

2. **Manual-fallback non-interference (PRD R13, Design Component 2)** — Direct child invocation by an author (e.g., `/strategy <topic>` outside `/charter`) is first-class steady-state capability. `/charter` MUST NOT detect, warn against, or otherwise interfere. The resume ladder owned by <<ISSUE:6>> handles drift detection on the NEXT `/charter` resume; Phase 1 prose names the discipline.

3. **Thesis-shift signal (PRD R4)** — The Phase 1 discovery prompt surfaces a literal question that elicits the three named utterance categories treated as positive thesis-shift signals. The signal is detected here; the `/vision` invocation decision that consumes it is owned by <<ISSUE:4>>.

The Phase 1 discovery flow itself uses the discover/converge engine that lives at `skills/explore/references/phases/{phase-2-discover.md, phase-3-converge.md}` (per Design Decision 1, the engine stays in place and parent skills point cross-skill at it). This issue's prose makes that pointer explicit.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md` (Solution Architecture > Component 2 "R13 manual-fallback as named behavioral commitment").
PRD: `docs/prds/PRD-shirabe-charter-skill.md` (R4, R12, R13; AC7 Public-repo silence half, AC21, AC22, AC23).

## Acceptance Criteria

### File presence

- [ ] `skills/charter/references/phases/phase-1-discovery.md` exists and is the file authored by this issue (extended by <<ISSUE:4>>, cited by <<ISSUE:6>>).

### Visibility detection (R12; verifies AC21)

- [ ] Documents that `/charter` reads `## Repo Visibility:` from CLAUDE.md (or CLAUDE.local.md when present) with valid values `Public` and `Private`.
- [ ] States that when the header is absent the default is `Private`.
- [ ] Contains the literal warning phrasing: `Default to Private if unknown — restricting is easier to undo than oversharing`.
- [ ] The warning prose names the missing `## Repo Visibility:` header explicitly so the author knows what to add.

### Manual-fallback non-interference (R13; verifies AC22, AC23 reach)

- [ ] Contains a non-interference statement that `/charter` SHALL NOT detect, warn against, or otherwise interfere with manual invocation of any of its children outside `/charter` (including but not limited to `/strategy`, `/vision`, `/comp`, `/roadmap`).
- [ ] States that direct child invocation is first-class steady-state capability, not a degraded path.
- [ ] References `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` (from <<ISSUE:1>>) for the contract framing of the parent ⇄ child surface that makes non-interference safe.
- [ ] States that out-of-chain edits are detected on the next `/charter` resume via child-snapshot drift (forward reference to the resume ladder owned by <<ISSUE:6>>) — the resume ladder offers a staleness-warning prompt; it does NOT act unilaterally.

### Thesis-shift signal (R4; signal-detection half of AC5/AC6)

- [ ] Contains the literal question: `Is the long-term thesis shifting, or is this an operational layer below it?` surfaced in the Phase 1 discovery prompt.
- [ ] Names the three utterance categories treated as positive thesis-shift signals:
  1. The author explicitly says the long-term thesis is changing or has changed.
  2. The author names a new audience, value proposition, or org fit that the existing VISION does not cover.
  3. The author indicates the existing VISION is no longer the right framing.
- [ ] States explicitly that signal detection is agent judgment — the requirement is that the question is surfaced and any of the three categories is treated as positive — and that the `/vision` invocation decision itself is owned by Phase 2 chain orchestration (forward reference to <<ISSUE:4>>).

### Cross-skill pointer (Design Decision 1)

- [ ] References the discover/converge engine at `skills/explore/references/phases/phase-2-discover.md` and `skills/explore/references/phases/phase-3-converge.md` for the conversational discovery loop `/charter` Phase 1 uses.

### Public-repo silence half of AC7

- [ ] The prose contains none of the literal substrings `/comp`, `competitive analysis`, or `competitive framing`. The chain-proposal-prompt half of AC7 (Public-repo silence in the proposal output) is owned by <<ISSUE:4>>; this issue ensures the discovery prelude itself does not leak these terms.

### Public-repo content discipline

- [ ] No references to private repos, internal tooling names, internal workflow commands, competitor names, or pre-announcement features.

### Downstream deliverables

- [ ] Must deliver: `skills/charter/references/phases/phase-1-discovery.md` containing the visibility-detection prose, manual-fallback rule, and thesis-shift signal prompt — extended in-place by <<ISSUE:4>> with child-invocation logic and the chain-proposal prompt.
- [ ] Must deliver: a non-interference statement and forward reference to child-snapshot drift detection, cited from <<ISSUE:6>>'s resume ladder.
- [ ] Must deliver: literal phrasings (visibility-default warning, thesis-shift question, three utterance categories) that <<ISSUE:9>>'s evals assert against (AC6, AC21, AC22).

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

FILE="skills/charter/references/phases/phase-1-discovery.md"

# File presence
test -f "$FILE"

# Visibility detection prose (R12 / AC21)
grep -qF "## Repo Visibility:" "$FILE"
grep -qF "Default to Private if unknown — restricting is easier to undo than oversharing" "$FILE"
grep -qiE "default(s|ing)?[[:space:]]+to[[:space:]]+Private" "$FILE"

# Manual-fallback rule (R13 / AC22, AC23 reach)
grep -qiE "(manual[- ]fallback|invoke[s]? a child directly|direct(ly)? invok(e|ing|ation)[[:space:]]+(of[[:space:]]+)?(a[[:space:]]+)?child)" "$FILE"
grep -qF "parent-skill-child-inspection.md" "$FILE"
grep -qiE "(child[- ]snapshot|child_snapshots)[[:space:]]*(drift|comparison)|drift[[:space:]]+(detect|fires)" "$FILE"

# Thesis-shift signal (R4 / AC5, AC6 signal half)
grep -qF "Is the long-term thesis shifting, or is this an operational layer below it?" "$FILE"
grep -qiE "thesis[- ]shift" "$FILE"

# Three utterance categories (lightweight: detect each category's anchor noun)
grep -qiE "long[- ]term[[:space:]]+thesis[[:space:]]+(is[[:space:]]+)?(changing|has[[:space:]]+changed)" "$FILE"
grep -qiE "(new[[:space:]]+audience|value[[:space:]]+proposition|org[[:space:]]+fit)" "$FILE"
grep -qiE "existing[[:space:]]+VISION[[:space:]]+is[[:space:]]+no[[:space:]]+longer" "$FILE"

# Cross-skill pointer to discover/converge engine (Design Decision 1)
grep -qF "skills/explore/references/phases/phase-2-discover.md" "$FILE"
grep -qF "skills/explore/references/phases/phase-3-converge.md" "$FILE"

# Public-repo silence half of AC7 — the discovery prelude itself must not leak /comp terminology.
# These substrings MUST NOT appear in the prose authored by this issue.
if grep -qF "/comp" "$FILE"; then
  echo "ERROR: phase-1-discovery.md contains '/comp' literal — Public-repo silence half of AC7 violated"
  exit 1
fi
if grep -qiF "competitive analysis" "$FILE"; then
  echo "ERROR: phase-1-discovery.md contains 'competitive analysis' literal — Public-repo silence half of AC7 violated"
  exit 1
fi
if grep -qiF "competitive framing" "$FILE"; then
  echo "ERROR: phase-1-discovery.md contains 'competitive framing' literal — Public-repo silence half of AC7 violated"
  exit 1
fi

echo "All validations passed"
```

## Dependencies

Blocked by <<ISSUE:2>>

`/charter`'s SKILL.md (owned by <<ISSUE:2>>) must exist with the Phase 1 phase-reference slot wired in the Phase Execution list so this issue's `phase-1-discovery.md` is the file SKILL.md points at. `/charter` SKILL.md also lays in the visibility-detection citation; this issue fills the actual visibility-detection behavioral prose. `<<ISSUE:1>>`'s `references/parent-skill-child-inspection.md` is cited by name from this issue's manual-fallback rule and lands earlier in the chain (transitive via <<ISSUE:2>>).

## Downstream Dependencies

- **<<ISSUE:4>>** — adds child-invocation logic and the chain-proposal confirmation prompt to the SAME file (`phase-1-discovery.md`). This issue's deliverable is the discovery prelude (visibility detection + manual-fallback + thesis-shift signal); <<ISSUE:4>> appends the four `/charter` → child invocation decisions and synthesizes the chain-proposal prompt. The Public-repo silence other half (chain proposal output containing no `/comp`/competitive terms) is owned by <<ISSUE:4>>.
- **<<ISSUE:6>>** — resume ladder cites the manual-fallback non-interference statement and the visibility detection idiom from this file when documenting out-of-chain edit detection (child-snapshot drift). This issue's deliverable: phase-1-discovery.md states the non-interference rule and forward-references child-snapshot drift so <<ISSUE:6>>'s resume ladder can cite it.
- **<<ISSUE:9>>** — evals assert literal phrasings authored here: the default-Private warning (AC21), the thesis-shift question (signal-detection half of AC6), and the manual-fallback non-interference behavior (AC22). This issue's deliverable: the literal phrasings exist in the file at the substrings the evals will grep for.
