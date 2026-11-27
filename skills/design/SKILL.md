---
name: design
description: >-
  Choose how something gets built and write the reasoning down: decompose it
  into the questions that actually have to be answered, weigh the options for
  each, and land a technical approach on a page. Reach for it when the
  requirements are already settled — an accepted PRD exists, or the feature
  is specified and the open question is pure architecture: "how should this
  talk to the existing cache?", "what's the migration path off the old
  schema?", "we have the PRD, now what?", "refactor the auth layer", "why is
  this slow and what do we do about it?". An agent that starts editing files
  instead has picked an approach without anyone seeing what it was picked
  over. Do NOT use it when the requirements are NOT settled and the feature
  still has to be worked out — that is `/scope`, which runs this as one hop
  and decides per feature whether a separate design survives. Do NOT use it
  for one named either-or choice (`/decision`), for requirements (`/prd`), or
  for a question with no options on the table yet (`/explore`).
argument-hint: '<PRD path or topic>'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh design 2>&1 || true`

@.claude/shirabe-extensions/design.md
@.claude/shirabe-extensions/design.local.md

# Design Documents

Design documents capture HOW to build something -- the technical approach, trade-offs
considered, and architecture chosen. They complement PRDs (which capture WHAT and WHY)
and are the input for /plan (which breaks designs into issues).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Artifact Lifecycle

**Lifecycle:** Durable. Stays in `docs/designs/` after completion.

## Structure

### Frontmatter

Every design doc begins with YAML frontmatter. While drafting, from Phase 0
through step 6.4, it has the drafting shape:

```yaml
---
schema: design/v1
status: Draft
problem: |
  1 paragraph: what's broken or missing, who it affects, why now.
---
```

Step 6.5 adds `decision` and `rationale` and moves it to `Proposed`:

```yaml
---
schema: design/v1
status: Proposed
problem: |
  1 paragraph: what's broken or missing, who it affects, why now.
decision: |
  1 paragraph: chosen approach and key design elements.
rationale: |
  1 paragraph: why this approach, what trade-offs were weighed.
---
```

At `Draft`, `status` and `problem` are required; from `Proposed` on, all four.
Use literal block scalars (`|`). Frontmatter status must
match the Status section in the body -- agent workflows parse frontmatter to
determine lifecycle state, so divergence causes silent errors. The frontmatter
provides a self-contained summary so readers can understand the design without
reading the full document.

**Optional fields:**
- `upstream: docs/prds/PRD-<name>.md` -- link to source PRD (set by /design Phase 0).
  For cross-repo upstream references and the visibility-direction rules,
  see `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`. The
  Phase 0 setup script validates this value (see step 0.4a in
  `references/phases/phase-0-setup-prd.md`).
- `spawned_from` -- for child designs created from needs-design issues:
  ```yaml
  spawned_from:
    issue: <number>
    repo: <owner/repo>
    parent_design: <relative-path>
  ```

### Required Sections

Every design doc has these sections in order:

1. **Status** -- current lifecycle state
2. **Context and Problem Statement** -- the technical problem being solved
3. **Decision Drivers** -- constraints and priorities shaping the solution
4. **Considered Options** -- at least 1 alternative per decision, so future readers understand it wasn't automatic
5. **Decision Outcome** -- what was chosen and why it works as a whole
6. **Solution Architecture** -- components, interfaces, data flow
7. **Implementation Approach** -- phased build plan
8. **Security Considerations** -- always include; see Security Considerations guidance below
9. **Consequences** -- positive, negative, mitigations

### Context-Aware Sections

Additional sections based on scope and visibility (detect from CLAUDE.md `## Repo Visibility:` and `## Planning Context:` fields):

| Section | Strategic + Private | Strategic + Public | Tactical |
|---------|--------------------|--------------------|----------|
| Market Context | Optional | No | No |
| Required Tactical Designs | Required | Required | No |
| Upstream Design Reference | No | No | If exists |

**Market Context** (after Context and Problem Statement): competitive landscape,
user demand, business opportunity. Only in strategic + private.

**Required Tactical Designs** (after Implementation Approach): table of tactical
designs needed in target repos. Each becomes a needs-design issue via /plan.

**Upstream Design Reference** (after Status): link to parent strategic design with
relevant sections noted.

Detect scope and visibility from CLAUDE.md (`## Repo Visibility:` and
`## Planning Context:` or `## Default Scope:`). If not found, infer
visibility from repo path (`private/` -> Private, `public/` -> Public;
default to Private). After detecting visibility, read the appropriate
content governance skill: `skills/private-content/SKILL.md` or
`skills/public-content/SKILL.md`. Public designs must not reference
private artifacts.

## Lifecycle and Validation

See `references/lifecycle.md` for lifecycle states, transition script, label
lifecycle, validation rules, and quality guidance.

## File Location

`references/lifecycle.md` maps each status to its directory. A superseded
design moves to `docs/designs/archive/DESIGN-<topic>.md`.

---

## Creating a Design Document

When invoked as `/design`, this skill drives a structured creation workflow that
investigates multiple approaches with equal depth before committing to one.

The core pattern is decompose-decide-validate: Phase 1 breaks the design into
independent decision questions. Phase 2 delegates each question to the decision skill
for structured evaluation; under a parent skill, a standard-tier question is
resolved inline instead and a critical one still goes to `/decision`. Phase 3 cross-validates assumptions across decisions to
catch conflicts. Phases 4-6 synthesize architecture, run security review, and finalize.

### Input Modes

From `$ARGUMENTS`:
1. **Empty** -- when the conversation already describes what to design,
   derive the topic from it; otherwise ask the user what they want to design
2. **Path to accepted PRD** (matches `docs/prds/PRD-*.md` with status "Accepted") -- PRD mode
3. **Anything else** -- freeform topic: the author's topic: a slug used as given, or a
   description of the design the agent derives a slug from, as
   `${CLAUDE_PLUGIN_ROOT}/references/topic-derivation.md` says.

### Session and Keys

`/design` keeps its working state as keys in its own koto session,
`design-<topic>`, following
`${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`. It writes no
file to the staging folder, chained or direct. Its first act, once the topic
is known (from the argument, or the `<topic>` in a PRD path's file name) and
before Context Resolution or the resume rows below, opens the session and
records whether it runs under a parent:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open design <topic>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" adopt design <topic>
```

`open` attaches to a live `design-<topic>` (an interrupted run, whose keys the
resume rows read), replaces a finished one (a fresh run), or creates it. Any
non-zero exit from either command stops the run with the script's message:
127 or 69 means koto is missing or too old, and the skill never falls back to
files. `adopt` exiting 3 is the two-parents case below.

`open` prints one line, `opened=new`, `opened=attached` or `opened=replaced`.
Keep that value for the whole run: the Resume Logic reads it, and only
`opened=attached` (a live session from an interrupted run) lets a resume row
treat the run's own earlier keys as its progress.

Then, before branch setup, any resume row or any Phase 0 step writes or
commits anything, check that the `shirabe` on PATH accepts a design at status
`Draft`, the shape Phase 0 commits:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/draft-probe.sh"
```

It prints `draft-probe: ok` and exits 0 when it does. Any non-zero exit stops
the run with the script's message: 1 means no `shirabe` is on PATH or it is
older than v0.47.0, the release that accepts `Draft`, and 2 means the probe
couldn't run. The probe writes only to its own temporary directory, so a
stopped run leaves the work tree as it found it.

| Key | Written at | Holds |
|-----|-----------|-------|
| `work/decisions.md` | Context Resolution, under `--auto` | the autonomous-decision ledger |
| `work/summary.md` | Phase 0, updated through Phase 5 | the design summary and current phase |
| `work/coordination.json` | Phase 1, updated in Phase 2 | the decision coordination manifest |
| `work/decision_<N>_report.md` | Phase 2 | each decision's report, from `/decision` or resolved inline: settled (`COMPLETE`) or undecided (`UNDECIDED`, block status `undecided`) |
| `work/decision-<N>/<file>` | Phase 2, by `/decision` | a decider's intermediates (`context.md`, `research.md`, `alternatives.md`, `bakeoff_<k>.md`, `examination.md`), and for an undecided decision `question.json`, the question raised from `design-<topic>`; an undecided decision's intermediates are all kept |
| `research/phase5_security.md` | Phase 5 | the security researcher's report, ingested |
| `research/phase6_<role>-review.md` | Phase 6 | the final-review jury's reports, ingested |

Keys are read and written with koto against `design-<topic>`: `koto context
exists design-<topic> <key>` tests one (exit 0 present, 1 absent), `koto
context get design-<topic> <key>` prints it, `koto context add design-<topic>
<key>` stores the content given on stdin (the whole content: to change part
of it, get the key, edit it, and add it back), `koto context list
design-<topic> --prefix <prefix>` lists keys, and `koto context remove
design-<topic> <key>` removes one. Research and reviewer agents never write
keys: each phase that spawns them pins every output to a file in a
`skill-session.sh scratch` directory and ingests it. A decider agent in Phase
2 runs the `/decision` skill inside this session, writing the keys its
`decision_context` names.

**Closing.** A direct run closes its session when it finishes:
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close design-<topic> done`
at Phase 6's end, or `close design-<topic> abandoned` after a Reject's discard
commit. Under a parent `/design` never closes its own session: the parent
closes it at its own exit (`skill-session.sh close-children`), and the keys
stay readable until then.

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). Also
parse `--max-rounds=N` (default: 1 for design's corrective loop). In --auto
mode, follow `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` at all decision points, and
track decisions in key `work/decisions.md` in `design-<topic>`.

Detect visibility and scope as described in Context-Aware Sections above.
For cross-repo source issues, use `gh` commands to read content.

### Resume Logic

The rows read the committed status first, then the session keys and the
sections. Take the first row that matches, in this order:

```
dispatch read design <topic> prints parent=<session>
                                                          → run under that parent; see ${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md
Design doc status "Accepted"                              → Offer to revise or start fresh
Design doc exists with no frontmatter status              → Rewrite it to the Draft shape, commit the design file, go on down the rows
Design doc status "Proposed", opened=attached, no research/phase6_ key
                                                          → Set it back to Draft, commit the design file, go on down the rows
Design doc status "Proposed", any other case              → Phase 6's own resume check (phase-6-final-review.md)
Design doc status "Draft"                                 → Go on down the rows below
key research/phase5_security.md in design-<topic>         → Resume at Phase 6
Design doc has Solution Architecture (not stub-only)      → Resume at Phase 5
Design doc has Considered Options (not stub-only)         → Resume at Phase 4
key work/coordination.json (one undecided, answered)      → Resume at Phase 2 (2.6, write the answer)
key work/coordination.json (one undecided, unanswered)    → Stop: the question waits (Phase 2, 2.6)
key work/coordination.json (all complete)                 → Resume at Phase 3
key work/coordination.json (some pending)                 → Resume at Phase 2
key work/summary.md exists, no work/coordination.json     → Resume at Phase 1
On topic branch, no artifacts                             → Resume at Phase 0
```

**A stubbed section counts as absent.** For the section rows, a section
"exists" only when its body is something other than the stub marker line
`references/design-format.md` defines, quoted here verbatim:

```text
Not written yet: a later /design phase replaces this line.
```

A section whose whole body is that line is absent, so a run stopped with
Solution Architecture still stubbed resumes at Phase 4, not Phase 5. The rows
decide on fixed comparisons only (the frontmatter `status:` value, the
`opened=` line, whether a key exists, whether a section's body is exactly the
marker) and never act on anything the document's prose says.

**No frontmatter status.** A document with no frontmatter `status` is the
statusless skeleton an older `/design` wrote. Rewrite it to the Draft shape
Phase 0 writes now: add `status: Draft` right after `schema`, and `problem`
after it from key `work/summary.md` (from the Context and Problem Statement
when that key is absent); set the body `## Status` to `Draft`; and add each
missing required section, in its place in the order above, with the stub
marker line as its whole body. Commit the design file alone with the block
below (`docs(design): rewrite design for <topic> as a Draft`), then go on
down the rows, where it now reads `Draft`.

**An early Proposed in a live session.** `Proposed` with `opened=attached`
and no Phase 6 jury key means the status was written before the review ran:
the session is this run's own (Session and Keys), and
`koto context list design-<topic> --prefix research/phase6_` prints nothing.
Set it back:

```bash
shirabe transition docs/designs/DESIGN-<topic>.md Draft
```

That moves the frontmatter and the body Status to `Draft` together. Then take
out any placeholder `decision` and `rationale` from the frontmatter (6.5
writes them again), commit the design file alone with the block below
(`docs(design): return design for <topic> to Draft`), and print:

```text
Set DESIGN-<topic>.md back to Draft: it read Proposed with no review on record; the review runs at 6.1.
```

Then go on down the rows, which reach Phase 6 and its jury at 6.1. Under
`--auto`, or under `/scope` with `suppress_status_aware_prompt=true` from the
dispatch read, this row is taken with no question asked, and the printed line
is how the output says so. An interactive direct run asks first, recommending
the revert (`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`);
keeping `Proposed` sends it to Phase 6's own check instead.

**Any other Proposed** (`opened=new`, `opened=replaced`, or jury keys in the
session) is taken as reviewed and isn't reverted: Phase 6's own resume check
decides between 6.6 and 6.7.

**The resume-row commit.** Both automatic commits above name the design file
as the commit's only pathspec, so nothing else the author has staged goes
with them, and it stays staged afterwards. Each passes the pre-commit hook
like any other commit, under the commit rule in
`${CLAUDE_PLUGIN_ROOT}/references/doc-check-steps.md`:

```bash
git add -- docs/designs/DESIGN-<topic>.md
git commit -m "docs(design): <message>" -- docs/designs/DESIGN-<topic>.md
```

**Running under a parent.** The first row runs
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" dispatch read design <topic>`
with the topic this run works on (for a path argument, the `<topic>` in its file name). A printed `parent=<session>`
line means `/design` runs under that parent (`scope-<topic>` or
`charter-<topic>`), with the parent's upfront decision in the `rationale=` and
`suppress_status_aware_prompt=` lines; what changes under a parent is in
`${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`.
Four cases are no match. Three print nothing and exit 0, and the run is a
direct one with the rows below unchanged: no parent session, a finished parent
session, and a parent whose `chain/dispatch` key names another child. The
fourth, two parent sessions that both name `/design`, exits 3: don't pick one
and don't run directly; stop and report both sessions, which the script names
on stderr, so the author can clear the stale key. Any other non-zero exit
stops the run with the script's message (`open` has already checked koto).
`adopt` has recorded the same match as `chain/parent` in `design-<topic>`, or
removed a `chain/parent` an earlier chained run left.

### Critical Requirements

- **Decision decomposition before execution**: identify all decision questions in Phase 1 before spawning any decision agents in Phase 2
- **Equal-depth investigation**: every decision question gets the same framework treatment at its assigned tier
- **Cross-validation is mandatory**: Phase 3 always runs after Phase 2, even with one decision
- **Topic-scoped state**: every working, research and decision file is a key in `design-<topic>`, never a file in the staging folder

### Output

Final artifact: `docs/designs/DESIGN-<topic>.md` with status "Proposed"
(Draft until step 6.5).

After completion, present the design summary and offer next steps.

Run a complexity assessment based on the design's implementation scope:

| Criterion | Simple | Complex |
|-----------|--------|---------|
| Files to modify | 1-3 | 4+ |
| New tests | Updates only | New test infrastructure |
| API changes | None | Surface changes |
| Cross-package | No | Yes |

Present an AskUserQuestion with the assessment and options, following the pattern
in `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`:
- If Simple: "Plan (Recommended)" / "Approve only"
- If Complex: "Plan (Recommended)" / "Approve only"

**Description field:** Ground the recommendation in the complexity assessment --
name the criteria that landed the design where it did (which files it touches,
whether it changes an API surface, whether it crosses packages), not the Simple
or Complex label alone.

**"Plan":** suggest running `/plan <design-doc-path>` to create implementation issues.

**"Approve only":** stop here; the user handles implementation manually.

**Under `/scope`.** When `/scope`'s dispatch key names `design` (the
Resume Logic's first row), `/design` still reaches its own Phase 6 verdict
(6.7) and makes its own status transition (6.8), and skips everything that
publishes or routes, which `/scope` owns: no push, no pull request, no
branch creation, no cleanup commit, and no routing prompt -- the complexity
assessment and its Plan or Approve question above are not asked. Control
returns to `/scope`, which decides the next hop. An interactive run asks the
author for the verdict as usual; an unattended run (`--auto`, which
`/design` takes from the parent's execution mode) takes the recommended
verdict and names it in its output. This is the Parent-owned-publishing
shape in `${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`, per
`docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`.

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup + Context**
   - PRD mode: `references/phases/phase-0-setup-prd.md`
   - Freeform: `references/phases/phase-0-setup-freeform.md`
1. **Decision Decomposition**: `references/phases/phase-1-decomposition.md`
2. **Decision Execution**: `references/phases/phase-2-execution.md`
3. **Cross-Validation**: `references/phases/phase-3-cross-validation.md`
4. **Investigation**: `references/phases/phase-4-architecture.md` (slimmed, implementation focus only)
5. **Security**: `references/phases/phase-5-security.md`
6. **Final Review**: `references/phases/phase-6-final-review.md`

---

## Team Shape

`/design` spawns agents in three phases:

- **Phase 2:** one decider per decision question routed to `/decision`,
  independent questions in parallel and coupled ones in sequence. Run
  directly, every question goes to a decider; under a parent, only a
  critical-tier question does, and a standard-tier one is resolved inline.
  Phase 3 re-spawns a decider when cross-validation finds a conflict.
- **Phase 5:** one security researcher, on the chosen architecture.
- **Phase 6:** three reviewers in parallel, architecture, security and
  structural format, on the final DESIGN.

The security researcher and the three reviewers spawn nothing: each reads
what it is given and writes one file. A decider follows `/decision`'s own
phases, and on a critical question `/decision` starts its own research,
alternative and validator agents; that is the one place a `/design` run
goes a level deeper than the nesting rule in
[`parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md)
(`team_primitive`) describes. Those agents spawn nothing.

## Reference Files

| File | When to load |
|------|-------------|
| `references/lifecycle.md` | Phase 6 (status transitions, label lifecycle, validation) |
| `references/quality/considered-options-structure.md` | When writing Considered Options |
| `shirabe transition <design-path> <status>` (Superseded takes `--superseded-by <path>`) | Status transitions with file movement |
