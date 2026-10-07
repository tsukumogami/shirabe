---
schema: design/v1
status: Current
problem: |
  /work-on routes every code-typed issue through scrutiny, review and QA, and
  nothing in its template carries an intended review level, checks a level
  against the change, takes a bound from a coordinator, or records any of it.
  The level has to be a value koto can route on mid-run, raised after
  implementation when the facts call for it, without a new engine primitive.
decision: |
  A rebindable REVIEW_LEVEL template variable, set only through a new
  review-level.sh that re-attaches the session to rebind it and appends to a
  JSONL ledger in context. A new review_level_choice state after analysis
  holds until the variable is set; a new review_level_check state between
  issue_type_routing and the panels gathers facts, applies a deterministic
  floor from a rules file through a command gate, carries a veto-mode decider
  check, and routes on the variable to a new one-seat light panel or to
  scrutiny. The review panel's passed routes split on the level to skip QA at
  standard. REVIEW_FLOOR and REVIEW_CEILING variables carry a coordinator
  bound from new --review-floor/--review-ceiling flags through /deliver and
  /execute, and the coordinate brief renders them from a review_level field.
rationale: |
  koto routes `when` clauses on declared variables, rebind ones included, and
  `koto init --attach-live` rebinds a live root or child session's variable
  mid-run, so a variable is the one place a level can live, change after
  implementation, and still route without new engine work. A command gate
  makes the floor apply to every user; the decider check adds judgment only
  where a user has opted in. Putting the light panel through panel-scope.sh
  as one more panel keeps sticky verdicts, packets and records unchanged.
upstream: docs/prds/PRD-review-level-up-front.md
user_visible_surface: false
---

# DESIGN: review-level-up-front

## Status

Current

Amended after review of the implementing pull request, before it merged: the
path classes gained `engine`, `instruction` and `manifest`, `template` and
`engine` floor at `full`, a path in no class floors at `standard`, `facts`
diffs from the larger of `impl_base` and the merge-base with the default
branch, and `review` and `light_review` re-check the variable against the
ledger on their level routes. The sections below describe the amended shape.

## Context and Problem Statement

The PRD asks for three named review levels in `/work-on` (`light`: one seat;
`standard`: scrutiny then review, six seats; `full`: scrutiny, review and QA,
seven seats), chosen before implementation, routed on by koto, raised but
never lowered by objective facts and by a veto-only decider check, bounded by
a coordinator, and recorded in a per-run ledger a script reads.

Today `skills/work-on/koto-templates/work-on.md` goes
`analysis → implementation → changed_paths_record → issue_type_routing`, and
`issue_type_routing` sends `code` to `scrutiny → review → qa_validation →
verification` with no other choice. Three properties of the current system
shape every decision here:

- **What koto can route on.** A `when` clause can test evidence, gate output,
  and, since koto's value routing, `vars.NAME: <value>` on a declared
  variable, rebind ones included. It cannot route on a context key or on a
  capture. A level that lives anywhere but a variable needs a gate per route
  that reads it back.
- **What can change a variable mid-run.** A declared `rebind: true` variable
  is re-applied by `koto init <session> --template <path> --attach-live --var
  NAME=VALUE`. Checked on koto 0.15.0 with a scratch template: a live root
  session and a child materialized by a parent both accept the attach with
  only the rebind variable passed, report `rebound`, and the next tick routes
  on the new value. A session's template path is readable from `koto status`.
  On the shipped `work-on.md` the attach must also pass `PLUGIN_ROOT`, which
  is required and rebindable: an attach re-applies every rebind variable from
  its own arguments, resetting one it omits (found wiring the template in).
- **What the panels already keep.** Since shirabe#596, each panel state runs
  `panel-scope.sh --plan <panel>` on entry, keeps `verdict_ledger.json` with a
  per-round spawn count, and gates its edges on `--carried` and `--recorded`.
  Since shirabe#595 each seat is commissioned with a model, a budget and a
  `review-packet.sh code` packet. shirabe#588 (open) rewrites the retry-cap
  paragraphs of the three panel directives and adds `panel_retries`.

The bound has to cross three skills to reach a `/work-on` run started by
`/execute` under `/deliver`, because `/deliver` forwards only the mode, the
leg and the merge switch to `/execute`, and `/execute` builds each child's
variables from `plan-to-tasks.sh` plus a `jq` that injects `SHARED_BRANCH` and
`PLUGIN_ROOT`. The coordinate brief has no field for it.

## Decision Drivers

- **D1. No new koto primitive** (a coordinator decision): only value routing
  on variables, command gates, `default_action`, `context_assignments` and
  veto-mode `decider-check` gates.
- **D2. The floor must protect every run.** A veto-mode decider check acts
  only for a user whose effective decider mode is `auto`; a guarantee can't
  rest on it (PRD R12, R13).
- **D3. Recorded or refused, never half.** Setting a level must update the
  variable and the ledger together, or neither (PRD R6), and a hand change
  of the variable must show up (PRD R6).
- **D4. Don't reshape #595, #596, or #588's lines** (PRD R20). New behaviour
  sits beside the panel states, not inside their retry machinery.
- **D5. Old sessions and init sites keep today's route** when the level is
  unset (PRD R19).
- **D6. Data, not code, for thresholds** (PRD R11): one rules file.
- **D7. Bash 3.2, jq, koto only**, like every shirabe script, each with a
  `_test.sh` on the floor list (PRD R21).

## Considered Options

### Decision 1: where the level lives

**Chosen: a rebindable `REVIEW_LEVEL` template variable, rebound through a
re-attach.** It is the only store koto routes on directly (D1), and the
re-attach works on root and child sessions alike.

**Alternative: a context key read by command gates.** `review-level.sh get`
would exit 0, 1 or 2 per level and every level-dependent edge would test that
gate. No re-attach is needed. Rejected because it multiplies gates (the
level check's three routes plus both review routes, each needing the gate
declared on its state), every gate is a process per tick, and the PRD (R2)
and the issue both ask for koto's routing on variable values.

**Alternative: evidence submitted at a level state, carried by path.** A
`light` path and a `standard`/`full` path through separate copies of the
panel states. Rejected: duplicating three panel states doubles the template
surface #588 and #596 edit, and a raise after implementation would need a
jump between copies.

### Decision 2: when the level is chosen

**Chosen: a new `review_level_choice` state between `analysis` and
`implementation`** whose only route forward is `vars.REVIEW_LEVEL: {is_set:
true}`. Its `default_action` records the bound line and the acceptance
criteria copy, then it holds until the agent runs `review-level.sh set`.
`analysis` stays as it is, apart from its `plan_ready` target.

**Alternative: gate `analysis`'s `plan_ready` route on the variable.** Fewer
states, but `analysis` already has a `default_action` (recording
`impl_base`), and the bound and criteria copy need writing before the first
`set` reads them. A second action can't share the state, and folding both
into `record-changed-paths.sh --base` would couple two unrelated records.

**Alternative: choose at init, from a flag.** Earliest possible, but before
the agent has read the issue's code, and an `/execute` child has no one to
pick it at init. Planned levels from `/plan` are out of scope.

### Decision 3: how the facts raise the level

**Chosen: a command gate on a new `review_level_check` state, plus a veto-mode
decider check on the same state.** The state's `default_action` runs
`review-level.sh facts`, which writes `review_facts.json` and appends a
`check` line; the gate runs `review-level.sh check` with the variable's value
and exits 0 only when the level is at or above the floor, matches the
ledger's last level, and sits inside the bound or has a recorded breach.
Holding is koto's normal gate behaviour, and `koto overrides record` is the
recorded way past it (D2).

**Alternative: let the facts action raise the level itself.** The action
would re-attach the session from inside a `koto next`. Rejected: a nested
`koto init` while the tick holds the session is untested ground, and a raise
the agent never sees is a raise nobody reasons about.

**Alternative: decider check only.** Matches the issue's wording literally,
but inert for every user not opted in (D2).

### Decision 4: the light panel

**Chosen: a new `light_review` state that is a fourth panel to
`panel-scope.sh`** (`light) SEATS="reviewer"`), with the same `--plan`
action, `--carried` and `--recorded` gates and the same three outcomes as
`review`. The seat is commissioned like a review seat (Sonnet, `review-packet.sh
code`) with one prompt that covers correctness against the acceptance criteria
and maintainability. Passed goes to `verification`; `blocking_retry` to
`implementation`.

**Alternative: run the `scrutiny` state with one seat.** Fewer states, but
`panel-scope.sh`'s seat list per panel is fixed, so a one-seat scrutiny needs
a level-aware seat list inside #596's script, and scrutiny's intent and
justification lenses aren't what a one-seat review should judge.

### Decision 5: carrying the bound

**Chosen: `REVIEW_FLOOR` and `REVIEW_CEILING` variables on `work-on.md`,
`execute.md` and `deliver.md`, set from `--review-floor=<level>` and
`--review-ceiling=<level>`**, each declared with the pattern
`^(light|standard|full)?$`, not rebindable on `work-on.md` (a bound doesn't
move inside a run) and forwarded the way `--max-rounds` is: `deliver-open.sh`
and `execute-open.sh` map the flags, `deliver.md`'s `execute_run` directive
appends them when non-empty, and `execute.md`'s spawn `jq` sets them on every
child's `vars`. The floor-above-ceiling check is `review-level.sh`'s, at the
first `set`, because koto can't compare two variables.

**Alternative: the worker passes the bound to `review-level.sh set` from its
brief.** No plumbing, but nothing would hold a worker to it, and an `/execute`
child never sees the brief.

## Decision Outcome

The level is a rebindable variable that only `review-level.sh set` changes,
in one call that rebinds it through a re-attach and appends to a JSONL ledger
in context. The run chooses it in a new state right after `analysis`, and a
new state right before the panels checks it against facts and a bound, holds
until it's high enough, and routes on it. A one-seat panel joins
`panel-scope.sh` as a fourth panel. The review panel's passed routes split on
the level so `standard` skips QA. A coordinator bound rides two more
variables from the brief through `/deliver` and `/execute`. A reader
subcommand turns the ledgers of retained sessions into one TSV row each.

## Solution Architecture

### Template changes (`skills/work-on/koto-templates/work-on.md`)

```
analysis --plan_ready--> review_level_choice --(REVIEW_LEVEL set)--> implementation
... issue_type_routing --code--> review_level_check
review_level_check --(check gate 0, level=light)--> light_review --passed--> verification
review_level_check --(check gate 0, level=standard|full)--> scrutiny --> review
review_level_check --(level unset)--> scrutiny                        (records `unset`)
review --passed, level=standard--> verification
review --passed, level=full or unset--> qa_validation
light_review --blocking_retry--> implementation
```

New variables:

| Variable | Pattern | rebind | required |
|---|---|---|---|
| `REVIEW_LEVEL` | `^(light\|standard\|full)?$` | yes | no |
| `REVIEW_FLOOR` | same | no | no |
| `REVIEW_CEILING` | same | no | no |

An optional variable with no default resolves to the empty string, so each
pattern admits it, and koto treats the empty value as `is_set: false` in a
`when` clause (both checked on koto 0.15.0). koto applies the pattern at init
and on every `--attach-live` rebind (a rebind to `light;touch x` is refused
with `invalid_var`), so the only strings `{{REVIEW_LEVEL}}` can substitute
into a gate or action command are the three names and the empty string.
None of the three is `required`, so `check-init-site-vars.sh` stays green at
every step of the rollout.

`analysis`'s `plan_ready` route now targets `review_level_choice` instead of
`implementation`; its gate and evidence are unchanged. This amends the PRD's
first routing criterion: with no level recorded the session doesn't reach
`implementation`, and it waits in `review_level_choice` rather than in
`analysis`.

`review_level_choice`:
- `default_action`: `review-level.sh init "{{SESSION_NAME}}" "{{REVIEW_FLOOR}}"
  "{{REVIEW_CEILING}}"`, which appends the `bound` line once, stores the
  bound in `review_level_bound.json`, stores the acceptance-criteria text
  `review-packet.sh` would carry in `review_level_criteria.txt`, and stores a
  copy of the plugin's rules file in `review_level_rules.tsv`. Idempotent: a
  second run finds the bound line and writes nothing.
- `accepts`: `level_status` (enum `blocked`) and `detail` (string).
- routes: to `implementation` when `vars.REVIEW_LEVEL: {is_set: true}`; to
  `done_blocked` when `vars.REVIEW_LEVEL: {is_set: false}` and
  `level_status: blocked`, with `failure_reason` from `detail`.
- directive: the three levels in one line each, the rule that the choice is
  made from the issue and the analysis plan, and the `set` command. `set`
  run before this state's action has stored the bound exits 1 with
  `refused: no bound recorded yet`, so a choice can't skip the bound.

`review_level_check`:
- `default_action`: `review-level.sh facts "{{SESSION_NAME}}"
  "{{REVIEW_LEVEL}}"`. Runs `git diff -z --numstat -M <base> HEAD`
  (NUL-separated, so no path can shift a field) from two bases, the stored
  `impl_base` and the merge-base of HEAD with the default branch
  (origin/HEAD's branch, else `origin/main`, else `main`), and keeps the
  larger diff: more changed lines, then more files, a tie keeping
  `impl_base`. An `impl_base` recorded after some of the work can't hide that
  work this way. With no merge-base (no shared history) `impl_base` is used
  alone. Classifies both sides of a rename with the rules copy
  `init` stored (never the working tree's or the plugin's current file, so a
  diff that edits the rules can't lower its own floor), compares criteria
  text with the stored copy, writes `review_facts.json` (`lines`, `files`,
  `classes`, `tests_changed`, `criteria_changed`, `unclassified`, `floor`,
  `rules_fired` as rule names only, `head`, `base`, `base_source` naming the
  base that won, and `bases` holding both candidates) and appends a `check` line when the head, level
  or floor differs from the last one, or an `unset` line when the level is
  empty. koto runs a state's action again on every tick that reaches it
  without evidence, gate-blocked retries included, so after a hold and a
  `set`, the next tick appends a `check` line at the raised level; that is
  the line `report` reads as the run's final level.
- gate `level_floor` (command): `review-level.sh check "{{SESSION_NAME}}"
  "{{REVIEW_LEVEL}}"`. Exit 0 pass; exit 1 hold, printing `hold:` and the
  reason: below the floor (naming the rule), the variable differs from the
  ledger's last level, outside the bound without a breach line, or
  `review_facts.json` was gathered at another head than HEAD (more commits
  landed while the state held; the next tick's action re-gathers); exit 3
  when the level is empty, printing nothing, so the unset route can test it.
- gate `level_fits_facts` (`decider-check`): command `review-level.sh slice
  "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}"` prints a fixed `jq` projection of
  the facts (the counts, class names, booleans and the floor) and a `level:
  <x>` line, never a path, reason or issue text; `max_bytes: 2048`; one
  criterion, `mode: veto`, `rule_ref` to the level reference, question:
  "Given these facts about a change and the review level definitions, is the
  chosen level too light?" with `fail` meaning too light. No route reads it.
  koto blocks a state on a failing veto check even when a route's other
  conditions hold ("a blocking check stops the state even when it accepts
  evidence", koto's decider guide), so a veto holds the run like the floor
  does; the directive then says to raise with `set --cause
  veto:level_fits_facts` or record a koto override. A poisoned or wrong
  answer can only hold the run, never route it or lower the level.
- `accepts`: `level_status` (enum `blocked`) and `detail`.
- routes:
  - `gates.level_floor.exit_code: 0` and `vars.REVIEW_LEVEL: light` →
    `light_review`
  - `gates.level_floor.exit_code: 0` and `vars.REVIEW_LEVEL: standard` →
    `scrutiny`; same for `full`
  - `gates.level_floor.exit_code: 3` and `vars.REVIEW_LEVEL: {is_set:
    false}` → `scrutiny`
  - `gates.level_floor.exit_code: 1` and `level_status: blocked` →
    `done_blocked`. A route with no gate condition would share no field
    with the others and fail koto's exclusivity check (checked with a
    scratch template of this exact shape, which compiles and routes the
    unset case to its target).

`review` passed routes (both the carried one and the evidence one) gain one
`vars.REVIEW_LEVEL` condition each: `standard` → `verification`; `full` →
`qa_validation`; `{is_set: false}` → `qa_validation`. The level is checked
against the facts only at `review_level_check`, so these routes, and
`light_review`'s two passed routes, also require a `level_unchanged` command
gate, `review-level.sh agree "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}"`: exit 0
when the variable equals the ledger's last level (both empty is the unset
route), 1 otherwise. A hand rebind made while the run sits in either state
then matches no passed route, so the state holds, its directive naming the
`set` to the ledger's level that clears it, instead of skipping QA with the
ledger untouched. `scrutiny`, `qa_validation` and their
directives' retry-cap paragraphs are untouched. The `review` directive gets
one sentence after its outcome paragraph saying where `passed` goes at each
level, outside the lines #588 rewrites. Every retry clearing loop that
removes `scrutiny_results.json review_results.json qa_results.json` also
removes `light_results.json`, so a stale light result can't satisfy the
next lap's results gate.

### `skills/work-on/scripts/review-level.sh`

One script, subcommands:

| Subcommand | Called by | Effect | Exits |
|---|---|---|---|
| `init <s> <floor> <ceiling>` | `review_level_choice` action | bound line; bound, criteria and rules-copy keys | 0, 64, 66 |
| `set <s> <level> [--reason t] [--cause veto:<c>]` | the agent | decide, rebind, append | 0, 1, 64, 66 |
| `facts <s> [<level>]` | `review_level_check` action | facts key, `check`/`unset` line | 0, 64, 66 |
| `check <s> <level>` | `level_floor` gate | read-only verdict | 0, 1, 3 |
| `agree <s> <level>` | `level_unchanged` gate | variable matches the ledger | 0, 1 |
| `slice <s> <level>` | decider check | prints facts and level | 0 |
| `report [<s>...]` | a maintainer | TSV | 0, 2, 64 |

Exit 64 is a usage error (a bad level, session name, flag or rules file, or
no git base for `facts`); 66 is a koto call that failed, the rebind or a
context read or write. `check` holds with 1 on anything it can't read or
judge, so the gate never exits a code no route reads.

`set` decides from the current level (the ledger's last `to`), the bound key,
the facts key when present, and its arguments:

- no current level: `choose`; refused outside the bound, or when the bound's
  floor is above its ceiling.
- higher: `floor_raise` when the new level equals the current facts floor
  and the current level is below it; `veto` when `--cause veto:` is given;
  otherwise `raise`. Above the ceiling, a `floor_raise` passes as is and adds
  `breach`; any other raise needs `--reason` and adds `breach`.
- lower: needs `--reason`; refused below the facts floor or the bound floor.
- equal: no level event; re-appends nothing, but a variable that drifted from
  the ledger is rebound to it, which clears the mismatch hold.

A `--reason` has control characters replaced by spaces and is cut to 200
characters before it is stored.

Then it rebinds: runs `koto init <s> --template <skill>/koto-templates/work-on.md
--attach-live --var REVIEW_LEVEL=<level>` with the template this script
ships beside (`koto status` reports only the compiled cache path, and koto
refuses an attach whose template hash differs from the session's, which is
the real guard against attaching the wrong template), checks the `rebound`
(or unchanged) reply, appends the ledger line with `koto context add`, and
reads both back. A failed rebind writes no ledger line (exit 66). A failed
append after a successful rebind rebinds back to the previous level before
exiting 66, so the two never disagree on exit. A plugin update between the
run's start and a `set` changes the template hash, so koto refuses the
attach and `set` exits 66 naming the mismatch; the run goes on at its
current level.

### Rules file: `skills/work-on/references/review-level-rules.tsv`

Tab-separated, `#` comments. Two record types:

```
class	ci	.github/workflows/**
class	security	**/hooks/**
class	template	**/koto-templates/**
class	engine	skills/work-on/scripts/review-level.sh
class	instruction	**/SKILL.md
class	docs	*.md
...
rule	full	class:ci
rule	full	class:template
rule	full	class:engine
rule	full	lines>400
rule	full	files>12
rule	standard	class:instruction
rule	standard	unclassified
rule	standard	criteria_changed
rule	standard	lines>40
```

The shipped classes: `ci`; `security` (with secrets: `.env`, `.env.*`,
`*.pem`, `*password*`); `template` and `engine` (every script a template
names in a gate's or a `default_action`'s command, plus every `*-open.sh`,
kept in step with the templates by a test), both at `full`; `instruction`
(`SKILL.md`, `references/**` at any depth, `CLAUDE.md`, `AGENTS.md`),
`executable`, `test` and `manifest` (lockfiles and package manifests,
`requirements*.txt` among them) at `standard`; and `docs` (`*.md`, `docs/**`,
`*.txt`, `LICENSE`), which no rule names. The `unclassified` fact fires when a
changed path is in no class, so `light` is reachable only when every changed
path is documentation or in a class no rule names.

Globs are matched by bash `case` patterns on the path, with `**/` also
matching zero directories. The floor is the highest level any rule yields;
`light` when none fires. The script refuses (exit 64) a file with an unknown
record type, level or fact name, so a typo can't silently drop a rule.

### Ledger: context key `review_level.jsonl`

One JSON object per line, appended with `koto context get` + `jq` + `koto
context add` on the whole key (koto has no append verb; the read-back
confirms the line). Fields per the PRD: `ts`, `event`, and `from`, `to`,
`reason`, `rule`, `floor`, `ceiling`, `level`, `head` as the event needs. Not
named by any retry clearing loop; a test greps every clearing site.

### `light_review` and `panel-scope.sh`

`panel-scope.sh` gains `light) SEATS="reviewer" ;;` in its panel switch and
`light` in its usage text; nothing else in the script changes. The template's
`light_review` state is a copy of `review`'s shape with `light` for the panel
name and `light_results.json` for the results key, plus scrutiny's
`has_commits` gate on its evidence `passed` route: at `light` scrutiny never
runs, and that gate is what stops a code run with no commits since
`impl_base` from reaching verification. A new phase file,
`references/phases/phase-4d-light.md`, holds the seat's commissioning line
and prompt.

### Level reference: `skills/work-on/references/review-levels.md`

Defines the three levels (panels, seat counts), the choose/raise/lower rules,
the bound, the floor rules (pointing at the TSV), and the ledger events. The
decider check's `rule_ref` and the choice directive point here.

### Bound plumbing

- `work-on.md`: the two variables. `SKILL.md`'s direct init lines add `--var
  REVIEW_FLOOR=` and `--var REVIEW_CEILING=` from `--review-floor=` and
  `--review-ceiling=` tokens; `work-on-open.sh` already takes `--var`.
- `execute.md` and `execute-coordinated.md`: the two variables; the spawn
  `jq` adds `.vars.REVIEW_FLOOR = $f | .vars.REVIEW_CEILING = $c` only when
  non-empty; the coordinated prose names them. `execute-open.sh` maps the
  flags.
- `deliver.md`: the two variables; `execute_run`'s directive appends
  `--review-floor={{REVIEW_FLOOR}}` and `--review-ceiling=` when non-empty.
  `deliver-open.sh` maps the flags.
- `entry-points.tsv`: `--review-floor=*,--review-ceiling=*` added to the
  `deliver`, `execute` and `work-on` rows.
- `render-brief.sh`: an optional `review_level` object (`floor`, `ceiling`);
  refused when either value isn't a level name, the floor is above the
  ceiling, or the entry point doesn't allow the flags. Rendered as one line
  in Acceptance criteria ("Review level: floor X, ceiling Y; /work-on's
  choice must fall inside it.") and as the two flags appended to the
  invocation. Absent, the output is byte-identical.
- `brief-template.md`: the line shown in the Acceptance criteria block.

### Reader

`review-level.sh report` lists sessions from `koto workflows` whose
`template_path` ends in `work-on.md` (or those named), reads
`review_level.jsonl`, `verdict_ledger.json` and `koto overrides list`, and
prints the PRD's columns. `final` is the level of the last `check` line
whose level is at or above its floor.

## Implementation Approach

1. **Level script and rules.** `review-level.sh` with every subcommand,
   `review-level-rules.tsv`, `review-levels.md`, `review-level_test.sh`
   against a koto stand-in and a real koto scratch session (rebind, ledger,
   refusals, facts on fixture commits, thresholds, report). Wired into
   `check-work-on-scripts.yml` and `check-bash-floor.sh`.
2. **Template wiring.** The two new states, `light_review`, the review
   routes, the variables, `panel-scope.sh`'s fourth panel, `phase-4d-light.md`,
   directive text, `SKILL.md` and the panel orchestration reference; real-koto
   route tests per level, unset and docs/task; template checks;
   settled-policy and retry-clearing tests updated for the new key and
   states. Depends on 1.
3. **Bound plumbing through `/execute` and `/deliver`**, with their open-script
   and template-structure tests. Depends on 2 for the variables it sets.
4. **Coordinate brief field**: `render-brief.sh`, its test,
   `brief-template.md`, `entry-points.tsv`. Depends on 3 for the flags to
   exist.

Steps 1 and 2 are one reviewable change about `/work-on`; 3 and 4 are one
about carrying a bound. Each step leaves CI green on its own.

## Security Considerations

- **Template interpolation.** `{{REVIEW_LEVEL}}`, `{{REVIEW_FLOOR}}` and
  `{{REVIEW_CEILING}}` reach gate and action command lines through koto's
  substitution, before any script sees them. koto enforces each variable's
  pattern at init and on every rebind, so the substituted text is one of
  three level names or empty; the commands still quote it.
- **Free text.** `set`'s `--reason` reaches a JSON line and nothing else:
  it goes through `jq --arg`, has control characters replaced and is capped
  at 200 characters. `report` escapes tabs, newlines and control characters
  in anything it prints, because a coordinator agent may read its output.
  Level names are matched against a fixed list before use; the session name
  is checked against koto's name pattern. `render-brief.sh` validates
  `review_level` values against the three names before they reach an
  invocation line, so a brief can't smuggle a flag.
- **Which template an attach uses.** `set` attaches with the `work-on.md`
  that ships beside it, never a path read from the session, and koto
  refuses an attach whose template hash differs from the session's.
- **The rules can't lower their own floor.** `facts` classifies with the copy
  `init` stored when the level was chosen, not with any file the run's diff
  can change, and the rules file is in the `security` class, so a diff that
  edits it floors at `full`. A change to the rules takes effect on runs that
  start after it lands.
- **Decider slice exposure.** `slice` prints a fixed projection: counts,
  class names, booleans, the floor and the level, never a path, a reason or
  issue text, and a test asserts that. An opted-in user sends no repository
  content to the decider provider through this check, and a poisoned answer
  can only hold the run.
- **Bypass.** A worker can lower its own review only with a recorded reason
  and never below the facts' floor or the bound floor; it can pass a hold
  only through `koto overrides record`, which koto logs and `report` counts.
  A bound floor is exactly as strong as the facts floor: both rest on the
  gate and on `set`. A hand rebind of the variable holds the run. None of
  this stops an agent that edits its own session store, and an override is
  visible only when someone runs `report`; both residuals are accepted, and
  the ledger makes such a run visible rather than impossible.
- **Ledger integrity.** The key is rewritten whole on each append, since
  koto has no append verb. Two writers at once could drop a line; only one
  agent drives a session, so this is accepted.
- **Coverage gap, narrowed.** A path in no class floors at `standard`, so
  only documentation and paths in a class no rule names can be reviewed by
  one seat. A sensitive file the `docs` globs happen to match is the gap
  left; the classes are data, so a path that proves sensitive is added to
  the rules file.

## Consequences

### Positive

- A small, contained change reviewed at `light` spawns one seat per round
  instead of seven; `standard` saves the QA tester, the most expensive seat by
  call budget.
- Every run leaves a ledger, and `report` gives the threshold data that
  doesn't exist today.
- The coordinator's lever from shirabe#521 exists, and its effect is visible
  per run.

### Negative

- Two new states and one more panel state make the template longer, and
  every code issue now passes `review_level_check` on each lap.
- A level change costs a `koto init --attach-live` and two context writes;
  a run makes a handful of them at most.
- The default thresholds are guesses until the ledger has data.
- Value routing and decider checks shipped in koto 0.15.0, so shirabe's koto
  minimum (`scripts/assert-koto-floor.sh`) moves from 0.14.1 to 0.15.0 with
  the template wiring.
- `light` catches less than three seats would; the floor rules are what keep
  it to small changes outside the risky classes.

### Mitigations

- The unset route and the empty-bound defaults keep every existing session
  and init site on today's path.
- The rules file and the reader make retuning a data change with evidence.
- The level check runs only scripts already on the plugin path, guarded by
  the same `PLUGIN_ROOT` checks the other actions use.
