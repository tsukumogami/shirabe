# Decision Context: Absorption visibility in a surviving document

## Question

Should a document that absorbed an upstream chain member visibly show that the
absorption happened -- that the chain ran, what it produced, and what was folded
away -- or should it read as though it had always been that shape?

## Complexity

standard (Tier 3, fast path: phases 0, 1, 2, 6)

## Mode

--auto. No user blocking. Assumptions recorded in the report.

## Constraints

- Must not degrade the survivor as a document for its intended reader.
- Must not create dangling references or add to the existing broken-reference
  class (five documents already carry unresolvable `upstream:` refs; `shirabe
  validate` exits 2 on them today and diff-scoped CI does not catch it).
- Prefer a mechanism that already exists over a new one.
- Whatever is chosen must be reachable by the judging agent at fold time and
  survive the PLAN's death and the squash merge, or else be honest about not
  surviving.

## Known Options

- **(a) No trace.** The survivor reads natively; nothing records the fold.
- **(b) Frontmatter-only trace.** Machine-readable, invisible in the rendered
  document.
- **(c) Frontmatter plus a short visible provenance line.**
- **(d) Trace outside the document**, in the durable half of the PR body that
  reaches main's git history.

## Background

`/scope` drives BRIEF -> PRD -> DESIGN -> PLAN. A consolidation judgment per hop
decides whether the upstream folds into the downstream and is deleted. Under the
settled model each type contributes one thing to the chain (illustratively
BRIEF/WHY, PRD/WHAT, DESIGN/HOW, PLAN/WHEN-as-sequence), and a survivor carries
each absorbed ancestor's *contribution* as one compact section ahead of its own
content, in chain order. Contributions accumulate transitively and are capped at
the number of ancestor types. Every fold is a distillation, so loss is by design.

The stakes: a survivor that reads natively is the better document; a survivor
that shows its lineage preserves an audit trail. DESIGN Decision 8 from #260
rejected DESIGN-to-PLAN folding precisely because it "loses the record of why the
work happened," and a visible trace is the cheapest partial answer to that
objection. But a survivor cluttered with provenance scaffolding is a worse
document for the reader it was written for, and this project's format references
are deliberate about content boundaries.

Evidence carried in from the exploration:

- `upstream:` frontmatter exists and is validated -- rule R6 resolves it to a
  tracked file. It is the natural carrier for a machine-readable trace. But #271
  made lineage one-to-many and the absorb's re-point is a set-replace rather
  than a splice, silently dropping sibling parents.
- Five documents carry dangling `upstream:` refs today (three stranded by a
  directory move, two by PLAN deletion).
- 73 files cite a PRD path in prose and nothing validates those citations.
  DESIGNs and PLANs cite requirements as bare `R<n>` numbers and there is NO
  rule anywhere in `crates/shirabe-validate/src/` that validates a requirement
  citation -- confirmed directly. Deleting a PRD orphans those references
  silently.
- `phase-3-exit-finalization.md` already states the run's production and
  absorption record goes into the PR body -- but that has no implementation,
  there is no PR on the ordinary path, and `/execute` would overwrite it with a
  full `--body-file` replacement anyway. PR body Part 1 becomes the squash
  commit message and lands on main permanently; Part 2 is trimmed at merge by a
  human editing the merge dialog.
- Repo convention: `docs/decisions/` holds standalone ADRs; `AGENTS.md` requires
  decision blocks "in the current artifact". Provenance here is artifact-resident
  by convention.
