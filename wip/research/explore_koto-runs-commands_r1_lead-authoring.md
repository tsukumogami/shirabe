# Lead: What authoring guidance, validation, and working examples exist for koto default actions — is rewriting shirabe's templates a documentation-following exercise or a trailblazing one?

## Findings

**1. koto's own agent-facing skills barely mention `default_action`.**

`koto-author/references/template-format.md` (882 lines, the authoring reference) contains exactly one substantive mention of `default_action`: a single row in the "Feature-to-action mapping" table, `template-format.md:142`: `| State with default_action + requires_confirmation | confirm |`. There is no schema section, no field list, no worked example, and no prose explaining what `default_action` does, when to reach for it, or how `requires_confirmation`/`polling` interact. The only other authoring-doc mention is `koto-author/references/batch-authoring.md:88`, a single sentence noting a `default_action` can be one of three ways to write `failure_reason` in a batch worker's terminal state — again no schema.

`koto-author/SKILL.md` never mentions `default_action`, `ActionDecl`, or the `confirm` action value at all. Its own action-dispatch instructions to the authoring agent (`SKILL.md:63-66`) list only `evidence_required`, `gate_blocked`, and `done` — omitting `confirm` and `integration`/`integration_unavailable` outright, even though `template-format.md`'s own mapping table two sections later documents `confirm` as a real value. The 8-state "What to expect" walkthrough (`SKILL.md:88-96`) and the "Reference material" pointer list (`SKILL.md:98-107`) never route an author toward default-action authoring at all.

By contrast, `koto-user/SKILL.md` (the skill for an agent *running* a koto-backed workflow, not authoring one) documents the runtime side correctly: the action-dispatch table at `koto-user/SKILL.md:65-76` has a `confirm` row — "A default action ran and requires your confirmation before advancing. Read `directive` and `action_output` (command, exit code, stdout, stderr). Confirm if correct, or submit evidence to redirect." So the *consumer* contract is documented; the *producer* (authoring) contract is not.

**2. Compile-time validation exists, but not where the lead's file list expected it.**

`src/config/validate.rs`, `src/engine/batch_validation.rs`, and `src/export/check.rs` contain zero references to `default_action` or `ActionDecl` — none of them touch action validation. `src/template/compile.rs` also does no semantic validation of `default_action`: it just deserializes `SourceActionDecl` (`compile.rs:86-94`: `command`, `working_dir`, `requires_confirmation`, `polling`) and maps it 1:1 into the compiled `ActionDecl` (`compile.rs:239-247`).

The real validation lives in `src/template/types.rs:806-853`, inside `CompiledTemplate`'s validate method, and it's more thorough than a skim suggests:
- Rejects a state declaring both `integration` and `default_action` (`types.rs:807-812`) — this matches the mutual-exclusion rule stated as an assumption in `docs/designs/current/DESIGN-default-action-execution.md:93` and specified again at line 262-263 ("Compile-time validation: reject states with both `integration` and `default_action`").
- Rejects an empty `command` string (`types.rs:814-818`).
- Validates `{{VAR}}` references in both `command` and `working_dir` against the declared `variables` block, reusing `extract_refs` (`types.rs:820-843`), also as the design doc specified.
- Requires `polling.timeout_secs > 0` when `polling` is declared (`types.rs:845-852`).

What's silently accepted: `SourceActionDecl` (`compile.rs:84-94`) has no `#[serde(deny_unknown_fields)]`, unlike its sibling `SourceState` which explicitly carries that attribute with a comment explaining why (`compile.rs:39-42`: "so that typos or unknown keys in template source are caught at compile time"). A typo inside a `default_action` block — `confirmation: true` instead of `requires_confirmation: true`, say — is silently dropped by serde and the action executes without confirmation rather than failing to compile. That's a safety-relevant gap for a feature whose entire design rationale (`DESIGN-default-action-execution.md`, "Safety via reversibility") is that irreversible actions must require confirmation. There's also no upper bound on `polling.interval_secs`/`timeout_secs` and no check relating the two (an interval larger than the timeout compiles fine), and no validation that `working_dir` exists on disk (unsurprising — it's resolved at runtime relative to session cwd, not compile time).

**3. A working example exists — but only in koto's own Rust test suite, nowhere in any `.md` file.**

`grep -rln "default_action:" --include="*.md" .` across the entire koto repo returns exactly one hit: `docs/designs/current/DESIGN-default-action-execution.md` itself (a design-doc code snippet, not a usable template). No template under `test/`, `tests/`, `docs/`, or `plugins/` declares `default_action`. The working, verified example lives in `tests/integration_test.rs:3846-3870`, function `template_with_default_action_creating_file`:

```yaml
---
name: action-workflow
version: "1.0"
initial_state: setup
states:
  setup:
    default_action:
      command: "touch marker.txt"
    gates:
      file_exists:
        type: command
        command: "test -f marker.txt"
    transitions:
      - target: done
  done:
    terminal: true
---

## setup

Run setup action.

## done

All done.
```

The paired test `default_action_creates_file_and_auto_advances` (`tests/integration_test.rs:3877-3924`) runs it end-to-end via `koto next`, asserting the state auto-advances to `done`, the file is actually created, and a `default_action_executed` event lands in the session's state file. `tests/integration_test.rs:3926` and `tests/status_phase_retrieval_test.rs:190,459` cover the override-skips-action and `koto status`-does-not-execute-actions cases respectively. So the feature is real and tested — just not documented anywhere an author would read.

**4. `CHANGELOG.md` never mentions `default_action`.** The changelog's most recent dated release is `[0.10.0] - 2026-05-24` (`CHANGELOG.md:75`); everything since, including this feature (issue #71), sits under `[Unreleased]` with no entry naming it. `Cargo.toml:16` currently reads `version = "0.11.7-dev"`.

**5. No documented rule for choosing gate vs. default_action vs. prose instruction.** A repo-wide search for language like "when to use a gate" or "action vs gate" turns up nothing except `docs/prds/PRD-koto-next-output-contract.md:150`, which asks `template-format.md` to document the *details-vs-directive* split and the feature-to-action-value mapping table — not a decision rule between authoring mechanisms. `template-format.md`'s Layer 3 (gates) and its one-line `default_action` table row sit in the same document but are never cross-referenced against each other. An author deciding "should this be a `command` gate the agent runs and reports on, or a `default_action` koto runs itself" has no guidance either way.

**6. shirabe's own templates and tooling never touch `default_action`.** `grep -rln "default_action" --include="*.md" public/shirabe` (excluding `wip/`) returns nothing. `docs/guides/koto-context-patterns.md` doesn't mention it. shirabe's template-checking scripts (`scripts/check-template-interpolation.sh`, `scripts/validate-template-mermaid.sh`) validate `{{VAR}}` interpolation and mermaid-diagram/template consistency — not action semantics. CI's `validate-templates.yml` (`.github/workflows/validate-templates.yml:28-30`) just runs `koto template compile` against every `koto-templates/*.md` file, which would catch the compile-time checks above but nothing about whether `default_action` is used well or safely.

**7. No version-compatibility blocker.** shirabe declares only `koto\tversion\t-\talways` in its preflight declarations (e.g. `scripts/skill-preflight_test.sh:308`) — a bare "must have some koto" requirement with no floor — and its install path is `tsuku install koto@latest` (`scripts/lib/preflight-report_test.sh:629,676`). koto's own `koto-author/SKILL.md:26` currently requires `koto >= 0.11.7`, matching the live `Cargo.toml` version (`0.11.7-dev`) in which `default_action` is fully implemented and tested. Since shirabe always installs latest and never pins below the version where this landed, there's nothing blocking shirabe's templates from using `default_action` today.

## Implications

Rewriting shirabe's templates to use `default_action` is a trailblazing exercise, not a documentation-following one. The engine feature is solid — implementation and validation are more careful than the doc surface suggests (integration-exclusion, empty-command rejection, var-ref checking, polling-timeout floor all real) — but the *authoring* path is close to unwritten. Whoever does this work will be inventing conventions as they go: there is no reference schema to copy from a `.md` doc (only a Rust test to reverse-engineer), no stated rule for gate-vs-action-vs-prose, and the authoring skill's own action-dispatch table doesn't even list the `confirm` value its own template-format guide says to expect. This mirrors a document/runtime split the codebase already has once (koto-user documents `confirm` correctly; koto-author doesn't) — the new work would need to close that gap for itself before shirabe's authors can follow anything resembling a paved path.

## Surprises

- The lead's suggested validation files (`src/config/validate.rs`, `src/engine/batch_validation.rs`, `src/export/check.rs`) were a dead end — none of them touch `default_action`. The real validation is in `src/template/types.rs`'s `CompiledTemplate::validate`, not `src/template/compile.rs` as the design doc's own file list implies (`DESIGN-default-action-execution.md:402` names only `src/template/compile.rs` for "YAML parsing for default_action", not mentioning where the semantic checks actually landed).
- `SourceActionDecl` is the one state-level YAML sub-struct that opted out of `deny_unknown_fields`, in a codebase that otherwise treats unknown-field rejection as a first-class authoring safety net (`compile.rs:39-42`'s comment explains the *general* policy precisely, then `SourceActionDecl` quietly doesn't follow it).
- koto-author's SKILL.md dispatch table is stale relative to its own template-format.md reference — an internal inconsistency inside koto's docs, not just an absence.

## Open Questions

- Should `default_action` authoring guidance land in `template-format.md` (extending the existing Layer 1-3 structure) or as a new Layer, given it changes engine behavior (auto-execution) rather than just being a routing primitive like gates?
- Is the missing `deny_unknown_fields` on `SourceActionDecl` intentional (forward-compat for a sub-struct that might grow fields) or an oversight that should be fixed before shirabe author agents start writing `default_action` blocks by hand?
- Does shirabe want a template-level lint (beyond `koto template compile`) that flags a `default_action` with `requires_confirmation: false` on a command matching known-irreversible patterns (`gh pr create`, `git push`, etc.), given the design's own safety principle is "reversibility" but nothing enforces it automatically?

## Summary
koto-author's SKILL.md and template-format.md give an authoring agent almost nothing on `default_action` — one table row, no schema, no example, and the SKILL.md's own action-dispatch table omits the `confirm` value that default_action produces; the only real, verified example lives in a Rust integration test, not any `.md` file. Compile-time validation is real and reasonably careful (integration/default_action mutual exclusion, empty-command rejection, `{{VAR}}` checking, polling-timeout floor, all in `src/template/types.rs:806-853`) but the sub-struct itself accepts unknown fields silently, and there's no documented rule anywhere for choosing gate vs. default_action vs. prose. shirabe pins no koto version floor and always installs latest, so nothing blocks adoption technically — but rewriting shirabe's templates means establishing authoring conventions from scratch, not following an existing paved path.
