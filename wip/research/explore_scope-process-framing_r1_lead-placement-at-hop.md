# Lead: Where does the artifact-persistence justification belong, and what already exists at the hop where the judgment fires?

## Findings

### 1. The per-hop justification already exists, and it is already two-document-scoped

`skills/scope/references/phases/phase-2-chain-orchestration.md:488-500` opens
the Consolidation Judgment section with:

```
## Consolidation Judgment

Step 8 is where the artifact set shrinks.

**Why it exists.** Three documents restating one problem at three
altitudes cost a reader three reads for one idea, and an obvious
concept articulated three times reads as ceremony. Reducing the
set is worth doing for the reader. It is only honest to do it
*here* — against two bodies that exist, where the question "does
the upstream do work the downstream does not?" has an answer. The
same question asked at Phase 1, before either document is
written, has no answer, and answering it anyway is how content
gets lost.
```

Compare `skills/scope/SKILL.md:474-478`:

```
Three documents that restate one problem at three altitudes cost a
reader three reads for one idea, and an obvious concept articulated
three times reads as ceremony. Sparing the reader that is worth
doing, and it is the only reason `/scope` ever ends a run with
fewer documents than the chain has altitudes.
```

These are the same sentence, near-verbatim, differing only in
"restate"/"restating" and the trailing clause. **The proposal in
issue #331 — "deliver it at the hop where the judgment fires, scoped
to the two documents in hand" — is already implemented in the phase-2
reference.** SKILL.md's version is the copy that should not exist.

The phase-2 version is also strictly better on the axis the issue
cares about: it is scoped ("*here* — against two bodies that exist"),
it names the failure mode of asking early ("answering it anyway is how
content gets lost"), and it sits under a heading that only an agent at
Phase 2 has reason to open.

### 2. Sentence-by-sentence diff of the two SKILL.md sections

**`## Why the Artifact Set Shrinks` (SKILL.md:472-530)** — seven
paragraphs. Where each already lives:

| SKILL.md lines | Content | Already exists at |
|---|---|---|
| 474-478 | ceremony / three-reads-for-one-idea argument | `phase-2:492-497` (near-verbatim) |
| 480-489 | "not a way to save the chain work"; the *when* distinction | `phase-2:496-500` (same argument, tighter) |
| 484-489 | history: an earlier revision decided per hop, "the party making that call was the one that benefited from not doing the work, and nothing it read could tell it what was being lost" | **nowhere else** — unique to SKILL.md |
| 491-497 | single-mechanism rule: "Nothing else in a `/scope` run removes a document" | `parent-skill-pattern.md:150-153` (pattern-level SHALL NOT); the mechanism itself at `phase-2:592-613` |
| 499-506 | withdrawn entry-altitude revision history | `phase-1-discovery.md:20-26`, `phase-1-discovery.md:305-331` |
| 508-518 | "A shorter conversation is still reached by invoking a child directly" | `phase-1-discovery.md:38-49` (near-verbatim) **and** `SKILL.md:439-445` in Chain-Proposal Output |
| 520-526 | no durable-artifact floor; every hop decidable | `phase-2:719-740` ("There is no durable-artifact floor", with both reasons and the do-not-add-a-guard prohibition) |
| 528-530 | re-entry protection recorded under its own name | `phase-1-discovery.md:28-31` |

Only the *history sentence at 484-489* has no home elsewhere. That is
precisely the sentence the issue reports as misfiring: the agent read
it as settled history explaining a withdrawn design, not as a live
warning. It would need writing fresh, in a different register, wherever
it lands.

**`## Consolidation Judgment` (SKILL.md:532-578)** — nothing in it is
unique. Keep/absorb verdicts (536-546) → `phase-2:592-613`; firing
condition (548-550) → `phase-2:502-530`; absorbability-against-documents-
not-types (551-558) → `phase-2:532-553`; the two bounding clauses
(560-566) → `phase-2:532-553` and `554-591`; carry check (567-572) →
`phase-2:637-650`. Line 574-578 is an explicit pointer to phase-2 for
"the full eight-step procedure, its rollback table, the firing
condition, and the prohibition on reintroducing a durable-artifact
floor". **This section is a summary of a reference it already points
at.** Deleting it costs no content.

**What phase-2 has that SKILL.md does not**, so nothing moves in this
direction: the firing condition's ill-posedness argument
(`phase-2:518-530`), Stage 1's deny-default routing table
(`554-591`), the citation guard's narrow-reach caveat (`583-591`),
Stage 3's eight steps (`614-674`), the rollback table (`675-697`), the
judgment YAML entry (`698-718`), cascade (`741-749`), and the
manual-fallback boundary (`750-759`).

**Net: nothing has to move. Two sentences would have to be written
fresh** — a live-warning form of the 484-489 history, and (if the
`/scope`-scoped single-mechanism claim at 491-497 is judged load-bearing
beyond the pattern-level SHALL NOT) a one-line restatement in phase-2.

### 3. Loading order: the progressive-disclosure claim holds, with two live leaks

`SKILL.md:362-364` — "Execute phases sequentially by reading the
corresponding phase file" — and the `## Reference Files` table at
`SKILL.md:403-420` bind `skills/scope/references/phases/phase-2-chain-orchestration.md`
to "Phase 2". Verified against the actual reference graph:

- `phase-0-setup.md` mentions phase-2 **zero times**; its References
  section (`phase-0-setup.md:322-333`) lists only
  `parent-skill-state-schema.md`, `parent-skill-pattern.md`, and
  `worktree-discipline.md`. Clean.
- `phase-resume.md` mentions consolidation/absorb/phase-2 **zero
  times**. Clean — the resume ladder does not leak.
- `phase-1-discovery.md` **does** point at phase-2 three times, and
  each pointer carries the conclusion with it:
  - `:33-36` — "Reducing the artifact set is Phase 2's job... See the
    Consolidation Judgment section of `phase-2-chain-orchestration.md`."
  - `:320-323` — "lives beside the judgment in
    `phase-2-chain-orchestration.md` — because that is where the
    temptation now is."
  - `:558-559` — References entry: "the Consolidation Judgment that
    reduces the artifact set after the artifacts exist."

  These are Phase-1-time invitations to open the phase-2 file. An agent
  that follows the "See" at `:35` loads the whole consolidation
  procedure at Phase 1, before `/brief` runs.

So the progressive-disclosure claim is **structurally sound at the
phase-file level and defeated at the SKILL.md level**, because SKILL.md
is loaded whole at invocation. All 968 lines — including 472-578 and the
write-target enumeration at 822-934 — are in context at Phase 0. That is
the actual disclosure defect: not that phase-2 loads early, but that
SKILL.md restates phase-2 and SKILL.md never unloads.

### 4. The rest of the disclosure surface

Checked each surface the lead named:

- **Frontmatter `description:` (`SKILL.md:3-12`)** — an agent sees this
  before anything else. It says "producing a PLAN as the terminal
  artifact" and "Do NOT use when the author already knows which artifact
  altitude they want (reach for `/brief`, `/prd`, `/design`, or `/plan`
  directly)." **No reduction leak** — no mention of consolidation,
  absorption, or a shrinking set. It does name the terminal artifact
  type and advertise direct child entry, which is the escape-hatch half
  of the argument but not the reduction half.
- **`## Chain-Proposal Output` (`SKILL.md:421-470`)** — leaks at
  `:435-445`: "the consolidation judgment does exactly that in Phase 2"
  and "the set is settled per hop after the artifacts land". This is
  the passage the issue quotes first. It is defensive in intent (it
  explains why the proposal offers no shorter chain) but it discloses
  that a shorter set is reachable downstream. The rendered proposal
  template in `phase-1-discovery.md:357-358` carries the same:
  "Any artifact that turns out to be redundant is absorbed after it and
  its successor both exist, not skipped now." That line is spoken to the
  *author*, at Phase 1, in the run's output.
- **`## Workflow Phases` table (`SKILL.md:299`)** — names "consolidation
  judgment" as a Phase 2 step. Name only, no argument. Low leak.
- **Resume ladder (`SKILL.md:322-361`, `phase-resume.md`)** — clean.
- **`references/state-schema.md`** — listed as "All phases" in the
  Reference Files table, so loadable at Phase 0. `:121-160` gives the
  full `consolidation_judgments:` shape including a worked example with
  `verdict: absorb`, `absorbed: docs/briefs/BRIEF-<topic>.md`,
  `into: docs/prds/PRD-<topic>.md`. That is the outcome, the deletion
  target, and the survivor, all before Phase 0 ends. This file is
  `/scope`-owned, so it is inside the stated blast radius.
- **`requires.tsv`** — mentions absorb only in a comment: "the absorb
  path's `git rm`". Trivial; it justifies the `git` tool declaration.
- **`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`** —
  bound to "All phases" by `SKILL.md:405`. Its Gate Vocabulary section
  (`:113-153`) states the reduction model in full, and `:142-146` names
  `/scope`'s mechanism specifically: "`/scope` defines one, its
  consolidation judgment, which reads the two bodies at each hop and
  absorbs the upstream when folding loses nothing." **This is outside
  the `/scope`-only blast radius** and cannot be moved. Its register is
  mandate-shaped rather than motivational (SHALL NOT decide before a
  child's artifact exists), so it reads as a constraint rather than an
  invitation — but it does hand a Phase-0 agent the conclusion.

### 5. Is there a natural place for a per-hop, two-document-scoped justification?

Yes, and there are two candidate positions.

The procedure is eight steps, structured as three stages
(`phase-2:614-616`): "Eight steps. Steps 1 and 2 are Stages 1 and 2
above; the rest run only on `absorb`."

1. Stage 1 — Citation preflight (`:554-591`), ceiling is `keep`
2. Stage 2 — Judgment (`:592-613`), the only stage that can return `absorb`
3. Compose the contribution, in memory (`:618-628`)
4. Carry check (`:637-650`)
5. Snapshot, then write the survivor (`:652-...`)
6. Delete the absorbed artifact with `git rm`
7. Re-validate the survivor
8. Commit

**Position A — where it is now**, at the head of the section
(`:492-500`). Already two-document-scoped. Its weakness is that it is
still a *general* argument about the mechanism, read before the specific
hop's two documents are named.

**Position B — immediately before Stage 2** (`phase-2:592`). This is
where the judgment actually fires, where both bodies are in hand, and
where the verdict can go either way. Stage 2's current text is bare:
"Read both bodies. The question is whether the upstream artifact does
work the downstream does not: does the upstream hold anything beyond its
contribution that compression into a contribution section would lose?"
That question is stated without any statement of *why the upstream
existed in the first place* — which is exactly the sink-and-source
framing the issue says is missing. A per-hop persistence justification
belongs here: this document was the sink of the step that produced it
and the source of the step that just consumed it; the step has run and
its output is in hand; the only remaining question is whether the
document still earns shelf space.

Position B is the answer to the lead's question. It requires no
restructuring — it is a paragraph inserted at `:592`, inside the stage
that already reads both documents by path.

### 6. `/charter` as a control

`skills/charter/SKILL.md` matches `consolidat|absorb|shrink` exactly
once, at `:119`, in the unrelated phrase "absorbing the violation".
`/charter` defines no reduction mechanism at all, consistent with
`parent-skill-pattern.md:144-147` ("`/charter` and `/execute` define
none"). So the control confirms the sections are `/scope`-specific and
that the pattern tolerates a parent with no reduction argument anywhere
in its SKILL.md.

## Implications

The cheapest correct fix is **deletion, not relocation**. `SKILL.md`
`## Why the Artifact Set Shrinks` (472-530) and `## Consolidation
Judgment` (532-578) are 107 lines that duplicate content already
correctly placed in `phase-2-chain-orchestration.md`,
`phase-1-discovery.md`, and `parent-skill-pattern.md`. Removing both
sections costs one sentence of unique content (the 484-489 history) and
leaves the per-hop justification exactly where the issue says it should
be. This is a much smaller edit than "move the justification to the hop"
implies, because the move already happened and the SKILL.md copy was
never retired.

The issue's stated general rule — never state the outcome of a later
decision in material delivered at the start — cannot be fully satisfied
inside the `/scope`-only blast radius. `parent-skill-pattern.md:142-146`
names the consolidation judgment and its absorb behavior, and it is
bound to "All phases". Any fix should note that the shared reference
still discloses the conclusion, and decide whether the mandate register
("SHALL NOT decide before the artifact exists") is defensive enough to
leave alone. My read: it is, because it never argues that fewer
documents are better — it only bounds *when* reduction may happen. The
harm in SKILL.md is the ceremony argument, and that argument does not
appear in the pattern reference.

`phase-1-discovery.md`'s three pointers at phase-2 are a second, smaller
leak inside the blast radius. The References entry at `:558-559` and
the "See" at `:35` both invite loading the full consolidation procedure
at Phase 1. Rewording those to describe the file by its phase rather
than by its outcome ("Phase 2's child invocation loop" rather than "the
Consolidation Judgment that reduces the artifact set") preserves the
navigation and drops the conclusion.

`references/state-schema.md:121-160` publishing a worked `absorb`
example with concrete deletion and survivor paths, under an "All phases"
binding, is the same defect the issue identifies in the security
write-target enumeration — the destination without the journey — and it
is in scope. The Reference Files table binding could be narrowed from
"All phases" to name which fields matter at which phase, or the worked
example could be reduced to field names.

## Surprises

**The fix the issue asks for is already in the tree.** Issue #331 says
"the artifact-persistence justification should not appear in `SKILL.md`
as a general argument about artifact sets. It should arrive at the hop
where the judgment fires." It already does, at
`phase-2-chain-orchestration.md:492-500`, in almost the same words. The
defect is not that the justification is misplaced; it is that it exists
twice and the early copy grew into forty lines while the correctly-placed
one stayed at nine.

**The audit trail is not removed before anyone reads it.**
`references/state-schema.md:234-238` says Phase 3 copies `chain_ran`,
`chain_skipped`, and `consolidation_judgments` into the run's PR body
before Phase 4 removes the state file, and that "the PR body is where a
reviewer can tell 'not produced' from 'absorbed into this other
document' after the scratch is gone." The issue's claim that "the audit
trail is authored by the party being audited and removed before anyone
reads it" is half right — it is self-authored, but it is preserved into
the PR body by design. Anything that argues from the trail's
disappearance should be re-checked against this.

**Eval 17 (`chain-shape-is-constant`) grades the direct-invocation
redirect against "`/scope`'s prose"**, expecting "Plan points the author
at invoking `/design` directly... and says plainly that this does not
reach a smaller artifact set, which the Phase 2 consolidation judgment
decides after the fact"
(`skills/scope/evals/evals.json`, eval id 17). That content lives in
both `SKILL.md:508-518` and `phase-1-discovery.md:38-49`. Deleting the
SKILL.md copy leaves the phase-1 copy, which is loaded at Phase 1 —
where the eval's scenario fires — so the eval should still pass. But it
is the one eval whose passing depends on an agent loading a phase file
rather than reading SKILL.md, and it is worth running rather than
assuming.

**`SKILL.md:43-46`, in the opening paragraph, already carries the
conclusion**: "a post-hoc consolidation judgment that is the only thing
reducing the artifact set and runs only after the artifacts exist." Line
43 is earlier than anything the issue names. Removing sections 472-530
and 532-578 without touching this leaves the conclusion in the skill's
third paragraph.

## Open Questions

1. Is the `/scope`-scoped single-mechanism claim ("Nothing else in a
   `/scope` run removes a document", `SKILL.md:496-497`) load-bearing
   beyond the pattern-level SHALL NOT at `parent-skill-pattern.md:150-153`?
   If a maintainer needs to know at a glance that `/scope` has exactly
   one reduction mechanism, that belongs somewhere — but "somewhere"
   might be phase-2 rather than SKILL.md.

2. Does the history sentence at `SKILL.md:484-489` — the one the issue
   says reads as settled history rather than a live warning — belong in
   phase-2 at all, or does it belong in `phase-1-discovery.md` beside
   the entry-altitude prohibition it is actually about? It is a warning
   against a *Phase 1* temptation, so phase-2 may be the wrong home for
   it either way.

3. Should `SKILL.md:43-46` be reworded in the same pass? It is inside
   the blast radius and states the conclusion earlier than either target
   section, but it is a structural declarator (it enumerates `/scope`'s
   asymmetries against the pattern) rather than an argument, so removing
   it may break the pattern-conformance narrative.

4. Does the `parent-skill-pattern.md` Gate Vocabulary disclosure need
   addressing, given the `/scope`-only blast radius? It is a different
   repo path (`${CLAUDE_PLUGIN_ROOT}/references/`) shared with
   `/charter` and `/execute`. My read is no — it is mandate-shaped, not
   motivational — but that is a judgment the author should confirm.

## Summary

The per-hop, two-document-scoped justification the issue asks for already exists at `skills/scope/references/phases/phase-2-chain-orchestration.md:492-500`, in nearly the same sentences as `SKILL.md:474-478` — so SKILL.md's `## Why the Artifact Set Shrinks` (472-530) and `## Consolidation Judgment` (532-578) are duplicates, not the original; only one sentence (the 484-489 history about the party that benefited from not doing the work) has no home elsewhere, and every other paragraph is already in phase-2, phase-1-discovery, or parent-skill-pattern.

Progressive disclosure holds at the phase-file level — phase-0-setup.md and phase-resume.md never mention consolidation, and phase-2 is bound to Phase 2 by both `SKILL.md:386` and the Reference Files table at `:415` — but it is defeated by SKILL.md itself, which loads whole at invocation, and leaks further via three Phase-1 pointers in `phase-1-discovery.md:35, 323, 558-559`, a worked `absorb` example in the "All phases" `references/state-schema.md:121-160`, and `parent-skill-pattern.md:142-146` (outside the blast radius); the frontmatter `description:` and `requires.tsv` are clean.

Two things contradict the framing: `SKILL.md:43-46` states the reduction conclusion in the skill's third paragraph, earlier than either section the issue targets, and `references/state-schema.md:234-238` says Phase 3 copies `consolidation_judgments` into the PR body before cleanup, so the audit trail is not in fact removed before anyone reads it.
