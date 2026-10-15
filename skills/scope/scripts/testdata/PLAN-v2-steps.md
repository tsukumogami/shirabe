---
schema: plan/v2
status: Active
execution_mode: multi-pr
tracking_level: none
milestone: "csv export"
step_count: 4
---

# PLAN: csv export

## Status

Active

## Scope Summary

Add a `report export` command that writes the report as CSV, then lets it pick
columns and write to standard output.

## Decomposition Strategy

**Walking skeleton.** Step 1 runs `report export` end to end on a one-row
report, so every later step adds one behaviour a person can see by running it.

## Steps

### Step 1: report export writes a one-row report as CSV

**Goal**: The export command reaches the CSV writer and leaves a file holding
the header and the one row.

**Acceptance Criteria**:

- [ ] `report export one-row.json out.csv` writes a header line and one data line.
- [ ] `report export` with no output path prints a usage line and exits 2.

**Check**: Run `report export one-row.json out.csv` and see two lines in `out.csv`.

**Dependencies**: None

**Files**: `src/export/csv.rs`, `src/cli/export.rs`

### Step 2: report export keeps only the columns named by --columns

**Goal**: `--columns` narrows the CSV to the named columns, in the order given.

**Acceptance Criteria**:

- [ ] `report export --columns name,total one-row.json out.csv` writes exactly those two columns.
- [ ] An unknown column name stops the export with a message naming it.

**Check**: Run the export with `--columns name,total` and see a two-column header.

**Dependencies**: Step 1

**Files**: `src/export/columns.rs`

### Step 3: report export writes to standard output when the path is -

An output path of `-` sends the CSV to standard output instead of a file.

### Step 4: report export refuses to overwrite a file without --force

An existing output file stops the export unless `--force` is given.
