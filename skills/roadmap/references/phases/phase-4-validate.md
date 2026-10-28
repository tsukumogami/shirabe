# Phase 4: Validate

Three-agent jury review followed by finalization and user approval.

## Goal

Validate the ROADMAP draft through independent review by three specialist agents, fix
any issues found, then finalize the ROADMAP with the user.

## Resume Check

If keys `research/phase4_*` exist in `roadmap-<topic>`, skip to step 4.3
(Process Feedback).

## Approach: 3-Agent Jury

Launch 3 agents with fixed roles. Each evaluates the ROADMAP from a different quality
dimension, all specific to what makes a roadmap effective.

### 4.1 Launch Jury Agents

Before launching, allocate two private directories outside the work tree, one for the
verdicts and one for the inputs the seats read, and materialize the scope key into the
second:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch          # prints <verdicts-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch          # prints <inputs-dir>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" get roadmap-<topic> work/scope.md <inputs-dir>
                                                                  # prints <scope-file>
```

Load `skills/roadmap/references/roadmap-format.md` and pass the relevant quality
guidance to each agent.

**Seat commissioning** (per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`): Theme Coherence, Sequencing and Dependency, and Annotation and Boundary run on `model: "sonnet"` with an 8-call budget. Packet: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" doc --doc docs/roadmaps/ROADMAP-<topic>.md --format skills/roadmap/references/roadmap-format.md --extra <scope-file> --scratch <inputs-dir>`. `<scope-file>` is the path `get` printed.

Before the round starts, run the document check on the draft
(`${CLAUDE_PLUGIN_ROOT}/references/doc-check-steps.md` has the whole loop):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-check.sh" --doc docs/roadmaps/ROADMAP-<topic>.md --format roadmap --moment pre_jury --phase 4 --topic <topic> --skill roadmap
```

Exit 0 goes on to the jury. Exit 1 means a block-stage rule failed: fix what
its findings name, commit, and run the fix loop in that reference with
`--answers check_fail` until the post-fix check exits 0, before spawning. A
`doc-check: unresolved after 3 cycles` line is a significant issue: present the findings to the user as a significant issue,
or under `--auto` stop the run and report them.

Beside the packet, before launching, record the round as telemetry (add
`--fallback` when the round runs as the serial self-jury). It always exits 0
and changes nothing the jury does; `${CLAUDE_PLUGIN_ROOT}/references/review-verdicts.md`
describes the verdict block each seat ends its file with and the calls here:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" round-started --skill roadmap --topic <topic> --doc docs/roadmaps/ROADMAP-<topic>.md --seat-count 3 --doc-format roadmap
```

Launch all 3 agents in parallel using the Agent tool with `run_in_background: true`.

Each agent receives:
- The ROADMAP draft (read from `docs/roadmaps/ROADMAP-<topic>.md`)
- Their role and evaluation criteria
- The scope (the contents of key `work/scope.md`) for reference
- A pinned output file in `<verdicts-dir>`; reviewers never call koto

#### Theme Coherence Reviewer

```
You are reviewing a ROADMAP document for theme coherence and feature quality.
Your job is to test whether the features belong together and each is at the
right level of granularity.

## ROADMAP to Review
[Contents of docs/roadmaps/ROADMAP-<topic>.md]

## Original Scope
[Contents of key work/scope.md in roadmap-<topic>]

## Evaluate
1. Do all features belong under the stated theme? Could any feature be removed
   without weakening the theme, or does each contribute to the coordinated
   initiative?
2. Is each feature independently describable at PRD level? A feature that can't
   stand alone as a PRD is too granular. A feature that would need multiple PRDs
   is too broad.
3. Is there at least one feature? A roadmap with none has nothing to track.
   A one-feature roadmap is legitimate -- it is still the progress ledger for
   the strategy's execution and still the bridge into the tactical chain --
   so do not fail a roadmap for having exactly one feature.
4. Is the theme itself coherent? Does it explain WHY this is one tracked
   initiative rather than unrelated independent work?
5. Are feature rationales specific to this roadmap, or could they apply to any
   project? Generic rationales suggest weak theme coherence.

## Verdict Block

End the file, after the Summary, with a fenced block tagged review-verdicts
holding a JSON array of one entry: {"rule_id": "rs-070", "section":
"document", "verdict": "PASS"}, with "FAIL" in place of "PASS" when your
verdict is FAIL.

## Output Format
Write your full review to `<verdicts-dir>/phase4_theme-coherence.md`:

# Theme Coherence Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

#### Sequencing and Dependency Reviewer

```
You are reviewing a ROADMAP document for sequencing correctness and dependency
integrity. Your job is to test whether the ordering is justified and dependencies
are explicit and acyclic.

## ROADMAP to Review
[Contents of docs/roadmaps/ROADMAP-<topic>.md]

## Original Scope
[Contents of key work/scope.md in roadmap-<topic>]

## Evaluate
1. Are all dependencies explicit? Check for implied ordering that isn't captured
   as a stated dependency. If Feature B uses something Feature A produces, that's
   a dependency even if not listed.
2. Is the dependency graph acyclic? Trace the dependencies -- no feature should
   transitively depend on itself.
3. Does the sequencing rationale explain WHY this order, not just state the order?
   "Feature A before B" isn't a rationale. "Feature A before B because A produces
   the API that B consumes" is.
4. Are parallelization opportunities acknowledged? Features with no mutual
   dependencies should be noted as parallelizable. Ignoring parallelization
   suggests the sequencing wasn't thought through.
5. Are hard blockers distinguished from soft preferences? Conflating the two
   creates artificial bottlenecks.

## Verdict Block

End the file, after the Summary, with a fenced block tagged review-verdicts
holding a JSON array of one entry: {"rule_id": "rs-071", "section":
"document", "verdict": "PASS"}, with "FAIL" in place of "PASS" when your
verdict is FAIL.

## Output Format
Write your full review to `<verdicts-dir>/phase4_sequencing-dependency.md`:

# Sequencing and Dependency Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

#### Annotation and Boundary Reviewer

```
You are reviewing a ROADMAP document for annotation accuracy and content boundary
violations. Your job is to check that needs-* labels are correct and the roadmap
doesn't contain downstream content.

## ROADMAP to Review
[Contents of docs/roadmaps/ROADMAP-<topic>.md]

## Original Scope
[Contents of key work/scope.md in roadmap-<topic>]

## Evaluate
1. Do needs-* labels match feature descriptions? If a feature says "needs-design"
   but the description implies requirements aren't written yet, the label should
   be "needs-prd" instead.
2. Does the roadmap contain downstream content that belongs in other artifacts?
   Check for:
   - Feature requirements or user stories (belongs in a PRD)
   - Technical architecture decisions (belongs in a Design Doc)
   - Implementation tasks or issue lists (belongs in a Plan)
   - Dates or deadlines (roadmaps sequence features, not calendar time)
   A milestone's Evidence clauses are not requirements: they say how someone
   checks the Outcome, not what the feature must do, so don't report them as
   PRD content.
3. Are all features marked `Not started`? At creation time, no feature should
   have progress.
4. Does the roadmap pass structural validation? Check against the format spec:
   required sections present, frontmatter correct (`schema: roadmap/v3`, with
   the items under `## Milestones`), status is "Draft", and `shirabe validate`
   reports no FC21 finding.
5. On a milestone roadmap (`roadmap/v2` or `roadmap/v3`), judge each
   milestone's content against the format reference's Milestones section,
   applying its Evidence rule to every clause. Each of these is an issue that
   fails the review and sends the draft back:
   - an Outcome that names mechanism (a command, file, component or
     implementation step to build) instead of who can do what, end to end;
   - an Evidence clause that doesn't say who checks, from what starting
     state, what they do and what they see;
   - an Evidence clause only the author could judge (the delivering session's
     say-so, "works well"), or one that is a merged pull request, a passing
     test run or an artifact existing;
   - an Evidence clause that names the file, script, function or line that
     implements the check (`run check-plugins.sh`, `the loader's
     parse_manifest returns an error`): that is mechanism, and it belongs in
     Left open;
   - a Left open that holds part of the Outcome: something whose absence
     would make the Outcome false.
6. Are scope boundaries clear? The "covers" and "doesn't cover" should leave no
   ambiguity about what work falls inside this roadmap.

## Verdict Block

End the file, after the Summary, with a fenced block tagged review-verdicts
holding a JSON array of one entry: {"rule_id": "rs-072", "section":
"document", "verdict": "PASS"}, with "FAIL" in place of "PASS" when your
verdict is FAIL.

## Output Format
Write your full review to `<verdicts-dir>/phase4_annotation-boundary.md`:

# Annotation and Boundary Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

### 4.2 Collect Results

Wait for all 3 agents to complete. Read their summaries. Then turn the verdict files
into keys (`ingest` removes the verdicts directory) and remove the inputs directory:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" verdicts --skill roadmap --topic <topic> --doc docs/roadmaps/ROADMAP-<topic>.md --dir <verdicts-dir> --doc-format roadmap
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" ingest roadmap-<topic> research <verdicts-dir>
rm -rf -- <inputs-dir>
```

`ingest` prints `added=research/phase4_<role>.md` per verdict and reports on stderr
anything it skipped. A verdict that did not become a key counts as a FAIL with reason
"verdict missing".

### 4.3 Process Feedback

**Reference**: Full review details available in keys `research/phase4_*` in `roadmap-<topic>`.

Determine consensus:

| Outcome | Action |
|---------|--------|
| All 3 pass | Proceed to finalization |
| 1-2 fail with minor issues | Fix issues, briefly show fixes to user, proceed |
| Any fail with significant issues | Present issues to user, incorporate fixes, re-validate if changes are substantial |
| Agents disagree on same issue | Present both perspectives, recommend the better-supported one, let the user override |

**Reviewer disagreement:** quote both perspectives, then say which one you find
better supported and why, citing the specific verdict finding that decides it.
If the two are genuinely balanced, say so explicitly, still recommend one, and
name the tiebreaker. The user overrides if they disagree.

**For minor issues** (wording fixes, sharpening a needs-* label, clarifying a
dependency): Fix directly, update the ROADMAP, show the user what changed.

Commit the fixes (`docs(roadmap): apply jury fixes for <topic>`), then record what they answered and check
the draft again:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-events.sh" fix --doc docs/roadmaps/ROADMAP-<topic>.md --format roadmap --answers jury_fail --skill roadmap
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-events.sh" sections --doc docs/roadmaps/ROADMAP-<topic>.md --format roadmap --skill roadmap
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-check.sh" --doc docs/roadmaps/ROADMAP-<topic>.md --format roadmap --moment post_fix --phase 4 --topic <topic> --skill roadmap
```

While the post-fix check exits 1, fix what it names, commit, and repeat the
three calls with `--answers check_fail`; on `doc-check: unresolved after 3
cycles`, present the findings to the user as a significant issue (under `--auto`, stop and report).

**For significant issues** (circular dependencies, missing features, downstream
content mixed in, sequencing without rationale, a mechanism Outcome, Evidence
the author alone could judge or that is a merge, test run or artifact, a Left
open holding part of an Outcome): Present the jury's findings to the
user with specific recommendations. Use AskUserQuestion when the findings surface
trade-offs or decisions. If changes are substantial (feature additions, dependency
rewrites), loop back to Phase 3 step 3.5.

**Record what follows the round**, once it is decided, as telemetry: `proceed`
when all three pass, `fix_and_proceed` for fixes applied without a new jury,
`loop_back` for a return to Phase 3, `rerun` for fixes that get a fresh jury,
`stop` when the document goes no further.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/review-events.sh" decision --skill roadmap --topic <topic> --doc docs/roadmaps/ROADMAP-<topic>.md --decision <decision> --doc-format roadmap
```

### 4.4 Finalize ROADMAP

After all issues are resolved:

1. Update the ROADMAP with all fixes
2. Populate the reserved sections (see 4.4a below)
3. Verify the ROADMAP passes the format reference's validation rules
4. Commit: `docs(roadmap): finalize ROADMAP for <topic>`

#### 4.4a Populate the reserved sections

The Implementation Issues and Dependency Graph sections are reserved for
the tool and ship as empty skeletons. Fill them here, before the author
reviews the roadmap in 4.5, so what they approve is what merges:

```bash
shirabe roadmap populate <roadmap-path> --no-issues
```

Three things about this step:

- **It is issueless, always.** The `--no-issues` flag is passed
  unconditionally, regardless of what `## Roadmap Issues:` resolved to
  during setup. An automatic run must never create GitHub issues; the
  preference governs only what a human-invoked `/roadmap populate <path>`
  does when that human passes no mode flag. Pass the flag explicitly rather
  than relying on the subcommand's default.
- **The R14 approval gate does not apply.** Nothing is created, so there
  is nothing to approve. Do not present the gate here.
- **Warnings are worth surfacing.** The run reports on stderr when a
  feature's label could not serve as a table key (it falls back to `F<n>`)
  or when a description had to be truncated. Include any such warning in
  the 4.5 summary -- it names a feature the author may want to rename or
  give a shorter opening.

If the roadmap has no items yet (an empty `## Milestones` section, or
`## Features` on a v1 or v2 roadmap), populate fails with a clear error. That
is a real problem with the draft, not a reason to skip this step: return to
Phase 3 and fix the items section.

### 4.5 Present to User

Present a brief summary:
- Theme (1 sentence)
- Feature count
- Key dependencies
- Any known open questions remaining

Use AskUserQuestion to ask for approval. Frame the question as the agent
recommending activation based on the jury verdicts, not neutrally presenting
options; the user's verdict is the gate. Options:
- **Approve (Recommended)** -- status changes to Active, ready for downstream work
- **Request changes** -- specify what needs to change

**Description field:** Ground the recommendation in the jury verdicts -- name
which reviewers passed and any finding they flagged as non-blocking (e.g., "All
three reviewers passed; the dependency validator flagged the Feature C stub as
borderline but not blocking. Recommending Approve."). If a reviewer's residual
concern makes activation the weaker call, recommend Request changes instead and
cite the finding that drove it.

### 4.6 Handle Approval

**If user approves:**
1. Re-run the issueless population, so the sections reflect any edit made
   during review:
   ```bash
   shirabe roadmap populate <roadmap-path> --no-issues
   ```
   The feature list locks once the roadmap leaves Draft, so this is the last
   moment the sections can be brought into agreement with the Features
   section. Populate is idempotent -- when nothing changed since 4.4a this
   rewrites the same bytes and the commit in step 3 is empty of section
   changes. Still issueless, still no R14 gate.
2. Run `shirabe transition <path> Active` to transition from Draft to Active
3. Commit: `docs(roadmap): activate ROADMAP for <topic>`
4. Create PR (or update existing PR if on a shared branch)

   The body describes the ROADMAP in terms a reader of the repository
   understands: the features it sequences and the order it puts them in, in a
   sentence or two, and a link to the STRATEGY its frontmatter names, if it
   names one. The ROADMAP itself is in the diff. By default the body carries
   none of the workflow's own records: no jury verdicts, reviewer findings or
   list of the fixes they prompted, no session or key names, and no link to
   another ROADMAP or a PLAN, which is deleted when its work completes. Those
   stay in the `roadmap-<topic>` session. A repository opts in to them with
   `## PR Workflow Content: include` in its `CLAUDE.local.md` or `CLAUDE.md`;
   ask the one reader rather than reading the header yourself:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/pr-workflow-content.sh"
   ```

   It prints `include` or `omit` (the default). Under `include`, the body may
   also summarize the jury's verdicts and link the ROADMAP at
   `docs/roadmaps/ROADMAP-<topic>.md` and any ROADMAP or PLAN it relates to.

The same re-run applies when `/roadmap activate <path>` is invoked
standalone (input mode 2) on a roadmap this session did not create: populate
issuelessly first, then transition. That is what covers roadmaps authored
before automatic population existed.

Then present routing options:

"The ROADMAP is active. Based on the features and their annotations, here are the
recommended next steps:"

| Situation | Suggestion |
|-----------|-----------|
| Features need requirements | /prd for features marked needs-prd |
| Features need architecture | /design-doc for features marked needs-design |
| Ready to plan implementation | /plan to break features into issues |
| Features should be tracked as GitHub issues | `/roadmap populate <path> --issues` to file them and re-render the table with issue links |

The last row is the issue-filing action. It is deliberately a separate step
taken after approval, not part of this run: the reserved sections are
already populated, and filing issues is the one action here with a side
effect on shared remote state. It goes through the R14 approval gate.

**If user wants changes:**
Return to Phase 3 step 3.5 to incorporate the specific feedback. Don't re-walk
the entire doc -- focus on the areas the user identified.

### 4.7 Close the Session

`/roadmap` kept its working state as keys in `roadmap-<topic>` and wrote no file to the
staging folder, so there are no working files to delete and no cleanup commit.

Under a parent (`dispatch read` printed `parent=`), skip this step: `/roadmap` never
closes its own session under a parent, and the parent closes `roadmap-<topic>` at its
own exit.

On a direct run, after the PR is created, close the session:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close roadmap-<topic> done
```

It prints `closed=done` (or `closed=noop` when the session was already finished). The
keys stay readable after the close. A run that discards the draft closes with
`abandoned` instead.

## Quality Checklist

- [ ] All 3 jury agents reviewed the ROADMAP
- [ ] All issues from jury review are resolved
- [ ] User has approved the ROADMAP

## Artifact State

Final ROADMAP at `docs/roadmaps/ROADMAP-<topic>.md` with:
- Status "Active" (after user approval)
- All features with correct needs-* annotations and `Not started` status
- `roadmap-<topic>` closed with its keys readable; under a parent it is still open for the parent to close
