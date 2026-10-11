---
schema: design/v1
status: Current
problem: |
  /explore, /comp and /release keep their working state as staging-folder files
  whose existence and content their prose instructions branch on, /work-on's
  context script still has a file fallback, and four pieces of enforcement exist
  only because some skill might write the folder. The convention's shared script
  has no way to move a topic's sessions to another host in one call.
decision: |
  Each leaf skill opens its own <skill>-<topic> session and keeps its files as
  keys by the convention's mapping; every branch a skill used to decide from a
  file moves into a thin per-skill state script the prose calls by path and a
  test drives against real koto. /explore clears its working keys when it hands
  off so the consumer's close rule holds. skill-session.sh gains an import
  subcommand over fixed session sets. The enforcement layer is removed in a last
  pull request once every writer is gone.
rationale: |
  A per-skill script is the only place the resume, handoff-cleanup, jury-resume
  and membership rules can be tested on their real path, and it follows the
  /scope scripts' precedent; prose-only moves would leave those rules untested,
  and extracting code blocks from prose ties tests to layout. Clearing /explore's
  keys at handoff keeps the settled close rule instead of reopening it. Fixed
  session sets match what koto's import offers, since koto can't list another
  workspace's sessions.
upstream: docs/prds/PRD-leaf-skills-off-folder.md
user_visible_surface: false
decision_provenance: inline-resolved
---

# DESIGN: Leaf skills off the staging folder

## Status

Current

Built as described in four pull requests, in the grouping Decision 2 chose:
#754 (the shared import step and the convention fixes), #755 (/explore),
#756 (/comp, /release and /work-on's context script) and #759 (the
enforcement layer's removal, merged last). Two outcomes differ from the
text below. Rule `branch/no-wip-files` is retired rather than deleted from
the registry. And `references/parent-skill-pattern.md`'s `storage_substrate`
v1 value is now `koto-session`, with the parent's state at the `work/state.md`
session key.

## Context and Problem Statement

The requirements are in `docs/prds/PRD-leaf-skills-off-folder.md` (R1 to R19).
This design settles how they're built on top of the merged convention
(`references/skill-session-convention.md`, `scripts/skill-session.sh`,
`docs/designs/current/DESIGN-resume-convention.md`), which it follows and
doesn't change.

The technical shape of the problem differs per skill:

- **/explore** is prose. Its SKILL.md and six phase files tell the agent to
  write `explore_<topic>_{scope,findings,decisions,crystallize,decision-brief}.md`
  and one research file per lead and round, and its resume table picks a phase
  by testing which of those exist and whether the findings carry the
  `## Decision: Crystallize` marker. Research leads are background agents that
  write their own files. The handoff arm already writes `handoff/scope.md` or
  `handoff/charter.md` into `explore-<topic>`, and the consumers (/scope,
  /charter) remove it and close the session "when it holds nothing else".
- **/comp** is prose. It writes a scope file and three jury verdicts, decides
  its jury resume from how many verdict files exist, and reads a parent state
  file in setup that nothing writes: `children_of` in `skill-session.sh` lists
  only /scope's and /charter's children.
- **/release** is prose with bash blocks. Phase 1 computes the range, the pull
  requests in it and the unattributed commits into three files, because each
  phase runs in a new shell; Phases 2 and 3 read them; Phase 4 writes the notes
  to a file for `gh release create --notes-file`.
- **/work-on**'s `extract-context.sh` writes `IMPLEMENTATION_CONTEXT.md` when
  it has no session or no koto, though its only caller always passes a session.
- **The enforcement layer**: `node-push.sh` step 3 (`git rm` of the folder plus
  a commit) and its post-push `ls-tree` check; rule `branch/no-wip-files`
  (`check-branch-output.sh --wip`), gated as `branch_wip_clean` in
  `skills/work-on/koto-templates/work-on.md` and `settled_wip_clean` in
  `skills/execute/koto-templates/execute.md`, plus an instruction in
  `execute-coordinated.md`; /scope's `publish-scoping-pr.sh` untrack step,
  `wip_paths` listing and private-marker scan over staging files,
  `print-scope-exit.sh`'s `wip_paths=` line, and /deliver's relay of it in its
  template and `deliver-report.sh`.
- **Import**: `koto session import <name> --from <workspace>` moves one root
  session from the bucket; it needs the cloud backend, refuses with typed codes
  (`import_source_not_found` for an absent source), and treats a re-run of the
  same import as a retry. koto has no listing of another workspace's sessions.

## Decision Drivers

- **Real-path tests (R17).** A move counts only when a test drives the commands
  the skill runs and reads the result back from koto. Prose can't be driven, so
  every rule a test has to reach must live in code.
- **Keep the convention.** Naming, key areas, the close rule and the dispatch
  key are settled; a move that needs a different rule is a question, not an
  edit.
- **Small reviewable moves, main consistent after each merge.** Each pull
  request moves a writer together with every reader of its files.
- **The enforcement goes last.** It may be removed only once nothing writes the
  folder (R15).
- **Existing idiom.** Bash scripts with `_test.sh` suites against real koto in a
  store isolated by `KOTO_SESSIONS_BASE`, invoked by path, declared in each
  skill's `requires.tsv`, run by a per-skill CI workflow, like
  `skills/scope/scripts/`.
- **No new dependency.** Nothing beyond koto and its configured bucket.

## Considered Options

### Decision 1: Where each leaf skill's state logic lives

Delegated to /decision.

The prose skills decide their resume, their handoff cleanup and their jury
resume by looking at files. Once the files are keys, those decisions have to
be expressed somewhere a test can run them.

Key assumptions:

- A test may call a script's own write subcommands to create state and then
  assert with `koto context get`; that is the real path, not seeding.
- Phase prose can call a script by `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/scripts/...`
  path and keep a one-line statement of the rule beside the call, as /scope's
  `phase-resume.md` does for `resume-probe.sh`.

#### Chosen: A thin per-skill state script

Each moved skill gets one script holding only the logic that decides a branch
from session state or sequences several session operations:
`skills/explore/scripts/explore-state.sh`, `skills/comp/scripts/comp-state.sh`
and `skills/release/scripts/release-state.sh`, each with a `_test.sh` that runs
against real koto. Plain `open`, `put`, `get` and `close` calls that decide
nothing stay in the prose as direct `skill-session.sh` calls.

#### Alternatives Considered

- **Prose calls `skill-session.sh` directly, tested only through the shared
  script** (how the chain children moved): rejected because the five-row
  resume, the handoff cleanup, the jury resume and the membership rules would
  have no test of their own, which R17 requires. It suited the chain children
  because their branches are decided by /scope's template and scripts.
- **Tests extract bash blocks from the phase files** (as
  `skills/work-on/scripts/retry-clearing_test.sh` does): rejected because only
  /release has such blocks; /explore and /comp would have to be rewritten as
  code blocks anyway, and the tests would break on prose edits.

### Decision 2: How the changes group into pull requests

Resolved inline.

#### Chosen: Four node pull requests, the enforcement removal last

1. The shared pieces: the `import` subcommand and its tests, the session-set
   rows it reads, and the three corrections from tsukumogami/shirabe#747.
2. /explore's move.
3. /comp's and /release's moves and /work-on's fallback removal.
4. The enforcement layer's removal, depending on 2 and 3 (and on 1, so it is
   the last to land).

Groups 1, 2 and 3 are independent: none needs another's code, and their
edits to the convention reference touch different sections, so whichever lands
later merges main in once. Each move updates its own rows in the
convention's per-skill table, its `requires.tsv`, its CI workflow and the eval
scenarios that name its files.

#### Alternatives Considered

- **One pull request per skill** (/comp, /release and /work-on apart):
  rejected as three reviews of a few dozen lines each, with the same
  convention-table conflicts.
- **The enforcement removal folded into the last move**: rejected because R15
  wants it reviewable and revertible as its own change, landing only after
  every writer is gone.

### Decision 3: How the import subcommand maps koto's results onto a set

Resolved inline.

#### Chosen: Fixed sets, skip not-found, stop on anything else

`skill-session.sh import <set> <topic> --from <path>` walks a fixed name list
per set, calls `koto session import` once per name, skips
`import_source_not_found`, stops at any other refusal, and exits 3 when every
name was skipped. It's tested in CI against a stand-in `koto` on `PATH` that
returns koto's documented JSON and exit codes, with an opt-in case against a
real bucket.

#### Alternatives Considered

- **Discover the source's sessions by listing the bucket**: rejected because
  koto offers no listing of another workspace's sessions; proposed as a koto
  feature instead.
- **Treat any absent name as an error**: rejected because a chain rarely opens
  every session in its set, so the common case would fail.
- **Run an S3-compatible server in CI**: rejected as a heavy dependency for one
  subcommand; a local bucket for tests is proposed as a koto feature.

## Decision Outcome

/explore, /comp and /release become convention skills: each opens `<skill>-<topic>`, keeps
its files as `work/` and `research/` keys by the mapping, has its agents write
into scratch directories it ingests, and closes its own session when a direct
run finishes. Every rule the skill used to evaluate against files lives in a
thin state script, so the tests that prove each move run the same code the
prose calls. /explore's handoff arm clears its working keys after writing the
handoff, which keeps the consumers' existing close rule true; its other arms
close the session. /release keys its session on the repository's owner and name and
rewrites its keys on every run, since it never resumes. `skill-session.sh
import` moves a topic's sessions to another host over fixed sets. Once all of
that has merged, a last pull request removes the sweep, the leftover-files
rule, the publish step's staging handling and the `wip_paths` field.

## Solution Architecture

### Overview

```
prose phase file ──calls──> <skill>-state.sh ──calls──> skill-session.sh ──> koto
        │                         ▲                            ▲
        └── plain open/get/put/close ──────────────────────────┘
<skill>-state_test.sh ──drives──> <skill>-state.sh against real koto (KOTO_SESSIONS_BASE)
```

### /explore

Session `explore-<topic>`. Opened with `skill-session.sh open explore <topic>`
at the end of Phase 0, after the branch step (0.1) and before the first scope
write (0.2a): `open` records `session/branch`, so opening on `main` before the
branch exists would make every later attach refuse. A detached HEAD is refused
by `open`; /explore stops with its message.

| File today | Key in `explore-<topic>` |
|---|---|
| `explore_<t>_scope.md` | `work/scope.md` |
| `explore_<t>_findings.md` | `work/findings.md` |
| `explore_<t>_decisions.md` | `work/decisions.md` |
| `explore_<t>_crystallize.md` | `work/crystallize.md` |
| `explore_<t>_decision-brief.md` | `work/decision-brief.md` |
| research `explore_<t>_r<N>_lead-<name>.md` | `research/r<N>_lead-<name>.md` |

Documents the agent edits across rounds (scope, findings, decisions) are read
with `skill-session.sh get` into a scratch directory, edited there and written
back with `skill-session.sh put`.

`skills/explore/scripts/explore-state.sh`:

- `resume-phase <topic>`: prints the phase the key rows select, or `none`:
  `work/crystallize.md` present → `5`; `work/findings.md` holds a line equal to
  `## Decision: Crystallize` → `4`; `work/findings.md` present → `3`; any
  `research/r*_lead-*.md` and no findings → `3`; `work/scope.md` present → `2`;
  otherwise `none`, and the prose's branch rows (on the topic branch → Phase 1,
  else Phase 0) decide. An absent session reads as `none`. The per-phase resume
  checks in the phase files call the same subcommand rather than restating it.
- `ingest-leads <topic> <round> <dir>`: checks every entry in `<dir>` is a
  file named `r<round>_lead-<slug>.md` with a kebab-case slug; it prints
  `rejected=<name>` for any other and deletes it from `<dir>`, so the ingest
  that follows can't pick it up; then it runs `skill-session.sh ingest
  explore-<topic> research <dir>`. A lead whose name is refused is reported,
  not silently lost.
- `finish-handoff <topic>`: requires a non-empty `handoff/scope.md` or
  `handoff/charter.md`, then removes every key under `work/` and `research/`,
  leaving the handoff and `session/branch`. The consumers' rule (close
  `explore-<topic>` when it holds nothing but the handoff they remove and the
  convention's own `session/branch`, which is what it holds today) then closes
  the session.

The arms without a handoff (spike report, rejection record, file an issue,
deferred, execute, /decision, /comp) end with a plain `skill-session.sh close
explore-<topic> done`. In the /decision and /comp arms the close comes after
the inline child returns, because /decision reads the research keys while it
runs. A run that stops before Phase 5 closes nothing, so its keys stay for the
resume.

Research leads: before Phase 2 launches its agents, the orchestrator runs
`skill-session.sh scratch` once per round and pins each agent's output to
`<dir>/r<N>_lead-<name>.md`, in the generic prompt and in the adversarial
lead's embedded prompt alike; after collecting, it runs `ingest-leads`. No
agent runs koto. The handoff body carries the exploration's material itself:
its provenance names the rounds and leads that ran, as a description, and
points at no key, since `finish-handoff` removes them once the handoff is
written. The /decision brief's "Relevant Research" names them as
`koto context get explore-<topic> research/<name>` reads, since /decision runs
in its own session and reads them before /explore closes. The brief's commit
step goes: a key isn't committed.

`skills/explore/requires.tsv` declares `koto context add|get|exists|remove` and
`koto context list --prefix`, as the chain children's do.

### /comp

Session `comp-<topic>`, opened after Phase 0's visibility decision (so eval 8's
"warning before anything is created" still holds) and topic check, which
becomes the topic grammar `^[a-z0-9][a-z0-9-]*$`. Section 0.4 (the parent
state file) and the "Parent Orchestration" sentinel text are removed; the
stdout `[/comp] FINALIZED` and `WARNING` lines stay, since eval 8 asserts the
warning.

| File today | Key in `comp-<topic>` |
|---|---|
| `comp_<t>_scope.md` | `work/scope.md` |
| research `comp_<t>_phase4_<role>.md` | `research/phase4_<role>.md` |

Jurors write their verdicts into a scratch directory; the orchestrator ingests
it. `skills/comp/scripts/comp-state.sh`:

- `jury-resume <topic>`: counts the three `research/phase4_<role>.md` keys;
  prints `aggregate` when all three exist, otherwise removes any that exist and
  prints `fresh`, so a re-run never mixes old and new verdicts.

Phase 5's cleanup becomes `skill-session.sh close comp-<topic> done`; the grep
that keeps a staging path out of the COMP document stays. `requires.tsv`
declares the koto commands.

### /release

Session `release-<topic>`. `skills/release/scripts/release-state.sh`:

- `topic`: prints the topic from `gh repo view --json owner,name` as
  `<owner>-<name>`, lowercased, each run of characters outside `[a-z0-9]`
  turned into one `-`, leading and trailing `-` trimmed
  (`tsukumogami-shirabe`); refuses an empty result. The owner keeps two
  same-named repositories on one machine apart.
- `membership <topic>`: computes the range (`<last v* tag>..HEAD`, or `HEAD`),
  the pull request numbers from `(#N)` subjects and the unattributed commits,
  exactly as Phase 1's block does today, and writes them as `work/range`,
  `work/prs` and `work/unattributed` with `koto context add`, replacing any
  value an earlier run left, and removes any `work/notes.md` an earlier run
  left so a crashed run's notes can't be published. An empty list is an empty
  key (measured on koto 0.16.0: `add` replaces an existing key, and an empty
  value is kept and reads back empty).
- `read <topic> <range|prs|unattributed|notes>`: prints the key, or exits 1
  with "Phase 1 did not run" when it's absent.

The prose opens the session with `skill-session.sh open release "$(release-state.sh topic)"`
at the start of Phase 1, calls `membership` there and `read` in Phases 2 and 3,
and in Phase 4 writes the notes with `skill-session.sh put`, materializes them
with `skill-session.sh get` into a `scratch` directory for `gh release create
--notes-file`, and removes that directory when the command returns. It closes
with `skill-session.sh close`: `done` after Phase 4 or a dry run, `abandoned`
on an earlier stop. Because every run closes its session, a live
`release-<topic>` means an interrupted run; when `open` refuses it as
`branch_mismatch` (it was opened on another branch), /release stops and tells
the author to close it with `skill-session.sh close release-<topic> abandoned`
and run again. Phases 5 and
6 read nothing from the session. `requires.tsv` declares koto. The Error
Recovery table's two rows that point at files point at the keys.

### /work-on

`extract-context.sh` loses `store_context`'s file branch and the koto-missing
downgrade: without `--session`, or with no `koto` on `PATH`, it prints a
`failed` JSON with `context_available: false` and a warning naming koto. The
header, usage and JSON contract drop `context_file`.
`references/koto-context-conventions.md` drops its line about the folder.
/work-on itself already stops at its preflight when koto is missing or below
the floor; that is the recorded behavior for an unreachable koto.

### The import subcommand

`skill-session.sh import <set> <topic> --from <path>`:

| Set | Names, in order |
|---|---|
| `tactical` | `scope-`, `brief-`, `prd-`, `design-`, `plan-`, `explore-<topic>` |
| `strategic` | `charter-`, `vision-`, `strategy-`, `roadmap-`, `explore-<topic>` |
| `explore`, `comp`, `release` | `<set>-<topic>` |

Before any koto call it checks the set, the topic grammar and that `<path>` is
absolute (exit 64), and that `koto session import --help` succeeds (exit 69, or
127 when koto is absent). For each name it runs `koto session import <name>
--from <path>` and reads the JSON: exit 0 with `"imported": true` prints
`imported=<name>`; exit 2 with `error.code` `import_source_not_found` prints
`skipped=<name> reason=not-found`; any other code prints `failed=<name>
code=<code>`, output it can't parse prints `failed=<name> code=unparseable`,
and either exits 1 at once. Exit 3 when every name was skipped. koto's retry
branch makes a re-run after a partial import report the finished names as
imported, so the recovery from a stop is to fix the cause and run the same
command again; an import already marked at the source can't be undone, which
the usage text says. The codes are matched as
strings against koto's output and never placed on a command line. The
templates an import needs must already be compiled on the importing host
(`koto template compile`), which the subcommand's usage text says; it doesn't
compile them itself, since that would read template paths from the plugin
root it may not share with the source host.

`skill-session_test.sh` gains cases driving the subcommand against a stand-in
`koto` placed first on `PATH`, which records its arguments and returns scripted
JSON and exit codes per name; a further case runs against a real bucket only
when `SKILL_SESSION_IMPORT_FROM` names a source workspace, and is skipped
otherwise.

### Shared reference edits

- `scripts/skill-session.sh`: `KNOWN_SKILLS` gains `comp` and `release`, so
  `reclaimable` can answer for their sessions.
- `references/skill-session-convention.md`: per-skill rows for /explore's
  working keys, /comp and /release; a "Leaf skills" row in Session sets; the
  `import` subcommand in "Finding a session after an import"; the Closing
  section's carve-out sentence (R10).
- `references/parent-skill-security.md`: the Slot 7 example names
  `handoff/<child>.md` in `explore-<topic>`.
- `skills/charter/references/phases/phase-finalization.md`: each
  `<<ISSUE:5>>` becomes a citation of `references/parent-skill-state-schema.md`.

### Removing the enforcement layer

- `skills/execute/scripts/node-push.sh`: step 3 and the post-push `ls-tree`
  check go; the header's step list and exit 69's causes lose them;
  `node-push_test.sh` drops its folder case and keeps its push cases.
- `references/rule-registry.json` retires `branch/no-wip-files` (corrected
  2026-10-11 from "loses": the registry keeps every id it has held, so the
  entry stays with `status: retired` and must not be deleted);
  `check-branch-output.sh` loses `--wip` and `check_wip`; the
  `branch_wip_clean` gate in `work-on.md` and `settled_wip_clean` in
  `execute.md` go with their routing and directive prose; the instruction in
  `execute-coordinated.md` goes; the affected tests
  (`check-branch-output_test.sh`, `check-rule-registry_test.sh`,
  `execute-output-gates-routing_test.sh`, the template-structure tests) change
  with them.
- `skills/scope/scripts/publish-scoping-pr.sh` loses the untrack commit, the
  `wip_paths` listing and context key, and the private-marker scan over
  staging files; `print-scope-exit.sh` and `record-scope-exit.sh` lose
  `wip_paths`; /scope's SKILL.md Security Considerations drop the untrack item;
  the scope template stops passing the field.
- `skills/deliver/koto-templates/deliver.md` stops copying `wip_paths`;
  `deliver-report.sh` stops printing it; their tests change.
- `CLAUDE.md` Intermediate Storage says every skill keeps intermediate state in
  koto sessions; `references/wip-hygiene.md` keeps the rule that a committed
  document cites no staging path and loses the enforcement rows; the
  `check-work-on-scripts.yml` path filter on it stays, since the registry test
  still reads it.

What stays, deliberately: the upstream guards that refuse a staging path, the
finalize greps over durable documents, `check-public-content.sh`'s staging-path
class and its allow file, `check-template-directives.sh`'s rule that a /scope
gate reads no staging path, `drift-facts.sh` ignoring a folder reference, and
the coordinate skill's own hygiene test.

## Implementation Approach

### Phase 1: Shared pieces

The `import` subcommand and its stand-in and opt-in tests; the convention's
session-set rows; the three corrections from tsukumogami/shirabe#747. No skill
changes behavior.

### Phase 2: /explore

`explore-state.sh` and its test, the SKILL.md and phase-file rewrite, the lead
and adversarial-lead prompts, the handoff provenance and /decision brief, the
convention's /explore rows, `requires.tsv`, a CI workflow for the skill's
scripts, and evals 1, 4, 5, 6 and 7. Independent of Phase 1.

### Phase 3: /comp, /release and /work-on

`comp-state.sh` and `release-state.sh` with tests, the prose rewrites, the
convention rows, `requires.tsv` entries, CI workflows, comp eval 8, and the
`extract-context.sh` change with a test. Independent of Phase 1 and of
Phase 2.

### Phase 4: The enforcement layer

Everything under "Removing the enforcement layer". Depends on Phases 1, 2 and
3, and merges last. Its entry gate: on the combined heads of Phases 1 to 3, a
search of `skills`, `scripts` and `koto-templates` for staging-file paths
shows no line any skill or script follows to write or read a file, every
remaining hit being a guard, prose or a fixture; the pull request body lists
them.

## Security Considerations

- **Names reach koto.** Every session name is composed from a fixed skill name
  and a topic checked against the topic grammar before any koto call;
  /release's topic is derived from the repository name by a normalization that
  can only produce `[a-z0-9-]`, and the result is checked again by `open`.
  The import subcommand composes names from its fixed lists only.
- **koto's output re-enters the script.** The import subcommand reads koto's
  JSON with `jq` and compares `error.code` as a string; it prints the code but
  never evaluates or interpolates it into a command. `--from` is passed as one
  argument after the absolute-path check; koto only hashes it.
- **Templates on import.** The subcommand never passes `--trust-template`, so
  the importing host runs only templates it compiled itself from its own
  plugin copy, never one taken from the bucket.
- **Files agents write.** Lead agents and jurors write into scratch
  directories that `ingest` reads with its existing guards (regular files,
  plain names, size cap, no symlinks); `ingest-leads` adds a name check before
  it. Agents still run no koto command.
- **Release notes on disk.** The notes reach `gh release create` through a
  0700 scratch file outside the work tree that is removed when the command
  returns; today they sit in the branch's staging folder until cleanup.
- **What the publish step stops scanning.** /scope's publish step scans
  staging files in unpushed history for a `private/` path component or a
  `Repo Visibility: Private` line before it pushes. With no shirabe skill
  writing the folder, and /scope committing only the named `docs/` paths, it
  has nothing of shirabe's to scan. `check-public-content.sh` doesn't replace
  it: it refuses committed text naming a staging file, home paths, session
  identifiers and secret shapes, but has no private-marker class, and its
  denylist runs only when one is supplied. Once this scan goes, the
  private-marker class is checked nowhere before a push. The residual risk is a
  staging file
  that another tool committed to the branch, carrying private content, being
  pushed to a public repository by /scope's publish step. It is accepted here
  because nothing in shirabe produces such a file, and it is raised with the
  coordinator rather than kept as a guard for a folder no skill uses.
- **Scratch directories are trusted by their caller.** `ingest` and `get`
  accept any private directory outside the work tree, not only one `scratch`
  made. The new callers always pass the path `scratch` just printed in the same
  step, so they add no new way to name another directory; tightening `ingest`
  itself is convention work, proposed rather than done here.
- **Key content is data.** Research outputs, verdicts, findings and notes read
  back from keys are untrusted text; agents reading them keep the
  fixed-preamble discipline, and values reach commands only through `jq --arg`
  or as compared strings.
- **What leaves the host.** With koto's cloud backend configured, these keys
  sync to the bucket like every other skill's. /comp's analysis and an
  exploration of a private topic then sit in the bucket, which therefore needs
  the access control of the most private repository whose work it holds, as
  the convention already states; nothing secret belongs in a key.

## Consequences

### Positive

- No shirabe skill writes the staging folder, so a pull request carries only
  documents and nothing has to sweep or gate it.
- Every leaf skill's resume and cleanup rule has a test on its real path.
- A topic's sessions move hosts with one call.
- The /deliver and /scope reports lose a field that was always empty.

### Negative

- /explore, /comp and /release require koto, and three more scripts with
  tests and workflows exist to maintain.
- /explore's research keys are gone once a handoff is written.
- The import subcommand's CI coverage is a stand-in; real-bucket behavior is
  tested only where a bucket is configured.
- A branch that already carries staging files from older work is no longer
  refused by any gate.

### Mitigations

- The skills' preflights and `skill-session.sh open` already stop on a missing
  or too-old koto with a message naming it.
- The handoff carries what the next skill needs; anything worth keeping from
  research belongs in the handoff or a document.
- The stand-in returns koto's documented codes, and the subcommand's mapping is
  a table small enough to read whole.
- `check-public-content.sh` still refuses committed text naming a staging
  file, and the workspace rule stays until the coordinator retires it.
