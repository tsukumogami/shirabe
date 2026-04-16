<!-- decision:start id="completion-cascade-implementation-strategy" status="assumed" -->
### Decision: Completion Cascade Implementation Strategy

**Context**

The plan_completion state in work-on-plan.md runs after CI passes on a
plan implementation PR. Its job is to delete the PLAN doc, transition upstream
artifacts to their post-implementation statuses, and update the ROADMAP. The
current implementation is directive prose that hardcodes a DESIGN→PRD→ROADMAP
traversal. It is documented as broken for chains where a DESIGN's upstream points
directly to a ROADMAP with no PRD layer — a real topology in the shirabe artifact
graph.

The decision has two intertwined dimensions: the traversal strategy (generic
upstream-chain walker vs. hardcoded topology enumeration) and the implementation
form (shell script vs. agent-interpreted directive prose in the koto template).

These dimensions are not independent. Hardcoded topology + directive prose is the
current broken state. Hardcoded topology + shell script is an improvement but
still requires exhaustive case enumeration. Generic topology + directive prose
handles any chain but cannot be tested in execute mode. Generic topology + shell
script is the only combination that satisfies all four stated constraints.

Each artifact type in shirabe has an existing transition-status.sh script (design,
prd, roadmap, vision). The artifact type is deterministic from the document
filename prefix. The upstream chain is connected by `upstream` frontmatter fields.
These two facts make a generic walker viable with a simple `case` dispatch on the
filename basename — no complex YAML parsing or topology pre-detection required.

The repo's precedent for this pattern is plan-to-tasks.sh: orchestration logic
that was previously agent-interpreted prose, extracted to a shell script with a
companion _test.sh when testability became a requirement. The barrier to adding
run-cascade.sh is low and the payoff (execute-mode eval coverage) is direct.

**Assumptions**

- The `upstream` frontmatter field contains a single file path, not a list. If
  upstream becomes multi-valued in a future artifact schema revision, the walker
  must be updated to iterate over the list. Neither the current prose nor any
  alternative handles this already.

- VISION-* artifacts are not cascade targets. The cascade starts from PLAN and
  walks to ROADMAP at most. If VISION is added as a cascade target, the
  run-cascade.sh dispatch table gains one case entry — no architectural change.

- `jq` and `bash` 4+ are available in the execution environment. The existing
  transition-status.sh scripts already assume these. run-cascade.sh can follow
  the same pattern.

**Chosen: Generic chain walker + shell script**

A new script (`skills/work-on/scripts/run-cascade.sh`) accepts a PLAN doc path.
It reads the `upstream` frontmatter field, walks the chain iteratively, and
dispatches each node to the matching transition-status.sh based on the filename
prefix. The loop terminates when no `upstream` field is found.

The plan_completion directive prose in work-on-plan.md is simplified to a single
bash invocation:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/run-cascade.sh {{PLAN_DOC}}
```

The script handles missing files and failed transitions by logging and continuing
(best-effort per constraint). A companion run-cascade_test.sh covers topology
variants. Eval fixtures include both DESIGN→ROADMAP and DESIGN→PRD→ROADMAP cases
to verify correctness.

**Rationale**

This is the only combination that satisfies all four constraints simultaneously:
arbitrary topology coverage (the generic walker handles any chain without case
enumeration), no private-tools runtime dependency (the script calls only local
shirabe scripts), cascade failures that do not block done (explicit `|| true`
patterns in bash, versus agent variance in prose), and execute-mode eval coverage
(the script is an invocable entry point for run-evals.sh).

The two shell-script alternatives diverge only on whether the dispatch is
topology-driven (case: "does this chain have a PRD?") or type-driven (case:
"what is the filename prefix of the current node?"). Type-driven dispatch is
simpler: each iteration needs only the current document's basename, not global
awareness of the chain structure. This makes the generic walker simpler to
implement and test than the hardcoded topology script, not more complex.

The prose alternatives are eliminated by the testability constraint. Eval #26
covers the cascade at tier-1 plan_only, which tests planning intent but not
execution behavior. The documented topology bug is precisely the kind of regression
invisible to plan_only evals. Execute-mode tier-2 coverage requires a script.

**Alternatives Considered**

- **Generic chain walker + directive prose**: Same topology coverage but no
  isolated entry point for execute-mode evals. Agent variance in failure handling
  violates the determinism requirement. Rejected on testability grounds.

- **Hardcoded sequence + shell script**: Testable and deterministic, but requires
  pre-detecting the chain topology as a structural question before branching. This
  is isomorphic to the generic walker's dispatch but more complex: instead of
  "what type is this node?", the script must ask "does this chain contain a PRD
  layer?". Any topology outside the enumerated cases silently fails. Rejected
  because the generic walker is strictly simpler and handles future topologies
  without code changes.

- **Hardcoded sequence + directive prose**: The current partial implementation.
  Known broken for DESIGN→ROADMAP topologies. Fails testability and topology
  constraints. Rejected as the status quo to be replaced.

**Consequences**

What changes: plan_completion in work-on-plan.md becomes a thin wrapper. All
cascade logic moves to run-cascade.sh. A companion _test.sh and updated evals
provide coverage before merge.

What becomes easier: adding a new artifact type to the cascade is a one-line
change in the dispatch table; adding a new topology requires no code change.
Regression detection is automated via execute-mode evals.

What becomes harder: cascade behavior lives in a bash script rather than the koto
template. Maintainers must look in two places (template for state machine,
script for cascade logic). This is the same trade-off as plan-to-tasks.sh and is
mitigated by a clear comment in the template pointing to the script.
<!-- decision:end -->
