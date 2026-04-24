# Explore Scope: work-on-friction-triage

## Visibility

Public (shirabe repo)

## Core Question

Given the 521-line friction log at `/tmp/codespar-enterprise-pr38.md` from
an external agent's run of `/shirabe:work-on` across five bundled issues,
which observations represent real improvement opportunities in shirabe,
which are bugs in koto, and which belong elsewhere (language skills,
Claude Code harness, user/agent foot-guns)?

## Context

- Source: an agent working on `codespar/codespar-enterprise` bundled five
  issues (#32-36) onto one branch, one PR, five commits. Total session
  ~20 min per issue at the tail, longer at the head.
- The friction log is first-hand observations, not maintainer-filed
  issues. Claims that name specific skill behavior need to be verified
  against the current skill/template code before filing.
- 0.5.0 capabilities (plan orchestrator, completion cascade, review
  panels) are NOT exercised in this friction log — the run was
  issue-backed mode, one issue at a time. All observations are about
  that path.
- Output: a categorized list the user reviews and files manually.

## In Scope

- Observations about /shirabe:work-on skill behavior (any phase)
- Observations that name koto primitives (states, gates, context, rewind)
- Observations that could belong to adjacent skills (nodejs, bash,
  language quality)
- Observations about harness/plugin env-vars the skill relies on

## Out of Scope

- Fixing anything in this exploration — output is the categorized list
- Observations that are strictly codespar-specific (turbo config, their
  migration FK issue, their npm dep conflict specifics)
- Rewriting the friction log — preserve the author's framing
- Verifying every factual claim exhaustively; spot-check the
  most consequential ones

## Research Leads

The research is the friction log itself. The verification lead is a
single focused pass: for each observation that names a specific skill
behavior, read the current skill/template/script code and confirm or
refute. No fan-out agents needed.

1. **Which observations match the current skill code, and which are
   stale / misattributed / already fixed?**
   Read phase files, template states, and helper scripts.

2. **Which observations name koto engine behavior vs skill behavior?**
   Distinguish "the template says X" (skill fix) from "koto does X
   regardless of template" (engine fix).

3. **Which observations would be better owned by a language skill
   (nodejs) or the harness (Claude Code)?**
   Turbo cache, system-reminders, and env-var resolution are not
   work-on's job to fix.
