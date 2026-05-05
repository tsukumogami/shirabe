# Lead: Doc CI framework landscape

## Findings

### Static doc validation tools: what they check

**markdownlint** (Node, `markdownlint-cli2`): Checks markdown syntax and style —
heading levels, list indentation, trailing whitespace, blank lines, code fence
consistency, line length, no bare URLs. Entirely structural; knows nothing about
content meaning. Config-driven (`.markdownlint.json`), extensive rule set, widely
used in GitHub Actions via `DavidAnson/markdownlint-cli2-action`.

**Vale**: The most capable static prose linter. Works with style packages (Google,
Microsoft, proselint, write-good). Checks: vocabulary (banned words, preferred
synonyms), grammar patterns, passive voice frequency, sentence length, heading
capitalization, acronym definitions. Can enforce custom vocabulary lists and
term substitution. Does NOT check whether content is correct or complete — only
whether it conforms to style rules. Configured via `.vale.ini` and vocab files.
Available as `errata-ai/vale-action`.

**remark / remark-lint** (unified ecosystem): Parses markdown AST, applies lint
rules. Plugins cover: broken relative links, heading structure, frontmatter
presence, definition list formatting, table formatting. Can also transform
(remark-validate-links checks that internal anchors exist). Composable via
`.remarkrc`. More programmable than markdownlint but same limitation: no semantic
understanding.

**textlint**: Rule-based text linter, similar to Vale. Can enforce prose style,
detect weasel words, check sentence structure. Plugin ecosystem (textlint-rule-*).
Used less often in GHA than Vale.

**yamllint**: Pure YAML syntax and style checker. Validates indentation, key
ordering, quoting style. Does not understand schema — just syntax well-formedness.
Often paired with schema validators.

**JSON Schema / custom awk/sed scripts**: What shirabe's `validate-plan.sh`
actually uses. Pure bash + awk: extract frontmatter, check field presence, validate
field values against an allowlist, walk the upstream chain. This is more powerful
than yamllint for schema enforcement because it can express domain rules (e.g.,
`upstream.status` must be `Accepted` or `Planned`). The cost is maintenance — bash
scripts need their own tests (`validate-plan_test.sh`).

**linkcheck / lychee**: Check that URLs referenced in docs resolve. Can distinguish
404 vs. connection refused vs. redirect loops. lychee (`lycheeverse/lychee-action`)
is the most popular GHA option. Network-dependent; often rate-limited by GitHub or
corporate proxies.

**mdBook**: A static site generator, not a linter. Its `mdbook test` does execute
Rust code blocks but does not validate prose. Not relevant to a validation tier
focused on content quality.

**pandoc**: Format converter. Can be used to check that a file is parseable
markdown, but it accepts nearly everything without error. Not used for validation in
practice.

**koto template compile** (shirabe's own): The `validate-templates.yml` workflow
installs tsuku + koto, then runs `koto template compile` on every koto-templates
file. This is structural validation of the YAML frontmatter schema that koto expects
— not prose validation.

### What all static tools share: the hard ceiling

Static analysis can check:

- **Syntax**: markdown is parseable, YAML is well-formed
- **Schema**: required frontmatter fields present, field values in allowlist, types correct
- **Referential integrity**: upstream file exists, is git-tracked, has an allowed status field value
- **Style rules**: banned words, heading capitalization, line length
- **Link reachability**: URLs return 2xx
- **Structural conventions**: required sections present (checked by grepping for known headings)

Static analysis cannot check:

- Whether the content under a required heading actually addresses that heading
- Whether a doc answers the question it poses (a "Summary" section with one sentence passes a section-presence check)
- Whether a design's rationale is plausible or internally consistent
- Whether wording like "this will be addressed later" is a placeholder left by the author
- Whether the scope of a PRD is realistic relative to the team size
- Whether a VISION doc is coherent as a strategy, not just structurally complete
- Whether dev-time scaffold content was trimmed before commit
- Writing quality beyond mechanical style rules

These are not tractable with regex or AST analysis because they require understanding intent, which requires a model of the domain and the reader.

### Reusable GHA workflow patterns in the wild

Well-designed reusable validation workflows published publicly share several traits:

**Thin caller pattern**: The consuming repo contains only a short workflow that calls
`uses: owner/repo/.github/workflows/validate.yml@v1`. All logic, scripts, and tool
installation live in the library repo. The caller passes minimal config via `with:`
inputs (file paths, config toggles). Examples: `actions/reusable-workflows`,
various organization-internal GHA libraries.

**Path filtering**: Workflows trigger only on `pull_request` with `paths:` filters
so they don't run on unrelated changes. Shirabe already does this in every workflow
(`check-evals.yml`, `check-plan-docs.yml`, `check-sentinel.yml`, etc.).

**OS matrix for scripts**: Scripts that need POSIX portability run on
`ubuntu-latest` and `macos-latest` via `strategy.matrix.os`. Shirabe does this in
`check-plan-scripts.yml` and `check-work-on-scripts.yml`.

**Secret gating**: Workflows that require a secret (API keys) are either
`workflow_dispatch`-triggered or run on a schedule rather than on every PR. The
`run-evals.yml` in shirabe exemplifies this: it uses `ANTHROPIC_API_KEY` and runs
on a weekly cron + manual dispatch, not on every PR. This is the established pattern
for AI-gated steps.

**workflow_call vs. caller-side trigger**: A workflow using `on: workflow_call`
exposes `inputs:` and `secrets:` that callers pass. This is how `finalize-release.yml`
and `release.yml` are structured in shirabe — they're designed to be called by
`prepare-release.yml` or by the downstream repo's own workflow.

**Versioned references**: Callers should pin to a tag (`@v1`, `@v0.5`) rather than
`@main` to get stability. The `check-templates.yml` workflow in shirabe calls
`tsukumogami/koto/.github/workflows/check-template-freshness.yml@main` — an
`@main` reference that would break callers if koto changes its interface. This
is a known anti-pattern in reusable GHA workflows.

### What shirabe's existing scripts already validate

From reading the scripts:

- `check-sentinel.sh`: manifest version field matches dev-suffix pattern (schema/value check)
- `validate-template-mermaid.sh`: state name consistency between YAML frontmatter and companion mermaid diagram; `default_template:` reference integrity; no hardcoded workflow names (referential integrity + convention check)
- `check-evals-exist.sh`: every invocable skill has at least one eval entry (structural coverage check)
- `validate-plan.sh`: frontmatter presence, `schema` field value, required fields present, upstream file exists + is git-tracked + has acceptable status (schema + referential integrity)
- `validate-templates.yml`: koto template compilation passes (koto-specific schema)

All of these are deterministic static checks. None of them evaluate content quality.

## Implications

**The static tier boundary is clear**: anything that reduces to "field present?",
"field value in set?", "referenced file exists and has correct status?", "required
section heading present?", "style rule violated?" belongs in static. This is well-
understood and tooling exists. The shirabe scripts already demonstrate the pattern
at a high level of quality (distinct exit codes, unit tests for scripts, path
filtering in workflows).

**The AI tier boundary is also clear**: anything that requires evaluating whether
content is complete, intentional, and meaningful requires a model. "Dev-time
scaffold trimmed?" is not statically detectable unless you check for literal
placeholder strings, which is easy to defeat. "Does this doc answer its stated
question?" is not a regex. These are genuine gaps where AI adds value that no
static tool fills.

**Reusable workflow structure is straightforward**: `on: workflow_call` +
`inputs:` for file paths/toggles + `secrets:` for `ANTHROPIC_API_KEY` is the
established GHA mechanism. The thin-caller pattern is well-understood. The main
design question is how callers configure which doc format is being validated
(since different formats have different required fields and section requirements).

**AI tier should not block PRs by default**: The `run-evals.yml` pattern —
weekly cron + manual dispatch, secret-gated — is the right model for AI-powered
checks. Requiring `ANTHROPIC_API_KEY` on every PR would break CI for contributors
without the key. The tier should be opt-in at the workflow level.

**The `@main` anti-pattern in `check-templates.yml`** is a concrete example of
what downstream repos should avoid. Vision docs should recommend version-pinned
`@v1` references.

## Surprises

**Vale's breadth is larger than expected.** Most teams use it only for vocabulary
and passive voice, but it can encode domain-specific rules via custom YAML style
packages — including flagging specific placeholder strings. This might cover a
narrow slice of what's thought to need AI ("trim dev-time content" partially
overlaps with Vale's vocabulary rules if placeholder phrases are known in advance).

**Bash + awk is the dominant approach for schema enforcement in doc CI**, not
dedicated YAML schema validators. yamllint checks syntax; actual schema rules
(field presence, value allowlists, cross-file referential integrity) are almost
universally done with shell scripts, even in large projects. This validates
shirabe's current approach.

**No widely-adopted open-source framework for multi-tier (static + AI) doc
validation exists yet.** There are AI writing assistants and prose checkers
(e.g., LanguageTool, Grammarly API, GPT-based linters), but no established GHA
workflow pattern that gates static vs. AI tiers cleanly. Shirabe has an opportunity
to define this pattern rather than inherit it.

**The `workflow_call` secret inheritance mechanism** makes AI-gated steps cleaner
than expected: callers can pass `ANTHROPIC_API_KEY` via `secrets: inherit` without
the reusable workflow needing to know the caller's secret names explicitly. This
removes a practical objection to the design.

## Open Questions

1. **How should doc-format selection work in a single reusable workflow?** Callers
   might have design docs, PRDs, and VISION docs in the same repo. Does the
   reusable workflow take a `doc-format` input and switch behavior, or is there one
   reusable workflow per format? The tradeoff is caller simplicity vs. workflow
   maintainability.

2. **What section headings are required for each format?** The static tier can
   check section presence, but only if the required headings are defined. Inventorying
   all formats and their canonical sections is a prerequisite (Research Lead 2 in
   the scope doc).

3. **Can Vale cover any of the "AI tier" checks?** If dev-time placeholder phrases
   are enumerable (e.g., "TODO", "TBD", "fill this in"), Vale can catch them
   statically. The AI tier may be narrower than assumed once Vale's full capability
   is applied.

4. **How should the AI tier report findings?** GHA annotations (`::warning::`,
   `::error::`) vs. a PR comment vs. a job summary. This affects how actionable
   the feedback is for contributors.

5. **Version pinning strategy**: Should downstream repos pin to `@v1` (semver) or
   commit SHA? SHAs are safer but harder to read. Semver tags require a disciplined
   release process in shirabe.

## Summary

Static doc validation tools (markdownlint, Vale, bash+awk scripts) can reliably check syntax, schema field presence and values, referential integrity between documents, required section headings, and style rules — but hit a hard ceiling at any check that requires understanding whether content is meaningful, complete, or intentional. The AI tier fills exactly and only this gap: completeness, placeholder detection beyond known strings, and semantic coherence. The GHA reusable workflow pattern (`on: workflow_call`, `inputs:`, `secrets: inherit`) is mature and shirabe's existing workflows already demonstrate the thin-caller and secret-gating patterns correctly. The biggest open question is how downstream repos specify which doc format to validate within a single reusable workflow entrypoint, since different formats have different section requirements.
