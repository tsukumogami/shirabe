# Lead: What do the evals, koto templates, and Rust crates pin down today about chain shape and step optionality?

## Findings

### 0. The eval corpus at a glance

`find skills -name evals.json` returns 17 files: comp, vision, scope, inflight,
strategy, review-plan, roadmap, decision, plan, brief, writing-style, design,
execute, release, charter, explore, work-on, prd.

Sizes for the four in scope: explore 16 evals, scope 26 evals, charter 21 evals,
execute 34 evals (ids 1–34, with id 34 physically located between id 20 and id 21
in the array).

Two assertion vocabularies coexist. Older scenarios carry an `expectations:`
array; three explore scenarios (9, 10, 11) carry `assertions:` plus a
`fixture_dir:`. Execute scenarios additionally carry `tier` (1 or 2), `mode`
(`plan_only` or `execute`) and sometimes `scenario:` naming a fixture tree.
A plan that touches assertions must know which key it is editing per file.

---

### 1. Scenario inventory, by skill

#### `/explore` — `skills/explore/evals/evals.json`

| id | name | what it fixes |
|---|---|---|
| 1 | open-ended-no-direction | Phase 0 → Phase 1, produces `wip/explore_<topic>_scope.md` |
| 2 | issue-based-exploration | `/explore #42`, `gh issue view`, needs-triage |
| 3 | routing-advisor-prd-vs-design | routing-advisor mode, Quick Decision Table |
| 4 | crystallize-to-design-doc | crystallize scores Design Doc, Phase 5 → `/design` |
| 5 | crystallize-to-prd | crystallize scores PRD |
| 6 | auto-mode-no-blocking | `--auto`, decision protocol, max 3 rounds |
| 7 | cross-repo-issue | visibility resolution |
| 8 | simple-task-routes-away | routes to `/work-on` |
| 9 | adversarial-strong-demand | fixture-backed demand validation (`assertions:`) |
| 10 | adversarial-absent-demand | fixture-backed (`assertions:`) |
| 11 | adversarial-diagnostic-topic | fixture-backed (`assertions:`) |
| 12 | roadmap-handoff-upstream-propagation | crystallize scores Roadmap, Phase 5 handler |
| 13 | trivial-classification | Trivial → `/work-on` |
| 14 | strategic-classification | Strategic → `/explore --strategic` / VISION |
| 15 | triage-stage-1-recommends-a-route | Phase 0 step 0.4 recommendation shape |
| 16 | triage-stage-2-recommendation-is-grounded | Phase 0 step 0.5, three-way split |

Assertions that bear directly on artifact-type selection / crystallize:

- **4**: "In Phase 4 Crystallize, evaluates artifact types using the crystallize
  framework. For a 'how to build' question with multiple architectural unknowns,
  should score Design Doc highest. Produces
  `wip/explore_migrate-monolith-to-microservices_crystallize.md` with scoring
  rationale. Phase 5 hands off to /design."
- **5**: "In Phase 4 Crystallize, should score PRD highest since the core
  question is about requirements rather than architecture. Produces crystallize
  artifact recommending /prd handoff."
- **12** expectations, verbatim:
  - "Transcript describes Phase 5 routing to the roadmap produce handler or
    phase-5-produce-roadmap.md"
  - "Transcript describes writing a scope artifact (wip/roadmap_*_scope.md) as
    part of the roadmap handoff"
  - "Transcript describes invoking or handing off to /roadmap or
    /shirabe:roadmap after the scope artifact is written"
- **3**: "Consults the Quick Decision Table and Complexity-Based Routing table…
  Does NOT immediately start the full explore workflow unless the user's
  situation maps to the Complex/Explore path."
- **8**: "Recognizes this as a Simple complexity task… Routes to /work-on or
  direct implementation rather than starting explore."
- **13**: "Transcript recommends /work-on or direct implementation rather than
  /explore, /prd, or /design"; "Transcript does NOT recommend creating an issue
  for this change."
- **14**: "Transcript recommends /explore --strategic or starting with a VISION
  document"; "Transcript does NOT recommend /prd or /design as the first step."
- **15/16** are about *how* a route is presented (one option marked
  `(Recommended)`, grounded in Stage 1/2 agent findings, user still chooses).
  15: "Transcript does NOT present the two routes neutrally and ask the user to
  pick with no stated preference." 16: "Transcript preserves the 'Different
  type' option so the user can override."

Note what is **absent**: nothing in `/explore`'s evals asserts that `/explore`
authors a chain artifact itself. Every crystallize scenario ends in a *handoff*
(`/design`, `/prd`, `/roadmap`, `/work-on`). The four-way router is closer to
what the evals already grade than the framework prose is.

#### `/scope` — `skills/scope/evals/evals.json`

Header note: scenarios 1–6 are the `baseline-*` shared parent-skill baseline
copied from `/charter`; 7–13 are `us-*` PRD user stories; 14–16 coordination;
17–26 the post-#302 and upstream-flag scenarios.

| id | name |
|---|---|
| 1 | baseline-slug-rejection |
| 2 | baseline-malformed-state |
| 3 | baseline-child-internals-isolation |
| 4 | baseline-visibility-default |
| 5 | baseline-team-lead-discipline-loop-ordering |
| 6 | baseline-default-option-wording |
| 7 | us-1-cold-standalone-full-run |
| 8 | us-2-prd-auto-skip |
| 9 | us-3a-prd-boundary-re-evaluation |
| 10 | us-3b-design-boundary-re-evaluation |
| 11 | us-4-prd-rejection-sub-shape |
| 12 | us-5-mid-chain-abandonment-forced |
| 13 | us-6-manual-fallback-reviewer-redirect |
| 14 | coord-intent-creates-coordination-pr-up-front |
| 15 | coord-intent-absent-behavior-unchanged-r3 |
| 16 | coord-smart-default-announces-and-overridable-r18 |
| 17 | chain-shape-is-constant |
| 18 | durable-artifact-floor-is-structural |
| 19 | consolidation-absorb-brief-into-prd |
| 20 | consolidation-keep-at-unmapped-hop |
| 21 | consolidation-carry-check-failure-aborts-absorb |
| 22 | upstream-path-invocation-preserves-child-isolation |
| 23 | upstream-flag-consumed |
| 24 | upstream-flag-stale-on-resume |
| 25 | pre-authoring-notice-cold-start |
| 26 | pre-authoring-notice-suppressed |

**`planned_chain` / `chain_skipped` assertions.**

- 7: "Plan populates `planned_chain:` as [brief, prd, design, plan] on this
  run"; "Plan describes no starting-altitude choice and no state field recording
  one"; "Plan does NOT decide, at Phase 1, whether any artifact is worth
  producing"; "Plan records `exit: full-run` with `exit_artifacts` listing the
  surviving durable artifacts".
- 8: "Plan detects the Accepted PRD and records /prd in `chain_skipped:` with
  reason 'settled-artifact-at-canonical-path-reentry-protection'"; "Plan states
  that re-entry protection is not a judgment about whether the artifact was
  worth producing"; "Plan runs /design and /plan; neither is declined on a
  predicate evaluated before its artifact exists."
- 11: "chain_skipped records /design and /plan with reason 'PRD-boundary
  rejection'".
- 26: "Plan suppresses the pre-authoring upstream notice when re-entry
  protection held /brief back."

**Confirmation-prompt assertions (the `Proceed / Adjust / Bail` surface).**

- 7: "Plan emits a chain-proposal output containing the literal substrings
  Proceed, Adjust and Bail"
- 25: "Plan leaves the options block \"Proceed / Adjust / Bail?\" unchanged and
  adds no new option or decision point" — and the expected_output says the
  options block "still reads \"Proceed / Adjust / Bail?\" **byte-for-byte**".
- 26: "Plan does not otherwise alter the chain-proposal output or its options
  block in either case."

Three separate scenarios therefore pin the triad. 25 and 26 pin it
*byte-for-byte*, which is stricter than 7.

**Re-entry prompt triads (a different, unrelated surface).** Evals 6, 9, 10
require `Re-evaluate / Revise / Bail` and forbid `Continue / Start fresh`; eval 8
requires `redirect to /work-on` / `redirect to /release` at PLAN-Active /
PLAN-Done rows and forbids the Re-evaluate triad there; eval 12 requires
`Resume / Force-materialize / Discard`; eval 13 requires
`Re-run / Accept / Proceed-without`. These are resume-ladder prompts, not chain
proposals — removing `Proceed / Adjust / Bail` does not touch them.

**Absorbability / consolidation assertions.** See §7 — evals 18–21 encode a
model the skill prose has already retired.

#### `/charter` — `skills/charter/evals/evals.json`

| id | name |
|---|---|
| 1–6 | `baseline-*` (same six as /scope) |
| 7 | us-1-cold-standalone-full-run |
| 8 | us-2-re-evaluation |
| 9 | us-3a-rejection-sub-shape |
| 10 | us-3b-abandonment-forced |
| 11 | us-4-manual-fallback-reviewer-redirect |
| 12 | r7-roadmap-declined-non-actionable |
| 13 | r7-informed-prompt-headed-for-execution |
| 14 | r7-negative-reading-still-invokes-roadmap |
| 15 | r7-roadmap-auto-mode-no-prompt |
| 16 | ac10d-chain-proposal-triad |
| 17 | upstream-flag-consumed |
| 18 | upstream-flag-bare-rejected |
| 19 | upstream-flag-private-in-public-repo |
| 20 | pre-authoring-notice-cold-start |
| 21 | pre-authoring-notice-suppressed |

`/charter` is where an **optional chain step still exists and is graded as such**.
Eval 12 (`r7-roadmap-declined-non-actionable`) is the whole surface:

- "Plan surfaces a roadmap confirmation prompt immediately before /roadmap would
  fire, after the Draft STRATEGY is on disk, with proceeding as the default"
- "Plan skips /roadmap because the author declined, and attributes the skip to
  the author's answer rather than to its own reading of the STRATEGY"
- "Plan records the declination in `chain_skipped` as a `{ child: roadmap,
  reason: ... }` entry, and omits /roadmap from `chain_ran`"
- "Plan writes state file with `exit: full-run` and `exit_artifacts` containing
  exactly one entry (STRATEGY path with status Draft) per AC11a"

Evals 13 and 14 grade the *informed* version of that prompt: /charter reads the
Draft STRATEGY, states a headed-for-execution verdict, but "keeps Proceed as the
default and treats the author's answer as the only thing that decides" (13), and
14 is the negative control — "A negative reading changes the prose, never the
pre-selected answer, and never the invocation." Eval 15 says the prompt does not
fire at all under `--auto`.

Eval 16 pins the chain-proposal triad for /charter, and pins it **per-token, not
contiguous**, because /charter renders it as `Proceed / Adjust chain / Bail?`:

- "Plan's prompt contains the literal substrings \"Proceed\", \"Adjust\", and
  \"Bail\" (case-insensitive), asserted individually rather than as one
  contiguous slash-joined string"
- "Plan does NOT require a contiguous \"Proceed / Adjust / Bail\" string, and
  tolerates the canonical rendering \"Proceed / Adjust chain / Bail?\""
- "Plan lists the children in chain order, with /strategy and /roadmap both
  shown as running because their gates are unconditional"

Evals 20 and 21 also pin `"Proceed / Adjust chain / Bail?"` byte-for-byte around
the pre-authoring notice.

So the two parents already disagree on the rendering (`Proceed / Adjust / Bail?`
vs `Proceed / Adjust chain / Bail?`) and their evals encode the disagreement
deliberately, citing a "Gate Vocabulary prompt-vocabulary rule" in
`references/parent-skill-pattern.md`.

#### `/execute` — `skills/execute/evals/evals.json`

34 scenarios. Grouped:

- **Mode dispatch / parse**: 1 single-pr-plan-to-merged-pr-unchanged,
  2 dispatcher-multi-pr-one-issue-at-a-time, 3 legacy-four-column-table-parse,
  14 execute-plan-detection-from-path.
- **Preflight / koto**: 4 cross-skill-work-on-path-preflight.
- **Parity (tier 2)**: 5, 6, 7, 8, 9, 10.
- **Plan orchestration**: 11, 12, 13, 15, 16, 17, 21.
- **Cascade**: 18 execute-plan-completion-cascade, 19
  e2e-execute-cascade-design-roadmap, 20
  e2e-execute-cascade-new-shape-plan-carries-roadmap, 34
  e2e-execute-cascade-old-shape-still-reaches-the-roadmap.
- **Coordinated**: 22, 23, 24.
- **Exit paths**: 25 execute-re-evaluation-exit, 30
  interactive-pause-leaves-chain-intact-at-paused-for-review, 31
  auto-drives-through-to-finalized-mergeable-result-no-pause, 32
  finalization-not-done-guard-via-validate-lifecycle-chain.
- **Branch adoption**: 26, 27. **PR body**: 28, 29. **Docs**: 33.

Chain-shape-bearing assertions:

- 20: "The chain is authored under the upstream-legality rule: PLAN -> DESIGN ->
  PRD -> BRIEF, with the ROADMAP named by the PLAN's own second upstream entry
  rather than by the BRIEF. No durable artifact in the chain names the ROADMAP."
  Expectation: "The walk stops on STRATEGY-cascade-test.md with a stop action,
  not an error action, and the STRATEGY is not transitioned."
- 34: the deliberate *old-shape* regression guard — "These fixtures are kept in
  the old shape on purpose and must not be migrated to the new one"; "Plan does
  NOT propose removing the BRIEF's `upstream:` field."
- 30: "At the pause the chain is intact: PLAN present on disk, BRIEF/PRD/DESIGN
  un-transitioned, PR still DRAFT."
- 25: the only /execute scenario about an *optional* step —
  upstream-must-change routes to `exit: re-evaluation`, "Agent does NOT
  re-execute or drive further issues against the upstream that must change
  first."

/execute has **no chain-proposal, no confirmation prompt, and no
`planned_chain`**. Its chain vocabulary is the finalization cascade (a
transition walk over documents that already exist) plus a three-exit contract.
Nothing in /execute's evals would move if `/scope`'s Phase 1 prompt changed.

---

### 2. Eval 17 — the entry-altitude shortcut

`skills/scope/references/phases/phase-1-discovery.md:283-288` says:

> The prohibition on guarding it survives, with a corrected reason,
> and lives beside the judgment in
> `phase-2-chain-orchestration.md` — because that is where the
> temptation now is. The Phase 1 form of the same temptation, an
> entry-altitude shortcut, is forbidden elsewhere and graded by
> eval 17.

Eval 17 in full (`skills/scope/evals/evals.json:262-272`):

```json
{
  "id": 17,
  "name": "chain-shape-is-constant",
  "prompt": "/scope refactor-topic  (the author says the problem and the requirements are settled; they only want to talk about architecture)",
  "expected_output": "The chain still runs /brief, /prd, /design and /plan. /scope has no altitude selection: an author who says the framing and requirements are settled is not offered a shorter chain, because deciding that an unwritten BRIEF is not worth writing is the exact judgment this skill removed. The BRIEF is written, the PRD is written from it, and if the BRIEF turns out to do no work the PRD does not, the Phase 2 consolidation judgment absorbs it after both exist. The correct redirect for an author who genuinely wants to start at the architecture is to invoke /design directly, and /scope's prose says so.",
  "files": [],
  "expectations": [
    "Plan runs the whole chain and does not offer a shortened one",
    "Plan explains that skipping the BRIEF here would be a judgment about an unwritten document",
    "Plan points the author at invoking /design directly if they want to start above /brief",
    "Plan notes a redundant BRIEF is removed by the Phase 2 consolidation judgment, after both documents exist"
  ]
}
```

**What it forbids, exactly:** offering the author a shorter chain at Phase 1 on
the strength of what the author says is already settled. It forbids *offering*,
not *asking*. It does not forbid a confirmation prompt; it forbids a prompt
whose options include a shortened chain. It positively requires three things —
the whole chain runs, the author is redirected to `/design` directly if they
want to start higher, and the reduction is attributed to Phase 2 after both
documents exist.

Consequence for the exploration: **removing `Proceed / Adjust / Bail` does not
conflict with eval 17.** Eval 17 is about altitude, not about whether the fixed
chain gets confirmed. Removing the prompt only breaks evals 7, 25 and 26 (see
§7). If anything, removing `Adjust` moves *toward* eval 17, because `Adjust`
is the one live option that could reasonably be read as "shorten the chain".

The prose's phrase "forbidden elsewhere" points at `skills/scope/SKILL.md:452-459`:

> A briefly-shipped revision of this skill also let Phase 1 choose an entry
> altitude for the chain. It was withdrawn. The question it asked the author was
> more answerable than the per-hop gates it replaced — which conversation are
> you having, rather than what would an unwritten document have said — but it
> was still a decision that shrank the artifact set before any artifact existed,
> and having two reduction mechanisms fire at different times meant neither read
> as the rule.

---

### 3. What koto enforces vs. what is prose

`skills/execute/koto-templates/execute.md` is a koto workflow template: YAML
frontmatter declaring `variables:`, `states:`, per-state `gates:`, `accepts:`
(typed evidence schema), and `transitions:` with `when:` clauses, followed by a
Markdown body of per-state instructions. `execute.mermaid.md` is a generated
companion state diagram, kept in sync by `scripts/validate-template-mermaid.sh`
(check 1: "State names in YAML frontmatter match states in companion
.mermaid.md").

**koto structurally enforces:**

1. **Reachability.** A state is reachable only via a declared `transitions:`
   edge. `plan_completion` is reachable only from `pr_finalization` with
   `finalization_status: updated, pause_decision: finalize`. `ci_monitor` is
   reachable only from `plan_completion`. `spawn_and_await` is reachable only
   from `worktree_discipline_check`. The pipeline
   `orchestrator_setup → worktree_discipline_check → spawn_and_await →
   pr_finalization → {paused_for_review | plan_completion → ci_monitor → done}`
   is a hard graph, not advice.
2. **Evidence typing.** `accepts:` declares enums; an agent cannot submit
   `ci_outcome: maybe`. `required: true` fields must be present.
3. **Gates**, of two kinds: `type: command` (shell exit code, e.g.
   `impact_classified: test -f wip/work-on_{{PLAN_SLUG}}_impact.json`) and
   `type: context-matches` (regex against a koto context key, e.g.
   `settled_branch_recorded` with `pattern: '^[A-Za-z0-9._/-]+$'`).
4. **Compile-time variable checking.** `{{KEY}}` references are rejected at
   compile time if the key is not in `variables:` — the reason `PLAN_SLUG` is a
   declared variable at all (see the comment at `execute.md:14-23`).

**koto does NOT enforce, and the template says so explicitly** (`execute.md:52-59`):

> The gate must be referenced in a `when` clause to bind. A failed gate on a
> state that has an `accepts` block does NOT block on its own — it falls through
> to transition resolution, and a conditional transition matching on agent
> evidence alone still fires. The two `gates.settled_branch_recorded.matches`
> keys below are what make the gate load-bearing; deleting them leaves a gate
> that is evaluated, reported, and ignored.

So gate binding is itself a hand-maintained convention. Everything else —
which shell commands run inside a state, what the PR body contains, DRAFT-before-
READY ordering *within* `plan_completion`, the autonomy mandate, the report-
upstream convention — lives in the Markdown body and is prose the agent is asked
to follow. The `ci_monitor` gate can be satisfied by an all-queued PR with zero
check-runs; the template compensates in prose ("Do NOT loop on `ci_passing` when
the merge state is DIRTY") plus a second `merge_state_clean` gate.

**Optionality in koto:** exactly one step in `/execute` is conditional, and it is
a *mode-derived* branch, not an author choice — `PAUSE_BEFORE_FINALIZE`
(interactive ⇒ `pause_decision: pause` ⇒ `paused_for_review`; `--auto` ⇒
`finalize` ⇒ `plan_completion`). The template is emphatic that this "is NOT a
separate user flag". Every other branch is a failure or escalation route
(`escalate`, `escalate_upstream_drift`, `escalate_dirty_merge_state`,
`done_blocked`). **No koto state is skippable on author preference.**

**Crucially: `/scope`, `/charter` and `/explore` have no koto templates at all.**
`grep -rn koto skills/scope skills/charter skills/explore` returns only an
incidental `tsuku-project/koto#15` string inside an explore eval prompt. The
document chain is entirely prose-governed; only the implementation altitude
(`/execute`, `/work-on`) is state-machine-backed.

### 4. Other koto templates

`find skills \( -name "*.mermaid.md" -o -path "*koto-templates*" \)` returns
exactly two template pairs:

- `skills/execute/koto-templates/execute.md` + `execute.mermaid.md`
- `skills/work-on/koto-templates/work-on.md` + `work-on.mermaid.md`

`work-on.md` is the far larger machine (entry → mode fan-out into
`context_injection` / `task_validation` / `plan_context_injection` /
`skipped_due_to_dep_failure`, then setup → staleness → analysis →
implementation → scrutiny → review → qa_validation → verification →
finalization → pr_creation → ci_monitor). Its optionality is
**issue-type-conditional, not author-conditional**: `implementation → scrutiny`
fires only for `issue_type: code`; `issue_type: docs` and `issue_type: task` go
straight to `verification`, skipping scrutiny/review/qa. That is the only
"skippable step" pattern anywhere in koto, and its discriminator is the work's
type, not a confirmation prompt.

The cross-skill coupling is real and guarded:
`execute.md` declares `default_template: ../../work-on/koto-templates/work-on.md`
under `spawn_and_await.materialize_children`, and `/execute` eval 4 grades the
`scripts/preflight.sh` fail-closed check that this path resolves.

### 5. The Rust crates

`ls crates/` → `shirabe` (the CLI binary) and `shirabe-validate` (the library).

`shirabe-validate/src/` modules: `formats.rs`, `lifecycle.rs`, `prose.rs`,
`advisory.rs`, `upstream.rs`, `frontmatter.rs`, `visibility.rs`, `transition.rs`,
`mermaid.rs`, `rules.rs`, `pr_body.rs`, `doc.rs`, `table.rs`, `gh.rs`,
`report.rs`, `validate.rs`, `checks.rs`, `annotation.rs`, `merge_gate.rs`,
`coordination.rs`, `features.rs`, `finalize.rs`.

The CLI's subcommands (`crates/shirabe/src/main.rs`): `validate`, `roadmap`,
`plan`, `transition`, `finalize-chain`, slug-convention detection, git-hook
install, `work-summary` (inflight), the `gh pr create/edit` PreToolUse hook, and
`populate`.

**`crates/shirabe-validate/src/formats.rs` — yes, it encodes chain shape and
absorbability.** It defines:

- `enum FormatId` — the eight artifact identities (Vision, Strategy, Roadmap,
  Brief, Prd, Design, Plan, Comp) plus a synthetic `Prose`.
- `enum Lifetime { Durable, Working }` — "Whether a type's documents survive the
  completion of their own work." Roadmap and Plan are `Working`; the other six
  are `Durable`.
- `struct FormatSpec` — per-type `legal_upstream: Vec<FormatId>`, `prefix`,
  `schema_version`, `required_fields`, `valid_statuses`, `required_sections`
  (order significant — FC15 checks order), `issues_table_columns`, `private`,
  and `execution_mode_required_sections` (Plan only: single-pr / multi-pr /
  coordinated).
- **`CONTRIBUTION_SECTIONS: [(&str, &str); 4]`** — this *is* the tactical chain,
  in code:
  ```rust
  pub const CONTRIBUTION_SECTIONS: [(&str, &str); 4] = [
      ("BRIEF-",  "Absorbed Brief"),
      ("PRD-",    "Absorbed PRD"),
      ("DESIGN-", "Absorbed Design"),
      ("PLAN-",   "Absorbed Plan"),
  ];
  ```
  Its doc comment: "Array order is chain order: it gives both the order
  contribution sections must appear in on a survivor, and the strict above-ness
  comparison that rejects a PRD declaring it absorbed a DESIGN." It also warns
  it is a *mirrored* constant, not a single source of truth: "the four
  `*-format.md` references and the `/scope` phase file that composes the heading
  at fold time must match it, and nothing enforces that."
- **`ABSORBED_ENTRY_PATTERN`**:
  `r"^docs/(briefs|prds|designs)/(BRIEF|PRD|DESIGN)-[a-z0-9-]+\.md$"` —
  the shape of every `absorbed:` frontmatter entry. Read by three sites: the
  `/scope` absorb procedure (the gate), FC18 (the backstop), and the record
  checker's fold signature (the trigger).
- `contribution_heading(path)` and `chain_position(path)` — the above-ness
  comparison.
- Invariant test `no_durable_format_declares_a_working_parent`: no `Durable`
  format may list a `Working` one in `legal_upstream`.
- Contract test `declared_lifetimes_and_parent_sets_match_the_contract`: the
  whole eight-row table asserted verbatim, "order is significant".

`checks.rs` implements the absorption checks: `parse_absorbed` →
`AbsorbedDecl::{Absent, Valid, Invalid}`, **FC18** (`absorbed:` entry must match
the pattern; must be strictly upstream — "'absorbed:' entry '{}' is not upstream
of this document; a document may only absorb a type above its own"; contribution
sections must follow `## Status` contiguously in chain order; the Status section
must carry an `Absorbed [<name>](<path>); carried in <heading>.` line), and
**FC19** (a requirement citation orphaned by this run's own absorb — fires only
when `absorbed:` names a PRD).

**Chain shape encoded in code, then:** BRIEF ≺ PRD ≺ DESIGN ≺ PLAN by array
order; BRIEF, PRD and DESIGN are absorbable (they appear in
`ABSORBED_ENTRY_PATTERN`); PLAN is not (its row in `CONTRIBUTION_SECTIONS` is
documented as "structurally unreachable, because the PLAN is terminal and
nothing downstream survives to carry it"). Legal re-point targets after an
absorb are the `legal_upstream` lists — e.g. `Design` legally names
`[Prd, Brief, Strategy, Vision]`, with the comment "and which the /scope absorb
re-points a survivor to when it removes an artifact that named one."

**Is there a crate that validates skill files or checks evals against skills?
No.** `shirabe validate` operates on `docs/**` artifacts, PR bodies,
coordination bodies and lifecycle state. Nothing reads `skills/*/SKILL.md`,
`skills/*/references/**` or `skills/*/evals/evals.json` as a validation target.
The only crate-side awareness of the skills tree is
`crates/shirabe/tests/absorption_corpus.rs`, which walks `docs/` (not `skills/`)
to assert the new absorption checks stay silent on documents that declare no
absorption, plus a companion test `no_existing_document_was_edited`.

Other integration tests worth naming for a planner:
`crates/shirabe/tests/absorption_parity.rs` (golden fixture corpus under
`tests/fixtures/absorption-golden`, append-only contract: "a new check is added
by appending a `cases.tsv` row, a corpus doc, and a baseline — never by editing
this function"), `absorption_corpus.rs`, `lifecycle_posture.rs`,
`transition_parity.rs`, `parity.rs`, `merge_gate.rs`, `coordination_body.rs`,
`fc07_corpus.rs`.

### 6. Scripts and CI

`scripts/`: `bash-floor-canary.sh`, `check-bash-floor.sh` (+ test),
`check-evals-exist.sh`, `check-no-duplicate-rule-list.sh`,
`check-no-fixture-design-leak.sh`, `check-sentinel.sh`,
`check-template-interpolation.sh` (+ test), `ci-gate-expression_test.sh`,
`lib/`, `run-evals.sh`, `validate-template-mermaid.sh` (+ test).
Plus `skills/scope/scripts/check-citations.sh` (+ test) and
`skills/execute/scripts/{preflight.sh,run-cascade.sh}`.

Relevant CI workflows and their `paths:` triggers:

| workflow | triggers on | what it would catch |
|---|---|---|
| `check-evals.yml` | `skills/**` | runs `scripts/check-evals-exist.sh` — **existence and count > 0 only**. It parses `len(json['evals'])` and nothing else. It does not read `expectations`, `assertions`, or `expected_output`. |
| `run-evals.yml` | **weekly cron (Mon 04:00 UTC) + `workflow_dispatch` only — NOT on pull_request** | actually executes the evals via `claude` + skill-creator |
| `check-scope-scripts.yml` | `skills/scope/scripts/**`, `crates/shirabe-validate/src/formats.rs`, itself | runs `check-citations_test.sh`, and greps `ABSORBED_ENTRY_PATTERN` out of `formats.rs`, widens it to admit `plans`/`PLAN`, and requires it to equal `DOC_PATH_RE` in `check-citations.sh` character for character |
| `check-template-consistency.yml` | `skills/*/koto-templates/**`, `scripts/validate-template-mermaid.sh` | frontmatter states ↔ `.mermaid.md` states, `default_template:` resolution, no hardcoded workflow names, shared gate names carry identical commands |
| `check-no-duplicate-rule-list.yml` | `skills/**`, `crates/**` | writing-style rule list must not be copied out of its one source |
| `check-no-fixture-design-leak.yml` | — | eval-fixture DESIGN must not land in `docs/designs/current/` |
| `validate-shirabe-docs.yml` | `docs/**`, `crates/**`, `Cargo.toml` | `shirabe validate` over the repo's own docs |
| `check-execute-scripts.yml`, `check-plan-scripts.yml`, `check-plan-docs.yml`, `parity-check.yml`, `lifecycle.yml`, `pr-body.yml`, `validate-*.yml` | various | none read skill prose |

**Net: no CI check would fail if chain-proposal prose changed.** Not one script
greps for `Proceed`, `Adjust`, `Bail`, `planned_chain`, `chain_skipped`, or any
chain-proposal wording. A repo-wide grep for `Proceed / Adjust` outside `.md`
prose returns only `skills/scope/evals/evals.json` and
`skills/charter/evals/evals.json`. The only structural coupling that fires on a
`skills/` change is `check-evals-exist.sh` (count > 0) and the
`formats.rs` ↔ `check-citations.sh` regex equality in `check-scope-scripts.yml`.

The practical implication: **eval drift is invisible on a PR.** An eval whose
assertions contradict the skill it grades passes CI indefinitely and surfaces
only on the Monday cron or a manual dispatch.

### 7. Blast radius

#### If `Proceed / Adjust / Bail` were removed from `/scope` Phase 1

Breaks, all in `skills/scope/evals/evals.json`:

1. **Eval 7** (`us-1-cold-standalone-full-run`) — expectation "Plan emits a
   chain-proposal output containing the literal substrings Proceed, Adjust and
   Bail". Delete or rewrite that one expectation; the other six in the scenario
   (`planned_chain`, no-altitude-choice, no-Phase-1-worth-judgment, upstream-path
   invocation, consolidation-per-hop, `exit: full-run`) survive unchanged.
2. **Eval 25** (`pre-authoring-notice-cold-start`) — the scenario's whole point
   is that the notice sits "above the options block, which still reads
   \"Proceed / Adjust / Bail?\" byte-for-byte", and the expectation "Plan leaves
   the options block \"Proceed / Adjust / Bail?\" unchanged and adds no new
   option or decision point". Needs rewriting around whatever the new
   non-blocking output is. The scenario itself stays valid — the notice's
   "this is a notice, not a question" framing gets *stronger* without a
   question beside it.
3. **Eval 26** (`pre-authoring-notice-suppressed`) — "Plan does not otherwise
   alter the chain-proposal output or its options block in either case".
   One-line edit.

Also touched, prose only, no eval: `skills/scope/references/phases/phase-1-discovery.md`
"Chain-Proposal Output" section (lines ~290-328) — the example skeleton, the
sentence "The output's options block contains the literal substrings `Proceed`,
`Adjust`, and `Bail` (case-sensitive, exact spelling per AC9)", and "The three
branch behaviors" list, which is also the only place `Bail` is bound to
"R8 bail-handling (force-materialize if any wip state exists for the topic;
clean-cancel otherwise)". **Removing Bail here orphans the interactive entry
point into R8 bail handling** — eval 12 (`us-5-mid-chain-abandonment-forced`)
still needs `abandonment-forced` reachable, and today the resume ladder row 4
`Resume / Force-materialize / Discard` prompt is the other route to it. Worth
confirming R8 stays reachable.

Does **not** break: eval 17 (about altitude, not confirmation); evals 6, 8, 9,
10, 12, 13 (resume-ladder triads, a different surface); anything in `/charter`,
`/execute`, `/work-on`, or the crates; any CI check.

**Cross-parent consistency question a plan must answer:** `/charter` eval 16
(`ac10d-chain-proposal-triad`) pins the same triad for `/charter`, and evals 20
and 21 pin `"Proceed / Adjust chain / Bail?"` byte-for-byte. If the triad is
removed from `/scope` but kept in `/charter`, the "one model consistently" goal
is only half met — and `/charter` has the better claim to keeping it, because
it genuinely has an optional child (evals 12–15). If it is removed from
`/charter` too, evals 16, 20, 21 break as well, plus the Gate Vocabulary
prompt-vocabulary rule in `references/parent-skill-pattern.md` that eval 16
cites by name.

#### If `/explore`'s crystallize framework were replaced by a four-way router

Breaks, in `skills/explore/evals/evals.json`:

- **Eval 4** (`crystallize-to-design-doc`) — "In Phase 4 Crystallize, evaluates
  artifact types using the crystallize framework… Produces
  `wip/explore_*_crystallize.md` with scoring rationale. Phase 5 hands off to
  /design." Under a four-way router the *outcome* survives (route to `/scope`,
  which reaches the DESIGN) but the mechanism named in the assertion does not.
- **Eval 5** (`crystallize-to-prd`) — same shape; "recommending /prd handoff"
  becomes "route to /scope".
- **Eval 12** (`roadmap-handoff-upstream-propagation`) — "Crystallize framework
  scores Roadmap highest. Phase 5 routes to the roadmap handoff handler
  (phase-5-produce-roadmap.md)." A ROADMAP is a `/charter` outcome, so this
  becomes the `/charter` arm — but the assertions naming
  `phase-5-produce-roadmap.md` and `wip/roadmap_*_scope.md` break outright.
- **Eval 6** (`auto-mode-no-blocking`) — names "crystallize confirmation" as one
  of the three decision points the `--auto` protocol handles.
- **Evals 3, 8, 13, 14** name the routing-advisor tables and the targets
  `/work-on`, `/prd`, `/design`, `/explore --strategic`, VISION. `/work-on` is
  not one of the four router arms as stated (file an issue / `/charter` /
  `/scope` / `/execute`), and `/explore --strategic` self-references. These four
  need target remapping even though their *classification* logic survives.
- **Evals 15, 16** (triage recommendation shape) survive — they are about how a
  recommendation is presented, not what the arms are. If anything a four-way
  router makes them easier to satisfy.
- **Evals 1, 2, 7, 9, 10, 11** survive untouched.

Breaks **outside** `/explore`, which is the non-obvious part:

- `skills/roadmap/evals/evals.json` **eval 7** `crystallize-discrimination` —
  prompt `/explore --auto --strategic improve CI pipeline reliability…`,
  expectations "Transcript recognizes this as an /explore command, not /roadmap
  directly", "Transcript describes a crystallize or artifact type selection step
  that scores Roadmap higher than PRD", "Transcript describes a Phase 5 handoff
  that routes to /roadmap with a scope artifact".
- `skills/roadmap/evals/evals.json` **eval 9** `upstream-propagation`.
- `skills/vision/evals/evals.json` **eval 2** `explore-handoff-detection` —
  "Detects existing handoff artifact at `wip/vision_workflow-engine_scope.md`.
  Skips Phase 1 (scope) and resumes at Phase 2… Does not re-ask scoping
  questions that were already answered during /explore." A four-way router that
  never authors chain artifacts still needs to produce *some* handoff artifact,
  or this contract dies.
- `skills/vision/evals/evals.json` **eval 8** `crystallize-discrimination` —
  prompt `/explore --auto --strategic should we build a developer analytics
  dashboard`, expectation "Plan includes a crystallize or artifact-type
  selection step".
- `skills/decision/evals/evals.json` **eval 5** `explore-crystallize-to-decision`
  — "The crystallize phase explicitly identifies a Decision Record as the
  appropriate artifact type". A Decision Record is not one of the four arms.
- `skills/decision/evals/evals.json` **eval 7** `auto-mode-loop-termination` —
  "auto-crystallizes with whatever findings exist".

Files, not evals, that a four-way router retires or rewrites:
`skills/explore/references/quality/crystallize-framework.md` (293 lines; it
declares "Ten artifact types can be produced through /explore today" — PRD,
Design Doc, Plan, No Artifact, Rejection Record, VISION, Roadmap, Spike Report,
Decision Record, Competitive Analysis, plus a Deferred Types section), and the
eleven Phase 5 handlers `skills/explore/references/phases/phase-5-produce*.md`
(`-decision`, `-deferred`, `-design`, `-no-artifact`, `-plan`, `-prd`,
`-rejection-record`, `-roadmap`, `-vision`, plus the `phase-5-produce.md`
dispatcher).

CI: nothing fails. `check-evals-exist.sh` only counts. `run-evals.yml` does not
run on PRs.

---

## Implications

**The confirmation prompt is cheap to remove and the eval corpus barely
resists.** Three `/scope` expectations across three scenarios, two of them
one-line edits. There is no CI check, no script, no crate constant, and no koto
gate holding it. The real cost is cross-parent consistency: `/charter` pins the
same triad in three scenarios and has a legitimate optional child, so a plan has
to decide whether the two parents keep different prompt contracts on purpose.

**The four-way router is expensive and its blast radius reaches four other
skills.** Six `/explore` scenarios move, six scenarios in `roadmap`, `vision` and
`decision` move, and eleven Phase 5 handler files plus a 293-line framework
document either die or shrink. The router's four arms (issue / `/charter` /
`/scope` / `/execute`) do not cover four outcomes the current evals grade:
`/work-on` for trivial work (evals 8, 13), a Decision Record (decision eval 5), and
`--strategic` VISION-first framing (eval 14, vision eval 8). Either those arms
fold into `/charter` and `/scope` — and the evals must say so — or the router is
wider than four ways.

**The handoff-artifact contract is the sharpest hidden dependency.** vision eval
2 and roadmap eval 12 both assert `/explore` writes a scope artifact
(`wip/vision_<topic>_scope.md`, `wip/roadmap_*_scope.md`) that the downstream
skill detects and resumes from. "Never authors chain artifacts itself" must be
read as "never authors *durable* chain artifacts", or those two evals and the
`wip/` handoff mechanism go with it.

**Nothing mechanical will tell anyone when this drifts.** Evals run weekly on a
cron, never on a PR. The one crate-level coupling to the chain
(`formats.rs` ↔ `check-citations.sh`) is a regex equality check about *paths*,
not about which steps run. A plan that changes chain-shape prose is changing
documentation whose only enforcement is a Monday-morning eval run and reviewer
attention.

**Where enforcement does exist, it points the other way.** `formats.rs` already
encodes a chain where every hop above the PLAN is absorbable (`BRIEF|PRD|DESIGN`
in `ABSORBED_ENTRY_PATTERN`, FC18's strict above-ness), i.e. the post-#302
model. The evals are behind the code, not the other way around.

## Surprises

**Four `/scope` evals encode a model the skill has already retired.**
`phase-1-discovery.md:271-281` says, in the present tense:

> This section previously stated a durable-artifact floor… All three of those
> rested on the type-level absorbability test, **which is gone. Every hop is now
> decidable, a run can absorb its way down to nothing**, and the redirect
> describes an escape hatch from a constraint that no longer exists.

And `phase-2-chain-orchestration.md:520-523` states the input restriction:

> *No check in this judgment may read either type's required-section list, or
> compare the two types' section sets.* Chain position and provenance are
> admissible inputs; a type's content contract is not.

Against that:

- **Eval 18** (`durable-artifact-floor-is-structural`) asserts "A /scope run
  always leaves at least one durable artifact"; "no hop above BRIEF-to-PRD is
  absorbable, so the smallest set a run can end with is a PRD, a DESIGN and a
  PLAN"; "a PLAN-alone run… is not reachable through /scope at all". `SKILL.md:472`
  now says flatly "There is no durable-artifact floor."
- **Eval 20** (`consolidation-keep-at-unmapped-hop`) asserts "Plan finds the
  prd->design mapping is not total and records `absorbable: false`" and "Plan
  derives absorbability from the per-type required-section contracts rather than
  a hard-coded list of hops" — the exact input the Phase 2 restriction now bans,
  and `absorbable:` is named in the phase file (line ~706) as "the retired
  `absorbable:` boolean".
- **Eval 19** (`consolidation-absorb-brief-into-prd`) assigns the mapping-total
  test to "Stage 1"; Stage 1 is now the citation preflight
  (`check-citations.sh`), Stage 2 is the judgment, Stage 3 the compose/carry/
  move. The scenario's outcome still holds; its stage numbering and its Stage 1
  content do not.
- **Eval 21** (`consolidation-carry-check-failure-aborts-absorb`) is the closest
  to still-correct — the carry check survives as Stage 3 step 4 — but it inherits
  eval 19's stage vocabulary.

These are four already-broken evals in the same file the exploration is about,
independent of anything the author is proposing. Any plan that touches
`skills/scope/evals/evals.json` should fix them in the same pass, because they
are the loudest surviving statement of the pre-#302 model in the corpus.

**Evals do not run on pull requests.** `run-evals.yml` is `schedule` +
`workflow_dispatch` only. The PR-time check is existence-and-count.

**`/execute` is not a chain-shape surface at all.** It has no `planned_chain`,
no chain proposal, no confirmation. Its only "chain" is the finalization cascade
over documents that already exist, and its only optionality is the mode-derived
pause. Including it in the exploration's "surfaces that treat chain steps as
optional" set looks like a false positive — the one exception is eval 25's
`exit: re-evaluation` on an upstream-must-change boundary, which is a blocker
route, not a choice.

**`/charter`'s roadmap prompt is the genuine remaining "choosable before the
fact" surface, and it is deliberate and heavily graded.** Four scenarios
(12–15) exist specifically to keep the reading advisory and the author's answer
decisive: "A negative reading changes the prose, never the pre-selected answer,
and never the invocation." If the corpus is to state one model, this is the
surface that has to be argued with, not `/scope`'s already-fixed chain.

**`CONTRIBUTION_SECTIONS` documents itself as an unenforced mirror.** Its own
comment: "the four `*-format.md` references and the `/scope` phase file that
composes the heading at fold time must match it, and nothing enforces that."
Any change to contribution headings has four hand-maintained copies.

## Open Questions

1. Should `Proceed / Adjust / Bail` be removed from `/charter` too, or does
   `/charter` keep it because its `/roadmap` child is genuinely optional? The
   two parents currently render it differently on purpose (`Adjust` vs
   `Adjust chain`), which suggests the pattern reference already tolerates
   divergence.
2. If `Bail` disappears from `/scope` Phase 1, what is the remaining interactive
   entry to R8 bail-handling / `abandonment-forced`? Eval 12 needs that exit
   reachable.
3. Do the four router arms subsume `/work-on` (explore evals 8, 13), Decision
   Record (decision eval 5), and VISION-first strategic framing (explore eval 14,
   vision eval 8)? If `/charter` is the VISION arm and `/execute` is the
   `/work-on` arm, the evals need to say so explicitly.
4. Does "never authors chain artifacts itself" permit the `wip/*_scope.md`
   handoff artifacts that vision eval 2 and roadmap eval 12 depend on?
5. Should evals 18–21 be fixed as part of this work, or filed separately? They
   are broken today regardless of the proposed change.
6. Is anyone watching the weekly `run-evals.yml` result? If not, the eval corpus
   is documentation, and the plan should say whether that is acceptable or
   whether a PR-time structural check (e.g. an eval-to-skill citation lint) is
   in scope.

## Summary

Chain shape is pinned in three places with very different force: `formats.rs`
encodes it in code (`CONTRIBUTION_SECTIONS` as the ordered tactical chain,
`ABSORBED_ENTRY_PATTERN` admitting BRIEF/PRD/DESIGN but not PLAN, FC18's strict
above-ness), koto encodes step *ordering* only for `/execute` and `/work-on`
(and only the pipeline graph, gate binding, and evidence enums — everything
inside a state is prose), while `/scope`, `/charter` and `/explore` have no koto
templates and no CI check on their prose at all, so removing
`Proceed / Adjust / Bail` breaks exactly three `/scope` eval expectations
(7, 25, 26) and nothing mechanical. Replacing `/explore`'s crystallize framework
with a four-way router is the expensive half: six `/explore` scenarios, plus
roadmap 7/9, vision 2/8 and decision 5/7, plus the 293-line framework document
and eleven Phase 5 handler files — and the router's four arms do not currently
cover `/work-on`, Decision Records, or VISION-first framing that today's evals
grade. The biggest surprise is that `/scope` evals 18–21 already contradict
their own skill (they assert a durable-artifact floor and derive absorbability
from per-type required-section lists, both of which Phase 1 and Phase 2 prose
explicitly retired), and nothing catches it because `run-evals.yml` runs on a
weekly cron rather than on pull requests.
