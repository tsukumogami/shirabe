# Demand Validation: Adopting tsuku's `.tsuku.toml` in Shirabe

**Status:** Lead Research Completed  
**Date:** 2026-04-03  
**Focus:** Adversarial demand validation for project-level tool management  
**Visibility:** Public

---

## Executive Summary

Evidence shows that **tsuku's `.tsuku.toml` feature was intentionally designed, implemented, and shipped** as part of a wider shell integration initiative (PR #2175, merged 2026-03-28). However, **demand specifically for shirabe adoption is minimal and entirely internal** — no distinct external issue reporters, feature requests from users, or GitHub discussions cite tool management as a pain point in shirabe.

The feature itself is validated by tsuku maintainers as built and current (not planned). Shirabe has a documented dependency on koto >=0.2.1, and CI currently installs tools manually per-step. The question is whether adopting `.tsuku.toml` represents real user demand or a natural-fit optimization offered by newly available infrastructure.

---

## Findings by Demand-Validation Question

### 1. Is demand real?

**Verdict: Low confidence**

**Evidence searched:**
- Shirabe GitHub issues: searched all 18 open issues, none mention tool declaration, project-level configuration, or developer setup friction related to missing tools
- Shirabe commits: searched for "tool", "koto", "depend", "setup" patterns; found koto adoption merged (#29, #27, #48) but no issue expressing demand for project-level declarations
- Tsuku GitHub issues: referenced design doc cites issue #1680 as spawn point for project configuration feature
- Koto GitHub issues: no linked demand data visible

**What we found:**
- **Tsuku design doc (DESIGN-project-configuration.md, spawned from issue #1680)** identifies the problem: "Tsuku installs tools globally with no way to declare per-directory tool requirements. Projects can't specify which tools and versions they need, forcing each developer to manually discover and install the right tools."
- This is a *tsuku-wide problem statement*, not specific to shirabe
- No evidence that shirabe developers filed an issue or explicitly requested tool declaration support
- Shirabe README (line 92-93) lists koto as a requirement with auto-install fallback, suggesting tool availability is already solved for CI

**Confidence: Low.** The problem is real in the *abstract* (tool discovery is a pain in large ecosystems), but no distinct shirabe reporter, user, or maintainer has explicitly asked for this feature in the shirabe repo.

---

### 2. What do people do today instead?

**Verdict: High confidence**

**Evidence found:**
- **validate-templates.yml (lines 14-23):** Manual, explicit tool installation in CI:
  ```yaml
  - name: Install koto via tsuku
    run: tsuku install tsukumogami/koto -y
  ```
- **README.md (lines 92-93):** Koto listed as a requirement with auto-install fallback:
  > koto >= 0.2.1 (for /work-on; installed automatically if missing)
- **CI pattern:** Each workflow step that needs a tool runs an explicit `tsuku install <tool>` command (validate-templates.yml), or assumes tools are pre-installed on the runner (release.yml uses `gh` and `jq` directly)
- **Local development:** No documented setup step; developers presumably run `tsuku install <tool>` on demand when they encounter a missing tool

**Current workarounds:**
1. **In CI:** Explicit per-tool install commands with `-y` flag
2. **Local:** Auto-install on first use via command-not-found hook (tsuku feature), or manual discovery/install
3. **For docs:** README lists dependencies; users read and install manually if needed

**Confidence: High.** The artifact evidence (workflow files, README) is explicit and durable.

---

### 3. Who specifically asked?

**Verdict: Absent**

**No evidence found** of a specific person, issue number, or pull request requesting `.tsuku.toml` adoption in shirabe.

**What we searched:**
- Shirabe issue tracker (#1–#61): no issue titled "tool management", "project config", "tsuku.toml", or similar
- Shirabe commits: no commit message citing a user request for tool declaration
- Cross-repo references: no GitHub link from koto or tsuku issues pointing to shirabe as a use case

**Single internal signal:** The scope document (commit 32877e1, 2026-04-03, **today**) references "the user wants to adopt `.tsuku.toml` and collect a friction log" — this is a *self-directed exploration* by an internal agent/user in the conversation, not a reported issue.

**Confidence: Absent.** No external or even documented internal issue ticket exists.

---

### 4. What behavior change counts as success?

**Verdict: Medium confidence**

**Implicit acceptance criteria from scope doc:**
- Create `.tsuku.toml` for shirabe
- Declare koto and other tools (gh, jq, python3, claude) with version pinning
- Update CI workflows to use `tsuku install` (no args) instead of explicit per-tool installs
- Collect friction observations to file back against tsuku

**Explicit goal from scope (line 9):**
> "We're treating this as a friction log exercise to surface UX issues worth filing back against tsuku."

**Measurable outcome:** Completion of the exploration yields:
1. A `.tsuku.toml` file committed to shirabe
2. CI workflows updated to use batch install
3. A list of friction findings filed as issues or research artifacts

**Confidence: Medium.** The scope doc is explicit, but it treats success as *process-driven* (friction discovery) rather than *outcome-driven* (solving a user problem). The "why" is exploratory (what's the ux like?) rather than "users need this."

---

### 5. Is it already built?

**Verdict: High confidence — YES, it is built**

**Evidence:**
- **Tsuku PR #2175 (merged 2026-03-28):** Implements shell integration Track B, including project configuration (`.tsuku.toml`)
- **Commit b3e39be7 message:**
  > "New internal/project package reads .tsuku.toml for per-directory tool requirements with parent directory traversal and $HOME ceiling. tsuku init creates the config file; tsuku install with no arguments batch-installs all declared tools with interactive confirmation and error aggregation."
- **Design doc status:** DESIGN-project-configuration.md marked "status: Current" (not Proposed, not Done)
- **Implementation evidence:** Multiple lead research docs found in shirabe/wip/research/ examining the actual behavior of `.tsuku.toml` (setup experience, CI workflows), suggesting the feature is already usable
- **Code reference:** `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-3/public/tsuku/internal/project/config.go` exists and contains `LoadProjectConfig` implementation

**Confidence: High.** The feature is shipped and documented. No partial work, no feature flags, no "coming soon."

---

### 6. Is it already planned?

**Verdict: High confidence — NO, it is not planned (it is already current)**

**Evidence:**
- **Design doc status:** "status: Current" — not "proposed", "under review", or "accepted"
- **Merged PR:** PR #2175 is merged into main, not open or in draft
- **No open issues blocking adoption:** The scope doc suggests adoption is ready ("recently shipped")
- **Roadmap:** Tsuku README and docs don't list `.tsuku.toml` as a future feature; it's presented as a current capability

**What *is* planned for .tsuku.toml itself:**
- From design doc lines 262–266: "Future extensibility" includes `extends` keyword for monorepo inheritance (deferred), `.tool-versions` compatibility (deferred), per-tool options (deferred)
- Design doc lines 289–294 note: "Track demand for `extends`" and "Track demand for a `tsuku migrate` command"

**Confidence: High.** The feature is not planned; it exists.

---

## Calibration

### State Assessment

**Demand is NOT VALIDATED.** Here's why:

1. **Absent issue evidence** (Q3): No distinct reporter, no GitHub issue, no documented user request
2. **Low problem specificity to shirabe** (Q1): The problem (tool discovery friction) is real in the abstract, but no evidence that shirabe *developers* experience it as a blocker
3. **Workaround exists** (Q2): Current patterns (manual installs, auto-install on first use, README docs) are functional, not broken
4. **Scope is exploratory, not remedial** (Q4): The stated goal is "collect friction" and "file issues back against tsuku", not "solve a shirabe user problem"

**However, this is NOT demand-validated-as-absent.** Here's why not:

- The feature **is** built and usable (Q5 = High)
- The feature **is not** planned as future work (Q6 = High)
- The adoption surface is **low friction** (lead-setup-experience research doc shows straightforward three-step flow)
- **No rejection evidence exists**: no discussion of "we tried `.tsuku.toml` and it doesn't fit", no decision to stick with manual installs, no maintainer statement that shirabe won't adopt project config

**What the gap reveals:** Shirabe is in a *naturally-fit, low-effort adoption zone* where the feature exists, is stable, and costs little to use — but no active demand signal from shirabe developers or users is visible.

---

## Cross-References

**Supporting artifacts in shirabe repo:**
- `/wip/explore_project-tool-management_scope.md` — Exploration charter
- `/wip/research/explore_project-tool-management_r1_lead-setup-experience.md` — End-to-end `.tsuku.toml` UX walkthrough
- `/wip/research/explore_project-tool-management_r1_lead-ci-workflows.md` — CI integration patterns

**Tsuku source references:**
- `/public/tsuku/docs/designs/current/DESIGN-project-configuration.md` (issue #1680, merged in PR #2175)
- `/public/tsuku/internal/project/config.go` (implementation)
- `/public/tsuku/cmd/tsuku/init.go` and `/install_project.go` (CLI commands)

**Shirabe internal references:**
- `.github/workflows/validate-templates.yml` — Current manual koto install pattern
- `README.md` (lines 92–93) — Koto requirement declaration

---

## Recommendation for Convergence

**Data point for decision:**

The demand question has two possible verdicts:

1. **"Demand is not validated"** → Exploratory adoption is acceptable as a friction-discovery exercise (stated goal). User/maintainer continues exploration to surface UX issues worth filing back to tsuku. Value is in feedback, not in solving a blocking shirabe problem.

2. **"Demand is validated at low/medium confidence"** → A natural-fit optimization is available. Adoption is low-cost and improves CI reproducibility. Proceed for its own merits (good practice, not urgent need).

Either path is defensible. The convergence question is: **Is exploring tsuku's UX (and collecting friction) a priority, or is shirabe's current tool management already sufficient?**

