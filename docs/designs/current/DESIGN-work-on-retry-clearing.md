---
schema: design/v1
status: Current
upstream: docs/prds/PRD-work-on-retry-clearing.md
problem: |
  /work-on's three review phases gate their `passed` transition on a
  presence-only `context-exists` key holding that phase's results artifact. A
  `blocking_retry` routes to `implementation`, which routes forward into
  `scrutiny`, so a retry re-enters every review phase at or above the one that
  raised it -- each finding its own previous verdict still present and its gate
  still satisfied. The one step that would fix it names `koto context remove`,
  which koto does not have, and the failure is swallowed by the `2>/dev/null`
  operators type to escape koto's migration noise.
decision: |
  On the `blocking_retry` path, before the submission, overwrite all three panel
  keys with a cleared sentinel through `koto context add`, read each value back
  and compare, and print the diagnostic on stdout. Convert the three gates from
  `context-exists` to `context-matches` on one anchored pattern keyed on
  `"passed": true`, referenced from the `passed` transition's `when` clause and
  from neither failure edge. A CI assertion drives the shipped sentinel through
  the shipped gate so the two cannot drift into agreement.
rationale: |
  It ships in one repo, in one PR, against the koto already installed, and it
  reuses the shape `/execute` merged for the identical defect class one skill
  over. Adding `koto context remove` to koto was the strongest rival and loses
  on ordering rather than on code: CI installs a released koto, so the shirabe
  PR stays red until a koto release ships the verb. A command gate computing
  genuine freshness is stronger still and is declined only because it leaves
  four of this PRD's requirements vacuous.
---

# DESIGN: /work-on Retry Clearing

## Status

Current

## Context and Problem Statement

`/work-on` drives a koto state machine whose post-implementation spine is three
review phases in order: `scrutiny`, `review`, `qa_validation`. Each writes a
results artifact into koto context and gates its `passed` transition on that
key. Each also accepts `blocking_retry`, which routes to `implementation` so a
coder agent can fix what a reviewer found.

The technical problem is that the gate cannot distinguish a verdict from this
round from one written before the fix. All three declare `type: context-exists`,
which reports presence and nothing else, and the artifact from the round that
just failed is present. So the verdict that sent the work back is the verdict
that satisfies the gate on the way past.

The phases are not three independent instances. `implementation` transitions
forward to `scrutiny` for `issue_type: code`, so a retry raised in `review`
re-enters `scrutiny` and `review`, and one raised in `qa_validation` re-enters
all three. A retry always re-enters every review phase at or above the one that
raised it. That is why the invalidation has to cover all three keys rather than
the raising phase's alone.

`skills/work-on/references/phases/phase-4a-scrutiny.md` tries to close this and
cannot: it instructs `koto context remove`, and koto's context group is `add`,
`get`, `exists`, `list`. The command exits with `error: unrecognized subcommand
'remove'`. The same passage also states its own causality backwards -- it says a
stale artifact makes the gate fail, when a stale artifact makes the gate *pass*
and the removal is the only thing that would produce a fresh run.

**The constraint that shapes every option**, verified rather than assumed:
koto's engine never writes to the context store. `context_assignments:` on a
transition is silently dropped at compile time -- koto's `Transition` struct
carries `target` and `when` only -- and a gate's `key:` is a static literal the
compiler copies verbatim, with `koto next` rewriting exactly one gate field
(`g.command`) at run time. So no mechanism can have the state machine invalidate
a key on an edge, and an invalidation-based design must place the step in
something an agent runs, leaving the gate to make the invalidated state
un-advanceable.

## Decision Drivers

- **The guarantee must not rest on prose.** PRD R3. A gate koto evaluates holds
  under an agent that skipped a step; a sentence does not. This is the lesson
  the same defect class already taught once, in `/execute`.
- **The failure must survive `2>/dev/null`.** PRD R5. koto's migration noise
  makes stderr the stream operators discard.
- **One contract across three phases.** PRD R2 and R6.
- **First-pass behaviour is frozen.** PRD R8. A phase reached for the first time
  advances exactly as it does today -- which, as it turns out, decides the
  pattern.
- **The failure exits stay reachable.** PRD R4. A run whose context store is
  broken must still reach a terminal state.
- **koto's interface is a boundary the design may cross, at a price.** PRD R1
  deliberately permits adding a subcommand to koto. The workspace's
  `## PR Grouping Policy: coarsest-legal` makes that a coordinated two-repo
  effort, and CI installs a *released* koto.

## Considered Options

### Decision 1: How a blocking retry forces a fresh verdict

Evaluated at critical tier through the full `/decision` path: research, four
alternatives, an adversarial bakeoff with three advocates, peer revision,
cross-examination, and an independent red team that re-ran the leading option's
probes from scratch. The report is a non-durable working artifact, so the
substance is reproduced here.

The question merges three sub-questions that are not separable. `remove` leaves
a key absent, which `context-exists` already reports correctly; an overwrite
leaves the key present, which `context-exists` cannot tell from a fresh write.
The verb decides what is viable for the gate, and the gate decides what the
placement has to be true of.

#### Chosen: overwrite-to-clear, a `context-matches` gate, at the exit edge

Three parts, each covering a failure the others do not.

**1. The invalidation is an overwrite through a command that exists.** On the
`blocking_retry` path, before the submission, the agent writes a cleared
sentinel over all three panel keys with `koto context add`, reads each value
straight back, and compares it against the literal it just wrote. A mismatch
prints a diagnostic on **stdout** and stops.

The read-back comparison is the check, and the exit status is deliberately not.
`koto context add` overwriting an existing key writes the content in place and
can then exit 3 on the bookkeeping that follows -- so a block branching on the
exit code would report failure on a write that landed. Comparing the value
answers the question the contract actually asks.

**2. The gate becomes `context-matches` on one anchored pattern.**

```yaml
      scrutiny_results:
        type: context-matches
        key: scrutiny_results.json
        pattern: '(?s)^\{.*"passed" *: *true.*\}\s*$'
```

referenced from the `passed` transition as `gates.<name>.matches: true`, and
from **neither** failure edge, so `blocking_retry` and `blocking_escalate` stay
reachable when the store is what is broken (R4). `override_default` is dropped:
`built_in_default` for `context-matches` already supplies the
`koto overrides list` record and the `agent_actionable` flag, so the block buys
nothing.

The anchors are load-bearing. `context-matches` evaluates `Regex::is_match`, a
substring test, so unanchored the pattern would accept any value merely
containing the token.

`\s*$` is required, and its reason is concrete: koto stores stdin verbatim and
all three phase files write their artifact with a heredoc, which leaves a
trailing newline. Anchored strictly at the end, the gate would reject every
legitimate pass.

`(?s)` is **defensive rather than required**, and an earlier draft of this
paragraph got that wrong by attributing both to the heredoc's newline. Checked
against the regex crate koto actually links: the shipped payloads are
single-line JSON, so `.` never has to cross a newline and the pattern matches
without DOTALL. It is carried so a future multi-line payload does not silently
stop matching, which is a different justification from the one `\s*$` has and is
worth keeping distinct — a reader who believes both are forced by the heredoc
will draw the wrong conclusion when they change the payload shape.

**Keying on `"passed": true` rather than on `"round"` is the detail that keeps
R8 true**, and it corrects this design's own earlier research. `scrutiny` and
`review` write `{"passed": true, "round": 1, "blocking_count": 0}`, but
`qa_validation` writes `{"passed": true, "scenarios_run": 3, "scenarios_passed":
3}` -- no `round` field at all. A `"round"`-keyed pattern would have rejected
the shipped QA artifact and forced a heredoc edit on the first-pass path, which
is the one thing R8 forbids. `"passed": true` accepts all three shipped payloads
unedited, and it is the semantically right key besides: the gate is referenced
only from the `passed` edge.

**3. The invalidation runs at the exit edge, ahead of the submission.** The
ordering is not stylistic. Clear-then-submit fails closed -- if the submission
never happens, the run sits in the phase with a failing gate. Submit-then-clear
fails open -- the state has already moved to `implementation` and nothing on the
path remains to retry the clear.

#### Alternatives Considered

- **Wire `koto context remove` into koto's CLI.** The strongest rival, and it
  loses on ordering rather than on code. `ContextStore::remove` is already a
  fully implemented trait method in both backends with no callers, so the novel
  logic is under 40 lines; it would make the shipped instruction true as
  written, need no gate change, and leave shirabe's template, its twelve gates
  and its eval fixtures untouched. Its remedy is also content-agnostic, which
  matters for the follow-up work below. It was rejected because shirabe's
  `.tsuku.toml` pins `"tsukumogami/koto" = "latest"` and CI installs a
  **released** binary: PRD acceptance criterion 1 keeps the shirabe PR red until
  a koto release ships the verb, and local koto is `0.11.5-dev` against a last
  release of v0.11.4. Building from source violates R9 and pinning still needs a
  tag to point at. Under `coarsest-legal` grouping a PLAN containing the koto
  issue must be coordinated -- `single-pr` has no schema slot for a second repo
  -- which costs roughly five extra durable artifacts, a milestone, and issues
  in two repos. Choosing it would also mean amending an In-Progress upstream
  PRD, because R5 demands the step read its result back and compare, and under
  removal the success state is a *missing* key whose only probe,
  `koto context exists`, is exit-code-only with no stdout. It remains the better
  answer if the koto verb is wanted for its own sake. It is not the better
  answer to a shirabe instruction naming a verb that does not resolve.

- **Restructure so no invalidation is needed** -- per-round keys, or routing the
  retry so the gate re-evaluates against a fresh key. **Unreachable, not merely
  unattractive**, and recorded as such because the issue that prompted this work
  listed it as live. A gate's `key:` is copied verbatim by the compiler and
  never substituted at run time, so `key: scrutiny_results_round_{{ROUND}}.json`
  yields a context key containing the literal `{{ROUND}}`. Nothing could
  increment such a counter even if it did interpolate: template variables come
  from a single `WorkflowInitialized` event emitted once at `koto init`, with no
  CLI verb to append another, and runtime variables are a hardcoded two-entry
  map. Everything that survives under this label collapses into the chosen
  option or violates R3.

- **A `command` gate that computes freshness.** Reachable, and by the end of the
  evaluation the technically strongest mechanism on the table. `{{SESSION_DIR}}`
  *is* substituted into gate commands, so the gate can decide freshness itself
  and **no invalidation step is needed at all** -- the event koto appends on the
  `blocking_retry` transition is what makes all three artifacts stale, at once,
  whichever phase raised it. It was verified end to end twice: with zero
  invalidation commands in the session, a stale artifact holds `passed` in both
  `scrutiny` and `review` after a `qa_validation` retry, a fresh one advances,
  and both failure exits stay reachable.

  An earlier draft rejected it for reading koto's undocumented internals. **That
  reason was wrong and is corrected here**, because a rejected alternative
  written down weaker than it is corrupts the record. The mechanism needs no
  `ctx/manifest.json` read: `koto context add` appends a first-class
  `ContextAdded` event carrying the key and an envelope `timestamp` into
  `koto-<session-id>.state.jsonl`, a file koto's `docs/workspace-layout.md`
  lists under AUTHORITATIVE state and whose envelope keys `docs/STABILITY.md`
  freezes behind a schema bump. It reads one documented, stability-pinned
  surface in about six lines of shell.

  What it actually loses on is this PRD, and only this PRD. Having no
  invalidation block, it leaves R5, R6's "literally the same step", R2's
  definition of invalidate, and three step-shaped acceptance criteria *vacuous*
  -- not violated, vacuous. Vacating an In-Progress upstream requirements
  document is the PRD author's call to grant, not a design's to assume, and the
  chosen option satisfies every criterion as written, today. Anyone reviving it
  should know one constraint found late:
  `scripts/check-template-interpolation.sh` rejects bare `$NAME` in `command:`
  fields after `{{KEY}}` stripping, so such a gate must express its reads and
  its timestamp comparison with no shell variables at all -- only nested
  `$(...)` and `{{SESSION_DIR}}`.

- **Placement at re-entry, clearing at the top of each phase.** Rejected on
  three independent grounds. It fails an acceptance criterion outright, since
  that criterion verifies by extracting the shipped block from the
  `blocking_retry` path and a re-entry-only design has none to extract. It puts
  a new command on the first-pass path, which is what R8 exists to prevent,
  because an agent entering `scrutiny` cannot tell round 1 from round 2. And
  because the step covers all three keys, a re-entry block in `review` would
  clobber the *fresh* `scrutiny_results.json` written moments earlier in the
  same round -- no gate breaks, since koto evaluates only the current state's
  gates, but a clean run then ends with only `qa_results.json` valid, destroying
  the evidence that the panels ran.

- **Placement at both edges.** Satisfies the criterion through its exit-edge
  half and adds nothing: it inherits the re-entry clobber and the first-pass
  command, doubles the surface the extraction test must keep byte-identical, and
  defends only against an agent that ran the `koto next` half of a block and
  skipped the loop directly above it inside the same fence.

### Decision 2: Where the test lives and how CI runs it

Tier 2, settled with the lightweight protocol rather than escalated: cheap to
revise, a clear winner from the repository's own conventions, and not the
question this design exists to answer.

A new `skills/work-on/scripts/retry-clearing_test.sh`, a new
`.github/workflows/check-work-on-scripts.yml` modelled on
`check-execute-scripts.yml`, and a `work-on` suite registered in
`scripts/check-bash-floor.sh`. Shell suites in this repository live beside the
skill they test and each has its own workflow; `skills/work-on/` has no
`scripts/` directory yet. `check-execute-scripts.yml` already solves the hard
part -- its Linux leg installs tsuku and then the project tool manifest to get a
real koto, and its macOS leg runs the suite on the bash 3.2 floor. The harness
needs the same koto-absent SKIP the precedent uses, because the floor leg has no
koto. `suite_needs_shirabe()` returns false: this harness drives koto only.

Adding the cases to `skills/execute/scripts/settled-branch-record_test.sh` was
rejected on ownership -- a `/work-on` regression failing a workflow named for
`/execute` sends the next reader to the wrong skill.

## Decision Outcome

The invalidation, the gate, and the drift assertion are one mechanism, and each
covers a failure the others do not. The overwrite fixes the command that never
worked. The read-back gives a human a sentence to act on, on the stream that
survives the redirection operators actually perform. The gate makes the cleared
state un-advanceable under an agent that skipped the re-run, which is the failure
this defect class has now produced twice. And the drift assertion covers the one
hazard the other two create between them.

The shape is not invented here. `skills/execute/koto-templates/execute.md`
carries `settled_branch_recorded` -- `type: context-matches`, anchored pattern,
referenced from the success transitions and deliberately not from the failure
transition -- merged as the fix for the identical defect class one skill over.
This design applies that decision to the phases whose sweep filed this issue.

The accepted trade-off is that the cleared value is a *value*, not an absence.
`koto context list` after a retry shows three keys holding the sentinel, which a
careless reader could misread and which a future consumer would have to learn.
Removal would have left a clean absence. That cost is smaller than putting a
cross-repo release on the critical path of a shirabe defect.

## Solution Architecture

Seven files change and two are new.

**`skills/work-on/koto-templates/work-on.md` -- three gates.** Each of
`scrutiny`, `review`, `qa_validation` changes `type: context-exists` to
`type: context-matches`, gains the shared `pattern:`, drops `override_default:`,
and changes its `passed` transition's `when` key from
`gates.<name>.exists: true` to `gates.<name>.matches: true`. The
`blocking_retry` and `blocking_escalate` transitions are untouched, which is
what keeps R4 true.

A comment beside the first converted gate states the separating rule below, so
the next reader learns why three of twelve gates converted.

**`skills/work-on/references/phases/phase-4a-scrutiny.md`,
`phase-4b-review.md`, `phase-4c-qa.md` -- the retry block.** Each gains the same
block on its `blocking_retry` path, byte-identical below its first line:

```bash
CLEARED='{"cleared": true, "superseded_by": "blocking_retry"}'
for KEY in scrutiny_results.json review_results.json qa_results.json; do
  printf '%s' "$CLEARED" | koto context add <WF> "$KEY" 2>/dev/null
  BACK=$(koto context get <WF> "$KEY" 2>/dev/null)
  if [ "$BACK" != "$CLEARED" ]; then
    echo "$KEY NOT cleared: read back [$BACK]"
    echo "do NOT submit a passed outcome on the next pass -- the previous round's verdict is still in place"
    exit 1
  fi
done
koto next <WF> --with-data '{"scrutiny_outcome": "blocking_retry"}'
```

**The loop is unconditional, and that is a correctness property rather than a
simplification.** An earlier draft guarded each key with
`koto context exists <WF> "$KEY" || continue`, to skip artifacts no phase had
written yet. The security review found that this reopens the defect the design
exists to close: `handle_exists` returns a bare `bool` from `ctx_exists`, so
koto's CLI cannot distinguish *key never written* from *store unreadable right
now*, and the guard's `continue` therefore silently skips clearing a key whose
real verdict is still sitting there. If the store recovers before the phase is
re-entered -- and `implementation` runs in between, so it has time to -- the
previous round's `"passed": true` satisfies the gate. Reproduced end to end.

Dropping the guard costs nothing, because the branch it was protecting does not
exist. `context-matches` reports `matches: false` for an absent key and
`matches: false` for the sentinel, so writing a sentinel over a never-written
key changes no gate outcome; `koto context add` creates a key on demand, so the
block still exits 0 on a `scrutiny`-raised retry before the other two phases
have run. What the unconditional loop buys is that every key now passes through
the read-back comparison, so an unreadable store is *caught* rather than skipped.

The only visible difference is that `koto context list` shows three keys after
any retry instead of one or two, which is the cost this design already accepted
when it chose a sentinel value over an absence. Both diagnostics go to stdout.

Each file also gains a sentence stating that the value written to context
carries `"passed": true`, and `phase-4a-scrutiny.md`'s Retry Loop is rewritten
so its stated causality is true: the invalidation is what makes the gate fail.

**`skills/work-on/references/review-panel-orchestration.md`.** Gains the
retry-clearing contract. Its existing claim that panel states carry
`override_default` "so skipping is auditable via `koto overrides list`" is
corrected -- `built_in_default` already supplies that, and the blocks are being
removed.

**`skills/work-on/scripts/retry-clearing_test.sh`** and
**`.github/workflows/check-work-on-scripts.yml`** are the two new files.
**`scripts/check-bash-floor.sh`** is modified to register the `work-on` suite:
`SUITES`, `suite_scripts()`, and `suite_workflow()`. `suite_needs_shirabe()`
is left alone, since this harness drives koto only.

**`skills/work-on/koto-templates/work-on.mermaid.md`** is regenerated; the gate
edits produce a diff there, and only koto's reusable freshness workflow catches
a stale companion.

### The separating rule

Presence-only gating is sound when **the key cannot survive from one evaluation
of that gate into another, by any path**. The rule is about the key, not the
state: "sound unless the state lies on a cycle" is close but wrong, and "sound
when no transition targets the state" over-indicts every non-initial state.

Under it `work-on.md` splits cleanly: six gates sound -- all on the
pre-implementation spine, reached only from strictly upstream states and
evaluated once in a run's life -- and six unsound, the three this change
converts plus three recorded below.

### Data flow

```
scrutiny/review/qa_validation, blocking finding
  for KEY in the three panel keys          (unconditionally -- no exists guard)
    printf | koto context add   -> ctx/<key> = sentinel
    koto context get + compare  -> pass/fail on stdout, non-zero exit on mismatch
  koto next --with-data blocking_retry
        |
        v
implementation -> scrutiny -> review -> qa_validation
        |
        v
koto advance: gates evaluated on each re-entered phase
  context-matches(<key>, (?s)^\{.*"passed" *: *true.*\}\s*$)
        |
        +-- matches:false + passed            -> no transition; state holds,
        |                                        blocking_conditions names the gate
        +-- matches:true  + passed            -> next phase
        +-- any           + blocking_retry    -> implementation
        +-- any           + blocking_escalate -> done_blocked
```

## Implementation Approach

1. **Convert the three gates and their `when` keys** in `work-on.md`, and add
   the separating-rule comment. Confirm `koto template compile` still exits 0 at
   its one-warning baseline -- a `when` key naming a gate field koto does not
   produce fails here rather than in a live run.
2. **Add the retry block and the evidence-contract sentence** to the three phase
   files, and rewrite `phase-4a-scrutiny.md`'s Retry Loop.
3. **Correct `review-panel-orchestration.md`.**
4. **Write the test** and run it. The drift assertion goes first, ahead of every
   other case.
5. **Register the suite and add the workflow.**
6. **Regenerate the mermaid companion.**
7. **Update and run `/work-on`'s evals.**

**Steps 1 and 2 must land together, and the reason is the opposite of the
obvious one.** The tempting justification -- that converting the gates without
adding the clearing block would starve the phases on a value nothing writes --
is false, and was disproved by building the partial state and driving it through
real koto. The previous round's artifact already contains `"passed": true`, so
it satisfies the new pattern trivially: with step 1 alone, a `blocking_retry`
raised downstream leaves it untouched, and re-entering `scrutiny` and submitting
`passed` with no new write advances the state, `advanced: true`, no blocking
condition. Step 1 alone is not a loud block. It is a silent reproduction of the
exact staleness this design exists to remove, through a different gate type --
fail-open, not fail-closed.

That is a stronger reason to land them together, not a weaker one: a partial
deployment that blocks everybody gets noticed on the next run, and one that
quietly passes stale verdicts does not. Step 2 without step 1 is the prose-only
fix this design rejected, and it fails in the ordinary way.

### What the test must cover

The harness extracts the retry block from the shipped phase file and the gate
definitions from the shipped template at run time. Both blocks in each phase
file contain `koto context add`, so the extraction marker is `blocking_retry`,
not the precedent's `koto context add`.

- **Case 0, the drift assertion, first.** Extract `CLEARED=` from the phase file,
  drive the shipped template's gate with that value through real koto, assert
  the state holds. Baseline passes; mutating only the sentinel fails; mutating
  only the pattern fails.
- All three shipped heredoc payloads advance their phase.
- The sentinel holds each phase on `passed`, and koto names the gate.
- The traversal, three times: a retry raised in `qa_validation`, in `review`,
  and in `scrutiny`.
- The `scrutiny`-raised retry exits 0 with the two not-yet-written keys absent,
  and leaves all three holding the sentinel afterwards.
- **An unreadable key is caught, not skipped.** With one key file unreadable,
  the block exits non-zero and names that key -- the regression test for the
  guard the security review removed. A version of the block carrying
  `koto context exists ... || continue` passes every other case in this list and
  fails this one, which is the point of having it.
- Both failure exits stay reachable with the gate failing.
- A failed clear exits non-zero and prints on stdout with stderr discarded.
  **The injection is `chmod 0444` on the key file, not a lock on the ctx
  directory** -- the precedent locks the directory, which is right for a *new*
  key, but this design overwrites an *existing* one, where a directory lock lets
  the value land anyway.

## Security Considerations

**The sentinel and the pattern are literals in files this repository controls.**
Neither is author-supplied, and neither reaches a shell as an unquoted word: the
sentinel is single-quoted in the block and passed through `printf '%s'`, and the
pattern is a template literal koto compiles into a regex it evaluates itself.

**The key list is a fixed three-element literal**, not composed from run state,
so nothing interpolates a caller-controlled string into a `koto context add`
argument. `"$KEY"` is quoted at every use.

**The anchoring is the security-relevant detail**, inherited from the precedent
and re-verified here. `context-matches` calls `Regex::is_match`, a substring
test, so an unanchored pattern would accept any value containing `"passed":
true` anywhere -- including a cleared sentinel that quoted it. `^...$` is what
makes the gate a validator rather than a formality, and the drift assertion
fails if a later edit unanchors it.

**The context values are workflow evidence, not secrets.** The store gains no
new sensitivity: a sentinel recording that a round was superseded is less
sensitive than the verdict it replaces. No network access, no credential
handling, and no file written outside koto's own session directory.

**The failure mode is fail-closed, and the qualification matters.** With the
store unreadable the gate reports `matches: false`, the `passed` transition does
not match, and the run cannot advance past a phase carrying a stale verdict. The
previous behaviour -- advance on whatever was there -- was fail-open.

That claim is unconditional only because the clearing loop is unconditional. An
earlier draft guarded each key with `koto context exists ... || continue`, and
under that draft the claim was false: koto cannot distinguish an absent key from
an unreadable store (`handle_exists` returns a bare `bool`), so a transient
failure during the guard skipped the clear, and a store that recovered before
re-entry left the real prior verdict satisfying the gate. The guard is gone for
that reason, and the property that replaces it is that every key passes through
the read-back comparison, where a store failure produces a diagnostic and a
non-zero exit instead of a silent skip.

**One residual, named rather than silently accepted.** `koto overrides record`
works whether or not a gate declares `override_default`, so an operator can
advance past a failing gate deliberately. That is correct behaviour and it is
auditable through `koto overrides list`, but it means R3's guarantee is
structural *modulo a recorded override* rather than absolute.

## Consequences

**Positive.** A retry can no longer advance a review phase on the previous
round's verdict, and the refusal is structural: koto returns `advanced: false`
with a `blocking_conditions` entry naming the gate, `matches: false`,
`agent_actionable: true`. All three phases carry one contract whose invalidation
step is byte-identical below its first line, so the sameness R6 requires is
checkable by `diff`. The fix ships in the repo that owns the defect, against the
koto already installed.

**Negative.** The artifact namespace gains a sentinel value where there was
previously either a real artifact or nothing. `work-on.md` gains a second gate
type. And the gate now couples to the artifact's *shape*: an editor who rewrites
a heredoc breaks the gate. That failure is loud rather than silent, which is the
right direction, but it is a coupling the file does not have today.

**What a failed clear can and cannot do, since the two are easy to conflate.**
When the clearing step fails, the gate cannot help: the previous round's
artifact is a well-formed `"passed": true` value, so `context-matches` accepts
it exactly as it should. Reproduced -- with the store broken during the clear
and recovered before re-entry, the phase advances on the stale verdict whether
or not the block noticed. The entire difference between a caught failure and an
uncaught one is whether the agent was told: the unconditional loop exits
non-zero and names the key, and the guarded draft exited 0 in silence. That is
why R5's diagnostic is load-bearing rather than a convenience, and why the
guard's removal is a correctness fix rather than a tidy-up.

**The key list is a literal, repeated three times.** `for KEY in
scrutiny_results.json review_results.json qa_results.json` is hardcoded in each
phase file, and the three copies are correct only in relation to the template's
state graph. Adding a fourth panel phase, or removing one, means updating four
places in sync — and nothing catches a partial update, because a block looping
over a stale list still exits 0. The risk is bounded: changing the panel phases
already requires editing the template's states in the same commit, and the test
asserts the three blocks stay byte-identical to each other, so a partial update
across the three phase files fails. What no check covers is all three agreeing
with each other and disagreeing with the state graph.

**The residual risk, stated plainly.** The three artifacts are written by agents
following a heredoc. If an agent improvises a different shape the gate rejects a
legitimate passing artifact, and every exit from that state is then a failure
exit. `phase-4c-qa.md` makes this concrete today: it shows two JSON shapes, the
tester's return format with no `passed` key and the context-write heredoc with
one, and an agent conflating them writes a pass the gate refuses -- verified,
`matches: false`. This is why the evidence contract is written into all three
phase files as a named implementation step rather than left implicit.

**The cost that does not show up until later.** The chosen mechanism does not
extend to the latent instances it uncovered. `plan.md` and `summary.md` are
markdown written `--from-file`, so a pattern keyed on `"passed": true` cannot
reach them at all. Fixing them will need a freshness marker for two markdown
documents and a second sentinel convention -- a different technique, not an
extension of this one. Removal would have reached all six gates by appending
strings to a loop. That does not change the decision, since the release
dependency is paid now rather than later, but the follow-up is not a
copy-paste and should not be filed as though it were.

**Three more latent instances of this defect, recorded rather than fixed.**
This PRD scopes to the three retry-bearing review phases, and widening a PR
because review found adjacent instances is how a reviewable change stops being
one. The same discipline filed *this* issue out of `/execute`'s sweep.

- `plan_artifact` (`work-on.md:387`) is satisfied by the previous round's
  `plan.md` when `implementation` returns on `scope_expanded_retry` -- a state
  whose purpose on that edge is to rewrite the plan, gated on the plan it is
  meant to replace.
- `summary_exists` (`:633`) is satisfied by the previous round's summary when
  `finalization` submits `issues_found` and the run returns through
  `verification`.
- `summary_exists` on `deferral_approval` (`:672`) is live for a subtler reason,
  and it is recorded because two reviewers reached opposite answers on it.
  Exactly one transition targets `deferral_approval` and nothing routes back
  into it, so the state is entered once -- which is why a state-based test calls
  it sound. But `finalization` *is* on a cycle, so a run can write `summary.md`,
  go back to `implementation` for a fix, return through `verification` to
  `finalization`, and enter `deferral_approval` for the first and only time with
  a `summary.md` that predates the fix. The gate passes on a stale key on a
  first entry. This is the case that forced the separating rule to be about the
  key rather than the state.

**A finding outside this defect, recorded for the same reason.**
`context_assignments:` is not a koto feature: the `Transition` struct carries
`target` and `when` only, the block is silently dropped at compile time, and the
context store is empty after a transition carrying one fires. Every
`context_assignments: failure_reason:` block in `work-on.md` is therefore a
no-op, and `review-panel-orchestration.md` and `/work-on`'s eval 14 both
document the behaviour as real. Wider than this work and left for its own issue.
