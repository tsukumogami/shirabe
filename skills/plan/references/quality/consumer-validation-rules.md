# Validation Rules by Consumer Phase

Different consumers validate different aspects of PLAN artifacts.

## During /plan Phase 1 (pre-planning)
- Source design doc or PRD status must be "Accepted"
- Source roadmap status must be "Active"
- If status is wrong, stop and inform user
- Topic input (no source doc): no status check, proceed directly

## During /plan Phase 6 (review)
- Every issue has a clear goal statement
- Dependencies form a DAG (no cycles)
- Walking skeleton issue exists first if that strategy was chosen
- All issues reference the source design doc
- Complexity assignments match the criteria above
- `<<ISSUE:N>>` placeholders are internally consistent

## During /plan Phase 7 (creation)
- PLAN doc follows `plan-doc-structure.md` format
- multi-pr: GitHub milestone and issues created, PLAN status set to Active
- single-pr: Issue Outlines populated, PLAN status stays at Draft
- Source design doc status transitions to "Planned"

## During /work-on (consuming the plan)

All modes:
- Issue dependencies resolved (blockers are closed)
- Issue body has acceptance criteria
- Complexity label matches issue content

Single-pr mode:
- PLAN doc has Issue Outlines section populated
- Outlines have goal, acceptance criteria, and dependency references
