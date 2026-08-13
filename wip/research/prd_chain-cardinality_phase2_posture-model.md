# Posture model options: where posture attaches when a document has N downstream roots

Research for PRD-chain-cardinality, Phase 2. All findings below are grounded in
`crates/shirabe-validate` as of commit `c86173a` on branch `charter-scope-parity`,
and verified empirically with two throwaway probe tests (deleted after the run; the
fixture shapes are reproduced inline so they can be recreated).

> **Concurrent working-tree edit.** While this research was running, another agent
> in this session left an uncommitted change in
> `crates/shirabe-validate/src/frontmatter.rs` adding a `sequence_source_text` helper
> so a YAML sequence renders as newline-joined text instead of collapsing to `""`.
> Everything below is measured against **HEAD** (`c86173a`), where line 236 is still
> `scalar_source_text(&val_node.data).unwrap_or_default()`. If that edit lands, the
> "list-shaped `upstream:` collapses to the empty string" finding in section 5 is
> fixed at the parser and the `.first()` truncation at `lifecycle.rs:542` becomes the
> live defect instead of a latent one. Two drive-by notes on that WIP: it inserts
> `sequence_source_text` *between* `scalar_source_text`'s doc comment and its
> signature, so the doc comment now documents the wrong function; and it does not
> touch `checks.rs:788` or `finalize.rs:393-396`, which would then receive a
> newline-joined multi-path string where they expect one path.

## Preliminary correction: `probe_1n.rs` does not exist

The task brief, the BRIEF, and `wip/research/explore_charter-scope-parity_r1_lead-cardinality.md`
(lines 135-137, 278-287, 328) all cite `crates/shirabe-validate/tests/probe_1n.rs` as
a checked-in, assertion-free probe on exactly this question. It is not in the tree:

- `crates/shirabe-validate/tests/` contains no `tests/` directory at all; the crate's
  tests are the 567 in-module `#[cfg(test)]` tests. Integration tests live in
  `crates/shirabe/tests/` (`absorption_parity.rs`, `cli.rs`, `coordination_body.rs`,
  `fc07_corpus.rs`, `lifecycle_advisory.rs`, `lifecycle_posture.rs`, `merge_gate.rs`,
  `parity.rs`, `populate_cli.rs`, `transition_parity.rs`, `transition.rs`,
  `work_summary.rs`).
- `find` across the whole workspace returns nothing matching `probe_1n*`.
- `git log --all --diff-filter=A -- '*probe_1n*'` returns nothing: the file was never
  committed on any branch.

The exploration's *substantive* claims about list-shaped `upstream:` behavior are
nonetheless correct — I re-derived them empirically below. Only the artifact
attribution is wrong. Anything the PRD writes that leans on "a probe already
documents this" should be rephrased, and the "Surprises" bullet in the exploration
research should be struck.

---

## 1. Reproducing the unsatisfiability

### The mechanism, in code

`discover_chains` (`lifecycle.rs:460-561`) iterates every indexed doc, and for each
one whose format is `Plan` or `Roadmap` (`:465-469`) builds a `Chain` by walking the
`upstream:` edge upward. A chain therefore *is* its root: one root, one `Chain`, one
`Chain.posture` (`:552-557`). Non-root members are cloned into every chain that
reaches them — `ChainMember` (`:157-162`) carries only `path`, `role`, `status`, with
no back-reference to the chain, and the same document appears as a distinct
`ChainMember` value in each chain.

`run_lifecycle_check` (`:851-895`) then loops chains-outer, members-inner and pushes
an L01 for every `(member, chain)` pair whose status fails `compute_passing_state`
(`:620-670`). Nothing groups by member. Two chains over one document produce two
independent obligations on that document's single `status:` field
(`doc.rs:31` — `pub status: String`).

The `errors.dedup()` at `:923` does not collapse them, because the L01 message
interpolates `effective_posture.name()` (`:883-888`), so the two findings differ in
their message text and both survive.

### The exact table rows

Reachable postures are only four. `infer_posture_from` (`:574-608`) can return
`MultiPrInFlight`, `MultiPrWorkCompleting`, `SinglePrMidPR`, `SinglePrAtMerge`;
`Posture::MultiPrAtMerge` (`:92`) is never constructed anywhere in the crate — its
five rows at `:641-645` are unreachable dead code, since `discover_chains` only ever
roots at a document present in the index.

The four live rows of `compute_passing_state`, per role:

| Role | `MultiPrInFlight` (:625-629) | `SinglePrMidPR` (:652-660) | `MultiPrWorkCompleting` (:633-637) | `SinglePrAtMerge` (:664-668) |
|---|---|---|---|---|
| BRIEF | `Status("Accepted")` | `Status("Accepted")` | `Status("Done")` | `Status("Done")` |
| PRD | `PrdAcceptedOrInProgress` = {Accepted, In Progress} | `PrdAcceptedOrInProgress` | `Status("Done")` | `Status("Done")` |
| DESIGN | `DesignPlannedOrCurrent` = {Planned, Current} | `DesignPlannedOrCurrent` | `Status("Current")` | `Status("Current")` |
| PLAN | `Status("Active")` | `Status("Active")` | `Deleted` | `Deleted` |
| ROADMAP | `Status("Active")` | `Status("Active")` | `Deleted` | `Status("Active")` |

The four postures partition into two **phase groups**:

- **in-flight** = {`MultiPrInFlight`, `SinglePrMidPR`}
- **completing** = {`MultiPrWorkCompleting`, `SinglePrAtMerge`}

Within a group the passing states are identical for BRIEF/PRD/DESIGN. Across groups:

- **BRIEF**: `Status("Accepted")` (row `:625` / `:652`) versus `Status("Done")`
  (row `:633` / `:664`). `PassingState::matches` (`:208-217`) is exact string equality
  for the `Status` variant, so the two admissible sets are `{Accepted}` and `{Done}` —
  **disjoint. Genuinely unsatisfiable**, not awkward: no value of one `String` field
  satisfies both, and there is no third status that satisfies neither-but-passes.
- **PRD**: `{Accepted, In Progress}` (`PrdAcceptedOrInProgress`, `:213-215`) versus
  `{Done}`. **Disjoint. Genuinely unsatisfiable.**
- **DESIGN**: `{Planned, Current}` versus `{Current}`. Intersection `{Current}` —
  **satisfiable**, at the cost that the shared DESIGN must be promoted to `Current`
  (and physically moved into `docs/designs/current/`, or L07 fires — `:784-808`)
  while a sibling PLAN is still in flight.

### Empirical confirmation

Fixture: one BRIEF, one PRD, two DESIGNs, two PLANs under the one PRD.

```
docs/briefs/BRIEF-x.md                  status: <varied>
docs/prds/PRD-x.md                      upstream: docs/briefs/BRIEF-x.md
docs/designs/DESIGN-a.md                upstream: docs/prds/PRD-x.md   status: Planned
docs/designs/current/DESIGN-b.md        upstream: docs/prds/PRD-x.md   status: Current
docs/plans/PLAN-a.md   execution_mode: single-pr  status: Active  upstream: DESIGN-a
docs/plans/PLAN-b.md   execution_mode: multi-pr   status: Done    upstream: DESIGN-b
```

`run_lifecycle_check(root, &Config::default(), ReviewPosture::Draft)`, sweeping the
BRIEF's status over the whole BRIEF enum:

```
BRIEF status = Draft        -> 2 L01 findings on BRIEF-x
    expected 'Accepted' for single-pr mid-PR posture
    expected 'Done' for multi-pr work-completing posture
BRIEF status = Accepted     -> 1 L01: expected 'Done' for multi-pr work-completing
BRIEF status = In Progress  -> 2 L01
BRIEF status = Done         -> 1 L01: expected 'Accepted' for single-pr mid-PR
```

Minimum over all four statuses is **1**, never 0. Same sweep on the PRD:

```
PRD status = Draft        -> 2 L01
PRD status = Accepted     -> 1 L01 (expected 'Done' for multi-pr work-completing)
PRD status = In Progress  -> 1 L01 (expected 'Done' for multi-pr work-completing)
PRD status = Done         -> 1 L01 (expected 'Accepted' or 'In Progress' for single-pr mid-PR)
```

A full 4x4 posture matrix, both review postures, minimum L01 count on the shared doc:

**Shared BRIEF or PRD, `ReviewPosture::Draft`** — 0 findings iff both roots are in the
same phase group; 1 finding (unsatisfiable) for all eight cross-group pairs.

**`ReviewPosture::Ready`** — the re-target at `:857-862` maps `SinglePrMidPR` to
`SinglePrAtMerge`, collapsing the groups to {`MultiPrInFlight`} versus
{`SinglePrMidPR`, `SinglePrAtMerge`, `MultiPrWorkCompleting`}. Ready posture does not
fix the problem; it moves which pairs conflict. `MultiPrInFlight` paired with any
other posture is unsatisfiable under Ready.

**Shared DESIGN** — 0 findings in all 16 pairs, both review postures, at `Current`.
Confirms DESIGN is the satisfiable-but-constrained case.

### The second failure mode: the same question answers differently by filename

`run_lifecycle_chain_check` (`:1020-1166`) — the mode the `/execute` cascade uses
(`skills/execute/scripts/run-cascade.sh:297`) and the R5 finalization guard
(`skills/execute/SKILL.md:508-533`) — does not iterate all chains. It picks one:

```rust
// lifecycle.rs:1113-1115
let matched_chain = chains
    .iter()
    .find(|c| c.members.iter().any(|m| m.path == canon_doc));
```

`chains` is built by iterating `idx.values()` (`:464`), and `DocIndex` is a
`BTreeMap<PathBuf, IndexedDoc>` (`:252`), so chain order is the lexicographic order
of root canonical paths. `.find()` therefore silently selects the chain whose **root
filename sorts first**. With the fixture above and no content change whatsoever:

```
single-pr PLAN named PLAN-aaa.md, multi-pr named PLAN-zzz.md
    -> chain-check seeded on BRIEF-x: 0 findings

same content, the two PLAN filenames swapped
    -> chain-check seeded on BRIEF-x: 3 findings
       [L01] BRIEF at status 'Accepted' (expected 'Done' for multi-pr work-completing)
       [L01] PRD   at status 'Accepted' (expected 'Done' for multi-pr work-completing)
       [L01] PLAN  at status 'Done'     (expected DELETED for multi-pr work-completing)
```

Two of those three are on the shared documents, which is the BRIEF's "flips a shared
BRIEF from zero findings to two" claim, confirmed exactly. Note the direction: whole-tree
mode is *always* wrong (unsatisfiable), chain-targeted mode is *arbitrarily* right or
wrong (a filename lottery). The seed-doc rule in `/execute` makes this worse rather
than better: post-finalization the guard is told to seed on the surviving DESIGN in
`docs/designs/current/`, which is precisely the document most likely to be shared.

### Is it live today, or latent?

**Latent.** Running the real validator across the workspace:

```
$ shirabe validate --lifecycle public/tsuku --mode draft
  DESIGN-install-ux-v2.md  [L01] ... single-pr mid-PR
  PLAN-install-ux-v2.md    [L01] ... single-pr mid-PR
  ROADMAP-auto-update.md   [L01] ... multi-pr work-completing
$ shirabe validate --lifecycle public/koto --mode draft     (clean)
$ shirabe validate --lifecycle . --mode draft               (two L02 notices only)
```

No multi-root conflict fires anywhere. The reason is that a conflict needs **two live
PLAN roots under one upstream, in different phase groups**, and PLANs are deleted at
chain completion. The corpus's fan-out is entirely post-completion:

| Fan-out | Repo | Children | Live PLANs under it |
|---|---|---|---|
| `PRD-auto-update.md` | tsuku | 9 DESIGNs, all in `docs/designs/current/` | 0 |
| `PRD-gate-transition-contract.md` | koto | 4 DESIGNs, all in `current/` | 0 (koto has no `docs/plans/` content) |
| `PRD-session-persistence-storage.md` | koto | 2 | 0 |
| `PRD-workspace-config-sources.md` | niwa | 2 | 0 |

Whole-repo PLAN counts today: tsuku 2 (`PLAN-curated-recipes`, `PLAN-install-ux-v2`,
under different PRDs), shirabe 1, koto 0, niwa 0. The nine designs under
`PRD-auto-update` were implemented sequentially, one PLAN at a time, so the two-live-roots
condition has never held. It holds the moment anyone runs two `/scope` or `/execute`
threads concurrently under one PRD — which is exactly what a fan-out-supporting
workflow would encourage.

One adjacent shape worth booking: a ROADMAP that a PLAN points at is a member of the
PLAN's chain *and* the root of its own single-member chain (a ROADMAP root's walk
breaks immediately at `:539`, so ROADMAP-rooted chains contain only the ROADMAP).
Its two obligations agree while the PLAN is `Active`, and become `Active` versus
`Deleted` (`:637`) once the PLAN reaches `Done` — unsatisfiable in the same way. No
corpus document is in that shape today.

---

## 2. Posture on the edge: what it would mean

Today `status:` is one scalar (`doc.rs:31`), authored in frontmatter, mirrored in the
body's `## Status` section (FC03 enforces equality, `checks.rs:118-166`), constrained
to a per-format enum (FC02, `checks.rs:85-110`), and written by the transition engine
(`transition.rs`, 2364 lines, 293 `status` references, entry point `run_transition`
at `:652`). Four shapes are available.

### Shape A — a genuinely per-edge status

`status:` becomes a mapping keyed by consumer, e.g.

```yaml
status:
  docs/plans/PLAN-a.md: Accepted
  docs/plans/PLAN-b.md: Done
```

Cost: this is the most expensive option in the crate by a wide margin.
`scalar_source_text` (`frontmatter.rs:264-270`) returns `None` for a mapping node, and
the caller at `:235` does `.unwrap_or_default()`, so a mapped `status:` parses to the
empty string — meaning `Doc.status` would silently become `""` and every downstream
check would need rewriting rather than merely adapting. FC02 and FC03 both assume a
scalar; the transition engine's whole `Rule`/`Precondition`/`Moves` model
(`transition.rs`) is single-status; `finalize::walk_chain_mode` calls
`run_transition(&upstream, target, ...)` (`finalize.rs:477`) with one target status
per node. It also inverts the authoring model: a document would carry knowledge of
its consumers, which today only the inverse graph has
(`build_inverse_upstream`, `lifecycle.rs:440-450`).

### Shape B — a derived status

`status:` stops being authored and becomes computed from the chain(s). The validator
would report what the status *should* be rather than checking what it *is*.

Cost: the transition engine and `docstatus` become no-ops or become the sole writers;
FC03's frontmatter-vs-body equality check needs a new source of truth for the body's
`## Status` section; the DESIGN's `Current` status doubles as its directory
(`check_location`, `:784-808`), so a derived status would have to drive a file move.
It also removes the author's ability to say "this BRIEF is Done" independently, which
the orphan rule at `:698-704` currently relies on to let a terminal orphan pass.
Cheaper than Shape A in the parser, more expensive in the workflow skills.

### Shape C — relaxation to "satisfies at least one chain"

Keep one scalar status; change the *check*, not the data. Group discovered chains by
member path, and emit L01 only when no chain's passing state accepts the member's
current status.

Cost in existing types: the smallest of the four. Both loops
(`run_lifecycle_check:863-891` and `run_lifecycle_chain_check:1124-1143`) restructure
from chains-outer/members-inner into a `BTreeMap<PathBuf, Vec<(Posture, PassingState)>>`
built once, then one pass. `Chain`, `ChainMember`, `Posture`, `PassingState`, and
`compute_passing_state` are all unchanged. Roughly 40-60 lines, concentrated in one
file. The message needs rewording since it can no longer name one posture.

Semantic consequence: it always yields a satisfiable state (pick any one chain's
requirement), but it weakens the forcing function — a shared BRIEF at `Accepted`
passes even when one of its PLANs is at `Done` awaiting deletion. It does not weaken
it when *all* chains agree (all-completing still requires `Done`).

### Shape D — order the postures and require one end

Give `Posture` a phase ordering (in-flight < completing) and make a multi-chain
member's obligation the phase-MIN (least-advanced consumer) or phase-MAX
(most-advanced). See section 3 — this is the same computation as the chain-side
aggregation options, differing only in where it is described as living.

`Posture` derives only `Debug, Clone, Copy, PartialEq, Eq` (`:82`), so an ordering is
a new `fn phase(self) -> u8` or a `PartialOrd` impl, ~10 lines.

---

## 3. Posture on the chain, made consistent

All three aggregations operate on the same input: for each document, the multiset of
postures of the chains it belongs to. That grouping does not exist today and is ~15
lines to build (`Chain.members.last()` is always the root, since the root is pushed
first at `:511-517` and the vector is reversed at `:550`).

### Computability with the current types

- **UNION** ("passes if any chain's state accepts it") — computable **as-is**, no type
  changes. `PassingState::matches` (`:208-217`) already answers per-chain; union is
  `.any(...)`. This is Shape C above.
- **INTERSECTION** — **not computable as-is**. `PassingState` is a four-variant enum
  (`:176-191`) with no set algebra: there is no variant that can represent
  `{Planned, Current} ∩ {Current}` as a result, and no way to represent the empty set
  other than by not having a value. It needs a conversion helper —
  `fn admissible(PassingState) -> Option<BTreeSet<&'static str>>` with `None` meaning
  "must be absent" (`PassingState::Deleted`, whose `matches` returns `false` for every
  status, `:210`) — plus a new `PassingState` variant or a switch to carrying the set
  directly. ~30 lines plus every `compute_passing_state` consumer.
  On the real cases: intersection is empty for BRIEF and PRD in exactly the
  cross-group pairs, so intersection reproduces today's unsatisfiability with a better
  error message. It is the *honest* aggregation and the least useful one.
- **MAX (most-advanced)** — needs the phase ordering from Shape D (~10 lines), then
  computable. Result on a shared BRIEF with one in-flight and one completing PLAN:
  requires `Done`. That transitions the BRIEF to terminal while work under it is still
  running, and `Done` is terminal in the BRIEF lifecycle, so the in-flight PLAN's
  completion has nothing left to transition. It also inverts the DESIGN case: a shared
  DESIGN would be forced to `Current` (and moved) at the first completing sibling.
- **MIN (least-advanced)** — same cost as MAX, opposite answer: the shared BRIEF stays
  at `Accepted` until its last consumer finishes, then moves to `Done`. On the three
  real fan-out shapes (9-way, 4-way, 2-way, all currently at zero live PLANs) MIN
  degenerates to today's behavior, and on the concurrent-PLAN shape it produces the
  answer an author would expect: the upstream stays open while anything below it is
  open. MIN is not in the question as posed but is the natural sibling of MAX and the
  one that survives the three real cases without forcing a premature terminal
  transition.

### What each says about the three real fan-out cases

Because all three real cases have zero live PLANs, every aggregation gives the same
answer today (no chain, no obligation — the documents fall through to the orphan rule
at `:686-768` and pass, since all nine DESIGNs are at `Current` and the PRD is
terminal). The differences appear only in the hypothetical concurrent-PLAN case, which
is the case the PRD is deciding for. Stated on that case:

| Aggregation | Shared BRIEF, one in-flight + one completing consumer | Shared DESIGN, same | Forcing function preserved? |
|---|---|---|---|
| Union | `Accepted` or `Done` both pass | `Planned` or `Current` both pass | Weakened (any one consumer suffices) |
| Intersection | unsatisfiable (empty) | `Current` | Preserved, but reproduces the defect |
| MAX | `Done` required | `Current` required | Preserved, but fires early |
| MIN | `Accepted` required | `Planned` or `Current` | Preserved, fires at the right time |

---

## 4. The cheap containment option: detect and report

### What it takes

The condition is decidable from data `discover_chains` already produces. After chain
discovery in both entry points, group members by path and report any member appearing
in more than one chain:

```rust
// after `let (chains, chain_errors) = discover_chains(&idx);`
let mut roots_for: BTreeMap<PathBuf, Vec<(PathBuf, Posture)>> = BTreeMap::new();
for chain in &chains {
    let root = chain.members.last().expect("non-empty by :545").path.clone();
    for m in &chain.members {
        roots_for.entry(m.path.clone()).or_default().push((root.clone(), chain.posture));
    }
}
for (path, roots) in &roots_for {
    if roots.len() > 1 {
        errors.push(error_path(path.clone(), "L08", &format!(
            "document belongs to {} chains ({}); its passing state is computed \
             independently per chain and may be unsatisfiable",
            roots.len(),
            roots.iter().map(|(r, p)| format!("{} [{}]", rel_path_lossy(r), p.name()))
                 .collect::<Vec<_>>().join(", "))));
    }
}
```

That is ~25 lines in `lifecycle.rs`, called from both `run_lifecycle_check` (after
`:838`) and `run_lifecycle_chain_check` (after `:1109`). It reports the condition; it
does not resolve it, so the L01 pair still fires alongside it unless L01 is also
suppressed for multi-chain members (a two-line guard, at the cost of losing the
underlying detail).

### The convention it fits

There is an established `Lnn` family and a well-defined registration surface. A new
`L08` needs edits in exactly these places:

| Location | What |
|---|---|
| `lifecycle.rs:9-36` | module doc-comment code list (L01-L07 documented there) |
| `lifecycle.rs` (new fn + 2 call sites) | the emit |
| `validate.rs:110-115` `posture_class` | classify draft-tolerable vs always-enforced |
| `validate.rs:83-98` `is_intrinsic_notice` | only if it should ship notice-level |
| `advisory.rs:104-113` `remedy_for` | remedy phrase; has a `_ =>` fallback (`:111`) so this is optional-but-expected |
| `docs/guides/lifecycle-posture.md:72-84` | the classification table |
| `validate.rs` tests (`:354`, `:412`, `:466`, `:528`) | four hardcoded code lists |

`is_known_check_code` (`validate.rs:150-172`) deliberately excludes the L-family — it
covers per-file `--check` selectable codes only — so no edit there. `L08` is free;
L01-L07 are taken.

Classification choice matters: `L02`/`L06`/`L07` are the draft-tolerable set
(`validate.rs:112`), notices under `--mode=draft` and errors under `--mode=ready`.
Putting `L08` in that set means a fan-out is legal mid-flight and must be resolved
before review; putting it in always-enforced means fan-out fails immediately in both
postures.

### Total

~25 lines of logic, ~10 lines of registration, plus tests. It is by a wide margin the
smallest of the options in this document, and it is the only one that changes no
existing semantics — a corpus that passes today still passes, because no document is
currently in two chains.

---

## 5. Blast radius per option

Baseline: `cargo test -p shirabe-validate` is 567 passing tests today, of which 50 are
in `lifecycle.rs`, 11 in `validate.rs`, 11 in `advisory.rs`, 27 in `finalize.rs`.
`crates/shirabe` adds 17 in `cli.rs`, 5 in `lifecycle_posture.rs`, 5 in
`lifecycle_advisory.rs`, 2 in `absorption_parity.rs`.

**None of the 50 `lifecycle.rs` tests constructs a two-root tree.** Every fixture has
exactly one PLAN or ROADMAP root (`PLAN-foo.md` in 33 places, `PLAN-a.md` once, in
`upstream_cycle_produces_l03` at `:1878-1902`). This is the single most useful fact for
scoping any of these options: any change that only alters *multi-chain* behavior
breaks zero existing tests.

Two other facts shrink the surface:

- `Chain`, `ChainMember`, `ChainRole`, `RootKind`, `PassingState` are `pub` in the
  module but **not re-exported from `lib.rs`** (the lifecycle exports are
  `run_lifecycle_chain_check`, `run_lifecycle_check`, `target_state_for`, `Posture`,
  `TargetState` — `lib.rs:55-57`). They are internal-shaped; changing them is a
  one-crate change.
- `Chain.root_kind` (`:170`) is **written and never read** — `RootKind` appears only
  at `:151`, `:170`, `:465-467`, `:555`. Dead field.
- `Posture` is re-exported but has **zero users outside `lifecycle.rs`**.

### Per option

**Option 4 (detect and report, new `L08`)**
- Changes: `lifecycle.rs` (new fn, 2 call sites, module doc), `validate.rs:110-115`,
  `advisory.rs:104-113`, `docs/guides/lifecycle-posture.md`.
- Existing tests broken: **0 in behavior**; 4 hardcoded code-list assertions in
  `validate.rs` tests (`:354`, `:412`, `:466`, `:528`) need the new code added if it
  joins the draft-tolerable set. `crates/shirabe/tests/absorption_parity.rs:182,325`
  documents L-code coverage and may want a row.
- Checks affected: none existing. L01 continues to double-fire unless explicitly
  suppressed.

**Option 3-Union / Shape C (satisfies at least one chain)**
- Changes: `run_lifecycle_check:851-895`, `run_lifecycle_chain_check:1117-1146`,
  the L01 message format (`:882-888`, `:1134-1140`), and `errors.dedup()` semantics
  at `:923` become moot for L01.
- `run_lifecycle_chain_check`'s `.find()` at `:1113-1115` **must** change too — if the
  whole-tree mode aggregates over chains and the chain-targeted mode still picks one
  arbitrary chain, the two modes disagree, and the cascade gate
  (`run-cascade.sh:297`) uses the chain-targeted one. This is a required companion
  change for every option in section 3, not an optional extra.
- Existing tests broken: **0** (single-root fixtures are unaffected by an
  any-of-one-chain rule), but the L01 message wording change would break any test
  asserting on message text. `lifecycle.rs` tests assert on `e.code` and
  `e.file.contains(...)` rather than message bodies in the cases I sampled
  (`:1719-1720`, `:1749-1750`, `:2745`), so the exposure is low but should be
  swept. `crates/shirabe/tests/lifecycle_posture.rs` (5 tests) and
  `lifecycle_advisory.rs` (5 tests) exercise the CLI's rendered output and are the
  likelier breakage site.

**Option 3-Intersection**
- Everything in Union, plus a new representation for admissible status sets:
  either a fifth `PassingState` variant carrying a set, or a
  `PassingState -> Option<BTreeSet<&'static str>>` conversion plus rework of
  `describe()` (`:194-205`) and `matches()` (`:208-217`).
- Existing tests broken: 0 behaviorally on single-root trees; `describe()`'s output
  strings appear verbatim in L01 messages ("status 'Planned' or 'Current'"), so the
  same message-text sweep applies.

**Option 3-MAX / MIN (Shape D)**
- Everything in Union, plus `fn phase(Posture) -> u8` or a `PartialOrd` impl on
  `Posture` (`:82`). ~10 lines.
- MAX additionally interacts with L07 (`:784-808`): forcing a shared DESIGN to
  `Current` implies a file move into `docs/designs/current/`, which the validator
  reports but does not perform — so MAX creates a finding that no tool currently
  resolves. MIN does not have this problem.
- Existing tests broken: 0 on single-root trees (MIN and MAX both degenerate to the
  single chain's posture when there is one chain).

**Shape A (per-edge status)**
- Changes: `frontmatter.rs:229-243` and `:264-270` (mapping nodes currently collapse
  to `""`), `doc.rs:31` (`Doc.status: String`), FC02 (`checks.rs:85-110`), FC03
  (`checks.rs:118-166`), the whole of `transition.rs` (293 status references),
  `finalize.rs:468-505` (which calls `run_transition` with one target per node),
  `merge_gate.rs`, plus the frontmatter format specs in `skills/*/references/*-format.md`
  and every existing document in four repos.
- Existing tests broken: essentially all status-touching tests — 11 FC02/FC03 tests
  visible in `checks.rs` alone, all of `transition.rs`'s suite, `transition_parity.rs`,
  and the corpus fixtures. This is a format-breaking change, and the BRIEF explicitly
  puts corpus migration out of scope.

**Shape B (derived status)**
- Changes: FC03's source of truth (`checks.rs:118-166`), the transition engine's role,
  `check_orphan`'s terminal-state test (`:698-704`), `check_location`'s dependence on
  an authored `Current` (`:784-808`), and the `/docstatus` and `/execute` cascade
  workflows that write status today.
- Existing tests broken: the orphan-rule tests (`orphan_brief_at_done_passes`,
  `orphan_brief_at_accepted_fails`, `orphan_design_at_current_passes`,
  `orphan_prd_with_active_roadmap_upstream_passes`) all assert on authored statuses,
  as do all 27 `finalize.rs` tests, which drive transitions.

### The two supporting defects, since any option here inherits them

**List-shaped `upstream:` collapses to the empty string.** `scalar_source_text`
(`frontmatter.rs:264-270`) returns `None` for sequence nodes, and `:235` applies
`.unwrap_or_default()`. Verified for all four YAML shapes:

| `upstream:` written as | `FieldValue.value` |
|---|---|
| `docs/prds/PRD-x.md` (plain scalar) | `"docs/prds/PRD-x.md"` |
| block sequence (`- a` / `- b`) | `""` |
| flow sequence (`[a, b]`) | `""` |
| block scalar (`\|` then two lines) | `"a\nb"` |

So `extract_upstreams`' doc comment at `lifecycle.rs:392-395` — "list-of-lines (the
`FieldValue` carries multi-line content when the YAML is a list)" — is **wrong for
real YAML lists**. Its multi-line handling (`:407-433`) only ever fires for a block
*scalar*, which no format documents. The consequences are three, in three different
components:

- lifecycle: the edge vanishes silently; the chain simply does not connect, no
  finding at all (confirmed: 0 lifecycle findings on a tree whose DESIGN has a
  block-sequence upstream naming two real PRDs).
- R6 `check_upstream_resolves` (`checks.rs:784-822`) reads `field.value` as one path
  and reports `[R6] upstream "" does not exist on disk` — a nonsense message.
- `finalize::walk_chain_mode` (`finalize.rs:393-396`) treats the empty value as
  "no upstream: chain complete" and **stops the finalization walk**, silently leaving
  every ancestor untransitioned. This is the write path, and it is the most damaging
  of the three.

**The `.first()` at `lifecycle.rs:542`** discards extra upstreams for the chain walk.
Its comment ("the additional upstreams are typically optional context, e.g. ROADMAP
parents") describes an intent that no format specifies and, given the parsing defect
above, cannot currently be exercised through a YAML list at all.

---

## Sources

- `crates/shirabe-validate/src/lifecycle.rs` — `:9-53` (code family + posture doc),
  `:82-114` (`Posture`), `:151-172` (`RootKind`, `Chain`), `:176-218` (`PassingState`),
  `:262-347` (`build_doc_index`, dir list at `:275-282`), `:396-436`
  (`extract_upstreams`), `:440-450` (`build_inverse_upstream`), `:460-561`
  (`discover_chains`; strategic-chain exclusion `:519-541`, `.first()` `:542`),
  `:574-608` (`infer_posture_from`), `:620-670` (`compute_passing_state`),
  `:686-768` (`check_orphan`), `:784-808` (`check_location`), `:831-925`
  (`run_lifecycle_check`), `:1020-1166` (`run_lifecycle_chain_check`; `.find()`
  `:1113-1115`), `:1263-2824` (50 tests).
- `crates/shirabe-validate/src/frontmatter.rs:229-243`, `:264-270`.
- `crates/shirabe-validate/src/checks.rs:85-110` (FC02), `:118-166` (FC03),
  `:764-822` (`is_cross_repo_reference`, `check_upstream_resolves`).
- `crates/shirabe-validate/src/doc.rs:28-39` (`Doc`), `:42-47` (`FieldValue`).
- `crates/shirabe-validate/src/validate.rs:44-67` (`Severity`, `PostureClass`),
  `:83-98` (`is_intrinsic_notice`), `:110-135` (`posture_class`,
  `effective_severity`), `:150-172` (`is_known_check_code`).
- `crates/shirabe-validate/src/advisory.rs:100-113` (`remedy_for`).
- `crates/shirabe-validate/src/finalize.rs:358-505` (`walk_chain_mode`), `:723-726`
  (`read_upstream`).
- `crates/shirabe-validate/src/lib.rs:55-57` (lifecycle re-exports).
- `docs/guides/lifecycle-posture.md:66-95` (classification table).
- `skills/execute/scripts/run-cascade.sh:297`; `skills/execute/SKILL.md:508-563`.
- Corpus: `public/tsuku/docs`, `public/koto/docs`, `public/niwa/docs`,
  `public/shirabe/docs`.
