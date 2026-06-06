# Security Review: shirabe-pattern-v1-ergonomics

**Dispatch context:** Serial-self security review under sub-agent dispatch from /scope. Independence-loss caveat applies — one agent evaluating the security dimensions; rubric is applied against each dimension's specific lens without cross-contamination across lenses.

## Dimension Analysis

### External Artifact Handling

**Applies:** No

The design produces and modifies markdown documentation files (`skills/<name>/SKILL.md`, reference markdown under `references/` and `skills/<name>/references/`, format reference markdown, the CLAUDE.md convention header) and adds Rust code to the existing `crates/shirabe-validate` crate. The Rust changes extend three existing checks/functions with notice-level emissions; no new external input sources, no new download/extract/execute paths, no new network endpoints. The validator continues to operate against committed-on-disk markdown only. The shared reference `references/cli-version-preflight.md` describes a `shirabe <subcommand> --help` capability probe that runs against the workspace's already-installed `shirabe` binary; no new external CLI is introduced.

### Permission Scope

**Applies:** No

The new validator checks read from the workspace's own files (`skills/writing-style/SKILL.md` for FC10, `plan-format.md` for FC11, the artifact under validation for SCHEMA-MISSING extension). No filesystem permission escalation beyond what `shirabe validate` already requires (read access to the worktree). The slug-prefix sampling step in `/scope` Phase 0 reads from `docs/briefs/`, `docs/prds/`, `docs/designs/`, `docs/plans/` — directories the existing `/scope` already reads to detect existing artifacts. No new directory accesses, no new write paths beyond the existing chain's write paths (durable artifacts plus `wip/`).

### Supply Chain or Dependency Trust

**Applies:** No

No new Rust crate dependencies are added to `crates/shirabe-validate/Cargo.toml`. The three new check functions use the same `Doc`, `FormatSpec`, `ValidationError` types the existing checks use. The new shared reference `references/cli-version-preflight.md` describes a probe pattern; it does not download or execute anything external. The `parent_orchestration:` sentinel reading is from the parent skill's state file at a known path; no cross-process IPC, no shared memory, no inter-skill substrate beyond the existing pattern-v1 wip/ filesystem convention.

### Data Exposure

**Applies:** Bounded, no new exposure surface

The `motivating_context:` optional frontmatter field documented per R12 accepts a cross-repo reference that MAY point at a private artifact. The field is metadata — the link target is referenced, not described. The visibility rule from `references/cross-repo-references.md` (read by Phase 0's step 0.4a) applies: public-repo artifacts can reference private artifacts by issue number or repo-relative path, but the public artifact does not contain the private content. The R12 field documentation explicitly states the field is allowed to point at a private artifact from a public document; the design doc's Context section above confirms public-repo readers see only the reference identifier, not the private content.

The verdict-artifact preamble convention (per Decision 1's serial-self-jury fallback) surfaces the operating context including the independence-loss caveat. The preamble is committed to git history (verdict files under `wip/research/` are not deleted until the end of the chain's cleanup phase, but Phase 6 verdict preambles also live in the artifact's own Status section when the operating context warrants — the PRD itself does this at `docs/prds/PRD-shirabe-pattern-v1-ergonomics.md:30-39`). No private information is exposed; the operating context is workflow metadata. The convention preserves audit-trail integrity without creating a new data-exposure surface.

The validator's FC10 writing-style check emits notices identifying banned-word matches in committed artifacts. The notices contain the banned word, the file path, and the line number — no private content beyond what was already in the committed file. The check operates on already-public content; it surfaces violations of a writing-style convention, not data.

The validator's CLAUDE.md `## Release Notes Convention:` value (per R28) is a workspace-policy path; the path itself is non-sensitive (it names a directory or file under the workspace, not a credential). No exposure surface.

## Recommended Outcome

**OPTION 2 — Document considerations.**

The design has bounded data-exposure considerations around (a) the `motivating_context:` cross-repo reference field, (b) the verdict-preamble operating-context disclosure pattern, and (c) the validator's writing-style notice emission. None require design changes; each is worth a one-sentence note in Security Considerations so downstream implementers understand the boundary.

## Summary

The design adds advisory checks and convention-level rules; no new external inputs, no new permissions, no new dependencies, no new exposure surface. The three bounded data-exposure considerations (cross-repo reference field, verdict-preamble disclosure, validator notice emission) are workflow metadata that operates on already-public content. Document considerations and proceed.
