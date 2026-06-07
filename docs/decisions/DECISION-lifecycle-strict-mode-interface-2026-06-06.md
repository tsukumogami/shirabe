---
status: Accepted
decision: |
  The strict-mode toggle on `shirabe validate --lifecycle` is exposed as a
  `--strict` CLI flag on the validate subcommand. Default off. The lifecycle
  CI workflow templates the flag conditionally based on
  `github.event.pull_request.draft` and passes it on the run line. No
  environment-variable fallback; no flag-and-env combination.
rationale: |
  Parallels the existing `--visibility` flag's shape, which is already
  templated from GitHub Actions context in the validate-docs.yml workflow.
  Surfaces in `--help` output so authors running the check locally before
  pushing see the mode they would otherwise need to discover from
  documentation. Avoids a flag-vs-env precedence rule the combined option
  would introduce. The marginal YAML cost of templating the conditional
  flag is small and matches an existing pattern in the codebase.
---

# DECISION: lifecycle strict-mode interface

## Status

Accepted

## Context

The chain-aware lifecycle check that landed in the previous increment
accepts single-pr-mid-PR as a passing state. That acceptance is correct
during DRAFT-PR iteration but wrong on a READY PR — the chain should
have settled into its terminal (PLAN deleted, BRIEF/PRD at Done,
DESIGN at Current) before the PR flips out of draft.

The CI workflow needs a way to tell the validator "this is a READY PR;
run in strict mode" so the single-pr-mid-PR exemption is disabled. The
workflow can detect READY state from
`github.event.pull_request.draft == false`, but the validator has no
strict-mode toggle today. Three viable interfaces could carry the
toggle from the workflow to the validator.

The validator binary uses `clap` for argument parsing. The existing
`Cli` struct has `--visibility`, `--custom-statuses`, and `--lifecycle`
long flags — all set as CLI arguments at invocation time. The
`validate-docs.yml` workflow templates `--visibility` from
`github.repository_visibility` and `--custom-statuses` from a
workflow_call input. Both patterns are precedent for templating a
CLI flag from workflow context.

## Decision

A `--strict` CLI flag is added to the `validate` subcommand. Defaults
to off when the flag is absent.

The flag is consumed by the lifecycle module's check function when
`--lifecycle <root>` is also set; on per-file mode the flag has no
effect (and the parser accepts it without error, because per-file
mode does not invoke the lifecycle pass).

When set, strict mode disables the single-pr-mid-PR exemption: a
single-pr chain whose PLAN is present in the tree fails `L01`
(regardless of the PLAN's `status:` value), and a single-pr BRIEF or
PRD at Accepted (chain in single-pr posture) fails `L01`. Multi-pr
postures are unchanged — multi-pr in-flight remains a passing state
in strict mode, multi-pr work-completing remains a forcing-function
failure in both modes.

The lifecycle workflow templates the flag conditionally:

```yaml
run: |
  STRICT_FLAG=""
  if [ "${{ github.event.pull_request.draft }}" = "false" ]; then
    STRICT_FLAG="--strict"
  fi
  shirabe validate --lifecycle . $STRICT_FLAG
```

The shell conditional reads cleanly, matches the
`${CUSTOM_STATUSES:+--custom-statuses="$CUSTOM_STATUSES"}` precedent
in `validate-docs.yml`, and surfaces in the workflow run log so
maintainers can see whether strict was active on any run.

## Options Considered

### Option A — `--strict` CLI flag (chosen)

A single long flag on the validate subcommand. Default off.

**Pros.**

- Parallels `--visibility`. Same shape, same templating idiom, same
  discoverability via `--help`.
- Surfaces in `--help`. An author running the check locally sees
  the flag and its description without needing to read documentation
  outside the binary.
- No precedence rule. There is one place strict mode can be set —
  the call site — and one source of truth.

**Cons.**

- Workflow YAML is slightly more verbose than the env-var
  alternative (a four-line shell conditional vs a one-line env
  block).

### Option B — `SHIRABE_LIFECYCLE_STRICT` environment variable

A single env var read by the validator at startup. Truthy values
enable strict mode.

**Pros.**

- Slightly simpler workflow YAML — a single `env:` block with a
  conditional expression sets the variable.

**Cons.**

- Hidden from `--help`. Authors running the binary locally do not
  see the toggle exists unless they read documentation or source.
- Diverges from the `--visibility` precedent. The validator's
  other dimensions are CLI flags; introducing an env var as the
  primary interface for a new dimension breaks the pattern.
- Run logs do not show the env var's value unless the workflow
  echoes it explicitly. The CLI-flag form's `--strict` appears in
  the run log line directly.

### Option C — Both (CLI flag and env var)

The validator accepts both interfaces, with the CLI flag winning if
both are set.

**Pros.**

- Maximally flexible — workflow YAML can use either form, and
  authors can set either at the local CLI.

**Cons.**

- Two API surfaces to maintain — the flag, the env var, and the
  precedence rule documenting which wins on conflict.
- No proven need. The CLI-flag alternative covers every use case
  the present work surfaces; the env-var alternative would be an
  unused second channel.
- Increased test surface — strict-mode-via-flag, strict-mode-via-env,
  flag-overrides-env, env-set-alone all become test cases the
  validator's test surface has to cover.

## Consequences

The validator gains one CLI flag (`--strict`) and one branch in the
lifecycle check's passing-state computation (single-pr postures
honor the flag; multi-pr postures do not).

The CI workflow has one shell conditional in the lifecycle workflow's
run step. The conditional is read directly from
`github.event.pull_request.draft` without intermediate YAML
expression machinery, keeping the workflow legible.

The author running the check locally invokes it as:

```bash
shirabe validate --lifecycle .          # non-strict (preserves #173 behavior)
shirabe validate --lifecycle . --strict # strict
```

Future extension — for example, adding a `--no-strict` explicit
disable, or extending strict mode to multi-pr in-flight cases — is
done by extending the flag's semantics or adding sibling flags. The
env-var alternative would have constrained the extension path
through a second interface that the present decision does not
introduce.

## References

- `docs/prds/PRD-lifecycle-draft-ready-discipline.md` — R2 names the
  three alternatives and defers the choice to this decision record.
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`
  — the posture-detection rule the strict-mode toggle filters on.
- `.github/workflows/validate-docs.yml` — the existing reusable
  validator workflow whose `--visibility` flag templating pattern
  this decision mirrors.
