# Decision 2: Resume Logic sentinel-consultation row format

**Dispatch context:** Walked as serial-self under sub-agent dispatch; independence-loss caveat applies.

## Question

Per R9/R10, each child SKILL Resume Logic table SHALL consult the `parent_orchestration:` sentinel before evaluating wip/-file-existence rows. What is the row position, what does the row read, what is the action when the sentinel is present vs absent, and where is the convention anchored at the pattern level (R10) so the seven children inherit consistently?

## Constraints

- **Composability** — one row shape across seven children.
- **R31** — absent-sentinel fall-through preserves existing Resume Logic behavior.
- **R32** — pattern-level reference edit (R10) lands before per-skill consumer edits.
- **Existing ladder template** — `references/parent-skill-resume-ladder-template.md` already names Slot 5 (status-aware re-entry) as a parent-specific body slot for parent skills; the child Resume Logic ladder is not the same as the parent's ladder. R10 needs a child-side convention, not a parent-side one.

## Options Considered

### Option A — First-row sentinel-consultation in each child Resume Logic table; child-side convention in `parent-skill-pattern.md` under the existing `## Conditional Feeder Invocation Shape` section

Add the sentinel-consultation row as the FIRST row of each child's Resume Logic table (above all existing wip/-file rows and status-aware rows). The row reads three subfields (`invoking_child`, `suppress_status_aware_prompt`, `rationale`); the action when present is to suppress the child's status-aware re-entry prompt and route per the `rationale` field's `fresh-chain | revise` value. The action when absent is to fall through to the next row (existing behavior). The pattern-level convention lives in `references/parent-skill-pattern.md` under a new subsection inside the existing `## Conditional Feeder Invocation Shape` section, titled `### Child-Side Sentinel Consultation Row Convention`.

**Pros:** R31 backward compatibility falls out — absent sentinel falls through to existing rows. R32 sequencing falls out — pattern-level subsection edit is upstream. Composability falls out — one row shape, copy-pasted into each child. The pattern-level convention is named with a precise location (a subsection of an existing section that already discusses `parent_orchestration:` mechanics at lines 181-206).

**Cons:** The new row sits above the child's existing top row (status-aware re-entry); a reader new to the child must read one extra row before reaching status-aware logic. The extra hop is one row, not one citation; lower cost than Option B's restructure.

### Option B — Restructure the child Resume Logic table to mirror the 9-row parent meta-ladder

Restructure each child's Resume Logic table to mirror the parent meta-ladder's shape (9 rows with state-file-malformed-handling, exit-field-set-handling, etc.), so the sentinel-consultation row becomes one of the meta-ladder rows. The pattern-level convention lives in a new reference file `references/child-skill-resume-ladder-template.md` that mirrors the parent-skill-resume-ladder-template.md.

**Pros:** Symmetric parent/child ladder templates would discharge a future "describe the child contract surface end-to-end" requirement.

**Cons:** Massive scope creep. The PRD does not require restructuring the child Resume Logic tables; it requires adding a sentinel-consultation row. R9 explicitly says "consult ... before evaluating the existing wip/-file-existence and status-aware rows" — i.e., the existing rows are preserved unchanged and the new row is added BEFORE them. Option B would touch every row of every child Resume Logic table — beyond R31's "preserve existing behavior" envelope.

### Option C — Sentinel-consultation lives in Phase 0 step prose, not in Resume Logic table

Add a Phase 0 step in each child that reads the sentinel before the Resume Logic table fires. The Resume Logic table itself is unchanged.

**Pros:** Resume Logic tables stay structurally identical.

**Cons:** AC2.1 explicitly requires "each child SKILL Resume Logic table ... contains a row that consults the `parent_orchestration:` sentinel." A reader of an AC grep against the Resume Logic table doesn't find the row; the AC fails. Option C also breaks the ladder semantic — the Resume Logic table is the FIRST surface the child consults on entry; Phase 0 fires after Resume Logic has already decided where to enter.

## Chosen: Option A — First-row sentinel-consultation in each child Resume Logic table; child-side convention pattern-level

**Rationale.** Option A satisfies AC2.1, AC2.2, AC2.3 directly. R31 backward compatibility is structural (absent-sentinel fall-through). R32 sequencing is structural (pattern-level subsection edit is upstream). Option B is out-of-scope; Option C fails AC2.1.

**Row shape (canonical, named pattern-side, applied identically to all seven children).**

The row sits at the top of the child's Resume Logic table. The row reads three subfields from `wip/<parent>_<topic>_state.md` (the parent's state file at the substrate-defined path per `references/parent-skill-state-schema.md`):

| Resume row position | Predicate | Action |
|---|---|---|
| 1 (top) | `parent_orchestration:` sentinel present in parent state file | Read `invoking_child:` (verify the current run is the named child); read `suppress_status_aware_prompt:` (suppress the child's status-aware re-entry prompt for this run); read `rationale:` (route per `fresh-chain | revise` semantics: `fresh-chain` enters at Phase 0 unconditionally; `revise` enters at status-aware revision mode); proceed to the child's Phase 0 with the sentinel's framing applied |
| 2+ (existing rows) | (existing predicates) | (existing actions — unchanged) |

The row's three subfields are quoted by name in the row's prose so an AC grep against the SKILL.md finds them: `invoking_child`, `suppress_status_aware_prompt`, `rationale`. When the sentinel is absent, the row falls through to row 2 (the child's existing top row); behavior is identical to the existing Resume Logic for direct invocation.

**Pattern-level convention location.** A new subsection `### Child-Side Sentinel Consultation Row Convention` lands in `references/parent-skill-pattern.md` after the existing `## Conditional Feeder Invocation Shape` section (which already discusses `parent_orchestration:` mechanics at lines 181-206). The subsection states: "Every child SKILL Resume Logic table SHALL begin with a sentinel-consultation row that reads the parent state file's `parent_orchestration:` block and routes per the three named subfields. When the sentinel is absent, the row falls through to the child's existing first row. Children copy the row shape verbatim from the canonical row template in this subsection."

**Row template (the canonical text children copy verbatim):**

```
parent_orchestration: sentinel present in <state-file-path>     -> read invoking_child, suppress_status_aware_prompt, rationale; route per rationale (fresh-chain | revise)
```

**Per-skill state-file path table.** Each child reads the sentinel from a parent-specific path; the path is named in each child's SKILL.md alongside the row:

| Child | Parent | State file path |
|---|---|---|
| `/brief`, `/prd`, `/design`, `/plan` | `/scope` | `wip/scope_<topic>_state.md` |
| `/vision`, `/strategy`, `/roadmap` | `/charter` | `wip/charter_<topic>_state.md` |

The child reads the file at the path; if the file doesn't exist (no parent dispatching), the predicate is false and the row falls through. If the file exists but doesn't contain a `parent_orchestration:` block (parent is in a different phase), the predicate is false and the row falls through.

## Assumptions

- The seven child SKILLs that have a Resume Logic section: `/brief` (line 170), `/prd` (line 105), `/design` (line 167), `/plan` (line 250), `/vision` (line 129), `/strategy` (line 159), `/roadmap` (line 144). Verified by grep above.
- The child's Resume Logic table format is plain code-fenced text (not Markdown table), so "row" means "line." Verified across all four tactical-chain children.
- The pattern-level `## Conditional Feeder Invocation Shape` section is the right anchor because it already discusses `parent_orchestration:` at lines 181-206.

## Status

complete
