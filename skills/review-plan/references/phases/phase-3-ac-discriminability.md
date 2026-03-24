# Phase 3: AC Discriminability (Category C)

This phase checks whether each acceptance criterion would pass for a plausible wrong
implementation. It runs in two passes:

1. **Pattern pass** — scans AC text for automatable signals (patterns 1, 3, 7 from
   the taxonomy). Matches are flagged immediately without further reasoning.
2. **Adversarial pass** — for each AC that did not match in the pattern pass, prompts
   the review agent to reason taxonomically using patterns 2, 4, 5, and 6.

The taxonomy is defined in `references/templates/ac-discriminability-taxonomy.md`.

## Inputs

Read the following from Phase 0 context:

- All issue body files (already read in Phase 0)
- Upstream design doc (needed for pattern 6 — interface name drift)
- Input type (gates behavior below)

## Behavior by Input Type

| Input type | Behavior |
|------------|----------|
| `design` | Full check — both passes run; pattern 6 uses the upstream design doc |
| `prd` | Full check — both passes run; pattern 6 uses the upstream PRD |
| `topic` | Full check — both passes run; pattern 6 is skipped (no upstream doc) |
| `roadmap` | Returns empty findings immediately (`critical_findings: []`) |

For `roadmap` input types, this phase returns empty findings immediately.

## Pass 1: Pattern Pass

For each acceptance criterion across all issue bodies, scan the AC text for these
exact signals:

### Pattern 1 — Fixture-anchored

**Detection trigger**: the AC text contains any of these terms — "all fixture",
"fixture data", "test data", "sample data", "seed data", "pre-populated" — AND
the issue body contains no AC that mentions a clean-state scenario (empty state,
empty registry, fresh start, reset before running).

Match condition: positive fixture-language match AND absence of any clean-state AC
in the same issue body.

Flag immediately. Do not proceed to adversarial pass for this AC.

### Pattern 3 — Happy-path only (issue-level check)

**Detection trigger**: scan the *entire issue body* (all ACs in the issue). If no
AC in the issue mentions any of: "fail", "failure", "error", "invalid", "edge case",
"empty", "missing", "not found", "rejected", "unauthorized", "timeout", "concurrent"
— flag the issue as happy-path-only.

This is a per-issue check, not per-AC. One issue with six happy-path ACs and no
failure AC produces one finding for the issue.

Flag immediately. Do not run adversarial pass on individual ACs of a happy-path-only
issue — the finding is at the issue level.

### Pattern 7 — Existence-without-correctness

**Detection trigger**: the AC text contains any of these phrases — "exists",
"is created", "is populated", "is not empty", "was created", "has been created" —
AND the AC contains no assertion about content, fields, values, or specific data.

Examples of content assertions (do not flag): "contains the expected rows",
"matches the config schema", "includes the required field", "equals the expected value".

Match condition: existence assertion present AND no content-verification assertion
in the same AC sentence or immediately adjacent AC.

Flag immediately. Do not proceed to adversarial pass for this AC.

## Pass 2: Adversarial Pass

For each AC that did not match in Pass 1, prompt the review agent to evaluate the
AC against patterns 2, 4, 5, and 6. Read the full taxonomy entry for each pattern
before applying it.

The adversarial pass prompt:

> For this acceptance criterion, consider each pattern in turn:
>
> - Pattern 2 (mock-swallowed): would a plausible wrong implementation that uses a
>   mock dependency satisfy this AC even though the real dependency would fail?
> - Pattern 4 (state-without-transition): does this AC check final state but not
>   the operation that produced it? Would a wrong implementation that starts in the
>   target state satisfy the criterion?
> - Pattern 5 (integration scope gap): can this behavior only be observed through
>   integration, and does the AC's scope prevent that observation? Apply the
>   false-positive guard: only flag when integration scope is the *only* observable
>   path — not for every unit AC.
> - Pattern 6 (interface name drift): does this AC reference a specific interface
>   or method name? If so, compare it to the upstream design doc. If they differ,
>   a correct implementation using the design doc name would fail this AC.
>
> If any pattern applies, name it and describe the specific gap. If none apply,
> return no finding for this AC.

## Finding Criteria

Produce a `critical_finding` with `category: "C"` when:

- Pass 1 flags an AC or issue under patterns 1, 3, or 7
- Pass 2 identifies a match under pattern 2, 4, 5, or 6

Do NOT produce a finding when:

- Pattern 3 triggers but the issue has at least one failure/error AC elsewhere in the body
- Pattern 5 is triggered for a unit AC where a unit test could also detect the
  behavior (false-positive guard)
- A pattern check is ambiguous — Category C findings must be confident; uncertain
  matches produce no finding

## Output Format

Findings use the `review_result` `critical_findings` format:

```yaml
- category: "C"
  description: "..."                  # issue number, AC number, pattern name, specific gap
  affected_issue_ids: [3]             # sequence number(s) of affected issue(s)
  correction_hint: "..."              # non-empty; describes what a discriminating AC should check
```

**Category C findings must include a non-empty `correction_hint`**. The hint
describes what a discriminating AC should check — not a replacement AC, but
directional guidance for Phase 4 regeneration agents. Example:

> "Add a clean-state scenario — empty the registry before running the command and
> verify the table is empty, then populate and verify it contains the expected rows."

If no findings: return `critical_findings: []` for this category.

## Loop-Back Target

Category C findings → `loop_target: 4` (Agent Generation)
