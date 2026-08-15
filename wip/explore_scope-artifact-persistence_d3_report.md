<!-- decision:start id="absorption-visibility" status="assumed" -->
### Decision: Whether a surviving document shows that it absorbed something

**Context**

Under the settled model for `/scope`, a document that absorbs an upstream chain
member carries that ancestor's contribution as one compact section and the
upstream is deleted. That deletion costs three different people three different
things. The reviewer of the run loses the ability to tell "absorbed" from "never
produced" -- the two outcomes are byte-identical on disk. The reader of the
survivor loses the explanation for why the document opens with a Why section that
reads like it came from somewhere else. The reader of some third document that
cites the dead path loses the trail entirely, and there are roughly ninety such
citations under `docs/` today, every one an unvalidated bare path that no rule and
no CI job checks. The four candidate mechanisms are not competing answers to one
question; they serve different beneficiaries, and only some of those beneficiaries
are the ones absorption actually harms.

The forces pull in opposite directions. DESIGN Decision 8 from #260 rejected
folding a DESIGN into the PLAN precisely because it "loses the record of why the
work happened," and a visible trace is the cheapest partial answer to that
objection. Against that: the whole point of folding is a better document, and a
survivor wearing provenance scaffolding is worse for the reader it was written
for. The project's format references are deliberate about content boundaries.

Two findings settle more than they look like they should. First, the validator has
no opinion: frontmatter is parsed generically (`frontmatter.rs:192-255`), FC01
only checks that a format's *required* keys are present (`checks.rs:76-89`), and no
rule anywhere iterates a document's own keys to complain about one it does not
recognise. A new `absorbed:` key on a DESIGN passes `shirabe validate` silently
today. `upstream:` is the only path-resolved frontmatter value in the crate
(`checks.rs:791-864`), and body prose is never path-resolved at all, with no link
checker among the 23 CI workflows. So a trace naming a deleted path cannot join
the existing dangling-reference class -- and equally, nothing will keep it honest.
Second, this pattern already ships. `shirabe transition` writes a `superseded_by:`
frontmatter key (`transition.rs:1271-1293`) *and* splices
`Superseded by [name](path)` into the `## Status` body (`transition.rs:1301-1318`)
for supersession, which is the nearest existing analogue of absorption. Three more
machine-body-write sites exist. A machine-inserted provenance line is house
pattern, not invention.

**Assumptions**

- The `/scope` procedure that performs the absorb is the thing that writes the
  trace, in the same step that writes the contribution section. If instead the
  trace is written by a separate pass, it can drift from the section it describes
  and the pairing argument weakens.
- `crates/shirabe-validate/` is the only frontmatter validator; no skill enforces
  an ad-hoc key allowlist in its own phase files (the research grepped the Rust
  crate exhaustively but did not audit every skill phase). If wrong, `absorbed:`
  moves from zero-cost to one-file-cost.
- PR body Part 2 is trimmed by a human in the merge dialog and does not reach
  main. If wrong -- if Part 2 lands -- alternative D gets meaningfully stronger,
  because the full absorption table would sit in `git log` rather than only
  whatever survived into Part 1.
- `superseded_by:` is genuinely never read back by any consumer (only writes were
  found). If wrong, there is a stricter precedent for lineage-key validation than
  reported, and `absorbed:` would inherit an expectation of being resolved.
- Made in `--auto` mode without user confirmation, hence `status="assumed"`
  regardless of the evidence quality.

**Chosen: Frontmatter key plus one visible line in `## Status`**

A survivor records what it absorbed in two paired places.

The machine-readable half is a new frontmatter key, `absorbed:`, taking the same
scalar-or-sequence shape `upstream:` takes after the one-to-many change
(`upstream.rs:82-91`), listing the repo-relative path of each folded ancestor.
It is **explicitly excluded from path resolution**. R6 is the only rule that
resolves a frontmatter value to a tracked file; wiring `absorbed:` into it would
guarantee a dangling reference on every single fold, because the target is deleted
by construction. That exclusion has to be written down in the design rather than
left implicit, since adding the resolution is exactly the helpful-looking change a
future contributor would make.

The human-readable half is one sentence per absorbed ancestor, spliced into the
survivor's `## Status` section, naming what was folded *and* which contribution
section now carries it -- roughly "Absorbed `docs/briefs/BRIEF-<topic>.md`; its
framing is the Why section below."

Two details do the real work. Placement: `## Status` is the lifecycle section, not
the substantive body, and `brief-format.md:113-117` already blesses free prose
there carrying transition context. A reader who came for the document's content
never has to walk past the trace. Direction: the line points forward to the
contribution section, not just backward at a corpse, which turns bookkeeping into
navigation.

Enforcement is deliberately excluded. The trace is written by the same procedure
that writes the contribution section, and presence is the whole of what a machine
could assert anyway. A paired presence check -- `absorbed:` present if and only if
the matching contribution sections are present -- is a cheap follow-on, not part of
this decision.

**Rationale**

It is the only option that serves the beneficiary absorption actually harms, at a
price the constraints permit. The reader who lands on a rotten
`docs/prds/PRD-<slug>.md` citation months later is not holding the survivor and
does not know it exists; they have a slug and a type. A visible line in the
survivor puts the dead slug back in the working tree as a grep-reachable string,
which is the difference between "this path is gone" and "this path was folded into
PRD-<x>". Nothing else on the list does that without new machinery.

It clears all three constraints. The survivor is not degraded, because the trace
lives in the lifecycle section and is bounded to one sentence per ancestor -- and
the two rules that could have fenced it out (`prd-format.md:106-124` and
`design-format.md:277-287` on citation-versus-restatement) cut *toward* a compact
trace, since a one-liner is a citation and a re-narration is not. No format's
Content Boundaries section mentions provenance; all four fence out altitude
violations only, and three of four already carry `motivating_context:` explicitly
for "why this document exists". It creates no dangling reference, because
`absorbed:` is inert to every rule in the crate. And it is not a new mechanism: it
is the `transition.rs` supersession pattern applied to the one case that pattern
does not cover.

It also answers Decision 8 on the only terms available. The objection was that
folding loses the record of why the work happened. A trace cannot restore the
folded content -- distillation is lossy by design -- but it does record that the
work happened, what it produced, and where the distillate went, which is the
difference between a lossy record and no record.

Finally, C is the cheapest route to D rather than a competitor to it. The same
`absorbed:` key on the PLAN is precisely the carrier `/execute`'s
`pr_finalization` needs: the PLAN is still on disk at that point (deleted later,
`execute.md:466`), `/execute` already reads its frontmatter, and R14/R15 do not bar
it. The reviewer-facing record becomes an increment on top of a durable trace
instead of a second, separate mechanism -- which matters, because the
single-mechanism constraint is what killed the entry altitude.

**Alternatives Considered**

- **A -- No trace.** The survivor reads natively; nothing records the fold.
  Rejected because it concedes Decision 8's objection in full for zero saving. An
  absorbed artifact and a never-produced one become indistinguishable, the ~88
  orphaned citations get no lead at all, and the reader of a survivor that opens
  with an out-of-character Why section has no way to know it is a fold-in. The
  corpus already shows what this costs: `DESIGN-shirabe-scope-skill.md` has to say
  "inherited verbatim from `DESIGN-shirabe-progression-authoring.md`" in free
  prose four times, with no frontmatter field at all, because no mechanism exists.

- **B -- Frontmatter-only trace.** Machine-readable, invisible when rendered.
  Rejected because its only beneficiary is tooling nobody has written. It helps no
  human today: not the survivor's reader, since frontmatter does not render, and
  not the orphaned reader, who never finds the survivor to begin with. It costs the
  same as C -- zero -- so the invisibility buys nothing. It is C minus the half
  that pays.

- **D -- Trace in the durable half of the PR body.** Rejected because it serves
  review, not archaeology, and archaeology is the problem. The record would live in
  `git log` and GitHub, not grep-reachable from a working tree, and Part 2 is
  trimmed at merge by a human in the merge dialog. It is also blocked on the
  ordinary path three ways: no code references `consolidation_judgments` (zero grep
  hits across `scripts/` and `crates/`), Phase 3's write-target set is closed and
  excludes `gh` (`phase-3-exit-finalization.md:283-291`), and single-pr `/scope`
  creates no PR at all (`skills/scope/SKILL.md:164-167`) -- while `/execute`'s
  unconditional `gh pr edit --body-file` would overwrite one if it existed. Not
  rejected permanently: it is the right answer for the reviewer, and C makes it
  reachable as an increment.

- **E -- Lineage entry in the survivor's `## References` section.** Rejected on
  placement, not on substance. `## References` lists precedents the document draws
  on and that still exist; a path to a deleted file there reads as a broken
  reference rather than as a record, which is the opposite of the intent. It also
  has no frontmatter half, and it is undocumented for exactly the two formats that
  matter most here (prd and design have the convention in the corpus but not in the
  format reference).

- **F -- Tombstone the absorbed document.** Rejected because it defeats the goal.
  It is the strongest answer on the merits -- it restores the reciprocal half that
  ADR supersession and RFC `Obsoletes` provide and that absorption removes by
  construction, and every one of the ~88 citations would keep resolving -- but it
  leaves one durable file per fold in a repo whose 366-DESIGN corpus is the
  evidence that motivated #280. Trading a full document for a stub is a smaller
  version of the problem, not a fix, and it would need a new format and a new
  validator posture besides.

**Consequences**

What becomes easier: a reader of a folded survivor can tell what it is and why it
has the shape it has. Grepping a dead slug returns a live pointer instead of only
rotten citations. `/scope`'s absorb procedure gains a durable output it did not
have, and the PR-body record that `phase-3-exit-finalization.md` already promises
becomes an increment on an existing carrier rather than new machinery. The
supersession and absorption paths converge on one provenance shape.

What becomes harder: there is now a frontmatter key that no rule validates and a
body line that no rule checks, in a repo that already has five dangling `upstream:`
refs it does not catch. `absorbed:` joins `superseded_by:` and `spawned_from:` as
write-only lineage metadata, which is a real if minor accumulation of
unenforceable convention. The design must state the non-resolution rule explicitly
or someone will wire `absorbed:` into R6 and manufacture a dangling reference on
every fold. And the ~88 orphaned prose citations are *not* fixed by this -- the
trace gives them a lead, not a resolution; closing that gap needs either a
citation-validating rule or the tombstone, both out of scope here.

What this does not do: it does not make the fold lossless. Distillation discards
whatever was not the essence, by design. The trace records that a fold happened
and where the distillate went; it does not preserve what the fold dropped, and no
mechanism on this list would.
<!-- decision:end -->
