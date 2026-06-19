# Security Review (Phase 6)

**Verdict:** PASS

The three load-bearing findings (F1, F2, F4) are now reflected in the Solution Architecture and Implementation Approach rather than only in the Security section, the Security Considerations section is complete (threat surface, findings+mitigations, residual risks, verdict), and the public-repo doc contains no private content.

## Evaluation against the four questions

### 1. F1 / F2 / F4 reflected outside the Security section — YES

The Phase 5 verdict made F1, F2, and F4 conditional ("conditional on the design adopting..."). The Phase 6 design has discharged that condition by threading the three rules into the architecture itself, not just listing them:

- **Solution Architecture (`shirabe capstone` subcommand bullets, lines 206-215):**
  - `status` / `sync` "Validates each `owner/repo:path` component before use (F2); resolves each repo's visibility and redacts private identifiers to opaque node ids when rendering a public capstone body (F1); escapes `gh`-sourced titles/branches (F3)."
  - `gate` "recompute ... from authoritative live `gh api` queries at gate time, never by parsing the editable PR body (F4); fails closed on any unresolvable PR."
  These are stated as behaviors of the components, so the architecture structurally supports each mitigation rather than deferring it to prose.

- **Implementation Approach (step 1, lines 238-240):** the contract reference is authored "including the F1 (fail-closed private-identifier redaction), F2 (`owner/repo:path` component validation), and F4 (gate recomputes from live `gh`, not PR body) hard rules" — and is sequenced first as the unblocking step, matching their load-bearing status.

- **Decision Outcome / sub-sections** reinforce the same: "the read pass surfaces only state, not bodies" (R15/R16, line 192) and the gate as "non-bypassable merge-last backstop" (lines 165-167).

All three are tied to `references/capstone-strategy.md` as testable hard rules (lines 255-256, 330-333), which is exactly what the Phase 5 verdict required.

### 2. Security Considerations completeness — YES

The section (lines 250-333) contains all required parts:
- **Threat surface** (lines 258-277): five new/widened surfaces plus an explicit "inherited controls that must not regress" list (`gh.rs` charset regex + 4 MiB cap + no-token-in-process, `finalize.rs` lexical confinement, `run-cascade.sh` quoting, `plan-to-tasks.sh` `jq --arg`).
- **Findings and mitigations** (F1-F7, lines 279-314), each with severity and a concrete mitigation. Faithfully carried over from Phase 5 with no severity downgrades or dropped findings.
- **Residual risks** (lines 316-326): staleness window, operator-credential blast radius, human index edits, moved cross-repo refs — each with why it is accepted.
- **Verdict** (lines 328-333): explicit, names the load-bearing conditions, confirms architectural support.

### 3. New security gap missed by Phase 5 — none blocking

Given the full design, the additional surfaces (the `/plan` collapse step, abandonment/failure paths, state re-derivation on resume) are all already covered: F6 covers `repo`/`pr_group` tag re-validation on every read including resume; F7 covers contraction acyclicity and R22 re-derivation not reintroducing cycles; the abandonment path (lines 183-188) halts-on-failure with the `lifecycle.yml` gate keeping the capstone unmerged (R21), consistent with F4's fail-closed posture. One minor observation, non-blocking: the design relies on the operator's `gh` credentials for the read pass (F5, accepted residual risk) and does not add scope-narrowing — correctly scoped out as a workstation-security concern. No new gap rises to blocking.

### 4. Visibility (public repo) — clean

The document contains no private-repo content. Cross-repo references are described generically as `owner/repo:path`; the one concrete-looking example from Phase 5 (`acme/secret-repo:...`) does NOT appear in the design body. F1 itself is the mechanism that keeps the *produced* artifact clean (fail-closed redaction of private identifiers), and the design states a public capstone "never embeds private content" (line 192). No private repo names, internal URLs, or pre-announcement details are present.

## Issues Found

None blocking. One optional polish item:

1. F1 in the design body (line 286) lists the private fields to redact but, unlike Phase 5, does not name the resolution mechanism (`gh repo view --json visibility`). Fix (optional): the canonical mechanism can be pinned in `references/capstone-strategy.md` at implementation time so the fail-closed default is unambiguous; not required at design altitude.

## Summary

The Phase 6 design discharges the Phase 5 conditional verdict: F1 (fail-closed private-identifier redaction), F2 (`owner/repo:path` component validation), and F4 (live-`gh` gate recomputation) are now expressed as component behaviors in the Solution Architecture and as the first, unblocking step of the Implementation Approach, all anchored to testable hard rules in `references/capstone-strategy.md`. The Security Considerations section is complete and the public-repo document leaks no private content. No new blocking gap surfaces given the full design.
