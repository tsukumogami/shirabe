# Rust-owned divergences from the frozen Go baseline

The golden corpus is a byte-parity contract against the Go implementation at
the pinned baseline commit. A divergence is normally a port defect.

This file records the exceptions: expectations the Rust implementation owns
because it checks something the Go baseline never did. Each entry names the
fixture, the change, and the design that authorized it. An expectation
amended without an entry here is a silent re-baseline, which is the thing
this file exists to prevent.

## DESIGN-vale-adoption

The writing-style check moved from a hardcoded seven-word constant to the
rule source at `skills/writing-style/rules.yaml`, which carries all 47 terms
the rulebook defines. It also gained markdown-aware prose scoping and now
reports the line an author sees rather than a body-relative index.

Three consequences reach this corpus.

**`real/ROADMAP-strategic-pipeline.md` gains an FC10 notice for
`narrative`.** A true positive under the widened rule set: the word appears
in prose at line 403 in its abstract-noun sense, which is the sense the
rulebook bans. The Go baseline never checked it because `narrative` was not
among the seven words the constant carried. The corpus file is unmodified;
only the expectation moves.

**`real/BRIEF-shirabe-strategy-skill.md` and
`synthetic/DESIGN-typed-scalar-roundtrip-underscore-int.md` do NOT gain
notices**, despite containing `journey` and `underscore` respectively. Both
resolve shirabe's `## Prose Vocabulary:` declaration by walking up from the
fixture to the repository root. That is the vocabulary mechanism working on
shirabe's own corpus rather than a special case for tests, and it is worth
noting that the fixtures exercise it: a regression in vocabulary resolution
surfaces here as a parity failure.

**Line numbers in FC10 annotations are unchanged in this corpus** because
the annotation output format carries `file=` without `line=`. The corrected
line reaches the `--format json` envelope instead, which the parity fixtures
do not capture.

**`real/PRD-roadmap-skill.md` gains an FC10 notice for `additionally`
alongside its existing schema-skip notice.** Prose checks now run above the
schema gate, so the 33 corpus files that carry no `schema` field and
therefore ran zero checks are no longer invisible. The word appears
line-initially at line 29, which is the adverb-opener sense the rulebook
bans, so this is a true positive rather than a scoping miss.

This one is a deliberate widening of the PRD's stated boundary and the
DESIGN records it as such: a file that runs no checks and reports success
is the same silent-success defect the format-gate work exists to end,
arriving through a different gate.

**`real/DESIGN-gha-doc-validation.md` gains an em dash density finding** at
11.2 per thousand words over 3,298 words of scoped prose, against a
threshold of 10. This is the first check in shirabe that computes a rate
rather than matching a pattern, and this fixture is the first real document
it fires on. The word count is scoped prose, so fenced code and table rows
are excluded from the denominator; a rate computed over them would not be
the rate the author is asked to act on.

The fixture moves twice under this design: once when prose began running
above the schema gate, and again here. Both are recorded rather than folded
together, because they come from independent changes and a reader tracing
one should not find the other silently bundled.

**Note on the adverb-opener rules.** They match anywhere in a line rather
than only at a sentence start, so a mid-sentence `additionally` would also
fire. No corpus file exercises that case today. Narrowing the match to
sentence-initial position needs sentence segmentation the scoper does not
have; it is a known imprecision rather than an oversight.
