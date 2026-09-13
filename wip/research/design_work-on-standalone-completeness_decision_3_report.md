# Decision 3: Gate-enforced versus evidence-carried obligations

## Context

The PRD (`docs/prds/PRD-work-on-standalone-completeness.md`) diagnoses `/work-on`'s
finishing obligations as prose the template's per-state directives cite rather
than states a run cannot advance past (PRD problem statement, lines 84-97). Three
field runs in two days each skipped an obligation the prose delivered. R6-R10
require: obligations resolving to a `gh`/git-observable fact become gates (R6);
irreducibly judgment-call obligations become named, required evidence fields
typed to a concrete referent — a path, a commit identifier, or a named command's
output, never free prose (R7, R7a); every obligation is classified in a
committed table as gate-enforced, evidence-carried, or dropped/advisory, with
none left unclassified (R8); the design-diagram obligation specifically is
brought within one reference-hop with an evidence field, or recorded as
deliberately advisory (R9); and nothing new may live only in
`skills/work-on/SKILL.md` (R10) — a child session is seeded from the compiled
`koto-templates/work-on.md` template and never loads the skill's prose.

## The obligation inventory

Read from `skills/work-on/references/phases/phase-5-finalization.md`,
`skills/work-on/references/phases/phase-6-pr.md`,
`skills/work-on/references/phases/phase-6-design-diagram-update.md`, and
`references/pr-body-conformance.md` (the last is cited by `phase-6-pr.md:28`).

1. **Rebase / merge cleanliness.** `phase-6-pr.md:9` — "Rebase on latest main if
   behind. Resolve conflicts and re-run tests." Pure prose today; no gate checks
   it in `work-on.md`.
2. **Closing keyword in the PR body.** `phase-6-pr.md:32` — "Include `Fixes
   #<N>` in Part 2." `references/pr-body-conformance.md`'s own "What stays
   advisory" section states plainly that a body whose Part 2 is only `Fixes #N`
   passes the mechanical check, but nothing requires that line be present —
   presence of the closing keyword is not one of PB1-PB4 (`references/pr-body-conformance.md:40-64`).
3. **PR body mechanical shape** (Conventional Commits title, two-part body with
   exactly one `---`, no AI-attribution footer, no ATX heading in Part 1) —
   PB1-PB4, `references/pr-body-conformance.md:40-64`.
4. **PR body Part 2 content selection** (which reviewer-context sections a
   change needs) — `phase-6-pr.md:29-31`, explicitly named subjective and
   advisory by `references/pr-body-conformance.md`'s "What stays advisory"
   section.
5. **Design-document diagram update** — `phase-6-pr.md:11-13` cites
   `phase-6-design-diagram-update.md` for the procedure; that file's own "When
   to run" and "Error handling" sections (`phase-6-design-diagram-update.md:15-16,
   74-78`) permit silent skip on four separate conditions (no `Design:`
   reference, path validation failure, diagram section not found, node not
   found, syntax validation failure). This is the PRD's named "two
   reference-hops... contract permitting silent skipping" (R9): `work-on.md`'s
   `pr_creation` prose points at `phase-6-pr.md`, which points at
   `phase-6-design-diagram-update.md`.
6. **Code cleanup** — `phase-5-finalization.md:11-12` — "Remove: debug
   statements, commented-out code, addressed TODOs, unused imports."
7. **Summary shape** — `phase-5-finalization.md:19-42` specifies six required
   sections (What Was Implemented, Changes Made, Key Decisions, Test Coverage,
   Known Limitations, Requirements Mapping). Only *existence* of `summary.md`
   is gated today (`work-on.md:632-634`, `gates.summary_exists`), not its shape
   — a one-line placeholder file satisfies the existing gate, which is exactly
   the R7a failure mode named in the PRD.
8. **Commit-message convention** for the summary commit —
   `phase-5-finalization.md:44` — "Commit summary: `docs: add implementation
   summary`."
9. **Final verification** (tests, build, lint) — already fully gate-enforced by
   the existing `verification` state (`work-on.md:592-628`); listed here only to
   confirm it needs no new work.
10. **Auto-skip routing for the summary** — `phase-5-finalization.md:6-8` —
    labels like `docs`/`config`/`chore` skip summary generation; `bug`/
    `enhancement`/`refactor`/`security` require it. Not itself a finishing
    obligation, but it gates the *applicability* of obligation 7's gate and
    needs its own discriminator.

## Read: the existing enforcement spine (`verification` through `ci_monitor`)

`work-on.md:592-820` is what "enforced" already looks like in this template:

- `verification` (`work-on.md:592-628`): `accepts.verification_outcome` is a
  required enum (`passed|failed|cannot_verify`), plus a required
  `commands_run` field whose description ties it to "the commands selected
  from the project's verification map... Required for all outcomes so the
  evidence captures what was executed, not merely declared" — this is already
  R7a-shaped: a field typed to "the output of a named command," not free
  prose. `cannot_verify` fails closed to `done_blocked` (line 621, "Fail
  closed").
- `finalization` (`work-on.md:630-661`): a `context-exists` gate
  (`summary_exists`) on the `summary.md` key, and `ready_for_pr` requires that
  gate true (`work-on.md:657`) in addition to the enum evidence.
  `deferral_requested` has no clean self-report terminal — it routes to a
  blocking human-approval gate, `deferral_approval` (`work-on.md:663-693`).
- `pr_precheck` (`work-on.md:695-750`): a `default_action` read of the current
  branch, gated (`on_feature_branch_pr`) before `pr_creation` is ever entered —
  "the template's only structural guarantee that a pull request is not opened
  from the default branch, at the point where opening one happens"
  (`work-on.md:703-704`).
- `pr_creation` (`work-on.md:752-775`) and `ci_monitor` (`work-on.md:777-820`):
  today `ci_monitor` gates only `ci_passing` — a `gh pr checks` bucket query.
  It does **not** yet carry the merge-cleanliness gate `execute.md` has.

## Read: the worked precedent (`execute.md`)

`execute.md:369-427` is the directly transferable shape for a gate item:
`ci_monitor` there carries **two** gates, `ci_passing` (identical command to
`work-on.md`'s) and `merge_state_clean`:

```
merge_state_clean:
  type: command
  command: "[ \"$(gh pr view --json mergeStateStatus --jq .mergeStateStatus)\" != \"DIRTY\" ]"
```

The `done` transition requires **both** gates at exit 0 (`execute.md:397-401`).
A third `ci_outcome` value, `dirty_merge_state`, routes to a dedicated escalation
state `escalate_dirty_merge_state` (`execute.md:412-427`) rather than folding
into the existing `failing_unresolvable` path, because the recovery instructions
differ (rebase guidance vs. CI-fix guidance) — the prose at `execute.md:692-694`
explains why the second gate exists at all: an all-DRAFT-suppressed PR and an
actually-green PR both evaluate `ci_passing` as true, so `merge_state_clean` is
what tells them apart.

`plan_completion`'s `cascade_status` (`execute.md:429-455`, prose at
`execute.md:700-757`) is the worked precedent for an evidence field with a
concrete-command referent under R7a: the agent does not decide `cascade_status`
by judgment. It runs `run-cascade.sh --push {{PLAN_DOC}}` (`execute.md:709`),
parses its JSON, and **copies** the verdict — "submit `cascade_status` from the
JSON output" (`execute.md:751`). The prose explicitly closes the loophole a
free-text field would leave open: "Checking for a failed `commit` or `push`
step is NOT sufficient... the most damaging shape emits neither" (`execute.md:733`),
and on `partial`, "submit nothing... submitting would report a failed cascade as
a successful run" (`execute.md:751`). This is the pattern to imitate for
obligation 6 (code cleanup) and obligation 7 (summary shape): don't ask the
agent "did you clean up?" — anchor the field to something a script or `git`
command produced.

## Read: the authoring rules

`references/default-action-conversion.md`'s rule: `default_action` is for a
command whose only irreversibility is "bounded and repairable after a
successful run" — never for a command whose successful exit is itself the
irreversible externally visible event (creating/publishing/closing a PR,
marking ready). This rules out converting `gh pr create` or `gh pr ready` calls
themselves to `default_action`; it does **not** rule out `gates:` blocks (plain
command checks re-evaluated on tick), which is how `merge_state_clean`,
`ci_passing`, and `on_feature_branch_pr` are all implemented today — none of
them are `default_action`, they're just `gates:`. Any new gate for this
decision (closing keyword, merge cleanliness) is a `gates:` addition, not a
`default_action` conversion, so this rule mostly doesn't constrain the new
work, but it does confirm that the PR-creation/PR-ready calls stay agent-driven
turns, consistent with how `pr_creation` is written today.

Two authoring constraints matter concretely for new gate commands:

- **`scripts/check-template-interpolation.sh`** forbids a bare `$NAME`/`${NAME}`
  in any `command:` field (only `{{KEY}}` and `$(...)` substitution are
  allowed). A closing-keyword gate needs the current PR number, which today's
  `ci_monitor` gate gets via nested `$(...)` command substitution
  (`work-on.md:792`) — that pattern is reusable verbatim; anything needing a
  local shell variable must go into a script under `skills/work-on/scripts/`
  instead of the inline `command:` field.
- **`scripts/validate-template-mermaid.sh` check 4** requires that a gate name
  shared across templates carry an identical command in all of them. Since
  `merge_state_clean` already exists in `execute.md`, adding it to `work-on.md`
  under that exact name means the command string **must** be copied verbatim
  (which is also just correct — it's the same check) or the linter fails the
  build. This is a hard constraint on obligation 1's mechanism, not just a
  preference.
- **`scripts/check-template-directives.sh` rule 1** ("unguarded evidence"):
  every non-terminal state with an `accepts:` block must have every transition
  behind a `when:` clause, or koto's fallback edge fires unconditionally on
  entry and the agent never sees the directive at all. Any new state this
  decision adds must satisfy this — which matters most for obligation 5
  (design-diagram), where the natural shape has a conditional branch (`Design:`
  reference present vs. absent) that must be modeled as distinct `when:`
  branches sharing a common gate/field, exactly like `pr_precheck`'s
  gate-plus-override pattern (`work-on.md:737-750`) or `pr_finalization`'s
  mode-driven `pause_decision` (`execute.md:352-362`).
- **`validate-template-mermaid.sh` check 1**: `work-on.md` has a companion
  `work-on.mermaid.md`. Any new state must be added there too or the build
  fails.

## Per-obligation mechanical-checkability assessment

- **Rebase/merge cleanliness**: mechanically checkable today via `gh pr view
  --json mergeStateStatus` — this is exactly what `execute.md`'s
  `merge_state_clean` gate already does. Directly transferable.
- **Closing keyword**: mechanically checkable via `gh pr view --json body --jq
  .body` piped through a regex for `(close|fixe?|resolve)[sd]?\s+#<N>`. This is
  new — no existing gate anywhere checks it; `references/pr-body-conformance.md`
  deliberately leaves it unchecked because a docs-only PR without a fixable
  issue is legitimate. The gate must therefore be conditioned on whether the
  issue is a real GitHub issue (not `plan_outline`), the same discriminator
  `execute.md:654` already uses for its own `Fixes #N` decision.
- **PR body mechanical shape (PB1-4)**: already mechanically checked, twice
  over — CI (`references/pr-body-conformance.md`'s "Consumers" section, the
  `pr-body.yml` workflow) and a client-side `PreToolUse` hook
  (`shirabe pr-body-hook`) that runs before `gh pr create`/`gh pr edit`
  executes. No new template gate is needed; the classification table's job is
  to record that this is gate-enforced *elsewhere*, not to duplicate it in
  `work-on.md`.
- **PR body Part 2 content**: not mechanically checkable — "which sections a
  change needs" is exactly the kind of judgment `references/pr-body-conformance.md`
  says would false-positive a correct minimal PR if gated. No concrete referent
  exists. Advisory under R7a's own exception.
- **Design-diagram update**: partially checkable. "Did the node's class change
  to `:::done`" is a regex a script can run against the design file at HEAD.
  "Was the `Design:` reference present/absent in the issue body" is checkable
  via `gh issue view --json body`. But the *legitimate*-skip conditions
  (old-format diagram, node not found, syntax invalid) are not distinguishable
  from a *silent* skip by exit code alone — `phase-6-design-diagram-update.md:74-78`
  lists four different reasons a skip is "correct," and a bare pass/fail gate
  can't tell a correct skip from an agent that never looked. This is the crux
  of R9 and is discussed under Options below.
- **Code cleanup**: not mechanically checkable in substance. A grep for
  `TODO`/`console.log`/`fmt.Println("DEBUG"` etc. is available but both
  over-matches (legitimate TODOs, intentional debug logging) and
  under-matches (commented-out code with no fixed marker). Genuinely R7's
  "irreducibly a judgment call" case.
- **Summary shape**: mechanically checkable for *structure* (the six `##`
  headers present) via a grep/script against `summary.md`'s content, which is
  strictly stronger than the existing `context-exists` gate that only checks
  the key exists. Not checkable for *substance* (is the Requirements Mapping
  table accurate) — that stays a judgment call, but it's out of scope: neither
  the PRD nor the existing template asks anyone to verify factual accuracy of
  summaries, only that the shape exists.
- **Commit-message convention**: trivially checkable — `git log -1 --format=%s`
  against a fixed string. Low value per obligation, but R6 draws no value
  threshold ("every finishing obligation that resolves to a fact observable
  from `gh` or from git SHALL be enforced by a gate").
- **Auto-skip routing**: checkable as a *lookup* (does the PR/issue carry a
  summary-skippable label — `gh issue view --json labels`), but it's a routing
  decision that changes which other gates apply, not itself a pass/fail fact.

## Options considered

### Option A — One new state carrying all finishing evidence

Insert a single batching state — call it `finishing_checks` — positioned once
in the sequence, gathering every obligation's gate/evidence into one
`accepts:`/`gates:` block.

**The sequencing problem this runs into immediately.** Obligations split
cleanly into two groups by when they're observable: pre-PR (code cleanup,
summary shape, design-diagram, commit-message convention — all true or false
before `pr_creation` runs) and post-PR (closing keyword, merge cleanliness —
both require a PR to exist so `gh pr view` has something to query). A single
state cannot sit both before `pr_creation` and after it in the same linear
walk without either running twice (once pre, once post, which is really
"Option A run twice" — an admission that one state can't hold everything) or
deferring the PR-dependent checks to a second pass that isn't structurally a
single state anymore. So "one state" degrades in practice to "one pre-PR
batching state plus reuse of the existing post-PR states (`pr_creation`/
`ci_monitor`) for the other half" — which is really a hybrid, not a clean
single-state design.

**Cost of the batching half that does work.** A state with five-plus required
fields (design-diagram evidence, cleanup referent, summary-shape check,
commit-message gate) multiplies conditional branches: design-diagram evidence
is only applicable when a `Design:` reference exists, auto-skip changes
whether the summary-shape gate applies at all. `check-template-directives.sh`
rule 1 requires every reachable evidence combination to route through an
explicit `when:`, which for N independent binary conditions is not N branches
but a combinatorial handful — the state's YAML and prose section balloon well
past the size of any existing state in `work-on.md` (the largest today,
`ci_monitor`, is ~40 lines). Reviewability suffers: a reviewer checking "is
obligation X's field required" has to parse one dense block holding every
other obligation's conditions too.

**What it buys.** A reviewer auditing R8's classification table has exactly
one place to look for "is this gated" for the whole pre-PR half, and the state
machine gains only one new node in the mermaid diagram rather than several,
which keeps `work-on.mermaid.md` and the state-count small.

### Option B — Several states, one per obligation

Give each obligation its own small state, mirroring `pr_precheck` and
`deferral_approval`'s existing atomicity (`work-on.md:663-693, 695-750`) and
`execute.md`'s `escalate_dirty_merge_state`, which is deliberately split out
from `ci_monitor` rather than folded in because its recovery guidance differs
(`execute.md:412-427`).

**What it buys.** Maximum clarity per obligation — the classification table's
"one row per obligation, naming... where it is enforced" (R8) maps one-to-one
onto the state graph, so satisfying the PRD's acceptance criterion ("every row
classified gate-enforced names a gate that exists on the state it names," PRD
line 378) is trivial to audit: one state, one gate, one row. It also
isolates blast radius — a bug in the design-diagram gate can't accidentally
block the closing-keyword check, because they're unrelated states with
unrelated transition edges.

**What it costs.** Five to six new states each need: frontmatter entry,
`accepts`/`gates` block, a prose section under the template's directive
listing, and a `work-on.mermaid.md` entry (`validate-template-mermaid.sh`
check 1 fails otherwise) — the linter and authoring overhead scale linearly
with obligation count, on a template already at 1227 lines. It also
multiplies agent turns: koto ticks once per state, so an obligation that today
costs zero extra turns (it's covered inside `finalization`'s existing
`ready_for_pr` submission) becomes a dedicated round-trip. The PRD's own
Decisions section records a directly analogous precedent against this kind of
bloat: a "shared template was rejected on the record once already, for
muddying the single-issue template's legibility" (PRD lines 534-537) — that
rejection was about a different sharing mechanism, but the underlying
complaint (legibility cost of more moving parts in this specific template)
generalizes to six new single-purpose states the same way. It also serializes
checks that are naturally independent and could be one shell invocation's
worth of gates evaluated together — the `default-action-conversion.md`
philosophy of spending agent turns on judgment, not bookkeeping, argues against
manufacturing turns for objectively mechanical checks.

### Option C — Extend the existing states' schemas in place

Add gates and fields to `finalization`, `pr_creation`, and `ci_monitor`
without introducing new states, following exactly how `execute.md` added
`merge_state_clean` to its existing `ci_monitor` rather than inventing a
"merge cleanliness state."

**What it buys.** Lowest diff risk against a template with an already-dense,
carefully-commented set of invariants — `finalization`'s comments
(`work-on.md:638-645`) spell out exactly why `ready_for_pr` is safe given the
current transition shape ("Reaching this state at all means verification ran
and passed... there is no clean finalization without it"). Extending in place
means most of that reasoning still holds; introducing a new state anywhere in
the chain means re-deriving which invariants still transfer. It directly
reuses the one piece of precedent that's an exact match (`merge_state_clean`
copied verbatim into `ci_monitor` satisfies the cross-template identical-gate
linter automatically, since it's the same command by construction). Turn count
stays the same as today for most obligations — cleanup/summary-shape/
design-diagram evidence rides along on `finalization`'s existing
`ready_for_pr` submission; closing keyword and merge cleanliness ride along on
`pr_creation`'s and `ci_monitor`'s existing submissions.

**What it costs.** `finalization`'s `accepts:` block would need to grow from
one enum field to several required fields, and every one of them is
implicitly gated by the *same* `ready_for_pr` transition — the state's
existing three-way branch (`issues_found` / `ready_for_pr` /
`deferral_requested`) has to absorb design-diagram applicability and
auto-skip's effect on whether summary-shape checking even applies. This is
the same combinatorial-branch cost Option A pays, just distributed across
three states instead of concentrated in one — marginally better for
legibility (each state's prose section stays scoped to what it already talks
about) but not free. There is also a real risk of silently changing
`finalization`'s current terminal-record and gate semantics that the PRD's
Known Limitations section already flags as a judgment call ("the
classification of obligations... is a judgment itself," PRD lines 575-579) —
piling evidence fields onto a state whose current three transitions are each
individually reasoned about in the comments increases the chance a future
edit breaks an invariant nobody restates when touching a different field.

## Proposed classification table

| # | Obligation | Class | Mechanism | What a wrong implementation looks like / how this catches it |
|---|---|---|---|---|
| 1 | Rebase/merge cleanliness | Gate-enforced | New `merge_state_clean` gate on `ci_monitor`, command copied verbatim from `execute.md:385-387` (`gh pr view --json mergeStateStatus`) | Agent self-reports `ci_outcome: passing` on a PR that still conflicts with `main`; the independent `gh` query disagrees and the transition to `done` is refused regardless of what the agent submits. |
| 2 | Closing keyword (`Fixes #N`) | Gate-enforced | New gate on `pr_creation` (or a small post-creation state), `gh pr view <num> --json body --jq .body \| grep -qiE '(close[sd]?\|fixe?[sd]?\|resolve[sd]?)\s+#<N>'`, conditioned on the issue being a real GH issue (not a plan-outline child, mirroring `execute.md:654`'s existing discriminator) | Agent creates a PR with no closing keyword — the exact incident that motivated this PRD (PRD lines 67-68) — and submits `pr_status: created`; the gate independently re-reads the live PR body and fails, blocking the walk to `ci_monitor` until the body is fixed. |
| 3 | PR body mechanical shape (PB1-4) | Gate-enforced (pre-existing, elsewhere) | `shirabe validate --pr-body` in CI + the `shirabe pr-body-hook` PreToolUse hook (`references/pr-body-conformance.md`, "Consumers") | Already caught path-independently; recorded in the table as satisfied outside the koto template rather than duplicated inside it. |
| 4 | PR body Part 2 content selection | Advisory | None — no concrete referent exists (`references/pr-body-conformance.md`, "What stays advisory") | N/A by design; gating it would fail a correct minimal PR, per the cited reference's own reasoning. |
| 5 | Design-diagram update | Gate-enforced + evidence field (exceeds R9's minimum) | Evidence field `design_diagram_status: enum[updated, skipped_no_reference, skipped_invalid]` with `design_diagram_path` (typed to a path, required when `updated`) or a fixed-vocabulary `detail` naming which of `phase-6-design-diagram-update.md`'s named skip conditions applied; a gate on the `updated` branch only, checking the referenced file's node actually carries `:::done` at HEAD. Folded to one hop by citing the diagram procedure directly from the state's own prose instead of through `phase-6-pr.md`. | Agent silently skips the diagram (today's failure mode) and reports nothing — now it must submit one of three named values, and if it claims `updated`, the gate independently verifies the class flip; if it claims a skip reason, that reason is one of a fixed, auditable set rather than free prose. |
| 6 | Code cleanup | Evidence-carried | Required field `cleanup_commit: <commit SHA>` (referent: commit identifier per R7a) naming the specific commit where cleanup happened; a light gate confirms the SHA exists and touches files in the PR's diff range | Agent submits a placeholder string instead of a real SHA — a gate that checks `git cat-file -e <sha>` and `git diff main...<sha> --stat` non-empty catches a fabricated or copy-pasted value, though it cannot judge thoroughness (irreducibly the R7 residue). |
| 7 | Summary shape | Gate-enforced (upgraded from the PRD's own evidence-carried example, since structure is objectively checkable) | Replace/augment the existing `context-exists` gate on `summary.md` with a `summary_shape_valid` command gate — a small script grepping the six required `##` headers out of the context-store file, exit non-zero if any is missing | A placeholder `summary.md` (e.g. "N/A") satisfies today's `context-exists` gate; the new shape gate does not, because it checks for the six specific headers rather than mere key presence. |
| 8 | Commit-message convention | Gate-enforced | `git log -1 --format=%s` matched against `^docs: add implementation summary$` | Agent commits the summary under an arbitrary message; trivial value but R6 sets no value floor. |
| 9 | Final verification | Gate-enforced (pre-existing, no new work) | Existing `verification` state, `work-on.md:592-628` | Already caught; listed for completeness of the table per R8. |
| 10 | Auto-skip routing (summary applicability) | Evidence-carried | A `summary_required: bool`-style discriminator (label lookup via `gh issue view --json labels`) feeding which branch of obligation 7's gate applies | Not itself a pass/fail obligation — misclassifying it as gate-enforced would force a summary-shape check on a docs-only PR that's correctly exempt; recorded as evidence-carried so its value is visible in the run record even though it isn't a fact to gate. |

## Recommendation

Extend in place (Option C) for the two obligations that slot directly onto an
existing post-PR state with an exact precedent — merge cleanliness onto
`ci_monitor` and the closing keyword onto `pr_creation` — because both have a
byte-for-byte or near-byte-for-byte match already proven in `execute.md`, and
`validate-template-mermaid.sh` check 4 makes copying the merge-cleanliness gate
verbatim close to mandatory rather than optional. Re-deriving these as new
standalone states would mean re-justifying invariants `execute.md` already
worked out, for no legibility gain.

For the pre-PR evidence-carried and hybrid obligations (code cleanup, summary
shape, design-diagram, commit-message, auto-skip discriminator), add one new
state rather than piling five more required fields onto `finalization`.
`finalization`'s existing three-way branch is already load-bearing for
`deferral_approval`'s human-gate contract, and the PRD's own framing treats
that gate as a delicate, carefully-reasoned mechanism (`work-on.md:638-661`'s
extended comments) — bolting unrelated obligations onto its `accepts:` block
risks entangling review of a change to, say, the design-diagram evidence
field with review of the deferral human-approval path, which is a needless
coupling. A single new state inserted between `finalization` and
`pr_precheck` (name pending the actual design hop — something like
`finishing_evidence`) keeps the new obligations' conditional branches
contained to one state whose only job is those obligations, satisfies
`check-template-directives.sh` rule 1 by modeling the `Design:`-present/absent
and auto-skip branches explicitly (the same shape `pr_precheck`'s
gate-plus-override edges and `pr_finalization`'s `pause_decision` already use),
and needs exactly one new `work-on.mermaid.md` entry rather than several. This
is a genuine hybrid of C and A — extend where an exact precedent exists,
batch narrowly where it doesn't — rather than a pure reading of either option,
and it avoids Option B's linear multiplication of new states and agent turns
for checks that are mechanically cheap to co-locate.

Within that new state, treat obligation 5 (design-diagram) as gate-enforced
plus evidence, not merely evidence-carried as R9's minimum allows — the class
flip is objectively checkable and doing so is what actually catches the silent
skip the PRD names, rather than only making the skip visible after the fact.
Treat obligation 7 (summary shape) the same way — upgrade from the PRD's own
illustrative classification of "evidence-carried" to gate-enforced, because
header presence is structurally as checkable as the diagram's class flip; keep
only the field that names *which* obligations the summary's Requirements
Mapping table claims are satisfied as evidence, since that content is the
genuine judgment residue.

## Open questions

- Whether the closing-keyword gate failure should retry `pr_creation` (agent
  fixes the body, re-submits `pr_status: created`) or route to a distinct
  small "fix PR body" state — the existing `creation_failed_retry` path
  (`work-on.md:768-770`) is about creation failing outright, not about a
  created-but-incomplete PR, and conflating the two loses the "why did this
  fail" signal the retry counter would otherwise carry.
- Whether the design-diagram gate's regex-based `:::done` check produces false
  negatives against real design docs in the corpus that use an older diagram
  format — `phase-6-design-diagram-update.md:74-78` names "old format design"
  as a legitimate, already-anticipated skip condition, and this decision
  doesn't establish how common that shape actually is in `docs/designs/`.
- Whether a fabricated-but-real commit SHA for the code-cleanup obligation is
  meaningfully stronger enforcement than free prose, given the agent still
  fully controls which commit it names — R7a's letter is satisfied (a
  concrete referent, not a string), but whether it closes the substantive gap
  the PRD is worried about is a fair question the design should not paper
  over.
- How the new finishing-evidence state and the extended `pr_creation`/
  `ci_monitor` gates interact with the child-suppression signal governed by
  R11/R12/R19 (a different decision in this same PRD) — a plan-backed child
  that reaches `pr_creation` with `SHARED_BRANCH` set routes straight to
  `done` (`work-on.md:765-767`) without ever entering `ci_monitor`, so any new
  gate placed on `ci_monitor` is automatically child-safe by the existing
  routing, but a gate placed on `pr_creation` itself (the closing-keyword
  check) is not — it needs to be scoped to skip when `pr_status: shared`, the
  same way the existing transitions already branch on that value.
- Whether obligation 10 (auto-skip routing) is in this feature's scope at all,
  since it predates this PRD and is a routing rule rather than a "finishing
  obligation that decides whether a change is finishable" in the PRD's own
  sense (PRD line 86) — worth confirming with whoever owns the design hop
  before spending a field on it.
