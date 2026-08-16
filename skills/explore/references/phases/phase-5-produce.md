# Phase 5: Produce

Take the arm the crystallize decision selected.

## Goal

Every arm does one of three things: it authors the one document `/explore` still
owns, it routes to the skill that owns the destination, or it writes a parent
handoff and names the command the author runs next.

No arm invokes a chain-internal child, and no arm writes a durable chain
artifact. `/explore` used to hand off to `/prd`, `/design`, `/vision`, and
`/roadmap` in-session and to write a DESIGN skeleton on the way; a chain step is
not a thing the router decides, so those arms are gone. The exploration's
research files stay in `wip/` for whatever runs next.

## Resume Check

If `wip/explore_<topic>_crystallize.md` exists, read it and take the arm it
names. The outcome is in the `## Chosen Type` section and the candidacy verdicts
are in `## Candidacy`.

If the arm was partially completed (the handoff artifact exists but the author
was never told what to run, say), pick up where it left off rather than
rewriting what's already there.

## Inputs

- **Crystallize decision**: `wip/explore_<topic>_crystallize.md`
- **Findings file**: `wip/explore_<topic>_findings.md` (for content to populate
  handoff artifacts)
- **Decisions file**: `wip/explore_<topic>_decisions.md` (if it exists; accumulated
  decisions from convergence rounds)
- **Scope file**: `wip/explore_<topic>_scope.md` (for the original context)

## Steps

### 5.1 Read the Crystallize Decision

Read `wip/explore_<topic>_crystallize.md` and extract the chosen outcome.

**Stage-1 terminal outcomes** — no chain owns these:

| Outcome | Reference File | Arm |
|---------|----------------|-----|
| Rejection Record | `phase-5-produce-rejection-record.md` | `/explore` authors `docs/decisions/REJECTED-<topic>.md` |
| Spike Report | `phase-5-produce-spike-report.md` | `/explore` authors `docs/spikes/SPIKE-<topic>.md` |
| Decision Record | `phase-5-produce-decision.md` | Routes to `/decision`, in session |
| Competitive Analysis | `phase-5-produce-comp.md` | Routes to `/comp`, in session; private repos only |

**Stage-2 entry points** — where a chain starts:

| Entry Point | Reference File | Arm |
|-------------|----------------|-----|
| File an issue | `phase-5-produce-file-an-issue.md` | No document; next step `/work-on <issue-number>` |
| `/charter` | `phase-5-produce-handoff.md` (`/charter` binding) | Writes `wip/charter_<topic>_handoff.md`; author runs `/charter` |
| `/scope` | `phase-5-produce-handoff.md` (`/scope` binding) | Writes `wip/scope_<topic>_handoff.md`; author runs `/scope` |
| `/execute` | `phase-5-produce-execute.md` | Only when a qualifying PLAN exists: no document, author runs `/execute <plan-path>` |

**Deferred type:**

| Type | Reference File | Arm |
|------|----------------|-----|
| Prototype | `phase-5-produce-deferred.md` | Not produced here; routes to the closest available option |

Read the matching file and follow its instructions.

### 5.2 What Each Arm Hands Over

Each arm's handover is stated in its own file. In summary:

- Both parent arms pass the topic slug, plus `--upstream <path>` when the
  exploration found one the parent accepts: a ROADMAP for `/scope`, a VISION for
  `/charter`. The path travels on the command line, not inside the handoff, so
  the parent's inbound validation reaches it.
- A STRATEGY is passed to neither. The retired roadmap arm passed
  `--upstream <STRATEGY>` to `/roadmap`; `/charter` accepts only a VISION, and a
  chain entering at `/charter` writes its own STRATEGY through `/strategy`.
  Handing one in would hand a parent the artifact its own child produces. An
  exploration that found a STRATEGY names it in the handoff's prose.
- The `/execute` arm passes the PLAN path. It is named only when crystallize
  recorded a qualifying PLAN as present, because `/execute` accepts nothing else.
- The file-an-issue arm passes the issue. Its next step is `/work-on`, the skill
  that accepts an issue number.
- The `/comp` and `/decision` arms pass the topic and the question respectively,
  and the exploration's `wip/` research stays readable to both.

### 5.3 Where the Session Goes

Two arms continue in the same session, because another skill owns the
destination and can start from what the exploration holds: `/decision` and
`/comp`.

Three stop with a command for the author to run: both parent arms and
`/execute`. The parents consume a handoff through their own resume ladders,
below re-entry protection, which is an ordering `/explore` cannot reproduce by
invoking them mid-session.

Three stop with a document or an issue and nothing to run: the rejection record,
the spike report, and filing an issue.

## Cleanup Rule

Do NOT delete `wip/` research files after routing. The parent skills and the
terminal destinations may reference them. Cleanup happens when the next workflow
completes or when the user runs `/cleanup`.

The handoff artifact is not `/explore`'s to clean either. It belongs to the
parent's run: the parent's Phase 4 sweep removes it on exit, and a parent that
bails at Phase 1 leaves it in place so a later invocation reaches it.

## Quality Checklist

Before completing:
- [ ] Crystallize decision read and the chosen outcome identified
- [ ] Correct sub-file read and instructions followed
- [ ] No file written under `docs/designs/` or `docs/competitive/`
- [ ] The arm's handover stated to the author, including any `--upstream` flag
- [ ] wip/ research files left in place (not deleted)

## Next Phase

None. Phase 5 is the final phase of `/explore`. If the session continues into
`/decision` or `/comp`, that skill's orchestrator takes over.
