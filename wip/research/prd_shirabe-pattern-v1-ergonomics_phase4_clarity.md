# Clarity Review

## Operating Context

Serial-self-jury under sub-agent dispatch from `/scope`. The
parallel-agent fan-out the phase prescribes was not available;
this verdict was produced by the same agent that authored the
PRD, evaluating the PRD against the clarity rubric only. The
clarity lens looked for ambiguity-signaling vocabulary
("should", "appropriate", "reasonable", "may", "might", "as
needed") and for requirements that could be interpreted multiple
ways. Independence-loss caveat: the cross-checking between
independent reviewers was not available; this PASS should be
treated as serial-self-jury PASS.

## Verdict: PASS

The 32 numbered requirements use SHALL throughout. The four
"should/may" hits in the document are all in non-normative prose
(Problem Statement narrative line 79, R16's prose explanation,
Out-of-Scope narrative, Known Limitations) — none gate behavior
that an implementer must produce. The acceptance criteria are
binary pass/fail with explicit grep / presence-check / exit-code
verification anchors.

## Ambiguities Found

None at FAIL severity. Below are notes flagged at NOTE severity.

1. **R12** uses "OR" between two alternative paths (optional
   `motivating_context:` field OR documented prose workaround)
   with the explicit prose "DESIGN picks one; the PRD requires
   at least one path be documented." The ambiguity is
   intentional — it's the contract-vs-mechanism split the
   PRD scopes via D2. Treated as clear-by-design rather than
   ambiguous.

2. **R20** (mechanical writing-style detection) names the
   banned vocabulary verbatim AND defers the surface (validator
   notice / Phase 4 reviewer / pre-commit hook) to DESIGN. The
   AC4.3 verification anchor ("is surfaced by the mechanical
   writing-style check at the surface DESIGN chooses") is
   conditional on the DESIGN choice. This is the same
   contract-vs-mechanism pattern as R12 and is acceptable per
   the PRD's stated framework.

3. **R29** ("the projected PRD's expected content shape")
   uses an under-defined noun phrase. The reviewer evaluated
   whether "expected content shape" is testable: yes — the AC
   anchors test for predicates that fire on the projected shape,
   not the absent file. Mechanism (what counts as "expected
   shape") is DESIGN territory. Flagged as a NOTE because it's
   the boundary case where the contract-vs-mechanism split
   stretches the clarity rubric the furthest.

## Suggested Improvements

1. **None blocking.** The PRD's clarity within the
   contract-vs-mechanism split it stated explicitly in D2 is
   acceptable. The implementer who reads the PRD AND the BRIEF
   AND the references the PRD cites (vision#514, vision#535,
   shirabe#157, shirabe#158) has enough to author the DESIGN.

## Summary

The PRD uses SHALL for normative requirements throughout; the
four "should/may" hits are in narrative prose, not gating
implementer behavior. The DESIGN territory the PRD defers is
named explicitly per the contract-vs-mechanism split. The
clarity rubric passes.
