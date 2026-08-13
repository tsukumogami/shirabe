# Lead: What is Vale actually good at, and what can it fundamentally not check?

Research round 1. Every claim below is grounded in Vale's documentation corpus
(`https://docs.vale.sh/llms-full.txt`, fetched 2026-08-13), Vale's Go source on
`github.com/vale-cli/vale`, or the published style packages downloaded and read
directly. Where I could not verify something by running it, I say so.

**Vale is not installed on this machine.** `which vale` returns nothing. I did
not install it, per instructions. That means no claim here rests on observed
Vale behavior. To compensate I read source rather than prose wherever the answer
mattered, and I reproduced one regex outside Vale to confirm its match set (see
"The passive-voice illusion"). Anything that needs a real run to settle is
listed under Open Questions.

Version context: latest release is **v3.17.1**, published 2026-08-05. The
project moved from `jdkato/vale` to the `vale-cli` org; the Go module path is
still `github.com/errata-ai/vale/v2`. 5.9k stars, actively maintained, MIT.

## Findings

### 1. The extension points: twelve, and eleven of them are regex

Vale's `Styles` page lists eleven checks; the `readability` check is documented
on its own page and the MCP page says "twelve check types," so twelve is the
real number. From `docs.vale.sh/topics/styles`:

| Check | What it does |
|---|---|
| `existence` | "Check for the presence of a specific regex pattern." |
| `substitution` | "Replace a regex pattern with a specific string." |
| `occurrence` | "Ensure the presence of a regex pattern a specific number of times." |
| `repetition` | "Avoid repeating a regex pattern a specific number of times." |
| `consistency` | "Ensure that a regex pattern is used consistently." |
| `conditional` | "Check for the presence of a regex pattern based on a condition." |
| `capitalization` | "Ensure that a regex pattern is capitalized in a specific way." |
| `metric` | "Check the readability (or other metrics) of your content using custom formulas." |
| `spelling` | "Spell check using Hunspell-compatible dictionaries." |
| `sequence` | "Ensure that a regex pattern is used in a specific order. Supports part-of-speech tagging." |
| `script` | "Run a custom Tengo script to check your content." |
| `readability` | Grade-level scoring; the one check that accepts no scope. |

Read the descriptions again and notice what they have in common. Nine of the
twelve say "regex pattern" outright. `spelling` is dictionary lookup.
`readability`/`metric` are arithmetic over counts. `sequence` is the sole check
that consults a language model of any kind, and `script` is a sandboxed
interpreter over the same raw text.

Shared header fields, verbatim from the same page:

| Name | Required | Default | Notes |
|---|---|---|---|
| `extends` | Yes | — | which check to extend |
| `message` | Yes | — | `%s` interpolates the match |
| `level` | No | `suggestion` | `suggestion`, `warning`, `error` |
| `scope` | No | `text` | see scoping below |
| `link` | No | — | reference URL |
| `limit` | No | — | max triggers per file |
| `vocab` | No | `true` | honor active vocabularies |

A representative rule, from the Microsoft style, showing the shape:

```yaml
# An example rule from the "Microsoft" style.
extends: existence
message: "Don't use end punctuation in headings."
link: https://docs.microsoft.com/en-us/style-guide/punctuation/periods
nonword: true
level: warning
scope: heading
action:
  name: edit
  params:
    - remove
    - '.?!'
tokens:
  - '[a-z0-9][.?!](?:\s|$)'
```

`tokens` is sugar: the list compiles to a word-bounded non-capturing group. The
docs give the expansion explicitly — `tokens: [appears to be, arguably]` becomes
`(?i)(?m)\b(?:appears to be|arguably)\b`. `raw` skips the sugar for full regex
control. The engine is `errata-ai/regexp2`, a fork giving lookahead and
lookbehind on top of Go's RE2 — so unlike stock Go regex, `(?<=import )` works.
One caveat the docs flag: `script`-based rules are "limited to the standard Go
regex syntax," meaning no lookarounds inside Tengo.

`substitution` is the highest-leverage check for a banned-words list, because it
carries the fix, not just the complaint:

```yaml
extends: substitution
message: Consider using '%s' instead of '%s'
level: warning
ignorecase: false
# swap maps tokens in form of bad: good
swap:
  abundance: plenty
  accelerate: speed up
```

Keys may be regexes with capture-group references (`'within the (.*)?directory': in the $1 directory`),
and a `|`-separated value offers several alternatives, which surface as LSP
Quick Fixes.

### 2. Markup awareness is Vale's genuinely strong suit

This is the part that earns the tool its reputation, and it holds up.

Vale classifies files as `markup`, `code`, or `text`. For markup it converts to
HTML and scopes every block. **By default, in Markdown, Vale ignores** (verbatim
from `docs.vale.sh/formats/markdown`):

- Indented blocks: Blocks starting with four or more spaces.
- Fenced blocks: Blocks surrounded by three or more backticks.
- Code spans: Text surrounded by backticks.
- Math: `$$…$$` blocks and `$x^2$` spans.
- URLs.

So fenced code and inline code are free — no configuration needed. That matters
a lot for skill files and agent instructions, which are dense with both.

Available markup scopes: `heading` (with `heading.h1` etc.), `table.header`,
`table.cell`, `table.caption`, `figure.caption`, `list`, `paragraph`,
`sentence`, `blockquote`, `alt`, `summary`, `raw`. As of v3.17.0 there are also
inline scopes — `link`, `code`, `strong`, `emphasis` — and class scopes
(`text.class.note`).

Selector semantics are worth internalizing because they are not what you'd
guess. A selector matches when **all its parts appear in the scope**; it is
neither prefix nor exact matching, and order is irrelevant. The docs' own table:

| Selector | Matches `text.list.md`? |
|---|---|
| `list` | Yes |
| `list.md` | Yes |
| `md.list` | Yes—order is irrelevant |
| `text.list` | Yes |
| `list.text.md` | Yes |
| `heading` | No—not one of its parts |

Consequence the docs call out: "a selector with fewer parts is broader: `text`
matches nearly everything." And arrays are OR, `&` is AND, `~` negates:

```yaml
scope:
  # (a heading that isn't an h1) OR (a list item in Markdown)
  - heading & ~heading.h1
  - list.md
```

**Frontmatter is scoped per field**, which is more useful than I expected.
YAML (`---`), TOML (`+++`), and JSON (`;;;`) are all recognized, and given

```yaml
---
title: 'My document'
description: "A short summary of the document's purpose."
---
```

"the generated scopes would be `text.frontmatter.title`,
`text.frontmatter.description`". A rule can target one field:

```yaml
extends: capitalization
message: "'%s' should be in title case"
level: warning
scope: text.frontmatter.title
```

For shirabe this is directly relevant: every SKILL.md has a `name` and
`description` in frontmatter, and `description` is the field whose quality
determines whether the skill triggers. `scope: text.frontmatter.description` is
a real, precise handle on it.

**The ignore keys**, and a trap in each:

- `IgnoredScopes` — inline tags whose content is skipped. Defaults to `tt`,
  `code`, `kbd`. Setting it **replaces** the defaults.
- `SkippedScopes` — block tags skipped entirely. Defaults to `script`, `style`,
  `pre`, `figure`, `noscript`, `iframe`. Also **replaces**.
- `IgnoredClasses` — defaults `problematic`, `pre`, `code`, and uniquely this
  one **adds** to the defaults rather than replacing.
- `BlockIgnores` / `TokenIgnores` — regex escape hatches for constructs with no
  HTML tag. "The idea is to write a regular expression that captures the entire
  block in the first grouping."

```ini
[*.md]
BasedOnStyles = Vale
BlockIgnores = (?s) *({< file [^>]* >}.*?{</ ?file >})
```

Both work by wrapping matches in the format's code delimiter, so they need a
markup format and are inert in a source file unless you map the format
(`[formats]` / `cc = md`).

A second trap that bit me while reading: `BasedOnStyles` **replaces** across
sections rather than accumulating, but individual rule toggles **accumulate**.

```ini
[*]
BasedOnStyles = Vale

[*.md]
# Markdown files get Microsoft *instead of* Vale, not as well as.
BasedOnStyles = Microsoft
```

And `scope: raw` disables all of this. The FAQ is blunt: "`raw` gives a rule the
unprocessed file contents, which means no scope-related feature applies to it."
Raw rules fire inside code blocks, and cannot be silenced by `<!-- vale off -->`
comments, "because comment processing happens after a document is converted to
HTML, and `raw` rules don't run on the converted document." Any rule needing
markup syntax (em-dash counting in source, bold-marker counting, alt-text
presence) pays this price.

Per-file and per-passage suppression exists and is good:

```markdown
<!-- vale off -->
This text will be ignored.
<!-- vale on -->

<!-- vale Style.Redundancy = NO -->
<!-- vale Style.Redundancy["ACT test","OTHER"] = NO -->
```

### 3. Style packages: what actually ships

`vale sync` downloads packages named in `Packages` into `StylesPath`.
`Packages` accepts four value types: an Explorer name, a URL, a local `.zip`
path, or a local directory. Naming a package gets its latest release, so the
docs recommend pinning by release URL where drift matters:

```ini
Packages = https://github.com/vale-cli/Google/releases/download/v0.7.0/Google.zip
```

I downloaded and counted the rules in the six best-known packages. **This is the
single most decision-relevant table in this report:**

| Package | Rules | `existence` | `substitution` | `metric` | other | `sequence` | `script` |
|---|---|---|---|---|---|---|---|
| Microsoft | 47 | \[combined below\] | | | | 0 | 0 |
| Google | 36 | 29 | 5 | 0 | 2 | 0 | 0 |
| proselint | 33 | \[combined below\] | | | | 0 | 0 |
| alex | 11 | 4 | 7 | 0 | 0 | 0 | 0 |
| write-good | 9 | \[combined below\] | | | | 0 | 0 |
| Readability | 7 | 0 | 0 | 7 | 0 | 0 | 0 |

Combined tally across write-good + proselint + Microsoft (89 rules): 66
`existence`, 18 `substitution`, and one each of `repetition`, `occurrence`,
`consistency`, `conditional`, `capitalization`.

**Across all 143 rules in the six flagship packages, `sequence` is used zero
times and `script` is used zero times.** The two checks that could do more than
pattern-match are used by none of the styles anyone actually installs. Vale's
production surface is a regex engine with a very good Markdown parser in front
of it.

What each package enforces, concretely:

- **write-good** (9 rules): `Cliches`, `E-Prime`, `Illusions`, `Passive`, `So`,
  `ThereIs`, `TooWordy`, `Weasel`. Word lists. `ThereIs` is one regex:
  `'(?:[;-]\s)There\s(is|are)|\bThere\s(is|are)\b'`.
- **proselint** (33 rules): `Airlinese`, `Annotations`, `Apologizing`,
  `Archaisms`, `Cliches`, `CorporateSpeak`, `Hedging`, `Hyperbole`, `Jargon`,
  `Nonwords`, `Oxymorons`, `RASSyndrome`, `Very`, and more. `Hedging` is three
  tokens total: `I would argue that`, `', so to speak'`, `to a certain degree`.
  `Annotations` flags `XXX`, `FIXME`, `TODO`, `NOTE` left in text.
- **Microsoft** (47 rules): the most complete. `Contractions`, `Passive`,
  `Wordiness`, `HeadingPunctuation`, `Headings`, `OxfordComma`,
  `SentenceLength`, `FirstPerson`, `We`, `Adverbs`, `Dashes`, `Ellipses`,
  `ExclamationPoints`, `Quotes`, `Terms`, plus bias-free-language rules.
- **Google** (36 rules): similar territory, lighter.
- **alex** (11 rules): inclusive-language substitutions, mostly with `action:
  name: replace` so the fix is offered.
- **Readability** (7 rules): pure `metric` formulas — Flesch-Kincaid,
  Gunning Fog, Coleman-Liau, SMOG, LIX, ARI, Flesch Reading Ease.

`Joblint` was in the brief; I did not find it under the `vale-cli` org. It may
be a community package on the Explorer or may have been retired. Unverified.

### 4. Output surface: good enough for an agent, with one sharp edge

Three built-in formats via `--output`: `CLI` (default, aligned for a terminal),
`line`, and `JSON`. Custom formats are Go `text/template` files in
`<StylesPath>/config/templates`, with `Sprig` functions available — the docs
include a worked RDJSONL template for Reviewdog.

Vale's own AGENTS.md is unambiguous about which to use: "Use `--output=JSON`
when you intend to parse the result. The default `CLI` output is aligned for a
terminal and is not stable to scrape." And `--output=line` gives one
`path:line:col:rule:message` per alert.

The JSON alert shape, from `internal/core/alert.go` (authoritative):

```go
type Alert struct {
	Action      Action   // a possible solution
	Span        []int    // the [begin, end] location within a line
	Offset      []string `json:"-"` // tokens to ignore before this match
	Check       string   // the name of the check
	Description string   // why `Message` is meaningful
	Link        string   // reference material
	Message     string   // the output message
	Severity    string   // 'suggestion', 'warning', or 'error'
	Match       string   // the actual matched text
	Line        int      // the source line
	Limit       int      `json:"-"` // the max times to report
	Hide        bool     `json:"-"` // should we hide this alert?
}
```

So a consumer gets `Check` (the `Style.Rule` name), `Severity`, `Message`,
`Match`, `Line`, `Span`, `Link`, `Description`, `Action`. That is a clean,
sufficient payload — rule identity plus exact location plus the offending text.
Good for an agent.

Exit codes:

| Code | Meaning |
|---|---|
| `0` | No errors found |
| `1` | Linting errors found |
| `2` | Runtime error |

**The sharp edge:** only `error`-level alerts produce a non-zero exit code.
Warnings and suggestions exit 0. AGENTS.md states it in bold and then warns:
"A CI job that 'passes' may still have reported a hundred alerts, so check the
output rather than the exit status unless the project has deliberately set
everything it cares about to `error`." Since `level` defaults to `suggestion`
and most shipped package rules are `suggestion` or `warning`, **a naive
integration that gates on exit status will pass essentially everything.** Any
adoption here must either parse JSON or deliberately promote rules to `error`.

Severity is overridable per rule or per style from `.vale.ini`, without editing
the style:

```ini
[*.md]
BasedOnStyles = proselint

# Everything in proselint is a suggestion ...
proselint = suggestion
# ... except this one.
proselint.Typography = warning
```

`--minAlertLevel` filters display, and `--no-exit` suppresses the failure code.
For reproducibility AGENTS.md recommends `--no-global` (ignore the machine's
own config) and explicit `--config=<path>`.

Also relevant to agent use: `--ext=.md` assigns a file type to stdin, and
`--path=docs/draft.md` associates a path with stdin so config sections and
format detection apply. So a skill can lint an in-memory draft before writing
it to disk. That is a real capability for the "invoke at drafting time" option.

### 5. The hard boundary — what Vale cannot detect

This is the most important section and I want to be blunt.

**The architectural fact.** A Vale rule is a pure function from one block of
text to a list of character spans. It cannot read another file, cannot call a
service, cannot maintain state across a document, cannot ask anything. This is
not a gap in the rule library — it is enforced in the source. The `script`
check, the most permissive escape hatch Vale offers, sandboxes Tengo like this
(`internal/check/script.go`):

```go
// TODO: Should we enable the `os` module? Is it worth the security
// implications?
//
// See #495, for example.
script.SetImports(stdlib.GetModuleMap("text", "fmt", "math"))
```

Three modules: `text`, `fmt`, `math`. No `os`, no network, no subprocess. The
maintainers considered `os` and explicitly declined. **There is no path by which
a Vale rule calls an LLM, shells out, or consults anything outside the block of
text it was handed.** Any hope of "we could write a Tengo rule that asks a model
whether this paragraph says anything" is closed at the source level.

Given that, here is what Vale cannot check, concretely, mapped against
shirabe's actual `writing-style` skill (`skills/writing-style/SKILL.md`, 73
lines). I went through it section by section:

| Skill section | Mechanizable in Vale? | How, or why not |
|---|---|---|
| **Avoid: words** (~50 words in 5 categories) | **Yes, fully** | One `existence` rule per category, or one `substitution` map where a replacement exists. This is the canonical use case. |
| **Avoid: phrases** (8 items) | **Mostly** | "It's worth noting", "In conclusion", "Great question!", "As of my training" are literal strings — trivial `existence`. But "experts argue / studies show *without citation*" needs the citation check, which Vale cannot do. |
| **Avoid: structural patterns** (7 items) | **Partial** | "serves as / stands as / boasts" yes. "It's not just X, it's Y" yes via regex. Stacked qualifiers yes-ish. Hollow gerunds yes as detection. **Synonym cycling — no** (needs cross-document semantic similarity). **"from X to Y" on no real scale — no** (needs judgment about whether a scale exists). **Forced rule of three — no** (needs to know the true count differs from three). |
| **Avoid: formatting tells** (5 items) | **Mostly yes, and this is Vale's sweet spot** | Em-dash overuse → `occurrence`, `scope: paragraph`, `max: N`. Title Case Headings → `capitalization`, `scope: heading`, `match: $sentence` — an excellent fit. No contractions → `substitution` (Microsoft.Contractions already ships this). Boldface overuse → `occurrence` on `raw`. **Uniform paragraph length — not with a built-in check**, but see below. |
| **Over-formality substitutions** (6 pairs) | **Yes, fully** | Textbook `substitution` swap map with `action: name: replace`, so the fix is offered, not just the complaint. Microsoft.Wordiness already covers several. |
| **Cognitive tells** (4 items) | **No. None of them.** | See below. |
| **What human writing has** (4 items) | **Almost entirely no** | Burstiness is the one exception (below). |

**The four cognitive tells, individually, and why each is out of reach:**

1. *"Low information density: well-formed sentences that say nothing."* This is
   a judgment about the relationship between a sentence and the world. Vale sees
   a character span. There is no regex for vacuity, and no counting formula
   approximates it — a dense sentence and an empty one can have identical word,
   syllable, and sentence counts. Readability scores measure the *opposite*
   thing: they reward short words and short sentences, so a paragraph of
   confident, empty, monosyllabic filler scores *better* than a precise
   technical one. Using readability as a proxy for information density would
   invert the signal.

2. *"Empty conclusions: adds no content."* Requires comparing a paragraph's
   propositional content against everything preceding it. Vale rules are
   block-scoped and stateless; `conditional` is the only check that relates two
   patterns, and it relates *literal patterns within one scope*, not meanings
   across a document.

3. *"'this/that/these' without antecedent."* This is coreference resolution.
   Vale has a POS tagger (see below) but no parser, no dependency tree, and no
   coreference model. You could heuristically flag sentence-initial "This " —
   and you would flag correct usages at a rate that makes the rule worthless.

4. *"Vague attribution without citation."* Detecting "studies show" is trivial;
   determining whether a citation is present, nearby, and *actually supports the
   claim* is not. Vale can flag the phrase and force a human to look. That is a
   real but much smaller service than the skill asks for.

**Beyond the skill, the general list of what Vale cannot do:**

- Judge whether a sentence is *true*, *supported*, or *relevant*.
- Detect a claim that contradicts an earlier claim.
- Detect that a document's structure doesn't match its stated purpose.
- Resolve pronouns, detect misplaced modifiers, or check subject-verb
  agreement across a clause boundary. (Corroborated by third-party writeups:
  Vale "won't catch subject-verb disagreement or misplaced modifiers.")
- Understand that "the system processes the request" and "the request is
  processed by the system" mean the same thing while only one is passive — it
  will flag both or neither depending on the regex.
- Check anything requiring knowledge of the codebase, the issue, or the reader.
- Lint a URL inside a link. The FAQ says so directly: "Can Vale lint the URL
  inside a link? **No.**"
- Validate its own rules' `link:` fields (that requires the paid MCP server's
  `check_links`).

**The one genuine surprise in the other direction: burstiness is computable.**
Sentence-length variance is arithmetic, and Tengo has `text` and `math`. A
`script` rule with `scope: raw` could split on sentence boundaries, compute the
standard deviation of sentence lengths, and flag a document whose prose is
suspiciously uniform. Nothing in Vale ships this, and I have not written or
tested it, but nothing in the sandbox prevents it. Of every item in the
`writing-style` skill, "burstiness: dramatic variation" is the one that looks
un-mechanizable and is not. Worth a spike.

### 6. Does Vale do real NLP? Barely, and the styles don't use it

Vale depends on `github.com/jdkato/prose v1.2.1` (confirmed in `go.mod` —
note **v1**, not the v2 rewrite). Prose provides tokenization, Penn Treebank POS
tagging, named-entity extraction, and Punkt sentence segmentation. The prose
README gives one performance figure: roughly 1.4 s per million words.

Only `sequence` consumes the tagger. Its tokens carry NLP metadata:

```yaml
extends: sequence
message: |
  The infinitive '%[4]s' after 'be' requires 'to'.
  Did you mean '%[2]s %[3]s *to* %[4]s'?"
tokens:
  - tag: MD
  - pattern: be
  - tag: JJ
  # The `|` notation means that we'll accept `VB`
  # or `VBN` in position 4.
  - tag: VB|VBN
```

Each `NLPToken` supports `pattern`, `tag` (Penn), `upos` (universal), `negate`,
`skip: n` (allow up to n intervening tokens), and `target` (narrow the alert to
one slot). Every sequence rule needs at least one literal `pattern` as an
anchor: "we find all instances of the first pattern and then check that the
left- and right-hand sides of the sequence match." So it is anchored pattern
matching with POS constraints — not parsing. There is no dependency tree, no
constituency parse, no coreference.

Sentence segmentation is genuinely useful and is what makes `scope: sentence`,
`occurrence` per sentence, and the readability formulas work at all.

**The passive-voice illusion.** This is the clearest illustration of the gap
between Vale's reputation and its mechanism, so I checked it carefully.
`sequence` with POS tags is exactly the tool for passive voice: a form of *be*
followed by a token tagged `VBN`. Both write-good and Microsoft ship a
`Passive.yml`. **Neither uses `sequence`.** Both are byte-for-byte the same
approach — `extends: existence`, with:

```yaml
extends: existence
message: "'%s' may be passive voice. Use active voice if you can."
ignorecase: true
level: warning
raw:
  - \b(am|are|were|being|is|been|was|be)\b\s*
tokens:
  - '[\w]+ed'
  - awoken
  - beat
  - become
  # ... ~150 more irregular past participles
```

A *be*-verb followed by `[\w]+ed` or a hardcoded participle list. Since I could
not run Vale, I reproduced the compiled pattern in Python to see its match set:

```
FLAG  'The file is red.'                        -> 'is red'
FLAG  'She was tired.'                          -> 'was tired'
FLAG  'They are excited.'                       -> 'are excited'
FLAG  'I am interested in this.'                -> 'am interested'
FLAG  'The bug was fixed by the team.'          -> 'was fixed'
FLAG  'The result is embedded in the output.'   -> 'is embedded'
FLAG  'He is bored.'                            -> 'is bored'
FLAG  'The doc was updated.'                    -> 'was updated'
```

Six of those eight are **adjectival predicates, not passive voice**. "is red"
matches because `[\w]+ed` accepts `r` + `ed`. Only "was fixed by the team" and
arguably "was updated" are passives. A POS tagger would separate these; the
regex cannot, and the shipped rule does not try.

The honest summary: **Vale embeds a POS tagger, exposes it through exactly one
check, and not one of the 143 rules in the six flagship style packages uses it.**
Treat "Vale does NLP" as false for any off-the-shelf configuration. It is true
only for rules you write yourself, and writing correct `sequence` rules is hard
enough that the paid MCP server sells `trace_rule` as a headline feature for
debugging why they silently never fire.

### 7. Performance: fast, offline, and not the constraint

I could not benchmark without installing, so this is inference from source and
docs rather than measurement — flagged accordingly.

- **Single static Go binary.** No runtime, no dependency tree. Startup is
  process spawn plus config parse plus rule compilation.
- **Concurrent per file.** `internal/lint/lint.go` spawns a goroutine per file
  ("creating a new goroutine to lint any" file under the walked root). A few
  hundred Markdown files should be seconds, not minutes.
- **No network at runtime.** Network is needed only by `vale sync`, which
  downloads packages once into `StylesPath`. Linting is fully offline. This
  matters for an edit-time hook.
- **Compile cost is the real cost on small inputs.** The MCP docs make this
  point well: `audit_style` "prices a style before any text is read — what it
  costs to compile, which is paid on every run whether or not a rule ever fires.
  On a short document that is most of the wall clock." A cited pathology: "a
  negated character class under `ignorecase`... at roughly 3.6× the compile cost
  of the `\s` it replaced." So a large style like Microsoft (47 rules) has a
  fixed per-invocation tax. For a per-file edit-time hook on small skill files,
  compile time likely dominates.
- Only AsciiDoc/DITA are slow, because they shell out to external parsers.
  "Due to the dependency on the third-party `dita` command, you'll likely
  experience worse performance with DITA files." Markdown is built in and needs
  no external process.

### 8. Unexpected: Vale ships first-party Claude Code tooling

Not in the brief, and directly relevant to both candidate uses. From the
Quickstart:

```
/plugin marketplace add vale-cli/agent-tools
/plugin install vale@agent-tools
```

The plugin bundles three things, and the split matters:

- **Agent skills** (`https://vale.sh/skills`) for "fixing alerts, triaging a
  first run, adding a vocabulary." Free, run the local CLI.
- **An edit-time linting hook** that "lints each prose file as your assistant
  writes it and hands back only error-level alerts, so a mistake is fixed in the
  same turn it was made." Free. This is almost exactly candidate use (b), built
  and maintained upstream.
- **The Vale CMS MCP server** — **paid**. "The hosted MCP server is part of Vale
  CMS, which is a paid product. Vale itself — the CLI, the engine, and the
  styles — stays free, open source, and MIT licensed."

Vale also publishes `https://vale.sh/AGENTS.md`, a 4.8 KB agent-oriented setup
guide meant to be dropped in a repo root.

The free/paid line is clean and worth stating plainly: the CLI, all styles, the
skills, and the hook are free and MIT. The MCP server (rule scaffolding,
`diagnose_rule`, `test_rule`, `trace_rule`, `diff_rule`) is the only paid piece.
Everything needed for both candidate uses is on the free side. The paid piece is
an *authoring* aid — it helps write rules, not enforce them.

## Implications

**Vale can absorb most of the volume of the `writing-style` skill and none of
its judgment.** The word tables, phrase list, and over-formality substitutions —
call it 60% of the skill's line count — are almost perfectly mechanizable, and
`substitution` rules would carry fixes rather than just complaints. The four
cognitive tells and the burstiness/specificity guidance are 0% mechanizable, and
they are plausibly where the skill's actual value sits. So the question for the
exploration is not "does Vale work" but "is the mechanizable 60% the part that
model judgment is currently getting wrong?" A model reliably remembers not to
write "leverage"; it is less reliable about noticing that a paragraph it just
wrote says nothing. If that intuition holds, Vale automates the part that
needed the least help. **That should be tested against real drafts, not
assumed** — round 2 should sample actual shirabe-produced prose and count which
category of tell survives.

**A hybrid split is the natural shape, and it is a real gain even if unglamorous.**
Move the mechanical tables into Vale rules and let the skill shrink to the
judgment-only content. A 73-line SKILL.md carrying ~50 banned words costs context
on every invocation and is applied by a model that may or may not attend to row
37 of a table. A Vale rule fires deterministically, every time, with a character
offset. Shrinking the skill to the cognitive tells would make the remaining
instructions more likely to be followed, not less. That argues for adoption even
though Vale checks the easier half.

**Machine consumption is well-served, with one mandatory precaution.** `--output=JSON`
gives rule name, severity, message, matched text, line, and span. `--path` and
`--ext` allow linting a draft from stdin before it is written — which is what
candidate use (b) needs. But **exit status is nearly useless by default**: only
`error` sets a non-zero code, and most rules ship as `suggestion` or `warning`.
Any integration must parse JSON or deliberately set levels. A design that gates
a skill phase on `vale` exiting non-zero would silently pass everything.

**Do not adopt an off-the-shelf style wholesale.** Microsoft and Google encode a
house style (contractions, first person, heading punctuation, Oxford commas)
that partly *conflicts* with shirabe's, and their `Passive` rules will produce a
steady stream of false positives on ordinary adjectival sentences. The value is
in a small hand-written style, possibly cherry-picking individual rules
(`Microsoft.Contractions = YES` without the rest of Microsoft, which
`BasedOnStyles` supports). Starting from `Packages = Microsoft` would generate
noise that discredits the tool in week one.

**Candidate use (b) is partly pre-built upstream, which lowers the cost of
trying.** The `vale@agent-tools` plugin's edit-time hook already does
"lint prose files as they're written, return error-level alerts." That is worth
evaluating before designing anything bespoke — but note its default filter is
error-level only, which interacts with the severity issue above.

**Two things constrain a `wip/`-adjacent adoption.** First, `StylesPath` is
build output and must be gitignored, but the `vocabularies/` subdirectory is
hand-maintained and must be tracked — the docs give a worked `.gitignore` for
exactly this. Second, package versions float unless pinned by release URL;
for a repo several people write in, pin.

## Surprises

1. **Zero of 143 rules in the six flagship style packages use `sequence`.** The
   POS tagger is Vale's most-advertised differentiator and is unused by every
   style anyone installs. I expected at least the passive-voice rules to use it.

2. **write-good's and Microsoft's passive-voice rules are the same regex**, and
   it flags "is red," "was tired," and "are excited" as passive voice. The most
   cited example of what Vale does well is the clearest example of its ceiling.

3. **Frontmatter fields get individual scopes** (`text.frontmatter.description`).
   I expected frontmatter to be skipped entirely. For a repo of SKILL.md files
   whose `description` field determines triggering behavior, this is a sharper
   tool than I anticipated.

4. **The Tengo sandbox is closed by deliberate decision, with the reasoning in a
   source comment.** No `os` module, considered and declined. This forecloses
   "call a model from a rule" definitively rather than incidentally.

5. **Vale ships a first-party Claude Code plugin** with an edit-time hook that
   is roughly candidate use (b). The scope assumption that this would need
   building from scratch is wrong.

6. **Burstiness is computable and nothing ships it.** Sentence-length variance
   via a Tengo `script` rule is within the sandbox. The item in the skill that
   sounds least mechanizable may be the most tractable un-served one.

7. **Only `error` produces a non-zero exit code** — documented, but easy to miss,
   and it inverts the naive CI/hook integration.

## Open Questions

- **Vale is not installed, so nothing here is verified by execution.** The
  highest-value next step is installing v3.17.1, pointing it at real shirabe
  SKILL.md and docs files, and reading actual output. Specifically: how many
  alerts does a minimal hand-written style produce per document, and what
  fraction are false positives?
- **What does the false-positive rate look like on this corpus?** My passive-voice
  finding is from reproducing the regex, not running Vale. A real run on real
  files would settle whether the noise level is tolerable.
- **Which category of tell actually survives current model judgment?** The whole
  adoption case turns on this and I have no data. Sample recent shirabe-authored
  prose and classify surviving tells as mechanizable vs. judgment-only.
- **Does the `vale@agent-tools` hook fit, and what exactly does it do?** I read
  its description in the Quickstart, not its source. Worth reading before
  designing a bespoke integration.
- **Is `Joblint` still published?** Not found under `vale-cli`; it was in the
  brief. May be community-hosted or retired.
- **Does a burstiness `script` rule actually work?** Untested. Small spike:
  write it, run it against a human-written and a model-written document, see if
  the scores separate.
- **How does `sequence` behave in practice?** The paid MCP server exists partly
  to debug rules that silently never fire, which suggests writing them is
  genuinely difficult. If shirabe wanted POS-aware rules, this is a real cost.
- **Author preference is unknown to me.** The brief says the author has never
  used Vale and doubts it earns its keep. Whether a 60%-of-volume/0%-of-judgment
  split clears that bar is a judgment call for them, not a research finding.

## Summary

Vale is an excellent markup-aware regex engine with a very good Markdown parser
and a POS tagger that none of the 143 rules in its six flagship style packages
actually use — its shipped passive-voice rule flags "is red" and "was tired" as
passive, and its Tengo sandbox is deliberately closed to `os` and the network,
so no rule can ever consult anything beyond the text block it was handed. Mapped
against shirabe's `writing-style` skill this means Vale can mechanize the banned-word
tables, phrase list, over-formality substitutions, and most formatting tells
(roughly 60% of the skill's line count, deterministically, with fixes attached
and character offsets), while the four cognitive tells — low information density,
empty conclusions, dangling "this", uncited attribution — are permanently out of
reach, and those are plausibly where the skill's real value sits. The biggest
open question is empirical and unanswered: which category of tell actually
survives current model judgment on real shirabe prose, because if models already
reliably avoid "leverage" but still write empty paragraphs, Vale automates the
half that needed the least help.
