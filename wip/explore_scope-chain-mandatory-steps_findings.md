# Exploration Findings: scope-chain-mandatory-steps

## Core Question

Since #302 landed, `/scope` runs the full tactical chain on every invocation and
reduces the artifact set afterward by absorbing documents that did not earn their
keep. Several surfaces across the skill corpus still behave as though chain steps
are optional and choosable before the fact. Which surfaces are they, what does
each one actually do today, and what should replace it so the corpus states one
model consistently?

## Round 1

### Key Insights

**`/scope` is already converted; what survives is a prompt with no referent.**
(lead-scope-choice-surfaces) `planned_chain:` is the constant
`[brief, prd, design, plan]` minus re-entry-protected children, and
`references/state-schema.md:48-53` says outright "There is no field recording
where the chain starts, because it always starts at `brief`." The
`Proceed / Adjust / Bail?` block is inert: the chain is fully determined before
the block prints, no state field records the answer, Phase 2 reads only
`planned_chain:` and `chain_skipped:`, and `--auto` skips the prompt entirely
while producing the identical chain.

**Adjust's only real effect self-corrects one child later.**
(lead-scope-choice-surfaces) Re-running discovery re-runs the R6 predicates,
which size `/design`'s decision roster — a value the post-`/prd` gate re-derives
against the real PRD body. `phase-1-discovery.md:165-168` gives that
self-correction as the reason a Phase 1 estimate is safe at all.

**Bail at Phase 1 cannot execute either of its branches.**
(lead-scope-choice-surfaces) Clean-cancel is unreachable because Phase 0 always
writes `wip/scope_<topic>_state.md` before returning control, so the wip-state
disjunction always holds. Abandonment-forced has no child intermediate to
force-materialize, and R9 condition 2 then refuses finalization on the empty
`exit_artifacts:` that results. No eval exercises a Phase 1 bail.

**The prompt is a pattern-level contract, not a `/scope`-local one.**
(lead-parent-pattern) `references/parent-skill-pattern.md:596` fixes the three
option tokens, declares Proceed "the expected path," explicitly blesses
`/charter`'s `Adjust chain` rendering, and warns against generalizing
contiguity. Both parents' eval suites cite the rule by name. Fixing `/scope`
alone leaves the shared pattern requiring an option `/scope` no longer offers.

**The pattern document has zero awareness of #302.** (lead-parent-pattern) No
occurrence of "consolidat", "absorb", "fold", "worth", or "earn" in either
`parent-skill-pattern.md` or `parent-skill-state-schema.md`. Every statement of
the post-#302 model lives inside `skills/scope/`. `chain_skipped[].reason` is
pattern-level free text — an open vocabulary each parent closes locally and
incompatibly: `/scope` forbids a worth-producing reason ever appearing;
`/charter` uses one as its canonical example.

**Every `/charter` gate is re-entry protection or content availability.**
(lead-charter-gates) `/vision`'s thesis-shift signal can only reopen a gate the
auto-skip closed — a cold start runs `/vision` whatever the author says.
`/comp`'s gate is that a public repo cannot produce a private-only artifact at
all. `/strategy` and `/roadmap` are ALWAYS. `/charter` retired its own
pre-artifact worth gate (a three-Building-Blocks threshold on `/roadmap`) before
#302 existed, and narrates the retirement in #280's own terms.

**The roadmap declination is the one remaining pre-artifact drop, and it is
deliberate.** (lead-charter-gates, lead-parent-pattern) It is authorized by the
pattern's ALWAYS-declination clause, which names `/charter` as its canonical
consumer. It forms its judgment against a Draft STRATEGY on disk, keeps Proceed
pre-selected under both readings of the O1/O2/O3 walk, does not fire under
`--auto`, drops only the unwritten ROADMAP, and is graded by four evals written
specifically to keep the parent's reading advisory and the author's answer
decisive.

**`/charter` has no consolidation judgment at all.** (lead-charter-gates)
`grep -rn "consolidat" skills/charter/` returns nothing; all nine `absorb` hits
are the unrelated sense of absorbing an error. #302 reached only the tactical
chain. The strategic chain runs unconditionally and then keeps everything it
produced.

**`/execute` is a false positive on this axis.** (lead-parent-pattern,
lead-evals-enforcement) No chain proposal, no confirmation prompt, no
`planned_chain` (its omission is explicitly sanctioned by the state schema),
never uses the Gate Vocabulary, and nothing an author can drop. Its only
optionality is a mode-derived pause that is a suspension, not an exit. It
carries the cleanest statement of the post-#302 model in the corpus
(`SKILL.md:559-574`).

**`/explore` is further from the model than the author's framing suggested.**
(lead-explore-routing) It names a chain-internal child or artifact type as a
destination in roughly sixty places across nine files, entering the tactical
chain at three depths (`/prd`, `/design`, `/plan`) and the strategic chain at two
(`/vision`, `/roadmap`), with no vocabulary at all for BRIEF or STRATEGY.
`/scope`, `/charter`, and `/execute` appear nowhere in the skill.

**`/explore` authors durable artifacts today.** (lead-explore-routing) Four of
nine produce handlers write committed documents:
`docs/designs/DESIGN-<topic>.md` with `status: Proposed`,
`docs/spikes/SPIKE-*.md`, `docs/competitive/COMP-*.md`, and
`docs/decisions/REJECTED-*.md`. "Router only" is therefore a behavioral change,
not a documentation change.

**The missing STRATEGY altitude already produced a documented workaround.**
(lead-explore-routing) `phase-5-produce-roadmap.md` carries a five-sentence
warning that its own handoff yields an orphan ROADMAP whose absent upstream is an
`R10` direction violation nothing downstream catches — a workaround for exactly
the defect a chain-entry router removes.

**Seven `/explore` destination strings resolve to nothing in this repo.**
(lead-explore-routing) `/spike`, `/competitive-analysis`, `/triage`, `/issue`,
`/cleanup`, `spike-report/SKILL.md`, `decision-record/SKILL.md`. The first two
are the declared routes for two of its ten *supported* types.

**`/explore` commits to an artifact type twice.** (lead-explore-routing) Phase 0
Stage 2 applies one of four `needs-*` labels before Phase 1 runs; Phase 4 then
scores ten types after Phases 2-3. Nothing reconciles them — the Stage 2 label is
quietly non-binding but still lands on the GitHub issue.

**Four `/scope` evals grade the retired model.** (lead-302-residue,
lead-evals-enforcement) `skills/scope/evals/evals.json` was never touched by
#302. Scenario 18 asserts "no hop above BRIEF-to-PRD is absorbable, so the
smallest set a run can end with is a PRD, a DESIGN and a PLAN" against
`SKILL.md:472`'s "There is no durable-artifact floor." Scenario 20 requires
deriving absorbability from per-type required-section contracts — the exact input
`phase-2-chain-orchestration.md:520` bans as the defining violation — and names
the retired `absorbable:` field. Scenarios 19 and 21 inherit a stage vocabulary
that no longer matches.

**This is an unmet acceptance criterion, not a discovered inconsistency.**
(lead-302-residue) `PRD-scope-artifact-persistence.md` R24 required scenarios
18/19/20 be rewritten so no scenario references a type-level mapping check;
`DESIGN-scope-artifact-persistence.md:444` names the file and singles out
scenario 17 as deliberately untouched. The scenario-17 carve-out landed by doing
nothing; the rewrite did not. Both documents sit at terminal status
(`Done` / `Current`) with the requirement unmet.

**Nothing mechanical catches this drift.** (lead-evals-enforcement)
`run-evals.yml` is `schedule` (Monday 04:00 UTC) plus `workflow_dispatch` — it
does not run on pull requests. The PR-time check, `check-evals-exist.sh`, only
counts that eval files are non-empty. No CI script greps for `Proceed`,
`Adjust`, `Bail`, `planned_chain`, or `chain_skipped`. No crate reads
`skills/**` as a validation target.

**#280 Direction 4 was already declined and fenced.** (lead-302-residue)
`PRD-scope-artifact-persistence.md` R28: "Nothing here SHALL reintroduce a
pre-artifact worth decision in any form, **including an author-chosen entry
altitude**," with eval 17 named as its tripwire. This exploration enforces an
existing rule rather than proposing a new one.

**Where enforcement exists, it already states the new model.**
(lead-evals-enforcement) `crates/shirabe-validate/src/formats.rs` encodes the
tactical chain in code — `CONTRIBUTION_SECTIONS` as the ordered chain,
`ABSORBED_ENTRY_PATTERN` admitting BRIEF/PRD/DESIGN but not PLAN, FC18's strict
above-ness. The evals are behind the code, not the other way around.

### Tensions

**The stale redirect and the guard that protects the model are the same string.**
`phase-1-discovery.md:38-43` gives "an author who wants a shorter chain reaches
for a child skill directly" as live advice; line 278 of the same file declares
that redirect an escape hatch from a constraint that no longer exists. One commit
updated one half of one file. But eval 17's third expectation — "Plan points the
author at invoking /design directly if they want to start above /brief" — pins
the redirect, and eval 17 is the tripwire against reintroducing entry-altitude
choice. Retiring the advice means re-cutting the tripwire without weakening what
it guards. Four other surfaces state the redirect as live: `SKILL.md:10-12`,
`SKILL.md:401-403`, `SKILL.md:461-465`, and `CLAUDE.md:171-174`.

**"Shorter chain" is ambiguous and the corpus never disambiguates it.**
Absorption reduces the artifact *set* but not the *conversation* — an author who
says the framing is settled still sits through a BRIEF and a PRD before the fold
happens. If "shorter" means fewer artifacts, the redirect is obsolete. If it
means less conversation, the redirect is the only answer. That decides whether
the redirect is retired or merely re-justified.

**The roadmap declination reads two ways from the same evidence.** It is the
corpus's only pre-artifact drop and the pattern clause authorizing it is the only
sanction for one (lead-parent-pattern's reading), and it is also the closest
`/charter` comes to #302's discipline, since the judgment is formed against a
document that exists (lead-charter-gates' reading). Both are supported. Resolved
this round in favor of keeping it — see Decisions.

**"Router only" collides with four outcomes no chain owns.** Rejection Record,
Decision Record, Spike Report, and COMP are terminal by construction. Three are
backed by real machinery. `/execute` takes a PLAN doc path, not an issue number,
so a strict four-arm router leaves "file an issue" terminating with no named next
step, contradicting explore evals 8 and 13 which route trivial and simple work to
`/work-on`.

**"Never authors chain artifacts" collides with the handoff mechanism.**
`vision` eval 2 and `roadmap` eval 12 both assert `/explore` writes a
`wip/<child>_<topic>_scope.md` that the downstream skill detects, so it skips its
Phase 1 rather than re-asking what the exploration settled. Resolved: the
prohibition covers durable artifacts, not wip handoff artifacts.

**`/scope` contradicts itself on whether `planned_chain:` is constant.** The
phase file says `[brief, prd, design, plan]` on every run;
`skills/scope/evals/evals.json:111` says a re-entry-protected `/prd` is kept out
of `planned_chain` and recorded in `chain_skipped`. Any "match `/scope`"
instruction to `/charter` has to say which `/scope`.

**`--upstream` shortens `/charter`'s chain but not `/scope`'s.** Same flag token,
same declared meaning, opposite effect on chain shape. In `/charter` a supplied
upstream makes the `/vision` entry read "skip"; in `/scope` `/brief` still runs
and grounds on the roadmap. An author moving between the parents cannot predict
this.

**`/scope` and `/charter` render the same triad differently on purpose.**
`Proceed / Adjust / Bail?` versus `Proceed / Adjust chain / Bail?`, with
`/scope`'s pinned byte-for-byte by evals 25 and 26 and `/charter`'s asserted
per-token by eval 16. Removing it from one parent but not the other only half
meets the one-model goal — and `/charter` has the better claim to keeping it,
since it genuinely has an optional child.

### Gaps

- **`docs/folds.md` has zero rows.** The whole post-#302 mechanism — the fold,
  the `absorbed:` frontmatter, FC17/FC18/FC19, the CI blob check — has never
  fired on this repository. #302's own PR body says its chain "ran under the
  mechanism it replaces," so the three `-scope-artifact-persistence` documents
  survive as artifacts of the retired test rather than as evidence the new one
  kept them. Any claim about how the new model behaves in practice rests on Rust
  unit tests and LLM-graded evals that themselves encode the old model.

- **No open issue tracks any of this.** `#255` (unasserted judgment gates in
  `/scope`, `/explore`, `/design`) is the nearest neighbour and predates #302;
  `#254` (three unresolved items in the parent-skill chains) may be the natural
  home for corpus-consistency chores. `#259` and `#256` cover README problems
  without naming the durable/working paragraph that a fold now invalidates.

- **Phase 4 reproduces only three of the framework's seven tiebreakers.** The
  four VISION tiebreakers exist only in `crystallize-framework.md`; a Phase 4 run
  following the phase file literally never applies them — precisely the
  strategic-altitude discriminations a router most needs.

- **`SKILL.md`'s Reference Files table is stale by three files** and misroutes
  Roadmap, a pre-existing inconsistency any rewrite inherits.

- **`references/pipeline-model.md` restates the old model while naming
  `/explore` as its authority.** Its "Skip" transition ("Simple work skips
  Diamonds 1-2. Medium skips Diamond 1") is a second corpus-level statement that
  steps are choosable before the fact.

- **The pattern doc's parent roster predates `/execute`.** It enumerates "both v1
  parents (`/scope`, `/charter`) and all seven children"; `/execute` and
  `/work-on` appear nowhere, while `/execute`'s Team Shape section claims
  complete conformance.

- **`chain_skipped:` reason counts are wrong in two places.** Both
  `phase-1-discovery.md:429-432` and `references/state-schema.md:89-91` say
  Phase 2 writes "one further reason"; the templates write two distinct literals
  (`PRD-boundary rejection`, `DESIGN-boundary rejection`), neither enumerated in
  the state schema, and `phase-2-chain-orchestration.md`'s own Reject Handling
  section never mentions writing `chain_skipped:` at all.

- **`chain_revised:` is an orphan.** Written by the phase file, absent from
  `/scope`'s state schema, read by nobody, and named after the produce-or-skip
  behavior `phase-1-discovery.md:156-160` explicitly retires. The post-`/prd`
  gate also carries a second confirmation prompt with no options block, no branch
  list, and no state record.

- **Retired-model prose in two adjacent Done documents.**
  `BRIEF-chain-cardinality.md` and `PRD-chain-cardinality.md` carry the
  section-mapping absorbability criterion with no amendment, unlike their
  consolidation siblings which got one on 2026-08-15. The amendment pattern is
  the corpus's established answer and the precedent is one commit old.

### Decisions

Recorded in full in `wip/explore_scope-chain-mandatory-steps_decisions.md`.
In brief: all four parent surfaces plus the shared pattern references are in
scope; `/explore` becomes a four-way router plus a terminal recording set for
the off-chain artifact types no chain owns; "never authors chain artifacts"
covers durable artifacts only, so the `wip/` handoff mechanism survives;
`/charter` keeps its roadmap declination and the model is restated around it;
porting a consolidation judgment to the strategic chain is out of scope for this
change; `/execute` needs no change on this axis; and the stale `/scope` evals
(18-21) are fixed in the same pass.

### User Focus

The author's initial framing named two surfaces: `/explore` determining a step
inside `/scope` to start from, and `/scope` opening by asking which steps will
run. Research confirmed both in substance and relocated both in detail — the
`/scope` prompt is inert and inherited from the shared pattern, and `/explore` is
further from the model than the framing suggested, because it authors durable
artifacts rather than merely naming children. The author elected to keep
`/charter`'s roadmap declination as the model to restate around rather than the
last violation to remove, chose the wider router that preserves off-chain
recording, and pulled the stale eval repairs into the same change.

## Accumulated Understanding

The corpus states one model in `/scope`'s and `/execute`'s prose and a different
one in four other places, and the difference is not evenly distributed.

The model, as `/scope` and `/execute` now state it: chain steps are mandatory,
because a judgment about whether a document would have carried anything can only
be made against a document that exists. Reduction happens after the artifacts
exist, per hop, against two bodies, by a judgment forbidden from reading either
type's required-section list. `/execute` states the corollary — it must not know
what the chain decided.

The four surfaces that have not caught up:

1. **`references/parent-skill-pattern.md`** is the fix site, and the least
   obvious one. It is the source of the chain-proposal triad that both parents
   emit and both eval suites grade; its ALWAYS-declination clause is the corpus's
   only authorization for dropping a step before its artifact exists; its
   `chain_skipped[].reason` vocabulary is open free text that the two parents
   close incompatibly; and it contains no statement of the post-#302 model at
   all. A skill-local fix leaves the pattern contradicting the skill.

2. **`skills/explore/`** is the largest surface by volume and the only one whose
   defect is behavioral rather than editorial. It routes into chain interiors at
   five different depths, has no vocabulary for two altitudes, authors four kinds
   of durable document, and names seven destinations that do not exist. Its
   Phases 0-3 — the discover-converge research loop that is its actual value —
   are untouched by the fix, and its crystallize *procedure* (score, rank,
   tiebreak, insufficient-signal fallback) is type-count-agnostic and survives
   against four arms as readily as ten types.

3. **`skills/scope/evals/evals.json`** is the only executable statement of what
   `/scope` should do, and four of its scenarios grade the model #302 removed.
   This is a shipped acceptance-criterion miss with a named requirement (R24) and
   two unchecked ACs, not a newly discovered inconsistency.

4. **A handful of single-paragraph staleness** in `/scope`'s own prose: the
   self-contradicting redirect at `phase-1-discovery.md:38-43`, the stale
   justification at `SKILL.md:401-403`, the stale reference annotation at
   `phase-2-chain-orchestration.md:853-855`, the orphan `chain_revised:` field,
   and the wrong reason-count claim about `chain_skipped:`.

What is *not* wrong: `/charter`'s gates (all re-entry protection or content
availability, its pre-artifact worth gate retired on its own timeline before #302
existed), `/execute` (clean, and ahead of `/scope` on stating the model), and
`/scope`'s actual chain behavior (`planned_chain:` is constant; the prompt that
appears to negotiate it cannot).

Two things the corpus has not decided and this change must:

- What "a shorter chain" means to an author now that absorption reduces the
  artifact set but not the conversation. That decides whether the
  direct-invocation redirect is retired, narrowed, or merely re-justified — and
  eval 17 pins it either way.
- Where the interactive entry to R8 bail-handling lives if `Bail` leaves the
  Phase 1 prompt. Eval 12 needs `abandonment-forced` reachable, and the resume
  ladder's `Resume / Force-materialize / Discard` row is currently the other
  route to it.

One structural observation that colors the whole change: nothing mechanical
enforces any of this. Evals run on a weekly cron rather than on pull requests,
the PR-time check only counts files, and no crate or CI script reads skill prose.
The corpus drifted for a full release cycle with a shipped requirement unmet and
nothing surfaced it. Whatever this change lands, the same drift can recur unless
something checks at PR time.

## Decision: Crystallize

Round 1 was sufficient. The author elected to decide rather than run a second
round; the residue is choices to make against alternatives, not facts to find.
