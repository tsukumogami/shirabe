---
schema: plan/v2
status: Active
execution_mode: single-pr
tracking_level: none
milestone: "hostile step titles"
step_count: 4
---

# PLAN: hostile step titles

## Status

Active

## Scope Summary

Step titles that would do harm if a reader ran them, printed them unescaped, or
posted them where a closing keyword or a mention is live.

## Decomposition Strategy

**Walking skeleton.** Step 1 is the smallest end-to-end run; the titles are
the point of the fixture.

## Steps

### Step 1: $(touch PWNED) runs end to end

**Goal**: The title carries a command substitution that stays text.

**Acceptance Criteria**:

- [ ] Nothing named PWNED is created.

**Check**: List the directory and see no file named PWNED.

**Dependencies**: None

**Files**: `src/hostile/run.sh`

### Step 2: `touch PWNED` in backticks, and Fixes #1

**Goal**: The title carries backticks and a closing keyword that stay text.

**Acceptance Criteria**:

- [ ] Nothing named PWNED is created and no issue is closed.

**Check**: List the directory and see no file named PWNED.

**Dependencies**: Step 1

### Step 3: --help is not an option, @octocat is not a mention

A title that starts with two dashes and names a user stays a title.

### Step 4: [31mred[0m and $(touch PWNED)

A title carrying an ANSI escape stays text.
