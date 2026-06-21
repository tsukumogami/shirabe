VERDICT: FAIL

## Findings

- **FC01 required frontmatter fields**: PASS. `schema: brief/v1` (line 2), `status: Draft` (line 3), `problem: |` (lines 4-10), `outcome: |` (lines 11-16) all present. Optional `motivating_context: |` (lines 17-20) is allowed.
- **FC02 valid status**: PASS. Frontmatter `status: Draft` (line 3) is a member of {Draft, Accepted, Done}.
- **Literal block scalars**: PASS. `problem`, `outcome`, and `motivating_context` all use `|` (lines 4, 11, 17).
- **FC03 frontmatter status matches body `## Status` first line**: PASS. Body `## Status` heading at line 25; first non-blank line is the bare word `Draft` (line 27) alone on its line, followed by a blank line (28) then prose (29+). Matches frontmatter `status: Draft`.
- **FC04/FC15 required sections present and in canonical order**: PASS. Status (25) → Problem Statement (34) → User Outcome (74) → User Journeys (96) → Scope Boundary (134). All five present, correct order. Optional Open Questions (173) and References (194) follow, which is allowed in Draft.
- **User Journeys lead with `###` name headings**: PASS. Four journeys, each with a `###` heading: "Land into the existing scoping PR" (98), "Implement, then pause for review before finalizing" (108), "A plan that adds user-visible surface reaches merge documented" (118), "Finish a run and find it already clean" (126).
- **Scope Boundary explicit IN and OUT lists**: PASS. `**IN:**` (136) with five items and `**OUT:**` (156) with four real exclusions (version-skew, multi-PR/coordinated paths, per-issue engine, chosen mechanisms).
- **Open Questions allowed in Draft**: PASS. Present (173), all entries genuinely defer framing details downstream.
- **Writing style / banned words / emojis**: PASS. No emojis. No instances of tier/robust/leverage/comprehensive/facilitate. Prose is direct, no obvious AI-tells.
- **Public-visibility cleanliness**: CONCERN, escalating to FAIL. See below.

### Public-visibility detail

The References section and frontmatter were scanned for private-repo references, private filenames, internal codenames, and private issue numbers.

- No references to `tsukumogami/vision`, `tsukumogami/coding-tools`, `tsukumogami/tools`, or `private/*` paths. PASS on that axis.
- No private issue numbers. PASS.
- Frontmatter `motivating_context` names "the niwa niwa-default-worktree feature" (line 18) — niwa is a public repo, so this is acceptable.
- **The blocking item — absolute local-machine path (line 197):**
  ```
  /home/dgazineu/dev/niwaw/tsuku/tsuku/friction_execute_niwa-default-worktree.md
  ```
  This is an absolute path into a specific developer's home directory (`/home/dgazineu/...`) on their local machine, committed as a durable reference in a PUBLIC repo BRIEF. Two problems:
  1. It is non-portable — it points outside the repo to a path no other reader (or CI, or a future maintainer) can resolve. The References section per the format contract is for "in-repo precedents ... Durable paths"; a local absolute path is neither in-repo nor durable.
  2. It leaks the author's local filesystem layout and username (`dgazineu`) into a public artifact. While not a private-repo reference, exposing a developer's home-directory path in a public document is a visibility-cleanliness defect.
  The reference is labeled "(durable copy)" but the path is the opposite of durable for any reader other than the author.

## Required changes (only if FAIL)

- **Line 197 (References) — remove or repath the absolute local friction-log reference.** Replace `/home/dgazineu/dev/niwaw/tsuku/tsuku/friction_execute_niwa-default-worktree.md` with an in-repo, repo-relative durable path (commit the friction log into the repo and reference it relatively), or drop the path and describe the source without leaking a local home-directory path. A public-repo BRIEF must not carry an absolute path rooted in a developer's home directory.

## Summary

The BRIEF is structurally sound: all FC01/FC02/FC03/FC04/FC15 checks pass, the five required sections are present in canonical order, User Journeys carry `###` name headings, Scope Boundary has explicit IN/OUT lists with real exclusions, and there are no banned words, emojis, private-repo references, or private issue numbers. The single blocking defect is the References entry at line 197, an absolute local-machine path (`/home/dgazineu/...`) committed into a public artifact — it is non-portable and leaks the author's local filesystem layout, so it must be repathed to an in-repo durable reference before the brief can pass the structural/public-cleanliness gate.
