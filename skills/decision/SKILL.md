---
name: decision
description: >-
  Settle one contested choice on the record: name the alternatives that are
  really live, put the evidence for each next to it, and land a call with the
  reasoning attached. Use it when three or more options are viable, when the
  evidence points both ways, or when the choice is expensive to undo —
  "Postgres or DynamoDB for this?", "should we roll our own or use library
  X?", "is it worth migrating off Y?", "the team can't agree on A versus B",
  "we tried this before and it didn't work, what now?". The one most often
  missed is "what do you think we should use for the queue?": phrased as an
  opinion, so the agent just answers, and months later nobody can reconstruct
  why. There is a floor — a cheaply reversible choice with an obvious answer
  does not need this. Do NOT use it for a document's worth of connected
  choices (`/design`), for options nobody has named yet (`/explore`), or for
  surveying a field of vendors before choosing among them (`/comp`).
argument-hint: '<decision question or topic>'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh decision 2>&1 || true`

@.claude/shirabe-extensions/decision.md
@.claude/shirabe-extensions/decision.local.md

# Decision Skill

Make well-reasoned, auditable decisions through structured evaluation. The skill
produces decision reports that map directly to design doc Considered Options
sections and standalone Decision Records (ADRs).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Decision Tiers

This skill handles Tier 3 (standard) and Tier 4 (critical) decisions. For Tier 1-2,
use the lightweight decision protocol (`references/decision-protocol.md`).

| Tier | Path | Phases | When |
|------|------|--------|------|
| 3 (standard) | Fast | 0, 1, 2, 6 | 3+ options, needs research, but not adversarial |
| 4 (critical) | Full | 0, 1, 2, 3, 4, 5, 6 | Irreversible, high-stakes, contested |

## Agent Hierarchy

When invoked as a sub-operation by a parent skill (e.g., /design), the decision
skill runs as a **decider agent**. The decider spawns sub-agents:

```
Level 1: Parent skill (design, explore)
  └── Level 2: Decider agent (this skill, one per decision question)
        ├── Level 3: Research agent (Phase 1, disposable)
        ├── Level 3: Alternative agents (Phase 2, disposable)
        └── Level 3: Validator agents (Phases 3-5, persistent via SendMessage)
              ├── Phase 3: argue FOR their alternative (bakeoff)
              ├── Phase 4: receive peer findings, revise position
              └── Phase 5: cross-examine peers, reach final position
```

**Validator persistence is critical.** Validators are spawned in Phase 3 and
re-messaged via `SendMessage` in Phases 4-5. They retain their full conversation
history to revise and defend their positions. Research and alternative agents are
disposable (single task, then done).

## Session and Keys

`/decision` keeps every intermediate and its report as keys in a koto session,
following `${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`. It
writes no file to the staging folder. Three names locate its state, and every
phase file uses them:

| Name | Run by a parent skill (`/design`) | Run directly |
|------|-----------------------------------|--------------|
| `<session>` | the parent's session, from `decision_context.session` (`design-<topic>`) | `decision-<topic>` |
| `<key_dir>` | `decision_context.key_dir` (`work/decision-<N>`) | `work` |
| `<report_key>` | `decision_context.report_key` (`work/decision_<N>_report.md`) | `work/report.md` |

The keys are `<key_dir>/context.md`, `<key_dir>/research.md`,
`<key_dir>/alternatives.md`, `<key_dir>/bakeoff_<k>.md` (one per validator)
and `<key_dir>/examination.md`, then `<report_key>`.

**Run by a parent skill.** The parent's session is already open, and the
parent owns it: `/decision` opens, adopts and closes nothing, and writes only
under the `key_dir` and `report_key` it was given.

**Run directly.** Phase 0 derives `<topic>` from the question (lowercase,
whitespace and underscores to `-`, every character outside `[a-z0-9-]`
dropped, at most 60 characters, never starting or ending with `-`; ask for one
when nothing is left), then opens the session and records that no parent
dispatched it:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open decision <topic>
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" adopt decision <topic>
```

Any non-zero exit from either command stops the run with the script's message:
127 or 69 means koto is missing or too old, and the skill never falls back to
files. At the end of Phase 6 a direct run closes its session:
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close decision-<topic> done`
(`abandoned` when the user abandons the decision). Under a parent `/decision`
never closes a session.

Keys are read and written with koto: `koto context exists <session> <key>`
tests one (exit 0 present, 1 absent), `koto context get <session> <key>` prints
it, `koto context add <session> <key>` stores the content given on stdin,
`koto context list <session> --prefix <key_dir>/` lists them, and `koto
context remove <session> <key>` removes one. The decider writes keys itself;
the research and validator agents it spawns never do. Each writes one file in a
`skill-session.sh scratch` directory, which the decider ingests with
`skill-session.sh ingest <session> <key_dir> <dir>`; a validator revising its
report edits a copy materialized with `skill-session.sh get` and the decider
writes it back with `skill-session.sh put`.

## Sub-Operation Interface

When invoked by a parent skill, the decider receives a decision context:

```yaml
decision_context:
  question: "Which cache invalidation strategy?"
  session: "design-foo"
  key_dir: "work/decision-1"
  report_key: "work/decision_1_report.md"
  options:
    - name: "TTL-based"
      description: "..."
  constraints:
    - "Must support < 100ms latency"
  background: |
    The system currently uses...
  complexity: "standard"  # standard | critical
```

And produces:

```yaml
decision_result:
  status: "COMPLETE"
  chosen: "TTL-based"
  confidence: "high"
  rationale: "..."
  assumptions:
    - "Redis cluster remains available"
  rejected:
    - name: "Event-driven"
      reason: "Adds infrastructure dependency for marginal gain"
  report_key: "work/decision_1_report.md"
```

See `references/decision-report-format.md` for the canonical output format
with consumer rendering sections.

## Input Detection

From `$ARGUMENTS`:
1. **Empty** -- ask what needs to be decided (or infer from context in --auto)
2. **Decision question** -- use as the topic, proceed to Phase 0

Check for `--auto` flag. In --auto mode, the skill never blocks on user input.
Follow `references/decision-protocol.md` for assumption handling.

## Workflow Phases

```
Phase 0: CONTEXT --> Phase 1: RESEARCH --> Phase 2: ALTERNATIVES --> Phase 3: BAKEOFF --> Phase 4: REVISION --> Phase 5: EXAMINATION --> Phase 6: SYNTHESIS
                                                    (fast path skips 3-5) ──────────────────────────────────────────────────────────────┘
```

| Phase | Purpose | Agents | Artifact |
|-------|---------|--------|----------|
| 0 | Context and framing | None | key `<key_dir>/context.md` |
| 1 | Research critical unknowns | 1 research agent (disposable) | key `<key_dir>/research.md` |
| 2 | Identify and present alternatives | N alternative agents (disposable) | key `<key_dir>/alternatives.md` |
| 3 | Validation bakeoff | N validator agents (persistent) | keys `<key_dir>/bakeoff_<k>.md` |
| 4 | Informed peer revision | Same validators (SendMessage) | Updated bakeoff keys |
| 5 | Cross-examination | Same validators (SendMessage) | key `<key_dir>/examination.md` |
| 6 | Synthesis and report | None (decider synthesizes) | key `<report_key>` |

**Fast path (Tier 3):** skip Phases 3-5. No validators spawned. The decider
goes from alternatives presentation directly to synthesis.

## Resume Logic

```
if key <report_key> exists                    -> Decision complete
if key <key_dir>/examination.md exists        -> Resume at Phase 6
if keys <key_dir>/bakeoff_* exist             -> Resume at Phase 4
if key <key_dir>/alternatives.md exists       -> Resume at Phase 3 (or Phase 6 for fast path)
if key <key_dir>/research.md exists           -> Resume at Phase 2
if key <key_dir>/context.md exists            -> Resume at Phase 1
else                                          -> Start at Phase 0
```

## Phase Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Context and Framing**: `references/phases/phase-0-context.md`
1. **Research**: `references/phases/phase-1-research.md`
2. **Alternative Presentation**: `references/phases/phase-2-alternatives.md`
3. **Validation Bakeoff**: `references/phases/phase-3-bakeoff.md`
4. **Peer Revision**: `references/phases/phase-4-revision.md`
5. **Cross-Examination**: `references/phases/phase-5-examination.md`
6. **Synthesis and Report**: `references/phases/phase-6-synthesis.md`

Every key row is tested in `<session>` (`koto context exists <session>
<key>`; the bakeoff row with `koto context list <session> --prefix
<key_dir>/bakeoff_`). A direct run reads the rows after Phase 0's open, so an
interrupted run's live session is attached and read; a finished one was
replaced and starts at Phase 0.

## Cleanup

After Phase 6 writes the report, remove the intermediate keys, since a parent
reads only the report and a restarted decision (`/design`'s Phase 3) must
start fresh:
- `<key_dir>/context.md`
- `<key_dir>/research.md`
- `<key_dir>/alternatives.md`
- `<key_dir>/bakeoff_<k>.md`, each one
- `<key_dir>/examination.md`

Only `<report_key>` persists. Nothing is deleted from the staging folder:
`/decision` writes nothing there.

## Validator Agent Contract

Validators are persistent agents. The contract between phases:

**Phase 3 (spawn):**
- Input: alternative description, decision question, constraints, background
- Output: validation report (strengths, weaknesses, risks, recommendation)

**Phase 4 (SendMessage):**
- Input: summaries from all OTHER validators
- Output: revised report (may change recommendation, add caveats)

**Phase 5 (SendMessage):**
- Input: specific challenges from competing validators
- Output: final position (defend, concede, or qualify)

If a validator times out or errors during Phase 4-5, the decider uses the
validator's last known position rather than re-spawning.

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-0-context.md` | Phase 0 |
| `references/phases/phase-1-research.md` | Phase 1 |
| `references/phases/phase-2-alternatives.md` | Phase 2 |
| `references/phases/phase-3-bakeoff.md` | Phase 3 (full path only) |
| `references/phases/phase-4-revision.md` | Phase 4 (full path only) |
| `references/phases/phase-5-examination.md` | Phase 5 (full path only) |
| `references/phases/phase-6-synthesis.md` | Phase 6 |
| `references/decision-report-format.md` | Phase 6 (output format) |
| `references/decision-block-format.md` | Phase 6 (block delimiters) |
