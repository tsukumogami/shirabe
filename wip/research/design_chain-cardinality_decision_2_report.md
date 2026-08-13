# Decision 2 — Per-document chain evaluation and finding identity

## Question

How should per-document chain evaluation be restructured across both validator
modes, and what constitutes finding identity for deduplication?

## Drivers

R6 (evaluate every chain containing a document; identity is the triple of check
code, document path, required status set), R7 (findings do not depend on
filenames), R8 (both modes report the same findings for the same document after
dedupe), R11 (a document under intersecting required sets passes anywhere in the
intersection), R23 (no corpus finding changes; the existing suite passes with no
test modified), R24 (no new field, artifact type, or status).

Two further drivers come from the code rather than the requirements. The two
modes today carry two textually identical emission loops, which is how they
drifted apart on L07 in the first place; any structure that leaves two loops in
place leaves that drift mechanism in place. And the emitted message is currently
the only carrier of a finding's identity, which is precisely why the existing
`errors.dedup()` at `lifecycle.rs:923` does nothing useful.

## Evidence gathered

Everything below was reproduced against the built binary
(`target/debug/shirabe`) on synthetic corpora under
`/home/dgazineu/.claude/jobs/0489d65c/tmp/`. Nothing in the repository was
modified.

**The filename lottery is worth four findings, not a nuance.** Corpus: one
BRIEF/PRD/DESIGN spine with two PLAN roots beneath the DESIGN — `PLAN-alpha`
(multi-pr, Active) and `PLAN-zeta` (multi-pr, Done). Whole-tree reports four L01
findings. Chain-targeted on the shared PRD reports **zero** and exits 0, because
`.find()` at `lifecycle.rs:1113` picks `PLAN-alpha`'s in-flight chain. Renaming
`PLAN-alpha.md` to `PLAN-zzz.md` — no content change anywhere — flips the same
invocation to four findings and exit 2. That single rename is simultaneously the
R7 violation and the R8 violation; they are one defect with two requirement
names.

**The posture-name duplicate.** Same spine, with `PLAN-alpha` changed to
single-pr at Done. Whole-tree emits eight findings, including two on the BRIEF,
two on the PRD, and two on the DESIGN, each pair differing only in the trailing
posture name (`multi-pr work-completing` versus `single-pr at-merge`) while
naming the same expected status. `errors.dedup()` cannot collapse them because
the message differs.

**A ROADMAP is already a multi-chain document in the ordinary corpus shape.**
This is not in the PRD and it changes what "latent" means. `discover_chains`
pushes a node into `members` *before* it breaks on `Brief | Roadmap`
(`lifecycle.rs:511-541`), so a ROADMAP reached by walking up from a PLAN is a
member of that PLAN's chain — and it also roots a one-member chain of its own.
With a ROADMAP at Done above a live single-pr PLAN chain, whole-tree emits:

```
[L01] ROADMAP at status 'Done' (expected DELETED (absent from tree) for multi-pr work-completing posture)
[L01] ROADMAP at status 'Done' (expected status 'Active' for single-pr at-merge posture)
```

Two findings, disjoint required sets, on a shape that needs no multi-valued
`upstream:` and no two plan roots. Chain-targeted on that ROADMAP reports only
the second. The root cause is one asymmetric cell in `compute_passing_state`:
`(Roadmap, SinglePrAtMerge) => Status("Active")` while `(Roadmap,
MultiPrWorkCompleting)` and `(Roadmap, MultiPrAtMerge)` are both `Deleted`
(`lifecycle.rs:637,645,668`). The PRD's Terms block says "within a group the
required sets agree"; that is true of every cell in the table except this one.

**The chain-targeted mode's scope rule is already incoherent.** It reports
corpus-wide L03/L04/L05 unconditionally (`errors` from `build_doc_index` plus
`chain_errors` from every chain, `lifecycle.rs:1091,1109-1110`), chain-scoped
L01/L06, target-only L02, and never L07 — `check_location` is called only from
`run_lifecycle_check` (`lifecycle.rs:910-914`). Demonstrated: adding an unrelated
`PLAN-ghost` with a missing upstream makes chain-targeted on the shared PRD
report that unrelated plan's L04 while still reporting nothing about the PRD's
own two-chain obligations. So a chain-member DESIGN sitting in the wrong
directory is an R8 violation today that has nothing to do with chain selection,
and any fix that only touches chain selection leaves it standing.

**R23 exposure is narrow.** No L-code appears in the golden parity baselines
under `crates/shirabe/tests/fixtures/golden/expected/` — the parity gate runs
per-file `validate <path>`, not `--lifecycle`. Exactly one existing test couples
to L01 message text beyond the check code:
`crates/shirabe-validate/src/lifecycle.rs:2178` asserts every L01 message
contains `single-pr at-merge`. Its fixture is single-chain. `run-cascade.sh` logs
and summarises findings but never matches on posture text. This repository's own
corpus is clean under whole-tree draft except one L02, has no `docs/roadmaps/`
entries, and has one plan, so it exercises none of the fan-out shapes; the R23
corpus check has to come from the sibling repositories.

## Options

### (a) A member-keyed obligation map consumed by one emitter

Build, once, from the chains `discover_chains` already returns:

```rust
type Obligations = BTreeMap<PathBuf, BTreeMap<PassingState, ObligationSources>>;

struct ObligationSources {
    postures: BTreeSet<Posture>,   // effective postures, after the ready re-target
    roots:    BTreeSet<PathBuf>,   // chain roots imposing this required set
}
```

For each chain, apply the ready-posture re-target once (as today), then for each
member insert `member.path -> compute_passing_state(role, effective) ->
{effective posture, chain root}`. `PassingState` and `Posture` need `Ord`
derived; nothing else about the existing types changes, and `discover_chains`
is untouched.

Emission becomes a single function over a *scope set* of document paths. For each
document in scope: emit one L01 per required-set key the document's status fails;
emit L02 when the document has no obligations at all; emit L06 per unticked AC on
a single-pr PLAN document; emit L07 on a DESIGN. The two modes differ only in the
scope set — whole-tree passes every indexed document, chain-targeted passes the
members of every chain containing the target. Corpus-integrity codes (L03, L04,
L05) stay whole-corpus in both modes, which is what both modes already do.

Finding identity is then literally the map key. R6's triple is `(code, path,
required set)`; the accumulator is keyed by `(path, PassingState)` per code, so a
duplicate cannot be constructed, let alone survive to a post-hoc `dedup()`. R11
falls out of "one finding per failed key": a document passes exactly when its
status satisfies every key, which is set intersection. R8 holds for the target
document because both modes read the same obligation map through the same
emitter, and the target is in scope in both — the mode no longer influences what
is *said* about a document, only which documents are *spoken about*. R7 holds
because the obligation map is a union over chains, unions are order-free, and no
L01 message interpolates a root path.

Cost: roughly 120 lines net, mostly deletion — the two emission loops
(`lifecycle.rs:851-895` and `1117-1146`) collapse into one. One behavior change
beyond those the PRD demands: chain-targeted gains L07 on in-scope documents,
which R8 requires anyway.

### (b) Keep the chains-outer loops, canonicalize and dedupe afterwards

Change `.find()` to `.filter()`, keep both loops, drop the posture name from the
message so textual dedupe collapses the duplicates, keep `errors.dedup()`.

This is the smallest diff by a wide margin — perhaps fifteen lines — and it does
satisfy R6, R7 and R11 the day it lands. Its problem is that identity becomes
message equality, which is the exact mechanism that failed here: the current
`dedup()` was written believing message equality tracked finding identity, and
the posture interpolation quietly falsified it. Restoring that arrangement means
R6 holds only while the message text happens to encode the required set and
nothing else; the next person who adds a hint, a chain root, or a line number to
an L01 message silently reopens the defect with no test able to name what broke.
The alternative — carrying structured identity fields on `ValidationError` so the
dedupe can key on them — means touching every producer in the crate and the
report layer, at which point (b) costs more than (a) and still leaves two
emission loops. And R8 needs separate work regardless, because the L07 asymmetry
lives in the mode difference rather than in chain selection.

### (c) Chain-targeted calls the whole-tree evaluation and filters

`run_lifecycle_chain_check` derives the root, calls `run_lifecycle_check`, and
filters the result to the target's chain. R8 becomes true by identity of the
producing code, which is the strongest possible form of the guarantee, and the
duplicated loop disappears.

It breaks on the filter. To filter to "the target's chain" you still need
`discover_chains` and a membership set, so the chains get computed twice. Worse,
filtering by path silently drops findings the mode reports today: the unrelated
`PLAN-ghost` L04 above would vanish, as would every L03 and L05 outside the
closure. That is a corpus-visible regression against R23 on the one mode the
cascade actually runs. Rescuing it means filtering by code — corpus-integrity
codes pass through, document codes get path-filtered — which is exactly option
(a)'s scope rule, arrived at by a worse route, with the whole-tree evaluation
computed and then mostly thrown away. On a large corpus the cascade would pay
full whole-tree cost, including an L06 body re-parse for every single-pr PLAN in
the repository, on every pre- and post-cascade probe.

### (d) Reachability instead of per-root walks

Build the membership map by inverting the graph and computing, for each document,
the set of roots that reach it — then attach obligations to that set. This is not
the edge-attached posture the PRD excludes; posture stays a property of the root.
It produces the same obligation map as (a) by a different traversal.

Rejected on R23 risk rather than on merit. The current walk carries three
behaviors that are easy to lose in a rewrite: it stops at `Brief` and `Roadmap`
but records the stopping node as a member, it emits L03 with the cycle path in
walk order, and it emits L04 attributed to the *root* rather than to the
referring document (`lifecycle.rs:499-506`). Those are observable in existing
tests and in the corpus. Reusing the existing walk and building the map from its
output keeps every one of them bit-identical for free.

## Recommendation

Option (a), with the scope rule stated explicitly as part of the decision:

> **Obligations are global; scope selects which documents are reported.** A
> document's obligations are the union over every chain containing it,
> independent of mode. The mode chooses only the set of documents evaluated:
> whole-tree evaluates every indexed document, chain-targeted evaluates the
> members of every chain containing the target. Corpus-integrity findings (L03,
> L04, L05) remain whole-corpus in both modes.

Two sub-decisions that the scope rule leaves open, and my answers:

*Shallow closure, not transitive.* The chain-targeted scope is the union of
members of chains containing the target, and it does not then expand to chains
containing *those* members. In the reproduction corpus, targeting `PLAN-alpha`
reports on the BRIEF, PRD and DESIGN — including their `PLAN-zeta`-derived
obligations, which is what R8 requires — but not on `PLAN-zeta` itself. A
transitive closure would, in a connected corpus, make the chain-targeted mode
indistinguishable from whole-tree, which defeats the mode's stated purpose of not
surfacing unrelated drift. The sibling plan's own status is the sibling's
business; the shared parent's obligation is not.

*Parity is per-document, not whole-output.* R8's acceptance criterion says "the
same findings as the whole-tree check reports **for that document**", and that is
the only reading under which the chain-targeted mode can continue to exist. The
design should write it that way so a later reviewer does not read R8 as demanding
identical output.

### Message wording

The constraint is that a finding can no longer name a single posture once its
required set arises from several. The wording that satisfies R6, R7 and R23
together is to keep today's message verbatim in the one-posture case and
pluralise in the many-posture case:

```
PRD at status 'Accepted' (expected status 'Done' for multi-pr work-completing posture)
PRD at status 'Accepted' (expected status 'Done' for multi-pr work-completing and single-pr at-merge postures)
```

The postures are rendered from the `BTreeSet<Posture>` in `Posture` declaration
order — never in chain-discovery or path order, which is what would reintroduce
filename dependence — joined with commas and a final "and", with the trailing
noun agreeing in number. One helper, roughly:

```rust
fn describe_postures(ps: &BTreeSet<Posture>) -> String
```

This keeps every single-chain corpus and every existing test byte-identical,
including `lifecycle.rs:2178`, whose fixture has one chain. It changes output only
where two chains impose the same required set on one document, which is the case
that is broken today.

Two wordings I considered and rejected. Naming the phase group instead of the
posture — "for a completing chain" — reads better and is inherently
multi-chain-safe, but it breaks the existing test (R23 forbids modifying it) and
discards what the module documentation says the posture name is *for*: telling
the author which gate did not run (`lifecycle.rs:17-18`). Naming the chain roots
instead of the postures — "for chains rooted at docs/plans/PLAN-zeta.md" — is the
most informative option and directly contradicts R7, since renaming a plan would
then alter a finding on a different document.

That last point needs saying out loud somewhere in the design, because R9
*requires* the conflict finding to name each conflicting chain, and chains are
identified by root path. So the conflict finding is deliberately rename-sensitive
in a way L01 must not be. R7's escape clause — "the path a finding names may
change with the rename" — has to be read as covering root paths named inside
another document's finding, or R7 and R9 contradict each other. Better to state
the reading than to let a reviewer discover the tension.

### What this hands Decision 3

The obligation map is the substrate for the conflict requirements, and carrying
`roots` in `ObligationSources` costs nothing now and supplies exactly what R9
needs. On one document's map: the conflict condition is two or more keys whose
status sets have empty intersection; R9's message reads off the keys and their
roots; R10's suppression is a filter on the same emission loop, skipping the L01
for keys that participate in a reported conflict. R11 needs no code at all — it is
the emission rule itself.

## Rejected alternatives

Summarised above in full: (b) post-hoc canonicalisation and dedupe, rejected
because it restores identity-by-message, the exact mechanism that already failed,
and does not address the L07 mode asymmetry that R8 also covers; (c)
chain-targeted delegating to whole-tree with a filter, rejected because a
path-filter drops corpus-integrity findings the mode reports today (an R23
regression, demonstrated with `PLAN-ghost`) and a code-aware filter is option (a)
reached by a costlier route; (d) reachability-based membership, rejected on R23
risk because the existing walk's stop rule, cycle-path ordering, and L04
attribution are all observable and all free if the walk is reused.

Also considered and set aside: fixing the `(Roadmap, SinglePrAtMerge) =>
Status("Active")` cell to `Deleted` so the completing phase group becomes uniform
and the ROADMAP's two findings collapse into one. It is very probably the right
long-term shape, and it is a corpus-visible output change — two findings become
one — so it fails R23 and belongs in its own issue with its own evidence.

## Open risks

**The ROADMAP shape makes the conflict finding fire on ordinary corpora.** A
ROADMAP at Done above a live single-pr chain already carries two disjoint
required sets, so a naive disjointness test for R9 will emit a conflict finding
on a shape that has nothing to do with multi-valued upstreams. The PRD's
Out-of-Scope section says the conflict finding firing often in practice is the
signal to revisit edge-attached posture; this shape could supply that signal on
day one for the wrong reason. Decision 3 should decide whether a document that is
its own chain's root and another chain's member counts as two chains for conflict
purposes, or whether the root's own obligation wins. This is the single largest
open question Decision 2 surfaces and it is not mine to close.

**Chain-targeted output grows on fan-out corpora, and the cascade gates on it.**
Global obligations mean a cascade probe on one plan now sees the shared parent's
obligations from a sibling chain, so a cascade that passes today can fail after
this change. That is correct — it is the same shared-parent hazard R12 exists to
block — but it is a live workflow behavior change, and the R23 corpus check has
to be run in chain-targeted mode per document, not only whole-tree per
repository, or it will not see this at all. The acceptance criterion as written
("validating every repository ... produces identical output in both draft and
ready modes") reads as whole-tree only.

**One existing test pins the message.** `lifecycle.rs:2178` asserts the posture
name appears in every L01 message. The recommended wording keeps it passing, but
it means the one-posture message text is now effectively frozen by R23; any
design that wants to restructure the L01 message has to renegotiate R23 first.

**`PassingState` gains `Ord`.** Using it as a map key fixes the emission order of
multiple findings on one document to the enum's declaration order. That is
deterministic and rename-independent, but it is a new ordering contract on a
public type; the final sort by (file, code, message) still runs, so the observable
order is unchanged.
