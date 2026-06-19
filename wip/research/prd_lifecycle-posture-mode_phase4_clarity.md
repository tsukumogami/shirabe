# Clarity Review

## Verdict: PASS

The PRD is specific enough that two developers would build substantially the same thing: postures are named, the finding classification is fully enumerated (L01-L07), and acceptance criteria are nearly all binary and exit-code-anchored.

## Ambiguities Found

1. **R8 / AC7-AC8 ("names what each needs before ready", "names what to fix to stay ready")**: The advisory output requirements specify *that* the output must name what each finding needs, but not the form or content of that text. -> Two implementers could produce wildly different advisory strings, and a reviewer can verify "a string is present per finding" but not "the string is correct/useful." -> Either provide expected advisory text per finding (L02/L06/L07) as a fixture, or explicitly state that exact wording is out of scope and the AC only checks presence of a per-finding line.

2. **R3 "assert review-ready posture" / Out of Scope "interface shape ... is a DESIGN decision"**: The PRD repeatedly defers the assertion mechanism to DESIGN while AC4 tests "no posture argument." -> "Argument" in AC4 pre-supposes a flag/argument shape that R3 and Out-of-Scope say is undecided; a developer could read AC4 as constraining the interface. -> Reword AC4 to "with no review-ready signal asserted" to match R2's wording and avoid implying an interface.

3. **R9 / R13 "ambient pull-request context" and "local, hermetic context"**: "Ambient PR context" is named but never defined (env vars? a passed-in JSON? CI-provided values?), and "hermetic" is asserted while R9 permits reading PR context. -> Whether reading PR context counts as "hermetic"/"local" is genuinely unclear — a developer could read it as "env vars only" or "any non-network source." -> Define what sources count as local/ambient (e.g. "process environment and CLI-passed values, no network or git calls") so R13's no-network rule is testable.

4. **R7 / Decisions "L01 remains posture-sensitive as it is today"**: The current L01 behavior is referenced ("as it is today") but not described in the PRD. -> A developer without the codebase open cannot know what L01 does or verify it is unchanged; there is no AC covering L01. -> Add a one-line description of L01's current posture behavior and an AC asserting it is preserved (regression), or explicitly state L01 has no new AC because it is untouched.

5. **Goals "points toward a passing state"**: Subjective phrasing in the Goals section. -> "Points toward" is not verifiable as written. -> It is operationalized by R8/AC7-AC8, so this is minor; consider cross-referencing R8 from the goal to make the binding explicit.

## Suggested Improvements

1. **Add an AC for R10/R12 wording vs. testability**: AC "documented in a single discoverable location" is binary-ish but "discoverable" is subjective. Pin it to a concrete path or a grep-able marker (e.g. "a section titled X in file Y") so the reviewer checks a location, not a judgment.

2. **Tie advisory ACs to a fixture**: AC7 and AC8 are the only criteria not anchored to an exit code or a parse check. Providing golden-output fixtures (even partial) would make them objectively pass/fail rather than "looks like it explains the posture."

3. **Define the posture vocabulary once**: The terms "in-flight/draft" and "review-ready/ready" are used interchangeably with parentheticals throughout. A one-line glossary mapping the author-facing term to the internal name removes any doubt about whether "draft" and "in-flight" are the same posture.

## Summary
The PRD is strong: requirements use SHALL/MAY consistently, the finding classification is fully enumerated rather than left abstract, and 8 of 10 acceptance criteria are binary and exit-code-anchored. The residual ambiguity is concentrated in the advisory-output requirements (R8/AC7-AC8), which describe intent but not verifiable content, and in undefined terms ("ambient PR context," "hermetic," L01's current behavior) that a developer without the codebase open could interpret differently. These are clarifications, not redesigns, so the PRD passes.
