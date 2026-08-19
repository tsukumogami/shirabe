# Lead: Does the `/scope` eval suite load phase references, or only `SKILL.md` — and what breaks if the two reduction sections are deleted?

## Findings

### 1. What is actually in an eval agent's context

`scripts/run-evals.sh` never invokes `/scope` as a skill. It builds one
large prompt and hands it to a single `claude -p` process
(`scripts/run-evals.sh:391-436`), which is told to invoke `/skill-creator`
and, per scenario, to spawn "a with-skill agent (reads the skill SKILL.md
then executes the prompt) and a without-skill baseline agent"
(`scripts/run-evals.sh:428`). The skill is named by filesystem path, not
loaded: `The skill is at: $skill_dir/SKILL.md`
(`scripts/run-evals.sh:394`).

Three consequences follow, and they are the whole answer to this lead.

**The agent has the entire repository, not a fixed context.** `claude -p`
runs in the checkout (CI: repo root, `.github/workflows/run-evals.yml:20-22`),
and the spawned agents inherit it with full tool access. Nothing sandboxes
the skill directory. So "does the eval agent load phase references" is not
a property of the harness — it is a behavior of the agent, and the only
thing steering it is `SKILL.md`'s own pointers.

**Those pointers are resolvable.** `/scope`'s phase references are written
as literal repo-relative paths —
`skills/scope/references/phases/phase-2-chain-orchestration.md`
(`skills/scope/SKILL.md:386`, `:413-419`) — so an agent reading SKILL.md
from the repo root can open them directly. The pattern-level references
use `${CLAUDE_PLUGIN_ROOT}/references/...`, which is unset in this harness;
those resolve only if the agent guesses the repo root (a `references/`
directory does exist there, so the guess usually works).

**Every `/scope` eval is tier 1, i.e. plan-only.** All 30 evals carry no
`tier` key, so the runner emits the tier-1 instruction for each of them:
`Read the skill file and describe the exact sequence of commands you would
run. Do NOT execute any commands.` (`scripts/run-evals.sh:376-378`). No
`/scope` eval has `fixture_dir`, none has `tier: 2`, none has
`preflight`. The suite grades a description, never a run.

### 2. Three harness defects that weaken every claim about what "passes"

These are not the subject of the lead but they bear directly on whether
"eval 17 presumably passes" is evidence of anything.

**`expectations` is never read.** The prep step writes
`"assertions": eval_item.get("assertions", [])` into each eval's
`eval_metadata.json` (`scripts/run-evals.sh:186`). `/scope`'s evals use
the key `expectations`, not `assertions`
(`skills/scope/evals/evals.json`, every eval). So the metadata file the
grading step is pointed at — "Grade each with-skill run against the
assertions in eval_metadata.json" (`scripts/run-evals.sh:430`) — carries
an empty list for all 30 `/scope` evals. The grader can recover them only
by opening `evals.json` itself, which the top-level prompt does name
(`:395`). Fourteen of eighteen suites are in this state; only `decision`,
`release`, `review-plan`, `writing-style` (and `explore`, which carries
both keys) use `assertions`.

**`expected_output` is never propagated.** The metadata dict is
`{eval_id, eval_name, prompt, assertions}` (`scripts/run-evals.sh:182-187`).
The rich `expected_output` narrative — which is where most of eval 17's
and eval 18's substance lives — never reaches the workspace.

**`files:` is inert.** Ten `/scope` evals declare precondition files
(evals 2, 6, 8, 9, 10, 12, 13, 23, 24, 30 — e.g. eval 8's
`docs/prds/PRD-test-topic.md`), but the prep step materializes only
`fixture_dir` (`scripts/run-evals.sh:191-206`). `files` is read nowhere in
the script. So `us-2-prd-auto-skip` runs against a prompt of `/scope
test-topic` with no PRD on disk and no statement that one exists.

**Nothing gates on evals.** `run-evals.yml` fires on a weekly cron and
`workflow_dispatch` only — never on `pull_request`. The only PR-time eval
check is `check-evals.yml`, which runs `scripts/check-evals-exist.sh`
(every skill has ≥1 eval). No eval result can block an edit to
`skills/scope/SKILL.md`.

**No results are committed.** `skills/scope/evals/` contains only
`evals.json`; there is no `workspace/` directory anywhere in the repo and
no `grading.json` on disk. There is no record in this checkout that eval
17 — or any `/scope` eval — has ever passed.

### 3. Eval 17 resolved: it does not depend on the two reduction sections

`chain-shape-is-constant` (`skills/scope/evals/evals.json`, id 17) has
prompt `/scope refactor-topic  (the author says the problem and the
requirements are settled; they only want to talk about architecture)` and
four expectations. Every one of them is satisfied by
`skills/scope/SKILL.md:421-470` — the `## Chain-Proposal Output` section,
which sits **above** line 472 and is untouched by the proposed deletion:

| Expectation | Surviving source |
|---|---|
| runs the whole chain, does not offer a shortened one | `SKILL.md:435` "The proposal never offers a shorter chain." |
| skipping the BRIEF would be a judgment about an unwritten document | `SKILL.md:438-440` "Phase 1 has no artifact to decide against. A shorter chain offered here would be a verdict on documents nobody has written" |
| points at `/design` directly; says plainly this does not reach a smaller artifact set, which Phase 2's judgment decides after the fact | `SKILL.md:442-445` "An author who wants to start above `/brief` still invokes `/design` or `/plan` directly. That buys a shorter conversation, not a smaller artifact set: inside `/scope`, the set is settled per hop after the artifacts land." |
| a redundant BRIEF is removed by the Phase 2 consolidation judgment, after both documents exist | `SKILL.md:436-437` "the consolidation judgment does exactly that in Phase 2" + `:444-445` |

So the answer to the lead's central hypothesis is **no**: eval 17 needs
neither `## Why the Artifact Set Shrinks` (472) nor `## Consolidation
Judgment` (532), and it does not need a phase file either. It passes off
`SKILL.md:435-445` alone. Round 1's flag on eval 17 is wrong. The
duplicated material at 472-578 is a *third* statement of what 435-445
already says, not the source eval 17 reads.

This also dissolves the lead's framing tension. Eval 17 and the live
incident are not the same failure. Eval 17 grades whether the agent
*declines to offer a shorter chain at Phase 1*. The incident is an agent
that accepted the full chain, then produced only the PLAN and asserted in
prose that the upstream had been consolidated away. Nothing in eval 17
touches that.

### 4. The evals that *do* require a phase file

Four evals grade content that exists **only** in
`phase-2-chain-orchestration.md`, with no counterpart anywhere in
`SKILL.md`:

- **18 `no-durable-artifact-floor`.** Three of its five expectations —
  the two reasons the keep-forcing guard is wrong, the single-mechanism
  rule not catching it, and the `/execute` finalization-guard routing —
  appear only at
  `skills/scope/references/phases/phase-2-chain-orchestration.md:719-739`.
  `SKILL.md:524-525` states the conclusion ("There is no durable-artifact
  floor; the prohibition on reintroducing one lives beside the judgment in
  Phase 2") and explicitly defers the reasoning.
- **19 `consolidation-absorb-brief-into-prd`.** Ten expectations covering
  the Stage 1 citation preflight and its exit-code routing, the carry
  check, the `upstream:` splice, the pinned `## Status` line, and the
  commit ordering. `SKILL.md:559-572` gives a four-sentence gloss;
  the graded procedure is `phase-2:554-718`, and `SKILL.md:574-577` says
  so in as many words.
- **20 `consolidation-keep-when-upstream-holds-more`** and
  **21 `consolidation-carry-check-failure-aborts-absorb`.** Same shape —
  stage names, `consolidation_judgments:` field values, abort semantics,
  all only in phase-2.

If the eval agent read only `SKILL.md`, these four would already be
failing today. Either they fail (and nobody has noticed, since no results
are committed and evals do not gate PRs), or the agent does open phase
files — in which case the phase files are the operative surface and
`SKILL.md:472-578` is not load-bearing for any eval.

### 5. Consumers that break on deletion

A repo-wide grep for both section titles (excluding `wip/`) returns
exactly four non-`wip` sites:

- `skills/scope/SKILL.md:472` — the heading itself.
- `skills/scope/SKILL.md:532` and `:576` — the heading, and the
  cross-pointer "…live in the Consolidation Judgment section of
  `skills/scope/references/phases/phase-2-chain-orchestration.md`."
- **`skills/brief/references/phases/phase-0-setup.md:313-315`** — the one
  external by-title citation: "See the Consolidation Judgment section of
  `skills/scope/references/phases/phase-2-chain-orchestration.md` and the
  \"Why the Artifact Set Shrinks\" section of `skills/scope/SKILL.md`."
  The first half survives (it points at phase-2). The second half dangles
  on deletion and must be dropped or re-pointed at
  `phase-2-chain-orchestration.md:488-500`.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:427,
  429, 443, 671` — the design doc that specified these sections. It is a
  historical record of a shipped design, not a live consumer; a
  Superseded/Accepted design describing sections that no longer exist is
  normal drift, though the author may want a line in the follow-up.

**`brief`'s eval 3 is not at risk.** `rich-issue-still-produces-a-brief`
(`skills/brief/evals/evals.json`, id 3) grades that a redundant brief is
removed by `/scope`'s consolidation judgment after a per-section carry
check — and `skills/brief/references/phases/phase-0-setup.md:309-315`
states all of that in its own prose before citing `/scope`. Deleting
`/scope`'s sections leaves the eval's grounds intact; only the citation
tail at `:315` needs fixing.

**No CI job does a structural grep on SKILL.md sections.** The scripts
under `scripts/` that touch skills are `check-skill-injection.sh`
(load-time `!`-prefixed commands), `check-skill-requires.sh`
(`requires.tsv` conformance), `check-evals-exist.sh` (≥1 eval per skill),
`check-tool-diagnostic-discards.sh`, `check-no-duplicate-rule-list.sh`
(writing-style rules only), and `check-bash-floor.sh`. None reads section
headings. `check-scope-scripts.yml` greps only for a regex shared between
`skills/scope/scripts/check-citations.sh` and
`crates/shirabe-validate/src/formats.rs`. `crates/` contains no reference
to either section title.

**`/charter` has no counterpart to break.** Neither title appears in
`skills/charter/`, and no eval in any suite references `/scope`'s section
names. The one adjacent precedent is in `/plan`: evals 17
(`execution-mode-rule-on-skill-surface`) and 26
(`coordinated-rule-surface-binds-not-restates`) explicitly grade
*placement*, asserting the rule is "on the plan SKILL.md surface (not
lazily loaded in a phase file)" and that the SKILL.md "binds to the
contract and does NOT restate it". `/scope` has no such placement eval for
the reduction rule, in either direction. Deletion is therefore
eval-unconstrained.

### 6. Is there an eval that would catch the incident?

**No.** All 30 `/scope` evals are tier 1: the agent is instructed to
"describe the exact sequence of commands you would run. Do NOT execute
any commands" (`scripts/run-evals.sh:377-378`). Grading is over that
description. An agent that describes the four-child chain correctly and
then, in a live run, writes only a PLAN and claims consolidation in prose
would score a clean pass on every eval in the suite — including 7, 17, 19,
20 and 21, all of which the incident agent's *description* would satisfy.

The closest anything comes is eval 7 (`us-1-cold-standalone-full-run`),
which expects `planned_chain: [brief, prd, design, plan]`, per-child
`parent_orchestration:` sentinel writes, and
`consolidation_judgments:` entries. But it grades the claim, not the
filesystem: nothing checks that `docs/briefs/BRIEF-test-topic.md` was
written, that a judgment ran against two bodies that exist, or that
`exit_artifacts:` names files present on disk. `/execute` and `/work-on`
carry tier-2 evals that execute real workflows against an isolated clone
(`scripts/run-evals.sh:229-267`); `/scope` carries none.

That is a real coverage gap: the suite can prove `/scope` *says* the right
thing and cannot prove it *does* it. Reporting it only, per the author's
constraint that mechanism is out of scope for this issue.

## Implications

1. **Deleting `SKILL.md:472-578` breaks no eval.** Eval 17 reads
   `435-445`; evals 18-21 read phase-2. The only edit forced by the
   deletion is one line of prose in another skill:
   `skills/brief/references/phases/phase-0-setup.md:315`.
2. **The navigational pointers survive.** After deletion, `SKILL.md` still
   names the consolidation judgment at `:43`, `:299` (Phase 2 table row,
   pointing at the phase file), `:384-386`, `:419`, and `:437`. An agent
   that follows the workflow table reaches phase-2 without the deleted
   sections. If `## Consolidation Judgment` is rewritten as a bounding
   statement rather than deleted, it should keep the `:574-577` pointer
   sentence, which is the only prose that names phase-2 as the home of the
   eight-step procedure and the floor prohibition.
3. **Existing eval coverage is not evidence about the incident.** The
   suite is entirely plan-only, its results are not committed, its
   `expectations` never reach the grader's metadata file, and it does not
   run on PRs. "Eval 17 passes" cannot be verified from this checkout and
   would not, if true, be evidence that `/scope` executes correctly.
4. **The incident's failure mode is unreachable by any current eval.**
   Any future work on this would need a tier-2 `/scope` eval that runs the
   chain against an isolated clone and asserts on files on disk. The
   harness already supports that shape (`setup_tier2_isolation`); `/scope`
   just does not use it.

## Surprises

- **Round 1's premise about eval 17 is wrong, and in an instructive
  direction.** Eval 17 is satisfied entirely by the Chain-Proposal Output
  section. That means `SKILL.md` states the "shorter conversation, not a
  smaller artifact set" rule *twice* — at `435-445` and again at
  `508-517` — before phase-1-discovery states it a third time at `38-49`.
  The duplication the issue is about is worse than a two-way duplicate.
- **`expectations` vs `assertions`.** The runner reads a key that 14 of 18
  suites do not use. The graded criteria reach the workspace metadata as
  an empty list for `/scope`. This is a live defect in
  `scripts/run-evals.sh:186`, unrelated to this issue but worth filing.
- **`files:` is declared and ignored.** Ten `/scope` evals name
  precondition artifacts that the harness never creates. Evals like
  `us-2-prd-auto-skip` and `us-3a-prd-boundary-re-evaluation` are, as
  executed, indistinguishable from a bare `/scope test-topic`.
- **`/plan` already has placement evals and `/scope` does not.** The repo
  demonstrably knows how to pin "this rule lives on the SKILL.md surface"
  as a graded property (`skills/plan/evals/evals.json`, ids 17 and 26).
  No equivalent exists for `/scope`'s reduction rule, so nothing in the
  eval corpus asserts where it should live.
- **Evals never gate a PR.** Weekly cron plus manual dispatch only. The
  practical consequence for this issue: the eval suite cannot object to
  the edit, but it also cannot confirm it.

## Open Questions

- Have `/scope`'s evals ever been run against the current SKILL.md? No
  workspace or grading artifact exists in the checkout, and the weekly
  workflow's results are not persisted here. If the author has run
  output elsewhere, evals 18-21 are the ones to check — they are the
  proof that the with-skill agent opens phase files.
- Should `skills/brief/references/phases/phase-0-setup.md:315` be
  re-pointed at `phase-2-chain-orchestration.md:488-500` (the surviving
  "why") or simply dropped, given the sentence's first half already cites
  phase-2? This is inside `/brief`, and the author constrained this issue
  to `/scope` — so it may need to be a separate follow-up rather than part
  of the same edit.
- Is the `expectations`/`assertions` key mismatch worth a separate issue?
  It is a harness bug affecting all 18 suites, not a `/scope` prose
  concern.

## Summary

The `/scope` eval suite loads whatever the agent chooses to open: `claude -p`
runs in the full checkout and the with-skill agent is merely told to read
`SKILL.md` by path (`scripts/run-evals.sh:394,428`), while `/scope`'s phase
references are written as repo-relative paths it can follow — and evals 18-21
grade content that exists *only* in `phase-2-chain-orchestration.md:554-739`,
so they already depend on it.

Eval 17 is resolved and Round 1's flag on it is wrong: all four of its
expectations are satisfied by `SKILL.md:435-445` (`## Chain-Proposal Output`),
above the deletion range, so deleting `472-578` breaks no eval at all — the only
forced edit anywhere is the dangling by-title citation at
`skills/brief/references/phases/phase-0-setup.md:315`, and no CI job greps
SKILL.md section headings.

No eval could catch the incident: all 30 `/scope` evals are tier 1 plan-only, so
an agent that *describes* the chain correctly and then writes only a PLAN passes
every one of them — a genuine coverage gap, compounded by three harness defects
(`expectations` is read as `assertions` at `scripts/run-evals.sh:186` so graded
criteria never reach the metadata, `files:` preconditions are never materialized,
and evals run only on a weekly cron, never on PRs).
