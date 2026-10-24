# work-on eval fixtures

## The cascade roadmaps

No work-on eval runs the completion cascade. Execute's evals do, against the
cascade chains in `skills/execute/evals/fixtures/`. Two cascade roadmaps stay
here because other files name them. Their `**Downstream:**` lines name
documents that aren't in this directory (`DESIGN-cascade-test-short.md`,
`PLAN-cascade-test-short.md` and `PLAN-cascade-test-full.md`), and nothing
reads those lines here.

| Fixture | Read by |
|---|---|
| `roadmaps/ROADMAP-cascade-test.md` | `no_roadmap_in_the_repository_gains_a_milestone_finding` in `crates/shirabe/tests/milestone_roadmap.rs`, which runs FC21 on every tracked roadmap, and the `work-on-evals/` line of `crates/shirabe/tests/fixtures/roadmap-identity/SOURCES.tsv`, which names it as the source of the corpus's frozen copy (the test reads the copy, not this file). The Phase 3 deliverables of `docs/designs/current/DESIGN-completion-cascade.md` also list it, next to work-on cascade fixtures that no longer exist. |
| `roadmaps/ROADMAP-cascade-test-v3.md` | The same FC21 run. |

Neither reader needs these files: the FC21 run checks whatever roadmaps are
tracked, and the corpus keeps its own copy. To remove them, first replace the
`SOURCES.tsv` line's source with a `(none: ...)` note, as the
`v2-milestone-word/` line has.
