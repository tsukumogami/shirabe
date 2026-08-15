# Phase 4 Jury Verdict: Structural Format Review

Document under review: `docs/briefs/BRIEF-skill-adherence-enforcement.md`
Format contract: `skills/brief/references/brief-format.md` (shirabe 0.17.1-dev)
Reviewer role: structural-format

VERDICT: FAIL

One defect remains outstanding (criterion 2). A second defect (criterion 6) was
found during this review and has since been fixed on the branch; it is recorded
below as found-and-fixed rather than as an outstanding failure.

## 1. Required sections present and in canonical order (FC04/FC15) — PASS

Heading order is exactly the canonical sequence, with both optional sections
trailing the five required ones:

| Section | Line |
|---------|------|
| `## Status` | 23 |
| `## Problem Statement` | 32 |
| `## User Outcome` | 73 |
| `## User Journeys` | 95 |
| `## Scope Boundary` | 134 |
| `## Open Questions` (optional) | 176 |
| `## References` (optional) | 189 |

Four `###` journeys, each with a name heading, a named actor, a trigger, and an
outcome shape. Scope Boundary carries both an `### IN` list (L135) and an
`### OUT` list (L153) with real exclusions.

## 2. Frontmatter valid — FAIL

`schema: brief/v1`, `status: Draft`, `problem`, and `outcome` are all present;
`motivating_context` is a legal optional field. Both `problem` and `outcome` are
YAML literal block scalars (`|`).

The failure is line count. The format contract specifies `problem` as "A 2-4 line
YAML literal block scalar (`|`)". The field spans **5 lines**, L5-L9:

```yaml
problem: |
  An agent holding shirabe's skills can be handed a finished plan and still
  not run it under the sanctioned workflow, either by never invoking the skill
  or by invoking it and quietly skipping the part that carries the guarantees.
  Both leave the author with no visibility while the work happens and no
  durable record that the plan's validation steps ran.
```

`outcome` (L11-L14) is 4 lines and in range.

This is a spec-range violation, not a validator-enforced one — `shirabe validate`
does not check block-scalar line counts, so the document validates clean despite
it.

Content match is good in both directions. The `problem` scalar names both failure
shapes (never invoked / invoked-then-abandoned) and both losses (no visibility
during the run, no durable record), which is what the Problem Statement
elaborates. The `outcome` scalar's "tell, from outside the agent and without
asking it" and "the departure is surfaced and recorded" both land in the User
Outcome body. No divergence between YAML and prose.

Fix: compress `problem` to four lines. For example:

```yaml
problem: |
  An agent holding shirabe's skills can be handed a finished plan and still not
  run it under the sanctioned workflow, either by never invoking the skill or by
  invoking it and skipping the part that carries the guarantees. Both leave the
  author no visibility during the run and no durable record that validation ran.
```

## 3. FC03 — frontmatter status matches body `## Status` first line — PASS

Line 25 is `Draft`, bare and alone on the first non-blank line under the
`## Status` heading, followed by a blank line before the explanatory paragraph at
L27. It equals the frontmatter `status: Draft`. The validator confirms it: FC03
does not appear in the findings.

## 4. Public-visibility clean — PASS

No private repo names, no `private/` paths, no private filenames, no internal
codenames, and no issue numbers of any kind. The document names mechanisms
generically where a private name would otherwise appear ("the workspace manager",
"the orchestration engine", "the plan-execution workflow"), and every named
artifact is a public in-repo path.

## 5. Writing style — PASS, zero findings

```
$ shirabe validate --format json --visibility=Public docs/briefs/BRIEF-skill-adherence-enforcement.md
{
  "schema_version": "shirabe-validate/v1",
  "summary": { "outcome": "clean", "errors": 0, "notices": 0 },
  "findings": [],
  "advisory": { "summary": "Draft posture: no draft-tolerable findings to flag.", "notes": [] }
}
EXIT: 0
```

FC10 em-dash density did not fire. The document contains zero em dashes, en
dashes, or `--` sequences in prose: `grep -nP "[\x{2013}\x{2014}\x{2015}]|--"`
over the file returns only the two `---` frontmatter fences at L1 and L19.
Density is 0 per thousand words against a threshold of 10, over 1659 words.

The clean result was confirmed to be a real pass rather than an unrun check, by
running the same command against the sibling DESIGN in this branch, which trips
the FC10 notice:

```
[FC10] em-dash-density: 14.9 per thousand words over 1136 words, above the
threshold of 10 -- see skills/writing-style/rules.yaml
  docs/designs/DESIGN-skill-adherence-enforcement.md:36
```

No declared prose-vocabulary term (`tier`, `journey`, `underscore`, per the
repo's CLAUDE.md) needed suppression. The document uses `journey` only as the
required section heading.

## 6. References paths durable — PASS (one defect found and fixed during review)

No `wip/...` path appears anywhere in the document, and there is no Downstream
Artifacts section.

Found during review: the References section cited
`docs/designs/DESIGN-execute-skill.md`, which does not exist. `docs/designs/` at
top level holds only `DESIGN-skill-adherence-enforcement.md` and the `current/`
subdirectory; the real file is `docs/designs/current/DESIGN-execute-skill.md`
(19685 bytes). Sibling briefs that cite Current-status designs all include the
segment, e.g. `docs/briefs/BRIEF-execute-skill.md:163` cites
`docs/designs/current/DESIGN-shirabe-progression-authoring.md`.

Fixed in commit `23d554b`. Verified in the current file at L191:

```
- `docs/designs/current/DESIGN-execute-skill.md` and
```

Existence check on all four cited paths, post-fix:

| Path | Line | Exists |
|------|------|--------|
| `docs/designs/current/DESIGN-execute-skill.md` | 191 | yes |
| `docs/prds/PRD-execute-skill.md` | 191 | yes |
| `docs/briefs/BRIEF-pr-template-gate.md` | 194 | yes |
| `references/workflow-principles.md` | 198 | yes |

## Non-blocking note

`docs/designs/DESIGN-skill-adherence-enforcement.md` exists in this branch, but
the BRIEF has no Downstream Artifacts section pointing at it. That section is
optional and its absence is not a violation, so it is not counted against the
verdict — noted only in case the downstream link was intended.

## Path to PASS

Trim the `problem` frontmatter scalar from five lines to four. That is the sole
remaining defect; every other criterion passes.
