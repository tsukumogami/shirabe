# Step Template (plan/v2)

The shape of one entry under `## Steps` in a `plan/v2` plan. `/plan` uses it
only when the resolved plan version is `v2`: Phase 3 drafts every step's
title and goal, Phase 4 writes the detailed steps from it, and Phase 7 copies
each block into the plan as it stands. A `v1` run never reads this file.

A step is either **detailed** or an **outline**. At authoring, steps 1 and 2
are detailed (every step when there are two or fewer) and every later step is
an outline. Detailed steps come first: no detailed step follows an outline.
`shirabe validate` checks the shape (FC22); the rules are in
`../plan-format.md` under "plan/v2: Step Plans".

## Template Variables

- `{{N}}` - the step number, from 1, no gap, no leading zero
- `{{TITLE}}` - the behaviour the step adds, said so a person could check it
  ("report export quotes fields that need it", not "add the quoting module")
- `{{GOAL}}` - one or two sentences: what changes for someone running the
  thing. Step 1's goal names the integration it crosses and the input it runs
  on
- `{{CRITERIA}}` - one or more `- [ ]` items, each an observable result: an
  output, an exit code, a message, or a state a person can see by running
  something
- `{{CHECK}}` - the command, test or walkthrough that shows the behaviour, and
  the result that shows it. Step 1's check runs the skeleton end to end
- `{{DEPENDENCIES}}` - `None`, or `Step <N>` references to earlier steps,
  comma-separated (`Step 1, Step 2`)
- `{{FILES}}` - optional: backticked paths the step expects to touch, a hint
  for conflict detection, never a criterion
- `{{OUTLINE}}` - one line naming the behaviour the step will add

## Detailed Step

```markdown
### Step {{N}}: {{TITLE}}

**Goal**: {{GOAL}}

**Acceptance Criteria**:

- [ ] {{CRITERIA}}

**Check**: {{CHECK}}

**Dependencies**: {{DEPENDENCIES}}

**Files**: {{FILES}}
```

Drop the `**Files**:` line when there is no hint to give. `**Type**:` and
`**Complexity**:` may be added with their `plan/v1` meaning.

A step that corrects behaviour someone reported as wrong adds a
`**Fixes**:` line after its goal, naming the report in one sentence or
by issue reference:

```markdown
**Fixes**: greet prints Hello for an empty name instead of error: name required
```

The step's run is then a fix: it records a failing check whose output
holds a marker from this line before it changes any code
(`../../../work-on/references/red-first.md`). Use only letters, digits,
spaces and `. _ / : @ + -`; `plan-to-tasks.sh` refuses other characters,
because the line reaches the run as a koto variable.

## Outline Step

```markdown
### Step {{N}}: {{TITLE}}

{{OUTLINE}}
```

Exactly one non-blank line under the heading, and no `**Field**:` line: no
goal, no criteria, no dependencies. The plan's owner turns it into a detailed
step later, after the step before it reaches its terminal.

## Writing the Criteria

A criterion describes what a person sees, not what an author builds.

| File-shaped (don't) | Behavioural (do) |
|---|---|
| Add `QuoteWriter` in `src/csv.rs` | A field holding a comma prints inside double quotes |
| Create the `--columns` flag | `--columns name,total` prints only those two columns |
| Update `config.rs` to read `greeting` | With `greeting = "Hi"` in the config, `greet Ada` prints `Hi, Ada` |

A criterion is file-shaped when its subject is a path or a code identifier,
its verb is a construction verb (add, create, implement, define, update,
remove, rename), and it names no result anyone could observe. `/review-plan`
reports file-shaped criteria; rewrite them before the plan is written.

## Writing the Check

The check is what the worker runs to show the step works, and what the
worker's report quotes with its result. Make it a command or walkthrough
with a result to look for ("run `report export sample --format csv | head
-3` and see the header and two rows"), not "tests pass". Step 1's check must
cross the whole path the skeleton opens, not one component of it.

A check is an instruction the worker runs with its own permissions. Write it
so a reviewer can read it like code: no download-and-run, no command built
from document text.
