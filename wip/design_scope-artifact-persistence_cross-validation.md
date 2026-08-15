# Cross-validation across the six decisions

Phase 3. Each decision was reached independently; this checks their assumptions
against each other before the architecture is synthesized.

## Ordering — the one place all six meet

Four decisions constrain the absorb's step order and they agree, but only
because each was reached against a different requirement. Written out once:

1. **Citation preflight** (D4, D6). Scans git-tracked files, excluding `wip/`,
   the survivor, and `docs/folds.md`. Path hit downgrades to `keep`; bare-name
   hit becomes a finding carried into the judgment. Nothing has been mutated, so
   a refusal here is a pure abort.
2. **Content question** (D4). Does the upstream hold anything beyond its
   contribution that compression would lose? The judging agent's call, no gate.
3. **Compose the contribution** (D2), sourced from the survivor's body.
4. **Carry check** (R13, R14), evaluated against the text step 3 wrote — never a
   prediction.
5. **Splice `upstream:`** (R17), preserving sibling and cross-repo parents.
6. **Append the row to `docs/folds.md` and `git add` it** (D1), before anything
   is deleted, so a failed append aborts to `keep` with nothing lost.
7. **`git rm` the absorbed artifact.**
8. **Commit** (R19a).

No decision wants a different order. D6 said "top of Stage 3"; D4 said "Stage 1";
these name the same position, because D4 renames the stage the check now occupies.

## Assumption conflicts found: none blocking, two worth stating

**D1's exclusion needs D6's script.** D1 requires `docs/folds.md` to join R15's
exclusion set. D6 owns that set as a pinned pathspec list in a tested script. The
dependency runs one way and is not circular: D6's script gains one more exclusion
entry, and its test gains one case.

**D5's declaration is D6's R16 key and D1's row source.** `absorbed:` is defined
once by D5 as a flat list of repo-relative paths. D6 keys R16's scoping on it
("whose target document this run absorbed"), and D1's row carries the same path
in its absorbed column. Three consumers, one definition, no divergence — but the
DESIGN must say the declaration is written *before* R16 can key on it, which
places it at step 5 or earlier in the ordering above.

## Agreements reached independently, which is the useful signal

- **The survivor carve-out.** D1's V3/V4/V5 and D6 reached it separately; D6
  measured it at 36 of 36 folds refused without it.
- **The preflight's placement.** D4 and D6, from different requirements — D4 from
  R15's soft half being unsatisfiable after the verdict, D6 from a refusal before
  mutation having nothing to undo.
- **`chain_ran:` is unwritten.** D1 and D4 both found it; D4 found a fourth
  consumer I had not (the bail tie-break's per-child timestamps).
- **The write-target set is already wrong.** D1 and D2 found different halves —
  D2 that the existing `upstream:` re-point writes the survivor unlisted, D1 that
  the `docs/{briefs,prds,designs}/` entry is gated on `abandonment-forced` only,
  so the full-run absorb's survivor mutation is already outside the set.

## Contested, recorded as contested

**The revert row.** D1 settled 3-2 for removing the row rather than marking it
`reverted`, with the two principals swapping sides mid-process. Both halves agree
the un-append must be specified explicitly, since R30 forces the row to exist
before the `git rm`; without it a revert strands a durable row asserting a fold
that was undone. What removal costs: a checker cannot assert `reverted` implies
the path is present at HEAD.

## One coupling the PLAN must know about

The fold-record checker cannot trigger on deletion alone. A real merged commit in
this history removes superseded roadmaps with no fold involved, and a naive check
would fail ordinary documentation housekeeping in every repository pinning the
reusable workflow. The trigger is a fold signature — a chain-document deletion
plus an absorption declaration added in the same diff naming that path — which
couples R20's check trigger to R21's declaration. Trigger only, not surface.

## Requirements amended during the design phase

R15 (bookkeeping exclusion, and the re-point option withdrawn), R18 (narrowed to
the survivor), R19a (added: the absorb commits its own output), R20 (persistence
reading made explicit), R30 (five decision points to four). Each is recorded at
its requirement with the reason.
