# Phase 0: Setup

Parse the flags, validate the topic slug, validate any supplied
upstream, and create the state file. Phase 0 is the entry-point
guard rail: it rejects unsafe or non-conforming inputs before any
other phase runs and records the bootstrap context the rest of the
workflow assumes. Repository visibility detection is deferred to
Phase 1, where the visibility gate consumes it — with one
exception named in step 0.4, because the upstream check that needs
visibility must run before the value is recorded anywhere.

## Goal

Establish the runtime context for `/charter`:

- Parse the execution-mode flags and `--upstream <path>` out of
  `$ARGUMENTS` FIRST, before anything reads the positional slug.
- If what remains is empty, surface the cold-start prompt and stop
  Phase 0 until the author re-invokes with a conforming slug.
- If what remains is non-empty, validate it AS PROVIDED against the
  pattern-level regex `^[a-z0-9-]+$`. No normalization, no
  derivation, no "best effort" massaging.
- Reject non-conforming input with a clear error message naming the
  offending value and the violated pattern. Phase 0 stops; the
  author re-invokes `/charter <conforming-slug>`.
- Canonicalize, bounds-check, and type-check any `--upstream`
  value, then run the three ordered checks in step 0.4.
- Detect repository visibility from CLAUDE.md (deferred to Phase 1
  per the visibility-gate use case; Phase 0 only reads it for the
  third upstream check, and otherwise records the slug and creates
  state).
- On match, create the state file at `wip/charter_<topic>_state.md`
  with `phase_pointer: 0` and `exit: UNSET`, plus
  `consumed_upstream:` when — and only when — an upstream survived
  step 0.4.

By the end of Phase 0, downstream phases can assume the slug
recorded in state is byte-identical to the validated positional
argument and that the state file exists with the expected initial
fields.

## 0.1 Parse Flags Before the Positional Slug Is Read

`/charter` parses four flags out of `$ARGUMENTS`: the three
execution-mode flags (`--auto`, `--interactive`, `--max-rounds=N`
— see SKILL.md "Execution-Mode Flags") and `--upstream <path>`,
which names an existing artifact this chain consumes rather than
produces. All four are parsed here, before any step reads the
positional slug.

**The residue rule.** Each flag — and, for `--upstream`, the token
that follows it — is removed from `$ARGUMENTS` before step 0.3
reads the positional argument. What remains after the removal IS
the positional argument, and step 0.3 validates it unchanged,
byte for byte.

The rule is what keeps the positional contract intact. The token
following `--upstream` is consumed as that flag's argument and is
NEVER tested against the topic-slug regex, so
`/charter <topic-slug> --upstream docs/visions/VISION-<name>.md`
validates `<topic-slug>` and nothing else. The path-rejection rule
is untouched by the flag's existence:
`/charter docs/visions/VISION-<name>.md`, with the path in the
positional slot, is still rejected at step 0.3 exactly as it is
today.

**A bare `--upstream` is a Phase 0 rejection.** When `--upstream`
is the last token in `$ARGUMENTS`, or the token following it
begins with `--`, there is no value to consume. Reject naming the
missing argument and stop — before the slug is validated, before
the state file is written, before any child is invoked:

> *"`--upstream` requires a path argument naming the upstream
> artifact this chain consumes, for example `--upstream
> docs/visions/VISION-<name>.md`. Re-invoke `/charter <topic-slug>
> --upstream <path>`."*

`--upstream` may appear at most once. A second occurrence is
rejected the same way, naming the repeated flag: the state field
that records the value holds one path, and silently keeping the
last occurrence would hide which upstream the chain consumed.

## 0.2 Handle Empty `$ARGUMENTS`

If `$ARGUMENTS` is empty or whitespace-only after step 0.1's flag
removal, surface the cold-start prompt:

> *"What strategic conversation do you want to have? Common framings:
> 'start a strategic conversation about X', 'open a charter for Y',
> or 'I need to think through the bet on Z'. Re-invoke `/charter
> <topic-slug>` where the slug matches `^[a-z0-9-]+$` — for example,
> `/charter pricing-model-rebuild` or `/charter ingest-pipeline`."*

Phase 0 then stops. The author re-invokes `/charter
<conforming-slug>` after composing the slug; the cold-start path
does not auto-retry, does not loop, and does not derive a slug from
the author's response. Re-invocation goes through step 0.3.

A run whose only content was `--upstream <path>` lands here: the
flag is not a topic, and the cold-start prompt fires rather than a
slug being derived from the upstream's filename.

## 0.3 Validate the Positional Argument Against `^[a-z0-9-]+$`

When the post-flag-removal residue is non-empty, test it AS
PROVIDED against the regex `^[a-z0-9-]+$`. The regex is the
pattern-level constraint
cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
(Topic-Slug Regex section).

There is NO normalization step before validation. The residue is
checked byte-for-byte against the regex. Phase 0 does not lowercase,
does not replace whitespace, does not strip punctuation, does not
collapse repeated hyphens, does not trim leading or trailing
characters. The slug the author typed IS the slug Phase 0 validates.
Flag removal is not normalization: it deletes tokens the author
marked as flags and leaves everything else exactly as typed.

On match: the topic slug is the residue verbatim; proceed to step
0.4 (upstream validation) and then step 0.5 (state-file creation).

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

The following non-empty residues are REJECTED by step 0.3 because
they violate `^[a-z0-9-]+$`. Phase 0 stops in each case; no state
file is created.

| Positional residue (as provided) | Violation | Rejection message |
|---|---|---|
| `MyTopic` | uppercase letters | *"Topic slug `MyTopic` does not match the required pattern `^[a-z0-9-]+$`. Uppercase letters are not allowed; use only lowercase letters, digits, and hyphens. Did you mean `mytopic` or `my-topic`?"* |
| `my_topic` | underscore | *"Topic slug `my_topic` does not match the required pattern `^[a-z0-9-]+$`. Underscores are not allowed; use hyphens instead. Did you mean `my-topic`?"* |
| `my.topic` | dot | *"Topic slug `my.topic` does not match the required pattern `^[a-z0-9-]+$`. Dots are not allowed; use only lowercase letters, digits, and hyphens. Did you mean `mytopic` or `my-topic`?"* |
| `Hello World` | whitespace + uppercase | *"Topic slug `Hello World` does not match the required pattern `^[a-z0-9-]+$`. Whitespace and uppercase letters are not allowed; use only lowercase letters, digits, and hyphens. Did you mean `hello-world`?"* |
| `docs/visions/VISION-foo.md` | slashes + uppercase + dot | *"Topic slug `docs/visions/VISION-foo.md` does not match the required pattern `^[a-z0-9-]+$`. Paths to existing artifacts are not accepted as topic slugs; re-invoke `/charter` with a topic slug like `vision-foo` or describe the topic conceptually."* |
| `--leading` | leading hyphen segment treated as a flag would normally short-circuit; if interpreted literally, the regex still matches (hyphens are permitted) — but the literal `--` is reserved for flag parsing | rejected by step 0.1's flag parsing (see SKILL.md "Execution-Mode Flags" and "Upstream Flag"); not a slug input |
| empty string after flag-stripping | empty input | handled by step 0.2 (cold-start prompt) — not a slug-rejection case |

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
positional residue that looks like a file path (contains `/`, `.`,
or uppercase letters from typical artifact prefixes like `VISION-`,
`STRATEGY-`) FAILS the regex and is rejected. The example
`/charter docs/visions/VISION-foo.md` is rejected at step 0.3
because the input contains slashes, dots, and uppercase letters.

This is the intended behavior: `/charter` does NOT accept paths to
durable artifacts as an input mode. The author must supply a
conforming topic slug (e.g., `vision-foo`), not a path. An upstream
the author wants this chain to consume is named with `--upstream
<path>`, whose value never reaches this check (step 0.1); an
upstream the chain discovers for itself is established during
Phase 1 discovery by inspecting topic-related child docs in the
repo. Neither route parses a path out of the slug.

## 0.4 Validate the `--upstream` Value

Runs only when step 0.1 consumed a value. Every check below is a
hard stop or a documented omission — no `--upstream` value reaches
the state file, a child invocation, or a committed frontmatter
field without passing all of them.

### Canonicalize and Bounds-Check

Canonicalize the value to an absolute path: resolve it against the
repo root (the working directory `/charter` was invoked from) and
resolve symlinks fully. Reject the invocation if the canonical path
resolves outside the repo working tree: a symlink pointing at
`/etc/passwd` or at a sibling clone is not an upstream, and unlike
most path arguments this one ends up in a committed field.

Cross-repo values are the exception, and they are deliberately
allowed: an upstream expressed in the `owner/repo:path` convention
from
[`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`](${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md)
is not a working-tree path and is not resolved against the
filesystem at all. It skips this check and the tracked-by-git check
below, and lands directly on the visibility check, which is the
only one that can say anything about it. On the strategic hop the
cross-repo case is the ordinary one rather than a corner: the
strategic corpus commonly lives outside the repo the chain runs in.

### Enforce the Basename

The canonical path's basename MUST start with `VISION-`, and the
same rule applies to the file component of a cross-repo value.
Reject anything else, naming the offending path and the expected
prefix.

Inbound validation enforces the basename even though the outbound
contract — the `--upstream` `/charter` hands `/roadmap` at Phase 2
— does not, and the asymmetry is deliberate. Outbound, `/charter`
hands over an artifact it just watched a child produce and whose
type it therefore knows. Inbound, it is routing on a string the
author typed. A wrong type inbound is not caught anywhere
downstream: `/strategy` would record a ROADMAP or a PLAN as the
strategy's parent, the chain head would be framed against the wrong
altitude, and nothing would say so.

### Three Ordered Checks

Run these in order, exactly as `/prd`'s draft phase runs them. They
are reused rather than reinvented, so an author sees one behavior
from the flag whichever skill they hand it to.

1. **Is the path under `wip/`?** STOP and reject. `wip/` artifacts
   are non-durable — the wip-hygiene cleanup deletes them before
   the PR can merge — so a `wip/` upstream would leave the produced
   document's `upstream:` pointing at a file that no longer exists
   the moment cleanup lands. Name the canonical location in the
   rejection so the author can re-invoke against it.
2. **Is the path tracked by git?** Run `git ls-files -- <path>`.
   An empty result on a value that resolved inside the working tree
   means the file exists locally but is not committed; reject,
   naming the untracked path. An untracked upstream is durable to
   nobody but this working copy.
3. **Would a public document name a private upstream?** Read repo
   visibility from CLAUDE.md's `## Repo Visibility:` header (the
   one Phase 0 use of a value Phase 1 otherwise owns; the check has
   to run before the value is recorded, and Phase 1 is after that).
   When this repo is Public AND the upstream lives in a private
   repo, STOP recording: do not write `consumed_upstream:`, do not
   pass the flag to any child, and tell the author the field is
   being omitted and why. The chain then runs exactly as it would
   have with no `--upstream` at all.

The third check is the load-bearing one, because the flag's value
reaches a committed `upstream:` field in the produced document. Public documents must not reference private ones (see the
visibility-direction table in
[`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`](${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md)),
and that rule is enforced by content governance rather than by
tooling: `shirabe validate`'s resolution check returns nothing for a
cross-repo value, so a public document carrying a private cross-repo
upstream validates clean today and always will. `/charter` owns the
check the validator cannot make.

Checks 1 and 2 reject the run while check 3 omits the field and
continues, and the difference is not an inconsistency. A `wip/` or
untracked path is malformed input the author can fix by re-invoking
with the canonical path; continuing without an upstream would hide
the mistake. A private upstream in a public repo is a legitimate
value that this repo cannot record — the bet is still worth
writing, so the chain proceeds and the link is what gets dropped.
When the field is omitted, the author may still describe the
source context in the produced document's prose, without naming a
private path or repo.

## 0.5 Create the State File

On regex match (step 0.3 passed) and after step 0.4 has settled any
`--upstream` value, create the state file at
`wip/charter_<topic>_state.md` (where `<topic>` is the validated
positional argument, byte-for-byte). The file is the v1 core-layer
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
consumed_upstream: <canonical upstream path>   # only when 0.4 passed
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

`consumed_upstream:` is the one conditional field Phase 0 can
write, because its trigger — an author supplying `--upstream` —
fires here or never. The same absence discipline binds: the field
is written when and only when step 0.4 passed, and is ABSENT
otherwise, never `none`, never null, never an empty string. A run
whose upstream was dropped by the visibility check is
indistinguishable in state from a run that supplied no upstream,
which is the intended shape — nothing records a private path in a
public repo, including the state file, which is itself durable on
the pushed feature branch. See the field's entry in
`skills/charter/references/phases/phase-state-management.md`.

After the state file is created, Phase 0 completes and control
transfers to Phase 1 (discovery + visibility gate + chain
proposal). The Phase 1 procedure is at
`skills/charter/references/phases/phase-1-discovery.md`.
