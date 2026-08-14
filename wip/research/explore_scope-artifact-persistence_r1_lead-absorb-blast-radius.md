# Lead: What breaks downstream when an UPPER hop absorbs — a PRD into a DESIGN, or a DESIGN into a PLAN?

## Findings

### 1. Walking the Stage 3 absorb procedure with a PRD or DESIGN as the absorbed artifact

The procedure is `skills/scope/references/phases/phase-2-chain-orchestration.md:485-501`:
read the absorbed artifact's `upstream:`, set the survivor's `upstream:` to that
value (or remove it), `git rm` the absorbed artifact, re-run `shirabe validate`
on the survivor, revert on non-zero.

Five things go wrong when the absorbed artifact is a PRD or a DESIGN.

**(a) The re-point is a SET, not a splice — and one-to-many lineage is now real.**
Step 2 (`phase-2-chain-orchestration.md:487-492`) says "Set the survivor's
`upstream:` to that value." That was safe while every `upstream:` was
single-valued. PR #271 (`9f45603`) made YAML sequence values survive frontmatter
parsing for the first time — see the commit body, "YAML sequence values never
survived frontmatter parsing, so the chain walk's list handling ... had never
once been reachable", and `crates/shirabe-validate/src/upstream.rs:82-91`
(`field_entries` handling `FieldEntries::Sequence`). Two concrete losses now
follow:

- A DESIGN naming two PRDs. Absorbing one PRD overwrites `upstream:` with that
  PRD's parents and silently drops the reference to the *other* PRD. The other
  PRD instantly becomes an unreferenced document.
- A PRD naming both a BRIEF and a ROADMAP (the `consumed_upstream:` shape #271
  added — `phase-2-chain-orchestration.md:166-171`). Absorbing the PRD into a
  DESIGN replaces the DESIGN's `upstream:` with that pair, which is correct, but
  the DESIGN's own other upstreams (if any) are gone.

The procedure has no merge/dedupe rule and no statement about cardinality.

**(b) There is no retirement guard.** `git rm` in step 3 is unconditional. The
finalization walk grew exactly this guard in #271
(`crates/shirabe-validate/src/finalize.rs:26-43`, and the decision logic at
`finalize.rs:800-855`): before retiring an ancestor it consults
`lifecycle::build_referrer_map` (`lifecycle.rs:539-554`) and refuses to retire a
document that another non-terminal document still names as `upstream:`. The
commit body names this as "the path that left five documents in this repository
carrying dangling upstream references." The absorb path has no equivalent check,
so absorbing a shared PRD or DESIGN reintroduces the exact failure #271 just
closed — on a different code path, three weeks later.

**(c) The re-validate in step 4 cannot see the damage.** Step 4 runs
`shirabe validate` on **the survivor only**. R6
(`crates/shirabe-validate/src/checks.rs:759-860`) is a per-document check: it
tests the document's own `upstream:` entries. A document stranded by the absorb
is a *different* file, so its R6 failure is not in the survivor's report and
step 4's revert never fires. Verified live: the repo already carries this state
—

```
$ ./target/debug/shirabe validate docs/briefs/BRIEF-single-pr-plan-validation.md --visibility=public
::error file=...,line=4::[R6] upstream "docs/plans/PLAN-roadmap-plan-standardization.md" does not exist on disk
EXIT=2
```

**(d) The deletion target is outside the closed write-target set.** Both
`skills/scope/references/phases/phase-3-exit-finalization.md:293-297` and
`skills/scope/SKILL.md:715-728` enumerate the consolidation judgment's deletion
target as exactly one path: `docs/briefs/BRIEF-<topic>.md`. Phase 3 states
"Writes outside this set fail the R9 hard-finalization check"
(`phase-3-exit-finalization.md:277-281`). A PRD or DESIGN absorb deletes
`docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`, or
`docs/designs/current/DESIGN-<topic>.md` — none of which is in the set. Under
the contract as written, an upper-hop absorb fails R9 at finalization. This is a
written security-surface enumeration (`SKILL.md:713-731`), not an incidental
list, so it needs an explicit amendment rather than a quiet widening.

**(e) `child_snapshots:` is not cleaned up, and resume then hunts a deleted
file.** Stage 3's four steps never touch `child_snapshots:`. The resume ladder
(`skills/scope/references/phases/phase-resume.md:138-151`) compares each
snapshot's frozen `{status, content_hash}` against "the live child doc at the
canonical durable path", computing `git hash-object` on it. For an absorbed
child that path does not exist and the contract has no absent-file branch, so
re-entry after an absorb either fires a spurious staleness prompt or errors.
This is latent for BRIEF absorbs today; roll-forward through every hop makes it
up to three phantom snapshots per run.

### 2. What else in `shirabe-validate` reads cross-document links

Cross-document readers, and what a deleted PRD/DESIGN does to each:

| Reader | Location | Effect of the deletion |
|---|---|---|
| R6 `check_upstream_resolves` | `checks.rs:759-860` | **Error** on every *other* doc whose `upstream:` named the deleted file: "does not exist on disk" / "is not tracked by git". Not caught by the absorb's own re-validate (see 1c). |
| L04 (missing upstream parent) | `lifecycle.rs:645-655` | Error, but only for docs the chain walk reaches — chains root at a PLAN or ROADMAP (`lifecycle.rs:592-600`). A stranded BRIEF/PRD with no PLAN below it is not a chain member and L04 never fires on it. |
| L02 orphan rule | `lifecycle.rs:1255-1337` | Fires on the stranded doc *unless* it is at its terminal status. `has_tactical_upstream` does `idx.get(p)` (`lifecycle.rs:1312-1315`); a deleted parent resolves to `None`, so the linkage exemption evaporates and a non-terminal stranded doc becomes an L02 violation attributed to the wrong document. A Done/Current one passes silently while its `upstream:` dangles — which is why the five existing dangles sit unnoticed (all six BRIEFs I checked are `status: Done`). |
| L08 conflicting chain requirements | `lifecycle.rs:38-44` (added by #271) | Absorbing one of two chains' shared parent removes half the conflict without resolving it. |
| L07 DESIGN location rule | `lifecycle.rs:1360-1384` | Fires if an absorb ever *moves* rather than deletes a DESIGN; also the reason the absorb has two candidate paths for a DESIGN (`docs/designs/` vs `docs/designs/current/`). |
| `build_referrer_map` / finalization guard | `lifecycle.rs:539-554`, `finalize.rs:800-855` | The one guard that would have prevented the strand — and the absorb path does not call it. |
| FC06 index alias | `checks.rs:639-720`, `table.rs:372-426` | **Not affected.** FC06 is explicitly document-local: it resolves dependency cells against rows in the same table, never across files. Not a blast-radius surface. |
| `upstream::field_entries` | `upstream.rs:69-91` | The single normalizer all three readers share. Placeholders (`<...>`) are skipped and cross-repo `owner/repo:path` entries are marked-not-removed — so a cross-repo `upstream:` on an absorbed doc must be preserved verbatim by the re-point, not resolved. |

**CI is diff-scoped, so the damage is deferred and misattributed.**
`.github/workflows/validate-docs.yml:79-100` computes the changed-file set with
`git diff` and passes those paths positionally. A doc stranded by an absorb is
not in the PR's changed set, so R6 never fires at the moment the strand is
created. It fires the next time somebody edits that doc for an unrelated reason,
in an unrelated PR, and looks like that PR's fault. The whole-tree
`--lifecycle .` run (`.github/workflows/lifecycle.yml:135-137`) is the only
corpus-wide gate, and per the table above it stays quiet on terminal-status
strandings.

### 3. Lifecycle: absorbing at a settled status

The re-entry protection table (`phase-1-discovery.md:115-122`) treats these as
settled: BRIEF at Accepted/Done, PRD at Accepted/In Progress/Done, DESIGN at
Accepted/Planned/Current, PLAN at Active/Done.

By the time an upper-hop absorb would run, both artifacts are already at settled
statuses by construction. `/design`'s PRD mode bumps the PRD to **In Progress**
(`phase-2-chain-orchestration.md:186-189`) and `/plan` sets the source DESIGN to
**Planned** (`skills/plan/SKILL.md:454,469`). So a PRD-into-DESIGN absorb deletes
an In-Progress PRD and a DESIGN-into-PLAN absorb deletes a Planned DESIGN — in
both cases a document the skill's own re-entry protection was written to refuse
to clobber. The two rules now point in opposite directions on the same file, and
nothing in Phase 2 reconciles them.

The re-entry protection also breaks on the *next* run. It globs canonical paths
(`phase-1-discovery.md:55-62`). After a PRD is absorbed, a later
`/scope <same-topic>` finds no PRD at `docs/prds/PRD-<topic>.md`, so `/prd` is
**not** skipped and re-authors the document the absorb deleted — while `/design`
*is* skipped (its DESIGN is settled). The run ends with a freshly written PRD
that nothing points at and that points at nothing: an L02 orphan, plus the
content duplication the consolidation judgment exists to remove.

Things that assume a DESIGN persists:

- **`finalize-chain`.** Its whole dispatch table is per-node
  (`finalize.rs:88-107`): `TransitionDesign` (strip Implementation Issues, move
  to `docs/designs/current/`), `TransitionPrd`, `TransitionBrief`. With the
  upstream chain absorbed away, the walk from the PLAN yields a single
  `DeletePlan` node and nothing else. That is arguably correct — but see the
  roadmap handoff below.
- **The `/execute` R5 finalization guard.** `skills/execute/SKILL.md:534-553`:
  post-finalization the PLAN is gone, so `--lifecycle-chain` "must be the durable
  surviving anchor: the DESIGN at its terminal
  `docs/designs/current/DESIGN-<slug>.md`, or the BRIEF/PRD at Done — never the
  deleted PLAN path (which returns `L05` / exit 2 and reads as a false
  failure)". And: "CI seeds on the surviving DESIGN anchor (**always present in
  a finalized chain**, an unambiguous chain root)". Under full roll-forward
  there is no surviving anchor at all, and every seed a human or CI could pick
  returns L05 (`lifecycle.rs:1545-1556`) — indistinguishable from a real
  failure. The whole-tree `--lifecycle .` scan still works; the per-chain seed
  rule becomes unsatisfiable and its written justification becomes false.
- **The roadmap `**Downstream:**` rewrite.** `skills/execute/scripts/run-cascade.sh:438-457`
  rewrites the ROADMAP feature's `**Downstream:**` to the DESIGN's post-move
  basename, sourced from `CASCADE_DESIGN_PATH` which is only set by a
  `transition_design` node (`run-cascade.sh:780-785`). With no DESIGN node,
  `CASCADE_DESIGN_REF` is empty and the awk **prints the original line
  unchanged** (`run-cascade.sh:448-453`) — the step still reports `ok`. The
  ROADMAP is left pointing at the plan slug whose PLAN was just `git rm`ed. A
  silent dangling reference, no failure signal.

### 4. Interaction with PR #271 (chain cardinality)

#271 is the most recent change to this area and it cuts against upper-hop
absorption in three ways.

First, it made lineage genuinely one-to-many. Before it, "set the survivor's
`upstream:` to the absorbed artifact's value" was total; after it, it is lossy
(finding 1a).

Second, it built the retirement guard the absorb lacks (finding 1b) —
`build_referrer_map` + the blocked-node reporting in `finalize.rs`. The API
exists, is public, and is exactly the shape the absorb needs: canonicalize, look
up referrers, treat "retired by this same operation" and "already terminal" as
non-blocking, block otherwise.

Third, it introduced `--upstream` on both parents and both head children so a
chain can *record* an upstream it did not produce
(`phase-2-chain-orchestration.md:166-171`, `consumed_upstream:` in the state
file). That makes the absorb's re-point strictly harder: the value being copied
forward may be a ROADMAP in another repo (`owner/repo:path`, marked-not-resolved
per `upstream.rs:124-141`) rather than a local tactical artifact.

### 5. What on disk points at a PRD or a DESIGN today

`upstream:` frontmatter: 88 documents carry one. Five already dangle, all
pointing into the roadmap-plan-standardization chain, and all five citing docs
are at `status: Done`:

- `docs/briefs/BRIEF-lifecycle-passing-state-validation.md:18`,
  `docs/briefs/BRIEF-table-diagram-reconciliation.md:20`,
  `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md:22` →
  `docs/designs/DESIGN-roadmap-plan-standardization.md` (the DESIGN was
  *promoted*, not deleted — it lives at `docs/designs/current/` now).
- `docs/briefs/BRIEF-cascade-outline-ac-completeness.md:16`,
  `docs/briefs/BRIEF-single-pr-plan-validation.md:4` →
  `docs/plans/PLAN-roadmap-plan-standardization.md` (deleted by the finalization
  cascade).

That second pair is the exact scenario the lead asks about, already realized: a
later chain took an earlier chain's terminal artifact as its `upstream:`, the
earlier artifact was removed by a lifecycle operation, and the citing docs now
fail R6. The first triple is worse in a way: a mere *directory move* (the
Accepted → Current promotion) was enough to strand three referrers. An absorb is
a strictly harder version of the same event.

Prose citations are far wider than frontmatter and are validated by nothing:
35 files cite a `docs/designs/current/DESIGN-*.md` path and 73 cite a
`docs/prds/PRD-*.md` path. `skills/scope/references/phases/phase-3-exit-finalization.md:340`
itself cites `docs/designs/DESIGN-shirabe-scope-skill.md` — already the wrong
path, since that DESIGN is at `docs/designs/current/`.

### 6. What `/execute` and `/work-on` read

`/execute` does not read the DESIGN body; it reads the PLAN and drives the
cascade. Its two DESIGN dependencies are indirect and both break: the R5 seed
anchor and the roadmap `**Downstream:**` rewrite (section 3).

`/work-on` does read the DESIGN, on the multi-pr issue path.
`skills/work-on/references/scripts/extract-context.sh:143-186`
(`find_design_doc`) searches every `docs/**/DESIGN-*.md` for a row referencing
the issue number, parses the Implementation Issues table row for complexity, and
extracts the cited section as implementation context. With the DESIGN absorbed,
`find_design_doc` returns nothing and the issue loses its design context.
Related: `/plan`'s own resume detection greps GitHub issue bodies for
`Design: <design-doc-path>` (`skills/plan/SKILL.md:354`), so the path is also
baked into remote issue bodies the absorb cannot rewrite.

Nothing reads absorbed decision provenance, because no such section exists. The
Plan format's required sections (`crates/shirabe-validate/src/formats.rs:186-203`
and the per-execution-mode map at `formats.rs:56-81`) are Status, Scope Summary,
Decomposition Strategy, Issue Outlines / Implementation Issues + Dependency
Graph, Implementation Sequence. No consumer, and no validator check, looks for
carried-forward decision content. Extra sections and extra frontmatter fields
*are* tolerated (FC04 checks presence, FC15 checks the order of required
sections only — `checks.rs:210-223`; there is no unknown-field rejection), so a
provenance section can be added without a validator change. It just would not be
read by anything.

## Implications

- The absorb procedure needs the retirement guard `build_referrer_map` already
  provides, applied before `git rm` rather than after. It is the single change
  that turns the reduction back into a move.
- Step 4's re-validate must widen from "the survivor" to "the survivor plus
  every referrer of the absorbed artifact", or the revert condition never
  triggers on the failure mode that matters.
- The re-point rule needs a cardinality rule: splice the absorbed artifact's
  entries into the survivor's list, dedupe, preserve cross-repo entries
  verbatim.
- The closed write-target set in `SKILL.md` and Phase 3 must be amended to name
  `docs/prds/`, `docs/designs/`, and `docs/designs/current/` before an upper-hop
  absorb can pass R9.
- Phase 1's re-entry protection and Phase 2's absorb need to agree about what a
  settled artifact is. Today one refuses to overwrite what the other deletes,
  and a re-run resurrects the deleted document as an orphan.
- `/execute`'s R5 seed-doc rule and `run-cascade.sh`'s roadmap Downstream
  rewrite both assume a DESIGN survives. Both are written as load-bearing and
  both fail quietly, not loudly.
- Prose citations are the largest surface (73 files cite a PRD path) and nothing
  validates them at all. Any roll-forward design has to decide whether that is
  in scope or explicitly accepted.

## Surprises

- The blast radius is not hypothetical. Five documents in this repo already
  carry dangling `upstream:` refs, `shirabe validate` returns exit 2 on them
  today, and CI does not notice because it is diff-scoped.
- Three of those five were stranded by a *directory move*, not a deletion — the
  DESIGN Accepted→Current promotion. The corpus is more fragile to lifecycle
  operations than the absorb discussion assumes.
- The exact guard the absorb needs was written three weeks ago, in #271, for the
  finalization walk, and is a public API. The absorb path predates it and does
  not call it.
- The scope skill's own prose already asserts the property that roll-forward
  breaks: "a `/scope` run always leaves something durable behind"
  (`SKILL.md:457-459`), and `/execute` doubles down with "always present in a
  finalized chain" about the DESIGN anchor.
- FC06 is a false lead. It is deliberately document-local and has no
  cross-document surface at all.
- The absorbability table in `phase-2-chain-orchestration.md:424-428` is
  accurate against `formats.rs` as it stands: a DESIGN genuinely has no home for
  Requirements or Acceptance Criteria, and a PLAN none for Decision Drivers or
  Solution Architecture. Making upper hops absorbable means changing the
  *formats*, not just the judgment — which reopens the "does an absorb discard
  content" question the current table was built to close.

## Open Questions

- Does the survivor keep the absorbed artifact's path as an alias (a
  `absorbed_from:` field, a redirect stub) so existing referrers keep resolving,
  or do referrers get rewritten? A rewrite is a multi-file mutation the skill's
  closed write-target set currently forbids.
- What happens to remote state the absorb cannot reach — GitHub issue bodies
  carrying `Design: docs/designs/DESIGN-<slug>.md`, and PR bodies?
- If the PLAN is the sole surviving artifact and is then deleted by the
  finalization cascade, what does `--lifecycle-chain` seed on? Does the R5 guard
  need a new "chain fully retired" answer distinct from L05?
- Should absorb refuse outright when the absorbed artifact has any non-terminal
  referrer, or downgrade to `keep` (matching the carry-check abort semantics)?
- Is prose-citation breakage in scope, or explicitly accepted as it is today?

## Summary

Upper-hop absorption breaks four concrete things: the `upstream:` re-point is a
set rather than a splice and silently drops sibling parents now that #271 made
lineage one-to-many; the `git rm` has no retirement guard, so it strands any
other document citing the absorbed artifact, and the step-4 re-validate checks
only the survivor and so never reverts; the deletion target falls outside the
closed write-target set that Phase 3 says fails R9; and `/execute`'s R5
finalization guard plus `run-cascade.sh`'s roadmap `**Downstream:**` rewrite
both assume a DESIGN survives, failing as a false L05 and as a silent no-op
respectively. This is not hypothetical — five documents in the repo already
carry dangling `upstream:` refs (three stranded by a mere directory move, two by
the PLAN deletion), `shirabe validate` exits 2 on them today, and diff-scoped CI
does not catch it until an unrelated PR touches the victim. The guard the absorb
needs already exists as `lifecycle::build_referrer_map`, written for the
finalization walk in #271 and never wired into the consolidation path.
