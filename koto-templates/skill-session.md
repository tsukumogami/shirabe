---
name: skill-session
version: "1.0"
description: >
  The store template of the skill-session convention. A skill with no koto
  template of its own opens its session, <skill>-<topic>, from this file and
  uses it only to hold context keys (work/, research/, chain/, handoff/,
  session/). It has one non-terminal state, open, which a first tick stops at
  and which stays put until the skill or its parent submits close evidence.
  Every tick carries --no-cleanup, so a closed session stays readable.

  The file name is part of the contract: koto init --attach-live compares a
  live session's template by file name, so renaming this file makes every
  live session refuse to attach. scripts/skill-session.sh opens, reads and
  closes these sessions; references/skill-session-convention.md states the
  rules.

  review_vocabulary lists the document jury seats and section slugs
  scripts/review-events.sh and scripts/doc-events.sh record on a direct child
  run or a /charter run, so koto keeps them as given and records anything
  else as other (references/review-verdicts.md). scope.md declares the
  /brief, /prd, /design and /plan lists for a run under /scope; the VISION,
  STRATEGY and ROADMAP seats and sections are declared here only, since
  /scope never runs those skills.
initial_state: open
review_vocabulary:
  seats: [content-quality, structural-format, completeness, clarity, testability,
          architecture, security, scope-gate, design-fidelity, ac-discriminability,
          sequencing, functional-shape, thesis-quality, content-boundary,
          section-guidance, bet-quality, altitude, theme-coherence,
          sequencing-dependency, annotation-boundary]
  sections: [status, problem-statement, user-outcome, user-journeys, scope-boundary,
             goals, user-stories, requirements, acceptance-criteria, out-of-scope,
             context-and-problem-statement, decision-drivers, considered-options,
             decision-outcome, solution-architecture, implementation-approach,
             security-considerations, consequences, scope-summary,
             decomposition-strategy, issue-outlines, implementation-issues,
             dependency-graph, implementation-sequence, steps, thesis, audience,
             value-proposition, org-fit, success-criteria, non-goals,
             strategic-context, defensibility-thesis, building-blocks,
             coordination-dependencies, bet-specific-falsifiability,
             downstream-artifacts, theme, features, milestones,
             sequencing-rationale, progress, frontmatter, document]
states:
  open:
    accepts:
      close:
        type: enum
        values: [done, abandoned]
        required: true
    transitions:
      - target: done
        when:
          close: done
      - target: abandoned
        when:
          close: abandoned
  done:
    terminal: true
  abandoned:
    terminal: true
---

## open

This session holds a skill's keys. Nothing here is a task: read and write
keys with `koto context`, and close the session through
`scripts/skill-session.sh close <session> done|abandoned`, which submits
`close` with `--no-cleanup`.

## done

The skill finished. The session is kept and its keys stay readable.

## abandoned

The skill stopped without finishing. The session is kept and its keys stay
readable.
