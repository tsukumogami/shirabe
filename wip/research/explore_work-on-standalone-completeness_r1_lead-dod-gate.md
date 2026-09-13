# Lead: Why does `/work-on`'s definition-of-done gate return `cannot_verify`, and is that the same defect as the boundary problem or an independent one?

## Findings

### The gate itself

The gate lives in the `verification` koto state, `skills/work-on/koto-templates/work-on.md:592-628`. It sits between `qa_validation` and `finalization`. Its `accepts` block declares the enum:

```
skills/work-on/koto-templates/work-on.md:594-597
      verification_outcome:
        type: enum
        values: [passed, failed, cannot_verify]
        required: true
```

Transitions (`work-on.md:610-628`):

- `passed` -> `finalization` (line 612-614)
- `failed` -> `implementation`, to fix and re-run the panels (line 617-619)
- `cannot_verify` -> `done_blocked`, with the comment: "Fail closed (R11): this must not reach a clean finalization. Route to the blocking terminal so it surfaces as a human decision." (line 620-628)

The companion prose state (`work-on.md:1082-1131`, section `## verification`) tells the agent to read the project's verification map, classify the issue's changed files against it, run matched commands (or the default), and submit `cannot_verify` "when verification cannot be determined (no map entry matched and no usable default, or a command could not run)." `SKILL.md:54-96` (`## Definition of Done`) restates the same three outcomes in prose, explicitly: "Cannot-verify ... fails closed: it must never read as 'verified' and never silently advances. It halts as a blocking condition that surfaces to the human."

### What `cannot_verify` does to the run

`done_blocked` is a real terminal: `terminal: true, failure: true` (`work-on.md:826-834`). Its prose (`work-on.md:1209-1223`) says "The workflow reached a blocking condition that requires human intervention" and that recovery is a manual `koto rewind`. So `cannot_verify` **blocks**, it does not warn-and-continue: the run stops before `finalization`, before `pr_precheck`, before any PR is opened or CI is watched. This is not the same defect shape as "PR opened but nothing finishes it" — here nothing downstream happens at all once verification returns `cannot_verify`.

### The verification map (`skills/work-on/references/verification-map.md`)

Read in full. It defines the contract the gate consumes:

- A **verification map** is a project-declared list of entries, each pairing a path-glob with one or more verification commands (`verification-map.md:15-17`), plus an optional default command (`verification-map.md:18-19`).
- It lives in the adopting repo's own extension file: "`/work-on`'s definition-of-done gate reads a project's verification map from that project's extension file, `.claude/shirabe-extensions/work-on.md`" (`verification-map.md:3-4`).
- Matching is additive across entries (`verification-map.md:32-34`); no match falls through to the default (`verification-map.md:35-37`); **"No match and no default -- or a matched/default command that cannot run -- yields cannot-verify, and the gate fails closed"** (`verification-map.md:38-40`).
- The doc is explicit that it is "generic and project-agnostic: it carries no project-specific commands. A project declares its own commands in its extension file" (`verification-map.md:8-9`).

`SKILL.md:296-298` states the fallback when the file is entirely absent: "If no extension file exists at `.claude/shirabe-extensions/work-on.md`, the skill proceeds with generic behavior: no language-specific quality checks." Combined with the verification-map contract, the arithmetic is direct: no extension file means no map entries and no default command, so every issue's diff matches nothing and there is nothing to fall through to -- `cannot_verify` is not a possible outcome in that situation, it is the *only* outcome, on every run, for that repo.

### Does shirabe have a verification map, and does the gate find it?

Yes. `.claude/shirabe-extensions/work-on.md` is tracked in git (`git ls-files` confirms it, alongside `.claude/shirabe-extensions/README.md`), and the repo's `.gitignore` carves an explicit exception for it:

```
.gitignore:17-20
!.claude/settings.json
# And shirabe's own /work-on extension (verification map; must ship in the repo)
!.claude/shirabe-extensions/
!.claude/shirabe-extensions/work-on.md
```

Its content is a working map:

```
.claude/shirabe-extensions/work-on.md:7-15
## Verification map

- `skills/**` -> `scripts/run-evals.sh <skill>`

### Default verification command (when no map entry matches; all must pass)

- `cargo test --workspace`
- `skills/plan/scripts/plan-to-tasks_test.sh`
- `skills/execute/scripts/run-cascade_test.sh`
```

This is loaded the normal way the gate expects: `SKILL.md:21` `@.claude/shirabe-extensions/work-on.md` pulls it into context on every `/work-on` run. Nothing in the gate's mechanism is shirabe-specific -- shirabe just did the one thing every adopting repo is supposed to do. The design doc for this feature says so explicitly when explaining why shirabe ships its own map: "The extension is consumer-side by design; for `/work-on` operating on shirabe-the-repo, the file must exist in shirabe's working tree, so shipping it here is what makes shirabe enforce its own rule... shirabe is just the first project to declare a map" (`docs/designs/current/DESIGN-work-on-definition-of-done.md:130-134`).

Because shirabe declared entries covering `skills/**` plus a default that covers everything else, an issue touching shirabe should essentially never hit `cannot_verify` (barring a command that errors at runtime). That the map is present and functional for the one repo we can inspect, and absent by definition for a repo with no extension file, is the whole story: **shirabe having a map and other repos returning `cannot_verify` is not a coincidence needing a gate fix -- it is the fail-closed contract operating exactly as specified.**

The design's own "Consequences" section names this outcome ahead of time, as an accepted trade-off rather than a bug:

```
docs/designs/current/DESIGN-work-on-definition-of-done.md:220-224
Negative / mitigations:

- A project with no map and no detectable test command hits the fail-closed human gate every
  run; mitigation: declaring a one-line default test command removes it -- fail-closed is the
  safe direction (R11), not an accident.
```

### Does `/execute` have an equivalent gate?

Yes, and it is not a separate implementation -- it is the literal same template. `/execute`'s per-issue children are koto-materialized using `/work-on`'s own template file:

```
skills/execute/koto-templates/execute.md:305
      default_template: ../../work-on/koto-templates/work-on.md
```

`skills/execute/SKILL.md:26-31` states this directly: "`/execute` runs a single-pr PLAN end-to-end by lifting `/work-on`'s plan-orchestrator template ... and pointing each per-issue child at `/work-on`'s `work-on.md`." Every per-issue child spawned by `/execute` runs the exact same `verification` state, reads the exact same `.claude/shirabe-extensions/work-on.md` in that child's repo, and is bound by the identical fail-closed transition to `done_blocked` on `cannot_verify`. There is no `/execute`-specific verification logic to diverge from `/work-on`'s -- they share the file byte-for-byte via a cross-skill template reference (`skills/execute/SKILL.md:171-174`), and `scripts/validate-template-mermaid.sh` enforces that shared states like this stay identical across templates (per the `pr_precheck` comment at `work-on.md:709-711`, which names the same mechanism). So a repo missing an extension file will produce `cannot_verify` whether the issue is worked via standalone `/work-on` or via an `/execute` run dispatching that issue to a `/work-on` child -- the symptom is orthogonal to which of the two candidate directions (`/work-on` folded into `/execute`, or kept standalone) is chosen, because both paths funnel through the same gate reading the same per-repo file.

## Implications

- `cannot_verify` is not evidence of a broken or half-implemented gate. The gate's own spec (`verification-map.md`) defines "no map, no default" as a valid, intentional input that must produce `cannot_verify`, and the design doc anticipated exactly this failure mode as a "negative but accepted" consequence with a one-line fix (declare a default command).
- It is also not a `/work-on`-vs-`/execute` boundary issue: both entry points reach the same state via the same shared template file, so neither "fold `/work-on` into `/execute`" nor "keep `/work-on` standalone" changes anything about whether this fires. Whatever caused the two adopting repos to hit `cannot_verify`, it will keep firing under either candidate direction unless those repos add `.claude/shirabe-extensions/work-on.md`.
- Given the visibility constraint, I could not inspect the two adopting repos named in the symptom report from this worktree (I'm scoped to the shirabe worktree only), so I cannot directly confirm they lack the extension file. But the code gives no other path to `cannot_verify`: the only documented triggers are (1) no map entry matches and no default exists, or (2) a matched/default command exists but errors before producing a result (`verification-map.md:38-40`). Given that shirabe's own map is proven functional and the file is entirely repo-authored (nothing in `/work-on` or `/execute` scaffolds it automatically -- confirmed by grepping `phase-1-setup.md` and finding no scaffolding logic), the parsimonious read is that the two repos simply hadn't authored the file (or authored one whose default doesn't cover the issue's changed files).

## Surprises

- The `/execute` and `/work-on` "equivalent gate" question turned out to have an unusually strong answer: they aren't two implementations that happen to behave the same, they are one file. `execute.md:305`'s `default_template` points straight at `work-on.md`. This makes the "is `cannot_verify` the same defect as the boundary problem" question almost answer itself: the boundary problem is about what happens *after* a clean finalization (PR opened but not finished); `cannot_verify` is about never *reaching* a clean finalization in the first place, in a state that both `/work-on` and `/execute` share unmodified. They intervene at different points in the state machine and neither entry point changes the other's exposure to it.
- The design doc for this feature (`DESIGN-work-on-definition-of-done.md`) essentially pre-wrote the postmortem for this exact symptom, months before it was reported, and even prescribed the fix ("declaring a one-line default test command removes it").
- `SKILL.md:296-298`'s "generic behavior: no language-specific quality checks" undersells the actual effect. Read casually it sounds like "the gate is skipped" or "less strict"; combined with `verification-map.md`'s fail-closed rule, the actual effect is the opposite: the issue *cannot* reach `finalization` at all without a human rewind.

## Open Questions

- Do the two adopting repos actually lack `.claude/shirabe-extensions/work-on.md`, or do they have one whose glob/default doesn't cover the changed files in those specific issues? Not determinable from this repo alone -- would need to inspect those repos directly.
- Is there a reason those repos wouldn't have authored the file yet -- e.g., were they onboarded to `/work-on` before this definition-of-done feature shipped, and never went back to add the extension? That would make this an onboarding/rollout gap rather than a per-run mystery, but it's not visible from shirabe's own history alone.
- Should `/work-on` (or its onboarding path) proactively scaffold a starter `.claude/shirabe-extensions/work-on.md` (e.g., with just a default test command) the first time it runs in a repo that lacks one, to convert an unbounded `cannot_verify` block into an explicit one-time setup step? Nothing in the current code does this today.

## Summary
`cannot_verify` fires exactly as the gate's own spec says it should: a repo with no `.claude/shirabe-extensions/work-on.md` (or one whose map/default doesn't cover the changed files) has nothing for the verification state to run, and the state fails closed to the blocking `done_blocked` terminal by design (`verification-map.md:38-40`, anticipated explicitly in `DESIGN-work-on-definition-of-done.md`'s consequences section). Since `/execute`'s per-issue children run the identical `work-on.md` template (`execute.md:305`), this is a per-repo configuration gap orthogonal to both candidate directions in the boundary question, not a variant of the "PR opened but nothing finishes it" defect. The open question is empirical, not architectural: whether the two adopting repos are simply missing the extension file, which this worktree cannot confirm directly.
