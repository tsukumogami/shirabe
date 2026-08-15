# Decision 1 report: how a blocking retry forces a fresh verdict

Tier 4 (critical), full path. Phases 0-6 with an adversarial bakeoff across four
alternatives and an independent red-team verification of the leading answer.

Process note, recorded because it affects how much weight the record carries.
Phase 5 was run as **independent verification by two neutral agents** who
advocated for nothing — one re-running the leading option's probes from scratch,
one settling the contested cross-repo question against the governing contracts.
That was a stronger check than peer revision on the point that mattered, because
the leading option's evidence had until then been produced only by its own
advocate. Every probe result below was reproduced by an agent with no stake in
the outcome.

The three bakeoff validators then returned their Phase 4 revisions late, after
the first synthesis. All three are folded in below. None changed the choice —
all three land on this option or concede it is right under the PRD as written —
but they corrected three things this report had wrong, and each correction is
recorded at the point it applies. The most consequential: alternative D withdrew
its central concession on evidence, which required rewriting D's rejection
rather than restating it.

<!-- decision:start id="retry-invalidation-mechanism" status="assumed" -->
### Decision: How a blocking retry forces a fresh verdict from the review phases it re-enters

**Context**

`/work-on` runs three review phases after implementation — `scrutiny`, `review`,
`qa_validation`. Each writes a results artifact into koto context and gates its
`passed` transition on a `context-exists` gate over that key. Each also accepts
`blocking_retry`, which routes to `implementation`, and `implementation` routes
forward into `scrutiny`. So a retry raised anywhere re-enters every review phase
at or above it, and each of those phases finds its own previous verdict still
present and its gate still satisfied. The verdict that sent the work back is the
verdict that waves it through. The one step that would fix this names
`koto context remove`, a subcommand koto does not have, and the failure is
swallowed by the `2>/dev/null` operators type to escape koto's migration noise.

The question merges three sub-questions that turned out to be inseparable: which
command invalidates the artifacts, which gate type rejects the invalidated
value, and at which edge the invalidation runs. They cannot be answered
independently — `remove` leaves a key absent, which `context-exists` already
reports correctly, while an overwrite leaves the key present, which
`context-exists` cannot distinguish from a fresh write. The verb determines what
is viable for the gate.

The decisive constraint is structural and was verified rather than assumed:
**koto's engine never writes to the context store.** `context_assignments:` is
silently dropped at compile time, and a gate's `key:` is a static literal that
nothing substitutes — `koto next` clones each gate and rewrites exactly one
field, `g.command`, leaving `key` and `pattern` untouched
(`koto/src/cli/mod.rs:3836-3841`). So the invalidation must live in something an
agent runs, and the gate's job is to make the invalidated state un-advanceable.

**Assumptions**

- **The three panel artifacts are written by LLM agents following a heredoc in
  the phase files, and will mostly follow it.** The chosen gate keys on
  `"passed": true`, a field every shipped heredoc already writes. If an agent
  improvises a different shape, the gate rejects a legitimate passing artifact
  and every exit from that state is a failure exit. *If wrong:* a passing run
  can be trapped. This is the residual risk the chosen option carries and the
  mitigations below exist for it.
- **No consumer downstream reads the panel artifacts.** Verified today
  (`grep` over `skills/` returns only the three phase files and the panel
  summary). *If wrong later:* a future consumer must learn the cleared sentinel,
  which the chosen option introduces into the artifact namespace.
- **tsuku's `latest` resolves the newest GitHub release of `tsukumogami/koto`
  with no recipe change.** Grounded in `koto/.tsuku-recipes/koto.toml` and
  tsuku's org-key resolution, not observed post-release. Bears only on the
  rejected option A.
- **koto would want a session event for a context removal**, by parity with
  `ContextAdded`. Unverified; bears only on option A's size.
- Made in `--auto` mode without user confirmation, which is why the status is
  `assumed` rather than `confirmed`.

**Chosen: Overwrite-to-clear with a `context-matches` gate, at the exit edge**

Three parts, and each covers a failure the others do not.

*1. The invalidation is an overwrite through a command that exists.* On the
`blocking_retry` path, before the submission, the agent writes a cleared
sentinel over **all three** panel keys using `koto context add` — the verb koto
ships today. It reads each value straight back and compares it against the
literal it just wrote, printing a diagnostic on **stdout** on mismatch, because
stderr is the stream operators redirect away. The read-back comparison is the
check, not the exit status: `koto context add` on an existing key with an
unwritable ctx directory exits 3 *after the value has landed*, so a block that
branched on the exit code would report failure on a write that worked.

*2. The gate becomes `context-matches` with one anchored pattern.* All three
states change from `type: context-exists` to `type: context-matches` with the
shared pattern

```
pattern: '(?s)^\{.*"passed" *: *true.*\}\s*$'
```

referenced from the `passed` transition's `when` clause as
`gates.<name>.matches: true`, and referenced from **neither** failure edge, so
`blocking_retry` and `blocking_escalate` stay reachable when the context store
is exactly what is broken (R4). `override_default` is dropped entirely, matching
the landed precedent: `built_in_default` for `context-matches` already supplies
both the `koto overrides list` record and the `agent_actionable` flag, so the
block buys nothing.

The pattern is anchored at both ends because `context-matches` evaluates
`Regex::is_match`, a substring test; unanchored it would pass any value merely
containing the token. `(?s)` and `\s*$` are load-bearing tolerances, not
decoration — koto stores stdin verbatim and the phase files write with a
heredoc, which appends a newline, so a strictly anchored pattern would reject
every legitimate pass.

*3. The invalidation runs at the exit edge, before the submission.* Placement
(i): in the same block that submits `blocking_retry`, with the clearing loop
ahead of `koto next`. The ordering is not stylistic. Clear-then-submit fails
closed — if the submission never happens the run sits in the phase with a
failing gate. Submit-then-clear fails open — the state has already moved to
`implementation` and nothing remains on the path to retry the clear.

**Rationale**

The mechanism was verified end-to-end against real koto 0.11.4 — the build the
project tool manifest installs — twice, by its advocate and then independently
by a neutral red team that re-ran every probe from scratch. One run discharges
four acceptance criteria: a `blocking_retry` raised in `qa_validation` holds
both `scrutiny` and `review` on `passed` until each has a fresh artifact; the
`review`-raised and `scrutiny`-raised traversals behave the same; a well-formed
artifact advances all three phases; and both failure exits stay reachable with
the gate failing. The real `work-on.md` with exactly these six edits compiles at
exactly its pre-existing one-warning baseline, exit 0.

It ships in one repo, in one PR, against the koto that is already installed.
That is the decisive difference. The defect is a shirabe defect — a shirabe
instruction naming a verb that does not resolve — and this keeps the fix, the
test, and the guarantee in the repo that owns the bug.

The shape is not invented. `skills/execute/koto-templates/execute.md` carries
`settled_branch_recorded` — `type: context-matches`, anchored pattern,
referenced from the success transitions and deliberately not from the failure
transition — merged as the fix for the *identical defect class* one skill over,
with its reasoning already commented in place. This decision applies that
decision to the phases whose sweep filed this issue.

Two things chosen against the grain of the earlier research, both on evidence.
The research carried a pattern keyed on `"round"`, which does not accept the
shipped QA artifact and would have forced a heredoc edit; keying on
`"passed": true` accepts all three shipped artifacts unedited (verified
independently) and is semantically stronger, since the gate is referenced only
from the `passed` edge. And the research's justification for converting only
three of the file's twelve gates — "only these three are re-entered" — is
**false**: `plan_artifact` (`work-on.md:387`) and `summary_exists`
(`:633`) sit on states that back-edges also reach and are live instances of the
same defect. That makes this a first step on a coherent path rather than a
permanent inconsistency, and it owes a written rule and a follow-up issue.

The accepted trade-off is that the cleared value is a *value*, not an absence.
`koto context list` after a retry shows three keys holding the sentinel, which a
careless reader could misread, and which a future consumer would have to learn.
The rejected option A leaves a clean absence instead. That is a real cost and it
is smaller than a cross-repo release on the critical path.

**Alternatives Considered**

- **A — wire `koto context remove` into koto's CLI.** `ContextStore::remove` is
  already a trait method fully implemented in both backends with no callers, so
  the novel logic is under 40 lines, and it would make the currently-shipped
  instruction true as written while leaving shirabe's template, twelve gates,
  three `override_default` blocks and three eval fixtures untouched. It was the
  strongest rival and it loses on the release, not on the code. shirabe's
  `.tsuku.toml` pins `"tsukumogami/koto" = "latest"` and CI installs a
  **released** binary, so PRD acceptance criterion 1 — `koto context remove
  --help` exits 0 against the koto CI installs — keeps the shirabe PR red until
  a koto release ships the verb. Local koto is `0.11.5-dev` against a last
  release of v0.11.4, and there is no legitimate escape: building from source
  violates R9, and pinning still needs a tag to point at. Independent
  verification confirmed the scoping consequence is real rather than
  hypothetical: a PLAN containing the koto issue **must** be coordinated
  (`single-pr` has no schema slot for a second repo), which costs roughly five
  extra durable artifacts and ten extra steps, plus a milestone and real issues
  in two repos. The advocate's escape — dispatch the koto verb as its own
  effort — is legitimate on the text of the contract, which conditions the mode
  on where work lands and never on motivation, but it survives only if the split
  is declared in the DESIGN, because `/review-plan`'s Scope Gate will otherwise
  pull the koto work back in. Separately, choosing A means amending an upstream
  In-Progress PRD: R5 demands the step "read its own result back and compare
  it", and under A the success state is a *missing* key, so the correct probe is
  `koto context exists`, whose contract is exit-code-only with no stdout. A's own
  advocate conceded the literal reading loses. A remains the better answer if the
  koto verb is wanted for its own sake; it is not the better answer to this
  defect.
- **C — restructure so no invalidation is needed** (per-round keys, or routing
  the retry so the gate re-evaluates against a fresh key). **Unreachable, not
  merely unattractive.** A gate's `key:` is copied verbatim by the compiler
  (`koto/src/template/compile.rs:512,538`) and never substituted at run time,
  so `key: scrutiny_results_round_{{ROUND}}.json` yields a context key
  containing the literal `{{ROUND}}`. And nothing could increment a counter even
  if it did interpolate: template variables come from a single
  `WorkflowInitialized` event emitted once at `koto init`
  (`koto/src/engine/substitute.rs:60-75`) with no CLI verb to append another,
  and runtime variables are a hardcoded two-entry map. Everything surviving
  under the label collapses into the chosen option or violates R3.
- **D — a `command` gate that computes freshness.** Reachable, and by the end of
  the process the technically strongest mechanism on the table.
  `{{SESSION_DIR}}` *is* substituted into gate commands, so the gate can decide
  freshness itself and **no invalidation step is needed at all** — the
  `transitioned` event koto appends on `blocking_retry` is what makes all three
  artifacts stale, atomically, whichever phase raised it. Verified end-to-end
  twice: a stale artifact holds `passed` in both `scrutiny` and `review` after a
  `qa_validation` retry with zero invalidation commands in the session, fresh
  advances, and both failure exits stay reachable.

  **This report's first draft rejected D for reading koto's undocumented
  internals, and that reason is wrong.** D's validator withdrew the concession
  on evidence and I verified it: the mechanism needs no `ctx/manifest.json` read
  at all, because `koto context add` appends a first-class `ContextAdded` event
  carrying the key and an envelope `timestamp` into
  `koto-<session-id>.state.jsonl` — the file `koto/docs/workspace-layout.md`
  lists by name in its directory tree under **AUTHORITATIVE state**, and whose
  envelope keys (`seq`, `timestamp`, `type`, `payload`) `koto/docs/STABILITY.md`
  freezes behind a schema bump. So D reads one documented, stability-pinned
  surface in about six lines of dash. The cloud objection also mostly falls: the
  event log syncs through `backend.append_event`, unlike the local ctx manifest.

  **What D actually loses on is the PRD, and only the PRD.** It has no
  invalidation block, so R5 ("the invalidating step reads its own result back
  and compares it"), R6's "it is literally the *same step*", R2's definition of
  invalidate by removal or replacement, and three step-shaped acceptance
  criteria are left vacuous — not violated, vacuous. D's own validator is right
  that vacating them is the PRD author's call to grant and not a DESIGN's to
  assume, and that the PRD is `In Progress` upstream in a chain
  `shirabe validate --lifecycle` checks. Choosing D means amending an upstream
  requirements document to accommodate a mechanism nobody has shipped in this
  workspace; the chosen option satisfies every criterion as written, today. That
  is the honest reason, and it should replace the wrong one in the DESIGN.

  One constraint on any future D, found in revision:
  `scripts/check-template-interpolation.sh` scans `command:` fields and rejects
  bare `$NAME` after `{{KEY}}` stripping, so D's gate must express its reads and
  its timestamp compare with **no shell variables at all** — only nested
  `$(...)` and `{{SESSION_DIR}}`.
- **Placement (ii), re-entry** — clear at the top of each phase before the panel
  re-runs. Rejected on three independent grounds. It **fails an acceptance
  criterion outright**: the criterion verifies by extracting the shipped block
  on the `blocking_retry` path, and a re-entry-only design has none to extract.
  It puts a new command on the first-pass path, which is what R8 exists to
  prevent, because an agent entering `scrutiny` cannot tell round 1 from round
  2. And because R6 makes the step cover all three keys, a re-entry block in
  `review` clobbers the *fresh* `scrutiny_results.json` written moments earlier
  in the same round — no gate breaks, since koto evaluates only the current
  state's gates, but a clean run then ends with only `qa_results.json` valid,
  destroying the evidence that the panels ran this round, which is exactly what
  the PRD's operator user story goes looking for.
- **Placement (iii), both.** Satisfies the criterion through its exit-edge half
  and adds nothing: it inherits (ii)'s clobber and first-pass command, doubles
  the surface the extraction test must keep byte-identical, and defends only
  against an agent that ran the `koto next` half of a block and skipped the loop
  directly above it in the same fence.

**Consequences**

*Positive.* A retry can no longer advance a review phase on the previous round's
verdict, and the refusal is structural — koto evaluates the gate and returns
`advanced: false` with a `blocking_conditions` entry naming the gate,
`matches: false`, `agent_actionable: true`. All three phases carry one contract
whose invalidation step is byte-identical below its first line, so R6 is
checkable by `diff`. The fix ships against the koto already installed, in the
repo that owns the defect.

*Negative.* The artifact namespace gains a sentinel value where there was
previously either a real artifact or nothing. `work-on.md` gains a second gate
type, and the reason only three of twelve gates converted needs writing down.
And the gate now couples to the artifact's *shape*: an editor who rewrites a
heredoc breaks the gate. That failure is loud rather than silent, which is the
right direction, but it is a coupling the file does not have today.

*The one cost that does not show up until later*, raised in revision by the
rival advocate and conceded here as correct. The chosen mechanism does not
extend to the three latent defects it uncovered. `plan.md` and `summary.md` are
**markdown**, written `--from-file` (`phase-3-analysis.md:42`), so a pattern
keyed on `"passed": true` cannot reach them at all. Fixing `:387`, `:633` and
`:672` later will need a freshness marker for two markdown documents and a
second sentinel convention — a different technique from this one, not an
extension of it. The rejected option A, whose remedy is content-agnostic
(removal does not care what the value looks like), would have reached all six
gates by appending strings to a loop. That does not change the decision — the
three latent defects are explicitly out of this PRD's scope and the release
dependency is paid now rather than later — but whoever picks up the follow-up
should know the technique does not come for free, and the DESIGN should say so
rather than let the follow-up issue imply a copy-paste.

*Required mitigations, each of which the design must carry.* These came out of
the independent verification and are not optional polish.

1. **The `"passed": true` field becomes a documented evidence contract in all
   three phase files, as a named acceptance item.** This is the residual risk's
   only real defence. `phase-4c-qa.md` currently shows two different JSON shapes
   — the tester's return format at `:17-24`, which has no `passed` key, and the
   context-write heredoc at `:35`, which does. An agent that conflates them
   writes a legitimate passing artifact the gate rejects (verified:
   `matches: false`), and koto names the gate but not the pattern, so the
   operator is left guessing. The three phase files must say that the value
   written to context carries `"passed": true`.
2. **The sentinel/pattern coupling must be asserted in CI, and the failure
   direction is fail-open.** The sentinel lives in the phase files and the
   pattern lives in the template, and they are correct only in relation to each
   other. If they drift into *agreement* the block still passes its own
   read-back — it compares against its own literal, so it always agrees with
   itself — and the gate then **accepts** the sentinel: the original defect
   restored, by a fix reporting success. A nested `"passed": true` is the
   realistic way in, and it arrives disguised as an improvement (a sentinel
   edited to "record what was superseded"). Verified hazard, not hypothetical.

   The mitigation is checkable rather than merely careful, and it was built and
   run: extract `CLEARED=` from the shipped phase file, drive the shipped
   template's gate with that value through real koto, assert the state holds.
   Baseline passes; mutating only the phase file's sentinel fails; mutating only
   the template's pattern fails. One four-line assertion, pasting neither side,
   catching both directions. It belongs first in the test, ahead of every other
   case.
3. **The extraction test's markers.** Both the success block and the retry block
   in each phase file contain `koto context add`, so the precedent's
   `extract_block "$TEMPLATE" "koto context add"` marker is ambiguous here. Use
   `blocking_retry` for the retry block.
4. **Failure injection targets the key file, not the ctx directory.** The
   precedent locks the directory, which is right for a *new* key; this design
   overwrites an *existing* one, where a directory lock lets the value land
   anyway. `chmod 0444` on the key file is what produces a genuine failure.
5. **Regenerate the mermaid companion.** Contrary to an advocate's claim, the B
   edits do produce a diff in `work-on.mermaid.md`, and only koto's reusable
   freshness workflow catches it.
6. **Correct `review-panel-orchestration.md:15-16`.** Its claim that panel states
   carry `override_default` "so skipping is auditable via `koto overrides list`"
   is wrong today — `built_in_default` already supplies that — and the blocks are
   being removed.

*Findings to record rather than act on.*

- **The PRD's Known Limitation is false as written.** It says koto "cannot make
  it otherwise" than agent-performed. koto **can**: a command gate reading
  `SESSION_DIR` computes freshness with no agent step at all, verified
  end-to-end. The design should say so with the evidence and give the real
  reason for declining — that it depends on koto's undocumented on-disk layout
  and misreads under the cloud backend — rather than repeat a claim that is not
  true.
- **A limitation nobody had named, mechanism-independent:** `koto overrides
  record` works with no `override_default` declared and lets an agent advance
  past the failing gate. So R3's guarantee is "structural modulo a recorded
  override". That is the correct design (an override is auditable and
  deliberate), but it belongs in Known Limitations because the PRD currently
  implies the gate is absolute.
- **Three more latent instances of this defect**, and the count needs care
  because two agents reached opposite answers on the third. `plan_artifact`
  (`work-on.md:387`) is satisfied by the previous round's `plan.md` when
  `implementation` returns on `scope_expanded_retry` — a state whose purpose on
  that edge is to rewrite the plan, gated on the plan it is meant to replace.
  `summary_exists` (`:633`) is satisfied by the previous round's summary when
  `finalization` submits `issues_found` (`:651`) and the run comes back around
  through `verification` (`:612`). Both verified by everyone who looked.

  The third, `deferral_approval`'s `summary_exists` at `:672`, was called live
  by one agent and dead by another, so I traced it directly. Exactly one
  transition targets `deferral_approval` — `finalization:659` on
  `deferral_requested` — and nothing routes back into it, so the *state* is
  entered once and the "not on a cycle" finding is correct as far as it goes.
  But it is the wrong test. `finalization` **is** on a cycle, so a run can write
  `summary.md`, go back to `implementation` for a fix, return through
  `verification` to `finalization`, and then enter `deferral_approval` for the
  first time with a `summary.md` that predates the fix. The gate passes on a
  stale key on a first and only entry. **It is a live instance.** Three, not
  two.
- **The separating rule, stated correctly — this is the durable finding.** Two
  formulations were offered and both over-indict. "Sound exactly when no
  transition targets its state" condemns every non-initial state. "Sound unless
  the state lies on a cycle" is closer but misses `:672`, as above. The rule
  that is actually true is about the **key, not the state**: presence-only
  gating is sound when the key cannot survive from one evaluation of that gate
  into another, by any path. Under it, `work-on.md` splits cleanly — six gates
  sound (`:80, :165, :197, :226, :295, :358`, all on the pre-implementation
  spine, reached only from strictly upstream states and evaluated once in a
  run's life) and six unsound (the three panel gates this change fixes, plus
  `:387`, `:633`, `:672`). That rule belongs in the DESIGN and in a comment
  beside the first converted gate.
<!-- decision:end -->
