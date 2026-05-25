# Security Review: shirabe-progression-authoring

## Scope and method

The design is a documentation-only initiative defining a parent-skill
pattern contract for shirabe's strategic-progression authoring chain.
It commits to (a) four new pattern-level reference files under
`references/`, (b) a SKILL.md template each parent skill follows,
(c) a two-layer contract surface (semantic invariants plus a YAML
reference state schema serialized into `wip/<parent>_<topic>_state.md`),
(d) a shared resume-ladder template, and (e) a team-shape declarator
mechanism. There is no code component, no network surface, no secret
handling, and no external-process invocation introduced by the design
itself. All filesystem activity is local to the worktree: writes to
`docs/<type>/`, `wip/<parent>_<topic>_state.md`, child-skill `wip/`
intermediates, and `skills/<name>/`. Reads include CLAUDE.md
(visibility header), child doc frontmatter `status:`, the git blob
hashes of child docs, and — for the rejection sub-shape — the discard
commit SHA from `git log`. The pattern crystallizes existing shirabe
behavior; it does not add new external surfaces.

This review walks the four standard dimensions plus five
project-specific extensions named in the coordinator brief.

## Dimension Analysis

### External Artifact Handling

**Applies:** Yes — partially. The design has the parent skill ingest
*author-controlled* inputs (a topic slug as `$ARGUMENTS`) and *local
file system* inputs (child doc frontmatter, CLAUDE.md visibility
header, sibling-edit blob hashes, `/strategy`'s discard commit SHA).
None of these originate outside the local repository. There is no
download step, no remote-fetch action, no execution of external
binaries, and no parsing of network-sourced data.

The relevant sub-surfaces:

- **Topic-slug input (R3, AC3, AC3b).** The pattern hard-enforces
  `^[a-z0-9-]+$` at Phase 0 and rejects on mismatch. This is the
  exact mitigation pattern that defeats path traversal (`../`),
  shell metacharacters, and filename injection into the
  `wip/<parent>_<topic>_state.md` and
  `docs/<type>/<TYPE>-<topic>.md` paths. The constraint matches
  `/strategy`'s existing constraint by design (R3 rationale).
  Severity: **low** — the constraint is already a load-bearing
  pattern invariant; the design ratifies it rather than introducing
  it. No additional mitigation needed.

- **State-file parsing on resume (R11, AC20c).** The design mandates
  a hard surface for malformed state files (R11: "MUST surface a
  clear error naming the malformation and offer Discard as a
  recovery path. The ladder MUST NOT silently fall through to Phase
  0"). This is the right behavior: the state file is committed to a
  feature branch as a YAML document with `.md` extension, and a
  malformed or maliciously-crafted state file could otherwise mask
  loss-of-state or trigger silent fall-through. Severity: **low**
  given the explicit hard-surface requirement. The state file is
  author-authored (committed by the same author running the skill)
  — there is no untrusted-author scenario in the current threat
  model.

- **Child doc frontmatter and git blob hashes (R11, R14).** A parent
  reads each child doc's frontmatter `status:` and computes a git
  blob hash for drift detection. Both reads are local-filesystem
  and local-`git` operations against files the same author is
  working with. The R14 widening explicitly restricts reads to
  "durable externally-visible status surface" — frontmatter +
  blob-hash for doc-emitting children; issue/PR state + labels +
  CI rollup for issue/PR-emitting children. The contract is
  *narrow-by-default*: no reading of child internals,
  `wip/research/`, or CI logs. Severity: **low**.

- **Discard commit SHA in rejection sub-shape (R8, R15, US-3a).**
  `/charter` reads the SHA of `/strategy`'s `git rm ...` commit and
  embeds it in the Decision Record body. SHAs are 40-hex strings;
  the read surface is well-bounded. Severity: **none**.

No mitigations beyond what the design already specifies.

### Permission Scope

**Applies:** Yes. The design's permission requirements:

- **Local filesystem writes** to `docs/<type>/`, `wip/`, and (during
  Stage 2 of Implementation Approach) `skills/<name>/`. All paths
  are author-controlled and inside the repo worktree. No
  out-of-worktree writes.
- **Local git reads** for `git log` (rejection sub-shape SHA) and
  `git cat-file` / blob-hashing (drift detection). No git writes
  beyond what `/strategy`'s existing `git rm` + commit performs;
  the design does not introduce new git mutations.
- **No network access.** The design specifies no HTTPS calls, no
  API queries, no external resolvers. The "conditional feeder
  invocation" pattern (Decision 6) checks for
  `skills/<feeder-name>/SKILL.md` existence on disk; no network
  side-effect.
- **No process spawning** beyond what the underlying skill system
  already does (skill-loader transitions). No `exec`, no shell-out
  to user-supplied commands.
- **No privilege escalation.** Slash commands run in the existing
  Claude Code authoring environment; the design does not raise the
  permission ceiling.

The slug constraint (R3) and the malformed-state hard-surface (R11)
together defeat the obvious permission-scope risks (path traversal
into out-of-worktree directories; out-of-bounds writes via attacker-
controlled state). Severity: **low**, with mitigations already in the
design.

### Supply Chain or Dependency Trust

**Applies:** Yes — narrowly, to the in-repo skill-loading surface.
The design does not pull external dependencies, no `go get`, no
`npm install`, no fetched archives. The supply chain is the set of
files inside the shirabe repo and the cross-skill references via
`${CLAUDE_PLUGIN_ROOT}/references/`.

Sub-surfaces worth surfacing:

- **`${CLAUDE_PLUGIN_ROOT}/references/<file>.md` resolution.** All
  four new pattern-level references load via this variable.
  Provided the loader resolves `CLAUDE_PLUGIN_ROOT` to the plugin's
  own root (and does not allow author-controlled paths to escape via
  `../` segments), the references are bounded to the plugin tree.
  The design's Key Assumptions (Decision 1) state: "shirabe's loader
  resolves `${CLAUDE_PLUGIN_ROOT}/references/<file>.md` uniformly
  from SKILL.md, phase files, and eval files." This is an assumption
  about the loader, not a property the design enforces; if the
  loader has a path-traversal flaw, the pattern inherits it. See
  the project-specific extension "Skill loader path resolution"
  below for a directly-applicable assessment.

- **Conditional-feeder skill-existence check (R5, Decision 6).**
  `/charter` checks `skills/comp/SKILL.md` existence on disk before
  invoking. This is the right shape — checking for a file at a
  known path inside the plugin tree, not following a symbolic
  reference. The check itself is a stat; the invocation is by name
  (`/comp`), not by author-controlled path.

- **Shared eval baseline via copy-paste with canonical source
  (Decision 4).** Each parent's `evals.json` includes a baseline
  scenario set copied from `/charter`'s canonical evals. Copy-paste
  reduces drift risk and removes a `$ref` indirection. The trust
  boundary is the in-repo eval files; no remote eval registry.

Severity: **low**. The design does not introduce new dependency
relationships; it ratifies the existing skill-loading model.

### Data Exposure

**Applies:** Yes. The design's data-exposure surfaces:

- **`docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md`
  body content (R15).** The rejection sub-shape's Decision Record
  embeds the author's stated rejection rationale and a reference to
  the discard commit SHA. The re-evaluation sub-shape embeds
  "evidence cited" (URLs, file paths, paraphrased findings). The
  Decision Record is committed to the public-by-default shirabe
  repo (or to whatever repo `/charter` runs in; see CLAUDE.md
  visibility detection below). Authors retain editorial control
  over what they paste into the Decision Record.
  Severity: **none** — the author drives content; the design does
  not auto-include any system data.

- **`wip/<parent>_<topic>_state.md` content.** The state file
  carries the topic slug, phase pointers, planned chain, exit
  marker, exit-artifact paths, child snapshots (path + status +
  blob hash), and conditional fields like `triggering_child`,
  `partial_phase_reached`, `rejection_rationale`,
  `discard_commit_sha`, `referenced_strategy`. No secrets, no
  credentials, no external identifiers (no user emails, no auth
  tokens). The `rejection_rationale` field is the only free-text
  field that could carry author-supplied prose — same surface as
  the Decision Record body and same author-editorial-control
  property.

- **`wip-hygiene` rule interaction (SE4 directive 9).** The design
  intentionally persists `wip/` artifacts as durable evidence (no
  Phase 6 cleanup); this departs from the workspace's usual
  wip-hygiene rule of "clean before merge." See the "wip/ artifacts
  in committed branches" project-specific extension below.

- **CLAUDE.md visibility detection (R12).** The header read is
  workspace-level; no PII traverses. The default-Private behavior
  fails closed (restricting is the safe direction). See the
  "CLAUDE.md visibility detection" project-specific extension below.

No new exposure beyond what the author already chooses to commit.
Severity: **low**.

## Project-Specific Extensions

### Public repo content safety

**Applies:** Yes — and the design handles it explicitly. R12
(ratified verbatim) reads CLAUDE.md's `## Repo Visibility:` header
and defaults to Private on missing-header. R5 (carter-specific but
relevant) gates `/comp` invocation on Private-visibility AND
skill-existence. The chain's discovery prompts NEVER mention `/comp`,
"competitive analysis", or "competitive framing" in public repos
(AC7) — the degenerate-silence rule (R5) is explicit.

The design references existing artifacts (PRD, decision reports,
prior skill names) but **does not name any private repo, private
artifact, or private project**. The Decision 2 substitution-surface
framing names "amplifier-layer substrate" abstractly without binding
it to a specific private codebase. The team-coordinator brief calls
the work "public visibility" and the design's own status block
clarifies the same.

I checked the design for any of: explicit reference to `tsukumogami`
private overlay, private repo names (`vision`, `tools`,
`coding-tools`, `dot-niwa-overlay`), private artifact paths
(`private/...`, `tsukumogami/...`), or strategic-positioning content
that could leak competitive framing. None present. The only
near-the-line reference is "competitive analysis" used to explain
why `/comp` exists (R5 rationale) — which is appropriate public
documentation of the *shape* of a feature, not a specific
competitive claim.

Severity: **none**. The design's degenerate-silence rule (R5) plus
the missing-header default-Private rule (R12) together cover the
public-repo content-safety risk for the future `/comp` feature.

### wip/ artifacts in committed branches

**Applies:** Yes — and surfaces a moderate-severity leakage surface
that the design should call out explicitly.

The design intentionally persists `wip/` artifacts as durable
evidence (SE4 directive 9 overrides the `/design` skill's Phase 6
wip/ cleanup). This means:

- `wip/<parent>_<topic>_state.md` lives on the feature branch and
  is committed to feature branch git history.
- Per the workspace CLAUDE.md's wip-hygiene rule, "Files under
  `wip/` are non-durable. They MUST NOT be referenced from any
  committed final artifact ... and they MUST be removed from the
  branch before a PR can merge."
- PRs use squash-merge, so `wip/` artifacts never appear in main.

The state file's contents (topic slug, planned chain, exit marker,
`rejection_rationale`, `referenced_strategy`, etc.) are present in
feature-branch git history *until squash-merge*. For the period
between commit and merge, anyone with read access to the branch can
see the contents.

**Leakage surface assessment.**

- **In-repo (public).** Feature branches in the public shirabe repo
  are public. State-file contents become public on push and remain
  public until squash-merge cleans them out of main's history (the
  squash collapses the feature branch's commits into a single main
  commit that doesn't include `wip/` files). Anyone watching the
  repo can scrape feature branches before merge.
- **In-repo (private overlay).** The same mechanism applies; the
  visibility ceiling is the repo's visibility. The design is shipped
  in the public shirabe repo, so the relevant ceiling is public.
- **Rejection sub-shape rationale.** The author-supplied
  `rejection_rationale` field is the most-likely-to-be-sensitive
  content. The same content appears in the Decision Record (also
  committed) — so the state-file copy is not the marginal exposure;
  the Decision Record is.

**Mitigations the design should specify.**

The design's Consequences section names "Negative: Cross-branch
resume is unimplemented in v1" but does not explicitly name
*pre-merge feature-branch wip/ visibility* as a known property.
Authors who paste sensitive context into `rejection_rationale` or
into Phase 1 discovery prompts that end up in the state file MAY
not realize the state file is public-on-push. The Decision Record
documentation gap is more severe because the Decision Record is
explicitly a durable artifact.

Recommend the Security Considerations section name this property
explicitly: **"State files and Decision Records committed to a
public repo are public on push. Authors should treat
`rejection_rationale`, `discard_commit_sha` (this is non-sensitive),
and Decision Record body content as durably public; do not paste
secrets, internal-team-only context, or unpublished competitive
positioning into these fields."**

Severity: **low-to-moderate** because the property is intrinsic to
public-repo workflow rather than novel to this design, but it
deserves explicit author-facing documentation. The design itself
introduces no new mechanism that worsens the leakage; it inherits
the existing public-repo property and persists the wip/ artifacts
that would otherwise be cleaned.

### Cross-branch state-file behavior (invariant I-6)

**Applies:** Yes. The design names I-6 (cross-branch resume) as a
pattern invariant the v1 core-layer implementation explicitly does
NOT satisfy. Three related scenarios deserve security framing:

1. **Merge a child PR, then try to resume `/charter` on main.** The
   wip/ state file is on the feature branch, not main. Resume on
   main fails the ladder; the design says "starts fresh (no
   cross-branch state inheritance)." This is the right failure mode:
   no silent cross-pollination, no state leakage from feature
   branch to main. The user sees a fresh chain. Severity:
   **none** — fail-closed is correct.

2. **Rebase or squash a feature branch with state files present.**
   A `wip/<parent>_<topic>_state.md` that gets squashed away
   disappears from the resulting commit, but the durable artifacts
   under `docs/<type>/` remain. The resume ladder will detect
   the durable artifact (e.g., Accepted STRATEGY) on the next
   `/charter` resume and fire the status-aware re-entry prompt
   (R11, AC18). This is the same surface as US-4 (manual fallback)
   and is handled correctly. Severity: **none**.

3. **Re-use a topic slug across multiple feature branches.** Two
   different feature branches could each have their own
   `wip/charter_<topic>_state.md` with the same topic. They are
   isolated by branch — invariant I-4 (state is topic-keyed)
   continues to hold because there is at most one state-file per
   branch per topic. No state leakage between branches.
   Severity: **none**.

The cross-branch limitation is a *functional* gap (the parent run
cannot resume on a different branch) rather than a *security* gap
(no data leaks, no privilege escalation, no integrity violation).
The design's framing as invariant I-6 with fail-closed v1 behavior
is the right shape.

### Skill loader path resolution

**Applies:** Yes — and merits an explicit assumption check.

The pattern-level references all load via
`${CLAUDE_PLUGIN_ROOT}/references/<file>.md`. The design assumes
(Decision 1, Key Assumptions): "shirabe's loader resolves
`${CLAUDE_PLUGIN_ROOT}/references/<file>.md` uniformly from
SKILL.md, phase files, and eval files."

The implicit security property is: **`${CLAUDE_PLUGIN_ROOT}` is
resolved by the loader at load time, not by author-controlled
input.** If a loader implementation allowed `..` segments in the
reference path or interpolated author-controlled text into the
resolved path, a malicious skill author could escape the plugin
tree.

The design itself does not introduce loader behavior; it consumes
the loader as-is. Reference paths in the design are author-time
constants (e.g., `references/parent-skill-pattern.md`), not
runtime-interpolated from author input. The slug constraint (R3)
keeps author input narrow.

Severity: **none** for this design, **note worth surfacing** for
the loader implementation review (out of scope for this design).
No mitigation required in the design doc; the implementation phase
(`/charter`'s SKILL.md authoring under Stage 2) should be reviewed
to confirm reference paths are constants.

### CLAUDE.md visibility detection (R12)

**Applies:** Yes. The design ratifies R12 verbatim: missing-header
defaults to Private. This is fail-closed — the unsafe direction is
"treat as Public and surface `/comp` content" — and the design
correctly chooses the conservative default.

**The known-edge case the design documents (PRD known-limitations
line 1085-1090): "A public repo without the `## Repo Visibility:`
header would surface `/comp` prompts in `/charter` Phase 1 if
`/comp` were shipped."** This statement is INVERTED from the actual
behavior — the default is Private, which means missing-header in a
public repo causes `/comp` prompts to surface (because the skill
*thinks* it's Private). This is a documentation inconsistency in
the PRD, not a design defect: the design's R12 ratification is
correct, and the design names the default-Private behavior in the
correct direction (Solution Architecture's Parent ⇄ workspace
interface section: "Missing-header default is Private with a
warning").

The actual security property: **a public repo that forgets to
declare visibility will get the *more restrictive* behavior**
(Private treats `/comp` as eligible-to-offer). The risk is that
`/comp`-driven competitive-analysis prompts might surface in a
public repo. The compensating mitigations:

- `/comp` is gated by skill-existence (R5), and is not yet shipped.
  When it ships, the integration becomes live.
- The warning text ("Default to Private if unknown — restricting is
  easier to undo than oversharing") prompts the author to fix the
  CLAUDE.md before continuing.
- The author can correct visibility before any `/comp`-related
  prompts get committed (the chain proposal output is interactive).

**The PRD-doc inconsistency is worth flagging back to the PRD or
the design's Open Questions.** The design doc itself is correct;
the PRD's known-limitation phrasing should be updated when the PRD
gets revised. For this security review, the design's behavior is
the safer of the two choices: any directional ambiguity defaults to
Private, which prevents accidental public-repo competitive surface.

Severity: **low**. The fail-closed default is correct; the PRD's
phrasing inconsistency is a documentation artifact, not a design
flaw.

## Recommended Outcome

**OPTION 2 - Document considerations.**

The design has no security-blocking issues and needs no design
changes. The four standard dimensions all apply at low severity
because the design ratifies existing safe patterns (slug constraint,
fail-closed visibility default, no-network-access, no-secret-handling)
and explicitly hard-surfaces malformed state files. The
project-specific extensions surface two items that deserve named
documentation in the design's Security Considerations section: the
pre-merge feature-branch visibility of wip/ state files in a public
repo, and the fail-closed-Private-on-missing-CLAUDE.md-header
property.

The recommended Security Considerations section content:

---

### Security Considerations

The parent-skill pattern adds no network surface, no external-
artifact ingestion, no secret handling, and no privilege
escalation. Filesystem activity stays inside the worktree: parent
skills write to `docs/<type>/` and `wip/<parent>_<topic>_state.md`,
read child doc frontmatter and git blob hashes, and (for the
rejection sub-shape) read a discard commit SHA from `git log`.
All inputs that affect filesystem paths are constrained by the
topic-slug regex (`^[a-z0-9-]+$`, R3) which is hard-rejected at
Phase 0; the resume ladder hard-surfaces malformed state files
(R11) rather than silently falling through. The conditional-feeder
invocation pattern (Decision 6) gates child-skill invocation on a
local skill-existence check, not on author-controlled paths.

Two visibility properties deserve explicit author-facing
documentation:

- **Public-repo pre-merge visibility of wip/ state files.** The
  pattern persists `wip/<parent>_<topic>_state.md` on feature
  branches as durable evidence. In a public repo, feature-branch
  contents become public on push. Authors should treat fields the
  state file carries — particularly the free-text
  `rejection_rationale` and the `referenced_strategy` path — as
  durably public from the moment the branch is pushed; squash-merge
  removes the wip/ files from the main branch's history but does
  not remove them from the feature branch's pre-merge history. The
  same property applies to the Decision Record body (which is a
  durable artifact, never cleaned). Authors should not paste
  secrets, customer-identifiable context, or unpublished
  competitive positioning into these fields. This is an inherited
  property of the public-repo workflow; the design does not worsen
  it, but the persistence of wip/ artifacts (Decision 12 of design
  drivers, SE4 directive 9) means the surface lives longer than
  under the workspace's default wip-hygiene rule.

- **Fail-closed visibility default.** Per R12 (ratified verbatim),
  a missing `## Repo Visibility:` header in CLAUDE.md causes the
  parent skill to default to Private and emit a warning. This is
  the conservative direction: a public repo that forgets to
  declare visibility gets the more-restrictive behavior (a Private
  treatment that could cause future `/comp` prompts to surface).
  The compensating mitigation is the warning text ("Default to
  Private if unknown — restricting is easier to undo than
  oversharing") which prompts the author to correct the CLAUDE.md
  before continuing; the chain-proposal output (R7.5) is
  interactive, so the author confirms intent before any
  visibility-gated content lands. Repos declaring public visibility
  explicitly avoid this surface entirely.

Cross-branch resume (invariant I-6) is unimplemented in v1 by
design. The v1 behavior is fail-closed: a resume on a different
branch starts a fresh chain rather than inheriting state across
branches. No data leaks between branches; no privilege escalation
across branches; the limitation is functional, not security-
relevant.

No third-party dependencies are added by this design. The shared
eval baseline (Decision 4) is copy-and-adapted across parents
rather than ref-imported; the trust boundary is in-repo files.

---

## Summary

The design is documentation-only and adds no security-blocking
surfaces. The four standard dimensions all apply at low severity:
external-artifact handling is constrained by the slug regex and the
malformed-state hard-surface; permission scope is local-filesystem
only; supply chain stays in-repo; data exposure is bounded to
author-driven content. Two project-specific items merit explicit
documentation in the design's Security Considerations section —
public-repo pre-merge visibility of wip/ state files (a property of
the durable-evidence policy under SE4 directive 9) and the
fail-closed Private default for missing CLAUDE.md visibility headers
— both already handled correctly by the design, but worth surfacing
to authors. Recommended outcome: ship the Security Considerations
section drafted above; no design changes required.
