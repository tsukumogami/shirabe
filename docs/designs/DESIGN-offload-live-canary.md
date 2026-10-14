---
schema: design/v1
status: Proposed
problem: |
  shirabe can't tell whether a gate-checked rule still needs preloading,
  because every /work-on run gets the same instructions, koto exports no
  variable values to Datadog, a passing check names no rule, and the rule
  registry forbids withholding any rule a gate checks. The offline ablation
  that was to answer it has stopped, and nothing new may run outside a
  session.
decision: |
  Withhold PB4 (no markdown heading in Part 1 of a pull request body) from a
  random half of standalone /work-on runs. A new initial state runs
  offload-canary.sh, which draws a group from /dev/urandom, records it in the
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
decision_provenance: inline-resolved
---

# DESIGN: Live Offload Canary

## Status

Proposed

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

**Chosen: an explicit list in `scripts/check-rule-registry.sh`.** A constant,
`WITHHOLD_GATE_RULES="pr-body/no-heading-in-part1"`, names the gate rules the
owner has approved for withholding. For an entry on the list, and only for
one, the check accepts `level: gate` with `guards: ["none"]`, and requires
`withhold: eligible` and non-empty `notes`. Every other gate entry keeps the
current rule: a guard other than `none`, hence `withhold: never`. Any
`eligible` entry whose guards include a protected action still fails. The
entry itself changes to `guards: ["none"]`, `withhold: eligible`, with
`notes` giving the reason from Decision 1.

*Alternative: drop the pairing "a gate needs a guard" for all entries.*
Simpler, and it would let any gate rule be reclassified in a JSON edit nobody
reviews as a safety decision. Rejected: the list makes the safety decision a
named, reviewable line that changes only with the owner's ruling.

*Alternative: a new registry field, such as `gate_after: pr-create`.* More
general, and it would ask the registry's schema, its reader and its design to
change for one rule. Rejected for now; it's the natural shape once a second
rule is withheld.

This decision depends on the owner's ruling on narrowing the withhold safety.
Until it's given, the registry change isn't committed.

### Decision 3: Where and how the group is drawn

**Chosen: a new initial state, `offload_canary`, whose `default_action` runs
`offload-canary.sh draw` and captures its output as `PR_BODY_RULES`.** The
script reads `OFFLOAD_CANARY`, `SHARED_BRANCH` and the session directory. It
draws one byte from `/dev/urandom` and takes its parity, records the group in
`<session-dir>/offload-canary/arm`, and prints the path of the conformance
text this run reads. A recorded group is read back rather than redrawn, so a
rewind into the state gives the same answer. With the canary off, a shared
branch set, or anything going wrong, it records nothing and prints the real
file's path. The script also asks the registry before it draws: unless
`rule-registry.sh` reports `pr-body/no-heading-in-part1` as
`withhold: eligible`, every run takes part in neither group, so the canary
can't withhold anything the registry hasn't admitted. The arm file is written
last, after the withheld rendering succeeds, so a failed render can't leave a
run labeled withheld while it reads the full text. The action is written so it always exits 0, because a failing
`default_action` holds its state, which a prototype confirmed.

*Alternative: a declared variable drawn at each init site.* Value routing
could then route on it directly. Rejected: `/work-on` is opened three ways
(the agent's own `koto init` from SKILL.md, `work-on-open.sh` under a leg,
and `/execute`'s `materialize_children`). The first is an agent typing a
command, which can't be trusted to draw at random, and three draw sites are
three places to keep in step.

*Alternative: draw in the `pr_creation` state itself.* Rejected: the PRD asks
for the group when the run starts, and a run that never reaches
`pr_creation` would then carry no group at all, which hides how many runs
each group started with.

### Decision 4: How the rule's text is withheld

**Chosen: the `pr_creation` directive names `{{PR_BODY_RULES}}` as the
conformance text to author against.** The preloaded group, a canary-off run, a
shared-branch run and a failed assignment all get
`{{PLUGIN_ROOT}}/references/pr-body-conformance.md`. The withheld group gets
`<session-dir>/offload-canary/pr-body-conformance.md`, which the script
renders from the real file with the lines `rule-registry.sh ref
pr-body/no-heading-in-part1` reports removed. `phase-6-pr.md` stops naming the
conformance file and defers to the directive. The directive also stops listing
the five PR-body rule ids, since a finding already names the rule it breaks
and the list would hand the withheld group PB4's id. Those two edits apply to
every run, so the preloaded group's text equals a canary-off run's.

*Alternative: a checked-in copy of the conformance file without PB4.* No
runtime rendering. Rejected: a second copy of the PR-body rules is the drift
`pr-body-conformance.md` was written to end, and a test pinning the copy to
the original still has to be kept in step.

*Alternative: substitute the rule's text itself.* Rejected: koto values can't
hold markdown.

### Decision 5: How the group reaches Datadog

**Chosen: two pass-through marker states.** A gate on `offload_canary`,
`offload_arm`, runs `offload-canary.sh arm` against the session directory: exit
0 for withheld, 1 for preloaded, 3 for neither. The transitions go to
`offload_arm_withheld`, `offload_arm_preloaded` or straight to `entry`. Each
marker state has a single unconditional transition to `entry`, so koto passes
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

A `/work-on` run starts in `offload_canary`. The draw runs, the gate reads the
recorded group, and the run passes through one marker state, or neither, into
`entry` as today. Nothing else about the run changes until `pr_creation`,
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
| `skills/work-on/scripts/offload-canary.sh` | New. `draw <switch> <shared-branch> <session-dir> <plugin-root>` prints the conformance path and records the group; `arm <session-dir>` exits 0, 1 or 3. POSIX `sh`, no dependency beyond `od`, `sed` and the registry reader. |
| `skills/work-on/koto-templates/work-on.md` | New variable `OFFLOAD_CANARY` (`values: ["on", "off"]`, default `"on"`, no `rebind`); `initial_state: offload_canary`; three new states; the `pr_creation` directive names `{{PR_BODY_RULES}}` and drops the rule-id list. |
| `skills/work-on/koto-templates/work-on.mermaid.md` | The three states and their edges. |
| `skills/work-on/references/phases/phase-6-pr.md` | The Create PR paragraph defers to the directive for the conformance text. |
| `skills/work-on/scripts/check-pr-output.sh` | After printing a `pr-body/no-heading-in-part1` finding, calls `rule-registry.sh release pr-body/no-heading-in-part1` once. |
| `references/rule-registry.json` | PB4: `guards: ["none"]`, `withhold: eligible`, `notes`. |
| `scripts/check-rule-registry.sh` | `WITHHOLD_GATE_RULES` and the narrowed pairing (Decision 2). |
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
      command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" || exit 3; "{{PLUGIN_ROOT}}/skills/work-on/scripts/offload-canary.sh" arm "{{SESSION_DIR}}"'
  transitions:
    - target: offload_arm_withheld
      when: {gates.offload_arm.exit_code: 0}
    - target: offload_arm_preloaded
      when: {gates.offload_arm.exit_code: 1}
    - target: entry
      when: {gates.offload_arm.exit_code: 3}
offload_arm_withheld:
  transitions: [{target: entry}]
offload_arm_preloaded:
  transitions: [{target: entry}]
```

The `arm` subcommand maps any exit it can't classify to 3, so every outcome
has an edge. `entry` keeps its own `skip_if` for plan-backed runs, which
fires after the canary states as it does today after init.

### Data flow

1. `koto init` fixes `OFFLOAD_CANARY` (default `on`) and the other variables.
2. The first `koto next` runs the draw: `on`, no shared branch, no recorded
   group means one byte from `/dev/urandom`, `withheld` on even parity, else
   `preloaded`, written to `<session-dir>/offload-canary/arm`. In the withheld
   group the script writes the rendered conformance text next to it.
3. The gate reads `arm` and koto passes through the marker state into
   `entry`. The journal records `state_entered` for each state.
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

1. **Delivery on failure.** `check-pr-output.sh` releases PB4's text after a
   PB4 finding, with tests for PB4 alone, PB4 with PB3, PB2 alone and a
   conformant body. This is useful on its own and changes no instructions.
2. **The canary in `/work-on`.** `offload-canary.sh` and its tests (balance
   over 200 draws, off, shared branch, read-back, rendering equals the file
   minus the anchored lines); the variable, the three states and the
   `pr_creation` directive; `phase-6-pr.md`; the mermaid file; a koto-level
   test that drives sessions through each group, off, shared and a failed
   assignment, and compares the rendered `pr_creation` directives.
3. **The guide.** `docs/guides/offload-live-canary.md`, and a test that its
   off-switch line matches the template.
4. **Registry admission.** The list in `check-rule-registry.sh`, the PB4
   entry, the doc updates, and the test cases R2 names. Last, because it
   waits on the owner's ruling. Steps 1 to 3 are safe without it: the draw
   asks the registry first, so until PB4 is eligible every run takes part in
   neither group and the canary withholds nothing.

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

**Negative.** Every `/work-on` run gains three states and one action, and its
first state is no longer `entry`, which tests and readers of the template
have to know. The withheld group reads its conformance text from outside the
repository, under the session directory. The baseline is low and the sample
small, so a readout means weeks, not days. Contamination from the agent's own
knowledge or a project's PR skill narrows any measured difference.

**Mitigations.** The new states pass through without asking for evidence, and
a test pins the canary-off directive. The guide states the sample size, the
limitation, and the reading window. A second rule waits for a schema field
(Decision 2's second alternative) rather than growing the list.
