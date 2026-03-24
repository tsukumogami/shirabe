# Phase 0: Setup

Read all plan artifacts and determine execution mode before any review category runs.

## Goal

Load the complete plan context from wip/ artifacts, detect the `input_type` that
gates category behavior, and select fast-path or adversarial execution mode.

## Steps

### 0.1 Resolve Plan Topic

Determine the `<topic>` string from input:

- If called as sub-operation: use `plan_topic` from args
- If called standalone with a file path: strip directory prefix and `wip/plan_`
  prefix; strip `_analysis.md` suffix to get `<topic>`
- If called standalone with a topic string: use as-is

All subsequent wip/ artifact reads use `wip/plan_<topic>_*.md` / `*.json` paths.

### 0.2 Validate Required Artifacts Exist

Check that all required wip/ artifacts are present before proceeding. If any are
missing, stop and report which files are absent — do not attempt partial review.

Required artifacts:

| Artifact | Purpose |
|----------|---------|
| `wip/plan_<topic>_analysis.md` | Design doc path, `input_type`, `review_rounds` counter |
| `wip/plan_<topic>_decomposition.md` | Issue count and decomposition strategy |
| `wip/plan_<topic>_manifest.json` | Enumeration of issue body file paths |
| `wip/plan_<topic>_dependencies.md` | Dependency graph between issues |

If any artifact is missing, output:

```
Phase 0 error: required artifact not found — <path>
Cannot proceed with review until all plan phases have completed.
```

### 0.3 Read Plan Artifacts

Read all four artifacts and extract the following values:

**From `wip/plan_<topic>_analysis.md`:**
- `input_type` — one of `design`, `prd`, `roadmap`, `topic`
- Upstream design doc path (for Category B design fidelity check)
- `review_rounds` counter (if present; defaults to 0 if absent)

**From `wip/plan_<topic>_decomposition.md`:**
- Issue count
- Decomposition strategy (`walking-skeleton` or `horizontal`)
- Complexity breakdown (simple / testable / critical counts)

**From `wip/plan_<topic>_manifest.json`:**
- List of issue body file paths (`wip/plan_<topic>_issue_*.md`)

**From `wip/plan_<topic>_dependencies.md`:**
- Full dependency graph
- Critical path length

### 0.4 Read Issue Body Files

Read each issue body file listed in the manifest. These are the inputs to
Categories A, C, and D. Category B also needs the upstream design doc path.

If the manifest lists a file that doesn't exist, report it and continue — the
missing file is itself a finding for Phase 1 (Scope Gate).

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

| input_type | Category A | Category B | Category C | Category D |
|------------|-----------|-----------|-----------|-----------|
| `design` | Full check | Full check | Full check | Full check |
| `prd` | Full check | Full check | Full check | Full check |
| `roadmap` | Issue count vs. roadmap item count only | Returns empty findings | Returns empty findings | Returns empty findings |
| `topic` | Full check | Returns empty findings (`critical_findings: []`) | Full check | Full check |

Record the `input_type` and the category behavior table entry. Pass both to
phases 1–4 so they can gate correctly.

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
