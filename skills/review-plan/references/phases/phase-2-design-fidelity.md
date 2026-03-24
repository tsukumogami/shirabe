# Phase 2: Design Fidelity (Category B)

This phase checks whether the plan has inherited contradictions from the upstream
design doc — for example, two sections of the design specifying different method
names for the same purpose, producing issues with mutually exclusive behaviors.

## Inputs

Read the following from Phase 0 context:

- Upstream design doc path (from `wip/plan_<topic>_analysis.md`)
- All issue body files (already read in Phase 0)
- Input type (gates behavior below)

## Behavior by Input Type

| Input type | Behavior |
|------------|----------|
| `design` | Full check — read upstream design doc and evaluate issue bodies against it |
| `prd` | Full check — read upstream PRD and evaluate issue bodies against it |
| `roadmap` | Returns empty findings immediately (`critical_findings: []`) |
| `topic` | Returns empty findings immediately — no upstream document to check against |

For `topic` and `roadmap` inputs, skip all checks and return empty findings.

## Full Design Fidelity Check (design, prd)

Read the upstream design doc. Run the following checks:

### 1. Interface and Method Name Consistency

Scan all issue bodies for interface names, method names, function signatures, and
type names that appear in the upstream design. For each name found in an issue body:

- Check whether the design uses the same name consistently.
- If the design has two sections using different names for the same entity (e.g.,
  `LookupRegistry` in section 3 and `RegistryLookup` in section 5), flag this as
  a contradiction that the plan has inherited.

This is the most common Category B failure mode: design inconsistency that survives
into the plan without reconciliation.

### 2. Behavioral Contradiction Across Issues

Check whether two or more issues specify mutually exclusive behaviors for the same
component. This happens when:

- Issue A implements behavior X for a shared component
- Issue B implements behavior Y for the same component where X and Y cannot coexist

Look for this in issue ACs and in issue body descriptions. A plan where issues
independently implement different strategies for the same data structure or API
is a signal.

### 3. Configuration and Schema Consistency

If the design specifies a configuration schema or data format, check that all
issues reference the same fields and format. Issues that encode different field
names for the same configuration value will produce implementations that cannot
interoperate.

## Finding Criteria

Produce a `critical_finding` with `category: "B"` when:

- The design doc contains two sections with different names for the same interface or
  method, and the plan's issues encode both variants
- Two issues implement mutually exclusive behaviors for the same component
- Two issues reference different field names for the same configuration schema entry

Do NOT produce a finding for stylistic naming variations that are not genuine
conflicts (e.g., different variable names in different issues' internal logic are
fine; different public API names for the same exported function are not).

## Output Format

Findings use the `review_result` `critical_findings` format:

```yaml
- category: "B"
  description: "..."          # name the specific sections or issues involved
  affected_issue_ids: [1, 2]  # all issue sequence numbers that encode the contradiction
  correction_hint: ""         # always empty for Category B
```

The `correction_hint` field is left empty for all Category B findings — corrections
require re-running Phase 1 (Analysis) to resolve the upstream contradiction first,
not changing issue body content.

If no findings: return `critical_findings: []` for this category.

## Confidence Note

When the upstream design doc is unavailable (wrong path in analysis.md, file missing),
set `confidence: "low"` in the verdict and note the missing doc in the `summary`.
Return empty findings for this category — do not invent findings without the source.

## Loop-Back Target

Category B findings → `loop_target: 1` (Analysis)
