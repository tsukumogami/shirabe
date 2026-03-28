<!-- decision:start id="ci-sentinel-validation" status="assumed" -->
### Decision: CI validation for sentinel enforcement

**Context**
Shirabe's release process uses a sentinel value (0.0.0-dev) in manifest files on
main. Real version numbers are injected only at release time via the tag-triggered
release workflow. Without CI enforcement, a contributor could accidentally commit
a version bump to plugin.json or marketplace.json in a PR, breaking the sentinel
contract and causing the release workflow to either double-bump or produce incorrect
version metadata.

The repo already has three CI workflows, all following a consistent pattern:
path-filtered triggers, single-concern validation, and shell scripts in `scripts/`
for non-trivial logic. The sentinel check needs to fit this established pattern
while providing clear error messages for contributors unfamiliar with the sentinel
convention.

**Assumptions**
- The sentinel value will be exactly the string "0.0.0-dev" -- a simple equality
  check is sufficient rather than pattern matching. If wrong: the check script
  would need regex or range-based validation instead.
- Only `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` contain
  version fields that need sentinel enforcement. If wrong: additional files would
  need to be added to the check script.

**Chosen: Dedicated workflow with shell script**
A new workflow file (`.github/workflows/check-sentinel.yml`) triggers on PRs that
modify `.claude-plugin/**`. It runs a shell script (`scripts/check-sentinel.sh`)
that parses both JSON files and verifies all version fields equal "0.0.0-dev".

The workflow follows the check-evals pattern exactly:
- Path-filtered to `.claude-plugin/**` changes
- Single job, single step calling the script
- The script produces clear pass/fail output with actionable guidance

The script uses `python3 -c` (already available in the check-evals workflow via
`actions/setup-python`) or `jq` to extract version fields from both JSON files.
On failure, it prints which file has the wrong version and what value was found,
along with a message explaining the sentinel convention.

**Rationale**
This approach scores highest on consistency with established patterns. All three
existing workflows use the same structure: path-filtered trigger, focused concern,
script in `scripts/`. Adding a fourth workflow that follows the same pattern keeps
the CI setup predictable for contributors. The script is locally runnable, so
contributors can debug failures without pushing to CI. Keeping the sentinel check
in its own workflow means it runs only when manifest files change, avoiding
unnecessary CI minutes on unrelated PRs.

**Alternatives Considered**
- **Inline workflow check (no script)**: Puts validation logic directly in the
  workflow YAML `run:` step. Rejected because it breaks the pattern of script-backed
  checks, can't be run locally for debugging, and saves only one file at the cost
  of consistency.
- **Add to an existing workflow**: Extends check-evals.yml or similar with an
  additional sentinel job. Rejected because it violates single-concern design,
  requires broadening path filters (skills changes would trigger manifest checks),
  and makes the workflow name misleading.
- **Pre-commit hook only**: Local git hook validates the sentinel before commit.
  Rejected because hooks are voluntary, easily bypassed, and don't provide the
  enforcement guarantee that CI does. Could be added as a complement but not as
  the primary mechanism.

**Consequences**
Adding a fourth workflow increases the CI surface area slightly, but the check is
fast (no tool installation, just JSON parsing) so it won't meaningfully impact PR
feedback time. Contributors modifying manifest files will see a clear sentinel
check in the PR checks list. The shell script in `scripts/` provides a local
debugging path. The path filter means the vast majority of PRs (which don't touch
`.claude-plugin/`) skip this check entirely.
<!-- decision:end -->
