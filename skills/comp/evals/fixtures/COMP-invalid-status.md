---
schema: comp/v1
status: Bogus
problem: |
  Which approach should our build-tool take for plugin distribution.
scope: |
  Developer build tools that support a plugin ecosystem.
---
<!-- SYNTHETIC TEST CONTENT — not a real competitive analysis. Used by skills/comp/evals/test-cli.sh. -->

# COMP: build-tool plugin distribution

## Status

Bogus

## Market Overview

Competitors are compared along three dimensions: distribution model,
plugin discovery, and version pinning.

## Competitors

### Acme Build

Strong plugin discovery via a central registry; weak on offline version
pinning.

### Borg Build

Strong offline pinning; weak discovery (no central registry).

## Comparative Matrix

| Tool       | Distribution | Discovery | Pinning |
|------------|--------------|-----------|---------|
| Acme Build | registry     | strong    | weak    |
| Borg Build | git          | weak      | strong  |

## Opportunities

No surveyed tool offers both a central registry and offline-deterministic
pinning.

## Implications

The analysis suggests we should pair a registry with a lockfile, because
neither competitor covers both.

## References

- [Acme Build docs](https://example.com/acme) (2026-01-15)
- [Borg Build docs](https://example.com/borg) (2026-01-15)
