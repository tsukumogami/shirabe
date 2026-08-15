# Verdict: FAIL

Re-review of `docs/prds/PRD-skill-preflight-checks.md` (502 lines, Draft)
after revision. All three axes run serially by one reviewer. 30 of the 35
prior required changes landed correctly, 3 landed partially, 2 were not
made. The revision also introduced four defects of its own, one of which
is an outright internal contradiction. The document is materially better
than the version the jury failed; it is not yet passable.

## Prior-change verification (35 items, grouped by source verdict)

### Completeness (8 items) — 8 applied, 0 missed

1. **`schema: prd/v1`** — APPLIED. Line 2. Validator now runs the full
   structural check set and returns clean (see Validator output).
2. **Decisions entry for the BRIEF's third question** — APPLIED. "What
   makes an instruction actionable" (lines 446-460) states the chosen
   shape, names all three alternatives (per-OS matrix, generic line,
   no-route unhandled), and gives the reason each lost, including the
   36-40-cells-versus-eleven-strings maintenance argument. The opening
   claim "All three are answered here" is now true.
3. **Criteria for R16 and R20** — APPLIED. R16 gets the no-re-run-
   affordance criterion; R20 gets the Linux/`gh`/machine-readable-source
   criterion, which correctly also forces the exclusion out of the
   `.tsuku.toml` comment.
4. **Widen R21 and its criterion** — APPLIED in scope, but see
   Regressions R-1: R21 was widened to all discard routes and R21a added
   for exit status, while the criterion acquired an exemption the
   requirements do not grant.
5. **Reconcile the skill count** — APPLIED. R23 now derives it in one
   sentence: twenty skills, nine need nothing beyond a checkout, four of
   those nine call `shirabe transition` at finalize, five declare
   nothing. The "six of twenty" sentence is gone from Known Limitations.
   Independently confirmed: `skills/` holds exactly 20 directories.
6. **Carry the default-flip mitigation** — APPLIED, and well. R22a
   states the requirement, a Decisions paragraph records it as a settled
   position rather than an unknown, an acceptance criterion binds it at
   the `roadmap populate` call sites, and the Known Limitation is
   narrowed to what survives the mitigation (a call site that ignores
   R22a).
7. **Name `/charter` alongside `/scope`** — APPLIED in both R22 and the
   criterion. Verified the claim: `skills/charter/references/phases/
   phase-finalization.md:165-198` does invoke `shirabe validate --format
   json` and parse the `shirabe-validate/v1` envelope, so the second
   consumer is real and the requirement is correctly grounded.
8. **Close the smaller coverage gaps** — APPLIED, all five. R2 gets
   "adding an entry to one skill's declaration leaves every other
   skill's evaluated set unchanged"; R5 gets the by-inspection
   distinction; R11's deferral-visibility half gets its own criterion;
   R19 gets a positive-case criterion (but see R-3); and AC17's
   unstated "runs no probe" clause was dropped rather than promoted.

### Clarity and altitude (14 items) — 12 applied, 2 partial

1. **Remove the `wip/` reference** — APPLIED. The Decisions section now
   cites `docs/decisions/DECISION-skill-preflight-verification-depth-
   2026-08-14.md`, which exists. Grepped the document: no `wip/` path,
   and no bare `decision_skill-preflight-verification_*` glob, survives.
   The workspace-wide wip-hygiene rule is satisfied.
2. **Fix the R9 criterion** — APPLIED. Subject and scope now agree
   ("nothing the check executes and nothing it emits"), the verb is
   aligned to R9 (comparison or gating, not reference), and the two
   permitted cases the old criterion wrongly banned — a `--version`
   liveness probe and a pinned install URL — are named as permitted.
3. **Reconcile R3 with its criterion** — APPLIED. The criterion is now
   mechanical ("every flag appearing in a `shirabe` or `koto` command
   line in that skill's own phases"), which is exactly R3's "depends on"
   reading made testable. The "branches on" wording is gone.
4. **Make R7 and R8 agree** — APPLIED. R8's added sentence settles it
   for both: "what the installed tool says it offers, not what it
   accepts when actually run."
5. **State R11's scope** — APPLIED. "This PRD requires that
   verification, not merely a declaration that marks it deferred."
   Reading A chosen explicitly.
6. **Align R21 with its criterion** — APPLIED in direction, broken in
   execution. See R-1.
7. **Lower R19 to outcome altitude** — APPLIED. Both offending clauses
   are gone. Two residues: R19's first sentence now near-duplicates
   R14's "exactly one command that will work on the host it is running
   on" (only the second sentence adds anything), and the deleted design
   content reappeared one section down in an acceptance criterion (R-3).
8. **Cut the subprocess cost claim** — PARTIALLY APPLIED. "One
   subprocess per declared subcommand" is gone, but the bullet now
   carries "a worst case of 6-9 calls for `/work-on`, under 100ms."
   The arithmetic survived; what changed is that it is attributed to the
   decision record and explicitly disclaimed ("an input to design, not a
   budget this PRD sets, and it assumes a probing strategy the DESIGN is
   free to change"). The disclaimer now does its job honestly, so I am
   recording this as acceptable rather than blocking.
9. **Replace "the check's probes" with verifying language** — PARTIALLY
   APPLIED. R21 and R21a now say "no verification performed by the
   check." Known Limitations still opens a bullet with "Surface
   probing," and the signal-integrity criterion says "Probes where a
   non-zero exit..." The original finding was marked soft; it stays
   soft. Nice-to-have.
10. **Fix the R24 citation** — APPLIED. The claim that R24 keeps
    declarations honest is gone; the replacement bullet says plainly
    that nothing mechanically proves a declaration complete and names
    the flag-extraction criterion as the closest available check,
    including its limit (only the two first-party tools).
11. **Name the survey or drop the universal claims** — APPLIED. Nine
    tools now named on both sides — `flutter doctor`, `nix doctor`,
    `brew doctor`, `rustup check`, `pre-commit` against direnv's `has`,
    npm `engines`, Cargo's `rust-version`, `go.mod` toolchains — and
    "every"/"none" softened to "of the tools surveyed during
    exploration."
12. **Delete Known Limitations bullet 1** — APPLIED. The restatement is
    gone. The replacement bullet is not a duplicate: it adds that a call
    site ignoring R22a is exposed and unpoliced, which appears nowhere
    else.
13. **Reword user stories 5 and 2** — APPLIED. Story 2 now promises
    information ("so that the choice to proceed or stop is one I make
    knowingly") rather than an outcome R17 leaves to the agent. Story 5
    is stated from the author's side. Story 5's "see no trace of this
    feature at all" is still a shade closer to the solution than the
    reviewer's suggested phrasing; not worth a gate.
14. **Negative criterion for R1** — APPLIED (this was the optional one).
    "A skill carrying no declaration is distinguishable from one
    carrying an empty declaration: presenting both to whatever reads
    declarations produces different results." R1's rationale is now
    tested, and the phrasing avoids naming the reader.

### Testability (13 items) — 10 applied, 1 partial, 2 not applied

1. **Name the discriminator and the consumer** — APPLIED with residue.
   The criterion now requires a *named* discriminator plus routing
   assertions for both inputs against both consumers. The PRD does not
   itself name the discriminator, which is correct at this altitude
   (naming it would pick between the three incompatible designs the
   reviewer listed). The no-op-passes problem is fixed by the routing
   half: `/charter`'s finalization branch does not today route a usage
   error to a tool-error outcome, so the unchanged system fails.
2. **State the path set, pattern, and verb for R9's criterion** —
   APPLIED. Path set is "the enumerated set of files the DESIGN names as
   the check's implementation," which is the glob-the-DESIGN-populates
   shape the reviewer allowed. No regex is given; acceptable given the
   verb is now precise.
3. **Make zero bytes measurable** — APPLIED, cleanly. R25a adds the
   single-invocable-entry-point requirement without prescribing what it
   is, the criterion names the stream ("stdout and stderr combined") and
   the measurement (`wc -c` over a combined capture), and it carries the
   live counterexample forward. Confirmed: `skills/execute/scripts/
   preflight.sh:28` still prints `execute preflight OK: ...`, so the
   criterion does bite on shipped code.
4. **Scope the grep or accept the cost** — APPLIED in scope, broken by
   the exemption. See R-1. The scoping itself is good and I measured it:
   restricting to non-test files takes the population from 109 to 27.
5. **Make the tsuku state creatable** — APPLIED. R25b requires an
   overridable filesystem root and the criterion says "verified against
   R25b's override, not against a real `$HOME`." This was the one gap
   the reviewer said forced a requirement change; the requirement was
   added rather than the criterion fudged.
6. **Remove AC2's judgment clause** — APPLIED. Now a mechanical extract-
   and-compare.
7. **Name the string in the `/execute` criterion** — APPLIED. The exact
   claim is quoted. Confirmed live at `skills/execute/SKILL.md:272`.
8. **Name the document for the split policy** — PARTIAL. "A durable
   document under `docs/`" is a class of artifact, which is the weaker
   of the two options the reviewer offered, and "with its rationale"
   remains a quality judgment. A tester still has to grep `docs/` and
   decide whether what they find counts. Nice-to-have.
9. **Add criteria for R16, R19, R20, R2** — APPLIED, all four. R19's
   introduces a new problem (R-3).
10. **Drop "runs no probe"** — APPLIED. The criterion is now "a skill
    whose declaration is empty produces no report."
11. **Pin the five or drop the number** — PARTIAL. R23 now derives the
    five rather than asserting them, which is a real improvement, but
    neither R23 nor the criterion enumerates which five. A tester counts
    empty declarations and asserts 5; an implementation that empties the
    wrong five passes. The flag-extraction criterion catches a wrongly-
    empty declaration only for `shirabe` and `koto`, not for `gh`,
    `jq`, `git`, or `python3`. Nice-to-have, but the residual hole is
    real.
12. **Replace "remains usable"** — **NOT APPLIED.** The criterion still
    reads "the skill still loads and remains usable." Unchanged from the
    failed revision. R17 is still bound to nothing mechanical.
13. **Separate the network and package-manager conditions** — **NOT
    APPLIED.** The criterion still reads "On a host with no network and
    no package manager." Unchanged. Which condition drives the no-route
    report is still unstated, and network absence still has no fixture
    precedent anywhere in the repo.

## Completeness

Seven required sections present and in canonical relative order: Status
(29), Problem Statement (33), Goals (72), User Stories (85),
Requirements (108), Acceptance Criteria (270), Out of Scope (490).
Decisions and Trade-offs (377) and Known Limitations (470) interleave
before Out of Scope, which the validator accepts.

Frontmatter is valid and complete: `schema: prd/v1`, `status: Draft`
matching the body, `problem`, `goals`, `upstream` resolving to an
Accepted BRIEF, and a legitimate `motivating_context`.

All three BRIEF-deferred questions now close as recorded decisions.
Checked against the BRIEF's Status section directly: (a) what the check
targets — closed under "What the check verifies" with alternatives and
the evidence for eliminating the floor; (b) how a declaration expresses
a mode-conditional dependency chosen after load — closed under
"Mode-scoped dependencies"; (c) what makes an instruction actionable
including the no-install-route case — now closed, which was the gap.

Requirement/criterion coverage is now near-total. 30 requirements, 27
criteria. Every requirement has at least one covering criterion. One
criterion is orphaned (R-3 below). Nothing material from the decision
record is dropped: the elimination evidence, the #278 argument, the
mode-scoping position, the silence-on-success prior art, and the
default-flip blind spot with its mitigation are all carried.

Two lower-severity omissions the earlier verdict recorded without
gating remain unaddressed and I again do not gate on them: the
`DESIGN-shirabe-pattern-v1-ergonomics` Decision 6 prior position (the
PRD argues past #278 only), and `/inflight`'s undeclared `shirabe
work-summary render`, which is the same class of defect R25 fixes for
`/execute`.

## Clarity and altitude

The altitude discipline held through the revision, and the revision
improved it. No requirement names a file format, serialization,
frontmatter key, load mechanism, code home, or shell-versus-binary
choice. R25a is the closest call and it is correctly written: it
requires that a single capturable entry point exist and says outright
"This PRD does not say what that entry point is." R25b requires an
override without saying what overrides it. R19's design content is
gone.

The one altitude leak the revision created is that R19's deleted
mechanism reappeared in an acceptance criterion (R-3).

Numbering is the clarity problem. All of R1-R25 plus R21a, R22a, and
R25a-c appear exactly once, and every `R<n>` token in the document
resolves. But the definition order is R1...R22a, then **R25a, R25b,
R25c**, then **R23, R24, R25**. The reader meets R25a sixteen lines
before R25.

On whether suffixed numbering is acceptable: it depends on whether the
suffix denotes subordination, and here it does in two cases and not in
three. R21a genuinely extends R21 (stderr and exit status are the two
halves of the same incident, and R21a says so). R22a genuinely extends
R22 (both concern signal integrity of a tool's own contract). Those two
are fine and I would keep them — renumbering them would break the
readable pairing. R25a, R25b, and R25c have nothing to do with R25,
which is about `/execute`'s false `gh` auth claim. They are
verifiability affordances, a distinct concern with its own section
heading. The suffix asserts a relationship that does not exist and
forces the out-of-order placement. They should be renumbered R26, R27,
R28, with the Verifiability section moved after Coverage and
retirement.

Writing style passes. No term from the rule source appears (`tier`,
`journey`, `underscore` excluded per instruction and absent anyway). Em
dash count is zero; the document uses `--` throughout. The Problem
Statement still proposes nothing, which remains the strongest part of
the document. The new Decisions paragraphs match the surrounding
register.

## Testability

The rewritten Acceptance Criteria section is a large improvement. The
new preamble naming `preflight_test.sh`'s `mktemp -d` fake roots,
`run-cascade_test.sh`'s `SHIRABE_BIN` and PATH injection, and the
`koto` 127-shim gives a tester the three fixture shapes the criteria
need, and I confirmed all three exist as described. The five subheading
groups map onto the requirement groups, which makes the coverage
mapping checkable by eye rather than by table.

**Zero-bytes measurement: now testable.** Entry point required by R25a,
stream named ("stdout and stderr combined"), measurement named (`wc -c`
over a combined capture), and the shipped counterexample named. Two
engineers will now reach the same verdict. This one is fixed.

**The named-discriminator criterion: testable, with one soft spot.**
"Distinguishable by a named discriminator" is self-referential — it
requires that the design name something without saying what — but the
criterion does not rest on that clause. The routing assertions carry
it: both inputs, both consumers, four assertions. A tester handed the
finished work reads the design's named discriminator and runs the four.
The no-op no longer passes, because `/charter` does not route usage
errors to a tool-error outcome today. Acceptable.

**The stderr scan: not testable as written, and it contradicts its own
requirements.** Full analysis in R-1.

**Constructibility of the rest.** Sealed-PATH fixtures cover the
removed-tool, missing-subcommand, missing-flag, and package-manager
cases. R25b's override makes the tsuku case constructible. Two states
remain unconstructible, both because the two unapplied testability
changes were not made: network absence (the no-install-route criterion)
and "remains usable" (the removed-from-PATH criterion). The mode-scoped
criterion's second half — "selecting multi-pr mode produces one" —
still needs an agent-eval harness; `skills/plan/evals/` holds
`evals.json` and no `fixtures/`. That was a WEAK rather than a required
change and I record it without gating, but R11's new "this PRD requires
that verification" makes it heavier than it was.

## Regressions introduced by the revision

**R-1. The stderr exemption is laxer than the requirements it verifies,
and its second conjunct is the judgment call the criterion existed to
remove.** The criterion exempts "probes where a non-zero exit is the
expected, handled outcome and the fallback is not a masked failure."
R21 and R21a grant no exemption at all — they are absolute ("No
verification performed by the check, and no skill call site, SHALL
discard a tool's diagnostic output"). So the document now says two
different things, and the requirement is the unsatisfiable one.

The measurements make this concrete rather than theoretical. Under the
criterion's own scoping — non-test files, tools named in a declaration —
27 sites exist today, not the 109 under `skills/` overall. Roughly
twenty of the 27 need the exemption to survive: `git checkout
impl/$SLUG 2>/dev/null || git checkout -b impl/$SLUG` at
`skills/execute/koto-templates/execute.md:339`, `git add "$target"
2>/dev/null || true` at three sites in `run-cascade.sh`, `git describe
--tags 2>/dev/null || echo ""` in `skills/release/SKILL.md:33`, `find
docs -name "DESIGN-*.md" 2>/dev/null || true`, and the `grep -q` probes
on optional files. Nobody is going to delete those, and R21 as written
requires it. The exemption is therefore load-bearing for the majority
of the population, not an edge case.

The first conjunct is decidable — "a non-zero exit is the expected,
handled outcome" can be pinned to a documented exit status. The second
is not. "The fallback is not a masked failure" is precisely the
judgment whoever wrote the `koto context set` call site in
`shirabe#279` made, and got wrong. The live cases that turn on it are
real: `finding_count=$(jq -r '.findings | length' <<< "$output"
2>/dev/null) || finding_count=0` appears twice in `run-cascade.sh`
(193, 243), with two more at 213 and 252 and one at 838 — jq parse
failures silently defaulting, in the exact `#279` shape.

The saving grace is "and enumerated," which does make the *gate*
mechanical: scan minus enumerated list must be empty. But the
enumeration's contents are unreviewed judgment, and the criterion gives
a reviewer no test to apply to a proposed entry. Fix in two moves:
carry the exemption into R21 and R21a so the requirements are
satisfiable, and replace "the fallback is not a masked failure" with a
decidable condition — the fallback path is entered only on an exit
status the tool documents, and the enumeration is a committed artifact
in which each entry names that status.

**R-2. R25c and its criterion pin line numbers, in two places.** Both
name `skills/execute/koto-templates/execute.md` lines 390 and 409. I
verified them: both are `SETTLED_BRANCH=$(koto context get
{{SESSION_NAME}} settled_branch 2>/dev/null || echo "impl/$PLAN_SLUG")`.
Correct today.

Pinning them is still unwise, and this is not a general objection to
citing line numbers — the Problem Statement's evidence citations are
fine, because evidence describes a past state. A *requirement* is a
future obligation, and this one will be discharged by editing the file
it cites. Anything inserted above line 390 during the same PR moves
both. The requirement then reads false while the work it demands is
being done correctly, and a reviewer looking at a mismatch cannot tell
"already fixed" from "wrong lines." Two places go stale, not one. Name
the file and the pattern instead: the `koto context get ... 2>/dev/null
|| echo` occurrences in `skills/execute/koto-templates/execute.md`,
both of them. That is greppable, stable, and self-updating.

**R-3. R19's design content moved from the requirement into an
acceptance criterion.** "On a host with a package manager present, the
emitted command delegates to that manager" is the clause the clarity
reviewer had struck from R19 as HOW. R19 now says only that an emitted
command must succeed on the host and must not be emitted without
established availability. So the criterion verifies a resolution
strategy no requirement mandates — an orphan criterion by the
completeness axis and a relocated altitude leak by the clarity axis, at
once. A design that resolves per-host without a package manager
satisfies every requirement and fails this criterion. Restate the
criterion in R19's terms: on a host where a working install route
exists, the emitted command runs successfully on that host.

**R-4. The Verifiability section sits between Signal integrity and
Coverage and retirement, breaking requirement order.** Covered under
Clarity above; listed here because it is new in this revision.

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

The `schema field missing, skipping` notice from the prior review is
gone. The document is now actually being checked, and it is clean.

## Remaining required changes

### Must fix

1. **Make R21/R21a and the stderr criterion agree, and mechanize the
   exemption.** Carry the exemption into R21 and R21a — as written they
   forbid roughly twenty legitimate existing sites and R25c names only
   two of them, so the requirements are unsatisfiable. Then replace
   "the fallback is not a masked failure" with a decidable test: the
   fallback is entered only on an exit status the tool documents, and
   each enumerated entry names that status in a committed artifact. Any
   in-scope site absent from the enumeration fails.

2. **Renumber R25a/R25b/R25c to R26/R27/R28 and move the Verifiability
   section after Coverage and retirement.** The suffix asserts
   subordination to R25 that does not exist, and it currently forces
   R25a-c to be defined before R23. Keep R21a and R22a as suffixed —
   those two genuinely extend their base requirements and the pairing
   is worth preserving. Update the one criterion citing R25b.

3. **Unpin the line numbers in R25c and its criterion.** They are
   correct today (both verified) but the requirement will be discharged
   by editing that same file. Name the file and the `koto context get
   ... 2>/dev/null || echo` pattern, both occurrences.

4. **Fix the orphaned package-manager criterion.** Either restate it in
   R19's outcome terms (a host with a working install route gets a
   command that runs on it) or restore an outcome-level requirement it
   verifies. As it stands it tests a strategy the revision deliberately
   removed from the requirements.

5. **Replace "remains usable" (testability change 12, not applied).**
   Bind R17 to something a shell test observes: the check's exit status
   does not halt the skill, or the skill's first phase still executes
   after an unsatisfied report.

6. **Separate the network and package-manager conditions (testability
   change 13, not applied).** Say which condition triggers the
   no-install-route report. Network absence has no fixture precedent in
   this repo; if it is genuinely required, say how a tester creates it.

### Nice to have

7. Enumerate the five empty-declaration skills, or restate the
   criterion as "every skill requiring no host tool carries an
   explicitly empty declaration" so no magic number is asserted.

8. Name the artifact for the split policy rather than "a durable
   document under `docs/`," and drop or operationalize "with its
   rationale."

9. Normalize the remaining mechanism vocabulary: "Surface probing" in
   Known Limitations and "Probes where..." in the signal-integrity
   criterion, now that R21 and R21a use verifying language.

10. R19's first sentence near-duplicates R14. Either fold it into R14 or
    keep only R19's second sentence, which is the part that adds
    something.
