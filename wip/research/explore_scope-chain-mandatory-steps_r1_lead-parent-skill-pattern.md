# Lead: What does the shared parent-skill pattern say a gate may be, and who conforms?

## Findings

### 0. What is actually in repo-root `references/`

`${CLAUDE_PLUGIN_ROOT}` resolves to the worktree root
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe_inconsistencies-03b57366/public/shirabe/.claude/worktrees/scope-chain`.
The repo-root `references/` directory holds 19 files plus a `fixes/`
subdirectory. The ones bearing on chain shape:

| File | Bearing |
|---|---|
| `references/parent-skill-pattern.md` (40 KB, 772 lines) | The contract surface. Owns the Gate Vocabulary, the Three Exit Paths, the Conditional Feeder Invocation Shape, the Dispatch Contract, the seven required SKILL.md structural elements **and the prompt-vocabulary literal-form table that governs the chain-proposal triad**. |
| `references/parent-skill-state-schema.md` (264 lines) | The 5-field minimum, the `planned_chain` / `chain_ran` / `chain_skipped` triad, conditional-field gating (I-5), R9 hard-finalization check. |
| `references/parent-skill-child-inspection.md` | R14-widened isolation rule + per-*child-shape* surface table (doc-emitting vs issue/PR). Names no parent by name; nothing chain-shape-deciding. |
| `references/parent-skill-resume-ladder-template.md` | Meta-ladder rows; mentions `/scope` and `/charter` only as examples. |
| `references/parent-skill-security.md` | Six security surfaces; nothing about gates. |
| `references/pipeline-model.md` | **Adjacent surface worth flagging** — see Surprises. Its "Named transitions" table defines a **Skip** transition: "Diamond 1 or 2 → Later diamond … Complexity routing bypasses diamonds. Simple work skips Diamonds 1-2. Medium skips Diamond 1." (`references/pipeline-model.md:63`). This is entry-altitude routing, not an in-parent gate, but it is a corpus-level statement that steps are chooseable before the fact. |
| `references/workflow-principles.md` | No gate content. |

### 1. The complete Gate Vocabulary (`references/parent-skill-pattern.md:113-195`)

The pattern opens the section with a closure claim:

> "Parents invoke children behind named gates. The pattern recognizes
> three gate shapes; **every child-invocation gate in every parent SHALL
> be one of these three.**" (lines 115-117)

The three shapes:

**ALWAYS** (lines 121-137) — "the child is invoked unconditionally on
every chain run; no gate exists." Canonical examples: `/charter`'s
`/strategy` and `/roadmap`, `/scope`'s `/plan`. **This entry carries the
declination clause, and it is the load-bearing sentence for this
exploration:**

> "A parent MAY additionally offer the author an explicit declination for
> an ALWAYS child (`/charter` does, for `/roadmap`); that is
> author-supplied input, not a predicate the parent computes, and unlike
> an exit-path intervention such as Bail it leaves the chain on its
> normal exit with the skip recorded in `chain_skipped`. A parent MAY
> read the upstream artifact to inform what it tells the author at that
> declination prompt — reading for the prompt is not reading for the
> gate, and the gate stays ALWAYS as long as no reading can change the
> pre-selected answer or skip the child on its own. Offering a
> declination is per-parent and optional — `/scope`'s `/plan` is ALWAYS
> with no declination surface."

**shape-dependent** (lines 139-147) — "the child invocation's *form*
(which sub-shape of the child fires, with how many peers, against which
set of inputs) is determined by an upstream-recorded predicate on the
chain. The gate is not whether-to-invoke but how-to-invoke." Canonical
example: `/scope`'s `/design` and the R6 predicates.

**Mandatory-with-auto-skip** (lines 149-168) — "the child SHALL be
invoked **unless its durable artifact already exists at the
published-Accepted status at the canonical path**, in which case the
child is recorded in `chain_skipped` and the chain proceeds to the next
gate." A parent MAY define an override that fires the child anyway; the
override "can only fire in the case the auto-skip would otherwise have
closed the gate — a settled artifact already on disk — so a cold start
fires the child whatever the signal says" (lines 174-179).

**A fourth shape existed and was retired.** Lines 181-195: *EITHER-signal
retired 2026-08-08* — folded into Mandatory-with-auto-skip's
optional-override clause, because no gate ever invoked its child on a
signal alone. Docs written before that date may still say EITHER-signal;
read the label as auto-skip-with-override.

#### Does the vocabulary still admit a "this artifact would not be worth producing" gate?

**Yes — via the ALWAYS declination clause, and the pattern does not
forbid it anywhere.** Three findings, in order of decisiveness:

1. **No prohibition exists.** `grep -in "worth\|consolidat\|absorb\|earn"`
   across `parent-skill-pattern.md` and `parent-skill-state-schema.md`
   returns **zero** hits on the concept. The pattern doc has no sentence
   forbidding a worth-producing predicate, no mention of consolidation or
   absorption, and no awareness that `/scope` now reduces its artifact
   set after the fact. Post-#302 language exists **only** in `/scope`'s
   own phase files and state-schema, never at the pattern layer.

2. **The declination clause positively sanctions a pre-authoring drop.**
   The quoted ALWAYS clause names `/charter`'s `/roadmap` declination as
   the canonical instance and blesses reading the upstream artifact to
   frame the question. So a parent may compute a reading about whether a
   downstream artifact is warranted, present it, and let the author drop
   the child before it ever runs. What the pattern forbids is only that
   the *parent's* reading decide by itself; the *author's* answer
   deciding is explicitly in-contract.

3. **`/charter` binds that clause as exactly a worth-producing question.**
   `skills/charter/references/phases/phase-2-chain-orchestration.md:300-313`
   — "The one path that skips `/roadmap` is an explicit author
   declination… The question the prompt asks is NOT 'is this strategy big
   enough to sequence.' Size never disqualifies a ROADMAP. The question is
   whether the strategy is **headed for execution at all** — a STRATEGY
   that records a bet nobody intends to act on is the one case that
   legitimately gets no ROADMAP." The observation walk (O1/O2/O3, lines
   314-341) reads the Draft STRATEGY and rolls up a
   `headed-for-execution` / `not-headed-for-execution` verdict, then asks
   with **Proceed** pre-selected in both readings (lines 352-376). Line
   404: "The confirmation prompt is the ONLY path that skips `/roadmap`."

   Note what this is: a judgment made **before the ROADMAP exists**,
   about whether the ROADMAP would earn its keep — the exact shape
   `/scope` now refuses to make. `/scope`'s Phase 1 says so in as many
   words (`skills/scope/references/phases/phase-1-discovery.md:134-140`):
   "**This is not a worth-producing judgment.** … Nothing at Phase 1 is
   in a position to make the second claim, because the artifact it would
   be about does not exist."

Two secondary observations on the vocabulary:

- **`/scope` has already been scrubbed inside the three shapes without
  the shapes changing.** Phase 1 lines 156-160: "The predicates do **not**
  decide whether `/design` is invoked. `/design` runs on every chain. R7
  previously read these verdicts as a produce-or-skip gate; that reading
  is retired, and 'shape-dependent' now means what it says in the Gate
  Vocabulary — the gate governs *how* a child is invoked, not whether."
  So #302's fix at `/scope` was achieved by *reinterpreting* shapes the
  pattern already defined, not by amending the pattern.
- **Mandatory-with-auto-skip's skip condition is re-entry protection, not
  reader economy.** Its condition is "a settled document is already here,
  and re-running would clobber it" — which never conflicts with the
  mandatory-steps model.

### 2. The `planned_chain:` / `chain_ran:` / `chain_skipped:` triad

`references/parent-skill-state-schema.md:135-152`:

> - **`planned_chain`** — the children the parent intended to invoke at
>   the start of the chain.
> - **`chain_ran`** — the children whose invocations completed.
> - **`chain_skipped`** — children the chain decided to skip, **with
>   free-text reasons**.

Plus (lines 147-152) the triad is itself conditional: non-chain-shaped
parents MAY omit all three; extension rule 3 (lines 206-209) says they
stay together — "no half-set."

**The reason vocabulary is OPEN, not closed.** "free-text reasons" is the
only pattern-level constraint on `chain_skipped[].reason`. There is no
enum, no allowed-value list, and no validator check named anywhere in the
schema doc. The only other pattern-level statement about the field is
negative and scoped to feeders: `parent-skill-pattern.md:220-224` — a
child whose *conditional-feeder* gate never opened gets **no**
`chain_skipped:` entry at all, "a child whose gate never opened was never
planned, so there is nothing to record."

Each parent then closes the vocabulary **locally**, and the two parents
close it differently:

- `/scope` (`skills/scope/references/state-schema.md:81-91` and
  `phase-1-discovery.md:427-432`): exactly two reasons exist —
  `settled-artifact-at-canonical-path-reentry-protection` (Phase 1), and
  one Phase 2 reason for a Reject at a settled-upstream boundary ending
  the chain. Explicitly: "a child is never recorded here because the
  chain judged its artifact not worth producing, since `/scope` makes no
  such judgment before an artifact exists."
- `/charter` (`phase-2-chain-orchestration.md:384-393`,
  `phase-state-management.md:143-159`): reasons include a supplied
  `--upstream` VISION, an Accepted/Active VISION with no thesis shift,
  and — the one at issue — `reason: author declined the roadmap at the
  confirmation prompt`.

So the same field carries, in one parent, a rule that no
worth-producing reason may ever appear, and in the other, a
worth-producing reason as its canonical example. Nothing at the pattern
layer arbitrates.

Also note `chain_skipped[].reason` is durably public: `/charter`'s
`phase-state-management.md:443-444` lists it among the free-text fields
"durable on the feature branch pre-merge; public."

### 3. Which parent skills exist, and how each conforms

Three parent skills: `/charter` (`skills/charter/SKILL.md`, 340 lines),
`/scope` (`skills/scope/SKILL.md`, 883), `/execute`
(`skills/execute/SKILL.md`, 734). All three declare conformance; all
three cite `parent-skill-pattern.md` in their Reference Files tables.

**`/charter`** — `SKILL.md:19-20` "the first parent skill in the shirabe
parent-skill pattern"; `:40-44` cites the pattern and its "three
companion references"; `:269` its Reference Files row names the vocabulary
verbatim: "Gate Vocabulary (Mandatory-with-auto-skip plus thesis-shift
override on `/vision`; ALWAYS on `/strategy` and `/roadmap`)". Uses the
vocabulary verbatim in its phase files, including the retired-shape note
(`phase-2-chain-orchestration.md:67-72`). **Divergence:** it exercises the
ALWAYS-declination clause for `/roadmap`, and its `/comp` feeder runs the
Conditional Feeder shape. It emits `Proceed / Adjust chain / Bail?`
(`phase-1-discovery.md:267` and `:291`) and that prompt genuinely can
drop nothing — `phase-1-discovery.md:250-255` is explicit that
`/strategy` and `/roadmap` "always appear as 'run' … The author's
opportunity to drop `/roadmap` comes later, at the roadmap confirmation
prompt … not here", and `phase-2-chain-orchestration.md:404-413` confirms
"Phase 1's 'Adjust' option re-shapes the chain before any child fires,
but it cannot drop `/roadmap`". `/vision` can be dropped at proposal
time, but only via the auto-skip (a VISION already exists, or
`--upstream` supplied) — not by author preference.

**`/scope`** — `SKILL.md:18` "the second parent skill"; `:32-44` cites the
pattern and names its own asymmetries including "a post-hoc consolidation
judgment that is the only thing reducing the artifact set and runs only
after the artifacts exist". Uses the vocabulary verbatim
(`SKILL.md:374`, `:393-395`; `phase-1-discovery.md:124-126`, `:159-160`,
`:261-264`, `:476-478`). **Divergence:** it still emits the pattern's
chain-proposal prompt (`SKILL.md:388-423`, `phase-1-discovery.md:290-328`)
whose Adjust branch is documented as inert against the chain — "Adjust
refines the topic and the framing, not the list of children"
(`SKILL.md:411-412`), "Adjust does not change which children run, because
that list is fixed" (`phase-1-discovery.md:465-466`), and "That list is a
constant. Phase 1 has no input that can shorten it and no field that
records a different shape" (`phase-1-discovery.md:416-417`). The proposal
itself now says so in its own body — "Planned chain (the full tactical
chain, as always)" and "Any artifact that turns out to be redundant is
absorbed after it and its successor both exist, not skipped now"
(`phase-1-discovery.md:301`, `:314-315`). So `/scope`'s residue is a
**prompt whose option no longer has a referent**, not a live skip path.

**`/execute`** — `SKILL.md:15` "the third parent skill in the trio, at the
implementation altitude (alongside `/charter` strategic and `/scope`
tactical)". Its frontmatter description claims "parent-skill conformance";
`SKILL.md:706-718` (Team Shape) asserts the binding is complete across
its sections. Its children are **`/work-on` single-issue runs, one per
PLAN issue** — single-pr materializes them through koto against
`${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md`
(`SKILL.md:191-196`); coordinated dispatches one per unblocked PR node in
the merge-order DAG (`SKILL.md:308-313`).

**`/execute` has no chain proposal, no confirmation prompt, and no way
for an author to drop anything.** Concretely:

- It **omits the chain-tracking triad entirely** —
  `SKILL.md:394-398`: "The `/execute` run is a homogeneous execution loop
  rather than a heterogeneous authoring chain, so the chain-tracking triad
  (`planned_chain` / `chain_ran` / `chain_skipped`) and the authoring
  discriminators … are omitted; their omission satisfies I-5". This is
  sanctioned by `parent-skill-state-schema.md:147-152`.
- It **never uses the Gate Vocabulary** — `grep` for ALWAYS /
  shape-dependent / Mandatory-with-auto-skip / Gate Vocabulary across
  `skills/execute/` returns nothing. Its pattern citation
  (`SKILL.md:731`) covers only "the seven required SKILL.md structural
  elements, the three exit names, substitution surfaces."
- Its only author-facing stop is the **mode-driven `paused_for_review`**
  (`SKILL.md:212-239`), and the SKILL is emphatic that this is a
  **suspension, not an exit and not a skip**: "`exit:` stays UNSET…"
  (`:500-513`). It drops no work; a resume finalizes.
- Its issue set comes from the PLAN via `plan-to-tasks.sh`; the only
  non-execution of an issue is `skip-dependents` isolation after a child
  blocks (`SKILL.md:481-483`, `:607-609`) — a failure-isolation mechanic,
  never an author choice, and never a worth-producing judgment.
- It already **knows about post-hoc consolidation** and handles it
  correctly: `SKILL.md:559-574` — "`/scope`'s consolidation judgment can
  absorb at any hop, so a chain can end with no durable artifact at all…
  **`/execute` does not know what the chain decided, and must not start
  knowing.** Whether any artifact survives is `/scope`'s call, made per
  hop against two documents."

**So `/execute` is clean on the optional-step question.** It is *not*
clean on a different axis: the pattern doc does not know it exists (below).

### 4. Is the fix THREE local fixes or ONE pattern-level fix?

**It is ONE pattern-level fix plus at most two thin local follow-ons.**
`/execute` needs no change on this axis at all, so it is not three.

The decisive evidence the lead asked for — **is the pattern document the
source of the `Proceed / Adjust / Bail` chain-proposal prompt?** Yes, in
the sense that matters. `references/parent-skill-pattern.md:582-607`
carries the "Which literal form to require" rule and this table row:

> | Chain proposal (`Proceed` / `Adjust` / `Bail`) | no — Proceed is the
> expected path, and a parent MAY render an interstitial label such as
> "Adjust chain" | per-token |

and immediately after (lines 600-602): "Do NOT generalize contiguity to a
triad in the per-token rows: a parent whose chain-proposal prompt renders
'Adjust chain' would fail a contiguous check against its own canonical
example."

That is the pattern **naming the chain-proposal prompt as a contract
surface, fixing its three option tokens, fixing the semantics of one of
them ("Proceed is the expected path"), and explicitly blessing
`/charter`'s "Adjust chain" rendering**. The preceding paragraph
(lines 575-580) says the default-option wording at these prompts "is part
of the contract surface, not a UX detail; each parent specifies it as
literal-substring requirements in ACs … so the eval surface can
grep-check the prompt vocabulary and downstream parents inherit the
discipline."

The inheritance is real and observable in both eval suites:

- `skills/charter/evals/evals.json:242-247` cites the rule by name — "Per
  the Gate Vocabulary's prompt-vocabulary rule in
  `references/parent-skill-pattern.md`, this triad is asserted PER-TOKEN
  rather than as one contiguous string" — and asserts the tolerance for
  "Adjust chain".
- `skills/scope/evals/evals.json:102` and `:383` assert the literal
  `Proceed`/`Adjust`/`Bail` substrings and that the options block reads
  `"Proceed / Adjust / Bail?"` byte-for-byte.

So changing or removing Adjust is a **pattern-level change** that
invalidates a pattern-doc table row, a pattern-doc "do NOT generalize"
warning, and graded assertions in both parents' eval suites. Fixing
`/scope` alone would leave the pattern still requiring an option `/scope`
no longer offers, and would leave `/charter` inheriting the requirement.

The second pattern-level item is the **ALWAYS declination clause**
(lines 128-137). It is the *only* place in the corpus that authorizes
dropping a chain step before the artifact exists, and it names `/charter`
as its canonical consumer. Whatever the corpus decides about
`/charter`'s roadmap declination has to be decided there — the clause's
canonical example is the behavior in question, so editing `/charter`
without editing the clause leaves the pattern advertising an example that
no longer exists (the same failure mode the EITHER-signal retirement note
was written to fix).

The counter-consideration, stated fairly: the two prompts do **different**
things today. `/scope`'s is dead wood (an option that cannot act);
`/charter`'s is live (an option that genuinely drops `/roadmap` and
records it). A minimal reading says `/scope` gets a prompt simplification
and `/charter` gets a policy decision, each local. But both hang off
pattern-doc text — the literal-form table row for the first, the ALWAYS
declination clause for the second — and neither can be changed without
the pattern doc going stale. The pattern doc is where the model is
stated; it is the fix site.

Third pattern-level item, smaller: the pattern doc contains **no
statement of the post-#302 model at all**. Nothing in
`parent-skill-pattern.md` or `parent-skill-state-schema.md` says chain
steps are mandatory and reduction is post-hoc. Both `/scope` phase files
state it in `/scope`-local prose. If the corpus is to "state one model
consistently," the sentence has to exist at the pattern layer, and
`chain_skipped[].reason`'s open free-text vocabulary is the natural place
to bound it.

### 5. `/inflight`

**Not a parent skill and not part of chain routing.** `skills/inflight/SKILL.md`
is a 111-line thin relay over the compiled `shirabe work-summary render`
subcommand, reporting the current session's tracked PRs
(`SKILL.md:19-23`). It is `disable-model-invocation: true`, user-invoked
only, `allowed-tools: Bash(shirabe:*)`, has no state file, no phases, no
children, no exit paths, and never mentions `parent-skill-pattern.md`. It
has no `references/` directory. It participates in nothing this
exploration touches.

## Implications

1. **The corpus-level fix belongs in `references/parent-skill-pattern.md`.**
   Two specific edits carry most of it: the ALWAYS declination clause
   (lines 128-137), which is the only pattern-level authorization for
   dropping a step before the artifact exists; and the prompt-literal-form
   table row for the chain proposal (line 596), which is why both parents
   emit an `Adjust` option and why both eval suites grade for it.

2. **`/scope` is already ~95% converted, and the residue is a prompt
   option with no referent.** Its phase files, state-schema, and eval
   expected-outputs all state the mandatory-chain model in as many words.
   The `Proceed / Adjust / Bail?` line survives because the pattern
   requires the triad, not because `/scope` still needs Adjust. The
   cheapest coherent outcome is: pattern drops or redefines Adjust for
   chain proposals; `/scope`'s prompt becomes a confirmation
   (Proceed / Bail) or a pure notice; both eval suites update.

3. **`/charter` is the live policy question, not `/scope`.** Its roadmap
   declination is a genuine pre-authoring worth-producing judgment,
   deliberately designed (observation walk, both-readings-default-Proceed,
   negative-control eval at `evals.json:216-220`). Converting `/charter`
   to the mandatory-steps model means the ROADMAP always gets written and
   any "this bet isn't headed for execution" reduction happens after the
   ROADMAP exists — which `/charter` has no consolidation machinery for.
   That is a design question, not a wording fix, and it is the thing that
   most needs a human decision.

4. **`/execute` needs nothing on this axis but exposes a separate
   pattern-doc staleness.** `parent-skill-pattern.md:381-384` says the
   dispatch contract "applies symmetrically to both v1 parents (`/scope`,
   `/charter`) and all seven children"; line 543 says "v1 has no
   per-parent override slot — the contract applies verbatim to both
   parents and all seven children"; lines 741-772 say "Both v1 parents
   (`/scope` and `/charter`)" and the closing table lists only `/scope`
   and `/charter`. `/execute` and `/work-on` appear nowhere. Whoever edits
   the pattern doc for the gate-vocabulary fix should fix the parent
   roster in the same pass.

5. **`chain_skipped[].reason` needs a bounded vocabulary if the model is
   to be enforceable.** Today it is free text at the pattern layer, and
   the two parents have incompatible local rules for it. A pattern-level
   sentence naming the legitimate reasons (re-entry protection against a
   settled artifact; a boundary Reject ending the chain; and — if
   `/charter` keeps it — author declination) is what would make "no child
   is ever skipped for not being worth producing" a checkable claim
   rather than a `/scope`-local convention.

## Surprises

- **The pattern document is the source of the very prompt the author
  wants gone**, and its table row does more than permit the triad: it
  fixes Proceed as "the expected path" and explicitly blesses `/charter`'s
  "Adjust chain" rendering with a "do NOT generalize" warning. A
  skill-local fix would leave the pattern contradicting the skill.

- **The pattern doc has zero awareness of #302.** No occurrence of
  "consolidat", "absorb", "fold", "worth", or "earn" in either
  `parent-skill-pattern.md` or `parent-skill-state-schema.md`. Every
  statement of the post-#302 model in the corpus lives inside
  `skills/scope/`. Meanwhile `/execute` knows about it
  (`SKILL.md:559-574`), so downstream skills have absorbed a model the
  shared contract never states.

- **`/scope` already retired an in-vocabulary produce-or-skip reading
  without amending the vocabulary.** `phase-1-discovery.md:156-160`
  retires R7's reading of the R6 predicates as a produce-or-skip gate and
  says "'shape-dependent' now means what it says in the Gate Vocabulary."
  So the shapes were never the problem; the ALWAYS declination clause is.

- **The 2026-08-08 EITHER-signal retirement is a ready-made template for
  this fix.** Lines 181-195 show exactly how this corpus retires a gate
  shape: name the shape, say what it claimed, walk each gate that carried
  the label, show the label had no examples left, date the retirement, and
  tell readers how to read old documents. If the declination clause goes,
  it should go the same way.

- **`references/pipeline-model.md:63`'s "Skip" transition** is a second,
  independent corpus surface saying steps are chooseable before the fact
  ("Simple work skips Diamonds 1-2. Medium skips Diamond 1"). It is
  entry-altitude routing rather than an in-parent gate, so it may be
  legitimate — but it is the same *shape* of statement and probably
  belongs on the exploration's surface inventory (likely the
  explore-routing lead's territory).

- **`/execute`'s Team Shape section claims complete parent-skill
  conformance** while the pattern doc it conforms to still enumerates only
  two parents. Neither document points at the other's gap.

## Open Questions

1. **Does `/charter` keep the roadmap declination?** This is the human
   decision. Keeping it means the corpus states "chain steps are mandatory
   *except* one author declination at the strategic altitude" — coherent,
   but not "one model." Dropping it means a ROADMAP is always written and
   the not-headed-for-execution case has to be handled post-hoc, which
   `/charter` cannot currently do (no consolidation machinery, no
   equivalent of `consolidation_judgments:`).

2. **If the declination clause is retired, what happens to `/scope`'s
   `/plan`?** The clause's closing sentence ("`/scope`'s `/plan` is ALWAYS
   with no declination surface") is what makes ALWAYS-without-declination
   the reference case. Retiring the clause makes that the only case, which
   is the desired end state — worth confirming nobody wants a `/plan`
   declination later.

3. **Should the chain-proposal prompt survive at all?** For `/scope` it is
   now a Proceed/Bail confirmation over a constant list plus two notices.
   Bail still routes to R8 (`SKILL.md:413-418`), so it cannot become a
   pure notice without relocating Bail. Someone has to decide whether the
   pattern keeps a two-option confirmation or drops the prompt and moves
   Bail elsewhere.

4. **What is the eval blast radius?** At minimum `skills/scope/evals/evals.json`
   scenarios asserting `"Proceed / Adjust / Bail?"` byte-for-byte
   (`:102`, `:383`) and `skills/charter/evals/evals.json` scenarios
   asserting the per-token form and the "Adjust chain" tolerance
   (`:246-247`, `:301`) plus the two roadmap-declination scenarios
   (`:188`, `:216-220`). Not audited beyond grep.

5. **Should the pattern doc's parent roster be fixed in the same PR?**
   `/execute` and `/work-on` are absent from the Dispatch Contract's
   "both v1 parents … all seven children" framing and from the closing
   parent/children table. Adjacent defect, same file, arguably the same
   pass — needs a scope call.

## Summary

The pattern's Gate Vocabulary is closed at three shapes (ALWAYS,
shape-dependent, Mandatory-with-auto-skip), but ALWAYS carries a
declination clause — "A parent MAY additionally offer the author an
explicit declination for an ALWAYS child (`/charter` does, for
`/roadmap`) … with the skip recorded in `chain_skipped`"
(`references/parent-skill-pattern.md:128-137`) — that is the corpus's
only sanction for dropping a step before its artifact exists, and nothing
in the pattern or the state schema forbids a worth-producing judgment
(`chain_skipped[].reason` is pattern-level free text, an open vocabulary
each parent closes differently and incompatibly). This is ONE
pattern-level fix, not three: the pattern document is itself the source
of the chain-proposal triad's contract (`:596` fixes the tokens, names
Proceed "the expected path," and blesses `/charter`'s "Adjust chain"
rendering, with both parents' eval suites grading against that rule), and
`/execute` — the third parent, whose children are per-issue `/work-on`
runs — has no chain proposal, omits the chain-tracking triad outright,
and offers the author nothing to drop, while `/inflight` is a PR-listing
relay that is not a parent skill at all. The biggest open question is
whether `/charter` keeps its roadmap declination, since it is a genuine
pre-authoring worth-producing judgment with no post-hoc consolidation
machinery to replace it.
