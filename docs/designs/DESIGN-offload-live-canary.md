---
schema: design/v1
status: Planned
problem: |
  shirabe can't tell whether a gate-checked rule still needs preloading,
  because every /work-on run gets the same instructions, koto exports no
  variable values to Datadog, a passing check names no rule, and the rule
  registry forbids withholding any rule a gate checks. The offline ablation
  that was to answer it has stopped, and nothing new may run outside a
  session.
decision: |
  Withhold PB4 (no markdown heading in Part 1 of a pull request body) from a
  random half of standalone /work-on runs. A new state on analysis's
  plan_ready edge runs offload-canary.sh, which draws a group from /dev/urandom, records it in the
  session directory and prints the path of the PR-body conformance text the
  run should read, captured as PR_BODY_RULES. A gate on the same state routes
  to one of two pass-through marker states, offload_arm_withheld or
  offload_arm_preloaded, whose state_entered events carry the group to
  Datadog. The pr_creation directive names {{PR_BODY_RULES}}, which is the
  real conformance file in the preloaded group and a session-directory copy
  without PB4's anchored lines in the withheld one. The PR-body gate releases
  PB4's text when it fails on it, and OFFLOAD_CANARY's default is the off
  switch.
rationale: |
  Everything stays inside a /work-on session and uses only what koto exports
  today: state names reach Datadog and variable values don't, so the group
  has to be a state. A capture is the one way a value drawn at run time can
  reach a directive. Value routing can't read a capture, so a gate does the
  routing. Rendering the withheld text from the registry's own anchors keeps
  one copy of the rule, and a gate that fails closed toward the canary-off
  path keeps a broken assignment from stopping a run. PB4 is the one gate
  rule whose gate runs after the action it would guard and whose harm CI
  still blocks, and the registry admits it by name on an explicit list.
upstream: docs/prds/PRD-offload-live-canary.md
user_visible_surface: true
decision_provenance: inline-resolved
---

# DESIGN: Live Offload Canary

## Status

Planned

## Context and Problem Statement

The requirements are in `docs/prds/PRD-offload-live-canary.md` (R1 to R14).
This section frames them in implementation terms.

`/work-on`'s `pr_creation` state opens the pull request and then holds on two
gates. One of them, `pr_body_conformant`, runs
`skills/work-on/scripts/check-pr-output.sh --pr-body`, which reads the pull
request from GitHub, runs `shirabe validate --pr-body`, and prints one
`::koto-finding::` line per violation with a registered rule id. koto writes
a `check_rule` journal event for each, and the Datadog sender forwards it with
`koto.session.id`, `koto.state`, `koto.check` and `koto.rule.id`. The
directive points the agent at `skills/work-on/references/phases/phase-6-pr.md`,
which points at `references/pr-body-conformance.md`, where PB1 to PB4 are
stated. The PB4 paragraph is lines 61 to 75 there, the span the registry
entry `pr-body/no-heading-in-part1` anchors.

Five constraints shape the build:

- **koto exports names only.** What reaches Datadog is the template name and
  hash on `session_started`, the state on `state_entered`, and gate and rule
  id on `check_rule`. Variable values, evidence, context keys and directive
  text never leave the host (koto's `docs/reference/run-journal.md`, and the
  sender's per-kind allow-list).
- **A passing check names no rule.** `check_rule` is written only when a gate
  fails, and `check_evaluated` reaches Datadog without its gate name because
  `koto.check` collides with `koto.check.*`. The Datadog lane is fixing the
  collision in the sender; the canary doesn't wait for it.
- **koto variable values are plain.** A value must match
  `^[a-zA-Z0-9._/:@+ \-]*$`, so it can carry a path but never a paragraph of
  markdown. A rule's text can't be substituted in; a pointer to it can.
- **koto has no random source** for templates. A draw has to be a command.
- **The registry forbids it today.** `scripts/check-rule-registry.sh`
  requires a guard other than `none` on every `level: gate` entry, and any
  such guard forces `withhold: never`. All 21 gate rules are `never`.

The volume: 64 `/work-on` sessions and 46 entries into `pr_creation` in the
seven days to 2026-10-14, read from Datadog.

## Decision Drivers

- Nothing new outside a session: no exporter, sender change, service or
  scheduled job.
- The group must be readable from events koto already exports.
- The preloaded group's instructions are byte-for-byte those of a canary-off
  run.
- One copy of the rule's text: no second statement that can drift.
- A failed assignment never stops a run.
- The change to the registry's withhold safety admits exactly one rule and
  never one that guards pushing, merging or opening a pull request.
- Small template footprint: no new state that asks for evidence.

## Considered Options

All five questions were resolved inline under `/scope`, at standard depth.

### Decision 1: Which rule to withhold

Resolved inline.

**Chosen: `pr-body/no-heading-in-part1` (PB4).** Its gate runs after
`gh pr create`, on the pull request GitHub already has, so it doesn't stand in
front of the creation. A violation is a formatting defect fixed by
`gh pr edit`. The harm it exists to prevent is a heading landing on `main`
as part of the squash commit, and CI's `shirabe validate --pr-body` blocks
that merge whatever the agent was told. Its text is one self-contained
paragraph, and its rule id isn't shared with any other rule. Over the week
to 2026-10-14 it broke in no recorded run, so it's a low-risk first canary.

*Alternative: PB2 (`pr-body/one-separator`).* It has a nonzero baseline (one
broken run that week), which would make a difference easier to see. Rejected:
the separator defines the two-part body every other PR-body check reads, so
withholding it changes more than one rule's behavior at once.

*Alternative: PB1 (`pr-body/conventional-title`).* Rejected: its text is
shared with `commit/conventional-subject`, whose gate stands before the push.

*Alternative: PB3 (`pr-body/no-ai-trailer`).* Rejected: an attribution line is
public the moment the pull request opens, and no later fix takes it back.

*Alternative: a commit, branch, docs, panel or verification rule.* Rejected:
each one's gate stands before a push or before the pull request opens.

### Decision 2: How the registry admits the rule

Resolved inline.

**Chosen: a `backstop` field the registry check enforces.** The owner ruled
on 2026-10-14 that a gate rule may be eligible when its harm is undone by a
later edit and a deterministic check blocks the irreversible step, and asked
for that to be a rule, not a one-off. An eligible gate rule names that check:
`backstop: {"before": "merge", "check": ".github/workflows/pr-body.yml"}` for
PB4. `scripts/check-rule-registry.sh` accepts `level: gate` with
`guards: ["none"]` only beside a backstop, requires a backstop to sit on an
eligible gate rule with notes, requires `before` to be a protected action and
`check` to exist, and still fails any eligible entry whose guards include a
protected action. The amendment is recorded in the registry design's
Decision 6.

*Alternative: an explicit list of approved rule ids in the check script.*
Narrow, and it would make the safety decision a list of names with no
statement of what qualifies a rule. Rejected after the owner asked for the
rule itself to be enforced.

*Alternative: drop the pairing "a gate needs a guard" for all entries.*
Simpler, and it would let any gate rule be reclassified in a JSON edit nobody
reviews as a safety decision. Rejected: the list makes the safety decision a
named, reviewable line that changes only with the owner's ruling.

*Alternative: drop the pairing "a gate needs a guard" for every entry.*
Rejected: it would let any gate rule become eligible in a JSON edit nobody
reviews as a safety decision.

### Decision 3: Where and how the group is drawn

Resolved inline.

**Chosen: a new state, `offload_canary`, on `analysis`'s `plan_ready` edge,
before `review_level_choice`, whose `default_action` runs
`offload-canary.sh draw` and captures its output as `PR_BODY_RULES`.** The
script reads `OFFLOAD_CANARY`, `SHARED_BRANCH` and the session directory. It
draws one byte from `/dev/urandom` and takes its parity, records the group in
`<session-dir>/pr-rules/sample`, and prints the path of the conformance
text this run reads. A recorded group is read back rather than redrawn, so a
rewind into the state gives the same answer. With the canary off, a shared
branch set, or anything going wrong, it records nothing and prints the real
file's path. The script also asks the registry before it draws: unless
`rule-registry.sh` reports `pr-body/no-heading-in-part1` as
`withhold: eligible`, every run takes part in neither group, so the canary
can't withhold anything the registry hasn't admitted. It draws only on a host
that has opted in: `${XDG_CONFIG_HOME:-$HOME/.config}/shirabe/offload-canary`
must exist, be a regular file, and read `on` on its first line. shirabe is a
public plugin, and other people's runs never reach this project's Datadog, so
withholding from them would be unmeasured risk; the coordinator ruled for a
per-host opt-in on 2026-10-14. The template default stays the global off
switch, and deleting the file turns one host off. The arm file is written
last, after the withheld rendering succeeds, so a failed render can't leave a
run labeled withheld while it reads the full text.

The capture has a fixed contract. `draw` prints exactly one line, as its last
act, and always exits 0, so the action's fallback `echo` never adds to its
output. The line is an absolute path built from `{{SESSION_DIR}}` or
`{{PLUGIN_ROOT}}`, which already pass koto's value pattern. A failing
`default_action` holds its state (a prototype confirmed it), which is why the
action's command ends in a fallback rather than trusting the script alone.

The unit of randomization is the koto session. A `/work-on` run that
`/execute` starts on its shared branch takes part in neither group; a
`/work-on` run per issue of a `multi-pr` plan draws on its own, so runs from
one plan can land in either group, and the guide notes that runs from one
plan are correlated. A session started before the canary shipped never enters
the assignment state and is in neither group.

*Alternative: put the draw in the gate and drop the action.* One command
instead of two. Rejected: a gate carries nothing forward to a directive, and
a gate that writes state would be re-run on every evaluation.

*Alternative: a declared variable drawn at each init site.* Value routing
could then route on it directly. Rejected: `/work-on` is opened three ways
(the agent's own `koto init` from SKILL.md, `work-on-open.sh` under a leg,
and `/execute`'s `materialize_children`). The first is an agent typing a
command, which can't be trusted to draw at random, and three draw sites are
three places to keep in step.

*Alternative: make `offload_canary` the template's initial state.* The
earliest possible draw. Rejected after the implementation tried it: the
documented first tick after `koto init` submits the entry evidence (`mode`
and the issue), and a first state that accepts no evidence advances to
`entry` with that evidence dropped, which broke every caller and every suite
that walks the template. `analysis`'s `plan_ready` edge is the one edge every
run that goes on to implement crosses, it carries no evidence onward, and it
still comes before any implementation.

*Alternative: draw in the `pr_creation` state itself.* Rejected: the draw
should come before the rule can matter, and a run that never reaches
`pr_creation` would then carry no group at all, which hides how many runs
each group started with.

### Decision 4: How the rule's text is withheld

Resolved inline.

**Chosen: the `pr_creation` directive names `{{PR_BODY_RULES}}` as the
conformance text to author against.** The preloaded group, a canary-off run, a
shared-branch run and a failed assignment all get
`{{PLUGIN_ROOT}}/references/pr-body-conformance.md`. The withheld group gets
`<session-dir>/pr-rules/pr-body-conformance.md`, a neutral name that doesn't
tell the agent its group, which the script renders from the real file with
the line range `rule-registry.sh range pr-body/no-heading-in-part1` reports
removed. The range is found from the entry's content anchors, not stored line
numbers, so an edit elsewhere in the file can't shift it onto another rule.
The script also checks that the first removed line holds the entry's
`text.first` anchor, and falls back to neither group if it doesn't.

Removing the anchored paragraph only works if it is the only place the rule is
stated, and today it isn't: `references/pr-body-conformance.md` restates PB4
in its "What stays advisory" section, names it in the setext residual, and
uses a `##` example in the fenced-code note. So the conformance file is
reorganized first, for every run, so that everything about PB4 lives inside
its anchored paragraph and the rest of the file mentions neither PB4 nor
headings. That is the registry's own model, one home per rule, and the
paragraph stays under `release`'s 60-line cap. A test asserts that the
rendered file contains neither `PB4` nor the word `heading`.

`phase-6-pr.md` stops naming the conformance file and defers to the directive.
The directive also stops listing the five PR-body rule ids, since a finding
already names the rule it breaks and the list would hand the withheld group
PB4's id. Those edits apply to every run, so the preloaded group's text equals
a canary-off run's.

*Alternative: a checked-in copy of the conformance file without PB4.* No
runtime rendering. Rejected: a second copy of the PR-body rules is the drift
`pr-body-conformance.md` was written to end, and a test pinning the copy to
the original still has to be kept in step.

*Alternative: substitute the rule's text itself.* Rejected: koto values can't
hold markdown.

### Decision 5: How the group reaches Datadog

Resolved inline.

**Chosen: two pass-through marker states.** A gate on `offload_canary`,
`offload_arm`, runs `offload-canary.sh arm` against the session directory: exit
0 for withheld, 1 for preloaded, 3 for neither. The transitions go to
`offload_arm_withheld`, `offload_arm_preloaded` or straight to
`review_level_choice`. Each marker state has a single unconditional
transition to `review_level_choice`, so koto passes
through it without stopping, and its `state_entered` event carries the name in
`koto.state`. The coordinator accepted marker states on 2026-10-14.

*Alternative: encode the group in a rule id or gate name.* Rejected: a rule id
reaches Datadog only on a failure, and a gate name on a pass is lost to the
collision above.

*Alternative: route on the value of a declared variable.* Rejected: a capture
can't be value-routed, and Decision 3 rules out a declared variable.

*Alternative: export the variable.* Rejected: it needs a sender change outside
a session, which the owner ruled out.

## Decision Outcome

A `/work-on` run starts at `entry` as today. When its analysis plan is
ready, `analysis` routes to `offload_canary`: the draw runs, the gate reads the
recorded group, and the run passes through one marker state, or neither, into
`review_level_choice`. Nothing else about the run changes until `pr_creation`,
whose directive tells the agent to author against `{{PR_BODY_RULES}}`. A
withheld agent reads a conformance text with no PB4 paragraph, and a
preloaded one reads the real file. When `pr_body_conformant` fails on PB4,
`check-pr-output.sh` prints the finding and releases PB4's text, so either
group can fix the body. In Datadog, the marker state on `state_entered`, the
entry into `pr_creation`, and the `check_rule` events for PB4 join on
`koto.session.id` into a per-group count of runs and broken runs.

The pieces fit because each uses a koto mechanism already in use in this
template: a captured value read by a later directive (`BRANCH`), command
gates routed on exit codes, and pass-through states. The canary's only
dependency outside `/work-on` is the registry's admission of PB4.

## Solution Architecture

### Components

| Component | Change |
|---|---|
| `skills/work-on/scripts/offload-canary.sh` | New. `draw <switch> <shared-branch> <session-dir> <plugin-root>` prints the conformance path and records the group; `arm <session-dir>` exits 0 (withheld, and its rendered file exists), 1 (preloaded) or 3 (neither). Bash 3.2, with `jq` through `rule-registry.sh`, as the other `/work-on` scripts. It reads the registry through the `<plugin-root>` it is given, which is also the test seam: a test points it at a fixture plugin root whose registry marks PB4 eligible. |
| `scripts/rule-registry.sh` | Two read subcommands: `withhold <id>` prints the entry's `withhold` value, and `range <id>` prints the first and last line numbers `resolve` already computes. The script stays the only reader of the registry. |
| `references/pr-body-conformance.md` | Reorganized so every statement of PB4 is inside its anchored paragraph, and the anchors move with it. |
| `skills/work-on/koto-templates/work-on.md` | New variable `OFFLOAD_CANARY` (`values: ["on", "off"]`, default `"on"`, no `rebind`); `analysis`'s `plan_ready` edge targets `offload_canary`; three new states; the `pr_creation` directive names `{{PR_BODY_RULES}}` and drops the rule-id list. |
| `skills/work-on/koto-templates/work-on.mermaid.md` | The three states and their edges. |
| `skills/work-on/references/phases/phase-6-pr.md` | The Create PR paragraph defers to the directive for the conformance text. |
| `skills/work-on/scripts/check-pr-output.sh` | After printing a `pr-body/no-heading-in-part1` finding, calls `rule-registry.sh release pr-body/no-heading-in-part1` once. |
| `references/rule-registry.json` | PB4: `guards: ["none"]`, `withhold: eligible`, `backstop`, `notes`. |
| `scripts/check-rule-registry.sh` | The `backstop` rule (Decision 2). |
| `crates/shirabe/src/pr_body_hook.rs`, `crates/shirabe-validate/src/pr_body.rs` | On a host with the canary's opt-in file, the PreToolUse hook stops denying PB4 in both groups, so a PB4 violation reaches the `/work-on` gate that counts it; PB1 to PB3 are still denied. |
| `references/rule-registry.md`, `docs/designs/current/DESIGN-rule-registry.md` | Say that one gate rule is withheld, and where the list lives. |
| `docs/guides/offload-live-canary.md` | New. The attributes, the query, the off switch, and how to read the result. |

### The new states

```yaml
offload_canary:
  default_action:
    command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" && "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" draw "{{OFFLOAD_CANARY}}" "{{SHARED_BRANCH}}" "{{SESSION_DIR}}" "{{PLUGIN_ROOT}}" || echo "{{PLUGIN_ROOT}}/references/pr-body-conformance.md"'
    capture_stdout_as: PR_BODY_RULES
  gates:
    offload_arm:
      type: command
      command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" || exit 3; "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" arm "{{SESSION_DIR}}" || { test $? -eq 1 && exit 1; exit 3; }'
  transitions:
    - target: offload_arm_withheld
      when: {gates.offload_arm.exit_code: 0}
    - target: offload_arm_preloaded
      when: {gates.offload_arm.exit_code: 1}
    - target: review_level_choice
      when: {gates.offload_arm.exit_code: 3}
offload_arm_withheld:
  transitions: [{target: review_level_choice}]
offload_arm_preloaded:
  transitions: [{target: review_level_choice}]
```

The gate maps any exit other than 0 or 1 to 3, a missing script included,
so every outcome has an edge and a broken script can't hold the run.
`analysis`'s `plan_ready` edge targets `offload_canary` instead of
`review_level_choice`; nothing else in the template moves.

### Data flow

1. `koto init` fixes `OFFLOAD_CANARY` (default `on`) and the other variables.
2. The tick that submits `plan_ready` at `analysis` runs the draw: `on`, no shared branch, no recorded
   group means one byte from `/dev/urandom`, `withheld` on even parity, else
   `preloaded`. In the withheld group the script first writes the rendered
   conformance text to `<session-dir>/pr-rules/`, then records the group in
   `<session-dir>/pr-rules/sample`; it creates the directory itself and
   refuses a session directory, directory or file that is a symlink.
3. The gate reads `arm` and koto passes through the marker state into
   `review_level_choice`. The journal records `state_entered` for each state.
4. At `pr_creation` the directive renders `{{PR_BODY_RULES}}`.
5. On a PB4 failure the gate output carries the finding and the released text.
6. The sender forwards `state_entered` and `check_rule` as it does today.

### The readout

From a session, with Datadog's log analytics (`analyze_datadog_logs`), over
the window to read:

- filter: `(state_entered @koto.state:(offload_arm_withheld OR offload_arm_preloaded OR pr_creation)) OR (check_rule @koto.rule.id:"pr-body/no-heading-in-part1")`
- columns: `@koto.session.id`, `@koto.state`, `@koto.rule.id` (all `varchar`)

```sql
WITH ev AS (
  SELECT "@koto.session.id" AS sid, message AS kind,
         "@koto.state" AS st, "@koto.rule.id" AS rid
  FROM logs),
arm AS (
  SELECT DISTINCT sid,
         CASE WHEN st = 'offload_arm_withheld' THEN 'withheld' ELSE 'preloaded' END AS arm
  FROM ev
  WHERE kind = 'state_entered' AND st IN ('offload_arm_withheld', 'offload_arm_preloaded')),
reached AS (SELECT DISTINCT sid FROM ev WHERE kind = 'state_entered' AND st = 'pr_creation'),
broken AS (SELECT DISTINCT sid FROM ev WHERE kind = 'check_rule' AND rid = 'pr-body/no-heading-in-part1')
SELECT a.arm, COUNT(r.sid) AS runs, COUNT(b.sid) AS broken_runs
FROM arm a JOIN reached r ON r.sid = a.sid LEFT JOIN broken b ON b.sid = a.sid
GROUP BY a.arm
```

`DISTINCT` counts each session once, the inner join drops sessions with no
marker state, and the left join gives a group with no broken run a 0. The
shape was run against the week to 2026-10-14 with `pr_precheck` standing in
for a marker state; it returned 46 runs.

## Implementation Approach

1. **One home for PB4, and delivery on failure.** Reorganize
   `references/pr-body-conformance.md` so PB4 is stated only in its anchored
   paragraph, moving the anchors with it. `check-pr-output.sh` releases PB4's
   text after a PB4 finding, with tests for PB4 alone, PB4 with PB3, PB2
   alone and a conformant body. This is useful on its own and changes no
   rule.
2. **The canary in `/work-on`.** `rule-registry.sh withhold` and `range`;
   `offload-canary.sh` and its tests against a fixture plugin root where PB4
   is eligible (balance over 200 draws, off, shared branch, PB4 not eligible,
   read-back, rendering equals the file minus the anchored range, no `PB4` or
   `heading` in the rendering); the variable, the three states and the
   `pr_creation` directive; `phase-6-pr.md`; the mermaid file; a koto-level
   test that drives sessions through each group, off, shared and a failed
   assignment, and compares the rendered `pr_creation` directives.
3. **The guide.** `docs/guides/offload-live-canary.md`, and a test that its
   off-switch line matches the template. It says the canary withholds
   nothing until PB4 is eligible, that the readout counts first failures
   (after one, both groups have the released text), and that runs from one
   plan are correlated.
4. **Registry admission.** The list in `check-rule-registry.sh`, the PB4
   entry, the doc updates, and the test cases R2 names. Last, because it
   waits on the owner's ruling. Steps 1 to 3 are safe without it: the draw
   asks the registry first, so until PB4 is eligible every run takes part in
   neither group and the canary withholds nothing. The JSON edit, the list and
   the narrowed check land in one commit, since either half alone fails CI.

## Security Considerations

**External artifact handling.** The draw reads `/dev/urandom` and the
plugin's own `references/pr-body-conformance.md`, and writes two files under
the session directory koto owns. No input comes from the network or from the
pull request. The rendered file is built only by deleting a line range the
registry computes from the plugin's own copy, so nothing a user typed reaches
it.

**Permission scope.** The script runs as a koto action and gate with the
agent's own permissions, as every `/work-on` script does. It writes only
under `{{SESSION_DIR}}`, and refuses a session directory that doesn't exist
or is a symlink.

**Supply chain.** No new dependency. `od`, `sed` and `sh` are already
required by the existing scripts.

**Data exposure.** Two state names reach Datadog, by the path every
`/work-on` state already takes. No variable, path or text is added to any
exported event.

**Integrity of the measurement.** An agent could read the real conformance
file on its own initiative, or run the script itself and read the arm file.
Neither weakens a safeguard: the gate still checks PB4 in both groups, and CI
still blocks the merge. It would only blur the measurement toward no
difference, which the guide states as a limitation.

**The safety change itself.** Narrowing the withhold safety is the one
change with a safety dimension. The list admits exactly one rule, the
protected-guard rule still fails any eligible entry that guards a push, merge
or pull-request creation, and the change waits on the owner's ruling. Three
things bound what a wrong call could cost:

- The `/work-on` gate holds `pr_creation` on a PB4 finding in every
  repository, and on an exit 2 (could not decide) too, since neither has an
  edge out of the state. So a withheld run can't leave the state with a
  heading in Part 1 whether or not CI checks it.
- "CI blocks the merge" holds only where a repository runs
  `shirabe validate --pr-body` in CI, as shirabe does. Elsewhere the gate
  above is the only check, which is the same position a preloaded run is in.
- The draw asks the registry before it withholds, so the canary's reach is
  exactly what the registry admits, and the list in
  `check-rule-registry.sh` is the single line a reviewer has to watch. The
  repository has no CODEOWNERS file, so that review is the pull request's.

The canary is on by default once PB4 is eligible. The guide says so first,
with the off switch.

## Consequences

**Positive.** The first live measurement of withholding, from runs that
happen anyway, at no eval cost. The group, the denominator and the numerator
all come from events already exported. The off switch is one line, and a
broken script can't stop a run. The release-on-failure path is useful even
with the canary off.

**Negative.** Every `/work-on` run that reaches a ready plan gains three
states and one action between `analysis` and `review_level_choice`, which
tests and readers of the template have to know. The withheld group reads its conformance text from outside the
repository, under the session directory. The baseline is low and the sample
small, so a readout means weeks, not days. Contamination from the agent's own
knowledge or a project's PR skill narrows any measured difference.

**Mitigations.** The new states pass through without asking for evidence, and
a test pins the canary-off directive. The guide states the sample size, the
limitation, and the reading window. A second rule waits for a schema field
(Decision 2's second alternative) rather than growing the list.
