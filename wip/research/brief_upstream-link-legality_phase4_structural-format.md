# Structural Format Verdict — BRIEF-upstream-link-legality

**Verdict:** PASS

## Validator output

Binary used: `../../../target/debug/shirabe` (no `./target/debug/shirabe` exists in
the worktree; the repo-root build was used).

Command:

```
../../../target/debug/shirabe validate docs/briefs/BRIEF-upstream-link-legality.md --visibility=public
```

Output (verbatim — the default `annotation` format emits nothing on a clean file):

```
```

```
exit code: 0
```

Same command with `--format human`, verbatim:

```
All checks passed.

Advisory: Draft posture: no draft-tolerable findings to flag.
```

```
exit code: 0
```

Same command with `--format json`, verbatim:

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

```
exit code: 0
```

Binary sanity check (to confirm the clean result is a real pass, not a silent
no-op): a copy of the document with `Draft` rewritten to
`Draft. broken prose on first line` produced

```
/home/dgazineu/.claude/jobs/c03b51a9/tmp/BRIEF-sanity.md:24 error [FC03] frontmatter status "Draft" does not match ## Status body "Draft. broken prose on first line"

1 error(s), 0 notice(s) -- violations

Advisory: Draft posture: no draft-tolerable findings to flag.
```

```
sanity exit: 2
```

The validator fires on this document class, so exit 0 on the real file is a
genuine clean pass.

## Findings

- **All five required sections present (FC04) — PASS.** `## Status` (line 24),
  `## Problem Statement` (31), `## User Outcome` (76), `## User Journeys` (97),
  `## Scope Boundary` (132). All five are present as `##` headings.

- **Canonical order (FC15) — PASS.** The five headings appear at lines 24, 31,
  76, 97, 132, which is the canonical order Status → Problem Statement → User
  Outcome → User Journeys → Scope Boundary. FC15 is registered notice-level and
  fired nothing; the JSON envelope reports `"notices": 0`, so the ordering check
  passed rather than being suppressed.

- **Frontmatter required fields (FC01) and schema pin — PASS.**
  `schema: brief/v1` (line 2), `status: Draft` (3), `problem:` as a `|` literal
  block (4-8), `outcome:` as a `|` literal block (9-13). All three FC01 fields
  present; the schema key routes to the `brief/v1` contract, confirmed by the
  fact that BRIEF-specific FC03 fired on the sanity copy.

- **Optional frontmatter fields are legal ones only — PASS.** The only optional
  field used is `motivating_context` (lines 14-19), one of the two legal
  optionals in the brief format (`upstream`, `motivating_context`). No
  extraneous keys. `upstream:` is absent, which the format explicitly permits
  ("Optional because a brief may be authored from a freeform topic with no
  single upstream document").

- **FC02 valid status — PASS.** `status: Draft` is in the legal set
  (Draft, Accepted, Done).

- **Body `## Status` first non-blank line (FC03) — PASS.** Line 26 is the bare
  word `Draft` alone, followed by a blank line, followed by the explanatory
  paragraph at lines 28-29. This matches the frontmatter `status: Draft`
  exactly. The validator's FC03 check confirms it, and the sanity copy proves
  the check is live.

- **Optional sections drawn from the legal set — PASS.** Two optional sections
  are used: `## Open Questions` (line 171) and `## References` (line 185). Both
  are in the legal set (Open Questions, Downstream Artifacts, References). No
  section outside the union of required and legal-optional appears.

- **Open Questions present only because status is Draft — PASS.** Status is
  `Draft` in both frontmatter and body, and the section matrix marks Open
  Questions "Draft only". Both entries defer a framing detail to a named
  downstream owner (the PRD's Decisions and Trade-offs section, and a design
  question below the PRD) rather than recording a blocker that should have
  stopped the brief. The section will need to be empty or removed before the
  Draft → Accepted transition, which is the finalization gate, not a Draft-time
  failure.

- **No `wip/...` paths anywhere — PASS.** A case-insensitive grep for `wip` over
  the whole file, frontmatter included, returns no match. There is no
  `Downstream Artifacts` section, so the durable-path rule for that section is
  vacuously satisfied. The three `## References` entries are durable
  repo-relative paths and all three files exist on disk:
  `docs/briefs/BRIEF-chain-cardinality.md`,
  `docs/prds/PRD-chain-cardinality.md`,
  `docs/designs/current/DESIGN-chain-cardinality.md`.

- **Public-visibility clean — PASS.** This repo declares `## Repo Visibility:
  Public` (CLAUDE.md line 6), and the validator was run with
  `--visibility=public`, so the public-repo checks (R7/R8/R9) were active and
  clean. Manually: no `private/` path component, no private repo name (`vision`,
  `coding-tools`, `tools`, `dot-niwa-overlay`), no internal codename, and no
  issue number of any kind — the document refers to "two issues" and "five
  committed briefs" by description rather than by reference. The word "private"
  occurs twice (lines 69, 140) but as the visibility concept the brief is
  reasoning about ("a public document whose upstream is private", "the private
  case"), never as a path or repo name. "Indexing the strategic document
  directories… visions and strategies" (lines 163-164) names the public shirabe
  artifact types VISION and STRATEGY, not the private `vision` repo.

- **No emojis — PASS.** A Unicode scan over the emoji and dingbat ranges returns
  no match.

- **No banned words from the workspace list — PASS.** A grep for the workspace
  CLAUDE.md quick-reference list (tier/tiered, robust, leverage,
  comprehensive/holistic, facilitate) and the wider writing-style word tables
  returns no true positive. The one word-table hit is "journey" inside the
  mandatory `## User Journeys` heading, which the brief format requires
  verbatim.

- **No AI tells — PASS with one nit.** No filler openers, no "it's worth
  noting", no adverb sentence-openers (Additionally / Notably / Ultimately /
  Furthermore / Moreover), no forced rule of three, no synonym cycling. Sentence
  length varies sharply ("When a link in that walk is wrong, the trail does not
  degrade — it ends." against the long paragraph-length sentences around it),
  which is the burstiness the style skill asks for. Two non-blocking nits, both
  cosmetic and neither a criterion under review:
  - Line 70 uses "the document stands as the head of its own lineage".
    "stands as" is in the structural-patterns table with the fix "use is/are/has".
    One occurrence in a 193-line document.
  - The frontmatter block scalars use ASCII `--` (lines 15, 17) while the body
    uses the em dash `—` (12 lines). Cosmetic inconsistency, not a rule; twelve
    em-dash lines across a ~170-line prose body is within this repo's house
    style rather than overuse.

## Required changes

None. The document passes every structural criterion under review.
