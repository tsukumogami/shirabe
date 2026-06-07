# Eval Fixture Frontmatter Resolution

Canonical resolution guidance for FC13 notices fired by the
validator's `check_eval_fixture_frontmatter` function. FC13 detects
eval fixture files where an HTML comment (`<!--`) appears on line 1
before the YAML frontmatter opener (`---`).

This file is dereferenced on-demand by FC13 notice text; readers
arrive here from `[FC13] ... see references/fixes/eval-fixture-frontmatter.md`.

## What an FC13 notice means

FC13 fires when:

- A fixture file under `skills/<skill>/evals/` or
  `crates/shirabe/tests/fixtures/` has `<!--` on its first
  non-blank line, AND
- The intended frontmatter opener (`---`) appears later in the
  file.

The notice text names the file path and line number of the
offending comment.

## The parser contract

The frontmatter parser requires the `---` opener to be the first
non-blank line of the file. Specifically:

- Blank lines before `---` are tolerated (whitespace-only lines).
- HTML comments before `---` are NOT tolerated -- they consume
  line 1 and the parser sees a comment, not a frontmatter opener,
  causing it to skip frontmatter parsing entirely.
- The result: a fixture intended to exercise a specific
  frontmatter shape silently degrades to a "no frontmatter"
  fixture, and the eval scenario it was meant to cover does not
  actually run.

This is a silent-skip failure mode: the fixture compiles cleanly,
the eval harness runs, but the assertion the fixture was meant to
exercise never fires.

## Valid marker placement options

There are two places an HTML comment can appear in a frontmatter-
bearing fixture:

### Option 1: Inside a frontmatter field value

```markdown
---
schema: brief/v1
status: Draft
problem: |
  A problem description. <!-- inline note -->
---
```

The comment is part of the field value (a literal block scalar)
and the YAML parser accepts it.

### Option 2: After the closing `---`, as the first body line

```markdown
---
schema: brief/v1
status: Draft
---

<!-- A note about what this fixture exercises -->

## Status

Draft
```

The comment sits in the document body, after the closing `---`.
The frontmatter parser has already completed its work by the time
the comment appears.

## Why line-1 markers are forbidden

The parser implementation reads line 1 and:

1. If line 1 is `---` -> begin frontmatter parsing.
2. If line 1 is blank -> skip and check line 2.
3. If line 1 is anything else (including `<!--`) -> the file has
   no frontmatter; skip frontmatter parsing.

There is no look-ahead for a deferred `---` opener. The contract
is "first non-blank line must be the frontmatter opener" and
HTML comments break that contract.

The historical reason: shirabe's frontmatter parser inherits the
Jekyll/Hugo convention where a missing opener on line 1 signals
"this file has no frontmatter, treat it as pure markdown." Eval
fixtures that want frontmatter must respect that convention.

## Fix

Move any explanatory comment to either Option 1 (inside a field
value) or Option 2 (after the closing `---`). The fixture file
contents and the eval scenario it exercises remain unchanged.
