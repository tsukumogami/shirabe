---
schema: plan/v2
status: Active
execution_mode: single-pr
milestone: "recurring reminders"
step_count: 4
---

# PLAN: recurring reminders

## Status

Active

## Scope Summary

Let a reminder repeat on a schedule (daily, weekly or monthly), so
`remind list` shows its next occurrence and `remind due` fires it each time.

## Decomposition Strategy

**Walking skeleton.** The schedule types come first so every later step can
build on them, and the command line picks them up in step 2.

## Steps

### Step 1: schedule types for recurring reminders

**Goal**: The reminder model gains the types a recurring schedule needs: a
`Recurrence` enum (daily, weekly, monthly) and a `next_after` method on it.

**Acceptance Criteria**:

- [ ] `cargo test -p remind-core recurrence` passes, with a test that
  `Recurrence::Weekly.next_after` on 2026-03-02 returns 2026-03-09.
- [ ] A test that `Recurrence::Monthly.next_after` on 2026-01-31 returns
  2026-02-28 passes.
- [ ] A test that parsing the text `fortnightly` as a `Recurrence` returns an
  error naming the text passes.

**Check**: Run `cargo test -p remind-core recurrence` and see every recurrence
test pass.

**Dependencies**: None

**Files**: `crates/remind-core/src/recurrence.rs`

### Step 2: remind add accepts a repeat schedule

**Goal**: `remind add --repeat weekly` stores a recurring reminder, and
`remind list` shows its next occurrence.

**Acceptance Criteria**:

- [ ] `remind add "water plants" --at 2026-03-02 --repeat weekly` exits 0, and
  `remind list` then shows `water plants` with `next: 2026-03-02 (weekly)`.
- [ ] `remind add "x" --at 2026-03-02 --repeat fortnightly` exits 2 with a
  message naming `fortnightly` and listing daily, weekly and monthly.

**Check**: Run `remind add "water plants" --at 2026-03-02 --repeat weekly`
then `remind list`, and see the reminder with its next date and schedule.

**Dependencies**: Step 1

**Files**: `crates/remind-cli/src/add.rs`

### Step 3: remind due fires a recurring reminder and moves it on

`remind due` on 2026-03-02 prints `water plants`, and `remind list` then shows next: 2026-03-09.

### Step 4: remind list shows the schedule column for every reminder

`remind list` prints a schedule column, `once` for a reminder that does not repeat.
