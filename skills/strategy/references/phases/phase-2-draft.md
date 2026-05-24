# Phase 2: Draft

Author the three prose-driven sections that carry the bet: Strategic Context,
Defensibility Thesis, and Bet-Specific Falsifiability. Phase 3 owns the
structural sections (Building Blocks, Coordination Dependencies, Non-Goals,
Downstream Artifacts); Phase 2 owns the prose that makes the bet legible.

## Goal

Produce a partial STRATEGY draft with:

- A Strategic Context section that grounds the bet for a reader landing cold
  on the document.
- A Defensibility Thesis that names the falsifiable hypothesis explicitly and
  identifies its load-bearing claims.
- A Bet-Specific Falsifiability section that articulates invalidation
  conditions and corrective actions per load-bearing claim.

Frontmatter and the Status section are written at Phase 2 in their Draft
shape. Building Blocks, Coordination Dependencies, Non-Goals, and Downstream
Artifacts are placeholder-stubbed; Phase 3 fills them.

## Resume Check

If `docs/strategies/STRATEGY-<topic>.md` exists with `status: Draft`, Phase 2
or later has already produced a draft. Re-read it, identify which sections
are complete, and continue from the first incomplete section.

If the file does not exist, proceed to step 2.1.

## 2.1 Load Inputs

Read all available context:

- `wip/strategy_<topic>_context.md` (Phase 0)
- `wip/strategy_<topic>_discover.md` (Phase 1)
- The upstream document (VISION or PRD) if Phase 0 recorded one
- `skills/strategy/references/strategy-format.md` (format specification —
  load this in full at Phase 2 since the section-by-section guidance lives
  there)

Detect repo visibility from `wip/strategy_<topic>_context.md`. Load the
appropriate content governance skill:

- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

## 2.2 Private-Upstream Sanitization Warning

When Phase 0 recorded an upstream path inside a private repo AND the current
repo's visibility is Public, surface a warning to the user before drafting:

> The upstream `<path>` lives in a private repo. Quoting verbatim from a
> private upstream into a public-visibility STRATEGY would leak private
> framing into a public artifact. Phase 2 will paraphrase rather than quote
> when carrying content forward; please review the Strategic Context section
> when the draft is ready to confirm no private wording slipped through.

This is a defense-in-depth warning. The Phase 4 structural reviewer also
flags verbatim copies of likely-private content in non-gated sections, but
the author's eye at Phase 2 is the cheapest place to catch the issue.

For Public-to-Public and Private-to-Private flows the warning is unnecessary
and should not appear.

## 2.3 Write Frontmatter and Status

Create `docs/strategies/STRATEGY-<topic>.md` with frontmatter:

```yaml
---
schema: strategy/v1
status: Draft
bet: |
  <one-paragraph falsifiable hypothesis with explicit invalidation conditions>
scope: <project | org>
upstream: <path to upstream VISION or PRD, omit field if none>
---
```

The `bet` field is a paragraph-length YAML literal block (`|`). It carries
the same content the Defensibility Thesis section elaborates in prose; the
two stay in sync (the Phase 4 structural reviewer checks consistency).

Write the body Status section as:

```markdown
## Status

Draft
```

## 2.4 Draft Strategic Context

Strategic Context grounds the bet for a reader who lands on the document
cold. The format reference allows free sub-structure; what matters is the
content properties.

**Required content properties:**

- If an upstream VISION exists, carry forward its essential framing (the
  audience, the value proposition, the org fit). Paraphrase rather than
  quote when the upstream is in a private repo and the strategy is public.
- If no upstream VISION exists (org-scope case), ground the context in the
  org artifacts and framings recorded at Phase 1.
- Identify the slice of the upstream framing this strategy operationalizes.
  STRATEGY does not re-justify the long-term thesis; it picks up a piece
  and articulates the medium-term bet about realizing that piece.
- The section MUST stand alone: a reader who has never seen the upstream
  should still understand what this strategy is about after reading
  Strategic Context.

**What not to include:**

- Verbatim copies of upstream prose, especially across visibility
  boundaries.
- Re-articulation of the long-term thesis (that's VISION-altitude content,
  not STRATEGY).
- Sequenced feature decomposition (that's ROADMAP-altitude content).

Sub-headings are author's choice. The proof-by-example shape uses 2-4
short sub-sections; longer strategies may use more. Phase 4's structural
reviewer checks content properties, not heading layout.

## 2.5 Draft Defensibility Thesis

Defensibility Thesis names the bet explicitly and identifies its
load-bearing claims. The shape is short and direct.

**Required content properties:**

- Stated as a falsifiable hypothesis, not a problem statement or a
  capability list. "We bet that <thesis> because <load-bearing claims>"
  is the canonical shape.
- The thesis text matches (paraphrased) the frontmatter `bet:` field.
  The Phase 4 structural reviewer checks consistency.
- Names 2-5 load-bearing claims. Each claim is something the bet relies on
  being true; if any claim turns out false, the bet is invalidated.
  Claims should be concrete enough that a reader can imagine evidence
  that would refute them.

**Length guidance:** 1-3 short paragraphs plus the load-bearing-claim list.
Resist the temptation to write a research report. The Defensibility Thesis
is a contract, not an essay.

## 2.6 Draft Bet-Specific Falsifiability

Bet-Specific Falsifiability ties each load-bearing claim from the
Defensibility Thesis to an invalidation condition and a corrective action.
The shape mirrors the proof-by-example:

```markdown
- *If <invalidation condition>*, ... → *Corrective: <action>*
```

**Required content properties:**

- One bullet per load-bearing claim. The set of bullets MUST cover the
  load-bearing claims named in Defensibility Thesis (the Phase 4 bet-quality
  reviewer verifies this 1:1 mapping).
- The invalidation condition is observable. "If users don't adopt this"
  is too vague; "if <90% of recipe adoption comes from <5 power users
  after 6 months" is observable.
- The corrective action is a concrete strategic move, not a vague
  "we'll rethink." "Pivot to per-tool packaging" is concrete; "iterate"
  is not.
- Conditions cover both axes of failure: thesis-failure (the bet was
  wrong) and execution-failure (the bet was right but the strategy
  missed). Some bullets address one axis, some the other.

**Common failure mode:** authors write conditions that are tautologies
("if the strategy fails, we'll reconsider"). The bet-quality reviewer
catches these; Phase 2 should aim for falsifiability the first time
through.

## 2.7 Stub Remaining Sections

To pass the format reference's required-sections check, the file needs
all eight required sections present. Phase 3 fills the structural
sections; Phase 2 stubs them with placeholder content:

```markdown
## Building Blocks

<Phase 3 will decompose the bet into 5-8 coordinated workstreams.>

## Coordination Dependencies

<Phase 3 will document dependency directions across the Building Blocks.>

## Non-Goals

<Phase 3 will record what this strategy deliberately does not pursue.>

## Downstream Artifacts

<Phase 3 will list ROADMAPs, DESIGNs, and PRDs flowing from this strategy.>
```

The stubs satisfy the structural validator but make obvious to a reader
that Phase 3 has not yet run. Phase 4's structural reviewer will reject
the draft if it sees these placeholders unfilled.

## 2.8 Present the Partial Draft

Tell the user the partial draft is ready:

> The STRATEGY partial draft is at `docs/strategies/STRATEGY-<topic>.md`.
> Strategic Context, Defensibility Thesis, and Bet-Specific Falsifiability
> are written; Phase 3 will fill the structural sections (Building Blocks,
> Coordination Dependencies, Non-Goals, Downstream Artifacts) next.

Surface thematic questions the user should weigh in on. Use AskUserQuestion
for questions that have a tradeoff shape. Avoid rehashing the draft
("does the thesis look right?") — the user can read the draft themselves.

Good questions target the bet:
- "The invalidation condition for Claim 2 names a 6-month signal. Is that
  the right time horizon, or should the strategy commit to a shorter
  feedback loop?"
- "Claim 4 reads more as an execution risk than a thesis-failure mode.
  Should we drop it from Defensibility Thesis or move it to Building
  Blocks?"

Bad questions:
- "Is the Strategic Context accurate?"
- "Does the thesis capture your intent?"

## 2.9 Incorporate Feedback

After the user responds:

- **Minor changes** (wording, condition rephrasing, claim sharpening):
  Apply directly and confirm what changed.
- **Significant changes** (re-framing the thesis, swapping a load-bearing
  claim): Apply, summarize what was updated, and ask if the changes
  landed.

Loop back to Phase 1 only if the bet itself needs to change. Phase 2
feedback loops within Phase 2 by default.

## 2.10 Commit

Commit the partial draft:

```
docs(strategy): draft STRATEGY for <topic>
```

Update `wip/strategy_<topic>_context.md`'s `## Phase` line to `2`.

## Quality Checklist

Before proceeding:
- [ ] Frontmatter `schema`, `status`, `bet`, `scope` fields are present
- [ ] Strategic Context grounds the bet for a cold reader
- [ ] Defensibility Thesis names 2-5 load-bearing claims as a falsifiable hypothesis
- [ ] Bet-Specific Falsifiability covers every load-bearing claim with an observable invalidation condition and a corrective action
- [ ] Stubbed sections are present (so the file passes structural checks)
- [ ] Private-upstream sanitization warning surfaced if the visibility cross is Private-to-Public

## Artifact State

After this phase:
- Partial STRATEGY draft at `docs/strategies/STRATEGY-<topic>.md` with `status: Draft`
- Context and discovery files still in `wip/`
- Phase 3 will extend the same file

## Next Phase

Proceed to Phase 3: Structural Fill (`phase-3-structural-fill.md`)
