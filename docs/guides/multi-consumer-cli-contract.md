# The `validate` multi-consumer contract

`shirabe validate` serves three callers: continuous integration, the
workflow skills, and local pre-commit hooks. Each consumes the same checks
through a different slice of the command's surface. This guide states the
contract each one relies on, so a change that would break a consumer is
visible before it ships.

## Output modes

`validate` has three output modes, selected with `--format`:

- **`annotation`** (the default) — GitHub Actions workflow commands
  (`::error file=...,line=...::message` and `::notice ...`). This is the
  format CI consumes, and it is byte-stable: the bytes for a given set of
  inputs do not change.
- **`json`** — a machine-readable envelope for programmatic consumers. Its
  shape is versioned (see below).
- **`human`** — a terminal-shaped summary: one line per finding
  (`<file>:<line> <severity> <message>`) and a footer with the error and
  notice counts and the outcome.

The default is `annotation` so an invocation that passes no `--format`
behaves exactly as it did before the modes existed.

### The JSON envelope

`--format json` emits a single object:

```json
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "violations",
    "errors": 1,
    "notices": 0
  },
  "findings": [
    {
      "code": "FC03",
      "severity": "error",
      "message": "...",
      "file": "docs/designs/DESIGN-foo.md",
      "line": 11
    }
  ]
}
```

- `schema_version` follows the `<name>/v<major>` convention. Additive
  changes keep the major; a breaking change bumps it. Pin on the major.
- `severity` is `error` or `notice`, derived from the same rule the
  annotation mode uses to split the two — the modes cannot disagree.
- `line` is the integer line number, or `null` when the finding has no
  specific line.

## Exit codes

`validate` returns the multi-level exit code shared with `transition` and
`finalize-chain`:

| Code | Meaning |
|------|---------|
| `0` | Clean — no error-level violations. |
| `1` | Tool error — the run could not complete (bad invocation, an unreadable or unparseable file, an unknown `--check` code). |
| `2` | Violations — the run completed and found at least one error-level result. |
| `3` | I/O error. |

Two rules matter for consumers:

- **Notice-level results never make a run non-clean.** A run that emits
  only notices exits `0`.
- **Across multiple documents the most severe outcome wins** — a tool
  error outranks violations, which outranks clean. Note that severity and
  the exit integer differ on purpose: a tool error is more severe than a
  violation but maps to the lower code `1`, matching the sibling commands.

A consumer that only distinguishes zero from non-zero (a pass/fail gate)
keeps working unchanged, because clean is `0` and every other outcome is
non-zero.

## Per-check selection

`--check <code>` restricts a run to one or more named checks. It is
repeatable and comma-splittable: `--check FC01 --check R7` and
`--check FC01,R7` are equivalent. With no `--check`, the full applicable
pass runs.

- The selectable codes are the per-file checks: `SCHEMA`, `FC01`-`FC13`,
  `FC-CONVENTIONS`, and `R6`-`R9`.
- An unknown code is a tool error (exit `1`), naming the offending code.
- A valid but format-inapplicable code (for example `FC05`, a plan check,
  against a brief) is a clean no-op: the check simply does not run for that
  format.
- Selection drives both what is reported and the outcome, so selecting
  only a check that passes is a clean run even if an unselected check would
  have failed.

## Path ownership

`validate` does not decide which files to look at. It validates exactly the
paths it is given and reads no git history to discover changed files. The
caller — the CI workflow, or the installed pre-commit hook — computes the
file set and passes the paths in.

## The three consumers

| Consumer | Output mode | Exit code | How paths are supplied |
|----------|-------------|-----------|------------------------|
| **CI** (the reusable `validate-docs.yml` workflow) | `annotation` (default; no `--format`) | Zero vs non-zero as the pass/fail gate | The workflow computes the changed-file set with `git diff --name-only` and passes the paths positionally. |
| **The workflow skills** | `json` | Branches on the `0/1/2/3` contract — proceed on clean, surface named violations on `2`, escalate differently on `1` | The skill passes the document paths it cares about. |
| **Local pre-commit hooks** | `human` | Fail-closed: any non-zero exit blocks the commit | The hook (scaffolded by `shirabe install-hooks`) computes the staged set with `git diff --cached` and passes the paths after a `--` separator. |

## Installing the local hook

`shirabe install-hooks` writes a pre-commit hook into the repository's
hooks directory. The hook runs `validate` over the staged Markdown
documents at commit time and blocks the commit on any non-zero exit. An
existing pre-commit hook is left untouched and reported unless `--force` is
given.
