# Exploration Decisions: scope-chain-mandatory-steps

## Round 1

- **All four parent-chain surfaces are in scope** (`/explore`, `/scope`,
  `/charter`, `/execute`), plus the shared parent-skill pattern references:
  taken at scoping time, before research. Research confirmed the choice —
  the load-bearing fix turned out to sit in `references/parent-skill-pattern.md`
  rather than in any one skill.

- **`/explore` becomes a router and stops authoring durable chain artifacts:**
  taken at scoping time. Research sharpened what that means — four of its nine
  produce handlers currently write committed documents (`DESIGN-*.md`,
  `SPIKE-*.md`, `COMP-*.md`, `REJECTED-*.md`), so "router only" is a larger
  behavioral change than removing child-skill names from routing tables.

- **`/explore`'s router is four handoffs plus a terminal recording set**, not
  strictly four arms. Rejection Record, Decision Record, Spike Report, and COMP
  are terminal by construction and no parent chain owns any of them; three are
  backed by real machinery (the `needs-spike` / `needs-decision` labels, produce
  handlers, and the `adversarial-absent-demand` eval fixture whose only
  destination is the rejection record). Deleting them silently would strand that
  fixture's payoff and remove `/explore`'s only way to record a "don't build
  this" conclusion.

- **"Never authors chain artifacts" means never authors *durable* ones.** The
  `wip/<child>_<topic>_scope.md` handoff mechanism survives — `vision` eval 2
  and `roadmap` eval 12 both assert the downstream skill detects that artifact
  and resumes from it rather than re-asking what the exploration settled.

- **`/charter` keeps its roadmap declination, and the model gets restated
  around it** rather than the declination being retired. It forms its judgment
  against a Draft STRATEGY that exists on disk, keeps Proceed pre-selected under
  both readings of the observation walk, and is graded by four evals (12-15)
  written specifically to keep the parent's reading advisory. Retiring it would
  require building consolidation machinery `/charter` does not have.

- **Eliminated: porting a consolidation judgment to the strategic chain in this
  change.** `/charter` has none (`grep -rn "consolidat" skills/charter/` returns
  nothing), so #302 reached only the tactical chain. Adding one is a separate
  design question — STRATEGY is the durable audit trail and ROADMAP is a working
  artifact retired by the PLAN cascade, a different disposal model from
  `/scope`'s absorb-into-survivor.

- **Eliminated: `/execute` as a fix site.** Research classified it a false
  positive on the optional-step axis. It has no chain proposal, no confirmation
  prompt, omits the `planned_chain`/`chain_ran`/`chain_skipped` triad outright
  (sanctioned by the state schema), never uses the Gate Vocabulary, and offers
  the author nothing to drop. It carries the cleanest statement of the post-#302
  model in the corpus. Its only defect here is that the pattern doc's parent
  roster does not know it exists.

- **The stale `/scope` evals are in scope for the same pass.** Scenarios 18, 19,
  20 and 21 grade the retired type-level absorbability model and are an unmet
  acceptance criterion of #302's own PRD (R24), with the PRD at `Done` and the
  DESIGN at `Current`. Fixing them closes shipped work rather than opening new
  work, and leaving them would keep pulling any eval-optimizing agent back
  toward the pre-#302 model.

- **Constraint accepted: this enforces an existing rule rather than proposing a
  new one.** `PRD-scope-artifact-persistence.md` R28 already forbids
  reintroducing "a pre-artifact worth decision in any form, including an
  author-chosen entry altitude," and eval 17 is the existing tripwire. The work
  is closing the gap between that rule and the surfaces that predate it.
