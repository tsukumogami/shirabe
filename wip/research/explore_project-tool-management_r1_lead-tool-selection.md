# Lead: Which tools should shirabe declare, and at what version pinning?

## Findings

### Tool Dependency Inventory

Shirabe depends on five external tools across three contexts:

| Tool | Where Used | Context |
|------|-----------|---------|
| koto | validate-templates.yml, run-evals.sh (tier 2 fixture shimming) | CI + local dev |
| gh | finalize-release.yml, release.yml (release management) | CI only (GitHub Actions provides it) |
| jq | check-sentinel.sh (JSON version parsing) | CI + local dev |
| python3 | check-evals-exist.sh, run-evals.sh (JSON parsing, workspace prep) | CI + local dev |
| claude | run-evals.sh (eval execution via `claude -p`) | Local dev only |

### Recipe Availability

**koto**: No recipe in the main tsuku registry (`public/tsuku/recipes/`). However, koto has a distributed recipe at `public/koto/.tsuku-recipes/koto.toml`. The org-scoped syntax `"tsukumogami/koto"` works in `.tsuku.toml` per the org-scoped project config design (DESIGN-org-scoped-project-config.md). The validate-templates.yml workflow already uses `tsuku install tsukumogami/koto -y`.

**gh**: Recipe exists at `public/tsuku/recipes/g/gh.toml`. Supports darwin and linux on amd64/arm64. Uses GitHub release archives. Version resolved from `cli/cli` GitHub releases.

**jq**: Recipe exists at `public/tsuku/recipes/j/jq.toml` but has significant limitations: `unsupported_platforms = ["darwin/arm64", "darwin/amd64"]` and depends on a homebrew action. This means the jq recipe is Linux-only and uses a different installation method than most recipes. It also has a runtime dependency on `oniguruma`.

**python3**: No recipe in the registry. Only `python-tabulate.toml` exists. Python is typically a system dependency.

**claude**: No recipe in the registry. Claude Code is installed via its own installer (`npm` or standalone binary).

### Org-Scoped Key Syntax

The `.tsuku.toml` format supports org-scoped keys via TOML quoted keys:

```toml
[tools]
"tsukumogami/koto" = "0.5.0"
```

This was designed and implemented per DESIGN-org-scoped-project-config.md. The `SplitOrgKey` function in `internal/project/orgkey.go` handles parsing: `"tsukumogami/koto"` splits into source=`tsukumogami/koto`, bare=`koto`. The colon syntax also works for non-default recipe names: `"myorg/registry:mytool"`.

During project install, `runProjectInstall` (`cmd/tsuku/install_project.go`) pre-scans for org-scoped keys, batch-bootstraps distributed sources, then installs each tool. The `--yes` flag enables non-interactive CI use.

### Version Constraint Syntax

From DESIGN-project-configuration.md and the code in `config.go`:

- **Exact version**: `tool = "20.16.0"` -- passed to version provider
- **Prefix matching**: `tool = "1.22"` -- provider resolves to latest 1.22.x
- **Latest**: `tool = "latest"` or `tool = ""` -- resolves to newest stable
- **No semver ranges** -- not supported in v1

The install code (`install_project.go`, lines 137-149) warns about unpinned versions (empty string or "latest") with a message about reproducibility.

### Pinning Strategy Analysis

For each tool:

**koto (recommended: pin to prefix)**: shirabe's README states `>= 0.2.1`. Current installed version is 0.5.0. koto is pre-1.0, so minor versions can contain breaking changes. Pinning to `"0.5"` gives patch-level flexibility while avoiding surprise breakage. Full exact pin (`"0.5.0"`) is safer for CI reproducibility.

**gh (recommended: include, pin to prefix)**: Used in release workflows. The gh recipe works well. Pinning to `"2"` gives maximum flexibility since gh's major version changes are rare and well-documented. CI workflows use `gh` from the GitHub Actions runner, but local developers running release scripts need it too.

**jq (recommended: skip)**: The jq recipe is problematic -- macOS is entirely unsupported and it depends on homebrew. jq is ubiquitous enough on developer machines and CI runners that declaring it in `.tsuku.toml` adds friction (install failures on macOS) without much value. Better to document it as a system prerequisite.

**python3 (recommended: skip)**: No recipe exists. Python is a system dependency. CI uses `actions/setup-python@v5`. Declaring a tool without a recipe causes install failures.

**claude (recommended: skip)**: No recipe. Claude Code has its own installation path. Only needed for eval execution, which is a local dev activity.

### What the `.tsuku.toml` Would Look Like

```toml
[tools]
"tsukumogami/koto" = "0.5"
gh = "2"
```

Minimal declaration covering only the tools that (a) have working recipes and (b) are needed for core development and CI workflows.

## Implications

1. Only 2 of shirabe's 5 tool dependencies have usable tsuku recipes. The `.tsuku.toml` will be small.
2. The jq recipe's macOS limitation is a blocker for cross-platform use. Either the recipe needs fixing or jq stays as a system prerequisite.
3. The org-scoped syntax for koto is well-supported and already in use in CI (`tsuku install tsukumogami/koto -y`). Adopting `.tsuku.toml` for koto is straightforward.
4. CI adoption requires `tsuku install -y` (the `--yes` flag) to skip interactive confirmation. The validate-templates workflow already does this pattern but installs koto individually rather than via project config.
5. The prefix pinning strategy (`"0.5"`, `"2"`) balances reproducibility against maintenance burden. Exact pins would require more frequent updates.

## Surprises

1. The jq recipe is macOS-unsupported. For a tool as fundamental as jq, this is unexpected and limits `.tsuku.toml` portability.
2. `tsuku search` returned no results for any tool -- even gh and jq which have recipes. The search appears to be hitting a misconfigured distributed source (`tsukomogami/koto` -- note the typo "tsukomogami" vs "tsukumogami") and failing before checking the main registry. This is likely a local config issue, not a tsuku bug, but it means search can't be used to verify recipe availability.
3. The version constraint system has no semver range support. The README's `>= 0.2.1` requirement for koto can't be expressed directly -- you either pin exact/prefix or use "latest".

## Open Questions

1. **Should gh be included?** GitHub Actions runners already provide gh. Including it in `.tsuku.toml` benefits local developers running release scripts, but adds an install step. Is the local dev use case strong enough?
2. **Should the jq recipe be fixed first?** If jq stays out of `.tsuku.toml`, the check-sentinel.sh script needs jq documented as a system prerequisite. Alternatively, could check-sentinel.sh be rewritten to avoid jq (e.g., use python3 for JSON parsing)?
3. **Exact pin vs. prefix pin for koto?** Pre-1.0 software can break on minor bumps. Is `"0.5"` safe enough, or should CI use `"0.5.0"` for maximum reproducibility?
4. **Should the `tsuku search` issue be reported?** The typo in the distributed source name (`tsukomogami` vs `tsukumogami`) causes a warning on every search. This may be a local config artifact.

## Summary

Only koto and gh have usable tsuku recipes suitable for `.tsuku.toml`; jq's recipe is macOS-broken, and python3/claude have no recipes at all. The recommended `.tsuku.toml` declares `"tsukumogami/koto" = "0.5"` and `gh = "2"`, using prefix pinning for patch-level flexibility while avoiding breaking changes. The main open question is whether to include gh at all given that CI already provides it and only local release workflows need it.
