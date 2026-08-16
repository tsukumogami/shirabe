# Explore Scope: fold-record-scaling

## Visibility

Public

## Core Question

`docs/folds.md` is a shared, append-only, one-row-per-fold record written by
`/scope`'s consolidation judgment. It was introduced to make an absorbed
document distinguishable from one that was never produced. The question is
whether that guarantee is worth a durable shared file at all — and if the
guarantee is worth keeping, whether a per-fold row in one repository-wide file
is the right carrier, given that the file grows without bound and is the single
place every parallel agent writes.

## Context

- Landed as part of `DESIGN-scope-artifact-persistence.md` /
  `DESIGN-scope-consolidation-over-skipping.md`, the effort to stop `/scope`
  from emitting a full artifact at every hop.
- The record is explicitly a record of the *operation*, never the content:
  date, absorbed path, survivor (`none` at a terminal fold), verdict, carried
  section outcomes, and the `git hash-object` of the pre-fold artifact.
- Concurrency is already partially addressed: `.gitattributes` gives the file
  `merge=union`. The design calls this the repository's first shared
  append-only durable file and its first merge driver, and calls the
  cross-branch duplicate a "residual, not a solved problem."
- A separate trace already exists for non-terminal folds: the surviving
  document carries an `absorbed:` frontmatter declaration and a matching
  `## Status` absorption line, both enforced by `shirabe validate`.
- The only mechanical reader found so far is the reusable CI workflow
  (`.github/workflows/validate-docs.yml`), which fires on a fold signature and
  checks row presence, blob-hash match, and additions-only.
  `skills/execute/SKILL.md` names the record as the evidence that distinguishes
  a fully-folded chain from a chain that never ran, while stating that nothing
  there reads it to make a lifecycle decision.
- shirabe is consumed by other repositories that pin the reusable workflow, so
  any answer has to hold for adopters, not just for this repo.

## In Scope

- What the record uniquely proves, and for which fold shapes.
- Whether the two stated failure modes (unbounded growth, merge contention)
  are real, and at what scale they bite.
- Alternative carriers for the same fact, and their cost.
- Blast radius of removal or replacement: checks, skills, scripts, tests, docs,
  and adopter repositories.

## Out of Scope

- Whether `/scope` should fold at all — the consolidation judgment itself is
  settled and not being reopened.
- The content of the fold (what carries into the survivor); this is about the
  record of the operation only.
- Redesigning `shirabe validate` beyond whatever this decision forces.

## Research Leads

1. **What does the fold record uniquely prove that the survivor's `absorbed:`
   frontmatter and `## Status` line do not?**
   If the surviving document already declares what it absorbed, the record may
   be redundant for every non-terminal fold. Separate the fold shapes: absorb
   into a surviving artifact, versus the terminal fold where the whole chain
   folds away and no durable artifact remains. Establish precisely which
   guarantee has no other carrier.

2. **Who reads the record today, and what breaks if it disappears?**
   Trace every consumer — the reusable CI workflow, `shirabe validate`,
   `check-citations.sh`, `/scope` phases, `/execute` and `run-cascade.sh`,
   docs, tests. For each, say whether it reads rows, writes rows, or only
   asserts the file's shape, and what its behavior would be with the file gone.

3. **Are unbounded growth and merge contention real problems, and at what
   scale?**
   Quantify: rows per `/scope` chain, expected chains per month, resulting
   file size over a year. Check whether any skill or agent actually loads the
   file into context. Then test the concurrency claim: does `merge=union`
   genuinely resolve parallel appends, what happens on a rebase rather than a
   merge, and — critically — do adopter repositories that pin the reusable
   workflow inherit the `.gitattributes` merge driver, or do they get the
   conflict without the mitigation?

4. **What else could carry the same fact, and what does each option cost?**
   Survey carriers: leaving it only in the survivor's frontmatter, a commit
   trailer or git-notes entry on the squash commit, the PR body, a per-chain
   file that retires with the chain, a machine-readable index that prunes, or
   nothing at all. For each, state what guarantee it preserves, what it loses,
   whether CI can still verify it, and what it costs an adopter repository.

5. **What is the blast radius of removing or replacing the record?**
   Enumerate every binding: the `Verify the fold record` CI step, the
   `merge=union` `.gitattributes` entry, `check-citations.sh` and its test,
   `/scope` phase 2/3/4 instructions, the `/execute` completion rule and
   `run-cascade.sh` output string, `docs/guides/doc-validation.md`, and the two
   design docs plus the PRD. Note which are requirement-backed and would need a
   documented supersession, and what a repository that already has rows would
   have to do.

6. **What did the original design consider and reject before choosing a shared
   append-only file?**
   Read the design and PRD history for the alternatives that were weighed,
   whether growth and concurrency were evaluated at the time, and what
   requirement the record is discharging. The point is to find whether the
   concerns being raised now were considered and consciously accepted, or
   simply not reached.
