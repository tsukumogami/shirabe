---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-populate-issueless-default.md
problem: |
  `shirabe roadmap populate` files one GitHub issue per feature when nobody
  names a mode, so the accidental invocation is the one with a remote side
  effect. And `/roadmap` never populates at all: the workflow ends at the
  Phase 4 jury, populate sits behind a second command a human has to remember,
  and FC16 is shape-gated, so an empty reserved-section skeleton validates at
  every lifecycle state.
decision: |
  Add an `--issues` flag that conflicts_with `--no-issues` at the clap layer,
  and invert `run_inner`'s branch so the issue-creating path is the one that
  requires an explicit request. Populate automatically at two points in the
  roadmap skill -- after the Phase 4 jury resolves and before the approval
  walkthrough, and again on the `activate` path -- both issueless, relying on
  populate's existing idempotence to make the second run free. Keep
  `/roadmap populate <path>` as the issue-filing action rather than adding a
  fifth input mode, and resolve its mode on the existing
  flag > CLAUDE.md-header > default stack with issueless as the default.
rationale: |
  The default is chosen on blast radius: issueless fails locally and
  recoverably, issue-creating fails on shared remote state someone must clean
  up by hand. Two populate points rather than one because they cover different
  entry paths -- the Phase 4 point makes the reviewed document the populated
  one, the activate point catches feature edits made during review and covers
  roadmaps created before this change. Reusing the existing input mode over a
  new verb follows the minimal-surface driver the issueless-preference design
  already set, and the mode stack is the mechanism this repo already uses twice.
---

# DESIGN: Populate issueless by default

## Status

Planned

Settles the four questions `BRIEF-populate-issueless-default.md` left open and
specifies the implementation for `PRD-populate-issueless-default.md`. The
default flip itself is not reopened here — it arrived as a maintainer decision
and this document records how to carry it out, plus the supersession of D5 it
requires.

## Context and Problem Statement

Two defects share a root and have to be fixed together.

`shirabe roadmap populate <path>` reads its mode from a single boolean:
`PopulateArgs::no_issues`, a clap flag defaulting to `false`. `run_inner`
branches on it at line 124 — `if args.no_issues { return run_issueless(...) }`
— and everything after that branch is the issue-creating path: `obtain_mapping`
(which shells out to `gh issue create` once per feature), `resolve_owner_repo`
(which shells out to `gh repo view`), then the issue-keyed renderers. The
issueless path below it is complete and hermetic; it constructs no `Command`
at all. So the safe behaviour is fully built and sits behind a flag, while the
behaviour with remote side effects is what you get by typing nothing.

Separately, nothing in the `/roadmap` workflow ever calls populate. The skill's
phase list runs Setup, Scope, Discover, Draft, Validate, and stops. Populate is
input mode 3, `/roadmap populate <path>`, invoked by a human out of band. FC16
— the reserved-section shape check — is documented as shape-gated rather than
status-gated at `skills/roadmap/references/roadmap-format.md:369`, so the empty
skeleton the template ships passes at Draft, Active, and Done alike. The
consequence is a roadmap that goes all the way to merged and worked with both
reserved sections blank, and no check anywhere objects.

These compound badly. Because populating is a step you can forget, the authors
who remember it are the ones running the command whose unflagged form files
issues. The easy-to-skip step is guarded by the expensive-to-mistake default.

## Decision Drivers

- **D1 — Blast-radius asymmetry.** The new default's failure mode is "no issues
  created": local, visible, and recoverable by re-running. The old default's
  failure mode is "unwanted issues created on a shared remote": a side effect on
  state other people see, which someone must clean up by hand. This is the
  driver the maintainer decided on, and it outranks backward compatibility here.
- **D2 — The workflow must never rely on the default.** The actual safety
  property is that every programmatic caller names its mode. The CLI default is
  a backstop for a human at a shell; if a workflow depends on it, the workflow
  breaks silently the next time it changes.
- **D3 — Issue creation stays deliberate and gated.** Creating issues is the
  one irreversible-ish action here. It happens after approval, by explicit
  invocation, behind the existing R14 gate, which stays in the skill.
- **D4 — Minimal surface.** Inherited from D6 of the issueless-preference
  design. Each new flag, input mode, or branch is future maintenance; prefer
  extending a mechanism the repo already runs over introducing a parallel one.
- **D5 — The reviewed document is the merged document.** An author who approves
  a roadmap should have read what actually lands, not a skeleton the tool fills
  in afterwards.
- **D6 — Supersession must be legible.** Reversing a recorded decision driver
  quietly is worse than not reversing it. The change needs a decision record and
  a release note.

### Superseding D5 of `DESIGN-roadmap-issueless-preference.md`

That design's decision driver D5 reads: *"Backward compatibility. Repos with no
new header must behave exactly as today (issue-creating populate, 'Do not fill
manually' in force). The default must be `required`."*

It is superseded deliberately. The reasoning it encoded was sound for a change
whose job was to *add* issueless mode without disturbing anyone — at that point
issueless was new and unproven, and defaulting to it would have changed
behaviour for every existing user in exchange for a benefit nobody had asked
for. What changed since is that issueless mode shipped, got its rendering fixed
in #262, and is now the mode the workflow will use on every automatic run. Its
correctness is no longer the open question. With that settled, D1's asymmetry
argument is what remains, and it points the other way. Backward compatibility
here buys a smoother upgrade for direct CLI callers at the cost of keeping the
dangerous default in the position you reach by accident. The decision record
required by R15 states this; the release note required by R16 warns the callers
who lose out.

## Considered Options

### Question A — Where does the automatic populate run?

- **A1: End of the Phase 4 jury only.** Populate after the jury's findings are
  resolved, before the approval walkthrough. Satisfies D5: the author reviews a
  populated document. But `/roadmap activate <path>` (input mode 2) can be
  invoked later, standalone, on a roadmap this run never touched — a roadmap
  authored before this change, or one whose Features section was edited during
  review. Those activate with empty sections, which is the original defect.
- **A2: On the `Draft -> Active` transition only.** Covers the standalone
  activate path and guarantees that anything leaving Draft is populated. But it
  violates D5: the approval walkthrough in Phase 4 happens *before* the
  transition, so the author would review an empty skeleton and only get the
  filled sections after saying yes.
- **A3: Both.** Populate after the jury resolves and again on the activate
  path. **Chosen.** The two points cover different entry paths rather than
  duplicating each other: the Phase 4 point serves D5, the activate point is
  the backstop for roadmaps that reach activation by another route. The cost of
  the overlap is one redundant run in the common case, and populate is
  idempotent — `rerun_is_idempotent` and `issueless_rerun_is_idempotent` in
  `crates/shirabe/tests/populate_cli.rs` both assert it — so the redundant run
  is a no-op on content. The feature list locks when the roadmap leaves Draft,
  which means the activate-time run is also the last moment the sections can be
  brought into agreement with a Features section edited during review.

### Question B — What does the separate issue-filing action look like?

- **B1: A new input mode** (e.g. `/roadmap file-issues <path>`). A distinct
  verb reads clearly and cannot be confused with the automatic run. But it
  leaves two input modes that do nearly the same thing — the new verb and the
  existing `populate` — and every document describing populate would have to
  explain which one to use when. Against D4.
- **B2: Retain `/roadmap populate <path>` and give it `--issues`.** **Chosen.**
  Input mode 3 already exists, already documents the invocation, and already
  carries the R14 approval gate in exactly the right place. After this change
  its remaining reason to exist *is* issue filing: the issueless render now
  happens automatically, so a human typing `populate` is almost always asking
  for issues. The mode still resolves on the stack rather than being hardcoded,
  so a repo that wants the old manual-issueless workflow keeps it. The
  post-approval issue-filing action is the explicit form `/roadmap populate
  <path> --issues`. No new mode, no second vocabulary, and the gate stays where
  it is — D3 and D4 both satisfied.

### Question C — How does the mode resolve?

The brief recommended the `flag > CLAUDE.md-header > default` stack and asked
for it to be confirmed against the code rather than taken on faith. Confirmed:
`skills/roadmap/SKILL.md:145-154` already reads `## Roadmap Issues:` "the same
way `## Execution Mode:` is read — grep the header, take the value after the
colon", and `references/fixes/claude-md-conventions.md:64` documents the header.
The validator never reads it; it is a skill-only preference. So the stack
exists and this change adjusts its bottom layer rather than inventing it.

- **C1: Keep the header fail-closed toward issue-creating.** Rejected. It
  contradicts D1 directly — the whole point is that the unspecified case should
  be the harmless one.
- **C2: Flag > header > issueless default.** **Chosen.** The per-invocation
  flag wins; absent a flag the `## Roadmap Issues:` header decides; absent both,
  issueless. Note the semantic inversion this forces: the header's resolution
  today "fail[s] closed toward the issue-creating, human-gated path", and after
  this change an absent header resolves to `optional`/issueless. `required`
  keeps meaning "this repo files issues for its roadmap features", but it now
  has to be said rather than assumed. The skill prose that documents the
  fail-closed direction changes with it.

One thing the stack does *not* govern: the automatic populate in Question A is
always issueless regardless of the header. R7 requires it, and the reason is
D3 — an automatic run must never create issues, so there is no mode for the
header to select there. The header governs only what a human-invoked
`/roadmap populate <path>` does when they pass no flag.

### Question D — What does `--issues --no-issues` do?

- **D-opt1: Last-wins.** Whatever clap resolves, silently. Rejected: the user
  finds out which half was ignored only by inspecting the result, and in this
  command the two outcomes differ by whether issues got filed.
- **D-opt2: Clear error.** **Chosen.** clap's derive API expresses this
  directly with `#[arg(long, conflicts_with = "no_issues")]`, which produces a
  non-zero exit and a message naming both flags before `run_inner` is ever
  called. That satisfies R4's "SHALL NOT mutate the roadmap and SHALL NOT call
  `gh`" for free — the conflict is detected during parsing, so no code with
  side effects runs. Using clap's own mechanism rather than a hand-rolled check
  in `run_inner` also keeps the error consistent with every other argument
  error the binary emits.

## Decision Outcome

Add `issues: bool` to `PopulateArgs` as `#[arg(long, conflicts_with =
"no_issues")]`. Invert the branch in `run_inner` so issueless is the fall-through
and the issue-creating path runs only when `args.issues` is set. Update the
`RoadmapCommands::Populate` doc comment in `main.rs`, which currently describes
issue creation as the default. Populate automatically at two points in
`skills/roadmap`, both issueless. Keep input mode 3 as the issue-filing action,
resolving its mode on the flag/header/issueless stack. Write the decision record
and the release note.

This keeps the subcommand's two render paths exactly as they are — neither
renderer changes — and moves only the question of which one runs.

## Solution Architecture

Components touched:

- **`crates/shirabe/src/populate.rs`.** The `PopulateArgs` struct gains
  `issues`. `run_inner`'s mode branch inverts. The four `PopulateArgs`
  constructions in unit tests gain the new field. The `no_issues_flag_parses`
  test grows a sibling for `--issues` and one for the conflict.
- **`crates/shirabe/src/main.rs`.** The `Populate` variant's doc comment, which
  is user-visible help text and currently states the old default.
- **`crates/shirabe/tests/populate_cli.rs`.** The 17 invocations that rely on
  the default gain `--issues`. The 7 `--no-issues` invocations are unchanged.
  New coverage for the conflict, for the unflagged run making no `gh` call, and
  for `--help` naming both flags.
- **`skills/roadmap/SKILL.md`.** Input mode 3's description, the "Populating
  the Issues Table" section's two-mode framing, the Invocation block (whose
  issue-creating example is the one in-repo invocation relying on the default),
  the options list, the R14 gate's mode conditions, and the Context Resolution
  paragraph describing the header's fail-closed direction.
- **`skills/roadmap/references/phases/phase-4-validate.md`.** The automatic
  populate step before the approval walkthrough, and the re-run on the activate
  path.
- **`skills/roadmap/references/roadmap-format.md`.** The Reserved Sections
  prose describing how the sections get filled and which marker each mode
  writes.
- **`references/fixes/claude-md-conventions.md`.** The `## Roadmap Issues:`
  entry, whose description states the current default.
- **`docs/decisions/`.** The new record superseding D5.
- **Release notes.** The breaking-change entry.

Explicitly not touched: `crates/shirabe-validate/src/checks.rs`, per R18. FC16
keeps its shape-gating. Neither `render_table`/`render_diagram` nor
`render_issueless_table`/`render_issueless_diagram` changes.

### Mode resolution, concretely

```
skill-side (roadmap SKILL.md, Context Resolution):
  --issues / --no-issues on /roadmap populate   -> that mode
  else `## Roadmap Issues: required`            -> issue-creating
  else `## Roadmap Issues: optional`            -> issueless
  else (header absent or unrecognized)          -> issueless

  automatic populate (Phase 4, activate)        -> issueless, unconditionally

CLI-side (populate subcommand), a backstop only:
  --issues                                      -> issue-creating
  --no-issues                                   -> issueless
  both                                          -> error, exit non-zero
  neither                                       -> issueless
```

The skill always passes one of `--issues` or `--no-issues`. The CLI's
"neither" row exists for humans, and per D2 nothing in this repository is
allowed to depend on it.

## Implementation Approach

Four batches, ordered so the suite stays green between them.

**Batch 1 — CLI surface.** Add the `issues` field with `conflicts_with`, invert
`run_inner`'s branch, update the `main.rs` doc comment and the `--no-issues`
doc comment (which says "Set by the roadmap skill when the repo declares `##
Roadmap Issues: optional`" and needs to reflect the new stack). Add the new
unit tests. At the end of this batch `cargo test -p shirabe --lib` passes and
the integration suite fails on the 17 default-relying tests, which is expected
and is the next batch.

**Batch 2 — Test callers.** Add `--issues` to the 17 invocations in
`populate_cli.rs` that relied on the default. These are updates, not deletions
— R17 — and the count of issue-creating-path tests must not drop. Add the three
new integration tests: the conflict case asserting a non-zero exit and an
unmodified roadmap file, the unflagged case asserting no `gh` call via the
existing PATH-injection harness, and the `--help` assertion. At the end of this
batch `cargo test --workspace` is green.

**Batch 3 — Skill and docs.** Update `skills/roadmap/SKILL.md` throughout, add
the automatic populate to `phase-4-validate.md` at both points, and correct
`roadmap-format.md` and `claude-md-conventions.md`. The Invocation block's
issue-creating example gains `--issues`, which closes the one in-repo
invocation that relied on the default. Then run the AC11 sweep: search
`skills/`, `docs/`, `references/`, and `crates/*/tests/` for populate
invocations and confirm every one names a mode.

**Batch 4 — Record-keeping.** The decision record under `docs/decisions/`
naming D5 and the blast-radius reasoning, and the release note describing what
a direct CLI caller must change. Then `shirabe validate` over the repo's own
docs.

### Blast radius, re-measured

The brief supplied figures measured at `d87a73b` and asked for them to be
verified rather than trusted. Re-measured on the same commit:

| Claim | Brief | Measured | Verdict |
|---|---|---|---|
| Skill invocations relying on the default | 1 | 1 (`SKILL.md:381-385`) | holds |
| `populate_cli.rs` invocations | 24 | 24 real (26 `.args([...])` call sites less `--help` at 122 and the not-found path at 453) | holds |
| ...of which pass `--no-issues` | 7 | 7 | holds |
| ...relying on the default | 17 | 17 | holds |
| `PopulateArgs` constructions in unit tests | 5 | **4** (lines 1641, 1713, 2210, 2278) | **differs** |
| Other mentions are prose, not invocations | yes | yes | holds |

The `PopulateArgs` discrepancy is a miscount in the brief, not a missing call
site: the fifth `PopulateArgs` occurrence at line 1600 is the `Probe` test
harness's field declaration (`args: PopulateArgs,`), which is a type
annotation rather than a struct literal and needs no new field.

## Security Considerations

The change reduces the subcommand's default privilege rather than widening it.
Before, an invocation with no flags reached `gh issue create` (once per
feature) and `gh repo view`; after, the same invocation constructs no
`Command` at all. There is no path by which the new default causes a network
call or a write outside the named roadmap file.

The conflict check runs during clap parsing, before `run_inner`, so a
conflicting invocation cannot partially apply — no `gh` call, no temp file, no
section replacement. This is why R4's guarantees fall out of `conflicts_with`
rather than needing their own enforcement.

The R14 approval gate does not move. It stays in the calling skill, still
guarding issue creation only, and after this change it guards a path that is
reached only by explicit `--issues`. A gate over an action that no longer
occurs on the automatic path is skipped, not bypassed: nothing gated happens.

Feature names and titles continue to reach `gh` as discrete
`Command::arg(...)` arguments with no shell, so the injection properties
documented in the skill's Security Guarantees section are unchanged. Nothing
in this change interpolates untrusted content into a shell string.

One residual risk worth naming: a user with a saved script that calls `shirabe
roadmap populate` unflagged and expects issues will silently get none. That is
the breaking change R16's release note exists to announce, and it fails in the
recoverable direction — the fix is to add `--issues` and re-run.

## Consequences

**Good.** The dangerous invocation now has to be typed deliberately. A
`/roadmap` run produces a complete roadmap without a second command, which
closes the hole that let empty reserved sections reach merged roadmaps. The
document an author approves is the document that lands. Both mode spellings are
explicit, so reading any in-repo invocation tells you what it does without
knowing the default.

**Bad.** Direct CLI callers with unflagged invocations get a silent behaviour
change — silent in the sense that nothing errors, though the summary JSON's
empty mapping does signal an issueless run. This is the cost D1 accepted, and
it is what the release note is for. The `## Roadmap Issues:` header's semantics
invert, so a reader who learned the old fail-closed direction has to relearn it;
the skill prose changes to match, but external notes may not.

**Neutral.** Two populate points instead of one means a redundant run in the
common path. Idempotence makes it free in content terms and cheap in time
terms, since the issueless path makes no network call.

**Deferred.** FC16 stays shape-gated, so an empty skeleton still validates
everywhere. This change makes the empty skeleton much rarer by populating
automatically, but it does not make it detectable. Teaching FC16 to be
status-gated — reject an empty skeleton on a non-Draft roadmap — would close
the hole rather than route around it, and it is a validator-surface change this
work is explicitly barred from making. Worth filing separately.

## References

- `docs/prds/PRD-populate-issueless-default.md` — the requirements this
  design implements.
- `docs/briefs/BRIEF-populate-issueless-default.md` — the framing and the four
  open questions settled above.
- `docs/designs/current/DESIGN-roadmap-issueless-preference.md` — introduced
  issueless mode and the `## Roadmap Issues:` header; its D5 is superseded here.
- `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md` — the
  sibling design that fixed the issueless table's rendering (#262).
- `skills/roadmap/references/roadmap-format.md` — Reserved Sections and the
  FC16 shape-gating.
- `references/fixes/claude-md-conventions.md` — the convention-header format.
