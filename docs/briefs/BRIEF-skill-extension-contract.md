---
schema: brief/v1
status: Accepted
problem: |
  An adopter outside the workspace shirabe grew up in can't rely on what it reads
  from their repository: with no visibility header, skills guess visibility from
  directory names, and the slots and headers adopters build on can be removed or
  renamed in a release with only a reviewer's attention in the way.
outcome: |
  An adopter gets visibility settled from the repository itself, or is asked,
  wherever the checkout sits; and a release that removes or renames a slot or a
  header they depend on is flagged before it ships and named as breaking in that
  release's notes.
---

# BRIEF: Skill extension contract

## Status

Accepted

Frames the two parts of shirabe's extension contract that still rest on
convention: how a skill decides visibility when nothing declares it, and what
stops a release from breaking the slots and headers adopters build on.

## Problem Statement

shirabe's skills promise a team outside the workspace shirabe was built in that it can
install them, layer its own rules on top, and keep working across upgrades.
Two things in that promise don't hold up yet.

The first is visibility. Every skill that writes a document, an issue or a pull
request picks its content rules from the repository's visibility, and it reads
that from a `## Repo Visibility:` header in CLAUDE.md. When the header is
missing, the skills don't ask and don't check: they look for a `public` or
`private` directory anywhere in the checkout's path, and fall back to Private.
That rule describes one workspace layout. For anyone else it guesses. A public
repository cloned to an ordinary path is handled as private, so the rules that
keep internal content out of public text never load. A repository that happens
to sit under a folder named `private` or `public` gets whatever that folder
name says, whatever the repository really is. The guess is silent, so the
adopter has no reason to suspect it.

The second is the extension points themselves. An adopter's rules reach a skill
through two include lines at the top of its SKILL.md, and project-wide settings
reach it through CLAUDE.md headers. shirabe's published extension guide lists a
removed slot line and a renamed header as breaking changes and says they're
announced in release notes. It also says plainly that nothing enforces this:
whether such a change is caught before it ships depends on someone noticing it
in review. When nobody does, the adopter's extension file or header stops
working with no error, because a missing include or an unread header fails
silently.

## User Outcome

An adopter runs any shirabe skill from wherever the repository is checked out
and gets visibility settled from the repository itself, or is asked when it
can't be settled. The directory the checkout happens to live in has no say.
A public repository is handled as public whether or not anyone wrote the header.

An adopter about to upgrade shirabe can trust the release notes. If a release
removes or renames a slot line or a header their setup relies on, something
that doesn't depend on a reviewer's attention flagged it before the release
went out, and the notes name it as a breaking change. A release whose notes are
silent on breaking changes didn't make one.

## User Journeys

- An adopter with a public repository and no visibility header runs `/prd` from
  a checkout at an ordinary path, and the skill applies the public-content rules
  because it settled visibility from the repository, not from the path.
- The same adopter keeps their checkouts under a directory named `private`; a
  skill run there still settles visibility from the repository, and when it
  can't, it asks rather than reading the folder name.
- A shirabe contributor opens a pull request that drops a skill's include line
  or renames a CLAUDE.md header a skill reads, and the change is flagged before
  a release can carry it, without a reviewer having to spot it.
- An adopter reading the notes of the release they're moving to finds a
  breaking change named with the slot or header it touches and what to change
  in their own files.

## Scope Boundary

**In:**

- How every skill that reads visibility settles it when the repository
  declares none, and the end of the guess from directory names wherever
  the skills and the validator make it.
- What an adopter sees when visibility can't be settled from the repository.
- A check, run before a release ships, that flags a removed or renamed
  include slot and a renamed CLAUDE.md header that a skill reads.
- How a flagged change reaches the release notes as a named breaking change.
- Updating the published extension guide so it describes what's enforced
  rather than calling it a review convention.

**Out:**

- Giving more skills an include slot, or any new extension mechanism.
- Renamed workflow phases, the guide's third breaking kind, unless the
  requirements bring them in; this brief frames slots and headers.
- The fixed formats some skills read inside their own extension files, which
  the guide already places outside the contract.
- Proving that a skill actually loads an extension file at run time, which
  needs a model run rather than a check.
- Changing what the content rules for public and private repositories say.

## References

- `docs/guides/extending.md` -- the published extension contract this brief
  completes.
- `docs/designs/current/DESIGN-skill-extensibility.md` -- the design that set
  up the two include lines and the header set.
