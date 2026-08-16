---
name: preflight-liveness-sat
description: >-
  Eval fixture. The satisfied twin of preflight-liveness-unsat -- same plugin,
  same injected line, a declaration that every host meets. Used to show that a
  met prerequisite costs the model nothing. Not a workflow skill and not
  shipped in the shirabe plugin.
argument-hint: ''
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh preflight-liveness-sat 2>&1 || true`

# Preflight liveness fixture (satisfied)

This skill does no work. Its only job is to be loaded.

It is the control for `preflight-liveness-unsat`. The injected line above is
identical apart from the skill name, and the declaration it reads names `sh`,
which resolves on every host this plugin runs on. A working check therefore
prints nothing, and the body arrives with no preamble.

The pair is what carries the meaning. Silence here on its own would also be
what a check that never ran produces; silence here alongside a report from the
unsatisfiable twin is evidence that the check ran and found nothing.

## What to do when this skill is invoked

Report, in this order, and nothing else:

1. Whether anything appeared in your context above this heading, and if so,
   reproduce it verbatim inside a fenced block.
2. The approximate byte count of what appeared, which should be zero.

Do not run any command.
