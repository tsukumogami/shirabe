# Demand Validation: Adopting tsuku's `.tsuku.toml` in Shirabe

**Date:** 2026-04-04
**Focus:** Adversarial demand validation for project-level tool management
**Visibility:** Public

---

## Executive Summary

No external demand exists for `.tsuku.toml` adoption in shirabe. No shirabe
user, contributor, or issue reporter has requested project-level tool
management. The exploration is self-directed by the maintainer as a friction
log exercise -- the stated goal is to surface UX issues worth filing back
against tsuku, not to solve a blocking shirabe problem.

tsuku 0.9.0 (released 2026-04-04) fixes the two biggest friction points from
the prior round: org-scoped recipes now work in `.tsuku.toml`
(tsukumogami/tsuku#2230), and `"latest"` version strings resolve correctly
(tsukumogami/tsuku#2229). These fixes reduce adoption friction but don't
change the demand picture.

---

## Findings by Demand-Validation Question

### 1. Is demand real?

**Confidence: Low**

Searched all 61 shirabe issues (open and closed). None mention tool
declaration, project-level configuration, `.tsuku.toml`, or developer setup
friction related to missing tools.

The tsuku design doc (DESIGN-project-configuration.md, spawned from
tsukumogami/tsuku#1680) frames the problem generically: "Projects can't
specify which tools and versions they need, forcing each developer to manually
discover and install the right tools." This is a tsuku-wide problem statement,
not specific to shirabe.

The scope document for this exploration (commit 4f61bb0) describes the work as
a "friction log exercise" -- an internal initiative, not a response to reported
demand.

### 2. What do people do today instead?

**Confidence: High**

Two durable workarounds are visible in the codebase:

1. **CI: explicit per-tool install commands.**
   `.github/workflows/validate-templates.yml` (line 23) runs
   `tsuku install tsukumogami/koto -y` directly. Release workflows assume `gh`
   and `jq` are pre-installed on GitHub runners.

2. **Local development: undocumented manual install.**
   README.md states koto >= 0.2.1 is required and "installed automatically if
   missing." No other tool requirements are declared for local development.
   Developers presumably run `tsuku install <tool>` on demand.

Both workarounds function. Neither has been reported as broken or insufficient.

### 3. Who specifically asked?

**Confidence: Absent**

No issue, PR, comment, or commit in shirabe's history requests `.tsuku.toml`
adoption. Searched:

- Shirabe issues #1 through #61 (all states)
- Shirabe commit messages on main
- Cross-repo issue references from tsuku and koto pointing to shirabe

The only signal is the current exploration scope document, authored by the
maintainer as a self-directed exercise.

### 4. What behavior change counts as success?

**Confidence: Medium**

The scope document defines success as:

- A `.tsuku.toml` file committed to shirabe
- CI workflows updated to use `tsuku install` (no args) instead of explicit
  per-tool installs
- Friction observations collected and filed as issues against tsuku

The goal is explicitly process-driven (discover friction) rather than
outcome-driven (solve a user problem). Prior round 1 findings (commit 2598fb3)
already produced three qa-discovered bugs filed against tsuku:
tsukumogami/tsuku#2229, tsukumogami/tsuku#2230, tsukumogami/tsuku#2231. All
three are now closed, with #2229 and #2230 fixed in v0.9.0.

### 5. Is it already built?

**Confidence: High -- the tsuku feature is built; shirabe adoption is not**

The `.tsuku.toml` feature shipped in tsuku as part of PR #2175 (merged
2026-03-28). Design doc DESIGN-project-configuration.md is status: Current.
Implementation lives in `internal/project/config.go`. CLI commands `tsuku init`
and `tsuku install` (no args) are functional.

No `.tsuku.toml` file exists in shirabe or any other public repo in the
workspace (confirmed via glob search across all of `/public/`). No repo in the
org has adopted project-level tool management yet.

### 6. Is it already planned?

**Confidence: Medium -- planned as an exploration, not as a tracked issue**

The current branch (`docs/project-tool-management`) and scope document
constitute the plan. There is no GitHub issue in shirabe's tracker for
`.tsuku.toml` adoption. The exploration is tracked only via wip/ artifacts on
this feature branch.

In tsuku's tracker, the feature itself is complete. Related follow-up work
(`.tool-versions` compatibility, `extends` keyword for monorepo inheritance)
is deferred per the design doc.

---

## Calibration

**Demand not validated.**

Four of six questions returned absent or low confidence. No distinct external
reporter, no issue requesting this, no evidence that current workarounds are
insufficient. The exploration is self-directed by the maintainer with an
explicit friction-log goal.

This is NOT demand validated as absent. There is no rejection evidence -- no
discussion concluding "we don't need this," no decision to stick with manual
installs, no maintainer statement against adoption. The feature is available,
low-cost to adopt, and three bugs surfaced during the prior friction log have
already been fixed upstream (v0.9.0).

**What changed since round 1:** tsuku 0.9.0 (released today) fixes
org-scoped recipe syntax in `.tsuku.toml` (tsukumogami/tsuku#2230) and
`"latest"` version resolution (tsukumogami/tsuku#2229). These were the two
largest blockers identified in the prior round. The jq shared library linking
issue (tsukumogami/tsuku#2231) is also closed. Adoption friction is materially
lower than it was 24 hours ago, but the demand picture is unchanged.

---

## Cross-References

**Shirabe artifacts:**
- `wip/explore_project-tool-management_scope.md` -- Exploration charter
- `.github/workflows/validate-templates.yml` -- Current manual koto install (line 23)
- `README.md` -- Koto requirement declaration

**Tsuku artifacts:**
- `docs/designs/current/DESIGN-project-configuration.md` (issue #1680)
- `internal/project/config.go` -- Implementation
- Issue #2229 (CLOSED) -- "latest" version string fix
- Issue #2230 (CLOSED) -- Org-scoped recipe syntax fix
- Issue #2231 (CLOSED) -- jq shared library linking fix
- Issue #2233 (CLOSED) -- Version string behavior documentation
- v0.9.0 release notes -- Confirms fixes shipped
