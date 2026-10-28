# Phase 4b: Functional Shape (Category E)

This phase checks whether the plan is cut by behaviour or by component. A plan
whose entries each build one layer (the types, then the compiler, then the
command line, then the tests) shows nothing a person can run until the last
entry lands, so every checkpoint before it can only confirm that files exist.
The same habit shows up inside entries as criteria that name a file or an
identifier to construct instead of a result to observe.

Category C asks whether one criterion would pass for a wrong implementation.
This category asks a different question, about the shape of the whole plan and
the subject of each criterion, and it applies to plans of either version.

## Inputs

Read the following from Phase 0 context:

- The plan version (`plan/v1` or `plan/v2`)
- Every entry: its number, title, goal, acceptance criteria and check, and for
  a `plan/v2` step whether it is detailed or an outline
- Whether this run is `/plan`'s sub-operation: `plan_topic` is in its
  arguments. A run started by a person (`/review-plan <topic>` or a PLAN path)
  is standalone, whatever session it reads.

An entry is an issue outline of a `plan/v1` plan or a `### Step <N>:` block of a
`plan/v2` plan. Under `plan/v2` an outline step is one line by design: it has no
criteria or check yet, and that absence is never a finding here.

## Behavior by Input Type

| Input type | Behavior |
|------------|----------|
| `design` | Full check |
| `prd` | Full check |
| `topic` | Full check |
| `roadmap` | Returns empty findings immediately (`critical_findings: []`) |

## Definitions

These are the PRD's definitions. Apply them as written; do not widen them.

- **Runnable check.** A criterion or `**Check**:` line that a person can run to
  observe a behaviour: a command, a walkthrough or a test whose result names an
  output, an exit code, a message or a state someone can see.
- **File-shaped criterion.** An acceptance criterion whose subject is a file
  path or a code identifier (a backticked name, or a path containing `/` or a
  file extension) paired with a construction verb (add, create, implement,
  define, update, remove, rename) and no observable result (an output, exit
  code, message or state a person can see by running something). A
  `**Files**:` line is a hint about where the work lands, never a criterion,
  and is never reported.
- **Layer-shaped plan.** A plan with three or more entries in which every entry
  before the last has no runnable check (no criterion and no `**Check**:` line
  a person can run to observe a behaviour), and the entries are named or
  grouped by component (types, model, schema, compiler, engine, core, CLI,
  command, tests, docs, templates).
- **Walking skeleton.** A first entry whose check runs it end to end: a command
  or walkthrough that crosses the integrations the plan adds on one real input
  and observes the result. A build, a type check, a compile, or a unit test of
  one component is not an end-to-end check, and a first entry with no check is
  not a skeleton.
- **Horizon.** At authoring, a `plan/v2` plan details its first two steps (every
  step when there are two or fewer) and leaves the rest as outlines. More than
  two detailed steps in a plan of three or more is past the horizon.

## The Four Tests

Run E1, E2 and E3 on every plan, and report each finding separately. E4,
the horizon test, runs only when this review is `/plan`'s sub-operation and the
plan is `plan/v2`; every other run skips it.

### E1. Layer Shape

Count the entries. With three or more, check each entry before the last for a
runnable check, reading its criteria and its `**Check**:` line (a `plan/v1`
issue has no `**Check**:` line; read its criteria alone). Then read the entry
titles and goals for the component each one builds.

Report the plan as layer-shaped when every entry before the last lacks a
runnable check and the entries are named or grouped by component. The finding
names every entry and the component it is cut by, for example "Issue 1 types,
Issue 2 compiler, Issue 3 CLI, Issue 4 tests, Issue 5 plugin templates".

A runnable check observes the behaviour the entry adds. A criterion that only
says a build, a compile or one component's unit tests pass, or that existing
behaviour and existing tests are unchanged, observes no new behaviour and does
not count.

A plan where some entry before the last has a runnable check is not
layer-shaped, even if one of its entries is named after a component.

### E2. Walking Skeleton

Read the first entry's check: its `**Check**:` line, or for a `plan/v1` issue
the criteria a person could run. Report the first entry as not a walking
skeleton when that check is a build, a type check, a compile or a unit test of
one component, or when there is none. The finding names the entry and says
what its check observes instead of an end-to-end result.

A first entry whose check runs a command on one input and observes its output
or exit code is a skeleton, even when most of the behaviour is hard-coded.

### E3. File-Shaped Criteria

For each criterion of each entry (never a `**Files**:` line), apply the
definition: a path or a backticked identifier as the subject, a construction
verb, and no observable result. Report each match with its entry and its text,
quoted as written.

A criterion that names an identifier and an observable result is behavioural:
"`greet Ada` prints `Hello, Ada`" and "`validate` exits 2 naming the step" are
not file-shaped. "Add `Transition` struct with `target: String`" and "Update
`validate()`: transition target extraction uses `t.target`" are.

### E4. Horizon (`/plan`'s sub-operation only)

Run this test only when `plan_topic` is in this run's arguments, which is when
`/plan` invokes the review at authoring, before any step's work has started.
Skip it on a standalone run: a plan reviewed later has a horizon that moved as
steps reached their terminal and their successors were detailed, so more than
two detailed steps is expected there.

When it runs, and the plan is `plan/v2` with three or more steps, count the
detailed steps. Report more than two as past the horizon, naming every detailed
step beyond step 2. `plan/v1` has no horizon and gets no E4 finding.

## Severity by Plan Version

| Finding | `plan/v2` | `plan/v1` |
|---------|-----------|-----------|
| E1 layer-shaped plan | critical, loop target 3 | advisory |
| E2 first entry not a walking skeleton | critical, loop target 3 | advisory |
| E3 file-shaped criterion | critical, loop target 4 | advisory |
| E4 past the horizon | critical, loop target 3 | not run |

Under `plan/v2` a finding goes in `critical_findings` and sends the plan back:
the cut and the horizon are decided in `/plan`'s Phase 3 (Decomposition), and a
detailed step's criteria are written in Phase 4 (Agent Generation).

Under `plan/v1` every finding goes in `advisory_findings`, never in
`critical_findings`. A `plan/v1` plan was cut by the rules of its time; the
findings tell the reviewer what a step plan would do differently, and they
change neither the verdict nor the loop target.

## Output Format

Findings use the `review_result` finding format, with the test's name leading
the description:

```yaml
- category: "E"
  description: "E1 layer-shaped: ..."   # or E2, E3, E4; name the entries
  affected_issue_ids: [1, 2, 3, 4, 5]   # entry numbers the finding names
  correction_hint: "..."                # plan/v2 critical only; "" when advisory
```

A critical finding (`plan/v2`) carries a `correction_hint` saying what the
re-cut plan or the rewritten criterion should do, in one or two sentences: for
E1, the behaviour each step should add instead of a layer; for E2, the command
step 1 should run end to end; for E3, the result the criterion should observe;
for E4, which steps to fold back to one-line outlines. The hint gives the
`/plan` phase that regenerates the plan a direction, never replacement text.
An advisory finding (`plan/v1`) changes nothing, so its hint stays empty.

An E3 description names the entry and quotes the criterion as written:

```text
E3 file-shaped: Issue 1, "Add `Transition` struct with `target: String`"
```

Report one E3 finding per criterion, so `/plan` and the reader see each one.

Return two lists for this category, `critical_findings` and
`advisory_findings`, either of which may be empty. If no test finds anything,
return both empty.

## Verdict Block

End the returned findings with a fenced block tagged `review-verdicts`
holding a JSON array with one `{"rule_id": "rs-063", "section", "verdict"}`
entry per section judged (`document` for the plan as a whole): `FAIL` where a
critical or advisory finding was raised, `PASS` otherwise
(`${CLAUDE_PLUGIN_ROOT}/references/review-verdicts.md`).
