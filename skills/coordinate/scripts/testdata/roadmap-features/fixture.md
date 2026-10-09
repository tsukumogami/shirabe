---
status: Active
---

# ROADMAP: fixture

A synthetic roadmap for roadmap-features_test.sh. Every item exercises one
rule of the picker's reading; expected.json holds what it should read.

## Status

AB1 and AB2 are named here, outside the Features section, and read as nothing.

## Features

### AB1: Obsolete base
**Status:** Obsolete

AB1 has no Dependencies line.

### AB2: Waits on the obsolete base
**Dependencies:** AB1
**Status:** Not started

### AB3: Finished over an unfinished dependency
**Dependencies:** AB1
**Status:** Done

### AB4: Done with a period
**Dependencies:** None
**Status:** Done.

### AB5: Done with a note
**Status:** Done -- shipped in #12

### AB6: Shipped
**Status:** Shipped (#34)

### AB7: Dropped over an unfinished dependency
**Dependencies:** AB2
**Status:** Dropped

### AB8: Waits on a dropped item
**Dependencies:** AB7
**Status:** Doneness

### AB9: A paragraph that ends at a blank line
**Status:** done
**Dependencies:** AB4 and, once the loader settles,
AB5 as well

AB2 is named in the description after the blank line and is no dependency.

### AB10: A paragraph that ends at the next field
**Dependencies:** AB6, then
AB7 here
**Needs:** AB2

### AB10a: A paragraph that ends at a heading
**Status:** Not started
**Dependencies:** AB10 and
AB3
#### Notes
AB2 is named under the sub-heading and is no dependency.

### Notes on sequencing

This heading is not an item, so the lines below it belong to no item.

**Dependencies:** AB1
**Status:** Done

### CD1: A mention in nested parentheses
**Dependencies:** AB4 (and the AB9 work (see AB2))
**Status:** In progress

### CD2: Unbalanced parentheses
**Dependencies:** AB5 (unbalanced, so AB9 stays
**Status:** Backlog

### CD3: Soft mentions
**Dependencies:** AB3 and AB2 soft, AB8 (optional), AB10 Preferred,
AB9 (sequencing-preferred) and AB1 paced by the release train.
**Status:** Not started

### CD4: A Soft sentence, a self-mention and another roadmap's tag
**Dependencies:** CD4 follows AB10a; it also tracks ZZ4 of the other roadmap.
Soft: AB1 and AB2; soft on AB7.
**Status:** Not started

### CD5: None, with tags after it
**Dependencies:** None (AB1 and AB2 land first, but this item does not wait on them)
**Status:** Not started

### CD6: Feature 2 on a prefixed roadmap
**Dependencies:** Feature 2
**Status:** Not started

### CD7: A Features list
**Dependencies:** Features 1, 2 and 3
**Status:** Not started

### CD8: F-numbers
**Dependencies:** F2, F4 and F99
**Status:** Not started

### CD9: One tag, soft once and hard once
**Dependencies:** AB2 soft for the docs; AB2 for the API.
**Status:** Not started

### CD10: A soft mention opening a list
**Dependencies:** AB2 soft, AB8.
**Status:** Not started

### CD11: A soft mark that opens a parenthetical
**Dependencies:** AB2 (soft, needs AB8 too)
**Status:** Not started

### CD12: A Features list with a parenthetical inside it
**Dependencies:** Features 1 (the base), 2 and 8
**Status:** Not started

## Sequencing Rationale

CD8 waits on AB1. Nothing in this section is read.
