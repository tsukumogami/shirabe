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
initial_state: open
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
