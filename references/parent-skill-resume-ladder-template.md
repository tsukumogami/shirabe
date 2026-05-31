# Parent-Skill Resume-Ladder Template

The resume-ladder template every parent skill SHALL implement. Resume
ordering is split into two parts: a universal meta-ladder whose semantics
are pattern-level fixed, and parent-specific body slots each parent's
SKILL.md fills with its own chain-shape prompts.

The ladder is first-match-wins, top to bottom. A reader of any parent's
SKILL.md sees the same 9-row ladder shape; the differences are in the body
slots' specific prompt vocabulary, not the meta-flow.

The ladder consults the state file documented in
[`parent-skill-state-schema.md`](parent-skill-state-schema.md) and the
child-doc surfaces documented in
[`parent-skill-child-inspection.md`](parent-skill-child-inspection.md).

## Ladder Shape

The template's 9-row ordering:

```
1. state file malformed                           -> Error + offer Discard
2. state file has exit field set                  -> Offer revise-equivalent / start fresh
3. state file exists, last_updated < threshold    -> Resume at recorded phase_pointer
4. state file exists, last_updated >= threshold   -> Offer Resume / Force-materialize / Discard
5. [parent-specific status-aware re-entry slot]   -> parent-specific prompt vocabulary
6. [parent-specific partial-child-run slot]       -> resume into the partial child
7. [parent-specific feeder-doc-detected slot]     -> parent-specific Phase 1 entry behavior
8. On branch related to topic                     -> Resume at parent's Phase 1
9. On main or unrelated branch                    -> Start at parent's Phase 0
```

Rows 1-4 and 8-9 are the meta-ladder (pattern-level fixed). Rows 5-7 are
parent-specific body slots each parent fills.

## Meta-Ladder Entries

### Entry 1 — state file malformed

Triggers when the state file exists but cannot be parsed, is missing
required fields for the recorded `phase_pointer`, or carries an invalid
`exit:` value without the gating sub-shape field. The handler SHALL NOT
silently fall through to a lower row; malformation is a hard surface.

Behavior: surface a clear error naming the specific malformation and offer
**Discard** as the recovery path. Discard removes the state file and
allows the author to restart the chain at Phase 0. No silent fall-through
to Phase 0 is permitted.

### Entry 2 — state file has exit field set

Triggers when the state file exists, is well-formed, and has `exit:` set
to a valid pattern-level exit-path value (`full-run`, `re-evaluation`, or
`abandonment-forced`). The chain has already terminated; this re-entry is
either a re-evaluation of the existing terminal artifact or a fresh
chain.

Behavior: offer the parent-specific revise-equivalent flow for the
existing `exit:` value (e.g., re-evaluation of a `full-run` exit), or
offer to start a fresh chain (Discard + restart). The parent's SKILL.md
provides the specific prompt vocabulary for each `exit:` value.

### Entry 3 — state file fresh

Triggers when the state file exists, is well-formed, has `exit:` UNSET,
and `last_updated` is within the parent's stale-session threshold.

Behavior: resume at the recorded `phase_pointer`. No prompt; the
parent proceeds.

### Entry 4 — state file stale

Triggers when the state file exists, is well-formed, has `exit:` UNSET,
and `last_updated` is at or beyond the parent's stale-session threshold.

Behavior: offer **Resume / Force-materialize / Discard**. Resume continues
at `phase_pointer`; Force-materialize routes to the parent's
`abandonment-forced` exit path; Discard removes the state file and
restarts at Phase 0.

### Entry 8 — on-topic branch

Triggers when no state file exists and the current branch name is related
to the topic (parent-specific match criterion — typically the branch name
contains the topic slug or a workflow-naming convention links them).

Behavior: resume at the parent's Phase 1. The branch context provides
enough signal to skip Phase 0 setup; the parent uses its Phase 1
discovery prompts.

### Entry 9 — main or unrelated branch

Triggers when no state file exists and the current branch is not related
to the topic.

Behavior: start fresh at the parent's Phase 0 (initial setup, slug
validation, visibility detection, state-file creation).

## Parent-Specific Body Slots

Rows 5-7 are body slots each parent fills. The slots have pattern-level
positions and pattern-level semantics; the specific prompts each parent
chooses are parent-specific.

### Slot 5 — status-aware re-entry

Triggers when the resume ladder detects a child doc (or other durable
artifact a parent depends on) in a status that would trigger that child's
own status-aware re-entry prompt on direct invocation. The slot exists so
the parent decides upfront whether the re-entry is a parent-resume or a
fresh chain — the parent's flow MUST NOT be hijacked by the child's
status-aware re-entry prompt.

Slot-filling rules:

- The parent's SKILL.md names which child doc(s) trigger this slot and
  what statuses count as triggers.
- The parent's prompt offers prompt vocabulary appropriate to the
  parent's exit-path bindings (typically a Re-evaluate / Revise / Bail
  triad against an Accepted upstream artifact).
- The signaling mechanism between parent and child (how the parent tells
  the child to suppress its own status-aware re-entry) is named in the
  parent's SKILL.md.

Some parents' terminal artifacts have lifecycle states owned by
downstream skills (e.g., `/scope`'s PLAN doc has an Active state owned
by `/work-on` and a Done state owned by `/release`). The parent's Slot
5 entries for those states SHALL refuse re-entry and emit a redirect
prompt naming the downstream-owning skill. The redirect prompt SHALL
contain the literal substring `redirect to /<skill-name>` (case-
insensitive) and SHALL NOT contain the Re-evaluate / Revise / Bail
triad (refuse-and-redirect is not a re-evaluation exit; the
downstream skill owns the artifact). When the parent's chain has no
downstream-owning skill (e.g., `/charter`'s STRATEGY is Accepted-
terminal), the parent's Slot 5 entries for the corresponding
lifecycle states are vacuous — the slot template accommodates both
cases without changing the 9-row meta-ladder count.

### Slot 6 — partial-child-run

Triggers when the resume ladder detects a child's own wip/ artifact (or
substrate-equivalent partial-state marker) indicating that an earlier
child invocation started but did not reach its durable terminal artifact.

Slot-filling rules:

- The parent's SKILL.md enumerates which children expose partial-run
  signals and which substrate path (or surface) each partial signal
  lives at.
- The slot's behavior is to resume into the partial child (re-invoke the
  child against its own resume ladder), rather than re-running the
  child from scratch.

### Slot 7 — feeder-doc-detected

Triggers when the resume ladder detects a related artifact that is not a
strict chain member but informs Phase 1 entry behavior (a "feeder doc"
in the conditional-feeder sense — see
[`parent-skill-pattern.md`](parent-skill-pattern.md) for the Conditional
Feeder Invocation Shape).

Slot-filling rules:

- The parent's SKILL.md names which feeder docs are recognized and how
  detection works.
- The slot's behavior is parent-specific Phase 1 entry behavior: the
  feeder doc informs Phase 1's discovery prompts (or pre-populates a
  chain-proposal) rather than triggering its own re-entry.

## Malformed State File Handling

Entry 1 in the meta-ladder makes malformed-state-file handling a hard
surface, not a silent fall-through. Three requirements bind every
parent's implementation:

1. **Surface the malformation.** The parent SHALL emit a clear error
   message naming the specific malformation (e.g., "missing required
   field `phase_pointer`", "unparseable YAML at line 14", "`exit:
   re-evaluation` without `decision_record_sub_shape:`").
2. **Offer Discard as recovery.** The author is offered the Discard
   option — remove the state file and restart the chain at Phase 0. No
   automatic discard; the author confirms.
3. **No silent fall-through.** The ladder MUST NOT fall through to a
   lower row when the state file is malformed. Entry 1 is terminal —
   either the author chooses Discard (state file removed; chain restarts
   at Phase 0) or the parent exits.

The hard-surface behavior catches state drift and substrate bugs at
re-entry time rather than letting them silently corrupt later phases.

## Stale-Session Threshold

The stale-session threshold (the boundary between Entry 3 and Entry 4) is
a parametric pattern-level concept whose numeric value each parent sets.
The pattern names the slot; the parent picks the number.

Parent-level guidance for picking the threshold:

- The threshold trades off between "broke for lunch" (the parent
  silently resumes — Entry 3) and "abandoned for a week" (the parent
  prompts the author to choose — Entry 4).
- Parents whose chains complete in tens of minutes typically pick a
  short threshold (hours).
- Parents whose chains span work-days or longer pick a longer threshold
  (days).

The threshold is recorded in the parent's SKILL.md and is consumed by
the resume ladder's `last_updated` comparison. Changes to the threshold
ship with the parent (a SKILL.md edit), not with the substrate.
