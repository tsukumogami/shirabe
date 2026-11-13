---
schema: prd/v1
status: Draft
problem: |
  An adopter who installs shirabe outside the workspace it was built in can't
  rely on what the skills read from their repository. With no visibility
  header, the skills and the validator guess visibility from directory names,
  so a public repository at an ordinary path is handled as private and the
  public-content rules never load. The include slots and CLAUDE.md headers
  adopters build on can be removed or renamed in a release with only a
  reviewer's attention in the way, and the break is silent.
goals: |
  Visibility is settled from the repository itself, or the author is asked,
  and a directory name never decides it. A release that removes or renames an
  include slot or a header a skill reads is flagged before it ships and named
  as a breaking change in that release's notes, so notes that are silent on
  breaking changes mean there were none.
upstream: docs/briefs/BRIEF-skill-extension-contract.md
---

# PRD: Skill extension contract

## Status

Draft

## Problem Statement

shirabe tells teams outside the workspace it grew up in that they can install
its skills, layer their own rules on top, and keep working across upgrades.
Two parts of that promise rest on convention.

Visibility comes first. Every skill that writes a document, an issue or a pull
request picks its content rules from the repository's visibility, read from a
`## Repo Visibility:` header. When the header is missing, the skills and
`shirabe validate` look for a `public` or `private` component in the
checkout's path and otherwise fall back to Private. That rule describes one
workspace layout and guesses everywhere else. A public repository cloned to an
ordinary path, or checked out in a worktree whose path has no `public`
component, is handled as private, so the rules that keep internal content out
of public text never load. A repository under a folder that happens to be
named `private` or `public` gets whatever the folder says. On macOS, temporary
directories resolve under `/private/`, so any checkout there reads as Private.
The guess is silent, and the adopter has no reason to suspect it. The fallback
lives in about a dozen skills, in the validator, in the gate scripts that call
the validator, and in the published extension guide, which documents it.

The extension points come second. An adopter's rules reach a skill through two
include lines at the top of its SKILL.md, and project settings reach it
through CLAUDE.md headers. The extension guide calls a removed slot line and a
renamed header breaking changes that the release notes announce, and says
plainly that this is a review convention no tool enforces. A missed change
breaks the adopter's setup with no error, because a missing include or an
unread header fails silently. The published lists of headers already disagree
with each other and with what the skills actually read.

## Goals

- An adopter runs any shirabe skill from wherever the repository is checked
  out and gets visibility settled from the repository itself, or is asked
  when it can't be settled. A public repository is handled as public whether
  or not anyone wrote the header.
- An adopter about to upgrade can trust the release notes: a removed or
  renamed slot line or header was flagged before the release went out by
  something that doesn't depend on a reviewer noticing it, and the notes name
  it as a breaking change. Notes silent on breaking changes mean the release
  made none.

## User Stories

- As an adopter with a public repository and no visibility header, I want
  `/prd` run from a checkout at an ordinary path to apply the public-content
  rules, so that internal content doesn't leak into my public documents
  because of where I cloned the repository.
- As an adopter who keeps checkouts under a directory named `private`, I want
  skills to settle visibility from the repository and ask me when they can't,
  so that a folder name never decides which content rules apply.
- As an adopter running a skill unattended with no network, I want the run to
  tell me visibility wasn't settled and which rules it applied instead, so
  that I can declare the header rather than discover the choice later.
- As a shirabe contributor, I want a pull request that drops a skill's include
  line or renames a header a skill reads to be flagged before a release can
  carry it, so that catching it doesn't rest on a reviewer spotting it.
- As an adopter reading the notes of the release I'm moving to, I want each
  breaking change to name the slot or header it touches and what to change in
  my own files, so that I can upgrade without reading shirabe's diff.

## Requirements

### Functional: visibility

- **R1. A declared header wins.** When the repository declares
  `## Repo Visibility: Public|Private` in its CLAUDE.md or CLAUDE.local.md,
  every skill and `shirabe validate` use that value, as today.
- **R2. No directory-name inference.** No skill, script or `shirabe validate`
  mode derives visibility from any component of the checkout's path. This
  holds everywhere the fallback lives today: skill text, reference files, gate
  scripts, the validator, and the README and extension guide that document
  it.
- **R3. Settled from the repository.** With no header, visibility is settled
  from the repository's own record at its hosting service: the visibility the
  host reports for the repository the checkout's remote names. A repository
  the host reports as public is Public; one it reports as private or internal
  is Private.
- **R4. Unsettled is said, then asked or failed closed.** When neither a
  header nor the host settles visibility (no remote, a remote the host can't
  resolve, no network, no credentials, an error), the outcome is "unsettled",
  never a guess:
  - an interactive run asks the author which visibility applies, and says
    that declaring the header stops the question;
  - an unattended run applies Private, and its output carries one line
    saying visibility was not settled, why, that Private rules were applied,
    and the header that settles it;
  - `shirabe validate` with no header and no `--visibility` value applies
    Private and reports a notice naming the same three facts.
- **R5. One answer per run.** A skill run settles visibility once and uses
  that answer for every document, issue and pull request it writes in that
  run, including the children a parent skill dispatches.

### Functional: the pre-release check

- **R6. One published list is the contract.** shirabe publishes one list of
  the include slots and the CLAUDE.md and CLAUDE.local.md headers its skills,
  scripts and validator read. The extension guide carries it or points to it,
  and the other places that list headers today agree with it or point to it.
- **R7. Slot check.** Before a release ships, a check compares the include
  slot lines of every skill at the previous release with those at the release
  candidate and flags each slot line that is gone or whose path changed. A
  renamed skill moves its slot path and counts as a removed slot.
- **R8. Header check.** The same check compares the published header list at
  the previous release with the candidate's and flags each header that left
  the list. It also flags each header on the candidate's list that nothing in
  the skills, scripts or validator reads any more, so a header that silently
  lost its reader can't stay listed.
- **R9. A flag stops the release until it is named.** A flagged change stops
  the release from completing until the release notes name it under a
  breaking-changes heading, with the slot or header it touches and what an
  adopter changes in their own files. A deliberate break is allowed; an
  unnamed one isn't.
- **R10. The check runs where releases run.** The check runs as part of
  shirabe's release flow, before the version is tagged, with no step a person
  has to remember. It can also run on its own against any two revisions, so a
  contributor can see the result on a pull request before release time.

### Functional: the guide

- **R11. The guide describes what's enforced.** `docs/guides/extending.md`
  says how visibility is settled when no header is declared, including the
  unsettled case, and that removed or renamed slots and headers are flagged
  before release and named in the notes. It no longer documents the
  path-based fallback or calls slot and header stability a review convention.

### Non-functional

- **R12. Bounded wait.** Settling visibility from the host waits at most 10
  seconds per run before treating visibility as unsettled.
- **R13. No new dependency for adopters.** Settling visibility uses only tools
  a shirabe run already needs; a repository with no hosting remote works, with
  visibility unsettled.
- **R14. The check needs no model run.** The pre-release check is mechanical:
  it reads files at two revisions and needs no model call or evaluation run.

## Acceptance Criteria

- [ ] A `grep` across `skills/`, `references/`, `scripts/` and `crates/` for
      the path fallback (a `private/` or `public/` path component mapped to a
      visibility) finds no live rule; `infer_visibility_from_path` or its
      equivalent is gone from the validator.
- [ ] In a public repository with no header, cloned under a directory named
      `private`, a skill run applies the public-content rules.
- [ ] In a private repository with no header, cloned under a directory named
      `public`, a skill run applies the private-content rules.
- [ ] With a header declared, the header's value is used even when the host
      reports the opposite visibility.
- [ ] In a repository with no remote and no header, an interactive run asks
      the author once, and an unattended run applies Private and prints one
      line naming the unsettled visibility, the reason and the header to
      declare.
- [ ] With the host unreachable, a run reaches the unsettled outcome within
      10 seconds of starting the lookup.
- [ ] `shirabe validate` with no header and no `--visibility` value, in a
      repository whose path contains `public/`, reports Private with a notice
      naming the unsettled visibility, not Public.
- [ ] A parent skill and the children it dispatches in one run use the same
      visibility answer.
- [ ] The published list names every header a skill, script or the validator
      reads, and each other place that lists headers matches it or points to
      it.
- [ ] Against a candidate that deletes one skill's `.local.md` include line,
      the check flags that skill and slot; against one that renames a skill,
      it flags both of that skill's slots.
- [ ] Against a candidate that drops a header from the published list, the
      check flags that header; against one where a listed header has no
      remaining reader, it flags that header.
- [ ] Against a candidate with no slot or header change, the check flags
      nothing.
- [ ] A release whose candidate carries a flagged change does not complete
      while its notes lack a breaking-changes entry naming that slot or
      header, and completes once the entry is there.
- [ ] The check runs in the release flow before tagging without a manual
      step, and runs on demand against two named revisions.
- [ ] `docs/guides/extending.md` describes the visibility order, the
      unsettled case and the pre-release check, and no longer documents the
      path fallback or calls the protection a review convention.

## Out of Scope

- New include slots, more skills with slots, or any new extension mechanism.
- Renamed workflow phases. Only an adopter's own prose depends on a phase
  name, and adding a phase renumbers the rest, so a check would flag changes
  no adopter feels. The guide keeps phase renames as a breaking kind announced
  by convention.
- The fixed formats some skills read inside their own extension files, which
  the guide already places outside the contract.
- Proving that a skill actually loads an extension file at run time, which
  needs a model run rather than a check.
- Changing what the content rules for public and private repositories say.
- Running the pre-release check in adopters' own repositories.

## Decisions and Trade-offs

- **The repository's signal is its host record.** The brief left open what
  "the repository itself" means. Files inside the repository (a license, a
  manifest's private flag) hint at intent but don't decide it; the host's
  record does. shirabe's merge gate already settles visibility this way and
  fails closed to Private, which sets the precedent. Chosen over file hints,
  which would be a new guess in place of the old one.
- **Unattended runs fail closed to Private, out loud.** An unattended run has
  nobody to ask. Private is the safe direction (it can over-restrict a public
  document, never leak into one), and the one-line notice is what separates
  this from today's silent fallback. Chosen over stopping the run, which
  would break every offline unattended run of a repository that simply never
  declared the header.
- **Slots are read from the skills; headers come from one fixed list.** Slot
  lines have a fixed shape and can be compared between revisions as they
  are. Headers can't be found that way: code matches them in lowercase or by
  bare name, and ordinary section headings look the same as a header. So the
  header list is a published contract, and the check adds a reader test so
  the list can't drift from what the skills read.
- **A flag stops the release until the notes name it, rather than blocking
  the change.** A deliberate break is legitimate; the goal is that it's
  named. The check therefore holds the release on the missing notes entry,
  not on the change itself.
- **The check lives in the release flow, with an on-demand mode.** Releases
  are where a missed break costs adopters, so that's where it must run
  without anyone remembering it. Running it on demand lets a contributor see
  the flag at pull request time.
- **Phase renames stay out.** The brief left this to requirements. No adopter
  file or header names a phase, and detection would be noisy, so the guide
  keeps them as a convention.
- **A renamed skill counts as a removed slot.** Renaming a skill moves both
  slot paths, which breaks an adopter's extension file exactly as removing
  the line would.

## Known Limitations

- A host lookup needs credentials for a private repository; without them the
  host may not reveal the repository at all, which lands in the unsettled
  case and, unattended, in Private. That's the correct direction, but it
  means a private repository with no header and no credentials gets a notice
  on every unattended run until the header is declared.
- The header list is maintained by hand. The reader test catches a listed
  header that lost its reader; a newly read header that nobody adds to the
  list is caught only when someone adds it.
