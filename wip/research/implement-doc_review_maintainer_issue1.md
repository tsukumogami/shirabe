# Maintainability Review: Issue 1
## feat(explore): add topic classification and adversarial lead injection

Files changed:
- `skills/explore/references/phases/phase-0-setup.md`
- `skills/explore/references/phases/phase-1-scope.md`

---

## Findings

### 1. Resume-path gap in Phase 0 Step 0.2a — implicit ordering contract (Blocking)

**Location:** `phase-0-setup.md`, Step 0.2a ("Persist Visibility to Scope File")

The Resume Check at the top of `phase-0-setup.md` reads:

> If already on a `docs/<topic>` branch and `wip/explore_<topic>_scope.md` exists, skip to Phase 1.

When a scope file exists, Phase 0 is skipped entirely — including Step 0.2a, which writes the `## Visibility` section. The next developer reading `phase-0-setup.md` will see the resume skip at the top and conclude that Phase 0 writes are idempotent (the file already exists, nothing was missed). But Step 0.2a also covers the **append** sub-case:

> If `wip/explore_<topic>_scope.md` already exists (resume case where the file was written but the section is absent), append the `## Visibility` section rather than overwriting the file.

This sub-case is unreachable: if the file exists, the resume check fires and skips to Phase 1 before 0.2a executes. A developer asked "why does the agent template in Phase 1 sometimes have an empty `{{VISIBILITY_FROM_SCOPE_FILE}}`?" will read Phase 0 and conclude the append logic covers it — but the code path never runs.

The text in 0.2a's append sub-case also describes a "resume case where the file was written but the section is absent." No scenario in Phase 0 can produce a scope file without a Visibility section, since 0.2a writes it immediately after 0.2. That scenario can only happen if a prior run crashed between 0.2 and 0.2a. The comment implies this is a normal recovery path, which is misleading.

**Fix:** Remove the append sub-case from 0.2a (or move it to Phase 1's Resume Check, which actually executes on resume). Phase 1's Resume Check is the right place to guard against a missing Visibility section, since that phase is the consumer.

---

### 2. `--auto` mode rule is buried after the interactive rule in Label Pre-Gate (Advisory)

**Location:** `phase-1-scope.md`, "Label Pre-Gate" section

The Label Pre-Gate has four paragraphs: three for interactive label cases, then one for `--auto` mode. The `--auto` mode paragraph overrides the third interactive paragraph ("any other label, or no issue — defer to 1.1a") but is placed after it. An agent reading top-to-bottom in `--auto` mode will read "defer to 1.1a" before reaching the `--auto` override. In practice an AI agent will likely read the whole section, but the next person editing this file may add a new label case to the interactive paragraphs and not notice the `--auto` paragraph silently applies a different rule for the same case.

The pattern used in section 1.1a ("Skip this section if: ...") is clearer because it leads with the skip condition. The Label Pre-Gate would be easier to maintain with a similar structure: open with `--auto` mode behavior (a separate labeled block before the interactive cases), so the two modes are visually distinct rather than interleaved.

**Fix:** Move the `--auto` mode paragraph to the top of the Label Pre-Gate section as a named block ("**In `--auto` mode:**"), before the interactive decision tree, so a reader knows which mode they're operating in before reading the case logic.

---

### 3. Section numbering gap: "1.1a" between 1.1 and 1.2 (Advisory)

**Location:** `phase-1-scope.md`, section header "1.1a Post-Conversation Classification"

The section is numbered `1.1a`, sandwiched between `1.1 Checkpoint` and `1.2 Persist Scope`. This numbering works for now, but it signals to the next developer that this was inserted after the original numbering was established — which is historically true but creates a readability wrinkle: a developer looking for "step 1.2" has to skip past `1.1a` and remember that `a` alphabetically follows the numbered steps, not that it's a sub-step of 1.1.

The skip conditions in 1.1a also cross-reference sections by number ("Skip this section if the Label Pre-Gate pre-classified..."), so any future renumbering touches both the section header and the skip list.

This is a minor structural issue that accumulates if more `a/b` sections are added. Worth noting for the next developer who edits this file, but doesn't create a wrong mental model on its own.

---

### 4. `{{ISSUE_BODY_IF_PRESENT}}` substitution placeholder — no fallback documented (Advisory)

**Location:** `phase-1-scope.md`, Adversarial Lead Agent Prompt Template, "## Issue Content" block

The template contains:

```
--- ISSUE CONTENT (analyze only) ---
{{ISSUE_BODY_IF_PRESENT}}
--- END ISSUE CONTENT ---
```

The placeholder name `{{ISSUE_BODY_IF_PRESENT}}` implies conditional substitution, but there's no instruction about what to do when there is no issue (e.g., when Phase 1 was entered from a plain topic with no issue). Should the agent omit the section entirely? Leave the delimiter block empty? Write "(none)"?

Phase 1's own "Label Pre-Gate" section handles the no-issue case with "entering from an issue with any other label, or no issue — defer to 1.1a," but 1.1a can still classify a no-issue topic as directional (if two signals align). In that case the adversarial lead fires with no issue body, and the template gives no instruction on how to render the block.

The next developer instantiating this template for a no-issue directional topic will make a judgment call. Different agents will make different calls.

**Fix:** Add a one-line note beneath the placeholder: "If no issue is present, write '(none)' and omit the delimiters, or omit this section entirely." Either choice is fine; what matters is documenting the choice so instantiation is consistent.

---

### 5. "Mention it in the checkpoint summary" instruction is separated from the checkpoint (Advisory)

**Location:** `phase-1-scope.md`, section 1.2 "Persist Scope", second paragraph

Section 1.2 says:

> Mention it in the checkpoint summary as a research lead, phrased as written above — no adversarial framing in the summary.

The "checkpoint summary" refers to Section 1.1 (Checkpoint), which appears *before* Section 1.1a and 1.2. A developer reading in order will encounter Section 1.1, complete the checkpoint, then reach the instruction in 1.2 that says to do something in that checkpoint. The instruction arrives after the action it modifies.

In practice the agent reads the full Phase 1 file before acting, so this likely works. But a developer modifying the checkpoint format in Section 1.1 won't see the adversarial-lead framing constraint unless they also read 1.2. The constraint should live at the point where the checkpoint behavior is defined, not at the persist step.

**Fix:** Add a brief note to Section 1.1 (Checkpoint): "If the adversarial lead is present, include it in the leads list phrased as its question — no adversarial framing." Move the guidance to its point of use.

---

## Summary

The code is clear overall. The adversarial lead agent prompt is well-structured — the confidence vocabulary, calibration section, delimiter framing, and visibility inheritance all read correctly and match the acceptance criteria. The classification logic in 1.1a is unambiguous.

One blocking issue: the resume path in Phase 0 skips Step 0.2a entirely, making the append sub-case (which covers the scenario where Visibility is missing from a resumed scope file) unreachable. A developer debugging a missing `{{VISIBILITY_FROM_SCOPE_FILE}}` substitution will find the append logic in Phase 0 and conclude it handles the case — but it never fires. The fix belongs in Phase 1's Resume Check, where Phase 0's skip actually lands.

Four advisory issues: the `--auto` mode rule is buried in the middle of the interactive decision tree and will cause maintainers to miss it when adding new label cases; the `1.1a` numbering signals an insertion and complicates future renumbering; the `{{ISSUE_BODY_IF_PRESENT}}` placeholder has no documented fallback for no-issue topics; and the instruction to mention the adversarial lead in the checkpoint is placed after the checkpoint section.
