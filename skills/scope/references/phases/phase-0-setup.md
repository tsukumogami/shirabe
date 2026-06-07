# Phase 0 — Setup

Phase 0 binds three contracts: topic-slug validation against the
pattern's regex, visibility detection from `CLAUDE.md`, and the
unconditional self-heal of any stale `parent_orchestration:`
block found at session start. Phase 0 ends with the initial
state-file written and the phase pointer advanced to Phase 1.

## Cold-Start Path

When `$ARGUMENTS` is empty, Phase 0 surfaces a cold-start prompt
naming the three trigger phrases ("start a tactical conversation
about X", "open a feature scope for Y", "I want to think through
the feature shape of Z") and asks the author to re-invoke
`/scope <topic-slug>` with a slug that matches the topic-slug
regex. Phase 0 then stops; there is no auto-derivation of a slug
from prior context and no looping retry.

## Topic-Slug Validation

The topic-slug regex `^[a-z0-9-]+$` is cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
(Topic-Slug Regex section). Phase 0 validates `$ARGUMENTS` AS
PROVIDED against the regex — byte-for-byte, with no normalization
step before validation. Slugs that fail the regex are hard-
rejected with a clear error naming the violated pattern; `/scope`
MUST NOT proceed silently when the slug is invalid and MUST NOT
silently normalize the input into a conforming slug.

Concrete rejection examples (the wording shape every rejection
SHALL use):

- Uppercase letters — input `Foo` → `Topic slug `Foo` does not
  match the required pattern `^[a-z0-9-]+$`.`
- Underscores — input `foo_bar` → `Topic slug `foo_bar` does not
  match the required pattern `^[a-z0-9-]+$`.`
- Dots — input `foo.bar` → `Topic slug `foo.bar` does not match
  the required pattern `^[a-z0-9-]+$`.`
- Slashes (path-as-topic) — input `docs/prds/PRD-foo.md` →
  `Topic slug `docs/prds/PRD-foo.md` does not match the required
  pattern `^[a-z0-9-]+$`.` Path-as-upstream is not the right
  shape for `/scope`'s entry mode; upstream artifact references
  are detected during Phase 1 discovery, not parsed from
  `$ARGUMENTS`.

## Slug-Prefix Convention Check (CLI invocation)

After the topic-slug regex validation passes, Phase 0 invokes the
shirabe-validate slug-prefix detection CLI to surface a
recommendation when the candidate slug does not conform to the
workspace's prevailing prefix convention:

```bash
shirabe slug-prefix-detect <slug> --docs-root docs
```

The CLI samples `docs/{briefs,prds,designs,plans}/` filenames,
extracts the most common first hyphen-delimited word after the
artifact-type prefix, and emits one of three outcomes:

- `no-prevailing-prefix: ...` — the docs corpus did not produce a
  >50% prefix majority. Phase 0 proceeds without a recommendation.
- `matches: ...` — the candidate slug already starts with the
  detected prefix. Phase 0 proceeds.
- `mismatch: ...` — a prevailing prefix was detected and the
  candidate slug does NOT start with it. Phase 0 surfaces the CLI
  output verbatim as an informational prompt, recommending the
  prefix-prepended form, then continues. The recommendation does
  not block the run -- the author may proceed with the original
  slug.

The deterministic sampling logic lives in the CLI per the
lazy-load principle. Phase 0 does NOT duplicate the
docs-directory walk or the >50% threshold in SKILL prose.

## Visibility Detection

Phase 0 reads `CLAUDE.md` for the `## Repo Visibility:` header.
Accepted values: `Public` or `Private`. The detected value is
recorded in the state file and consumed by Phase 2's validator
pass-through
(`shirabe validate --format json --visibility=<value>`). When the
header is absent, `/scope` defaults to `Private` and surfaces a
warning containing the literal phrasing "Default to Private if
unknown" naming the missing header. The warning is informational;
the run proceeds against the Private default.

## Slug Re-Validation on Resume

Slugs RECOVERED from on-disk artifact paths during resume —
specifically, Slot 5 file-glob matches against
`docs/{briefs,prds,designs/current,designs,plans}/<TYPE>-<topic>.md`
and Slot 6 matches against `wip/{brief,prd,design,plan}_<topic>_*`
— SHALL be re-validated against `^[a-z0-9-]+$` BEFORE entering
interpolation into any emitted shell command or state-file write
path. An unparseable slug rejects the resume entry, surfaces a
diagnostic naming the offending path, and routes to R8 bail-
handling. The resume MUST NOT silently proceed with an unvalidated
slug.

The re-validation closes the path-traversal surface that would
otherwise open if an attacker placed a maliciously-named artifact
under `docs/` to be discovered by Slot 5's ladder match.

## Stale `parent_orchestration:` Self-Heal

The `parent_orchestration:` block is ephemeral within a chain
instance: `/scope` writes it immediately before invoking a child
and clears it immediately after the child returns. The block's
presence at session start (when a fresh `/scope` invocation
opens against a topic with an existing state file) is by
definition stale — the chain that wrote the block is no longer
in flight.

Phase 0 SHALL unconditionally clear any `parent_orchestration:`
block found at session start. The self-heal MUST NOT prompt the
author for confirmation; it MUST NOT surface a warning; it MUST
NOT treat the block as authoritative on the resume. The clear
is the contract.

The unconditional shape rules out any conditional behavior — no
"if author confirms", no "if last_updated is recent", no
prompt-on-clear. The block is removed from the state file
silently, the rest of the state file is left untouched, and the
resume ladder proceeds against the cleaned state.

## Initial State-File Shape

After validation passes and the self-heal completes, Phase 0
writes (or updates) the state file at `wip/scope_<topic>_state.md`
with the initial shape:

```yaml
topic: <slug>
chain_started: <ISO-8601 timestamp>
last_updated: <ISO-8601 timestamp>
phase_pointer: phase-0
exit: UNSET
exit_artifacts: []
planned_chain: []
```

The 5-field minimum (`topic`, `last_updated`, `phase_pointer`,
`exit`, `exit_artifacts`) is filled with their initial values;
the `/scope`-specific extensions (`chain_started`,
`planned_chain`) are also written. Other `/scope`-specific
fields are absent at Phase 0 per invariant I-5; they appear only
when their triggering condition fires later in the chain.

Phase 0 advances the `phase_pointer:` to `phase-1` immediately
before returning control to Phase 1, so a resume against the
written state enters at Phase 1's discovery prompts.

## Worktree-Discipline Trigger Is Not in Phase 0

The worktree-discipline three-phase flow (Rebase phase → Impact-
analysis phase → Escalation phase) defined in
`${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`
fires BEFORE EACH Phase 2 child invocation. It does NOT fire in
Phase 0. Phase 0's contracts are bounded to slug validation,
visibility detection, self-heal, and the initial state-file
write; the trigger condition for worktree-discipline is upstream
to those.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — topic-slug regex, 5-field minimum, parent-specific
  conditional-field discipline.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` —
  storage substrate substitution surface (`wip-yaml-md` is the
  v1 value), L13 amendment defining the `parent_orchestration:`
  block as the pattern-level parent-orchestration primitive.
- `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`
  — the three-phase flow Phase 2 invokes before each child
  invocation (not Phase 0).
