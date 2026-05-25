---
complexity: testable
complexity_rationale: Two surgical edits to a pattern-reference markdown file whose downstream consumers (state-schema doc, /scope SKILL.md, /charter follow-up) grep its literal section names and section text; correctness is verifiable by literal-substring assertions plus structural ordering checks, but a misplaced section or a dropped substring would silently break those consumers — heavier than a docs typo, lighter than security-sensitive code.
---

## Goal

Edit `references/parent-skill-pattern.md` to insert a new "Gate Vocabulary" section between "Three Exit Paths" and "Conditional Feeder Invocation Shape" enumerating the four gate shapes (EITHER-signal / ALWAYS / shape-dependent / Mandatory-with-auto-skip) each with one canonical example, AND rewrite the existing "Parents do not extend children's input surfaces" paragraph (L13) to permit a uniform pattern-level `parent_orchestration:` state-file sentinel as the sole permitted parent-orchestration primitive.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

`/scope` is the second parent skill landing in shirabe and the first to bind the parent-skill pattern v1 against the tactical chain (`/brief → /prd → /design → /plan`). Two of the tactical-chain asymmetries the design must absorb sit inside `references/parent-skill-pattern.md` itself: `/prd`'s invocation gate is mandatory-unless-an-Accepted-PRD-already-exists (a fourth gate shape the existing three-entry vocabulary — EITHER-signal / ALWAYS / shape-dependent — has no name for), and `/scope`'s resume-suppression signaling needs a pattern-level convention because `/charter`'s current `--parent-orchestrated` flag is in direct tension with L13 ("Parents do not extend children's input surfaces") as currently written.

Component 1 of the Solution Architecture splits into two sub-edits that share a single reviewer surface (one PR, one pattern-doc file) and so ship as a single atomic issue:

- **1.1 Gate Vocabulary section** (Design Decision 8 — sub-edit A.1): a new top-level section codifying all four gate shapes with one canonical example per shape, so `/scope`'s Mandatory-with-auto-skip gate is named honestly inside the pattern doc rather than jammed into a misnamed third gate. Canonical examples come from the two existing parent skills:
  - EITHER-signal — `/charter`'s `/vision` invocation
  - ALWAYS — `/charter`'s `/strategy` invocation
  - shape-dependent — `/charter`'s `/roadmap` invocation
  - Mandatory-with-auto-skip — `/scope`'s `/prd` invocation
- **1.2 L13 amendment** (Design Decision 3 — sub-edit A.2): the existing "Parents do not extend children's input surfaces" paragraph is rewritten to preserve L13's spirit (no per-parent flags coupling parent to child API) while permitting one pattern-defined convention every parent uses identically: a state-file `parent_orchestration:` sentinel block at a substrate-defined path that children read at child Phase 0 to suppress their own status-aware re-entry prompt when the parent has already decided upfront that the invocation is a fresh chain.

These edits unblock <<ISSUE:8>> (state-schema doc adds `boundary:` and `plan_execution_mode:` conditional fields and cites the Mandatory-with-auto-skip definition from this section for its chain-skipped semantics) and <<ISSUE:10>> (`/scope` SKILL.md cites both the new Gate Vocabulary section in its Phase 1 R4/R5/R6 binding prose and the amended L13 in its `parent_orchestration:` sentinel-write step). Both downstream issues will fail at the cite step if the section name or the L13 wording diverges from the design's canonical text.

The L13 amendment is also load-bearing for the follow-up `/charter` migration tracked separately under SE12 — `/charter`'s `phase-resume.md` documents a `--parent-orchestrated` flag today that no shirabe child recognizes; the amendment is the pattern-level decision the migration depends on.

This issue does NOT add the `parent_orchestration:` block schema to `references/parent-skill-state-schema.md` — that lives in <<ISSUE:8>>. It also does NOT migrate `/charter`'s flag to the sentinel; that is downstream follow-on work outside this milestone.

## Acceptance Criteria

- [ ] `references/parent-skill-pattern.md` contains a new top-level section titled exactly `## Gate Vocabulary`
- [ ] The Gate Vocabulary section is positioned AFTER the existing `## Three Exit Paths` section AND BEFORE the existing `## Conditional Feeder Invocation Shape` section (mechanically: line number of `## Gate Vocabulary` is greater than line number of `## Three Exit Paths` and less than line number of `## Conditional Feeder Invocation Shape`)
- [ ] The Gate Vocabulary section enumerates all four gate shapes with the literal substrings: `EITHER-signal`, `ALWAYS`, `shape-dependent`, `Mandatory-with-auto-skip`
- [ ] Each of the four gate shapes is paired with at least one canonical example citing a specific parent-skill and child-skill: `/charter`'s `/vision` invocation (EITHER-signal), `/charter`'s `/strategy` (ALWAYS), `/charter`'s `/roadmap` (shape-dependent), `/scope`'s `/prd` (Mandatory-with-auto-skip)
- [ ] The Mandatory-with-auto-skip shape includes prose semantics that the child SHALL be invoked unless its durable artifact already exists at the published-Accepted status at the canonical path, in which case the child is recorded in `chain_skipped` and the chain proceeds to the next gate
- [ ] The existing paragraph beginning `**Parents do not extend children's input surfaces.**` inside `## Conditional Feeder Invocation Shape` is rewritten in place (same anchor sentence retained as the leading bold statement) to permit a pattern-level suppression signal as the sole permitted parent-orchestration primitive
- [ ] The amended L13 paragraph contains the literal substring `parent_orchestration:` naming the state-file block identifier the convention defines
- [ ] The amended L13 paragraph contains language to the effect that the signal is defined once at the pattern-doc layer (not per-parent) and read by all parents and children identically (e.g., phrasing such as "defined once in the pattern-doc, read by all parents, and recognized by all children identically")
- [ ] The amended L13 paragraph preserves the original prohibition on adding per-parent flags or arguments to child input surfaces; only the pattern-level convention is admitted as an exception
- [ ] The previously-cited PRD R4 thesis-shift example in the original L13 paragraph is either retained or replaced with equivalent illustrative prose; the example MUST NOT be silently dropped without a replacement that demonstrates the loose-coupling rule
- [ ] No other section of `references/parent-skill-pattern.md` is modified beyond the new Gate Vocabulary section and the L13 paragraph rewrite (the seven semantic invariants I-1 through I-7, the Three Exit Paths, the Named Substitution Surfaces, the Team-Shape Declarator, the Required SKILL.md Structural Elements, and the Team-Lead Operating Discipline sections all remain byte-identical except where the new section's insertion forces a line-number shift)
- [ ] CI green
- [ ] Must deliver: a Gate Vocabulary section whose `Mandatory-with-auto-skip` definition is citable by <<ISSUE:8>>'s `plan_execution_mode:` chain-skipped semantics (required by <<ISSUE:8>>)
- [ ] Must deliver: an amended L13 paragraph whose `parent_orchestration:` convention is the pattern-doc anchor <<ISSUE:10>>'s `/scope` SKILL.md sentinel-write step cites (required by <<ISSUE:10>>)

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

REF="references/parent-skill-pattern.md"

test -f "$REF"

# Gate Vocabulary section exists with the exact heading
grep -q '^## Gate Vocabulary$' "$REF"

# All four gate shapes named literally
grep -q 'EITHER-signal' "$REF"
grep -q 'ALWAYS' "$REF"
grep -q 'shape-dependent' "$REF"
grep -q 'Mandatory-with-auto-skip' "$REF"

# Mandatory-with-auto-skip semantic substrings present
grep -q 'chain_skipped' "$REF"

# Ordering: Gate Vocabulary sits between Three Exit Paths and Conditional Feeder Invocation Shape
line_three_exits=$(grep -n '^## Three Exit Paths$' "$REF" | cut -d: -f1)
line_gate_vocab=$(grep -n '^## Gate Vocabulary$' "$REF" | cut -d: -f1)
line_feeder=$(grep -n '^## Conditional Feeder Invocation Shape$' "$REF" | cut -d: -f1)

test -n "$line_three_exits"
test -n "$line_gate_vocab"
test -n "$line_feeder"

if [ "$line_gate_vocab" -le "$line_three_exits" ]; then
  echo "FAIL: Gate Vocabulary must come AFTER Three Exit Paths" >&2
  exit 1
fi

if [ "$line_gate_vocab" -ge "$line_feeder" ]; then
  echo "FAIL: Gate Vocabulary must come BEFORE Conditional Feeder Invocation Shape" >&2
  exit 1
fi

# Canonical examples cite the right parent+child pairings
grep -E 'EITHER-signal' "$REF" -A 20 | grep -q '/vision'
grep -E 'ALWAYS' "$REF" -A 20 | grep -q '/strategy'
grep -E 'shape-dependent' "$REF" -A 20 | grep -q '/roadmap'
grep -E 'Mandatory-with-auto-skip' "$REF" -A 20 | grep -q '/prd'

# L13 amendment: anchor sentence retained, parent_orchestration: convention introduced
grep -q 'Parents do not extend' "$REF"
grep -q 'parent_orchestration:' "$REF"

# Original prohibition on per-parent flags survives the rewrite
grep -qE '(flags|arguments)' "$REF"

# Semantic invariants section is unchanged at the section-title level (I-1 through I-7 still present)
for inv in 'I-1' 'I-2' 'I-3' 'I-4' 'I-5' 'I-6' 'I-7'; do
  grep -q "$inv" "$REF"
done

echo "All validations passed"
```

## Dependencies

None — this issue lives at the head of PR-4's pattern-doc-edit cluster and has no upstream issue dependencies. PR-1's `references/parent-skill-worktree-discipline.md` (<<ISSUE:1>>) lives in a different file and does not block this edit.

## Downstream Dependencies

This issue unblocks two downstream issues inside PR-4:

- **<<ISSUE:8>>** (`docs(refs): extend parent-skill-state-schema.md with boundary, plan_execution_mode, and R9 additions`) — the new `plan_execution_mode:` conditional field's chain-skipped semantics cite the Mandatory-with-auto-skip gate definition introduced here. The state-schema bullet for `plan_execution_mode:` will name the gate by its pattern-doc identifier (`Mandatory-with-auto-skip`); if that identifier or its semantic prose changes, <<ISSUE:8>>'s citation must update in lockstep.
- **<<ISSUE:10>>** (`feat(scope): add /scope SKILL.md body`) — the `/scope` SKILL.md's Phase 1 binding prose cites the Gate Vocabulary section by name for `/prd`'s Mandatory-with-auto-skip evaluation, and the `parent_orchestration:` sentinel-write step in `/scope`'s Phase 2 prose cites the amended L13 paragraph by its pattern-doc anchor. Both citations are literal references readers grep against.

What downstream consumers need from this issue:

- A grep-stable section heading (`## Gate Vocabulary`) and grep-stable gate-shape identifiers (the four literal strings) that downstream cite-prose can reference without ambiguity.
- An amended L13 paragraph whose `parent_orchestration:` mention is the canonical anchor for the convention's name; downstream issues quote this anchor.
- Preserved structural ordering — downstream prose ("Gate Vocabulary section between Three Exit Paths and Conditional Feeder Invocation Shape") describes the section's position; reviewers cross-checking the description against the file will notice if the section migrated.
