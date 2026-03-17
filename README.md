# shirabe (調べ)

Structured workflow skills for AI coding agents.

shirabe provides five workflow skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
that guide you from idea to implementation with enforced phase transitions,
multi-round research, and CI-validated document lifecycle. Powered by
[koto](https://github.com/tsukumogami/koto) for structural enforcement.

**Pronunciation:** shee-RAH-beh

## What it does

shirabe covers the thinking phase before coding:

| Skill | What it does |
|-------|-------------|
| `/explore` | Fan out research agents to investigate options, then decide what artifact to produce |
| `/design` | Produce a technical architecture document with jury validation |
| `/prd` | Capture product requirements with numbered criteria |
| `/plan` | Decompose a design into sequenced GitHub issues with dependency graphs |
| `/work-on` | Implement a single issue with structured phases |

Each skill is backed by a koto workflow template -- a state machine with
evidence-gated transitions. Agents can't skip steps they can't see.

## Installation

### As a Claude Code plugin

```
/plugin install tsukumogami/shirabe
```

### For your team (CI validation)

Add a small PR to your repo (~4 files, ~60 lines) that references shirabe's
reusable validation workflows:

```yaml
# .github/workflows/validate-docs.yml
name: Validate Design Docs
on: [pull_request]
jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1
    with:
      config-path: tsukumogami.yml
```

See [Repo Setup Guide](docs/guides/repo-setup.md) for the full setup.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [koto](https://github.com/tsukumogami/koto) (installed automatically on
  first skill invocation)

## License

Apache 2.0
