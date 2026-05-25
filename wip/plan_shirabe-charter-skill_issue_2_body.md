---
complexity: testable
complexity_rationale: New skill SKILL.md plus Phase 0 setup prose with deterministic structural and slug-rejection contract; verifiable via grep-based checks rather than security review.
---

## Goal

Ship `skills/charter/SKILL.md` with the seven structural elements per Design Component 2, including Input Modes per PRD R2 (cold-start ask + freeform topic), the topic-slug regex `^[a-z0-9-]+$` hard-rejection at Phase 0 per R3, and the no-team Team Shape declaration per Design Component 5; ship `skills/charter/references/phases/phase-0-setup.md` with the slug-validation procedure.

## Context

`/charter` is the first parent skill in the shirabe parent-skill pattern. The four pattern-level reference files landed by `<<ISSUE:1>>` define the contract surface (state schema, resume-ladder template, child-inspection rule, conditional-feeder shape). This issue authors the consumer-side SKILL.md that cites those references and wires up `/charter`'s entry point: input parsing, slug validation, and Phase 0 setup. Downstream issues add Phase 1 discovery prose (`<<ISSUE:3>>`), child invocation logic (`<<ISSUE:4>>`), state schema body (`<<ISSUE:5>>`), resume ladder body (`<<ISSUE:6>>`), exit-path orchestration (`<<ISSUE:7>>`), exit artifacts (`<<ISSUE:8>>`), evals (`<<ISSUE:9>>`), and CLAUDE.md surfacing (`<<ISSUE:10>>`); each plugs into a SKILL.md section this issue structures.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md` (Solution Architecture Component 2 — parent-skill SKILL.md template; Component 5 — team-shape declarator, prose form for v1 per Decision 8).

PRD: `docs/prds/PRD-shirabe-charter-skill.md` (R1 SKILL.md template structure, R2 Input Modes, R3 slug constraint).

The Resume Logic ladder body content is owned by `<<ISSUE:6>>`; this issue only structures the section heading and references the meta-ladder template from `parent-skill-resume-ladder-template.md`. The chain-proposal prompt prose and child-invocation logic are owned by `<<ISSUE:3>>` and `<<ISSUE:4>>`; this issue only structures the Workflow Phases diagram and Phase Execution list with placeholder phase-reference paths those issues fill.

## Acceptance Criteria

### File presence and frontmatter

- [ ] `skills/charter/SKILL.md` exists.
- [ ] `skills/charter/references/phases/phase-0-setup.md` exists.
- [ ] `skills/charter/SKILL.md` frontmatter declares `name: charter`.
- [ ] `skills/charter/SKILL.md` frontmatter includes a `description:` field naming `/charter` as a parent skill for the strategic chain.

### Seven structural elements per PRD R1

- [ ] `skills/charter/SKILL.md` contains an `## Input Modes` section (or equivalent header matching the literal substring "Input Modes").
- [ ] `skills/charter/SKILL.md` contains a section covering execution-mode flag parsing for `--auto`, `--interactive`, and `--max-rounds=N` (matchable by the literal substrings `--auto`, `--interactive`, and `--max-rounds`).
- [ ] `skills/charter/SKILL.md` contains a topic-slug constraint statement with the literal regex `^[a-z0-9-]+$`.
- [ ] The topic-slug constraint statement cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` as the contract source.
- [ ] `skills/charter/SKILL.md` contains a `## Workflow Phases` section (or equivalent header matching the literal substring "Workflow Phases") with a diagram or list of phases (Phase 0 setup, Phase 1 discovery, Phase 2 chain orchestration, Phase N finalization).
- [ ] `skills/charter/SKILL.md` contains a `## Resume Logic` section (or equivalent header matching the literal substring "Resume Logic").
- [ ] `skills/charter/SKILL.md` contains a `## Phase Execution` section (or equivalent header matching the literal substring "Phase Execution") listing one phase-reference path per `/charter` phase.
- [ ] `skills/charter/SKILL.md` contains a `## Reference Files` section (or equivalent header matching the literal substring "Reference Files") in a table or list form.
- [ ] Every one of the seven structural elements is non-empty (each section has body content beyond the header itself).

### Input Modes content per PRD R2

- [ ] The Input Modes section specifies that empty `$ARGUMENTS` triggers a cold-start prompt asking the author what strategic conversation they want.
- [ ] The Input Modes section specifies that a non-empty `$ARGUMENTS` value is treated as a freeform topic string from which the slug is derived.
- [ ] The Input Modes section explicitly states that `/charter` MUST NOT accept paths to durable artifacts as an input mode (i.e., a path string is treated as a freeform topic for slug derivation, not as an upstream-artifact pointer).
- [ ] The Input Modes section names a concrete example of path-as-topic behavior (e.g., `/charter docs/visions/VISION-foo.md` is treated as a freeform topic, not as an upstream path).

### Slug-constraint content per PRD R3 / Phase 0 wiring

- [ ] The SKILL.md slug-constraint statement names the regex `^[a-z0-9-]+$` and states slugs failing the regex MUST be rejected at Phase 0 with a clear error.
- [ ] The SKILL.md slug-constraint statement states `/charter` MUST NOT proceed silently when the slug is invalid.
- [ ] `skills/charter/references/phases/phase-0-setup.md` contains the slug-validation procedure: derive slug from `$ARGUMENTS`; if empty, surface the cold-start prompt; if non-empty, apply the regex `^[a-z0-9-]+$`; on match, create `wip/charter_<topic>_state.md` with `phase_pointer: 0` and `exit: UNSET`; on regex failure, surface a clear error naming the violated pattern.
- [ ] `skills/charter/references/phases/phase-0-setup.md` contains the literal regex `^[a-z0-9-]+$`.
- [ ] `skills/charter/references/phases/phase-0-setup.md` names at least three concrete rejection examples (uppercase like `MyTopic`, underscore like `my_topic`, dot like `my.topic`, or whitespace like `Hello World`) with the rejection-message phrasing.
- [ ] `skills/charter/references/phases/phase-0-setup.md` is cited from `skills/charter/SKILL.md`'s Phase Execution section.

### Reference Files table cites Issue 1 pattern-level references

- [ ] The Reference Files section cites `parent-skill-pattern.md`.
- [ ] The Reference Files section cites `parent-skill-state-schema.md`.
- [ ] The Reference Files section cites `parent-skill-resume-ladder-template.md`.
- [ ] The Reference Files section cites `parent-skill-child-inspection.md`.
- [ ] Each of the four citations uses the `${CLAUDE_PLUGIN_ROOT}/references/<file>.md` path form.

### Team Shape declaration per Design Component 5 / Decision 8

- [ ] `skills/charter/SKILL.md` contains a Team Shape declaration (matchable by the literal substring "Team Shape" or equivalent prose) declaring `/charter` as a single-agent skill in v1.
- [ ] The Team Shape declaration states no team is spawned and the parent-of-the-parent invokes `/charter` directly.
- [ ] The Team Shape declaration is prose (not structured YAML/JSON metadata) per Decision 8's v1 form.

### Downstream deliverables

- [ ] Must deliver: SKILL.md's Phase Execution section lists `skills/charter/references/phases/phase-1-discovery.md` as the Phase 1 reference path so `<<ISSUE:3>>` has a target file to author (required by `<<ISSUE:3>>`).
- [ ] Must deliver: SKILL.md's Resume Logic section references the state-file path `wip/charter_<topic>_state.md` as the per-topic state location so `<<ISSUE:5>>` and `<<ISSUE:6>>` can build the schema and ladder against it (required by `<<ISSUE:5>>`, `<<ISSUE:6>>`).
- [ ] Must deliver: SKILL.md and phase-0-setup.md fully specify the cold-start prompt, the slug-rejection behavior, and the path-as-topic-not-upstream behavior so eval scenarios in `<<ISSUE:9>>` have a contract to verify (required by `<<ISSUE:9>>`).
- [ ] Must deliver: `skills/charter/SKILL.md` exists at the canonical path so the CLAUDE.md surfacing in `<<ISSUE:10>>` has a real target to mention (required by `<<ISSUE:10>>`).

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# File presence
test -f skills/charter/SKILL.md
test -f skills/charter/references/phases/phase-0-setup.md

# Frontmatter: name field
grep -qE '^name: charter$' skills/charter/SKILL.md

# Frontmatter: description field exists
grep -qE '^description:' skills/charter/SKILL.md

# Seven structural elements (header presence)
grep -qE '^##+ Input Modes' skills/charter/SKILL.md
grep -qE '^##+ Workflow Phases' skills/charter/SKILL.md
grep -qE '^##+ Resume Logic' skills/charter/SKILL.md
grep -qE '^##+ Phase Execution' skills/charter/SKILL.md
grep -qE '^##+ Reference Files' skills/charter/SKILL.md

# Execution-mode flag parsing prose
grep -qF -- '--auto' skills/charter/SKILL.md
grep -qF -- '--interactive' skills/charter/SKILL.md
grep -qF -- '--max-rounds' skills/charter/SKILL.md

# Topic-slug constraint regex
grep -qF '^[a-z0-9-]+$' skills/charter/SKILL.md
grep -qF '^[a-z0-9-]+$' skills/charter/references/phases/phase-0-setup.md

# Slug-constraint citation to state-schema reference
grep -qF 'parent-skill-state-schema.md' skills/charter/SKILL.md

# Reference Files table cites all four pattern-level references
grep -qF 'parent-skill-pattern.md' skills/charter/SKILL.md
grep -qF 'parent-skill-state-schema.md' skills/charter/SKILL.md
grep -qF 'parent-skill-resume-ladder-template.md' skills/charter/SKILL.md
grep -qF 'parent-skill-child-inspection.md' skills/charter/SKILL.md

# CLAUDE_PLUGIN_ROOT citation form for at least one reference
grep -qF '${CLAUDE_PLUGIN_ROOT}/references/' skills/charter/SKILL.md

# Input Modes content: cold-start, freeform topic, path-not-upstream
grep -qiE '(cold[- ]start|empty .*ARGUMENTS)' skills/charter/SKILL.md
grep -qiE '(freeform|topic[- ]slug|topic string)' skills/charter/SKILL.md
grep -qiE '(MUST NOT accept paths|not.*upstream|path.*as.*topic|treated as.*freeform)' skills/charter/SKILL.md

# Team Shape declaration
grep -qiE '(Team Shape|single[- ]agent.*skill|no team)' skills/charter/SKILL.md

# Phase 0 setup: state-file path, phase_pointer, exit unset
grep -qF 'wip/charter_' skills/charter/references/phases/phase-0-setup.md
grep -qE 'phase_pointer' skills/charter/references/phases/phase-0-setup.md
grep -qiE '(exit.*UNSET|exit:.*unset)' skills/charter/references/phases/phase-0-setup.md

# Phase 0 setup: rejection message naming the violated pattern
grep -qiE '(reject|invalid|violates|does not match)' skills/charter/references/phases/phase-0-setup.md

# Phase Execution list cites phase-0-setup.md and phase-1-discovery.md placeholder
grep -qF 'phase-0-setup.md' skills/charter/SKILL.md
grep -qF 'phase-1-discovery.md' skills/charter/SKILL.md

# Resume Logic section references the state-file path
grep -qF 'wip/charter_' skills/charter/SKILL.md

echo "All validations passed"
```

## Dependencies

Blocked by `<<ISSUE:1>>` (the four pattern-level reference files at `references/parent-skill-*.md` must exist so SKILL.md can cite them).

## Downstream Dependencies

- `<<ISSUE:3>>` — Phase 1 discovery prose plugs into `skills/charter/references/phases/phase-1-discovery.md`, referenced from SKILL.md's Phase Execution list. This issue lists the path so `<<ISSUE:3>>` has the target file location locked in.
- `<<ISSUE:4>>` — child invocation logic and the chain-proposal confirmation prompt live in `skills/charter/references/phases/phase-1-discovery.md` and `phase-2-chain-orchestration.md`, referenced from SKILL.md's Phase Execution list. This issue lists the placeholder phase-reference paths so `<<ISSUE:4>>` slots into the same SKILL.md skeleton.
- `<<ISSUE:5>>` — state-file schema is authored against `wip/charter_<topic>_state.md`, referenced from SKILL.md's Resume Logic prelude. This issue references the state-file path so `<<ISSUE:5>>`'s schema work has the canonical location named in SKILL.md.
- `<<ISSUE:6>>` — the resume ladder body fills the Resume Logic section this issue structures, plus references the meta-ladder template from `parent-skill-resume-ladder-template.md` cited in the Reference Files table. This issue structures the section heading and references the template so `<<ISSUE:6>>` only fills the body.
- `<<ISSUE:7>>` — exit-path orchestration plugs into `skills/charter/references/phases/phase-finalization.md` referenced from SKILL.md's Phase Execution list. This issue lists the path so `<<ISSUE:7>>` has the target file location.
- `<<ISSUE:9>>` — eval scenarios verify cold-start prompt, slug rejection, and path-as-topic behavior; the eval assertions target SKILL.md and phase-0-setup.md prose. This issue fully specifies Phase 0 behavior in those files so `<<ISSUE:9>>`'s eval scenarios have a contract to assert against.
- `<<ISSUE:10>>` — CLAUDE.md surfacing references `/charter <topic>` as a direct-invocation entry trigger. This issue creates `skills/charter/SKILL.md` at the canonical path so the CLAUDE.md mention has a real target.
