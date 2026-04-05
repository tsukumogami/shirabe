# Cross-Repo Artifact References

Convention for referencing artifacts in other repositories from `upstream`
frontmatter fields.

## Default: same-repo relative paths

Most `upstream` values are relative paths within the same repo:

```yaml
upstream: docs/visions/VISION-foo.md
upstream: docs/roadmaps/ROADMAP-bar.md
upstream: docs/prds/PRD-baz.md
```

Use relative paths whenever the upstream artifact lives in the same repository.

## Cross-repo syntax

When the upstream artifact lives in a different repository, use the
`owner/repo:path` format:

```yaml
upstream: tsukumogami/shirabe:docs/designs/DESIGN-foo.md
upstream: tsukumogami/vision:docs/visions/VISION-bar.md
```

The first colon separates the repository identifier from the file path.
The repository identifier uses the GitHub `owner/repo` format.

## When to use cross-repo references

Cross-repo references are the exception, not the norm. Use them when:

- A private repo's strategic artifact (VISION, Roadmap) spawns tactical
  work in a public repo
- A public repo's artifact needs to trace back to another public repo's
  upstream artifact
- A design doc in one repo references a parent design in another

## Visibility rule

**Public repos must not reference private repo artifacts.** This rule is
enforced by content governance (see `skills/public-content/SKILL.md`),
not by tooling. If a public artifact's true upstream lives in a private
repo, omit the `upstream` field rather than referencing a resource that
external contributors can't access.

The directional rule:

| From | To | Allowed |
|------|----|---------|
| Private | Private | Yes |
| Private | Public | Yes |
| Public | Public | Yes |
| Public | Private | **No** |

## Examples

| Artifact | upstream value | Meaning |
|----------|---------------|---------|
| Roadmap in shirabe | `docs/visions/VISION-pipeline.md` | Same-repo VISION |
| PRD in shirabe | `docs/roadmaps/ROADMAP-strategic-pipeline.md` | Same-repo Roadmap |
| Design in shirabe | `docs/prds/PRD-traceability.md` | Same-repo PRD |
| Roadmap in private vision repo | `tsukumogami/shirabe:docs/roadmaps/ROADMAP-foo.md` | Cross-repo, private -> public |

## Anti-patterns

- **Relative cross-repo paths** (`../../other-repo/docs/...`): breaks when
  repos are cloned to different locations. Use `owner/repo:path` instead.
- **Stale references**: cross-repo paths can't be validated by local
  tooling. Verify manually when the referenced artifact may have moved.
- **Public referencing private** (`tsukumogami/vision:docs/...` in a
  public repo): violates visibility rules. Omit the field instead.
