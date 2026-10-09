---
schema: brief/v1
status: Accepted
problem: |
  The two document chains, /scope and /charter, and the skills they run keep a
  run's working state as files on the feature branch, while /scope also keeps a
  koto session. Two stores for one run disagree, the parent signals a child
  through a file at a literal path, and every scoping pull request carries
  scratch files the cleanup has to strip before merge.
outcome: |
  An author runs a chain, stops, and resumes it, and the run picks up from koto
  sessions found by name, with nothing staged in the working tree and nothing
  intermediate in the pull request. A skill author moving the next skill has one
  written convention to follow instead of reverse-engineering /work-on.
---

# BRIEF: One resume convention for the document chains

## Status

Accepted

## Problem Statement

A run of `/scope` or `/charter` passes through several skills, and each of them
keeps its working state as files under the branch's staging folder: the parent's
state file, each child's context and discovery notes, research verdicts, the
handoff an exploration leaves behind. `/scope` also drives a koto
session, so its run lives in two stores, and the scope adoption design recorded
that as a deliberate exception rather than the intended shape. The repository's
own rule already says koto-driven workflows keep intermediate state in koto
context and never in the folder; the chains are the largest place that rule is
not yet true.

The cost lands on three people. The author running a chain gets a resume that
depends on which files happen to be on disk, and a stop in the middle can leave
the folder and the session telling different stories. The reviewer of a scoping
pull request sees scratch files arrive with the documents, and the cleanup has to
remove them, and grep committed prose for references to them, before the pull
request can merge. And the skill author who wants to move the next skill off the
folder has no written convention to follow: `/work-on` already keeps its state in
context keys, but the way it does so is specific to one skill, and nothing says
how a parent and its children find each other once the folder is gone.

The coupling is what makes this a chain-level problem rather than one per
skill. A parent tells a child it is running under a chain by writing a
block into its own state file, and every child finds that block by globbing the
folder for the parent's file. Moving a child off the folder without moving its
parent, or the reverse, breaks that handshake, so the parents and their direct
children have to move together, on one convention, or not at all.

## User Outcome

An author runs `/scope` or `/charter`, stops it anywhere, and re-invokes it,
and the run continues from where it was, whatever the working tree holds; an
author could empty the staging folder mid-run and the resume would not notice.
A child running under a chain still knows it is under one, and the parent still
learns what the child did, without either of them reading a file the other left
at a known path.

The scoping pull request carries the documents the chain produced and nothing
else, so a reviewer reads the feature, not its scratch, and there is no
intermediate state to clean out before merge.

A skill author picking up the next skill reads one design that says how keys
are named, how a skill finds its predecessor's session, what a parent writes for
a child, and what happens to a finished child's session, and moves the skill by
following it. The same design names what the convention does not give yet:
until sessions are imported to another host, a skill's working state stays on
the host that ran it, where the branch used to carry it.

## User Journeys

### An author resumes an interrupted /scope run

An author starts `/scope` on a feature, and the run stops partway through the
design hop when the session crashes. They re-invoke `/scope <topic>`. The run
finds its own session and the design child's session by name, reads where each
one stopped, and continues the design hop, with no file in the staging folder
consulted or written. This case shows that resume no longer depends on
the folder.

### An author's /charter run is interrupted inside a child

An author runs `/charter` on an initiative and the session dies while
`/strategy` is drafting. They re-invoke `/charter <topic>`. The parent sees it
had handed the strategy hop to `/strategy`, re-enters it, and `/strategy` picks
up its own draft knowing it still runs under the chain: it suppresses its
re-entry prompt and its publishing steps as it does today. When it returns,
`/charter` learns what it produced without reading a file `/strategy` left at a
known path. This case shows the parent-to-child handshake across an
interruption.

### A reviewer reads a scoping pull request

A maintainer opens the pull request a `/scope` run published. It holds the
BRIEF, PRD, DESIGN and PLAN, each committed by its hop, and no scratch files; no
cleanup commit is needed before it can merge. This case shows that the
pull request no longer carries intermediate state.

### A skill author moves a leaf skill

A contributor taking on `/explore` reads the convention's design, opens the
skill's session the way the chain children do, names its keys by the
convention's rules, and replaces its resume ladder's file checks with key
checks. They don't need to read the chain code to learn the rules. This case
shows that the convention is reusable beyond the chains.

## Scope Boundary

**In scope:**

- One written convention for a skill's intermediate state in koto sessions:
  session naming, key naming, how a skill finds another skill's session by name
  on one host and, by naming that survives an import, on another, the
  parent-to-child signal as a
  key, what a chain child's session does when it finishes, and the session
  namespace later coordinator work reuses.
- The shared scripts every skill calls to follow it, with tests.
- `/scope` and `/charter` moving onto it, including `/scope`'s state file and
  its koto template's checks over the folder, and `/charter` gaining a session
  of its own.
- Their direct children moving with them: `/brief`, `/prd`, `/design`, `/plan`
  under `/scope`, and `/vision`, `/strategy`, `/roadmap` under `/charter`, plus
  any skill a chain child runs inline whose files it reads or writes (for
  example `/review-plan` reading `/plan`'s working files); the PRD lists them.
- The exploration handoff that `/scope` and `/charter` read on entry, since the
  chains consume it.
- A dated note on the scope adoption design saying its recorded exception is
  closed.

**Out of scope:**

- The leaf skills no chain runs directly (`/comp`, `/decision` where it runs
  alone, `/explore`'s own working files, `/release`, `/review-plan` where it runs
  alone). They follow later, one skill at a time, on this convention.
- The enforcement that exists because of the folder: the sweep in `/execute`,
  the stray-path field in `/deliver`'s report, the per-repository CI check. It
  stays until the last skill stops writing the folder.
- `/work-on`'s fallback file when koto is unreachable.
- The coordinate skill's own state handling and its record, beyond reserving the
  namespace this convention fixes.
- Any koto change. A format koto lacks is proposed to koto's maintainers, not
  built here.
- Carrying a skill's working state to another host. The convention only keeps
  its names valid across an import; applying koto's session import to skill
  sessions is later work.

## References

- `docs/designs/current/DESIGN-scope-koto-adoption.md` -- records `/scope`'s state
  file as a deliberate exception and names a chain with no filesystem state as
  the direction.
- `docs/designs/current/DESIGN-work-on-koto-unification.md` -- `/work-on`'s move to
  context keys, the precedent this convention generalizes.
- `references/parent-skill-pattern.md` -- the parent-to-child signal this feature
  turns into a key.
- `skills/work-on/references/koto-context-conventions.md` -- how a skill writes a
  key without leaving a file behind.
