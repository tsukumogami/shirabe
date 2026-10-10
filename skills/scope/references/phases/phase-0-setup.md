# Phase 0 — Setup

Phase 0 binds five contracts: tokenizing the invocation and the
residue rule, the entry into koto through `scripts/scope-open.sh`
(where koto checks every argument its variables can express),
visibility detection from `CLAUDE.md`, the recording of the run's
effective intent, and the unconditional removal of any stale
`chain/dispatch` key found at invocation. Phase 0 ends with
the initial `work/state.md` key written and the phase pointer advanced to
Phase 1.

## Tokenizing and the Residue Rule

`/scope` splits `$ARGUMENTS` into tokens as typed: the positional
topic, the execution-mode flags (`--auto`, `--interactive`,
`--max-rounds=N`), the coordination flags (`--coordinated`,
`--no-coordinated`), `--intent=continue|stop`, `--upstream <path>`, and
`--koto-leg=<request-id>:<leg>`. It does not judge any token. It
writes them, in order, to an args file and lets `scope-open.sh` map
them.

**The residue rule.** Each flag — and, for `--upstream`, the token
that follows it — is set aside before the topic slug is read. What
remains IS the positional argument, and it reaches koto unchanged,
byte for byte, as `TOPIC`. `scope-open.sh` applies the rule itself:
the token following `--upstream` is consumed as that flag's value and
is NEVER read as the topic, so
`/scope <topic-slug> --upstream docs/roadmaps/ROADMAP-<name>.md`
passes `<topic-slug>` and nothing else as the slug. The
path-rejection rule is untouched by the flag's existence:
`/scope docs/roadmaps/ROADMAP-<name>.md`, with the path in the
positional slot, is refused by koto's topic pattern exactly as it
was refused by prose. Setting flags aside is not normalization — it
removes tokens the author marked as flags and leaves everything else
as typed. Two leftover words, or an unknown flag, are joined into
one topic value and fail the pattern.

**The args file.** A JSON array of the raw tokens, positional
included, written outside the work tree: to a private directory from
`${CLAUDE_PLUGIN_ROOT}/scripts/koto-open.sh --alloc-dir` (mode
0700, under `$TMPDIR`), or to the koto session directory. Write it
with the Write tool or `jq`, never by pasting tokens into a shell
command: a token is data, and the file is the only route by which it
reaches koto. `scope-open.sh` removes the file on every exit path,
refusals included. An args file inside the work tree is refused
before any koto call.

## Cold-Start Path

When `$ARGUMENTS` holds no positional token once the flags are set
aside, Phase 0 surfaces a cold-start prompt saying what reaches this
entry point, in the terms CLAUDE.md uses — a feature to be built,
added, or redesigned whose requirements are not already written down
— and asks the author to re-invoke `/scope <topic-slug>` with a slug
that matches the topic-slug regex. Phase 0 then stops, before any
args file is written and before `koto init`; there is no
auto-derivation of a slug from prior context and no looping retry. A
run whose only content was `--upstream <path>` lands here: the flag
is not a topic, and the cold-start prompt fires rather than a slug
being derived from the upstream's filename.

The cold-start prompt is a standalone run's affordance. Under
`--koto-leg` the caller built the invocation and named a topic.

## Workflow Session: Entry Through `scope-open.sh`

The session name is `scope-<topic>`, composed from the fixed prefix
and the slug and from nothing else. It is recomputed at every use
rather than read back from anywhere.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/scope/scripts/scope-open.sh \
  --plugin-root ${CLAUDE_PLUGIN_ROOT} <args-file>
```

`scope-open.sh` maps each flag occurrence to one `["NAME", "VALUE"]`
pair with `jq` and calls `koto init scope-<topic> --vars-file <file>
--attach-live` once, through the shared
`${CLAUDE_PLUGIN_ROOT}/scripts/koto-open.sh`:

| Token | Variable |
|---|---|
| positional residue | `TOPIC` |
| `--intent=<v>` | `INTENT_FLAG=<v>`, unmodified; a lone `--intent=` is left out, like a missing flag; a bare `--intent` is the literal token, which the pattern refuses |
| `--auto` / `--interactive` | `EXEC_MODE=auto` / `EXEC_MODE=interactive` |
| `--max-rounds=<n>` | `MAX_ROUNDS=<n>` |
| `--coordinated` / `--no-coordinated` | `COORDINATION=coordinated` / `COORDINATION=no-coordinated` |
| `--upstream <path>` | `UPSTREAM=<path>`; with no value, the literal token |
| `--koto-leg=<request-id>:<leg>` | passed to koto as `--koto-leg` |

It also passes `PLUGIN_ROOT` and `PLUGIN_ROOT_PLACEMENT`, which it
computes on every invocation (`outside`, or `inside-worktree` when the
plugin root lies in the repository being scoped). Every flag
occurrence is its own pair, so a repeated `--intent`, `--auto` with
`--interactive`, or `--coordinated` with `--no-coordinated` is a
duplicate koto refuses. The variables and their constraints are
declared, with their reasons, in `scope.md`.

Read the lines it prints:

- `opened=new` — no session had the name, and koto made one.
- `opened=attached` — a live session with the same template, origin
  (worktree and session store), and fixed variables was joined; the
  rebindable settings (`EXEC_MODE`, `MAX_ROUNDS`, `PLUGIN_ROOT`,
  `PLUGIN_ROOT_PLACEMENT`) took this invocation's values, listed on
  the `rebound=` line. A bare re-invocation attaches: an omitted
  `--intent` is not compared.
- `refused=<code>` followed by `outcome=error` and
  `step=scope:refused`, with the refusal text on stderr — print the
  text and those two lines and stop. Nothing was created: no session,
  no state key. `refused` is never printed after `outcome=`.
- `failed=<kind>` or `error=usage`, also followed by `outcome=error`
  and `step=scope:refused` — the same: report and stop.

The refusal text is `/scope`'s own wording, rendered from koto's typed
error by `scope-open.sh` (`skills/scope/scripts/scope-open.wording.tsv`):
the slug refusal names the pattern `^[a-z0-9-]+$`, an `--intent`
refusal names the flag, and `--intent=none` or `--intent=unset` read
exactly like `--intent=bogus` apart from the value. A live session
started with a different `--intent` is refused as `var_mismatch` and
left untouched; one opened from another worktree or store is refused
as `origin_mismatch`. `/scope` never removes or cancels the other
session: koto's message may recommend that remedy, and it would
destroy another run.

**Under `--koto-leg`.** `scope-open.sh` checks the value against
koto's request-id grammar and the closed leg-name set (`scope`)
before any koto call. The flag changes nothing but where the
terminal result goes: koto binds the session to the leg, and a
refusal at `koto init` — every argument refusal included — is
recorded on the leg as `source: refused` with a payload whose
`reason` is `invalid-var:<V>`, `duplicate-var:<V>`,
`var-mismatch:<V>`, `template-mismatch` or `origin-mismatch`. A
malformed `--koto-leg` is the one refusal that cannot reach the leg:
no koto call can be built.

**Ticking.** Every `koto next` carries `--no-cleanup`, on every tick,
whether or not `--koto-leg` is given; see Running the Workflow in
`skills/scope/SKILL.md`. The first tick runs `intake`,
`branch_check` and `resume_route`, each of which advances on its own.
On a fresh topic it stops at `setup`. `resume_route` runs the resume
ladder (`skills/scope/references/phases/phase-resume.md`) and may
instead stop at a ladder prompt, re-enter a resumed chain, go to a
publish retry or one of the `--intent` shortcuts, or end the run at
`done_refused` for a PLAN under way; `intake` ends it at
`done_refused` or `done_error` when it refused the invocation or could
not check it.

## Topic-Slug Validation

The topic-slug regex `^[a-z0-9-]+$` is cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
(Topic-Slug Regex section). koto applies it, as `TOPIC`'s pattern
`^[a-z0-9][a-z0-9-]*$` — the same regex with no leading `-`, so a
slug can never be read as an option — to the positional token AS
PROVIDED, byte for byte, with no normalization step before it. A slug
that fails is refused at `koto init`; `/scope` never proceeds with an
invalid slug and never normalizes the input into a conforming one.

The refusal reads, for example:

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

After the session opens, Phase 0 invokes the shirabe-validate
slug-prefix detection CLI to surface a recommendation when the
candidate slug does not conform to the workspace's prevailing prefix
convention:

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
recorded in key `work/state.md` and consumed by Phase 2's validator
pass-through
(`shirabe validate --format json --visibility=<value>`). When the
header is absent, `/scope` defaults to `Private` and surfaces a
warning containing the literal phrasing "Default to Private if
unknown" naming the missing header. The warning is informational;
the run proceeds against the Private default.

## Upstream Validation

Runs only when the invocation named `--upstream`. No `--upstream`
value reaches key `work/state.md`, a child invocation, or a committed
frontmatter field without passing every check below. Two of the
three places they run are not Phase 0 prose.

**The shape, in koto.** `UPSTREAM`'s pattern admits only a
repository-relative `docs/roadmaps/.../ROADMAP-*.md` path, or an
`owner/repo:` cross-repo value followed by one, with no `..` segment
anywhere. A bare `--upstream` (no value, or the next token starts
with `--`) reaches koto as the literal token and is refused with the
same message:

> *"`--upstream` requires a path argument naming the upstream
> artifact this chain consumes, for example `--upstream
> docs/roadmaps/ROADMAP-<name>.md` [...]. Re-invoke `/scope
> <topic-slug> --upstream <path>`."*

A second `--upstream` is a duplicate koto refuses, naming the
repeated flag: the state field that records the value holds one
path, and silently keeping the last occurrence would hide which
upstream the chain consumed.

**The working-tree battery, in `intake`.**
`skills/scope/scripts/check-upstream.sh` resolves the path from the
repository root with symlinks followed, and refuses, in order:

1. `upstream-outside` — the resolved path leaves the repository. A
   symlink pointing at `/etc/passwd` or at a sibling clone is not an
   upstream, and unlike most path arguments this one ends up in a
   committed field.
2. `upstream-wip` — the resolved path lies under `wip/`. `wip/`
   artifacts are non-durable — the wip-hygiene cleanup deletes them
   before the PR can merge — so a `wip/` upstream would leave the
   produced document's `upstream:` pointing at a file that no longer
   exists the moment cleanup lands.
3. `upstream-basename` — the resolved file's basename does not start
   with `ROADMAP-`. Inbound validation enforces the basename even
   though an outbound hand-off does not, and the asymmetry is
   deliberate: outbound, the parent hands over an artifact it just
   watched a child produce and whose type it therefore knows;
   inbound, it is routing on a string the author typed. `/brief`
   records no `upstream:` at all, so a wrong-type value never reaches
   frontmatter for a reviewer or the validator to catch — it silently
   frames the brief's problem and outcome against the wrong artifact.
4. `upstream-outside` — the resolved path is not under
   `<repo-root>/docs/roadmaps/`. This is the constraint `/brief`'s
   positional roadmap mode already carries, so a value the parent
   accepts is never one a child then rejects.
5. `upstream-untracked` — the file does not exist, or `git ls-files`
   does not list it. An untracked upstream is durable to nobody but
   this working copy.

A cross-repo value in the `owner/repo:path` convention from
[`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`](${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md)
is not a working-tree path and is not resolved against the
filesystem at all: only the basename check applies to its file
component, and it lands directly on the visibility check below, which
is the only one that can say anything about it.

**The visibility check, here.** Using the visibility detected above,
when this repo is Public AND the upstream lives in a private repo,
STOP recording: do not write `consumed_upstream:`, do not pass the
flag to any child, and tell the author the field is being omitted and
why. The chain then runs exactly as it would have with no
`--upstream` at all.

The visibility check is the load-bearing one, because the flag's value
reaches a committed `upstream:` field in the produced PLAN. The
roadmap path itself never reaches the BRIEF's frontmatter: the brief
grounds on the roadmap and records the roadmap's own durable ancestor,
resolved at `/brief`'s Phase 0 and run through the same visibility
check there. The crossing from the strategic chain into the tactical
one is recorded on the PLAN alone, because the PLAN is deleted by the
same cascade that deletes the roadmap and goes first — see
`${CLAUDE_PLUGIN_ROOT}/references/pipeline-model.md`.

## Recording the Effective Intent

`intake` resolved the run's effective intent before `setup`, and the
`setup` directive delivers it as `RUN_INTENT`: the caller's
`--intent` when one was given, else the `intent:` key `work/state.md`
already records, else `none`. Phase 0 writes it into that key
as `intent: <value>` — always present, always one of `continue`,
`stop`, `none`, never empty. An explicit `--intent` equal to the
recorded one proceeds; a different one against an unfinished run
never reaches this point (koto refuses it at attach while the session
lives, and `intake` refuses it as `intent-mismatch` once the session
is gone). The field's contract is in
`skills/scope/references/state-schema.md`.

The run's other settings are the session's variables and are read
from the `setup` directive rather than re-parsed: `EXEC_MODE`,
`COORDINATION`, `MAX_ROUNDS` (empty means the default of 5), and
`UPSTREAM`.

## Stale `chain/dispatch` Self-Heal

The dispatch key is ephemeral within a chain instance: `/scope`
writes `chain/dispatch` into its own session, `scope-<topic>`,
immediately before invoking a child and clears it immediately after
the child returns. A key present at session start (when a fresh
`/scope` invocation opens against a topic with an existing session)
is by definition stale — the chain that wrote it is no longer in
flight.

Phase 0 SHALL unconditionally remove it:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" dispatch clear scope <topic>
```

The self-heal MUST NOT prompt the author for confirmation; it MUST
NOT surface a warning; it MUST NOT treat the key as authoritative on
the resume. The clear is the contract, and it is idempotent: with no
key it changes nothing.

The unconditional shape rules out any conditional behavior — no
"if author confirms", no "if last_updated is recent", no
prompt-on-clear. The key is removed silently, `work/state.md` is left
untouched, and the resume ladder proceeds. The convention behind the
key is in `${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`.

## Initial `work/state.md` Shape

After the session opened and the self-heal completes, Phase 0
writes (or updates) key `work/state.md` in session `scope-<topic>`
(the state lives in koto session context; write it with
`koto context add scope-<topic> work/state.md`, content on stdin)
with the initial shape:

```yaml
topic: <slug>
session: scope-<topic>
intent: <continue|stop|none>                  # RUN_INTENT, always present
chain_started: <ISO-8601 timestamp>
last_updated: <ISO-8601 timestamp>
phase_pointer: 0
exit:
exit_artifacts: []
planned_chain: []
consumed_upstream: <canonical upstream path>   # only when validation passed
```

The 5-field minimum (`topic`, `last_updated`, `phase_pointer`,
`exit`, `exit_artifacts`) is filled with their initial values;
`phase_pointer` is the integer phase `0`, never `phase-0`, and `exit:`
is empty: `skills/scope/scripts/resume-probe.sh` accepts only `0`-`4`
as a pointer and reads only an empty, `null` or `~` exit as unset, so
a `phase-0` pointer or a literal `UNSET` exit routes a resume to the
malformed-state row. The `/scope`-specific extensions (`session`, `intent`,
`chain_started`, `planned_chain`) are also written. Other
`/scope`-specific fields are absent at Phase 0 per invariant I-5;
they appear only when their triggering condition fires later in the
chain.

`session:` records the session this run opened or attached to. It
is the name recomputed from the validated slug, written here so a
reader of the key can find the run's per-hop record, and it
is never read back for interpolation: a use recomputes the name and
compares.

`intent:` is the effective intent above. Every later write that
rewrites the key keeps it.

`consumed_upstream:` is the one conditional field Phase 0 can
write, because its trigger — an author supplying `--upstream` —
fires here or never. The same absence discipline binds: the field
is written when and only when Upstream Validation passed, and is
ABSENT otherwise, never `none`, never null, never an empty string.
A run whose upstream was dropped by the visibility check is
indistinguishable in state from a run that supplied no upstream,
which is the intended shape — nothing records a private path in a
public repo, including `work/state.md`.

Phase 0 advances the `phase_pointer:` to `1` immediately
before returning control to Phase 1, so a resume against the
written state enters at Phase 1's discovery prompts. The write
follows the tick that advanced the session out of `setup`, never
precedes it: the pointer names the phase of the state the session
is now in, read off that state's `# phase: N` comment in
`skills/scope/koto-templates/scope.md`. Writing it first would
record a position the session might not reach, and the pointer is
what a resume with no session to consult has to trust.

The initial write above is the one exception, and it is the case the
rule already covers: the session is still in `setup` when Phase 0
writes `phase_pointer: 0`, so the value comes from `/scope`'s
own phase.

## Worktree-Discipline Trigger Is Not in Phase 0

The worktree-discipline three-phase flow (Merge phase → Impact-
analysis phase → Escalation phase) defined in
`${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`
fires BEFORE EACH Phase 2 child invocation. It does NOT fire in
Phase 0. Phase 0's contracts are bounded to tokenizing, the koto
entry, visibility detection, self-heal, and the initial `work/state.md`
write; the trigger condition for worktree-discipline is upstream
to those.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — topic-slug regex, 5-field minimum, parent-specific
  conditional-field discipline, and the invocation-intent field.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` —
  storage substrate substitution surface (this skill's value is the
  session: the state lives in koto session context), L13 amendment defining the `chain/dispatch` key as
  the pattern-level parent-orchestration primitive.
- `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`
  — the three-phase flow Phase 2 invokes before each child
  invocation (not Phase 0).
- `skills/scope/koto-templates/scope.md` — the variables koto checks
  at init, the `intake` state, and the `# phase: N` comments the
  pointer is derived through.
- `skills/scope/scripts/scope-open.sh` — the token mapping, the
  refusal wording, and the result lines.
- `skills/scope/SKILL.md` — the Running the Workflow section, which
  points here for the session procedure and carries the
  directive-versus-details contract the rest of the run depends on.
