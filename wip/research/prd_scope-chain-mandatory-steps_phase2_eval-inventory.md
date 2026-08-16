# Eval assertion inventory — scope-chain-mandatory-steps

Taken against the current worktree tree (post-#292). All counts and quotes
read from the files, not from prior notes.

## Suite sizes right now

The top-level key is `evals`, not `scenarios`.

| Suite | File | Scenario count |
|---|---|---|
| scope | `skills/scope/evals/evals.json` | 28 |
| explore | `skills/explore/evals/evals.json` | 16 |
| charter | `skills/charter/evals/evals.json` | 22 |
| roadmap | `skills/roadmap/evals/evals.json` | 15 |
| vision | `skills/vision/evals/evals.json` | 10 |
| decision | `skills/decision/evals/evals.json` | 12 |

Total across the six: 103.

Field-shape note that matters for anyone proposing replacement assertions:
**explore scenarios 1–8 carry no `expectations` and no `assertions` array at
all** — only `prompt`, `expected_output`, `files`. Explore 9–11 use
`assertions`; 12–16 use `expectations`. Decision uses `assertions`
throughout. Scope, charter, roadmap and vision use `expectations`. A
replacement assertion for explore 3/4/5/8 therefore has to either edit
`expected_output` prose or introduce the array that scenario has never had.

## CI

`.github/workflows/run-evals.yml` does **not** run on pull requests. Its
trigger block is:

```yaml
on:
  schedule:
    - cron: '0 4 * * 1'  # Mondays at 04:00 UTC
  workflow_dispatch:
    inputs:
      skill: ...
      ref: ...
```

So: weekly Monday cron plus manual dispatch. The only eval-related workflow
that fires on PRs is `.github/workflows/check-evals.yml`, which runs on
`pull_request` with `paths: ['skills/**']` and executes
`scripts/check-evals-exist.sh` — an existence check, not a run of the
scenarios. Practical consequence: a stale assertion can sit on main for up
to a week before anything notices, and a PR that breaks one gets no signal.
Bucket A below is evidence this already happened.

---

## Bucket A — grades the retired absorbability model

These are broken **today**, on main, independent of the mandatory-steps
work. The skill moved to a two-clause judgment whose Stage 1 is a citation
preflight and whose Stage 2 reads the two bodies; the required-section
mapping question was retired along with the `absorbable:` boolean. Three
scope scenarios still grade the retired model.

The governing skill text, quoted so the contradiction is checkable in both
directions:

`skills/scope/references/phases/phase-2-chain-orchestration.md:538-541` —

> **The input restriction.** *No check in this judgment may read
> either type's required-section list, or compare the two types'
> section sets.* Chain position and provenance are admissible inputs;
> a type's content contract is not.

`phase-2-chain-orchestration.md:723-726` —

> `stage:` names where the verdict settled — `preflight`, `judgment`
> or `carry`. It replaces the retired `absorbable:` boolean, which
> asked whether the required-section mapping was total: the question
> this judgment no longer asks.

`phase-2-chain-orchestration.md:728-748`, section heading **"There is no
durable-artifact floor"** —

> A run can absorb its way down to a single surviving artifact, or to
> none once the PLAN is implemented, and that is a reachable outcome
> rather than a defect.
>
> **Do not add a guard that forces `keep` on the ground that the
> survivor would be the last artifact.** [...] it would
> fire at exactly the DESIGN-to-PLAN hop that must be absorbable,
> closing by a second route the floor this work opened.

`skills/scope/SKILL.md:497-503` —

> Every hop is decidable, so a run ends with all four artifacts, or some, or —
> once the PLAN is implemented and deleted — none. [...]
> There is no durable-artifact floor; the prohibition on
> reintroducing one lives beside the judgment in Phase 2.

`skills/scope/SKILL.md:528-534` —

> Absorbability is decided against the two documents, never against
> their types. [...] So there is no hop the types make
> impossible: the question is only ever whether this upstream holds
> something beyond its contribution that folding would lose.

### A1. scope / id 18 / `durable-artifact-floor-is-structural`

**Why it must change:** the scenario's entire premise — that a floor exists
and is structural — is the exact claim the skill now names as retired and
prohibits reintroducing.

Affected `expected_output` (verbatim, the stale clauses):

> "A /scope run always leaves at least one durable artifact, and nothing
> implements a guard for it. The chain always writes BRIEF, PRD, DESIGN and
> PLAN, and no hop above BRIEF-to-PRD is absorbable, so the smallest set a
> run can end with is a PRD, a DESIGN and a PLAN. A PLAN-alone run — which
> would leave nothing behind, since the PLAN is deleted once its work is
> implemented — is not reachable through /scope at all"

Three separate contradictions in that passage:

1. "always leaves at least one durable artifact" vs. SKILL.md "or —
   once the PLAN is implemented and deleted — none."
2. "no hop above BRIEF-to-PRD is absorbable" vs. "there is no hop the
   types make impossible" and the Phase 2 line naming "the DESIGN-to-PLAN
   hop that must be absorbable."
3. "A PLAN-alone run [...] is not reachable through /scope at all" vs.
   "A run can absorb its way down to a single surviving artifact."

Affected `expectations` (all four; 1 and 3 are outright false, 2 and 4 are
accidentally still true but for the opposite reason):

> 1. "Plan states the durable-artifact floor follows from the chain shape plus the absorbability rule rather than from a guard"
> 2. "Plan does NOT add a check or warning for a run that leaves no durable artifact"
> 3. "Plan notes that a PLAN-alone outcome is unreachable through /scope and requires invoking /plan directly"
> 4. "Plan gives the reason for not adding a guard: the condition cannot hold, and dead checks mislead"

Expectation 1 asserts a floor exists. Expectation 3 asserts PLAN-alone is
unreachable. Both are now false. Expectation 4's stated reason ("the
condition cannot hold") is now the wrong reason — the condition *can*
hold; the guard is prohibited because it would decide from the artifact set
rather than from the two documents, and because it would close the
DESIGN-to-PLAN hop.

**Proposed replacement** (rename the scenario to
`no-durable-artifact-floor` and rewrite all four):

- "Plan states there is no durable-artifact floor: a run may absorb down to a single surviving artifact, or to none once the PLAN is implemented and deleted"
- "Plan does NOT add a check, warning, or guard that forces `keep` on the ground that the survivor would be the last artifact"
- "Plan gives the prohibition's two stated reasons: such a guard would decide a fold from the artifact set rather than from the two documents at the hop, and it would fire at exactly the DESIGN-to-PLAN hop that must be absorbable"
- "Plan states that a chain which folds everything away is handled downstream by /execute's finalization guard, not prevented in /scope"

### A2. scope / id 19 / `consolidation-absorb-brief-into-prd`

**Why it must change:** its Stage 1 and Stage 2 are the retired
mapping-totality stages, not the shipped citation preflight and body
judgment, and its Stage 3 omits every durable side effect the current
nine-step procedure requires.

Affected `expected_output` (verbatim, the stale clauses):

> "Stage 1 finds the mapping total (Problem Statement to Problem Statement,
> User Outcome to Goals, User Journeys to User Stories, Scope Boundary to
> Requirements and Out of Scope), so absorb is available."

Stage 1 is now `skills/scope/scripts/check-citations.sh --target <deleted>
--survivor <survivor>` with deny-by-default routing on exit status. The
quoted sentence is a section-set comparison, which the input restriction
forbids anywhere in the judgment.

> "Stage 3 runs the per-section carry check, records where each of the four
> concerns landed, then sets the PRD's upstream to the BRIEF's own upstream
> (or removes the field), removes the BRIEF from the repository, and
> re-runs shirabe validate on the PRD."

Current Stage 3 is nine steps: compose the contribution from the
**survivor's** body, carry check, snapshot-then-write (splice `upstream:`
**preserving sibling and cross-repo parents**, write the `absorbed:`
declaration, write the `## Status` absorption line in the pinned shape
`Absorbed [<name>](<path>); carried in <Heading>.`, write the contribution
section, rewrite the survivor's own prose citations), append a row to
`docs/folds.md` and `git add` it, `git rm` the absorbed artifact, re-validate,
commit. "sets the PRD's upstream to the BRIEF's own upstream (or removes the
field)" is a *replacement* semantics the skill now explicitly rejects.

Affected `expectations`:

> - "Plan finds the brief->prd mapping total and treats absorb as available at that hop"  — **retired model, must go**
> - "Plan re-points the PRD's upstream to the BRIEF's own upstream, or removes the field when the BRIEF had none"  — **wrong splice semantics**
> - "Plan runs the consolidation judgment after the PRD lands, not before the BRIEF was written"  — still correct, keep
> - "Plan runs a per-section carry check before removing anything and records where each of the BRIEF's four concerns landed in the PRD"  — correct but under-specified; carry check must also cover inherited contributions
> - "Plan re-runs shirabe validate on the surviving PRD after the absorb"  — still correct, keep
> - "Plan records the verdict and the carry check in consolidation_judgments:"  — still correct, but must also require `stage:`

**Proposed replacements** (replace the first two, tighten the last three):

- "Plan runs the citation preflight `skills/scope/scripts/check-citations.sh --target <deleted> --survivor <survivor>` before anything is composed, written or deleted, and routes any status other than 0 or 2 to verdict `keep`"
- "Plan reaches `absorb` by reading both bodies and asking whether the BRIEF holds work beyond its contribution, and does NOT compare the two types' required-section lists at any stage"
- "Plan composes the BRIEF's contribution section from the surviving PRD's own body, not from the BRIEF about to be deleted"
- "Plan splices `upstream:` preserving sibling and cross-repo parents rather than replacing the list, and drops a spliced parent that resolves to a private artifact when the repo is Public"
- "Plan writes the `absorbed:` declaration and a `## Status` absorption line in the pinned shape `Absorbed [<name>](<path>); carried in <Heading>.`"
- "Plan appends the row to `docs/folds.md` and `git add`s it before any deletion, then deletes with `git rm`, re-validates the survivor, and commits all of it together"
- "Plan records the entry with `stage:` set to `preflight`, `judgment` or `carry`, and does NOT emit an `absorbable:` boolean"

### A3. scope / id 20 / `consolidation-keep-at-unmapped-hop`

**Why it must change:** the scenario grades exactly the type-rule the input
restriction forbids, records the retired `absorbable:` boolean, and asserts
the DESIGN-to-PLAN hop is unabsorbable — the one hop the skill says "must be
absorbable."

Affected `expected_output` (verbatim, the whole reasoning is stale):

> "Stage 1 finds the mapping is not total: a DESIGN has a home for the PRD's
> Problem Statement in Context and Problem Statement, but none for Goals,
> User Stories, Requirements, Acceptance Criteria or Out of Scope. Absorb is
> unavailable, the only verdict is keep, and the finding names the unmapped
> sections. The same holds at the design->plan hop."

Affected `expectations` (all four are broken):

> 1. "Plan finds the prd->design mapping is not total and records absorbable: false"
> 2. "Plan reaches verdict keep and names the unmapped sections in the finding"
> 3. "Plan applies the same rule at the design->plan hop"
> 4. "Plan derives absorbability from the per-type required-section contracts rather than a hard-coded list of hops"

Contradiction in both directions:

- Expectation 4 says derive absorbability from required-section contracts.
  Phase 2 line 538 says *no check may read either type's required-section
  list*. These cannot both hold.
- Expectation 1 records `absorbable: false`. Phase 2 line 724 calls
  `absorbable:` "retired".
- Expectation 3 makes `design->plan` a permanent `keep`. Phase 2 line 744
  calls DESIGN-to-PLAN "the hop that must be absorbable."
- The scenario is also the textbook violation of the skill's own detector:
  "a condition that refuses one pair while permitting its structural twin
  under identical repository state is a type rule."

**Proposed replacement** — the scenario cannot be repaired in place; the
situation it grades no longer exists. Replace it with a `keep`-reaching
scenario grounded in the surviving mechanisms. Suggested name
`consolidation-keep-on-body-judgment`:

- "Plan reaches verdict `keep` because the upstream holds work the downstream does not, and the finding names what the upstream holds that the survivor does not"
- "Plan does NOT justify `keep` by comparing the two types' required-section lists or by naming unmapped sections"
- "Plan records no `absorbable:` field; the entry carries `stage: judgment`"
- "Plan states that no hop is unabsorbable because of the types involved, including prd->design and design->plan"

Optionally add a second replacement for the preflight-`keep` path:
- "Plan routes to `keep` with `stage: preflight` when check-citations.sh exits with any status other than 0 or 2, including statuses the script does not define"

### A-adjacent, but NOT broken: scope / id 21 / `consolidation-carry-check-failure-aborts-absorb`

The lead flagged this one for checking. **It survives.** Its expected_output
("reaches absorb at stage 2, then the per-section carry check finds the
PRD's User Stories do not carry the BRIEF's User Journeys. The absorb
ABORTS") matches Stage 3 step 4 verbatim in behaviour:

> Any `carried: false` **aborts the absorb**: the verdict is
> downgraded to `keep`, the finding names what did not arrive, and
> both artifacts stay on disk.

All four of its expectations still grade shipped behaviour. Two coverage
gaps worth folding in while the file is open, neither of which is a
contradiction:

- the current carry check must itemize "every contribution the ancestor
  itself carries — its own and any it inherited, read from the ancestor's
  `absorbed:` list"; the eval only covers the ancestor's own four sections.
- the recorded entry now takes `stage: carry`; the eval says only that the
  failed carry check is recorded.

Suggested additive expectation, not a rewrite:
- "Plan's carry check itemizes the ancestor's required sections plus every contribution the ancestor itself carries, and records the settling stage as `stage: carry`"

**Bucket A count: 3 broken (18, 19, 20), with 21 verified intact.**

---

## Bucket B — pins the `/scope` chain-proposal prompt

Three scope scenarios pin the chain proposal's options block. The pinning
strength differs between them, which matters: a per-token pin survives a
re-worded label, a byte-for-byte pin does not.

The current canonical rendering,
`skills/scope/references/phases/phase-1-discovery.md:317`:

> `> Proceed / Adjust / Bail?`

and the contract statement at `phase-1-discovery.md:296-297`:

> The output's options block
> contains the literal substrings `Proceed`, `Adjust`, and `Bail`
> (case-sensitive, exact spelling per AC9).

### B1. scope / id 7 / `us-1-cold-standalone-full-run` — **per-token**

`expected_output`: "The chain-proposal output names those four children with
their re-entry verdicts and contains the literal Proceed / Adjust / Bail
substrings."

Expectation (index 4), verbatim:

> "Plan emits a chain-proposal output containing the literal substrings Proceed, Adjust and Bail"

Per-token. Survives a re-labelled option (e.g. `Adjust scope`) but not the
removal of any of the three words. If mandatory-steps removes `Adjust` as an
option, or converts the proposal from a prompt into an announcement, this
breaks.

**Proposed replacement**, if the proposal becomes a confirm-only
announcement:
- "Plan emits a chain-proposal output naming the four children in chain order, and its options block offers no option that shortens or re-shapes the chain"

If `Adjust` survives with narrowed meaning, the safer form is:
- "Plan emits a chain-proposal output containing the literal substrings Proceed and Bail, asserted individually; where an Adjust option is offered, it adjusts the topic and framing only and never the list of children"

That second form is already what `skills/scope/SKILL.md:441-442` says:
"Adjust refines the topic and the framing, not the list of children."

### B2. scope / id 25 / `pre-authoring-notice-cold-start` — **byte-for-byte**

`expected_output`, verbatim:

> "The notice sits in the entry list above the options block, which still
> reads \"Proceed / Adjust / Bail?\" byte-for-byte."

Expectation (index 2), verbatim:

> "Plan leaves the options block \"Proceed / Adjust / Bail?\" unchanged and adds no new option or decision point"

This is the strictest pin in the six suites — it fixes the slash spacing and
the trailing question mark. Any re-wording of the options line, however
small, fails it.

**Proposed replacement** — the load-bearing claim here is that the *notice*
changes nothing about the options block, not that the block has a
particular spelling. Decouple the two:
- "Plan leaves the chain proposal's options block exactly as the skill defines it and adds no new option, no new default, and no new decision point on account of the notice"

### B3. scope / id 26 / `pre-authoring-notice-suppressed` — **per-token, indirect**

`expected_output`: "In both cases the rest of the chain-proposal output and
its options block are unchanged."

Expectation (index 2), verbatim:

> "Plan does not otherwise alter the chain-proposal output or its options block in either case"

No literal string is pinned, so this one only breaks if the options block
stops existing. Lowest-risk of the three; likely survives untouched.
Re-read it once the new block wording is settled.

### Do not confuse these with the other Proceed/Adjust/Bail hits in the scope suite

Six further scope scenarios contain one of those tokens but pin a
**different prompt**. None belongs in Bucket B, and touching them would be a
regression:

- id 6 `baseline-default-option-wording` and id 9 `us-3a-…`, id 10
  `us-3b-…` pin `"Re-evaluate / Revise / Bail"` — the resume-ladder entry
  router at rows 5.4/5.6, not the chain proposal.
- id 8 `us-2-prd-auto-skip` asserts the negative: "Plan ensures neither
  PLAN-Active nor PLAN-Done rows contain the 'Re-evaluate / Revise / Bail'
  triad".
- id 13 `us-6-manual-fallback-reviewer-redirect` pins the staleness prompt
  "Re-run (re-invoke the affected child), Accept (…), and Proceed-without
  (…)".
- id 24 `upstream-flag-stale-on-resume` pins "Re-supply, Continue without,
  and Bail, with Re-supply as the interactive default".

**Bucket B count: 3 (ids 7, 25, 26).**

---

## Bucket C — pins `/explore` routing to a chain-internal child

Current explore routing surface, for reference.
`skills/explore/references/phases/phase-5-produce.md:40-47`:

| PRD | `phase-5-produce-prd.md` | Auto-continues into /prd |
| Design Doc | `phase-5-produce-design.md` | Auto-continues into /design |
| VISION | `phase-5-produce-vision.md` | Auto-continues into /vision |
| Plan | `phase-5-produce-plan.md` | Stops — user runs /plan |
| Roadmap | `phase-5-produce-roadmap.md` | Auto-continues into /roadmap |

and `skills/explore/SKILL.md:36-45`, the Artifact Type Routing Guide, which
routes directly to `/design <topic>`, `/brief <topic>`, `/prd <topic>`,
`/plan <design-doc-path>` and `/work-on <issue>`.

### explore suite

| id | name | field | verbatim string that pins the child |
|---|---|---|---|
| 3 | `routing-advisor-prd-vs-design` | `expected_output` only | "Asks clarifying questions to determine whether the core question is 'what should we build' (PRD) vs 'how should we build it' (Design Doc)." The whole scenario is a two-way choice between two chain-internal children. |
| 4 | `crystallize-to-design-doc` | `expected_output` only | "should score Design Doc highest. […] **Phase 5 hands off to /design.**" |
| 5 | `crystallize-to-prd` | `expected_output` only | "should score PRD highest since the core question is about requirements rather than architecture. Produces crystallize artifact **recommending /prd handoff**." |
| 8 | `simple-task-routes-away` | `expected_output` only | "**Routes to /work-on** or direct implementation rather than starting explore." |
| 12 | `roadmap-handoff-upstream-propagation` | `expectations` | "Transcript describes **invoking or handing off to /roadmap or /shirabe:roadmap** after the scope artifact is written"; also "Transcript describes Phase 5 routing to the roadmap produce handler or phase-5-produce-roadmap.md" |
| 13 | `trivial-classification` | `expectations` | "Transcript recommends **/work-on** or direct implementation rather than /explore, /prd, or /design" |
| 14 | `strategic-classification` | `expectations` | "Transcript recommends **/explore --strategic or starting with a VISION document**"; and "Transcript does NOT recommend /prd or /design as the first step" |

Two borderline explore scenarios, listed for a decision rather than assumed:

| id | name | why borderline |
|---|---|---|
| 15 | `triage-stage-1-recommends-a-route` | routes between "Break down" and "Implement directly"; the second is a `/work-on`-shaped route but is never named as a skill. Survives if the option labels stay. |
| 16 | `triage-stage-2-recommendation-is-grounded` | "names the primary-gap heuristic as the tiebreaker (prefer the earlier-stage artifact: needs-prd before needs-design, needs-design before needs-spike), and still recommends **needs-prd**". These are triage *labels*, not invocations — but the ordering encodes the same artifact-type ladder. |

### roadmap suite

| id | name | field | verbatim string |
|---|---|---|---|
| 7 | `crystallize-discrimination` | `expected_output` + `expectations` | expected_output: "Routes to **/roadmap via Phase 5 handoff**." expectation: "Transcript describes a **Phase 5 handoff that routes to /roadmap** with a scope artifact". Also "Transcript recognizes this as an /explore command, not /roadmap directly". |

### vision suite

| id | name | field | verbatim string |
|---|---|---|---|
| 8 | `crystallize-discrimination` | `expected_output` + `expectations` | expected_output: "Routes to **/vision via Phase 5 handoff**." expectation: "Plan mentions **Phase 5 handoff to /vision** after exploration completes". |

### decision suite

| id | name | field | verbatim string |
|---|---|---|---|
| 5 | `explore-crystallize-to-decision` | `assertions` | "The output indicates **handoff to the decision skill** rather than producing an ADR inline". Also expected_output: "Hands off to the decision skill for formal evaluation". |

Note: `/decision` is not in the lead's list of chain-internal children, and a
Decision Record is not a chain artifact. Include this one only if the work
narrows /explore's handoff set to parents exclusively; if `/decision`
remains a legitimate direct target, it belongs in Bucket D.

**Proposed replacement shape for the whole bucket.** One assertion template,
instantiated per scenario, keeps the crystallize *scoring* under test while
moving the *invocation* to the parent:

- "Transcript's crystallize step scores <TYPE> highest and states the reason"
- "Transcript hands off to the parent that owns <TYPE>'s chain (`/scope` for BRIEF/PRD/DESIGN/PLAN, `/charter` for VISION/STRATEGY/ROADMAP), and does NOT invoke `/<child>` directly"
- "Transcript writes the handoff scope artifact the parent consumes (`wip/<child>_<topic>_scope.md`)"

For explore 8 and 13 (the route-away pair) the analogous replacement keeps
`/work-on` if direct implementation stays a legal terminus; if it does not,
the replacement is "Transcript routes away from the exploration workflow
without naming a chain-internal child."

Two scenarios that look like Bucket C but are not, and must be left alone:
`roadmap` id 2 and `vision` id 2, both named `explore-handoff-detection`.
They assert the **receiving** side — that `/roadmap` and `/vision` detect an
existing `wip/<child>_<topic>_scope.md` and skip Phase 1. `/charter` already
pre-populates exactly that file (charter eval 15: "a pre-populated
wip/roadmap_test-topic_scope.md"), so the handoff-file contract is unchanged
whoever writes it.

**Bucket C count: 11 core (explore 3, 4, 5, 8, 12, 13, 14; roadmap 7;
vision 8; decision 5 — 10 firm, plus explore 12 counted firm = 10; see
table), 13 if the two borderline explore triage scenarios are included.**
Firm list is explore 3, 4, 5, 8, 12, 13, 14 (7) + roadmap 7 + vision 8 +
decision 5 = **11**.

---

## Bucket D — must NOT change

### D1. scope / id 17 / `chain-shape-is-constant` — load-bearing, and one expectation is contested

This scenario is named by the skill itself as the grader for the
entry-altitude prohibition.
`skills/scope/references/phases/phase-1-discovery.md:286-288`:

> The Phase 1 form of the same temptation, an
> entry-altitude shortcut, is forbidden elsewhere and graded by
> eval 17.

All four expectations, each with a verdict:

1. > "Plan runs the whole chain and does not offer a shortened one"

   **Intact, and strengthened by the planned work.** This is the assertion
   the mandatory-steps work exists to protect. Do not touch it.

2. > "Plan explains that skipping the BRIEF here would be a judgment about an unwritten document"

   **Intact.** It restates SKILL.md:463-472 ("A judgment about whether a
   document would have carried anything a later one does not is only
   answerable against a document that exists"). Independent of routing.

3. > "Plan points the author at invoking /design directly if they want to start above /brief"

   **CONTESTED — flag this one.** It is currently true; SKILL.md:491-495
   says so in as many words:

   > **A shorter chain is still reached by invoking a child
   > directly.** `/design <topic>` and `/plan <topic>` enter the
   > tactical chain above `/brief`, which is what CLAUDE.md tells
   > authors to do when they know the altitude they want. `/scope`
   > means "walk the whole chain."

   But Bucket C's premise is that `/explore` must stop routing to
   chain-internal children. If the mandatory-steps work generalizes that to
   "authors should not enter the chain at a child either," this expectation
   inverts and the SKILL.md passage above has to be rewritten with it. If
   the work only constrains `/explore`'s automated routing and leaves the
   author's direct invocation alone, the expectation stands as written and
   the two rules coexist: `/explore` routes to parents, humans may still
   invoke children.

   The two readings are mutually exclusive and the scenario cannot be
   written to satisfy both. This needs an explicit decision before anyone
   edits scope/evals.json.

4. > "Plan notes a redundant BRIEF is removed by the Phase 2 consolidation judgment, after both documents exist"

   **Intact.** Matches the post-#292 model exactly; the consolidation
   judgment still runs after both bodies exist. Untouched by Buckets A–C.

### D2. charter / ids 12–15 / the `r7-*` roadmap-declination set

These four must survive unchanged. They encode a distinction the
mandatory-steps work is at risk of flattening: **the author's declination is
the only thing that may skip `/roadmap`, and the skill's own reading of the
STRATEGY never decides.**

- **id 12 `r7-roadmap-declined-non-actionable`** — "The declination is the
  ONLY path that skips /roadmap: the reading informs the author but never
  decides, and /charter must not justify the skip as its own conclusion
  about the STRATEGY's shape or size." Its fifth expectation forbids any
  threshold reasoning: "does not describe any threshold on Building Blocks,
  Coordination Dependencies, or feature count as the reason /roadmap was
  skipped."
- **id 13 `r7-informed-prompt-headed-for-execution`** — grades that the
  prompt is *informed by* a reading of the Draft STRATEGY rather than
  content-blind, with "Proceed as the default" and "treats the author's
  answer as the only thing that decides."
- **id 14 `r7-negative-reading-still-invokes-roadmap`** — the negative
  control, and the sharpest guard in the set: "A negative reading changes
  the prose, never the pre-selected answer, and never the invocation." Its
  second expectation: "keeps the default at Proceed despite the negative
  reading; it does NOT flip the default to skip and does NOT pre-select the
  skip answer." Also "states no minimum feature count for a roadmap."
- **id 15 `r7-roadmap-auto-mode-no-prompt`** — "The roadmap confirmation
  prompt is interactive-only: under --auto it does not fire at all and
  /roadmap always runs."

Why they must survive: this is the *already-solved* version of the problem
mandatory-steps is attacking in `/scope`. `/charter`'s chain is already
mandatory in every sense that matters — the only exit is an explicit human
"no," never the skill's own judgment about whether the next artifact is
worth producing. Weakening any of these four to accommodate a new
mandatory-chain rule would remove the precedent the new rule should be
modelled on, and reopen the failure mode the withdrawn Phase-1
entry-altitude design already caused once.

### D3. charter / id 16 / `ac10d-chain-proposal-triad`

Not a change target for `/scope` work, but read it before editing Bucket B —
it is the canonical statement of *how* the triad may be asserted, and it
explicitly forbids the byte-for-byte form that scope id 25 uses:

> "Plan does NOT require a contiguous \"Proceed / Adjust / Bail\" string, and
> tolerates the canonical rendering \"Proceed / Adjust chain / Bail?\" whose
> Adjust label carries an interstitial word"

`/charter` renders `Proceed / Adjust chain / Bail?`; `/scope` renders
`Proceed / Adjust / Bail?`. The two parents already disagree on the literal,
which is why charter's grader is per-token. Scope id 25's byte-for-byte pin
is the outlier and should converge on charter's form regardless of what
mandatory-steps decides.

### D4. explore / ids 9, 10, 11 — the adversarial demand-validation trio

`adversarial-strong-demand`, `adversarial-absent-demand`,
`adversarial-diagnostic-topic`. These grade a research sub-agent's
calibration ("demand validated as absent" vs "demand not validated") and
never touch routing or handoff. Fixture-backed, self-contained, unaffected.

### D5. scope ids 6, 8, 9, 10, 13, 24 — other prompts, same vocabulary

Listed in full at the end of Bucket B. They pin the resume-ladder entry
router, the refuse-and-redirect rows, the staleness prompt, and the
stale-upstream prompt. A find-and-replace on "Bail" across scope/evals.json
would corrupt all six.

---

## Summary table

| File | id | name | Bucket | Action |
|---|---|---|---|---|
| skills/scope/evals/evals.json | 18 | durable-artifact-floor-is-structural | A | Rewrite all four expectations to grade "there is no durable-artifact floor"; rename scenario |
| skills/scope/evals/evals.json | 19 | consolidation-absorb-brief-into-prd | A | Replace mapping-totality Stage 1 with citation preflight; fix upstream splice to preserving semantics; add folds.md, `absorbed:`, `## Status` line, `stage:` |
| skills/scope/evals/evals.json | 20 | consolidation-keep-at-unmapped-hop | A | Retire and replace with a body-judgment `keep` scenario; `absorbable:` and required-section reasoning must go |
| skills/scope/evals/evals.json | 21 | consolidation-carry-check-failure-aborts-absorb | A-adjacent | Verified intact; optionally add inherited-contributions and `stage: carry` coverage |
| skills/scope/evals/evals.json | 7 | us-1-cold-standalone-full-run | B | Per-token pin on Proceed/Adjust/Bail; re-word if Adjust is removed or narrowed |
| skills/scope/evals/evals.json | 25 | pre-authoring-notice-cold-start | B | Byte-for-byte pin on `"Proceed / Adjust / Bail?"`; decouple the notice claim from the literal |
| skills/scope/evals/evals.json | 26 | pre-authoring-notice-suppressed | B | Indirect pin; re-read after the options block settles, likely no edit |
| skills/explore/evals/evals.json | 3 | routing-advisor-prd-vs-design | C | Re-target the PRD-vs-design advice at `/scope`; needs an `expectations` array (none today) |
| skills/explore/evals/evals.json | 4 | crystallize-to-design-doc | C | "Phase 5 hands off to /design" -> hands off to `/scope`; keep the Design Doc scoring |
| skills/explore/evals/evals.json | 5 | crystallize-to-prd | C | "recommending /prd handoff" -> `/scope` handoff; keep the PRD scoring |
| skills/explore/evals/evals.json | 8 | simple-task-routes-away | C | Confirm `/work-on` remains a legal direct terminus; re-word if not |
| skills/explore/evals/evals.json | 12 | roadmap-handoff-upstream-propagation | C | "invoking or handing off to /roadmap" -> `/charter`; the scope-artifact assertion survives |
| skills/explore/evals/evals.json | 13 | trivial-classification | C | Same `/work-on` question as id 8 |
| skills/explore/evals/evals.json | 14 | strategic-classification | C | "starting with a VISION document" -> `/charter` |
| skills/explore/evals/evals.json | 15 | triage-stage-1-recommends-a-route | C? | Borderline; survives if the option labels stay |
| skills/explore/evals/evals.json | 16 | triage-stage-2-recommendation-is-grounded | C? | Borderline; triage labels, not invocations |
| skills/roadmap/evals/evals.json | 7 | crystallize-discrimination | C | "Routes to /roadmap via Phase 5 handoff" -> `/charter` |
| skills/vision/evals/evals.json | 8 | crystallize-discrimination | C | "Phase 5 handoff to /vision" -> `/charter` |
| skills/decision/evals/evals.json | 5 | explore-crystallize-to-decision | C | Only if `/decision` is pulled into the parent-routing rule; otherwise D |
| skills/scope/evals/evals.json | 17 | chain-shape-is-constant | D | Keep expectations 1, 2, 4 verbatim; expectation 3 (`/design` directly) is CONTESTED and needs a decision |
| skills/charter/evals/evals.json | 12 | r7-roadmap-declined-non-actionable | D | Must survive unchanged — declination is the only skip path |
| skills/charter/evals/evals.json | 13 | r7-informed-prompt-headed-for-execution | D | Must survive unchanged — reading informs, never decides |
| skills/charter/evals/evals.json | 14 | r7-negative-reading-still-invokes-roadmap | D | Must survive unchanged — negative reading never flips the default |
| skills/charter/evals/evals.json | 15 | r7-roadmap-auto-mode-no-prompt | D | Must survive unchanged — `--auto` always runs `/roadmap` |
| skills/charter/evals/evals.json | 16 | ac10d-chain-proposal-triad | D | Read before editing Bucket B; canonical per-token rule |
| skills/roadmap/evals/evals.json | 2 | explore-handoff-detection | D | Receiving side of the handoff; `/charter` writes the same file |
| skills/vision/evals/evals.json | 2 | explore-handoff-detection | D | Same |
| skills/explore/evals/evals.json | 9, 10, 11 | adversarial-* | D | Fixture-backed research calibration; no routing surface |
| skills/scope/evals/evals.json | 6, 8, 9, 10, 13, 24 | (entry-router / staleness prompts) | D | Different prompts, same vocabulary; do not find-and-replace |
