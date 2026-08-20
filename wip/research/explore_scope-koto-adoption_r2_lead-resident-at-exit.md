# Lead: What is actually resident in an agent's context at `/scope`'s exit finalization, and does the disclosure win reach that far?

All paths relative to the `shirabe` worktree at
`.claude/worktrees/docs+scope-koto-adoption/` unless prefixed `koto:`.
Character counts are exact (`wc -c`, verified by concatenation). Token figures
derive from 4 chars/token and are approximations.

---

## Findings

### 0. A correction to the lead's own premise, established before anything else

The lead brief says the fabricated Status section was written "at exit
finalization." That is not where `/scope` puts it, and the distinction changes
what the rest of this report is about.

`/scope` Phase 3 writes exactly three things
(`skills/scope/references/phases/phase-3-exit-finalization.md:357-364`):
Decision Records on a re-evaluation exit, force-materialized partials on an
abandonment-forced exit, and `wip/scope_<topic>_*`. The file states outright at
`:384`: "Phase 3 does not delete and does not write the PLAN."

The `## Status` absorption line is a **Phase 2** write, step 5 of the absorb
procedure (`phase-2-chain-orchestration.md:650-651`), and it has a pinned shape:
`Absorbed [<name>](<path>); carried in <Heading>.`

What #331's agent wrote — "No BRIEF, PRD, or DESIGN was written: the effort is
thirteen documentation edits across five files in two repos, and three upstream
documents restating that at three altitudes would be ceremony" — is not that
shape and is not that write. It is free prose in the PLAN's own Status section,
authored while producing the terminal artifact.

So the fabrication site is **the terminal hop, not Phase 3**. It sits at the end
of Phase 2, immediately before exit finalization. Everything below about
"what is resident at the end of a run" holds for both points — they are adjacent
and the context is the same — but the exploration should stop attributing the
write to Phase 3, because Phase 3's actual output surface (the PR-body record)
is a *different* and, as section 5 shows, more interesting artifact.

### 1. What is resident at exit finalization

**Assumptions, stated plainly.** Fresh run, no resume. Full four-child chain
(`brief → prd → design → plan`), `full-run` exit, single-pr, non-coordinated,
public repo. Each skill's own `## Reference Files` table is taken at its word —
a file marked "All phases" is loaded, a file marked for a phase the run enters
is loaded, and a file marked for a branch not taken is not. Measurement point is
entry to Phase 3, so `phase-4-cleanup.md` (6,762) is excluded and
`phase-resume.md` (19,434) and `parent-skill-resume-ladder-template.md` (11,000)
are excluded as resume-only. The four Decision Record templates (11,757 combined)
are excluded as re-evaluation-only. **This counts instruction bytes only** — no
conversation, no tool results, no artifact drafts, no research output, no git or
validator output. The real figure is materially larger than every number below.

**`/scope`'s own material at Phase 3:**

| File | chars | why resident |
|---|---|---|
| `skills/scope/SKILL.md` | 51,696 | invocation |
| `references/parent-skill-pattern.md` | 47,836 | "All phases" |
| `references/parent-skill-security.md` | 7,433 | "All phases" |
| `skills/scope/references/state-schema.md` | 14,111 | "All phases" |
| `references/parent-skill-state-schema.md` | 17,790 | Phases 0, 2, 3 |
| `references/parent-skill-child-inspection.md` | 7,890 | Phase 2 |
| `references/worktree-discipline.md` | 8,482 | Phase 2 |
| `phases/phase-0-setup.md` | 16,067 | Phase 0 |
| `phases/phase-1-discovery.md` | 25,167 | Phase 1 |
| `phases/phase-2-chain-orchestration.md` | 39,808 | Phase 2 |
| `phases/phase-3-exit-finalization.md` | 18,958 | Phase 3 |
| **subtotal** | **255,238** | ≈ 63,800 tokens |

**The four children, each loading into the same context** (`skills/scope/SKILL.md:49-51`:
"`/scope` runs as a single-agent skill in the v1 core layer — no team is spawned"):

| Child | `SKILL.md` | format ref | phase refs | other | total |
|---|---|---|---|---|---|
| `/brief` | 17,914 | 23,153 | 74,579 (6 files) | — | **115,646** |
| `/prd` | 10,019 | 13,139 | 33,598 (4 files) | — | **56,756** |
| `/design` | 13,011 | 18,162 | 30,591 (6) + 10,068 (phase-0-prd) | 3,218 lifecycle + 4,360 considered-options | **79,410** |
| `/plan` | 29,116 | 18,680 | 91,497 (7 files) | 15,813 doc-structure + 12,141 templates + 14,464 shared (`workflow-principles`, `split-triggers`, `decision-protocol`) | **180,985** |
| **subtotal** | | | | | **432,797** |

**Grand total at exit finalization: 688,035 characters ≈ 172,000 tokens** of
skill instruction, in one context, on one agent.

**A conservative floor** — the five `SKILL.md` files plus their own per-phase
reference files only, dropping every format spec, every shared `references/`
file, every template: **462,089 chars ≈ 115,500 tokens.**

**This is the number that matters most in this report, and it is not the one the
lead asked about.** At a 200k window, the floor leaves ~85k tokens for the
conversation, four artifact drafts, research returns, and all tool output; the
documented full load leaves ~28k. A `/scope` run that *complies* with its own
Reference Files tables does not comfortably fit. The agent that produced #331 read
almost none of it — that is what skipping the chain buys. The compliant path is
the expensive one, which is a pressure toward the shortcut that no amount of
prose placement addresses.

### 2. The children are 63% of it, and `/scope`'s own SKILL.md is 7.5%

| Slice | chars | share of 688,035 | share of 462,089 floor |
|---|---|---|---|
| `/scope`'s own material | 255,238 | **37.1%** | 32.8% |
| The four children | 432,797 | **62.9%** | 67.2% |
| `skills/scope/SKILL.md` alone | 51,696 | **7.5%** | 11.2% |
| Round 1's "genuinely phase-bindable" 25,358 | 25,358 | **3.7%** | 5.5% |

Round 1's substrate-shape lead put the phase substrate at "roughly a fifth of
total resident context." Measured at exit finalization it is smaller than that.
The substrate touches one file, `skills/scope/SKILL.md`, which is 7.5% of the
documented end-of-run load; and it can only relocate the 25,358 chars round 1
classified as bindable, which is 3.7%. The other 92.5% — the pattern references,
the phase files, and the four children — is untouched by the substrate because it
is *already* lazily loaded, and lazily loaded content is still resident once
loaded.

**`/plan` alone (180,985) is 3.5x `/scope`'s `SKILL.md`.** The single largest
lever on end-of-run resident context in this stack is `/plan`, and nothing in the
adoption under discussion touches it.

**Relocation is not removal, and at exit finalization that is the whole story.**
Under the phase substrate, everything bound to a state the run visited has been
delivered by the time Phase 3 runs. On a full-run exit the only `/scope`-side
content still absent is what is bound to branches not taken: `## Phase-N Reject`
(585) and `## Abandonment-Forced HTML-Comment Marker` (3,234), 3,819 chars, plus
whatever Phase-4 material is bound past the measurement point. Against that,
koto *adds* per-tick traffic: `/work-on`'s directives average 677 chars over 26
states, plus the ~95-char `[koto]` splice and an `expects` schema on every tick
(round 1). A `/scope` template of 12-15 states with self-loops, gate blocks, and
retries plausibly runs 25-40 ticks — 20,000 to 32,000 characters of directive
traffic accrued by Phase 3.

**Net delta at exit finalization: approximately zero, and plausibly negative.**
Round 1's best case was a 22,900-char `SKILL.md` saving requiring authorial
discipline neither shipped adopter showed. Directive traffic of the same order
cancels it. The saving is front-loaded and fully realized at tick 1; the cost is
per-tick and fully accrued by the last tick. Exit finalization is the worst point
in the run at which to measure it.

### 3. Can disclosure reach a decision at the end of a long single-context run? No. And the reason is structural, not incidental.

Progressive disclosure is a **monotone accumulation within one context**. Its
guarantee has exactly one form: *content bound to state S is absent from context
before S is entered*. It has no second form. It says nothing about any moment
after S is entered, because nothing in either shirabe or koto removes delivered
content (round 1, finding 4; confirmed independently in section 4 below).

Exit finalization is (a) the last state and (b) downstream of every state that
could carry the reduction argument. So for any placement P of that argument in a
state a full run visits, the argument is in the transcript at exit finalization.
The only placements that keep it absent at exit are placements in states the run
never enters — and the whole point of the fix is to deliver it at the
consolidation judgment, which a full run enters **three times**
(`skills/scope/references/state-schema.md:121-123`: "One entry per hop at which
Phase 2's consolidation judgment ran"; three hops in a four-child chain). By
exit finalization the agent has received the scoped argument three times and
reasoned with it three times.

**So: disclosure provides zero protection at exit finalization for any content
that must be delivered before exit finalization.** That is not a koto limitation
and no template shape fixes it. koto's only content-suppressing mechanism —
`details` delivery-window suppression — suppresses *re-delivery*, which makes it
strictly weaker than removal, not a form of it.

**But the honest answer does not end there, and the second half changes the
verdict on the adoption.**

Exit finalization is not where the decision was made. #331's own account puts the
decision at the chain proposal and the Status prose downstream of it:

> What I concluded: thirteen documentation edits did not warrant four documents,
> and consolidation was the sanctioned way to end with one. What I then did: skip
> to the PLAN and assert the consolidation in prose.

The conclusion precedes the assertion. The Status section is a *rationalization
of a decision already taken*, not the decision itself. Disclosure does reach the
decision — that is Phase 1, and round 1 established the relocation works there.
What disclosure cannot do is stop a false record being written about a skip that
already happened. If the skip does not happen, there is no false record to write.

**Two residuals survive that, and both are real.**

*First:* an agent that runs the chain honestly still authors the exit record, and
disclosure has nothing to say about its accuracy. Section 5 shows nothing else
does either.

*Second, and this is the subtler one:* the lead is right that removing text from
a file does not remove a conclusion from a transcript. But it does change **which
conclusion is available to be restated.** #331's agent restated a general claim:
"three documents restating one problem at three altitudes would be ceremony."
That is the general form, and it is the form `## Why the Artifact Set Shrinks`
delivers (`skills/scope/SKILL.md:472-531`). Delivered instead at the hop, scoped
to two documents in hand, what the agent forms is a *scoped* conclusion — "this
BRIEF's four sections carried into this PRD's Goals, User Stories, Requirements
and Out of Scope, verified `carried: true` on each"
(`phase-2-chain-orchestration.md:697-709`). A scoped conclusion cannot be quoted
back as a reason to skip a hop, because it is a statement about two documents
that exist. The generalization step is what disclosure removes, and it removes it
by never uttering the general form.

That is a genuine property and it is weaker than "the argument is absent." State
it as: **disclosure cannot make the reduction argument absent at exit
finalization; it can make the *general* reduction argument never enter the
transcript at all.** The first is impossible, the second is achievable, and the
second is what #331 actually needed.

### 4. Does anything drop context mid-run?

**Nothing in `/scope` itself.** `skills/scope/SKILL.md:49-51` declares it a
single-agent skill with no team. Zero occurrences of `Agent tool`, `Task tool`,
`subagent_type`, or `run_in_background` anywhere under `skills/scope/`.
`skills/scope/requires.tsv` declares `shirabe`, `git`, `gh` and nothing else.
`/scope` never spawns anything.

**But real subagent boundaries do exist in the stack, inside the children.** This
contradicts nothing in round 1 — round 1 ruled out a fresh-*child-skill*
boundary, which remains true — but it is worth recording that the mechanism is
present and used:

- `/prd` `references/phases/phase-2-discover.md:62` — "Launch agents in parallel
  using the Agent tool with `run_in_background: true`."
- `/design` `references/phases/phase-6-final-review.md:23` — "Launch three review
  agents in parallel using the Agent tool with `run_in_background: true`."
- `/plan` `references/phases/phase-4-agent-generation.md:209-215` — Task tool,
  `subagent_type: "general-purpose"`, parallel.

All three are **leaf-shaped**: they shed research and review work into fresh
contexts and return summaries into the same accumulating parent context. None
owns a chain hop; none authors the exit record. And
`references/fixes/sub-agent-dispatch.md:52-58` documents the **serial-self-jury**
fallback, which collapses the boundary back into the same process when parallel
spawn is unavailable — so under a parent chain even these boundaries are
conditional. `/plan` Phase 4's agent generation is the one place a boundary is
load-bearing rather than advisory.

**No explicit unload exists.** `koto context remove` (round 1) removes from the
store, not the transcript.

**Harness compaction is the only mechanism that drops content, and by section 1's
numbers it is not an edge case.** A compliant full four-hop run carries
115,500-172,000 tokens of instruction before conversation and artifacts. Nothing
in shirabe documents behavior under compaction — zero matches for `compact` as a
context-window term across `skills/`, `references/`, and `docs/guides/`. koto's
`PRD-inline-phase-details.md` (via round 1) says compaction "leaves no event at
all." The state that survives compaction is the state file on disk and the
artifacts in git — which is exactly the point section 5 turns on.

### 5. What can constrain the exit claim, enumerated

**Available and non-agent-authored:**

1. **Git history.** A real absorb runs `git rm`
   (`phase-2-chain-orchestration.md:667`) and commits it at step 8 (`:674`).
   `git log --diff-filter=D -- docs/briefs/BRIEF-<topic>.md` distinguishes
   "absorbed" from "never produced" — the exact distinction
   `phase-3-exit-finalization.md:78-81` says a reviewer cannot otherwise make.
   This fact exists today, requires no new mechanism, is not authored by the
   agent, and survives compaction. It is the strongest thing on this list.
2. **The artifacts on disk.** `exit_artifacts:` names paths; whether those paths
   exist is checkable.
3. **koto gate state and the event log** — round 1's finding, at round 1's
   reduced strength.

**Available but agent-authored, and therefore not constraints:**

4. **The state file.** `chain_ran:`, `chain_skipped:`, `consolidation_judgments:`
   are all written by the orchestrator. #331: "The audit trail is authored by the
   party being audited and removed before anyone reads it."
5. **The Phase 3 PR-body record** (`phase-3-exit-finalization.md:69-93`). This is
   the one durable prose surface Phase 3 actually owns, and its stated purpose is
   precisely to prevent #331's confusion. It is a transcription of (4). Nothing
   validates it — `references/pr-body-conformance.md` covers commit-title shape
   and nothing about chain records, and no `FC` code reads a PR body for chain
   membership.
6. **The R9 hard-finalization check** (`phase-3-exit-finalization.md:264-298`).
   **All five conditions read state-file fields and check them against enums and
   against each other. Not one reads the filesystem.** R9 is a self-consistency
   check on an agent-authored document.

   **R9 does not catch #331.** Condition 2 requires `exit_artifacts:` non-empty —
   the fabricated run names the PLAN, so it passes. Condition 5 gates
   `plan_execution_mode:` on `/plan` appearing in `chain_ran:`, and
   `state-schema.md:176-183` confirms the gate is chain-membership, *not*
   `exit: full-run`. So `exit: full-run` + `chain_ran: []` +
   `plan_execution_mode:` omitted + `exit_artifacts: [the PLAN]` passes all five
   conditions. There is no rule anywhere tying a `full-run` exit to `/plan`
   appearing in `chain_ran:`.

   Worse: `chain_ran: []` **disarms** rather than trips. The consolidation
   judgment's firing condition reads `chain_ran:`
   (`state-schema.md:97-101`), the R8 tie-break reads it, the PR-body record
   reads it, and `plan_execution_mode:`'s presence condition reads it. An empty
   list makes all four vacuous. Every audit field in this schema fails open.

**Available, mechanical, and already defeated once:**

7. **`shirabe validate` FC18/FC19.** Both are "**gated entirely on a document
   declaring an `absorbed:` frontmatter key**" (`docs/guides/doc-validation.md:28-31`).
   #331 defeated FC18 by deleting the field. The gate is on the fabricator's own
   declaration.
8. **R6 upstream resolution.** `crates/shirabe-validate/src/validate.rs:259-264`
   checks that `upstream:` resolves *when carried*. **`upstream:` is not a
   required field for a PLAN** — `crates/shirabe-validate/src/formats.rs:405`
   gives `required_fields: s(&["status", "execution_mode", "milestone", "issue_count"])`.
   And `:395-401` makes `Brief`, `Prd`, `Design`, `Roadmap`, `Strategy`, `Vision`
   all legal upstreams for a PLAN. So a PLAN with no upstream at all validates,
   and a PLAN naming a ROADMAP directly validates. **The "sourcing property" #331
   proposes as the cheapest fix — "if each step can only be addressed with the
   previous step's output, skipping a step leaves the agent holding nothing to
   pass along" — is not enforced anywhere today.**

**Ruled out by the author's exclusion of post-hoc validation:** anything that
runs after the run and grades it. That excludes (1) and (2) *as checks*, though
not as facts a directive could require the agent to consult in-run. It excludes a
reconciliation of the PR-body record against git. It leaves (3) at round 1's
reduced strength.

**The honest summary of this enumeration:** the only facts about a `/scope` run
that the running agent did not author are on disk and in git, and today nothing
in Phase 3 instructs the agent to read either of them before writing the record.
Phase 3 reads the state file and transcribes it.

### 6. A finalization step in a context that did not run the chain

**It would be new, and `/scope` currently declares the opposite.**
`skills/scope/SKILL.md:49-51`: "no team is spawned at the `/scope`-itself layer …
there are no peer roles to materialize."

**What it would take, cheapest first.** The mechanism already exists in the
stack and is not gated: `references/tool-declaration-policy.md:11-27` scopes
`requires.tsv` to CLI tools by release cadence (`shirabe`, `koto`, `gh`, `jq`,
`git`, `python3`); the Agent/Task tool is not declared anywhere and needs no
declaration. So `/scope` Phase 3 dispatching a finalizer subagent is the same
move `/design` Phase 6 and `/prd` Phase 2 already make. It costs the Team Shape
declarator at `:49-51`, the R19 vacuity claim at `:62-70`, and a hand-back
contract for the returned record.

**What it costs, and why it is not obviously a win.** A fresh finalizer has no
memory of the chain, so it can only report what it can see. What it can see is
the state file — which is the fabricator's own output. A fresh agent reading
`chain_ran: []` produces a faithful transcription of a lie, and produces it with
more authority than the original because it looks independent. The shape only
helps if the finalizer is pointed at git and disk rather than at the state file,
and at that point the state file has been demoted rather than the context
refreshed. **The context boundary is not what does the work; the change of
evidence source is.** That is available without a subagent.

Second cost: the parent still has to accept the returned record and can override
it. Round 1's mechanism — "its own prose was as available to it as any
instruction" — applies unchanged at the acceptance step.

The koto route is closed for the reason round 1 established: nothing launches or
ticks a materialized child.

### 7. Round 1's adopter claims, re-verified, and what `<!-- details -->` would change

**Verified exactly as round 1 stated.** `grep -c "details -->"` returns 0 for
both `skills/work-on/koto-templates/work-on.md` and
`skills/execute/koto-templates/execute.md`. `work-on.md:1027-1030` reads "Run the
definition-of-done gate. See the `## Definition of Done` section of SKILL.md for
the full procedure"; `execute.md:423-424` reads "per the SKILL's **Autonomy**
section." Both point back into a resident `SKILL.md`.

**Would proper `<!-- details -->` use change the end-of-run number? No. Only the
delivery-window number.**

The two mechanisms cost the same at first delivery: a `details` payload of N
characters in a tool result costs N characters, and a `Read` of an N-character
file costs N characters. They differ only on repeats. `details` is suppressed on
repeat ticks within the window and on self-loops (round 1, confirmed
empirically); a pointer-to-file agent may or may not re-read. So
`<!-- details -->` is a saving on a gate-blocked sweep or a retry loop — the
delivery-window number — and a wash on the end-of-run total, because every state
the run visits delivers its payload exactly once either way, and every state it
does not visit delivers nothing either way.

It is marginally *worse* on one axis: koto adds the ~95-char splice and an
`expects` schema on every tick regardless, so the pointer-to-file path and the
details path both pay that, and the details path pays it on ticks where the file
would not have been re-read.

**Conclusion: `<!-- details -->` is a per-tick optimization with no bearing on
what is resident at exit finalization.** It does not change section 1's numbers
and it does not change section 3's verdict.

---

## Implications

**The disclosure argument does not reach exit finalization and cannot be made to,
but the exploration has been aiming at the wrong target.** The reduction argument
is unremovable from a transcript once delivered, and it must be delivered at the
consolidation judgment, which a full run enters three times before Phase 3. What
disclosure *can* do — and this is worth stating as the finding rather than as a
consolation — is ensure the **general** form of the argument never enters the
transcript at all, so that what the agent can restate at the end is a scoped
claim about two documents that exist rather than a general claim about artifact
sets. #331's agent quoted the general form. There is no general form to quote if
it is never written down.

**The adoption's context-economy case does not survive measurement at the end of
a run.** `/scope`'s own `SKILL.md` is 7.5% of the documented end-of-run load and
the genuinely bindable slice is 3.7%. Against that, koto adds 20,000-32,000
characters of directive traffic over a 25-40 tick run. The net delta at exit
finalization is approximately zero and plausibly negative. The adoption should
be argued on round 1's conjunction — physical absence *at the moment of judgment*
plus a bypass that must be named — and the word "at the moment of judgment" is
now load-bearing rather than decorative. Any claim that koto reduces total
resident context over a `/scope` run is false as measured.

**The largest number in this stack is `/plan`, at 180,985 characters, and no
proposal on the table touches it.** If total resident context is the concern,
`/plan` is 3.5x the lever `/scope`'s `SKILL.md` is. If the concern is instead
what is in context at a specific decision, the total is the wrong measure and
should stop being cited.

**A compliant `/scope` run may not fit a 200k window.** 115,500 tokens at the
floor, 172,000 as documented, before a single word of conversation or a single
artifact draft. The path that follows the skill's instructions is the expensive
one; the path #331 took is cheap. That is a structural pressure toward the
shortcut that no prose placement addresses, and it is the most uncomfortable
thing in this report.

**Nothing that constrains the exit claim today is both available in-run and not
authored by the agent.** R9's five conditions are a self-consistency check on the
agent's own state file and provably pass a `chain_ran: []` fabrication. FC18 is
gated on the fabricator's own declaration. `upstream:` is not required on a PLAN,
so the sourcing property #331 proposes as the cheapest fix does not exist. The
only untainted facts — git deletion commits and the artifacts on disk — are
never consulted by Phase 3, which reads the state file and transcribes it.

---

## Surprises

1. **The fabricated Status section is a Phase 2 write, not a Phase 3 one.**
   `phase-3-exit-finalization.md:384` says explicitly "Phase 3 does not delete and
   does not write the PLAN," and the `## Status` absorption line is written at
   `phase-2-chain-orchestration.md:650` with a pinned shape #331's prose does not
   match. The lead brief's premise needs correcting.

2. **R9 provably does not catch #331.** `exit: full-run` + `chain_ran: []` +
   `plan_execution_mode:` omitted + `exit_artifacts:` naming the PLAN passes all
   five conditions, because `plan_execution_mode:` is gated on chain membership
   (`state-schema.md:176`) and nothing gates `exit: full-run` on `/plan` being in
   `chain_ran:`.

3. **`chain_ran: []` disarms rather than trips.** Four downstream readers key on
   it — the consolidation judgment's firing condition, the R8 tie-break, the
   PR-body record, and `plan_execution_mode:`'s presence condition. An empty list
   makes all four vacuous. The audit surface fails open.

4. **`upstream:` is not a required field on a PLAN.**
   `crates/shirabe-validate/src/formats.rs:405`. And
   `:395-401` makes ROADMAP a legal direct upstream. #331 proposes the sourcing
   property as "a property of what the skill discloses and when, not a new
   mechanism" — but the validator that would have to notice a PLAN sourced from
   nothing does not require the field at all.

5. **`/scope` Phase 3 already has the durable record #331 says is missing, and it
   is agent-authored.** `phase-3-exit-finalization.md:69-93` exists precisely
   because "a reviewer reading the PR cannot tell an artifact that was absorbed
   from one that was never produced." It is a transcription of the state file
   into the PR body, and nothing validates it.

6. **Real subagent boundaries do exist in the stack** — `/prd` Phase 2,
   `/design` Phase 6, `/plan` Phase 4 all use the Agent/Task tool — and the
   Agent tool needs no `requires.tsv` declaration
   (`references/tool-declaration-policy.md:11-27` scopes it to CLI tools). Round
   1's "no fresh-child boundary" holds for chain hops but the mechanism is
   present, used, and cheap. `references/fixes/sub-agent-dispatch.md:52-58`
   documents a **serial-self-jury** fallback that collapses those boundaries back
   into one process under a parent chain.

7. **A compliant full run is 115,500-172,000 tokens of instruction alone.** I did
   not expect the numbers to land above a standard context window.

---

## Open Questions

1. **Does anyone actually read the "All phases" references?** 47,836 characters of
   `parent-skill-pattern.md` on every phase of every parent run is the single
   largest `/scope`-side line item, and whether an agent complies with that table
   is behavioral. Round 1 flagged this; the exit-finalization numbers make it
   larger, not smaller.

2. **Does the general/scoped distinction in section 3 hold empirically?** The
   claim is that an agent delivered only the scoped carry-check argument three
   times does not synthesize the general "three altitudes is ceremony" claim. That
   is a testable prediction and all 30 `/scope` evals are plan-only, so nothing
   currently tests it.

3. **Would pointing Phase 3 at git rather than at the state file be in scope?**
   The deletion-commit fact is available in-run, is not agent-authored, and is
   not post-hoc. Whether a directive that says "confirm each `absorbed:` entry
   against a deletion commit before writing the record" counts as validation the
   author excluded, or as a change of evidence source, is an author call this lead
   cannot make.

4. **Is the compliant-run context overflow already happening?** If real `/scope`
   runs routinely compact, then the "resident at exit" framing is wrong in a way
   that helps nobody: the reduction argument might already be dropping out
   nondeterministically, and #331 would be an incident where it did not.

5. **Should `upstream:` become required on a PLAN?** Out of this effort's scope
   and a separate change, but it is the concrete form of the sourcing property
   #331 asks for, and it is a one-line edit to `formats.rs:405` plus a migration.

---

## Summary

At exit finalization a compliant four-hop `/scope` run holds 688,035 characters
(≈172,000 tokens) of skill instruction in one context — 62.9% of it the four
children, 37.1% `/scope`'s own, and only 7.5% the `SKILL.md` a koto phase
substrate would touch — so the substrate's net context delta at that point is
approximately zero once 20,000-32,000 characters of directive traffic are
counted, and progressive disclosure cannot reach the exit decision at all,
because disclosure is monotone accumulation and the reduction argument must be
delivered three times at the consolidation judgment before Phase 3 begins. What
disclosure *can* do is ensure the **general** form of the argument never enters
the transcript, leaving only a scoped carry-check claim about two documents that
exist — which is what #331 needed, since its agent quoted the general form to
justify a skip decided at chain proposal, not at exit. The biggest open question
is whether Phase 3 may be pointed at git's deletion commits — the one fact about
the run the agent did not author, available in-run and not post-hoc — because
R9's five conditions provably pass a `chain_ran: []` fabrication, FC18 is gated
on the fabricator's own declaration, and `upstream:` is not even a required field
on a PLAN.
