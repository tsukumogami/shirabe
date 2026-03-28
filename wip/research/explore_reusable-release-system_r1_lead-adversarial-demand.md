# Adversarial Demand Validation: Reusable Release System

## Visibility

Public

## Question 1: Is demand real?

**Confidence: High**

Multiple independent artifacts across repos confirm that release process
fragmentation is a real, recurring problem:

- **Koto issue #81** (closed): `koto version` reported wrong version after
  v0.2.0 release because Cargo.toml was still at 0.1.0. The fix required
  inventing a `build.rs` approach to derive version from git tags. This is
  the same class of version-drift problem shirabe faces with plugin.json.

- **Shirabe DESIGN-release-process.md** (lines 37-38): "The manifests already
  drifted: both say 0.2.0 while the only git tag is 0.1.0." Identical symptom
  to koto's problem, solved independently with a different mechanism.

- **Koto DESIGN-koto-installation.md** explicitly states the design goal is to
  "mirror tsuku's release infrastructure patterns so both projects grow in
  complexity together rather than diverging" -- acknowledging the duplication
  problem at design time.

- **Shirabe issue #4** (open, needs-design): "CI validation portability --
  reusable workflows with config-driven validation." This directly asks for
  reusable GitHub Actions workflows published from shirabe that external repos
  can reference. Labeled needs-design with 16-24 hour estimate.

- **Shirabe issues #31-34** (open, milestoned "Release Process"): Four issues
  implementing a release process that the design doc itself calls "generic"
  -- issue #33 says the pre-tag hook "makes it a generic hook any plugin repo
  can use."

The demand is real but narrow: it comes from one maintainer (dangazineu) across
multiple repos, not from external contributors.

## Question 2: What do people do today instead?

**Confidence: High**

Each repo has independently built its own release workflow:

| Repo | Language | Release mechanism | Version management | Lines in release.yml |
|------|----------|-------------------|--------------------|---------------------|
| tsuku | Go + Rust | GoReleaser + custom Rust builds + integration tests + finalize | GoReleaser ldflags + sed for Cargo.toml | ~520 |
| koto | Rust | Cross-compiled builds + checksums + finalize-release | build.rs reads git tags (post-v0.2.0 fix) | ~166 |
| niwa | Go | GoReleaser + tag annotation notes | GoReleaser ldflags | ~52 |
| shirabe | None (plugin) | No workflow yet | Manual (drifted) | 0 (planned) |

Common patterns duplicated across repos:
- Tag-triggered on `v*`
- Extract release notes from annotated tag via `git tag -l --format='%(contents)'`
- Create GitHub release with `gh release create`
- finalize-release job pattern (koto has it, tsuku has it, shirabe plans it)
- RELEASE_PAT secret for pushing to protected main

Divergent patterns:
- tsuku uses GoReleaser; koto uses `cargo build` + `cross`; niwa uses GoReleaser
- tsuku has integration tests in the release pipeline; others don't
- koto pins the reusable workflow version in finalize-release; others don't
- Shirabe needs JSON manifest stamping; others need binary version injection

## Question 3: Who specifically asked?

**Confidence: Medium**

All evidence traces to a single author:

- **dangazineu** created shirabe issue #4 (reusable workflows), issues #31-34
  (release process), DESIGN-release-process.md, and the explore scope document
  that frames this investigation.
- **dangazineu** authored koto DESIGN-koto-installation.md which states the
  "mirror tsuku" design driver.
- **dangazineu** authored koto issue #81 (version drift fix).

No external contributors, community requests, or third-party interest found.
All four repos have a single maintainer. The demand is self-identified
maintainer pain, not user-reported.

## Question 4: What behavior change counts as success?

**Confidence: Medium**

The explore scope document (wip/explore_reusable-release-system_scope.md)
defines the target state:

- A reusable GitHub Actions workflow published from shirabe
- Repo-local hook scripts (like `set-version.sh`) that the workflow calls
- A new release skill that replaces the current org-level /release and
  /prepare-release skills
- Multi-ecosystem support: Go binaries, Rust binaries, Claude Code plugins

Shirabe issue #4 has concrete ACs:
- Four core validators parameterized via YAML config
- Reusable GHA workflows published
- Thin caller workflow template (~10 lines each)
- Version pinning via tags (@v1)
- At least one external repo tested as a consumer

No quantitative success metrics (time saved per release, error rate reduction)
are defined anywhere.

## Question 5: Is it already built?

**Confidence: High (partially built)**

Significant partial work exists:

- **Shirabe DESIGN-release-process.md** is at "Planned" status with four
  implementation issues (#31-34). Issue #31 (sentinel bootstrap) is
  strikethrough in the design's implementation table, suggesting it's done
  or in progress.

- **Koto release.yml** already implements the finalize-release pattern that
  shirabe's design references as the target model.

- **Niwa release.yml** already copies tsuku's GoReleaser pattern.

- The `/release` and `/prepare-release` org skills already exist (referenced
  throughout the design). Issue #33 extends the existing `/release` skill
  rather than replacing it.

What is NOT built:
- No reusable workflow exists yet (shirabe's release.yml doesn't exist)
- No shared hook contract
- No config-driven parameterization (issue #4 is needs-design)
- Each repo's release.yml is independent, copy-pasted and diverged

## Question 6: Is it already planned?

**Confidence: High**

This is extensively planned:

- **DESIGN-release-process.md**: Full design doc at Planned status with
  solution architecture, security considerations, and four phased issues
- **Issues #31-34**: Four milestoned issues under "Release Process" milestone
- **Issue #4**: Broader reusable-workflow portability issue (needs-design)
- **Explore scope document**: Active exploration underway with seven research
  leads including this adversarial validation

The planning focuses on shirabe's immediate release needs. The broader
"reusable across all repos" goal is in the explore scope but not yet in any
design doc or issue set.

## Calibration

**Demand validated -- but scope mismatch detected.**

The evidence strongly supports that release process fragmentation is a real
problem causing real bugs (koto #81 version drift, shirabe manifest drift).
The maintainer has independently solved the same problem three different ways
in three repos. This is not "demand not validated" and definitely not "demand
validated as absent."

However, the evidence supports two different scopes, and the investigation
should distinguish them:

1. **Shirabe needs a release process (narrow scope)**: Strongly validated.
   Version drift already occurred. Four issues planned. Design doc written.
   This is immediate, concrete, and clearly worth pursuing. It's also already
   being pursued via issues #31-34.

2. **The ecosystem needs a reusable release system (broad scope)**: Weakly
   validated. The pain is real (three independent implementations), but:
   - Only one maintainer across all repos -- the coordination cost of
     independent workflows is low when one person maintains everything
   - The repos have genuinely different build requirements (Go+Rust+musl+GPU
     vs pure Rust vs pure Go vs JSON manifests)
   - tsuku's release.yml is 520 lines of complex multi-platform builds that
     won't simplify into a reusable template
   - No external consumers have asked for reusable workflows
   - The "at least one external repo tested as a consumer" AC in issue #4
     assumes external adoption that has no evidence of demand

**Risk**: The broad scope could become a yak-shave. Shirabe's release process
(narrow scope) is blocked on the broad exploration, but the narrow scope could
ship independently in days while the broad scope requires design work on hook
contracts, workflow parameterization, and multi-ecosystem support.

**Recommendation for convergence**: The narrow scope (shirabe release process)
has clear demand. The broad scope (reusable across ecosystem) is a legitimate
future optimization but lacks urgency given the single-maintainer context.
The user should decide whether to pursue the broad scope now or ship the
narrow scope first and extract the reusable pattern later when a second
consumer actually needs it.
