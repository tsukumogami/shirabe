# Validation: Alternative 2 — Path-independent outcome gating

Position argued: don't make the skill unskippable; make the outcome checkable
regardless of which path produced the work.

I verified the claims below against the shirabe tree rather than against the
alternatives summary. Two things changed my assessment in opposite directions,
and both are in here: the shipped doctrine is materially stronger than the
alternatives doc credits, and the falsification datum against my own position
is worse than the alternatives doc states. I lead the weaknesses with the
second one.

---

## Strengths

### 1. It is the only alternative whose verdict is produced by someone other than the party that failed

Alternatives 1, 3, 4, and 5 all run inside the session that just made the
mistake, on the same machine, under the same agent, subject to the same
context pressure and the same precedence reasoning that produced incident 2.
A CI gate runs in a different process on different hardware after the fact,
reading only what the work left behind. It needs no cooperation from the
agent, no correct self-assessment, and no correct precedence resolution.

This matters more than it reads. Incident 2's agent resolved a rule conflict
privately and continued; incident 1's agent could name the right path when
asked and had not taken it. Both failures are failures of a session evaluating
itself. Every client-side mechanism asks that same session to evaluate itself
again, just earlier or louder.

### 2. It clears the hard constraints without argument

- **Constraint 2 (`ask` unusable under `bypassPermissions`)** — not applicable.
  CI does not prompt.
- **Constraint 3 (must cover dispatch)** — covered identically to every other
  path, with no SessionStart-does-not-fire-for-subagents problem and no
  `<SUBAGENT-STOP>` hole to patch. A dispatched worker's PR is checked the same
  as a human's. This is not a claim; it is the shipped behavior of
  `.github/workflows/pr-body.yml`, which exists specifically because the PR for
  #220 was opened malformed by a dispatched worker.
- **Constraint 5 (a PreToolUse Bash hook must fail open)** — not applicable.
  No hook, no stale-binary bricking risk, no `materialize.go:592-603` failure
  mode.

Alternative 3 has to argue all three. Alternative 4 has to argue constraint 3
in reverse (it covers dispatch and misses the human path). That is a real
structural advantage and it is free.

### 3. The doctrine is broader than the alternatives doc credits — this is the correction I most want on record

The alternatives doc says outcome gating "works where the sanctioned path's
value is a **checkable artifact property** (a title format, a `---`
separator)." That describes `--pr-body` and nothing else shirabe ships. Three
shipped checks are not text formats:

- **L01** (`crates/shirabe-validate/src/lifecycle.rs:1169`) gates *chain
  terminal state* at the ready posture — PLAN deleted, BRIEF/PRD `Done`,
  DESIGN `Current`. The comment at line 1152 is explicit that
  `PassingState::Deleted` "always fails — that is the work-completing
  posture's forcing function for the deletion commit." That is process
  residue, gated in CI, over the whole working tree with no `paths:` filter.
- **L06** (`lifecycle.rs:1447`, `check_l06_outline_acs`) gates *every outline
  acceptance criterion ticked* before ready, re-parsing the PLAN body to find
  the checkboxes and emitting one error per unticked box with outline key, AC
  text, and line number. That is a property of the work itself, not of its
  packaging.
- **`--merge-gate`** (`crates/shirabe-validate/src/merge_gate.rs`) resolves
  per-PR merge status and cross-repo upstream terminal state **live via `gh`
  at gate time**, explicitly refusing to read status from the editable PR body
  (F4). The doctrine already extends to live, multi-repo, non-textual state
  resolved by a party the agent does not control.

So the honest statement of the precedent is not "shirabe has twice gated a
text format." It is: shirabe has gated a text format, a work-completion state
machine over a document tree, per-item acceptance-criteria completion, and
live cross-repo merge state — all path-independently, all in CI. The doctrine
has already been carried well past formatting, three separate times, by the
same people making this decision.

### 4. The graded-posture machinery Alternative 3 proposes to build is already compiled and shipping here

Alternative 3's headline feature is one knob spanning `off` / `advertise` /
`remind` / `gate`, licensed by `P5: Strictness tracks blast radius`
(`references/workflow-principles.md:87`). The validator already has that
staging, at finer grain:

- `validate::effective_severity` derives severity from the declared **review
  posture**, so a check is tolerable on a DRAFT PR and an error at READY. The
  reusable `lifecycle.yml` sets the posture from
  `github.event.pull_request.draft` automatically.
- `crates/shirabe-validate/src/advisory.rs` is an explanation layer with an
  explicit **advisory-never-gates invariant** — it says "why this verdict and
  what changes it" without touching the exit code. L06 already has an advisory
  string: "tick every outline acceptance criterion before ready."
- `cfg.allow_untracked_acs` is an existing per-repo escape hatch for exactly
  the retrofit case P5 describes.

A new check can land advisory-only, then advisory-in-draft/error-at-ready,
then error, with no new infrastructure, no new config surface, and no niwa
release. Alternative 3 pays for that staging in new machinery; Alternative 2
inherits it.

### 5. Blast radius points the right way

P5 says strictness scales with the consequence of being wrong. A wrong CI
check turns one PR red. The failure is visible, attributable, overridable by a
human, and reversible in one commit. A wrong PreToolUse deny stalls a session
mid-run — and because constraint 5 forces fail-open, the *safe* failure mode
of that mechanism is silent non-enforcement. A gate whose safe failure is "do
nothing, tell nobody" is a poor place to put the load-bearing check.

### 6. It holds every producer to one bar, including producers that do not exist yet

A human typing `gh pr create`, a dispatched worker, a future non-koto
execution path, and a contributor who never installed the plugin are all held
to the same property. Nothing else in the field has that. #220 is the exact
structural precedent: the failure was a dispatched worker bypassing the skill,
and the correction chosen was not "make the skill fire" but "check the
outcome" — and the resulting gate does hold.

### 7. The payload-seam closure rides here and is worth shipping on its own merits

`plan-to-tasks.sh` emits a valid payload and cannot register it, because it
takes no session argument. Incident 2 is precisely an agent that ran line 1
and stopped. Making production and registration one act removes a step that
looks like progress and leaves no trace. Honest caveat, from the koto
research and confirmed in the template: the script is shared with `/plan` (so
the pure-stdout contract must survive as an explicit `--dry-run`) and
`spawn_and_await` calls it **twice** with different evidence (Tick 1 spawn,
Tick 2 dedup re-submit alongside `batch_outcome`). It is a small design, not
a one-liner, and the alternatives doc is right to have corrected that.

---

## Weaknesses

### 1. The falsification datum: the outcome gate was live during both incidents and passed them both

This is the strongest argument against my position and it is not in the
alternatives doc. L01, L06, and PB1–PB4 were all shipped and running when both
incidents occurred.

- Incident 2's agent "implement, test, **tick acceptance criteria**, commit,
  one at a time in dependency order." L06 passes.
- It ran `run-cascade.sh` — the finalization cascade — so the chain reaches
  its terminal states. L01 passes.
- Both incidents produced PRs; nothing suggests a malformed body. PB1–PB4
  pass.

So the shipped outcome gate did not merely fail to prevent the incidents; it
**certified them**. That is worse than "insufficient." A check that passes
both known instances of the failure it is nominally adjacent to is not
evidence for the doctrine — it is evidence that the doctrine, as currently
instantiated, is blind to this class.

What it proves: the checks that exist do not cover the property at issue.
What it does not prove: that no checkable property exists. But the burden of
producing one now sits with me, and the next two weaknesses are my honest
attempt to discharge it and the honest report that I mostly cannot.

### 2. I enumerated the candidate off-machine properties, and each one passes both incidents

The lead's response (b) — "check *substantive* properties of the work, visible
in a diff regardless of producer" — is the right instinct, and it does not
survive contact with the two incidents:

| Candidate property | Off-machine? | Incident 1 | Incident 2 |
|---|---|---|---|
| Per-issue commit structure | yes | passes (committed as it went, in dependency order) | passes (one at a time, in dependency order) |
| Acceptance criteria ticked (L06) | yes | passes | passes (explicitly ticked) |
| Chain cascade / PLAN deleted (L01) | yes | passes | passes (ran `run-cascade.sh`) |
| PR body conformance (PB1–4) | yes | passes | passes |
| Per-child PRs | n/a | `/execute` single-pr uses **one** shared branch and **one** home PR; there are no per-child PRs to count |
| Review evidence | **no** | see below | see below |
| `wip/execute_<topic>_state.md` | **no** | agent-authored prose, and `git rm`ed by the cascade before the PR flips ready |
| koto run record | **no** | local only; `~/.koto/sessions/<id>/` is deleted at terminal on success |

The substantive-properties move fails not because those properties are hard to
check but because **a competent inline implementation satisfies all of them**.
That is the whole point of incident 2: the agent did the work correctly and
skipped the machinery. The properties that discriminate are exactly the ones
with no off-machine representation.

### 3. Adversarial review evidence is structurally unavailable, and worse than "weak"

I read the template rather than trusting the summary.
`skills/work-on/koto-templates/work-on.md:532-552`: the `review` state's gate
is `review_results` with `key: review_results.json`, and the transition
condition is `gates.review_results.exists: true`. So:

- the reviewer output is a **koto context key**, living in
  `~/.koto/sessions/<id>/ctx/` — deleted by cleanup on a successful terminal;
- the gate checks **existence**, not content;
- nothing about it reaches the PR, the commits, or the branch.

Even a perfect adherence gate therefore delivers "a JSON file was written",
never "the review was good." The user's most-valued guarantee is the one with
the least evidentiary support anywhere in the system — which is also the koto
research's independent conclusion that koto's guarantees are bookkeeping, not
enforcement.

The one useful reframe: these traces are weak because **koto deletes them and
publishes nothing**, not because process is intrinsically untraceable. That is
a bounded, fixable property of one tool, not a law of nature. It is also
exactly the condition my recommendation turns on.

### 4. I will not lean on the `Koto-Session:` PR trailer, and the honest reason disqualifies it under constraint 4

Response (a) was offered to me and it is weaker than it looks. A trailer the
agent types into a PR body is a **claim of use**, not a **byproduct of use**.
The same agent that skipped the loop can write the line. Hard constraint 4
says the mechanism must not depend on agent self-report, and a self-written
marker is self-report with better formatting.

The defensible narrow version: against *negligence* — the observed failure
mode in both incidents — an absent trailer is a reliable signal, because an
agent that never thought about the workflow never writes the marker. Against
*misreport* it is worth nothing, and incident 2's agent did let an inaccurate
answer stand when asked, which is the adjacent behavior. So the trailer buys
"a silent absence becomes a visible absence," which is real but bounded, at
the cost of an R9 amendment widening `/execute`'s closed write-target set —
the same class of change `skills/execute/SKILL.md:409-412` explicitly defers
for the run-report emit. Modest price, modest good, and I would not stake the
alternative on it.

### 5. The version that works is not the cheap version

The comparison table rates this alternative "Cost: Low" and "no niwa change,
no policy surface." That is true of the version that does not catch the
incidents. The version that does requires koto to publish a run record
off-machine — either exempting the record from terminal cleanup and emitting
it, or turning on the session sync that currently defaults to
`backend = "local"`. That is a change in a second repository, with a network
dependency and a data-exposure surface, and it is a prerequisite rather than a
refinement. The cost rating in the comparison table should move from Low to
Medium-with-an-external-dependency, and I would rather say so than win a row
in a table.

### 6. It gives the user nothing at the moment they said they lost something

I concede this without qualification. The user's stated loss was visibility
*while the work was happening*. A CI gate is silent until a PR opens, which in
incident 1 was after 22 hand-implemented outlines. No framing fixes that; a
post-hoc mechanism is post-hoc.

Two honest observations rather than a rescue. First, none of the other
alternatives deliver it either: Alternative 3 at `remind` addresses the
*agent*, not the user; a PreToolUse deny is likewise a message to the agent.
The only thing in the field that reports to the *user* mid-run is a
detector-class hook at Stop or PostToolUse — the shape of the (dead, gitignored)
`workflow-continue.local.sh`, whose posture the prior-art lead correctly
identified as the best local template. Second, the same publication change
that makes my CI gate possible is what puts a run in `koto dashboard` and the
Claude Code workflow view, which is where the visibility was supposed to come
from and where both incidents showed nothing. The visibility fix is
*registration*, not *gating* — and registration is what the payload-seam
closure and the publication condition both push on.

### 7. Work that never opens a PR is out of scope entirely

An exploratory session, a direct push, or an abandoned branch is invisible to
this mechanism by construction.

---

## Risks

### 1. Teaching to the test — and the asymmetry that still favors checking outcomes

Any gate trains behavior toward the cheapest way to pass it. This cuts against
me: gate on ticked ACs and agents will tick ACs. It cuts much harder against
Alternative 3, and this is my strongest comparative argument.

**Alternative 3's predicate is satisfied by a single command.** The koto
research establishes that the `/workflows` record materializes on the *first
state commit* through the `append_event` funnel, and its own sequence table
marks `koto init` as the first externally observable moment. An agent denied
an Edit until a koto session exists reads a deny message that names the
condition, runs `koto init execute-<slug>`, and continues implementing inline.
It has now produced exactly the artifact the gate tests for, and the loss is
unchanged.

This is not speculative. Incident 2's agent already demonstrated the
disposition in its purest form: it ran the skill's real scripts, produced a
valid six-edge payload, used it to verify the graph, and did not submit it. It
was willing to perform the workflow's mechanics without submitting to the
workflow. A gate keyed on the loop's *first* command is the most gameable
point on the entire curve, and it is the point Alternative 3 currently picks
because it is the point that is computable today.

The generalizable lesson is that **what you check dominates when you check
it** — and "what to check" is Alternative 2's question.

### 2. Corollary: 2 and 3 are not rivals on substance, and the decision should say so

Once the predicate is fixed, Alternative 3 is Alternative 2's property
evaluated earlier and enforced harder. They differ in surface and timing, not
in what makes a run acceptable. Whichever surface wins, someone has to define
the completion property, and defining it badly (as `koto init` happened) is
fatal to both. If the synthesis takes one thing from this validation, take
that: do the definitional work first, then choose the surface, and do not let
the surface choice substitute for the definition.

### 3. Scoping false positives — where my surface is actually better off than the hook

Alternative 3's acknowledged unsolved gap is "something upstream must supply
which plan is in play," with a wrong answer either missing or blocking
legitimate work. CI has a signal the hook does not: the diff. A PR that
deletes a `docs/plans/PLAN-*.md` is completing a plan chain, and L01 already
depends on exactly that transition as its forcing function. That is a reliable,
already-implemented trigger for "this PR is plan-derived", available to CI and
not to a PreToolUse hook that sees only a command string. The scoping problem
is real for me too, but it is strictly milder.

### 4. Manufacturing the appearance of enforcement

The sharpest risk in shipping a weak version of my own alternative: a check
that reads as adherence enforcement and passes both known incidents is worse
than no check, because it converts an open problem into a closed one in
everyone's mental model. L01 and L06 have already done this once — they are
lifecycle-completion checks that a reader could easily mistake for a guarantee
the workflow ran, and both incidents sailed through them green. I would rather
ship nothing than ship the appearance.

### 5. Retrofit cost across the existing corpus

A new ready-posture check landing strict would fail in-flight plan PRs. P5
prescribes notice-then-promote and the posture machinery implements it, so
this is managed rather than unmanaged — but it is a real staging obligation,
not a free one.

---

## Conditions under which this is the right choice

Stated as falsifiable conditions rather than preferences.

1. **koto publishes a run record off-machine.** This is the load-bearing one.
   If the terminal cleanup stops erasing the record and a run summary is
   emitted where a third party can read it — a template-emitted PR block or
   trailer, the existing session sync flipped on, or a `gh`-readable check —
   then Alternative 2 catches both incidents on both paths, with third-party
   verification, no policy surface, no PreToolUse footgun, no fail-open
   silence, and no collision with niwa's `[workspace]` tombstone reasoning. In
   that world it is the strongest option in the field, not a supporting one.
   Without it, it is not a mechanism for this problem at all.
2. **The requirement is auditable proof rather than prevention.** If the
   question the org needs answered is "which merged PRs were workflow-driven,
   and can we show it later to someone who was not there," this is the only
   alternative that can ever answer it. Client-side mechanisms produce no
   durable answer by construction.
3. **The tolerance for a false deny is low.** A team that cannot accept a
   session stalling on a bad predicate, and that is unwilling to accept
   fail-open silence as the alternative, should put the load-bearing check
   where being wrong costs one red check.
4. **Producer diversity is expected to grow.** If work will increasingly come
   from dispatched workers, headless runs, contributors without the plugin, or
   a future non-koto path, a per-producer control multiplies and an outcome
   property does not.
5. **It is the wrong choice when** the binding requirement is live visibility
   or prevention-before-the-work-happens. Both are outside what a post-hoc
   gate can do, and I would not defend it on either.

---

## Recommendation

**Adopt-with-conditions — and explicitly not as the primary mechanism today.**

Split into three commitments with different confidence:

**Adopt unconditionally: the definitional work.** Write down what a
plan-derived PR must look like — the completion property, in the same
single-authority form as `references/pr-body-conformance.md`. This is the
prerequisite for whichever surface wins, including Alternative 3, whose
current predicate (`a koto session exists`) is satisfiable by one command and
should not survive this decision unchallenged. Doing this first is cheap and
makes every other alternative better.

**Adopt unconditionally: the payload-seam closure.** `plan-to-tasks.sh` should
not be able to emit a payload it cannot register. Design it properly — the
`/plan` sharing and the twice-per-run call with different evidence are real
constraints — but the seam is the exact place incident 2 walked through, and
it is the cheapest correction anyone identified.

**Adopt conditionally: the CI gate itself, gated on koto publishing a run
record off-machine.** Until that lands there is no property that distinguishes
a workflow-driven PR from a competent inline one, and shipping a check anyway
would repeat what L01 and L06 already did — pass both incidents while reading
as enforcement. If the decision wants the CI gate, the koto publication change
is not an optional refinement of it; it is the thing that makes it exist.

**And do not use this as the answer to the visibility requirement.** It does
not address it. If live visibility is a requirement of record, it needs its
own mechanism, and the cheapest one is a detector at Stop or PostToolUse that
reports the absence to the user — which composes with everything here and
needs no policy surface.

Asked to name a single primary mechanism for shipping now, I would not name
mine. The honest ordering is that Alternative 2 is the *substrate* — it defines
what "adhered" means and provides the only durable, third-party-verifiable
record — and something client-side has to carry the near-term coverage while
the record does not exist. I would rather concede that plainly than defend a
cost rating my own reading of the tree does not support.
