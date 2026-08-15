# Verdict: PASS

Final verification pass on `docs/prds/PRD-skill-preflight-checks.md` (519
lines, Draft). All six must-fix items from
`prd_skill-preflight-checks_phase4_rereview.md` are resolved. One clean
pass across completeness, clarity/altitude, and testability found no
blocking defect. The document is ready to transition Draft -> Accepted.

## Must-fix resolution (6 items)

**1. Make R21/R21b and the stderr criterion agree, and mechanize the
exemption. RESOLVED.**

The prior defect was structural: R21 and R21a forbade discarding
absolutely while the acceptance criterion granted an exemption whose
second conjunct ("the fallback is not a masked failure") was the exact
judgment the `shirabe#279` author made and got wrong. Three things
changed and all three were needed.

R21a is gone, folded into R21, which now carries both halves of the
`#279` incident in one sentence -- "SHALL discard that tool's diagnostic
output or ignore its exit status" -- and carries the exemption on its
face: "except under R21b." The requirement is now satisfiable. I
measured the population it has to survive: 36 non-test discard sites
under `skills/`, including the four in `koto-templates/`. Under the old
absolute R21 roughly twenty of those would have had to be deleted; under
R21/R21b they are enumerable.

R21b replaces the undecidable conjunct with a records obligation: a
discarding site "SHALL then be recorded in a committed enumeration
naming the site and the exit status the fallback is entered on." The
criterion states the gate in the only form that admits no argument: "A
site that discards and is absent from the enumeration fails; no judgment
about whether the discard was reasonable is made at scan time." Scan
minus enumeration must be empty. That is a set difference, not an
opinion.

The exemption's residual judgment -- whether a *proposed entry* deserves
to be there -- is not hidden. R21b names it and assigns it: "adding one
is a reviewed edit rather than a judgment made silently at the call site
-- which is the judgment whoever wrote the `#279` site made and got
wrong." The mechanism converts a silent per-site judgment into a
reviewed committed diff. It does not claim to make bad judgment
impossible, and it does not pretend otherwise. That is the honest
version of this requirement and I accept it.

**2. Renumber R25a/R25b/R25c and move Verifiability. RESOLVED.**

Definition order is now strictly monotonic: R1 through R22a in place,
then R23, R24, R25, R26 under "Coverage and retirement," then R27 and
R28 under "Verifiability," which now sits after Coverage and retirement
(line 265). No requirement is defined before a lower-numbered one. R21b
and R22a survive as suffixed, which was the explicit instruction --
both genuinely extend their base requirement. The one criterion that
cited R25b now cites R28 (line 321): "Verified against R28's override,
not against a real `$HOME`."

**3. Unpin the line numbers in R25c and its criterion. RESOLVED.**

R26 (the renumbered R25c) names the file and the pattern:
"`skills/execute/koto-templates/execute.md` carries two occurrences of
`koto context get ... 2>/dev/null || echo ...`". Its criterion is
likewise pattern-shaped, with the count carried as a dated observation
rather than a pinned address: "Two such occurrences exist at the time of
writing." I confirmed the pattern still resolves to exactly two sites,
now at lines 390 and 409. Both are greppable and self-updating; neither
requirement nor criterion goes stale when the file is edited to
discharge them, which was the whole objection.

**4. Fix the orphaned package-manager criterion. RESOLVED.**

Restated in R19's outcome terms: "On a host where at least one install
route is available, the emitted command is one that runs successfully on
that host. Verified by executing the emitted command in the test
environment." The "delegates to that manager" clause -- a resolution
strategy no requirement mandates -- is gone. The criterion now verifies
R19 exactly, and verification is by execution rather than by inspecting
the command's shape. A design that resolves per-host without a package
manager now passes, as it should.

**5. Replace "remains usable." RESOLVED.**

Now: "the skill's first phase still executes afterwards. Observed by
running the skill and asserting the phase ran, not by judging
usability." R17's no-blocking guarantee is bound to an observable event.
The second sentence forecloses the reading that failed before.

**6. Separate the network and package-manager conditions. RESOLVED.**

The no-install-route criterion now says how the state is built: "The
condition is constructed by making every route the resolver would
consider unavailable; the test states which routes those are rather than
assuming network absence, which no fixture in this repo can currently
create." This is the right shape -- the resolver's route set is
design-determined, so the test enumerates it at implementation time
rather than the PRD guessing. Network absence is explicitly demoted from
test condition to motivating case, and R15 keeps it in that role ("a
sandboxed host that cannot reach the network being the case that
motivates this"). The unconstructible fixture is no longer required.

## Blocking defects found (if any)

None. The four specific checks requested:

**Numbering and cross-references.** Thirty requirement definitions:
R1-R28 contiguous, plus R21b and R22a, and no others suffixed. Every
requirement is covered by at least one acceptance criterion -- I walked
all thirty against the twenty-eight criteria and found no uncovered
requirement and no orphaned criterion. R26, R27, and R28 are covered by
criteria that do not cite them by number (the `koto context get`
criterion, the entry-point criterion, and the injected-root criterion
respectively), which is coverage by content and is fine. Every `R<n>`
token in the prose resolves to a requirement that says what the citing
text claims: I checked R3-from-R4, R4-from-Decisions, R9/R12/R17/R22
from Out of Scope, R10/R11 from the mode-scoping paragraph,
R13/R14/R15/R18/R19 from the actionable-instruction paragraph, R21-from-
R26, and R28-from-its-criterion. All hold.

**R21/R21b decidability.** I walked three real sites from the tree.

`git checkout impl/$PLAN_SLUG 2>/dev/null || git checkout -b
impl/$PLAN_SLUG` at `skills/execute/koto-templates/execute.md:339` --
the legitimate probe. It discards, so it fails the scan unless
enumerated; enumerated, it passes. The entry names the site and the
non-zero status git returns when the branch does not exist. No engineer
reaches a different verdict, and nobody has to argue about whether the
probe is *reasonable* to reach that verdict.

`koto context get {{SESSION_NAME}} settled_branch 2>/dev/null || echo
"impl/$PLAN_SLUG"` at lines 390 and 409 of the same file -- the bad one.
Worth being precise about what catches it, because the scan alone does
not: an implementer could enumerate these two sites and pass the
signal-integrity criterion. What catches them is R26 and its own
criterion, which name this file and this pattern and require the
occurrences gone. The document does not rely on the scan to make a
quality judgment it has explicitly disclaimed making. Two mechanisms,
each doing the job it can actually do.

`finding_count=$(jq -r '.findings | length' <<< "$output" 2>/dev/null)
|| finding_count=""` at `skills/execute/scripts/run-cascade.sh:193` --
the ambiguous one I picked, and it is genuinely ambiguous. jq is a
declared tool; the site discards diagnostics and substitutes a
fabricated value that flows onward, which is the `#279` shape. But the
surrounding comment shows the author expected non-envelope input, and
the empty-string fallback routes to "preserve the raw output," which is
real handling. Whether this deserves an enumeration entry is a question
two careful engineers could answer differently. Whether it passes the
criterion is not: it discards, so it is enumerated or it fails. The
ambiguity is confined to the reviewed edit, which is where R21b puts it
on purpose. That is the distinction the revision was asked to draw, and
it draws it.

The one weakening I noted and decided not to gate on: the prior review
asked for "the fallback path is entered only on an exit status the tool
documents," and R21b kept only "the exit status the fallback is entered
on." For a `||` construct an author can write "any non-zero" and satisfy
it. That lowers what an entry tells a reviewer; it does not make the
criterion undecidable, and the criterion's decidability was the defect.

**HOW leakage.** None introduced. R26 names a file and a shell pattern,
but as the current-state defect to be remediated -- which is what the
prior review itself prescribed in place of line numbers -- not as an
implementation instruction. R21's enumeration of discard spellings
scopes the prohibition rather than prescribing a scanner. R21b's `git
checkout` line is labelled as illustration ("is the shape this
permits"). R27 still says outright "This PRD does not say what that
entry point is," and R28 requires an override without naming what
overrides it. The struck package-manager clause did not reappear
anywhere.

**BRIEF-deferred questions.** All three close on the Decisions and
Trade-offs surface, checked against the BRIEF's Status section directly.
Absence versus skew versus subcommand surface closes under "What the
check verifies," with all three alternatives named and the version floor
eliminated on evidence rather than preference. Mode-conditional
dependencies chosen after load close under "Mode-scoped dependencies."
What makes an instruction actionable, including the no-install-route
case, closes under "What makes an instruction actionable," which names
the per-OS matrix, the generic line, and leaving no-route unhandled, and
gives the reason each lost. The opening claim "All three are answered
here" is true.

**Non-blocking observations, recorded and not gated.** R21b exists with
no R21a, since R21a was folded into R21 -- a naming artifact a reader
may pause on. The Declaration criterion still asserts "the five whose
declaration is empty" even though R23 no longer asserts the number
(prior nice-to-have 7, unchanged in force). R23's first sentence
restates R1's obligation. The split-policy criterion's closing clause,
"cited by name from the requirement it governs," is ambiguous about who
does the citing, since neither R3 nor R4 names an artifact. None of
these changes what an implementer builds or what a tester asserts.

## Validator output

```
$ shirabe validate --format json --visibility=public docs/prds/PRD-skill-preflight-checks.md
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "clean",
    "errors": 0,
    "notices": 0
  },
  "findings": [],
  "advisory": {
    "summary": "Draft posture: no draft-tolerable findings to flag.",
    "notes": []
  }
}
EXIT=0
```
