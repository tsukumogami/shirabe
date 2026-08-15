# Decision 2: Declaration format and location

## Options considered

- **A. SKILL.md frontmatter under `metadata:`.** A nested block inside the
  existing YAML frontmatter of each `skills/<name>/SKILL.md`.
- **B. Per-skill sidecar file** at `skills/<name>/requires.yaml`, alongside
  the existing `team.yaml` and `evals/` siblings.
- **C. A table compiled into the `shirabe` binary**, keyed by skill name.
- **D. Line-oriented bespoke sidecar** (`requires.txt`, one entry per line,
  parseable by `grep`/`awk` with no YAML reader). Identified while
  establishing the readability constraint below.

## Evaluation against drivers

### Verifying the frontmatter claim

The claim is **confirmed at its source**, with two nuances that change what
it means.

`/Users/danielgazineu/.claude/plugins/cache/claude-plugins-official/skill-creator/55b58ec6e564/skills/skill-creator/scripts/quick_validate.py:42`:

```python
ALLOWED_PROPERTIES = {'name', 'description', 'license', 'allowed-tools', 'metadata', 'compatibility'}
```

Line 44's comment reads "Check for unexpected properties (excluding nested
keys under metadata)", and line 45 subtracts the whole set from
`frontmatter.keys()`. So `metadata:` is genuinely the one free-form key, a
novel top-level `requires:` key would produce the quoted
`Unexpected key(s) in SKILL.md frontmatter` error, and the same file exists
verbatim in the `anthropic-agent-skills/document-skills` cache entry.

**Nuance 1 — the constraint is weaker than stated.** `argument-hint` is
also absent from `ALLOWED_PROPERTIES`, and 62 of the 116 cached SKILL.md
files use it, including shirabe's own `/work-on`, `/plan`, `/decision`,
`/roadmap`, and `/inflight`. shirabe already fails this validator. Adding
`requires:` would not introduce a new failure mode; it would add a second
name to an error shirabe already trips. So "metadata is the only legal key"
cannot by itself decide the question.

**Nuance 2 — the constraint is stronger in a direction nobody framed.**
`quick_validate.py` reads *only* `SKILL.md` (lines 12-95); it never
enumerates the skill directory. A sidecar file is therefore **invisible** to
that validator and to every packaging path that shares its rule set. Option
B does not bet on `metadata:` staying free-form across a spec revision; it
removes the bet.

Corroborating: **zero** of the 116 cached SKILL.md files use `metadata:` at
all. The full key census across the cache is `name` (116), `description`
(116), `argument-hint` (62), `license` (14), `disable-model-invocation` (8),
`allowed-tools` (2). `metadata:` is a spec affordance nobody in the local
corpus exercises, which means no worked example to copy and no evidence of
how the packaging paths treat its contents.

### Is `metadata:` readable by whatever runs the check?

No assumable reader can parse it, and this is the constraint that decides
the question.

- **jq** parses JSON only. It cannot read YAML in any spelling, and the
  repo installs it explicitly in three workflows
  (`check-plan-scripts.yml:17`, `check-execute-scripts.yml:17`,
  `run-evals.yml:42`), which confirms it is not assumable even in CI.
- **yq** appears nowhere in this repo, in any workflow, or in `.tsuku.toml`.
  It happens to be on the developer machine this research ran on
  (`/opt/homebrew/bin/yq`) — that is a homebrew accident, not a contract.
- **python3** is one of the six declared tools, but YAML is not in the
  stdlib. PyYAML is present on this machine (6.0.3), again by homebrew.
  `scripts/check-evals-exist.sh:41` uses `python3 -c "import json"` — JSON,
  pointedly not YAML.
- **bash** is 3.2.57 on macOS (verified). `shirabe#270` is on file as bash 4
  syntax meeting exactly this shell. Hand-rolling a nested-YAML parser in
  awk on that substrate reproduces the incident class the PRD exists to end.

The only reader that can parse YAML without a new assumption is the
`shirabe` binary itself. Both crates already depend on `saphyr = "=0.0.6"`,
and there is a direct precedent: `skills/writing-style/rules.yaml` is a
per-skill YAML sidecar parsed by `shirabe validate` via
`crates/shirabe-validate/src/rules.rs`, with a documented resolution order
(`--rules` flag, then `SHIRABE_RULES`, then an ancestor walk).

This kills option D's motivation. A bespoke line format would buy a
bash-native reader — but the check also has to do R6/R7/R8 surface probing,
R13's five-way posture split, R18's PATH-vs-tool-root discrimination,
R20's machine-readable `.tsuku.toml` exclusion, and R28's overridable root.
That is not bash-3.2 work. Once the reader is Rust, YAML costs nothing and a
bespoke format costs a new parser plus a new thing for maintainers to learn.

### The precedent is not merely analogous — it is the same decision

`docs/designs/current/DESIGN-shirabe-child-dispatch-contract.md` asked
literally this question for team-shape declarations and answered it:

> **Chosen: 2E — Dedicated `team.yaml` file at `skills/<name>/team.yaml`**

Its **Option 2B — Structured YAML in SKILL.md frontmatter** was rejected:

> Children's SKILL.md frontmatter today does not follow the artifact
> schema/v1 convention [...] Adding a `team:` key to that frontmatter risks
> collisions with the plugin loader's parser and with future
> skill-marketplace metadata. [...] *Verdict:* Rejected. The frontmatter
> surface is wrong: SKILL.md frontmatter is for plugin metadata, not for
> content schemas.

Its 2D rejection (fenced YAML in the SKILL.md body) adds the
minimum-context-load argument: a reader loads ~10 lines rather than a
300-700-line SKILL.md. `skills/work-on/SKILL.md` is in that range.

Choosing A now would split shirabe's declaration surface: team shape in a
sidecar, tool requirements in frontmatter, for no reason either decision
records.

### Writers and readers

**Writes:** a human maintainer editing one skill. A sidecar is a ~10-line
file they open, edit, and close, with no risk of disturbing the
`description` string that governs skill triggering. Under A, every
requirement edit touches the file whose frontmatter drives invocation.

**Reads:** three consumers, all served better by a sidecar.

1. *The load-time check.* Rust, `saphyr`, one file open. Under A it must
   extract frontmatter from markdown first — the extra parse step 2D was
   rejected for.
2. *The R23 conformance scan.* `ls skills/*/requires.yaml` returns 20 or it
   does not. `scripts/check-evals-exist.sh` is the shape, already in CI.
   Under A the scan greps 20 markdown files for a nested key, and R1's
   "declares nothing" vs "was never given a declaration" distinction becomes
   a grep for an empty YAML sequence inside a frontmatter block inside a
   markdown file.
3. *The flag-extraction criterion.* Extract `--flags` from `shirabe`/`koto`
   command lines in the skill's own files; compare against the declared set.
   With a sidecar, the declared side is one file read. Under A, both sides
   come out of the same markdown file and the extractor must exclude the
   frontmatter region from the command-line scan or it will find the
   declaration and call it a call site.

### Why not C (compiled table)

It fails R2's composability in practice and the PRD's own reasoning about
authorship. The PRD's answer to PR #278 turns on the declaration being
"written by the same author, in the same change, as the call it describes."
A table in `crates/shirabe/src/` puts the declaration in a different repo
region, in a different language, behind a release cycle, from the skill
prose it describes — and the PRD's central problem is precisely that skills
ship in the plugin while the binary installs separately. A compiled table
would drift against the skills by construction. It also makes the check
unable to serve a repo that adds a skill without rebuilding shirabe.

## Recommendation

**Option B: a per-skill sidecar at `skills/<name>/requires.yaml`**, parsed
by the `shirabe` binary via `saphyr`.

## The concrete schema

```yaml
# skills/<name>/requires.yaml
schema: skill-requires/v1

# An entry is one (tool, subcommand, mode) triple. `requires: []` is an
# explicit empty declaration; an absent file means undeclared (R1).
# `when:` is mandatory on every entry -- `always` or `mode:<name>` (R5).
requires:
  - tool: <name>
    subcommand: <name>        # first-party tools only (shirabe, koto)
    flags: [--a, --b]         # flags this skill's own logic depends on
    when: always | mode:<name>
```

`when:` is required rather than defaulted to `always`. R22a's lesson —
`roadmap populate --no-issues` flipping its default under a stable name — is
that an unstated default is where the failure hides. An entry that forgets
its mode marker should fail the schema, not silently become always-required.

`subcommand:` carries the full subcommand path including spaces
(`roadmap populate`, `decisions record`), because that is the string the
surface probe must hand to `--help`.

### `skills/work-on/requires.yaml`

```yaml
schema: skill-requires/v1
requires:
  - { tool: koto, subcommand: version, flags: [], when: always }
  - { tool: koto, subcommand: init, flags: [--template, --var], when: always }
  - { tool: koto, subcommand: next, flags: [--with-data], when: always }
  - { tool: koto, subcommand: workflows, flags: [], when: always }
  - { tool: koto, subcommand: rewind, flags: [], when: always }
  - { tool: koto, subcommand: "decisions record", flags: [--with-data], when: always }
  - { tool: gh, when: always }
  - { tool: git, when: always }
  - { tool: jq, when: always }
```

(Shown in flow style for compactness; block style is equivalent and is what
a maintainer would write.) Sources: `skills/work-on/SKILL.md` lines 178-286
for the koto surface, `skills/work-on/koto-templates/work-on.md` lines
735/896/1090 for `gh pr checks`, `gh pr list`, `gh issue view`,
`git rev-parse`, and jq.

**Note the consequence of R3's cadence split.** `/work-on` has three modes
(`issue_backed`, `free_form`, `plan_backed`) and they differ in `gh` usage —
`gh issue view` runs only in `issue_backed`. But `gh` is independent-cadence,
so its entry names the tool alone, and every mode needs `gh` for PR
creation regardless. The mode distinction is therefore invisible at the
granularity R3 permits, and `/work-on`'s declaration is all-always. R5's
split only produces mode-scoped entries where a mode changes *which tool* is
needed, or changes a first-party subcommand or flag. This is worth stating
in the design so an author does not go looking for a `/work-on` mode
declaration that correctly does not exist.

### `skills/roadmap/requires.yaml`

```yaml
schema: skill-requires/v1
requires:
  - tool: shirabe
    subcommand: transition
    flags: []
    when: always
  - tool: shirabe
    subcommand: roadmap populate
    flags: [--no-issues]
    when: always
  - tool: shirabe
    subcommand: roadmap populate
    flags: [--issues, --milestone, --milestone-description, --output-map]
    when: mode:issues
  - tool: gh
    when: mode:issues
```

Sources: `skills/roadmap/SKILL.md` lines 115, 310 (`shirabe transition`),
418-428 (both `roadmap populate` forms verbatim), 369/379
(`gh issue create`). The issueless form runs on every path — line 390's
Phase 4 population and line 394's activate path — so `--no-issues` is
always-required while the issue-creating flags and `gh` are `mode:issues`.
This is the shape that satisfies the AC "Loading `/plan` on a host without
`gh` produces no `gh` finding; selecting multi-pr mode produces one," read
across to `/roadmap`.

Two entries share `tool: shirabe` and `subcommand: roadmap populate` at
different modes. That is deliberate: the entry unit is the triple, so R2's
composability holds per-entry and the check can evaluate the always subset
by filtering one field.

### `skills/decision/requires.yaml`

```yaml
schema: skill-requires/v1
requires: []
```

Verified: `skills/decision/SKILL.md` contains no `shirabe`, `koto`, `gh`,
`jq`, `git`, or `python3` call line. This is the PRD's named exemplar ("As
an author running `/decision`, which needs nothing beyond a checkout, I want
to see no trace of this feature at all"). The file exists and is empty;
deleting it would make `/decision` undeclared, which R1 requires be a
different state.

## Consequences

- **The reader is the `shirabe` binary.** No pure-bash reader is possible,
  because no assumable host tool parses YAML. This is a hard constraint on
  Decision 3 (what runs the check), and it carries a bootstrap problem: a
  skill declaring `shirabe` cannot have that declaration read when `shirabe`
  is the thing that is missing. Decision 3 needs a non-YAML fallback for
  exactly that one case — `command -v shirabe` is enough, and it needs no
  declaration to run.
- **The extraction scan must cover the whole skill directory**, not just
  `SKILL.md`. `/work-on`'s koto calls concentrate in
  `koto-templates/work-on.md`; `/execute`'s koto calls live in
  `koto-templates/execute.md`. A scan limited to `SKILL.md` would find
  almost none of the first-party call sites.
- **The scan must not follow cross-skill references.** R2 forbids
  inheritance, so `/execute` declares koto in its own file even though it
  delegates each issue to `/work-on`. `skills/execute/scripts/preflight.sh`
  resolves `../../work-on/koto-templates/work-on.md`; the extractor must
  stop at the skill boundary or `/execute` will be charged with
  `/work-on`'s surface.
- **Mode names are an interface.** `when: mode:issues` means the phase that
  selects the mode invokes the check with that exact string. The entry point
  Decision 3 chooses must accept a mode argument, and the mode names in
  `requires.yaml` must match the names the SKILL.md phases use.
- **Probing uses the full subcommand path.** `shirabe roadmap populate
  --help`, not `shirabe roadmap --help`. Two-word subcommands exist for both
  first-party tools (`roadmap populate`, `decisions record`).
- **A new CI check is needed either way.** Nothing in this repo validates
  SKILL.md frontmatter today — `crates/shirabe-validate/` never touches
  SKILL.md, and `scripts/` only checks for `evals.json` and
  `disable-model-invocation`. So option A's "the validators already parse
  frontmatter" advantage does not exist here; it would have to be built. A
  sidecar's presence check is the cheaper build:
  `scripts/check-evals-exist.sh` is a 20-line template for it.
- **Retirement lands cleanly.** `skills/work-on/SKILL.md:178` ("Run `koto
  version` to verify koto >= 0.3.3") is replaced by the `koto version` entry
  above minus the floor, satisfying R9 and R24 in the same edit.
  `references/fixes/cli-version-preflight.md`'s `shirabe <subcommand>
  --help | grep -qE -- '--flag'` probe is exactly what R7/R8 mechanize, so
  the reference retires into the check rather than being deleted outright.
