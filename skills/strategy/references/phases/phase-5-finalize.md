# Phase 5: Finalize

Surface the jury verdicts to the user for explicit approval, transition the
STRATEGY from Draft to Accepted, clean up working artifacts, and create the
PR. Phase 5 is the irreversible point where the artifact becomes locked for
downstream reference.

## Goal

By the end of Phase 5:

- The user has explicitly approved the STRATEGY (jury PASS alone is not
  enough — human ratification is required).
- The STRATEGY's status is `Accepted` in both frontmatter and the body
  Status section, transitioned via the per-skill script.
- Working artifacts in `wip/` are removed (no committed references to
  `wip/...` paths remain in the artifact or anywhere else).
- A PR is created (or an existing PR on the topic branch is updated).

## Resume Check

If the STRATEGY at `docs/strategies/STRATEGY-<topic>.md` already has
`status: Accepted`, Phase 5 already ran. Verify the wip/ cleanup completed
(no `wip/strategy_<topic>_*` files remain) and exit the workflow. If
cleanup is incomplete, resume from step 5.4.

If the file is still in Draft status but the workflow is in Phase 5, start
at step 5.1.

## 5.1 Summarize the STRATEGY for the User

Surface a brief summary so the user can give meaningful approval without
re-reading the full document:

> Ready to accept STRATEGY for `<topic>`:
> - Bet: <one-sentence paraphrase of the Defensibility Thesis>
> - Scope: <project | org>
> - Upstream: <path or "none">
> - Building Blocks: <N>
> - Downstream Artifacts named: <N>
> - Visibility: <Public | Private>

Then surface the jury verdicts. **Fence each verdict body inside a code
block** to prevent rendered-markdown injection — verdict files contain
author-evaluated prose that may include markdown formatting, and rendering
it as live markdown could skew the human reader's interpretation. A bold
"**PASS**" inside a verdict's prose, if rendered as live markdown, could
visually compete with the verdict marker the user is supposed to read.

For each verdict file, surface as:

> Bet quality reviewer verdict:
>
> ```
> [verbatim verdict body, including the `**Verdict:** PASS | FAIL` marker]
> ```
>
> Altitude reviewer verdict:
>
> ```
> [verbatim verdict body]
> ```
>
> Structural format reviewer verdict:
>
> ```
> [verbatim verdict body]
> ```

If Phase 4 fenced the verdicts in its own summary already, repeat the
fencing here. Verdict bodies are author-data; the orchestrator treats them
as such consistently across both Phase 4 surfacing and Phase 5 surfacing.

If Phase 4 applied minor fixes in place, list those fixes so the user can
see what changed since the verdict was written:

> Minor fixes applied during Phase 4:
> - <fix 1>
> - <fix 2>

## 5.2 Request Explicit Approval

Use AskUserQuestion to request approval. Frame as the agent recommending
acceptance based on the jury verdicts, not neutrally presenting options.

Options:

1. **Approve** — STRATEGY transitions to Accepted, ready for downstream
   ROADMAP / DESIGN / PRD work to reference it as a stable upstream.
2. **Request changes** — name what needs to change; the workflow loops
   back to Phase 2, Phase 3, or Phase 4 as appropriate.
3. **Reject** — discard the draft. The wip/ cleanup runs and the file is
   deleted via `git rm`; no STRATEGY ships.

Description field grounds the recommendation in the jury verdicts (e.g.,
"All three reviewers passed; bet quality reviewer flagged Claim 3 as
borderline but not blocking. Recommending Approve.").

Do not skip the approval step even when all three reviewers pass. Jury PASS
de-risks the approval but does not eliminate human judgment — the user may
add caveats, request narrowing, or block on a concern the jury did not
catch.

## 5.3 Handle Approval Outcome

### If Approve

1. Run the transition script to move Draft → Accepted:

   ```bash
   skills/strategy/scripts/transition-status.sh \
     docs/strategies/STRATEGY-<topic>.md \
     Accepted
   ```

   The script updates both the frontmatter `status:` field and the body
   `## Status` section. The Draft → Accepted transition does not move the
   file out of `docs/strategies/` — that movement only happens on Sunset.

2. Remove or empty the Open Questions section if it was present (Open
   Questions is Draft-only per the format reference; Accepted status
   forbids it).

3. Commit the acceptance:

   ```
   docs(strategy): accept STRATEGY for <topic>
   ```

Proceed to step 5.4 (Cleanup).

### If Request Changes

1. Capture the specific feedback in the response (which sections, what
   to change).
2. Update `wip/strategy_<topic>_context.md`'s `## Phase` line to the
   target phase (`2`, `3`, or `4`).
3. Loop back to the chosen phase. Phase 4's resume check will re-spawn
   the jury on the next pass if the changes were structural; the
   resume mechanics in each phase file handle the re-entry.

### If Reject

1. Confirm the rejection with the user one more time — accepting that
   the STRATEGY draft will be deleted.
2. Run `git rm docs/strategies/STRATEGY-<topic>.md`.
3. Run the cleanup at step 5.4 to remove wip/ artifacts.
4. Commit:

   ```
   docs(strategy): discard STRATEGY draft for <topic>
   ```

Then exit the workflow.

## 5.4 Cleanup

Remove all working artifacts for this invocation:

```bash
rm -f wip/strategy_<topic>_context.md
rm -f wip/strategy_<topic>_discover.md
rm -f wip/research/strategy_<topic>_phase4_*.md
```

Two-part cleanup contract per the workspace's wip-hygiene rule:

1. Delete the physical files (the commands above).
2. Grep the committed STRATEGY, any other docs in the branch, code
   comments, and frontmatter for any `wip/` path references. Remove
   every reference. The STRATEGY itself should never reference
   `wip/...` paths (Downstream Artifacts durability checks in Phase 3
   and Phase 4 enforce this), but the grep catches any reference that
   slipped in elsewhere.

If the grep surfaces a `wip/` reference in the committed content, do not
proceed to the cleanup commit until the reference is removed or
documented. References to `wip/` are dangling pointers the moment the
cleanup commit lands.

Commit the cleanup:

```
chore(strategy): clean up working artifacts for <topic>
```

## 5.5 Create the PR

If a PR already exists for the topic branch (the workflow may have been
running on a shared branch), update its description with the STRATEGY
acceptance summary. If no PR exists, create one:

- **Title:** `docs(strategy): introduce STRATEGY for <topic>`
- **Body:**
  - Short summary (the bet in 1-2 sentences)
  - Link to the STRATEGY at `docs/strategies/STRATEGY-<topic>.md`
  - Jury verdict summary (all three reviewers PASS, with any caveats
    surfaced at Phase 5)
  - Upstream link if applicable
  - Reminder that downstream ROADMAP / DESIGN / PRD authors can now
    reference this STRATEGY as a stable upstream

Push the branch and create the PR via the standard tooling (e.g., `gh pr
create`). CI runs `shirabe validate` against the new STRATEGY file,
exercising FC01-FC04 plus the R8 visibility-gating check.

## 5.6 Suggest Next Steps

After the PR is open, suggest follow-up routes:

| Situation | Suggestion |
|-----------|-----------|
| Building Blocks have clear feature scope | `/roadmap` to sequence the blocks |
| A specific Building Block needs technical architecture | `/design` to decompose implementation |
| The strategy operationalizes a complex feature | `/prd` to capture requirements for one of the Downstream Artifacts |
| Strategy needs cross-org alignment | Share the STRATEGY PR for stakeholder review |

These are recommendations, not mandates. The strategy's Downstream
Artifacts section names planned work; the user routes when ready.

## Quality Checklist

- [ ] User explicitly approved the STRATEGY (not just jury PASS)
- [ ] Transition script ran successfully and updated both frontmatter and body Status
- [ ] Open Questions section is empty or removed (no Draft-only content remains)
- [ ] All `wip/strategy_<topic>_*` files are deleted
- [ ] No `wip/...` references remain in the committed STRATEGY or in other branch content
- [ ] PR is created or updated with the STRATEGY summary
- [ ] Verdict bodies were fenced in code blocks when surfaced to the user

## Artifact State

After this phase:
- Final STRATEGY at `docs/strategies/STRATEGY-<topic>.md` with `status: Accepted`
- All `wip/` artifacts removed
- PR open with the STRATEGY as the headlining change
- Workflow complete; ready for downstream consumption

## Workflow Exit

`/strategy` exits here. The next interaction with this STRATEGY is via the
`transition-status.sh` script when the bet moves to Active (first downstream
artifact transitions to Active) or to Sunset (bet is invalidated, pivoted,
or abandoned). Transitions outside Draft → Accepted are operator-invoked,
not workflow-driven.
