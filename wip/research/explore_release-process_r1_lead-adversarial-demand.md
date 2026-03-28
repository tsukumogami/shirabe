# Lead: Adversarial Demand Validation for Release-Process Exploration

## Executive Summary

Demand for automated release versioning in shirabe **cannot be validated from the repository's durable artifacts**. The topic originated with a single author (Daniel Gazineu) who unilaterally created the scope document, commit history shows no distinct issue reporters or external requests, and no GitHub issues exist requesting this feature. The search discovered only internal work-in-progress documentation and one manual version bump commit. No evidence exists of users reporting version drift as a problem, maintainer acceptance criteria, or explicit organizational prioritization.

---

## Question 1: Is demand real?

**Confidence: ABSENT**

**What I searched:**
- GitHub issues in tsukumogami/shirabe (`gh issue list --repo tsukumogami/shirabe --state all --limit 200`)
- Pull requests and their discussions (`gh pr list --repo tsukumogami/shirabe --state all --limit 50`)
- Git commit messages mentioning "release" or "version" (`git log --all --grep="release"`, `git log --all --grep="version"`)
- Commit body text for context clues (`git log --all --format="%B"`)
- Repository documentation (README.md, design docs, roadmap)
- Code comments and docstrings mentioning version management

**What I found:**
- No open or closed GitHub issue requesting automated release versioning
- No pull requests with discussions about release process improvements
- Git history shows only **two commits** related to versioning:
  - `2fb8ee9` (2026-03-27): "chore: bump plugin version to 0.3.0" — a manual, one-line commit by Daniel Gazineu with no supporting description
  - `166340e` (2026-03-28): "docs(explore): capture scope for release-process" — creates the scope document that defines this work
- No commit references to issues, no linked PRs, no cross-repo issue citations
- README.md contains a "Roadmap" section but does not mention releases or version automation
- Design docs focus on workflow skills (explore, design, plan, review-plan, work-on), not plugin distribution

**Interpretation:**
The only person who raised this topic is the author of the scope document itself. No distinct issue reporters exist. No maintainer-assigned labels, no explicit acceptance criteria authored by the wider team, no linked merged PRs addressing this request. The work appears self-initiated rather than user-driven.

---

## Question 2: What do people do today instead?

**Confidence: MEDIUM**

**What I searched:**
- GitHub issues for workarounds or manual processes (`gh issue list`)
- Git log for manual version bumping patterns (`git log --all --oneline`)
- Code comments explaining version maintenance
- Commit messages describing version drift or synchronization efforts

**What I found:**
- **Current state (confirmed by manifest inspection):**
  - `.claude-plugin/plugin.json` declares version `"0.2.0"`
  - `.claude-plugin/marketplace.json` declares version `"0.2.0"`
  - Git tag is only `0.1.0`
  - Versions are **out of sync**
  
- **Manual version bumping:** Commit `2fb8ee9` shows the current practice: edit plugin.json and marketplace.json directly, commit with a "chore:" prefix
  
- **No documented process:** The README does not describe how to release shirabe. No RELEASE.md, no contribution guide describing release steps

**Interpretation:**
People currently bump versions manually by editing manifest files. The fact that shirabe's manifests drifted from the git tag (0.2.0 vs 0.1.0) suggests this manual process has failed at least once. This is a real pain point—versions got out of sync. However, the pain point is not articulated in any issue or discussion; it's only evident from the state of the repo itself.

---

## Question 3: Who specifically asked?

**Confidence: ABSENT**

**What I searched:**
- Issue authors and reporters (`gh issue list`)
- Pull request authors and reviewers (`gh pr list`)
- Commit authors and comments (`git log --all --format="%an %ae %aI %s"`)
- GitHub mentions and notifications in the repository

**What I found:**
- No issue filed requesting this feature
- No PR opened proposing release automation
- All work traced back to a single author: **Daniel Gazineu** (danielgazineu@gmail.com)
  - `2fb8ee9`: Authored and committed
  - `166340e`: Authored and committed (scope document)
- No other contributors mentioned in commit history related to versioning
- No external references to this work from issues, PRs, or discussions

**Interpretation:**
Daniel Gazineu initiated this work unilaterally. No other team member, user, or maintainer explicitly requested this feature. This is not a response to customer demand or team consensus; it's exploratory work by one contributor.

---

## Question 4: What behavior change counts as success?

**Confidence: HIGH**

**What I searched:**
- The explore scope document itself (`wip/explore_release-process_scope.md`)
- Linked design docs or acceptance criteria

**What I found:**
The scope document explicitly states (in its "Core Question" section):

> "How should shirabe handle releases so that the git tag, plugin.json version, and marketplace.json version are always in sync — with the version set automatically at release time rather than maintained manually in the manifests?"

**Success criteria (implicit in the scope):**
1. Version is set **automatically at release time**, not maintained manually before release
2. **Git tag, plugin.json, and marketplace.json are always in sync**
3. Integration with existing org-level `/prepare-release` and `/release` skills
4. CI validation that versions are consistent

**Interpretation:**
The scope document defines clear success criteria: automation that prevents version drift, with synchronization across all three version sources. However, these criteria are self-authored (by the person who initiated the work) rather than stakeholder-authored. No external validation that this is the *right* success criterion exists.

---

## Question 5: Is it already built?

**Confidence: ABSENT (for full automation), MEDIUM (for partial work)

**What I searched:**
- GitHub Actions workflows in `.github/workflows/`
- Release scripts in `scripts/`
- Version injection patterns in the codebase

**What I found:**
- **Existing workflows:** Three GitHub Actions exist, but none handle releases:
  - `check-evals.yml` — runs evaluation tests
  - `check-templates.yml` — validates koto templates
  - `validate-templates.yml` — validates template structure
  - **No release.yml workflow**
  
- **Research artifacts (exploratory only):**
  - `wip/research/explore_release-process_r1_lead-manifest-injection-patterns.md` — investigates how koto and tsuku handle versioning (post-tag commits and ldflags injection, respectively)
  - `wip/research/explore_release-process_r1_lead-marketplace-caching.md` — documents how Claude Code marketplace resolves versions
  - `wip/research/explore_release-process_r1_lead-atomic-version-workflow.md` — design exploration of a release workflow
  - `wip/research/explore_release-process_r1_lead-superpowers-releases.md` — analysis of how superpowers (another Claude Code plugin) handles releases
  
- **No implementation:** Zero automation exists in the main codebase. All files are exploratory wip/ artifacts.

**Interpretation:**
The feature is completely unbuilt. Exploration and research are underway, but no release automation has been implemented. The org's existing `/prepare-release` and `/release` skills are referenced in the scope but not integrated here.

---

## Question 6: Is it already planned?

**Confidence: MEDIUM**

**What I searched:**
- Open GitHub issues (`gh issue list --repo tsukumogami/shirabe --state all`)
- Project boards or milestone entries
- Design docs in `docs/designs/`
- Roadmap entries in README or elsewhere

**What I found:**
- **No GitHub issue filed** for release automation
- **No design doc** in `docs/designs/current/` for release process
- **No milestone** associated with this work
- **Scope document exists** at `wip/explore_release-process_scope.md` (just created 2026-03-28)
- **Research leads are outlined** in the scope (six research directions)
- **This is the first of six exploratory leads** being executed
  - Lead 1: manifest injection patterns (completed)
  - Lead 2: marketplace caching (completed)
  - Lead 3: atomic version workflow (completed)
  - Lead 4: superpowers releases (completed)
  - Lead 5: CI validation approach (not found)
  - Lead 6: adversarial demand validation (this artifact)

**Interpretation:**
This work is *tentatively* planned as an exploration. The scope document and research methodology exist, but no official issue or design doc. The work is in the "investigate whether this is worth pursuing" phase, not the "build this" phase. The fact that it's paired with adversarial demand validation (lead 6) suggests the team is uncertain whether this feature is actually needed.

---

## Evidence of Version Drift

The only positive evidence that a problem exists is **state evidence** rather than **demand evidence**:
- Git tag: `0.1.0`
- Manifest versions: `0.2.0`
- **Gap: 0.1.0 → 0.2.0**

This proves the manual process failed once. However, no issue was filed about it, and no user complained. It was discovered only through exploratory work.

---

## Calibration

### Demand not validated as absent

**Majority of question results:**
1. Is demand real? — **ABSENT**
2. What do people do today instead? — **MEDIUM** (manual process exists, drift proves it failed)
3. Who specifically asked? — **ABSENT**
4. What behavior change counts as success? — **HIGH** (but self-authored)
5. Is it already built? — **ABSENT**
6. Is it already planned? — **MEDIUM** (exploratory phase, no committed issue)

### The Gap

**This is a case of "demand not validated," not "demand validated as absent."**

Evidence for the distinction:
- **No positive rejection:** No design doc that de-scoped this feature, no maintainer comments declining the request, no closed issue with reasoning
- **But also no positive demand:** No users complained, no team member explicitly requested this, no issue reports of version drift causing operational problems
- **Root cause:** The repository's visibility is narrow. Shirabe is a 4-week-old plugin (first commit 2026-03-17). It has one contributor (Daniel Gazineu). No external users can open issues yet

### Flag: What's Unknown

The research cannot determine:
1. **Is version drift actually a problem for users?** Users can install shirabe, but we don't know if any have reported confusion when marketplace version (0.2.0) doesn't match git tag (0.1.0)
2. **Will the org's release process even use shirabe?** The scope mentions integration with org-level `/prepare-release` and `/release` skills, but those live in a different repository. This work may be exploratory but not urgent if those skills aren't regularly used
3. **Who owns the decision to release?** Is Daniel Gazineu the maintainer, or is this exploratory work on behalf of a team? The commit history shows only one author
4. **Has this been discussed in synchronous conversation?** Git and GitHub are asynchronous. Office hours, Slack, or one-on-one conversation might have motivated this—but no traces exist in durable artifacts

---

## Summary

**Is release-process automation demanded?**

No evidence supports the claim that users or the team have requested automated release versioning. The work is self-initiated by one contributor as an exploratory investigation. The pain point (version drift) is real and visible in the repo state, but it has not been articulated as a problem by anyone else or reported in any issue.

**This is exploratory work that belongs in the `/explore` skill's Phase 1 (Scope) and Phase 2 (Discover) phases.** The adversarial demand-validation lead is correctly questioning whether this feature is worth building at all, given the lack of independent demand signals.

**Recommendation for convergence:** Before committing to a design and implementation, the team should:
1. File a public issue if this work is internal-only motivation, to establish a canonical request
2. Consult with users (if any exist) about version sync challenges
3. Clarify whether the org's release skills will actually use shirabe's automation
4. Decide whether this is "nice to have" polish or "must have" for the plugin to be usable

---

## Sources

All findings are from durable artifacts in the tsukumogami/shirabe repository at `/home/dgazineu/dev/workspace/tsuku/tsuku-5/public/shirabe`:

- Git history: `git log --all`, `git show` output
- Manifest files: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- GitHub artifacts: Issues and PRs via `gh` CLI
- Scope document: `wip/explore_release-process_scope.md` (created 2026-03-28)
- Research artifacts: Four completed leads in `wip/research/`
- Repository structure: `.github/workflows/`, `scripts/`, `docs/designs/`, `README.md`
