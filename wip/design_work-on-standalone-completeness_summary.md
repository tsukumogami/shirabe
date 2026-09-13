# Design summary: work-on-standalone-completeness

Synthesized from `docs/prds/PRD-work-on-standalone-completeness.md` (In Progress).

## Technical problem

A single-issue run reaches "PR created, CI green" and stops. Two mechanisms are
missing, and they fail differently.

The document-chain cascade cannot be entered at all from a single-issue run.
`run-cascade.sh` takes a plan-shaped path as its only positional argument and
has no no-document mode, so there is nothing to hand it when an issue was filed
on its own. The neighbouring case — an anchor that resolves to no upstream chain
— already works and is pinned by a test.

The other finishing obligations exist as prose in reference files that the koto
template's per-state directives cite. They are delivered and skipped. What is
absent is anything that would catch the omission, so the fix is enforcement
altitude rather than relocation.

A constraint binds where any fix may be written: koto seeds a child session from
the compiled template and never loads `SKILL.md`, so an obligation written there
is unreachable by a child rather than merely skippable.

Separately, the single-issue skill is currently the documented way to run
multi-pr plans, which makes it responsible for deciding when a plan is finished
— the plan entry point's job, and one it already has machinery for.

## Decision drivers

- **Dependency direction.** `/execute` depends on `/work-on`'s template; the
  shared machinery must not invert that (PRD R5a).
- **Reachability.** Every new obligation must reach a materialized child, which
  means `work-on.md` and not `SKILL.md` (R10).
- **Cadence.** A plan run must still cascade once per plan (R13).
- **No second mechanism.** The root/child discriminator established by the
  separately-landing terminal-record fix is to be reused, not re-invented
  (R19b).
- **koto templates cannot compose.** Sharing is available only as a script or a
  prose reference, never a template fragment.
- **The repository's CLI rule.** Artifacts are authored by skills; `shirabe
  validate` is the correctness engine. No subcommand may render an artifact
  body.
- **Existing precedent for unavoidable duplication:** deliberate duplication
  guarded by a CI drift check, as `work-on.md` and `execute.md` already do for
  one CI-gate expression.
- **Two pull requests, ordered.** Completeness first, migration second (R22).

## Decomposition rationale

Six candidate questions were identified; two were merged. The multi-pr
migration's runtime shape (a third execution path, the single-issue refusal) and
its documentation surface (the routing-claim inventory, the supersession record)
are one body of work — the second pull request — and their sub-choices interact:
whether the single-issue entry point refuses a plan decides what the eval
scenarios must assert, which is part of the routing surface. Merging them avoids
the false independence cross-validation would otherwise have to catch.

That leaves five decisions, within the band the scaling heuristic proceeds on
normally.

## Constraint added mid-hop: the cascade script's steps can report ok having done nothing

Raised by the coordinator and verified here against the current branch. Five
sites in `skills/execute/scripts/run-cascade.sh`:

- Two awk rewrites (`> "$tmp" && mv "$tmp" "$path"`, around :531-579) under a
  single unconditional `add_step ... "ok"`. The awk exits 0 whether or not a
  rule fired, so a rewrite that matched nothing still reports ok.
- Three `git add ... 2>/dev/null || true` calls (:903-919, the `transition_design`,
  `transition_prd` and `transition_brief` arms), each followed by an
  unconditional `add_step ... "ok"`.

The `git add` sites are worse than a bare `|| true`: each is followed by an
unconditional `STAGED_FILES+=(...)`, so a failed add still records the path as
staged. That array gates both the commit block and the post-cascade
verification, so a cascade can report ok, believe it staged a document it did
not, and commit without it.

**Design position, stated rather than left implicit.** Hardening those five
sites is **not** in this feature's scope; it stays with the issue filed for it.
The reasoning is the same one applied to the terminal-record defect: a
pre-existing, independently testable defect should not be held behind a large
feature pull request, and nothing this feature establishes changes what the fix
should be.

**What that obliges this design to do instead.** Because the fix is not ours,
this feature's cascade states MUST NOT treat the script's step-level `ok` as
evidence that the chain moved. The evidence for a completed cascade is the
**observed post-state** — the anchor absent from disk, each upstream document at
its expected status, the finalization commit containing them — established
independently of what the script reported.

That is the better design regardless of who fixes the script, and it is the
same principle the feature exists to apply one level up: a report of success is
not evidence of success. Building the new caller on the script's self-report
would reproduce, inside the fix, the defect the fix is for.

### The evidence must read the commit, not the working tree

VERIFIED here, upgrading what reached this hop as an inference.

`run-cascade.sh`'s post-cascade verification (:1093-1100) calls `lifecycle_probe
"post"`, which runs `shirabe validate --lifecycle-chain "$seed" --mode=ready`
(:377-381). That validates a **path** — it reads the file from the working tree.
Nothing in the post-verify inspects the commit's contents.

So the blind spot is real and it compounds the staging defect exactly as
suspected: a document whose `git add` silently failed is still transitioned on
disk, so the tree-reading post-verify passes, while the document is absent from
the finalization commit and therefore from the merge. `git commit` takes no
pathspec — it publishes the index — and the bogus `STAGED_FILES` entry keeps the
commit block running, so nothing between the failed add and the merge notices.

**Consequence for this design's evidence definition.** A cascade is evidenced by:

1. the anchor absent from disk;
2. each upstream document at its expected status; and
3. **the finalization commit containing each of those documents, read from the
   commit rather than from the tree** — for example by listing the commit's own
   paths (`git diff-tree --no-commit-id --name-only -r <sha>`) and requiring each
   expected path to appear.

Item 3 is the one that matters and the one that is easy to get wrong. Checking
the tree for item 3 would inherit the same blind spot one level up and make this
feature's evidence exactly as trustworthy as the report it was written to stop
trusting.

Count correction carried from the same review: there are four unconditional
`STAGED_FILES+=` appends after a failing-tolerant `git add`, not three — the
fourth is the ROADMAP staging around :603-604 — so six silent no-op operations
in total. Line 684 is correctly conditional and is not one of them.

### Retention changes resume semantics, and the cascade states are the worst place for it

Carried from the terminal-record fix this chain rebases onto. Before retention, a
session that ended blocked was deleted, so a later run on the same issue fell
through to a fresh init. After it, the session is retained and still listed with
nothing marking it terminal, so a later run finds it, ticks it, gets `action:
done`, and reports the issue complete having done no work. That fix carries its
own repair — a state-read signal distinguishing a finished run from a resumable
one — and this chain uses that signal rather than inventing a second terminality
test, the same way it uses the root/child discriminator rather than re-deriving
one.

**Why this lands harder on the cascade states than on the states before them.**
Resumability is not uniform across a run. The implementation states are
re-enterable: re-running analysis or a test costs time and changes nothing that
was not already going to change. The cascade states are not. By the time one has
run, documents have been transitioned on disk, a finalization commit may exist,
and a push may have happened. Re-entering a partially-run cascade is not a retry
— it is a second walk over a chain whose nodes have already moved, which is how
a double transition or a second finalization commit gets made.

So this design must not treat "the session was retained" as "the run may be
resumed from wherever it stopped". For the cascade states specifically, the
question a resuming run has to answer first is not *where did I stop* but *what
already happened* — which is the same observed-post-state evidence this design
already requires, consulted on entry rather than only on exit.

That is a pleasing convergence rather than extra work: the evidence definition
written to avoid trusting the script's self-report is also what makes a retained
session safe to re-enter. A resuming run reads the anchor's presence, the
upstream statuses and the finalization commit's own paths, and from those three
facts knows whether the cascade ran, ran partially, or never started — without
consulting any record the run wrote about itself.

**Open until the other fix settles:** the exact signal for finished-versus-
resumable. This design commits to consuming it, not to its shape.
