# Phase 0: Setup

Read all plan artifacts and determine execution mode before any review category runs.

## Goal

Load the complete plan context from the keys in `plan-<topic>` (or from the PLAN
document when there is no plan session), detect the `input_type` that gates
category behavior, and select fast-path or adversarial execution mode.

## Steps

### 0.1 Resolve Plan Topic

Determine the `<topic>` string from input:

- If called as sub-operation: use `plan_topic` from args
- If called standalone with a PLAN path (`docs/plans/PLAN-<topic>.md`): strip the
  directory, the `PLAN-` prefix and the `.md` suffix to get `<topic>`
- If called standalone with a topic string: use as-is

Check `<topic>` against `^[a-z0-9][a-z0-9-]*$` before it reaches any command.
Every read and write below names keys in `plan-<topic>`.

### 0.1a Pick the Session Case

SKILL.md's Session and Keys names three cases. Pick one:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" status plan-<topic>
```

- Called as a sub-operation: `/plan` holds `plan-<topic>` open. Use it as is.
- `live` (standalone): a plan is in flight. Use it as is; close nothing.
- `absent` or `finished` (standalone): review the PLAN document alone. Check
  that `docs/plans/PLAN-<topic>.md` exists (stop and say so when it doesn't),
  then open the session the verdict goes to and record any parent match:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open plan <topic>
  "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" adopt plan <topic>
  ```

  Any non-zero exit stops the run with the script's message. Remember that
  this run opened the session: Phase 5 closes it (unless `adopt` matched a
  parent). In this case skip 0.2 to 0.4 and read the PLAN document instead
  (0.4a).

### 0.2 Validate Required Artifacts Exist

Check that all required keys are present in `plan-<topic>` before proceeding
(`koto context exists plan-<topic> <key>` for each). If any are missing, stop and
report which keys are absent — do not attempt partial review.

Required artifacts:

| Artifact | Purpose |
|----------|---------|
| `work/analysis.md` | Design doc path, `input_type`, `review_rounds` counter |
| `work/decomposition.md` | Issue count and decomposition strategy |
| `work/manifest.json` | Enumeration of issue bodies (each entry's `file` is a key's last component) |
| `work/dependencies.md` | Dependency graph between issues |

If any artifact is missing, output:

```
Phase 0 error: required key not found in plan-<topic> — <key>
Cannot proceed with review until all plan phases have completed.
```

### 0.3 Read Plan Artifacts

Read all four keys (`koto context get plan-<topic> <key>`) and extract the
following values:

**From `work/analysis.md`:**
- `input_type` — one of `design`, `prd`, `roadmap`, `topic`
- Upstream design doc path (for Category B design fidelity check)
- `review_rounds` counter (if present; defaults to 0 if absent)

**From `work/decomposition.md`:**
- Issue count
- Decomposition strategy (`walking-skeleton` or `horizontal`)
- Complexity breakdown (simple / testable / critical counts)

**From `work/manifest.json`:**
- List of issue bodies: each entry's `file` (`issue_<id>_body.md`) names key
  `work/issue_<id>_body.md`

**From `work/dependencies.md`:**
- Full dependency graph
- Critical path length

### 0.4 Read Issue Bodies

Read each issue body key the manifest lists (`work/<file>`). These are the
inputs to Categories A, C, and D. Category B also needs the upstream design doc
path.

If the manifest lists a body whose key doesn't exist, report it and continue —
the missing body is itself a finding for Phase 1 (Scope Gate).

When a category's agent is spawned with a packet (SKILL.md's Seat
commissioning), materialize the keys it reads into one private directory and
pass the printed paths to `review-packet.sh`; remove the directory once the
agents return:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch          # prints <inputs-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" get plan-<topic> work/decomposition.md <inputs-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" get plan-<topic> work/analysis.md <inputs-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" get plan-<topic> work/dependencies.md <inputs-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" get plan-<topic> work/issue_<id>_body.md <inputs-dir>   # each body
```

### 0.4a Read the PLAN Document (no plan session)

When 0.1a found no plan session, the PLAN document is the whole input. From
`docs/plans/PLAN-<topic>.md` take the upstream design doc (its `upstream:`
frontmatter), `input_type` from that upstream's type (`design`, `prd`,
`roadmap`, or `topic` when it has none), the issue count and decomposition
strategy from its Decomposition Strategy section, each issue's outline (from
Issue Outlines, or the Implementation Issues table and the issues it links)
as that issue's body, and the dependency graph from its Dependency Graph
section. `review_rounds` is 0. Seat packets use `--doc` on the PLAN document.

### 0.5 Detect Execution Mode

Determine which execution mode applies:

```
if args.mode == "fast-path"   → fast-path mode
if $ARGUMENTS contains "--adversarial"  → adversarial mode
else                          → fast-path mode (default)
```

Record the selected mode. It determines agent count in phases 1–4:
- **Fast-path**: single agent per category
- **Adversarial**: multiple validators per category + cross-examination step

### 0.6 Detect Input Type Behavior

`input_type` gates category behavior in later phases:

Record the `input_type` and pass it to phases 1–4; each phase has its own
input-type behavior table.

### 0.7 Log Setup Summary

Output before continuing to Phase 1:

```
Review Plan — Phase 0 complete
  topic:        <topic>
  input_type:   <input_type>
  mode:         fast-path | adversarial
  issue_count:  <N>
  strategy:     <walking-skeleton | horizontal>
  round:        <args.round if called as sub-operation, else review_rounds + 1>
  upstream_doc: <path or "none">
```
