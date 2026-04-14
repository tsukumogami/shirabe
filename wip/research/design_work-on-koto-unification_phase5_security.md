# Security Review: work-on-koto-unification

*Re-run after koto v0.8.0 revision (2026-04-14). Supersedes the prior
review; all references to `plan-deps.sh` / `plan-queue.sh` and the `jq`
dependency are retired with the script itself.*

## Dimension Analysis

### External Artifact Handling

**Applies:** No

This design does not download, execute, or process external inputs from
untrusted sources. All inputs are authored by the same user operating the
workflow:

- PLAN documents are local markdown files written by the user or generated
  by prior workflow phases within the same session.
- `tasks.json` is produced by SKILL.md prose from the PLAN doc and lives
  on the local filesystem; it is submitted via `koto next --with-data
  @tasks.json` which koto reads locally (1 MB cap).
- Koto context keys store locally-produced summaries, review results, and
  failure reasons -- not external content.

The closest thing to "external" input is GitHub issue metadata referenced
from PLAN docs, used as labels and routing keys, not executed or
interpreted as code.

### Permission Scope

**Applies:** Yes (low severity)

**Risks identified:**

1. **Filesystem writes via koto state.** Koto writes parent and child
   state files to its configured state directory. The skill layer writes
   `tasks.json` to `wip/` before submission. Both are scoped to the
   project working directory. No writes occur outside the repository
   tree.

2. **No orchestration script.** The previous revision's shell script has
   been removed. Koto's CLI-level scheduler runs in-process with the
   `koto` binary; no shell interpretation of untrusted strings, no
   `eval`, no dynamic command composition.

3. **Multi-agent spawning.** Review panels spawn 3 parallel agents for
   scrutiny and code review. These operate within Claude Code's existing
   permission model -- no privilege escalation.

**Severity:** Low. All operations stay within the existing permission
boundary of a Claude Code session operating on a local repository. The
surface is smaller than the prior revision (no shell script, no
`jq`-invocation boundary).

**Mitigations (already present):**
- Koto state files follow established conventions with no new filesystem
  scope.
- `--with-data @file` reads a local file path; koto enforces the 1 MB
  cap and rejects malformed payloads pre-append.
- No `sudo`, no network listeners, no daemon processes.

**No additional mitigations needed.**

### Supply Chain or Dependency Trust

**Applies:** Yes (low severity)

**Risks identified:**

1. **Koto v0.8.0 floor.** The design now requires koto v0.8.0 or later.
   Koto is a first-party tool (same organization), so the trust boundary
   is internal. The strict-mode migration (Decision 3) continues to avoid
   the deprecated `--allow-legacy-gates` flag.

2. **No jq dependency.** The prior revision's shell script required `jq`;
   the revised design removes the script entirely, eliminating this
   dependency.

**Severity:** Low. First-party tool upgrade. No new external dependencies
introduced; one dependency (`jq`) removed.

**Mitigations (already present):**
- Koto pinning is handled by the workspace's tsuku installation, keeping
  the version floor under organizational control.
- Shirabe's CI should assert the minimum koto version as part of template
  compilation (noted in design Consequences).

**No additional mitigations needed.**

### Data Exposure

**Applies:** No

This design does not access or transmit user credentials, secrets, API
keys, or personal data:

- Koto context stores workflow artifacts: implementation summaries, review
  panel results, failure reasons, plan metadata. These are developer
  workflow data, not sensitive user information.
- `tasks.json` contains issue numbers, titles, dependencies, and var
  assignments -- already public GitHub data for public repositories.
- No telemetry, no network transmission of workflow state, no logging to
  external services.
- `wip/` artifacts are cleaned before PR merge per existing convention.
- The design's Security Considerations section explicitly notes "No
  credentials or secrets are stored in context."

### Template Variable Interpolation

**Applies:** Yes (low severity, newly called out)

Koto substitutes `vars` entries into gate command strings before shell
execution. Task-list composition in SKILL.md must validate var values to
prevent shell injection via crafted entries:

- `ISSUE_NUMBER` must be numeric (validate against `^[0-9]+$`)
- `PLAN_DOC` must be a valid file path within the repo
- `ISSUE_SOURCE` must match the enum `{github, plan_outline}`
- Task-entry names pass koto's regex `^[A-Za-z0-9_-]+$` (R9)

For plan-backed mode, vars are derived from PLAN doc content authored by
the same user. The attack surface is self-injection -- low severity -- but
the validations above make the pipeline robust against malformed PLAN docs
regardless.

**Severity:** Low. Self-authored content, typed validation at submission
time (koto R0-R9 pre-append).

**Mitigations (already present):**
- Koto's R9 rejects non-regex-matching task names pre-append with typed
  `InvalidBatchReason::NameRegex`.
- SKILL.md's `tasks.json` composer includes documented sanitization for
  var values (design Phase 5 deliverables).

## Recommended Outcome

**OPTION 3: N/A with justification**

This design is a workflow orchestration refactoring that reorganizes how
existing components (koto state machines, skill markdown, review panels)
interact. After the v0.8.0 revision, it introduces no new trust
boundaries, no new external inputs, no new permission requirements, and
no new data flows. The surface is smaller than the prior revision (one
shell script and one `jq` dependency retired). The low-severity items
identified (filesystem writes within the repo, koto version floor, var
interpolation) are already mitigated by the design and koto's own
pre-append validators.

## Summary

This design presents minimal security risk. The v0.8.0 revision reduces
the surface relative to the prior revision: no orchestration script, no
`jq` dependency, and typed pre-append validators for all submissions.
The filesystem, dependency, and variable-interpolation observations are
low-severity and already addressed in the design document's own security
and consequences sections. No design changes or additional security
documentation are needed beyond what the design already includes.
