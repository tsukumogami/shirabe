# Decision 3 — how the ROADMAP path reaches the produced PLAN's `upstream:`

PRD: `docs/prds/PRD-upstream-link-legality.md` (R11-R16.1, R18, R19, R22, R23).
Consumer inventory: `wip/research/prd_upstream-link-legality_phase2_consumers.md`
(spot-checked; its claims about `upstream.rs`, `finalize.rs`, `lifecycle.rs`,
`run-cascade.sh` and `validate-plan.sh` all hold — see the corrections and
additions below, which extend rather than contradict it).

All paths are relative to
`/home/dgazineu/dev/niwaw/tsuku/tsuku+upstream_link_legality-aa457090/public/shirabe/.claude/worktrees/upstream-link-legality`.

---

## Recommendation

**Option A — `/plan` gains `--upstream <path>`.** It is the only option that
holds R16 without an exception, reuses a flag contract five sibling skills
already ship, keeps the standalone and under-`/scope` PLAN byte-identical, and
puts the value inside `/plan`'s own Phase 7 hygiene gate rather than outside it.

R14 already names A as the mechanism, so this decision is a confirmation with
its costs priced rather than an open choice. The costs are real and are the
substance of this report: **`skills/plan/scripts/validate-plan.sh` cannot read a
sequence-valued `upstream:` and silently skips the entire upstream check when it
meets one**, and the same scalar assumption is baked into Phase 7's own
reference-hygiene step. Both must be fixed as part of this work or R14 lands a
silent regression in the CI gate that exists to catch exactly this.

---

## What `/plan` does with its input today

### `input_type` classification, verbatim

`skills/plan/SKILL.md` "Input Detection" (lines 233-246):

> From `$ARGUMENTS` (after stripping flags):
>
> 1. **Empty** -- ask the user what to plan (document path or topic)
> 2. **Path matching a known pattern** -- use it as the source document:
>    - `docs/designs/DESIGN-*.md` -- design doc (input_type: design)
>    - `docs/prds/PRD-*.md` -- PRD (input_type: prd)
>    - `docs/roadmaps/ROADMAP-*.md` -- roadmap (input_type: roadmap)
> 3. **Anything else** -- treat as a direct topic (input_type: topic). No upstream
>    document is required. [...]
>
> Store the detected `input_type` in the Phase 1 analysis artifact -- it gates
> branching behavior in Phases 1, 3, and downstream phases.

So **`/plan` does already have an input mode that accepts a roadmap** —
`input_type: roadmap` — and what it does with it is the whole problem. That mode
means "plan this roadmap", not "record this roadmap":

- **Decomposition** is fixed to feature-by-feature: one planning issue per
  roadmap *feature*, `simple` complexity, each carrying a `needs_label`
  (SKILL.md 126-136). No walking-skeleton/horizontal selection runs.
- **Execution mode** is forced multi-pr; single-pr is "Not available for roadmap
  input" (SKILL.md 470). A `/scope` chain that settled on single-pr cannot
  express itself.
- **Topic slug** comes from the source filename: "Topic is derived from the
  source document filename: `DESIGN-foo-bar.md` produces topic `foo-bar`,
  `ROADMAP-foo-bar.md` produces topic `foo-bar`" (SKILL.md 330-332). The PLAN
  therefore lands at `docs/plans/PLAN-<roadmap-slug>.md`.
- **Status gate** requires the roadmap at `Active`
  (`references/phases/phase-1-analysis.md:100-110`).
- **Phase 7.5** skips the upstream status transition entirely for roadmap input
  ("Roadmaps stay at 'Active' status ... No status change is needed",
  `phase-7-creation.md:342-344`).

### Flag parsing today

`/plan`'s Context Resolution parses `--auto`, `--interactive`, `--strategic`,
`--tactical`, `--walking-skeleton`, `--no-skeleton` and then: "Remove flags from
arguments before using the remainder as the document path" (SKILL.md 249-270).
**Every one of those is boolean.** `/plan` has no value-consuming flag today, so
Option A adds a residue rule `/plan` does not yet have — while `/brief`,
`/prd`, `/roadmap`, `/strategy`, `/comp` and `/scope` all already do
(`skills/brief/SKILL.md:130-147,157-165`, `skills/prd/SKILL.md:81-86`,
`skills/roadmap/SKILL.md:165`, `skills/strategy/SKILL.md:123-134,157-169`,
`skills/comp/SKILL.md:17,115`, `skills/scope/references/phases/phase-0-setup.md:11-47`).
The wording to copy is `/brief`'s, near-verbatim.

---

## Option A — `/plan --upstream <path>`

### Files that change, and how much

| File | Change | Size |
|---|---|---|
| `skills/plan/SKILL.md` | `argument-hint` frontmatter; a `--upstream <path>` bullet in "Parse Flags" with the residue rule, bare-flag rejection, at-most-once rule; an **Upstream** paragraph in Context Resolution mirroring `/brief` 157-165; amend line 56 ("Optional `upstream` links to the source document") to admit the second entry | ~30 lines added, 1 amended |
| `skills/plan/references/phases/phase-1-analysis.md` | carry the validated value into `wip/plan_<topic>_analysis.md` as a `## Upstream Path` section (the same name `/brief`'s context file uses); a ROADMAP-at-`Active` status check for the flag value, distinct from the positional's Handoff Validation table | ~15 lines |
| `skills/plan/references/phases/phase-7-creation.md` | both frontmatter templates (multi-pr 7.2b line 162, single-pr 7.1 line 248) gain the sequence branch; **step 7.4b's `head -20 \| grep -E '^upstream:'` must become an entry enumeration** (see "Hygiene re-check" below); Quality Checklist bullet | ~20 lines |
| `skills/plan/references/plan-format.md` | line 44-46 field description ("path to the upstream DESIGN doc") widened to name the ROADMAP second entry; the two-shapes paragraph at 55-62 already covers the mechanics and needs nothing | ~6 lines |
| `skills/plan/references/quality/plan-doc-structure.md` | lines 66 and 75, same widening | ~4 lines |
| `skills/plan/scripts/validate-plan.sh` | **enumerate sequence entries; accept `Active` for a `ROADMAP-` entry** | ~35 lines — the largest single change |
| `skills/plan/scripts/validate-plan_test.sh` | new cases for both written shapes and for the ROADMAP-at-Active pass | ~60 lines |
| `skills/scope/references/phases/phase-2-chain-orchestration.md` | the child-argument table (lines 174-183) gains `--upstream <roadmap-path>` on the `/plan` row; the `/brief` bullet at 167-171 reworded to "grounds the framing, records nothing" | ~10 lines |
| `skills/scope/references/phases/phase-1-discovery.md` | the pre-authoring notice sentence, committed twice (R22) | 2 lines |
| `skills/plan/evals/evals.json` | one new scenario: `--upstream <roadmap>` recorded, slug from the positional (the PRD's AC demands both halves) | ~20 lines |
| the five evals + two fixtures in R22/R23 | already scoped by the PRD | — |

Nothing in `crates/` changes for Option A. That is the headline: the Rust side
already handles the shape (below).

### Does the value survive Phase 7's hygiene re-check?

**Half of it does; half of it silently stops checking.** `phase-7-creation.md`
step 7.4b (lines 277-315) runs two greps:

```bash
git grep -nE 'wip/' -- 'docs/plans/PLAN-<topic>.md'
head -20 'docs/plans/PLAN-<topic>.md' | grep -E '^upstream:'
```

The first is shape-agnostic and keeps working: a `wip/` path in either entry
still hits. The second is scalar-shaped. Against

```yaml
upstream:
  - docs/designs/current/DESIGN-x.md
  - docs/roadmaps/ROADMAP-x.md
```

it prints the bare line `upstream:` and the instruction that follows it — "The
`upstream:` value must resolve. If `git ls-files <path>` returns empty ... the
upstream is broken" — has no value to resolve. The step passes without checking
either entry. It must be rewritten to enumerate entries (the `- ` lines
following the key, or the inline `[a, b]` form) and run `git ls-files` on each.

`head -20` is also worth widening: the sequence pushes `milestone:` and
`issue_count:` down, and a PLAN with a long `motivating_context:` block could
push the `upstream:` key itself past line 20.

### `validate-plan.sh` and a second upstream entry — **the likely breakage point**

Lines 133-181, and `get_field` at 61-72, which is the load-bearing part:

```bash
get_field() {
    local field="$1"
    awk -v field="$field" '
        $0 ~ "^" field ":" {
            sub("^" field ":[ \t]*", "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            sub(/[ \t]+$/, "")
            print
            exit
        }
    '
}
```

**It handles a scalar only.** It matches the first line beginning `upstream:`,
strips the key, prints whatever is left on that line, and exits. It never looks
at the following lines.

Verified empirically against the real script (throwaway git repo, real
`docs/designs/current/DESIGN-x.md` at `Accepted` and
`docs/roadmaps/ROADMAP-y.md` at `Active`, both committed):

| PLAN's `upstream:` | Result |
|---|---|
| block sequence `- DESIGN` / `- ROADMAP` | `ok: no upstream field — skipping upstream validation`, **exit 0** |
| inline flow `[DESIGN, ROADMAP]` | `error: upstream file does not exist: '[docs/designs/current/DESIGN-x.md, docs/roadmaps/ROADMAP-y.md]'`, exit 3 |
| scalar ROADMAP alone | `error: upstream file 'docs/roadmaps/ROADMAP-y.md' has status 'Active' — expected 'Accepted' or 'Planned'`, exit 3 |
| scalar DESIGN alone (control) | ok, exit 0 |

Three separate problems, in descending order of danger:

1. **The block sequence — the shape `plan-format.md` recommends — degrades to a
   silent skip, not a failure.** `upstream_val` comes back empty, the script
   takes the `[[ -z ]]` branch at line 137, announces "no upstream field", and
   exits 0. The existence check, the `git ls-files` tracking check and the
   status check are all skipped, and the PLAN reports as valid. This runs in CI:
   `.github/workflows/check-plan-docs.yml:23` calls the script on every changed
   PLAN. So under R14 as written, every `/scope`-produced PLAN would quietly
   stop being upstream-validated by the one CI gate that does it, and nothing
   would say so. This is the finding the design must act on.
2. **The inline flow form hard-fails** with a nonsense path. Both written shapes
   are documented as supported (`plan-format.md:55-62`), so the script disagrees
   with the format reference in both directions.
3. **A ROADMAP entry fails the status check even as a scalar**, because a
   ROADMAP is `Active` and the check admits only `Accepted` or `Planned`
   (lines 173-177). This is a *pre-existing* bug — `/plan`'s own SKILL.md
   documents producing a PLAN "for a roadmap-scoped slice" (SKILL.md 358-362,
   460-463) and such a PLAN fails this CI check today — but R14 is what makes it
   load-bearing.

**Required fix:** enumerate entries (block `- ` items and inline `[...]`), run
existence + `git ls-files` on each, and make the expected-status set
type-dependent — `Accepted|Planned` for a `DESIGN-`/`PRD-` entry, `Active` for a
`ROADMAP-` entry, unchecked for a cross-repo `owner/repo:path` value (which the
script does not handle today either: it would try to resolve it as a local
path). R21 forbids modifying existing tests in `cargo test --workspace`;
`validate-plan_test.sh` is a shell suite outside that, so adding cases there is
clean, and none of its six existing upstream cases (lines 68, 192-330) change
behaviour under the fix.

### Is a two-entry `upstream:` expressible and correctly handled?

**Yes, everywhere in `crates/`, with no code change.** Checked against all three
readers:

**Parse — `crates/shirabe-validate/src/upstream.rs`.** `field_entries` (line 82)
handles `FieldEntries::Sequence` by mapping one entry per item; `upstream_entries`
(69) is the single front door. Entries keep written order (test
`sequence_entries_keep_written_order`, line 172), are trimmed, blanks dropped,
placeholders skipped, cross-repo marked-not-removed. A scalar is never split
(test at 166). Two entries are exactly the supported case, and
`skills/plan/references/plan-format.md:55-62` already documents both written
shapes for PLAN specifically.

**Finalization walk — `finalize.rs::walk_chain_mode` (line 482).** Its own doc
comment: *"The walk follows **every** `upstream` entry, in written order,
visiting each document once."* Discovery is a BFS over `pending`, pushing one
node per entry (lines 525-545), with `by_key` deduplicating a shared ancestor
reached by two branches. `classify_node` (line 660) dispatches on filename
prefix: `Design` → `TransitionDesign`, `PRD`/`Brief` → `Transition*`,
**`Roadmap` → `NodeAction::RoadmapHandoff` with `target_status: None`**, and
`expands()` (line 648) excludes `RoadmapHandoff`, so the roadmap ends its branch
without being expanded or transitioned. The retirement guard never runs on it
(`target_status.is_none()` short-circuits to `Verdict::kept()`). A PLAN with
`[DESIGN, ROADMAP]` therefore produces exactly the report a BRIEF-named roadmap
produces today, one hop earlier.

**Lifecycle chain walk — `lifecycle.rs::discover_chains` (line 592).** Follows
`node.upstreams` in written order (pushed reversed onto a DFS frontier so they
pop in written order, lines 697-701), with a `expanded` set that treats a
reconvergent diamond as a diamond rather than a cycle. The stop at line 690 —
`if matches!(node.format.as_str(), "Brief" | "Roadmap") { continue; }` — fires
*after* the member push at 662, and the comment at 683-689 says so explicitly:
"Both stops happen after the push above, so the stopping node is itself a
member."

**The consequence that matters, and which the consumer inventory does not
draw:** under R14 the ROADMAP becomes a **member of the PLAN-rooted chain**,
which it never is today (today the walk stops at the BRIEF before reaching it).
That position is **already handled and already tested**:

- `lifecycle.rs::required_state` (line 917):
  `if member.role == ChainRole::Roadmap && member.path != chain.root { return PassingState::Status("Active"); }`
  with a 20-line doc comment (895-916) explaining precisely this hazard — a
  multi-pr PLAN at `Done` puts its chain at `MultiPrWorkCompleting`, whose
  ROADMAP cell in the passing-state table reads `Deleted`, so read straight off
  the table "one feature finishing beneath a ROADMAP demands the ROADMAP be
  deleted while the rest of its features are still running." The special case
  exists to stop exactly that.
- The tests that pin it (`lifecycle.rs:3074-3180`) build the shape through a
  **PRD → ROADMAP** edge — one of the three edges R5.2 forbids. The position
  they pin is identical to the one R14 creates; only the edge that reaches it
  differs. So R14 inherits a tested guard rather than opening a new hole, and
  `a_live_member_roadmap_under_a_completing_chain_is_not_required_absent` /
  `..._single_pr_chain_stays_active` keep passing unmodified (R21 satisfied).

The design should state this explicitly, because it is the non-obvious reason
R14 is safe: the roadmap-as-member repair predates this work and is what makes
moving the edge onto the PLAN a no-op for the lifecycle checker.

### Written order: DESIGN first, ROADMAP second

```yaml
upstream:
  - docs/designs/current/DESIGN-<topic>.md
  - docs/roadmaps/ROADMAP-<name>.md
```

Reasons, in order of weight:

1. **First-entry-is-the-primary-parent is the assumption every current consumer
   and every current reference makes.** `plan-format.md:44` calls `upstream`
   "path to the upstream DESIGN doc"; `validate-plan.sh`'s status check expects
   a DESIGN's `Accepted|Planned`; FC12 keys on the PLAN's design relationship.
   Any future reader fixed the cheap way — "take the first entry" — stays
   correct under DESIGN-first and breaks under ROADMAP-first.
2. **`plan-format.md` already blesses the sequence and says "Reach for the
   sequence when the document genuinely has more than one parent"** — the
   nearest tactical parent leads, the cross-chain crossing follows.
3. Order does not affect any correctness property established above: the
   finalization walk visits both regardless, `by_key` dedups, `discover_chains`
   records both, and the fixed `validate-plan.sh` must enumerate rather than
   index.

**One cosmetic cost, named so the design can accept it deliberately.** The
finalization report's node order is BFS by index, so with `[DESIGN, ROADMAP]`
the report reads `PLAN, DESIGN, ROADMAP, PRD, BRIEF`. `run-cascade.sh` sets each
step's `found_in` to *the previous node's effective path* (line 745 and the
comment at 752-757), which is a documented approximation, not a real parent
pointer. Two step records therefore misattribute: the roadmap's `found_in`
becomes the DESIGN's post-move path, and the PRD's becomes the ROADMAP's. The
roadmap one surfaces in the only diagnostic that prints `found_in` — the
`update_roadmap_feature` *skipped* message at `run-cascade.sh:403-407`, "…(from
$found_in)…" — so a maintainer debugging a missed feature match is sent to look
at the DESIGN. Writing ROADMAP-first would cut this from two misattributions to
one and fix the diagnostic, which is the only argument on that side; it loses to
reason 1 above. The honest fix, if the design wants one, is for `finalize-chain`
to emit a real per-node parent path instead of `run-cascade.sh` inferring one —
a contained change to `NodeEntry` plus the report consumer, but it alters the
report JSON and so risks R21's frozen-golden clause. Recommend: accept the
inaccuracy, note it in the design's Known Limitations.

**What does *not* break on ordering, contrary to the reasonable worry:**
`handle_roadmap` is deferred until after the entire node loop finishes
(`run-cascade.sh:832`), so `CASCADE_DESIGN_PATH` is always set before the
roadmap's `**Downstream:**` rewrite runs, whatever order the report arrives in.
The in-line comment at 799-801 ("the design precedes the roadmap in the chain")
becomes stale under R14 but is not relied upon; worth correcting in the same
change.

---

## Option B — `/scope` passes the roadmap positionally to `/plan`

**Fails, and fails hard.** The positional slot is the `input_type` classifier
(SKILL.md 233-246) and the slug source (330-332). Handing `/plan` a ROADMAP path
positionally does not add a link; it changes what `/plan` is planning. Five
distinct breakages, each independently fatal:

1. **`input_type` flips to `roadmap`**, and with it the decomposition strategy:
   one planning issue per roadmap *feature*, all `simple`, each with a
   `needs_label`. The chain's DESIGN is not decomposed at all. The PLAN plans
   the wrong document.
2. **The DESIGN is dropped from the invocation entirely.** `/scope`'s table
   currently hands `/plan` `docs/designs/DESIGN-<topic>.md`
   (`phase-2-chain-orchestration.md:180`); the positional slot holds one value,
   so the roadmap displaces it. The PLAN then records the ROADMAP as its only
   upstream — which is the very durable-to-working shape R14 exists to *place
   correctly*, and which fails `validate-plan.sh`'s status check (verified
   above, case C).
3. **The slug is wrong.** `PLAN-<roadmap-slug>.md`, not `PLAN-<topic>.md`. This
   breaks `/scope`'s own R20 structural file-existence check, which looks for
   `docs/plans/PLAN-<topic>.md` (`phase-2-chain-orchestration.md:225-231`), so
   the chain reports a returning child with no artifact — a
   PASS-with-no-artifact violation. `/scope` already wrote this argument down
   for `/brief` in "Why the slug and the upstream travel separately"
   (lines 195-207): handing `/brief` a ROADMAP positionally "would name the
   produced document after the ROADMAP … under a slug `/scope` never validated,
   and the R20 file-existence check … would then fail against the chain's own
   artifact." Every word transfers to `/plan`.
4. **Execution mode is forced multi-pr.** Single-pr is "Not available for
   roadmap input" (SKILL.md 470), so a chain that decided single-pr cannot
   produce its PLAN, and GitHub issues plus a milestone are created as a side
   effect.
5. **The DESIGN never transitions `Accepted → Planned`.** Phase 7.5 skips the
   transition for roadmap input (`phase-7-creation.md:342-344`), leaving the
   DESIGN at `Accepted` under an `Active` PLAN — an L01 posture failure on the
   chain the cascade later walks.

Option B is not a cheaper version of A; it is a different, wrong operation.

---

## Option C — `/plan` discovers the roadmap itself

`/plan` would scan `docs/roadmaps/*.md` for a feature whose `**Downstream:**`
line names this chain's slug — the reverse edge `handle_roadmap` already greps
for (`run-cascade.sh:401`).

**Rejected, and the PRD has already rejected it.** Its Decisions section names
"giving the cascade a reverse lookup that finds the roadmap whose feature names
this chain" as an alternative that "works but rests on a roadmap field that the
roadmap format does not actually document, so it would have to canonicalize that
field first," and Out of Scope excludes "Canonicalizing the roadmap's
per-feature downstream field." Confirmed independently:
`skills/roadmap/references/roadmap-format.md:138-150` specifies `**Needs:**`,
`**Dependencies:**` and `**Status:**` for a feature entry and nothing else, and
`references/issues-table.md:196-200` says the `Downstream Artifact` column "is
dropped during migration." The field the cascade both reads and writes is
undocumented in the format that owns it.

Two further objections beyond the PRD's:

- **The edge does not exist yet at plan time.** The cascade *writes*
  `**Downstream:**` to the post-move DESIGN basename when the work completes
  (`run-cascade.sh:426-450`). At the moment `/plan` runs, a feature entry may
  name the PRD, the DESIGN, or nothing. Discovery would be matching against a
  field whose value is set later by the consumer that would read it.
- **It makes `/plan` guess.** A slug collision across two roadmaps, or a feature
  whose downstream text merely contains the slug as a substring, silently
  attaches the wrong roadmap to a committed frontmatter field. Option A's value
  is author-supplied and validated; C's is inferred from prose.

C also drags `/plan` into directory scanning it does nothing like today, for a
value the invoking parent already holds in `consumed_upstream:`.

---

## Option D — `/scope` writes the roadmap in after `/plan` returns

**Rejected.** Note first that D does not straightforwardly violate R16's *letter*
— R16 forbids a parent suppressing or rewriting "what a child records **at the
moment the child records it**", and D writes afterwards. It fails on four other
grounds, the first of which is decisive:

1. **The PLAN is explicitly outside `/scope`'s closed write-target set.**
   `skills/scope/references/phases/phase-3-exit-finalization.md` ("Closed
   Write-Target Set"): "Phase 3's filesystem write surface is confined to the
   enumerated set. **Writes outside this set fail the R9 hard-finalization
   check.**" The set is Decision Records, force-materialized
   `{BRIEF,PRD,DESIGN}-<topic>.md` on abandonment, and `wip/scope_<topic>_*`.
   And explicitly: "The PLAN artifact at `docs/plans/PLAN-<topic>.md` is
   produced by `/plan` (not directly by Phase 3); Phase 3's full-run exit only
   updates the state file's `exit_artifacts:` list to reference the PLAN, **it
   does not write the PLAN itself**." D requires widening a set the skill
   describes as closed and enumerable and gates its own finalization on.
2. **R16.1's carve-out does not extend to it.** The one existing parent-rewrites-
   a-child's-`upstream:` act is the consolidation absorb
   (`phase-2-chain-orchestration.md:487-499`), and R16.1 justifies it narrowly:
   it "rewrites a surviving PRD's `upstream:` after both children have returned
   and one document has been removed, which is a statement about the corpus
   after a deletion rather than an override of what a child recorded." D has no
   deletion behind it. It is a parent adding a fact the child could have
   recorded itself, which is the shape R16 exists to prevent.
3. **It breaks the hand-back contract's read-only posture.**
   `references/parent-skill-pattern.md`'s Observability Surface limits the
   parent to durable-artifact path polling, `git log` since `pre_invocation_sha`,
   and its own `wip/`; the Hand-Back Contract's three steps are R20 existence,
   a frontmatter `status:` read, and a blob-hash capture. All reads. `/scope`
   already states in its own Phase 2 that R14 child-isolation is preserved
   because "`--upstream` is part of that surface rather than an addition to it"
   (lines 211-217) — the sentence is written about `/brief` and reads as an
   argument for A.
4. **The added entry escapes every check that would have seen it.** `/plan`'s
   Phase 7.4b hygiene step and `validate-plan.sh` both run *inside* `/plan`,
   before Phase 7 finishes. An entry appended by the parent afterwards is
   committed having passed neither — including the `wip/`-path rejection and
   the `git ls-files` tracking check that exist precisely for author-supplied
   upstream values.

D also produces a PLAN that differs by whether a parent ran, which is the
practical property R16's first sentence protects: the artifact is no longer
reproducible by running the child yourself.

---

## Sub-question: what happens to the roadmap link when a run bails before `/plan`

**First, a correction to the framing.** Under Option A the hand-off does not
*move* from `/brief` to `/plan`; it is *duplicated*. R13 keeps `/brief`'s
roadmap input mode and its `--upstream` flag "unchanged as *inputs* — the
roadmap is still read, and still grounds the framing conversation" — only the
recorded field goes. R22's disposition for `skills/brief/evals/evals.json`
confirms it: `upstream-roadmap-grounding` is "rewritten: the roadmap grounds the
framing and no field is written". So `/scope` Phase 2 still passes
`--upstream <roadmap>` to `/brief` for framing, and passes it again to `/plan`
for the record. Two hand-offs, one first child and one last.

**What a bail costs, precisely.** `/scope` has three exit paths
(`phase-3-exit-finalization.md`): `full-run` (reached `/plan`),
`re-evaluation` (ended at a settled-upstream boundary, produces a Decision
Record), and `abandonment-forced` (force-materializes the most-recently-running
child's intermediate as a Draft `BRIEF`/`PRD`/`DESIGN`/`PLAN`). On the two
non-`full-run` paths where `/plan` never ran:

- **The framing is not lost.** It happened at `/brief`, which read the roadmap
  and, under R12, announced that it read it and omitted the field.
- **The durable record of *which roadmap* is lost — and that is R13's intended
  outcome, not a new hole.** After R13, no durable tactical artifact may name a
  ROADMAP. A chain that produces no PLAN has no legal node to carry the link.
  `consumed_upstream:` lives in `wip/scope_<topic>_state.md`, which Phase 4
  deletes, and Phase 3's PR-body record covers `chain_ran:`, `chain_skipped:`
  and `consolidation_judgments:` — **not `consumed_upstream:`**.
- **Nothing downstream breaks.** R19's consumer is the cascade, and the cascade
  only ever runs from a PLAN (`run-cascade.sh` takes `$PLAN_DOC`;
  `finalize-chain` requires a `Plan`-format input,
  `finalize.rs:487-498`). No PLAN means no cascade means nothing needed the
  link. The roadmap feature correctly stays at `**Status:** Planned`, because
  the feature was in fact not delivered.
- **Compare against today:** a bail after `/brief` currently leaves the roadmap
  recorded on the BRIEF — one of the eight illegal edges this work exists to
  outlaw. A bail *before* `/brief` loses it today too. So A trades an illegal
  record for no record on the bail paths, which is the trade R13 already made.

**One gap worth closing in the design, cheaply.** R12 obliges the producing
skill to announce an omitted-but-real upstream. On a bail, the *chain* consumed
a roadmap that no artifact records, and nothing currently says so in a durable
place. Two low-cost options: add `consumed_upstream:` to the artifact record
Phase 3 writes into the PR body (its stated purpose is "the record of which
artifacts were produced ... has to leave `wip/` before" Phase 4 deletes the
state file), and/or have the `re-evaluation` and `abandonment-forced` exits
state in their run output that the chain consumed roadmap X and no produced
artifact records it. The first is the more durable and costs one bullet in
`phase-3-exit-finalization.md`'s "Durable record of what the chain produced".

**Sequencing note.** Under A the roadmap value must survive from `/scope` Phase
0 (`consumed_upstream:`) through three child invocations to the `/plan` call at
the end of Phase 2. It already does — the state file persists across the whole
chain and is exactly what `consumed_upstream:` is for — but the `/scope` Phase 2
prose currently mentions the value only in the `/brief` bullet, so the `/plan`
row of the child-argument table has to name it or the last hand-off has no
written home.
