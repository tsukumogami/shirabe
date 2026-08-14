# Decomposition — upstream-link-legality

Source: `docs/designs/DESIGN-upstream-link-legality.md` (Accepted).
`input_type: design`. Visibility Public, scope Tactical, mode `--auto`.

## Strategy: horizontal

The design describes five layered build steps with stable interfaces between
them — declarations, then the check that reads them, then the prose that must
agree with them, then the skills, then the evals. Its own sequencing note says
phases one and two are independent of three through five. There is no runtime
integration risk to force early: the check is a pure function over two strings
and the skill changes are contracts, not components that have to meet at
runtime. Walking skeleton buys nothing a horizontal split does not.

## Value confirmation (step 3.5a)

Each unit was tested against "does this land observable value on its own".

| Unit | Standalone value | Verdict |
|---|---|---|
| Declarations | None. Nothing reads them; no validation result changes. | building block |
| The check | Yes, but only paired with the declarations it reads. | building block |
| Reference sweep | Prose only; contradicts the code until the check ships. | building block |
| Skill contracts | A brief that stops recording is a regression until the check justifies it. | building block |
| Evals and fixtures | Test material for behaviour that does not exist yet. | building block |

**Result: no unit is an independent increment.** Every one is a building block
for a single rule, and the rule's acceptance criteria are all-or-nothing — "no
document outside the named list changes its findings" cannot be evaluated
against a tree where the check has landed and the skills have not. Splitting
would leave the corpus with new failures and the skills still producing the
shape those failures name.

Decision block, per the decision protocol under `--auto`:

```
decision: execution-mode
status: confirmed
choice: single-pr
reason: |
  Neither escape condition holds. There is no hard constraint forcing
  multiple PRs — one repository, no landing order, no merge gate — and no
  unit is independently useful. The value-confirmation table above tested
  all five and every one is a building block.
review_priority: normal
```

## Issues

| # | Title | Complexity | Depends on |
|---|---|---|---|
| 1 | Declare each artifact type's lifetime and legal parents | testable | none |
| 2 | Enforce upstream legality in `shirabe validate` | critical | 1 |
| 3 | Correct the references that name a roadmap as a durable type's parent | simple | 1 |
| 4 | `/brief` reads its roadmap and records nothing | testable | 3 |
| 5 | `/plan` gains `--upstream`, and its pre-flight reads sequences | critical | none |
| 6 | Route the roadmap to `/plan`, and fix `/explore`'s roadmap handoff | testable | 4, 5 |
| 7 | Cascade fixtures and the execute eval | testable | 6 |

Issue 5 is independent of 1-4 by construction: the flag and the script fix
concern what a plan records and how it is validated, neither of which reads the
new declarations.
