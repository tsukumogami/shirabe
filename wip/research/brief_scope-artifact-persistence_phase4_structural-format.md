PASS

# Structural-Format Review — BRIEF-scope-artifact-persistence.md

## 1. Required sections present, canonical order (FC04, FC15)
PASS. Body headings, in order: `## Status` (L23), `## Problem Statement` (L31),
`## User Outcome` (L62), `## User Journeys` (L80), `## Scope Boundary` (L124).
All five required sections present, in the mandated order. `## References`
(L170) is an allowed optional trailing section.

## 2. Frontmatter required fields (FC01), schema, status enum (FC02)
PASS. Frontmatter (L1-19) carries `schema: brief/v1` (L2), `status: Draft`
(L3), `problem: |` block (L4-8), `outcome: |` block (L9-13). `schema` is
exactly `brief/v1`. `status` is `Draft`, a valid member of
{Draft, Accepted, Done}. Optional `upstream` is absent (permitted — brief may
be authored from a freeform topic/private ancestor); optional
`motivating_context` is present (L14-18) and correctly used to explain why the
brief exists (cites shirabe#280) distinct from `problem`/`outcome`.

## 3. FC03 — frontmatter status vs. body `## Status` first line
PASS. Body:
```
## Status

Draft

The framing here is settled; ...
```
First non-blank line under `## Status` (L25) is the bare word `Draft`, alone
on its own line, followed by a blank line (L26) before the explanatory prose
(L27-29) begins. Compared value is exactly `Draft`, matching frontmatter
`status: Draft` character-for-character. Checked byte-by-byte — no trailing
punctuation, no inline prose on that line.

## 4. Public-visibility cleanliness
PASS. Grep for `private/`, `tsukumogami/(vision|coding-tools|tools|dot-niwa-overlay)`,
and `wip/` returned no matches anywhere in the file. Issue references present
are `shirabe#280` (motivating_context, L15) and `#270` (Problem Statement
context via motivating_context prose) — both public-repo issue numbers from
this repo, which the rule explicitly permits. No private filenames or
internal codenames found.

## 5. Content-boundary / altitude check
PASS, with one observation (not a violation). Problem Statement (L31-60)
frames a problem, not a smuggled solution — it describes symptoms (a fixed
verdict, permanent artifacts, four untested defects in an unexercised code
path) rather than prescribing the fix. User Outcome (L62-78) is outcome-
shaped and names the user (the author running `/scope`). User Journeys
(L80-122) each lead with a `###` heading, name a concrete user/trigger/
outcome. Scope Boundary (L124-168) has explicit IN and OUT lists with real
exclusions (retroactive corpus application, the strategic chain, manual
child-skill invocation, a citation index, pre-existence judgments) — none of
the OUT items are filler.

Observation: the Scope Boundary IN list (L135-138) names four specific known
defects in the existing absorb procedure (`upstream:` re-point, missing
retirement guard, post-absorb re-validation scope, write-target set) at a
level of technical specificity that brushes up against DESIGN territory.
However, each item states *that* the defect is in scope, not *how* it will be
fixed (no interface shapes, data flow, or infrastructure choices are
prescribed) — this matches the format's explicit allowance that Scope
Boundary items need "enough specificity that a downstream PRD author knows
where the feature ends." Not a violation of the FC content-boundary rules,
but flagging for awareness since it sits close to the line.

No PRD-level requirements, acceptance criteria, user-story format, DESIGN-
level architecture decisions, implementation task breakdown, or feature-
sequencing content found.

## 6. References entries — durable paths, existence verified
PASS. No `Downstream Artifacts` section present (optional, correctly absent
at Draft stage with nothing downstream yet). All four `References` entries
are durable repo-relative paths (none under `wip/...`), and all four were
verified to exist on disk:
- `docs/briefs/BRIEF-scope-consolidation-over-skipping.md` — exists
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — exists
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — exists
- `skills/scope/references/phases/phase-1-discovery.md` — exists

## 7. Open Questions section
PASS. No `## Open Questions` heading present anywhere in the document — no
unresolved items to flag before an eventual Draft -> Accepted transition.

## `shirabe validate` run
```
shirabe validate docs/briefs/BRIEF-scope-artifact-persistence.md --visibility=Public
```
Exit code: 0. No stdout/stderr output (silent success — no findings).

## Overall verdict: PASS
No structural-format violations found. All FC01-FC04/FC15 checks pass
mechanically and by manual inspection; public-visibility cleanliness holds;
content stays at BRIEF altitude; all References paths are durable and exist;
no Open Questions section to block Accepted transition.
