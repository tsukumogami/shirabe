# Lead: How much of shirabe's writing-style rulebook survives translation into Vale rules?

## Findings

### 0. What I read, and what I could and couldn't run

Sources read in full:

- `public/shirabe/skills/writing-style/SKILL.md` (74 lines, 7 sections)
- `public/shirabe/skills/writing-style/evals/evals.json` (8 evals, 79 assertions)
- `CLAUDE.md` (workspace root) — "Writing Style" and "Communication Style" sections
- A second, older copy of the rulebook shipped with the `tsukumogami` plugin at
  `private/tools/plugin/tsukumogami/helpers/writing-style.md` (private repo — do
  not cite this path in any public artifact; I read it only to assess divergence)
- `public/shirabe/docs/prds/PRD-shirabe-pattern-v1-ergonomics.md` (status: Done) —
  contains R20 and AC4.3, an already-accepted requirement for exactly this check
- `public/shirabe/skills/design/references/design-format.md` — the DESIGN template

**Vale is not installed** (`command -v vale` → not found; nothing in `~/.tsuku/bin`
or `/usr/local/bin`). Per the brief I did not install it. Everything below is
derived from the Vale specification (fetched from docs.vale.sh) plus **empirical
regex approximation** run over the real corpus: 145 markdown files / 397,198 prose
words under `docs/`, and 211 files / 156,569 prose words under `skills/`, code
fences stripped. Vale uses `regexp2`, which supports lookaround, so `grep -P` is a
fair stand-in for `existence`/`substitution` matching. The `occurrence`,
`capitalization`, `metric`, and `script` behaviours I reimplemented in Python
against the same corpus. Scripts live in `/home/dgazineu/.claude/jobs/b0818094/tmp/`.

### 1. Vale's capability surface (verified against docs.vale.sh)

Eleven extension points exist: `existence`, `substitution`, `occurrence`,
`repetition`, `consistency`, `conditional`, `capitalization`, `spelling`,
`sequence`, `script`, `metric`.

The two that matter most for the hard cases, and that I had to verify rather than
assume:

- **`metric`** is real. Fields are `formula` and `condition`. Pre-defined
  variables: `characters`, `words`, `sentences`, `syllables`, `paragraphs`,
  `complex_words`, `polysyllabic_words`, `long_words`, `blockquote`, `list`,
  `pre`, `heading.h{n}`. Operators `+ - * /`, `math.sqrt`, `math.abs`; conditions
  `> < == >= <=` against floats. **All metric rules are summary-scoped** (whole
  document). Critically: the variable list contains *no punctuation counts and no
  per-sentence data*, so metric alone cannot do em dashes, bold, or variance.
- **`script`** is real: Tengo, file at `$StylesPath/config/scripts/*.tengo`. The
  script receives the `scope` text and must populate a `matches` array of
  `{begin, end}` maps. With `scope: raw` it sees the whole document. Regex inside
  scripts is limited to *standard Go* syntax (no lookaround) — unlike every other
  rule type.
- **Scopes**: `heading` (+`.h1`–`.h6`), `paragraph`, `sentence`, `list`, `table.*`,
  `blockquote`, `alt`, `summary`, `raw`, `link`, `code`, `strong`, `emphasis`.
  Negate with `~`, AND with `&`, OR with a list. `strong` scope means bold text is
  directly addressable.
- **`occurrence`** counts `token` matches *within each block the scope selects*,
  not across the document. Document-wide counting requires `scope: raw`.

### 2. The classification table

Granularity: one row per rule as a reader of `SKILL.md` would count them
(a table row, a bullet, or a word category). 38 rules.

| # | Section | Rule (verbatim where short) | Class | Note |
|---|---------|------------------------------|-------|------|
| 1 | Words | Organizing: `tier/tiered, robust, comprehensive, holistic, crucial, pivotal, paramount` | **B** | 4 of 7 clean; `tier` and `robust` are domain terms here |
| 2 | Words | Verbs: `leverage, utilize, facilitate, delve, foster, navigate, showcase, grapple, transcend, elucidate, underscore, highlight, enhance, align with, garner` | **B** | 7 clean; `underscore`/`highlight`/`navigate`/`enhance`/`align with`/`leverage` all have literal technical senses |
| 3 | Words | Descriptors: `innovative, transformative, profound, vibrant, seamless, meticulous, invaluable, nuanced, groundbreaking, intricate` | **A** | cleanest category in the book |
| 4 | Words | Abstract nouns: `journey, narrative, tapestry, testament, resilience, landscape (fig.), interplay, realm` | **B** | the `(fig.)` qualifier is unmechanizable; `journey` is a required section name |
| 5 | Words | Adverb openers: `Additionally, Notably, Ultimately, Seamlessly, Significantly, Furthermore, Moreover` | **A** | `scope: sentence` + `^` anchor |
| 6 | Phrases | "It's worth noting / important to note that" | **A** | |
| 7 | Phrases | "In today's X", "Let's delve into", "At its core" | **A** | |
| 8 | Phrases | "In conclusion", "In summary", "As previously mentioned" | **A** | |
| 9 | Phrases | "I hope this helps", "Great question!", "Absolutely!", "Certainly!", "Of course!", "Sure!" | **A** | |
| 10 | Phrases | "As of my training / knowledge cutoff" | **A** | |
| 11 | Phrases | "experts argue", "studies show" **without citation** | **C** | the token is trivial; "without citation" is the rule and Vale can't evaluate it |
| 12 | Phrases | "This provides valuable insights into" | **A** | |
| 13 | Structural | "serves as", "stands as", "boasts" → is/are/has | **B** | measured 27% precision (see §4) |
| 14 | Structural | "It's not just X, it's Y" | **B** | `not just … (but\|it's)` window regex |
| 15 | Structural | Synonym cycling → repeat the word | **D** | `consistency` needs you to *name* the synonym pair in advance |
| 16 | Structural | "from X to Y" on no real scale | **D** | 0/55 precision empirically — unusable |
| 17 | Structural | Stacked qualifiers ("could potentially possibly") | **B** | adjacent-hedge regex only; non-adjacent stacking escapes |
| 18 | Structural | Hollow gerunds: "highlighting/underscoring/emphasizing" | **B** | precision rises a lot if you require a preceding comma |
| 19 | Structural | Forced rule of three | **D** | a script can count 3-item lists; nothing can know the true count |
| 20 | Formatting | **Em dash overuse (—)** | **B** | `occurrence` per paragraph works; density needs `script` |
| 21 | Formatting | **No contractions** | **C** | absence undetectable; detect the uncontracted form as a proxy, or ratio via script |
| 22 | Formatting | **Title Case Headings** → sentence case | **A** | mechanically trivial; **conflicts with shirabe's own templates** (§5) |
| 23 | Formatting | **Boldface overuse** | **B** | `occurrence` on `\*\*…\*\*` per paragraph; "genuine emphasis" is not decidable |
| 24 | Formatting | **Uniform paragraph length** | **C** | `script` only; `metric` has `paragraphs` but no per-paragraph lengths |
| 25 | Formality | "In order to" → "To" | **A** | free from `Microsoft.Wordiness` |
| 26 | Formality | "Due to the fact that" → "Because" | **A** | free |
| 27 | Formality | "At this point in time" → "Now" | **A** | free (Microsoft swaps to "at this point") |
| 28 | Formality | "Prior to" / "Subsequent to" → "Before" / "After" | **A** | free |
| 29 | Formality | "With respect to" → "About"/"For" | **A** | not in Microsoft; one line to add |
| 30 | Formality | "Has the ability to" → "Can" | **A** | free |
| 31 | Cognitive | Low information density | **D** | |
| 32 | Cognitive | Empty conclusions | **D** | only the lexical shell ("In conclusion") is reachable, already row 8 |
| 33 | Cognitive | "this/that/these" without antecedent | **C** | sentence-initial bare demonstrative + verb is a decent partial proxy |
| 34 | Cognitive | Vague attribution without citation | **C** | same shape as row 11 |
| 35 | Human | **Burstiness** (3-word next to 25-word sentence) | **C** | `script` can compute stdev; `metric` cannot |
| 36 | Human | "And"/"But"/"Or" as sentence starters are fine | **A** | an *anti*-rule: it means you must not enable `proselint.But` etc. |
| 37 | Human | Specifics over abstractions: name the file, cite the number | **D** | |
| 38 | Human | Opinions: take a position | **D** | |

**Ratio by raw rule count:**

| Class | Count | Share |
|-------|-------|-------|
| A — fully mechanizable, high precision | 16 | 42% |
| B — mechanizable, false-positive problem | 9 | 24% |
| C — partially mechanizable | 6 | 16% |
| D — out of reach for a token matcher | 7 | 18% |

A+B = 66%. Counting individual lexical items instead of rules (47 words + ~20
phrases + 6 substitutions = 73 tokens) shifts it toward A: roughly 48 A / 25 B,
because the word lists dominate by volume.

**Ratio weighted by what actually matters for output quality — this is the number
that counts, and it inverts:**

| Class | Weighted share of realizable quality value | Why |
|-------|---------|-----|
| A | ~10% | Empirically already satisfied. On 554k words of real shirabe prose the A-class phrase rules fire **essentially zero true positives** (§4). They would run green forever. |
| B | ~65% | Em dash density alone is the single largest measurable defect in the corpus (§4) and it lives here. Bold density and the word lists are also here. |
| C | ~20% | Burstiness and paragraph uniformity are real defects a script could measure; contraction ratio likewise. |
| D | ~5% | Genuinely lost, but these were never going to be caught by anything short of a model. |

The uncomfortable conclusion: **the mechanizable-with-high-precision half of the
rulebook is the half the model is already obeying.** The value is concentrated in
class B, where Vale needs custom `occurrence`/`script` rules that no off-the-shelf
package provides and where false positives are the design problem.

### 3. The actual Vale configuration

22 rule files plus a config. Directory layout:

```
.vale.ini
styles/
  config/
    vocabularies/Shirabe/accept.txt
    scripts/em-dash-density.tengo
    scripts/burstiness.tengo
    scripts/contraction-ratio.tengo
  Shirabe/
    WordsDescriptors.yml
    WordsOrganizing.yml
    WordsVerbs.yml
    WordsAbstract.yml
    AdverbOpeners.yml
    FillerPhrases.yml
    ChatbotArtifacts.yml
    EmptyOpeners.yml
    VagueValue.yml
    UncitedAuthority.yml
    ServesAs.yml
    NotJust.yml
    StackedQualifiers.yml
    HollowGerunds.yml
    OverFormality.yml
    EmDashPerParagraph.yml
    EmDashDensity.yml
    BoldPerParagraph.yml
    HeadingCase.yml
    BareDemonstrative.yml
    Burstiness.yml
    SentenceLength.yml
```

#### `.vale.ini`

```ini
StylesPath = styles
MinAlertLevel = suggestion
Packages = Microsoft
Vocab = Shirabe

[*.md]
BasedOnStyles = Shirabe

; free coverage from Microsoft for the over-formality table
Microsoft.Wordiness    = warning
Microsoft.Contractions = suggestion

; explicitly OFF: shirabe's rulebook says these are fine or wanted
Microsoft.We           = NO
Microsoft.FirstPerson  = NO
Microsoft.Passive      = NO
Microsoft.Headings     = NO
Microsoft.Adverbs      = NO

[skills/writing-style/**]
BasedOnStyles =
```

That last block is not optional: without it, the rulebook flags itself. Empirically
`skills/writing-style/SKILL.md` accounts for a hit on **almost every single banned
word and phrase** — 1 hit each for "delve", "at its core", "great question",
"boasts", "in conclusion", and 30 others. Same for the PRD that quotes them.

#### Class A — existence and substitution

`Shirabe/WordsDescriptors.yml` (row 3, the cleanest rule in the book):

```yaml
extends: existence
message: "'%s' is an AI-tell descriptor. Cut it or name the concrete property."
link: https://github.com/tsukumogami-dev/shirabe/blob/main/skills/writing-style/SKILL.md
level: warning
ignorecase: true
tokens:
  - innovative
  - transformative
  - profound(ly)?
  - vibrant
  - meticulous(ly)?
  - invaluable
  - groundbreaking
  - intricate
  - seamless(ly)?
  - nuanced
```

`Shirabe/AdverbOpeners.yml` (row 5):

```yaml
extends: existence
message: "'%s' as a sentence opener is an AI tell. Start with the subject."
level: warning
scope: sentence
raw:
  - '^(?:Additionally|Notably|Ultimately|Seamlessly|Significantly|Furthermore|Moreover)\b'
```

`Shirabe/FillerPhrases.yml` (rows 6, 7, 8):

```yaml
extends: existence
message: "'%s' is filler. State the point directly."
level: error
ignorecase: true
raw:
  - "it(?:'s| is) (?:worth noting|important to note|worth mentioning)"
  - "in today(?:'s| ?s) [a-z-]+ (?:landscape|world|environment|era)"
  - "let(?:'s| us) (?:delve|dive) into"
  - 'at its core'
  - 'in (?:conclusion|summary)'
  - 'as (?:previously|already) mentioned'
```

`Shirabe/ChatbotArtifacts.yml` (rows 9, 10):

```yaml
extends: existence
message: "'%s' is a chatbot artifact. Delete it."
level: error
ignorecase: true
raw:
  - 'I hope this helps'
  - 'Great question[!.]'
  - '^(?:Absolutely|Certainly|Of course|Sure)[!,]'
  - 'as of my (?:training|(?:knowledge )?cutoff)'
```

`Shirabe/VagueValue.yml` (row 12):

```yaml
extends: existence
message: "'%s' says nothing. Name what it shows."
level: error
ignorecase: true
raw:
  - '(?:provides?|offers?|gives?) (?:valuable |useful |key |important )?insights? into'
```

`Shirabe/OverFormality.yml` (rows 25–30 — keep even with `Microsoft.Wordiness`
on, because Microsoft misses "with respect to" and swaps "at this point in time"
to "at this point" rather than "now"):

```yaml
extends: substitution
message: "Use '%s' instead of '%s'."
level: warning
ignorecase: true
nonword: false
swap:
  'in order to':          to
  'due to the fact that': because
  'at this point in time': now
  'prior to':             before
  'subsequent to':        after
  'with respect to':      'about'
  'has the ability to':   can
  'have the ability to':  can
```

`Shirabe/HeadingCase.yml` (row 22 — mechanically trivial, politically loaded; see §5):

```yaml
extends: capitalization
message: "'%s' should use sentence case."
level: suggestion
scope: heading
match: $sentence
threshold: 0.8
prefix: '^(?:\d+(?:\.\d+)*\s+|(?:BRIEF|PRD|DESIGN|PLAN|ROADMAP|STRATEGY|VISION|DECISION|COMP|SPIKE|ADR):\s+)'
exceptions:
  - Vale
  - CLI
  - GitHub
  - JSON
  - YAML
  - Markdown
  - Tengo
  - I
```

#### Class B — the rules that carry the value

`Shirabe/WordsOrganizing.yml` (row 1). Note what the exceptions cost:

```yaml
extends: existence
message: "'%s' is banned by the writing-style rulebook."
level: warning
ignorecase: true
tokens:
  - comprehensive
  - holistic
  - crucial
  - pivotal
  - paramount
  - tiered?
  - robust
exceptions:
  - robust against
  - robust to
```

`Shirabe/WordsVerbs.yml` (row 2). The split into two token groups is the
false-positive mitigation — the second group only fires in figurative
constructions:

```yaml
extends: existence
message: "'%s' is banned by the writing-style rulebook."
level: warning
ignorecase: true
tokens:
  - leverag(?:e|es|ed|ing)
  - utiliz(?:e|es|ed|ing)
  - facilitat(?:e|es|ed|ing)
  - delv(?:e|es|ed|ing)
  - foster(?:s|ed|ing)?
  - showcas(?:e|es|ed|ing)
  - grappl(?:e|es|ed|ing)
  - transcend(?:s|ed|ing)?
  - elucidat(?:e|es|ed|ing)
  - garner(?:s|ed|ing)?
  - align(?:s|ed|ing)? with
```

```yaml
# Shirabe/WordsVerbsFigurative.yml — lower level, these have literal senses
extends: existence
message: "'%s' — check this isn't the figurative AI-tell sense."
level: suggestion
ignorecase: true
raw:
  - '\bunderscor(?:e|es|ed|ing)\s+(?:the|its|their|how|why|that)\b'
  - '\bhighlight(?:s|ed|ing)?\s+(?:the|its|their|how|why|that)\b'
  - '\bnavigat(?:e|es|ed|ing)\s+(?:the|this|its)\s+(?:complexit|challeng|landscape|realm|nuance)'
  - '\benhanc(?:e|es|ed|ing)\b'
```

`Shirabe/ServesAs.yml` (row 13):

```yaml
extends: substitution
message: "Prefer '%s' over '%s'."
level: suggestion
ignorecase: true
swap:
  'serves as':  is
  'serve as':   are
  'stands as':  is
  'stand as':   are
  'boasts':     has
  'boast':      have
```

`Shirabe/NotJust.yml` (row 14):

```yaml
extends: existence
message: "'%s' — the 'not just X, it's Y' frame. Just say Y."
level: warning
ignorecase: true
scope: sentence
raw:
  - "(?:it(?:'s| is)|this is) not (?:just|merely|only) [^.,;]{2,60}[,;] (?:it(?:'s| is)|but)"
```

`Shirabe/StackedQualifiers.yml` (row 17):

```yaml
extends: existence
message: "'%s' stacks qualifiers. Keep one."
level: warning
ignorecase: true
raw:
  - '\b(?:could|can|may|might|would)\s+(?:potentially|possibly|perhaps|conceivably)\b'
  - '\b(?:potentially|possibly|perhaps)\s+(?:potentially|possibly|perhaps)\b'
  - '\bit(?:''s| is) (?:possible|likely) that .{0,30}\b(?:might|may|could)\b'
```

`Shirabe/HollowGerunds.yml` (row 18) — the leading comma is doing the precision work:

```yaml
extends: existence
message: "Hollow gerund '%s'. Cut it or make it the main clause."
level: warning
ignorecase: true
raw:
  - ',\s+(?:highlighting|underscoring|emphasizing|showcasing|demonstrating|reflecting|ensuring|allowing|enabling)\s'
```

`Shirabe/EmDashPerParagraph.yml` (row 20 — no scripting needed, and this is the
highest-yield rule in the whole set):

```yaml
extends: occurrence
message: "More than one em dash in this paragraph (%s). Use a comma, parentheses, or a colon."
level: warning
scope: paragraph
token: '—'
max: 1
```

`Shirabe/BoldPerParagraph.yml` (row 23):

```yaml
extends: occurrence
message: "%s bold runs in one paragraph. Bold genuine emphasis only."
level: suggestion
scope: paragraph
token: '\*\*[^*\n]+\*\*'
max: 2
```

`Shirabe/BareDemonstrative.yml` (row 33 — partial, but it does catch the real case):

```yaml
extends: existence
message: "'%s' — demonstrative with no antecedent noun. Name the thing."
level: suggestion
scope: sentence
raw:
  - '^(?:This|That|These|Those)\s+(?:is|are|was|were|means|provides|allows|ensures|makes|creates|gives|shows|helps)\b'
```

`Shirabe/SentenceLength.yml` (a `metric` rule, for row 24/35's neighbourhood —
this is what `metric` can actually do):

```yaml
extends: metric
message: "Mean sentence length is %s words. Break some up."
level: suggestion
formula: |
  words / sentences
condition: "> 26.0"
```

#### Class C — the `script` rules

These are spec-derived and **untested** (Vale is not installed, so no Tengo
interpreter was available). Treat the logic as sound and the syntax as unverified.
Note the Go-regex restriction inside scripts: no lookaround.

`styles/config/scripts/em-dash-density.tengo` (row 20, the length-normalized form):

```go
text := import("text")

matches := []

body := text.re_replace("(?s)```.*?```", scope, "")
words := len(text.fields(body))

found := text.re_find("—", body, -1)
dashes := 0
if !is_undefined(found) {
    dashes = len(found)
}

if words > 200 {
    per_k := float(dashes) * 1000.0 / float(words)
    if per_k > 4.0 {
        matches = append(matches, {begin: 0, end: 1})
    }
}
```

```yaml
# Shirabe/EmDashDensity.yml
extends: script
message: "This document exceeds 4 em dashes per 1000 words. Convert some to commas, parentheses, or colons."
level: warning
scope: raw
script: em-dash-density.tengo
```

`styles/config/scripts/burstiness.tengo` (row 35). Variance rather than standard
deviation, so it does not depend on `math` being available inside Vale's Tengo
sandbox — the docs only guarantee `text`:

```go
text := import("text")

matches := []

body := text.re_replace("(?s)```.*?```", scope, "")
body = text.re_replace("(?m)^[#>|*-]+.*$", body, "")
body = text.re_replace("([.!?])\\s+", body, "$1\n")

lens := []
for line in text.split(body, "\n") {
    n := len(text.fields(line))
    if n > 1 {
        lens = append(lens, n)
    }
}

if len(lens) >= 20 {
    sum := 0.0
    for l in lens { sum += float(l) }
    mean := sum / float(len(lens))

    ss := 0.0
    for l in lens {
        d := float(l) - mean
        ss += d * d
    }
    variance := ss / float(len(lens))

    // stdev < 9 words => uniform, unbursty prose. 81.0 == 9^2.
    if variance < 81.0 {
        matches = append(matches, {begin: 0, end: 1})
    }
}
```

```yaml
# Shirabe/Burstiness.yml
extends: script
message: "Sentence lengths are uniform. Human writing varies dramatically — put a 3-word sentence next to a 25-word one."
level: suggestion
scope: raw
script: burstiness.tengo
```

`styles/config/scripts/contraction-ratio.tengo` (row 21 — the honest way to do
"no contractions", since absence has no position to report):

```go
text := import("text")

matches := []

body := text.re_replace("(?s)```.*?```", scope, "")

count := func(pattern) {
    f := text.re_find(pattern, body, -1)
    if is_undefined(f) { return 0 }
    return len(f)
}

contracted := count("(?i)\\b[A-Za-z]+'(?:s|t|re|ve|ll|d|m)\\b")
uncontracted := count("(?i)\\b(?:do not|does not|did not|is not|are not|was not|were not|will not|would not|could not|should not|cannot|have not|has not|had not|it is|that is|there is|you are|we are|they are|we have|let us)\\b")

total := contracted + uncontracted
if total > 25 {
    ratio := float(uncontracted) / float(total)
    if ratio > 0.6 {
        matches = append(matches, {begin: 0, end: 1})
    }
}
```

```yaml
# Shirabe/Contractions.yml
extends: script
message: "This document avoids contractions. Use don't, it's, we've where they fit."
level: suggestion
scope: raw
script: contraction-ratio.tengo
```

An equivalent paragraph-uniformity script (row 24) is the same shape with
paragraph word counts instead of sentence word counts; I have not written it out
because the empirical case for it is weak (§4).

#### The vocabulary file — the part that makes the config survivable

`styles/config/vocabularies/Shirabe/accept.txt`:

```
[Tt]ier
[Tt]iers
[Tt]iered
[Jj]ourney
[Jj]ourneys
```

Without this, the config produces 259 alerts on shirabe's own docs that are all
correct usage of defined domain terms.

### 4. Empirical results on the real corpus

**Word rules.** All 47 banned words, word-boundary matched, over `docs/`
(397k prose words, 145 files):

| Word | Hits | Verdict on the hits |
|------|------|---------------------|
| tier/tiers/tiered | **147** | ~100% false positive. "Tier 1/2/3/4" is the defined complexity-routing vocabulary of `DESIGN-decision-framework.md` and `DESIGN-plan-review.md`. |
| journey/journeys | **112** | ~100% false positive. "User Journeys" is a *required section name* in the BRIEF and PRD templates. |
| robust | 7 | 3 are quotes of the rulebook itself; the rest are literal ("keeps the validator robust against prose input", "Maximally robust. **Rejected**"). ~0 true. |
| comprehensive | 4 | 3 are rulebook quotes. 1 true positive ("comprehensive about classification criteria"). |
| holistic | 3 | all 3 are rulebook quotes. 0 true. |
| leverage(s)/leveraging | 5 | 3 rulebook quotes, 2 the literal noun ("no leverage to nudge external systems"). 0 true. |
| facilitate(s) | 3 | all 3 rulebook quotes. 0 true. |
| underscore(s) | 2 | both about the `_` character in filenames. 0 true. |
| narrative | 4 | 2–3 borderline ("reads as a sequential build narrative"). |
| nuanced / resilience / landscape | 3 | 1 borderline, 2 domain ("competitive landscape", "resilience and lifecycle edges"). |
| everything else (37 words) | **0** | |

Total word-rule alerts on `docs/`: **290**. True positives by my read: **about 5**.
Raw precision ≈ **1.7%**. After the `accept.txt` vocab (tier, journey) and
excluding the one PRD that quotes the rulebook: 31 alerts, ~5 true, precision ≈16%.

**Phrase rules.** All 20 phrase and structural patterns over both trees:

| Pattern | docs hits | skills hits | True positives |
|---------|-----------|-------------|----------------|
| "worth noting" / "important to note" | 0 | 1 | 0 (the 1 is the rulebook) |
| "In today's" | 1 | 1 | 0 |
| "delve into", "At its core", "In conclusion", "In summary", "As previously mentioned", "I hope this helps", "Great question", "Absolutely!"…, "as of my training", "experts argue", "studies show", "valuable insights" | 0–1 each | exactly 1 each | **0** — every skills hit is `writing-style/SKILL.md` itself |
| "serves as"/"serve as" | 11 | 9 | ~3 of 11. Most are the literal predicate "label cannot serve as a table key". |
| "stands as"/"stand as" | 4 | 4 | **0 of 4**. All are "the invariants stand as ratified" — a fixed idiom. |
| "from X to Y" | 46 | 9 | **0 of 46**. All are state transitions: "from Accepted to Done", "from framing to a finished plan". |
| "in order to" | 1 | 2 | 1 |
| "with respect to" | 2 | 1 | 2 |
| adverb opener at line start | 1 | 0 | 1 |
| stacked qualifiers, hollow gerunds, "not just X it's Y" | 0 | 1–3 | 0 |

So: **the entire class-A phrase apparatus — 15 of the 16 class-A rules — would
produce roughly two true alerts across 554,000 words of real shirabe prose.**

**Em dashes. This is the finding.**

| Corpus | Em dashes | Per 1000 words | Files over 3/1000 |
|--------|-----------|----------------|-------------------|
| `docs/` (145 files, 397k words) | **3,114** | **7.84** | 104 of 145 (72%) |
| `skills/` (211 files, 157k words) | **1,188** | **7.59** | 76 of 211 |

Worst offenders: `PRD-shirabe-pattern-v1-ergonomics.md` at 28.5/1000 (118 em
dashes in 4,138 words), `DESIGN-work-on-definition-of-done.md` at 21.7,
`DESIGN-capstone-orchestration.md` at 18.5. Location breakdown: 2,974 in body
prose, only 27 in table cells and 126 in headings — so this is not a table
artifact, it's prose.

Under the `occurrence` rule above (`scope: paragraph, max: 1`), **679 of 5,776
paragraphs in `docs/` (11.8%)** and 227 of 3,378 in `skills/` (6.7%) would alert.
At `max: 2` it is 246 (4.3%) and 108 (3.2%). Those are actionable volumes, and
the underlying defect is real: 28.4% of `docs/` paragraphs contain at least one
em dash.

This rule is the entire empirical case for Vale. The model applying the skill by
judgment has not controlled em dash frequency at all, and it structurally cannot —
frequency is a document-level property invisible while composing one sentence.

**Title Case headings.** 162 of 2,838 headings in `docs/` (5.7%) and 585 of 2,832
in `skills/` (20.7%) are Title Case. But see §5 — most are template-mandated.

**Bold.** 10.9 bold runs per 1000 words in `docs/`, 12.9 in `skills/` — roughly
one bold run every 80 words. Real, but "genuine emphasis only" isn't decidable, so
this is a suggestion-level nudge at best.

**Contractions.** `docs/` has 4,396 contractions against 1,892 uncontracted forms
(ratio 0.30); `skills/` 1,477 vs 891 (0.38). The rulebook's rule is already
satisfied. Turning on `Microsoft.Contractions` as-is would produce **1,892
alerts** on `docs/`, nearly all of them wrong. This is why the ratio script is the
only defensible form.

**Burstiness.** `docs/`: 18,060 sentences, mean 22.5 words, stdev 17.5; 9.5% under
8 words, 32.0% over 25. `skills/`: mean 21.0, stdev 21.5; 14.7% under 8. The
corpus already has burstiness. Least-bursty files sit at stdev 7.6–8.2
(`DESIGN-skill-cascade-lifecycle-check.md`, `verification-map.md`) — a threshold
of 9 would flag maybe 5–8 files per tree. Low volume, but they're the right files.

### 5. Two conflicts between the rulebook and shirabe's own conventions

These matter more than any Vale mechanic, because they mean some rules cannot be
enforced without changing something else first.

**Title Case is mandated by shirabe's own templates.** `skills/design/references/
design-format.md:90` specifies "Every DESIGN has these nine sections in order",
and names them: **Context and Problem Statement**, **Decision Drivers**,
**Considered Options**, **Decision Outcome**, **Solution Architecture**,
**Implementation Approach**, **Security Considerations**, **Consequences**. All
Title Case. The writing-style rule says "Title Case Headings → Sentence case". The
validator enforces the section names. A sentence-case Vale rule would flag every
conformant DESIGN document — 5.7% of headings in `docs/` are exactly these
template names. (The same file describes a section as capturing "the technical
landscape", using a banned word in the template that governs the corpus.)

Vale can be told to ignore them (`exceptions`, or scoping to `~heading.h2`), but
that guts the rule: what's left is the free-text `###` headings inside sections.
This is a policy decision, not a configuration one.

**"tier" is a defined term.** R20 of `PRD-shirabe-pattern-v1-ergonomics.md`
(status: Done) requires mechanical detection of exactly `"robust", "leverage",
"comprehensive", "holistic", "facilitate", "tier", "tiered"` — and AC4.3 makes it
a checkbox. Taken literally, that requirement fires 147 times on shirabe's own
`docs/`, essentially all correct. The complexity-routing vocabulary in
`DESIGN-decision-framework.md` is built on Tier 1–4.

### 6. Divergence between the copies of the rulebook

There are three-and-a-half copies of these rules and they do not agree.

1. **`CLAUDE.md:76`** says "See `.claude/helpers/writing-style.md` for details."
   **That file does not exist.** The workspace root `.claude/` contains only
   `bin/`, `hooks/`, `rules/`, `settings.json`. The pointer is dangling. The same
   dangling line is duplicated verbatim at `public/dot-niwa/.niwa/claude/
   workspace.md:76`, so it will be regenerated on every `niwa apply`.
2. **`CLAUDE.md`'s quick reference** lists 5 words (tier, robust, leverage,
   comprehensive/holistic, facilitate) with substitutions that don't match the
   skill's — CLAUDE.md gives "robust → reliable, solid" where the skill gives no
   substitution at all.
3. **The plugin's older copy** (private repo, ~14 rules) bans two words the
   shirabe skill dropped: **"explore"** and **"insight"**. Shirabe ships an
   `/explore` skill and a `crystallize-framework.md` reference — banning "explore"
   is unworkable, which is presumably why it was dropped, but the older copy is
   still what ~12 `tsukumogami` skills load via `Read ../../helpers/
   writing-style.md`. It also carries three rules shirabe dropped entirely
   ("Numbered lists for everything", "Key takeaways sections", "Perfect grammar —
   don't over-polish") and lacks about 25 that shirabe added.
4. **The evals** quantify thresholds the SKILL.md leaves qualitative. `evals.json`
   asserts "at least one sentence under 8 words and one over 18 words" (eval 6) and
   "not all sentences within 5 words of each other" (eval 1). SKILL.md only says "a
   3-word sentence next to a 25-word sentence is the target". If you're going to
   set a Vale burstiness threshold, the evals are where the number should come
   from, and they disagree with the prose.

Adopting Vale would force these into one place, which is arguably a bigger win
than the linting.

### 7. How much comes free from off-the-shelf packages

Available packages: `Google`, `Microsoft`, `proselint`, `write-good`, `alex`,
`Joblint`, `Readability`, `RedHat`, `Hugo`.

| Shirabe rule | Free coverage |
|---|---|
| Over-formality (rows 25–30) | **`Microsoft.Wordiness` covers 5 of 6** — "in order to"→to, "(previous\|prior) to"→before, "subsequent to"→after, "due to the fact that"→because, "has the ability to"→can, plus "utilize"→use. Misses "with respect to"; swaps "at this point in time"→"at this point" not "now". |
| Title Case headings (row 22) | `Google.Headings` and `Microsoft.Headings` both do `capitalization/$sentence/scope: heading`. Drop-in — modulo §5. |
| No contractions (row 21) | `Microsoft.Contractions` detects the uncontracted form. Correct mechanism, wrong calibration for this corpus (1,892 alerts). |
| Stacked qualifiers (row 17) | `proselint.Hedging` and `write-good.Weasel` overlap partially. |
| Mean sentence length | `Microsoft.SentenceLength`, `Readability.*` (Flesch-Kincaid etc.). |
| **The 47 banned words** | **Essentially nothing.** proselint's 34 rules are Airlinese, Cliches, CorporateSpeak, Hedging, Jargon, Malapropisms, Needless, Nonwords, Oxymorons, RASSyndrome, Skunked, Uncomparables, Very… all authored 2014–2016, pre-LLM. "delve", "tapestry", "showcase", "underscore", "seamless", "groundbreaking", "robust" are not in any of them. |
| **Em dash overuse** | **Nothing.** No package ships an em-dash frequency rule. This is the highest-value rule and it must be written from scratch. |
| Burstiness, paragraph uniformity, cognitive tells | Nothing. |
| Rules you must actively **disable** | `proselint.But` / `Microsoft.We` / `Microsoft.FirstPerson` / `Microsoft.Passive` / `Microsoft.Adverbs` all fight row 36 ("'And', 'But', 'Or' as sentence starters are fine") and shirabe's direct-voice preference. |

Free coverage is roughly **6 of 38 rules**, all of them class A, all of them
already satisfied by the corpus. The packages buy almost nothing here.

## Implications

**The A/B-vs-C/D ratio is 66/34 by rule count and that number is misleading.**
Weighted by defects actually present in shirabe's prose, the picture is: one rule
(em dash density) accounts for most of the realizable value, three or four more
(bold density, the word lists behind a vocab file, heading case, burstiness) round
it out, and the other thirty-odd would run green forever. A Vale adoption
justified as "mechanize the rulebook" will disappoint. A Vale adoption justified
as "measure the four document-level frequency properties the model cannot see
while writing" is well-founded — and those are precisely the rules that need
custom `occurrence` and `script` work rather than off-the-shelf packages.

**The division of labour falls out cleanly.** Vale is good at what the model is
structurally bad at: counting things across a whole document. The model is good at
what Vale is structurally bad at: word sense, antecedents, whether three is the
real count, whether a sentence carries information. There is almost no overlap in
the middle. That argues for a narrow, high-signal Vale config (roughly 8–10 rules,
not 22) sitting alongside the skill rather than replacing any part of it.

**Adoption has a pre-existing hook.** R20/AC4.3 of `PRD-shirabe-pattern-v1-
ergonomics.md` (status: Done) already requires "mechanical writing-style banned-word
detection" and explicitly leaves the mechanism — "validator notice, Phase 4
reviewer, pre-commit hook" — as DESIGN territory. Vale is a fourth candidate for
that slot, and a strong one. But the seven words R20 names are the *worst* seven to
start with: two of them (tier, tiered) are defined domain vocabulary appearing 147
times, and the remaining five produce roughly one true positive across the corpus.
If Vale is adopted to satisfy R20 as literally written, it will fail on first run.

**Two prerequisites are not Vale's problem.** The Title Case rule cannot be
enforced until the DESIGN/BRIEF/PRD templates and the writing-style rulebook are
reconciled — right now they contradict each other outright. And the rulebook needs
to become one artifact: the `CLAUDE.md` pointer is dangling, `dot-niwa` will keep
regenerating it dangling, and a divergent older copy still governs about twelve
plugin skills.

**Self-exemption is mandatory, not optional.** Any file that discusses the rules
trips them. `skills/writing-style/SKILL.md` hits on nearly every token in the book;
`PRD-shirabe-pattern-v1-ergonomics.md` accounts for most of the docs-level word
hits. That's a `.vale.ini` block plus `<!-- vale off -->` discipline, and it needs
to be in the design from the start or the first run looks catastrophic.

## Surprises

**The corpus is already clean on almost everything the rulebook is specific
about.** I expected the phrase rules to be the free win. Instead: zero true hits
for "worth noting", "delve into", "In conclusion", "Great question", "valuable
insights", "as of my training", and a dozen more across 554,000 words. The only
hits are the rulebook quoting itself. Model judgment is genuinely working on the
lexical layer, which removes most of the stated motivation for a lexical linter.

**Em dashes are running at 7.8 per 1000 words with 72% of documents over any
sane budget.** I did not expect the gap between the lexical rules (obeyed) and the
frequency rules (completely unobeyed) to be this stark. The rulebook lists "em dash
overuse" as one formatting tell among five; empirically it is the dominant defect
in the corpus by an order of magnitude.

**"from X to Y" is unusable — 0 true positives in 55 hits**, all of them state
transitions ("from Accepted to Done"). Likewise "stands as": 0 of 8, all the fixed
idiom "the invariants stand as ratified". These are rules that read sensibly in
prose and collapse entirely on contact with a real technical corpus.

**Vale's `metric` extension point cannot count punctuation.** Its variable list is
words/sentences/syllables/paragraphs/complex_words/long_words/headings — readability
inputs only. So the obvious "em dashes per 1000 words" rule is *not* a metric rule;
it needs Tengo. I expected metric to be the answer to the whole frequency class and
it is the answer to almost none of it.

**shirabe's own DESIGN template mandates the Title Case its writing-style skill
bans**, and describes a section as covering "the technical landscape" — a banned
word — in the same file. The rulebook and the templates were written independently
and never reconciled.

**The `.claude/helpers/writing-style.md` path in CLAUDE.md points at nothing**, and
is regenerated from `dot-niwa`, so it will stay broken until fixed upstream.

## Open Questions

1. **Does the Title Case rule survive at all?** Either the DESIGN/BRIEF/PRD
   templates move to sentence case (touching the validator and every existing doc),
   or the writing-style rule gets scoped to "headings you invent, not headings the
   template names". Author decision, blocking for row 22.
2. **Is "tier" actually banned?** R20 says yes; `DESIGN-decision-framework.md` uses
   Tier 1–4 as its complexity vocabulary 147 times. Either the term gets an
   explicit carve-out in the rulebook or the framework gets renamed. Blocking for
   R20/AC4.3.
3. **What em dash budget?** I used 4/1000 words for the density script and max 1
   per paragraph for the occurrence rule. Both are my numbers, not shirabe's. At
   max 1/paragraph, 11.8% of existing paragraphs alert — is that a useful signal or
   an unbearable one? Needs a human calibration pass, ideally on one recently
   authored DESIGN.
4. **Does Vale's Tengo sandbox expose `math`?** The docs only guarantee the `text`
   module. I wrote the burstiness script variance-based to avoid `math.sqrt`, but
   this is unverified. Someone should install Vale and run the three scripts before
   any design commits to `script` rules.
5. **Where does Vale run?** Pre-commit hook, CI, or invoked mid-skill at drafting
   time changes the calibration completely — a blocking CI check needs precision
   near 100% (so: em dash occurrence and the phrase rules only), while an advisory
   nudge inside `/design` Phase 6 can tolerate the suggestion-level word rules.
   This is the real decision and my findings don't settle it.
6. **Is the rulebook consolidated first?** Adopting Vale against three divergent
   copies bakes in whichever copy the config is written from. The
   dangling-pointer fix and the plugin-copy reconciliation look like prerequisites,
   not follow-ups.

## Summary

Sixty-six percent of shirabe's 38 writing-style rules translate into runnable Vale
YAML (42% class A, 24% class B), but weighted by defects actually present in
554,000 words of shirabe prose the ratio inverts: the class-A lexical rules produce
about two true alerts across the entire corpus because model judgment is already
enforcing them, while one class-B rule — em dash frequency, running at 7.8 per 1000
words with 72% of documents over budget and 3,114 instances in `docs/` alone —
carries most of the realizable value, and no off-the-shelf package ships it. The
implication is that Vale earns its keep only as a narrow document-level frequency
checker (em dashes, bold density, burstiness, heading case) rather than as a
mechanization of the rulebook, and adopting it exposes two unreconciled conflicts
first: shirabe's DESIGN template mandates the Title Case the rulebook bans, and
R20/AC4.3 bans "tier" while the decision framework uses Tier 1–4 as defined
vocabulary 147 times. The biggest open question is where Vale runs — a blocking CI
gate and an advisory nudge inside `/design` Phase 6 need opposite calibrations, and
nothing in this audit settles which one the workspace wants.
