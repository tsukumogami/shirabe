# Security Review: release-process

## Dimension Analysis

### External Artifact Handling

**Applies:** No

This design does not download, execute, or process external inputs. All artifacts
are internally generated: version strings come from the tag name (controlled by
the /release skill), manifest files are read/written with `jq` against known
schemas, and release notes are extracted from annotated tag messages authored by
the release operator. No external URLs are fetched, no user-uploaded content is
processed, and no third-party artifacts are consumed during any step of the
release flow.

### Permission Scope

**Applies:** Yes

**Severity:** Low

The design requires a `RELEASE_PAT` personal access token with `contents: write`
scope, used by the `finalize-release` CI job to push a commit directly to the
protected main branch. This is the most sensitive permission in the design.

**Assessment:**

- The PAT is stored as a GitHub repository secret, which limits exposure to
  repository admins and workflows that explicitly reference it.
- The finalize-release job runs only on tag push events matching `v*`, which
  narrows the trigger surface. An attacker would need push access to create
  tags (which already implies write access to the repo).
- The job performs a narrow, deterministic operation: reset two JSON fields to a
  fixed string and push. There is no dynamic input that could alter the commit
  content.

**Risks:**

- If the PAT is over-scoped (e.g., granted `admin` or cross-repo access), a
  compromised workflow could escalate beyond the intended operation. The design
  correctly notes the token should be scoped to minimum permissions, but does not
  specify enforcement.
- The finalize-release job pushes directly to main, bypassing branch protection
  rules (required reviews, status checks). This is inherent to the pattern and
  accepted by koto already, but worth documenting as a known bypass.

**Mitigations already in the design:**

- PAT scoped to `contents: write` only.
- Same token pattern already used by koto (established precedent).

**Suggested additions:**

- Document that the PAT must not have cross-repo scope. A fine-grained PAT
  limited to the shirabe repository is preferred over a classic PAT.
- Note that the finalize-release push bypasses branch protections by design, so
  reviewers understand this is intentional, not accidental.

### Supply Chain or Dependency Trust

**Applies:** Yes

**Severity:** Low

The design introduces a runtime dependency on `jq` in two contexts: the
check-sentinel.sh CI script and the /release skill's local pre-tag step. It also
depends on GitHub Actions runner images providing standard tools (`git`, `gh`).

**Assessment:**

- `jq` on CI runners comes from the GitHub-hosted runner image (ubuntu-latest),
  which is maintained by GitHub. This is standard and low-risk.
- `jq` on the developer's local machine (for the /release skill) is outside the
  design's control but is a common, well-established tool.
- The design does not introduce new GitHub Actions from third-party authors. The
  workflow uses only built-in actions (`actions/checkout`, `gh` CLI). This is
  good practice.
- No new package dependencies are added to any lockfile or manifest.

**Risks:**

- If a future version of the workflow adds third-party Actions (e.g., for release
  note generation), supply chain risk would increase. The current design avoids
  this.

**Mitigations already in the design:**

- Uses `jq` for JSON manipulation instead of `grep`/`sed`, which avoids injection
  from malformed JSON.
- No third-party Actions introduced.

No additional mitigations needed for the current design.

### Data Exposure

**Applies:** No

This design does not access or transmit user data, telemetry, credentials (beyond
the CI secret), or system information. The only data flowing through the system is:

- Version strings (public, embedded in manifest files).
- Release notes (public, derived from commit history and written by the release
  operator).
- The RELEASE_PAT secret, which is handled by GitHub's secret masking and never
  logged or exposed in outputs.

No new data collection, transmission, or storage is introduced.

## Recommended Outcome

**OPTION 2 - Document considerations**

## Summary

The design has a clean security posture. The only meaningful concern is the
RELEASE_PAT permission scope: it should be documented as a fine-grained PAT
limited to the shirabe repository with `contents: write` only, and the direct
push to main (bypassing branch protections) should be acknowledged as intentional.
These are documentation items, not design changes -- the architecture itself
introduces no new attack surface beyond the established koto pattern.
