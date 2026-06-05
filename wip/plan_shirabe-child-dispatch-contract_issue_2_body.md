---
complexity: testable
complexity_rationale: "Two subsections to update in the pattern reference; discipline content must be preserved verbatim while binding-layer description changes. Grep checks confirm the rework lands; verbatim preservation needs careful diff."
---

# Issue 2: docs(parent-skill-pattern): rework Binding Notes for /charter and add Binding Notes for /scope

## Goal

Reword the existing `### Binding Notes for /charter` subsection in `references/parent-skill-pattern.md` to reflect the new contract's binding (R19/I-7 binds inside the child against the child's own peers, not at the child-skill-dispatch layer). Add a new `### Binding Notes for /scope` subsection symmetrically. Discipline content stays verbatim.

## Acceptance Criteria

- [ ] **AC2.1** — `### Binding Notes for /charter` exists and has been reworded to describe R19/I-7 binding inside the child against the child's own peers (not at the child-skill-dispatch layer with parent as team-lead).
- [ ] **AC2.2** — `### Binding Notes for /scope` exists symmetrically with parallel wording to /charter's, differing only in parent name and child name (/scope's children are /brief, /prd, /design, /plan).
- [ ] **AC2.3** — Discipline content elsewhere in `## Team-Lead Operating Discipline` (sleep-check-nudge loop, terminal exits PASS/FAIL/ESCALATE, timing table, idle-pings-are-not-inbox-messages rule, nudge content rule, ci_outcome semantics) is byte-identical to the pre-edit version. Verify by diff.
- [ ] **AC2.4** — Both Binding Notes subsections cite the new `## Dispatch Contract` section as the source of which mechanism the discipline binds against (per AC12).
- [ ] **AC2.5** — Verify: `grep -cE '^### Binding Notes for /(scope|charter)$' references/parent-skill-pattern.md` returns `2`.

## Dependencies

**Dependencies**: Issue 1
