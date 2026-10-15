---
schema: plan/v2
status: Active
execution_mode: single-pr
milestone: "hostile titles"
step_count: 4
---

# PLAN: hostile titles

## Status

Active

## Scope Summary

Step titles that would do harm if a reader ran or printed them unescaped.

## Decomposition Strategy

**Walking skeleton.** Step 1 is the smallest end-to-end run; the titles are the point of the fixture.

## Steps

### Step 1: $(touch PWNED) runs end to end

**Goal**: The title carries a command substitution that must stay text.

**Acceptance Criteria**:

- [ ] Nothing named PWNED is created.

**Check**: List the directory and see no file named PWNED.

**Dependencies**: None

### Step 2: `touch PWNED` in backticks

**Goal**: The title carries backticks that must stay text.

**Acceptance Criteria**:

- [ ] Nothing named PWNED is created.

**Check**: List the directory and see no file named PWNED.

**Dependencies**: Step 1

### Step 3: --help is not an option

A title that starts with two dashes stays a title.

### Step 4: [31mred[0m and $(touch PWNED)

A title carrying an ANSI escape stays text.
