# Phase 5: Produce

Take the arm the crystallize decision selected.

## Goal

Every arm does one of three things: it authors the one document `/explore` still
owns, it routes to the skill that owns the destination, or it writes a parent
handoff and names the command the author runs next.

No arm invokes a chain-internal child, and no arm writes a durable chain
artifact. `/explore` used to hand off to `/prd`, `/design`, `/vision`, and
`/roadmap` in-session and to write a DESIGN skeleton on the way; a chain step is
not a thing the router decides, so those arms are gone. Every arm ends the
session `explore-<topic>` one of two ways: the parent arms hand the exploration
over in a handoff key and clear the working keys, and every other arm closes the
session, which keeps its keys readable.

## Resume Check

Ask the session where the run stands:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/explore/scripts/explore-state.sh" resume-phase <topic>
```

On `5`, key `work/crystallize.md` exists: read it and take the arm it names. The
outcome is in the `## Chosen Type` section and the candidacy verdicts are in
`## Candidacy`. On any other answer, the run is not at Phase 5: go back to the
phase it names (`none` means a handoff arm already cleared the working keys;
check for `handoff/scope.md` or `handoff/charter.md` before starting over).

If the arm was partially completed (the handoff artifact exists but the author
was never told what to run, say), pick up where it left off rather than
rewriting what's already there.

## Inputs

- **Crystallize decision**: key `work/crystallize.md`
- **Findings key**: `work/findings.md` (for content to populate handoff
  artifacts)
- **Decisions key**: `work/decisions.md` (if it exists; accumulated decisions
  from convergence rounds)
- **Scope key**: `work/scope.md` (for the original context)

Read a key with `koto context get explore-<topic> <key>`.

## Steps

### 5.1 Read the Crystallize Decision

Read key `work/crystallize.md` and extract the chosen outcome.

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
| `/charter` | `phase-5-produce-handoff.md` (`/charter` binding) | Writes key `handoff/charter.md` in `explore-<topic>`; author runs `/charter` |
| `/scope` | `phase-5-produce-handoff.md` (`/scope` binding) | Writes key `handoff/scope.md` in `explore-<topic>`; author runs `/scope` |
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
  and the exploration's keys stay readable to both: `explore-<topic>` is closed
  only after the inline child returns.

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

## Closing Rule

Every arm except the two parent arms ends with a plain close, once its last step
is done:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close explore-<topic> done
```

A close keeps the session and its keys readable. In the `/decision` and `/comp`
arms the close comes only after the inline child returns, because the child
reads the research keys while it runs. A run that stops before Phase 5 closes
nothing, so its keys stay for the resume.

The parent arms don't close. They write the handoff and then run the
`finish-handoff` subcommand of `explore-state.sh`, which removes every `work/`
and `research/` key and leaves the handoff and `session/branch`. The handoff is not
`/explore`'s to clean: it belongs to the parent's run. Each parent removes its
handoff key once consumed — `/scope` removes `handoff/scope.md` and `/charter`
removes `handoff/charter.md` — and closes `explore-<topic>` when it then holds
nothing else. A parent that bails at Phase 1 leaves the handoff in place so a
later invocation reaches it.

## Quality Checklist

Before completing:
- [ ] Crystallize decision read and the chosen outcome identified
- [ ] Correct sub-file read and instructions followed
- [ ] No file written under `docs/designs/` or `docs/competitive/`
- [ ] The arm's handover stated to the author, including any `--upstream` flag
- [ ] A parent arm ran `finish-handoff`; every other arm closed `explore-<topic>`
      (after the inline child returned, for `/decision` and `/comp`)

## Next Phase

None. Phase 5 is the final phase of `/explore`. If the session continues into
`/decision` or `/comp`, that skill's orchestrator takes over.
