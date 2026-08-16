# Structural-Format Verdict: BRIEF-scope-chain-mandatory-steps

**Verdict:** PASS

All five required sections are present and canonically ordered, the frontmatter
is valid, FC03 holds under a raw-byte check, every cited path resolves, and the
validator returns `clean` with a single non-blocking notice.

## Verdict

PASS

## Per-Criterion

### 1. Required sections present and ordered

PASS. Heading scan (`grep -n '^## '`):

| Line | Section | Status |
|------|---------|--------|
| 23 | Status | required, 1st |
| 33 | Problem Statement | required, 2nd |
| 92 | User Outcome | required, 3rd |
| 120 | User Journeys | required, 4th |
| 166 | Scope Boundary | required, 5th |
| 222 | Open Questions | optional, Draft-only |
| 235 | References | optional |

The five required sections appear in the canonical order the Section Matrix
specifies, with no interleaving. Both optional sections follow all five.

`Open Questions` is legal here: the Section Matrix marks it `Draft only` and the
document is in `Draft`. It carries two entries, each deferring a framing detail
to the downstream PRD's Decisions and Trade-offs section (the canonical closure
surface the format names) rather than raising a blocker that should stop the
brief. `Downstream Artifacts` is absent, which is correct — it is optional and
no downstream PRD or design exists yet.

Sub-structure checks: `## User Journeys` carries five `###` journey headings
(lines 122, 132, 141, 150, 159), and `## Scope Boundary` carries the required
explicit `### In` (168) and `### Out` (196) lists.

### 2. Frontmatter valid

PASS.

- `schema: brief/v1` — correct, matches the routing key the validator uses.
- `status: Draft` — one of the three legal values (Draft / Accepted / Done).
- `problem:` — YAML literal block scalar (`|`), 4 lines (file lines 5-8). Within
  the 2-4 line bound.
- `outcome:` — literal block scalar (`|`), 3 lines (lines 10-12). Within bound.
- `motivating_context:` — literal block scalar (`|`), lines 14-18. Optional and
  legal; the format reference sets no line bound on this field.
- `upstream:` — absent. Optional, and correctly so: this brief is authored from
  an `/explore` run rather than sequenced off a roadmap, so there is no
  one-hop durable ancestor to name. No R11 exposure.

No unknown or misspelled fields. The full key set is `schema`, `status`,
`problem`, `outcome`, `motivating_context` — every one is in the format
reference's recognized set.

### 3. FC03 status match

PASS. Verified literally against the raw bytes with `sed -n '19,34p' ... | cat -A`:

```
## Status$
$
Draft$
$
Framed from the `/explore` run on this branch. Two questions are deferred to the$
```

The entire first non-blank line under `## Status` is `Draft` — the bare status
word alone, with no trailing punctuation, no trailing whitespace, and no prose
on the line. It is followed by a blank line before the explanatory paragraph.
It equals the frontmatter `status: Draft` exactly. This is the shape the format
reference documents as passing, and it avoids the corpus's most common FC03
failure (prose appended to the status line).

Confirmed independently by the validator, which reported no FC03 finding.

### 4. Public-visibility clean

PASS. No violations found.

Every path named anywhere in the document (11 distinct paths, see criterion 6)
is an in-repo public path under `docs/`, `references/`, `skills/`, or `crates/`.
A targeted scan for private-visibility markers returned nothing:

```
grep -n -i -E 'private/|tsukumogami/vision|tsukumogami/coding-tools|dot-niwa-overlay|CLAUDE.overlay' -> no match
```

**On the issue numbers.** The brief cites `#280` and `#302` in bare form (12
occurrences of `#302`, 1 of `#280`). These are clean. The format reference is
explicit that the restriction covers issue numbers *from private repos*, and
that "public GitHub issue numbers from the same repo are routinely cited and
not in scope of this restriction." A survey of the committed public corpus
confirms bare `#NNN` is the established convention here — `#176` appears 27
times, `#220` 14 times, `#159` 11 times, and so on across `docs/briefs/` and
`docs/prds/`. The predecessor brief writes the same issue as `shirabe#280`
(repo-qualified); both forms appear in the corpus and neither is a visibility
problem.

No internal codenames, no pre-announcement features, no private filenames.

### 5. Writing style

PASS, with one notice-severity finding recorded under Optional Improvements.

Mechanical checks against `skills/writing-style/rules.yaml` (the single
authoritative source, read directly rather than from memory):

- **Banned vocabulary: zero hits.** A scan across all five term categories —
  organizing, verbs, descriptors, abstract-nouns — returned no match. The
  document does not even lean on the CLAUDE.md Prose Vocabulary exemption: the
  only occurrence of any exempted term is `## User Journeys`, which is the
  format-mandated section heading, and `tier` and `underscore` appear nowhere.
- **Adverb openers: zero hits.** No sentence or bullet opens with
  Additionally / Notably / Ultimately / Furthermore / Moreover / Significantly /
  Seamlessly.
- **Structural tells: zero hits.** No "serves as", "stands as", "boasts", no
  "it's not just X, it's Y", no "it's worth noting".
- **Over-formality: zero hits.** No "in order to", "due to the fact that",
  "prior to", "subsequent to", "with respect to", "has the ability to".
- **No emojis** (Unicode range scan returned nothing), **no AI attribution
  lines**, **no placeholder text** (`TBD`, `TODO`, `<Phase N will fill this>`
  all absent). Every section carries real content.

Judgment-only rules — the part no matcher reaches, and where the review value
sits:

- **Low information density:** not present. The prose is unusually concrete. It
  names specific surfaces (`chain_revised:`, `chain_skipped[].reason`, the
  `Proceed / Adjust / Bail?` prompt), specific scenario names, and specific
  counts. There is no paragraph that could be deleted without losing a fact.
- **Empty conclusions:** none. The Problem Statement's closing paragraph ("The
  cost is not cosmetic...") adds three consequences not stated above it, one per
  affected reader, rather than restating the section.
- **Demonstratives without antecedent:** checked, none found. Each "this" and
  "that" resolves to a nameable prior noun.
- **Attribution without citation:** none. Claims about what a surface says are
  attached to the named surface.
- **Forced rule of three:** not present. The counts are load-bearing and vary
  (four surfaces, five journeys, two open questions, four routing entries).
- **Synonym cycling:** not present. "Absorb", "fold", and "consolidate" are used
  consistently as the shipped vocabulary rather than rotated for variety.

Burstiness is good — short declaratives ("Then the chain starts." / "What goes
is the question mark." / "It is kept.") sit next to long analytical sentences.

### 6. References resolve

PASS. Every path in the References section and in the body prose was checked on
disk with `ls`. All 11 exist:

| Path | Cited in | Exists |
|------|----------|--------|
| `docs/briefs/BRIEF-scope-artifact-persistence.md` | References | yes |
| `docs/prds/PRD-scope-artifact-persistence.md` | References | yes |
| `docs/designs/current/DESIGN-scope-artifact-persistence.md` | References | yes |
| `docs/prds/PRD-scope-consolidation-over-skipping.md` | References | yes |
| `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` | References | yes |
| `references/parent-skill-pattern.md` | References + prose (151, 184) | yes |
| `skills/scope/references/phases/phase-2-chain-orchestration.md` | References | yes |
| `references/parent-skill-state-schema.md` | Scope Boundary In | yes |
| `skills/scope/evals/evals.json` | Journeys + Scope Boundary In | yes |
| `references/pipeline-model.md` | Scope Boundary In | yes |
| `crates/shirabe-validate/src/formats.rs` | Scope Boundary Out | yes |

Extraction was done two ways to avoid missing an unbackticked path — a scan for
backticked `a/b` tokens and a scan for bare `dir/file.ext` tokens — and both
returned the same 11. No `wip/...` paths appear anywhere in the document, so
the wip-hygiene rule is satisfied.

Beyond paths, the two eval scenario names quoted in the Problem Statement were
verified as real rather than paraphrased:
`durable-artifact-floor-is-structural` at `skills/scope/evals/evals.json:276`
and `consolidation-keep-at-unmapped-hop` at line 304. Both exist verbatim.

## Validator Output

Command run (the flag combination in the rubric worked as given):

```
shirabe validate docs/briefs/BRIEF-scope-chain-mandatory-steps.md --format json --visibility=Public
```

Exit status: **0**

```json
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "clean",
    "errors": 0,
    "notices": 1
  },
  "findings": [
    {
      "code": "FC10",
      "severity": "notice",
      "message": "[FC10] em-dash-density: 11.5 per thousand words over 1912 words, above the threshold of 10 -- see skills/writing-style/rules.yaml",
      "file": "docs/briefs/BRIEF-scope-chain-mandatory-steps.md",
      "line": 37
    }
  ],
  "advisory": {
    "summary": "Draft posture: no draft-tolerable findings to flag.",
    "notes": []
  }
}
```

Summary outcome is `clean` with 0 errors. FC01 through FC04 (required fields,
valid status, FC03 status match, required sections) all pass silently. The one
finding is notice severity, and the Draft-posture advisory explicitly clears it.

## Required Changes

None.

## Optional Improvements

1. **Frontmatter `problem` and the body disagree on which side `/scope` is on.**
   The frontmatter reads "`/scope` and `/execute` state the post-#302 model"
   and then lists the stale surfaces as `/explore`, the parent-skill pattern,
   and the eval suite — three. The body's Problem Statement says "Four surfaces
   still describe the world before #302" and counts `/scope` among them. Both
   statements are individually true and reconcile once you read the body's
   `/scope` paragraph (its prose is correct, the prompt beside it is stale), but
   a reader comparing the frontmatter summary against the body headline gets
   three versus four. Since the frontmatter is the machine-read summary, one
   qualifying clause there — something like "`/scope` states it and then
   contradicts it" — would close the gap. Non-blocking: the format's consistency
   test is "paraphrase is fine; contradiction is not," and the body resolves
   this within the same section.

2. **Em-dash density (FC10), 11.5 per thousand against a threshold of 10.**
   Twenty-two em dashes across 1912 scoped words; dropping three would clear it.
   Worth knowing before you act on this: it is corpus-normal rather than an
   outlier. The predecessor `docs/briefs/BRIEF-scope-artifact-persistence.md`
   carries the same notice at 10.3 per thousand. The rule is a document-level
   rate a drafting model cannot see while composing, which is why it exists. If
   you do trim, the densest cluster is the Problem Statement (the finding points
   at line 37); several of those pairs read fine as commas or parentheses.

3. **Journeys 2 and 3 are the closest call in an otherwise well-separated set.**
   "An author entering the tactical chain" and "An author who knows the framing
   is already settled" both open with an author running `/scope`. They do clear
   the distinctness bar — different entry conditions (routine invocation versus
   a belief that upstream work is unnecessary) reaching different outcome shapes
   (the confirmation prompt disappearing versus the redirect being answered
   coherently) — so this is not a violation. But journey 3's opening line could
   name its distinguishing trigger more sharply, since it is the one journey
   whose separation depends on the reader reaching the second sentence.

4. **Contraction density is low** — one contraction in roughly 1900 words. The
   writing-style skill lists absent contractions as a formatting tell. Applied
   here it is a weak signal: the register is consistent with the rest of the
   durable-spec corpus, and the prose is direct rather than stiff. Mentioned for
   completeness, not as something to change.
