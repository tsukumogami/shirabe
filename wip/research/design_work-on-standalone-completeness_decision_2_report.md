# Decision 2: Anchor detection and the no-chain path

## Context

The PRD defines *anchor* precisely: "the PLAN that sequences the issue being
worked... the only document the cascade can be entered from: the cascade
script takes a plan-shaped path as its sole positional argument"
(`docs/prds/PRD-work-on-standalone-completeness.md:159-165`). R2 forbids
invoking `run-cascade.sh` and letting it report a skip, because the script has
no no-document mode (`PRD:170-174`); R3 requires a run with no anchor to
complete with zero cascade-related output (`PRD:175-177`); R4 pins the
existing behaviour of an anchor that resolves to no upstream chain
(`PRD:178-182`).

`run-cascade.sh` confirms the constraint directly. It takes a mandatory
positional `<plan-doc-path>` and, given nothing, fails hard rather than
skipping cleanly:

```
skills/execute/scripts/run-cascade.sh:697-707  # usage() exits 1, no JSON
```

and `validate_upstream_path` (`run-cascade.sh:97-130`) additionally requires
the path to resolve inside the repo root, be a regular non-symlink file, and
be tracked by git — so whatever a caller hands it must be a real, on-disk,
committed PLAN, not a placeholder. The two existing "no-op" shapes both
presuppose a real path was given: a clean pre-probe pass
(`run-cascade.sh:807-810`, `cascade_status: skipped`, "chain at ready-posture
passing state") and a PLAN with no upstream field
(`run-cascade.sh:1104-1123`, `1130-1153`) — the second is R4's case, discussed
below. Neither is reachable without a path already in hand. This is also the
conclusion `wip/research/explore_work-on-standalone-completeness_r2_lead-multipr-cadence.md`
reached independently (Finding 4): "the *caller* — not `run-cascade.sh` — must
decide whether a PLAN doc... exists at all before invoking the script."

**Where the anchor is already known vs. not.** `work-on.md` declares
`PLAN_DOC` as an optional template variable
(`skills/work-on/koto-templates/work-on.md:34-36`), but only the plan-backed
path uses it — `plan_context_injection`'s directive reads `{{PLAN_DOC}}`
directly for the `issue_source: plan_outline` case
(`work-on.md:955-957`). `plan-to-tasks.sh` never writes a `PLAN_DOC` key into
a per-task `vars` object (`skills/plan/scripts/plan-to-tasks.sh:373,721,728`
list only `ISSUE_SOURCE`, `ISSUE_NUMBER`, `ARTIFACT_PREFIX`, `ISSUE_TYPE`), so
this only works because koto resolves an unset child variable against the
declared value on the **parent** session — `execute.md` declares `PLAN_DOC`
as `required: true` (`execute.md:11-13`) and every `/execute` child therefore
inherits it automatically, with no per-task plumbing. So for any run
materialized by `/execute` — `mode: plan_backed`, whether `issue_source:
github` or `plan_outline` — the anchor is already resolved before the child
takes its first tick.

The gap is the standalone case the PRD is about: `mode: issue_backed` with
`ISSUE_NUMBER` set and **nothing else** — no `PLAN_DOC`, because nobody
declared or passed one. `mode: free_form` has no GitHub issue number at all,
so it can never appear in a PLAN's Implementation Issues table
(`skills/plan/references/plan-format.md:163-186`, which keys that table on
`#N` GitHub links) — a free-form run has no anchor by construction, and the
detection question for it is trivial. The real question is: given only
`ISSUE_NUMBER`, does the issue sit under some `docs/plans/PLAN-*.md` still on
disk, and how does the run find out without a human or an orchestrator
telling it.

## Options considered

### Option 1: Read a value the caller passes in

`work-on.md` already has the variable — `PLAN_DOC` — and a human or a future
orchestrator could pass it at `koto init` time, exactly as `/execute` does for
its own children. This is free to build: nothing changes except the entry
prose acknowledging the variable for `issue_backed` mode too.

**Where it works.** Any run whose caller *knows* the anchor and says so: a
plan-backed child (already true today), and — if R14/R15's multi-pr migration
someday lets `/execute` dispatch multi-pr children directly — those children
too, since they inherit `PLAN_DOC` from the same parent session exactly like
single-pr children do.

**Where it fails.** The motivating scenario, exactly. The PRD's own framing
is that three dispatched worker sessions ran `/work-on` standalone against
real GitHub issues, with nobody supplying anything beyond the issue number
(`PRD:20-26`, `motivating_context`). A human running `/work-on 361` from a
terminal has no reason to know, let alone type, the path of the PLAN that
happens to sequence issue 361 — that is precisely the fact the run is
supposed to establish for itself. As a sole mechanism this option is a pure
false-negative generator for the case R1/R2/R3 exist to fix: every anchor
that exists but wasn't told to the run is missed, and the run falls through
to R3's no-anchor path even though a real chain sits waiting. It costs
nothing per run (no extra command), which is its only virtue; it composes
with every other option as a short-circuit (if the caller *did* pass one,
skip the search) but cannot stand alone.

### Option 2: Search `docs/plans/` for a PLAN naming this issue

The codebase already does the structurally identical thing for a different
document type. `skills/work-on/references/scripts/extract-context.sh:145-165`
(`find_design_doc()`) searches `docs -name "DESIGN-*.md"` and greps each for
`#${issue}`, collecting every match and tie-breaking on which candidate also
carries an Implementation Issues table (`extract-context.sh:162-...`). It is
explicitly best-effort — a miss degrades to "using issue body only" and marks
`STATUS="degraded"` (`extract-context.sh:288-289`) — because it feeds
*context*, not a control-flow decision that can corrupt an unrelated
document's lifecycle.

The direct analogue for PLAN: a PLAN stays in `docs/plans/` through every
lifecycle state up to and including `Active`
(`skills/plan/references/plan-format.md`, Lifecycle section: "The PLAN stays
in `docs/plans/` through every state") and is deleted only as part of the
finalization commit `run-cascade.sh` itself produces
(`run-cascade.sh` step 1 comment, "finalize-chain... reports the PLAN as a
delete node"). So at the moment a standalone run is deciding whether to
cascade, any PLAN that actually sequences the issue is still sitting on disk,
un-mutated, with the issue's number in its `## Implementation Issues` table
(`plan-format.md:161-186`) — provided the PLAN is issue-carrying
(`tracking_level: issues` or `issues-and-milestone`; outline-shaped PLANs
never materialize a real GitHub issue number in the first place, so an
`issue_backed` run can only exist for an issue-carrying PLAN).

**Cost.** A single grep over a directory this repository keeps deliberately
small (`docs/plans/` holds one file today: `docs/plans/PLAN-work-on-friction-fixes.md`).
No network call, no dependency on `gh` rate limits, nothing that can go stale
between context-injection time and cascade-decision time because it reads the
same working tree the run is already sitting in.

**A concrete false-positive this repository's own PLAN already exhibits.**
`docs/plans/PLAN-work-on-friction-fixes.md:78` and `:86`:

```
| [#79: docs(design): extract-context DESIGN doc resolution...](https://github.com/tsukumogami/shirabe/issues/79) | None | simple |
...
| [#84: docs(design): per-branch context findings cache...](.../issues/84) | [#79](.../issues/79) | simple |
```

A bare `grep "#79"` over this file matches **twice**: once in issue 79's own
Issue-column row (correct — this PLAN is #79's anchor), and once in issue
84's Dependencies column, which links to #79 as a *blocking dependency*, not
as the row's own subject. A naive "does this PLAN mention `#N` anywhere"
search would (wrongly, but harmlessly in this specific case since both rows
belong to the same PLAN) treat #79 as anchored by a match that isn't really
about #79 being sequenced there — and in a repository running two PLANs
concurrently, the false hit could land in a **different** PLAN than the one
that actually owns the issue, which is the dangerous case: `run-cascade.sh`
would be invoked with a real, git-tracked, structurally valid PLAN path that
is nonetheless the *wrong* document, and it would walk and potentially
transition that PLAN's own upstream chain instead of doing nothing. This is
not a hypothetical: `extract-context.sh:207`'s own regex, `grep "| \[#${issue}\]"`,
is anchored on the leading `| [#N` prefix specifically to stay inside the
Issue column and avoid this kind of cross-column collision.
`skills/execute/koto-templates/execute.md:81-84` states the general
principle this repository already applies elsewhere: "the pattern is
anchored at BOTH ends... What makes this a validator instead of a
formality." An anchor-detection regex for PLAN tables needs the same
discipline — anchored at line start (`^\|\s*\[#${N}:`), matching only the
Issue column's own cell, never a mid-line Dependencies reference.

**A second correctness risk, avoidable by not re-inventing a parser.**
`docs/decisions/DESIGN-issue-outlines-one-parser.md` records that this
exact table was once read by three independent implementations (a Rust
reader, a bash reader, and a third) that "disagree in eight ways," including
one where "a PLAN with an unrecognized dependency reference validates at
exit 0 and then extracts to a task graph with no edges at all." The fix
consolidated the parse into `shirabe-validate`, exposed to shell callers
through a single subcommand, `shirabe plan outlines`
(`skills/plan/scripts/plan-to-tasks.sh:420-419`, `process_single_pr()`
comment: "This function used to carry its own line-by-line re-implementation
of that parse; the two drifted in eight ways... None of it reads the
document" — the parse itself is delegated, deliberately, to avoid exactly
this class of bug). A hand-rolled grep for anchor detection would be a fourth
independent reader of PLAN-table syntax. The safer construction is a small
reverse-lookup surfaced through the same engine (e.g., a `shirabe plan
find-issue <N>` walking the canonical Implementation Issues table the
validator already parses) rather than a bespoke regex script — this is a
detail for whichever design hop settles where the shared cascade machinery
lives (Decision 1), not a blocker to choosing this option's *shape*.

**Failure direction.** False negative is the default failure mode: a PLAN
that is Draft (issues not yet materialized — but then there'd be no
`ISSUE_NUMBER` for this issue anyway), a PLAN whose table uses the legacy
four-column shape in a way an under-built matcher misses, or a table row
whose markdown got hand-edited into a shape the matcher doesn't recognize,
all read as "no anchor" rather than crashing or guessing. Given the anchored
regex above, a false positive would require a *different* PLAN's table to
carry this exact issue number as a **subject** row (not merely a dependency
reference) — something the corpus doesn't produce today (each issue is
created from exactly one PLAN) and that `shirabe validate`'s own FC-series
checks would likely already object to as duplicate work-item ownership if it
ever happened.

### Option 3: A reference embedded in the issue body, read via `gh`

The repository already has a working precedent for an issue-body reference
field — just not to a PLAN. `Design: \`<path>\`` is an existing, real field:
`skills/work-on/references/phases/phase-6-design-diagram-update.md:10-17`
("Only if the issue body contains `Design: \`<path>\``... Look for `Design:
\`<path>\`` in the issue body") and `phase-6-pr.md:11-14` both key off it. It
is read via `gh issue view $N --json body` (already fetched today in
`extract-context.sh:319-320` for the degraded no-design-doc path), so a
`Plan: \`<path>\`` field of the identical shape is a small, mechanically
obvious extension — cheap per-run (a body already fetched during
`context_injection` could carry the reference forward, no extra API call
needed if reused).

**Why it does not fit this feature.** Two separate problems. First, it does
not point at the right document — `Design:` names a DESIGN, and DESIGN is
explicitly excluded from being an anchor by the PRD's own definition:
"'Anchor' never refers to a BRIEF, PRD or DESIGN — those are reached
*through* the anchor, by the cascade's own walk, and never entered directly"
(`PRD:163-165`). A DESIGN's own frontmatter records its *upstream* (the PRD
above it), never a *downstream* PLAN — there is nothing to read on the
DESIGN side that names the PLAN that sequences a given issue, so introducing
a `Plan:` field would be new content, not a repurposing of `Design:`.
Second, and more decisively: it only helps issues created *after* the field
is added. The three field-observed failures this PRD exists to fix
(`PRD:66-69`, three dispatched sessions against real, already-open issues)
are issues that already exist, with bodies already written, by
`create-issue.sh` (`skills/plan/scripts/create-issue.sh:150-260`), which has
no such field today. A detection mechanism that only covers issues minted
after this feature ships does not fix the motivating case — it would need a
one-time backfill across every open issue tracked by every currently-Active
PLAN, which is a second, unscoped body of work the PRD's Out-of-Scope section
would reasonably reject ("the naming fossils left by the earlier split... not
this feature's purpose", `PRD:471-472`, is the same shape of scope
discipline). This option is sound in principle and cheap going forward, but
it cannot be the *sole* mechanism without abandoning every issue that exists
today, which is precisely the population that surfaced the defect.

### Option 4: Carry it in koto context from an earlier state

This is really a timing variant of Option 2 or 3 rather than an independent
detection mechanism: instead of searching at the cascade-decision point
(after `ci_monitor`, wherever the design hop places the new state),
perform the same search during `context_injection` — which already runs
`extract-context.sh` and already fetches the issue body
(`extract-context.sh:319-320`) — and stash the result as a koto context key
(e.g. an `anchor.json` written alongside `context.md`), read back later by
the cascade-decision state's gate.

**Argument for.** Reuses a `gh`/filesystem read that's happening anyway, so
if Option 3's body-field is ever added this is where it would naturally be
captured. It also gives a single point of truth read once, rather than one
gate command re-implementing the search logic wherever it's invoked.

**Argument against.** It caches a fact — "does an anchor exist" — at the
*start* of a run and trusts it through implementation, three review panels,
verification, PR creation, and CI monitoring, all of which can take
substantial wall-clock time and, in principle, cross a window where a
concurrent `/execute` run on the same PLAN could finalize and delete it. The
existing `staleness_check` state exists for exactly this class of problem —
codebase facts captured early can go stale by the time a run reaches its
later states (`work-on.md:990-1008`) — so caching the anchor early
reintroduces a smaller version of the same risk the template already treats
as worth a dedicated gate elsewhere in this same file. A fresh read
immediately before the cascade decision (Option 2's search run as a gate at
that point, not earlier) is safer for the same reason `staleness_check` is
gated late rather than trusted from setup: the world can move under a
long-running implementation. Where Option 4 is worth keeping is narrower than
"cache the answer": if a body-derived signal (Option 3, once it exists for
new issues) is captured once, re-reading `gh issue view` a second time buys
nothing since the body doesn't change mid-run — but that's an optimization
on top of Option 3, not a replacement for a late, live filesystem check.

### Composing with the child-signal (Decision 4/R11/R12)

Anchor detection is orthogonal to, and must run *after*, whatever
discriminator Decision 4 settles for suppressing child self-finalization. A
plan-backed child (single-pr, materialized by `/execute`) already has
`PLAN_DOC` set — Option 1 trivially "succeeds" for it — but R11 forbids it
from cascading regardless of whether an anchor is known
(`PRD:235-236`, "A child run dispatched by the plan entry point SHALL NOT
pull the document chain to its terminal state. Finalization is the plan's,
once."). If a future multi-pr child (R14) also inherits `PLAN_DOC` the same
way, the same suppression must still fire for it, per R12
(`PRD:238-241`). So the state ordering that matters is: check "is this a
child that must not self-finalize" first (cheap, already-known variables or
whatever R19's root/child mechanism provides); only for a run that clears
that check does "does an anchor exist" (this decision) need to run at all.
Getting the order backwards — checking for an anchor first — would waste the
search on every plan-backed child, since the answer is thrown away by R11's
suppression immediately afterward.

## The no-output requirement

R3 requires that a run with no anchor "complete normally and SHALL NOT emit
cascade-related output" (`PRD:175-177`). Mechanically, this repository has an
established pattern for exactly this shape — a `default_action`-run command
gated with zero-evidence transitions on the passing branch — and the
underlying koto engine confirms *why* it works down to the response payload.

**The template-level pattern.** `references/default-action-conversion.md`
documents the contract precisely: "On the passing path the state advances
with no evidence and the agent never sees it" (line ~106), illustrated by
`pr_precheck` (`work-on.md:695-750`) — "Reading the branch this work is on...
you only see this state if it could not" (`work-on.md:1166`) — and
`settled_branch_record` (`execute.md:515-537`) — "On the passing path the run
advances to `worktree_discipline_check` with no evidence and you never read
this" (`execute.md:531`). The shape required is: every transition out of the
state names the gate (never an evidence-only fallback that could fire
independently), and the passing-path transition requires no `accepts` field
at all — an agent driving the run literally has nothing to submit and
receives no prompt asking it to reason about the state's subject matter.

**Confirmed from the engine itself, not just template convention.**
`wip/research/explore_work-on-standalone-completeness_r2_lead-koto-materialization.md`
traced this into koto's Rust source: what an agent receives per tick is
exactly two template-sourced fields, `directive` and `details`, split from
the state's markdown body at the `<!-- details -->` marker
(`extract_directives`, `src/template/compile.rs:632-672`), and koto's
transition resolver (`resolve_transition`, `src/engine/advance.rs:1228-1310`)
treats a `gates.<name>.exit_code` condition as ordinary evidence — a state
whose only conditioned transitions are gate-keyed advances the run without
ever constructing a response that shows the agent that state's directive
text for the branch that didn't fire. There is no gate type, among the four
that exist (`command`, `context-exists`, `context-matches`,
`children-complete`; `src/gate.rs:14-16`), that inspects prose or asks
whether the agent "read" anything — enforcement here is entirely about
whether a transition's condition is met, not about what text was shown.

**What this means concretely for the no-anchor path.** A state placed after
`ci_monitor` (name pending the design hop that settles state layout) with:

- a `command`-type gate running the Option 2 search (or whatever Decision 1
  resolves it to), exit 0 with the PLAN path captured when found, exit 1
  otherwise;
- a transition to the cascade-invoking state when the gate exits 0, requiring
  no evidence;
- a transition straight to `done` when the gate exits 1, likewise requiring
  no evidence;

produces a run where, on the no-anchor branch, the agent's transcript never
carries a directive mentioning a cascade, a document chain, or anything the
PRD's "maintainer fixing an ordinary bug must not learn a cascade step
exists" (`PRD:176-177`) forbids. The only prose the agent ever sees on that
path is whatever `## done`'s own directive says today — unchanged, since the
no-anchor branch routes there directly and does not pass through the
cascade-invoking state's markdown at all.

**One caveat worth stating precisely.** The *session event log* — the
append-only record `koto next`/`koto init` write to on every tick — still
records that the gate command ran and its exit code
(`default-action-conversion.md`'s own "One check before converting anything"
section: "Every run appends the command, its exit code, stdout, and stderr to
the session event log"). That is a durable audit trail, not agent-facing
narration, and it is the same shape every other zero-evidence gate in this
codebase already produces (`settled_branch_record`, `pr_precheck`) without
anyone treating that as a violation of "the maintainer must not learn." R3's
target is what a person reads as the run's *story* — the directive text and
whatever the agent says to the user — not the machine-internal event log a
maintainer would have to go looking for on purpose. The design should say
this explicitly so a reviewer checking R3 knows which artifact the
requirement is judged against.

## Preserving R4

The existing no-upstream-chain behaviour lives entirely inside
`run-cascade.sh` and is untouched by anything this decision proposes,
because this decision only concerns whether the caller invokes the script at
all — once a real PLAN path is handed to it, R4's case is the script's own
business. Concretely: `run-cascade.sh`'s finalize-chain step reports a
one-node chain (the PLAN itself, with no upstream) as
`cascade_status: skipped` while still staging and — under `--push` —
committing and pushing the PLAN's own deletion
(`run-cascade.sh:1130-1153`, "`skipped` — the PLAN had no upstream chain
(only the delete step ran)... Note that the second of those still commits
and pushes: the PLAN's own deletion is part of the finalization, so a
no-upstream chain publishes that one change and reports `skipped`").

This is pinned by `scenario_push_plan_only_commits_deletion`
(`skills/execute/scripts/run-cascade_test.sh:2046-2140`, "Scenario 24:
--push commits a PLAN-only chain's own deletion"), which asserts: the
worktree is clean after the cascade, HEAD advanced past the fixture commit,
the new commit deletes the PLAN, the push reached origin, and —
explicitly — "`cascade_status` is still `skipped` for a one-node chain... A
fix that flips this to `completed` would be a contract regression, not a
fix" (`run-cascade_test.sh:2114-2117`). Nothing in either the anchor-search
mechanism (Option 2) or the no-evidence routing (the mechanical answer above)
touches this script; a run that finds a real anchor via the search simply
hands `run-cascade.sh` the same path `/execute` would hand it today, and the
script's own pre-probe and finalize-chain logic decide `completed` vs.
`partial` vs. `skipped` exactly as they do now. The design can state this
directly: R4's case is reached by construction whenever Option 2's search
finds a real, on-disk PLAN whose upstream chain happens to already be empty
or already terminal — the caller-side change only widens *when* the script
gets called with a real path, never *what* the script does once it has one.

## Recommendation

Detect the anchor by searching `docs/plans/` for a PLAN whose Implementation
Issues table names `{{ISSUE_NUMBER}}` in its Issue column specifically
(Option 2), run as a late `command`-type gate immediately before the
cascade-invoking state — not cached from `context_injection` (Option 4's
caching variant) and not dependent on a caller-supplied value or a new
issue-body field as the sole path (Options 1 and 3). Wire the two outcomes
through zero-evidence, gate-only transitions exactly as `pr_precheck` and
`settled_branch_record` already do, so the no-anchor branch produces no
agent-facing cascade language by construction rather than by convention.

The decisive reason is that this is the only option, among the four, that
covers the actual motivating population — issues that already exist, created
by a PLAN that already ran `create-issue.sh` with no forward-looking field —
without requiring anyone (a human, an orchestrator, or a past `/plan` run) to
have already known this feature would exist. Option 1 is a valid
*short-circuit* to keep (a caller who does know should not be made to pay for
a search), and Option 3's `Plan:` field is worth adding *in addition*, since
it is cheap and becomes the fast, authoritative path for every issue created
from here forward — but neither can be the mechanism the PRD's acceptance
criteria are checked against, because both are silent for the issues that
already surfaced the defect.

The failure direction being accepted is false negative: an issue-carrying
PLAN in a shape the anchored search doesn't recognize (a hand-edited table
row, a format the FC05 migration hasn't reached, a PLAN a run can't find for
some other reason) reads as "no anchor" and the run completes via R3's
pass-through rather than pulling a chain that, in fact, existed. This is the
same direction the PRD's own "Decisions and Trade-offs" section already
commits to for the adjacent case — rejecting a synthesized anchor "to make a
control-flow decision" (`PRD:507-508`) in favor of treating uncertainty as
"no chain, no output" — and it is the safer failure here specifically because
the alternative, a false positive, means handing `run-cascade.sh` a
plausible-looking but *wrong* PLAN path (a different PLAN that happens to
reference this issue number in a dependency cell, per the concrete collision
shown above), which would let the script mutate an unrelated document's
lifecycle state. A missed chain is a recoverable, visible gap — someone can
run `/execute` on the real PLAN later, or notice the PLAN is still open next
time anyone looks at it. A wrongly-cascaded document is a corrupted lifecycle
record that has to be found and reverted.

## Open questions

- **Exact placement in the post-`ci_monitor` spine.** Whether the
  anchor-check is its own named state or folded into whatever state Decision
  3 gives the cascade invocation is a template-authoring detail this
  decision doesn't need to settle, but it does need the ordering constraint
  from "Composing with the child-signal" above carried into that design: the
  child/root discriminator must gate before the anchor search runs, not
  after.
- **Whether the search belongs in a shell script or a new `shirabe`
  subcommand.** `DESIGN-issue-outlines-one-parser.md`'s history argues
  strongly for reusing the engine's own table parser rather than adding a
  fourth independent reader of this syntax, but *where* that lands (a new
  `shirabe plan find-issue` subcommand vs. extending `plan outlines`) is
  bound up with Decision 1's choice of where shared cascade machinery lives,
  and shouldn't be pre-empted here.
- **Multiple-match handling.** If the search ever finds more than one PLAN
  naming the same issue in its Issue column (which should not happen given
  each issue is materialized from exactly one PLAN, but nothing in the
  validator suite explicitly forbids it), the safer response is routing to
  the run's blocking terminal for a human decision rather than guessing —
  consistent with the false-positive-averse bias above — but the exact
  routing (a new evidence value, or treating it as a gate failure with an
  `override`) is an authoring detail for whoever writes the state.
- **Whether Option 3's `Plan:` field is worth adding in this same PR.** It is
  cheap and strictly additive (a fast path for future issues, never a
  correctness requirement), but adding a new issue-body convention touches
  `create-issue.sh` and the issue-drafting templates, which sit outside this
  PRD's stated Functional requirements — worth flagging to the coordinator as
  a candidate for a follow-up issue rather than assuming it belongs in either
  of this feature's two PRs.
