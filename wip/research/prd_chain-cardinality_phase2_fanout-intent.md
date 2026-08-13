# PRD→DESIGN fan-out: intended, tolerated, or unconsidered?

Phase 2 research for the chain-cardinality brief. Repo:
`public/shirabe` (worktree `charter-scope-parity`), with sibling repos
`public/tsuku` and `public/koto` for the real cases.

## Verdict

**Split. One PRD with several DESIGNs beneath it is an INTENDED shape when
the fan-out is mediated by a ROADMAP — and an UNCONSIDERED shape everywhere
else, including inside `/scope`.**

Two separate mechanisms can produce the same `upstream:` topology, and the
project has thought carefully about exactly one of them:

- **Roadmap-mediated fan-out (intended).** A PRD covering a multi-feature
  initiative, a ROADMAP partitioning its requirements into features, and one
  DESIGN per feature. All three real cases are this. The roadmap format has a
  first-class per-feature `**Design:**` link, `/prd` explicitly supports a
  ROADMAP upstream "when the PRD is part of a multi-feature initiative", the
  strategy format sizes building blocks in units of design docs, and the
  completion cascade implements an all-features-Done guard for precisely this
  fan-out point.
- **`/design`-internal split (unconsidered).** The 8-9/10+ scaling heuristic
  in `/design` Phase 1 can propose or force a split, but its own design record
  says the split mechanics are undefined, and it has never fired in this
  corpus. Nothing downstream — not `upstream:`, not the cascade, not `/scope` —
  has a story for the second document.

The premise in the task brief that `/design`'s decomposition phase is the
producing mechanism does not hold: **all three fan-outs predate the split
heuristic being reachable in practice and none of them came from a `/design`
run.** Evidence below.

---

## 1. The split heuristic's provenance

The thresholds entered the repo in a single squash commit, `5f14a84`
(2026-03-21, "feat(skills): extract workflow skills, add decision framework,
and establish eval infrastructure (#5)") — the commit that created
`skills/design/references/phases/phase-1-decomposition.md` in its current
shape. `git log --follow` on that path returns exactly one commit, so the
thresholds have never been revised.

The rationale lives in the design doc that shipped in the same commit,
`docs/designs/current/DESIGN-decision-framework.md`, as **Decision 13:
Decision count scaling** (lines 493-522). The relevant quotes:

> Phase 1 (Decision Decomposition) applies escalating friction based on the
> count of **independent decision questions after merging coupled decisions**.
> (`DESIGN-decision-framework.md:497-499`)

> In --auto mode, the 8-9 band does NOT auto-execute the split. Auto-splitting
> violates user expectations (they asked for one doc) and **the split mechanics
> (branch strategy, resume, sibling doc naming) are undefined.** Instead, the
> agent proceeds and flags the count as a high-priority assumption for review.
> (`DESIGN-decision-framework.md:508-512`, emphasis added)

> **The binding constraint is document readability, not cross-validation cost.**
> (`DESIGN-decision-framework.md:514`)

> **Scope note:** this ceiling applies to the design skill's runtime Considered
> Options output, not to architectural design records or specification
> documents generally. (`DESIGN-decision-framework.md:516-518`)

The alternatives-considered block (lines 520-528) reasons entirely about
readability and rigidity: "too rigid for 8-9 orthogonal decisions", "users
always override suggestions", "misses the readability constraint". The one
rejected option that would have touched lineage — **"Hierarchical
decomposition"** — is dismissed as introducing "a new document type and
two-level cross-validation for a problem that rarely arises"
(`DESIGN-decision-framework.md:526-527`).

**Answer to sub-question 1:** the rationale reasons *only* about document size
and reviewability. It never mentions `upstream:`, the doc index, or chain
validation. It does explicitly acknowledge that sibling-doc naming, branching,
and resume are undefined — which is a statement that the consequences of a
split were noticed and deliberately left open, not resolved.

Corroborating: `skills/design/references/quality/considered-options-structure.md:48`
("When to Split Into Multiple Decisions") is about splitting one question into
several **decisions inside one document**, not into several documents. And
`skills/plan/references/phases/phase-2-milestone.md:88` says the opposite of a
lineage-aware split — it routes large work into "multiple designs, each with
`needs-design` issues spawning the sub-designs", i.e. back through the
roadmap/issue mechanism, not through a `/design` self-split.

---

## 2. The three real cases

### Case A — tsuku `PRD-auto-update.md`, 9 DESIGNs

All nine carry `upstream: docs/prds/PRD-auto-update.md`. They are consistent
in value and inconsistent only in frontmatter position (line 3 for most, line
18 for `DESIGN-update-outcome-telemetry.md`, line 20 for
`DESIGN-project-level-auto-update.md` — those two put `upstream:` after the
`problem/decision/rationale` blocks).

They did **not** land in one commit. `git log --diff-filter=A` in
`public/tsuku`:

```
a2ece13e 2026-03-30 docs: add auto-update PRD and roadmap (#2180)
3bb94bdd 2026-03-31 feat(update): channel-aware version resolution (#2195)
b988fd3a 2026-03-31 feat(updates): add background update check infrastructure (#2197)
2174234e 2026-03-31 feat(updates): add auto-apply with rollback (#2198)
9823df4c 2026-04-01 feat(updates): add self-update mechanism (#2199)
a5a70c22 2026-04-01 feat(telemetry): update outcome telemetry (#2213)
80bd5d16 2026-04-01 feat(updates): add notification system with suppression (#2212)
610b3fcc 2026-04-02 feat(updates): add update polish (#2217)
2542606a 2026-04-02 feat(update): project-level auto-update integration (#2219)
4ed1ce0d 2026-04-02 feat(updates): add resilience (#2224)
```

This is **not** drift. The PRD landed with a ROADMAP in the same commit
(`a2ece13e`), and `docs/roadmaps/ROADMAP-auto-update.md` pre-declares the
whole fan-out: nine `### Feature N` entries, each carrying a
requirement-partitioned upstream and a design link. E.g.
`ROADMAP-auto-update.md:33-37`:

```
### Feature 1: Channel-aware version resolution ([#2181](...))
**Dependencies:** None
**Status:** Done
**Upstream:** [PRD-auto-update](../prds/PRD-auto-update.md) (R1, R2, R6, R15a)
**Design:** [DESIGN-channel-aware-resolution.md](../designs/current/DESIGN-channel-aware-resolution.md) (Current)
```

The requirement partitions are disjoint across features (R1/R2/R6/R15a, then
R4/R5, then R3/R9/R10/R11a, … R17, R22), with a separate "Cross-cutting
constraints" section for R19 and R21 that every design must honour
(`ROADMAP-auto-update.md:108-113`). Each DESIGN accreted one PR at a time
because the roadmap sequenced them that way — the plan for nine designs
existed before the first one was written.

`ROADMAP-auto-update.md` has **no `upstream:` field**, and `PRD-auto-update.md`
has no `upstream:` either. So the PRD and the ROADMAP are siblings here, not
chained: the initiative-level PRD was written first and the roadmap sequences
it. That inverts the documented chain order (`pipeline-model.md` puts ROADMAP
above PRD), which is the second-order oddity in this case.

`PRD-auto-update.md` frontmatter is `status: Accepted` today, while the
ROADMAP is `status: Done` and all nine designs are `Current`. It never reached
Done — but that is pre-cascade history, not a guard failure (see §5).

### Case B — koto `PRD-gate-transition-contract.md`, 4 DESIGNs

Identical shape. `d7382b7` (2026-03-31, "docs: gate-transition contract PRD
and roadmap (#115)") added the PRD and `ROADMAP-gate-transition-contract.md`
together; the commit message says outright "The roadmap sequences this into 4
features with GitHub issues." The roadmap's four features carry disjoint
requirement partitions:

```
Feature 1 → (R1, R2, R3, R4a, R11)
Feature 2 → (R4, R5, R5a, R6, R7, R8, R12)
Feature 3 → (R9)
Feature 4 → (R10)
```

The four designs then landed one per PR over 2026-04-01 → 2026-04-03 (`5dd3e48`,
`64d50ac`, `48a166c`, `ce0f84a`). The roadmap file no longer exists — deleted
in `70ba97c` ("docs: audit and clean up docs/ (#169)") — so today the four
designs look like a bare 1→4 fan-out with the mediating artifact gone. That is
the one genuine drift finding: **the intent record was deleted, leaving the
topology without its explanation.**

### Case C — koto `PRD-session-persistence-storage.md`, 2 DESIGNs

`58ad7e8` (2026-03-27) and `ecddd32` (2026-03-28), six days and one day before
the roadmap era respectively. Two designs, `DESIGN-local-session-storage.md`
and `DESIGN-config-and-cloud-sync.md`, both `upstream:` the same PRD. No
roadmap was ever committed for this one. This is the case closest to plain
accretion.

### Timing, which settles the mechanism question

`/scope` shipped 2026-05-31 (`20fb8ed`, PR #127) and `/charter` 2026-05-25
(`05f0eda`, PR #96). Every fan-out DESIGN above landed between 2026-03-27 and
2026-04-03 — one to two months earlier. **None of the three cases could have
come from a `/scope` chain, and none shows any trace of a `/design` Phase-1
split** (no sibling-numbered docs, no shared decision manifest, staggered
per-feature PRs with per-feature GitHub issues).

---

## 3. Deliberate statements about plural downstream

**The format references permit it, and one of them sizes it explicitly.**

- `skills/prd/references/prd-format.md:92-93` — "**Downstream Artifacts** —
  added when downstream work starts. Links to design docs, plans, issues, or
  PRs that implement this PRD." Plural, unbounded, optional. Nothing forbids
  more than one design.
- `skills/prd/SKILL.md:81-84` — the `--upstream` flag "Typically points to a
  Roadmap document **when the PRD is part of a multi-feature initiative**."
  This is the closest thing to an explicit blessing of the initiative-PRD
  shape, though it puts the ROADMAP *above* the PRD, not beside it.
- `skills/strategy/references/strategy-format.md:372-378` — the sharpest
  deliberate statement anywhere:

  > **Downstream work volume.** Each block should map to 1-2 design docs
  > minimum once it reaches the tactical chain. Blocks with no plausible
  > downstream design are framing statements rather than coherent units of
  > work; blocks decomposing into 5+ design docs are likely conflating
  > multiple blocks. This is a sizing heuristic, not a link rule — **those
  > design docs are reached through the ROADMAP and never appear in
  > Downstream Artifacts.**

  So multiple designs per upstream unit is contemplated and even quantified —
  but the trailing clause routes them through the ROADMAP, and keeps them off
  the direct link surface.

**Nothing forbids it.** No format reference, no validator check, no CI grep
states a 1:1 PRD→DESIGN rule. `references/pipeline-model.md:113-121` draws the
chain as a single vertical line (`PRD → Design Doc → Plan`) but immediately
qualifies: "The diagram above is the full chain, not a mandatory one." It is
silent on cardinality in either direction. The only cardinality statement it
makes is about the *strategic* chain being "strict in both directions", and the
only fan-out it draws is the roadmap-branching diagram at
`pipeline-model.md:200-208`:

```
Roadmap
  ├── Feature A (needs-prd) -> /prd -> /design -> /plan -> /work-on
  ├── Feature B (needs-design) -> /design -> /plan -> /work-on
  ...
```

Note what that diagram says: the intended fan-out point is **Roadmap →
features**, and each feature gets its *own* PRD. Under that reading the three
real cases have the fan-out one level too low — an initiative-sized PRD where
the model expects a ROADMAP with per-feature PRDs beneath it.

The GitHub issue/PR search on `tsukumogami/shirabe` turned up nothing on this
topic: no closed issue or PR discusses one PRD carrying several designs.

---

## 4. The reverse direction — does 9 DESIGNs mean 9 PLANs?

**No, and the corpus shows why.** `public/tsuku/docs/plans/` contains exactly
two files (`PLAN-curated-recipes.md`, `PLAN-install-ux-v2.md`) — neither
related to auto-update. `public/koto/docs/plans/` does not exist at all.

The auto-update fan-out never produced PLAN docs because it ran under the
older multi-pr shape: each roadmap feature had a GitHub planning issue
(#2181-#2189), each design carried its own Implementation Issues section, and
each shipped as one feature PR. So the observed cardinality is
1 PRD → 1 ROADMAP → 9 features → 9 issues → 9 designs → 9 feature PRs. The
"9 PLANs and 9 milestones" worry does not materialise here because the plan
altitude was skipped entirely.

Nothing anywhere states how N plans under one PRD would relate back. The
closest statement is `skills/plan/references/phases/phase-2-milestone.md:88`,
which handles the >15-issue case by recommending "multiple designs, each with
`needs-design` issues spawning the sub-designs" — again routing back through
issues rather than defining a design-sibling relationship.

---

## 5. The scope-chain angle (sharpest sub-question)

### `/scope` binds exactly one design slot, three times over

1. **Re-entry protection** (`skills/scope/references/phases/phase-1-discovery.md:121`):
   `/design`'s canonical path is `docs/designs/DESIGN-<topic>.md,
   docs/designs/current/DESIGN-<topic>.md` — one topic slug, two lifecycle
   locations, one document.
2. **Child input argument** (`skills/scope/references/phases/phase-2-chain-orchestration.md:171-175`):
   `/plan` is invoked with `docs/designs/DESIGN-<topic>.md`. One path.
3. **R20 file-existence check** (`skills/scope/references/phases/phase-2-chain-orchestration.md:205-222`):
   tests `docs/designs/DESIGN-<topic>.md`, falling back to
   `docs/designs/current/DESIGN-<topic>.md`. The file says outright why there
   are two paths — "`/design`'s own File Location contract moves the artifact"
   — so the pair is a lifecycle pair, not a plurality allowance. The same pair
   is what `parent-skill-pattern.md:459-465` tests at hand-back.

`/design`'s File Location contract agrees: `skills/design/SKILL.md:114-120`
gives one path per lifecycle state keyed on `<topic>`, and `SKILL.md:206`
says "Final artifact: `docs/designs/DESIGN-<topic>.md`". There is no naming
convention anywhere for a sibling design produced by a split.

### `/scope` sizes the decision count that the heuristic reads

This is the part that makes the collision reachable rather than theoretical.
`/scope` Phase 1 walks the R6 shape-predicates (P1 architectural-alternatives
count, P2 new-component references, P3 complex classification) whose "verdicts
have exactly one consumer: `/design`'s decision-roster shape"
(`phase-1-discovery.md:150-154`). R7 then "sizes `/design`'s decision roster
from the R6 per-predicate verdicts" (`phase-1-discovery.md:252-254`), and the
post-PRD gate re-evaluates against the real PRD, possibly recording
`chain_revised: true` and re-narrating the roster
(`phase-1-discovery.md:88-103`).

So `/scope` is actively estimating, then correcting, the very quantity that
`/design` Phase 1 counts against the 8-9/10+ bands. **`/scope` has no ceiling
of its own.** Nothing in `phase-1-discovery.md` caps the roster, mentions 8, 9,
or 10, or contemplates a roster large enough to force a split. The word "split"
appears in `skills/scope/` only in unrelated senses (a cleanup-scope split at
`phase-4-cleanup.md:74`, an eval user-story split).

### Where the second document goes: nowhere

Under `/scope`, `/design` is invoked with the PRD path and nothing else — the
L13 amendment forbids the parent adding flags or arguments
(`phase-2-chain-orchestration.md:186-196`: "`/scope` does NOT extend the
child's `$ARGUMENTS` parser, does NOT add env-var consumption, does NOT add
flags or arguments"). So `/design` resolves its execution mode from the
CLAUDE.md header, defaulting to `interactive` (`skills/design/SKILL.md:148-150`).
That means the **Interactive** column of the scaling table applies inside a
`/scope` chain:

- **8-9 decisions** → "Present split proposal, require confirmation"
  (`phase-1-decomposition.md:45`). The proposal is presented to a human whose
  approval UX the parent has explicitly suppressed —
  `suppress_status_aware_prompt: true` in the sentinel
  (`references/fixes/sub-agent-dispatch.md:20-22`, `:31-34`) means "the parent
  presents the unified prompt at chain boundaries." A mid-child split prompt
  is not a chain boundary and has no owner.
- **10+ decisions** → "Refuse, require splitting"
  (`phase-1-decomposition.md:46`). `/design` returns with no artifact at
  `docs/designs/DESIGN-<topic>.md`. That is precisely R20's
  PASS-with-no-artifact case, and `phase-2-chain-orchestration.md:225-231`
  maps it to **STALE, routed via R8 bail-handling** — the chain bails, and the
  reported cause is a missing file, not "the design was too big to write."

And the sub-agent dispatch contract confirms nobody modelled this. The five
canonical fallback shapes (`references/fixes/sub-agent-dispatch.md:44-110`)
cover serial-self-jury, parent-delegated-approval,
decision-bypass-with-inline-resolution, inline-substitute-review, and
deterministic-mode-bypass. The per-skill binding table
(`sub-agent-dispatch.md:117-131`) lists `/design` at **Phase 2 decisions** and
**Phase 6 jury** — **`/design` Phase 1 has no row at all.** Phase 1 runs
parent-unaware. No fallback shape anywhere covers "the child needs to produce
more than one durable artifact."

### Has it ever happened?

**No.** Real `/scope` runs exist in history — `wip/scope_*_state.md` files were
committed for topics `lifecycle-draft-ready-discipline` and
`skill-cascade-lifecycle-check` (`89b712d`, `f533fc1`, both 2026-06-06),
`execute-friction` (`ebb580b`, `7ed9332`, 2026-06-20), and
`chain-cardinality` (this branch). Each produced exactly one DESIGN.

Near misses are real though. Decision counts in `public/shirabe/docs/designs/`:

| Design | `### Decision` count |
|---|---|
| `DESIGN-decision-framework.md` | 15 |
| `DESIGN-skill-extensibility.md` | 9 |
| `DESIGN-scope-consolidation-over-skipping.md` | 9 |
| `DESIGN-shirabe-scope-skill.md` | 8 |
| `DESIGN-shirabe-progression-authoring.md` | 8 |
| `DESIGN-roadmap-plan-standardization.md` | 8 |

Four documents sit inside the 8-9 split-proposal band and one — the design
that *authored the ceiling* — carries 15, half again past its own hard refusal
threshold. `DESIGN-scope-consolidation-over-skipping.md` (9 decisions) landed
2026-08-10 in `3f702b6`, well after `/scope` shipped, with a clean 1:1
`upstream: docs/prds/PRD-scope-consolidation-over-skipping.md`. So the band is
routinely occupied and the split has never once fired. Whether that is because
the heuristic is not actually enforced, or because authors merge coupled
questions down as Phase 1 instructs, the corpus does not say — but the split
path is untrodden.

### Why the cascade is the clinching evidence

The completion cascade implements a sibling-completion guard for exactly one
fan-out point, and it is not the PRD.

`crates/shirabe-validate/src/finalize.rs:358+` (`walk_chain_mode`) follows a
single `upstream:` pointer up from the PLAN and dispatches per node type
(`finalize.rs:432-435`):

```rust
Some("PRD") => (NodeAction::TransitionPrd, Some("Done".to_string()), false),
Some("Brief") => (NodeAction::TransitionBrief, Some("Done".to_string()), false),
Some("Roadmap") => (NodeAction::RoadmapHandoff, None, true),
```

The PRD → Done transition is **unconditional**. PRD is a `MembershipOnly`
transition type — `crates/shirabe-validate/src/transition.rs:15` describes the
"no-precondition path (prd, roadmap, brief base behavior)" and `:40` says
`MembershipOnly` types "accept any valid status as a target". There is no
sibling check, no "are the other designs done" query, nothing.

The ROADMAP gets the opposite treatment. `RoadmapHandoff` routes to
`handle_roadmap()` in `skills/execute/scripts/run-cascade.sh:376`, which at
`:445-457` reads every feature's status and only proceeds when all are Done:

```
# Check if all features are Done → guard ROADMAP → Done transition
local all_done=true
...
if [[ "$all_done" == "true" ]]; then
    log_info "All ROADMAP features Done. Delegating to handle_roadmap_deletion..."
```

with a re-verification in `handle_roadmap_deletion()` at `:498-514`.

**A system that builds a careful all-children-complete guard at the ROADMAP
fan-out and none at the PRD fan-out has modelled one of them and not the
other.** Under the current cascade, the first PLAN to complete beneath any of
the three real PRDs would flip that PRD to Done while the remaining designs
were still unbuilt. (The three cases never hit this: the cascade shipped
2026-06-06 in `a3c8153` / 2026-06-20 in `aebd1c1`, months after they landed.
Their PRDs sit at `Accepted` for pre-cascade reasons, not because a guard
caught anything.)

---

## Summary of the evidence

| Claim | Evidence |
|---|---|
| Roadmap-mediated fan-out is intended | `ROADMAP-auto-update.md:33-113` per-feature `**Design:**` + disjoint requirement partitions; `strategy-format.md:372-378` sizes blocks in design docs; `prd/SKILL.md:81-84` blesses multi-feature-initiative PRDs; `prd-format.md:92-93` permits plural downstream links |
| All three real cases are roadmap-mediated | tsuku `a2ece13e` and koto `d7382b7` land PRD+ROADMAP together, before any design |
| None came from a `/design` split | All designs landed 2026-03-27→04-03; `/scope` shipped 2026-05-31, `/charter` 2026-05-25; no sibling naming, no shared manifest |
| The split heuristic never reasoned about lineage | `DESIGN-decision-framework.md:493-528` — readability only; "split mechanics ... are undefined"; hierarchical decomposition rejected as rare |
| `/scope` binds one design slot | `phase-1-discovery.md:121`; `phase-2-chain-orchestration.md:175`, `:212-213`; `parent-skill-pattern.md:459-465`; `design/SKILL.md:114-120` |
| `/scope` sizes the count the heuristic reads, uncapped | `phase-1-discovery.md:150-154`, `:252-254`, `:88-103`; no 8/9/10 anywhere in `skills/scope/` |
| A mid-chain split has no landing zone | `sub-agent-dispatch.md:117-131` — `/design` Phase 1 absent from the binding table; a 10+ refusal maps to R20 PASS-with-no-artifact → STALE → R8 bail (`phase-2-chain-orchestration.md:225-231`) |
| Reachable but never reached | Four shirabe designs in the 8-9 band, one at 15; four real `/scope` runs, each one DESIGN |
| The cascade models roadmap fan-out and not PRD fan-out | `run-cascade.sh:445-457`, `:498-514` (all-features guard) vs `finalize.rs:433` + `transition.rs:15,40` (unconditional PRD→Done) |
| One case lost its intent record | koto's `ROADMAP-gate-transition-contract.md` deleted in `70ba97c` |
