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
  constraint, not a footnote.** (confirmed) The user asked for hard guards
  against unintended side effects. A mechanism that removes outward-facing
  commands from the user's own allow/deny surface works against that goal, so
  round 3 asks explicitly whether it can be mitigated and what the answer implies
  for side-effecting conversions.

- **`context_assignments` being inert is logged as a separate defect, not folded
  into the main thread.** (confirmed) 28 uses across the two shipped templates,
  all silently doing nothing, with a compiler warning that recommends the broken
  mechanism. koto issue #204 already exists. It is adjacent to this exploration
  rather than part of it, and the final artifact should hand it off rather than
  absorb it.
