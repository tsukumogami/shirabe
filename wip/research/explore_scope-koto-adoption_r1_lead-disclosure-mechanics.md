# Lead: What does koto mechanically put into an agent's context at each state, and would a koto-driven `/scope` still load a whole `SKILL.md`?

All paths in this document are relative to a repo root unless absolute. koto source
paths are relative to `public/koto/`; skill paths are relative to the `shirabe`
worktree at `.claude/worktrees/docs+scope-koto-adoption/`.

Token estimates throughout use 4 characters per token. Character counts are exact
(`wc -c`); token figures are derived and are stated as approximations.

---

## Findings

### 1. What is actually in a `koto next` response

The response type is `NextResponse`, an enum with seven variants, defined at
`src/cli/next_types.rs:63-124`. Every non-terminal, non-error variant carries the
same four instruction-bearing fields:

```
state: String
directive: String
details: Option<String>
expects: ExpectsSchema        // event_type, fields, options
```

plus `advanced: bool`, `blocking_conditions: Vec<BlockingCondition>`, and
`unassigned_children: Vec<UnassignedChild>`. `Terminal` carries only `state`,
`advanced`, `unassigned_children` (`src/cli/next_types.rs:98-102`) — no directive
at all.

Serialization is hand-written (`impl Serialize for NextResponse`,
`src/cli/next_types.rs:504-...`), one arm per variant. `directive` is always
emitted; `details` is emitted only when `Some` (`src/cli/next_types.rs:521-523`).

**Where `directive` and `details` come from.** They are not structured data. They
are raw markdown lifted out of the template file's body. `extract_directives`
(`src/template/compile.rs:637-670`) walks the markdown body after the YAML
front-matter, treats every `## <state-name>` H2 that matches a declared state as a
section boundary, and assigns the intervening lines to that state.
`split_directive_details` (`src/template/compile.rs:674-687`) then splits that
block at the first line equal to `<!-- details -->` (`DETAILS_MARKER`,
`src/template/compile.rs:623`): everything before becomes `directive`, everything
after becomes `details`. With no marker, the whole block is the directive and
`details` is empty.

**How big can a directive be?** There is no cap. I grepped `src/template/` and
`src/cli/next.rs` for length validation, max constants, and truncation
(`MAX_`, `const .*: usize`, `truncat`, `len() >`) and found nothing that bounds
either field. The only compile-time check is that a directive is non-empty
(`src/template/compile.rs:188-191`). A directive is whatever the template author
wrote between two H2 headings — arbitrary length markdown, including fenced shell
blocks (see `spawn_and_await` below, 104 lines).

koto's own PRD records a measured size: "a phase carrying a 7,140-character
procedure" (`docs/prds/PRD-inline-phase-details.md`, Problem Statement, final
paragraph) — roughly 1,800 tokens in one `details` payload.

**What the agent receives verbatim.** I ran a probe template through the installed
binary. Tick 1 on a state with a `<!-- details -->` marker returned:

```json
{"action":"evidence_required","advanced":false,"blocking_conditions":[],
 "details":"LONG PROCEDURE LINE A. ...",
 "directive":"[koto] Lost context? `koto status <name>` returns this phase's directive/details/expects.\n\nSHORT DIRECTIVE: decide and submit verdict.",
 "error":null,
 "expects":{"event_type":"evidence_submitted","fields":{"verdict":{"required":true,"type":"enum","values":["ok","retry"]}},
            "options":[{"target":"s2","when":{"verdict":"ok"}},{"target":"s1","when":{"verdict":"retry"}}]},
 "state":"s1","unassigned_children":[]}
```

Two things to note. First, koto splices a ~95-character recovery pointer into the
front of **every** directive — this is the "koto-authored pointer" of
`DESIGN-inline-phase-details.md`'s decision block. It is a small per-tick tax paid
on every state. Second, `expects` is not free: it enumerates every field, every
enum value, and every transition target with its `when` clause. On a state with
several branches this is a few hundred characters per tick.

**Variable substitution.** `{{VAR}}` placeholders in a directive are substituted
before emission (`NextResponse::with_substituted_directive`, referenced at
`src/cli/next_types.rs:390`). Substitution can only make a directive longer.

### 2. Does a directive substitute for a file read, or supplement it?

**koto's design intent is substitute. shirabe's shipped adopters do supplement.**

koto's intent is unambiguous. `PRD-inline-phase-details.md` describes the
alternative to the `details` mechanism as "to read the template file by hand,
which is the file read the mechanism exists to remove." The `<!-- details -->`
marker exists precisely so a long procedure rides in the tool result instead of
costing a `Read`.

But:

```
$ grep -c "details -->" skills/work-on/koto-templates/work-on.md
0
$ grep -c "details -->" skills/execute/koto-templates/execute.md
0
```

**Neither shipped shirabe template uses the `<!-- details -->` marker at all.**
Every state in both templates emits one undifferentiated `directive` and no
`details`. koto's actual progressive-disclosure feature is unused by its only
adopters. (The installed `koto-user` skill,
`/home/dgazineu/.claude/plugins/cache/koto/koto-skills/0.11.5-dev/skills/koto-user/SKILL.md`,
does not document the marker either — its only mention of `details` is the
per-field error array at line 486. So the feature is largely invisible to skill
authors.)

What the templates do instead is split into two directive styles.

**Pointer directives** — the directive names a reference file and adds routing.
`skills/work-on/koto-templates/work-on.md`:

| State | Template line | Directive shape | File it points at | File size |
|---|---|---|---|---|
| `context_injection` | 804 | 5 lines: one pointer + evidence options | `references/phases/phase-0-context-injection.md` | 37 lines |
| `setup_issue_backed` | 878 | 5 lines | `references/phases/phase-1-setup.md` | 73 lines |
| `introspection` | 953 | 5 lines | `references/phases/phase-2-introspection.md` | 24 lines |
| `analysis` | 960 | 20 lines | `references/phases/phase-3-analysis.md` | 112 lines (+219-line agent-instructions file) |
| `implementation` | 982 | 17 lines | `references/phases/phase-4-implementation.md` | 175 lines |
| `scrutiny` | 1001 | 7 lines | `references/phases/phase-4a-scrutiny.md` | 79 lines |
| `finalization` | 1072 | 17 lines | `references/phases/phase-5-finalization.md` | 111 lines |
| `pr_creation` | 1107 | 13 lines | `references/phases/phase-6-pr.md` | 63 lines |

For these, the directive **supplements**. The substantive instruction lives in the
file; the directive contributes koto-specific glue (which evidence field to submit,
which enum values route where, gate-name-vs-context-key disambiguation). Context
cost per state is *directive plus file*, not directive instead of file.

**Self-contained directives** — the directive inlines its whole instruction:
`entry` (784), `task_validation` (812), `research` (839),
`post_research_validation` (857), `plan_context_injection` (892),
`plan_validation` (909), `staleness_check` (933), `verification` (1025),
`deferral_approval` (1090). These are 10-45 lines each and reference no file.
`execute`'s `spawn_and_await` (`skills/execute/koto-templates/execute.md:420-523`)
is the extreme case: 104 lines, including a ~40-line fenced bash block with
inline commentary.

**Quantification.** `skills/work-on/koto-templates/work-on.md` is 1,156 lines /
43,376 chars. Front-matter (the YAML state machine) runs lines 1-782; the
directive body is lines 784-1156 = **17,616 chars across 26 states**, averaging
~677 chars (~170 tokens) per directive. The phase files it points at total
**1,210 lines** across 13 files. So roughly 18KB of instruction lives in
directives and roughly 40KB still lives in files the directives tell the agent to
read.

**A directive that points back into `SKILL.md`.** The `verification` state's
directive (`skills/work-on/koto-templates/work-on.md:1027-1029`) reads:

> Run the definition-of-done gate. See the `## Definition of Done` section of SKILL.md
> for the full procedure: read the project's verification map, classify the issue's
> changed files against it, run each matched command...

And `spawn_and_await` (`skills/execute/koto-templates/execute.md:423-424`):

> **Autonomy at every tick.** When the run is authorized autonomous (the `--auto` flag
> or a clear author instruction, per the SKILL's **Autonomy** section)...

Both shipped adopters have directives that cite `SKILL.md` sections as their
authority. This is the single most important observation in this report and it
recurs under sub-question 6.

### 3. The bootstrap surface — does `SKILL.md` still load whole?

**Yes. Unambiguously, in both shipped adopters.**

| Skill | koto adopter | `SKILL.md` lines | `SKILL.md` chars | template chars |
|---|---|---|---|---|
| `/work-on` | yes | 287 | 17,706 | 43,376 |
| `/execute` | yes | 773 | 48,371 | 40,224 |
| `/scope` | no | 968 | 51,696 | — |

`/execute` is a koto adopter whose `SKILL.md` is 48,371 chars — within 7% of
`/scope`'s 51,696. Adopting koto did not shrink it.

**What is in `/work-on`'s 287 lines.** Reading `skills/work-on/SKILL.md`:

- Lines 1-12: front-matter, preflight hook, extension-file imports.
- Lines 13-40 (**Input Resolution**, `needs-triage`, blocking labels): pre-koto
  instruction. Must be resident — it runs before `koto init`.
- Lines 43-108 (**Definition of Done**, **Finalization and No Silent Deferral**):
  66 lines of semantic doctrine about what "done" means, what fails closed, and
  why unapproved caveats are disallowed. This is *not* bootstrap. It is exactly
  the class of content the `verification` state needs — and the `verification`
  directive points back at it (see above). It stays resident from invocation.
- Lines 110-172 (**Plan Input**, **Mode Detection**, **Plan-Backed Child Mode**):
  argument dispatch. Partly bootstrap, partly doctrine.
- Lines 178-249 (**Koto Orchestration**): the init commands, the execution loop,
  branch-setup conditions, resume ladder, decision capture. ~72 lines that exist
  *because of* koto — pure additive cost.
- Lines 251-287 (**Output**, **Begin**): bootstrap.

Split by character count: lines 13-177 = **12,080 chars (68%)** is workflow
instruction that did not move into the template; lines 178-287 = **4,736 chars
(27%)** is koto orchestration boilerplate that koto adoption *added*.

**Did koto adoption shrink `/work-on`'s `SKILL.md`? Barely, and only once.**
From git history in this worktree:

| Commit | Subject | `SKILL.md` |
|---|---|---|
| `5f14a84` | extract workflow skills (pre-koto) | 127 lines / **7,299 chars** |
| `711d385` | integrate koto orchestration (#20) | 134 lines / **6,280 chars** |
| `8e07f07` | HEAD | 287 lines / **17,706 chars** |

koto adoption cut 1,019 chars (~14%, ~250 tokens) and *added* 7 lines. Since then
the file has grown 2.8x. Nothing about koto resists that growth.

**Critically: `/work-on` already had per-phase reference files before koto.**
`git show 5f14a84 --name-only` lists `references/phases/phase-0-context-injection.md`
through `phase-6-pr.md` in the pre-koto commit. The adoption commit message states
the win precisely: "Koto directives point to phase reference files rather than
summarizing them, so agents read guidance once per phase instead of twice." The
win was **deduplication** — `SKILL.md` stopped restating what the phase files said
— not the introduction of lazy loading. Lazy loading already existed.

`/scope` is in exactly the same position: it already has six per-phase reference
files (`skills/scope/references/phases/`) loaded per phase. koto has no new
mechanism to offer it there.

**What `/execute` did with its `SKILL.md`.** Section sizes:

```
## Single-PR Execution Path                        7649 chars
## Coordinated Execution Path                      5961 chars
## Finalization-Not-Done Guard (R5)                5437 chars
## State                                           5104 chars
## Security Considerations                         3948 chars
## Exit Paths                                      3349 chars
...
```

`## Single-PR Execution Path` (lines 148-277) narrates the koto template's states
in prose — `orchestrator_setup`, `spawn_and_await`, `pr_finalization`,
`paused_for_review`, `plan_completion` — each with its mechanics, gates, and
routing. That content is *also* in the template's directives. `/execute` pays for
its state machine twice: once in `SKILL.md` at invocation, once in directives at
each tick.

### 4. Does anything ever leave the agent's context?

**No. koto has no mechanism that removes content from an agent's context window.**
Its disclosure is strictly additive; the mechanisms below reduce *re-adding*, not
what is already there.

**Delivery-window suppression of `details`.** This is real and it works. The
suppression combinator is
`NextResponse::with_details_suppressed_unless_full(already_delivered, full)`
(`src/cli/next_types.rs:392`), and the predicate is
`instructions_delivered_this_window(events, current_state)`
(`src/engine/persistence.rs:1192-1199`), which asks whether an
`InstructionsDelivered` event naming this state exists since the most recent entry
into it. `koto next --full` (`src/cli/mod.rs:145-147`, "Always include the details
field in the response, regardless of visit count") forces re-delivery.

Empirically confirmed against the installed binary on a probe template:

| Call | `details` present? |
|---|---|
| Tick 1, fresh entry into `s1` | yes |
| Tick 2, same state, no advance | **no** |
| Tick 3, `--full` | yes |
| Tick 4, self-loop `s1 → s1` via `verdict: retry` (`advanced: true`) | **no** |

The self-loop result matches `docs/designs/current/DESIGN-self-loop-suppresses-details.md`
("A self-transition appends one too and was originally included in that list; the
boundary now looks past it").

This prevents a 7,140-character procedure being re-emitted on all fourteen ticks of
a gate-blocked sweep. That is a genuine saving. But it operates on the *second and
subsequent* deliveries. The first delivery is in the transcript and stays there.

**`koto context`** (`src/cli/mod.rs:505-548`: `add`, `get`, `exists`, `remove`,
`list`) is a filesystem-backed key-value store. It lets an artifact live on disk
instead of in the transcript, and gates can assert its existence without reading it
(`context-exists`). `koto context remove` deletes from the *store*; it has no
effect on anything the agent already read. `koto context get` puts content back
into context.

**The one thing that does remove content is harness compaction, which koto
explicitly cannot see.** `PRD-inline-phase-details.md`: "Context compaction is
worse, because it leaves no event at all, and the payload in question is a tool
result — content the platform documents as compaction-eligible and not guaranteed
to survive a turn." koto's answer is the recovery path — `koto status` now returns
the phase's directive, details, and expects without moving the workflow, and every
directive carries the spliced `[koto] Lost context?` pointer to it. That is a
mechanism for *restoring* content koto has lost track of, not for shedding it.

**Verdict on the prior finding.** `SKILL.md` "loads whole at invocation and never
unloads" — koto changes the "at invocation" half for whatever content an author
moves into directives, and changes nothing about "never unloads."

### 5. The realistic delta for `/scope`

**Assumptions.** Fresh run (not a resume). Measurement point is the end of Phase 1,
when the chain proposal is put to the author and the agent is deciding whether and
how to run the chain. "In context" means the skill instruction the agent has read,
excluding conversation and tool output. 4 chars/token.

**Today.** From `skills/scope/SKILL.md`'s own `## Reference Files` table (lines
403-420), which marks three references "All phases":

| File | chars | loaded by Phase 1? |
|---|---|---|
| `skills/scope/SKILL.md` | 51,696 | yes, at invocation |
| `references/parent-skill-pattern.md` | 47,836 | "All phases" |
| `references/parent-skill-security.md` | 7,433 | "All phases" |
| `skills/scope/references/state-schema.md` | 14,111 | "All phases" |
| `references/parent-skill-state-schema.md` | 17,790 | Phase 0 (slug regex) |
| `skills/scope/references/phases/phase-0-setup.md` | 16,067 | yes |
| `skills/scope/references/phases/phase-1-discovery.md` | 25,167 | yes |
| **Total** | **180,100** | **≈ 45,000 tokens** |

A conservative floor that counts only `SKILL.md` + the two phase files is
92,930 chars ≈ 23,200 tokens.

**Under koto.** koto changes exactly one line of that table: `SKILL.md`. The phase
files and the pattern-level references are read by directives under koto too —
they are unchanged. So the delta is bounded above by the `SKILL.md` reduction.

Classifying `/scope`'s sections (sizes measured per `## ` block):

*Must stay resident — needed before the first `koto next`:*

| Section | chars |
|---|---|
| front-matter + preamble (lines 1-48) | 2,467 |
| `## Input Modes` | 1,362 |
| `## Execution-Mode Flags` | 953 |
| `## Upstream Flag` | 2,677 |
| `## Coordination Intent` | 5,182 |
| `## Topic-Slug Constraint` | 1,095 |
| `## Resume Logic` | 2,004 |
| `## State File Schema` | 913 |
| `## Visibility Detection` | 877 |
| `## Team Shape` | 1,343 |
| new koto orchestration section (by `/work-on`'s precedent) | ~2,500 |
| **subtotal** | **~21,373** |

*Stays by shipped precedent — `/execute`'s koto-era `SKILL.md` keeps both:*
`## Security Considerations` 5,893 + `## Binding Notes` 1,572 = **7,465**.

*Genuinely phase-bindable:* `## Workflow Phases` 2,660 + `## Phase Execution` 1,967
+ `## Reference Files` 2,168 (all three collapse into the loop) + `## Chain-Proposal
Output` 2,523 + `## Why the Artifact Set Shrinks` 3,112 + `## Consolidation
Judgment` 2,296 + `## Three Exit Paths` 2,527 + `## Manual-Fallback
Non-Interference` 1,667 + `## Validator Pass-Through` 2,619 + `## Phase-N Reject`
585 + `## Abandonment-Forced HTML-Comment Marker` 3,234 = **25,358 chars**.

**Best case** (aggressive author moves everything bindable): `SKILL.md` →
~28,800 chars. Saving **~22,900 chars ≈ 5,700 tokens**.

- Against the 180,100-char realistic total: **~13% reduction**.
- Against the 92,930-char floor: **~25% reduction**.

**Shipped-precedent case**: `/execute` adopted koto and its `SKILL.md` is 48,371
chars. A `/scope` that adopts koto the way `/execute` did saves **close to zero**.

**Range: 0 to ~5,700 tokens**, with the top of the range requiring authorial
discipline that neither shipped adopter demonstrated.

**One caveat that cuts the other way.** Directives are not free. `/work-on`'s
directive body is 17,616 chars across 26 states; a `/scope` run that visits, say,
twelve states pays several thousand characters of directive, plus the ~95-char
`[koto]` pointer and the `expects` schema on every tick, plus retries. Over a long
run with self-loops and gate-blocked ticks, the accumulated directive traffic can
approach or exceed the `SKILL.md` saving. The saving is front-loaded; the cost is
per-tick.

### 6. Where `## Why the Artifact Set Shrinks` ends up

**If the author does nothing else: it stays in `SKILL.md`, resident from
invocation, exactly as today.** koto has no mechanism that relocates prose — a
section only moves into a directive if a human moves it.

If the author *does* move it, it is genuinely Phase-2-bindable. The section's own
argument establishes this: "the reduction runs in Phase 2, after each artifact
lands, never at Phase 1 against artifacts nobody has written"
(`skills/scope/SKILL.md:481-484`). Bound to a `consolidation_judgment` state, it
would not be in context during the chain proposal. That is a real, non-trivial win
against #331's specific diagnosis.

**But three mechanical facts limit it.**

First, the shipped precedent runs the other way. `/work-on`'s `## Definition of
Done` (lines 43-108) is structurally the same kind of section — semantic doctrine
governing one state's judgment — and after koto adoption it sits in `SKILL.md`,
with the `verification` directive citing it: "See the `## Definition of Done`
section of SKILL.md for the full procedure"
(`skills/work-on/koto-templates/work-on.md:1027-1028`). `/execute` does the same
with `## Autonomy`. Both adopters, given the choice, left the doctrine resident and
pointed the directive back at it.

Second, once Phase 2 delivers it, it is resident for the remainder of the run.
There is no unload (finding 4). #331's failure was a Status section asserting
consolidation that had not happened — Status-section authoring is Phase 2/3 work,
by which point a Phase-2-bound argument is in context anyway. koto moves *when* the
argument arrives; it does not remove it before the moment the fabrication happened.

Third, `/scope` runs its chain by dispatching child skills as separate agents. The
argument's presence in the *parent's* context is what #331 turned on, and the
parent occupies Phase 2 for the whole chain — the longest-lived phase of the run.

This confirms the prior finding verbatim: koto governs when a directive arrives,
never what it says.

---

## Implications

The progressive-disclosure case for adopting koto in `/scope` is weaker than the
framing assumes, for a reason that is structural rather than incidental: **`/scope`
already does progressive disclosure.** Six phase reference files, loaded per phase,
totalling 2,708 lines that are *not* resident at invocation. The pre-koto
`/work-on` had the same shape, and koto adoption bought it 1,019 characters.

The reduction koto could deliver for `/scope` is real but bounded by one number:
how much of `SKILL.md`'s 51,696 characters an author is willing to relocate into
state directives. koto neither performs that relocation nor resists its reversal.
The only shipped evidence of what happens in practice is `/execute`, whose
koto-era `SKILL.md` is 48,371 characters and narrates its own state machine in
prose alongside the template that already encodes it.

Against #331 specifically, koto offers a narrow, genuine win: `## Why the Artifact
Set Shrinks` and `## Consolidation Judgment` (5,408 chars combined) are correctly
Phase-2 content and could arrive at the consolidation state rather than at
invocation. That removes them from the chain-proposal decision. It does not remove
them from the exit-finalization decision, which is where the fabricated Status
section was written.

If the exploration's goal is "the reduction argument must not be in context when
the agent decides what to produce," koto is one way to get there but not the only
one and not obviously the cheapest — moving those two sections into
`phase-2-chain-orchestration.md` achieves the same relocation with no new
dependency. What koto adds beyond relocation is *gating*: a state machine that
will not let the agent reach exit finalization without evidence from each hop. That
is a different argument from disclosure and it should be made on its own terms.

The `<!-- details -->` mechanism deserves separate attention. It is koto's actual
progressive-disclosure feature, it is measured and it works (confirmed empirically
above), and **no shirabe template uses it.** If `/scope` adopts koto, using
`<!-- details -->` for the long procedural bodies — rather than the pointer-to-file
pattern both existing adopters use — would be the first genuine deferral of a file
read the mechanism was built for. That is an authoring choice available today, not
something adoption confers.

---

## Surprises

1. **Neither shipped shirabe koto template uses `<!-- details -->`.** Zero
   occurrences in `work-on.md` and `execute.md`. The adopters use the
   pointer-to-file pattern instead, so per-state cost is directive *plus* file
   read. koto's disclosure feature is unused by its only consumers, and the
   installed `koto-user` skill does not document it.

2. **`/execute` is a koto adopter with a 48,371-character `SKILL.md`** — 94% the
   size of `/scope`'s. A large chunk of it (`## Single-PR Execution Path`,
   7,649 chars) narrates the koto template's own states in prose, so the state
   machine is paid for twice.

3. **Directives in both templates cite `SKILL.md` sections as their authority.**
   `work-on.md:1027` ("See the `## Definition of Done` section of SKILL.md") and
   `execute.md:423` ("per the SKILL's **Autonomy** section"). The shipped adopters
   independently converged on leaving semantic doctrine resident and pointing
   directives back into it — the exact pattern that would leave `## Why the
   Artifact Set Shrinks` in context at state 1.

4. **koto adoption barely shrank `/work-on`'s `SKILL.md` (7,299 → 6,280 chars) and
   it has since grown to 17,706.** The adoption commit's own stated win was
   deduplication, not lazy loading — `/work-on` already had per-phase files.

5. **koto splices ~95 characters into every directive** (`[koto] Lost context?
   \`koto status <name>\`...`). Confirmed empirically. Small, but it is a per-tick
   tax across every state of every run.

6. **A self-loop does not re-deliver `details`.** Confirmed empirically:
   `verdict: retry` returning to `s1` with `advanced: true` still suppressed. This
   is deliberate (`DESIGN-self-loop-suppresses-details.md`) but means an agent
   re-running a phase after a correction has the procedure only in older transcript
   — and must know to call `koto status` to get it back.

---

## Open Questions

1. **Would the author actually move `## Why the Artifact Set Shrinks` into a
   Phase-2 directive?** Everything in the delta estimate hinges on this and both
   shipped adopters chose otherwise. This is a human-input question, not a
   mechanical one.

2. **Directive traffic over a full `/scope` run is unmeasured.** I have per-state
   directive sizes for `/work-on` (677 chars mean) but no trace of how many ticks a
   real `/scope` chain run takes, including gate-blocks, self-loops, and retries.
   Without that, I cannot say whether accumulated directive traffic offsets the
   `SKILL.md` saving. A recorded run would settle it.

3. **Do the "All phases" references genuinely load at Phase 0?** `/scope`'s
   `## Reference Files` table says `parent-skill-pattern.md` (47,836 chars) loads
   for all phases, which dominates the token budget. If in practice agents read it
   lazily, the denominator drops and koto's percentage delta rises. Whether agents
   comply with that table is behavioural, not mechanical.

4. **Would the `<!-- details -->` mechanism actually help `/scope`?** Its phase
   files are 6,762-39,808 chars. A 39,808-char `details` payload for
   `phase-2-chain-orchestration.md` would ride in every first-entry tool result.
   That is not obviously better than a `Read`, and it defeats the delivery-window
   saving on the one phase most likely to be re-entered. There may be a size above
   which pointer-to-file is correct; koto's docs do not state one.

5. **Does #331's failure survive gating?** My scope was disclosure. Whether a koto
   state machine that requires per-hop consolidation evidence would have prevented
   the fabricated Status section is a gating question — mechanically separate from
   everything above and worth answering on its own.

---

## Summary

koto's `koto next` returns a state's `directive` (uncapped raw markdown from the
template body) plus an optional `details` block that is delivered once per phase
entry and suppressed on repeat ticks — a real mechanism I confirmed empirically,
but one that neither shipped shirabe template uses, and one that never removes
anything already in context; koto changes the "at invocation" half of "loads whole
at invocation and never unloads" and nothing about the "never unloads" half.
`SKILL.md` still loads whole in both adopters — `/execute`'s is 48,371 chars
against `/scope`'s 51,696 — and both have directives that cite `SKILL.md` sections
as their authority, so a koto-driven `/scope` that does nothing else keeps
`## Why the Artifact Set Shrinks` resident from invocation; the realistic saving
is 0 to ~5,700 tokens out of ~45,000, the top of that range requiring the author to
relocate 25,358 chars of prose by hand, which is achievable today without koto.
The biggest open question is whether koto's value here is disclosure at all rather
than gating — `/scope` already loads six phase files lazily, so the disclosure
delta is small, while a state machine that demands per-hop consolidation evidence
before exit finalization is a different and possibly stronger argument that this
lead did not investigate.
