# Lead: Is shipping a dev build (`0.12.1-dev`) alongside stable (`0.11.0`) in one plugin cache intended, and is "version skew within one skill chain" a shirabe release/versioning concern or a niwa/install concern?

## Findings

### Declared version (shirabe repo, worktree)
Both manifest files in the worktree declare the dev version:
- `/home/dgazineu/dev/worktrees/shirabe-execute-friction/.claude-plugin/plugin.json` → `"version": "0.12.1-dev"`
- `/home/dgazineu/dev/worktrees/shirabe-execute-friction/.claude-plugin/marketplace.json` → `"version": "0.12.1-dev"`

`grep -rn "0.1[12]" .claude-plugin/` returns only those two lines. The marketplace entry and plugin manifest are kept in lock-step.

### Dev-bump convention (confirmed)
`git log --oneline` on the worktree HEAD:
```
1c5352d chore(release): advance to 0.12.1-dev   <- current main / HEAD
65becd0 chore(release): set version to v0.12.0
...
5b40711 chore(release): advance to 0.11.1-dev
d03c0b4 chore(release): set version to v0.11.0
```
After each release the repo bumps `main` to `<next>-dev`. Crucially, **no `-dev` git tags exist** — `git tag -l '*dev*'` is empty; tags are clean (`v0.12.0`, `v0.11.0`, …). The `-dev` string lives *only* in `main`'s manifests between releases. `finalize-release.yml` validates tags against `v<major>.<minor>.<patch>` (line 36), i.e. it rejects `-dev` tags by design.

### `/execute` only exists in 0.12.0+
`git log --diff-filter=A -- skills/execute/`:
```
aebd1c1 feat(execute): add implementation-altitude plan-execution skill and narrow /work-on (#199)
```
PR #199 landed *after* the v0.11.0 tag (d03c0b4) and is part of what shipped in v0.12.0. So `/execute` does not exist in any 0.11.x tree.

### Actual plugin cache on disk
`ls -la /home/dgazineu/.claude/plugins/cache/shirabe/shirabe/`:
```
drwxrwxr-x 14 ... Jun  8 16:35 0.10.1-dev
drwxrwxr-x 14 ... Jun 20 16:14 0.11.0
drwxrwxr-x 14 ... Jun 20 16:41 0.11.1-dev
drwxrwxr-x 13 ... Jun 20 16:41 0.12.1-dev
drwxrwxr-x 11 ... Jun 20 09:53 0.4.1-dev
drwxrwxr-x 13 ... Jun  6 22:42 0.9.1-dev
```
Six version directories coexist — a mix of release (`0.11.0`) and dev snapshots (`0.4.1-dev`, `0.9.1-dev`, `0.10.1-dev`, `0.11.1-dev`, `0.12.1-dev`). This is an accumulated cache of every version that was ever resolved, not a deliberate "ship dev next to stable" act.

### Which skills exist in which cache dir
- `0.11.0/skills/`: brief charter comp decision design explore plan prd … scope … work-on — **no `execute`**
- `0.11.1-dev/skills/`: same set — **no `execute`**
- `0.12.1-dev/skills/`: same set **plus `execute`**

So `/execute` physically exists only under `0.12.1-dev/`. Any 0.11.x cache directory cannot serve it.

### What is actually installed/pinned (the decisive evidence)
`installed_plugins.json` has exactly ONE `shirabe@shirabe` entry:
```json
"shirabe@shirabe": [{
  "scope": "local",
  "projectPath": ".../tsuku-4/public/shirabe",
  "installPath": ".../cache/shirabe/shirabe/0.12.1-dev",
  "version": "0.12.1-dev",
  "gitCommitSha": "1c5352dbd4c0d3638fafc3a290f333042bb26ca4"   <- == worktree HEAD 1c5352d
}]
```
`known_marketplaces.json` shows the shirabe marketplace source is `github: tsukumogami/shirabe` with **no tag/ref pin** and `autoUpdate: false`; its live checkout (`/home/dgazineu/.claude/plugins/marketplaces/shirabe`) is at HEAD `1c5352d` ("advance to 0.12.1-dev"). The marketplace resolves the plugin from the repo's **default branch**, whose manifest currently says `0.12.1-dev`.

**Conclusion on the mechanism:** the installed/active shirabe is *entirely* `0.12.1-dev` — not a stable+dev split. The `0.11.0` and other directories are stale caches from earlier installs that Claude Code never garbage-collected. The friction author's observation that `/explore`/`/scope`/etc. ran under `…/shirabe/0.11.0/…` while `/execute` ran under `…/0.12.1-dev/…` is therefore a **within-session resolution artifact**: the session was launched/cached against a 0.11.0 tree, and when it hit `/execute` (which doesn't exist in 0.11.0) the loader fell forward to a newer cache dir that *does* contain it (`0.12.1-dev`). The lead's hypothesized mechanism is consistent with what's on disk: a skill missing from the pinned version dir gets served from a newer cached version dir.

## Implications

**Ownership: primarily (b) install/marketplace + Claude-Code cache behavior, with a small (c) benign component. Low likelihood of (a) a shirabe code bug.** Confidence: high that this is not a shirabe release-process defect; medium-high on the precise fall-forward mechanism (it's inferred from disk state, not from reading Claude Code's loader source).

Reasoning:
- **Not a shirabe versioning bug.** shirabe never tags or publishes a `-dev` release; `-dev` is just the in-flight version string on `main` between tags, which is a standard and intentional convention. The marketplace exposing `0.12.1-dev` is a *direct consequence of installing from the default branch* (the marketplace source has no tag pin). If a consumer points a marketplace at a repo's main branch, they get main's version — that's expected behavior of an unpinned install, owned by whoever configured the install (niwa / the marketplace consumer), not by shirabe.
- **The skew within one chain is a Claude-Code cache/resolution detail.** Multiple version directories accumulate because the cache isn't pruned. The cross-version fall-forward for a skill absent from the pinned dir is Claude Code plugin-loader behavior. shirabe has no code that controls which cache directory a given skill resolves from.
- **Benign in outcome here.** `0.12.1-dev` is a strict superset of `0.11.0` for the skill set (same skills + `execute`). Running `/execute` from `0.12.1-dev` while siblings ran from `0.11.0` did not produce a broken chain — the dev tree is newer and forward-compatible. The risk is *latent*: if a future dev build changed a shared artifact (e.g. a skill's I/O contract or a shared template) in a way that the older siblings didn't expect, a mixed-version chain could silently disagree. That risk is a property of unpinned/dev installs, not of shirabe's release pipeline.

## Surprises
- There is only ONE installed shirabe entry and it is `0.12.1-dev` — the dogfood is running fully on the dev build, not a 0.11.0 stable with a dev `/execute` bolted on. The "0.11.0 for every other skill" the friction author saw must come from a session whose cache predates the 0.12.1-dev install (stale per-session resolution), not from the current pin.
- The marketplace install is unpinned (`autoUpdate: false` but tracking default branch HEAD), so every fresh resolve picks up whatever `-dev` version main currently carries. That, not any shirabe action, is why a dev version is "installable."
- Six shirabe version dirs are cached and never cleaned; Claude Code does not prune old plugin versions.

## Open Questions
- Does Claude Code's plugin loader actually "fall forward" to a newer cached version dir for a skill missing in the pinned dir, or does it instead re-resolve the whole plugin to the newest cache (and the 0.11.0 sighting was just an older session)? Confirming requires reading the Claude Code loader, which is outside the shirabe repo. (Route to a claude-code-guide / niwa-install investigation.)
- Is niwa's apply step the thing that installs shirabe from the marketplace default branch (unpinned)? If so, whether to pin niwa installs to release tags is a niwa decision, not shirabe's.
- Should shirabe's marketplace consumers be steered to install from tags rather than main? That's a packaging/distribution-policy question for the install side.

## Summary
The active install is entirely `0.12.1-dev` (single `installed_plugins.json` entry, gitCommitSha == worktree HEAD `1c5352d`), pulled because the shirabe marketplace tracks the repo's default branch unpinned and main carries the post-release `-dev` string; shirabe never tags or publishes a `-dev` release, so this is not a shirabe release/versioning defect. The within-chain skew (`/execute` under `0.12.1-dev`, siblings under `0.11.0`) is a Claude-Code cache/resolution artifact: `/execute` exists only in 0.12.0+, so a session cached against an older 0.11.0 tree fell forward to the newer dev cache dir that contains it, and stale version dirs accumulate because the cache is never pruned. F2 is best routed as an install/marketplace + plugin-cache concern (owned by niwa / Claude Code), benign in this instance because 0.12.1-dev is a forward-compatible superset of 0.11.0 — recommend shirabe NOT take code work for it beyond, at most, advising consumers to pin installs to release tags.
