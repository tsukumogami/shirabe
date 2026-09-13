# Exploration Findings: cascade-verdict-residue

## Core Question

shirabe#354 asked for `cascade_status: partial` when the completion cascade can't
find the ROADMAP feature it was asked to update. PR #353 (7cd13d1) delivered that
verdict by recording the step as `failed` rather than `skipped`. Two of #354's three
acceptance criteria are written against a `skipped` step and a worked example that
shows `skipped` with `partial`. What is the residue: a document to amend, criteria
that were wrong, or a behavioural gap nobody has named?

Evidence labels: MEASURED (command output exists), VERIFIED (read by the
orchestrator), AGENT-MEASURED (run by a research agent; its harness is
`$CLAUDE_JOB_DIR/tmp/exp/exp.sh`, output `results.txt`, excerpts re-read by the
orchestrator but not re-run).

## Round 1

### Key Insights

1. **The design isn't split between a failures table and an example. It has one
   model and a misread table.** (lead-design-reading, lead-status-vocabulary;
   VERIFIED) `DESIGN-completion-cascade.md` renders "ROADMAP feature not found" as a
   `skipped` step under a `partial` verdict in four places: the worked example
   (`:340-356`), the substitution prose (`:388-391`), `handle_roadmap` step 1
   (`:407-410`), and Mitigations (`:572-574`). All four date from the original commit
   67b7839 and are untouched since. The one internal contradiction is Consequences
   (`:562-564`, "silently skipped"). The table at `:296-304` is headed "Error message
   contract", has no status column, sits under a rule covering "every `skipped` or
   `failed` step" (`:281`), and includes "Issue still open", which the script records
   as `skipped` under `completed` (`run-cascade.sh:671`, Scenario 12). So a row in that
   table doesn't classify a case as `failed`. The code comment at
   `run-cascade.sh:486-499` and the #353 PR body cite it as though it did. #353 had no
   review comments and never mentioned the worked example.

2. **The code follows an exact rule, and the `failed` label carries weight.**
   (lead-status-vocabulary, lead-consumers-and-landing; VERIFIED) On 7cd13d1 every
   `failed` arm sets `ANY_FAILED` and no `skipped` arm does, so `partial` holds iff
   some step failed (`:1150-1156`). `skipped` means one of three things: nothing to
   do, couldn't verify because of an earlier failure, or deliberately deferred. It
   never means "asked and couldn't". The suite pins this (Scenarios 5, 12, 28 and the
   post-verify scenarios). The only production reader of a step's `status` is
   `execute.md`'s halt, which prints `select(.status == "failed")` on a `partial`. A
   `skipped` step with `partial` would halt and print no reason. Earlier precedent
   flips: `PRD-cascade-post-verify-seed.md` R8 cited `skipped` "already in use at
   :404, :414, :564, :698". At 10e46f4, `:404` and `:414` are the two not-found arms
   #353 changed to `failed`.

3. **How #354's three criteria stand on 7cd13d1.** (MEASURED: `run-cascade_test.sh`
   33 passed / 0 failed, Scenario 28 PASS. Log at `$CLAUDE_JOB_DIR/tmp/cascade-suite.log`.)
   - AC1: its intent is met but its wording can't be satisfied, because no `skipped`
     `update_roadmap_feature` step exists any more.
   - AC2: met by Scenario 28 for the first not-found arm only. The second arm (a
     `Downstream:` line with no `###` heading above it, `:518-523`) is reachable
     (AGENT-MEASURED, E3) but has no test.
   - AC3: literally met on the verdict (both are `partial`) and not on step status,
     which the criterion doesn't mention.

4. **A real behavioural gap nobody has named: the ROADMAP lookup never matches the
   format the roadmap skill produces.** (lead-behaviour-gaps; format VERIFIED, run
   AGENT-MEASURED as E9)
   - `handle_roadmap` looks for a line containing the plan slug and `Downstream:`.
     The standard per-feature format has only `**Needs:**`, `**Dependencies:**` and
     `**Status:**`, with no Downstream field (`skills/roadmap/references/roadmap-format.md:149-167`),
     and no skill writes one. The issues-table reference lists `Feature | Status |
     Downstream Artifact` only as an old committed shape to migrate away from
     (`:31`).
   - Yet `/plan` records the ROADMAP on the PLAN it produces under a ROADMAP-fed
     `/scope` (`skills/scope/references/phases/phase-2-chain-orchestration.md:210-216`),
     so the cascade does reach the ROADMAP.
   - Every per-feature `**Downstream:**` line in the repo sits in a test or eval
     fixture, or in one legacy golden-corpus roadmap. The eval fixture
     `skills/execute/evals/fixtures/roadmaps/ROADMAP-cascade-test.md` writes one by
     hand for each cascade eval, which is why the evals pass.
   - The one public sibling ROADMAP (tsuku `ROADMAP-auto-update.md`, 11 features)
     has zero Downstream fields (MEASURED).
   - Consequence: before #353 this path reported `completed` and silently left the
     feature un-updated. Since #353 it reports `partial` and halts `/execute` before
     `gh pr ready`, after the finalization has already been pushed. #353 made a
     standing defect loud. It didn't create it.

5. **A substring slug match can close the wrong feature and delete the ROADMAP,
   with every signal green.** (AGENT-MEASURED, E4, E4b; output re-read)
   - The lookup `grep -F "$plan_slug" | grep -i "Downstream:" | head -1` is neither
     anchored nor bounded, so a plan slug that is a substring of another feature's
     slug matches first.
   - In E4b an unrelated in-progress feature was marked Done, which made every
     feature Done. The ROADMAP was then `git rm`'d and pushed. The verdict was
     `completed` with post-verify `ok`, and the published tree passed the ready check.
   - No issue covers this.

6. **A not-found run through a chain still publishes, and nothing tells the operator
   so.** (AGENT-MEASURED, E1/E2/E2b/E2c; ordering VERIFIED at `:990-1010`)
   - Through a DESIGN, PRD or BRIEF chain, `STAGED_FILES` already holds the
     transitioned nodes, so the commit fires. It includes the PLAN's staged
     deletion, then pushes, then reports `partial`.
   - Scenario 28's comment "nothing publishes" (`run-cascade_test.sh:2585-2586`)
     holds only for the direct PLAN-to-ROADMAP shape.
   - `execute.md`'s recovery list has no entry for "`update_roadmap_feature` failed,
     commit and push ok". That file is read-only for this worker.

7. **The open-issue `delete_roadmap` skip gives recovery advice that can't be
   followed.** (AGENT-MEASURED, E7/E7b/E7c; re-run exit VERIFIED at `:774-777`)
   - Its detail says to "run the cascade again after it closes". But the same run
     deletes and pushes the PLAN, and a re-run without it exits 1.
   - A `gh` failure (unauthenticated, network) is read as "issue still open"
     (`:176-179`).
   - The ready-mode validator accepts an all-Done ROADMAP still at `Active`. Nothing
     ever deletes that ROADMAP.

8. **Already filed, so not new:** #362 covers the no-op awk rewrites that still record
   `ok` (the shapes behind E5, E6 and E8) and the `git add ... || true` sites.
   (VERIFIED)

9. **#358's premise is stale.** (lead-consumers-and-landing; VERIFIED in part) #358
   says the report schema is still accurate and keeps the worked examples "as they
   are" as the contract (its third criterion). On 7cd13d1:
   - The schema's `action` enum lists `transition_roadmap`, which the script never
     emits, and misses six actions it does emit.
   - "Always emits JSON to stdout" is false.
   - The `check_issue_closed` origin-equality claim is false.
   - The not-found example contradicts shipped code.

### Tensions

- **Amending the design to say `failed` records a lookup contract that the roadmap
  format never satisfies.** The vocabulary fix is independent of how the lookup
  works: whatever mechanism locates the feature, failing to find it is `failed`. So
  the amendment doesn't need to wait on the lookup decision. But closing #354
  honestly also means saying out loud that its `partial` now fires on the normal path
  for ROADMAP-fed chains.
- **Amend in place or add a dated section.** The repo allows both: in-place edits to
  Current designs are common (#305, #271 and others), and dated Amendment sections
  exist (#224). A dated section would leave the contradicting passages in the body,
  which is the defect being fixed. That favours an in-place correction.

### Gaps

- The research agent ran the behavioural shapes in its own harness. The orchestrator
  re-read the E4b and E9 output but did not re-run them.
- There's no public evidence of how often ROADMAP-fed `/scope` chains reach
  `/execute` in practice. PLANs are deleted after completion, and no public doc
  names a ROADMAP as upstream. The finding is structural, not observational.
- The second not-found arm has no test.

### Decisions

See `wip/explore_cascade-verdict-residue_decisions.md`.

### User Focus

The coordinator (speaking for the author) said:
- Hand off the ROADMAP lookup gap. It's being filed as its own shirabe issue and
  treated as serious. This worker keeps its deliverable to the #354 docs fix. If
  that fix describes ROADMAP behaviour, it has to describe the current behaviour
  honestly and cite the new issue.
- Crystallize.
- Make one point prominent: reverting to `skipped` would break `execute.md`'s halt,
  which prints only `failed` steps. That's what makes the docs-only answer safe
  rather than just convenient.
- Keep reading-verified claims separate from run-measured ones, and mark the roadmap
  runs as agent-measured wherever they're cited.

## Accumulated Understanding

The residue of #354 itself is documentary. Code and tests encode one exact rule:
`partial` holds iff some step failed, and `skipped` means nothing to do, couldn't
verify, or deferred. The only consumer of the step label depends on `failed` being
present for this case. `DESIGN-completion-cascade.md` holds one consistent `skipped`
plus `partial` model that the code has now left behind, and #353 justified the change
by misreading a message-contract table as a classification. Fixing it is docs-only:
- correct about five passages of the design in place, and state the rule it never
  wrote down;
- update the script's own emit comment (`run-cascade.sh:1129-1136`), which omits
  not-found from `partial` and overstates `completed`;
- reword AC1 and AC3 to the behaviour that shipped, and close #354 against Scenario
  28.

None of that needs `execute.md` or `work-on.md`. Reverting the code to `skipped` is
the only option that would, and it would break the rule and empty the halt's printed
reason.

Next to #354, the exploration turned up a behavioural defect nobody has named. The
cascade's ROADMAP lookup keys on a `Downstream:` field that the roadmap format
doesn't define and no skill writes, so on real roadmaps "feature not found" is the
normal outcome. Since #353, every `/execute` run over a ROADMAP-fed chain pushes and
then halts on `partial`. The lookup is also unanchored enough to close the wrong
feature and delete the ROADMAP under a green `completed`. Fixing that needs a design
call on how the cascade identifies a feature, or on having `/plan` or `/brief` write
the field. That's `/scope`-shaped work, not a doc edit.

Smaller neighbours, also unfiled:
- a not-found run through a chain publishes before it halts, and neither Scenario
  28's comment nor `execute.md`'s recovery list describes that;
- the open-issue deletion skip's recovery path can't be followed, and a `gh` failure
  is read as an open issue.

## Decision: Crystallize
</content>
