# Pragmatic Review: Issue 1 — Topic Classification and Adversarial Lead Injection

## Scope

Files changed: `phase-0-setup.md`, `phase-1-scope.md`

---

## Findings

### 1. Dead identifier in scope file output (Blocking)

**File:** `skills/explore/references/phases/phase-1-scope.md`
**Lines:** 141-143, 183, 192

The implementation names the adversarial lead entry `lead-adversarial-demand` in the scope file (appended as `(lead-adversarial-demand)` in the template at line 183) and the prose at line 141 justifies this with "so Phase 2 can identify it when dispatching."

However, `phase-2-discover.md` has no logic that reads or uses this identifier. Phase 2 derives agent slug names from the lead's question text (step 2.3: "kebab-case the lead's core concept"), not from an embedded annotation in the scope file. Grepping the entire `skills/explore` tree confirms `lead-adversarial-demand` appears only in `phase-1-scope.md`.

The identifier is never consumed. It appears in the scope file output as a visible annotation — `(lead-adversarial-demand)` — that pollutes the artifact with a meaningless tag. Either:
- Remove the identifier and the justification prose, or
- Update Phase 2 to actually read and use it (which would be the fix if special dispatch handling for the adversarial lead is genuinely needed)

If Phase 2 special-casing is intended for a future issue, that's speculative generality right now and should be deferred to the issue that needs it.

### 2. `{{ISSUE_BODY_IF_PRESENT}}` placeholder is underspecified (Blocking)

**File:** `skills/explore/references/phases/phase-1-scope.md`
**Line:** 209

The agent prompt template includes:

```
--- ISSUE CONTENT (analyze only) ---
{{ISSUE_BODY_IF_PRESENT}}
--- END ISSUE CONTENT ---
```

There is no instruction anywhere in the file explaining:
- What to substitute when there is no issue (plain topic invocation)
- Whether to leave the delimiters in place with empty content, omit the block entirely, or substitute a placeholder string

The AC requires: "Issue body content fed into the agent prompt is framed under an explicit delimiter." That criterion is met for the issue case. But the handling for the no-issue case is absent, leaving the template ambiguous for a valid invocation path. An agent following these instructions for a plain-topic exploration would encounter an unresolved placeholder.

Fix: add a note after the template explaining what to substitute when no issue is present. For example: "When invoked without an issue, omit the `## Issue Content` block entirely."

### 3. No over-engineering or speculative generality elsewhere (Advisory / None)

The rest of the implementation is appropriately scoped:
- `phase-0-setup.md` Step 0.2a is tight: writes one field, handles the resume case (append vs. create), and derives the value from actual context rather than hardcoding. No excess.
- The Label Pre-Gate and post-conversation classification gate in `phase-1-scope.md` map directly to AC bullets. No extra signal types, no unused branches.
- The `--auto` mode shortcut (label-only, default to not firing) is explicitly required by AC and has no speculative extensions.
- The six demand-validation questions, confidence vocabulary (high/medium/low/absent), and calibration section distinction are all required by AC and nothing extra was added.
- The visibility block in the agent prompt template is required by AC and is minimal.

---

## Summary

Two blocking findings:

1. The `lead-adversarial-demand` identifier written into the scope file (phase-1-scope.md:183) is never read by Phase 2 or any other consumer. The justification "so Phase 2 can identify it when dispatching" isn't backed by any Phase 2 logic. Either remove the identifier and its prose, or update Phase 2 in this same issue if special dispatch handling is needed.

2. The `{{ISSUE_BODY_IF_PRESENT}}` placeholder in the agent prompt template (phase-1-scope.md:209) has no instructions for the no-issue case. Agents running a plain-topic exploration will encounter an unresolved placeholder. Add a sentence specifying what to substitute (or omit) when no issue is present.

The rest of the implementation is well-scoped: the classification logic, visibility persistence, and agent prompt template all map directly to AC requirements with no excess.
