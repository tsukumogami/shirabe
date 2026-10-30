# Phase 6: Final Review + Finalize

Validate the complete design doc, add frontmatter, commit, and route to next step.

## Goal

Ensure the design doc is complete and ready for approval:
- Launch review agents (architecture + security)
- Validate all required sections
- Check that rejected alternatives have genuine depth (strawman check)
- Add frontmatter, commit, create PR (under `/scope`: commit only)
- Route to next step based on complexity (not under `/scope`)

## Resume Check

If the design doc has YAML frontmatter with status "Proposed", skip to step 6.7
(present for approval).

## Steps

### 6.1 Launch Review Agents

**Seat commissioning** (per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`): Architecture and Security run on `model: "sonnet"` with an 8-call budget; Structural Format runs on `model: "haiku"` with a 6-call budget, since its criteria are a closed checklist. Packet: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" doc --doc docs/designs/DESIGN-<topic>.md --format skills/design/references/design-format.md --scratch <scratch>`. `<scratch>` is a directory from `skill-session.sh scratch` that holds only the packet and is removed once the round is aggregated.

Allocate a private directory outside the work tree for the reviews and keep
the path it prints, `<reviews-dir>`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch
```

Before the round starts, run the document check on the draft
(`${CLAUDE_PLUGIN_ROOT}/references/doc-check-steps.md` has the whole loop):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-check.sh" --doc docs/designs/DESIGN-<topic>.md --format design --moment pre_jury --phase 6 --topic <topic> --skill design
```

Exit 0 goes on to the jury. Exit 1 means a block-stage rule failed: fix what
its findings name, commit, and run the fix loop in that reference with
`--answers check_fail` until the post-fix check exits 0, before spawning. A
`doc-check: unresolved after 3 cycles` line is a significant issue: present the findings to the user before launching,
or under `--auto` stop the run and report them.

Before launching, record the round as telemetry (add `--fallback` when the
round runs as the serial self-jury). It always exits 0 and changes nothing the
review does; `${CLAUDE_PLUGIN_ROOT}/references/review-verdicts.md` describes
the verdict block each reviewer ends its file with and the calls here:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" round-started --skill design --topic <topic> --doc docs/designs/DESIGN-<topic>.md --seat-count 3
```

Launch three review agents in parallel using the Agent tool with `run_in_background: true`.
Reviewers never call koto: each writes one file in `<reviews-dir>`, which the
orchestrator ingests.

**Architecture reviewer:**
```
Review the solution architecture for this design document.

Questions:
1. Is the architecture clear enough to implement?
2. Are there missing components or interfaces?
3. Are the implementation phases correctly sequenced?
4. Are there simpler alternatives we overlooked?
5. Do two passages anywhere in the document that share a number or a
   backticked term contradict each other? A decision that picks one value
   and an architecture section that builds on another, or a component
   described two incompatible ways, is a FAIL. Passages that use the same
   term about different things pass.

[Include Solution Architecture and Implementation Approach sections for
questions 1 to 4, and the whole document for question 5]

Write full analysis to <reviews-dir>/phase6_architecture-review.md, and nowhere else.
End the file with a fenced block tagged review-verdicts holding a JSON array:
one {"rule_id", "section", "verdict"} entry per question per section you
judged it on (verdict PASS or FAIL; section a heading slug such as
solution-architecture, or document). Question ids: 1 rs-047, 2 rs-048,
3 rs-049, 4 rs-050, 5 rs-009. Question 5 is judged on document, once for
the whole design.
Return only key findings and recommendations.
```

**Security reviewer:**
```
Review the security analysis for this design.

Questions:
1. Are there attack vectors not considered?
2. Are mitigations sufficient for identified risks?
3. Are any "not applicable" justifications actually applicable?
4. Is there residual risk that should be escalated?

[Include Security Considerations section]

Write full analysis to <reviews-dir>/phase6_security-review.md, and nowhere else.
End the file with a fenced block tagged review-verdicts holding a JSON array:
one {"rule_id", "section", "verdict"} entry per question per section you
judged it on (verdict PASS or FAIL; section a heading slug such as
security-considerations, or document). Question ids: 1 rs-051, 2 rs-052,
3 rs-053, 4 rs-054.
Return only key findings and recommendations.
```

**Structural-format reviewer:**
```
Review the design document's artifact-shape conformance against the
canonical DESIGN format reference.

Reference: skills/design/references/design-format.md.

Questions covering the four named items:
1. Section presence and order: do all nine required sections appear
   in the canonical order (Status, Context and Problem Statement,
   Decision Drivers, Considered Options, Decision Outcome, Solution
   Architecture, Implementation Approach, Security Considerations,
   Consequences)?
2. Frontmatter field order: does `schema: design/v1` come first, then
   the four required fields (status, problem, decision, rationale) in
   the canonical order with the documented YAML literal block scalar
   shape? Do optional fields (upstream, spawned_from,
   motivating_context, user_visible_surface, decision_provenance)
   follow in the format reference's order?
3. Section-altitude conformance: does each section contain the
   altitude of content the reference prescribes (no PRD-altitude
   requirements, no PLAN-altitude atomic issues)?
4. R19 budget-vs-spec: heuristic check on section length. If any
   section's prose exceeds the reference's documented budget by
   more than 50%, flag the overshoot and ask whether content
   belongs at a different altitude. The >50% threshold avoids
   flagging healthy detail and surfaces only meaningful overshoot.

The reviewer dereferences references/fixes/sub-agent-dispatch.md
when this run is under a parent (the Resume Logic's first row found a
`chain/dispatch` key naming `design` in `scope-<topic>`). Running
under a parent still spawns the jury; the serial-self-jury fallback
applies only when the harness can't spawn subagents.

[Include all nine required sections plus the frontmatter]

Write full analysis to <reviews-dir>/phase6_structural-format-review.md, and nowhere else.
End the file with a fenced block tagged review-verdicts holding a JSON array:
one {"rule_id", "section", "verdict"} entry per question per section you
judged it on (verdict PASS or FAIL; section a heading slug such as
decision-outcome, frontmatter, or document). Question ids: 1 rs-055,
2 rs-056, 3 rs-057, 4 rs-058.
Return only key findings and recommendations.
```

The structural-format reviewer is "in addition to" the existing
architecture and security reviewers (per AC4.4). Reach for it on
every design; the reviewer's checks are mechanically applicable
against the format reference and surface drift the discretionary
reviewers do not catch.

### 6.2 Process Review Feedback

After all three agents complete, record their verdict blocks as telemetry, then
turn the reviews into keys (`ingest` removes the directory, so the verdicts
call comes first):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" verdicts --skill design --topic <topic> --doc docs/designs/DESIGN-<topic>.md --dir <reviews-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" ingest design-<topic> research <reviews-dir>
```

Then consolidate feedback:

| Source | Feedback | Action | Applied |
|--------|----------|--------|---------|
| Architecture | <finding> | <action> | [ ] |
| Security | <finding> | <action> | [ ] |
| Structural-Format | <finding> | <action> | [ ] |

Apply changes to the design doc. If a review finding requires significant rework,
discuss with the user before making changes.

Commit the fixes (`docs(design): apply review feedback for <topic>`), then record what they answered and check
the draft again:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-events.sh" fix --doc docs/designs/DESIGN-<topic>.md --format design --answers jury_fail --skill design
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-events.sh" sections --doc docs/designs/DESIGN-<topic>.md --format design --skill design
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-check.sh" --doc docs/designs/DESIGN-<topic>.md --format design --moment post_fix --phase 6 --topic <topic> --skill design
```

While the post-fix check exits 1, fix what it names, commit, and repeat the
three calls with `--answers check_fail`; on `doc-check: unresolved after 3
cycles`, discuss the findings with the user as significant rework (under `--auto`, stop and report).

Once what follows the review is decided, record it as telemetry: `proceed`
when nothing needed changing, `fix_and_proceed` for applied changes,
`loop_back` for rework in an earlier phase, `rerun` for a fresh review, `stop`
when the design goes no further.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" decision --skill design --topic <topic> --doc docs/designs/DESIGN-<topic>.md --decision <decision>
```

### 6.3 Strawman Check

Read the "Considered Options" section. For each rejected alternative, verify:
- Does it have a genuine explanation of why it was rejected?
- Could someone reading only the rejected alternative understand what it proposed?
- Does the rejection reference real weaknesses from the decision evaluation?

If any rejected alternative reads like a strawman (vague description, superficial
rejection, no evidence of investigation), flag it and strengthen using the decision
reports from Phase 2 (keys `work/decision_<N>_report.md` in `design-<topic>`) and the
Considered Options already written in Phase 3.

### 6.4 Validate Document Structure

Check all required sections are present and well-formed:

**Required Sections:**
- [ ] Status (must be "Proposed")
- [ ] Context and Problem Statement
- [ ] Decision Drivers
- [ ] Considered Options (at least 1 alternative per decision)
- [ ] Decision Outcome
- [ ] Solution Architecture
- [ ] Implementation Approach
- [ ] Security Considerations (content per Phase 5 outcome)
- [ ] Consequences (positive, negative, mitigations)

**Reference Hygiene Checks:**

Run this grep from the repo root:

```bash
git grep -nE 'wip/' -- docs/designs/DESIGN-<topic>.md || true
```

- [ ] No `wip/...` paths appear in the committed frontmatter or prose. The
  only acceptable matches are quoted statements OF the wip-hygiene rule
  itself; any path-shaped reference is a hard fail.
- [ ] `upstream:` value resolves on disk via `git ls-files <path>`, OR is a
  valid public `owner/repo:path` cross-repo reference, OR is omitted (per
  Phase 0 step 0.4a). See
  `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`.
- [ ] No references in the design body to working state: a session key
  name (`work/...`, `research/...`) or a staging-folder path is not a
  durable reference.

**STOP if any check fails.** Fix before proceeding.

### 6.5 Write Frontmatter

Replace the skeleton's frontmatter with the full block, using the summary key
(`work/summary.md`). Each summary field is 1 paragraph, using YAML literal block
scalars (`|`):

```markdown
---
schema: design/v1
status: Proposed
problem: |
  <1 paragraph: what technical problem this solves>
decision: |
  <1 paragraph: what approach was chosen and key properties>
rationale: |
  <1 paragraph: why this approach over alternatives>
upstream: docs/prds/PRD-<name>.md   # Only if PRD mode AND step 0.4a resolved to a usable path. OMIT if 0.4a resolved to "omit" (private cross-repo) or if no upstream PRD exists.
decision_provenance: inline-resolved   # Only when Phase 2 resolved a question inline (step 2.2a). OMIT otherwise.
---
```

Keep the keys in this order: `schema`, `status`, `problem`, `decision`,
`rationale`, `upstream`, `spawned_from`, `motivating_context`,
`user_visible_surface`, `decision_provenance`. An optional key you add goes in
its place in that list, and `shirabe validate` reports a key out of place as
FC24. The frontmatter must be the first content in the file, before the
`# DESIGN:` heading.

### 6.6 Commit and PR

Under `/scope`'s dispatch key (SKILL.md, Output, "Under `/scope`"),
run step 1 only: commit, with no push and no pull request.

1. Commit: `docs(design): add design for <topic>`
2. Push and create PR
   - If spawned from an issue: use `Ref #<N>` in PR body (not `Fixes`)
   - Title: `docs(design): design for <topic>`
   - Body: what the design decides and why, from the frontmatter's `problem`,
     `decision` and `rationale`, in plain terms; a link to
     `docs/designs/DESIGN-<topic>.md`; and a link to the upstream document its
     frontmatter names, if it names one. By default it carries none of the
     workflow's own records: no review-agent findings or verdicts, no list of
     the fixes they prompted, no session or key names, and no link to a
     ROADMAP or PLAN, which is deleted when its work completes. Those stay in
     the `design-<topic>` session. A repository opts in to them with
     `## PR Workflow Content: include` in its `CLAUDE.local.md` or
     `CLAUDE.md`; ask the one reader rather than reading the header yourself,
     `"${CLAUDE_PLUGIN_ROOT}/scripts/pr-workflow-content.sh"`, which prints
     `include` or `omit` (the default). Under `include`, the body may also
     summarize the step 6.2 review feedback and link a ROADMAP or PLAN the
     design relates to.

### 6.7 Present for Approval

Display the design summary:

```
## Design Summary

**Problem:** <frontmatter problem field>

**Decision:** <frontmatter decision field>

**Rationale:** <frontmatter rationale field>
```

Ask user for the verdict using AskUserQuestion, following the pattern in
`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`. Frame the question
as the agent recommending a verdict based on the Phase 6 review agents, not
neutrally presenting options; the user's verdict is the gate. The prompt copy
MUST advise the author that any rejection rationale becomes part of the
repository's permanent git history, so private content must not be included:

> Rationale will be committed to git history. Do not include secrets,
> customer identifiers, or content you intend to keep private.

**Description field:** Ground the recommendation in the step 6.2 consolidated
feedback -- name which reviewers raised findings, what was applied, and any
residual concern left standing (e.g., "Architecture and structural-format
cleared after the two applied fixes; security flagged the token path as
worth revisiting post-merge but not blocking. Recommending Approved."). If a
residual finding makes acceptance the weaker call, recommend Continue-revising
instead and cite the finding that drove it.

Options (mark the recommended one "(Recommended)"):

- **Approved**: The design is ready; proceed to acceptance and routing.
- **Reject**: Terminal verdict. The Draft DESIGN is discarded via `git rm`
  and a discard commit lands on the current branch. No DESIGN ships. The
  discard commit is the durable observable signal of rejection in both
  in-chain (`/scope` reads it from `git log`) and out-of-chain (author
  re-reads the same commit) contexts per AC30c.
- **Continue-revising**: The design needs more work. Specify what needs to
  change; the workflow loops back to the relevant phase and re-runs Phase 6
  when changes are complete. (This is the existing "Needs iteration"
  behavior, renamed.)

Under `/scope`'s dispatch key, the verdict is still this step's: an
interactive run asks the author as above, and an unattended run (`--auto`)
takes the recommended verdict and names it in its output, as "Took the
recommended verdict: <verdict>".

### 6.8 Handle Approval

**If approved:**

1. Change status from "Proposed" to "Accepted" (frontmatter and body)
2. Commit: `docs(design): accept design for <topic>`
3. **Remove blocking label from source issue.** Skip if there is no source issue.
   Check your project's label vocabulary (CLAUDE.md `## Label Vocabulary`) for
   which labels to remove on design acceptance. If no vocabulary is defined, look
   for any `needs-*` label and remove it. The tracking label is applied later by
   /plan, not here.
   Under `/scope`'s dispatch key, skip this step. The label
   edit is a `gh` write that is not among the `gh` writes `/scope`'s SKILL.md
   lists for a run (its pull request, `/plan`'s gated issue filing and the
   coordination PR), and that list skips a child's own upstream-issue edit;
   skipping it is this skill's reading of
   `docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`,
   which leaves publishing to the parent. Nothing in a `/scope` run removes
   the label instead: `/plan` removes it at its step 7.8 only when the author
   names the upstream issue, and that is a routing prompt `/scope`'s children
   skip. The label stays on the issue for the author to remove; who should
   remove it under `/scope` is an open question, tracked as #666.
4. **Update parent design doc** (only when the design doc has `spawned_from` in its frontmatter).
   If your project defines a label lifecycle in the extension file
   (`@.claude/shirabe-extensions/design.md`), follow those instructions for
   parent doc updates (Mermaid diagram class changes, child reference rows,
   spawned_from metadata). If no extension defines this, skip parent doc updates.
   This is an edit to a file on the branch, not a `gh` write, so it runs
   under `/scope`'s dispatch key too.
5. **PR body convention.** If spawned from an issue, use `Ref #<N>` in the PR
   body, NOT `Fixes #<N>`. The issue stays open until implementation completes.
6. Under `/scope`'s dispatch key, skip this step and return control to
   `/scope`. Otherwise, run the complexity assessment and routing from the design SKILL.md "Output" section (the table comparing Simple vs Complex criteria, followed by the AskUserQuestion presenting Plan vs Approve options). Use `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md` for the AskUserQuestion formatting pattern.

### 6.9 Close the Session

`/design` kept its working state as keys in `design-<topic>` and wrote no file
to the staging folder, so there are no working files to delete and no cleanup
commit.

Under `/scope`'s dispatch key, skip this step: `/design` never closes its own
session under a parent, and `/scope` closes `design-<topic>` at its own exit.

On a direct run, after approval and routing, close the session:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close design-<topic> done
```

It prints `closed=done` (or `closed=noop` when the session was already
finished). The keys stay readable after the close.

**If continue-revising:**
- Discuss what needs changes with user
- Return to the relevant phase
- Re-run Phase 6 when changes are complete

**If reject:**

The Reject branch is a terminal verdict. It discards the Draft DESIGN and
exits the phase. The Reject branch fires AFTER step 6.6 (Commit and PR) has
already committed the Draft to the branch — the commit-then-approve ordering
is load-bearing because it preserves Draft durability across session
interruptions. Reject pays the `git rm` cost in exchange for that durability
guarantee. Do not reorder 6.6 and 6.7.

Run the following ordered actions; do not skip steps.

1. **Capture the rationale.** Prompt the author for a one-sentence rationale
   explaining why the DESIGN is being discarded. Restate the public-history
   disclaimer ("Rationale will be committed to git history") in the prompt
   so the author has a second opportunity to redact private content. An
   unattended run (`--auto`) asks nobody: write the rationale yourself from
   the review findings behind the verdict, as
   `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` has you do at any
   decision point, keeping it free of private content.

2. **Write the rationale to a tmpfile.** Author-supplied rationale strings
   are free-form and may contain shell metacharacters (quotes, backticks,
   dollar signs). Persist the rationale to a temporary file rather than
   passing it through any shell argument:

   ```bash
   RATIONALE_FILE=$(mktemp)
   cat > "$RATIONALE_FILE" <<EOF
   docs(design): discard DESIGN draft for <topic>

   <rationale captured at step 1>
   EOF
   ```

   The first line is the conventional-commit subject (the literal substring
   `/scope`'s Phase-N Reject Handling searches `git log` for); a blank line separates
   the subject from the rationale body.

3. **Remove the durable DESIGN artifact.**

   ```bash
   git rm docs/designs/DESIGN-<topic>.md
   ```

4. **Commit the discard via `git commit -F`** (file path), never `-m`. This
   commit still happens under `/scope`'s dispatch key: it is the rejection signal
   `/scope` reads from `git log`, not the cleanup commit the dispatch key skips.

   ```bash
   git commit -F "$RATIONALE_FILE"
   rm -f "$RATIONALE_FILE"
   ```

   Equivalent stdin form (`git commit -F -` reading from a here-document)
   is acceptable when scripting inline; the invariant is that the rationale
   never transits a `-m "..."` shell argument.

5. **Close the session as abandoned**, on a direct run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close design-<topic> abandoned
   ```

   Under `/scope`'s dispatch key, skip this step: `/design` never closes its
   own session under a parent, and `/scope` closes it at its exit. There are
   no working files to remove either way: the working state is keys.

6. **Exit the phase.** Do not flip status from Proposed to Accepted; do not
   run the Approved-path complexity assessment or routing; do not run step
   6.9 (the Reject branch closed the session in step 5, or left it to
   `/scope` under the dispatch key).
   No DESIGN ships; the discard commit is the only artifact. The gate
   behaves identically in-chain and out-of-chain — `/design`'s
   responsibility stops at the discard commit. (Any `/scope`-side handling
   is the parent skill's concern, not this phase's.)

## Quality Checklist

Before declaring the phase complete:
- [ ] Strawman check passed (rejected alternatives have genuine depth)
- [ ] Validation per `references/lifecycle.md` rules passed
- [ ] All actionable feedback addressed

## Artifact State

Final design document at `docs/designs/DESIGN-<topic>.md` with:
- YAML frontmatter (status, problem, decision, rationale)
- All required sections complete
- Status: Proposed (or Accepted after approval)
