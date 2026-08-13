# Minimum viable change: making the corpus's existing fan-out evaluable

Research for PRD-chain-cardinality, phase 2. Documentation only — no
implementation is proposed or recommended here.

**Provenance of every result below.** All findings in sections 1-3 were
produced by an **unmodified** validator: `target/release/shirabe` built from
this worktree at commit `c86173a` with `crates/` pristine (`git diff` empty
on all three source files). The whole battery was re-run against a
force-rebuilt pristine binary after the fact and reproduces byte-identically.
The installed `shirabe v0.15.0` on PATH behaves identically on every case
tested.

Section 4 sizes a hypothetical change. Its line counts come from a
throwaway experiment that has been reverted; the repository is clean and no
patch exists in the tree. Scratch corpora and driver scripts live under
`/home/dgazineu/.claude/jobs/0489d65c/tmp/` (`yaml/`, `order/`). Nothing was
written into any repo except this file.

---

## 1. Empirical baseline

### 1.1 The briefed command reports nothing because it validates nothing

```
$ shirabe validate docs --visibility=public --format human
All checks passed.

Advisory: Draft posture: no draft-tolerable findings to flag.
exit=0
```

This is a false clean. A directory positional is silently discarded:
`crates/shirabe/src/main.rs:603-607` calls `detect_format(basename(path))`
and `continue`s on `None`. `docs` has no artifact prefix, so the loop body
never runs. No warning, no non-zero exit.

The same trap exists in the other mode. `--lifecycle` takes a **repo root**,
not a docs directory — `build_doc_index` joins `root` with `docs/briefs`,
`docs/prds`, and so on (`lifecycle.rs:275-282`). Passing `docs` makes it
look for `docs/docs/briefs`, index zero files, and report clean at exit 0.
Both of the first two baseline runs in this investigation were false
negatives for this reason. The correct invocations are an explicit file list
and `--lifecycle .`.

Expanding to the real file list gives the actual per-file baseline:

```
$ shirabe validate $(find docs -name '*.md' | sort) --visibility=public --format human
docs/briefs/BRIEF-cascade-outline-ac-completeness.md:16 error [R6] upstream "docs/plans/PLAN-roadmap-plan-standardization.md" does not exist on disk
docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md:22 error [R6] upstream "docs/designs/DESIGN-roadmap-plan-standardization.md" does not exist on disk
docs/briefs/BRIEF-lifecycle-passing-state-validation.md:18 error [R6] upstream "docs/designs/DESIGN-roadmap-plan-standardization.md" does not exist on disk
docs/briefs/BRIEF-single-pr-plan-validation.md:4 error [R6] upstream "docs/plans/PLAN-roadmap-plan-standardization.md" does not exist on disk
docs/briefs/BRIEF-table-diagram-reconciliation.md:20 error [R6] upstream "docs/designs/DESIGN-roadmap-plan-standardization.md" does not exist on disk

5 error(s), 128 notice(s) -- violations
exit=2
```

Those five errors are the brief's fourth user journey, already live in the
corpus. `git log --diff-filter=D` shows both targets removed in one commit:

```
a133581 chore(plan): verify-then-delete roadmap-plan-standardization (#190)
docs/designs/DESIGN-roadmap-plan-standardization.md
docs/plans/PLAN-roadmap-plan-standardization.md
```

Three documents pointed at the DESIGN and two at the PLAN. All five were
left dangling. Neither gate catches this: `validate-docs.yml:88` computes
its file set with `git diff --name-only`, so an untouched sibling is never
checked; and whole-tree `--lifecycle` reports zero here, because the
dangling references sit on BRIEFs at `Done`, which the orphan rule passes on
terminal status alone.

### 1.2 Lifecycle mode, correctly invoked

| repo | `--lifecycle . --mode=draft` | `--mode=ready` |
|---|---|---|
| shirabe (this worktree) | 0 errors, 2 notices (exit 0) | 2 errors (exit 2) |
| koto | clean (exit 0) | clean (exit 0) |
| tsuku | 3 errors (exit 2) | 3 errors (exit 2) |

```
### shirabe, --mode=ready
docs/briefs/BRIEF-chain-cardinality.md:1 error [L02] orphan BRIEF at status 'Accepted' ...
docs/prds/PRD-koto-adoption.md:1 error [L02] orphan PRD at status 'Accepted' ...

### tsuku, --mode=draft
docs/designs/DESIGN-install-ux-v2.md:1 error [L01] DESIGN at status 'Accepted' (expected status 'Planned' or 'Current' for single-pr mid-PR posture)
docs/plans/PLAN-install-ux-v2.md:1 error [L01] PLAN at status 'Draft' (expected status 'Active' for single-pr mid-PR posture)
docs/roadmaps/ROADMAP-auto-update.md:1 error [L01] ROADMAP at status 'Done' (expected DELETED (absent from tree) for multi-pr work-completing posture)
```

**None of these findings is about fan-out.** They are ordinary status drift.

### 1.3 The fan-out families, and what the validator says about them

Counted by grouping every `upstream:` value across the three repos:

| repo | parent | children |
|---|---|---|
| tsuku | `docs/prds/PRD-auto-update.md` | 9 DESIGNs |
| koto | `docs/prds/PRD-gate-transition-contract.md` | 4 DESIGNs |
| koto | `docs/prds/PRD-session-persistence-storage.md` | 2 DESIGNs |
| shirabe | `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` | 1 BRIEF + 1 PRD |
| shirabe | `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` | 1 BRIEF + 1 PRD |

`--lifecycle-chain` on thirteen documents drawn from these families — the
three PRDs, six of the DESIGNs, both BRIEFs, one downstream PRD:

```
--- docs/prds/PRD-auto-update.md ---                  All checks passed. exit=0
--- docs/designs/current/DESIGN-self-update.md ---    All checks passed. exit=0
--- docs/prds/PRD-gate-transition-contract.md ---     All checks passed. exit=0
--- docs/briefs/BRIEF-lifecycle-passing-state-validation.md --- All checks passed. exit=0
... (all thirteen identical)
```

**The validator reports nothing wrong about any fan-out in the corpus
today.** This is load-bearing, and the reason is specific rather than
reassuring: the fan-out is *dormant*, not *checked*.

Chains root only at a PLAN or a ROADMAP and walk upward
(`lifecycle.rs:460-561`). No PLAN survives under any of the nine tsuku
designs or the six koto designs — that work shipped and the plans were
deleted. With no root, none of those documents is a chain member at all, so
each falls to the orphan rule instead. There, `has_downstream_child`
(`lifecycle.rs:742-749`) passes any document that something points at. So
`PRD-auto-update` sits at `Accepted` beneath nine `Current` designs and
passes precisely *because* it has nine children — the fan-out is the thing
suppressing the finding.

The shirabe BRIEF fan-out is invisible for a different reason: the chain
walk stops unconditionally at a BRIEF (`lifecycle.rs:539-541`), so a
`BRIEF -> BRIEF` edge is never a membership edge under any circumstances.

Two corpus facts worth recording. First, the brief's "`BRIEF -> PRD` is
uniform at 58 of 58" holds only if you count PRD children; two shirabe
BRIEFs each have two children, and in both cases one child is another BRIEF.
Second, **there is no strategic corpus to test** — `docs/visions/`,
`docs/strategies/`, and `docs/competitive/` are absent from all three repos.
The strategic-chain half is entirely prospective; every fan-out on disk is
tactical.

---

## 2. The four YAML `upstream:` shapes, against the unmodified validator

Five shapes (the four asked for, plus a single-item sequence), each written
into an otherwise identical DESIGN, all targets present and git-tracked:

| shape as written | R6 result |
|---|---|
| `upstream:` + `- a` / `- b` (block sequence) | `error [R6] upstream "" does not exist on disk` |
| `upstream: [a, b]` (flow sequence) | `error [R6] upstream "" does not exist on disk` |
| `upstream:` + `- a` (single-item sequence) | `error [R6] upstream "" does not exist on disk` |
| `upstream: \|` + `a` / `b` (block scalar) | `error [R6] upstream "a\nb" does not exist on disk` |
| `upstream: a` (plain scalar) | `All checks passed.` |

The reported claim is confirmed, and the mechanism is one line.
`frontmatter.rs:236` reads
`scalar_source_text(&val_node.data).unwrap_or_default()`, and
`scalar_source_text` (`frontmatter.rs:264-270`) matches only
`Representation` and `Value`, returning `None` for every sequence node. The
`unwrap_or_default()` turns that into `""`. R6 (`checks.rs:784-822`) then
treats `field.value` as one path and reports the empty string verbatim.

Note the **single-item** sequence fails identically. This is not a plurality
problem; it is a "sequences do not survive parsing" problem. A single-parent
document written in list syntax breaks the same way.

The same documents under `--lifecycle-chain` show the two readers
disagreeing about the same field:

```
--- DESIGN-block-sequence.md ---
docs/designs/DESIGN-block-sequence.md:1 notice [L02] orphan DESIGN at status 'Planned' ...
--- DESIGN-flow-sequence.md ---
docs/designs/DESIGN-flow-sequence.md:1 notice [L02] orphan DESIGN at status 'Planned' ...
--- DESIGN-block-scalar-pipe.md ---
All checks passed.
--- DESIGN-plain-scalar.md ---
All checks passed.
```

The sequence shapes lose their lineage entirely — the walk sees no upstream,
so the document becomes an orphan. The block scalar keeps *both* parents,
because `extract_upstreams` (`lifecycle.rs:396-436`) already splits on
newlines and strips `- ` prefixes. **List handling is already implemented in
the chain walk and has simply never been reachable**, because the parser
destroys the value before the walk sees it.

Three independent readers of the field exist, and no two agree:

| reader | shape it understands |
|---|---|
| `checks.rs:790` (R6) | one scalar path |
| `lifecycle.rs:396-436` (`extract_upstreams`) | a newline-separated list, all entries |
| `finalize.rs:723-726` (`read_upstream`) | one scalar path |

And the walk that consumes `extract_upstreams` discards the plurality one
line later: `lifecycle.rs:542`, `cur = node.upstreams.first().cloned();`.

One more thing this turned up.
`docs/prds/PRD-lifecycle-passing-state-validation.md:147-148` states as a
shipped requirement (R2) that "the walker handles both scalar
(`upstream: docs/path/file.md`) and list (`upstream: [...]` or YAML-list
form) shapes." That requirement is not met by the code that ships. Whatever
the PRD decides, this is an existing accepted requirement in an unmet state,
not new scope.

---

## 3. The filename-ordering claim: reproduces, in the opposite direction

Scratch corpus: one `BRIEF-shared.md` at `Accepted`, two PRDs pointing at
it, two DESIGNs, two multi-pr PLANs — `PLAN-aaa.md` at `Done`
(work-completing posture, wants the BRIEF at `Done`) and `PLAN-zzz.md` at
`Active` (in-flight posture, wants the BRIEF at `Accepted`).

```
$ shirabe validate --lifecycle-chain docs/briefs/BRIEF-shared.md --visibility=public
docs/briefs/BRIEF-shared.md:1 error [L01] BRIEF at status 'Accepted' (expected status 'Done' for multi-pr work-completing posture)
docs/designs/DESIGN-one.md:1 error [L01] DESIGN at status 'Planned' (expected status 'Current' for multi-pr work-completing posture)
docs/plans/PLAN-aaa.md:1 error [L01] PLAN at status 'Done' (expected DELETED (absent from tree) for multi-pr work-completing posture)
docs/prds/PRD-one.md:1 error [L01] PRD at status 'Accepted' (expected status 'Done' for multi-pr work-completing posture)
4 error(s) -- exit=2

$ git mv docs/plans/PLAN-aaa.md docs/plans/PLAN-zzzz.md    # no content change
$ shirabe validate --lifecycle-chain docs/briefs/BRIEF-shared.md --visibility=public
All checks passed.
exit=0
```

**Reproduced.** The brief reports 0 -> 2; this reproduction runs 4 -> 0. The
direction depends on which chain sorts first and the magnitude on how many
members differ, but it is the same defect: a rename with no content change
anywhere flips a shared BRIEF between clean and failing.

The cause is `lifecycle.rs:1113-1115`, which takes the **first** matching
chain:

```rust
let matched_chain = chains
    .iter()
    .find(|c| c.members.iter().any(|m| m.path == canon_doc));
```

`chains` is built by iterating a `BTreeMap` keyed on canonical path
(`lifecycle.rs:464`), so chain order is the sorted order of the root PLAN's
filename. `PLAN-aaa.md` sorts before `PLAN-zzz.md`; `PLAN-zzzz.md` sorts
after. Whole-tree `--lifecycle` is *not* affected — it iterates every chain
and dedups — so the two modes disagree about the same corpus, which is a
second symptom of the same line.

### 3.1 The unsatisfiability is real and produces no diagnostic

Same corpus, whole-tree mode, sweeping the shared BRIEF's status:

```
BRIEF status 'Accepted':  error [L01] BRIEF at status 'Accepted' (expected status 'Done' for multi-pr work-completing posture)
BRIEF status 'Done':      error [L01] BRIEF at status 'Done' (expected status 'Accepted' for multi-pr in-flight posture)
BRIEF status 'In Progress':
                          error [L01] BRIEF at status 'In Progress' (expected status 'Accepted' for multi-pr in-flight posture)
                          error [L01] BRIEF at status 'In Progress' (expected status 'Done' for multi-pr work-completing posture)
```

No value passes. Each message reads as ordinary status drift and names one
expectation; nothing tells the author another chain demands the opposite.
Only the third case — a status neither chain wants — makes the contradiction
visible at all, and then only by inference from two adjacent lines.

### 3.2 `finalize-chain` walks one branch and silently retires shared parents

```
$ shirabe finalize-chain --dry-run docs/plans/PLAN-zzzz.md
{"nodes":[
  {"path":"docs/plans/PLAN-zzzz.md","action":"delete_plan"},
  {"path":"docs/designs/DESIGN-one.md","action":"transition_design","target_status":"Current"},
  {"path":"docs/prds/PRD-one.md","action":"transition_prd","target_status":"Done"},
  {"path":"docs/briefs/BRIEF-shared.md","action":"transition_brief","target_status":"Done"}]}
```

It drives the shared BRIEF to `Done` while the other chain, still `Active`,
requires it at `Accepted`. No consumer count, no warning. This is the
mutating path by which fan-out actually breaks, and the same shape that
produced PR #190's five dangling references.

---

## 4. Sizing the floor

The costs below are described, not applied. The line counts for (a) come
from a throwaway experiment run to measure the diff; it has been reverted
and the repository is clean.

### (a) Make it not-wrong

The three defects in sections 2 and 3 correspond to three functions:

| file | function | what would have to change |
|---|---|---|
| `frontmatter.rs` | `parse_yaml_fields`, plus a private helper | make a YAML sequence node survive parsing instead of collapsing to `""` — for example by rendering it as newline-joined text, the shape a `\|` block scalar already produces |
| `checks.rs` | `check_upstream_resolves` (R6) | iterate the entries in the field rather than treating the whole value as one path; emit one finding per unresolvable entry |
| `lifecycle.rs` | `run_lifecycle_chain_check` | evaluate every chain containing the input doc rather than the first one found, removing the filename dependence and aligning the mode with `--lifecycle` |

Measured cost: **3 files, +50/-31 lines**, of which most of the `checks.rs`
count is reindentation into a loop — roughly 35 substantive lines. **Three
functions modified, one private helper added, zero type changes, zero new
public API, zero new finding codes.** The experiment passed the full suite
(843 tests, 0 failures) and produced byte-identical output on all three
repos in both postures.

Two things make this floor cheaper than it looks. First,
`extract_upstreams` already handles lists, so a parser fix activates
existing code rather than adding a code path. Second, **no document in any
of the three repos uses a sequence-valued frontmatter field** (verified by
scanning every frontmatter block), so a newline-join representation changes
no existing byte.

Three things to weigh against that. A bare `upstream:` with an empty value
currently produces `R6 upstream "" does not exist`; under a line-iterating
R6 it would produce nothing, which is a deliberate behavior choice someone
has to make. The Go-vs-Rust parity gate (`parity-check.yml`) is a latent
risk if Go remains the baseline for sequence-valued fields, though no
fixture in the repo exercises one. And most importantly:

**What (a) does not do:** it makes a shared BRIEF fail against *both* chains
instead of one arbitrarily-chosen chain. That is stable and honest, but not
diagnostic — the author gets two contradictory L01s and no statement that
they contradict.

### (b) Report a clear diagnostic

Everything (b) needs is already computed. `discover_chains` returns every
chain with its posture, and `compute_passing_state` is a pure function of
`(role, posture)`. A conflict check is a new function over that existing
vector: group members by path, compute each chain's required state, report
when the accepted-status sets are disjoint.

Estimated from the existing shapes rather than measured: one new function
(~40 lines) plus a compatibility predicate on `PassingState` (~15 lines,
which needs `PassingState` to derive `PartialEq`, currently absent — the
only type-level change, and it is a derive rather than a redesign).
Suppressing the contradictory L01 pair in favor of the conflict message is a
branch in the emission loop of both `run_lifecycle_check` and
`run_lifecycle_chain_check`. A new code (L08) needs **no registration**:
`posture_class` (`validate.rs:110-115`) falls through to `AlwaysEnforced`,
and the advisory remedy map is optional. Call it two functions added, two
touched, one derive.

Journey 4 — knowing who still points at a document before deleting it — is
adjacent but separate. `build_inverse_upstream` already answers it inside
the validator, but `finalize.rs` has no document index at all; it is a pure
single-path walk. Giving it a consumer count means building an index there
and threading it into the mutation path, not the check path.

### (c) Fully model 1:N

Everything above keeps the assumption that a chain is a path and posture is
a property of that path. (c) breaks it. Posture attaching to the edge means:
`discover_chains` becomes a graph traversal rather than a per-root linear
walk; `Chain.members` / `ChainMember` become a per-document set of
obligations rather than a list with one posture; `compute_passing_state`
takes an edge set and needs an intersection operation over `PassingState`;
L01's message has to name which edge imposed which expectation; and
`--lifecycle-chain` needs a defined answer to "which chain" when there are
several. That is a redesign of the module's core data structures, not an
addition to them.

**The gap between (a) and (c) is large; the gap between (a) and (b) is
small.** (a) is ~35 substantive lines across three functions with no type
changes. (b) adds a check over structures that already exist. (c) rewrites
the data model.

---

## 5. What the floor does not buy

**Confirmed: no validator change touches the parent-skill half.** The two
halves share no code. `/charter` is prose in
`skills/charter/references/phases/`; the validator is Rust in
`crates/shirabe-validate/`. The only coupling is that `/charter` shells out
to `shirabe validate --format json` at chain finalization to check the
STRATEGY it just wrote — a per-file check on one document, unrelated to
cardinality.

The mechanism the brief describes is confirmed in the skill text.
`phase-2-chain-orchestration.md:33-37`: "Phase 1 inspects
`docs/visions/VISION-<topic>.md` for the topic slug; if nothing Accepted or
Active is there, `/vision` runs. A cold start is therefore always a
`/vision` run — there is no upstream thesis to build on, and nothing the
author says about the thesis changes that." And line 64: "The invocation
passes ONLY the topic slug." Meanwhile `/strategy` invoked directly takes an
arbitrary upstream VISION path as `$ARGUMENTS`
(`skills/strategy/references/phases/phase-0-setup.md:13,156-158`) and
records it into the draft's `upstream:`. The child accepts what the parent
cannot express, exactly as reported.

So after the full (a)+(b)+(c) validator work, all of this remains:

- A second bet under a live thesis is still unreachable through `/charter`.
  A distinct slug still misses the VISION lookup and writes a second VISION;
  a reused slug still collides on the STRATEGY path and routes into resume.
- `/scope`'s absorbability test still ignores how many consumers an upstream
  has. A better validator would report the dangling sibling afterward; it
  would not stop the absorb.
- `finalize-chain` still walks one branch and retires shared parents without
  counting consumers — unless the index is threaded into the mutation path,
  which is not a check-side change.
- The strategic directories are still outside the lifecycle index
  (`lifecycle.rs:275-282` lists six directories, none strategic). With no
  VISION or STRATEGY on disk in any of the three repos, no validator change
  has anything to evaluate on that side. Indexing them is a prerequisite for
  the strategic half mattering at all, and is itself unbounded by the
  tactical fan-out work.
- The formats still describe a shape the tools do not produce. Nothing in
  the validator makes `/charter` produce it.

A validator change makes fan-out *checkable*. It does not make fan-out
*creatable through a parent skill*, and the corpus's fan-out was created by
`/design`'s split heuristic and by direct child invocation, not by a parent.
