# PRD Phase 4 Clarity Review: Skill Adherence Enforcement

VERDICT: FAIL

Reviewed: `docs/prds/PRD-skill-adherence-enforcement.md` (Draft) against
`skills/prd/references/prd-format.md` (shirabe 0.17.1-dev).

The document is well written and the Problem Statement is among the better ones
I have read at this altitude. It fails on criterion 1 and criterion 3. Six of
the seventeen requirements admit two conforming implementations that differ
materially, and two mechanism decisions have leaked — one into a non-functional
requirement, one into an acceptance criterion where it silently forecloses a
DESIGN choice. Criteria 2, 5, and 6 pass; criterion 4 passes with two findings.

---

## Criterion 1: Requirement ambiguity — FAIL

Six material ambiguities (R2, R3, R7, R12, R14, R17), four moderate (R1, R6,
R11, R13), three minor (R4, R8, R15).

| R | Verdict | The ambiguity |
|---|---------|---------------|
| R1 | Moderate | Two undefined terms carry the requirement. **"plan-scale work"** appears nowhere else in the document and has no threshold: is a three-issue PLAN plan-scale? A single-issue one? A free-form task an agent decomposed itself? Engineer A scopes the check to any session that read a `PLAN-*.md`; engineer B scopes it to sessions above some issue count; both conform. **"state the agent under evaluation did not author"** is the anti-self-report clause and is the requirement's whole point, but the boundary is unstated: incident two's agent *ran a script* that produced a valid payload. Engineer A reads "did not author" as "the agent did not compose the content" — script output qualifies, and the payload from incident two becomes admissible evidence. Engineer B reads it as "no tool call the agent issued produced it" — script output is disqualified. These are opposite readings of the incident the PRD is built around. |
| R2 | **Material** | **"delegated its work"** has no completeness threshold. Incident two delegated nothing and implemented six issues inline; but a run that delegates five of six and does one inline is the case the requirement does not decide. Engineer A implements "at least one delegation occurred"; engineer B implements "every issue in the plan was delegated". Both claim conformance and the first passes a run that is 83% the failure being fixed. The AC ("drove the workflow to fan-out") makes it worse rather than better, since reaching fan-out is weaker than delegating. Separately, **"registered the workflow"** is used here, in Goals ("a run that never registered"), and nowhere defined. R6 implies registration means an orchestration session exists; that inference should be stated, not left to be drawn. |
| R3 | **Material** | The requirement never says **whose** writes are refused, or **when the refusal is armed**. Read literally — "The system SHALL refuse a filesystem write that falls outside the closed write-target set" — it refuses every out-of-set write in every session on the machine, which would stop all ordinary work. The AC discloses the intended scope ("An attempt to write a source file **from the orchestrator**"), but an AC cannot narrow a requirement; the requirements are the contract. Engineer A arms the refusal only inside a session that has entered plan-execution as orchestrator; engineer B arms it whenever a PLAN doc is present in the repo; engineer C arms it globally and adds an allowlist. All three conform to R3 as written, and only one is the feature. This alone is disqualifying. |
| R4 | Minor | **"what the sanctioned alternative is"** does not say whether the alternative is computed per refusal or fixed. Engineer A emits one constant string ("delegate this issue to a child rather than writing it here"); engineer B computes a per-path suggestion. Both satisfy "names ... what the sanctioned alternative is". The AC does not separate them either. Low stakes, but the discriminating case (a refused agent that "proceeds correctly on its next attempt") may need the specific form. |
| R5 | Clear | Two conditions, both binary and observable: refusal holds under `--dangerously-skip-permissions` / non-interactive, and does not depend on a prompt being answerable. Directly testable. |
| R6 | Moderate | **"SHALL NOT report a failure"** leaves the positive answer unspecified. For a coordinated multi-repo run, does the check report *conformance* or *indeterminate*? Both "do not report a failure", and R7 makes indeterminate a legal output. But to the reviewer in user story six, "this run conformed" and "I cannot tell" are opposite answers. The AC restates the negative and so disambiguates nothing. Secondary: the requirement does not say on what basis the system recognizes a coordinated run — recognition is DESIGN's, but a carve-out that cannot be triggered is a silent false-failure surface, and nothing here obliges DESIGN to close it. |
| R7 | **Material** | Category error between the two halves of the feature. "Where the system cannot determine **conformance**" is R1/R2 vocabulary (a post-hoc determination that *reports*), but "SHALL permit **the action**" is R3 vocabulary (an in-band gate that *blocks*). The check does not permit or deny anything; the refusal does not determine conformance. Engineer A scopes R7 to the write refusal only, leaving the check free to return indeterminate. Engineer B applies it to the check and makes an undetermined check report conforming — which directly contradicts R2's discipline that ambiguous evidence must not pass. The requirement needs splitting into one clause per surface. |
| R8 | Minor–Moderate | "The system SHALL **provide** a sanctioned route" obliges the route to exist, not the agent to take it. R8 is therefore satisfied by a route that no agent ever uses, and the AC agrees ("An **agent that records** a conflict under R8 produces..."), conditioning on the agent electing to. Engineer A ships only the route; engineer B also adds a directive obliging the agent to route the conflict before departing. Given the field incident — an agent that "conceded afterward that it should have flagged the conflict ... and did not" — the difference between those two implementations is the difference between fixing the incident and not. If leaving the choice with the agent is deliberate (R16 and the Goals suggest it is), say so in the requirement. |
| R9 | Clear | Three named record fields, each checkable by inspection. Trivial wrinkle: "the course the agent took" is past tense on a record written at conflict time, so it may be an intention rather than an outcome; not worth a rewrite. |
| R10 | Clear | Binary and testable, and the R1–R9 range is correctly drawn (R11–R13 are not session-scoped). |
| R11 | Moderate | **"rather than inventorying its architecture"** is a negative criterion with no test, and its AC hardens it into "contains no **internal architecture vocabulary**" — a term this document never defines. Two competent reviewers will disagree over whether "state projection", "exit-path bindings", or "orchestration session" are internal architecture vocabulary or the plainest available names. This AC fails the format's own "binary pass/fail — no subjective judgment" bar. |
| R12 | **Material** | Nothing in the requirement or its AC fixes the sample, the size, or the bar. "**plan-shaped work**" is undefined; "**how often the correct skill is selected**" does not say who adjudicates correct; the AC asks only that a before-and-after rate exist and be "comparable". Engineer A runs five prompts by hand and reports 3/5 → 4/5; engineer B builds a scenario harness with a fixed corpus and a stated n. Both conform, and only one makes R11's effect falsifiable, which is the stated reason R12 exists. At minimum the requirement should fix that the same prompt set is used before and after, and that the set is recorded. |
| R13 | Moderate | **"the enforcement"** is not scoped. The feature has three surfaces — the write refusal, the conformance check, the conflict route. Does the operator switch disable all three or only the refusal? The AC tests only the refusal ("no refusal occurs and the session completes"), so engineer A ships a refusal-only switch and passes; engineer B ships a whole-feature switch. These differ in whether a disabled workspace still produces conformance records. |
| R14 | **Material** | Two defects. (a) **No threshold.** "without adding latency a user perceives as a stall" is unmeasurable, and no acceptance criterion covers R14 at all, so the requirement is unfalsifiable as shipped. The format guidance asks for measurable thresholds on non-functional requirements where possible, and here it is possible (a per-invocation budget in milliseconds). Engineer A at 40ms and engineer B at 900ms both claim conformance. (b) **Terminology collision.** R14 calls the thing on the tool-call path "the conformance check", but R1's conformance check is the post-hoc determination a reviewer runs on a finished branch — that one is not on any interactive path. The thing that runs per tool call is R3's refusal. As written, R14 either constrains the wrong component or asserts the check and the refusal are the same component, which no other requirement says. |
| R15 | Minor | "**staleness**" is undefined — stale relative to what, and detected by whom? Absence and failure are observable; staleness needs a referent (a version, a schema, a timestamp) before it can be tested. Otherwise clear. |
| R16 | Clear-but-untestable | Unambiguous as a prohibition, and correctly stated. It is a meta-requirement over implementations rather than a system behavior, so it is verifiable only by review and has no acceptance criterion. That is acceptable for a constraint of this kind; noting it so DESIGN does not treat it as covered by an executable test. |
| R17 | **Material** | The requirement governs "public-facing artifacts produced by the enforcement", but the document never establishes that any such artifact exists. Out of Scope explicitly excludes "making the conformance record travel off the machine", and Known Limitations confirms the trace is machine-local. So engineer A concludes there are no public-facing artifacts and implements nothing, conforming vacuously; engineer B decides the conflict record under R8/R9 is committed to a branch, therefore public-facing, and builds redaction for it. The requirement needs to name which artifact it governs, or be dropped as covered elsewhere. |

**The three to fix first:** R3 (missing scope — the most consequential), R7
(two surfaces conflated in one sentence), R14 (no threshold, and probably
constrains the wrong component).

---

## Criterion 2: Problem Statement states a problem and stands alone — PASS

It states a problem. "An agent ... can produce all of the code and none of the
process. The author finds out by asking." No solution appears anywhere in the
section; the closest it comes is enumerating what was absent in incident one
("no orchestration session was created, no per-issue child ran, no review gate
fired"), which describes the loss rather than prescribing the fix.

It stands alone. Both incidents are narrated in enough detail that a reader who
has never opened the BRIEF can reconstruct the failure, including the part that
makes it hard: incident two passed every surface-level check and had a
defensible cause. The paragraph beginning "Neither incident was a
discoverability failure" pre-empts the obvious wrong fix, and the closing
paragraph answers both "who is affected" and "why now" explicitly. This is the
strongest section in the document.

Two small jargon items a cold reader will step over rather than trip on, both
worth a two-word gloss: "implemented 22 **outlines** by hand" (outline is
shirabe's term for a plan's per-issue stub) and "its **task-payload** script".
Neither is a blocker.

---

## Criterion 3: "How" leaked into the PRD — FAIL

Two genuine leaks, both foreclosing a decision that belongs to DESIGN.

**1. R14 stipulates the enforcement runs on the tool-call path.** "The
conformance check SHALL run on the interactive path of tool calls" is not a
requirement about how well the system performs — it is an assertion that the
enforcement is implemented as something invoked per tool call (a hook). DESIGN
has not chosen that yet. The requirement's actual content is that enforcement
must not add latency a user notices; the clause about *where it runs* is the
mechanism. Rewrite toward the property: enforcement must not add more than
<N>ms to any tool call it observes.

**2. The acceptance criterion "With the enforcement **binary** absent from the
**path**, a session runs to completion unblocked."** This decides that the
enforcement ships as a compiled executable resolved through `PATH`. That is a
distribution and packaging decision, and the Decisions section says one page
earlier that placement is "deferred to DESIGN as a mechanism choice" — so the
AC contradicts the document's own deferral. If DESIGN chooses a
non-binary mechanism, this criterion becomes untestable rather than merely
wrong. Restate against the property R15 already requires: with the enforcement
component absent, a session runs to completion unblocked.

**Checked and cleared** (naming a contract the requirement binds to, which is
legitimate):

- R3's "the closed write-target set the plan-execution skill declares for
  itself" — binds to an existing declared contract, does not specify the
  enforcing mechanism. Clean.
- R3's "at the point the write is attempted rather than at a later
  self-administered check" — a timing property (in-band vs post-hoc), which is
  a behavioral requirement, not a mechanism. Clean, and load-bearing.
- R8's "when no orchestration session yet exists" — orchestration session is an
  existing concept of the workflow this feature governs. Clean.
- R13's "without editing skill or workflow content" — negative constraint
  stating an operator property, not a named mechanism. Clean.
- The AC's "including the workflow's own state file, its scratch, and its
  pull-request operations" — enumerates the existing execute contract's
  declared targets. Borderline but defensible; it is citing the set R3 binds
  to, not designing it.
- Decisions and Trade-offs on skill-carried vs workspace-manager placement —
  the section is the sanctioned place for recorded alternatives, and it labels
  itself as deferring the choice. Clean.
- Known Limitations' "would require operating-system-level confinement" — names
  a mechanism *class* to explain why a boundary exists. Appropriate here.

---

## Criterion 4: User Stories distinct, each a real role — PASS with findings

No generic "as a user" role appears. All six name a concrete actor: the author
who dispatched, the author watching, the orchestrating agent, the agent facing
a conflict, the coordinating agent writing a brief, the reviewer.

**Finding A — stories 1 and 6 are close to one story told twice.** Both request
a post-hoc determination of whether a branch ran under the workflow, read from
a durable trace the agent did not author; both land on R1. What separates them
is the reader's information position rather than the system's behavior: story
1's author *could* ask the agent and is choosing not to trust the answer; story
6's reviewer has no agent to ask and would otherwise infer from commit shape.
That is a real distinction and it is the reason I am not failing the criterion,
but the two stories as written do not make it visible. Either sharpen story 1
to the in-run/at-handoff moment or merge the pair.

**Finding B — story 5 asks for something no requirement provides.** "As a
coordinating agent writing a task brief for a worker, I want the workflow the
work should run under to be **part of what a brief carries**" is a request to
change the dispatch brief format. No requirement in R1–R17 requires that. R10
covers agent-launched sessions, and the upstream BRIEF resolves this journey by
a different route entirely (the worker's first out-of-contract write is
refused, and the refusal names the workflow). So the story promises a
brief-format change the requirements do not deliver, and a reader cannot tell
whether that change is in scope. Either add the requirement, or rewrite the
story so its "I want" is the coverage R10 actually provides.

---

## Criterion 5: Goals are outcomes — PASS

All four substantive paragraphs state outcomes, not implementations:
conformance becomes checkable by someone who was not watching; departure is
caught in-band with enough information to self-correct; conflicts stop being
resolvable in silence; coverage reaches sessions no human started. "By reading
a trace the agent did not author" is the closest thing to a mechanism, and it
is a property of the evidence rather than a choice of storage — it is the
outcome, since a self-authored trace would not deliver the goal.

One note, not a finding: the fifth paragraph ("Nothing here promises that
adversarial reviews ran...") is a non-goal rather than a goal, and it repeats
the first Out of Scope bullet nearly in full. It earns its place — the
constraint is important enough to state twice and R16 depends on it — but if
the section is trimmed, this is the paragraph that is already covered
elsewhere.

---

## Criterion 6: Writing quality — PASS

`shirabe validate --format json --visibility=Public
docs/prds/PRD-skill-adherence-enforcement.md` (shirabe v0.17.0):

```
outcome: clean, errors: 0, notices: 0, findings: []
advisory: "Draft posture: no draft-tolerable findings to flag."
```

No errors and no notices. Nothing to report against the repo's declared
prose-vocabulary exemptions (`tier`, `journey`, `underscore` per CLAUDE.md) —
`journey` appears only as the User Stories framing, `tier` and `underscore` do
not appear at all, and none produced a finding.

FC10 em-dash density: measured **0.0 per thousand words** (0 em-dashes across
2,226 body words), against a threshold of 10. The document uses no em-dashes or
en-dashes anywhere; sentence rhythm is carried by short declaratives instead,
which reads well.

Prose quality independent of the validator is good: varied sentence length,
concrete nouns, no preamble, no bulleted-bold-label padding. "It also had a
defensible cause" and "Knowledge was present and unused" are the kind of
sentences that make the section land.

---

## Summary of required changes to reach PASS

1. **R3** — state whose writes are refused and when the refusal is armed
   (orchestrator, inside an active plan-execution run). Currently readable as a
   machine-wide gate.
2. **R7** — split into one clause for the check (what an undetermined check
   reports) and one for the refusal (what an undetermined gate does).
3. **R14** — give a measurable latency budget, drop "on the interactive path of
   tool calls", and name the component it actually constrains; add an
   acceptance criterion.
4. **R2** — define the delegation threshold (all issues, or some), and define
   or replace "registered".
5. **R12** — fix that before/after measurement uses the same recorded prompt
   set, and say who adjudicates a correct selection.
6. **R17** — name the public-facing artifact it governs, or drop it.
7. **AC** — replace "enforcement **binary** absent from the **path**" with the
   mechanism-neutral form; it contradicts the document's own deferral of
   placement to DESIGN.
8. **R11's AC** — "no internal architecture vocabulary" is not binary; restate
   as a positive test (the description names the situations in which the skill
   applies).
9. **R1, R6, R13, R15** — resolve "plan-scale work", "did not author", what R6
   reports positively, what "the enforcement" covers for R13, and what
   "staleness" is relative to.
10. **User stories** — merge or sharpen 1 vs 6; reconcile story 5 with the
    requirements.
