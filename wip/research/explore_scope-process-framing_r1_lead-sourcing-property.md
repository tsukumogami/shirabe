# Lead: Can the chain be made self-sequencing by what it discloses and when — is the sourcing property real or aspirational?

## Findings

### 1. Inside a `/scope` run, the invocation argument is a slug-derived constant, not a value handed forward

`SKILL.md:299`'s phase table says Phase 2 will "invoke child with its
upstream artifact's path". That is literally true of the reference, but
the path is *computed*, not *received*.

`skills/scope/references/phases/phase-2-chain-orchestration.md:183-187`
is the authoritative table:

| Child | Argument |
|---|---|
| `/prd` | `docs/briefs/BRIEF-<topic>.md` |
| `/design` | `docs/prds/PRD-<topic>.md` |
| `/plan` | `docs/designs/DESIGN-<topic>.md`, plus `--upstream <roadmap-path>` when the state file carries `consumed_upstream:` |

Every entry is a fixed directory plus a fixed prefix plus `<topic>`. The
topic slug is validated at Phase 0 and is in hand before any child runs.
So the string `/plan docs/designs/DESIGN-<topic>.md` is fully derivable
at Phase 0 from the one thing the author typed. Nothing about it depends
on `/design` having run.

The only state-dependent case is the absorb path
(`phase-2-chain-orchestration.md:189-192`): "When an artifact above the
child was absorbed at an earlier hop, the argument is the surviving
artifact's path." That is a *substitution* on top of the constant, and
it fires only after a hop already ran.

The same constants are printed a second time by the R20 file-existence
check (`phase-2-chain-orchestration.md:271-275`) and a third time by the
closed write-target set (`SKILL.md:837-847`). The issue names the
write-target enumeration as the leak. It is not the only one, and it is
not even the first: the phase-2 argument table publishes the same
addresses, in the file whose job is to describe the hop.

### 2. Standalone entry: every child accepts a bare topic, explicitly and by design

This is where the property breaks hardest, and it is not incidental —
each child names the case in its own Input Modes:

- `skills/brief/SKILL.md:120` — "**Anything else** — use as the starting topic for Phase 1 scoping."
- `skills/prd/SKILL.md:74` — "**Anything else** -- use as the starting topic for Phase 1 scoping"
- `skills/design/SKILL.md:147` — "**Anything else** -- freeform topic"
- `skills/plan/SKILL.md:256-258` — "**Anything else** -- treat as a direct topic (input_type: topic). **No upstream document is required.** Use when /explore produced a clear scope with no open decisions, or when planning a well-understood list of capabilities directly."

`/plan`'s is the load-bearing one and it is the most explicit of the
four: it does not merely tolerate a bare topic, it names two legitimate
uses for one. `skills/plan/SKILL.md:399-401` reinforces it: "Direct
topics skip status validation."

`/plan`'s `argument-hint` (`skills/plan/SKILL.md:10`) is
`'<doc-path-or-topic> ...'` — the alternation is in the skill's declared
interface.

So: **no, `/plan` does not require a DESIGN path, and it does not
require `upstream:` frontmatter pointing at a real DESIGN.**

### 3. `shirabe validate` treats `upstream:` as optional, everywhere

Three independent confirmations in the Rust:

- `crates/shirabe-validate/src/formats.rs:405` — the Plan profile's
  `required_fields` is `["status", "execution_mode", "milestone", "issue_count"]`.
  `upstream` is not in it. `skills/plan/references/quality/plan-doc-structure.md:66,75`
  says the same in prose: "`upstream:` ... # optional" / "**Optional fields:** `upstream`".
- `crates/shirabe-validate/src/checks.rs:1226-1229` — `check_upstream_resolves`
  (R6) opens with `let field = match doc.fields.get("upstream") { Some(f) => f, None => return Vec::new() };`.
  The doc comment at `checks.rs:1193-1194` states it outright: "The field
  is optional; an absent upstream value returns an empty vec." R6 checks
  that a *present* upstream resolves. It has nothing to say about an
  absent one.
- `crates/shirabe-validate/src/lifecycle.rs:1303-1305` — `check_orphan`'s
  first act is `if doc.format == "Plan" || doc.format == "Roadmap" { return None; }`,
  commented "Plans and roadmaps are the chain roots — they are never
  'orphan' in this sense." So even in `--lifecycle` whole-tree mode, a
  PLAN with no upstream and no chain above it is not an L02. A rootless
  PLAN is a *modelled, supported* state.

**A PLAN with no `upstream:` is valid. This is not a gap; it is a
deliberate contract stated in four places.**

### 4. FC18 confirms the issue's account exactly

`crates/shirabe-validate/src/checks.rs:421-424`:

```rust
pub fn check_fc18(doc: &Doc) -> Vec<ValidationError> {
    let line = doc.fields.get("absorbed").map(|f| f.line).unwrap_or(1);
    let entries = match parse_absorbed(doc) {
        AbsorbedDecl::Absent => return Vec::new(),
```

The doc comment at `checks.rs:401-403` says it in words: "Gated entirely
on `absorbed:` being present, so it is silent on every document that
declares no absorption."

FC19 (`checks.rs:557-560`) is gated identically — `let AbsorbedDecl::Valid(entries) = parse_absorbed(doc) else { return Vec::new(); }`.

FC18's six clauses (`checks.rs:405-412`) are all *internal consistency of
a declaration that exists*: entries are usable, well-shaped, not
cross-repo, strictly above the carrier's type, matched by contiguous
contribution sections after `## Status`, and matched by a `## Status`
absorption line. Not one of them looks at the body for an absorption
*claim*. There is no reverse check. Deleting the field moves the document
from "declaration present and false" to "declaration absent", and the
absent branch is a one-line early return.

I confirmed the issue's claim in the source rather than taking it on
faith: **nothing cross-checks a PLAN whose prose asserts consolidation
against the presence of `absorbed:`.** A grep for `absorb` across
`prose.rs` and `validate.rs` returns one comment (`validate.rs:261`) and
no check.

### 5. R9 audits the state file against itself, never against disk

`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md:287-327`:
R9's three parts are (1) `exit:` is a valid enum member, (2) sub-shape
discriminators are set when their gating `exit:` fires, (3) conditional
fields are absent when ungated. Every one is a statement about field
presence and enum membership within the file.

`chain_ran:` is never compared to what is on disk by anything. Phase 3
writes the record into the PR body (`phase-3-exit-finalization.md:69-77`)
and Phase 4 deletes the state file. The issue's "the audit trail is
authored by the party being audited" is accurate as written.

### 6. The decisive structural fact: parent and child are the same agent

`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md:499-504`,
Dispatch Mechanism, first binding:

> **Inline Skill-tool invocation.** The authoring parents (`/scope`,
> `/charter`) call the Skill tool from their own agent context with the
> child's name and the topic slug, the same way a user typing
> `/<child-name> <topic-slug>` would. **The child runs in the parent's
> agent context** and constructs whatever team it needs at the child
> layer.

Note also what the pattern itself says the parent passes: "the child's
name and the topic slug".

This is the fact that decides the lead. The sourcing property, as the
issue states it, is an *information* property: "an agent that skipped a
step is holding nothing to pass along." Under inline Skill-tool
invocation there is no boundary across which anything could fail to be
passed. One agent context holds `/scope`'s SKILL.md, the phase-2
reference with the argument table, the write-target enumeration, and
then `/plan`'s SKILL.md. Withholding an argument from yourself is not a
thing a document can arrange.

Contrast `/execute`, whose binding (`parent-skill-pattern.md:505-510`)
materializes each `/work-on` in a koto session — a real process boundary.
`/scope` does not have one.

### 7. `planned_chain:` is already a constant, and the prose already argues the point once

`skills/scope/references/phases/phase-1-discovery.md:486-488`: "That list
is a constant, and now literally so: it is `[brief, prd, design, plan]`
on every run, and re-entry protection no longer subtracts from it. Phase
1 has no input that can shorten it and no field that records a different
shape."

And `phase-1-discovery.md:303-306`: "Nothing here bounds how many
artifacts a run ends with. That is Phase 2's, decided per hop against two
documents that exist."

Eval 17 (`skills/scope/evals/evals.json`, `chain-shape-is-constant`)
grades exactly the failure the issue reports: an author who says framing
and requirements are settled "is not offered a shorter chain, because
deciding that an unwritten BRIEF is not worth writing is the exact
judgment this skill removed."

So the correct rule is already written down, correctly, and already
graded. It is in Phase 1's reference file — a file the agent in the issue
plausibly never loaded, because `SKILL.md`'s reference table
(`SKILL.md:405-419`) says to load `phase-1-discovery.md` at "Phase 1",
and an agent that has already decided to skip to the PLAN is not in Phase 1.
`SKILL.md` itself contains no equivalent statement. Its only motivated
argument is `## Why the Artifact Set Shrinks` (`SKILL.md:472-495`).

### 8. The stated commitment to standalone entry, verbatim

- `CLAUDE.md:172-175` — "The child skills `/brief`, `/prd`, `/design`,
  and `/plan` remain directly invocable on their own for authors who
  already know which altitude they want." (`CLAUDE.md:152-155` says the
  same for `/charter`'s children.)
- `skills/scope/SKILL.md:508-517` — "**A shorter conversation is still
  reached by invoking a child directly.** ... All four children ship as
  standalone entry points, so the choice is real and it stays supported.
  What it no longer is, is the route to a smaller artifact set."
- `phase-1-discovery.md:328-331` — "What survives with the redirect gone
  is direct invocation itself, narrowed. It is still how an author
  reaches the altitude they want, and what it buys is a shorter
  conversation rather than a smaller artifact set."

The repo has already done the work of separating the two contracts. It
draws the line at *artifact-set size*, not at *sequencing*.

## Implications

**The sourcing property does not hold, and prose cannot make it hold.**

Two independent reasons, either sufficient:

1. **The argument is a constant.** Even inside `/scope`, `/plan`'s
   argument is `docs/designs/DESIGN-<topic>.md`, computable from the
   validated slug at Phase 0. The skipped hop costs the agent nothing it
   needs. Suppressing the enumeration in `SKILL.md`'s security section
   does not change this: the same string is in `phase-2`'s argument table
   (the file that describes the hop), in R20's check list, in
   `/plan`'s own SKILL.md, and in the repo's directory layout. The
   address is a naming convention, not a secret.

2. **There is no boundary to withhold across.** Under inline Skill-tool
   dispatch the parent and child are one agent context. A property of the
   form "you would be holding nothing to pass along" requires a
   recipient that is not you.

Closing (1) means changing the invocation so the argument is not
slug-derivable — an opaque handle, a token minted by the previous hop.
Closing (2) means changing the dispatch binding to a real process
boundary. Both are mechanism, both are outside `/scope`, and both exceed
"prose and placement only."

**The honest smallest statement of the property, restricted to what is
true:**

> Inside a `/scope` run every child after the first is invoked with the
> path of the artifact the previous hop produced, and Phase 2 confirms
> that artifact exists on disk before the next hop begins (R20). A hop
> that did not run leaves no artifact for R20 to find, so the chain
> cannot advance past it *as `/scope` defines advancing*.

Every clause of that is verifiable against
`phase-2-chain-orchestration.md:38-51` and `:266-295`. Note what it does
*not* say: it does not say the agent would be unable to construct the
next argument. It says `/scope`'s own loop would detect the gap at the
R20 step — and R20's detection depends on the loop having been entered,
which is precisely the caveat the issue raised.

**On the tension with standalone invocability: both can hold, and the
repo already frames the distinction correctly.** They are different
contracts, and the difference is not "sourcing" — a standalone `/plan
<topic>` is legitimately sourced from a conversation. The difference is
that `/scope` is a *promise about the shape of the run*: `planned_chain:`
is the literal constant `[brief, prd, design, plan]`, and "`/scope` means
'walk the whole chain'" (`SKILL.md:517`). Standalone `/plan <topic>`
makes no such promise. The agent in the issue did not violate a sourcing
property; it violated `/scope`'s constant-chain promise while inside
`/scope`. Framing the fix as *sourcing* aims at the wrong invariant and
lands on the one contract the repo has committed to keeping open.

**The prose-reachable version of the caveat's goal.** The issue wants
"something that makes the hop unavoidable." What prose can actually
supply is not unavoidability but *un-deniability*: state, in `SKILL.md`
where the reduction argument now sits, that `planned_chain:` is a
constant, that `/scope` has no altitude selection, and that the artifact
that survives is decided at Phase 2 against two written bodies. That is
the Phase-1 text (`phase-1-discovery.md:303-306`, `:486-488`) and eval
17's expected output, promoted to the file every agent loads. It is
prose, it is placement, it is entirely true, and it directly contradicts
the sentence the agent in the issue acted on. It is the strongest honest
move available under the constraint. It is not the sourcing property, and
it should not be sold as one.

## Surprises

- **The phase-2 argument table is a bigger disclosure leak than the
  security enumeration.** The issue indicts `SKILL.md:847`. But
  `phase-2-chain-orchestration.md:183-187` publishes the same four
  addresses inside the file whose job is to explain the hop — and it must,
  because it is telling the orchestrator what to type. This is the sharpest
  demonstration that the leak is structural: the address cannot be hidden
  from the party that has to use it, and under inline dispatch that party
  is also the party that might skip.

- **Phase 2's own text already contains the sink-and-source idea, and
  reaches the opposite conclusion from `SKILL.md`.**
  `phase-2-chain-orchestration.md:15-20`: "Children are invoked with the
  artifact this chain produced above them rather than with the bare topic
  slug, so each consumes its upstream instead of re-deriving it. And the
  artifact set is reduced *here*, after the artifacts exist." And
  `:260-264`: "Invoking every child in its cold-start mode was the
  mechanical cause of the duplication this skill's consolidation judgment
  now reduces: a child handed a bare slug re-derives the framing its
  upstream already settled." The correct framing exists — in a Phase 2
  reference file, which is loaded at Phase 2, which is the phase the agent
  skipped.

- **`check_orphan` deliberately exempts PLANs from the orphan rule**
  (`lifecycle.rs:1303-1305`), calling them chain roots. The one check that
  might plausibly have noticed a rootless PLAN is written to not notice,
  on purpose, with a DECISION doc behind it
  (`DECISION-orphan-doc-passing-state-rule-2026-06-06.md`).

- **`/plan`'s bare-topic mode has named, sanctioned uses**
  (`skills/plan/SKILL.md:257-258`): "/explore produced a clear scope with
  no open decisions", "planning a well-understood list of capabilities
  directly." Removing it would break `/explore`'s documented handoff.

- **The repo already grades this exact failure and still shipped it.**
  Eval 17 is a near-verbatim description of the incident. Whatever the fix
  is, "write the rule down and grade it" is already done — in the wrong
  file.

## Open Questions

- Does the `/scope` eval suite run against `SKILL.md` alone or against
  the full reference set? If evals load references the incident agent
  did not, eval 17 could pass while the live failure remains — which would
  explain how both facts are true at once. Worth confirming before
  treating eval coverage as evidence of anything.

- `SKILL.md:405-419`'s reference table is per-phase ("load at Phase 1",
  "load at Phase 2"). If an agent's first decision — whether to run the
  chain at all — is made before loading any phase file, then `SKILL.md`
  is the *entire* basis for that decision. This looks like the real
  disclosure defect and it is squarely prose-and-placement. Confirm with
  the placement lead.

- Is `--upstream` on `/plan` ever *required* by any consumer downstream
  (`/execute`, the work-on cascade, the merge gate)? If a rootless PLAN
  breaks something later, that constraint could be surfaced as prose in
  `/plan` without new mechanism. Not investigated here.

## Summary

The sourcing property is aspirational, not real: `/plan`'s argument inside `/scope` is `docs/designs/DESIGN-<topic>.md`, computable from the validated slug at Phase 0 and printed in three places, and every child explicitly accepts a bare topic — `skills/plan/SKILL.md:256-258` says "No upstream document is required", `upstream:` is absent from the Plan profile's `required_fields` (`formats.rs:405`), R6 early-returns on an absent field (`checks.rs:1226-1229`), and `check_orphan` exempts PLANs by name (`lifecycle.rs:1303-1305`); FC18 likewise early-returns the moment `absorbed:` is deleted (`checks.rs:424`), confirming the issue's account in source.

It cannot be made real by prose, for a reason prior to any of that: `parent-skill-pattern.md:499-504` binds `/scope` to inline Skill-tool dispatch where "the child runs in the parent's agent context" — there is no boundary across which an argument could be withheld, so closing the gap requires an opaque handle or a real dispatch boundary, both mechanism and both outside `/scope`.

What prose can honestly reach instead is `/scope`'s constant-chain promise, which is already written correctly in `phase-1-discovery.md:303-306` and `:486-488` and graded by eval 17 but lives in a file loaded at Phase 1 — promote it into `SKILL.md` where the reduction argument now sits; and drop "sourcing" as the framing, because it aims at sequencing while the repo's stated commitment (`CLAUDE.md:172-175`, `SKILL.md:508-517`) deliberately keeps standalone entry open and draws its line at artifact-set size instead.
