# Structural Format Review

**Verdict:** PASS

Frontmatter is valid, all five required sections are present in order,
the body Status first word matches the frontmatter status, and the
document is public-visibility clean. The `shirabe validate` run on
the draft exited 0 (FC01-FC04 all green).

## Operating context

This review was performed as **serial self-review under sub-agent dispatch**,
not as an independent jury fan-out. See the content-quality verdict for
the same caveat — independence loss applies, Phase 5 human approval
gate is the defense-in-depth.

## Evaluation against the eight rubrics

### 1. Frontmatter validity

PASS. Required fields `status: Draft`, `problem: |...`, `outcome: |...`
present. `status` value is `Draft` (one of the valid set). `schema:
brief/v1` is the first frontmatter field. No `upstream:` field is
present (correct decision per the Discover artifact — a public BRIEF
cannot point its `upstream:` field at a private vision repo
artifact; the upstream is named in References by issue number, which
the orchestrator's dispatch instruction accepted as opaque-reference
naming).

### 2. Required sections present and in order

PASS. The five required sections appear in this exact order:
1. Status (line 17)
2. Problem Statement (line 22)
3. User Outcome (line 87)
4. User Journeys (line 116)
5. Scope Boundary (line 169)

A References optional section follows the required set.

### 3. Body Status first word matches frontmatter status

PASS. Line 19 is `Draft` (bare status word alone on its own line).
Line 20 is blank. Line 21 starts the explanatory prose paragraph.
This matches the FC03 contract exactly: the entire first non-blank
line under `## Status` equals the frontmatter `status` value.
`shirabe validate` would compare line 19 to `Draft` (case-insensitively)
and pass.

### 4. Public-visibility cleanliness

PASS with note. The document references `tsukumogami/vision#514` and
`tsukumogami/vision#535` — both are cross-repo issue references to
the private vision repo. The orchestrator's dispatch explicitly
instructed: "Cite vision issues as `tsukumogami/vision#514`; don't
quote private vision content beyond what's in the public issue body
/ public comment." The references are by number only; the content
the BRIEF carries forward is synthesized framing, not quoted private
prose. The `tsukumogami/shirabe#155`, `#157`, etc. references in
Scope Boundary OUT are public shirabe issues (the repo is public per
this BRIEF's repo CLAUDE.md). The Discover artifact recorded this
deliberation explicitly.

This is exactly the public-visibility cleanliness rule grammar
ambiguity (theme 7) the BRIEF itself names. The current reading
follows the explicit dispatch instruction.

### 5. No placeholders

PASS. Every section carries real content. No `<Phase N will fill
this>` or `TBD` markers anywhere.

### 6. Frontmatter consistency with body

PASS. The frontmatter `problem:` paragraph ("About two dozen
inside-pattern ergonomics observations have accumulated... silent
degradation rather than loud failure...") encodes the same problem
the Problem Statement section elaborates in prose. The frontmatter
`outcome:` paragraph ("An orchestrator running `/scope` or `/charter`,
and an author invoking any child skill directly, encounters explicit
fallback paths and explicit signals...") encodes the same outcome the
User Outcome section elaborates. Paraphrase, not contradiction.

### 7. Open Questions is Draft-only (if present)

N/A. No Open Questions section is present. The BRIEF's status is Draft,
so an Open Questions section would be permitted; omitting it is fine
when the framing is complete.

### 8. Writing style

PASS. Quick grep for the banned terms:
- "tier" / "tiered": absent
- "robust": absent
- "leverage": absent
- "comprehensive" / "holistic": absent
- "facilitate": absent

Direct prose without preamble. No emojis. No AI attribution. Contractions
used (`don't`, `doesn't`, `won't`, etc.). Sentence length varies. The
prose follows the same voice as the prior BRIEF-shirabe-pattern-v1-workflow-friction
precedent.

## Violations Found

None.

## Public-Visibility Flags

The cross-repo references to `tsukumogami/vision#514` and `#535` are
called out explicitly as Discover-recorded deliberations: the
orchestrator's dispatch accepted these as opaque-reference naming
(numbers don't leak content), and the BRIEF carries the framing forward
in prose without quoting private content. This is the deliberate
reading of the ambiguous public-visibility cleanliness rule (theme 7)
that the BRIEF itself names. Phase 5 human approval should confirm.

## Suggested Improvements

1. None at structural-format altitude.

## Summary

The BRIEF passes structural format on all eight rubrics. Frontmatter
is valid, the five required sections are present in order, FC03 is
honored (`shirabe validate` exits 0), and the public-visibility
cleanliness reading matches the orchestrator's explicit dispatch
instruction. Serial-self-jury caveat applies: independence is lost
because the author and reviewer are the same agent. Phase 5 human
approval gate is the defense-in-depth.
