# Lead: Which tools should shirabe declare, and at what version pinning?

## Findings

### Tool Availability in tsuku Recipes

| Tool | Recipe Exists | Recipe Location | Notes |
|------|--------------|-----------------|-------|
| koto | Org-scoped | `tsukumogami/koto` | Not in main recipes dir; installed via org-scoped syntax |
| gh | Yes | `recipes/g/gh.toml` | Homebrew builder, GitHub version provider |
| jq | Yes | `recipes/j/jq.toml` | Homebrew builder |
| python3 | Unclear | Discovery shows `python@3.12`, `python@3.13` variants | Needs verification |
| claude | No | Not found | No recipe in tsuku |

### Pinning Strategy by Tool

**koto**: Required >= 0.2.1 per shirabe README. Org-scoped recipe (`tsukumogami/koto`). Exact pin recommended since koto lacks version provider infrastructure in tsuku's discovery system.

**gh**: Standard recipe with GitHub version provider. Latest or prefix pin works. Not version-sensitive for shirabe's usage (standard `gh api` and `gh release` commands).

**jq**: Standard recipe. Latest is fine -- jq's API is extremely stable.

**python3/claude**: Recipe availability uncertain. May not be declarable in `.tsuku.toml` yet.

### Org-Scoped Recipe Syntax

CI currently uses `tsuku install tsukumogami/koto -y`. The `.tsuku.toml` format supports org-scoped names based on the design doc's tool requirement parsing, but this needs verification.

## Implications

- koto is the primary tool to declare; it's the only one with a hard version requirement
- gh and jq are good candidates if we want comprehensive declarations
- python3 and claude may need to stay as system dependencies for now
- The org-scoped recipe question (`tsukumogami/koto` vs `koto`) is a potential friction point

## Surprises

- koto doesn't have a recipe in the main recipes directory -- it uses org-scoped syntax
- Whether `.tsuku.toml` supports org-scoped recipe names (e.g., `tsukumogami/koto`) is not obvious from the docs
- python has multiple version-suffixed variants rather than a single recipe

## Open Questions

1. Does `.tsuku.toml` support org-scoped recipe names like `tsukumogami/koto`?
2. Are python3 and claude available as tsuku recipes?
3. Should we declare gh and jq even though they're commonly pre-installed on dev machines?

## Summary

Shirabe should declare koto (exact pin at 0.2.1), gh (latest), and jq (latest) -- these three have confirmed tsuku recipes. Python and claude lack clear recipe availability and may need to remain system dependencies. The key friction point is whether `.tsuku.toml` supports org-scoped recipe names like `tsukumogami/koto`, which is how koto is currently installed in CI.
