# Phase 0 — Setup

Phase 0 binds four contracts: flag parsing ahead of the positional
argument, topic-slug validation against the pattern's regex,
visibility detection from `CLAUDE.md`, and the unconditional
self-heal of any stale `parent_orchestration:` block found at
session start. Phase 0 ends with the initial state-file written and
the phase pointer advanced to Phase 1.

## Flag Parsing Before the Positional Slug Is Read

`/scope` parses its flags out of `$ARGUMENTS` before any step
reads the positional argument: the execution-mode flags (`--auto`,
`--interactive`, `--max-rounds=N`), the coordination-intent flags
(`--coordinated`, `--no-coordinated`), and `--upstream <path>`.

**The residue rule.** Each flag — and, for `--upstream`, the token
that follows it — is removed from `$ARGUMENTS` before the topic
slug is read. What remains after the removal IS the positional
argument, and it is validated unchanged, byte for byte.

The rule is what keeps the positional contract intact. The token
following `--upstream` is consumed as that flag's argument and is
NEVER tested against the topic-slug regex, so
`/scope <topic-slug> --upstream docs/roadmaps/ROADMAP-<name>.md`
validates `<topic-slug>` and nothing else. The path-rejection rule
is untouched by the flag's existence:
`/scope docs/roadmaps/ROADMAP-<name>.md`, with the path in the
positional slot, is still rejected exactly as it is today. Flag
removal is not normalization — it deletes tokens the author marked
as flags and leaves everything else as typed.

**A bare `--upstream` is a Phase 0 rejection.** When `--upstream`
is the last token in `$ARGUMENTS`, or the token following it begins
with `--`, there is no value to consume. Reject naming the missing
argument and stop — before the slug is validated, before the state
file is written, before any child is invoked:

> *"`--upstream` requires a path argument naming the upstream
> artifact this chain consumes, for example `--upstream
> docs/roadmaps/ROADMAP-<name>.md`. Re-invoke `/scope <topic-slug>
> --upstream <path>`."*

`--upstream` may appear at most once. A second occurrence is
rejected the same way, naming the repeated flag: the state field
that records the value holds one path, and silently keeping the
last occurrence would hide which upstream the chain consumed.

## Cold-Start Path

When `$ARGUMENTS` is empty after flag removal, Phase 0 surfaces a
cold-start prompt naming the three trigger phrases from CLAUDE.md
("specify a feature called X", "scope feature Y", "walk me through
specifying Z") and asks the author to re-invoke
`/scope <topic-slug>` with a slug that matches the topic-slug
regex. Phase 0 then stops; there is no auto-derivation of a slug
from prior context and no looping retry. A run whose only content
was `--upstream <path>` lands here: the flag is not a topic, and
the cold-start prompt fires rather than a slug being derived from
the upstream's filename.

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
  shape for `/scope`'s entry mode; an upstream the chain consumes
  is named with `--upstream <path>`, and one the chain finds for
  itself is detected during Phase 1 discovery. Neither is parsed
  out of the positional slot.

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

## Upstream Validation

Runs only when the flag parsing above consumed a value. Every check
below is a hard stop or a documented omission — no `--upstream`
value reaches the state file, a child invocation, or a committed
frontmatter field without passing all of them.

**Canonicalize and bounds-check.** Resolve the value against the
repo root and resolve symlinks fully. Reject the invocation if the
canonical path resolves outside the repo working tree: a symlink
pointing at `/etc/passwd` or at a sibling clone is not an upstream,
and unlike most path arguments this one ends up in a committed
field.

Cross-repo values are the exception, and they are deliberately
allowed: an upstream expressed in the `owner/repo:path` convention
from
[`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`](${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md)
is not a working-tree path and is not resolved against the
filesystem at all. It skips this check and the tracked-by-git check
below, and lands directly on the visibility check, which is the
only one that can say anything about it.

**Enforce the basename.** The canonical path's basename MUST start
with `ROADMAP-`, and the same rule applies to the file component of
a cross-repo value. Reject anything else, naming the offending path
and the expected prefix. Inbound validation enforces the basename
even though an outbound hand-off does not, and the asymmetry is
deliberate: outbound, the parent hands over an artifact it just
watched a child produce and whose type it therefore knows; inbound,
it is routing on a string the author typed. A wrong type inbound is
caught nowhere downstream — `/brief` would record a PRD or a DESIGN
as the feature's upstream, inverting the chain it sits in, and
nothing would say so.

**Three ordered checks.** Run these in order, exactly as `/prd`'s
draft phase runs them. They are reused rather than reinvented, so
an author sees one behavior from the flag whichever skill they hand
it to.

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
3. **Would a public document name a private upstream?** Using the
   visibility detected above, when this repo is Public AND the
   upstream lives in a private repo, STOP recording: do not write
   `consumed_upstream:`, do not pass the flag to any child, and
   tell the author the field is being omitted and why. The chain
   then runs exactly as it would have with no `--upstream` at all.

The third check is the load-bearing one, because the flag's value
reaches a committed `upstream:` field in the produced BRIEF.
Public documents must not reference private ones (see the
visibility-direction table in
[`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`](${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md)),
and that rule is enforced by content governance rather than by
tooling: `shirabe validate`'s resolution check returns nothing for a
cross-repo value, so a public document carrying a private cross-repo
upstream validates clean today and always will. `/scope` owns the
check the validator cannot make.

Checks 1 and 2 reject the run while check 3 omits the field and
continues, and the difference is not an inconsistency. A `wip/` or
untracked path is malformed input the author can fix by re-invoking
with the canonical path; continuing without an upstream would hide
the mistake. A private upstream in a public repo is a legitimate
value that this repo cannot record — the feature is still worth
scoping, so the chain proceeds and the link is what gets dropped.

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
consumed_upstream: <canonical upstream path>   # only when validation passed
```

The 5-field minimum (`topic`, `last_updated`, `phase_pointer`,
`exit`, `exit_artifacts`) is filled with their initial values;
the `/scope`-specific extensions (`chain_started`,
`planned_chain`) are also written. Other `/scope`-specific
fields are absent at Phase 0 per invariant I-5; they appear only
when their triggering condition fires later in the chain.

`consumed_upstream:` is the one conditional field Phase 0 can
write, because its trigger — an author supplying `--upstream` —
fires here or never. The same absence discipline binds: the field
is written when and only when Upstream Validation passed, and is
ABSENT otherwise, never `none`, never null, never an empty string.
A run whose upstream was dropped by the visibility check is
indistinguishable in state from a run that supplied no upstream,
which is the intended shape — nothing records a private path in a
public repo, including the state file, which is itself durable on
the pushed feature branch.

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
