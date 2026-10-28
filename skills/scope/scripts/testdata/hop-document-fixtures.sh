# hop-document-fixtures.sh -- minimal valid topic documents for
# check-hop-document_test.sh. Valid includes the notice-level rules the gate
# reports: the BRIEF's summaries span two to four lines (FC23) and the
# DESIGN's keys are in order (FC24).
# Sourced. Each writer prints a document for topic $1 on stdout.

fx_brief() {
    cat <<EOF
---
schema: brief/v1
status: Draft
problem: |
  Authors lose track of which documents a run wrote.
  Nothing lists them when the run ends.
outcome: |
  Authors can see every document a run wrote.
  One list names them all.
---

# BRIEF: $1

## Status

Draft

## Problem Statement

Authors lose track of which documents a run wrote.

## User Outcome

Authors can see every document a run wrote.

## User Journeys

An author opens the run's record and reads the list.

## Scope Boundary

In: the list. Out: editing the documents.
EOF
}

fx_prd() { # <topic> [<upstream>]
    cat <<EOF
---
schema: prd/v1
status: Draft
problem: |
  Authors lose track of which documents a run wrote.
goals: |
  Authors can see every document a run wrote.
${2:+upstream: $2}
---

# PRD: $1

## Status

Draft

## Problem Statement

Authors lose track of which documents a run wrote.

## Goals

Authors can see every document a run wrote.

## User Stories

As an author, I want the list, so that I can find each document.

## Requirements

- **R1.** The run lists its documents.

## Acceptance Criteria

- [ ] The run prints one line per document.

## Out of Scope

Editing the documents.
EOF
}

fx_design() {
    cat <<EOF
---
schema: design/v1
status: Proposed
problem: |
  Runs don't list their documents.
decision: |
  Print a list at exit.
rationale: |
  It is the simplest place.
---

# DESIGN: $1

## Status

Proposed

## Context and Problem Statement

Runs don't list their documents.

## Decision Drivers

Keep it simple.

## Considered Options

Print at exit, or write a file.

## Decision Outcome

Print at exit.

## Solution Architecture

One function prints the list.

## Implementation Approach

Add the function and call it.

## Security Considerations

The list holds only paths the run wrote.

## Consequences

Authors see the list.
EOF
}

fx_plan() { # <topic> [<dependency line>]
    cat <<EOF
---
schema: plan/v1
status: Active
execution_mode: single-pr
milestone: "Run document list"
issue_count: 1
---

# PLAN: $1

## Status

Active

## Scope Summary

Print the run's documents at exit.

## Decomposition Strategy

One issue.

## Issue Outlines

### Issue 1: feat(run): print the documents at exit

**Goal**: Print every document the run wrote.

**Acceptance Criteria**:
- [ ] One line per document.

**Dependencies**: ${2:-None}

## Implementation Sequence

Issue 1.
EOF
}
