# Security Review: Reusable Release System

**Design**: DESIGN-reusable-release-system.md
**Phase**: 5 (Security)
**Date**: 2026-03-28

## 1. External Artifact Handling

### Draft release as data channel (LOW risk)

The design routes release notes through a draft GitHub release rather than
workflow dispatch inputs. This is a sound choice -- it avoids shell injection
from markdown content flowing through `-f` parameters where special characters
could break quoting or be interpreted by the shell.

However, the design does not address:

- **Draft release squatting.** An attacker with write access could pre-create a
  draft release for a future tag, injecting malicious release notes. The skill's
  precondition check ("no existing draft release") would catch this, but the
  workflow itself has no equivalent check. If someone dispatches the workflow
  directly from the UI (bypassing the skill), the pre-existing draft with
  attacker-controlled notes would be promoted.

  **Recommendation:** The finalize workflow should verify that the draft release
  was created by an expected actor (the skill's `gh release create` call or the
  workflow service account), or at minimum the release workflow should validate
  that no draft already exists for the tag before proceeding.

### Artifact count verification (LOW risk)

The `expected-assets` input on finalize-release.yml is optional and defaults to
0 (skip check). If a repo misconfigures this or leaves the default, the draft
gets promoted with zero binaries. This isn't a vulnerability per se, but it
creates a window where users could download a release with no artifacts.

**Recommendation:** Repos with builds should be required to set `expected-assets`
to a non-zero value. Consider making it required (no default) in the finalize
workflow, forcing callers to be explicit.

## 2. Permission Scope

### Configurable token with GITHUB_TOKEN fallback (MEDIUM risk)

The `${{ secrets.token || github.token }}` pattern is the core of the auth model.
Several concerns:

- **PAT scope ambiguity.** The design says "fine-grained PAT scoped to the
  specific repo with contents:write only." This is good guidance but it's not
  enforced. Nothing prevents someone from configuring a classic PAT with broad
  org-wide permissions. The early validation step checks if the token can push,
  but it doesn't verify the token's scope is minimal.

  **Recommendation:** Document the exact fine-grained PAT permissions required
  (contents:write, possibly actions:read) and add a check that rejects classic
  PATs or overly-broad tokens if GitHub's API exposes that information.

- **Branch protection bypass.** The PAT exists specifically to bypass branch
  protection. This is an inherent tension -- the release workflow needs to push
  directly to main, which is exactly what branch protection is designed to
  prevent. The design acknowledges this but doesn't discuss:
  - Who can trigger `workflow_dispatch` on the release workflow? Anyone with
    write access to the repo can dispatch it manually, creating an unreviewed
    commit on main.
  - The PAT stored as a repo secret is accessible to anyone who can edit
    workflows in the repo. A malicious PR that modifies a workflow file to
    exfiltrate `secrets.RELEASE_PAT` would be caught by branch protection on
    the workflow file itself, but only if the repo has the "Require approval for
    all outside collaborators" setting.

  **Recommendation:** Restrict `workflow_dispatch` trigger to repo admins or a
  specific team using GitHub's environment protection rules. Document that the
  PAT secret should be stored in an environment with required reviewers, not as
  a plain repo secret.

- **Token passed to reusable workflow.** Secrets passed to reusable workflows
  via `secrets:` are available to the called workflow. The reusable workflow in
  shirabe receives the caller's PAT. If shirabe's workflow is compromised (e.g.,
  a malicious commit to the `v1` tag), the PAT for every consuming repo is
  exposed.

  **Recommendation:** This is partially mitigated by pinning to a tag (`@v1`),
  but tags are mutable. Consider recommending SHA pinning for the reusable
  workflow reference, or at minimum signing tags. See section 3.

### No force-push (GOOD)

The design explicitly states fast-forward-only pushes. This prevents the
workflow from rewriting history on main. Good.

## 3. Supply Chain / Dependency Trust

### Reusable workflows as third-party code (HIGH risk)

This is the most significant security concern in the design. Every consuming
repo delegates its release process -- including git mutations on main and tag
creation -- to workflows hosted in `tsukumogami/shirabe`. The trust model:

- **Tag mutability.** The design pins callers to `@v1`. Git tags are mutable --
  anyone with push access to shirabe can move the `v1` tag to point to arbitrary
  code. A compromised shirabe maintainer (or a compromised PAT for shirabe)
  could replace `release.yml` with a version that exfiltrates secrets or injects
  malicious content into release commits across all consuming repos.

  **Recommendation:** Use SHA pinning in caller workflows
  (`@abc123` instead of `@v1`) with a documented process for updating the SHA
  when shirabe releases a new version. Alternatively, use GitHub's tag
  protection rules on shirabe to prevent tag overwrites.

- **Scope of blast radius.** A compromised release.yml in shirabe can:
  - Read any secrets passed to it (including RELEASE_PAT)
  - Push arbitrary commits to main in the caller repo
  - Create arbitrary tags in the caller repo
  - Modify any files via the set-version hook execution context

  This is the standard risk for any reusable workflow, but the design should
  acknowledge the blast radius explicitly.

- **Transitive dependency risk.** The reusable workflow presumably uses
  `actions/checkout` and possibly other actions. Each of those is another supply
  chain dependency. The design doesn't discuss pinning these inner dependencies.

  **Recommendation:** Pin all action references inside the reusable workflows to
  SHA digests, not tags. This is standard practice for security-sensitive
  workflows.

### Hook script trust (LOW risk, well-addressed)

The design correctly notes that `.release/set-version.sh` runs in the caller's
own CI environment with the caller's own permissions. The reusable workflow
doesn't inject code. This is the right trust model.

One gap: the design doesn't mention that hook scripts should be
reviewed as part of release workflow changes. A PR that modifies
`.release/set-version.sh` could inject malicious code that executes during the
next release. This is standard CI trust -- anyone who can merge to main can
modify CI scripts -- but worth calling out.

## 4. Data Exposure

### Release notes content (LOW risk)

Release notes are generated by the skill from commit messages and PR titles,
then stored in a draft release. The data flow is:

  commits/PRs -> skill analysis -> draft release -> published release

No sensitive data should be in commit messages or PR titles in a public repo,
so this is low risk. The design's choice to use the draft as the data channel
rather than workflow inputs is good -- it avoids the notes appearing in workflow
run logs as input parameters.

### Workflow run logs (LOW risk)

The release workflow will log its operations (checkout, set-version calls,
commit messages, push output). In a public repo, these logs are publicly
visible. The design should ensure that:

- The token value is never logged (GitHub masks secrets automatically, but
  custom scripts could accidentally echo it)
- The set-version.sh hook doesn't print sensitive information

**Recommendation:** Add a note that hook scripts must not echo secrets or
internal paths. Consider running hooks with `set +x` to prevent bash trace
output from leaking values.

### Tag as data channel in finalize bridge (MEDIUM risk)

In the finalize bridge workflow pattern:

```yaml
tag: ${{ github.event.workflow_run.head_branch }}
```

This uses `head_branch` from the `workflow_run` event to pass the tag name to
the finalize workflow. The `head_branch` for a tag-triggered workflow is the tag
ref itself. This is a well-known pattern but has a subtle issue: if someone
creates a branch named `v1.0.0` (matching a tag name), it could confuse the
finalize logic. The finalize workflow should validate that the tag input
actually corresponds to a git tag and a draft release, not just trust the
`head_branch` value blindly.

**Recommendation:** The finalize workflow should verify that the input is a
valid tag with an associated draft release before proceeding.

## Risk Summary

| Dimension | Risk | Key Issue |
|-----------|------|-----------|
| External artifact handling | Low | Draft squatting; optional artifact count |
| Permission scope | Medium | PAT scope not enforced; dispatch access unrestricted |
| Supply chain trust | High | Mutable tag pinning for reusable workflows |
| Data exposure | Low | Standard CI log visibility; head_branch confusion |

## Overall Assessment

The design makes several good security choices: draft-as-data-channel avoids
shell injection, no-force-push prevents history rewriting, and configurable auth
avoids forcing PATs on everyone. The hook trust model is correctly scoped.

The primary gap is supply chain trust for the reusable workflows themselves.
Mutable tag pinning (`@v1`) means a compromise of shirabe's repository could
cascade to all consuming repos. This is the standard reusable workflow risk, but
given that the workflows receive push tokens and make commits to main, the blast
radius is significant.

The secondary gap is permission governance -- no enforcement of minimal PAT scope,
no restriction on who can trigger `workflow_dispatch`, and no environment
protection on the PAT secret.

## Recommended Outcome

**OPTION 2: Conditional approval with required changes before implementation.**

The design is architecturally sound and the core security decisions (draft as
data channel, no force-push, configurable auth) are good. However, the following
should be addressed before implementation begins:

1. **Required:** Pin reusable workflow action dependencies (actions/checkout, etc.)
   to SHA digests inside release.yml and finalize-release.yml.
2. **Required:** Document that consuming repos should use SHA pinning or at
   minimum that shirabe must have tag protection rules preventing `v*` tag
   overwrites by non-admins.
3. **Required:** Add draft-existence validation in the release workflow itself
   (not just the skill) to prevent draft squatting.
4. **Recommended:** Store RELEASE_PAT in a GitHub environment with required
   reviewers rather than as a plain repo secret. Document this in the caller
   workflow templates.
5. **Recommended:** Add guidance that `workflow_dispatch` should be restricted
   via environment protection rules to prevent unauthorized release triggers.
6. **Recommended:** The finalize workflow should validate that its tag input
   corresponds to an actual git tag with a draft release.

None of these require architectural changes. They're hardening measures that fit
within the existing design structure.
