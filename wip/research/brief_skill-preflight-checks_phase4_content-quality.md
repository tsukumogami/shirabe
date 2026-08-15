# Verdict: PASS

Re-review of `docs/briefs/BRIEF-skill-preflight-checks.md` against the seven
required changes from the prior FAIL, plus a full rubric re-run for regressions.

## Required-change verification

1. **Guard claim, Problem Statement first paragraph -- applied correctly.** The
   false headline ("six tools ... one is guarded") is gone. The paragraph now
   draws the distinction the evidence supports: `koto >= 0.3.3` in
   `skills/work-on/SKILL.md:178` is the only version floor stated at skill
   altitude (verified -- the only other hit is that skill's own eval fixture),
   and presence guards for `shirabe`, `git`, and `jq` exist but live inside
   individual scripts (verified: `run-cascade.sh:639` guards `shirabe`, `:628`
   guards `git rev-parse` with a failure branch, and five scripts carry
   `command -v jq`). The follow-on paragraph ("A `command -v` buried in a script
   protects that script") turns the correction into the argument, which is
   stronger framing than the claim it replaced.

2. **`jq` count -- applied correctly.** Nineteen becomes fifteen in both places
   (Problem Statement, Scope OUT). Recount confirms 15 jq-binary invocations in
   `skills/execute/scripts/run-cascade.sh` (`:193`, `:209`, `:243`, `:247`,
   `:337`, `:343`, `:347`, `:381`, `:761`, `:765-768`, `:838`, `:917`); the
   four excluded lines are three comments and the `gh --json ... --jq` at
   `:162`. The adjacent "`python3` once" also holds (`:44`, the realpath shim).

3. **Journey 2 -- applied correctly.** "The run stops at a sentence" is gone.
   The check now "catches the gap at load ... and says so," the *agent* "elects
   to stop and report," and the journey states outright: "The check does not
   halt the run; it makes the run's own decision an informed one." That is
   exactly the shape Scope OUT permits ("The check informs; the agent decides")
   and the shape User Outcome requires ("Nothing is blocked"). Full-document
   sweep for halt language finds no remaining sentence implying the check gates:
   the only other "blocks" is in the Problem Statement describing today's broken
   127-to-violation misrouting, which is the bug, not the feature.

4. **Scope IN mechanism -- applied correctly.** "through the mechanism Claude
   Code already provides and `skills/inflight/SKILL.md` already uses" is
   deleted. The bullet now reads as a pure boundary: "Execution when the skill
   loads, deterministically -- not lazily, not on demand, and not dependent on
   the agent choosing to run it." `skills/inflight/SKILL.md` survives in
   References as precedent, which is where it belongs.

5. **Zero-declaration count -- applied correctly.** Scope IN now says "the five
   that will declare an empty set" and carries the accurate breakdown ("Nine
   need nothing beyond a checkout, but four of those nine call `shirabe
   transition` at a single finalize step"). This matches the grounding research
   verbatim (`wip/explore_skill-preflight-checks_findings.md:143-146`). Journey
   5 still says "Nine of shirabe's twenty skills are in this position," but the
   position it names is "needs nothing but a working checkout" -- the same
   nine-skill predicate Scope IN uses, not the five-skill empty-declaration
   predicate. The two sections now use the same vocabulary for the same
   quantity, and the inflated "the nine that will declare that they need
   nothing" is gone. Consistent, and no longer overstated.

6. **Open Question 3 -- applied correctly, and at the right altitude.** The
   contested-shape deferral is gone from Open Questions and answered in the
   Problem Statement instead. Both citations re-verified directly against
   `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md`: Decision 6
   rejected per-skill inlining because "inlining duplicates the pattern across
   seven SKILLs" (`:319`) and rejected once-per-chain-entry probing because
   "the version-skew fires per-subcommand-invocation, not per-chain-entry"
   (`:321`), choosing the lazy-loaded `references/fixes/cli-version-preflight.md`
   (`:295`, `:415`). The brief's paraphrase of both rejections is faithful. The
   chosen option required that "each child SKILL that prescribes a `shirabe`
   subcommand emits a structured pointer to this file" -- and a repo-wide grep
   confirms zero references to `cli-version-preflight` anywhere under `skills/`
   (hits only in the design doc, this brief, and `wip/`). So the brief's claim
   that the file never loads is exact, and it is the correct kind of argument:
   evidence that an existing mechanism did not close the gap, which is problem
   territory. The `shirabe#270` quotation is now verbatim -- "a pattern list
   only catches what its author remembered" appears in
   `.github/workflows/check-plan-scripts.yml:33`, authored by the PR that closed
   the issue.

   The paragraph's closing two sentences ("a declaration is written by the same
   author, in the same change, as the call it describes") lean nearest to
   solution-defence of anything in the section. They stay on the right side of
   the line: they argue the problem is tractable by rebutting an objection to
   its tractability, and they name no mechanism, interface, or data shape. The
   brief's own outcome frontmatter already commits to a declaration, so this
   introduces no commitment that was not there. Not a new violation, but it is
   the closest thing in the document to one.

7. **"Eight sites" figure -- applied correctly.** Now "`shirabe validate` is
   invoked from `/scope` and `/charter` at a dozen or so points," which is a
   hedge consistent with the 28 raw mentions across those two skills once prose
   references are separated from invocation-shaped lines.

## Regression check

Full rubric re-run, all six criteria.

**Problem Statement.** Still problem-shaped and still stands alone. The added
paragraph lengthens the section but does not change its altitude: it inventories
what was tried and why it did not work, which is the strongest form of a
problem argument. The internal contradiction that drove the prior FAIL is
resolved, and resolving it improved the section -- the script-local versus
skill-altitude distinction is now the load-bearing sentence. "The consequence is
not that runs fail. It is that they don't" survives intact.

**User Outcome.** Unchanged and unaffected. Still outcome-shaped, still names
both users, still matches `outcome:` frontmatter beat for beat. "Nothing is
blocked and nothing is installed on its behalf" now has no contradicting
passage anywhere in the document.

**User Journeys.** All five keep their `###` heading, concrete user, trigger,
and outcome shape. Distinctness is unharmed by the Journey 2 rewrite -- the
three host states (absent, wrong surface, not on PATH) still produce three
different instructions, and Journey 2's rewrite actually sharpens its
distinctness by moving the decision to the agent. Journey 4 still changes the
user; Journey 5 still holds the null case.

**Scope Boundary.** IN is now six clean boundary items with no design altitude.
OUT is unchanged and remains the strongest section. The Journey 2 rewrite
removes the only IN/OUT conflict. The `jq` figure in OUT matches the Problem
Statement.

**Open Questions.** Three items, all genuine deferrals now that the contested
shape is answered rather than deferred. Q1 (absence versus skew versus
subcommand surface) names two shipped artifacts that disagree and hands the
pick to the PRD "and says why." Q2 (mode-conditional dependencies chosen after
load) defers the requirements half of a real tension. Q3 (what makes an
instruction actionable, including the sandboxed-host case with no reachable
install route) is a requirements bar, not a blocker. None is "should this
feature exist."

**Altitude.** No PRD requirements and no DESIGN architecture anywhere. The
removal of the inflight mechanism from Scope IN was the last of it.

One residual nit, carried over and not worth another round: "four separate
re-implementations of the same `jq` check" undercounts by one -- the corpus
carries a fifth in `skills/work-on/references/scripts/extract-context.sh:133`
alongside the four in `/plan`. The prior review declined to fail on this and
still does; it understates rather than inflates, and the sentence's point
survives either number.
