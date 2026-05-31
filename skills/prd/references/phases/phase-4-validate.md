# Phase 4: Validate

Three-agent jury review followed by finalization and user approval.

## Goal

Validate the PRD draft through independent review by three specialist agents, fix any
issues found, then finalize the PRD with the user.

## Resume Check

If `wip/research/prd_<topic>_phase4_*.md` files exist, skip to step 4.3 (Process Feedback).

## Approach: 3-Agent Jury

Launch 3 agents with fixed roles. Each evaluates the PRD from a different quality
dimension.

### 4.1 Launch Jury Agents

Launch all 3 agents in parallel using the Agent tool with `run_in_background: true`.

Each agent receives:
- The PRD draft (read from `docs/prds/PRD-<topic>.md`)
- Their role and evaluation criteria
- The scope document (`wip/prd_<topic>_scope.md`) for reference

#### Completeness Reviewer

```
You are reviewing a PRD for completeness. Your job is to find gaps -- requirements that
are missing, scenarios that aren't covered, acceptance criteria that don't fully verify
the requirements.

## PRD to Review
[Contents of docs/prds/PRD-<topic>.md]

## Original Scope
[Contents of wip/prd_<topic>_scope.md]

## Evaluate
1. Are requirements sufficient? Could an implementer build this without guessing?
2. Are there gaps between the problem statement and the requirements?
3. Do the acceptance criteria cover all requirements? Are there requirements with no
   corresponding AC?
4. Are the user stories complete? Are there user types or scenarios missing?
5. Is Out of Scope clear enough to prevent scope creep?

## Output Format
Write your full review to `wip/research/prd_<topic>_phase4_completeness.md`:

# Completeness Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>
2. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

#### Clarity Reviewer

```
You are reviewing a PRD for clarity. Your job is to find ambiguity -- requirements that
could be interpreted multiple ways, acceptance criteria that are subjective, user stories
that are vague.

## PRD to Review
[Contents of docs/prds/PRD-<topic>.md]

## Evaluate
1. Could two developers read this PRD and build different things?
2. Are requirements specific enough? Look for words like "should," "appropriate,"
   "reasonable," "as needed" -- these signal ambiguity.
3. Are acceptance criteria binary pass/fail? Could a reviewer objectively verify each one?
4. Are user stories concrete enough to derive test cases from?
5. Is the problem statement specific enough to evaluate solutions against?

## Output Format
Write your full review to `wip/research/prd_<topic>_phase4_clarity.md`:

# Clarity Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Ambiguities Found
1. <location>: <the ambiguous text> -> <why it's ambiguous> -> <suggested clarification>
2. <location>: <the ambiguous text> -> <why it's ambiguous> -> <suggested clarification>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, ambiguity count, and summary to this conversation.
```

#### Testability Reviewer

```
You are reviewing a PRD for testability. Your job is to determine whether someone could
write a test plan from the acceptance criteria alone, without reading the requirements
or talking to the author.

## PRD to Review
[Contents of docs/prds/PRD-<topic>.md]

## Evaluate
1. Could you write a test plan from the acceptance criteria alone?
2. For each acceptance criterion: what would you test? How would you verify it?
   If you can't answer these questions, the criterion isn't testable.
3. Are there requirements that have no testable acceptance criteria?
4. Are there acceptance criteria that are technically untestable (require subjective
   judgment, depend on external factors, or are too vague to verify)?
5. Do the criteria cover edge cases and error conditions, or only the happy path?

## Output Format
Write your full review to `wip/research/prd_<topic>_phase4_testability.md`:

# Testability Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Untestable Criteria
1. <criterion>: <why it's untestable> -> <how to make it testable>

## Missing Test Coverage
1. <requirement or scenario>: <what AC is missing>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

### 4.2 Collect Results

Wait for all 3 agents to complete. Read their summaries.

### 4.3 Process Feedback

**Reference**: Full review details available in `wip/research/prd_<topic>_phase4_*.md`.

Determine consensus:

| Outcome | Action |
|---------|--------|
| All 3 pass | Proceed to finalization |
| 1-2 fail with minor issues | Fix issues, briefly show fixes to user, proceed |
| Any fail with significant issues | Present issues to user, incorporate fixes, re-validate if changes are substantial |
| Agents disagree on same issue | Present both perspectives to user, let user decide |

**For minor issues** (wording fixes, adding a missing AC, clarifying a requirement):
Fix directly, update the PRD, show the user what changed.

**For significant issues** (missing requirements, scope gaps, untestable criteria):
Present the jury's findings to the user with specific recommendations. Use AskUserQuestion
when the findings surface trade-offs or decisions (provide context, recommended answer,
and alternatives). If changes are substantial (new requirements, changed scope), loop
back to Phase 3 step 3.5 to incorporate the changes.

### 4.4 Finalize PRD

After all issues are resolved:

1. Update the PRD with all fixes
2. Verify the PRD passes the `prd` skill's validation rules for /prd drafting
3. Commit: `docs(prd): finalize PRD for <topic>`

### 4.5 Present to User

Present a brief summary of the PRD:
- Problem (1 sentence)
- Key requirements count
- Acceptance criteria count
- Any known limitations

Use AskUserQuestion to request the verdict. Frame the question as the agent
recommending acceptance based on the jury verdicts; the user's verdict is the
gate. The prompt copy MUST advise the author that any rejection rationale
becomes part of the repository's permanent git history:

> Rationale will be committed to git history. Do not include secrets,
> customer identifiers, or content you intend to keep private.

Options:

- **Approve** -- status changes to Accepted, ready for downstream work
- **Request changes** -- specify what needs to change; the workflow loops back
  to Phase 3 step 3.5 to incorporate the feedback
- **Reject** -- terminal verdict; the Draft PRD is deleted via `git rm` and a
  discard commit lands on the current branch. The author exits the workflow;
  no PRD ships. The discard commit is the durable observable signal of
  rejection in both in-chain (`/scope` reads it from `git log`) and
  out-of-chain (author re-reads the same commit) contexts.

### 4.6 Handle Approval

**If user approves:**
1. Update PRD status from "Draft" to "Accepted" (both frontmatter and Status section)
2. Remove or empty the Open Questions section (if present)
3. Commit: `docs(prd): accept PRD for <topic>`
4. **Remove blocking label from source issue.** Check the PRD's frontmatter for a
   `source_issue` field. If present, check your project's label vocabulary
   (CLAUDE.md `## Label Vocabulary`) for which label to remove on PRD acceptance.
   If no vocabulary is defined, skip label removal -- the project hasn't
   configured which labels map to PRD completion.
   Skip this step if `source_issue` is not set in the frontmatter.
5. Create PR (or update existing PR if on a shared branch)

Then present routing options:

"The PRD is accepted. Based on the complexity, here are the recommended next steps:"

Assess complexity from the requirements:
- **Simple** (few requirements, clear scope, could be a single PR): Suggest direct
  implementation
- **Medium** (multiple requirements, needs issue breakdown): Suggest a planning
  workflow
- **Complex** (needs technical design decisions): Suggest a design workflow first

**If user wants changes:**
Return to Phase 3 step 3.5 to incorporate the specific feedback. Don't re-walk
the entire doc -- focus on the areas the user identified.

**If user rejects:**

The Reject branch is a terminal verdict. It discards the Draft PRD and exits
the workflow. Run the following ordered actions; do not skip steps.

1. **Second-confirmation prompt.** Re-ask the author with AskUserQuestion that
   they want to discard the Draft PRD permanently. Surface the commit subject
   that will land (`docs(prd): discard PRD draft for <topic>`) so the author
   sees the durable trace before approving destruction. If the author declines,
   route back to step 4.5 without modifying any files.

2. **Capture the rationale.** Prompt the author for a one-paragraph rationale
   explaining why the PRD is being discarded. Restate the public-history
   disclaimer ("Rationale will be committed to git history") in the prompt so
   the author has a second opportunity to redact private content.

3. **Write the rationale to a tmpfile.** Author-supplied rationale strings are
   free-form and may contain shell metacharacters (quotes, backticks, dollar
   signs). Persist the rationale to a temporary file rather than passing it
   through any shell argument:

   ```bash
   RATIONALE_FILE=$(mktemp)
   cat > "$RATIONALE_FILE" <<EOF
   docs(prd): discard PRD draft for <topic>

   <rationale captured at step 2>
   EOF
   ```

   The first line is the conventional-commit subject (the literal substring
   `/scope`'s Component 7.7 git-log search reads); a blank line separates the
   subject from the rationale body.

4. **Remove the durable PRD artifact.**

   ```bash
   git rm docs/prds/PRD-<topic>.md
   ```

5. **Remove the wip working artifacts** for this invocation:

   ```bash
   rm -f wip/prd_<topic>_*.md
   rm -f wip/research/prd_<topic>_phase2_*.md
   rm -f wip/research/prd_<topic>_phase4_*.md
   ```

6. **Commit the discard via `git commit -F`** (file path), never `-m`:

   ```bash
   git commit -F "$RATIONALE_FILE"
   rm -f "$RATIONALE_FILE"
   ```

   Equivalent stdin form (`git commit -F -` reading from a here-document) is
   acceptable when scripting inline; the invariant is that the rationale never
   transits a `-m "..."` shell argument. The discard commit lands on the
   current branch and is the durable observable signal of rejection per
   AC30c — `/scope`'s Component 7.7 reads the commit subject from `git log`
   when invoked in-chain; an out-of-chain author reads the same commit body
   for the rationale.

7. **Exit the workflow.** Do not run step 4.7 cleanup (the Reject branch
   handled its own wip cleanup inline in step 5). No PRD ships; the discard
   commit is the only artifact. If on a shared branch with an open PR,
   surface the discard commit SHA in your final response so the caller can
   route accordingly.

### 4.7 Cleanup

After the PR is created, clean up temporary artifacts:

```bash
rm -f wip/prd_<topic>_scope.md
rm -f wip/research/prd_<topic>_phase2_*.md
rm -f wip/research/prd_<topic>_phase4_*.md
```

Commit: `chore(prd): clean up working artifacts`

## Quality Checklist

- [ ] All 3 jury agents reviewed the PRD
- [ ] All issues from jury review are resolved
- [ ] User has approved the PRD

## Artifact State

Final PRD at `docs/prds/PRD-<topic>.md` with:
- YAML frontmatter with status "Accepted"
- All required sections complete and validated
- Working artifacts cleaned up (scope doc, research files removed)
