# Phase 6 Architecture Review: DESIGN-skill-adherence-enforcement

VERDICT: FAIL

Reviewed: `docs/designs/DESIGN-skill-adherence-enforcement.md` against
`docs/prds/PRD-skill-adherence-enforcement.md` (R1-R19, AC1-AC28).

The document is strong where it is strong: the option analysis is genuine,
the arming/registration split is the right architectural move and is argued
from evidence, and the security section is unusually thorough. It fails on
coverage and interface specification, not on judgment.

Four blocking findings:

1. **R13 has no architectural answer at all.** No component, no mechanism,
   not even a named deliverable in the staging.
2. **R16 (100ms p95) has no architectural answer.** The budget is never
   mentioned, and the hook's specified per-call work plausibly exceeds it
   with no caching or memoization strategy named.
3. **Both cross-validation interfaces are underspecified** in exactly the
   way criterion 3 defines as failing: the document says the hook writes a
   log and says the log matters, and never says what is in it. Same for the
   conflict store, which the determination must join against.
4. **Stage 2 ships an inert component and the staging says otherwise.**
   With the witness stubbed absent, the determination reports
   `indeterminate` for every non-coordinated run, which contradicts the
   stated rationale that stage 2 "produces the evidence that tells us
   whether the refusal is needed."

Plus R5, R19, R15, and R17's staleness half are partial, and there are five
internal inconsistencies including a second stale carry-over in Decisions
Already Made.

---

## Criterion 1: requirement-to-component coverage

| Req | Architectural answer in Solution Architecture | Verdict |
|---|---|---|
| R1 | Determination component; reads workflows records, terminal index, PLAN, conflict store, evaluation log | Partial — admissibility not reconciled (below) |
| R2 | Determination path: "conforming when registration holds and delegation is complete or its shortfall is covered by a recorded conflict; and non-conforming otherwise" | Covered |
| R3 | Adherence hook, PreToolUse on edit tools; "compares the write target against the declaration and either allows or denies" | Covered |
| R4 | Decision 2 + refusal data flow: arming on plan reference in the session's own inbound records; registration separated from arming | Covered — the design's strongest element |
| R5 | "denies with a target-specific reason"; Decision Outcome adds "and the sanctioned alternative" | **Partial — no mechanism derives the alternative** |
| R6 | Decision driver ("`ask` is unusable... Gates resolve allow-or-deny"); command-handler choice in Decision 3 | Covered |
| R7 | "coordinated when the plan's execution mode says so" | Covered |
| R8 | "If the plan does not resolve, or the execution mode is coordinated, or a single-issue delegation marker is present, it allows" | Covered |
| R9 (PRD) | "indeterminate when the liveness witness is absent or evidence is unreadable" | Covered |
| R10 | Conflict recorder, machine-local append-only store, works with no session | Covered |
| R11 | Surfacing via session-summary hook emission and home-PR block | **Partial — record contents never specified** |
| R12 | Hook registers unconditionally per session; subagent identity field used as routing key; determination walks children | Covered |
| R13 | — | **NOT COVERED** |
| R14 | Selection measurement component; Decision 5 (committed prompt set, wrapper, quantized per-query rate, tolerance band) | Covered |
| R15 | Named only in passing in Security Considerations ("The disable switch...") | **Partial — switch is never specified as a component** |
| R16 | — | **NOT COVERED** |
| R17 | "must guard on the binary's presence, must not exec, and must swallow a non-zero exit" | Partial — absence/failure covered, version staleness (AC17) not |
| R18 | Decision driver: "The ordering statement must narrow interpretation, never claim precedence"; conflict route as sanctioned bypass | Covered |
| R19 | "the published form is a reference and a summary rather than the verbatim instruction" | **Partial — does not meet AC23** |

### R13 — no architectural answer (blocking)

R13 requires the plan-execution skill's description to name the situations
the skill applies in and to contain no term absent from its user-facing
documentation. AC25 makes that a set-membership test.

The design never addresses it. The Components table has five rows and none
is the description or its check. Decision 5 is about *measuring* selection
(R14), which is a different requirement. The only trace of R13 anywhere in
the document is an oblique reference inside Stage 5's rationale — "The
measurement is worth running before the description change so there is a
baseline" — and Stage 5's own deliverable list is "the conflict recorder
and the selection measurement." The description change is not a deliverable
of any stage. Nothing names where the set-membership test runs, or against
which documentation set.

R13 and R14 are a matched pair in the PRD (R14: "The same set SHALL be used
before and after any change made under R13"). The design shipped the
measurement and dropped the thing being measured.

### R16 — no architectural answer (blocking)

The 100ms p95 budget appears nowhere in the document. The single
acknowledgement is in Consequences, and it is a cost admission rather than a
design response: "The design adds a component on the path of every
edit-shaped tool call, with the latency and failure-mode cost that implies."

This matters because the specified per-call work is not obviously cheap.
Per the refusal data flow, every edit-shaped tool call: selects a transcript,
scans received records for a plan reference, resolves that reference against
the working tree, reads the plan's schema and execution mode, reads the
write-target declaration, and appends an evaluation-log entry. Transcript
scanning grows with session length — and Consequences concedes the surface is
large: "The arming predicate reads transcripts, which is a larger and less
stable surface than a configuration lookup." No per-session memoization, no
caching of the resolved plan, no early-exit ordering, and no bound on how much
transcript is scanned is specified. AC28 measures this; the design gives an
implementer nothing to hit it with.

### R5 — the sanctioned alternative has no source (partial)

R5 requires the reason to name "the refused target **and the sanctioned
alternative for that target**," and to be "specific to the refused write
rather than a single constant."

Naming the refused target is trivially specific, and the design covers that.
The alternative is not sourced. Stage 1 defines the declaration as
"the plan-execution skill's closed write-target set" extracted "from prose
into a data file" — and that prose (`skills/execute/SKILL.md:661-667`) is a
list of *permitted* locations (state file and scratch under
`wip/execute_<topic>_*`, the skill's own files, `gh pr edit|ready|close`,
the finalization cascade's transitions, Decision Records). It contains no
mapping from a refused target class to its sanctioned move. The design does
not say the declaration gains one, and no other component supplies it.

As specified, the honest output is "target X is outside the set" — which
satisfies half of R5 and would let AC12 pass while AC13 ("proceeds correctly
on its next attempt with no human input") rests on the model guessing.

### R19 — mechanism does not meet AC23 (partial)

The design's answer: "a public repository must not carry content from a
private one, so the published form is a reference and a summary rather than
the verbatim instruction."

AC23 is stricter: the record "contains no path, repository name, or issue
number belonging to a private repository." A *reference* to the private
instruction is, in the ordinary case, exactly a private path or issue number.
The mitigation names the disallowed artifact class as its solution.

Two things are also missing: how the writing repository's visibility is
determined at record time, and where redaction happens. Prior art exists and
is not bound: `skills/execute/SKILL.md` item 5 carries a visibility boundary
with `shirabe validate --visibility=Public` routing and an F1 rule that "a
public coordination PR never embeds private-repo content." That is the same
constraint with a shipped enforcement path, and the design does not reference
it.

### R1 — admissibility not reconciled (partial)

R1's letter: evidence must be "derived only from state that no tool call
issued by the session under evaluation produced."

The design's frame is authorship — "making the record one the evaluated agent
did not author" — and it calls the surfaces "koto-authored." But the workflows
record exists *because the session ran `koto init`*. A tool call issued by the
session under evaluation produced it. Under R1's literal wording that is
inadmissible; under the design's authorship reading it is fine.

The distinction the design is reaching for is real (the engine wrote the
record, not the agent, and the agent cannot forge it without doing the thing).
It is never stated. Given that R1's admissibility clause is the load-bearing
answer to incident 2, and AC5 tests it directly, the design should say in one
sentence why engine-written side-effects of a session's own command are
admissible where script output is not.

### R15 and R17 (partial)

R15's operator switch is referenced only as an attack surface in Security
Considerations ("The disable switch, the plugin's enablement, and a
project-level setting..."). It has no row in the Components table, no form,
and no location. The second half of R15 — the determination surviving the
refusal being disabled — is covered by "The determination does not depend on
the refusal being present, so the two degrade independently."

R17's absence and failure halves are covered by the guard/swallow discipline.
The staleness half is not: AC17 posits "an enforcement component reporting a
contract version older than the session's skill declares," and no contract
version field, negotiation, or comparison appears anywhere — including on the
write-target declaration, which is the natural carrier.

---

## Criterion 2: the strawman check

**Result: passes.** No rejected alternative reads as set up to lose. Two are
thin and one is a category error, none blocking.

Checked all thirteen rejections across the five decisions:

**Decision 1.** "Registration record alone" is falsified with dated machine
state: "A completed eight-child run carries no workflows record, because koto
defaulted that recording on in a commit dated 2026-07-18 while the record only
began appearing in that workspace on 2026-08-04." That is a specific,
checkable observation, and it is the reason the liveness witness exists at
all. "Any koto session for this plan exists" states setup and outcome: "with
an unrelated session present, an inline run that never registered returned
indeterminate where AC2 and AC3 require non-conforming." *Thin:* the session
directory rejection asserts the mechanism ("Cleanup deletes it on success")
without a cited test, and the hedge "the naive existence test" leaves a
non-naive variant unconsidered.

**Decision 2.** The subagent-identity rejection is the opposite of a strawman
— it rejects the framing the researcher was *given* ("This was the framing
supplied to the researcher and it was declined, correctly: absence is an
open-world assumption") and then retains the field where it is sound, as a
routing key. Workflow-state arming is rejected structurally and correctly.
*Thin:* branch-name arming gets one sentence, though the counterexample
(an adopted-branch run) is concrete enough to be decisive.

**Decision 3.** Both rejections are strong, and one is exemplary:
skill-frontmatter registration is documented as *working* — Decisions Already
Made item 6 records that the 2.1.233 binary supports it, "emits `Registered
${i} hooks from skill '${n}'`, and a matching one-shot removal path proves the
default persists" — and is rejected anyway on a structural argument. Settings
injection likewise: "It works and is the shipped precedent," rejected on reach
and lifetime, and explicitly "Retained as a fallback." Nobody strawmans an
option they keep as their fallback.

**Decision 4.** The gate-override rejection is tested with the observed
failure quoted: "it exits non-zero with 'workflow not found' when no session
exists, which is exactly the case the requirement names." The two-vehicles
rejection reasons from the incident rather than from taste. *Thin:* the
runtime-directory rejection is one aphorism ("An audit record that does not
survive a reboot is not an audit record") — true and decisive, but the
underlying fact is left implicit.

**Decision 5.** The description-optimizer rejection is decisive and
self-evidently sound ("pointing it at the description under test would
rewrite the thing being measured"). The filename rejection names two
independent concrete blockers. *Category error, not strawman:* "claiming
exact reproducibility" is not an alternative mechanism, it is a claim the
design declines to make; listing it among rejected options inflates the count
by one.

**On the "tested" claims specifically.** Four assert testing. Three state what
was observed: the dated workflows-record absence, the unrelated-session
outcome, and the gate-override exit and message (stated twice, consistently,
at Decisions Already Made item 9 and Decision 4). The gate-override claim does
not say which invocation was run, which is a minor omission given the message
is quoted. The session-directory claim uses no testing language and does not
need to. No claim is a bare assertion dressed as evidence.

---

## Criterion 3: interface coherence — FAIL

Both interfaces are named, both have their *purpose* stated, and neither has
its *contents* specified. This is the failure mode the criterion defines.

**The evaluation log.** The document is emphatic that it matters: "The
evaluation log is a contract, not an implementation detail. The hook writes it
so the determination can distinguish 'this run did not register' from 'nothing
was watching.'" The Components table says the hook writes "its own per-session
evaluation log" and the determination reads "the hook's evaluation log." The
data flow says "Every path writes an evaluation-log entry."

What an implementer cannot learn from the document: what an entry contains;
how it is keyed to a session; where it lives; how the determination decides
"a witness was present *for this run*" as opposed to "a log file exists";
whether entries carry timestamps and whether the determination bounds them
against the run's window; what happens on rotation or truncation; what the
determination does when the log exists but has no entry in the run's window.

That last one is not academic. The witness's whole job is separating
"nothing was watching" from "this run did not register." A per-session log
with no specified keying or time bounds cannot make that separation, and the
separation is the reason the interface was created.

**The conflict store.** Stated as load-bearing: "A delegation shortfall
covered by a recorded conflict is conforming; the same shortfall uncovered is
not. The join walks children as well as the parent, because a child records
under its own session identity."

The join is described; the joined-on fields are not. For the determination to
decide that a *specific* shortfall is covered, the record must link to the
issue or step it excuses — otherwise any recorded conflict covers any
shortfall, and the recorder becomes the gameable predicate the Decision
Drivers explicitly disqualify ("A predicate satisfiable by one honest command
teaches agents the command that buys permission"). The Components table says
the recorder writes "its arguments," which defers the schema to a caller.

R11's three mandated fields — the instruction, the workflow step it conflicts
with, and the intended course — appear in the PRD and in the Decision Outcome
prose ("records a departure before it happens"), but never as a record
structure in Solution Architecture. There is no place in this design where a
reader learns what a conflict record looks like.

---

## Criterion 4: staging — FAIL

Dependency direction is right in one place and inverted in another, and the
"each is independently useful" claim is false for stage 2.

**Stage 2 produces a component that is honest and inert.** The determination's
own decision order is: "coordinated when the plan's execution mode says so;
indeterminate when the liveness witness is absent or evidence is unreadable;
conforming when registration holds...; and non-conforming otherwise." Stage 2
ships "with the liveness-witness input stubbed as always-absent."

Composing those: if stage 2 ships and stage 3 never does, the determination
reports `indeterminate` for **every non-coordinated run, permanently**. It
satisfies AC6 and nothing else. AC1, AC2, AC3, AC4 and AC5 all fail by
construction, including AC2, which the PRD calls "the discriminating case."

To the specific question: it does not *lie* — `indeterminate` is the correct
value for the evidence it has, and that part of the design is right. But the
stated justification does not survive: "Build it first because... it produces
the evidence that tells us whether the refusal is needed as strongly as we
think." A component that returns the same non-answer for every run produces no
evidence about anything. Stage 2 as scoped is not independently useful, and
the document claims all five stages are ("ordered so each is independently
useful"). Either merge stages 2 and 3, or let the determination reach
`non-conforming` without a witness in the case where registration evidence is
affirmatively absent *and* the run is recent enough to postdate the recording
path — and say which.

**Stage 5's independence claim contradicts the interfaces section.** Stage 5:
"The conflict recorder and the selection measurement. Independent of the
others and of each other." But the interfaces section states the opposite for
the recorder: "The conflict store is an input to the determination."

The consequence is concrete. From stage 2 through stage 4, the determination's
"or its shortfall is covered by a recorded conflict" branch is dead, because
no store exists to cover it. A run that legitimately hit a conflict, departed,
and would be conforming is reported `non-conforming` — a false negative
against a sanctioned path, which is precisely the failure the Decision Drivers
forbid ("Must not block sanctioned paths"). The recorder is a dependency of
the determination and belongs before or with it, not last.

**What is right.** Stage 1 before everything is correct — the declaration is a
hard prerequisite for the hook. Stage 3 before stage 4 is correct and well
argued: observe-only produces "a measured false-positive rate for the arming
predicate before any session is blocked by it." Gating stage 4 on the
one-command startup-ordering probe, with settings injection named as the
fallback, is the right treatment of the document's largest open risk.

---

## Criterion 5: altitude — passes, with the opposite concern

No downward drift. There are no function names, no file-by-file breakdowns,
no schemas-as-code. The two line-number citations (`materialize.go:592-606`,
`skills/execute/SKILL.md:242-246`) are evidence citations supporting decision
drivers, which is correct use at this altitude. Requirements are not
restated; Decision Outcome describes the components' behavior rather than
re-listing R1-R19.

The concern runs the other way. The document is abstract to the point where
some mechanisms cannot be assessed for feasibility. "The session's own inbound
records," "the transcript holding this agent's received instructions," "the
terminal index," "four koto-authored surfaces" — a DESIGN answers *how*, and a
reader cannot tell from these what is being read or how expensive it is. This
is not a separate finding so much as the root of the R16 gap: you cannot
budget latency against a surface you have declined to name.

---

## Criterion 6: internal consistency — five findings, one a second stale carry-over

**1. The "four surfaces" count is wrong three ways.** Decision 1's heading
says "four koto-authored surfaces plus the PLAN," then enumerates four items
of which the PLAN is one ("the expected issue count from re-parsing the PLAN")
— so the PLAN is both inside and outside the four. Of the four enumerated,
only two are koto-authored: the workflows record and the terminal index. The
PLAN is author-written and the liveness witness is written by the hook, which
this design introduces. Meanwhile the frontmatter and Decision Outcome both
say "four koto-authored surfaces plus the conflict store," and the Components
table lists five distinct reads (workflows records, terminal index, PLAN,
conflict store, evaluation log). The phrase "four koto-authored surfaces" is
load-bearing for the R1 admissibility argument and it does not describe what
the determination reads.

**2. Decisions Already Made item 9 is stale, in the same way item 6 was.**
It states the pre-session conflict vehicle "is the `shirabe work-summary` hook
path, already session-keyed and default-on." Decision 4 decided otherwise:
"one command, two backends," writing to "a durable machine-local append-only
record," with the hook demoted from vehicle to notification channel
("Surfacing reaches a watching author through the existing session-summary
hook emission"). Item 6 was corrected in place with an explicit "Design
rejected it: ... See Considered Options, decision 3." Item 9 needs the same
treatment — the tested `koto overrides` half is still valid, the vehicle claim
is not.

**3. `R9` names two different things in one document.** Decisions Already Made
item 5 — "The primary predicate is R9 write-target conformance" — uses the
`/execute` skill's own code, where "A write outside this set fails the R9
hard-finalization check" (`skills/execute/SKILL.md:667`). In this design's
upstream PRD, R9 is the indeterminate-outcome requirement, and the
determination's own R9 behavior is described three sections later. The same
token carries two meanings with no disambiguation. The reference is also
slightly off on its own terms: R9 is the finalization check, write-target
conformance is what it checks — and this design's whole point is to move that
check *off* finalization ("enforced at write time rather than at
self-administered finalization"), so naming the predicate after the check it
replaces reads as a contradiction.

**4. Stage 1 contradicts the Components table.** Stage 1 justifies the
declaration with "two components need to read it." The Components table shows
one: the hook. The determination's Reads column is "koto workflows records,
koto terminal index, the PLAN, the conflict store, the hook's evaluation log"
— no declaration. Either the determination also reads it (in which case the
table is wrong, and the determination's post-hoc write-target check needs
describing) or Stage 1's justification is.

**5. Decisions Already Made item 3 promises adoptions no component delivers.**
"Outcome gating is rejected as the primary mechanism... Its definitional half
and two cheap checks are adopted." Nothing in Solution Architecture, the
Components table, or the five stages implements a definitional half or two
cheap checks. Either name them or drop the claim.

**Not a contradiction, but a phrasing hazard.** Context says "Publishing the
record to a remote surface was considered and is excluded by the
requirements," while Decision 4 and the Components table both have the
conflict recorder writing "the home pull request body," which is remote. The
two survive together because the PRD's exclusion is specifically "Making the
*conformance* record travel off the machine" and the conflict record is a
different artifact — but the design says "the record" unqualified, three
sections before shipping a different record remotely. One qualifying word
fixes it.

---

## What would clear the FAIL

1. Give R13 a component and a stage — the description repair, plus where the
   AC25 term-membership test runs and against which documentation set.
2. Answer R16: name the surfaces the hook reads, and the caching or
   memoization that keeps per-call cost inside 100ms p95.
3. Specify both interfaces' contents: the evaluation-log entry (fields,
   session keying, time bounds, and what the determination concludes when the
   log exists but the run's window is empty), and the conflict record (R11's
   three fields plus the key the determination joins a shortfall on).
4. Fix the staging: either merge stages 2 and 3, or define what the
   determination may conclude without a witness; and move the conflict
   recorder ahead of the determination it feeds.
5. Close the partials: source R5's sanctioned alternative, specify R15's
   switch, add R17's contract-version comparison, and replace R19's
   "reference and a summary" with a mechanism that meets AC23 — binding to
   the existing `--visibility=Public` / F1 path is the obvious route.
6. Repair the six consistency items: the surface count, item 9's stale
   vehicle, the `R9` collision, Stage 1's "two components," item 3's
   unimplemented adoptions, and the unqualified "the record" in Context.
7. Add one sentence reconciling R1's literal admissibility wording with the
   design's authorship reading.
