# Decision 3: state/substrate + conformance binding

How `/execute` (an implementation-altitude single-agent parent conforming to
parent-skill pattern v1) persists state, how its parent-skill state file
relates to the on-PR coordination state and koto session state, how the three
pattern-level exit paths bind to EXECUTION outcomes, and how the resume ladder
is filled for an execution chain rather than an authoring chain.

The decision is constrained by three settled-upstream facts:

1. `/execute` conforms to parent-skill pattern v1 — it MUST carry the 5-field
   minimum state file, the three named exit paths, the 9-row resume ladder, and
   the R9 hard-finalization check.
2. The ephemeral-home model: for `single-pr`, the single PR is the ephemeral
   home for the PLAN doc + wip; for `coordinated`, the coordination PR is the
   home. `/execute` holds ephemeral artifacts there and cleans them before the
   home merges.
3. I-6 cross-branch-resume MUST hold for `/execute`. The v1 reference substrate
   (`wip-yaml-md`) explicitly does NOT satisfy I-6 (state lives on the
   originating feature branch; resume on a different branch starts fresh). An
   execution chain that spans multiple per-repo branches and multiple sessions
   cannot tolerate that gap — this is the central tension Decision 3 resolves.

## Substrate options

### Option (a) — `wip-yaml-md`, like `/charter` and `/scope`

State at `wip/execute_<topic>_state.md` as YAML-in-`.md`, the v1 reference
serialization. This is the cheapest conformance: the 5-field minimum, the
chain-tracking triad, `child_snapshots:`, and `parent_orchestration:` all carry
over verbatim from `/scope`'s schema, and the R9 check is already specified
against this serialization.

The fatal problem: `wip-yaml-md` does NOT satisfy I-6 (named explicitly in
`parent-skill-pattern.md`, line 220-222 and lines 68-76). State lives on the
branch where the run originated; resume on another branch starts a fresh chain.
For authoring parents (`/scope`, `/charter`) this is tolerable — the whole
authoring chain runs on one docs branch in one or a few sittings. For
`/execute` it is disqualifying: an execution chain's defining shape is that work
lands across MULTIPLE per-repo implementation branches (coordinated mode) or
proceeds across multiple sessions on a long-running single PR. The author who
resumes `/execute` is frequently NOT on the branch the run started on. A
single-branch wip file would silently fork the chain on every cross-branch
resume — the exact failure I-6 names. Option (a) fails the load-bearing
constraint and is rejected as the sole substrate.

### Option (b) — durable state ON the home PR; wip-yaml-md only for in-session scratch

Bind `storage_substrate` to the **ephemeral home PR itself** as the durable
resume surface, with `wip-yaml-md` retained only as in-session scratch that is
reconstructable from the PR.

- **Coordinated mode**: the coordination PR already carries durable state by
  contract (`coordination-strategy.md` Lifecycle step 2: "State lives on the
  coordination branch/PR itself, so an interrupted effort reconnects from
  durable state — no session file is the source of truth"). The PR-Index and
  the fenced `merge-order` DAG block ARE the execution chain's durable state.
  This is a PR-body substrate, reachable from any branch via `gh pr view` — it
  satisfies I-6 by construction because the GitHub PR is not branch-local.
- **Single-pr mode**: the single PR is the ephemeral home. Durable resume state
  lives in the PR body (or a tracked state file committed to the PR's branch and
  reachable via the PR ref), again reachable cross-branch via `gh`.

This is the option that fits the ephemeral-home model already settled upstream.
The home PR is where ephemeral artifacts live and get cleaned before merge; it
is also the natural cross-branch-durable anchor. Binding the substrate to the
home PR makes "where ephemeral artifacts live" and "where resume state lives"
the same place — one cleanup contract, one home.

### Option (c) — koto-context-store

A cloud/session-scoped context store is exactly the amplifier-layer substrate
`parent-skill-pattern.md` names (lines 222-225: "a context-store-backed
persistence layer, a session-scoped store... The amplifier-layer implementation
SHALL satisfy I-6"). It would satisfy I-6 cleanly. But the pattern is explicit
that the amplifier layer is a FUTURE mandate, not a v1 deliverable, and the
upstream context for this decision states the koto-session mechanism is
DEFERRED to a separate decision. Adopting (c) now would couple `/execute`'s v1
shippability to an unbuilt substrate. Reject as the v1 substrate; keep it as the
named amplifier-layer alternate.

### Recommendation on substrate

**Option (b): `storage_substrate = on-home-PR-durable + wip-yaml-md-scratch`.**
The home PR (coordination PR for coordinated, single PR for single-pr) is the
durable, cross-branch-reachable source of truth for resume; `wip-yaml-md` is
retained as conformant in-session serialization of the 5-field schema and as the
`parent_orchestration:` handoff surface children read, but it is NOT the source
of truth — it is a reconstructable cache. This is the only option that satisfies
I-6 without depending on an unbuilt amplifier substrate, and it reuses the
coordination-PR durable-state contract that already exists.

### Layering: one source of truth, two roles

The relationship between the three state surfaces is **layered with a single
authority**, not three competing sources:

- **Authority (durable, cross-branch):** the home PR. Coordinated: PR-Index +
  `merge-order` DAG, recomputed live from `gh` (F4: never trust body text for
  merge state). Single-pr: PR-body/PR-ref state. This is what a cross-branch or
  cross-session resume reads first.
- **Conformance cache (per-session, branch-local):** the `wip-yaml-md` state
  file. It carries the pattern-mandated 5-field schema + chain-tracking +
  `child_snapshots:` + `parent_orchestration:` sentinel so the R9 check, the
  dispatch contract, and child-isolation all bind verbatim. On a fresh-branch
  resume it is absent and gets reconstructed FROM the home PR — its absence is
  never a fork signal, because the PR is the authority.
- **Ephemeral session artifact (deferred):** koto sessions. Per upstream, the
  koto-session mechanism is a separate decision. In this decision koto sessions
  are NOT a state authority and NOT the conformance cache — they are
  session-execution scaffolding that, like the PLAN doc and wip files, lives in
  the ephemeral home and is cleaned before merge. They layer BELOW the wip cache
  and never override PR-durable state.

One source of truth: the home PR. The wip file is a derived projection of it for
in-session conformance; koto sessions are ephemeral execution scaffolding. R9
runs against the wip projection at finalization, but the `exit:` it records is
mirrored to the home PR (coordinated: the merged coordination PR IS the
done-signal; the `exit:` lives durably there).

## Exit-path binding

The three pattern-level exit names bind to EXECUTION outcomes (not authoring
outcomes). The names are fixed across parents; the per-parent binding is
`/execute`'s SKILL.md.

| Pattern exit | Authoring binding (`/scope`) | `/execute` (implementation) binding |
|---|---|---|
| **full-run** | Chain reaches terminal artifact (PLAN Accepted) | Chain reaches the **merged-PR done-signal**: single-pr = the single PR merges; coordinated = the coordination PR merges last (the contract done-signal, `coordination-strategy.md` "The Done-Signal"). `exit_artifacts:` lists the merged PR(s) / the merged coordination PR + the consumed PLAN. |
| **abandonment-forced** | Force-materialize schema-compliant partial doc | **Forced stop**: the execution chain cannot reach the merged done-signal (a per-repo PR is unmergeable, a non-PR gate node fails closed, or the team-lead's patience budget exhausts → ESCALATE). The chain force-materializes a schema-compliant partial — a coordination PR/PLAN frozen at the reached state with the abandonment marker and `triggering_child:`/`triggering_teammate:` recording what stalled. The home PR stays unmerged (the merge-last gate holds it). |
| **re-evaluation** | Re-entry on terminal topic → Decision Record, no re-author | **Upstream-must-change**: re-entry concludes the chain should NOT execute as planned because a settled upstream (the PLAN, or a DESIGN/PRD the PLAN derives from) must change first. The parent writes a Decision Record (sub-shape `/execute`-specific) and exits `exit: re-evaluation` WITHOUT re-running implementation. `boundary:` discriminates which upstream boundary the record attaches to (PLAN vs the design boundary above it). |

Binding notes:

- **full-run is the merged done-signal, not "code written."** The execution
  chain's terminal state is a MERGE, not an artifact authored. This is the
  altitude shift: authoring parents terminate at an Accepted doc; `/execute`
  terminates at a merged PR. For coordinated this is precisely the coordination
  PR merging last (the single done-signal, non-bypassably gated by
  `shirabe validate --merge-gate`). `exit_artifacts:` records the merged PR
  references with their merge state.
- **abandonment-forced is the forced stop that preserves a review surface.**
  The pattern's principle (every disciplined run has a durable home even when
  production is wrong) maps directly: a stalled execution leaves the
  coordination PR + frozen PLAN as the review surface, abandonment-marked,
  rather than a half-merged set of repos with no record. The ESCALATE terminal
  from the Team-Lead Operating Discipline (patience budget exhausted) is the
  canonical trigger and carries `triggering_teammate:`.
- **re-evaluation does NOT re-execute.** It is the "the plan was wrong, fix the
  plan/design, don't push code against a stale plan" exit. The durable record is
  the Decision Record, gated by `exit: re-evaluation`, with `boundary:` set
  because `/execute`'s chain has more than one settled-upstream boundary (the
  PLAN it consumes, and the design-level boundary the PLAN itself derived from).
  Per R9 Part 2's multi-discriminator rule, every discriminator gating
  re-evaluation MUST be set when it fires.

## Resume model (I-6)

I-6 is satisfied because the **durable resume authority is the home PR, not the
branch-local wip file.** The resume ladder's 9-row shape is unchanged (it is
pattern-level fixed); what changes is what the rows READ and how the
parent-specific body slots (5-7) are filled for an execution chain.

How I-6 holds: rows 8-9 of the meta-ladder ("on-topic branch" / "main or
unrelated branch") are the rows that, under pure `wip-yaml-md`, would start a
fresh chain on a different branch. For `/execute` these rows are augmented to
first consult the home PR (via `gh pr view` / PR-Index lookup keyed by the topic
slug) BEFORE concluding "no state → fresh chain." A topic-keyed home-PR lookup
succeeds from ANY branch, so a cross-branch resume reconstructs the chain from
the coordination PR's PR-Index + merge-order DAG (coordinated) or the single
PR's durable state (single-pr) and rebuilds the `wip-yaml-md` cache, rather than
forking. That is exactly the I-6 closure the amplifier layer was supposed to
provide — `/execute` achieves it within v1 by binding to the PR substrate the
coordination contract already mandates, instead of a not-yet-built context
store.

Resume-ladder slot filling for an execution chain (vs an authoring chain):

- **Meta-rows 1-4** (malformed / exit-set / fresh / stale): unchanged semantics.
  Stale threshold is set LONGER than authoring parents — execution chains span
  work-days (per-repo PRs land over days), so the Entry-3/Entry-4 boundary uses
  a days-scale threshold (the resume-ladder template explicitly says chains that
  "span work-days or longer pick a longer threshold").
- **Row 2 (exit set):** for `/execute`, an `exit: full-run` means the home PR
  already merged (chain done) — re-entry offers re-evaluation of the executed
  outcome or a fresh chain, NOT a re-merge.
- **Slot 5 (status-aware re-entry):** the upstream artifact `/execute` depends on
  is the **PLAN at its lifecycle states**. Critically, the resume-ladder
  template already notes `/scope`'s PLAN has an **Active state owned by
  `/work-on`** and a **Done state owned by `/release`**. `/execute` operates at
  the implementation altitude where those downstream states live, so its Slot 5
  must decide whether `/execute` IS the owner of the Active/execution state or
  whether it redirects. Recommendation: `/execute` OWNS the execution lifecycle,
  so Slot 5 entries for "PLAN Active / execution in-flight" route to a
  parent-resume (reconnect to the in-flight execution via the home PR), and only
  the terminal Done state (owned by `/release`) emits the
  `redirect to /release` literal-substring refuse-and-redirect prompt.
- **Slot 6 (partial-child-run):** for an execution chain the "partial child" is a
  per-repo implementation PR that opened but has not merged. The slot resumes
  into the partial execution unit (re-attach to the unmerged per-repo PR /
  re-derive the merge-order remainder over the unmerged nodes, per
  coordination-strategy "Re-derivation with merged nodes"), rather than
  re-running already-merged nodes. An already-merged PR is a fixed satisfied
  predecessor and is never re-executed.
- **Slot 7 (feeder-doc-detected):** parent-specific; an execution chain's feeder
  is the source DESIGN/PRD that informs whether the PLAN is still valid to
  execute — its detection pre-populates the re-evaluation judgment rather than
  triggering its own re-entry.

## Recommendation

1. **`storage_substrate = on-home-PR-durable + wip-yaml-md-scratch`** (Option
   b). The home PR — coordination PR (coordinated) or single PR (single-pr) — is
   the durable, cross-branch source of truth for resume state; `wip-yaml-md`
   stays as the pattern-conformant in-session serialization (5-field schema,
   chain-tracking, `child_snapshots:`, `parent_orchestration:`) and is
   reconstructed from the home PR on any fresh-branch resume. Reject pure
   `wip-yaml-md` (fails I-6) and koto-context-store (unbuilt amplifier substrate,
   deferred). Keep koto-context-store as the named amplifier-layer alternate.
2. **One source of truth, layered.** The home PR is authority; the wip file is a
   derived per-session projection of it for R9/dispatch/child-isolation
   conformance; koto sessions are ephemeral execution scaffolding cleaned with
   the rest of the ephemeral home before merge. R9 runs against the wip
   projection; the recorded `exit:` is mirrored durably to the home PR (for
   coordinated, the merged coordination PR IS the durable `exit: full-run`
   signal).
3. **Exit binding:** full-run = merged-PR done-signal (coordination PR merges
   last / single PR merges; `exit_artifacts:` = merged PRs + consumed PLAN);
   abandonment-forced = forced stop (unmergeable PR / failed gate node / ESCALATE
   patience-exhaustion) leaving an abandonment-marked coordination PR + frozen
   PLAN as the review surface with `triggering_child:`/`triggering_teammate:`;
   re-evaluation = upstream-must-change (PLAN or its design boundary must change
   first), producing a Decision Record with `boundary:` set, no re-execution.
4. **I-6 satisfied within v1** by augmenting resume-ladder rows 8-9 to do a
   topic-keyed home-PR lookup before declaring "no state → fresh chain," so a
   cross-branch/cross-session resume rebuilds the chain from the durable PR
   substrate rather than forking. Slot 5 owns the PLAN Active/execution
   lifecycle (redirect only to `/release` for the Done state); Slot 6 resumes
   into unmerged per-repo PRs via merge-order re-derivation over the unmerged
   remainder.
