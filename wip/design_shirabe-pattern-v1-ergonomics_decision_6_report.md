# Decision 6: Convention updates

**Dispatch context:** Walked as serial-self under sub-agent dispatch; independence-loss caveat applies.

## Question

PRD's Cluster 6 (R27-R29) plus Cluster 7 (R30) prescribe four convention updates: /scope Phase 0 slug-prefix detection (R27), release-notes adopter-doc location convention (R28), /scope Phase 1 R6 cold-start projected-PRD evaluation + framing-shift short-circuit (R29), CLI version-skew preflight prose mechanism (R30). Settle placement and mechanism for each.

## Constraints

- **R31** — direct invocation behavior unchanged.
- **D3 (per PRD)** — CLI version-skew preflight is a skill-prose contract, not a validator extension.
- **/scope Phase 0** is the chain-entry step where slug validation happens.

## Options Considered per Convention

### R27 — /scope Phase 0 slug-prefix detection

**Option A — /scope Phase 0 sampling step:** Add a step in `/scope`'s Phase 0 that samples existing artifacts in `docs/briefs/`, `docs/prds/`, `docs/designs/`, `docs/plans/` to detect a repo-prefix convention (e.g., counting how many existing artifacts use `<some-prefix>-<feature>` shape and what the most common prefix is). When the input slug lacks the detected prefix, Phase 0 prompts the author: "Existing artifacts use the `<prefix>-` prefix. Use `<prefix>-<input-slug>` instead?"

**Option B — separate skill-side detection in each child:** Each child does its own sampling.

**Option C — validator check:** Validator reads existing artifacts and flags slug-prefix drift.

**Chosen: A.** R27 explicitly names `/scope` Phase 0 as the surface; the AC1.1 wording in Cluster 6 (AC6.1) names `/scope` Phase 0 as well. Per-child detection (Option B) is redundant — `/scope` is the chain-entry that names the topic; children inherit the topic. Validator check (Option C) fires too late (after the artifact has committed under the wrong name). The sampling implementation: read `docs/briefs/BRIEF-*.md`, `docs/prds/PRD-*.md`, `docs/designs/DESIGN-*.md`, `docs/plans/PLAN-*.md` filenames; extract the first hyphenated word after the artifact-type prefix; count occurrences; if >50% of artifacts share a prefix, treat it as detected.

### R28 — release-notes adopter-doc location convention

**Option A — `/prd` and `/design` learn the workspace's release-notes location convention from CLAUDE.md:** Add a CLAUDE.md convention `## Release Notes Convention:` that names the durable adopter-doc location (e.g., `docs/guides/` or `docs/releases/` or `CHANGELOG.md`). `/prd` and `/design` read the convention at Phase 0 and use it when authoring adopter-obligation ACs.

**Option B — hardcode `docs/guides/` in skill prose:** Each skill that needs release-notes targets hardcodes the location.

**Option C — /prd and /design auto-detect the location by scanning the repo:** Look for `docs/guides/`, `docs/releases/`, `CHANGELOG.md` files to infer.

**Chosen: A.** The PRD's R28 commit defers location confirmation to DESIGN; the design ships the CLAUDE.md convention mechanism. Reading from CLAUDE.md preserves per-repo flexibility (different repos in the workspace use different conventions — shirabe uses `docs/guides/`, tsuku might use a different home). Hardcoding (Option B) breaks portability. Auto-detection (Option C) is brittle (the location might exist without the convention being honored). The CLAUDE.md convention reads: `## Release Notes Convention: docs/guides/` (or per-repo value). The `/prd` and `/design` skills read the value at Phase 0 and use it when authoring ACs that reference release-notes targets.

### R29 — /scope Phase 1 R6 cold-start projected-PRD evaluation

The PRD's R6 predicates (P1 and P3) inspect a PRD body. At cold-start the PRD doesn't yet exist; the existing behavior is the predicates trivially-not-fire.

**Option A — Phase 1 projects the expected PRD content shape from the BRIEF (if BRIEF exists) or from the topic slug (if no BRIEF):** When cold-start is detected (no PRD body), `/scope` Phase 1 projects what content the future PRD will likely contain by inspecting upstream artifacts (BRIEF, ROADMAP). The R6 P1/P3 predicates evaluate against the projection; `/design` fires tentatively when the projection implies architectural alternatives. A post-`/prd` re-evaluation gate re-runs R6 against the actual PRD body.

**Option B — R6 predicates skip the cold-start case entirely; `/design` always fires under cold-start:** Simpler default: cold-start always includes `/design`.

**Option C — operator-prompted decision at cold-start:** Prompt the operator: "Cold-start detected. Should `/design` fire tentatively?"

**Chosen: A.** Option B always-fires would over-include `/design` for topics that don't have architectural alternatives. Option C breaks the auto-flow (`/scope` under sub-agent dispatch with no AskUserQuestion surface — circular dependency with Cluster 1). Option A's projection mechanism: read the BRIEF (if exists) and look for keywords ("alternatives," "mechanism," "choices," "trade-offs") in the User Journeys and Problem Statement sections; tentative-fire `/design` when matches are found. The post-`/prd` re-evaluation gate runs after `/prd` lands and re-evaluates R6 against the actual PRD body; if the PRD doesn't surface alternatives, `/design` is skipped from the chain (a `chain_revised` record is written to `/scope`'s state file).

The framing-shift opener short-circuit (R29's second clause): Phase 1's opener asks "what shifts the framing from prior work?" — if topic-related child-doc discovery returns empty (cold-start), there's no prior work to shift from. The short-circuit: detect empty discovery, skip the opener, proceed to the regular Phase 1 scope conversation.

### R30 — CLI version-skew preflight (D3 commits skill-prose, not validator)

**Option A — inline shell-snippet in each child SKILL.md that prescribes a `shirabe` subcommand:** Each SKILL.md that prescribes `shirabe transition` (or any `shirabe <subcommand>`) grows a preflight step before the subcommand invocation: `shirabe --version | grep -q '^shirabe <X.Y.Z>$' && shirabe transition ... || sed -i '...'` (the sed fallback is the documented manual-edit equivalent).

**Option B — capability detection helper that each SKILL cites:** A shared reference (`references/cli-version-preflight.md`) describes the preflight pattern; each SKILL cites the reference and customizes the subcommand name.

**Option C — parent-skill inheritance — `/scope` and `/charter` do the preflight once at chain entry; children inherit:** /scope's Phase 0 runs `shirabe --version` and stores the version in the parent state file; children read the version and choose path A (subcommand) or path B (manual fallback).

**Chosen: B.** Option A is what the PRD's "Known Limitations" notes as the workaround (`manual sed-edit`); inlining it in seven SKILL.md files duplicates the pattern. Option C requires parent state-file extension; the version-skew is a runtime condition that fires per-subcommand-invocation, not per-chain-entry — children invoked directly don't have a parent state file to inherit from. Option B (shared reference + per-skill citation) is the pattern's composability winner: the reference at `references/cli-version-preflight.md` describes the preflight; each child SKILL.md that prescribes `shirabe transition` (or any other versioned subcommand) cites the reference and names its specific subcommand + version requirement.

The reference describes a per-subcommand preflight contract:

```bash
# CLI Version Preflight (cite when prescribing `shirabe <subcommand>`)
if ! shirabe <subcommand> --help >/dev/null 2>&1; then
  echo "shirabe CLI installed at $(which shirabe) does not support '<subcommand>'."
  echo "Fallback: <documented manual operation>"
  exit 1
fi
shirabe <subcommand> ...
```

Each child SKILL.md that calls `shirabe transition` (the main affected subcommand per the PRD's Known Limitations) gains a preflight citation before the call: `Before invoking shirabe transition, run the CLI version preflight from references/cli-version-preflight.md against the 'transition' subcommand. On preflight failure, follow the documented sed-edit fallback (manually update the artifact's frontmatter status field and run git mv to move the file to the target directory).`

## Summary

| Convention | Placement |
|---|---|
| R27 slug-prefix detection | /scope Phase 0 sampling step |
| R28 release-notes location | CLAUDE.md `## Release Notes Convention:` field; /prd and /design read at Phase 0 |
| R29 cold-start R6 + framing-shift | /scope Phase 1 projected-PRD evaluation + opener short-circuit |
| R30 CLI version-skew preflight | New shared reference `references/cli-version-preflight.md`; per-skill citations |

## Assumptions

- /scope Phase 0 has the chain-entry slug-validation step; verified by reading the scope SKILL prose (existing).
- CLAUDE.md is the workspace-policy surface for per-repo conventions; `## Release Notes Convention:` parallels existing `## Repo Visibility:` and `## Planning Context:` conventions.
- The `references/` directory at the worktree root holds shared cross-skill references; adding `cli-version-preflight.md` follows the existing pattern of `worktree-discipline.md`, `wip-hygiene.md`.

## Status

complete
