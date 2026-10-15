---
schema: plan/v2
status: Active
execution_mode: single-pr
milestone: "report export"
step_count: 4
---

# PLAN: report export

## Status

Active

## Scope Summary

Add a `report export` command that writes the month's transactions as CSV,
then lets the caller pick the columns and refuses a month with no data.

## Decomposition Strategy

**Walking skeleton.** Step 1 runs `report export` end to end on one month of
real transactions, from the command line through the store reader to the CSV
writer, with every column fixed. Each later step adds one behaviour a person
can see by running the command.

## Steps

### Step 1: report export writes a month of transactions as CSV

**Goal**: The command line reaches the store reader and the CSV writer, run on
the March transactions in the sample store.

**Acceptance Criteria**:

- [ ] `report export --month 2026-03` prints a header line `date,payee,amount`
  followed by one line per March transaction in the sample store, and exits 0.
- [ ] A payee holding a comma, such as `Smith, Jones`, prints inside double
  quotes, so the line still has three fields.
- [ ] `report export` with no `--month` prints a usage line naming `--month`
  and exits 2.

**Check**: Run `report export --month 2026-03` against the sample store and see
the header line, one line per March transaction, and exit 0.

**Dependencies**: None

**Files**: `src/cli/export.rs`, `src/store/reader.rs`, `src/csv/writer.rs`

### Step 2: report export prints only the columns asked for

**Goal**: A `--columns` list changes which columns the export prints, in the
order given.

**Acceptance Criteria**:

- [ ] `report export --month 2026-03 --columns amount,date` prints the header
  `amount,date` and each March transaction's amount then date.
- [ ] `--columns payee,colour` exits 2 with a message naming `colour` as an
  unknown column, and prints no CSV.
- [ ] Without `--columns` the output is the same as step 1's.

**Check**: Run `report export --month 2026-03 --columns amount,date` and see
two columns, amount first; run it with `colour` and see exit 2 naming the
column.

**Dependencies**: Step 1

**Files**: `src/cli/export.rs`, `src/csv/columns.rs`

### Step 3: report export refuses a month with no transactions

`report export --month 2026-07` on a store with no July data exits 1 naming the month.

### Step 4: report export writes to a file with --output

`--output march.csv` writes the CSV to that file and prints only its path.
