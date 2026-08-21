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
