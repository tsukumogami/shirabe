<!-- decision:start id="utilities-sharing" status="assumed" -->
### Decision: Utilities Sharing for Completion Cascade

**Context**

The completion cascade needs two categories of utility logic that already exist in
the private tools repo: frontmatter extraction (to walk `upstream` chains between
artifact docs) and GitHub API querying (to confirm issues are actually closed before
marking a ROADMAP Done). Shirabe is a public repo and cannot reference or source
files from the private tools repo at runtime.

The private `scripts/ci/checks/common.sh` provides `extract_frontmatter()`,
`get_frontmatter_status()`, and `has_frontmatter()` — built for CI validation
orchestration with `emit_pass`/`emit_fail` conventions. The private
`scripts/ci/get-github-status.sh` batch-queries the GitHub API for issue and
milestone state, returning a JSON map. Neither file can be sourced directly.

Shirabe's established pattern — visible across all three existing transition scripts
(`skills/design/scripts/transition-status.sh`, `skills/prd/scripts/transition-status.sh`,
`skills/roadmap/scripts/transition-status.sh`) — is to inline frontmatter parsing
locally in each script rather than sharing a common library. All three contain nearly
identical `has_frontmatter()` and `get_frontmatter_status()` implementations. This
duplication is not accidental; it keeps each script self-contained and dependency-free.

**Assumptions**

- Decision 1 (cascade orchestration form) has not yet resolved. If the cascade is
  fully agent-driven directive prose with no bash component, this decision is moot.
  This report assumes a bash script component exists for at least the chain-walking
  and GitHub status check steps.
- The cascade's frontmatter need is for arbitrary field extraction (specifically the
  `upstream` field), not just `status` — a superset of what private common.sh provides.
- Eval coverage is achievable for an inlined implementation via scenario-based evals
  that feed fixture documents to the cascade script.

**Chosen: Inline utilities in the cascade script**

The cascade script (`scripts/cascade.sh` or similar) implements its own
frontmatter field extraction and GitHub status querying inline, following the same
pattern as the existing transition scripts. No shared library file is introduced.

The implementation requires roughly:
- A `get_frontmatter_field <field> <doc>` function (~15 lines, using `sed` or `awk`)
  that generalizes what the transition scripts already do for the `status` field
- A `check_issue_closed <url>` function (~30-40 lines, using `gh api` and `jq`)
  that mirrors the core loop in `get-github-status.sh` without the batch-processing
  scaffolding

Total addition: approximately 50-60 lines of bash within the cascade script's
utility section.

**Rationale**

The inlining approach is consistent with shirabe's established pattern, keeps the
cascade script dependency-free, and produces a smaller, more targeted implementation
than porting private common.sh (which was built for CI validation orchestration with
conventions irrelevant to cascade use). Porting common.sh would introduce a new
library layer in shirabe that doesn't currently exist, maintenance divergence risk
versus the private source, and an interface (emit_pass/emit_fail/exit codes) the
cascade doesn't use. The actual utility needed — extract a named field from YAML
frontmatter, query one issue URL — is 50-60 lines, well within the script that
consumes it.

**Alternatives Considered**

- **Port common.sh into shirabe**: Creates `scripts/ci/checks/common.sh` in shirabe
  as a shared library sourced by cascade and CI scripts. Rejected because common.sh's
  interface is CI-validation-specific (emit_pass/emit_fail, exit code constants) and
  irrelevant to cascade logic; the cascade needs arbitrary frontmatter field extraction
  that common.sh doesn't provide without extension; and adding a library layer
  contradicts the inlining pattern every other shirabe script follows. The maintenance
  risk (silent divergence from private source) is also undesirable for a 50-line
  utility.

- **Reuse existing transition script side effects**: The cascade calls per-skill
  transition scripts and relies on their JSON output. Rejected because transition
  scripts don't expose the `upstream` field — they only read and update `status`. The
  GitHub issue status check is not served by transition scripts at all. Making this
  work would require modifying all transition scripts to accept and return upstream
  metadata, coupling scripts that are currently independent.

- **Agent reads frontmatter directly**: Since the cascade may be agent-driven
  directive prose (Decision 1 pending), the agent uses file-reading tools to extract
  `upstream` and native `gh` CLI invocations for issue status. Conditionally viable,
  but depends on Decision 1 resolving to a fully agent-driven form. If any bash
  component exists, this option leaves that component without a pattern. Agent-only
  paths are also harder to cover with the eval framework, and the design doc requires
  eval coverage before merge.

**Consequences**

- The cascade script becomes self-contained with no external script dependencies
- The `get_frontmatter_field` function it introduces can be the reference
  implementation if a shared library is ever warranted in the future
- The GitHub status check logic will be duplicated if other future scripts need it,
  but that duplication can be consolidated at that time rather than speculatively
- Eval coverage for the utilities is straightforward: fixture docs with known
  frontmatter fields, fixture issue URLs with known states
<!-- decision:end -->
