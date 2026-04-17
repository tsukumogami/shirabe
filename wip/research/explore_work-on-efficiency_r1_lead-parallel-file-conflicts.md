# Lead: parallel agent file conflict prevention

## Findings

### Current state of plan-to-tasks.sh

`plan-to-tasks.sh` processes single-pr PLAN docs by parsing `## Issue Outlines` sections. For each `### Issue N: Title` heading it collects two things: a slugified name and a `**Dependencies**:` field (or `### Dependencies` subsection). The output is a JSON array of koto task-entry objects with `name`, `vars`, and `waits_on` fields.

The script has no awareness of file paths. It knows only about explicit `Issue N` references in the dependencies field. There is no mechanism — not even a comment — that hints at file-level conflict detection. The `waits_on` array is built purely from `Issue N` cross-references.

`validate-plan.sh` is even more constrained. It checks three things: YAML frontmatter presence, required fields (`schema`, `execution_mode`, `issue_count`), and the optional `upstream` chain (file existence + git tracking + status field). It does no structural analysis of the Issue Outlines body at all. It has no hook point for file-level checks without a significant rewrite of its scope.

### What the PLAN doc format exposes today

The `plan-doc-structure.md` reference spec defines Issue Outlines as free-form prose with three required sub-sections: `**Goal**`, `**Acceptance Criteria**`, and `**Dependencies**`. There is no `files_changed:` field, no machine-readable file annotation, and no convention for marking which files an outline touches. The format is designed for human readability, not static analysis.

Looking at the actual PLAN-work-on-friction-fixes.md outlines, Issues 4 and 5 both mention `skills/work-on/SKILL.md` in their Goal and Acceptance Criteria prose — clearly readable by a human but only parseable by a text scanner that understands what looks like a file path. Neither issue declared a dependency on the other because the PLAN author correctly assessed them as touching different *sections* of the file. The conflict arose from concurrent writes, not logical coupling.

### Approach A: Static text analysis in plan-to-tasks.sh

The idea is to parse each Issue Outline's text for strings that look like file paths, build a per-file index of which issues mention each path, and auto-add `waits_on` edges when two issues share a path.

**Feasibility**: Technically possible. A regex like `[a-z][a-z0-9_/-]*\.[a-z]{1,5}` would catch most paths. The script already does multi-pass analysis (three passes over the outlines array), so a fourth pass to build a file-collision map is structurally feasible.

**False positive rate**: High. Paths appear in: Goal prose, Acceptance Criteria bullet text, inline code spans, and examples. A path like `SKILL.md` appearing in both Issue 2 ("document the override path in `skills/work-on/SKILL.md`") and Issue 4 ("plan orchestrator initialization section in SKILL.md") would force a serial dependency between them even though Issue 2 touches a different section and could safely run in parallel. More broadly: any shared reference file (e.g., `plan-doc-structure.md`, `SKILL.md`) that appears in multiple outlines as *context* rather than as a *change target* would generate spurious edges.

**False negative rate**: Also non-trivial. A path might be described as "the koto template file" without naming it, or referenced by a shortened alias. The scanner would miss these.

**Maintenance cost**: The regex needs updating whenever a new path style is introduced. False positives degrade plan execution efficiency — the key property that this entire exploration is trying to improve. Serializing all issues that mention `SKILL.md` would turn a parallel plan into a waterfall.

**Overall**: Infeasible as a default-on behavior. Would require a very conservative extraction strategy (only `backtick`-quoted paths inside Acceptance Criteria bullets) to avoid over-constraining, and even then the false positive rate for commonly-referenced files is too high.

### Approach B: Explicit `files_changed:` annotation in the PLAN format

Add a structured field to each Issue Outline that lists the files the issue will write to. The `plan-to-tasks.sh` script reads these fields and auto-adds `waits_on` edges when two issues share a file.

**Feasibility**: Requires two changes: (1) update `plan-doc-structure.md` to specify the field format, and (2) update `plan-to-tasks.sh` to parse and index the field. Neither is architecturally complex. The field would live inside the Issue Outline block, e.g.:

```
**Files**: `skills/work-on/SKILL.md`, `skills/work-on/koto-templates/work-on-plan.md`
```

The script could parse lines matching `\*\*Files\*\*:` using the same pattern it uses for `\*\*Dependencies\*\*:`, extract backtick-quoted tokens, and build a file-to-issue map before generating the `waits_on` arrays.

**False positive rate**: Near zero — the annotation is explicit. The plan author decides what counts as a write target.

**False negative rate**: Non-zero but attributable. If the author omits the field or lists only one of two conflicting files, the conflict survives. But the failure mode is human omission, not tooling error.

**Maintenance cost**: Low. The field is optional in `plan-to-tasks.sh` (absent = no file edges inferred). `validate-plan.sh` could add a warning (not an error) when two issues share a file but have no `waits_on` dependency between them, making the gap visible without blocking the plan.

**Field optionality**: For outlines that clearly touch different files (the common case), the field can be omitted entirely. It is only useful when two or more issues in the same plan touch the same file. This makes it a low-burden annotation: plan authors only need to add it when they're about to run concurrent agents on shared files.

### Existing patterns

No file-dependency inference pattern exists elsewhere in shirabe or the visible tooling. `build-dependency-graph.sh` inverts an explicit dependency list — it does not infer dependencies. `validate-plan.sh` checks structural metadata, not content semantics. The closest analogy is the `**Dependencies**:` field itself, which is already explicit and author-maintained. The `files_changed:` approach is a natural extension of that convention.

The `plan-doc-structure.md` spec notes that Issue Outlines are "brief descriptions" before full issue bodies exist. This makes the spec the right place to add the field definition — it's already the authoritative format reference consumed by both human authors and the scripts.

## Implications

1. Adding `files_changed:` to the Issue Outline format is the only approach with an acceptable false positive rate for a system designed around parallel execution. Static text analysis would undo the parallelism benefits the plan orchestrator provides.

2. The auto-add behavior in `plan-to-tasks.sh` should be additive: if the author has already declared `waits_on: Issue N` for other reasons, the file-collision edge simply merges into the existing `waits_on` array without duplicating entries.

3. A `validate-plan.sh` warning (not error) for "shared file, no declared dependency" is the right enforcement level. Making it an error would block plans where the author intentionally allows concurrent writes (e.g., to different sections of a config file that has known non-conflicting merge behavior).

4. The conflict in Issues 4 and 5 would not have been caught by static analysis even with this annotation, because the plan author assessed them as touching different sections. This points to a deeper issue: file-level granularity is too coarse when two agents edit different sections of the same file. The annotation prevents naive conflicts but doesn't solve section-level concurrent editing.

5. For the section-level problem, the real solution may be a post-execution merge step rather than prevention: child workflows write to named temp files or section-delimited blocks, and a final merge step assembles them. This is out of scope for the annotation approach but worth noting as the limit of what pre-flight detection can solve.

## Surprises

- `validate-plan.sh` does no structural analysis of Issue Outline content at all — it is purely a frontmatter validator with an upstream-chain check. Adding file-conflict detection here would require scoping it into the outline body, which is architecturally inconsistent with its current role. The better hook is `plan-to-tasks.sh`, which already parses outline content.

- The `plan-doc-structure.md` spec has no mention of machine-readability for outline fields beyond `**Dependencies**:`. The Issue Outline format is explicitly described as "brief descriptions" for human consumption. Adding `**Files**:` would be the first annotation in the format intended for script consumption.

- The PLAN-work-on-friction-fixes.md Decomposition Strategy section explicitly states "Each is a contained change to one or two files" — which means the plan *author knew* Issues 4 and 5 would touch `SKILL.md` but didn't consider the concurrent-write risk because they were focused on logical independence, not file-level concurrency.

- There are no evals or CI gates that test `plan-to-tasks.sh` output for dependency correctness — only for schema validity and name format. File-collision detection would need its own eval scenarios.

## Open Questions

1. Should `**Files**:` be required when `execution_mode: single-pr` (where parallel execution is the default), or optional everywhere? Making it required for single-pr would force authors to be explicit but adds friction for the common case where all issues touch different files.

2. What is the right format for the field value? Backtick-quoted paths (` `path/to/file` `) are already conventional in outlines and easy to parse. A YAML-style list would be more structured but breaks the markdown prose format.

3. Should the auto-added `waits_on` edge be the full serialization (A waits on B) or just a warning with no automatic edge? Automatic edges are safer (prevent the conflict) but may produce suboptimal scheduling. A warning leaves the human in control.

4. Can `validate-plan.sh` be extended to parse outline content without breaking its single-responsibility as a frontmatter validator? Or should file-collision detection live in a new `lint-plan.sh` script?

5. Does the section-level concurrent editing problem require a fundamentally different approach (temp files + merge) rather than pre-flight annotations? If so, is that a shirabe change or a koto engine feature?

## Summary

Neither `plan-to-tasks.sh` nor `validate-plan.sh` has any mechanism for file-level dependency inference today — both operate entirely on explicit `**Dependencies**:` fields and frontmatter metadata. Static text analysis of outline prose is technically feasible but produces too many false positives (commonly-referenced files like `SKILL.md` appear in multiple outlines as context, not change targets) and would degrade the parallelism the orchestrator provides. The right approach is an explicit `**Files**:` annotation in the Issue Outline format, parsed by `plan-to-tasks.sh` to auto-add `waits_on` edges when two issues share a write target; this mirrors the existing `**Dependencies**:` convention, has near-zero false positives, and is optional so it only adds friction when parallel file conflicts are actually possible. However, this approach doesn't fully solve the case that caused the original incident — Issues 4 and 5 were touching different *sections* of `SKILL.md`, not the same lines — suggesting that section-level concurrent editing may require a post-execution merge strategy rather than pre-flight detection.
