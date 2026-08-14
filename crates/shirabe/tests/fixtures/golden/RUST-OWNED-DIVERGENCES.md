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
