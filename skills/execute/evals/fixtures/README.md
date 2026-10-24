# execute eval fixtures

## The old-shape cascade chain

Four fixtures form the old-shape cascade chain, PLAN -> DESIGN -> PRD -> BRIEF ->
ROADMAP, in which the BRIEF names the ROADMAP. No eval runs this chain any more.
The evidence that a pre-existing corpus in this shape still cascades is Scenario 6
(`scenario_brief_with_upstream`) of `skills/work-on/scripts/run-cascade_test.sh`,
which builds the same chain in a scratch repository and reads none of these files.

They stay because other files still name them. Each file's `upstream:` names the
next one up, so the PLAN holds the DESIGN, the DESIGN holds the PRD, and the PRD
holds the BRIEF. The PLAN and the BRIEF are each held from outside the chain.

| Fixture | Read by |
|---|---|
| `plans/PLAN-cascade-test-full.md` | The Feature 2 `**Downstream:**` line of `roadmaps/ROADMAP-cascade-test.md`, which three evals read. The roadmap-identity corpus in `crates/shirabe/tests/fixtures/roadmap-identity/` keeps frozen copies of `ROADMAP-cascade-test.md` that name it. No script opens the PLAN by that name; it stays so the roadmap's Planned feature doesn't point at a missing plan. |
| `designs/DESIGN-cascade-test-full.md` | The `upstream:` of `PLAN-cascade-test-full.md`. |
| `prds/PRD-cascade-test-full.md` | The `upstream:` of `DESIGN-cascade-test-full.md`. |
| `briefs/BRIEF-cascade-test-full.md` | The `upstream:` of `PRD-cascade-test-full.md`; R23 of `docs/prds/PRD-upstream-link-legality.md`, which names it as kept in the old shape on purpose; and the scope boundary of `briefs/BRIEF-cascade-test-new-shape.md`. |

To remove the chain, change Feature 2 of `roadmaps/ROADMAP-cascade-test.md` first. That frees the PLAN,
and with it the DESIGN and the PRD. The BRIEF also needs R23 and the new-shape
BRIEF's mention dealt with.

`docs/designs/current/DESIGN-completion-cascade.md` lists PLAN, DESIGN and PRD
files with the same names under `skills/work-on/evals/fixtures/`. That was
work-on's own copy of the chain, which nothing read and which is gone; the
design records what its plan delivered. Those paths aren't readers of this
chain.

The new-shape chain beside it (`*-cascade-test-new-shape.md`) is the one the
`e2e-execute-cascade-new-shape-plan-carries-roadmap` eval runs.
