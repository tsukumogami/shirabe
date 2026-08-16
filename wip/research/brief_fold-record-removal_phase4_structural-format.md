# Structural-Format Verdict: BRIEF-fold-record-removal

## Verdict

PASS

## Validator output

Command: `shirabe validate --format json --visibility=public docs/briefs/BRIEF-fold-record-removal.md`
(binary: `/home/dgazineu/.tsuku/tools/current/shirabe`)

```json
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
```

Two targeted passes were also run to make the coverage explicit rather than
inferred from the full pass:

`--check FC01,FC02,FC03,FC04,FC15` — identical clean envelope, 0 errors, 0 notices.

`--check R7,R8,R9,R10,R11` — identical clean envelope, 0 errors, 0 notices. R7
is the public-visibility prose check family, so the writing-style rulebook
(including the `em-dash-density` frequency rule) was evaluated under
`--visibility=public` and returned nothing.

## Rubric findings

**1. Required sections present and in canonical order — PASS.**
Heading scan of the body:

| Line | Heading |
|------|---------|
| 23 | `# BRIEF: Fold-Record Removal` |
| 25 | `## Status` |
| 34 | `## Problem Statement` |
| 82 | `## User Outcome` |
| 98 | `## User Journeys` |
| 142 | `## Scope Boundary` |
| 185 | `## Open Questions` |
| 195 | `## References` |

All five required sections present, in the canonical order Status → Problem
Statement → User Outcome → User Journeys → Scope Boundary. Both optional
sections (Open Questions, References) follow the required set, in the order the
Section Matrix lists them. No `Downstream Artifacts` section — correctly
omitted, since no downstream PRD exists yet. The H1 at line 23 matches the
corpus convention (`# BRIEF: <Title>`, cf. `docs/briefs/BRIEF-scope-artifact-persistence.md`).

**2. Frontmatter — PASS, with one non-blocking length observation.**
`schema: brief/v1` (line 2), `status: Draft` (line 3), `problem:` literal block
scalar (lines 4-9), `outcome:` literal block scalar (lines 10-14),
`motivating_context:` literal block scalar (lines 15-20). All three required
fields present with `|` block scalars; FC01 clean.

`upstream:` is absent. Legal — the format reference makes it optional, and its
absence trivially satisfies both the no-ROADMAP and no-`wip/...` constraints.

Length: `outcome` is 4 body lines (in range). `problem` is 5 body lines,
one over the documented 2-4 range. Non-blocking, on corpus evidence: 30 of the
44 briefs in `docs/briefs/` carry a `problem` block longer than 4 lines,
including the brief that framed the brief skill itself
(`BRIEF-shirabe-brief-skill.md`, 7 lines) and `BRIEF-scope-consolidation-over-skipping.md`
(5 lines). The 2-4 figure is unenforced authoring guidance, not a checked
constraint, and holding this document to it would fail two thirds of the
existing corpus. Recorded as an optional improvement below.

Frontmatter/prose agreement: the `outcome` field names three beneficiaries
(parallel `/scope` runs, adopting repositories, a reader) and the `User Outcome`
section elaborates exactly those three in three paragraphs (lines 84-96). The
`problem` field's claim maps onto the Problem Statement's three-part breakdown.
No staleness signal.

**3. FC03, `## Status` first-line convention — PASS.**
Line 25 is `## Status`, line 26 is blank, line 27 is `Draft` — the bare status
word alone, no trailing punctuation, no trailing whitespace (a `grep -n " $"`
over the whole file returns no hits). Line 28 is blank; the explanatory prose
starts at line 29. This is exactly the shape the format reference's "Passes
FC03" example specifies. The frontmatter `status: Draft` at line 3 matches
character for character. The `--check FC03` pass confirms.

**4. FC02, valid status — PASS.** `Draft`, one of the three permitted values.

**5. Open Questions in Draft only — PASS.** The section exists at line 185 and
the document is `Draft`, which the Section Matrix permits ("Draft only"). Both
entries defer framing details rather than stating blockers: whether the merge
attribute is deleted or left inert (lines 186-190), and what text the roadmap's
downstream cell carries once it cannot cite the record (lines 191-193). Both
are downstream-PRD-shaped, matching the format reference's "deferred detail" vs
"blocker" distinction. Confirming the transition requirement: this section must
be emptied or removed before Draft → Accepted, and the Status prose at lines
29-32 already anticipates that by naming what the downstream PRD owns.

**6. Public-visibility cleanliness — PASS.** A grep for `private/`,
`tsukumogami/vision`, `tsukumogami/coding-tools`, and `wip/` returns no hits
anywhere in the file. The document cites no issue numbers at all, public or
private. External systems are referred to generically ("a hosted forge",
"the shared validation workflow") with no internal codenames or private tooling
named. R7/R8/R9 clean under `--visibility=public`.

**7. Durable paths only, and paths actually exist — PASS.** No
`Downstream Artifacts` section, so `References` (lines 195-206) is the only
path-bearing section. All four cited paths were stat'd in the worktree and all
four exist:

| Line | Path | Status |
|------|------|--------|
| 197 | `docs/designs/current/DESIGN-scope-artifact-persistence.md` | exists (43028 bytes) |
| 199 | `docs/prds/PRD-scope-artifact-persistence.md` | exists (36712 bytes) |
| 201 | `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` | exists (45437 bytes) |
| 204 | `skills/scope/references/phases/phase-2-chain-orchestration.md` | exists (40170 bytes) |

All four are durable repo-relative paths; none is a `wip/...` path. Each carries
the one-sentence purpose the format reference asks for.

**8. Writing style — PASS.** A case-insensitive grep for the full `rules.yaml`
term list (all four `words` categories plus the seven adverb openers) over the
whole file returns exactly one hit: `journey`, at line 98, in the required
section heading `## User Journeys`. That term is declared in this repo's
`CLAUDE.md` Prose Vocabulary header (line 12) precisely because it is a
mandatory BRIEF heading, so it does not fire. None of the workspace
`CLAUDE.md` banned words appear — no "tiered", "robust", "leverage",
"comprehensive", "holistic", or "facilitate".

AI tells: no "It's worth noting", "Moreover", "Furthermore", "In conclusion",
"In today's", or "delve". No preamble — the Problem Statement opens on the
mechanism (line 36) rather than on throat-clearing.

Em-dash density: 14 occurrences file-wide, 13 in the body below the
frontmatter. Against 1443 body words that is 9.0 per thousand, under the
rulebook's threshold of 10 per thousand; the R7 pass agrees. Worth knowing the
margin is thin — roughly two more em dashes at this length would cross it, so a
content-driven expansion should watch the count.

Sentence length varies genuinely across the document. The Problem Statement
alternates long analytic sentences with short verdicts ("Three things are wrong
with it.", line 44), and the closing paragraph at lines 78-80 is a single long
sentence following four short-to-medium ones. No uniform-cadence tell.

**9. No emojis — PASS.** A Unicode-class grep across the emoji, dingbat,
arrow, and variation-selector ranges returns no hits.

**10. Validator run — done, output verbatim above.**

## Required changes

None.

## Optional improvements

1. **Frontmatter `problem` runs 5 lines against a documented 2-4** (lines
   5-9). Non-blocking on corpus precedent (30 of 44 briefs exceed it), but if
   the author wants strict conformance, the tightest cut is the parenthetical
   at the end of line 8 through line 9 — "a contention point and an adopter
   obligation bought for a guarantee the surviving document already carries"
   is the sentence the body's three-part breakdown already delivers at length.

2. **Em-dash margin is 9.0 against a threshold of 10** (13 in the body over
   1443 words). Nothing to fix now; flagging so that any Phase 5 prose
   expansion re-runs `shirabe validate --check R7` rather than assuming
   headroom.

3. **The fourth journey is the weakest of the four as a journey** (lines
   133-140). "A future contributor notices folds leave no central trace" names
   a user, a trigger, and an outcome shape, so it satisfies the mechanical
   rule I own — but its outcome shape is "they find a durable record", which
   describes reading an artifact this work produces rather than exercising the
   feature from a distinct entry point. Whether that clears the "journeys are
   distinct" bar is a content judgment and belongs to the content-quality
   reviewer, not to me. Noting it so the verdict pair does not both assume the
   other covered it.
