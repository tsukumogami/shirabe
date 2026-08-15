# D2 Research B — Existing gating/reviewing machinery, and what the prior decisions actually said

Scope: the `shirabe` repo at
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe280_take2-e297cbad/public/shirabe/.claude/worktrees/scope-artifact-persistence`
(worktree; verified byte-identical to the shared checkout for `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`
and for the whole of `skills/scope/`). All paths below are repo-relative to that worktree root.
HEAD is `fdcd7ad`, with #260 merged as `3f702b6` and #271 as `9f45603`.

---

## Research conducted

- Full read of `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` (819 lines) and
  `docs/prds/PRD-scope-consolidation-over-skipping.md` (391 lines).
- Full read of `skills/scope/SKILL.md` §Why the Artifact Set Shrinks / §Consolidation Judgment / §Execution-Mode Flags /
  §Team Shape / §Resume Logic, and of `skills/scope/references/phases/phase-2-chain-orchestration.md`
  §Per-Child Invocation Loop / §Child Invocation / §Consolidation Judgment.
- Repo-wide grep for the single-mechanism wording; for `jury`, `advisory`, `blocking`, `veto`, `AskUserQuestion`,
  `autonomy mandate`, `--auto`, `Draft -> Active`, `independen*`, `latency`/`cost`/`expensive`.
- Read of the jury phases: `skills/prd/references/phases/phase-4-validate.md` (whole),
  `skills/brief/references/phases/phase-4-validate.md`, `skills/strategy/references/phases/phase-4-validate.md`,
  `skills/design/references/phases/phase-6-final-review.md`, plus `skills/vision/…/phase-4-validate.md`,
  `skills/roadmap/…/phase-4-validate.md`.
- Read of `references/fixes/sub-agent-dispatch.md` (162 lines — the five fallback shapes and the per-skill binding table),
  `references/decision-protocol.md`, `AGENTS.md`, `scripts/run-evals.sh`.
- Dump of all 26 scenarios in `skills/scope/evals/evals.json` and full text of the four consolidation-relevant ones.
- `git log -1 --format=%B 3f702b6` (the #260 squash commit body, which is the durable record of the PR).

---

## Findings

### Q1 — Verbatim prior art

#### Decision 5, in full (`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:253-277`)

```
### Decision 5: How an absorb is verified

- **Option A (chosen): an explicit per-section carry check, recorded as a
  table, run before the upstream is removed.** For each required section of
  the absorbed type, the check names where in the survivor that concern
  landed and marks it carried or not-carried. Any not-carried aborts the
  absorb; both artifacts stay and the finding is recorded.
- **Option B (rejected): a `shirabe validate` mode that checks the
  consolidated artifact.** "Carries the same concern" is semantic, not
  structural. The PRD's four counterpart sections are required already, so a
  structural check would pass unconditionally — worse than nothing, because
  it would look like verification.
- **Option C (rejected): trust the absorb verdict with no itemized check.**
  This is the shipped fold path: a recommendation with no receiver and
  nothing confirming the transfer. Violates D5.
- **Option D (rejected): an independent reviewer agent per absorb.** Buys
  independence the other options lack, at a per-run cost on the most common
  hop, for a check whose inputs are two documents in front of the same
  agent. Deferred; the recorded table is what makes a later reviewer
  possible.

Chosen because the itemized table is the smallest thing that makes the
transfer auditable by a human reading the PR, and because it fails in the
right direction: a section the survivor does not carry aborts the absorb
rather than losing content. Its non-independence is recorded in Consequences.
```

Note the heading says "(rejected)" for Option D while the body says "Deferred". The prose is the operative
word — three other places treat the reviewer as still available:

- `…DESIGN-scope-consolidation-over-skipping.md:761-763` (Consequences → Negative):
  "The carry check is performed by the same agent that wrote both documents. / It reads real bodies rather
  than guessing at unwritten ones, which is the improvement being bought, but it is not an independent review."
- `…:780-782` (Mitigations): "**Non-independent carry check:** the recorded table is the artifact a
  human reviewer or a later independent reviewer reads. Decision 5 Option D stays available without rework."
- `docs/prds/PRD-scope-consolidation-over-skipping.md:369-373` (Known Limitations): "The carry check in R10 is a
  judgment made by the same agent that wrote both artifacts. It is a real check against a written body rather
  than a guess about an unwritten one, which is the improvement being bought, but it is not independent."

**The stated deferral reason is three-part and only one part is about cost:** (1) per-run cost on the most
common hop; (2) "for a check whose inputs are two documents in front of the same agent" — i.e. the reviewer
would read exactly the same inputs, so independence buys less than it looks like; (3) the recorded carry table
is the enabling artifact, so deferring costs nothing later. There is no argument anywhere that a reviewer
would violate a constraint.

#### Decision 8, in full (`…DESIGN-scope-consolidation-over-skipping.md:329-351`)

```
### Decision 8: The durable-artifact floor

- **Option A (chosen): the floor is structural, and no guard implements
  it.** A `/scope` run always writes BRIEF, PRD, DESIGN and PLAN, and
  Decision 4 makes every hop above BRIEF-to-PRD unabsorbable, so the smallest
  set a run can end with is a PRD, a DESIGN and a PLAN. A run that leaves no
  durable artifact is unreachable through `/scope`, and nothing has to check
  for it.
- **Option B (rejected): an explicit guard that refuses to reduce below one
  durable artifact.** Dead code. The guard's condition cannot hold given
  Decision 4, and a check that can never fire teaches a later maintainer that
  the case is possible.
- **Option C (rejected): allow a PLAN-alone `/scope` run behind a warning.**
  Requires an altitude selection to reach at all, which Decision 1 removed.
- **Option D (rejected): make DESIGN absorbable into PLAN so the shortest
  outcome stays reachable.** The PLAN is deleted once its work is
  implemented, so this trades a durable audit trail for a shorter run and
  loses the record of why the work happened.

The PRD asks for the PLAN-alone answer to be stated deliberately rather than
left to fall out of the model, so: a `/scope` run never produces it. An
author who genuinely wants no durable record beyond the code invokes `/plan`
directly, which is a claim they are entitled to make and which is visible in
what they typed.
```

Option D verbatim is the four lines above beginning "**Option D (rejected): make DESIGN absorbable into PLAN…**".
Corresponding PRD text at `PRD-…:193-197` (R14) and `PRD-…:353-356`.

#### The carry check: who performs it, does it block, what happened on the #260 dogfood run

- **Where it is specified:** `skills/scope/references/phases/phase-2-chain-orchestration.md:456-503`
  (Stage 3), summarized at `skills/scope/SKILL.md:486-492`, required by `PRD-…:175-178` (R10),
  chosen at DESIGN Decision 5 Option A.
- **Who performs it:** `/scope` Phase 2 itself, step 8 of the per-child loop
  (`phase-2-chain-orchestration.md:62-66`). It is not delegated to any agent. The DESIGN calls this out as
  the design's own weakness: "The carry check is performed by the same agent that wrote both documents"
  (`DESIGN-…:761`). Note the literal actor is the `/scope` parent, and under sub-agent dispatch the children
  may be separate processes — but the parent is the one that read/orchestrated both bodies, and both the
  DESIGN and the PRD characterize it as non-independent.
- **Does it block the delete?** Yes, and it is the only thing that does.
  `phase-2-chain-orchestration.md:481-485`: "Any `carried: false` **aborts the absorb**: the verdict is
  downgraded to `keep`, the finding names the section that did not arrive, and both artifacts stay on disk.
  Nothing is deleted on a failed carry check." The `git rm` is step 3 of a four-step procedure that only
  begins after the check clears (`:487-500`).
- **What happens when it fails:** the verdict downgrades to `keep`; both artifacts survive; the failed table
  is still recorded so the abort is auditable (`skills/scope/evals/evals.json`, scenario
  `consolidation-carry-check-failure-aborts-absorb`, id 21).
- **The #260 dogfood run.** The mechanism that produced "shipped all four artifacts" is exactly this abort
  path: the carry check found the PRD's User Stories did not carry the BRIEF's User Journeys, so the absorb
  aborted and the BRIEF stayed. Confirmed on disk: `docs/briefs/BRIEF-scope-consolidation-over-skipping.md`,
  `docs/prds/PRD-scope-consolidation-over-skipping.md` and
  `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` all exist, and the PRD's frontmatter still
  carries `upstream: docs/briefs/BRIEF-scope-consolidation-over-skipping.md` (`PRD-…:18`) — i.e. no re-point,
  no deletion. The round-1 findings for this exploration record the same conclusion at
  `wip/explore_scope-artifact-persistence_findings.md:52-57`: "All 35 PRDs with an `upstream:` point at their
  same-topic BRIEF and no BRIEF has ever been deleted. Even #260's own dogfood run failed its carry check on
  User Journeys and shipped all four artifacts. Every code path below the verdict is untested."
  I found no committed `consolidation_judgments:` record anywhere (the `wip/` state file is deleted at Phase 4
  and the PR-body record is unimplemented per `wip/explore_…_d2_context.md:115-117`), so the failure itself is
  attested by the round-1 research and by the surviving artifacts, not by a durable machine record.

#### The single-mechanism constraint, fullest statement

The fullest wording is `skills/scope/SKILL.md:414-449` (§Why the Artifact Set Shrinks). Verbatim, the two
load-bearing paragraphs:

```
One mechanism follows from that, and only one. **The
consolidation judgment** (Phase 2) reduces the set after the
fact. It reads two written bodies and asks whether the upstream
does work the downstream does not. It can only absorb where the
downstream type's required sections have a home for every one of
the upstream's, so absorbing never discards content or invents
somewhere to put it. Nothing else in a `/scope` run removes a
document.

A briefly-shipped revision of this skill also let Phase 1 choose
an entry altitude for the chain. It was withdrawn. The question it
asked the author was more answerable than the per-hop gates it
replaced — which conversation are you having, rather than what
would an unwritten document have said — but it was still a
decision that shrank the artifact set before any artifact existed,
and having two reduction mechanisms fire at different times meant
neither read as the rule.
```

The other three statements, for comparison:

- `PRD-…:325-333`, trade-off (b), heading verbatim **"One mechanism reduces the set, and it runs after the
  fact."** — "…It was rejected: it is still a decision that shrinks the artifact set before any artifact
  exists, which is the exact shape this feature removes, and having two reduction mechanisms operating at
  different times made neither one legible. `/scope` now walks the whole chain and the consolidation judgment
  is the only thing that removes a document."
- `DESIGN-…:132-137` (Decision 1 Option B): "…But it is still a decision that shrinks the artifact set before
  any artifact exists, which is the shape this design exists to remove, and it left two reduction mechanisms
  operating at different times so neither read as the rule." And the chosen-because at `:148-151`: "Chosen
  because it leaves exactly one mechanism that reduces the artifact set, and that mechanism reads two bodies
  that exist."
- `DESIGN-…:26-27` (frontmatter rationale): "…so the chain runs whole and the consolidation judgment is the
  single mechanism that removes a document."
- Second `skills/scope/` occurrence: `skills/scope/SKILL.md:461-464` ("Anything held back for any other reason
  is re-entry protection…so the two never blur again").

### Q2 — Is a verifier a second reduction mechanism? (the framing question)

**Answer the text supports: the objection was about (i) — two things that can SHRINK the artifact set — not
about (ii) two things that make a judgment.** Every statement of the constraint is scoped by a verb of
removal, never by a verb of judging:

- "the consolidation judgment is the **single mechanism that removes a document**" (`DESIGN-…:27`).
- "it leaves exactly **one mechanism that reduces the artifact set**" (`DESIGN-…:148`).
- "the consolidation judgment is **the only thing that removes a document**" (`PRD-…:332-333`).
- "**Nothing else in a `/scope` run removes a document.**" (`SKILL.md:439-440`).
- "the only reason `/scope` ever **ends a run with fewer documents** than the chain has altitudes"
  (`SKILL.md:418-420`).
- The Goals bullet: "**Reducing the artifact set** is the only mechanism that ends a run with fewer documents
  than the chain has altitudes" (`PRD-…:86-88`).

The two mechanisms the objection actually named were (a) the withdrawn Phase 1 entry-altitude selection and
(b) the Phase 2 consolidation judgment — *both of which shrink the set*, at different times. The separate
"two mechanisms share one name" complaint at `PRD-…:53-54` names `/brief`'s fold-into-PRD branch and
`/scope`'s auto-skip — again both reductions.

Three further pieces of evidence that a check inside the judgment is not counted:

1. **The carry check already is a judgment, made at a different moment from the verdict, and nothing calls it
   a second mechanism.** Decision 5 (adopting it) and Decision 1 (declaring exactly one mechanism) sit in the
   same document, unreconciled because there is nothing to reconcile. Stage 2 reaches the verdict; Stage 3
   re-judges section-by-section and can overturn it (`phase-2-chain-orchestration.md:440-485`).
2. **Multiple things already force `keep`, and the design counts none of them as mechanisms.** An unmapped hop
   forces keep (Stage 1); a failed carry check forces keep (Stage 3); a post-absorb `shirabe validate`
   non-zero exit reverts the absorb (`:497-500`); R8 bail-handling can take the run out. The DESIGN states
   this as a property rather than a problem — `DESIGN-…:735-738`: "**Failure direction.** Every new failure
   mode fails toward keeping artifacts: an unmapped hop keeps, a failed carry check keeps, a post-absorb
   validation failure reverts the absorb. No path deletes an artifact on an error."
3. **The constraint's stated purpose is legibility of the rule, not uniqueness of the judge** — "meant neither
   read as the rule" / "made neither one legible". A veto-only reviewer does not create a second answer to
   "what removes a document"; the answer stays "the Phase 2 consolidation judgment."

What the text does *not* settle: whether a reviewer with authority to *cause* an absorb (or to overturn a
`keep`) would fall inside the constraint. By the wording above it would — it would then be a second thing that
can shrink the set. The read is therefore asymmetric and clean: **veto-only is outside the constraint; a
reviewer that can flip `keep` to `absorb` is inside it.**

### Q3 — Existing reviewer/jury patterns across shirabe skills

| Skill | Where | Agents | Parallel? | Model/effort | Output shape | Advisory or blocking? |
|---|---|---|---|---|---|---|
| `/brief` | `references/phases/phase-4-validate.md` | 2 (Content Quality, Structural Format) | Yes — "Spawn two reviewer agents in parallel via the Agent tool with `run_in_background: true`" (`:47-48`) | none specified; tools intended to be Read+Write only (`:55-63`) | file at pinned path + literal `**Verdict:** PASS \| FAIL` marker (`:96`, `:258`) | Advisory-with-escalation |
| `/prd` | `references/phases/phase-4-validate.md` | 3 (Completeness, Clarity, Testability) | Yes — "Launch all 3 agents in parallel using the Agent tool with `run_in_background: true`" (`:36`) | none specified | file `wip/research/prd_<topic>_phase4_*.md`, `## Verdict: PASS \| FAIL`, returns only verdict+count+summary | Advisory-with-escalation |
| `/design` | `references/phases/phase-6-final-review.md` | 3 (Architecture, Security, Structural-format) | Yes — "Launch three review agents in parallel using the Agent tool with `run_in_background: true`" (`:23`) | none specified | file `wip/research/design_<topic>_phase6_*.md`; "Return only key findings and recommendations" | Advisory-with-escalation |
| `/strategy` | `references/phases/phase-4-validate.md` | 3 (Bet Quality, Altitude, Structural Format) | Yes (`:45-47`) | none specified | pinned verdict file + `**Verdict:** PASS \| FAIL` | Advisory-with-escalation |
| `/vision`, `/roadmap`, `/comp` | `…/phase-4-validate.md` | jury of reviewers, same shape | Yes | none specified | same | Advisory-with-escalation |
| `/design` Phase 5 | `references/phases/phase-5-security.md:30` | 1 dedicated security agent | background | none | findings file | Advisory |
| `/plan` Phase 6 | `skills/review-plan/SKILL.md` | fast-path: 1 agent per category × 4 categories; adversarial: multiple validators per category + cross-examination | yes | none | `review_result` YAML verdict, loop-back | Loops the plan back for revision; not a deletion |
| `/work-on` Phase 4b | `references/phases/phase-4b-review.md` | code reviewers | — | — | JSON with `blocking_count` / `advisory_count` | **Genuinely blocking** — `blocking_count > 0` re-enters the coder loop; unresolvable → `review_outcome: blocking_escalate` → `done_blocked` (`:31-43`) |

**The exact instructions that settle advisory-vs-blocking.** For `/prd`, the aggregation table at
`skills/prd/references/phases/phase-4-validate.md:173-178`:

```
| Outcome | Action |
|---------|--------|
| All 3 pass | Proceed to finalization |
| 1-2 fail with minor issues | Fix issues, briefly show fixes to user, proceed |
| Any fail with significant issues | Present issues to user, incorporate fixes, re-validate if changes are substantial |
| Agents disagree on same issue | Present both perspectives, recommend the better-supported one, let the user override |
```

No row terminates the workflow. A FAIL routes to a fix or to the human; it never stops the artifact. And the
gate is explicitly relocated to the human at `:210-212`: "Use AskUserQuestion to request the verdict. Frame
the question as the agent recommending acceptance based on the jury verdicts; **the user's verdict is the
gate.**"

For `/brief`, the same shape at `skills/brief/references/phases/phase-4-validate.md:298-303` ("Both PASS →
Proceed…"; "Any FAIL with significant issues → Surface to user via AskUserQuestion with option to loop back to
Phase 2 or Phase 3"), and the Goal at `:29-33`: "…then fix issues found or surface them to the user for
resolution. By the end of Phase 4 the BRIEF should be **jury-cleared and ready for explicit human ratification
at Phase 5**." `/strategy` uses identical wording (`:25-31`, `:426-429`), and `/design` mirrors it at
`skills/design/references/phases/phase-6-final-review.md:196-199`: "Frame the question as the agent
recommending a verdict based on the Phase 6 review agents, not neutrally presenting options; **the user's
verdict is the gate.**"

So across every jury in the repo: **the jury advises the authoring agent; the human ratifies.** A jury verdict
alone cannot stop an artifact from shipping, and a jury verdict alone cannot destroy one.

**Does any jury ever cause a DELETION?** No. Every jury is a quality gate on prose. The only deletions in the
chain are (a) the `Reject` branch of the human ratification prompt — `/prd` step 4.5/4.6
(`git rm docs/prds/PRD-<topic>.md`, `:292-296`, gated behind a **second-confirmation** AskUserQuestion at
`:263-267`) and `/design` step 6.7 Reject (`:220-225`); (b) the Phase 2 consolidation absorb; (c)
`/execute`'s post-implementation cascade `git rm` of the PLAN. All three are human-gated or
verdict-gated, none is jury-gated.

**Important degradation to note.** Under parent dispatch the juries lose their independence by design.
`references/fixes/sub-agent-dispatch.md:53-61`, fallback shape 1: "**Serial-self-jury.** When the child's
normal flow spawns a multi-reviewer jury in parallel … and the dispatch context does not support parallel
sub-agent spawns, the child runs each reviewer **serially within the same process**, preserving the rubric set
but losing parallelism." Bindings: `/design` Phase 6, `/prd` Phase 4 jury, `/strategy` Phase 6 (`:60-61`).
So "an independent reviewer agent" in a `/scope` run may in practice be the same process wearing a different
rubric — which is precisely the objection Decision 5 Option D raised ("a check whose inputs are two documents
in front of the same agent").

### Q4 — Where `/scope` blocks on a human today

Enumerated blocking points in `/scope` itself:

1. **Phase 0 cold-start prompt** when `$ARGUMENTS` is empty — `skills/scope/SKILL.md:77-78`,
   `skills/scope/references/phases/phase-0-setup.md:52-59`. Blocks: asks the author to re-invoke.
2. **Phase 0 stale-session ladder**, ≥7 days — surfaces a "Resume / Force-materialize / Discard" prompt
   (`skills/scope/SKILL.md:302-306`).
3. **Phase 1 chain proposal** — a confirmation prompt containing the literal substrings **Proceed / Adjust /
   Bail** (`skills/scope/SKILL.md:377-392`). This is the one the skill says the author always answers: "the
   author still answers exactly one question here" (`phase-1-discovery.md:396-398`).
4. **Phase 2 worktree-staleness escalation** — an `Intent-changing` classification "escalates to the author
   with a three-option prompt (re-author affected artifacts; proceed against original intent …; bail per R8's
   bail-handling rule)" (`phase-2-chain-orchestration.md:103-109`).
5. **Resume ladder Slot 5/6 rows** — e.g. the `Re-supply` option, "stop and ask the author to re-invoke"
   (`phase-resume.md:108`); the drift triad Re-run / Accept / Proceed-without; the settled-upstream boundary
   rows offering **Re-evaluate / Revise / Bail** (`skills/scope/SKILL.md:308-317`).
6. **Every child's ratification gate, delegated up to the parent.** `references/fixes/sub-agent-dispatch.md:68-77`,
   fallback shape 2: "**Parent-delegated-approval.** When the child would normally prompt the author for an
   Accepted/Reject verdict, but the parent chain owns the unified prompt at the chain boundary, the child
   writes its draft to disk in a non-Accepted state (`Draft` for BRIEF/PRD/PLAN; `Proposed` for DESIGN) and
   hands control back to the parent. **The parent presents the chain-level prompt and triggers the Accepted
   transition on approval.**" Bindings: "all seven authoring children". The sentinel's
   `suppress_status_aware_prompt: true` means "the parent owns the prompt UX" (`:32-35`), not that the prompt
   disappears. Caveat: I could not find where `/scope`'s Phase 2 actually *presents* that unified prompt —
   `phase-2-chain-orchestration.md` documents no per-child approval prompt. That looks like an unimplemented
   half of the contract, not an intentional absence.
7. **Multi-pr PLAN `Draft -> Active`** — `skills/plan/SKILL.md:58-63`: "Only the `Draft -> Active` gate
   differs: **multi-pr requires human approval** (GitHub issues + milestone are created on the transition);
   single-pr auto-fires when /plan finishes authoring (no human gate, no GitHub side effects)." Confirmed at
   `skills/plan/references/phases/phase-7-creation.md:233-237` and `skills/plan/references/plan-format.md:235`.

**Autonomy mandate:** `/scope` does **not** have one. The only skill in the repo with an explicit autonomy
mandate is `/execute` — `skills/execute/SKILL.md:9-10` ("…and an explicit autonomy mandate"), `:212`
("consistent with the autonomy mandate that an authorized autonomous run does not stop short of completion"),
`:592-598` ("The interactive finalization pause is solicited, not an advisory stop … a mode-driven solicited
stop, not the kind of unsolicited 'advise a checkpoint' stop the mandate forbids"). Grepping `autonomy
mandate|AUTONOMY` across `skills/` and `references/` returns hits in `skills/execute/SKILL.md` only.

What `/scope` has instead is a mode flag — `skills/scope/SKILL.md:99-118`:

```
- `--auto` — non-interactive mode. Decisions follow the recommended
  default based on context; the run does not block on user input.
- `--interactive` (default) — the run blocks on user-input prompts
  at decision points.
```

plus the repo-wide standard at `AGENTS.md:87`: "Non-interactive mode (`--auto`) support at all decision
points", and `PRD-…:222-224` (R20): "Every author-facing decision point added or changed SHALL reach a
conclusion and mark one option recommended, grounded in stated findings, **with the human able to override
outside `--auto`**."

**Conclusion for the decision:** a human confirmation at the terminal fold would be entirely ordinary in
`/scope` — it already blocks in at least five places interactively, and the pattern's own R20 says every
author-facing decision point gets a recommended option the human can override. The unusual thing would be a
human gate that *survives `--auto`*: nothing in `/scope` does that today, and R20 explicitly scopes the
override to "outside `--auto`". The nearest precedent for an unconditional gate is `/prd`'s Reject branch,
which requires a **second confirmation** before a `git rm` (`skills/prd/…/phase-4-validate.md:263-267`) — i.e.
the repo already treats "delete a durable artifact" as deserving a double human confirmation, but only on a
path a human initiated.

### Q5 — Cost and reliability of a spawned reviewer

- **Nothing in the repo measures sub-agent cost.** No eval result, agent-count budget, latency target, or
  token budget for these skills exists. The only cost instrumentation is the eval harness's per-run
  `timing.json` capturing `total_tokens` and `duration_ms` (`scripts/run-evals.sh:363-368`), and its
  `workspace/` is gitignored, so no numbers are committed.
- **The only cost-vs-depth guidance in the repo** is `/review-plan`'s two execution modes:
  fast-path is "Called as a sub-operation by `/plan` Phase 6. One agent evaluates each category. Optimized for
  latency — same coverage as adversarial mode, lower depth" (`skills/review-plan/SKILL.md:37-40`), versus
  adversarial, where "adversarial mode's multi-agent bakeoff catches more findings **at the cost of
  significantly higher latency**" (`:134-136`). That is the shape of the trade-off the repo already knows how
  to state; it does not quantify it.
- **Relative cost of one more agent.** `/scope` itself is single-agent
  (`skills/scope/SKILL.md:46-51`: "runs as a single-agent skill in the v1 core layer — no team is spawned at
  the `/scope`-itself layer"), but each of its four children spawns its own fleet:
  `/brief` 2 jury; `/prd` 2-3 research (`skills/prd/references/phases/phase-2-discover.md:18,62`) + 3 jury;
  `/design` N decider agents, one per pending decision, each of which runs the whole `/decision` workflow in
  `--auto` (`skills/design/references/phases/phase-2-execution.md:23-45`) + 1 security agent
  (`phase-5-security.md:30`) + 3 review agents; `/plan` N issue-generation agents
  (`phase-4-agent-generation.md:209-215`) + `/review-plan`'s 4 category agents. A full `/scope` run is
  comfortably 20+ sub-agents, several of them recursive. **One reviewer per absorb hop is a rounding error
  against that** — which is what makes Decision 5 Option D's "per-run cost on the most common hop" the weakest
  of its three deferral reasons, and its "two documents in front of the same agent" the strongest.
- **No repo rule about agents reviewing other agents' work.** `AGENTS.md` is entirely about evals (eval
  requirement, eval structure, running evals, quality standards); it contains no reviewer-independence rule.
  Grepping `independen*` across `references/`, `skills/scope/` and `CLAUDE.md` surfaces only the jury phase
  descriptions ("independent review by two specialist agents", `skills/brief/…/phase-4-validate.md:31`).
  `skills/scope/references/` contains no reviewer guidance at all (its files are the four decision-record
  templates, the phases, and `state-schema.md`).
- **Tier rules** (`references/decision-protocol.md`): Tier 1 skips the protocol; Tier 2 is the default
  micro-protocol; escalation signals in override order are "1. **Reversibility**: is the decision practically
  irreversible? -> Tier 4"; "2. **Heuristic confidence** … No (contested, ambiguous) -> Tier 3";
  "3. **Phase primacy**: is this the primary question this phase exists to answer? Yes -> minimum Tier 3"
  (`:56-68`). Under this rule set, a fold into a soon-to-be-deleted PLAN is Tier 4 **by the reversibility
  signal alone**, and every Tier 3+ decision "should escalate to the decision skill rather than completing the
  micro-protocol" (`:36-38`). That is the closest thing the repo has to a rule that would demand a backstop —
  and note the escalation target it names is `/decision` (a heavyweight multi-agent workflow), not a reviewer.
- **Reliability counter-evidence.** The one time the carry check ran for real (#260's dogfood), it *failed* —
  i.e. the same-agent check did detect a non-carry rather than rubber-stamping. That is one data point, and it
  is a point in favour of the non-independent check, not against it.

### Q6 — The eval surface

- **Where evals live:** co-located, `skills/<name>/evals/evals.json`, per `AGENTS.md:29-47`. Runner:
  `scripts/run-evals.sh` (582 lines); CI presence check: `scripts/check-evals-exist.sh`.
- **Form:** each scenario is `{id, name, prompt, expected_output, files, expectations[]}`. The harness spawns
  a with-skill agent and a without-skill baseline agent per scenario, grades **only the with-skill run**
  against the expectations, and writes `grading.json` (`scripts/run-evals.sh:327-372`, `:423-425`).
- **Two tiers, and `/scope` is entirely tier 1.** `scripts/run-evals.sh:307-322`: tier defaults to 1
  (`ev.get("tier", 1)`), and tier 1 is `plan_only` — "Instruct agent: 'Read the skill file and describe the
  exact sequence of commands you would run. **Do NOT execute any commands.**'" Tier 2 (`execute`) sets
  `EVAL_SCENARIO` and shims `gh`/`koto` onto PATH. None of the 26 scenarios in
  `skills/scope/evals/evals.json` carries a `tier` field, so all of them are plan-only.
- **The consequence that matters here:** every expectation is phrased as *"Plan states/runs/notes X"*. E.g.
  `chain-shape-is-constant`: "Plan runs the whole chain and does not offer a shortened one"; "Plan explains
  that skipping the BRIEF here would be a judgment about an unwritten document".
  `durable-artifact-floor-is-structural`: "Plan states the durable-artifact floor follows from the chain shape
  plus the absorbability rule rather than from a guard"; "Plan does NOT add a check or warning…".
  `consolidation-absorb-brief-into-prd` (id 19): "Plan runs the consolidation judgment after the PRD lands,
  not before the BRIEF was written"; "Plan runs a per-section carry check before removing anything…".
  `consolidation-carry-check-failure-aborts-absorb` (id 21): "Plan aborts the absorb when any section of the
  carry check is not carried".
- **So: the harness can tell whether the agent follows the procedure. It cannot tell whether the agent gets
  the worth call right.** The scenario prompts *stipulate* the answer in their parenthetical setup —
  `/scope small-topic  (a feature whose framing is two uncontested paragraphs)` and
  `/scope partial-topic  (a BRIEF whose User Journeys carry detail the PRD's User Stories drop)`. There are no
  fixture documents (`"files": []` on all 26), so the agent never reads two real bodies and never actually
  makes the content judgment. Grading a fold *verdict* would need tier-2 execution against fixture BRIEF/PRD
  pairs with a known-correct verdict — the machinery for fixtures exists (`skills/brief/evals/fixtures/`,
  `skills/explore/evals/fixtures/`, `has_fixtures` handling at `scripts/run-evals.sh:358`), and
  `references/fixes/eval-fixture-frontmatter.md` exists for exactly that, so this is buildable, not
  unprecedented. It just does not exist for `/scope` today.
- The "4/4 with skill vs 1/4 baseline" numbers for `chain-shape-is-constant` and
  `durable-artifact-floor-is-structural` are not in the repo (workspace is gitignored; the #260 squash body
  quotes no eval scores). Given tier 1, those scores measure *procedural conformance*, not verdict quality —
  4/4 means the agent described the right procedure, and the baseline's 1/4 means an unaided agent invents a
  shorter chain.

---

## Assumptions made

- **Assumed:** the worktree and the shared checkout are content-identical for everything I read; I verified it
  for the DESIGN doc and for `skills/scope/` (recursive diff clean) but not for every file, since some greps
  ran against the shared checkout path. **If wrong:** line numbers for `skills/prd/`, `skills/brief/`,
  `skills/design/`, `skills/strategy/`, `references/` and `scripts/` could be off, though the worktree is only
  three explore commits ahead of the merge base and none touched those trees.
- **Assumed:** Decision 5's heading word "rejected" for Option D is a template artifact and "Deferred" in the
  body is the operative status. **If wrong:** the reviewer was rejected outright and reopening it is a
  reversal rather than a resumption — but the two Mitigations lines ("Decision 5 Option D stays available
  without rework") make this reading hard to sustain.
- **Assumed:** #260's dogfood carry-check failure on User Journeys is accurately reported by the round-1
  findings. **If wrong:** the "the absorb procedure has never executed" claim weakens, though the on-disk
  evidence (BRIEF still present, PRD's `upstream:` still pointing at it) independently shows no absorb landed
  for that topic.
- **Assumed:** the parent-delegated-approval prompt is genuinely unimplemented in `/scope` Phase 2 rather than
  documented somewhere I did not grep. **If wrong:** `/scope` blocks on a human once per child, which
  strengthens the "human confirmation is ordinary" reading considerably.
- **Assumed:** the absent `tier` field in `skills/scope/evals/evals.json` means tier 1 in every consumer, per
  `ev.get("tier", 1)` in `run-evals.sh`. **If wrong** (e.g. an interactive `/skill-creator` path defaults
  differently): some scope evals might execute, but the empty `files` arrays still mean no real document pair
  is ever judged.

---

## Critical unknowns that remain

- **Does the chain-boundary human approval prompt actually fire under `/scope`?** The dispatch contract says
  the parent owns it for all seven authoring children; `/scope`'s Phase 2 never mentions it. Whether a
  `/scope` run today stops once per artifact or only at Phase 1 changes the baseline against which "a human
  gate at the terminal fold" is measured. Settling it needs either an implementation trace or an author ruling.
- **Whether a veto-only reviewer stays veto-only in practice.** A reviewer that reads both bodies and says
  "this fold loses X" is one edit away from being asked "then what should have folded?" Nothing in the repo
  constrains a reviewer's authority; the juries' authority is bounded only by the aggregation table in each
  phase file.
- **What "independent" can mean under serial-self-jury.** If `/scope` runs its children through a dispatch
  context that cannot spawn parallel sub-agents, the reviewer degrades to the same process — reproducing
  exactly the condition Decision 5 Option D was deferred over. Whether the current dispatch context supports
  parallel spawns from a child is not stated anywhere I found.
- **Cost is entirely unmeasured.** No committed number exists for tokens or wall-clock of a `/scope` run, so
  "one more agent" and "one more agent per hop" cannot be compared to anything. The eval harness could produce
  the number (`timing.json`) but nothing retains it.
- **Whether a verdict-quality eval is worth building.** The fixture machinery exists and
  `references/fixes/eval-fixture-frontmatter.md` addresses the frontmatter-leak hazard, but no skill currently
  runs a tier-2 eval that grades a *judgment*. Building one for the fold verdict would be new ground, and it
  is the only way "trust the agent" becomes checkable rather than asserted.
- **The `consolidation_judgments:` record does not durably survive.** Phase 4 deletes the `wip/` state file
  and the PR-body record documented at `DESIGN-…:604-610` has no implementation (per the round-1 research
  captured in `wip/explore_scope-artifact-persistence_d2_context.md:115-117`). Any backstop that relies on "a
  human reviewer reads the recorded table in the PR" — which is Decision 5's stated justification for the
  chosen option — currently relies on an artifact that is not written.
