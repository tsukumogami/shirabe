# Clarity Verdict — PRD-upstream-link-legality

**Verdict:** FAIL

Two requirement-level defects: the PRD removes the cascade's only route to the
roadmap and never states, as a numbered requirement, what replaces it (R16 vs
R11/R13); and R18 defers a decision instead of making one, in a way that
contradicts R20 and an acceptance criterion. Both fixes are small. Structure,
style, and public-visibility cleanliness all pass.

## Validator output

```
$ ./target/debug/shirabe validate docs/prds/PRD-upstream-link-legality.md --visibility=public
$ echo $?
0
```

No output, exit 0 — a clean pass. Confirmed the binary is actually exercising
the checks rather than no-op'ing: a stub PRD with `schema: prd/v1` and a missing
body produced eight findings (`FC01` x2, `FC04` x6) and exit 2.

## Structure

Pass on every count.

All seven required sections are present and in canonical order: Status,
Problem Statement, Goals, User Stories, Requirements, Acceptance Criteria,
Out of Scope.

The two optional sections — Decisions and Trade-offs, Known Limitations — sit
between Acceptance Criteria and Out of Scope. This is legal: FC15 constrains the
relative order of the *required* sections, which is preserved, and the format
reference places no positional constraint on optional sections. The validator
confirms.

Frontmatter carries `schema: prd/v1`, `status`, `problem`, `goals` (all
required), plus `upstream` and `motivating_context` — both legal optional
fields, both single paragraphs in literal block scalars as the format asks.
`upstream:` is a scalar pointing at `docs/briefs/BRIEF-upstream-link-legality.md`,
which exists and is Accepted. No `wip/...` path in frontmatter.

FC03: the body's `## Status` first non-blank line is the bare word `Draft`,
matching frontmatter `status: Draft`. No prose on that line.

Requirements are numbered R1-R21 continuously with no gaps or reuse. Acceptance
criteria all use `- [ ]` checkbox format. No Open Questions section, which is
fine for Draft (it's optional) — and the brief's two deferred questions both
land as recorded decisions under Decisions and Trade-offs, which is the
conventional closure surface the format names.

## Content boundaries

The PRD holds the line better than a validator-check PRD has any right to, but
it crosses in four places. Three are trimmable clauses; the fourth is a whole
paragraph of Decisions and Trade-offs reasoning.

**R8 — prescribes the algorithm, not just the outcome.**

> "Legality is decided from the naming document's format and the target's
> basename. No document index, no filesystem read of the target, and no
> traversal is required."

The second sentence forbids three specific implementation mechanisms. That is a
design decision. The observable half of R8 is legitimate and should survive —
"the check does not cause `docs/visions/` or `docs/strategies/` to be indexed"
has a user-visible consequence (those directories stay out of the orphan check)
and is a real constraint on the WHAT. "No filesystem read of the target, and no
traversal is required" is the design doc's call.

**R4 — decides when the check runs and which mechanism reports it.**

> "This is checked when the declarations are built, not when a document is read,
> so a maintainer who adds a durable type with a working parent finds out from
> the test suite rather than from a dangling link months later."

Build-time versus read-time is an implementation-timing decision, and "from the
test suite" names the mechanism. The requirement underneath is sound and stays:
no durable type may declare a working parent, and a maintainer who writes one
finds out before it reaches the corpus. How and when is downstream. Note the
matching acceptance criterion ("A test asserts that no Durable type declares a
Working type among its legal parents") is *fine* — an AC may name a test,
because an AC is a verification condition.

**R14 — an architectural layering constraint.**

> "Every change to a skill's recording behaviour is authored in that skill's own
> contract. A parent skill does not reach into a child to suppress or rewrite
> what the child records."

This decides where instructions live and how parent and child skills compose.
It is a real and probably correct constraint, but it is architecture. The
WHAT it is standing in for is observable: a skill invoked standalone records
the same upstream it records when a parent invoked it. State that, and let the
design decide that co-locating the change in each skill's contract is how you
get it.

**Decisions and Trade-offs, "The roadmap pointer moves down the chain rather
than disappearing" — descends well below requirements altitude.**

> "the roadmap's path is assigned in exactly one place in the cascade, from the
> walk's report, and there is no directory scan or reverse index"

> "the finalization walk already expands a plan's upstream entries and already
> dispatches a `ROADMAP-` node to the roadmap handoff"

> "...puts discovery logic in a shell script when a frontmatter link would do"

The decision this section records — which node in the chain may name the
roadmap — is genuinely requirements-level and belongs in the PRD. The
justification is not. Comparing a shell-script directory scan against a
frontmatter link is an implementation-approach comparison, and the call-site
detail ("assigned in exactly one place in the cascade, from the walk's report")
is the kind of fact a design doc establishes. The decision can be justified from
the rule alone: links run from the shorter-lived document to the longer-lived
one, the plan is Working and dies with the roadmap, so the plan is the node that
may name it. That argument needs no reference to the walk's internals.

**Borderline, flagging without demanding a change:** R17 names internal
components ("the finalization walk", "the lifecycle chain walk") and asserts
"The opinion about legality lives in the validator alone." Preserving an
existing consumer's behaviour is a legitimate compatibility requirement and the
components have to be named to be pinned. The placement claim in the last
sentence is architecture, but it reads as scope-setting rather than design.

Nothing else crosses. There are no code examples, no API specifications, no
security analysis, and no competitive content. R5's table is the substance of
the rule, not a schema — it belongs.

## Ambiguity

**1. R16 states a constraint and never discharges it. No requirement says which
skill records the replacement link.** This is the most serious finding.

R13 is explicit about removal: "`/brief` no longer records a ROADMAP as the
produced brief's `upstream:`." There is no corresponding requirement about
recording. R16 says only:

> "The cascade must still locate the ROADMAP whose feature a completed chain
> implemented... The route must be a link the definition permits."

The answer — the PLAN names the roadmap — appears only in Decisions and
Trade-offs prose and, obliquely, in one acceptance criterion ("the roadmap is
still reachable from the chain by the cascade"). Two competent readers can
satisfy every numbered requirement and produce different systems: one has
`/plan` write a `ROADMAP-` entry into the plan's `upstream:`; another has
`/scope` pass the value down to the plan (which R14 would forbid, but R16 does
not); a third notices that R11 says "Where the value is legal, the skill records
it as it does today" — and `/plan`'s skill contract contains no instruction to
record a roadmap today — and changes nothing, leaving the cascade unable to find
the roadmap in exactly the case R16 exists to protect. R11 as written actively
points away from the change R16 needs.

The PRD's central promise is "remove an illegal link, keep the consumer whole."
The removal is a requirement; the repair is prose.

**2. R18 defers a decision, and one of its two permitted branches contradicts
R20 and an acceptance criterion.**

> "The change must state what happens to a brief that is correctly the head of
> its own lineage and has no downstream document yet, and either preserve its
> current validation result or record the new one as a deliberate change under
> R20."

A requirement that instructs the implementer to decide something is not a
requirement. Both branches are permitted and they produce different validation
behaviour for an entire class of documents.

The branches are not equally available. R20 says "The list is fixed by R5 and is
exactly:" followed by eight rows, and closes with "The other 73 edges in the
corpus stay legal." The matching acceptance criterion is stricter still: "The
eight documents named in R20 produce exactly the findings R20 predicts, and **no
document outside that list changes its findings**." Taking R18's second branch —
recording a new result under R20 — adds rows to a list R20 calls exact and
changes findings for documents outside it, which that criterion forbids. A
reader cannot satisfy both.

R18 also has no acceptance criterion of its own, so whichever branch is taken,
nothing verifies it.

**3. Minor — R15 is an Out of Scope statement wearing a requirement number.**

> "The obligation that a document with no recorded upstream be self-contained is
> discharged by the self-containment each format already requires of its head
> sections. No new section, field, or check is added for it."

Nothing here is testable and there is no acceptance criterion. The operative
content is "no new section, field, or check," which is a boundary. It does no
harm where it is, but it is not a requirement.

Everything else in R1-R21 is unambiguous. R7's precedence rule (lifetime
reported, direction suppressed) is stated crisply and has a matching criterion.
R9's "unchecked rather than failed" is clear. R10's per-entry independence is
clear and matched. R20's table is the model of a testable requirement.

## Citation vs Restatement

**User Stories: correct.** Four of the five stories carry the brief's four
journeys forward into the PRD's own required section, re-expressed in
"As a / I want / so that" form, plus a fifth ("As the cascade") that is new to
the PRD. This is carrying framing forward into the PRD's own sections, which the
format prescribes — not summarizing the brief alongside them. There is no
separate journeys restatement anywhere.

**Problem Statement: correct.** An independent, compressed retelling that stands
on its own. The format explicitly requires exactly this and exempts only this
section from the citation rule.

**Out of Scope: the closest thing to a restatement problem, but it clears.**
Four of the PRD's six exclusions reproduce the brief's OUT list, one nearly
verbatim:

| Brief OUT | PRD Out of Scope |
|---|---|
| "Teaching the cascade to strip inbound references when it deletes a working artifact." | identical wording |
| "Whether a single upstream may have more than one downstream document of the same type." | "Whether one upstream may have several downstream documents of the same type." |
| "Removing support for a document having several upstreams." | "Removing multi-valued `upstream:`." |
| "Indexing the strategic document directories." | "Indexing the strategic directories." |

What keeps this from being duplication is that every PRD entry adds reasoning
the brief does not have, anchored to a requirement number — "R8 rules it out by
construction", "R10 judges each entry independently", "They are named in R20 so
the diff is readable, and they stay illegal after this change." And Out of Scope
is a required section that cannot be discharged by citation; a PRD whose
boundary section said "see the brief" would be worse. Noting it because it is
the one place the PRD brushes the trap, not as a required change.

## Style

Clean. No changes required.

No banned words: no "tier/tiered", "robust", "leverage", "comprehensive",
"holistic", "facilitate", "utilize", "delve", "foster", "showcase", "seamless",
"meticulous", "crucial", "pivotal", "paramount". No abstract-noun tells
("journey", "narrative", "tapestry", "testament", "landscape", "realm"). No
adverb openers. No emojis anywhere in the file.

No preamble phrases, no "It's worth noting", no "At its core", no "In summary".
One structural tell at line 64 — "the document **stands as** the head of its own
lineage" — where the style guide asks for "is/are/has". Trivial, and the same
construction appears in the brief; not worth a revision cycle on its own.

Burstiness is genuinely good, which is rare. "Nothing states what makes a link
legal, and nothing checks." sits next to 40-word sentences. "It is real, and it
is already written down." "Recording nothing has two." "Checked on its merits,
the edge is where all the signal is." Paragraph lengths vary. Contractions
appear ("does not" dominates, but that is register, not avoidance).

Em dashes: 26 in ~4050 words. PRD-chain-cardinality carries 45 dash-bearing
lines in ~5155 words, so this is at or below the repo's own baseline. Not an
outlier and not a finding.

British "behaviour" appears three times (Goals, R14, R17). The docs corpus uses
"behaviour" 43 times, so this is house style, not an inconsistency.

## Public-visibility cleanliness

Clean. No private repo names, no private paths, no internal codenames, no issue
numbers of any kind (public or otherwise). Every path referenced is inside this
public repository: `docs/briefs/`, `docs/prds/`, `docs/roadmaps/`,
`docs/visions/`, `docs/strategies/`, `references/pipeline-model.md`. Every skill
named (`/brief`, `/scope`, `/strategy`, `/plan`) ships in this repo. No
organization-internal workflow or proprietary tooling is mentioned.

One note that is not a defect: `wip/` appears three times (lines 321, 322, 463)
in the discussion of why `wip/` paths are *rejected* rather than omitted. These
reference the category of wip paths, not any specific file, so no dangling
pointer is created and the wip-hygiene rule is not violated. Flagging only
because a naive grep-based CI check keyed on the string `wip/` could trip on
them.

## Required changes

1. **Add a requirement that assigns the roadmap link.** R16 states the
   obligation; something in the R11-R15 band must discharge it — a numbered
   requirement saying that where a tactical chain runs under a roadmap, the
   produced PLAN records that ROADMAP among its `upstream:` entries. Without it,
   R11's "the skill records it as it does today" leaves `/plan` unchanged and
   the cascade loses the roadmap. Add a matching acceptance criterion naming the
   plan's field rather than the indirect "still reachable from the chain."

2. **Resolve R18 rather than deferring it.** State the actual outcome for a
   brief that heads its own lineage with no downstream document. If that outcome
   changes any document's findings, add those documents to R20's table and drop
   "The list is fixed by R5 and is exactly" — or reconcile the acceptance
   criterion "no document outside that list changes its findings," which the
   second branch currently contradicts. Give R18 an acceptance criterion either
   way.

3. **Trim the implementation clauses.** Cut "No document index, no filesystem
   read of the target, and no traversal is required" from R8, keeping the
   basename statement and the strategic-directory consequence. Cut "This is
   checked when the declarations are built, not when a document is read"
   and "from the test suite" from R4, keeping the rule and the
   before-it-reaches-the-corpus outcome. Restate R14 as observable behaviour —
   a skill records the same upstream standalone as it does under a parent —
   rather than as a rule about where the change is authored.

4. **Lift the cascade decision back to requirements altitude.** In "The roadmap
   pointer moves down the chain rather than disappearing," cut the call-site
   detail ("assigned in exactly one place in the cascade, from the walk's
   report"), the "smallest change to the walking machinery" paragraph, and the
   "puts discovery logic in a shell script when a frontmatter link would do"
   clause from the rejected alternative. The lifetime argument — the plan dies
   with the roadmap, so a plan naming a roadmap can never dangle — carries the
   decision on its own.

Items 1 and 2 are the blocking ones. Items 3 and 4 are deletions, not rewrites.
