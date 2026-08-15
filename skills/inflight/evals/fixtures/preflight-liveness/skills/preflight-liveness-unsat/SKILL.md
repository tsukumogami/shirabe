---
name: preflight-liveness-unsat
description: >-
  Eval fixture. A skill whose prerequisite declaration cannot be satisfied on
  any host, used to prove that the injected preflight line still executes at
  skill load and that its report reaches the model. Not a workflow skill and
  not shipped in the shirabe plugin.
argument-hint: ''
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh preflight-liveness-unsat 2>&1 || true`

# Preflight liveness fixture (unsatisfiable)

This skill does no work. Its only job is to be loaded.

The line above this heading is the same injected command every shirabe skill
carries, character for character apart from the skill name. When this skill is
loaded, the harness runs it and puts whatever it printed into your context
ahead of this body. This fixture's `requires.tsv` declares a tool that exists
on no host, so a working check prints a "prerequisite not met" block and a
broken one prints nothing at all.

Those two outcomes are indistinguishable from inside the check, which is why
this fixture exists: a satisfied host and a check that never ran are both
silent, so the only way to tell them apart is to load a declaration that cannot
be satisfied and look for the report.

## What to do when this skill is invoked

Report, in this order, and nothing else:

1. Everything that appeared in your context above this heading, verbatim,
   inside a fenced block. If nothing appeared, say exactly that.
2. Whether the text names the skill `/preflight-liveness-unsat` and the tool
   `preflight-absent-tool`.
3. The approximate byte count of what you reproduced.

Do not run any command. Do not run the preflight script yourself, and do not
read `requires.tsv` to reconstruct what the report would have said: a
reconstruction proves the file is on disk, and the question is whether the
injected line ran.
