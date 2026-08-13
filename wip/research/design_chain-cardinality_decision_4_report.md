# Decision 4 — The consumer-aware, multi-branch finalization walk

**Classification:** CRITICAL (mutation path; irreversible failure mode)
**Source PRD:** `docs/prds/PRD-chain-cardinality.md` — R12, R13, R14, R23, R24, Terms
**Subject module:** `crates/shirabe-validate/src/finalize.rs`

## Question

How should the finalization walk become consumer-aware (R12/R13) and multi-branch
(R14), given that it has no document index today and reads only the documents on
its single upstream path?

## Drivers

Six forces bound the answer. Four are measured; two are textual.

**D1 — The failure is invisible after the fact.** The whole-tree lifecycle check
does not report the damage this walk causes. Measured below (E3): after the walk
drives a shared BRIEF to `Done`, the still-`In Progress` PRD pointing at it
produces no finding at all. The only finding that surfaces is a dangling
`upstream:`, and only because a DESIGN's promotion *moves the file*. Prevention is
the only mechanism; detection does not exist for the status half of the damage.

**D2 — R14's acceptance criterion demands a per-node verdict.** "A document whose
two upstreams lead to different ancestors has both branches walked at
finalization: the ancestor R12 does not block is transitioned, and the one it
blocks is not." One run, two ancestors, two different outcomes. No all-or-nothing
pre-flight gate can produce that.

**D3 — R5 and the three-readers criterion forbid a second `upstream:` reader.**
R5: "Every reader of the `upstream:` field SHALL interpret the same written value
the same way." The AC: "the same set of two upstream paths is visible in all three
of: the resolution check's findings, the document's chain memberships, and the
finalization walk's node list." Whatever finalize does about R14, it must consume
the same parse the validator does, not a parallel one.

**D4 — R23 pins the existing test suite.** "The full existing test suite SHALL
pass unmodified"; the AC adds "no test modified or removed." Nine of the
twenty-two tests in `finalize.rs` run in a flat temp directory with no `docs/`
layout (`fresh_dir()`), where the validator's root derivation returns `None` and
no index can be built (E8). Any design that hard-fails on an underivable index
root breaks those nine.

**D5 — The index is cheap, and the cascade already pays for it twice.** Measured
(E7): the full whole-tree lifecycle run over this repository — 125 documents,
3.2 MB — completes in 44 ms; the current single-path dry-run walk takes 5 ms.
`skills/execute/scripts/run-cascade.sh` calls `validate --lifecycle-chain` before
finalize (`lifecycle_probe pre`, line 289) and again after (`post`), and
`run_lifecycle_chain_check` builds the same full index and the same
inverse-upstream graph both times (`lifecycle.rs:1091`, `:1108`). The cost
objection in the framing — "finalize currently opens only the documents on its
path" — is true of the subcommand in isolation and false of the workflow that
invokes it.

**D6 — A nonzero exit destroys the record of mutations already applied.** In
`Mode::Apply` the walk mutates as it goes. `run-cascade.sh:816` is explicit: on a
nonzero exit "the report's stdout is then absent, we cannot reconstruct the
successful prefix of the walk." Whatever R12 does on a block, it must not discard
the report of what the walk already did to the tree.

## Evidence

All experiments under `/home/dgazineu/.claude/jobs/0489d65c/tmp/repro/`, using the
existing release binary. Nothing in the repository was modified; `git status` is
clean.

Fixture corpus: `BRIEF-shared` (Accepted) ← `PRD-alpha` (In Progress) and
`PRD-beta` (In Progress); `PRD-alpha` ← `DESIGN-alpha` (Planned) ← `PLAN-alpha`
(Active, single-pr).

**E1 — The defect reproduces.** `finalize-chain docs/plans/PLAN-alpha.md
--dry-run` emits `transition_brief` → `Done` on `BRIEF-shared` while `PRD-beta`,
a non-terminal document outside the walk, still names it. Confirmed.

**E2 — The DESIGN's promotion move is itself a stranding operation.** With a
second live plan (`PLAN-beta`, Active) also pointing at `DESIGN-alpha`, applying
the walk against `PLAN-alpha` moves the DESIGN into `docs/designs/current/` and
leaves `PLAN-beta` with a dangling `upstream:`. This matters for the wording of
the guard: R12's "transition" must be read to include the DESIGN promotion,
because the promotion is a rename and the rename is what breaks the link. It also
fixes *when* the check runs — against the ancestor's pre-move path, before the
transition.

**E3 — The status half of the damage is invisible whole-tree.** After the E1
apply, `validate --lifecycle .` reports exactly one finding: an `L04` dangling
reference from the PLAN (which the cascade then deletes anyway). The
`PRD-beta` → `Done` BRIEF relationship produces nothing. In E2's two-plan variant
the only findings are two `L04`s, both about the moved DESIGN. Nothing anywhere
says a live chain lost its parent's status.

**E4 — The validator currently instructs the transition R12 must forbid.**
`validate --lifecycle-chain docs/plans/PLAN-alpha.md --mode=ready` reports
`[L01] BRIEF at status 'Accepted' (expected status 'Done' for single-pr at-merge
posture)` on the shared BRIEF. The check and R12 disagree about the same document
on the same corpus. Decision 3's conflict finding is the mechanism that resolves
this; Decision 4 must not assume the lifecycle check can be used as its oracle.

**E5 — The existing gate slot has inverted polarity.** `lifecycle_probe pre`
(`run-cascade.sh:302-308`) treats a *clean* validator run as the signal to skip
the cascade and a *failure* as the expected go-signal. Any blocking finding routed
through that probe is indistinguishable from the failure the cascade is waiting
for. Option (d) cannot reuse this slot; it needs a new gate with a new contract
and new bash.

**E6 — A sequence-valued `upstream:` is a silent no-op at this surface today.** A
PLAN whose `upstream:` is a two-entry block sequence walks to *one* node — the
PLAN itself — and exits 0 with a report that reads as a clean nothing-to-do. Not
an error; a silent success. R14's fix removes a false-clean path, not just a
truncated one.

**E7 — Cost.** Whole-tree lifecycle run (full index + inverse graph + chain
discovery + all checks) over 125 documents / 3,183,566 bytes: **44 ms**. Current
single-path dry-run walk: **5 ms**. The index is ~40 ms and is already built twice
per cascade.

**E8 — The index domain is narrower than finalize's input domain.**
`derive_chain_root` (`lifecycle.rs:1172`) matches the six known suffixes and
returns `None` otherwise; the CLI then reports `[L05] doc path '…' is not inside
docs/{briefs,prds,designs,designs/current,plans,roadmaps}/`. Nine `finalize.rs`
tests run outside that domain.

**E9 — There is a second, unguarded retirement path in the same script.** The
ROADMAP node is *handed back* by finalize (`NodeAction::RoadmapHandoff`) and
retired in bash: `handle_roadmap` (`run-cascade.sh:375`) rewrites the feature
status and, when all features read Done, `handle_roadmap_deletion` transitions the
ROADMAP to `Done` and `git rm`s it — guarded by "all features Done" and "all
issues closed", never by a referrer check. A BRIEF still pointing at that ROADMAP
is stranded exactly as in E2. See Open Risk 5.

**E10 — The terminal predicate already has a public home, and it is not
`transition_spec`.** PRD and Design are `Rule::MembershipOnly`
(`transition.rs:436`, `:448`) and carry no `terminal` field; only VISION,
Strategy, Roadmap, Brief, Comp and Plan do. The type-level answer lives in
`lifecycle::target_state_for` (`lifecycle.rs:227`), already `pub` and re-exported
from the crate root: Brief/PRD → `Done`, Design → `Current`, Plan/Roadmap →
`Deleted`. `Deleted` is the important one — a Plan or Roadmap that is *present on
disk* is by definition non-terminal and therefore always blocks, which is exactly
what the PRD's Terms block says ("for the document types whose lifecycle ends in
removal, reaching terminal means the document is gone").

## Options

### (a) Build a document index inside `finalize.rs`

Mirror `build_doc_index` + `build_inverse_upstream` in the mutation module.

- **Cost of the index:** ~40 ms (E7). Not the objection.
- **Real cost:** a second reader of `upstream:`. R1 and R4 change how that field
  parses; `extract_upstreams` (`lifecycle.rs:396`) is where the list-splitting,
  `- ` stripping, placeholder filtering, self-edge suppression and
  canonicalization live. A copy in `finalize.rs` must reproduce all five
  behaviours and stay reproduced. D3 says the three readers must agree; (a) makes
  that agreement a maintenance promise rather than a structural fact, in the same
  change whose whole premise is that three readers of this field currently
  disagree.
- **Concurrency / partial corpus:** identical to (b).

### (b) Call the validator's index through a narrow exported API — **recommended**

`finalize.rs` and `lifecycle.rs` are modules of one crate (`shirabe-validate`),
whose own doc comment says every export is internal-shaped and unstable.
`finalize.rs` already imports `coordination`, `frontmatter`, `gh` and
`transition`. Depending on `lifecycle` is not a new architectural direction; it is
the fourth intra-crate module import in a file that has three.

The coupling to avoid is `finalize` learning about *chains, postures and passing
states* — the check's judgment. R12 needs none of that. Note that `PRD-beta` in
the fixture belongs to no chain at all (chains are rooted at PLAN/ROADMAP and
nothing roots beneath it), yet it must block. **The R12 referrer predicate is
graph-level, not chain-level**: an inverse-upstream edge plus a per-type terminal
test. That is `build_inverse_upstream` and `target_state_for`, and nothing else.

Suggested exported surface — one struct, one function, no chain vocabulary:

```rust
pub struct Referrer { pub path: PathBuf, pub format: String, pub status: String, pub terminal: bool }
pub fn build_referrer_map(root: &Path) -> (BTreeMap<PathBuf, Vec<Referrer>>, Vec<ValidationError>)
```

- **Cost of the index:** ~40 ms, built once per walk, before the first mutation.
- **Correctness:** one snapshot for the whole walk, so every node's verdict is
  read from the same view of the corpus.
- **Coupling created:** `finalize` gains a dependency on `lifecycle`'s index
  construction. `lifecycle` gains no dependency on `finalize`. The dependency
  direction stays check → nothing, mutation → check, which is the right way round:
  the mutation asks the checker a question, not the reverse.

### (c) Lazy per-candidate referrer scan

Compute the referrer set on demand for each ancestor the walk reaches.

Strictly dominated. A referrer is discovered by *content* — some document's
`upstream:` names the candidate — so a targeted scan still reads every document in
the corpus. For a four-node chain that is three full reads instead of one, and
each candidate is judged against a different snapshot, so the walk can act on an
internally inconsistent view. It buys nothing: the saving would have to come from
locating referrers without reading them, which nothing in the format permits.

### (d) Report-only walk plus a separate gate

Leave `finalize.rs` a pure walker; have it emit intended actions (`--dry-run`
already does) and have a separate gate refuse before any mutation.

**The case for it is real and should be stated.** The blast radius is genuinely
smaller: not one line of the mutation module changes, so R23's "no document
changes its validation result" is satisfied trivially at that surface. The check
lives beside `build_inverse_upstream`, where the index already is, with no new
cross-module dependency. Half the mechanism — the read-only intent report —
already exists and is already tested. And a gate generalizes: the same gate could
run in CI over a proposed diff and catch the `git rm` case the PRD lists under
Known Limitations as permanently out of reach ("a document removed by any other
means … can still strand references").

It loses on four counts.

1. **D2.** The R14 acceptance criterion requires one branch transitioned and
   another refused in the same run. A gate that clears-or-refuses the whole walk
   cannot express that. A gate that instead emits a per-node verdict list which
   the walker then honours is not option (d) — it is option (b) with the index
   computed in a different process, and it pays (b)'s coupling anyway.
2. **A wider TOCTOU window.** Gate and apply are separate binary invocations
   against a mutable working tree. In-process, the snapshot-to-mutation gap is
   microseconds; across processes it is however long the caller takes.
3. **Bypass.** `finalize-chain` is a documented public subcommand
   (`docs/guides/multi-consumer-cli-contract.md`), and the repository's own
   CLAUDE.md instructs contributors that "lifecycle moves go through `shirabe
   transition` / `finalize-chain`." A guard living in `run-cascade.sh` protects
   the cascade and nothing else, while the binary the guide points people at
   remains willing to perform the unsafe transition on request. R12's subject is
   the walk; putting the guard outside the walk leaves the walk unguarded.
4. **It is not cheaper in the cascade.** E5: the existing gate slot's polarity is
   inverted, so (d) needs a new gate contract and new bash regardless.

**Keep its good half.** Two pieces of (d) are worth adopting inside (b): the
`--dry-run` report should show blocked nodes, so an author can see what will be
refused before applying anything; and the referrer query is worth exposing as a
callable surface for the bash roadmap handler (Open Risk 5).

### (e) Status quo — detect afterwards, do not prevent

Named for completeness because it is what the tool does today and what E3
measures the value of: for the status half of the damage, nothing detects it, ever.
The PRD's Goals sentence ("Nothing retires a parent that something still points
at") forecloses it.

## Recommendation

**Adopt (b): build the referrer map once per walk from the validator's existing
index, exposed through a narrow graph-level API, and have the walker make a
per-node decision. A block is a reported skip, not a walk-aborting failure.**

Nine specifics the design should carry.

**1. One reader of `upstream:`.** Replace `read_upstream` (`finalize.rs:723-726`,
which returns the raw scalar and treats it as one path) with `lifecycle`'s
`extract_upstreams`. This is what makes E6's silent no-op go away and what makes
the three-readers AC structural rather than coincidental.

**2. Multi-branch as a worklist with a visited set.** The single `loop` over
`current_doc_path` becomes a worklist seeded with the PLAN's upstreams. A shared
ancestor reachable through two branches must be visited **once** — otherwise it is
transitioned twice, and the second attempt either no-ops or is refused by the
transition engine depending on the type's rule, which would make the exit code
depend on traversal order.

**3. Traversal order follows written order, not path order.** R1 preserves
sequence entries "in the order written", which is content. Ordering branches by
path would reintroduce exactly the filename dependence R7 outlaws elsewhere.

**4. The carve-out is "documents this walk retires", not "documents this walk
visits".** This distinction is load-bearing and gives the design a property for
free: when a node is blocked, it stays non-terminal, so it remains a blocking
referrer for *its own* ancestors, and the block propagates upward with no
additional rule. If the carve-out were written as "visited", a blocked BRIEF would
stop blocking its ROADMAP and the walk would retire the parent of a document it
just refused to retire.

**5. The input PLAN counts as retired.** `finalize` reports the PLAN for deletion
and the cascade performs the `git rm` (`run-cascade.sh:829`). If the PLAN did not
count as retired it would block its own DESIGN and no chain would ever finalize.
This is the one place the guard trusts a caller it does not control: if the
cascade's `git rm` fails after the DESIGN moved, the PLAN survives with a dangling
link. The cascade already treats an rm failure as `ANY_FAILED` / partial, so the
condition is surfaced — worth an explicit sentence in the design rather than
leaving it implicit.

**6. Evaluate R12 before the transition, against the pre-move path.** Referrers
name the ancestor's current location; the DESIGN promotion changes it (E2).

**7. Terminality comes from `target_state_for`, with `Deleted` meaning "present ⇒
never terminal".** Do not read `transition_spec`'s `terminal` field: it is absent
for PRD and Design (E10). Put the predicate in one helper so a future addition to
the spec table cannot create a second source of truth.

**8. R13's report shape — additive, on the node.** The `Report` JSON has no
`schema_version`, and the CLI contract's rule is that additive changes keep the
major. Add to the blocked node:

```json
{ "path": "docs/briefs/BRIEF-shared.md", "format": "Brief", "action": "blocked",
  "target_status": "Done",
  "blocked_by": [ { "path": "docs/prds/PRD-beta.md", "format": "PRD", "status": "In Progress" } ],
  "note": "not transitioned: 1 non-terminal document still names it (docs/prds/PRD-beta.md, PRD at 'In Progress')" }
```

Three choices in that shape are deliberate. Referrer paths are **root-relative**,
matching the `file` field of every lifecycle finding, so the two surfaces name the
same document the same way — the design should note that finalize's own node
`path` values are whatever the `upstream:` field contained (relative or absolute)
and decide whether to normalize those too. Each referrer carries its **status**,
because the status is the actionable half: it tells the author whether to finish
that chain or whether a referrer that should have been terminal is not. And the
rendered `note` is present because `run-cascade.sh` reads `note` with `jq` for its
human-facing step detail and has no way to render a structured array.

**9. Blocked is a reported skip; the exit code stays 0.** Three reasons, in
descending strength: D2 requires per-node outcomes in one run, which a walk-aborting
error cannot express; D6 says a nonzero exit discards the report of mutations
already applied, and in apply mode that report is the only record of them; and the
precedent already exists — `NodeAction::Error` reports an unrecognized node and
still returns `Ok`, which `run-cascade.sh:791` documents in so many words
("finalize-chain reported it as a per-node error entry but still exited 0.
Surface it as a failed step and mark the cascade partial"). Add a `blocked)` arm
to that `case` alongside `error)`, setting `ANY_FAILED` and recording a failed
step; without it the block falls through to the `*)` arm and reports as "unknown
action", which is true but useless.

The consequence to accept and state: a consumer that only checks the exit code
sees a blocked finalization as success. That is the same contract `error` nodes
already have, and the alternative — nonzero — costs the audit trail of a
half-applied mutation, which is worse on a CRITICAL path. If the design wants a
scalar signal, the right one is a top-level `"blocked": <n>` count in the
envelope, not an exit code.

## Rejected alternatives

**(a) Own index in `finalize.rs`** — rejected on R5 and D3, not on cost. It
duplicates `extract_upstreams` at the exact moment R1 and R4 change what that
function does, in a change whose stated problem is that three readers of this
field disagree. The ~90 lines of directory walking are the small part; the
`upstream:` parse is the part that must not fork.

**(c) Lazy per-candidate scan** — rejected as strictly dominated. Same total read
set as the index, multiplied by the number of candidate ancestors, with a
per-candidate snapshot instead of a per-walk one. There is no version of it that
avoids reading the corpus, because referrers are found by content.

**(d) Report-only walk plus an external gate** — rejected, after a serious
hearing, on four counts: R14's acceptance criterion needs a per-node verdict that
an all-or-nothing gate cannot produce; a cross-process gate widens the
check-to-mutate window; a gate outside the binary leaves the documented public
subcommand willing to perform the unsafe transition; and the existing probe slot's
inverted polarity means it saves no bash. Its reporting half is adopted.

**(e) Status quo** — foreclosed by the PRD's Goals, and by E3: for the status half
of the damage there is no later detection to fall back on.

## Open risks

**1. The un-indexable corpus, and the one genuine safety compromise.** When
`derive_chain_root` returns `None` (E8), no referrer map exists and the guard
cannot run. Failing closed (exit 1) is the safe answer and breaks nine existing
tests, which R23 forbids. The recommendation is to fail *visibly* open: record a
node-level note on each transition node stating the guard did not run, keep exit 0,
and have the plan add a test asserting the note appears. This is the design's only
real safety hole; production invocation is always a `docs/plans/` path, but the
hole should be named rather than discovered. A cheap upgrade if the design wants
it: fall back to indexing the input document's own directory, which would let the
guard run in the flat-directory tests too — at the price of a second index domain
to explain.

**2. TOCTOU between snapshot and mutation.** The referrer map is read before the
transitions; another process could add a referrer in between. No locking exists
anywhere in this tool today (`run_transition` has none either), and git's index is
the real serialization point — two cascades in one work tree already collide there.
Recommend accepting this explicitly rather than introducing a lock on this path
alone.

**3. Conservatism can require a re-run, and the re-run reports as a failure.** Two
chains finalizing concurrently under one shared BRIEF: each sees the other's live
PLAN and blocks, so the BRIEF is retired only when the second chain finalizes
after the first has landed. The direction is safe. But the cascade will mark that
run `partial` for what is a correct and expected outcome. The design should decide
whether a blocked shared ancestor is surfaced as an author action item ("re-run
finalize after the sibling chain lands") or as a failure; reporting a correct
outcome as a failure is how a guard trains people to ignore it.

**4. Cross-repo referrers are invisible.** A document in another repository naming
this one is not in the index, so R12 cannot see it. `finalize` already walls off
cross-repo `upstream:` values on the *write* side (`NodeAction::Stop`); the
referrer side is the matching hole and is currently unstated. It belongs in Known
Limitations next to the `git rm` one.

**5. The ROADMAP is retired outside the guard (E9).** `handle_roadmap_deletion`
transitions and `git rm`s a ROADMAP from bash, guarded only by feature statuses
and issue closure. A BRIEF still pointing at it is stranded exactly as in E2.
Whether this is in scope turns on whether "the chain-finalization walk" in R12
means the subcommand or the cascade — finalize explicitly *hands the ROADMAP back*
to the caller, so the literal reading excludes it and the Goals sentence
("Nothing retires a parent that something still points at") includes it.
Recommendation: expose the referrer query as a small read-only surface the bash
handler can call before its deletion, which is a modest addition once the map
exists in (b), and is the one piece of option (d)'s shape that earns its place. If
the design excludes it, say so explicitly — silently leaving a second unguarded
retirement path in the same script is the outcome most likely to reproduce the
original damage.

**6. Decision 3's conflict finding and this guard must agree.** E4 shows the
lifecycle check currently *instructs* the transition R12 forbids. Once the
conflict finding exists, a shared ancestor under two chains in different phase
groups will be reported as conflicted by the checker and blocked by the walker.
Those are two different messages about one situation. The design should make the
walker's block message and the conflict finding legible as the same fact, or an
author will read them as two separate problems.
