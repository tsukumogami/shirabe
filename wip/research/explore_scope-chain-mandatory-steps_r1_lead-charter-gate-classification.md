# Lead: Is `/charter`'s chain genuinely conditional, or is it the pre-#302 shape?

Sources read in full: `skills/charter/SKILL.md`, `skills/charter/references/phases/{phase-0-setup,phase-1-discovery,phase-2-chain-orchestration,phase-state-management,phase-finalization}.md`, `skills/charter/evals/evals.json`, plus the comparison surfaces `skills/scope/references/phases/phase-1-discovery.md`, `skills/scope/references/phases/phase-2-chain-orchestration.md` (Consolidation Judgment), and `references/parent-skill-pattern.md` (Gate Vocabulary).

## Findings

### Bottom line up front

Every gate in `/charter`'s chain classifies as **re-entry protection** or **content-availability**. None of them is a worth-producing judgment made before the artifact exists. `/charter` is not carrying the pre-#302 shape in its gates — the pre-#302 shape was already removed from `/charter` twice, by two dated retirements that the files still narrate (EITHER-signal retired 2026-08-08; the Building-Blocks/Coordination-Dependencies threshold on `/roadmap` retired at an unnamed earlier revision).

What `/charter` *does* lack is the other half of #302: it has **no consolidation judgment at all**. `/scope` reduces the artifact set after the fact; `/charter` never reduces it. So the inconsistency between the two chains is not "charter still gates before the fact" — it is "charter never asks the document-level question `/scope` now asks."

### Gate-by-gate classification

**1. `/vision`'s thesis-shift gate — re-entry protection, with the override strictly subordinate to it.**

`phase-2-chain-orchestration.md:26-38` states the shape outright: "The `/vision` gate is the Mandatory-with-auto-skip shape from the Gate Vocabulary ... with the thesis-shift signal as its override. The settled statuses `/charter` skips against are Accepted and Active." And: "A cold start with no supplied upstream is therefore always a `/vision` run — there is no upstream thesis to build on, **and nothing the author says about the thesis changes that**."

The thesis-shift prompt (`phase-1-discovery.md:139-204`) is asked verbatim on every run — "Is the long-term thesis shifting, or is this an operational layer below it?" — and classified into three positive-signal categories (thesis-change, new-frame, VISION-rejection) or the no-signal default. But `phase-1-discovery.md:150-155` pins its reach: "The classification decides the `/vision` invocation **only when** an Accepted or Active VISION already exists at `docs/visions/VISION-<topic>.md` — a positive signal overrides it. On a cold start `/vision` runs regardless, and the question is asked for the framing it gives the conversation."

The no-signal default (`phase-1-discovery.md:180-187`) can only *drop* `/vision` when something is already on disk or was supplied: "it drops `/vision` from the chain proposal when an Accepted or Active VISION exists at the published path or the state file carries `consumed_upstream:`, and changes nothing on a cold start with no supplied upstream."

This is exactly `/scope`'s Mandatory-with-auto-skip: the artifact state decides, the signal only reopens a gate the artifact state closed. The pattern reference says so explicitly (`references/parent-skill-pattern.md:174-179`): "An override is not a second route into the child. It can only fire in the case the auto-skip would otherwise have closed the gate ... so a cold start fires the child whatever the signal says." And the file records the retirement (`phase-2-chain-orchestration.md:66-72`): "An earlier revision of the pattern classified this gate as EITHER-signal ... They never were, and the shape was retired 2026-08-08."

The `--upstream` variant is the same category (`phase-2-chain-orchestration.md:40-56`): a supplied `consumed_upstream:` is "an upstream thesis," and the auto-skip fires against that value instead of the canonical path. The stated rationale is duplicate-avoidance, not worth: "Running `/vision` against a chain whose author just pointed at the thesis would write a second copy of it under this chain's slug."

*One wording difference worth flagging.* `/scope` records its skip with a machine-legible reason string, `settled-artifact-at-canonical-path-reentry-protection`, and its prose says outright that the skip "is NOT a judgment that the PRD would not have been worth producing" (`skills/scope/evals/evals.json:111`). `/charter`'s chain-proposal skip reason is free prose — "skip `/vision` because an Accepted VISION already exists and the thesis isn't shifting" (`phase-1-discovery.md:243-245`) — which reads, to a casual eye, like a worth judgment even though the mechanism is not one. That is a surface-wording inconsistency, not a behavioral one.

**2. `/comp`'s visibility gate — content-availability constraint.**

`phase-2-chain-orchestration.md:95-111`: `/comp` fires when (1) repository visibility is Private and (2) `skills/comp/SKILL.md` exists on disk. The stated-skip sentences (lines 118-124) name the reason: "`/comp` writes a private-only artifact and this repo is public" / "the `/comp` skill isn't installed in this workspace."

Both conditions are "the artifact cannot exist in this repo at all," not "would it have been worth writing." Line 176-182 makes the framing explicit: `/charter`'s "job is to not route someone toward a private-only artifact type in a public repo in the first place." A public-repo COMP is not a thin document; it is an impossible one.

Notable: `/comp` is the one child the state file does not record at all. `phase-2-chain-orchestration.md:131-146` — "no `chain_skipped:` entry for `comp`, and `comp` is absent from `planned_chain`. ... A child whose gate never opened was never planned, so there is nothing to record; `chain_skipped:` is for children that were planned and then dropped, like a declined `/roadmap`." The skip lands in conversation only, deliberately, so a public repo's committed surfaces never name a private-only artifact type.

**3. `/strategy`'s gate — there is none. ALWAYS.**

`phase-2-chain-orchestration.md:206-214`: "`/charter` ALWAYS invokes `/strategy`. It is the load-bearing child of the chain ... There is no condition under which `/charter` skips `/strategy`." Failure to complete routes to abandonment-forced, not to a skip. This is the `/scope` `/plan` shape: unconditional, no declination surface.

**4a. `/roadmap`'s gate — there is none. ALWAYS, with an explicit author declination.**

`phase-2-chain-orchestration.md:285-291` is emphatic that no property of the STRATEGY feeds the decision: "`/charter` does NOT count Building Blocks, does NOT test the Coordination Dependencies section for qualifying entries, and does NOT parse the document for feature-sequencing surface. The chain that produced a STRATEGY produces a ROADMAP."

Lines 486-493 record the retirement of the pre-#302-shaped gate that used to be here: "An earlier revision gated the invocation on the STRATEGY's shape — three or more Building Blocks plus a qualifying Coordination Dependencies entry. That threshold cost more than it saved." That is the same class of judgment #280 objected to, and it is already gone from `/charter`.

**4b. The roadmap confirmation prompt — an author declination against a document that exists; it drops `/roadmap` only, and the STRATEGY is untouched.**

This is the surface the lead asked to read carefully, and it is the most interesting thing in `/charter`. Mechanics (`phase-2-chain-orchestration.md:300-413`):

- *When.* "Immediately before the invocation — after `/strategy` has completed and the Draft STRATEGY is on disk — `/charter` reads that STRATEGY, says what it observed, and asks."
- *What it asks.* Explicitly **not** a size question: "The question the prompt asks is NOT 'is this strategy big enough to sequence.' Size never disqualifies a ROADMAP. The question is whether the strategy is **headed for execution at all** — a STRATEGY that records a bet nobody intends to act on is the one case that legitimately gets no ROADMAP."
- *The observation walk (O1/O2/O3).* Building Blocks as deliverables vs open questions; invalidation conditions as actionable signals vs abstract hypotheticals; an explicit deferral of the work. "Roll the three up as headed-for-execution unless O3 fires, or O1 and O2 both read not-headed-for-execution."
- *The walk cannot decide.* "The default is **Proceed** in both readings. A negative reading changes what `/charter` says, never which answer is pre-selected — the observations inform the author, they do not vote. And the observation walk is not a gate: whatever it reads, `/charter` still invokes `/roadmap` unless the author says otherwise." Under `--auto` the prompt does not fire at all and `/roadmap` always runs.

**What exactly can the author drop:** only the `/roadmap` invocation — i.e. only the ROADMAP that has not been written yet. Nothing already produced is dropped, merged, or deleted.

**What happens to the STRATEGY if they do:** nothing changes about the document. The chain still exits `full-run`; the Draft STRATEGY is the sole `exit_artifacts` entry (the AC11a shape, `phase-finalization.md:91-108`); `roadmap` stays in `planned_chain` and moves into `chain_skipped` with `reason: author declined the roadmap at the confirmation prompt`; `roadmap` is absent from `chain_ran`. `phase-finalization.md:104-108` makes the pairing a hard contract: "A one-entry `exit_artifacts` under `exit: full-run` is valid ONLY alongside the matching `chain_skipped:` declination entry. A STRATEGY-only full-run with no recorded declination means `/roadmap` was dropped without the author asking, which is a contract violation rather than a permitted shape."

The declination is described as the author "marking the STRATEGY **non-actionable**" (`phase-2-chain-orchestration.md:399-402`) — "It is not a judgment about the STRATEGY being too small or too simple to sequence." The prompt also warns of the cost: "a ROADMAP is the only bridge from a STRATEGY into the tactical chain, so skipping leaves this work with no path forward until someone runs `/roadmap` by hand."

*Where this sits relative to the three categories.* It is none of the three cleanly. It is not re-entry protection (nothing is on disk to protect), not content-availability (a ROADMAP is perfectly producible), and not a parent-computed worth judgment (the parent computes nothing that can change the outcome). It is a fourth thing the pattern reference already names: an **author declination on an ALWAYS gate** (`references/parent-skill-pattern.md:126-137`) — "that is author-supplied input, not a predicate the parent computes ... A parent MAY read the upstream artifact to inform what it tells the author at that declination prompt — reading for the prompt is not reading for the gate, and the gate stays ALWAYS as long as no reading can change the pre-selected answer or skip the child on its own."

Note what this prompt got right that a pre-artifact gate cannot: the judgment is formed **against a Draft STRATEGY that exists on disk**. It is the closest `/charter` comes to #302's "judge documents, not types" discipline — applied to the decision to produce a downstream, rather than to the decision to retain an upstream.

**5. The Stated-Skip Rule — a disclosure rule, not a gate.**

`phase-2-chain-orchestration.md:113-192`. It governs what `/charter` *says* when a gate did not open, not whether it opens: "When either gate condition fails, `/charter` SHALL state the skip in its conversational output and continue the chain. The statement names the child and the reason. ... The reason is stated, not implied. An author who expected a competitive step and gets none deserves to know a rule dropped it rather than being left to wonder whether `/charter` considered the question at all."

Its second half is a visibility discipline: the sentence lives in conversation and never in a committed file, so "neither the sentence `\"skipping competitive analysis\"` nor the word `/comp` reaches a committed file." It replaced an earlier "degenerate-silence rule" whose cost was that "the same silence covered two unrelated conditions (a public repo and a missing skill) that call for different responses."

`phase-1-discovery.md:293-302` extends the same discipline to the chain proposal: "The skip entries state the reason rather than omitting the child. ... The reason lands in the conversation only; the chain's committed output ... carries no trace of the skipped child."

Classification: neither of the three categories — it is orthogonal to gate shape entirely. It is a good rule and is not in scope for #302-style repair.

### Does `/charter` have a consolidation judgment?

**No. Plainly, no.**

`grep -rn "consolidat" skills/charter/` returns nothing. `grep -rn "absorb" skills/charter/` returns nine hits and every one is the unrelated sense of *absorbing an error* — "silently absorb input the author did not intend" (`phase-0-setup.md:165`), "silently absorbing the violation" (`SKILL.md:116`), "silently absorbs chain abandonments into Decision Records" (`phase-finalization.md:558`, `:724`), "does not absorb or paraphrase the malformation" (`evals.json:31`). There is no artifact-merging mechanism, no `absorbed:` frontmatter, no `consolidation_judgments:` state field, no keep/absorb/defer verdict, and no post-hop step of any kind.

Consequence: **#302 reached only the tactical chain.** `/scope` gained the document-level test (`skills/scope/references/phases/phase-2-chain-orchestration.md:470-528` — "It is only honest to do it *here* — against two bodies that exist, where the question 'does the upstream do work the downstream does not?' has an answer. The same question asked at Phase 1, before either document is written, has no answer, and answering it anyway is how content gets lost"). `/charter` gained nothing corresponding, because it had nothing to convert: it had already retired both of its pre-artifact worth gates on its own timeline, and it never had a post-artifact reduction step to replace them with.

So the strategic chain today: every artifact it produces, it keeps. VISION, STRATEGY, ROADMAP all survive to `exit_artifacts` / `child_snapshots` with no merge question ever asked. Whether that is a gap or a deliberate difference is the live question — see Open Questions.

### Does Phase 1 have the equivalent of `/scope`'s "What Phase 1 Decides, and What It Does Not"?

**No.** There is no such section, and no equivalent statement anywhere in `/charter`.

`/scope`'s version (`skills/scope/references/phases/phase-1-discovery.md:11-43`) states four things: `planned_chain:` is `[brief, prd, design, plan]` on every run; "There is no starting altitude to choose and no child that Phase 1 can decide is not worth invoking"; the only thing that stops a child is re-entry protection, "not a verdict on the artifact's worth"; and "An author who wants a shorter chain reaches for a child skill directly."

What `/charter` has instead is Phase 1's Goal section (`phase-1-discovery.md:13-27`), which is a list of what the prelude establishes, plus a forward pointer:

> "Phase 1's chain-shape decisions, child-invocation gates, and the chain-proposal confirmation prompt are NOT in this prelude — they extend this file below and consume the three behaviors documented here."

And the closest thing to a scope-boundary statement, in the chain-proposal section (`phase-1-discovery.md:250-256`):

> "`/strategy` and `/roadmap` always appear as \"run\" — both gates are unconditional. The author's opportunity to drop `/roadmap` comes later, at the roadmap confirmation prompt documented in `skills/charter/references/phases/phase-2-chain-orchestration.md`, not here."

Plus the corresponding restatement at the Phase 2 end (`phase-2-chain-orchestration.md:404-413`):

> "The confirmation prompt is the ONLY path that skips `/roadmap`. Phase 1's \"Adjust\" option re-shapes the chain before any child fires, but it cannot drop `/roadmap`: `/roadmap` has no Phase 1 gate to adjust, and a chain that reached full-run without a recorded declination would land a one-entry `exit_artifacts` with no matching `chain_skipped:` entry — the contract violation ... An author who already knows at discovery time that no roadmap is wanted still declines at the confirmation prompt; that is what records the decision."

Those two passages *do* the job for `/roadmap` specifically — they say Phase 1 cannot drop it and where the decision actually lives. What is missing is the general statement about the chain as a whole and the explicit "this is not a worth judgment" framing that `/scope` puts in the reader's hands. A reader coming to `/charter` from `/scope` has to reconstruct the model from four scattered passages.

Also missing: `/charter`'s Phase 1 documents an **Adjust** option that can force a previously-skipped child on OR "opt out of a child that would otherwise fire" (`phase-1-discovery.md:385-388`). Read literally that is an author-side, pre-artifact worth judgment surface with no corresponding record in `chain_skipped:` and no documented interaction with the AC11a contract — but it is bounded, since `/strategy` and `/roadmap` have no Phase 1 gate to adjust and `/comp`'s gate is content-availability, leaving `/vision` as the only child Adjust can actually turn off. See Open Questions.

### Is `planned_chain:` a constant in `/charter`?

**No.** It is variable, by explicit schema definition. `phase-state-management.md:132-138`:

> "**`planned_chain`** — ordered list of child-name strings naming which children are in scope for this run. Values are drawn from `{vision?, comp?, strategy, roadmap}` (children with `?` are conditional on their Phase 1 gates; `strategy` and `roadmap` are unconditional). Set at Phase 1 chain-proposal acceptance; **modified only if the author re-proposes the chain.** `roadmap` is planned on every chain even though the author may later decline it at the Phase 2 roadmap confirmation prompt — a declination moves `roadmap` into `chain_skipped`, it does not retract the plan."

Contrast `/scope` (`skills/scope/references/phases/phase-1-discovery.md:14` and `:399-404`): "`planned_chain:` is `[brief, prd, design, plan]` on every run", and `skills/scope/references/phases/phase-2-chain-orchestration.md:814`: "`planned_chain:` is a constant."

Two structural differences follow, and the second is the sharper one:

- `/scope`'s constant-with-carve-out shape is muddied by its own eval text: `skills/scope/evals/evals.json:111` says a re-entry-protected `/prd` is recorded in `chain_skipped` and that "planned_chain contains the children that run (not /prd)", which contradicts the "constant on every run" claim in its own phase file. Worth a separate look; not this lead's scope.
- `/charter` deliberately *excludes* `/comp` from `planned_chain` entirely when its gate never opens (`phase-2-chain-orchestration.md:136-146`), while `/roadmap` stays in `planned_chain` even when declined. The asymmetry is principled and stated: "A child whose gate never opened was never planned ... `chain_skipped:` is for children that were planned and then dropped." A move toward a `/scope`-style constant would have to preserve the `/comp` visibility property, since recording `comp` anywhere in a public repo's committed state file is exactly what the visibility rule forbids.

### Which charter behaviors are graded, and the pinned literals

21 scenarios in `skills/charter/evals/evals.json`: six shared-baseline (`baseline-*`, ids 1-6), five user-story (`us-*`, ids 7-11), four `/roadmap` gate scenarios (ids 12-15), one chain-proposal triad (16), three `--upstream` flag scenarios (17-19), two pre-authoring-notice scenarios (20-21).

**Chain-proposal literals (id 16, `ac10d-chain-proposal-triad`):**

- "Plan's prompt contains the literal substrings \"Proceed\", \"Adjust\", and \"Bail\" (case-insensitive), asserted individually rather than as one contiguous slash-joined string"
- "Plan does NOT require a contiguous \"Proceed / Adjust / Bail\" string, and tolerates the canonical rendering \"Proceed / Adjust chain / Bail?\" whose Adjust label carries an interstitial word"
- "Plan lists the children in chain order, with /strategy and /roadmap both shown as running because their gates are unconditional"

The expected_output adds the reason the triad is asserted per-token: "the chain proposal is not a co-equal menu (Proceed is the expected path)."

**Option-line literals pinned byte-for-byte (ids 20, 21):**

- "Plan leaves the option line \"Proceed / Adjust chain / Bail?\" unchanged and adds no new option or decision point"
- id 21 expected_output: "the option line stays \"Proceed / Adjust chain / Bail?\"" in both notice-suppression cases

**Resume-entry literals (ids 6, 8):**

- "Plan ensures the entry-router prompt against an existing Accepted/Active STRATEGY contains the literal substring \"Re-evaluate / Revise / Bail\" (case-insensitive components allowed)"
- "Plan ensures the entry-router prompt MUST NOT contain the literal substring \"Continue / Start fresh\" — that vocabulary belongs to /strategy and would hijack /charter's flow"
- id 8: option line is "the contiguous literal \"Re-evaluate / Revise / Bail\" (case-insensitive, separator \" / \" exactly)"

**Skip reasons that are graded:**

- `/comp`, id 7: "Plan does not invoke the gated feeder /comp under public-repo visibility, and states the skip in the chain-proposal output with **public visibility named as the reason** (stated-skip rule)"; and the committed-surface half: "Plan keeps the skip statement out of every committed surface: no chain_skipped entry for comp, no comp in planned_chain, and no mention of /comp or competitive analysis in any artifact written under docs/"
- `/vision` under `--upstream`, id 17: "Plan skips /vision and records the skip with **a reason naming the supplied upstream**"
- `/roadmap` declination, id 12: "Plan records the declination in chain_skipped as a { child: roadmap, reason: ... } entry, and omits /roadmap from chain_ran" — the reason string itself is free text and is NOT pinned to a literal
- `/vision` cold start, id 7: pins the verbatim thesis-shift question — "surfaces the literal question \"Is the long-term thesis shifting, or is this an operational layer below it?\", and invokes /vision because R4 runs /vision unless an Accepted or Active VISION already exists at the published path — on a cold start none does, so /vision runs regardless of the thesis-shift answer"

**Negative assertions that pin the no-pre-artifact-worth-judgment property (ids 12, 14):**

- id 12: "Plan skips /roadmap because the author declined, and **attributes the skip to the author's answer rather than to its own reading of the STRATEGY**"
- id 12: "Plan treats the STRATEGY-only full-run as the exception path rather than the default, and **does not describe any threshold on Building Blocks, Coordination Dependencies, or feature count as the reason /roadmap was skipped**"
- id 14: "Transcript keeps the default at Proceed despite the negative reading; it does NOT flip the default to skip and does NOT pre-select the skip answer"
- id 14: "Transcript does NOT treat the single Building Block or a single candidate feature as a reason to skip, and states no minimum feature count for a roadmap"

**Pre-authoring notice, pinned verbatim (id 20)** — the full paragraph "A new VISION will be written for this topic. If one already exists that this chain should build on, re-invoke as /charter payment-retries --upstream <path-to-the-VISION> and this chain will consume it instead of authoring another. No candidate has been looked for; this is a notice, not a question, and the chain proceeds as proposed."

**Not graded anywhere:** no scenario exercises a consolidation or artifact-reduction behavior (there is none to exercise); no scenario asserts the `/comp` "feeder skill not on disk" skip sentence; no scenario exercises the Phase 1 Adjust option.

## Implications

1. **The exploration's framing needs adjusting for `/charter`.** The core question asks which surfaces "still behave as though chain steps are optional and choosable before the fact." `/charter`'s gates do not — they are re-entry protection plus one content-availability constraint plus two ALWAYS gates. Whatever the corpus-wide fix is, it should not be written as "port #302's gate removal to `/charter`," because there is nothing left there to remove.

2. **The real strategic-chain gap is the missing consolidation judgment.** If the corpus is to state one model, that model has two halves — run the chain, then reduce the set — and `/charter` implements only the first. A recommendation to add one has to answer whether VISION→STRATEGY→ROADMAP is even an absorbable set: `/charter` currently treats STRATEGY as the durable audit-trail artifact and ROADMAP as a working artifact with its own lifecycle-owned completion condition (`SKILL.md:26-38`), which is a different disposal model from `/scope`'s absorb-into-survivor.

3. **The cheapest and highest-value fix is documentation, not mechanism.** `/charter` Phase 1 should carry the equivalent of `/scope`'s "What Phase 1 Decides, and What It Does Not," stating that the skips it can produce are re-entry protection and content availability, that neither is a worth judgment, and that the only pre-artifact drop an author can make is the `/roadmap` declination — which happens in Phase 2, against a document that exists. Four passages currently carry fragments of this; one section would carry it whole.

4. **Skip-reason vocabulary is worth unifying.** `/scope` uses a machine-legible `settled-artifact-at-canonical-path-reentry-protection`; `/charter` uses free prose that reads like a worth verdict. Making `/charter`'s reason strings name the mechanism would make the shared model visible at the state-file level rather than only in prose.

5. **The roadmap confirmation prompt is a model to point at, not a problem to fix.** It already does what #280 asked: form the judgment against a document that exists, tell the author what you read, and let the author decide. If the corpus wants a house shape for "author may decline a downstream," this is it — and the pattern reference's ALWAYS-with-declination clause already names it.

6. **`planned_chain:` divergence should be resolved deliberately, not by mechanical alignment.** Making `/charter`'s a constant would require recording `comp` in a public repo's committed state file, which the visibility rule forbids. Either the constant carries a documented content-availability carve-out, or `/charter` keeps a variable list and the difference gets stated as intentional.

## Surprises

- **`/charter` retired its own pre-artifact worth gate before #302 existed, and narrates the retirement in the same terms #280 used.** `phase-2-chain-orchestration.md:486-493` describes the old three-Building-Blocks + Coordination-Dependencies threshold and rejects it on the same grounds: authors and agents had to "hold two counting rules in their head to predict what `/charter` would do, and the payoff was skipping a small, disposable document." The strategic chain arrived at #302's conclusion independently for `/roadmap`.
- **The `/roadmap` prompt cites `/scope`'s R6 predicate walk as its shape template** (`phase-2-chain-orchestration.md:319-321`) — cross-pollination already runs in this direction, which makes the absence of a consolidation judgment on the strategic side look more like an oversight than a decision.
- **The scope assumption that `/vision` and `/comp` "can read skip" is true but under-describes both.** `/vision`'s skip is re-entry protection and never fires on a cold start; `/comp`'s skip is content availability and is deliberately erased from every committed surface. Calling both "conditional" flattens two different mechanisms into one word.
- **`/scope`'s own `planned_chain:` documentation contradicts itself.** The phase file says the list is `[brief, prd, design, plan]` on every run; `skills/scope/evals/evals.json:111` says a re-entry-protected `/prd` is kept out of `planned_chain`. If `/charter` is asked to match `/scope`, it is worth knowing which `/scope` it should match.
- **`/charter` Phase 1's Adjust option lets the author "opt out of a child that would otherwise fire"** (`phase-1-discovery.md:385-388`) — a pre-artifact drop with no `chain_skipped:` record described for it, and no eval covering it. `/roadmap` and `/strategy` are protected from it by having no Phase 1 gate, so `/vision` is the only child it can reach, but the prose is broader than the mechanism.

## Open Questions

1. **Should the strategic chain have a consolidation judgment at all?** VISION and STRATEGY have different audiences and lifecycles, and ROADMAP is a working artifact retired by the downstream PLAN cascade rather than by a merge. If the answer is no, the corpus should say so explicitly — the asymmetry then becomes a stated difference rather than a silent one. Needs a human call.
2. **If yes, which hops?** `vision→strategy` is the only adjacent pair where both endpoints can be produced by one run and both are durable. `strategy→roadmap` crosses the durable/working boundary that `SKILL.md:26-38` treats as load-bearing. This looks like a one-hop judgment at most.
3. **Does the Phase 1 Adjust option need bounding?** Its "opt out of a child that would otherwise fire" clause is the one place in `/charter` where an author makes a pre-artifact drop with no recorded reason. Should an Adjust-driven `/vision` opt-out write a `chain_skipped:` entry, the way the `/roadmap` declination must?
4. **Which `/scope` is canonical on `planned_chain:`** — the phase file's constant or the eval's variable list? Resolving this is a prerequisite for any "state one model" recommendation.
5. **Should `/charter` adopt machine-legible skip reasons?** Low cost, but it touches three graded eval scenarios (7, 12, 17), so it needs to be a deliberate change rather than a drive-by.

## Summary

Every gate in `/charter`'s strategic chain classifies as re-entry protection (`/vision`'s Mandatory-with-auto-skip, whose thesis-shift override cannot fire on a cold start) or content availability (`/comp`'s private-only visibility gate); `/strategy` and `/roadmap` are ALWAYS with no computed gate, and `/roadmap`'s escape hatch is an author declination formed against a Draft STRATEGY that already exists on disk, which drops only the unwritten ROADMAP and leaves the STRATEGY as the sole `exit_artifacts` entry under a still-`full-run` exit. The main implication is that #302 reached only the tactical chain in the half that matters: `/charter` has no consolidation judgment of any kind — `grep -rn "consolidat" skills/charter/` returns nothing — so the strategic chain runs unconditionally and then keeps everything it produced, and it also lacks `/scope`'s explicit "Phase 1 decides nothing about the size of the artifact set" statement and treats `planned_chain:` as variable rather than constant. The biggest open question is whether the strategic chain should gain a document-level consolidation judgment at all, given that STRATEGY is the durable audit trail and ROADMAP is a working artifact retired by the downstream PLAN cascade — a different disposal model from `/scope`'s absorb-into-survivor.
