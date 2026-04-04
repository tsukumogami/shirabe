# Exploration Findings: project-tool-management

## Core Question

How should shirabe adopt tsuku's `.tsuku.toml` project-level tool management for local development and CI? This is a friction log exercise: the deliverable is both a working config and a catalog of UX issues to file against tsuku.

## Round 1 (Code and docs review)

### Key Insights

- **0.9.0 fixed the two critical blockers from the original exploration**: org-scoped recipes work in `.tsuku.toml` via quoted keys (PR #2235), and "latest" version resolution works (PR #2234). (lead: 0.9.0-changes)
- **Only koto and gh have working recipes**: jq is macOS-broken, python3/claude have no recipes. The config would be 2 tools. (lead: tool-selection)
- **One CI workflow needs changing**: `validate-templates.yml` switches from `tsuku install tsukumogami/koto -y` to `tsuku install -y`. Other workflows use runner-preinstalled tools or koto's reusable workflow. (lead: ci-workflows)
- **No `tsuku add` command exists**: Setup is `tsuku init` (empty file), hand-edit TOML, `tsuku install`. (lead: setup-experience)
- **Shirabe would be first adopter in the org**: tsuku doesn't dogfood `.tsuku.toml` in its own CI. (lead: ci-workflows)
- **tsuku-user plugin covers syntax but lacks CI guidance**: Good reference card, missing adoption workflow and org-scoped recipe docs. (lead: tsuku-user-plugin)
- **Demand is self-directed**: No external user requested this. Value is the friction log itself. (lead: adversarial-demand)

### Tensions

- Small config (2 tools) vs. maintenance overhead
- Dual koto install paths in CI (validate-templates uses tsuku, check-templates uses koto's own installer)
- gh: CI runners provide it free, but local devs need it for release scripts

### Gaps

- No GitHub Action for tsuku setup
- jq recipe broken on macOS
- `tsuku search` doesn't find all recipes

## Round 2 (Hands-on Docker testing)

### Key Insights

- **Partial semver fails for distributed sources**: `"tsukumogami/koto" = "0.5"` fails; must use `"0.5.0"`. Meanwhile `gh = "2"` works fine. Inconsistent resolution across recipe sources. (lead: hands-on-testing)
- **`--dry-run` actually installs things**: Correctness bug -- the flag has no effect. (lead: hands-on-testing)
- **jq is broken on Linux too**: Shared library relocation fails. `libjq.so.1` not found at runtime despite patchelf being installed. (lead: hands-on-testing)
- **Idempotent install is noisy**: Re-executes full plan (download from cache, extract, chmod) before printing "already installed". Wastes CI output. (lead: hands-on-testing)
- **`tsuku search` doesn't find distributed source recipes**: `tsuku search koto` returns nothing despite `tsukumogami/koto` being registered. (lead: hands-on-testing)
- **`tsuku list` may not show distributed source tools**: koto potentially missing from list output. (lead: hands-on-testing)
- **The happy path works**: With `"0.5.0"` and `gh = "2"`, both tools install correctly in ~5 seconds. Verification passes. (lead: hands-on-testing)

### Issues to File Against tsuku

| # | Issue | Severity | Workaround |
|---|-------|----------|------------|
| 1 | Partial semver fails for distributed source recipes | High | Use exact semver (`"0.5.0"`) |
| 2 | `--dry-run` actually installs things | High | None |
| 3 | Idempotent install re-executes full plan | Medium | Tolerate noisy output |
| 4 | `tsuku search` misses distributed source recipes | Medium | Know the recipe name |
| 5 | jq recipe broken on Linux (shared lib relocation) | High | Don't declare jq |
| 6 | `tsuku list` may not show distributed source tools | Low | Unverified |

### Decisions

- Use `"0.5.0"` not `"0.5"` for koto until partial semver is fixed
- Skip jq in `.tsuku.toml` (broken on both macOS and Linux)
- Skip python3 and claude (no recipes exist)
- Include gh (works, useful for local dev consistency)

## Accumulated Understanding

tsuku 0.9.0 makes `.tsuku.toml` adoption viable for shirabe. The happy path works: `"tsukumogami/koto" = "0.5.0"` and `gh = "2"` install correctly in a clean Docker environment. The CI change is a one-line edit in `validate-templates.yml`.

The friction log produced six concrete issues to file against tsuku, three of which are high severity (partial semver resolution inconsistency, `--dry-run` bug, jq Linux breakage). The original exploration's friction log had already shipped three bug fixes in 0.9.0, and this round surfaced three more high-severity bugs -- validating the friction log approach.

The implementation is small: one `.tsuku.toml` file (2 tools), one CI workflow edit, and 5-6 issues to file. No design doc or PRD needed.

## Decision: Crystallize
