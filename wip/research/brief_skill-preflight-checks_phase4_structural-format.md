# Verdict: PASS

Reviewer: structural-format (Phase 4 two-reviewer jury)
Target: `docs/briefs/BRIEF-skill-preflight-checks.md` (247 lines)
Format reference: `/Users/danielgazineu/.claude/plugins/cache/shirabe/shirabe/0.16.1-dev/skills/brief/references/brief-format.md`

## Checks

1. **Frontmatter — PASS.** `schema: brief/v1` present on line 2. All three required fields present: `status` (line 3), `problem` (lines 4-8), `outcome` (lines 9-13). Both `problem` and `outcome` are YAML literal block scalars (`|`) at 4 content lines each, inside the 2-4 line window. Optional `motivating_context` (lines 14-18) is a well-formed `|` block scalar, 4 content lines, and carries situational trigger content distinct from `problem` and `outcome` as the format reference requires. `upstream:` is absent, which is correct here rather than an omission: no ROADMAP grounded this brief (the Status section records that the work started from an exploration, not from a sequenced roadmap feature), and the format reference lists `upstream` as optional precisely for briefs authored from a freeform topic. Byte inspection of lines 1-19 via `od -c` confirms clean `---` delimiters and no trailing-whitespace or CRLF damage.

2. **FC02 — PASS.** Frontmatter `status: Draft`. `Draft` is one of the three valid statuses (Draft, Accepted, Done).

3. **FC03 — PASS (verified byte-exactly).** `od -c` of lines 23-26 returns:
   `#   #       S   t   a   t   u   s  \n  \n   D   r   a   f   t  \n  \n`
   The entire first non-blank line under `## Status` is the bare word `Draft` — no trailing prose, no period, no trailing whitespace. It matches frontmatter `status: Draft` exactly (and therefore case-insensitively). The explanatory prose (the exploration-provenance paragraph and the downstream-PRD-ownership paragraph) begins on line 27, after a blank line, which is the shape the format reference prescribes. This is the check that most commonly fails; it does not fail here.

4. **FC04 / FC15 — PASS.** Heading scan returns, in file order:
   - L23 `## Status`
   - L38 `## Problem Statement`
   - L94 `## User Outcome`
   - L118 `## User Journeys`
   - L168 `## Scope Boundary`
   - L213 `## Open Questions`
   - L235 `## References`

   All five required sections are present and in canonical order. The two optional sections both sit after `Scope Boundary` and appear in the Section Matrix's own order (Open Questions, then — with Downstream Artifacts absent — References), so no optional section interrupts the required ordering. `Open Questions` is permitted because status is `Draft`. Sub-headings (`###`) appear only under `User Journeys` (five journeys) and `Scope Boundary` (`### In`, `### Out`), which is legal sub-structure and does not affect FC04/FC15 `##`-level matching.

5. **Public-visibility cleanliness — PASS.** Repo is public (`CLAUDE.md` line 6: `## Repo Visibility: Public`). Grep for `private/`, `vision`, `coding-tools`, and `overlay` returns no matches. Every issue reference in the brief is a public `shirabe` issue: `shirabe#80` (L60), `shirabe#270` (L68 and L230), `shirabe#279` (L70), plus `/work-on 214` (L122) as an illustrative public issue number in a journey. No `tsukumogami/vision#NNN`, no `tsukumogami/coding-tools#NNN`, no private filenames or internal codenames. The host paths that do appear (`~/.tsuku/tools/current/`, `~/.tsuku/env`) are user-machine paths for a publicly documented tool, not private-repo references.

6. **wip/ hygiene — PASS.** `grep -n 'wip/'` over the brief returns no matches (exit 1). No `wip/...` path appears in frontmatter, prose, the Open Questions section, or References. All four References entries are durable repo-relative paths, and there is no Downstream Artifacts section to check.

7. **Writing style — PASS.** Rulebook read from `skills/writing-style/rules.yaml` (schema `writing-style-rules/v1`) and `skills/writing-style/SKILL.md`. A word-boundary, case-insensitive grep over the full banned-terms list — organizing, verbs, descriptors, abstract-nouns, and adverb-openers categories, with the repo's declared vocabulary (`tier`, `journey`, `underscore`) excluded per `CLAUDE.md` line 11 — returns zero matches. `journey` does appear (section heading and journey prose) and is correctly not flagged, since it is declared vocabulary; note the declaration is term-scoped, and no variant such as `journeys` used outside the section sense creates a separate problem here. Frequency rule `em-dash-density`: the document contains zero U+2014 em dash characters (`grep -c '—'` returns 0); the author consistently uses the double-hyphen `--` form, which the pattern does not match, so the rule cannot fire. Judgment-only rule spot check: `landscape` does not appear; no forced rule-of-three or empty-conclusion pattern observed at the structural level.

8. **Referenced-path existence — PASS.** Every repo-relative path cited, in References and in prose, resolves on disk:

   References section:
   - `references/fixes/cli-version-preflight.md` — exists (4003 bytes). The brief's claim that it is "a hundred and eight lines" is accurate: `wc -l` returns 108.
   - `skills/inflight/SKILL.md` — exists (5633 bytes).
   - `skills/execute/scripts/preflight.sh` — exists (1542 bytes, mode 755).
   - `docs/briefs/BRIEF-shirabe-check-absorption.md` — exists (8029 bytes).

   Prose:
   - `skills/work-on/SKILL.md` (L42) — exists (17724 bytes).
   - `.tsuku.toml` (L80) — exists (190 bytes).
   - `.tsuku-recipes/shirabe.toml` (L220) — exists (684 bytes).
   - `run-cascade.sh` (L46, L207) — cited by bare filename rather than path; resolves to `skills/execute/scripts/run-cascade.sh`.
   - `DESIGN-shirabe-pattern-v1-ergonomics` (L229) — cited by document name rather than path; resolves to `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md`.
   - `skills/inflight/SKILL.md` (L184, Scope Boundary) — same file as above, exists.

   Two corpus counts the brief asserts also check out: "shirabe's twenty skills" (L39, L165, L172) matches the 20 directories under `skills/`, and "Nine of shirabe's twenty skills" is consistent with that denominator. The two bare-name citations (`run-cascade.sh`, `DESIGN-shirabe-pattern-v1-ergonomics`) are unambiguous — each resolves to exactly one file in the repo — so neither is a dangling reference, though a downstream PRD may prefer full paths.

## Validator output

Binary used: `shirabe` on PATH, resolving to `/Users/danielgazineu/.tsuku/tools/current/shirabe` -> `/Users/danielgazineu/.tsuku/tools/shirabe-0.16.0/bin/shirabe`, reporting `shirabe v0.16.0`. The fallback path was not needed; PATH and the `~/.tsuku/tools/current/shirabe` fallback are the same binary.

Command:

```
shirabe validate --format json --visibility=public docs/briefs/BRIEF-skill-preflight-checks.md
```

Output (verbatim), exit code 0:

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

## Required changes (if FAIL)

None. All eight checks pass and the validator reports `clean` with zero errors and zero notices under `--visibility=public`.

Two optional, non-blocking observations for the author, neither of which affects the verdict:

1. `run-cascade.sh` (L46, L207) and `DESIGN-shirabe-pattern-v1-ergonomics` (L229) are cited by bare name rather than repo-relative path. Both resolve unambiguously today, so this is not a dangling-reference violation, but full paths (`skills/execute/scripts/run-cascade.sh`, `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md`) would survive a file move and match how the References section already cites its entries.
2. `Open Questions` is populated, which is correct and expected for `Draft`. It must be empty or removed before the Draft -> Accepted transition; flagging here only so the finalization step does not encounter it as a surprise.
