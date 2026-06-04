# Structural Format Review

**Verdict:** PASS

Frontmatter is valid, all five required sections are present and ordered, FC03 is satisfied, no banned writing-style words appear, and no private references remain.

## Violations Found

None remaining after the inline fix below.

Initial scan flagged two issue-number references (`tsukumogami/shirabe#150` at two locations). Per the brief-format public-visibility cleanliness rule ("no `private/` paths, private repos, private filenames, internal codenames, or issue numbers"), these were removed inline before this verdict was finalized — the prose now describes the upstream issue by title and content without citing its number.

## Public-Visibility Flags

none

(Cross-references retained: `references/parent-skill-pattern.md`, `skills/scope/SKILL.md`, `skills/charter/SKILL.md`, `docs/briefs/BRIEF-shirabe-scope-skill.md`, `references/brief-format.md` — all are repo-internal paths inside the public shirabe repo. The `/work-on` mention is a forthcoming public parent skill named in pattern docs; not a private artifact.)

## Suggested Improvements

1. **Verify FC03 round-trip.** The transition-status.sh script rewrites only the bare status word on the first line; the current "Draft" + blank line + prose shape is exactly what the script preserves. No fix needed; just noting the BRIEF will survive Draft -> Accepted cleanly.
2. **`upstream:` field.** The frontmatter intentionally omits `upstream:` because no in-repo ROADMAP/PRD names this work — the BRIEF was authored from a conversation grounded by a GitHub issue. Omission is correct per the format reference ("Omit the field entirely when the upstream is a private artifact a public brief cannot name" — and here the public-issue-numbers rule applies the same way).

## Summary

The BRIEF passes structural format. Frontmatter has `schema: brief/v1`, `status: Draft`, `problem:` block scalar (10 lines), and `outcome:` block scalar (8 lines) — all four required fields with valid shapes. The body opens with the required `## Status` section whose first non-blank line is the bare word `Draft`, satisfying FC03. All five required sections appear in the prescribed order (Status, Problem Statement, User Outcome, User Journeys, Scope Boundary). The User Journeys section contains four `###`-headed journeys; the Scope Boundary contains explicit IN (six items) and OUT (eight items) lists. No banned writing-style words (`tier`, `robust`, `leverage`, `comprehensive`, `holistic`, `facilitate`), no emojis, no AI attribution, and no private-visibility references remain.
