# Brief Structural-Format Verdict: shirabe-scope-skill

## Verdict: PASS

## shirabe validate Output

```
$ go run ./cmd/shirabe validate --visibility=public docs/briefs/BRIEF-shirabe-scope-skill.md
(no output)
EXIT=0
```

The validator emits no findings and exits 0. FC01 (required fields), FC02
(valid statuses), FC03 (frontmatter status matches body `## Status` first
line), and FC04 (required sections present) all pass mechanically. The
public visibility flag did not surface any violation.

## Findings

### Frontmatter

```yaml
---
schema: brief/v1
status: Draft
problem: |
  shirabe ships `/brief`, `/prd`, `/design`, and `/plan` at the tactical
  chain's altitude as direct-invocation child skills, but no parent
  skill walks an author through the chain as a sequence, enforces the
  three-exit contract across BRIEF/PRD/DESIGN/PLAN boundaries, or
  proves the parent-skill pattern v1 against the tactical chain's
  asymmetries (extra re-evaluation boundary, no Phase-5 Reject by
  default, multi-output-mode terminal child). Authors today sequence
  the chain by hand; the pattern stays unratified for the parent skills
  that follow.
outcome: |
  An author invokes `/scope`, the skill orients on whichever durable
  upstream artifacts already exist (BRIEF, PRD-Accepted, DESIGN at
  `current/`, PLAN at any of Draft/Active/Done), proposes a chain from
  the most-downstream settled point, and walks the children under
  their per-gate semantics. The conversation lands at one of three
  durable exits — full-run, re-evaluation Decision Record (at TWO
  boundaries now), or abandonment-forced — with cross-boundary resume
  and manual fallback as first-class steady-state surfaces.
---
```

- `schema: brief/v1` — correct map key (not an FC01-checked field, but the
  routing key the validator uses to select the brief format contract).
- `status: Draft` — valid per FC02 (one of `Draft`, `Accepted`, `Done`).
- `problem:` — present, literal block scalar, multi-line, framed as a
  problem (the absence of a parent skill that walks the chain), not as a
  smuggled solution. FC01 satisfied.
- `outcome:` — present, literal block scalar, outcome-shaped (the author
  experiences `/scope` orienting on disk state, proposing a chain, and
  landing at one of three exits). FC01 satisfied.
- `upstream:` — omitted. Acceptable per format spec: a brief may be
  authored from a freeform topic with no single upstream document.
  Public-visibility clean by omission (no risk of a public brief pointing
  at a private path).

### Required Sections Present & Ordered

Section headings found, in document order:

| # | Heading | Required? | Order check |
|---|---------|-----------|-------------|
| 1 | `## Status` (L27) | Required (1st) | OK |
| 2 | `## Problem Statement` (L31) | Required (2nd) | OK |
| 3 | `## User Outcome` (L142) | Required (3rd) | OK |
| 4 | `## User Journeys` (L257) | Required (4th) | OK |
| 5 | `## Scope Boundary` (L389) | Required (5th) | OK |
| 6 | `## Open Questions` (L494) | Draft-only optional | OK (status is Draft) |
| 7 | `## References` (L555) | Optional | OK |

All five required sections present, in the exact order specified by
`skills/brief/references/brief-format.md` section matrix. `Open Questions`
is permitted because `status: Draft`. `Downstream Artifacts` is absent;
that section is optional, and absence is fine for a brief that has not
yet been picked up by a downstream PRD.

User Journeys section contains five distinct `### Journey N:` sub-headings
(L263, L288, L311, L336, L361), each naming a concrete user, trigger, and
outcome shape.

### Status Line Convention

Body `## Status` heading at L27, blank line at L28, first non-blank line
at L29:

```
Draft
```

The bare status word `Draft` sits alone on its own line. There is no
trailing prose on the same line. The frontmatter `status: Draft` matches
the body status word case-sensitively (and the validator's FC03 check is
case-insensitive). FC03 passes — confirmed by the validator's silent
exit.

The format spec's bare-word-first shape is honored; the optional
explanatory-prose paragraph below is permitted but absent (also fine).

### Public-Visibility Compliance

- `upstream:` field omitted — no risk of pointing at a private artifact.
- No `private/` paths grep-matched in the body.
- No private repo references (e.g., `vision`, `tools`, `coding-tools`,
  `dot-niwa-overlay`) appear in the prose.
- No internal codenames, issue numbers, or private filenames surfaced.
- The References section (L555-573) lists in-repo paths only:
  `docs/briefs/BRIEF-shirabe-charter-skill.md`, `skills/charter/SKILL.md`,
  parent-skill pattern references under `references/`, tactical-chain
  child SKILL.md paths, `skills/explore/references/phases/`, the planned
  `docs/designs/DESIGN-shirabe-scope-skill.md`, and
  `references/cross-repo-references.md`. All paths are within the
  shirabe public repo.

Borderline observation (informational, not a violation): the body prose
mentions `wip/` six times (L58, L205, L227-228, L346, L418, L480). These
are descriptions of where partial-run state lives at runtime, not
durable pointers to specific committed `wip/` files. The CLAUDE.md
wip-hygiene rule targets dangling pointers in committed final artifacts
— pointers cleanup would invalidate. These mentions describe the
runtime semantics of the resume ladder (e.g., `wip/brief_<topic>_*`
patterns as a template, not actual filenames). The phase-4 structural
rubric does not call this out as a violation, and a parent-skill brief
that describes resume-ladder semantics legitimately needs to name the
`wip/`-pattern surface. Flagged for awareness; not a FAIL trigger.

### Writing Style

Grep against the avoid-list words from `CLAUDE.md` (`tier`, `tiered`,
`robust`, `leverage`, `comprehensive`, `holistic`, `facilitate`)
returned zero matches.

Spot-checked for AI tells:
- No "It's worth noting that" / "In essence" / "Importantly" preambles.
- No emojis.
- No AI attribution lines.
- Contractions used naturally (`don't`, `doesn't`, `can't`, `won't`).
- Sentence length varies between short directive sentences and longer
  analytic ones; no monotone cadence.
- Direct prose throughout; the writing leads with claims rather than
  meta-commentary.

The writing-style rules are honored.

## Required Revisions

None. Verdict: PASS.
