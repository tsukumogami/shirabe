# Verdict: FAIL

Reviewer: clarity and altitude. Target: `docs/prds/PRD-skill-preflight-checks.md`
(364 lines, Draft). Format reference: shirabe 0.16.1-dev
`skills/prd/references/prd-format.md`.

The headline is that the altitude discipline held. I went looking hard for the
drift the BRIEF was corrected for -- a file format for the declaration, a
shell-script-versus-subcommand decision, a named mechanism that runs the check
at load, a code home for new code -- and none of it is here. R1 says "carry a
declaration" without saying in what. R6-R8 say what is verified without saying
how it is probed. Nothing names a hook, a wrapper, a frontmatter key, or a
binary. Two leaks got through (R19 and a Known Limitations bullet) and they are
narrow. The failure is driven by a dangling reference into `wip/`, a criterion
that contradicts the requirement it verifies, and four requirement/criterion
pairs that disagree about what is being required.

## Altitude violations

**A1. R19 mandates a resolution strategy and forbids an implementation
alternative.** "Install instructions SHALL be resolved against what the host
actually has rather than enumerated per operating system, delegating to a
package manager already present where one is." Two of the three clauses are
HOW. "Delegating to a package manager already present" names the mechanism by
which the instruction is produced; "rather than enumerated per operating
system" rejects a competing implementation. The WHAT underneath is one
sentence: the command in the report must be one that runs on the host the
reader is on -- which R14 already says ("exactly one command that will work on
the host it is running on"). As written R19 either duplicates R14 or, where it
adds anything, adds design. Restate as the outcome and let the DESIGN choose
between per-host detection, package-manager delegation, and a table.

**A2. Known Limitations bullet 3 commits to a cost model that presumes an
implementation.** "Surface probing costs one subprocess per declared subcommand
on skills that declare them." One subprocess per subcommand is only true if the
check verifies a subcommand by invoking the tool once per subcommand -- which
is exactly the probing strategy the DESIGN is supposed to choose (a single
top-level help parse would cost one subprocess for all of them). The bullet
then disclaims itself: "Whether that is affordable at load is a design question
this PRD does not answer." It cannot both assert the cost and disclaim
answering the question. Keep the disclaimer, drop the arithmetic.

**A3 (soft). Mechanism vocabulary leaking into requirement text.** R6-R8, R10,
R12-R17 say "the check ... SHALL verify / evaluate / produce / distinguish."
R21 switches to "the check's probes," and Known Limitations to "surface
probing." "Probe" is a mechanism noun; "verify" is not. This is the vocabulary
that will license design content on the next edit. Normalize on the verifying
language.

**A4 (soft, defensible). R25 anchors the fix to a specific script.**
"`skills/execute/scripts/preflight.sh` checks a file path and nothing else."
Naming an existing file as evidence of a false claim is legitimate PRD content,
and R25's actual requirement ("SHALL either become true or be removed") is
correctly stated about the *claim*, not the script. I am recording it only
because a design-drift reviewer reading the sentence alone could mistake it for
a mandate that the preflight remain a shell script at that path. No change
required.

Explicitly checked and clean: no requirement decides where new code lives; no
requirement names a file format, serialization, or frontmatter key for the
declaration; no requirement decides shell script versus binary subcommand; no
requirement names the mechanism that runs the check at load. "At load" as a
*timing* claim (R10, R12, and four criteria) is user-visible behavior and
belongs here.

## Ambiguities

**B1. R3 and its acceptance criterion disagree on which flags get declared.**

> R3: "for each subcommand the flags the skill's own logic **depends on**"
> AC 2: "names flags wherever the skill's logic **branches on** one"

Reading A (depends on): a skill that always passes `--json` to a subcommand
declares `--json`, because the call fails without it. Reading B (branches on):
it does not, because no conditional reads the result. These produce materially
different declaration sets across the corpus, and the second is a strict subset
of the first. R13 and R14 make the difference visible to users -- under Reading
B, an always-passed flag that disappears from the tool produces exactly the
misroute this PRD exists to stop, and the check would not have caught it. Pick
one word and use it in both places. On the evidence in the Decisions section
("a skill therefore declares what its own calls depend on"), Reading A is the
intended one and the criterion is the error.

**B2. R7 and R8 disagree on what "the surface" means.**

> R7: "each declared subcommand **appears in the tool's advertised surface**"
> R8: "each declared flag **exists on** the subcommand it is declared against"

Reading A: verification reads what the tool advertises (help output,
completion, whatever it publishes). Reading B: verification establishes that
the thing actually works when called. These differ on real cases -- an
undocumented-but-functional subcommand passes B and fails A; a subcommand
advertised in help but broken passes A and fails B. R7 picks A explicitly; R8
is silent and reads as B. Either is a legitimate PRD-altitude choice; having
one of each is not.

**B3. R11 does not say whether building the deferred check is in scope.**

> R11: "Mode-scoped requirements SHALL be verified where the mode is actually
> selected, and the declaration SHALL make that deferral visible rather than
> silent."

Reading A: this PRD requires mode-selection-point verification to be built --
`/plan`'s multi-pr branch grows a check. Reading B: the requirement's real
content is the second clause (the declaration marks the deferral), and where
the deferred verification happens is left open. The acceptance criterion picks A
("the multi-pr branch reports it when that mode is selected"), but the
requirement's grammar puts the weight on the second clause and R10 frames the
whole area as what the load-time check does *not* do. The two readings differ
by roughly the number of mode-scoped call sites in the corpus. State the scope
in R11 itself.

**B4. R21 bans more than its criterion checks.**

> R21: "Neither the check's probes nor the skills' own call sites SHALL
> **discard** a tool's stderr."
> AC 12: "No probe and no skill call site **redirects a tool's stderr to
> `/dev/null`**. Verified by grep across `skills/`."

Reading A (R21): stderr must reach somewhere a human or agent can see -- so
capturing stderr into a variable that is then dropped on the success path also
violates it. Reading B (the AC): only the literal `2>/dev/null` spelling is
prohibited, and capture-then-discard passes. Reading B is grep-able and Reading
A is the one that actually prevents `shirabe#279`, whose own diagnosis in the
Problem Statement is that the error "went with it" -- not that a particular
redirect spelling was used. As it stands a conforming implementation can
satisfy every acceptance criterion and still reproduce the incident.

**B5 (minor). R1's "explicit empty declaration" does not say what distinguishes
it from absence.** The requirement's own rationale is that "declares nothing"
and "was never given a declaration" must be distinguishable -- but by whom, and
at what moment? By a human reading the skill, or by the check at load? AC 17
("Loading a skill whose declaration is empty produces no output and runs no
probe") tests the empty case but never tests the *missing* case, so the
distinction R1 is built to create is never verified. Add the negative criterion
or drop the rationale.

## Cross-reference integrity

Numbering is clean. R1 through R25 appear exactly once each, in order, with no
gaps and no duplicates. Every `R<n>` token in the document resolves to a
requirement that exists.

Semantic accuracy of the citing text, checked one by one:

- R4 -> "R3's split": R3 does state the split. Correct.
- R14 -> "which outcome from R13 holds": R13 defines the outcome set. Correct.
- Decisions -> R4, R5, R10, R11, R12: all accurate to what those requirements
  say.
- Out of Scope -> R17, R9, R22: accurate. The R22 gloss ("concerns how its
  failures are told apart, not what it validates") matches R22's text.
- Known Limitations -> R12 ("R12's zero-output rule is not a latency budget"):
  accurate.

**C1. One citation claims more than its target says.** Known Limitations: "R24's
requirement that superseded prose be deleted in the same change is the
discipline that keeps declarations honest; nothing mechanically proves a
declaration is complete." R24 requires removal of prose the declaration
supersedes. Deleting stale prose does not make a declaration complete or honest
-- it removes a competing statement. The sentence's own second clause concedes
the point. The citation resolves, but the claim it makes about R24 is not
supported by R24.

**C2 (blocking). The Decisions section points into `wip/`.** "the first went
through a five-way adversarial bakeoff whose working artifacts are the
`decision_skill-preflight-verification_*` files." The only file matching that
glob in this worktree is `wip/decision_skill-preflight-verification_report.md`.
The workspace CLAUDE.md is unambiguous: files under `wip/` are non-durable and
"MUST NOT be referenced from any committed final artifact -- not from
frontmatter, not from prose, not from code comments," because cleanup deletes
them and the reference becomes a dangling pointer. Omitting the `wip/` prefix
does not exempt the reference; it makes it harder to grep. This is a durable
PRD citing a file that is guaranteed to be deleted before the PR merges. Either
promote the bakeoff's conclusions into the Decisions section (they largely
already are -- the paragraph that follows stands on its own without the
pointer) or drop the clause.

## Style and consistency

Mechanical rules pass. No term from `skills/writing-style/rules.yaml` appears in
the document -- I checked all five word categories plus the structural and
over-formality tables. Em dash count is zero (the document uses `--`
throughout), so the density rule does not apply. `tier`, `journey`, and
`underscore` were excluded from review per shirabe's declared vocabulary and do
not appear anyway. Burstiness is good; the Problem Statement in particular
varies well and the specifics are named rather than gestured at.

Judgment-only findings:

**D1. Vague attribution without citation.** Decisions, Silence on success:
"Every 'doctor' tool surveyed treats a green checklist as the product and none
can be made quiet; the systems that are silent when healthy separate the
predicate from the reporter." Two universal claims ("every," "none") resting on
a survey that is never named or linked. This is the `vague attribution without
citation` rule in the rule source. Name the tools or soften the claim -- the
argument that follows it ("The reader here is an agent") carries the decision on
its own and does not need the survey.

**D2. A sentence whose meaning survives its deletion.** Known Limitations bullet
1: "Semantic changes behind a stable surface are out of reach, as above." The
Decisions section already carries this in full under "Known unknown, carried
deliberately," with the concrete example (`roadmap populate --no-issues` in
#264) that the bullet drops. The bullet is a pointer to a paragraph four inches
up the page. Cut it.

**D3 (minor). A user story names the solution instead of the need.** "As an
author running `/decision`, which needs nothing beyond a checkout, I want **the
feature to be invisible**." Every other story states what the author experiences;
this one states what the feature does. "I want to see nothing about tools this
skill does not use" says the same thing from the role's side.

Problem/solution separation: **passes cleanly.** The Problem Statement describes
five filed incidents by number, the drift precondition, and the exit-code
collision, and never once proposes the declaration or the check. It is a problem
in problem's clothing. The strongest part of the document.

User Stories: six stories, six distinct scenarios (fresh laptop, agent
pre-dispatch, tsuku-managed PATH skew, maintainer adding a dependency, the
no-dependency skill, the misdiagnosed chain halt). Roles are real and
differentiated -- engineer, loading agent, shirabe maintainer, author -- with no
generic "user." Every "so that" reaches a concrete outcome. Use-case framing
would have been acceptable here and was not needed.

Self-consistency on R17 (nothing hard-blocks): checked against Goals ("Nothing
is blocked"), Out of Scope ("Blocking or gating a skill on an unsatisfied check
(R17)"), and AC 5 ("the skill still loads and remains usable"). All consistent.
One soft tension, recorded not as a contradiction: user story 2 promises "I do
not send twelve children at a branch that was never created," but R17 leaves
that entirely to the agent's discretion. The story promises an outcome the
requirements deliberately do not guarantee. Reword the "so that" to the
information the agent gets rather than the action it takes.

Self-consistency on R9 (no version comparison anywhere): the *system behavior*
is consistent -- nothing anywhere reintroduces a version comparison, floor,
pin, or negotiation, and Out of Scope reinforces it. But see E2 below: the
criterion written to verify R9 is false against the document that contains it.

## Required changes

1. **Remove the `wip/` reference (C2).** Delete "whose working artifacts are the
   `decision_skill-preflight-verification_*` files" from the Decisions section
   opening, or replace it with the conclusions themselves. A durable PRD must
   not point at a file the cleanup phase deletes. This one is not negotiable --
   it is a workspace-wide rule and public CI greps for it.

2. **Fix the R9 acceptance criterion (E2).** As written: "No requirement, check,
   or report references a version number. Verified by grep over the shipped
   check surface." R9 itself contains "`koto >= 0.3.3`"; the Problem Statement
   contains `0.16.1-dev` and `v0.16.0`; the Decisions section contains `0.3.3`
   again. The criterion is false the moment it is written, and its scoping
   clause ("the shipped check surface") contradicts its subject ("no
   requirement"). Rewrite the subject to match the scope -- something that
   constrains the shipped check and report, not the prose of the PRD.

3. **Reconcile R3 with its criterion (B1).** Choose "depends on" or "branches
   on" and use the same phrase in R3 and in acceptance criterion 2. The
   Decisions section indicates "depends on" is intended.

4. **Make R7 and R8 agree on what is being read (B2).** Either both verify
   against the advertised surface or both verify actual acceptance. Say which in
   both requirements.

5. **State R11's scope (B3).** Say explicitly whether mode-selection-point
   verification is required by this PRD or only marked as deferred by the
   declaration. The acceptance criterion currently answers a question the
   requirement leaves open.

6. **Align R21 with its criterion (B4).** Either narrow R21 to the `/dev/null`
   redirect its criterion greps for, or broaden the criterion so that
   capture-and-drop is also caught. As it stands the criteria can all pass while
   `shirabe#279` remains reproducible.

7. **Lower R19 to outcome altitude (A1).** Remove "delegating to a package
   manager already present where one is" and "rather than enumerated per
   operating system." State the property the report must have; leave the
   resolution strategy to the DESIGN.

8. **Cut the subprocess cost claim from Known Limitations (A2).** Keep "whether
   that is affordable at load is a design question this PRD does not answer";
   drop "costs one subprocess per declared subcommand," which presupposes the
   probing strategy.

9. **Replace "the check's probes" with verifying language in R21 (A3),** and the
   same in Known Limitations.

10. **Fix the R24 citation in Known Limitations (C1).** R24 requires removing
    superseded prose; it does not keep declarations honest. Say what actually
    provides the discipline, or state plainly that nothing does.

11. **Name the survey or drop the universal claims in the Silence on success
    decision (D1).**

12. **Delete Known Limitations bullet 1 (D2)** -- it restates the Decisions
    section's "Known unknown" paragraph without its example.

13. **Reword user story 5 from the author's side (D3),** and soften user story
    2's "so that" clause so it promises information rather than an outcome R17
    leaves to the agent (see Style and consistency).

14. **Optional, recommended: add a negative criterion for R1 (B5)** -- that a
    skill with no declaration at all is distinguishable from one with an empty
    declaration. Without it, R1's stated rationale is untested.
