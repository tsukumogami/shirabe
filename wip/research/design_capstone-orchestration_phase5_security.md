## Security Considerations

This section is the mandatory Phase 5 security review for the capstone-orchestration
design. The architecture is pull-based and repo-local — it introduces no cross-repo
write path and no always-on service — which removes the highest-severity classes up
front. The remaining surface is concentrated in three places: the new `gh`-backed read
pass over the operator's own credentials, the rendering of cross-repo PR metadata into a
**public** capstone PR body, and the `lifecycle.yml` merge-last gate as the
non-bypassable backstop. The findings below assume the existing controls confirmed in
the codebase (see Threat surface) and prescribe what the new components must add.

### Threat surface

New or widened surfaces introduced by this design:

- **Cross-repo read pass (`shirabe capstone status/sync`, `gate`, `finalize.rs` read pass).**
  Reads each indexed PR and each cross-repo upstream on the operator's own `gh`
  credentials, spanning public AND private repos. New trust boundary: data fetched from
  *other* repos (PR titles, branch names, merge state, issue state) now flows into shirabe
  and onward into a rendered artifact and a CI gate.
- **Public capstone PR body.** The rendered PR-index + fenced merge-order block embeds
  `owner/repo:path` references and PR metadata. On a public capstone, this is a
  cross-visibility egress point (PRD R15).
- **Untrusted `owner/repo:path` and PR metadata as inputs.** Cross-repo references authored
  in the PLAN, plus titles/branch names/numbers read back from `gh`, are interpolated into
  markdown, into shell/`gh` argument positions, and into the gate's decision logic.
- **`/plan` collapse step.** New `repo` and `pr_group` tag values become part of node
  identity, get serialized by a `plan-to-tasks.sh` sibling, and feed the contraction +
  acyclicity logic that decides whether a plan is schedulable.
- **`lifecycle.yml` strict-mode gate.** The merge-last backstop now reads
  attacker-influenceable data (the PR-index in the PR body, per-repo merge state) to decide
  "ready."

Existing controls this design inherits and must not regress (confirmed in the codebase):

- `gh.rs` shells out to `gh api` with `Command`/`.args()` (no shell string), validates
  owner/repo against `^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$` before every call, caps subprocess
  output at 4 MiB, and never holds the token bytes (the `gh` binary owns the token).
- `finalize.rs` confines paths via lexical normalization (no symlink resolution), rejects
  symlinks/non-files, and detects cross-repo refs structurally; `validate_node_path` already
  enforces in-root confinement.
- `run-cascade.sh` quotes all path variables, validates issue URLs against the `origin`
  slug, and passes AWK variables via `ENVIRON[]` rather than `-v` interpolation.
- `plan-to-tasks.sh` validates every generated task name against `^[a-z][a-z0-9-]*$` before
  use and builds JSON with `jq --arg`.

### Findings and mitigations

**F1 — Private content leak through a public capstone PR body (PRD R15). [High]**
*Risk:* The capstone PR is public, but its index and merge-order block render data read
from private repos. The design states "the read pass surfaces only state, not bodies,"
but a private repo's *name*, *path*, *branch name*, *PR title*, and *PR/issue number* are
themselves private content — and `owner/repo:path` references plus PR metadata are exactly
what gets rendered. A public capstone that lists `acme/secret-repo:docs/...` or a private
PR title leaks the existence, naming, and shape of private work.
*Mitigation the design should adopt:* Make the visibility filter explicit and
fail-closed, not a side effect of "state only." Before rendering any node into a public
capstone body, `shirabe capstone` MUST resolve each indexed PR's repo visibility
(via `gh repo view --json visibility` or `github.repository_visibility`) and, for any
private repo, render a redacted placeholder that carries *no* private owner/repo, path,
branch, title, or number — only an opaque, non-reversible node id and merge state. The
canonical source of truth for a public capstone's private dependency is the gate's
boolean, never the private identifier. Add an assertion in the `create`/`sync` render path:
on a public capstone, the rendered body must contain zero references to a repo whose
visibility resolved to private; if visibility cannot be resolved, fail closed (treat as
private). This belongs in `references/capstone-strategy.md` as a hard rule and must be
covered by a unit test feeding a private-repo node into a public render.

**F2 — Path traversal / injection via a crafted `owner/repo:path`. [High]**
*Risk:* `owner/repo:path` strings authored in the PLAN flow into the new read pass and
into write/render paths. `is_cross_repo_ref` currently *detects* the shape structurally but
does not *validate the components*. A crafted value (`../../`, embedded newline, shell
metacharacters, an `owner` or `repo` outside GitHub's charset, or a `path` escaping the
repo root) could traverse paths, poison the rendered body, or reach a `gh`/git argument.
*Mitigation the design should adopt:* The new read pass MUST parse `owner/repo:path` into
its three components and validate each independently *before* use: `owner` and `repo`
against `gh.rs`'s existing `^[A-Za-z0-9][A-Za-z0-9._-]{0,38}$`; `path` against the
in-root, no-symlink, lexical-normalization confinement `finalize.rs` already applies to
node paths (and additionally reject any `path` containing a newline or NUL). Reuse the
existing validators rather than re-implementing — the design already plans to reuse
`is_cross_repo_ref`, so extend that reuse to the component validators. Any reference that
fails validation halts the operation with a diagnostic naming the offending value (R21
halt-on-failure), never silently skipped.

**F3 — Markdown / metadata injection from attacker-controllable PR titles and branch
names. [Medium]**
*Risk:* PR titles and branch names read back via `gh` are written into the capstone PR
body. A malicious or careless title (`](http://evil), ` fenced-block terminators, HTML,
or an `@org/team` mention that fires notifications) can break out of the rendered table,
forge merge-order rows, or inject content into a document reviewers trust as
machine-generated. Forged rows are the dangerous case: the body is the merge-time canon
(Decision D), so a spoofed row could misrepresent the merge order a human reads.
*Mitigation the design should adopt:* Treat all `gh`-sourced strings as untrusted on
render. Escape or strip markdown/HTML control characters from titles and branch names
before interpolation; never place raw `gh` strings inside the fenced merge-order block
whose structure carries meaning. Prefer rendering machine-derived fields (node id, repo,
state) from validated values and treating the human-readable title as a clearly-delimited,
escaped, non-load-bearing annotation. The fenced merge-order block's authoritative fields
MUST derive from validated PLAN/`gh` state, not from free-text titles.

**F4 — Merge-last gate reads attacker-controllable data; spoofed "merged" state. [High]**
*Risk:* `lifecycle.yml`'s strict gate is the non-bypassable backstop (PRD R7/R14/R21). If
the gate's "all indexed PRs merged" decision is computed by parsing the PR *body*
(which a PR author can edit) rather than by authoritative API queries, an author can
delete or rewrite index rows to make the gate pass while per-repo PRs are still open —
bypassing merge-last and creating the partial cross-repo state R21 forbids. Equally, the
gate must not trust a "merged" string in the body.
*Mitigation the design should adopt:* The `gate` verb MUST recompute merge state from
authoritative `gh api` queries against each indexed PR at gate time — never from the
rendered body text. The body is a *display* of state; the gate is a *recomputation* of
state. The list of indexed PRs may be read from the body (it is the durable index per R8),
but each entry's merged/open status and the acyclicity of the order MUST be verified live.
The gate fails closed: any PR it cannot resolve (deleted, renamed, access lost, `gh`
error) is treated as not-merged, blocking the capstone. Pin the gate to the existing
strict-mode trigger (`draft == false`) so it cannot be skipped by toggling draft after
review. Document that the gate's inputs are GitHub-Actions context + live API, not
PR-body free text.

**F5 — Privilege scope and token exposure of the read pass. [Medium]**
*Risk:* The read pass runs on the operator's full `gh` credentials, which may carry write
scope across many repos. The design only needs read. Separately, fetched cross-repo state
or error output could land in logs or in the PR body, and a `gh` failure could surface a
token or a private URL in a diagnostic.
*Mitigation the design should adopt:* State explicitly that all capstone `gh` use is
read-only (`GET`/`view`) — no capstone verb performs a cross-repo write, consistent with
Decision C's "writes stay repo-local." Inherit `gh.rs`'s no-token-in-process property and
do not log raw `gh` responses; redact owner/repo/path/title from any error surfaced on a
public capstone (route private identifiers through the same F1 redaction before they reach
a diagnostic, a log line, or the PR body). The 4 MiB output cap in `gh.rs` should apply to
the read pass to bound a hostile/oversized response.

**F6 — `repo`/`pr_group` tags interpolated into shell and write paths (parent-skill
re-validation rule). [Medium]**
*Risk:* The `/plan` collapse step introduces new `repo` and `pr_group` values that become
node identity, get serialized by a `plan-to-tasks.sh` sibling, and may reach branch names,
file paths, or `gh`/git arguments. `parent-skill-security.md` requires every value
interpolated into a shell command or write path to be re-validated against its regex at
the point of use, including on resume from durable artifacts.
*Mitigation the design should adopt:* Constrain `pr_group` and the `repo` tag to a
validated charset before any interpolation — reuse `plan-to-tasks.sh`'s existing
`^[a-z][a-z0-9-]*$` for `pr_group` and the owner/repo regex for the repo tag. Because the
capstone re-derives state from the PR body on resume (R9, R22), these tags are read back
from a durable, editable artifact and MUST be re-validated on every read before
interpolation — not only at authoring time — matching the slug/enum re-validation-on-resume
rule. Continue building any serialized JSON with `jq --arg`.

**F7 — Acyclicity / scheduling integrity of the contraction step (PRD R13). [Low,
integrity not confidentiality]:** *Risk:* The DAG contraction and acyclicity check decide
whether a plan is schedulable; a bug or a crafted `waits_on`/tag set that defeats the cycle
check could emit a deadlocked or mis-ordered merge plan, and the merge order is the canon a
human follows. *Mitigation:* Treat the acyclicity check as a correctness gate with explicit
test coverage for contraction-induced cycles and self-loops; on any unresolved cycle, refuse
to emit (the design already specifies this) rather than emitting a partial order. Validate
that re-derivation (R22) treating merged PRs as fixed nodes cannot reintroduce a cycle among
the unmerged remainder.

### Residual risks

- **Staleness window.** Between `sync` runs the rendered body can misstate merge state. This
  is acceptable because F4 makes the *gate* recompute live at merge time, so a stale body
  can mislead a human reader but cannot cause a wrong merge. Reviewers should be told the
  body is a snapshot and the gate is authoritative.
- **Operator-credential blast radius.** The read pass is only as confined as the operator's
  `gh` token; a compromised operator environment is out of scope for this design (it is a
  workstation-security problem, not a capstone-design problem). The design reduces, but does
  not eliminate, exposure by being read-only.
- **Human edits to the durable index.** The PR body is editable by the author; the F4 live
  recompute and F1 redaction assertion bound the damage, but a misleading (non-load-bearing)
  annotation could still confuse a reviewer. Accepted, given the gate's independence.
- **Cross-repo references that move.** Per `cross-repo-references.md`, `owner/repo:path`
  cannot be locally validated for existence; a renamed/moved target degrades to a
  fail-closed gate (blocks merge), which is the safe direction.

### Verdict

No blocking security issues — conditional on the design adopting F1 (fail-closed public/private
redaction in the render path), F2 (component validation of `owner/repo:path`), and F4 (gate
recomputes merge state from live `gh` queries, never from PR-body text) as explicit,
testable requirements in `references/capstone-strategy.md`. These three are load-bearing for
PRD R15 and R7/R14/R21; the architecture supports all three with existing seams, so they are
hardening requirements rather than architectural blockers. F3, F5, F6, and F7 are standard
hardening to fold into the same reference and the new code.
