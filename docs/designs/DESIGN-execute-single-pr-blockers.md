---
schema: design/v1
status: Accepted
upstream: docs/prds/PRD-execute-single-pr-blockers.md
user_visible_surface: false
problem: |
  Two defects halt /execute's single-pr path. The worktree-discipline gate uses
  shell-style `${PLAN_SLUG}` in a field koto executes itself, which koto neither
  resolves nor validates, so the gate tests a path with an empty slug. And
  plan-to-tasks.sh uses bash 4 constructs -- eight associative arrays plus a
  nameref -- on a platform whose system bash is 3.2, so it dies before emitting
  a task. CI hid the second defect by installing bash 5 on its macOS runner.
decision: |
  Four contained changes. Declare PLAN_SLUG as a koto template variable and
  interpolate it as `{{PLAN_SLUG}}`, so koto's compile-time declared-reference
  check turns any future typo into a build error rather than a silent empty
  expansion. Replace plan-to-tasks.sh's associative arrays with a small
  insertion-ordered key/value store built on plain strings, and its one nameref
  with positional arguments. Name the gate's expected path in the directive
  prose, which is the only failure surface koto passes through. Delete CI's
  macOS bash 5 install so the existing test suite becomes the regression guard,
  and add one grep check for the interpolation defect class.
rationale: |
  Each change stays inside the mechanism that already exists: koto's `{{KEY}}`
  substitution, the script's own helper conventions, the directive text koto
  already surfaces on a blocked gate, and the CI workflows that already watch
  these paths. The koto-variable route is the only gate fix that fails loudly on
  a future mistake -- a glob would pass on a stale file from another run, and
  deriving the slug inside the gate would put shell fragility back into the
  field that caused the defect. Removing CI's bash 5 install is what converts
  the portability fix from a one-time repair into a guarded property.
---

# DESIGN: execute-single-pr-blockers

## Status

Accepted

Mechanism choices for the two defects specified in
`docs/prds/PRD-execute-single-pr-blockers.md`. Four decisions: how the gate
resolves the plan slug, how the script drops its bash 4 dependencies, where the
diagnostic naming lives, and what guards reintroduction.

## Context and Problem Statement

`/execute`'s single-pr path runs on koto. The orchestrator template at
`skills/execute/koto-templates/execute.md` declares two variables — `PLAN_DOC`
and `PAUSE_BEFORE_FINALIZE` — and `/execute`'s SKILL.md passes both at
`koto init`. koto substitutes declared variables written as `{{KEY}}` into
directives, gate commands, and default-action commands, validating at compile
time that every `{{KEY}}` reference resolves to a declared variable
(`src/template/types.rs`, `VAR_REF_PATTERN`). Values pass a conservative
character allowlist before substitution (`src/engine/substitute.rs`), because a
substituted value can land inside a `sh -c` gate command.

The `worktree_discipline_check` state's gate is written outside that mechanism:

```yaml
    gates:
      impact_classified:
        type: command
        command: "test -f wip/work-on_${PLAN_SLUG}_impact.json"
```

`${PLAN_SLUG}` is not a koto reference. koto's compile-time check only sees
`{{KEY}}` forms, so an undeclared `${...}` passes validation untouched and koto
hands the literal string to `sh -c`. The shell expands the unset variable to the
empty string and the gate tests `wip/work-on__impact.json`. The state's
directive prose does tell the agent to derive `PLAN_SLUG` — but it derives it in
the agent's own shell, which is a different process from the one koto evaluates
the gate in. The result is a gate that cannot pass regardless of what the agent
does correctly. Every other `${...}` in the shipped templates is koto's own
`${evidence.<field>}` reference namespace, which koto resolves itself; this gate
is the only instance of the defect.

The second defect is in `skills/plan/scripts/plan-to-tasks.sh`, which converts a
PLAN's issue outlines into the koto task list `spawn_and_await` submits. The
script depends on two bash features newer than the platform floor:

- **Associative arrays** (bash 4.0) in eight places: `slug_counts`,
  `number_to_name`, `file_first_owner`, `issue_to_node`, `is_gate`, `edges_set`,
  `seen`, and `indeg`.
- **A nameref** (bash 4.3) at line 75, in `array_to_json`, which takes an array
  by variable name.

macOS ships bash 3.2.57 as `/bin/bash`, and the script's shebang is
`#!/usr/bin/env bash`. Run under the system bash the failure is immediate:

```
plan-to-tasks.sh: line 75: local: -n: invalid option
plan-to-tasks.sh: line 76: _arr_ref: unbound variable
```

The nameref at line 75 is reached before any associative array, so the
originally reported line 395 is not even the first failure — it is where a run
that somehow got past `array_to_json` would stop next. The reported defect was
one of nine.

The reason this shipped is in CI. `.github/workflows/check-plan-scripts.yml`
runs the script's test suite on a macOS runner, and installs Homebrew bash
first:

```yaml
      # plan-to-tasks.sh uses declare -A (bash 4+); macOS ships bash 3.2
      - name: Install bash 5 (macOS)
```

The macOS job has therefore never exercised the script under the bash macOS
provides. The comment records the defect accurately and works around it, so the
matrix entry that exists to catch platform breakage was the thing preventing it
from being caught.

The last piece of context is a constraint on diagnosis. koto renders a failed
command gate as `{"exit_code": N, "error": ""}` (`src/gate.rs`) — the command's
stdout and stderr are read and then discarded before the result reaches the
caller. A diagnostic echoed by a gate command goes nowhere. What koto does pass
through on a blocked gate is the state's `directive` and `details` text, with
`{{KEY}}` references already substituted.

## Decision Drivers

1. **A future mistake must fail loudly.** The defect's cost came from silence,
   not from the typo. A fix that works today but re-admits a silent failure
   tomorrow has not addressed what went wrong (PRD R1, R7).
2. **Stay inside mechanisms that exist.** koto's variable substitution, the
   script's own helpers, and the CI workflows already watching these paths can
   all carry the fix. Nothing here justifies a new subsystem (PRD R9).
3. **Output must not move.** `plan-to-tasks.sh` output feeds task names,
   collision suffixes, and the merge-order graph. A portability rewrite that
   changes ordering changes plans (PRD R4, R8).
4. **No new runtime dependency.** The fix cannot require a newer bash, a
   different interpreter, or a tool not already needed to run `/execute` (PRD
   R9).
5. **The guard must have teeth.** A check that passes because CI compensates for
   the defect is worse than no check, because it reads as coverage (PRD R5, R7).
6. **Fix the class, not the instance.** Both defects were reported as single
   lines and both are wider than reported (PRD R2, R3).

## Considered Options

### D1 — How the `impact_classified` gate resolves the plan slug

**Option 1a — Declare `PLAN_SLUG` as a koto template variable.** Add
`PLAN_SLUG` to the template's `variables:` block as required, pass
`--var PLAN_SLUG=<slug>` in `/execute`'s `koto init` call alongside the
`PLAN_DOC` and `PAUSE_BEFORE_FINALIZE` it already passes, and write the gate as
`test -f wip/work-on_{{PLAN_SLUG}}_impact.json`. koto substitutes the value
after checking it against the allowlist; plan slugs match `^[a-z0-9-]+$` and
pass. A future `{{PLAN_SLUGG}}` typo fails koto's compile-time
declared-reference check with a message naming the state and the reference.

**Option 1b — Glob for any classification file.** Write the gate as
`ls wip/work-on_*_impact.json >/dev/null 2>&1`, sidestepping the slug entirely.
It is the smallest edit and needs no new variable. It also passes on a
classification left behind by a previous run or by a different plan in the same
worktree, which turns a gate that currently never passes into one that can pass
on the wrong evidence. The worktree-discipline check exists to confirm *this*
run classified *this* upstream drift; a gate that cannot tell those apart does
not do that job.

**Option 1c — Derive the slug inside the gate command.** Write the gate as
`test -f wip/work-on_$(basename {{PLAN_DOC}} .md | sed 's/^PLAN-//')_impact.json`.
koto resolves `{{PLAN_DOC}}` correctly, so this works. It also puts command
substitution and a `sed` expression back into a `sh -c` string built from a
substituted value — the precise field whose fragility caused the defect — and it
duplicates a derivation `/execute` already performs at `koto init`. The gate
would silently succeed-with-wrong-path again if the naming convention changed on
one side only.

### D2 — How `plan-to-tasks.sh` drops its bash 4 dependencies

**Option 2a — An insertion-ordered key/value store over plain strings.** Add a
small helper block: each map becomes a string variable holding `key<TAB>value`
lines, with `kv_get` / `kv_set` / `kv_has` reading and rewriting it, and set-only
maps using `set_add` / `set_has` / `set_items` over the same shape. All eight
sites use one mechanism. No `eval`. Iteration follows insertion order, which is
*more* deterministic than the bash 4 code it replaces — associative-array key
order is unspecified hash order. Keys here are issue numbers, node ids matching
`^[a-z][a-z0-9-]*$`, `from->to` edge strings, slugs, and file paths, none of
which can contain a tab or a newline; file paths with spaces are already
unsupported by the existing unquoted `for fpath in $files_str` loop, so the
delimiter choice takes nothing away. Lookups become linear scans, which on plans
of tens of issues is not measurable.

**Option 2b — Dynamic variable names via `eval`.** Emulate maps with
`eval "m_${key}=..."`. Keys include `/` and `->`, so each key needs sanitizing
into a valid identifier first, and the sanitization has to be collision-free or
two keys silently merge. It introduces `eval` over strings derived from a plan
document the script parses — a shell-injection surface in a script that
currently has none. Rejected on that alone.

**Option 2c — Per-map bespoke rewrites.** Rewrite each of the eight sites in
whatever shape suits it: parallel indexed arrays here, a sorted list there. Each
site gets the tightest possible code. Eight mechanisms is also eight things for
a reviewer to check and eight places for a future edit to reintroduce a `-A`
because the local idiom did not suggest otherwise.

**Option 2d — Port the script to the shirabe Rust CLI.** `plan-to-tasks.sh` is
a thousand lines of graph contraction and topological ordering, which is not
what shell is for, and the repo already ships a Rust binary that could own it.
This is very likely the right long-term home. It is also a rewrite of the
single-pr path's most load-bearing script, proposed as the fix for a bug report.
Out of scope here; worth its own design.

Independent of the map question, the nameref at line 75 has one sensible
replacement: change `array_to_json` to take the elements positionally
(`array_to_json "${waits_on[@]}"`) rather than by name. All three call sites
pass the same `waits_on` array. Under `set -u`, bash 3.2 errors on `"${arr[@]}"`
for an empty array, so call sites use the `${arr[@]+"${arr[@]}"}` guard.

### D3 — Where the diagnostic naming lives

**Option 3a — Name the expected path in the directive prose.** The
`worktree_discipline_check` directive already instructs the agent to write the
classification. Have it state the literal path the gate tests, written as
`wip/work-on_{{PLAN_SLUG}}_impact.json` so koto substitutes the real slug. koto
passes `directive` and `details` through on a blocked gate, so this is the one
surface that reaches the developer. No new machinery.

**Option 3b — A preflight step the agent runs before submitting.** Add a state
or a script that checks for the file and reports. It produces a better message
than 3a in the abstract, and it adds a state to the orchestrator template to
report a condition the directive can simply name.

**Option 3c — Change koto to surface gate stdout and stderr.** The real fix for
gate diagnosability generally, and explicitly out of scope per the PRD: it is a
change to another repository, and it would block this one behind a koto release.

For the script side of the requirement, `plan-to-tasks.sh` already fails with
`single-pr PLAN has no issue outlines in ## Issue Outlines section` (line 366)
and routes every schema failure through `die_schema`, which prefixes
`[plan-to-tasks] Error:` and exits 2. That surface already satisfies PRD R6;
this design adds nothing to it.

### D4 — What guards reintroduction

**Option 4a — Delete CI's bash 5 install; add one grep check for the
interpolation class.** Removing the `Install bash 5 (macOS)` step from
`check-plan-scripts.yml` makes the existing `plan-to-tasks_test.sh` run under
the system bash, so a reintroduced `declare -A` — or any other bash 4 construct,
including ones nobody thought to grep for — fails the macOS job at the point of
use. That is strictly stronger than a pattern list. The interpolation defect has
no equivalent runtime detector, so it gets a small script that greps shipped
templates' gate and default-action command fields for shell-style
interpolation, wired into `check-templates.yml`, which already watches
`skills/*/koto-templates/**`.

**Option 4b — Two grep-based checks.** Also grep the scripts for a list of
bash 4 constructs. The list is the weakness: this investigation found namerefs
only after `declare -A` had been swept for and the script was actually run.
A hand-maintained pattern list encodes what the author remembered.

**Option 4c — Extend `shirabe validate`.** Fold both checks into the Rust
validator. It is a natural home for repo-wide invariants, and it makes the
checks available outside CI. It also means a Rust change, a release, and a
version bump before a two-line grep can run, for checks that are inherently
about this repository's own file layout rather than about the artifact schemas
`shirabe validate` owns.

To make 4a's macOS job honest, the test invocation is pinned to `/bin/bash`
explicitly rather than `bash`, so a Homebrew bash that happens to be on the
runner's PATH cannot silently restore the old behavior.

## Decision Outcome

**D1: Option 1a** — `PLAN_SLUG` becomes a declared koto template variable,
passed at `koto init`, referenced as `{{PLAN_SLUG}}`.

This is the only option that makes the next mistake loud. koto validates
`{{KEY}}` references against the template's `variables:` block at compile time,
so a typo becomes a template error naming the state and the reference, rather
than an empty expansion nobody sees. The glob would trade a gate that never
passes for one that passes on a stale file, and in-gate derivation would put
shell fragility back where the defect started. It also matches how the sibling
`work-on.md` template already writes a slug-dependent gate
(`check-staleness.sh --issue {{ISSUE_NUMBER}}`), so the two templates stop
disagreeing about which mechanism to use.

**D2: Option 2a**, plus positional arguments for `array_to_json`.

One mechanism at nine sites, no `eval`, and iteration order that is deterministic
by construction. The output-stability requirement (PRD R4) is met rather than
hoped for: the two places that iterate an associative array's keys today
(`edges_set` when clearing, and `indeg` when summing in `kahn_order`) are
order-insensitive, and everything that reaches the output is already driven by
`node_order` and `issue_numbers`, which are built in first-appearance order.
Replacing hash-ordered iteration with insertion-ordered iteration therefore
cannot move the output, and `plan-to-tasks_test.sh` is the check that it did not.

**D3: Option 3a** — the directive names the path.

koto discards gate output, so the directive is the only surface that reaches the
developer. Naming the path there costs one sentence and turns "gate failed,
exit 1" into "gate failed, exit 1; the directive says it wants
`wip/work-on_execute-single-pr-blockers_impact.json`". The script side needs no
change; `die_schema` already reports what is missing.

**D4: Option 4a** — delete the CI workaround, add one interpolation grep.

The bash guard is the test suite running on the platform floor, which catches
constructs nobody enumerated. The interpolation guard is a grep, because there
is no runtime that exercises a template's gate strings in CI. Pinning the macOS
invocation to `/bin/bash` keeps the guard from being re-defeated by a PATH.

## Solution Architecture

Four change sites, no new components.

```
skills/execute/koto-templates/execute.md
  variables:                    + PLAN_SLUG (required)
  worktree_discipline_check:
    gates.impact_classified.command
                                ${PLAN_SLUG} -> {{PLAN_SLUG}}
    directive prose             + names wip/work-on_{{PLAN_SLUG}}_impact.json

skills/execute/SKILL.md
  Step 2 koto init             + --var PLAN_SLUG=<plan-slug>

skills/plan/scripts/plan-to-tasks.sh
  helper block                 + kv_get / kv_set / kv_has
                               + set_add / set_has / set_items
  array_to_json                nameref -> positional args (3 call sites)
  8 associative arrays         -> string-backed stores

.github/workflows/check-plan-scripts.yml
  "Install bash 5 (macOS)"     removed
  test invocation              bash -> /bin/bash on the macOS leg

scripts/check-template-interpolation.sh   (new)
scripts/check-template-interpolation_test.sh (new)
.github/workflows/check-templates.yml     + runs the check
```

### The key/value store

Each map is one string variable. Entries are `key<TAB>value`, one per line, in
insertion order. Set-shaped maps store the key with an empty value.

```
kv_set <store-var> <key> <value>   # replace-or-append, preserving position
kv_get <store-var> <key>           # value on stdout, empty if absent
kv_has <store-var> <key>           # exit 0 if present
set_add <store-var> <key>          # no-op if present
set_has <store-var> <key>          # exit 0 if present
set_items <store-var>              # keys, one per line, insertion order
```

The helpers read the store through `${!name}` indirect expansion, which bash 3.2
supports, and write through `printf -v`. Neither needs `eval`. Membership tests
use a `case` glob against the store bracketed with newlines, which avoids
spawning a process per lookup.

### The interpolation check

`scripts/check-template-interpolation.sh` walks `skills/*/koto-templates/*.md`,
extracts gate `command:` values and `default_action` command values, and fails
when one contains `$NAME` or `${NAME}`. `${evidence.<field>}` is not matched
because it only appears in `context_assignments`, which the check does not read;
`{{KEY}}` is not matched by the pattern at all. The script follows the existing
`scripts/check-sentinel.sh` shape and ships with a `_test.sh` companion, as the
repo's other check scripts do.

## Implementation Approach

Four batches, sequenced so each lands independently green. The batches are
ordered by dependency, not by importance: the CI change must land with or after
the script change, or the macOS job fails on the unfixed script.

1. **Gate resolution.** Declare `PLAN_SLUG`, pass it at `koto init`, switch the
   gate to `{{PLAN_SLUG}}`, and name the path in the directive. This covers D1
   and D3 together — they touch the same two files and separating them would
   mean editing the same state twice.
2. **Script portability.** Add the helper block, convert `array_to_json` to
   positional arguments, and convert the eight maps. Verified by running
   `plan-to-tasks_test.sh` under `/bin/bash` and by diffing the script's output
   for a representative plan against the pre-change output under bash 5.
3. **CI honesty.** Remove the bash 5 install and pin the macOS test invocation
   to `/bin/bash`. Depends on batch 2; landing it first turns the macOS job red.
4. **Interpolation guard.** Add the check script, its test, and the workflow
   step. Independent of the others, but sequenced last so it lands against a
   tree that already passes it.

## Security Considerations

The relevant surface is command construction, and this design narrows it.

**Gate command interpolation.** Moving the slug from shell expansion to koto
substitution puts the value behind koto's allowlist
(`^[a-zA-Z0-9._/:@ \-]*$`, `src/engine/substitute.rs`), which is validated at
`koto init` and re-validated when read back from the event log. The value being
substituted is a plan slug matching `^[a-z0-9-]+$`, so it passes; more to the
point, a value that did not pass would be rejected rather than concatenated into
a `sh -c` string. The current code has no such check — an attacker-controlled
`PLAN_SLUG` in the agent's environment would be expanded by the shell with no
validation at all. That the variable is currently always empty is the only
reason this is not already exploitable.

**`eval` avoidance in the script.** Option 2b would have introduced `eval` over
keys derived from a PLAN document — a file the script parses and does not
control. Rejecting it keeps `plan-to-tasks.sh` free of `eval`, which it is
today. The chosen helpers use `${!name}` and `printf -v` over caller-supplied
variable names, which are literals in the script, not values from the plan.

**Delimiter injection into the store.** A key containing a tab or a newline
would corrupt a store's framing and could make one key's lookup return another's
value. The keys are issue numbers, node ids already validated against
`^[a-z][a-z0-9-]*$` by `validate_name`, edge strings built from those node ids,
slugs from `slugify` (which reduces to `[a-z0-9-]`), and file paths from the
plan. Only file paths are unconstrained, and the existing unquoted
`for fpath in $files_str` loop already word-splits them, so a path containing
whitespace is already mishandled upstream of the store. The implementation
should reject a key containing a tab or newline rather than rely on that, since
the guarantee costs one test per `kv_set`.

**The check script.** `check-template-interpolation.sh` reads repository files
and writes nothing. It runs in CI on pull-request content, so it must not
execute what it reads — it greps, and does not source or evaluate template
content.

## Consequences

**Positive.**

- The single-pr path completes on a default macOS host, which is the point.
- The gate's failure mode changes category: a future typo in the slug reference
  is a koto compile error naming the state, not an empty expansion.
- CI's macOS job starts testing what it was added to test. The bash guard now
  covers constructs nobody enumerated, including the nameref class this
  investigation only found by running the script.
- The gate command gains value validation it did not have, because koto's
  allowlist now sits between the slug and the `sh -c` string.
- `plan-to-tasks.sh` output becomes deterministic by construction rather than
  incidentally, since insertion order replaces unspecified hash order.

**Negative, and what is done about it.**

- **The script gets longer and its map operations get slower.** Nine call sites
  move from a language feature to hand-written helpers, and lookups go from
  hashed to linear. At plan sizes of tens of issues the cost is not measurable,
  and the helpers are six short functions in one block rather than logic
  scattered across the file. The real cost is that a reader now has to learn a
  local convention; the block carries a comment explaining why it exists.
- **Shell remains the wrong language for this script.** Nothing here changes
  that a thousand lines of graph contraction live in bash, and option 2d names
  the better home. This design deliberately does not take that on, which means
  the next portability question lands on the same file. Recording 2d here is the
  mitigation: the argument does not have to be rebuilt.
- **The interpolation check is a grep, and greps are approximations.** It reads
  gate and default-action command fields and will not catch a shell-style
  reference introduced somewhere koto later starts executing. The compensating
  control is koto's own compile-time check on `{{KEY}}` forms, which covers the
  correctly-written case; the grep only has to catch the incorrectly-written one.
- **Removing CI's bash 5 install can surface unrelated breakage.** Any other
  bash 4 dependency reachable from `plan-to-tasks_test.sh` or
  `validate-plan_test.sh` will now fail the macOS job. The sweep found none
  outside `plan-to-tasks.sh`, and batch 3 is sequenced after batch 2 so the
  failure, if it happens, lands in the batch that can fix it.
