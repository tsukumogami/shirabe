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

Terms used below. An **interactive run** is a skill run with an author
present to answer questions: one started with `--interactive`, or with no mode
flag where the repository's execution mode is interactive. An **unattended
run** is one started with `--auto`, or a child run dispatched by a parent that
runs unattended. The **previous release** is the most recent release tag
reachable from the release candidate.

### Functional: visibility

- **R1. A declared header wins.** When the repository declares
  `## Repo Visibility: Public|Private` in CLAUDE.md or CLAUDE.local.md, every
  skill and `shirabe validate` use that value. When the two files declare
  different values, Private applies and the run says the two files disagree.
  A `--visibility` value given to `shirabe validate` outranks both.
- **R2. No directory-name inference.** No skill, reference file, script or
  `shirabe validate` mode derives visibility from any component of the
  checkout's path, and the README and extension guide no longer document
  such a rule.
- **R3. Settled from the repository's host record.** With no header, a run
  asks the repository's host for the repository's visibility. The repository
  is the one the `origin` remote names, or the only remote when there is
  exactly one and it isn't named `origin`. The supported host is GitHub, the
  host shirabe's skills already work against. A repository the host reports
  as public is Public; private or internal is Private.
- **R4. Unsettled is said, then asked or failed closed.** Visibility is
  unsettled when no header is declared and any of these holds: there is no
  remote, or several remotes and none named `origin`; the remote isn't on a
  supported host; the lookup fails for any reason (the repository isn't
  found, credentials are missing or refused, the network or host returns an
  error); or the lookup passes the time bound in R12. Unsettled is never
  resolved by a guess:
  - an interactive run asks the author once whether the repository is
    Public or Private, and the question says that declaring the
    `## Repo Visibility:` header stops it being asked;
  - an unattended run applies Private and prints one line that says
    visibility was not settled, gives the reason from the list above, says
    Private rules were applied, and names the `## Repo Visibility:` header;
  - `shirabe validate` with no header and no `--visibility` value applies
    Private and reports a notice carrying the same three facts.
- **R5. One answer per run.** A run settles visibility once. A parent skill
  hands its answer to every child it dispatches, and a child under a parent
  neither queries the host again nor asks the author again.

### Functional: the pre-release check

- **R6. One published list is the contract.** `docs/guides/extending.md`
  carries the one list of include slots and of the CLAUDE.md and
  CLAUDE.local.md headers that shirabe's skills, scripts and validator read.
  `references/fixes/claude-md-conventions.md` and the README point to that
  list rather than keep their own.
- **R7. Slot check.** A check compares the include slot lines of every skill
  at the previous release with those at the candidate. It flags each slot line
  present at the previous release and absent at the candidate, which covers a
  removed line, a changed slot path and a renamed skill (a rename moves both
  of the skill's slot paths). A slot added at the candidate isn't flagged.
- **R8. Header check.** The same check compares the published header list at
  the previous release with the candidate's and flags each header that left
  the list. It also flags each header on the candidate's list that has no
  reader at the candidate. A header has a reader when its name, matched
  without regard to case and with or without the leading `## ` and trailing
  colon, appears in a file under `skills/`, `references/`, `scripts/` or
  `crates/` other than test and eval fixtures.
- **R9. A flag holds the release until the notes name it.** A flagged change
  stops the release from completing until the release notes carry a section
  headed `Breaking changes` with an entry that contains the flagged slot path
  or header name verbatim, followed by at least one sentence saying what an
  adopter changes in their own files. A deliberate break is allowed; an
  unnamed one isn't.
- **R10. The check runs where releases run.** `/shirabe:release` runs the
  check among the checks it runs before tagging, with no option or extra step
  needed to turn it on. The check also runs on its own against two named
  revisions, so a contributor can see the result on a pull request; given a
  revision that doesn't exist, it exits non-zero and names the revision.
- **R11. Without an earlier release there's nothing to compare.** When the
  candidate has no reachable release tag, the check says it has no baseline
  and flags nothing.

### Non-functional, and the guide

- **R12. Bounded wait.** The host lookup is abandoned 10 seconds after it
  starts, and the run treats visibility as unsettled.
- **R13. No new dependency for adopters.** Settling visibility uses git and
  the GitHub CLI, which shirabe's skills already require; no new install step
  is added.
- **R14. The guide describes what's enforced.** `docs/guides/extending.md`
  states the visibility order (header, then host record, then unsettled), what
  an unsettled run does, and that removed or renamed slots and headers are
  flagged before release and must be named in the notes. It no longer
  documents the path-based rule or calls slot and header stability a review
  convention.
- **R15. The check needs no model and no network.** The pre-release check
  reads files at two revisions of a local clone. It makes no model call and
  no network request.

## Acceptance Criteria

Visibility:

- [ ] `git grep -nE 'infer_visibility_from_path|infer from repo path'` over
      `skills/`, `references/`, `scripts/`, `crates/`, `README.md` and
      `docs/guides/extending.md` returns no match, and neither does a
      `git grep` there for a `private/` or `public/` path component followed
      by `->` and a visibility.
- [ ] A public GitHub repository with no header, checked out under a
      directory named `private`, gets the public-content rules from a skill
      run.
- [ ] A private GitHub repository with no header, checked out under a
      directory named `public`, gets the private-content rules.
- [ ] A repository checked out under macOS's `/private/var/folders` temporary
      area with no header gets the visibility its host reports.
- [ ] A repository the host reports as internal is handled as Private.
- [ ] A header in CLAUDE.md is used even when the host reports the opposite;
      a header only in CLAUDE.local.md is used the same way; when the two
      files disagree, Private applies and the run's output says they
      disagree.
- [ ] With no header, an unattended run prints exactly one unsettled line in
      each of these cases, each line naming its own reason: no remote; two
      remotes and none named `origin`; a remote on a host other than GitHub;
      a repository the host can't find; missing credentials.
- [ ] With no header and no remote, an interactive run asks the author once,
      the question names the `## Repo Visibility:` header, and the answer
      is used for the rest of the run.
- [ ] With the host lookup made to hang, the run reaches the unsettled
      outcome no later than 10 seconds after the lookup starts.
- [ ] `shirabe validate` with no header and no `--visibility`, on a document
      whose path contains `public/`, reports Private and a notice that says
      visibility was not settled, why, and names the header.
- [ ] `shirabe validate --visibility public` reports Public whatever the
      headers and path say.
- [ ] In a `/scope` run with no header, the host is queried at most once and
      the author is asked at most once across the parent and all its
      children, and every child applies the parent's answer.
- [ ] The README's installation steps gain no new tool.

Pre-release check:

- [ ] The list in `docs/guides/extending.md` names at least Repo Visibility,
      Planning Context, Default Scope, Execution Mode, Roadmap Issues,
      Delivery Preference, Tracking Level, Release Notes Convention, Fix
      Labels, Test Change Acceptance, PR Workflow Content, PR Grouping Policy,
      Reviewability Ceiling, Prose Vocabulary and Label Vocabulary, and each
      skill's two slot paths; `references/fixes/claude-md-conventions.md` and
      the README link to it and carry no header list of their own.
- [ ] Against a candidate that deletes one skill's `.local.md` include line,
      the check flags that slot path; against one that renames a skill, it
      flags both of that skill's old slot paths; against one that changes a
      slot's path, it flags the old path.
- [ ] Against a candidate that adds a slot, the check flags nothing.
- [ ] Against a candidate that drops a header from the list, the check flags
      that header.
- [ ] Against a candidate where a listed header's only reader is removed, the
      check flags that header; where the header is still read only in
      lowercase (for example `## repo visibility:` in Rust source), it
      doesn't.
- [ ] Against a candidate with no slot or header change, the check flags
      nothing and exits zero.
- [ ] With no reachable release tag, the check prints that there's no
      baseline and flags nothing.
- [ ] Run on demand with a revision that doesn't exist, the check exits
      non-zero and its message names that revision.
- [ ] `/shirabe:release` on a candidate with a flagged change stops before
      creating the tag while the notes lack a `Breaking changes` entry
      containing the flagged name and a following sentence, and goes on to
      tag once that entry is present; no option is added to the invocation.
- [ ] The check completes with networking disabled and no model credentials
      in the environment.
- [ ] `docs/guides/extending.md` contains the visibility order, the unsettled
      behaviour for interactive and unattended runs, and the pre-release
      check, and `git grep -n "review convention" docs/guides/extending.md`
      returns no match.

## Out of Scope

- New include slots, more skills with slots, or any new extension mechanism.
- Renamed workflow phases. Only an adopter's own prose depends on a phase
  name, and adding a phase renumbers the rest, so a check would flag changes
  no adopter feels. The guide keeps phase renames as a breaking kind announced
  by convention.
- Catching a header that a skill starts reading without anyone adding it to
  the list. The check guards what's listed; adding to the list is part of
  adding a header, and review of that pull request is where it's caught.
- Hosts other than GitHub. A remote elsewhere lands in the unsettled case,
  where the header settles it.
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
- **Disagreeing headers fail closed too.** When CLAUDE.md and CLAUDE.local.md
  declare different values, neither is obviously the one the adopter meant,
  so Private applies and the run says why. Chosen over letting the local file
  win silently.
- **Slots are read from the skills; headers come from one fixed list.** Slot
  lines have a fixed shape and can be compared between revisions as they
  are. Headers can't be found that way: code matches them in lowercase or by
  bare name, and ordinary section headings look the same as a header. So the
  header list is a published contract, and the reader test keeps the list
  from naming headers nothing reads.
- **A flag holds the release until the notes name it, rather than blocking
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
  case and, unattended, in Private. That's the correct direction, but a
  private repository with no header and no credentials gets the notice on
  every unattended run until the header is declared.
- The header list is maintained by hand. The reader test catches a listed
  header that lost its reader, not a new reader nobody listed.
