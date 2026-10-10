---
schema: design/v1
status: Planned
problem: |
  /scope and /charter and the skills a chain runs keep their working state as
  files in the staging folder, and the folder is also their interface: a parent
  signals a child through a block in a file the child globs for, a parent
  detects a mid-flight child from its files, inline skills read each other's
  files, and /explore hands off through a file. /scope also keeps a koto
  session, so its runs live in two stores.
decision: |
  Each skill holds its state in its own root koto session, <skill>-<topic>,
  opened from its own template or one shared store template. Files map to keys
  mechanically (work/, research/), the parent-to-child signal is chain/dispatch
  in the parent's session answered by chain/parent in the child's, a parent
  detects a mid-flight child from a live session holding a work/ key and closes
  its children and then itself at exit, and finished-run facts come from koto's
  replaced result. A shared script and a normative reference carry it.
rationale: |
  Root sessions named from skill and topic are what koto's session import
  carries, so nothing rests on lineage, pointers or host files. A per-file
  mapping keeps every later skill move mechanical, the parent-owned dispatch key
  keeps the pattern's rule that a parent adds no input to a child, and landing
  both ends of each interface together keeps main consistent after each merge.
upstream: docs/prds/PRD-resume-convention.md
decision_provenance: inline-resolved
user_visible_surface: false
---

# DESIGN: One resume convention for skill state in koto sessions

## Status

Planned

## Context and Problem Statement

Eleven skills take part in a chain run today and every one of them keeps its
working state as files in the staging folder (`wip/`): `/scope` and
`/charter` keep a state file each (`scope_<topic>_state.md`,
`charter_<topic>_state.md`), and `/brief`,
`/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, `/review-plan`
and `/decision` keep context notes, discovery notes, coordination manifests,
issue bodies, research outputs and reviewer verdicts under the same folder.
Each skill's resume ladder decides where to continue by testing which of those
files exist. `/scope` is the one chain parent that also drives a koto session
(`scope-<topic>`, opened by `skills/scope/scripts/scope-open.sh`), so a `/scope`
run has two stores, and `docs/designs/current/DESIGN-scope-koto-adoption.md`
records that as a deliberate exception to the repository rule that koto-driven
workflows keep intermediate state in koto context.

The technical problem is that the folder is also the interface between skills.

- **The parent-to-child signal is a file.** `/scope` writes a
  `parent_orchestration:` block (`invoking_child`, `suppress_status_aware_prompt`,
  `rationale`) into its state file before each child; the children find it by
  reading the folder's `scope_<topic>_state.md` or `charter_<topic>_state.md`
  (`/design` globs `*_<topic>_state.md` there), and under it skip their push,
  pull request, branch creation, cleanup commit and routing prompt.
  `/charter` never writes the block, so its children run as if invoked
  directly.
- **A parent decides resume from its children's files.** `/scope`'s
  `resume-probe.sh` checks the folder for `plan_<topic>_*`,
  `design_<topic>_coordination.json`, `prd_<topic>_decisions.md` and
  `brief_<topic>_*` to tell that a child
  was mid-flight, and the `bail` state's gate runs `find wip` over the
  children's prefixes. `/charter`'s ladder does the same for `/vision`,
  `/strategy` and `/roadmap`, and it hands `/roadmap` a pre-populated scope file.
- **A skill run inline reads another skill's files.** `/review-plan` reads
  and, on loop-back, deletes `/plan`'s files; `/design` runs `/decision` with a
  `design_<topic>_decision_<N>` prefix whose report it then reads; `/plan`
  passes issue bodies to `skills/plan/scripts/create-issue.sh` by path.
- **Handoffs between entry points are files.** `/explore` leaves
  `scope_<topic>_handoff.md` or `charter_<topic>_handoff.md` in the folder, which the
  parents consume on entry.

What has to be decided is a convention that replaces each of those file
contracts with koto session context, stated once so later skills follow it.
The PRD (`docs/prds/PRD-resume-convention.md`) fixes the outer requirements,
carried here in its own words where each constrains a decision:

- Each skill under the convention holds its state in one session named
  `<skill>-<topic>`, composed from the skill name and the validated slug, never
  read back from stored state (R1). Sessions are roots: nothing a chain needs
  rests on `koto init --parent` lineage, the request store, or host files
  outside koto's store (R2), because koto's session import refuses a child as
  its source and carries no children.
- A staging-folder file `<skill>_<topic>_<rest>` becomes key `work/<rest>` in that
  session; a research file becomes `research/<rest>`; `chain/` holds what a
  parent writes for a child, `handoff/` what one skill leaves another, and
  `record/` and `legs/` are reserved for coordinator state (R3).
- Skills without a template open a session from one shared template that only
  holds keys (R4); a skill finds another's session by recomputing its name and
  reading its status read-only, and never resumes a finished session (R5).
- The signal becomes key `chain/dispatch` in the parent's session with fields
  `child`, `suppress_status_aware_prompt` and `rationale`; children check the
  two parents' sessions by name; a parent removes a stale key at start; a child
  that matched records `chain/parent` (R6).
- Every tick carries `--no-cleanup`; a chain child never closes its own
  session, the parent closes them after writing its `exit`, a direct run closes
  its own; a session is reclaimable when finished and its `chain/parent`, if
  any, names an absent or finished session (R7).
- The sessions named for a chain's topic hold everything it needs, so an
  import under the same names gives another host a resumable chain (R8).
- Content is assembled only in a private per-run directory outside the work
  tree, removed on every path (R9), and a moved skill stops when koto is
  missing rather than falling back to the folder (R10).
- `/scope`'s state moves into its session and its template stops reading the
  folder, with finished-run facts recovered from koto's replaced result (R11);
  `/charter` gets a session and writes the dispatch key (R12); the seven
  direct children, `/review-plan` and `/decision` move wholesale (R13, R14);
  `/explore`'s handoffs become keys (R15); parents detect a mid-flight child
  by a live session with a `work/` key (R16); the shared contract documents
  and other readers follow (R17, R18); a chain run writes nothing under the
  folder (R19).
- Shared scripts with tests carry the repeated operations (R20); the
  enforcement layer stays untouched (R21); this document is the reference,
  including which skills later work moves and the limits (R22); the scope
  adoption design's exception is closed with a dated note (R23); evals follow
  (R24); nothing private is committed (R25).

## Decision Drivers

- **Survives an import.** Whatever a chain needs must live in context keys of
  root sessions whose names derive from skill and topic alone, since import
  carries keys byte for byte and keeps the name, but carries no children,
  refuses a child as source, and leaves a request leg unbound.
- **Mechanical to apply.** Later work moves a dozen more skills one at a time;
  a rule that maps a skill's existing files to keys without redesign keeps each
  move small and reviewable.
- **Keeps today's contracts.** The children's behavior under a parent
  (keep verdict and status transition, skip publishing and routing) is settled
  by `docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`
  and must not change; only its carrier does.
- **Measured koto behavior, not assumed.** koto 0.15.0, measured for this
  design in an isolated store: a template with one non-terminal state stops
  there on its first tick; context add, get, list, exists and remove work on a
  live session and get and list keep working on a finished, kept one; a close
  without `--no-cleanup` deletes the session; `koto init --attach-live
  --replace-terminal` attaches to a live session (keys kept) when the template
  file name matches, replaces a finished one (keys gone, `replaced_result`
  printed), and refuses a template whose file name differs; `--from-stdin`
  can't be combined with either flag; `koto status` exits 2 for an absent
  session; a gate reads only its own session's context; each key operation
  costs about 12 ms.
- **Small scripts, existing idiom.** Shared code follows `scripts/koto-open.sh`
  and the bash-with-tests style of `skills/scope/scripts/`.
- **No half-migrated main.** The sentinel couples parent and child, so the
  order of changes must never leave a parent writing a key a child doesn't
  read, or a parent probing files a child no longer writes.

## Considered Options

### Decision 1: How a skill's session lives and ends

Delegated to /decision.

A child skill with no koto template of its own must hold its working keys
somewhere while it runs inside `/scope` or `/charter`, and the same code must
work when the skill runs directly. koto binds the choice: an import carries one
root session by name and refuses a child as its source; names are machine-wide;
a success terminal reached without `--no-cleanup` deletes the session; opening
with `--attach-live --replace-terminal` keeps a live session's keys and discards
a finished one's.

Key assumptions:

- The shared store template keeps one file name for the life of the plugin,
  because attach compares the template's file name.
- The only parents are `scope-<topic>` and `charter-<topic>`.
- A crash between a child's open and its first key write leaves an empty live
  session, which the next open attaches to.

#### Chosen: Each skill owns a root session; the parent closes the children it dispatched

Every skill, chained or direct, opens `<skill>-<topic>` from the shared store
template and writes only there. A chained child writes `chain/parent` as its
first key, naming the parent's session, so any session holding `work/` keys
also says who dispatched it; a direct run removes a `chain/parent` an earlier
chained run left. A chained child never closes its session. At its exit the
parent writes `exit` to its own state, then, for each child in its fixed child
list, closes `<child>-<topic>` when that session is live and its `chain/parent`
equals the parent's recomputed name, and closes itself last. Closing is
idempotent, so a parent that crashes between writing `exit` and the closes
finishes them on its next run, and a closed parent never leaves live children
behind. A direct run closes its own session when it finishes. Every tick
carries `--no-cleanup`, so a close keeps the session.

"At its exit" binds the paths that record an `exit:` value — full-run,
re-evaluation and abandonment-forced. A clean cancel, a refusal and an error
terminal record none, and deliberately close nothing: the children's live
sessions are what the next run's resume rows detect a mid-flight chain by, so
closing them there would erase exactly the state a cancelled run exists to
leave behind.

A session is reclaimable when it is finished and either has no `chain/parent`,
or its `chain/parent` string-equals `scope-<topic>` or `charter-<topic>` for its
own topic and that session is absent or finished. A malformed `chain/parent`
makes a session non-reclaimable; the value is compared, never interpolated.
This feature evaluates the rule; the later prune work deletes.

#### Alternatives Considered

- **A namespace inside the parent's session** (`scope-<topic>` holding
  `brief/...`): rejected because the child would need two key layouts, one
  chained and one direct, a replaced parent would take every child's keys with
  it, and a parent would have to know each child's internals.
- **koto child sessions through `koto init --parent`**: rejected because an
  import refuses a child as its source and carries no children, so a chain
  resting on lineage cannot move hosts.
- **Per-run stamped sessions found through a pointer key**: rejected because
  the session name would be read back from stored state, a crash could lose or
  dangle the pointer, and every import and prune would chase pointers.

### Decision 2: The parents' own state, and facts from a finished run

Delegated to /decision.

`/scope`'s state file is read by four scripts (`resume-probe.sh`,
`run-intake.sh`, and through it `resolve-intent.sh` and
`check-recorded-intent.sh`) and written by agent prose; `/charter`'s is prose
only. A later `/scope` invocation needs three facts from a finished run, its
intent, its exit and a failed publish step, and every terminal state's result
map already records them. koto prints that map as `replaced_result` when
`--replace-terminal` replaces the finished session.

Key assumptions:

- The result map of `/scope`'s terminal states reaches `replaced_result`
  intact; if a key is missing, no prior-run key is written and the probe falls
  through to its artifact rows.
- The publish retry needs only exit, intent and the failed step.
- `done_refused` happens before any state is written, so replacing it loses
  nothing.

#### Chosen: One document key, finished-run facts from the replaced result

The state file becomes key `work/state.md` in `scope-<topic>` and in
`charter-<topic>`, keeping its YAML shape, so the schema documents change only
where they name the path and how it is written. Scripts compose the session
name from the validated topic, read the key once with `koto context get`, and
feed the existing field readers from that value, re-validating every field
against its closed set as today. `resolve-intent.sh` and
`check-recorded-intent.sh` take `--session <name>` instead of `--state-file`.

When `scope-open.sh` replaces a finished session, it parses `replaced_result`
with `jq`, keeps only values that match closed patterns (`outcome`, `exit`,
`intent`, `step` in `{scope:push, scope:pr-create}`) and writes them as key
`work/prior-run.md` in the new session before anything else. The probe's
publish-retry rows and the intent scripts read that key. A successful publish
and the run's cleanup remove it, so it can't fire twice.

#### Alternatives Considered

- **One key per field**: rejected because about 35 keys, with nested and list
  fields still needing fragments, would lose single-write updates and rewrite
  every schema reference, test and eval, while scripts read only about 11
  scalar fields.
- **Template variables and context assignments**: rejected because koto fixes
  variables at init and assignments write small literals, so evolving state
  can't live there.
- **Read the finished session's keys before replacing it**: rejected because
  the read-destroy-copy sequence has the same crash window, revives a whole
  in-flight document from a destroyed run, and copies a stale `last_updated`.
- **A small durable file for finished-run facts**: rejected as the exception
  this work closes; the replaced result already carries what the retry reads.

Writing `work/prior-run.md` after the replace has a crash window of its own,
between koto's replace and the first key write. A crash there loses the
retry facts, and the probe falls through to its artifact rows: the run starts
fresh instead of retrying the publish, which costs a repeated step, not
corrupted state.

### Decision 3: Where the dispatch signal lives

Resolved inline.

#### Chosen: `chain/dispatch` in the parent's own session

The parent writes the key immediately before invoking a child, removes it
immediately after the child returns, and removes any it finds at its own
start. The child reads `chain/dispatch` from `scope-<topic>` and
`charter-<topic>`, using the topic it was invoked on, and matches `child` to
its own name; an absent or finished parent session is no match, and two
matches stop the child with an error naming both. The value is three YAML
lines: `child`, `suppress_status_aware_prompt` and `rationale`, the same
fields `parent_orchestration:` carries today. Everything that changes in a
child's behavior under the signal stays as
`references/fixes/sub-agent-dispatch.md` states it; only the carrier moves.

#### Alternatives Considered

- **The parent writes the key into the child's session**: rejected because
  the parent would open the child's session itself, coupling it to the child's
  template, and a key a crashed parent left would sit where a later direct run
  reads it with no parent to clear it.
- **A flag or environment variable on the child**: rejected by the pattern's
  rule that a parent adds no input of its own invention to a child; `/charter`'s
  unread `--parent-orchestrated` marker shows how that fails.
- **A koto request leg per child**: rejected because the request store is
  host-local and a leg arrives unbound after an import.

### Decision 4: Key naming and the file-to-key mapping

Resolved inline.

#### Chosen: One key per file, by a mechanical mapping

A skill's file `<skill>_<topic>_<rest>` becomes `work/<rest>` in
`<skill>-<topic>`, and a research or verdict file of the same shape becomes
`research/<rest>`. `chain/` holds what passes between a parent and its child
(`chain/dispatch` and `chain/roadmap-scope` written by the parent,
`chain/parent` by the child); `handoff/` holds what one skill leaves for
another's entry (`handoff/scope.md`, `handoff/charter.md`); `record/` and
`legs/` are reserved for coordinator state. A skill run inside another
skill's session writes under a sub-area there: `/decision` run by `/design`
writes `work/decision-<N>/<rest>` in `design-<topic>`. A `<rest>` koto's key
grammar refuses has each character outside `[A-Za-z0-9._-]` replaced by `-`,
and an `x` prefixed to any component that doesn't start with a letter or
digit; no current file needs it.

Sub-agents never write keys. The orchestrator allocates a private directory
outside the work tree, the agent writes its file there under the pinned name,
and the orchestrator ingests the directory as `research/<name>` keys and
removes it. A key-held document an agent edits in place is materialized into
such a directory, edited, and put back.

#### Alternatives Considered

- **One structured document per skill**: rejected because parallel agents would
  race on one key and every resume check would parse a document instead of
  testing for a key.
- **Keys redesigned per phase for each skill**: rejected because a dozen later
  moves would each re-argue naming.
- **Sub-agents calling `koto context add` themselves**: rejected because it
  widens reviewer agents' tool surface past Read and Write, which their prompts
  restrict to limit what injected text in a document can reach.

### Decision 5: The order changes land in

Resolved inline.

#### Chosen: Land by contract, both ends of an interface together

Each change moves the writer and every reader of one interface, so main is
consistent after each merge: the shared code first, then the dispatch key in
both parents and all children at once, then each chain's children with the
readers of their files, then the exploration handoffs, then each parent's own
state. The Implementation Approach gives the order.

#### Alternatives Considered

- **One change per skill**: rejected because it splits coupled pairs across
  merges, leaving a parent probing files a child no longer writes.
- **A transition where children read both the key and the file**: rejected as
  a workaround to remove again later, with a doubled test matrix, when the
  plugin ships both ends together.
- **One change for the whole feature**: rejected as too large to review with
  care.

## Decision Outcome

The five answers make one convention. Every skill that keeps intermediate state
holds it in its own root session, `<skill>-<topic>`, opened from its own
template (`/scope`) or the shared store template (everyone else). Its files
become `work/` and `research/` keys by a fixed mapping, so a resume ladder's
"file exists" rows become "key exists" rows one for one. A parent tells a
child it runs under a chain through `chain/dispatch` in the parent's session,
and the child answers by writing `chain/parent` in its own. A parent learns a
child was mid-flight from a live child session holding a `work/` key, and
closes its children, then itself, at exit. Finished-run facts travel in koto's
result, not in a surviving file. Because every name is recomputed from a skill
and a topic and nothing rests on lineage, importing a chain's sessions under
their own names gives another host everything the chain needs.

The convention gives the skills three things they don't have today: one store
per run, no file shared between skills at a known path, and a pull request
that carries only documents. It doesn't yet give them a second host: a skill's
state is local to the host that ran it until session import is applied to
skill sessions, where the pushed branch used to carry it. A replacement on
another host reaches nothing of a skill's state through koto today either, so
the regression is accepted.

## Solution Architecture

### Overview

A shared script, `scripts/skill-session.sh`, owns every operation the
convention repeats, and a shared template, `koto-templates/skill-session.md`
at the plugin root, gives template-less skills a session to hold keys. The
normative statement of the convention lives in `references/skill-session-convention.md`,
which every moved skill cites at the point it opens, reads or closes a session,
the way skills cite `references/koto-session-retention.md` today. Skills change
in their prose and scripts only: each file read or write becomes a
`skill-session.sh` or `koto context` call against the skill's own session.

### The convention, rule by rule

This is the part later skill moves cite. `references/skill-session-convention.md`
restates it as the normative reference.

**Session naming.** A skill's session is `<skill>-<topic>`: the skill's
directory name, a hyphen, and a topic that has passed `^[a-z0-9][a-z0-9-]*$`.
It is recomputed at every use and never read back from a key. Every session is
a root; no skill passes `--parent`. A skill opens its own session at its first
phase, from its own koto template if it has one and from
`koto-templates/skill-session.md` otherwise.

**Key naming.** A staging-folder file `<skill>_<topic>_<rest>` becomes
`work/<rest>`, and one in the folder's `research/` directory becomes
`research/<rest>`, with `<rest>` kept byte for byte. The areas are fixed:
`work/` and `research/` belong to the session's own skill; `chain/` carries
what passes between a parent and a child (`chain/dispatch`,
`chain/roadmap-scope`, `chain/parent`); `handoff/` carries what one skill
leaves for another's entry; `session/` holds the convention's own bookkeeping
(`session/branch`, below); `record/` and `legs/` are reserved for
coordinator state. A name koto's grammar refuses is renamed as Decision 4
says.

**Finding a session by name, on one host.** A reader recomputes the name and
runs `skill-session.sh status`, which reports `absent`, `live` or `finished`
without advancing anything. A reader may read a finished session's keys but
never resumes it; the next open of that name replaces it. Because session names
are machine-wide, `open` writes `session/branch` (the current git branch, which
git allows in only one worktree of a clone) and every cross-session read that
acts on what it finds (`dispatch read`, `close-children`, `has-work` from a
parent) compares it with the reader's own branch and treats a mismatch as
absent. koto's own `--attach-live` already refuses a session opened from
another worktree.

**Finding a session after an import.** An import keeps the session name
(unless `--as` is given) and carries every key byte for byte, and the branch
name means the same on the new host. Importing every session in a chain's set
(the table under Key Interfaces) under its own name therefore gives the second
host a resumable chain with no rewrite. An import under another name breaks the
lookup and is outside the convention. Nothing in a chain may rest on koto
parent-child lineage, the request store, or a request leg, since an import
carries none of them.

**The dispatch key.** Described in Decision 3 and in Key Interfaces below.

**Closing, and the reclaimable rule.** Described in Decision 1. A consumer of
a handoff closes the `explore-<topic>` session once it has removed the handoff
key and the session holds no other key.

**The reserved coordinator namespace.** Under Key Interfaces below.

**Limits.** A skill's state is local to its host until session import is
applied to skill sessions; until then a replacement on another host reaches
none of it, as it reaches none of it through koto today. And no chain may rest
on koto parent-child lineage, since an import neither carries children nor
accepts a child as its source.

**The staging-folder allowlist.** The plan's per-group grep criteria
(`git grep -n 'wip/'` over a moved skill) pass only lines of these kinds,
which is the allowlist those criteria cite:

- prose stating the folder is not used, or describing this move away from it;
- hygiene-rule statements over committed documents: an `--upstream` value
  rejected under the folder, the no-staging-paths checks a reviewer or a
  finalize step runs over a durable artifact, and the rule text those checks
  cite;
- `/scope`'s publish untrack step and its tests, untouched until the
  enforcement layer goes with later work;
- the `/explore` handoff and `/charter`'s own state file, wherever a moved
  skill's prose or evals describe them, until their own groups move them.

Everything else — a path a skill reads or writes for its working, research
or verdict state — is gone from the moved skills.

### Per-skill keys

Each moved skill's current files and the keys they become. `<N>`, `<role>`
and `<id>` are the same placeholders the skills use today.

| Skill | Files today (in the staging folder) | Keys, in `<skill>-<topic>` |
|-------|--------------------------------------|----------------------------|
| `/scope` | `scope_<t>_state.md` | `work/state.md`; `work/prior-run.md` after a replace |
| `/charter` | `charter_<t>_state.md`; `roadmap_<t>_scope.md` it pre-populates | `work/state.md`; `chain/roadmap-scope` |
| `/brief` | `_context.md`, `_discover.md`; `research/…_phase4_<role>.md` | `work/context.md`, `work/discover.md`; `research/phase4_<role>.md` |
| `/prd` | `_scope.md`, `_decisions.md`; `research/…_phase2_<role>.md`, `_phase4_<role>.md` | `work/scope.md`, `work/decisions.md`; `research/phase2_<role>.md`, `research/phase4_<role>.md` |
| `/design` | `_summary.md`, `_decisions.md`, `_coordination.json`, `_decision_<N>_report.md`; `research/…_phase5_*`, `_phase6_*` | `work/summary.md`, `work/decisions.md`, `work/coordination.json`, `work/decision_<N>_report.md`; `research/phase5_*`, `research/phase6_*` |
| `/decision` (run by `/design`) | `design_<t>_decision_<N>_{context,research,alternatives,bakeoff_<k>,examination}.md` | `work/decision-<N>/{context,research,alternatives,bakeoff_<k>,examination}.md` in `design-<topic>` |
| `/decision` (direct) | `<prefix>_{context,…,report}.md` | `work/<file>` in `decision-<topic>` |
| `/plan` | `_analysis.md`, `_milestones.md`, `_decomposition.md`, `_dependencies.md`, `_decisions.md`, `_manifest.json`, `_mapping.json`, `_issue_<id>_body.md` | `work/` plus the same name each |
| `/review-plan` | `plan_<t>_review.md`, `plan_<t>_review_loopback.md` | `work/review.md`, `work/review_loopback.md` in `plan-<topic>` |
| `/vision` | `_scope.md`, `_decisions.md`; `research/…_phase2_*`, `_phase4_*` | `work/scope.md`, `work/decisions.md`; `research/phase2_*`, `research/phase4_*` |
| `/strategy` | `_context.md`, `_discover.md`; `research/…_phase4_*` | `work/context.md`, `work/discover.md`; `research/phase4_*` |
| `/roadmap` | `_scope.md`; `research/…_phase2_*`, `_phase4_*` | `work/scope.md`; `research/phase2_*`, `research/phase4_*` |
| `/explore` (handoff only) | `scope_<t>_handoff.md`, `charter_<t>_handoff.md` | `handoff/scope.md`, `handoff/charter.md` in `explore-<topic>` |

`/review-plan` run directly on a topic with no `plan-<topic>` session reviews
the PLAN document alone, opens `plan-<topic>` to write its verdict, and closes
it when it finishes, since it opened it.

### Components

- **`koto-templates/skill-session.md`.** One non-terminal state, `open`,
  accepting `close: done | abandoned`, with conditional transitions to the
  terminal states `done` and `abandoned`. Its first tick stops at `open`. Its
  file name is fixed: attach compares it.
- **`scripts/skill-session.sh`.** Subcommands, each validating its inputs
  before any koto call:
  - `name <skill> <topic>`: prints `<skill>-<topic>` after checking the skill
    against `^[a-z][a-z-]*$` and the topic against `^[a-z0-9][a-z0-9-]*$`.
  - `open <skill> <topic>`: runs `scripts/assert-koto-floor.sh`, then opens the
    session from the store template through `scripts/koto-open.sh` with
    `--attach-live --replace-terminal`, ticks once with `--no-cleanup`, writes
    `session/branch` on a new or replaced session, and prints `session=` and
    `opened=new|attached|replaced`. An attached session whose `session/branch`
    differs from the current branch is refused.
  - `status <session>`: prints `absent`, `live` or `finished` from `koto
    status`, read-only (exit 2 with "not found" is absent; any other failure
    exits nonzero as cannot-tell).
  - `has-work <skill> <topic>`: true when the session is live and lists a key
    under `work/`.
  - `close <session> <done|abandoned>`: ticks `koto next --no-cleanup` with the
    close evidence when the session is live from the store template; a
    finished session is left alone.
  - `dispatch write <parent> <topic> <child> <rationale> [--no-suppress]`,
    `dispatch read <child> <topic>` (prints the matching parent session or
    nothing; exits 3 on two matches), `dispatch clear <parent> <topic>`.
  - `adopt <child> <topic>`: called by a child at start; writes or removes
    `chain/parent` according to `dispatch read`.
  - `close-children <parent> <topic> <done|abandoned>`: closes each child in
    the parent's fixed list whose session is live, whose `chain/parent` names
    this parent and whose `session/branch` matches the current branch,
    re-reading both immediately before the close tick.
  - `scratch`: allocates a private directory outside the work tree (through
    `scripts/koto-open.sh --alloc-dir`) and prints its path.
  - `ingest <session> <area> <dir>`: adds each regular, non-symlink file
    directly in `<dir>` whose name matches `^[A-Za-z0-9][A-Za-z0-9._-]*$` and
    whose size is under 1 MiB as key `<area>/<name>`, reports anything it
    skipped, then removes `<dir>`, on success and on failure alike. A file
    sub-agents wrote is never followed through a link.
  - `get <session> <key> <dir>` / `put <session> <key> <file>`: materialize a
    key into a scratch directory and write a file back, for documents an agent
    edits in place. Both refuse a key outside the session's own `work/` and
    `research/` areas, a key or path containing `..`, and a path outside a
    scratch directory.
  - `reclaimable <session>`: evaluates the rule from Decision 1 and prints
    `yes` or `no`.
- **`scripts/skill-session_test.sh`.** Runs every subcommand against real koto
  in a store isolated by `KOTO_SESSIONS_BASE`, and skips the engine cases with
  exit 0 when koto is absent, as `scripts/koto-open_test.sh` does. It includes
  the parent-and-child case the PRD asks for. A new workflow,
  `.github/workflows/check-skill-session.yml`, installs koto, asserts the
  floor, and runs it, modelled on `check-koto-open.yml`.
- **`references/skill-session-convention.md`.** The normative rules: naming,
  the key areas and the mapping, the dispatch key, open and close, the
  reclaimable rule, the import rule, and the reserved coordinator areas.
- **`/scope`.** `scope-open.sh` writes `work/prior-run.md` after a replace;
  `resume-probe.sh`, `run-intake.sh`, `resolve-intent.sh` and
  `check-recorded-intent.sh` read `work/state.md` and `work/prior-run.md` from
  the session; the probe's child checks call `has-work`; the `bail` gate calls
  `skill-session.sh has-work` over the four children instead of `find`; the
  phase files write the dispatch key and close the children at exit; the
  cleanup phase removes `work/prior-run.md` instead of deleting files.
  `scripts/check-template-directives.sh` drops `resume-probe.sh` from its
  routing allowlist once the probe names no folder path, and flags any gate
  command naming `wip/`.
- **`/charter`.** Opens `charter-<topic>` at setup, keeps `work/state.md`,
  writes and clears `chain/dispatch` around each child, writes
  `chain/roadmap-scope` for `/roadmap` instead of pre-populating its scope
  file, checks its children with `has-work`, and closes children and itself
  at exit.
- **The children.** `/brief`, `/prd`, `/design`, `/plan`, `/vision`,
  `/strategy`, `/roadmap`, `/review-plan` and `/decision` call `open` and
  `adopt` at their first phase, map each file to its key, ingest their
  agents' outputs, check keys in their resume tables, and close their own
  session at the end of a direct run. `/design`'s sentinel-gated PRD
  transition reads `dispatch read`. `/review-plan` names its files with
  `/plan`'s prefix today, so by the mapping it reads and writes `/plan`'s
  session, `plan-<topic>`, and on loop-back removes `/plan`'s keys there;
  run directly on a topic with no `plan-<topic>` session, it reviews the
  PLAN alone, opens `plan-<topic>` to write its verdict, and closes it
  when it finishes, since it opened it (the Per-skill keys table above
  says the same). `/plan` materializes
  issue bodies into a scratch directory for `create-issue.sh` and
  `create-issues-batch.sh`, whose interfaces are unchanged.
- **`/explore`.** Its handoff step opens `explore-<topic>` and writes
  `handoff/scope.md` or `handoff/charter.md`; nothing else in `/explore`
  changes. The parents read the handoff by name and remove it once consumed.
- **Shared contract documents.** `references/parent-skill-pattern.md`,
  `references/parent-skill-state-schema.md`, `references/parent-skill-security.md`,
  `references/parent-skill-resume-ladder-template.md` and
  `references/fixes/sub-agent-dispatch.md` describe the dispatch key and the
  parent's session state in place of the block at a path; the stale-sentinel
  self-heal becomes "remove `chain/dispatch` at start".

### Key Interfaces

The dispatch value:

```yaml
child: design
suppress_status_aware_prompt: true
rationale: fresh-chain
```

`child` is one of the parent's fixed children, `suppress_status_aware_prompt`
is `true` or `false`, and `rationale` is `fresh-chain` or `revise`. A reader
re-validates each field against those sets and treats any other value as no
match.

The session names a chain uses, which are also the set an import moves:

| Chain | Parent | Children (and inline skills) | Handoff |
|-------|--------|------------------------------|---------|
| tactical | `scope-<topic>` | `brief-`, `prd-`, `design-`, `plan-<topic>`; `/decision` inside `design-<topic>`, `/review-plan` inside `plan-<topic>` | `explore-<topic>` |
| strategic | `charter-<topic>` | `vision-`, `strategy-`, `roadmap-<topic>` | `explore-<topic>` |

The reserved coordinator areas, for later coordinator work and written by no
skill this feature moves: a coordinator's own session keeps its stored set
under `record/` and each worker's result under `legs/<request-id>/<leg>`, so
an import carries both. Session names beginning `coordinate-` belong to the
coordinate skill.

### Data Flow

A `/scope` run, end to end:

1. `scope-open.sh` opens or attaches `scope-<topic>`; on a replace it writes
   `work/prior-run.md` from the replaced result.
2. Setup removes any `chain/dispatch` and writes `work/state.md`.
3. For each hop: `dispatch write`; invoke the child; the child runs `open`
   and `adopt` (writing `chain/parent`), keeps its files as keys, and returns;
   `dispatch clear`; the hop's gate and commit run as today, on the durable
   document.
4. On resume, the probe reads `work/state.md` and checks each child with
   `has-work` to find a hop that was mid-flight.
5. At exit: write `exit` into `work/state.md`, publish, `close-children`,
   remove `work/prior-run.md`, and reach the template's terminal with
   `--no-cleanup`.

Nothing in that flow writes the staging folder, and the per-hop commits'
pathspecs already name only `docs/` paths.

## Implementation Approach

The order follows Decision 5: both ends of every interface land together.

### Phase 1: The convention's shared code

Deliverables: `koto-templates/skill-session.md`, `scripts/skill-session.sh`,
`scripts/skill-session_test.sh` (including the parent-and-child case, the
koto-absent and below-floor cases, and the status-read-is-read-only case),
`.github/workflows/check-skill-session.yml`, and
`references/skill-session-convention.md`. No skill changes.

### Phase 2: The dispatch key

`/scope` writes and clears `chain/dispatch` and removes a stale one at setup;
`/charter` opens `charter-<topic>`, does the same around each child, and closes
its session at its current finalization (its state file stays for now); all
seven children decide whether they run under a chain with `dispatch read`
alone, opening no session yet; `/design`'s PRD transition reads it. The five
shared contract documents change here. Depends on Phase 1.

### Phase 3: `/scope`'s children onto keys

`/brief`, `/prd`, `/design` (with `/decision`) and `/plan` (with
`/review-plan` and the issue-body hand-off) keep their files as keys and close
their own session on a direct run, with `open` and `adopt` arriving here
together with the file move; `/scope`'s probe child checks and `bail` gate move
to `has-work`, and `scripts/check-template-directives.sh` and its test change
with them, since the lint today admits a gate that reads the children's
prefixes; `/scope` closes its children at exit; their evals follow. Depends on
Phase 2.

### Phase 4: `/charter`'s children onto keys

`/vision`, `/strategy` and `/roadmap` the same way, with `open` and `adopt`;
`/charter`'s ladder rows
over their files move to `has-work`; `/roadmap` reads `chain/roadmap-scope`;
`/charter` closes its children at exit; evals follow. Depends on Phase 2.

### Phase 5: The exploration handoffs

`/explore` writes `handoff/scope.md` and `handoff/charter.md`; both parents
read and remove them and close `explore-<topic>` when it holds nothing else;
the scope template's directives that name the handoff file change here.
Depends on Phase 1.

### Phase 6: `/scope`'s own state

`work/state.md`, `work/prior-run.md` and the script changes from Decision 2,
the lint's routing allowlist losing `resume-probe.sh`, the cleanup phase, every
directive in `skills/scope/koto-templates/scope.md` that names the state file
(about a dozen, including the clean-cancel and discard instructions), the two
stale per-tick retention sentences there, the remaining scope evals, and the
dated note on `docs/designs/current/DESIGN-scope-koto-adoption.md`. Before this
phase starts, re-check every script in `skills/scope/scripts/` for a state-file
read; the research behind this design found four. Depends on Phases 3 and 5.

### Phase 7: `/charter`'s own state

`work/state.md` in `charter-<topic>`, its ladder rows 1 to 4, its finalization
closing itself, and its evals. Depends on Phases 4 and 5.

### What later work moves

| Moved here | Left for later work |
|------------|--------------------|
| `/scope`, `/charter`, `/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, `/review-plan`, `/decision`, `/explore`'s two handoffs | `/comp`, `/release`, `/explore`'s own working files, `/work-on`'s fallback file when koto is unreachable, and then the enforcement layer (`/execute`'s sweep in `node-push.sh`, the `wip_paths=` field in `/deliver`'s report, the per-repository CI check) |

`/review-plan` and `/decision` are leaf skills that move here because a chain
child runs them inline and they read or write that child's state; leaving
them would keep a chain run on the folder.

## Security Considerations

The convention moves where state lives; it adds no network access, no new
dependency and no new execution path. Four points need care, and the design
handles each:

- **Names reach koto commands.** Every session name is composed from a fixed
  skill name and a topic that has passed `^[a-z0-9][a-z0-9-]*$`, and is never
  read back from stored state. A `chain/parent` or `chain/dispatch` value read
  from a session is compared against a closed set and never interpolated into
  a command, so a tampered key can't redirect a close, a removal or a prune.
- **Stored values re-enter scripts.** `work/state.md` and `work/prior-run.md`
  are read into variables and every field is re-validated against its closed
  set before use, as `references/parent-skill-security.md` requires of the
  state file today; `scope-open.sh` keeps only `replaced_result` values that
  match closed patterns.
- **Temporary files.** Scratch directories come from `koto-open.sh
  --alloc-dir` (mode 0700, outside the work tree) and are removed on every
  exit path of the script that ingests them, so no content is left readable
  in the working tree or committed by a sweeping stage.
- **What leaves the host.** Intermediate state no longer travels in a pushed
  branch, so less reaches GitHub than today. With koto's cloud backend
  configured, session keys sync to the configured bucket, which already holds
  `/scope`'s and `/work-on`'s sessions; the convention adds content of the
  same kind.

- **Files sub-agents write.** `ingest` takes only regular, non-symlink files
  with plain names under a size cap, so an agent that writes a link to a host
  file can't get that file's content into a key, a cloud bucket or a later
  agent's context.
- **Same names from another worktree.** Session names are machine-wide.
  koto's `--attach-live` refuses a session opened from another worktree, and
  every cross-session read that acts on what it finds compares
  `session/branch`, so a run never takes another worktree's dispatch key or
  closes another worktree's children.
- **Forged keys.** A forged `chain/dispatch` can at most make a direct run of
  a child behave as a chain child (skip its push and routing prompt); a forged
  `chain/parent` can at most get a session closed early, and a closed session
  stays readable. Neither reaches a command line.
- **Key content is data.** Research outputs, handoffs and verdicts read back
  from keys are untrusted text, as the folder's files are today, and agents
  reading them keep the fixed-preamble discipline the reviewer prompts use.
  Values from keys reach commands only through `jq --arg` or as compared
  strings, never through `eval` or an unquoted expansion.
- **Retention.** Sessions are kept with `--no-cleanup` until the later prune
  work exists; nothing secret belongs in a key, and a cloud bucket holding
  them needs the same access control as the repositories whose work it holds.

The visibility checks on documents (`shirabe validate --visibility`, the
public-content check) are unchanged, and the public-content check still reads
every committed line. Session keys are outside those checks, which is why the
last point matters.

## Consequences

### Positive

- One store per run: a chain's position, its children's state and their
  hand-offs all live in sessions found by name.
- Scoping pull requests carry documents only; the untrack step finds nothing
  for the moved skills.
- `/charter`'s children finally learn they run under a chain, so they stop
  pushing and asking routing questions mid-chain.
- Later skill moves are mechanical: map each file to a key, rewrite the resume
  table, call `open` and `close`.
- The names an import needs are fixed now, before any import is applied.

### Negative

- A skill's state is host-local until session import is applied to skill
  sessions; the branch used to carry it.
- A reviewer no longer sees intermediate state at all.
- Every moved skill now requires koto; a host without it can run none of them.
- `/explore` keeps its own files in the folder while its handoff moves, a
  two-store split until later work moves it.
- A child run directly on a topic whose parent crashed mid-dispatch reads the
  stale key and behaves as a chain child until the parent's next start clears
  it.

### Mitigations

- The skills' preflight already checks the koto floor; `skill-session.sh open`
  checks it again and stops with a message naming koto.
- The reclaimable rule never frees a session a live parent may still read, so
  the later prune can't lose a chain's state; it should also keep a finished
  `scope-` or `charter-` session until its next run has consumed the replaced
  result.
- The stale-dispatch window is bounded by the parent's next start, and the
  child's `adopt` records which parent it matched, so the case is visible.
