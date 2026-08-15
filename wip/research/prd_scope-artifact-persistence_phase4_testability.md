# Testability review — PRD-scope-artifact-persistence

## Round 3 verdict (final)

PASS

B1 is properly fixed, all seven finish-work findings are addressed, and both
halves of the R26/R27 pushback landed with the right reasoning attached. 36
criteria, each naming an instrument, across a three-tag taxonomy that holds.
Two tag inconsistencies and one stale schema comment remain; all are one-line
fixes that do not affect whether anything is verifiable, and none should hold
the document.

---

## B1 — resolved

R16 now reads "SHALL fail when an `R<n>` requirement citation whose target
document this run absorbed resolves neither within the surviving document nor
within its spliced upstream," and carries the exposure in its own body: 77
documents, the PRD-citing-R-numbers class, the `Done` BRIEF citing another
chain's PRD by path. The scoping lives in the requirement rather than in an Out
of Scope line, which is what a DESIGN will read. R28's guarantee holds by
construction: the check cannot fire on a document this run did not absorb, so
the corpus walk and `git diff --exit-code docs/` are jointly satisfiable with
it.

## Finish-work — all resolved

- **N1.** Band stated at 10%. The judgment-dependent clause moved into the
  [judg] criterion as fixture construction, where it is an instruction rather
  than a check. The [mech] criterion now asserts only structural equalities,
  all of which a machine decides.
- **N2.** **[insp]** added as a third tag with a definition that names why it
  exists ("prose with no machine-readable enumeration to diff against"). The
  write-target criterion carries it, and its body explains the method rather
  than asserting it.
- **N3.** All five gaps closed: R3 ([insp]), R5 ([mech], and correctly so —
  see below), R13 ([insp]), R14's transitive itemization ([mech]), R29's first
  decision point ([judg]).
- **N4.** Known Limitation added. "That is an argument, not a test" is the
  right last sentence — it states the proxy and refuses to let it read as
  coverage.
- **N5.** Both criteria name their four and three targets. Excluding BRIEF
  from the content-boundary one, with the reason, is a correctness improvement
  I had not asked for and did not spot.
- **N6.** The preamble separates the two eval cases and notes the `/execute`
  one can be graded against an executed run.
- **N7.** Reworded to what the instrument can observe.
- **R27.** Criterion added, naming scenario 17 and carrying the regression
  argument rather than a completeness one.
- **R26.** Write-target criterion extended with the abort-or-absorb clause and
  an explanatory sentence naming the second-deletion-site risk.

---

## Answer to the R14 tagging question

**No, it is not the same error as N1, and the tag is better grounded than the
question assumes.**

The distinction. N1's criterion required *evaluating* the judgment property —
deciding whether an alternative is live is the reading the paired eval exists
to perform, so asserting it mechanically claimed a machine could do the
agent's job. R14's criterion never evaluates whether a contribution carried. It
takes each row's verdict as an input and checks the structure around it: that
three rows exist, and that one false row aborts. Plumbing, not water. That is a
legitimate and valuable [mech] check, and it is the strongest thing anyone can
assert about a transitive carry without grading content.

It is also concretely implementable today, which the question does not claim.
`skills/scope/references/state-schema.md:67-88` already defines
`consolidation_judgments[].carry_check` as a structured YAML map:

```yaml
carry_check:
  <upstream section>: {target: <downstream section>, carried: <bool>}
```

One key per section, each with a boolean. Counting rows and asserting the
abort on a false value is a parse-and-assert over that map, not a reading. R14
extends the same map with contribution rows — same shape, same instrument. Keep
[mech].

One constraint the DESIGN must honour for the tag to stay true: the state file
is scratch. It lives in `wip/`, is removed at Phase 4, and is projected into
the PR body first (`state-schema.md:158-161`). A [mech] check over
`carry_check` must run while the state file exists, or against the PR-body
projection. If the DESIGN instead lets the carry table become prose the agent
writes, the tag silently degrades to [insp] — worth a sentence in the DESIGN so
that does not happen by accident.

---

## Remaining nits, none blocking

### The [mech]/[insp] line is drawn inconsistently across three prose-file criteria

Three criteria check "does this prose file say X" and carry two different tags:

- **[insp]** "Each of the BRIEF, PRD, DESIGN and PLAN format references names
  exactly one contribution for its type."
- **[mech]** "The contribution-section contract in each of the BRIEF, PRD,
  DESIGN and PLAN format references states both the too-long and the too-thin
  failure."
- **[mech]** "`/work-on`'s implementation phase file carries the rationale
  instruction, and the maintainer reviewer's brief names it as a blocking
  finding."

The first and second are the same kind of check on the same four files with
opposite tags. The principled line, matching the preamble's own definitions:
[mech] when a fixed string can be grepped or a structured enumeration diffed;
[insp] when it requires judging whether prose expresses a concept. By that
line, "states both the too-long and the too-thin failure" is [insp] (judging
that prose expresses two ideas), and "carries the rationale instruction" is
[insp] unless the instruction text is pinned to a fixed string.

R5's heading criterion is correctly [mech] by the same test and worth keeping:
the validator must encode the heading strings to implement R8 and R9, so there
is a machine-readable enumeration — the validator's constants — to diff the
format reference against. That is a real test, not a reading.

Retagging two criteria costs two words. The taxonomy is this draft's central
structural claim, and it is 34-of-36 consistent; closing the last two makes it
whole.

### The state schema still documents the model R1 deletes

`skills/scope/references/state-schema.md:75` defines the field as:

```yaml
absorbable: true           # is the required-section mapping total?
```

That comment is the type-level mapping question R1 abolishes, sitting in the
machine-readable contract that R14's [mech] criteria parse. R24 requires the
eval scenarios to stop referencing a type-level mapping check but names no
other surface, so nothing in the criteria set reaches this file. A fixture
built against the current schema would encode the deleted model in the field
the criteria depend on.

Cheapest fix is a clause on R24 — "and `/scope`'s state schema records the
judgment's inputs in terms R1 permits" — rather than a new requirement.

---

## Verified across the three rounds

Empirical checks run against this worktree rather than taken on the document's
word:

- **77 format-prefixed documents** cite an `R<n>` they do not define, including
  `PRD-shirabe-scope-skill.md` (22, with a BRIEF upstream that carries no
  requirement numbers) and `BRIEF-lifecycle-passing-state-validation.md:177`,
  a `Done` BRIEF citing `docs/prds/PRD-roadmap-plan-standardization.md` (R17
  and R18) by path. This is what made B1 undeniable and is now cited in R16.
- **The 18/19/20 list is complete.** All 26 scenarios in
  `skills/scope/evals/evals.json` scanned for type-level-mapping language;
  exactly three match. Naming the three is equivalent to R24's property, not
  weaker than it.
- **Scenario 17 survives this work unchanged** — no type-level mapping
  language, which is why it is correctly absent from the rewrite list and
  available as R27's tripwire.
- **"Re-entry protection" is a precise term** with a `chain_skipped:` state
  field, defined across `state-schema.md:47-57`, `phase-1-discovery.md:6` and
  `phase-2-chain-orchestration.md:525-533`.
- **The cascade criterion's failure claim is accurate.**
  `skills/execute/scripts/run-cascade.sh:439-457`: `design_ref` is `""` when
  `CASCADE_DESIGN_PATH` is unset and the awk branch falls to bare `print`,
  leaving the pre-existing `**Downstream:**` line untouched.
- **`carry_check` is already structured YAML**, which is what grounds R14's
  [mech] tag.
- **`docs/guides/` is not corpus-walk exposure** — no format-prefixed
  basename, so the validator skips those files.

## Closing note

The document that arrived in round 1 had nine of twenty-two requirements
uncovered, a central criterion that asserted a post-`/execute` state at the end
of a `/scope` run, and no statement anywhere of what instrument would decide
anything. What it is now names an instrument per criterion across three
honestly-defined tags, admits in Known Limitations that its central behaviour
is graded rather than gated and that its cross-repo regression half is an
argument rather than a test, and carries empirical corpus measurements inside
the requirements that depend on them.

The remaining nits are finish-work for the DESIGN to absorb, not gaps in the
contract.
