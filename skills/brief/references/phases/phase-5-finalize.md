# Phase 5: Finalize

Surface the jury verdicts to the user for explicit approval, transition the BRIEF
from Draft to Accepted, close the session, and create the PR. Phase 5 is
the point where the artifact becomes locked for downstream reference.

## Goal

By the end of Phase 5:

- The user has explicitly approved the BRIEF (jury PASS alone is not enough — human
  ratification is required).
- The BRIEF's status is `Accepted` in both frontmatter and the body Status section,
  transitioned via the per-skill script.
- A direct run has closed its `brief-<topic>` session (its keys stay readable),
  and no committed content references a staging-folder path. `/brief` wrote no
  file there, so there is nothing to delete. Under `/scope` the session stays
  open: `/brief` never closes its own session under a parent, and `/scope`
  closes it at its own exit.
- A PR is created (or an existing PR on the topic branch is updated), except
  under `/scope`, which publishes at its own exit (see "Under /scope" below).

## Under /scope

When `/scope`'s dispatch key names `brief`, Phase 5 keeps the
verdict (5.1 to 5.3), the status transition and the acceptance commit, and skips
what publishes or routes, which `/scope` owns
(`docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`,
the Parent-owned-publishing shape in
`${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`):

- 5.2 is asked in an interactive run; an unattended run (`--auto`, from the
  parent's execution mode) takes the recommended option and names it.
- 5.4 closes nothing: `/brief` never closes its own session under a parent.
  `/scope` closes `brief-<topic>` at its exit (`skill-session.sh
  close-children`), and its keys, the jury's verdicts included, stay readable
  until then.
- A Reject still makes its discard commit, the signal `/scope` reads, and an
  unattended run takes it without the confirmation prompt (5.3).
- 5.5 pushes nothing and creates or edits no pull request.
- 5.6 asks no routing question: control returns to `/scope`.

## Resume Check

If the BRIEF at `docs/briefs/BRIEF-<topic>.md` already has `status: Accepted`,
Phase 5 already ran. On a direct run, finish step 5.4 (closing is idempotent: a
finished session is left alone) and exit the workflow. Under `/scope`'s dispatch
key the session stays open by design, since `/scope` closes it at its own exit:
return control to `/scope`.

If the file is still in Draft status but the workflow is in Phase 5, start at step
5.1.

## 5.1 Summarize the BRIEF for the User

Surface a brief summary so the user can give meaningful approval without re-reading
the full document:

> Ready to accept BRIEF for `<topic>`:
> - Problem: <one-sentence paraphrase of the Problem Statement>
> - Outcome: <one-sentence paraphrase of the User Outcome>
> - User Journeys: <N>
> - Upstream: <path or "none">
> - Visibility: <Public | Private>

Then surface the jury verdicts. **Fence each verdict body inside a code block**.

For each verdict file, surface as:

> Content quality reviewer verdict:
>
> ```
> [verbatim verdict body, including the `**Verdict:** PASS | FAIL` marker]
> ```
>
> Structural format reviewer verdict:
>
> ```
> [verbatim verdict body]
> ```

If Phase 4 fenced the verdicts in its own summary already, repeat the fencing here.
Verdict bodies are author-data; the orchestrator treats them as such consistently
across both Phase 4 surfacing and Phase 5 surfacing.

If Phase 4 applied minor fixes in place, list those fixes so the user can see what
changed since the verdict was written:

> Minor fixes applied during Phase 4:
> - <fix 1>
> - <fix 2>

## 5.2 Request Explicit Approval

Use AskUserQuestion to request approval. Frame as the agent recommending acceptance
based on the jury verdicts, not neutrally presenting options.

Options:

1. **Approve** — BRIEF transitions to Accepted, ready for a downstream PRD to
   reference it as a stable upstream.
2. **Request changes** — name what needs to change; the workflow loops back to
   Phase 2, Phase 3, or Phase 4 as appropriate.
3. **Reject** — discard the draft. The file is deleted via `git rm` and the
   session is closed as abandoned; no BRIEF ships.

Description field grounds the recommendation in the jury verdicts (e.g., "Both
reviewers passed; content-quality flagged Journey 3 as borderline-distinct but not
blocking. Recommending Approve.").

Do not skip the approval step even when both reviewers pass. Jury PASS de-risks the
approval but does not eliminate human judgment — the user may add caveats, request
narrowing, or block on a concern the jury did not catch.

The one run that does not ask is an unattended run under `/scope`'s dispatch key: it
takes the recommended option and says so in its output, as "Took the recommended
verdict: <verdict>", then handles that outcome below.

## 5.3 Handle Approval Outcome

### If Approve

1. Run the transition subcommand to move Draft → Accepted:

   ```bash
   shirabe transition \
     docs/briefs/BRIEF-<topic>.md \
     Accepted
   ```

2. Remove or empty the Open Questions section if it was present (Open Questions is
   Draft-only per the format reference; Accepted status forbids it).

3. Commit the acceptance:

   ```
   docs(brief): accept BRIEF for <topic>
   ```

Proceed to step 5.4 (Close the Session), or, under `/scope`'s dispatch key, return
control to `/scope`.

### If Request Changes

1. Capture the specific feedback in the response (which sections, what to change).
2. Update key `work/context.md`'s `## Phase` line to the target phase
   (`2`, `3`, or `4`).
3. Loop back to the chosen phase. Phase 4's resume check will re-spawn the jury on
   the next pass if the changes were structural; the resume mechanics in each phase
   file handle the re-entry.

### If Reject

1. Confirm the rejection with the user one more time — accepting that the BRIEF
   draft will be deleted. An unattended run under `/scope`'s dispatch key asks
   nothing: it already named the verdict it took (5.2).
2. Run `git rm docs/briefs/BRIEF-<topic>.md`.
3. Commit (under `/scope`'s dispatch key too: this discard commit is how `/scope`
   reads the rejection):

   ```
   docs(brief): discard BRIEF draft for <topic>
   ```

4. On a direct run, close the session as abandoned:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close brief-<topic> abandoned
   ```

   Under `/scope`'s dispatch key, don't: `/brief` never closes its own session
   under a parent, and `/scope` closes it.

Then exit the workflow.

## 5.4 Close the Session

`/brief` kept its working state as keys in `brief-<topic>` and wrote no file to
the staging folder, so there are no working files to delete and no cleanup
commit.

Under `/scope`'s dispatch key, skip this step: `/brief` never closes its own
session under a parent. `/scope` closes `brief-<topic>` at its own exit.

On a direct run:

1. Grep the committed BRIEF, any other docs in the branch, code comments, and
   frontmatter for a staging-folder path reference (`git grep -n 'wip/'`), and
   remove any you find. The BRIEF itself should never reference one (the
   Downstream Artifacts and References durability checks in Phase 3 and Phase 4
   enforce this), but the grep catches any reference that slipped in elsewhere.
2. Close the session:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close brief-<topic> done
   ```

   It prints `closed=done` (or `closed=noop` when the session was already
   finished). The keys stay readable after the close.

## 5.5 Create the PR

Under `/scope`'s dispatch key, skip this step: `/scope` pushes and opens the pull
request at its own exit.

If a PR already exists for the topic branch (the workflow may have been running on
a shared branch), update its description with the BRIEF acceptance summary. If no
PR exists, create one:

- **Title:** `docs(brief): introduce BRIEF for <topic>`
- **Body:**
  - Short summary (the problem and outcome in 1-2 sentences)
  - Link to the BRIEF at `docs/briefs/BRIEF-<topic>.md`
  - Jury verdict summary (both reviewers PASS, with any caveats surfaced at Phase
    5)
  - Upstream link if applicable
  - Reminder that a downstream PRD author can now reference this BRIEF as a stable
    upstream

Push the branch and create the PR via the standard tooling (e.g., `gh pr create`).
CI runs `shirabe validate` against the new BRIEF file, exercising FC01-FC04 (the
Formats-map entry drives them; BRIEF has no custom check).

## 5.6 Suggest Next Steps

Under `/scope`'s dispatch key, skip this step and return control to `/scope`, which
decides the next hop.

After the PR is open, suggest follow-up routes:

| Situation | Suggestion |
|-----------|-----------|
| Framing is settled and requirements are the next conversation | `/prd` to capture requirements, with this BRIEF as upstream |
| The brief surfaced a technical question that needs deciding | `/design` to work the architecture |
| The framing changed which features should ship | `/roadmap` to re-sequence |
| A framing question is still open | `/explore` to investigate further |

These are recommendations, not mandates. The brief's downstream is most often a
PRD; the user routes when ready.

## Quality Checklist

- [ ] User explicitly approved the BRIEF (not just jury PASS), or, in an unattended
      run under `/scope`, the output names the recommended verdict it took
- [ ] Transition script ran successfully and updated both frontmatter and body Status
- [ ] Body `## Status` first line is the bare word `Accepted` on its own line (FC03)
- [ ] Open Questions section is empty or removed (no Draft-only content remains)
- [ ] A direct run closed `brief-<topic>` (under `/scope`, the session is still
      open and `/scope` closes it)
- [ ] No staging-folder path references remain in the committed BRIEF or in other
      branch content
- [ ] PR is created or updated with the BRIEF summary (not under `/scope`)
- [ ] Verdict bodies were fenced in code blocks when surfaced to the user

## Artifact State

After this phase:
- Final BRIEF at `docs/briefs/BRIEF-<topic>.md` with `status: Accepted`
- `brief-<topic>` closed with its keys readable (under `/scope`, still open for
  `/scope` to close)
- PR open with the BRIEF as the headlining change (under `/scope`, no PR: control
  is back with `/scope`)
- Workflow complete; ready for downstream consumption

## Workflow Exit

`/brief` exits here. The next interaction with this BRIEF is via
`shirabe transition` when the brief moves to Done (its downstream PRD has
operationalized it). The Accepted → Done transition is operator-invoked, not
workflow-driven, and moves no files.
