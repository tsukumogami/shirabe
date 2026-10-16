---
schema: roadmap/v3
status: Active
---

# ROADMAP: numbered-v3

numbered.md as a roadmap/v3 roadmap, for roadmap-features_test.sh: its
`Milestone N` headings are out of order and its Dependencies prose still
says `Feature N`, `Features N, M and K` and `F<N>`, which resolve to the item
tagged `Milestone N`, not to the Nth item. It is held to numbered.md's entry
in expected.json with each `Feature N` id read as `Milestone N`.

## Milestones

### Milestone 1: Base
**Dependencies:** None
**Status:** Done

### Milestone 3: Third, listed second
**Dependencies:** Feature 2
**Status:** Not started

### Milestone 2: Second, listed third
**Dependencies:** Feature 1
**Status:** Not started

### Milestone 4: A Features list
**Dependencies:** Features 1, 2 and 3
**Status:** Not started

### Milestone 5: F-numbers and a lower-case keyword
**Dependencies:** F2 and F7; see also feature 4.
**Status:** Not started
