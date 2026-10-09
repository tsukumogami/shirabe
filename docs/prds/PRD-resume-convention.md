---
schema: prd/v1
status: Accepted
problem: |
  /scope and /charter, and the skills they run, keep a run's working state as
  files in the branch's staging folder, and /scope keeps a koto session as
  well. The parent tells a child it runs under a chain through a block in a
  file the child finds by globbing that folder, and the scoping pull request
  carries every scratch file until a cleanup strips it. There is no written
  convention a skill can follow to keep its state in koto instead.
goals: |
  One written convention for keeping a skill's intermediate state in koto
  session context keys, applied to both chains and every skill a chain runs,
  so a chain run writes nothing under the staging folder, finds what it needs
  by session name, and publishes a pull request that holds only its documents.
absorbed:
  - docs/briefs/BRIEF-resume-convention.md
---

# PRD: One resume convention for the document chains

## Status

Accepted

Absorbed [BRIEF-resume-convention](docs/briefs/BRIEF-resume-convention.md); carried in Absorbed Brief.

## Absorbed Brief

Why this feature exists. The two document chains keep each run's working
state in two stores, files on the feature branch and, for `/scope`, a koto
session, and the parent signals a child through a file at a literal path.
That costs three people something: the author, whose resume depends on what
happens to be on disk; the reviewer, whose scoping pull request arrives with
scratch that has to be stripped before merge; and the contributor moving the
next skill, who has no written convention to follow. Because the signal
couples a parent to its children, the chains and their direct children move
together or not at all.

The outcome a user should experience: an author stops a chain anywhere and
re-invokes it, and it continues whatever the working tree holds; a chain
child still knows it runs under the chain, and the parent still learns what
the child did, without either reading a file the other left at a known path;
the scoping pull request holds only documents; and a contributor moves the
next skill by following one design. The convention's limit is stated up
front: until sessions are imported to another host, a skill's working state
stays on the host that ran it, where the branch used to carry it.

## Problem Statement

A `/scope` run passes through `/brief`, `/prd`, `/design` and `/plan`; a
`/charter` run passes through `/vision`, `/strategy` and `/roadmap`. Every one
of them keeps its working state as files named `<skill>_<topic>_*` in the
branch's staging folder, and its resume logic decides where to continue by
checking which of those files exist. `/scope` also drives a koto session, so
its run lives in two stores, which the scope adoption design recorded as a
deliberate exception to the repository's own rule that koto-driven workflows
keep intermediate state in koto context.

The parent and child are coupled through that folder. Before invoking a child,
`/scope` writes a `parent_orchestration:` block into its state file; the child
finds the block by globbing the folder for a parent state file and checking
which child it names, and suppresses its publishing steps when it is the one
named. `/charter` was meant to do the same and doesn't write the block at all,
so its children run as if invoked directly. A child also runs other skills
inline that write the folder: `/plan` runs `/review-plan`, which reads and
deletes `/plan`'s files, and `/design` runs `/decision` for its hardest
questions.

Three costs follow. An author's resume depends on which files are on disk, and
the folder and the session can disagree about where a run stopped. Every
scoping pull request carries scratch that a cleanup step has to untrack before
merge, with a sweep, a report field and a CI check existing only to catch what
the cleanup misses. And a contributor moving the next skill off the folder has
no convention to follow: `/work-on` keeps its state in context keys, but only
for itself, and nothing says how a parent and a child find each other's state
without a shared path.

## Goals

- A contributor can move any skill off the staging folder by following one
  written convention, without reading another skill's code.
- An author can interrupt a `/scope` or `/charter` run anywhere and resume it,
  and the resume reads koto sessions found by name, never the working tree.
- A scoping pull request holds the chain's documents and nothing intermediate.
- The convention stays valid when koto's session import moves a chain's
  sessions to another host, so the multi-host step later needs no new naming.

## User Stories

- As an author running `/scope`, I want to interrupt a run during the design
  hop, re-invoke `/scope <topic>`, and land back in the design hop with the
  design's working state intact, so that a crash costs me nothing I already
  did, and emptying the staging folder in between changes nothing.
- As an author running `/charter`, I want `/strategy` to skip its own push,
  pull request and routing prompt when the chain runs it, so that the chain,
  not the child, decides what happens next.
- As an author running `/prd` directly on a brief, outside any chain, I want
  it to behave as it does today (its prompts, its pull request) while keeping
  its working state in its own session, so that the move costs a direct user
  nothing.
- As a maintainer reviewing a scoping pull request, I want its file list to
  hold only the chain's documents, so that I review the feature and nobody
  strips scratch before merge.
- As a contributor moving a leaf skill such as `/comp` off the folder, I want
  one convention that says how sessions and keys are named and how a skill
  finds another's session, so that the move needs no reading of the chain
  code.
- As the author of later coordinator work, I want the session namespace fixed
  now, so that a coordinator's session and its workers' results land in names
  nothing else claims.
- As an operator moving a chain to another host once session import is
  applied to skill sessions, I want the chain's sessions to carry everything
  it needs under their own names. This story is satisfied by the design's
  naming rules only; no import is run by this feature.

## Requirements

Terms used below. A **session** is a koto session. A session's **status** is
one of three values: *absent* (koto reports no session of that name), *live*
(the session exists and its state is not terminal), or *finished* (its state
is terminal, cancelled included). To **close** a session is to advance it to
a terminal state with `--no-cleanup`, so koto keeps it. The **staging folder**
is the repository's `wip/` directory.

### The convention

- **R1. Session per skill and topic.** Each skill that keeps intermediate
  state under the convention holds it in one koto session named
  `<skill>-<topic>`: the skill's directory name, a hyphen, and the topic slug
  after it has passed the slug pattern `^[a-z0-9][a-z0-9-]*$`. The name is
  recomputed from those two values at every use and never read back from
  stored state for interpolation; an invalid slug is refused before any koto
  call.
- **R2. Root sessions only.** No session under the convention is created with
  `koto init --parent`, and nothing a chain needs to resume is held in koto
  parent-child lineage, the koto request store, or any host file other than
  koto's own session store.
- **R3. Key naming.** A skill's working file `wip/<skill>_<topic>_<rest>`
  becomes key `work/<rest>` in session `<skill>-<topic>`, and a research or
  verdict file `wip/research/<skill>_<topic>_<rest>` becomes key
  `research/<rest>`, keeping `<rest>` (extension included) byte for byte. A
  `<rest>` that koto's key grammar refuses (each `/`-separated component must
  start with a letter or digit and contain only letters, digits, `.`, `_` and
  `-`, at most 255 characters in all) is renamed by the design's stated rule,
  never by ad hoc choice. Keys a parent writes for a child live under
  `chain/`; keys one skill leaves for another skill to read on entry live
  under `handoff/`; `record/` and `legs/` are reserved for coordinator state
  and written by none of the skills this feature moves.
- **R4. A session for skills without a workflow template.** A skill with no
  koto template of its own opens its session from one shared template shipped
  with the plugin, whose only behavior is to hold keys until closed. Opening
  attaches to a live session of the same name and template and keeps its
  keys; opening over a finished session replaces it with a fresh one; opening
  over a live session from another worktree or another template is refused
  with koto's error and leaves that session untouched.
- **R5. Finding a session by name.** A skill finds another skill's session by
  recomputing its name and reading its status with a read-only koto command.
  It never advances, cancels or removes a session it did not open, and never
  resumes a finished one: a finished session's keys may be read, and a fresh
  run replaces it.
- **R6. The parent-to-child signal is a key.** Immediately before invoking a
  child, a parent writes key `chain/dispatch` in its own session, holding
  three fields: `child` (the child's skill name), `suppress_status_aware_prompt`
  (`true` or `false`) and `rationale` (`fresh-chain` or `revise`, the values
  today's `parent_orchestration:` block carries). Immediately after the child
  returns, whatever its outcome, the parent removes the key. A child decides
  it runs under a chain by reading `chain/dispatch` from `scope-<topic>` and
  `charter-<topic>` (the only parents), using the topic it was invoked on,
  and matching `child` to its own name; a parent session that is absent or
  finished, or a key naming another child, is no match. Two matches stop the
  child with an error naming both sessions. A parent removes any
  `chain/dispatch` in its own session when it starts, without prompting. A
  child that matched records the parent's session name as key `chain/parent`
  in its own session.
- **R7. Closing sessions.** Every `koto next` a skill issues on a session
  under the convention carries `--no-cleanup`. A child running under a parent
  never closes its own session. The parent closes every child session it
  dispatched after it has written its `exit` field to its own state keys, on
  every exit path; a skill run
  directly closes its own session when it finishes. A parent that crashes
  before closing leaves its children live, and its next run resumes against
  them. A session is reclaimable when it is finished and either has no
  `chain/parent` key or the session that key names is absent or finished; this
  feature evaluates the rule and deletes nothing.
- **R8. Surviving an import.** Everything a chain needs to resume is held in
  the sessions named `<skill>-<topic>` for the chain's parent, its children,
  and any `explore-<topic>` handoff, so importing those sessions under their
  own names gives a second host a resumable chain. An import under another
  name (`--as`) breaks the lookup, and the design says so.
- **R9. No shadow on disk.** Content assembled before it becomes a key,
  including the files reviewer and research agents write, is written only
  under a private directory created per run outside the working tree, and
  that directory is removed once its files are ingested and on every failure
  path of the script that ingests them.
- **R10. koto required.** A moved skill checks at start that koto at the
  plugin's minimum version (the floor `scripts/assert-koto-floor.sh`
  enforces) is reachable, and stops with a message naming koto
  if it isn't. It never falls back to the staging folder.

### The chains

- **R11. /scope holds its state in its session.** `/scope`'s state file
  becomes keys in `scope-<topic>`. Its koto template's commands that read the
  staging folder (the bail gate's `find` and the resume probe's file reads)
  read keys and child sessions instead. What a later invocation needs from a
  finished run (intent, exit, and a failed publish step) comes from the
  result koto hands back when the finished session is replaced, so nothing
  depends on a file outliving its run.
- **R12. /charter gets a session.** `/charter` opens `charter-<topic>` under
  R4, holds its state there, writes and removes `chain/dispatch` around each
  child (it writes no sentinel today), and hands `/roadmap` its pre-populated
  scope as key `chain/roadmap-scope` instead of a file.
- **R13. The direct children move wholesale.** `/brief`, `/prd`, `/design`,
  `/plan`, `/vision`, `/strategy` and `/roadmap` keep every working, research
  and verdict file they write today as a key in their own session, whether
  run under a chain or directly, and their resume logic checks keys. The
  design lists each file and its key.
- **R14. Skills a child runs inline move with it.** `/review-plan` (run by
  `/plan`, which it reads and partly deletes) and `/decision` (run by
  `/design` for critical questions) keep their state in keys, whether run
  under a chain or directly. `/review-plan` reads `/plan`'s keys from
  `plan-<topic>`; `/decision` under `/design` writes into `design-<topic>`
  under `work/decision-<N>/`, and run directly into `decision-<topic>`.
- **R15. Exploration handoffs are keys.** `/explore` writes the handoff it
  leaves for `/scope` or `/charter` as key `handoff/scope.md` or
  `handoff/charter.md` in `explore-<topic>`, and the parent reads it there by
  name. `/explore`'s other working files are not moved by this feature.
- **R16. A parent reads its children's state by name.** Wherever a parent's
  resume logic checks a child's files today to decide the child was
  mid-flight, it checks instead that the child's session is live and holds at
  least one key under `work/`.
- **R17. Shared contract documents follow.** `references/parent-skill-pattern.md`,
  `references/parent-skill-state-schema.md`,
  `references/parent-skill-security.md`,
  `references/parent-skill-resume-ladder-template.md` and
  `references/fixes/sub-agent-dispatch.md` describe the dispatch key, the
  parent's state in its session, and the start-of-run removal of a stale
  dispatch key, in place of the `parent_orchestration:` block at a path.
- **R18. Other readers follow.** Any script or skill outside the moved set
  that reads a moved skill's working files (for example `/plan`'s issue
  bodies handed to `skills/plan/scripts/create-issue.sh`) reads the key, or a
  file materialized from it under R9.
- **R19. Nothing under the folder.** A complete `/scope` or `/charter` run,
  including its children and the skills they run inline, creates no file
  under the staging folder, and the pull request it publishes adds no file
  outside `docs/`.

### Shared code, records and limits

- **R20. Shared scripts with tests.** The repeated operations (composing and
  validating a session name, opening and closing a session, reading a
  session's status, writing, reading and removing the dispatch key, ingesting
  a private directory's files as keys, and evaluating the reclaimable rule)
  live in shared scripts under `scripts/`, with tests that run against a koto
  store isolated by `KOTO_SESSIONS_BASE`.
- **R21. The enforcement layer stays.** `skills/execute/scripts/node-push.sh`'s
  sweep, the `wip_paths=` field `skills/deliver/scripts/deliver-report.sh`
  validates, the repository's CI check for a leftover staging folder, and
  `/scope`'s publish untrack step are not modified by this feature.
- **R22. The design is the reference.** One design document settles R1 to R10
  and lists which skills this feature moved and which later work moves
  (`/comp`, `/release`, `/explore`'s own files, `/work-on`'s fallback file),
  and states the limits: a replacement on another host reaches a skill's
  state only once session import is applied to skill sessions, and no chain
  may rest on koto parent-child lineage, since an import neither carries
  children nor accepts a child as its source.
- **R23. The recorded exception closes.** The scope adoption design gains a
  dated note saying its state-file exception is closed under this
  convention.
- **R24. Evals follow.** Every eval scenario and fixture of a moved skill
  that names a staging-folder path or the `parent_orchestration:` block is
  rewritten in terms of sessions and keys.
- **R25. Public content.** Nothing committed, and no pull request body or
  issue, names a private repository, a local path, or a session or instance
  name from a real run. A staging-folder path appears only in code and prose
  that remove the folder's use or describe the folder itself.

## Acceptance Criteria

The convention and its code:

- [ ] `docs/designs/DESIGN-resume-convention.md` (or its `current/` location)
      has one section each for session naming, key naming, finding a session
      by name, finding one after an import, the dispatch key, closing and the
      reclaimable rule, and the reserved coordinator keys, plus a table of
      moved skills and a table of skills left for later work, and a limits
      section stating both limits in R22.
- [ ] The shared scripts' tests run in CI and pass, with at least these
      cases: a valid slug composes `<skill>-<topic>` and an invalid slug
      (`Foo`, `a_b`, `../x`, empty) is refused with no koto call; open on an
      absent name creates, on a live same-template session attaches with keys
      kept, on a finished session replaces with old keys gone, and on a
      session from another template is refused with it untouched; status
      reports absent, live and finished; close leaves the session finished
      and readable; the dispatch key round-trips its three fields and is gone
      after removal; ingest turns every file in the private directory into a
      key and removes the directory, including when a key write fails; and
      the reclaimable rule returns the right answer for each of its four
      cases (live; finished with no parent; finished with a live parent;
      finished with a finished or absent parent).
- [ ] A test drives a parent and a child through the shared scripts against
      real koto: the parent writes `chain/dispatch` naming the child; the
      child detects it from `scope-<topic>` by name, records `chain/parent`
      and writes keys under `work/`; the parent reads those keys from the
      child's session by name and then closes it. The same test shows a stale
      key removed at parent start, a key naming another child not matched,
      and two matching parents refused.

The chains:

- [ ] `git grep -n 'wip/' -- skills/{scope,charter,brief,prd,design,plan,vision,strategy,roadmap,review-plan,decision}`
      returns only lines on the design's allowlist (prose stating the folder
      is not used, and `/scope`'s untouched publish untrack step and its
      tests); every other hit is gone, `evals/` and `scripts/` included.
- [ ] `skills/scope/koto-templates/scope.md` contains no command that reads
      the staging folder, `scripts/check-template-directives.sh` passes on
      it, and the template and script tests under `skills/scope` pass.
- [ ] `/scope`'s re-invocation tests show a replaced finished session's
      intent, exit and failed publish step reaching the new run from koto's
      replaced result.
- [ ] Each moved child's `SKILL.md` resume table has a row reading
      `chain/dispatch` by session name and no row naming a staging-folder
      path.
- [ ] `/charter`'s phase files write `chain/dispatch` before each child and
      remove it after, and `/vision`, `/strategy` and `/roadmap` each check it.
- [ ] `/explore` writes its scope and charter handoffs as keys, and `/scope`'s
      resume probe and `/charter`'s resume ladder read them by name.
- [ ] One eval scenario for `/scope` and one for `/charter`, chosen as those
      the change bears on, run once and pass; each asserts that after the
      run `git status --porcelain -- wip/` is empty and that every file the
      run committed is under `docs/`. The pull request body states which ran.
- [ ] `/scope`'s resume-probe tests include a run whose staging folder is
      empty and whose `design-<topic>` session is live with a key under
      `work/`: the probe routes back into the design hop. The same probe with
      the child session finished routes past it.
- [ ] A shared-script test with koto removed from `PATH`, and one with a koto
      below the floor, each stop with a message naming koto and create no file
      under the staging folder.
- [ ] `git grep -n -- '--parent'` over the moved skills' scripts and
      templates finds no `koto init` call with it, and a shared-script test
      shows a status read leaves the session's state log unchanged in length.
- [ ] The parent-and-child test closes the child only after the parent's
      `exit` key is written, and shows the child finished afterwards.
- [ ] The five shared contract documents in R17 describe the dispatch key and
      no longer describe a `parent_orchestration:` block at a path.

Records and limits:

- [ ] The scope adoption design carries a dated note closing its state-file
      exception.
- [ ] `git diff origin/main --stat` over the feature's pull requests shows no
      change to `skills/execute/scripts/node-push.sh`,
      `skills/deliver/scripts/deliver-report.sh`, or the CI workflow that
      checks for a leftover staging folder.
- [ ] `scripts/ablation/check-public-content.sh --diff origin/main` passes on
      every pull request of the feature.

## Out of Scope

- Moving `/comp`, `/release`, `/explore`'s own working files, and `/work-on`'s
  fallback file when koto is unreachable; later work does each on this
  convention.
- Removing the enforcement layer listed in R21.
- The coordinate skill's state handling and record; this feature only reserves
  its key areas.
- Any koto change. Where the convention needs something koto lacks, it is
  proposed to koto's maintainers instead.
- Applying session import to skill sessions or carrying them between hosts.
- Changing what a chain's documents contain or how many survive the
  consolidation judgment.

## Known Limitations

- Until session import is applied to skill sessions, a skill's intermediate
  state lives only on the host that ran it, where the pushed branch used to
  carry it. A replacement on another host reaches nothing of it through koto
  today either, so the regression is accepted.
- A reviewer of a scoping pull request no longer sees the chain's
  intermediate state at all; the per-hop record stays in the session, as the
  scope adoption design already accepted for its own record.
- Session names are machine-wide. Two worktrees running the same skill on the
  same topic collide, and koto refuses the second open as it already does for
  `/scope`; unique topic names remain the separation.
- A parent that crashes while a child runs leaves `chain/dispatch` in its
  live session. A run of that child made directly on the same topic before
  the parent restarts matches the stale key and behaves as a chain child; the
  parent's next start removes the key, and the design may narrow the window.
- `/explore` ends this feature with its handoff in a session and its other
  working files still in the folder, the two-store split this feature removes
  from the chains. Later work moves the rest of `/explore`.

## Decisions and Trade-offs

- **Grandchildren move with the chain.** `/review-plan` and `/decision` are
  leaf skills, but `/plan` and `/design` run them inside a chain and they
  read or write the child's files, so leaving them would keep the chain on the
  folder. They move wholesale rather than gaining a chain-only mode, since one
  code path is simpler than two. Alternative: leave them for later work and
  accept folder writes inside a chain, rejected because it fails R19.
- **The next hop needs the predecessor's document, not its scratch.** Each
  child already reads the durable document above it; what a parent needs from
  a child's session is whether the child was mid-flight and what it left, for
  resume. So "finding the predecessor by name" means the parent's resume and
  the handoff consumers read sessions by name; no hop reads another hop's
  working files. This settles what crosses hops.
- **Children never close their own sessions under a parent.** The parent
  closes them at its exit, mirroring today's split where the parent's cleanup
  removes the children's files. Alternative: each child closes its own session
  on return, rejected because a parent resuming after a crash, or folding one
  document into another, may still need the child's state.
- **Finished-run facts come from the result, not a surviving file.** A
  finished `/scope` session is replaced on the next run and its keys go with
  it; every terminal already records intent and exit in its result, and koto
  returns that result on replacement. Alternative: keep a small file, rejected
  as the exception this feature closes.
- **The exploration handoff moves now; the rest of `/explore` later.** The
  handoff is the chains' input, so it moves with them; `/explore`'s own files
  are a leaf concern.

## Downstream Artifacts

None yet.
