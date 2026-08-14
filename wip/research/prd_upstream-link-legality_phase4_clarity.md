# Clarity Verdict — PRD-upstream-link-legality

**Verdict:** PASS

Both blocking items from the previous round are genuinely resolved, not papered
over. R14 assigns the roadmap link as a numbered requirement and R11's new escape
clause stops pointing away from it; R20 decides rather than defers, and the
contradiction with R24 and the acceptance criteria is gone. The trims to R8 and
R4 did not over-correct — both are still testable requirements with acceptance
criteria behind them. What remains is one notation collision and four small
nits, none of which would produce a wrong implementation.

## Validator output

```
$ ./target/debug/shirabe validate docs/prds/PRD-upstream-link-legality.md --visibility=public
$ echo $?
0
```

No findings, exit 0. Confirmed the binary exercises its checks: a stub PRD with
`schema: prd/v1` and a missing body returns eight findings (`FC01` x2, `FC04`
x6) and exit 2.

## Structure

Pass, re-checked on the assembled file.

Required sections all present and in canonical order: Status (26), Problem
Statement (30), Goals (69), User Stories (88), Requirements (112), Acceptance
Criteria (313), Out of Scope (516). The two optional sections — Decisions and
Trade-offs (361), Known Limitations (484) — sit between Acceptance Criteria and
Out of Scope, which preserves the required sections' relative order and so is
legal under FC15. The validator agrees.

FC03: line 28's first non-blank content under `## Status` is the bare word
`Draft`, matching frontmatter `status: Draft`. Frontmatter carries `schema:
prd/v1`, `status`, `problem`, `goals`, plus the legal optionals `upstream` and
`motivating_context`, each a single paragraph in a literal block scalar. No
`wip/` path in frontmatter.

**Numbering reads cleanly.** R1 through R25 are contiguous with no gaps and no
reuse. The four sub-numbers each attach to the requirement they qualify —
R5.1/R5.2/R5.3 elaborate R5's table, R16.1 carves an exception-that-isn't out of
R16 — and none of them is load-bearing in a way that would have been clearer as
a top-level number.

**No stale references.** Every `R<n>` citation in the body resolves to an
existing requirement: R5.2→R4, R5.3→R5.1, R14→R19, R16.1→R16/R13, R17→R7,
R19→R14, R22→R13/R14/R18, R23→R18/R24, R24→R5, Known Limitations→R25/R24/R13,
Out of Scope→R24/R10/R14/R8, Decisions→R5/R6/R7/R24. I checked all 60 occurrences
against the 29 definitions; nothing points at a number that moved.

## Over-correction check on R8 and R4

Asked for explicitly. Neither is too thin.

**R4** now reads: "No Durable type may declare a Working type in its legal parent
set. A maintainer who writes such a declaration finds out before it can reach the
corpus." The rule is stated exactly and is binary. The second sentence sets an
outcome without prescribing the mechanism, which is the right altitude, and the
mechanism it used to prescribe now lives where it belongs — in the acceptance
criterion "A test asserts that no Durable type declares a Working type among its
legal parents, and fails when one is added." R4 also does more work than before:
R5.2 now leans on it to justify three changed table rows, so it has become the
load-bearing rule rather than a side constraint. Still a requirement.

**R8** now reads: "Legality is decided from the naming document's format and the
target's basename alone. Nothing about the check causes `docs/visions/` or
`docs/strategies/` to be indexed, so no VISION or STRATEGY is drawn into the
orphan rule, which was never written for them." The first sentence is the
definitional input, not an implementation choice — it is what makes R9's "matches
no known artifact prefix" coherent and what the basename paragraph in Known
Limitations is a consequence of. The second states an observable outcome and now
says *why* it matters, which the old version left implicit. Verification is
indirect but real: if visions or strategies were drawn in, they would acquire
orphan findings and trip the "no other document under `docs/` changes its
findings" criterion. Requirement intact, and better than before.

## Content boundaries

Clean enough to pass. The four crossings from the previous round are gone: R8
lost the mechanism prohibition, R4 lost the timing-and-test-suite clause, old R14
is now R16 stated as observable behaviour ("A skill records the same `upstream:`
value when invoked standalone as it does when a parent skill invoked it"), and
the cascade decision keeps the lifetime argument while dropping the call-site
detail, the walking-machinery paragraph, and the shell-script clause.

Three small things sit on the line. None demands a change.

**One acceptance criterion names an internal Rust symbol.**

> "`is_known_check_code` gains exactly the two new codes, and no format's
> required-section list changes."

This is a function name from the validator crate. An acceptance criterion may
name a test, but naming an internal symbol pins the implementation's shape, and
the criterion two lines above already covers the same ground from the outside:
"Both new check codes are selectable with `shirabe validate --check <CODE>`, and
the message listing valid codes names them." The second half of the
`is_known_check_code` criterion (no required-section list changes) is worth
keeping; the first half is redundant with the user-facing one.

**R12's last sentence is acceptance-criterion content in a requirement.**

> "The announcement is graded by the skill's eval suite rather than by a string
> match, which is how the five skills that already carry this obligation are
> graded."

This specifies the verification mechanism. It is defensible — it heads off a
brittle string-match implementation of an announcement obligation, which is a
real risk — but it is describing how the requirement gets checked, and the
matching acceptance criterion already says "Its eval suite grades that... the run
announced the omission and its reason."

**R16.1 describes control flow.** "It rewrites a surviving PRD's `upstream:`
after both children have returned and one document has been removed" narrates
`/scope`'s internal sequencing. It is describing existing behaviour in order to
argue it is not an exception to R16, which is legitimate scoping work, but the
argument would survive without the ordering detail.

Nothing else crosses. No code examples, no API specifications, no security
analysis, no competitive content. R5's table, R22's eval table, and R24's
document table are all change manifests — the same category, and all three belong.

## Ambiguity

**Resolved: the roadmap link now has a requirement.** R14 states it directly —
"Where a tactical chain runs under a roadmap, the produced PLAN records that
ROADMAP among its `upstream:` entries" — R11 now ends "except where a requirement
below says otherwise" so it no longer points an implementer away from the change,
R19 explicitly says R14 supplies the link it walks, and the acceptance criterion
names the field rather than gesturing at reachability: "the produced PLAN carries
the roadmap among its `upstream:` entries." R14's premise checks out: `/brief`,
`/prd`, `/roadmap`, `/strategy`, and `/comp` do each carry `--upstream` today and
`/plan` does not, so "the same flag five siblings already carry" is accurate. The
slug clause is covered by its own criterion.

**Resolved: R20 decides.** The outcome is preserved — exemption, behaviour, and
tests stay; nothing in the corpus depends on it; no document's validation result
changes. That is consistent with R24's list staying exact and with the criterion
"no other document under `docs/` changes its findings." R20 has its own criterion
and a Known Limitations paragraph covering the notice a lone brief carries. The
contradiction is gone.

**Also resolved, without my raising it: the R21/R22 split.** The previous draft's
unqualified "No existing test is modified" sat badly against a change that
obviously required eval updates. R21 is now scoped to `cargo test --workspace`
plus golden-corpus fixtures, and R22 names the four eval expectations that change
with their dispositions. That was a latent conflict and it is fixed.

**One remaining ambiguity: `R6` means two different things in this document.**

Shirabe already ships check codes `R6`, `R7`, `R8`, and `R9` — `R6` is the
upstream resolution check, and `R7`/`R8`/`R9` are the public-repo visibility
checks (`shirabe validate --help`: "Codes are the per-file checks: `SCHEMA`,
`FC01`-`FC13`, `FC-CONVENTIONS`, `R6`-`R9`"). The PRD numbers its requirements
R1-R25, so the tokens collide.

The collision is live in R24's table, which is the document's most load-bearing
artifact. Its **Today** column reads "R6 error" for five rows — that can only
mean the existing *check code*, since requirement R6 does not exist yet. But
sixty lines earlier, "**R6.** `shirabe validate` reports an error-severity
finding..." defines requirement R6, and Decisions says a rule "is enforced by R5
and R6," meaning the requirement. Same token, two referents, and one acceptance
criterion depends on the table verbatim: "The eight documents named in R24
produce exactly the findings R24 predicts."

I did not flag this last round and should have — it was present in the original
draft too. It is recoverable in every instance from context, which is why it does
not block: nobody implementing this from the shirabe codebase will mis-read the
Today column. But a reader coming to R24 cold has to work it out, and the
document never acknowledges the overlap. A footnote under R24 saying the Today
column's `R6` is the existing resolution check code, distinct from requirement
R6, would close it. Renumbering is not worth it.

A related non-defect worth noting so it is not mistaken for one: R7 requires
"two distinct check codes" without naming them, and codes R6-R9 are already
taken. Leaving the names to the design is correct — the acceptance criterion
verifies selectability regardless of what they are called.

**Minor: a count that reads as inconsistent.** The Problem Statement and
Decisions both say "Nine places in the skill corpus state that rule"; R12 says
"the five skills that already carry this obligation." Nine statements across five
skills is a perfectly good reading, but nothing in the document says so.

**Minor: R23's exemption is redundant.** It exempts two eval fixtures from
"R24's no-other-changes clause," but R24 is scoped to documents "under `docs/`"
and both fixtures live under `skills/execute/evals/fixtures/`. They were never in
R24's scope. Harmless, but it invites a reader to re-check R24's scope.

Everything else in R1-R25 is unambiguous. R5.2 is a notable improvement — the
previous draft claimed R5 "encodes rather than changes" the settled rule, which
was false for three rows; the revision now states plainly that three rows change
what `pipeline-model.md` and `prd-format.md` document, derives each from R4, and
commits to updating the references. That correction was not on my list and it
mattered. R15 is new and catches a real defect: `/explore`'s phase-5 reference
does instruct passing a VISION path as `--upstream` to `/roadmap`, which R5's
table forbids.

## Citation vs Restatement

Unchanged from the previous round and still fine.

User Stories carry the brief's four journeys forward into the PRD's own required
section, in story form, plus a fifth that is new to the PRD — carrying forward,
not summarizing alongside. The Problem Statement is an independent retelling,
which the format requires. Out of Scope still overlaps the brief's OUT list on
four of seven items, but every entry adds reasoning anchored to a requirement
number, and the section has grown a seventh item ("Canonicalizing the roadmap's
per-feature downstream field") that is the PRD's own, arising from the rejected
reverse-lookup alternative. Out of Scope is a required section that cannot be
discharged by citation; this stays a soft observation, not a finding.

## Style

Clean. No changes required.

No banned words anywhere in the file: no "tier/tiered", "robust", "leverage",
"comprehensive", "holistic", "facilitate", "utilize", "delve", "foster",
"showcase", "seamless", "meticulous", "crucial", "pivotal", "paramount", and no
abstract-noun tells. No emojis. No preamble phrases. The one "stands as" I noted
last round survives at line 64; still trivial, still not worth a cycle.

Em dashes: 29 dash-bearing lines in ~4900 words, against 45 in ~5155 for
PRD-chain-cardinality. At or below the repo's own baseline, so not an outlier.
British "behaviour" is house style here (43 occurrences across the docs corpus).

Burstiness holds up in the new material. "The rule says which node may carry it."
next to a 40-word sentence. "It is real, and it is already written down."
"Recording nothing has two." The new R5.2 ends on a bolded one-sentence
consequence after a long derivation, which is the right shape for the most
consequential claim in the requirements.

## Public-visibility cleanliness

Clean. No private repo names, no private paths, no internal codenames, no issue
numbers of any kind. Every path in the new material is inside this public
repository: `skills/brief/evals/evals.json`, `skills/scope/evals/evals.json`,
`skills/execute/evals/evals.json`, the two cascade fixtures under
`skills/execute/evals/fixtures/`, and `references/pipeline-model.md`. Every skill
named — `/brief`, `/prd`, `/roadmap`, `/strategy`, `/comp`, `/plan`, `/scope`,
`/explore` — ships in this repo. `/comp` is safe to name: the COMP *artifact* is
private-only, but the skill and the type are public here and R5's table already
lists COMP.

The three `wip/` mentions (lines 390, 391, 543) still reference the category of
wip paths rather than any file, so no dangling pointer is created and the
wip-hygiene rule holds. Flagging only because a grep-based CI check keyed on the
bare string could trip.

## Recommended changes (non-blocking)

1. Add a footnote under R24 noting that `R6` in the Today column is the existing
   resolution check code, not requirement R6.
2. Drop `is_known_check_code` from its acceptance criterion, keeping "no format's
   required-section list changes"; the user-facing selectability criterion above
   it already covers the codes.
3. Move R12's grading sentence into its acceptance criterion, where the same
   statement already partly lives.
4. Reconcile "nine places" with "five skills" in one clause, or drop the count
   from R12.
5. Cut R23's exemption clause — R24 is scoped to `docs/` and the fixtures are
   not.
