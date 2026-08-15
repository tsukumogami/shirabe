```yaml
review_result:
  topic: work-on-retry-clearing
  round: 1
  mode: fast-path
  verdict: proceed
  categories:
    - category: A
      name: Scope Gate
      verdict: pass
      critical_findings: []
    - category: B
      name: Design Fidelity
      verdict: pass
      critical_findings: []
    - category: C
      name: AC Discriminability
      verdict: fail
      critical_findings: 4
      resolution: all four addressed in the plan; see below
    - category: D
      name: Sequencing/Priority Integrity
      verdict: pass
      critical_findings: []
```

# Review verdict: proceed

Three categories passed on the first pass. Category C failed with four findings,
all four are real, and all four are fixed in
`docs/plans/PLAN-work-on-retry-clearing.md` rather than waved through. The
verdict is `proceed` because the findings were corrections to acceptance
criteria, not to the decomposition or the design -- no loop-back to Phase 3 was
needed.

## What the passing categories established

**A (Scope Gate).** All nine files in the design's Solution Architecture map to
an issue. The three latent gate-staleness instances and the `context_assignments`
no-op that the design records but declines to fix are absent from every issue,
so the plan neither over- nor under-scopes. It noted that Issue 1's bundle rests
on two arguments of unequal strength -- the gate-plus-clearing-block pairing is a
correctness constraint, folding in the panel-orchestration summary is editorial
-- which is accurate and is how the plan argues it.

**B (Design Fidelity).** Verified against real koto rather than against the
documents: the pattern accepts the `qa_validation` payload that carries no
`round` field and rejects the sentinel, the template-compile baseline is exactly
one W3 warning, and `built_in_default` for `context-matches` returns
`{matches:true,error:""}` with the resolution order
`--with-data -> override_default -> built_in_default`, so dropping
`override_default` keeps `koto overrides record/list` working. That last check
also independently confirms the `review-panel-orchestration.md` correction is
right rather than inherited.

**D (Sequencing).** The Issue 3 -> Issue 2 dependency is real:
`check-bash-floor_test.sh`'s `test_registry_scripts_exist` fails on a registered
script that does not exist. And single-pr mode means the PR cannot reach a
mergeable state with the contract unverified, since every issue lands on one
branch and Issue 3's workflow is part of the same PR.

## Category C's four findings, and what each changed

Three of the four were fail-open shapes *in the acceptance criteria*, which is
the same failure mode the plan exists to fix, one altitude up.

1. **Issue 2's drift assertion bundled a checkable baseline with an unenforced
   meta-property.** The criterion said mutating the sentinel or the pattern
   fails the assertion, but nothing required those mutation checks to be
   persisted, automated sub-cases. An implementer could demonstrate them once by
   hand, revert, and ship only the baseline -- satisfying the checkable half
   while leaving the harness unable to catch the exact drift the design's Case 0
   exists for. Split into two criteria, the second requiring both variants be
   derived at run time inside the shipped script and asserted every run.

2. **Issue 4's "reported as a finding rather than rewritten" was pure honor
   system**, and it sits beside two criteria that *require* editing eval
   assertion text. From the committed diff a reviewer cannot distinguish a
   legitimate contract update from a failing assertion quietly rewritten to
   match a buggy implementation -- the two are identical. Now requires the
   `run-evals.sh` output pasted verbatim into the PR description, and any
   failing assertion named there separately from the mandated text updates.

3. **Issue 3 was happy-path only.** All five criteria were static checks on YAML
   and shell registration; none required observing the job actually run. A
   workflow typo, a wrong step order, or a macOS leg that silently no-ops would
   have satisfied every one. Added a criterion requiring a green run of
   `check-work-on-scripts.yml` with its URL recorded, and one requiring the
   harness's non-zero exit to reach the job -- no `continue-on-error`, no
   `|| true`.

4. **Two of Issue 1's criteria checked prose presence rather than content.** The
   separating-rule comment and the panel-orchestration sentence would have been
   satisfied by any technically-true sentence on the topic. Both now pin the
   substance: the comment must carry the "by any path" clause that makes the
   rule correct for `deferral_approval`, and the summary must say *all three*
   artifacts rather than that a retry affects them.

## What C also confirmed

No criterion in any of the four issues already passes against `main`. Verified
directly: the three gates are still `context-exists` with `override_default`
blocks, `phase-4a-scrutiny.md` still instructs `koto context remove`,
`review-panel-orchestration.md` still carries the wrong auditability claim,
`skills/work-on/scripts/` and the workflow do not exist, and `evals.json` still
asserts `context-exists`. The discriminating-criteria failure mode did not turn
up anywhere in this plan.
