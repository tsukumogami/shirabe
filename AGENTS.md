# Agent Guidelines for shirabe

This is a skills repository. The quality of skills is validated through evals,
not just code review. These guidelines apply to any agent working on this repo.

## Eval Requirement

When adding or modifying a skill:

1. **Write eval scenarios** in `skills/<name>/evals/evals.json` that cover the
   skill's key behaviors. Each eval has a prompt (what a real user would say),
   expected output (what the skill should produce), and assertions (objectively
   verifiable checks).

2. **Run evals using /skill-creator** before considering the work done. Use
   `scripts/run-evals.sh <skill-name>` to set up the eval workspace, then
   spawn agents with the skill loaded and without (baseline), grade against
   assertions, and generate the eval viewer for human review.

3. **Iterate based on eval results.** If an eval fails or produces unexpected
   output, fix the skill and re-run. Don't ship skills that haven't been
   validated against their eval scenarios.

This applies to:
- New skills (write evals during skill creation)
- Skill modifications (run existing evals + add new ones for changed behavior)
- Specification changes (reference files, format specs) that affect skill behavior

## Eval Structure

Evals are co-located with their skill, not in a central directory:

```
skills/<name>/
  SKILL.md
  evals/
    evals.json                # This skill's eval scenarios + assertions
    workspace/                # gitignored; created by run-evals.sh
      iteration-N/
        <eval-name>/
          with_skill/outputs/   # Agent outputs with skill loaded
          without_skill/outputs/ # Baseline outputs without skill
          eval_metadata.json    # Prompt + assertions for this eval
          grading.json          # Pass/fail per assertion
          timing.json           # Token count and duration
        benchmark.json          # Aggregated results for this iteration
```

## Running Evals

Two paths: automated (CLI/CI) and interactive (Claude Code session).

### Automated (CLI / CI)

```bash
# List skills that have evals
scripts/run-evals.sh --list

# Run evals end-to-end (prep + execute via claude -p + validate)
scripts/run-evals.sh decision

# Run all skills
scripts/run-evals.sh --all

# Re-validate the latest iteration without re-running
scripts/run-evals.sh --validate decision
```

### Interactive (Claude Code with /skill-creator)

```bash
# Prepare workspace only
scripts/run-evals.sh --prep-only decision
```

After `--prep-only`, invoke `/skill-creator` in your Claude Code session and
point it at the prepared workspace. This gives a tighter feedback loop: the
skill-creator handles agent spawning, grading, and the eval viewer within
your session. After running, validate with `scripts/run-evals.sh --validate decision`.

## Skill Quality Standards

Skills in this repo follow the patterns documented in the skill-creator skill:
- Progressive disclosure (SKILL.md under 500 lines, reference files under 300)
- Imperative instructions that explain "why" not just "what"
- Decision blocks for all non-trivial choices (see references/decision-protocol.md)
- Non-interactive mode (--auto) support at all decision points
