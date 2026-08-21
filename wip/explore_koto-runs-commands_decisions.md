# Exploration Decisions: koto-runs-commands

Running in `--auto`. Each entry follows the lightweight decision protocol:
frame, gather from evidence already in hand, decide, record. Status is
`confirmed` where the evidence was unambiguous and `assumed` where it was not.

## Round 1

- **The framing question is settled: this is an unused capability plus three
  koto gaps, not "poor koto use" alone.** (confirmed) `default_action` is
  implemented, shipped, and verified working in `koto 0.11.6`; shirabe uses it
  zero times; and three specific engine gaps (output routing, failure
  propagation, execution anchoring) block the target design regardless of how
  well shirabe authors its templates. Subsequent rounds treat both halves as in
  scope rather than choosing between them.

- **No prior rejection to respect.** (confirmed) lead-history found no design,
  issue, or PR in either repo recording a decision to skip `default_action`.
  The exploration proceeds as if adoption were simply never done, and does not
  spend a round hunting for an implicit objection.

- **The MIXED bucket is out of reach today and is treated as koto-blocked, not
  template-blocked.** (confirmed) Both inventory leads conditioned conversion of
  the 11 MIXED `/execute` commands on actions being able to populate evidence
  from output. The probe and lead-output-plumbing establish that they cannot.
  Round 2 asks what the smallest enabling change is rather than re-asking
  whether the ability exists.

- **`requires_confirmation` is not treated as the failure-fallback mechanism.**
  (confirmed) It fires unconditionally, after execution, on success and failure
  alike. Any design that reaches for it as "stop when the command fails" is
  misreading both the code and the design doc, so that path is ruled out now.

- **Execution anchoring is promoted from a caveat to a first-class finding.**
  (confirmed) The user named wrong-directory execution as the hazard to guard
  against. The probe showed it is the default behavior, not an edge case, so
  round 2 gives it a dedicated design lead rather than folding it into a general
  safety note.

- **koto's own protocol traffic is scoped in, but as a separate mechanism.**
  (assumed) The eight retry-clearing blocks in `/work-on` are the densest
  mechanical concentration found, and they are koto talking to koto through the
  agent. They cannot be `default_action` — a transition-time hook is the shape
  that fits. Treated as in scope for the map because the user asked for all
  hardcoded commands, with the caveat that it is a different koto feature.

- **Artifacts land in shirabe.** (assumed) The symptom, the templates, and the
  bulk of the eventual rewrite live in `public/shirabe`; koto-side work will be
  named explicitly as koto issues. Revisit at crystallize if the koto half turns
  out to dominate.

## Round 2

- **The three-path pattern is treated as available, not aspirational.** (confirmed)
  Verified running against the shipped binary, including the compiler constraint
  that every conditional transition must share a field. Round 3 stops asking
  whether the shape works and starts asking which steps deserve it.

- **`on_failure:` and similar schema additions are ruled out.** (confirmed)
  Gates were always the intended arbiter of success, and the failure gaps are
  plumbing — action output missing from the two failure response variants, and
  no detection at all for a state with an action and no gates. Round 3 costs the
  plumbing, not a new policy field.

- **`capture_stdout_as:` is the working assumption for output routing.**
  (assumed) It satisfies the motivating case, avoids the response-contract
  surface that makes `action_output`-everywhere expensive, and reuses the
  existing variable path. Not final — it carries a same-tick staleness trap that
  a design doc would need to address.

- **The 64KB deadlock is promoted above the whole conversion question.**
  (confirmed) It is a live defect in the layer gates already use, it produces
  false failures with the evidence destroyed, and it affects shipped shirabe
  templates today. Whatever the exploration concludes about `default_action`,
  this does not wait on it.

- **The earlier "koto cannot call koto because of a lock" reading is retracted.**
  (confirmed) The cause is the un-drained pipe plus koto's own 106KB of
  migration warnings per session-touching command. Findings that built on the
  lock framing — including part of the counter-case — are re-read accordingly:
  the deadlock is real and environment-dependent, not structural.

- **The permission-bypass objection is carried forward as a first-class design
  constraint, not a footnote.** (confirmed at the time; **OVERTURNED** by the
  author ruling in Round 4 below) Round 2 read a mechanism that removes
  outward-facing commands from the user's allow/deny surface as working against
  the stated wish for hard guards. The author has since ruled that the
  relocation of consent is the intent.

- **`context_assignments` being inert is logged as a separate defect, not folded
  into the main thread.** (confirmed) 28 uses across the two shipped templates,
  all silently doing nothing, with a compiler warning that recommends the broken
  mechanism. koto issue #204 already exists. It is adjacent to this exploration
  rather than part of it, and the final artifact should hand it off rather than
  absorb it.

## Round 3

- **Conversion is scoped by a principle, not by a percentage.** (confirmed)
  koto runs a step when it is isolated to its own state, gate-verifiable
  independent of the action's own exit code, and either read-only or a
  repo-local mutation safe to reach twice. Remote mutations and anything needing
  per-repo configuration stay agent-run. This replaces "convert the mechanical
  bucket" as the operative rule.

- **The blanket read-only restriction is rejected.** (confirmed) Applied line by
  line it collapses `/execute`'s yield to zero and is unenforceable at compile
  time. The principle above keeps its safety intent — remote mutations stay with
  the agent — without discarding repo-local automation.

- **The permission-bypass problem is accepted as unfixable inside koto.**
  (confirmed as to mechanism; **its scoping consequence is OVERTURNED** by the
  author ruling in Round 4 below) No preview-before-execution mechanism exists
  and building one reproduces the current prose-plus-gate pattern. Round 3 turned
  that into a scoping constraint. It is not one — it is the design.

- **Deadlock severity is stated as latent, not active.** (confirmed) Round 3
  measured `go test ./...` at 3,793 bytes across 63 packages on the tsuku
  monorepo, and only one of eleven gates writes captured stdout at all. The
  earlier framing overstated it; the corrected framing is that expansion, not
  time, is what makes it fire.

- **The eighteen non-koto skills are named but not absorbed.** (assumed) They are
  real hardcoded-command surface under the user's literal question, and none of
  it is reachable by koto automation. The right treatment is a pointer in the
  final artifact — particularly the `shirabe transition` / `shirabe validate`
  duplication across eight lifecycle skills — not an expansion of this topic.

- **The retry-clearing item is deferred behind a decision, not sequenced.**
  (confirmed) `DESIGN-work-on-retry-clearing.md` is Current and chose manual
  clearing deliberately. Implementing koto issue #204 does not retire anything
  in shirabe until that doc is revisited on its own terms.

- **Exploration ends here.** (confirmed) Three rounds, twenty-one leads and two
  orchestrator probe rounds. What remains open are choices belonging to the
  author — whether koto-store writes count as side effects, who revisits the
  retry-clearing design — not questions more research would answer.

## Round 4 — Author Ruling (2026-08-20, post-exploration)

- **Engine-run commands bypassing the agent's permission layer is the intended
  behavior.** (confirmed by the author, directly) Loading a skill that drives
  koto is itself the broad grant: invoking a koto-backed workflow authorizes
  every command that workflow bakes in. The risk is acknowledged and accepted.
  Consent moves from per-command prompting to the decision to run the workflow,
  and that relocation is the feature — it is what lets koto carry mechanical
  work without interrupting the agent at each step. **Why this is recorded
  prominently:** two separate leads independently derived the objection from the
  code and one of them made it the centerpiece of its recommendation. Left
  standing in the research, it would keep resurfacing and would sap a future
  agent's confidence in a direction the author has already chosen.

- **The permission argument is struck as a scoping input.** (confirmed) It no
  longer justifies keeping any command with the agent, and must not be
  re-derived as an objection. Where the artifacts still describe it as a
  constraint, the Author Ruling section at the top of the findings file
  supersedes them.

- **The conversion principle is amended.** (confirmed) koto runs a step when it
  is isolated to its own state and gate-verifiable independent of the action's
  own exit code. Reversible, repo-local steps convert now. Irreversible
  outward-facing steps convert once failure output reaches the agent — deferred
  on diagnosability and irreversibility, never on authorization. Only commands
  needing per-repo knowledge to know what to run stay with the agent, and that
  set shrinks once a `TEST_COMMAND` style variable carries the answer.

- **Published conversion yields become floors, not estimates.** (assumed) The
  round-2 and round-3 figures were computed with the permission constraint
  applied to the writes-remote bucket. With it removed, the reachable set is
  larger than any number recorded in this exploration.

- **`requires_confirmation`'s after-the-fact firing is promoted to a real
  defect.** (confirmed) It is now the only in-band checkpoint in the design, so
  a flag that runs the irreversible thing before asking is worth fixing on its
  own merits rather than noting as a curiosity.

- **One adjacent risk survives untouched.** (confirmed) Action output is
  persisted into an event log committed to feature branches, so a command whose
  output contains a secret leaks it. That concerns what gets written down, not
  who authorized the command, and the ruling does not reach it.
