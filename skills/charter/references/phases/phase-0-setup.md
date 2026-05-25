# Phase 0: Setup

Validate the topic slug and create the state file. Phase 0 is the
entry-point guard rail: it rejects unsafe or non-conforming inputs
before any other phase runs and records the bootstrap context the
rest of the workflow assumes. Repository visibility detection is
deferred to Phase 1, where the visibility gate consumes it.

## Goal

Establish the runtime context for `/charter`:

- If `$ARGUMENTS` is empty, surface the cold-start prompt and stop
  Phase 0 until the author re-invokes with a conforming slug.
- If `$ARGUMENTS` is non-empty, validate it AS PROVIDED against the
  pattern-level regex `^[a-z0-9-]+$`. No normalization, no
  derivation, no "best effort" massaging.
- Reject non-conforming `$ARGUMENTS` with a clear error message
  naming the offending input and the violated pattern. Phase 0
  stops; the author re-invokes `/charter <conforming-slug>`.
- Detect repository visibility from CLAUDE.md (deferred to Phase 1
  per the visibility-gate use case; Phase 0 only records the slug
  and creates state).
- On match, create the state file at `wip/charter_<topic>_state.md`
  with `phase_pointer: 0` and `exit: UNSET`.

By the end of Phase 0, downstream phases can assume the slug
recorded in state is byte-identical to the validated `$ARGUMENTS`
and that the state file exists with the expected initial fields.

## 0.1 Handle Empty `$ARGUMENTS`

If `$ARGUMENTS` is empty or whitespace-only, surface the cold-start
prompt:

> *"What strategic conversation do you want to have? Common framings:
> 'start a strategic conversation about X', 'open a charter for Y',
> or 'I need to think through the bet on Z'. Re-invoke `/charter
> <topic-slug>` where the slug matches `^[a-z0-9-]+$` — for example,
> `/charter pricing-model-rebuild` or `/charter ingest-pipeline`."*

Phase 0 then stops. The author re-invokes `/charter
<conforming-slug>` after composing the slug; the cold-start path
does not auto-retry, does not loop, and does not derive a slug from
the author's response. Re-invocation goes through step 0.2.

## 0.2 Validate `$ARGUMENTS` Against `^[a-z0-9-]+$`

When `$ARGUMENTS` is non-empty, test the value AS PROVIDED against
the regex `^[a-z0-9-]+$`. The regex is the pattern-level constraint
cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
(Topic-Slug Regex section).

There is NO normalization step before validation. `$ARGUMENTS` is
checked byte-for-byte against the regex. Phase 0 does not lowercase,
does not replace whitespace, does not strip punctuation, does not
collapse repeated hyphens, does not trim leading or trailing
characters. The slug the author typed IS the slug Phase 0 validates.

On match: the topic slug is `$ARGUMENTS` verbatim; proceed to step
0.3 (state-file creation).

On regex failure: reject the invocation with an error message that
names the offending input and the violated pattern. Phase 0 stops;
no state file is created; no Phase 1 invocation; no "best effort"
slug derivation.

The error message MUST name the violated pattern explicitly so the
author knows what to fix. Example wording:

> *"Topic slug `<offending input>` does not match the required
> pattern `^[a-z0-9-]+$`. Slugs MUST contain only lowercase letters,
> digits, and hyphens — no uppercase letters, underscores, dots,
> slashes, or whitespace. Re-invoke `/charter` with a conforming
> slug, for example `/charter <suggested-slug>`."*

The error message MAY suggest a conforming alternative in prose
(e.g., "did you mean `my-topic`?"), but the suggestion is
advisory ONLY — Phase 0 never auto-substitutes the suggestion. The
author must explicitly re-invoke with the corrected slug.

### Concrete Rejection Examples

The following non-empty `$ARGUMENTS` values are REJECTED by step
0.2 because they violate `^[a-z0-9-]+$`. Phase 0 stops in each
case; no state file is created.

| `$ARGUMENTS` (as provided) | Violation | Rejection message |
|---|---|---|
| `MyTopic` | uppercase letters | *"Topic slug `MyTopic` does not match the required pattern `^[a-z0-9-]+$`. Uppercase letters are not allowed; use only lowercase letters, digits, and hyphens. Did you mean `mytopic` or `my-topic`?"* |
| `my_topic` | underscore | *"Topic slug `my_topic` does not match the required pattern `^[a-z0-9-]+$`. Underscores are not allowed; use hyphens instead. Did you mean `my-topic`?"* |
| `my.topic` | dot | *"Topic slug `my.topic` does not match the required pattern `^[a-z0-9-]+$`. Dots are not allowed; use only lowercase letters, digits, and hyphens. Did you mean `mytopic` or `my-topic`?"* |
| `Hello World` | whitespace + uppercase | *"Topic slug `Hello World` does not match the required pattern `^[a-z0-9-]+$`. Whitespace and uppercase letters are not allowed; use only lowercase letters, digits, and hyphens. Did you mean `hello-world`?"* |
| `docs/visions/VISION-foo.md` | slashes + uppercase + dot | *"Topic slug `docs/visions/VISION-foo.md` does not match the required pattern `^[a-z0-9-]+$`. Paths to existing artifacts are not accepted as topic slugs; re-invoke `/charter` with a topic slug like `vision-foo` or describe the topic conceptually."* |
| `--leading` | leading hyphen segment treated as a flag would normally short-circuit; if interpreted literally, the regex still matches (hyphens are permitted) — but the literal `--` is reserved for execution-mode flag parsing | rejected by execution-mode flag parsing (see SKILL.md "Execution-Mode Flags"); not a slug input |
| empty string after flag-stripping | empty input | handled by step 0.1 (cold-start prompt) — not a slug-rejection case |

The five slug-rejection rows above are the canonical cases the
shared eval baseline (slug rejection scenario) asserts against.
Each rejection MUST name the violated pattern and MAY include a
suggested alternative; the author re-invocation is manual.

### Why No Normalization

Normalization would silently absorb input the author did not
intend. If a user types `my_topic` expecting it to be a literal
slug, normalizing to `my-topic` and proceeding would:

- write `wip/charter_my-topic_state.md` while the author searches
  for `wip/charter_my_topic_state.md`;
- name `docs/strategies/STRATEGY-my-topic.md` as the terminal
  artifact while the author refers to it as `my_topic`;
- create drift between what the author typed and what the
  artifacts on disk are named.

Reject-then-let-the-author-fix-it is the only correct contract.
The pattern-level requirement (PRD R3) is: any input containing
characters outside `[a-z0-9-]` MUST be rejected with a clear
error, not silently normalized.

### Path-as-Topic Behavior

Because validation is byte-for-byte against the regex, any
`$ARGUMENTS` that looks like a file path (contains `/`, `.`, or
uppercase letters from typical artifact prefixes like `VISION-`,
`STRATEGY-`) FAILS the regex and is rejected. The example
`/charter docs/visions/VISION-foo.md` is rejected at step 0.2
because the input contains slashes, dots, and uppercase letters.

This is the intended behavior: `/charter` does NOT accept paths to
durable artifacts as an input mode. The author must supply a
conforming topic slug (e.g., `vision-foo`), not a path. The
upstream-artifact relationship is established during Phase 1
discovery by inspecting topic-related child docs in the repo, not
by parsing paths out of the slug.

## 0.3 Create the State File

On regex match (step 0.2 passed), create the state file at
`wip/charter_<topic>_state.md` (where `<topic>` is the validated
`$ARGUMENTS` value, byte-for-byte). The file is the v1 core-layer
materialization of the `storage_substrate = wip-yaml-md`
substitution variable (see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`).

Initial state-file fields (Phase 0 writes these; Phase 1 and later
phases update them):

```yaml
topic: <validated-slug>
last_updated: <ISO-8601 timestamp>
phase_pointer: 0
exit: UNSET
exit_artifacts: []
```

The `exit: UNSET` value is the sentinel indicating the chain is in
progress; the R9 hard-finalization check (see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`,
R9 Hard-Finalization Check Spec section) fires at Phase N if this
field is still UNSET or not in the valid exit-enum at termination.

The `exit_artifacts: []` empty-list initial value is allowed
because the list is not gated by a specific `exit:` value — it is
filled progressively as children complete. Parent-specific
conditional fields (e.g., `referenced_strategy`,
`triggering_child`) are NOT written at Phase 0 — they are absent
per invariant I-5 until their triggering exit condition fires.

After the state file is created, Phase 0 completes and control
transfers to Phase 1 (discovery + visibility gate + chain
proposal). The Phase 1 procedure is at
`skills/charter/references/phases/phase-1-discovery.md`.
