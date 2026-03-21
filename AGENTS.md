# Agent Guidelines for shirabe

This is a skills repository. The quality of skills is validated through evals,
not just code review. These guidelines apply to any agent working on this repo.

## Eval Requirement

When adding or modifying a skill:

1. **Write eval scenarios** in `evals/evals.json` that cover the skill's key
   behaviors. Each eval has a prompt (what a real user would say), expected
   output (what the skill should produce), and assertions (objectively
   verifiable checks).

2. **Run evals using /skill-creator** before considering the work done. Spawn
   agents with the skill loaded and without (baseline), collect outputs, grade
   against assertions, and generate the eval viewer for human review.

3. **Iterate based on eval results.** If an eval fails or produces unexpected
   output, fix the skill and re-run. Don't ship skills that haven't been
   validated against their eval scenarios.

This applies to:
- New skills (write evals during skill creation)
- Skill modifications (run existing evals + add new ones for changed behavior)
- Specification changes (reference files, format specs) that affect skill behavior

## Eval Structure

```
evals/
  evals.json              # All eval scenarios with assertions
<skill>-workspace/
  iteration-N/
    eval-<name>/
      with_skill/outputs/  # Outputs from agent with skill loaded
      without_skill/outputs/ # Baseline outputs without skill
      eval_metadata.json   # Prompt + assertions
      grading.json         # Pass/fail per assertion
      timing.json          # Token count and duration
    benchmark.json         # Aggregated results
```

## Skill Quality Standards

Skills in this repo follow the patterns documented in the skill-creator skill:
- Progressive disclosure (SKILL.md under 500 lines, reference files under 300)
- Imperative instructions that explain "why" not just "what"
- Decision blocks for all non-trivial choices (see references/decision-protocol.md)
- Non-interactive mode (--auto) support at all decision points
