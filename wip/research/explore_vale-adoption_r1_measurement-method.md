# Measurement Method: vale-adoption

How every measured number in the BRIEF and findings was produced, so the
DESIGN can re-run them rather than trusting a transcript. Vale is not
installed on this machine; the runs below used the official v3.17.1 release
binary downloaded to a scratch directory.

## Setup

```bash
curl -sL --cacert /etc/ssl/certs/ca-certificates.crt \
  -o vale.tgz \
  https://github.com/vale-cli/vale/releases/download/v3.17.1/vale_3.17.1_Linux_64-bit.tar.gz
tar xzf vale.tgz vale
./vale --version   # vale version 3.17.1
```

Note the org move: the repo is now `vale-cli/vale`, not `errata-ai/vale`.
`vale sync` needs network; linting afterwards does not.

## Off-the-shelf styles on shirabe content

```ini
# .vale.ini
StylesPath = styles
MinAlertLevel = suggestion
Packages = write-good, proselint, Microsoft

[*.md]
BasedOnStyles = write-good, proselint, Microsoft
```

`vale sync` then:

```bash
vale --no-global --config=.vale.ini --output=line <path>
```

Measured alert density (alerts per 1000 words):

| File | Words | Alerts | Per 1k |
|---|---|---|---|
| `skills/writing-style/SKILL.md` | 576 | 0 | 0.0 |
| `skills/design/SKILL.md` | 1622 | 77 | 47.5 |
| `skills/prd/SKILL.md` | 1304 | 94 | 72.1 |
| `skills/plan/SKILL.md` | 3199 | 222 | 69.4 |
| `skills/execute/SKILL.md` | 6027 | 645 | 107.0 |
| `CLAUDE.md` | 1636 | 169 | 103.3 |
| `README.md` | 2263 | 165 | 72.9 |
| `AGENTS.md` | 423 | 21 | 49.6 |

Rule breakdown on `CLAUDE.md` (169 alerts): `write-good.E-Prime` 36,
`Microsoft.Acronyms` 28, `Microsoft.Headings` 15, `write-good.Passive` 13,
`Microsoft.Passive` 13, `Microsoft.Vocab` 11, `Microsoft.SentenceLength` 9,
`Microsoft.Semicolon` 8, `Microsoft.Dashes` 7, `Microsoft.Contractions` 7,
rest single digits.

Representative false positives, verbatim:

```
CLAUDE.md:1:3:Microsoft.Headings:'shirabe' should use sentence-style capitalization.
CLAUDE.md:6:4:Microsoft.Headings:'Repo Visibility: Public' should use sentence-style capitalization.
CLAUDE.md:57:8:Microsoft.Acronyms:'BRIEF' has no definition.
CLAUDE.md:57:15:Microsoft.Acronyms:'PRD' has no definition.
CLAUDE.md:61:37:Microsoft.Acronyms:'SKILL' has no definition.
```

`## Repo Visibility: Public` is parsed by the validator's FC-CONVENTIONS
check as an exact string, so complying with that alert would break the
tooling. This is the concrete reason a stock style cannot ship here.

## The vacuity demonstration

A three-paragraph document of fluent, grammatical, contentless prose:

```markdown
# Architecture overview

The system is designed to handle the needs of the platform. Its components
work together in a way that supports the goals of the project. Each part
has a role, and the roles fit together.

The approach we take reflects the priorities we have set. Where trade-offs
arise, we resolve them in line with those priorities. This gives us a
foundation we can build on.

Going forward, the architecture will continue to evolve. As requirements
change, the design will adapt. The result is a system that meets its
objectives.
```

Result: 10 alerts, none about the vacuity. The only `error`-level alert,
and therefore the only one that would produce a non-zero exit code, was
`Microsoft.Contractions`: "Use 'we've' instead of 'we have'." The rest were
passive-voice and first-person-plural suggestions.

This is the empirical form of the capability ceiling. It also demonstrates
the exit-code trap: Vale exits non-zero only on `error`-level alerts, and
most shipped rules are `suggestion` or `warning`, so a CI gate keyed on
exit status passes almost everything.

## Custom shirabe-derived style

Three rule files translating `skills/writing-style/SKILL.md`:
`AvoidWords.yml` (34 tokens, `extends: existence`), `Formality.yml`
(9 pairs, `extends: substitution` with `action: name: replace`), and
`Phrases.yml` (13 patterns, `extends: existence`).

Run over `docs/` (145 files, 463,440 words):

| Rule | Alerts |
|---|---|
| `Shirabe.AvoidWords` | 156 |
| `Shirabe.Formality` | 5 |
| `Shirabe.Phrases` | 1 |

Word frequency within the 156:

| Word | Hits |
|---|---|
| tier | 82 |
| Tier | 46 |
| robust | 7 |
| leverage | 5 |
| comprehensive | 4 |
| tiered | 3 |
| holistic | 3 |
| facilitate | 3 |
| Tiered | 1 |
| resilience | 1 |
| nuanced | 1 |

128 of 156 (82%) are `tier` in its Tier 1-4 sense. Concentration:
`DESIGN-shirabe-pattern-v1-ergonomics.md` 65,
`DESIGN-decision-framework.md` 24. Sample context from
`DESIGN-decision-framework.md`:

```
157:decision is Tier 3+, it:
471:1. **Reversibility**: irreversible forces Tier 4
472:2. **Heuristic confidence**: decisive result = Tier 2, close result = Tier 3
```

## Em dash density

```bash
grep -o "—" -r docs --include="*.md" | wc -l    # 3195
grep -o "—" -r skills --include="*.md" | wc -l  # 1222
```

Per-thousand rates use `find <dir> -name "*.md" -exec cat {} + | wc -w`
as the denominator (`docs/` = 463,440 words).

## Performance

Full custom-style run over `docs/`, 145 files, 463k words:

```
real 0m0.444s
user 0m2.004s
sys  0m0.141s
```

Concurrent per file. Latency is not a constraint for any deployment shape
under consideration.

## Validator claims verified directly

```bash
grep -n "FC10_BANNED_WORDS" -A 12 crates/shirabe-validate/src/checks.rs
sed -n '245,260p' crates/shirabe-validate/src/formats.rs
grep -n "^## User Journeys" docs/briefs/BRIEF-execute-skill.md
```

confirming the seven-word constant, that `detect_format` is a
`starts_with` prefix match over the eight artifact types, and that
`## User Journeys` is a real required section heading (so `journey` on
the banned list collides with the BRIEF format itself).

The FC10 line-offset bug reproduces on this chain's own BRIEF: the
validator reported `tier` at lines 40, 41, 43, 69, 107, 127 while the
word actually appears at 60, 89, 127, 147. The delta is exactly 20, the
frontmatter length.
