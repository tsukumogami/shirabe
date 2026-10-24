# execute eval fixtures

## The old-shape cascade chain

Four fixtures form the old-shape cascade chain, PLAN -> DESIGN -> PRD -> BRIEF ->
ROADMAP, in which the BRIEF names the ROADMAP. No eval runs this chain any more.
The evidence that a pre-existing corpus in this shape still cascades is Scenario 6
(`scenario_brief_with_upstream`) of `skills/work-on/scripts/run-cascade_test.sh`,
which builds the same chain in a scratch repository and reads none of these files.

They stay because other files still name them. Each link in the chain is the
upstream of the file below it, so deleting one leaves the next pointing at a file
that is gone. Before deleting any of them, check that every reader listed here is
gone too.

| Fixture | Read by |
|---|---|
| `plans/PLAN-cascade-test-full.md` | The Feature 2 `**Downstream:**` line of `roadmaps/ROADMAP-cascade-test.md`, which three evals read, and of `roadmaps/ROADMAP-cascade-test-v3.md`. The roadmap-identity corpus in `crates/shirabe/tests/fixtures/roadmap-identity/` keeps frozen copies of `ROADMAP-cascade-test.md` that name it. |
| `designs/DESIGN-cascade-test-full.md` | The `upstream:` of `PLAN-cascade-test-full.md`. Its basename is also in the set `scripts/check-no-fixture-design-leak.sh` collects from every skill's `evals/fixtures/designs/`. |
| `prds/PRD-cascade-test-full.md` | The `upstream:` of `DESIGN-cascade-test-full.md`. |
| `briefs/BRIEF-cascade-test-full.md` | The `upstream:` of `PRD-cascade-test-full.md`; R23 of `docs/prds/PRD-upstream-link-legality.md`, which names it as kept in the old shape on purpose; and the scope boundary of `briefs/BRIEF-cascade-test-new-shape.md`. |

The new-shape chain beside it (`*-cascade-test-new-shape.md`) is the one the
`e2e-execute-cascade-new-shape-plan-carries-roadmap` eval runs.
