# Phase 4 Verdict: Structural Format

VERDICT: PASS

Reviewed: `docs/briefs/BRIEF-vale-adoption.md` (188 lines; frontmatter lines
1-20, body lines 21-188). Contract:
`skills/brief/references/brief-format.md` @ shirabe 0.16.1-dev.

Counts below are machine-produced from the file, not estimated. The word
denominator is 1,484 whole-file / 1,349 body-only, tokenized on
`[A-Za-z0-9\`_./:-]+` (backticked paths count as one token).

## Per-criterion

**1. Frontmatter: PASS**

`schema: brief/v1` present at line 2. All three required fields present with
the right shapes:

| Field | Line | Form | Lines in block |
|---|---|---|---|
| `status` | 3 | scalar `Draft` | n/a |
| `problem` | 4-8 | literal block `\|` | 4 |
| `outcome` | 9-13 | literal block `\|` | 4 |
| `motivating_context` | 14-19 | literal block `\|` | 5 |

`problem` and `outcome` are both 4-line literal block scalars, at the top of
the contract's 2-4 line range and within it. `motivating_context` runs 5
lines; the contract sets no line bound on that field (the 2-4 constraint is
written only against `problem` and `outcome`), so this is not a violation.

`upstream` is absent, and that is correct, confirmed rather than flagged. The
contract makes it optional precisely for this case: "Optional because a brief
may be authored from a freeform topic with no single upstream document." No
ROADMAP exists for this topic. Adding a placeholder or pointing at a PRD would
be the actual error (the contract forbids a PRD upstream as a chain
inversion).

`motivating_context` is genuinely distinct, which I checked rather than
assumed. `problem` states the gap (four divergent rulebook copies, the
mechanical one narrow and blind to most prose). `outcome` states what changes
(one source, both surfaces, reports what the model cannot self-catch).
`motivating_context` states neither of those: it records that a round-1
exploration *inverted its own starting premise* by measuring the corpus, so
the brief exists to frame a problem that turned out to be the opposite of the
one that was assumed. That is the "why this brief is being written now"
content the field is for. There is mild thematic overlap with the closing
clause of `problem` and of `outcome`, but the load-bearing fact (a measurement
inverted the premise) appears in neither. Distinct.

Frontmatter `status: Draft` matches the body Status section (see criterion 2)
and the validator's FC03 agrees.

**2. FC03 status line: PASS**

Verified exactly, line by line:

```
22: ## Status
23: (blank)
24: Draft
25: (blank)
26: The framing is tool-neutral by construction. Whether the answer is an
```

The first non-blank line under `## Status` is the bare word `Draft` alone on
its own line, with nothing appended: no trailing period, no prose, no
punctuation. A blank line follows, then the explanatory paragraph. This is the
exact shape the contract's FC03 section prints as passing, and it avoids the
documented failure mode (`Draft. The brief stops before...`) where the whole
sentence becomes the compared value. The validator confirms: zero FC03 errors.

**3. Required sections and order: PASS**

All five required sections present, in canonical order, with no interleaving:

| # | Section | Line | Contract position |
|---|---|---|---|
| 1 | `## Status` | 22 | 1 |
| 2 | `## Problem Statement` | 31 | 2 |
| 3 | `## User Outcome` | 74 | 3 |
| 4 | `## User Journeys` | 92 | 4 |
| 5 | `## Scope Boundary` | 135 | 5 |
| - | `## Open Questions` | 178 | optional, Draft only |

FC04 (all five present) and FC15 (canonical order) both satisfied. Heading
text matches the contract's section names character-for-character, so the
validator's section matcher has nothing to trip on.

`## Open Questions` at line 178 carries three unresolved items and is
permitted: the Section Matrix marks it "Draft only" and the document is in
Draft. Each of the three genuinely defers a framing detail downstream rather
than naming a blocker that should have stopped the brief (where the rule
source lives; whether FC10 is replaced or extended; what severity a frequency
finding carries on first release). All three are PRD-altitude questions. They
must be empty or removed before the Draft -> Accepted transition, which is the
next gate, not this one.

No unrecognized sections. `Downstream Artifacts` and `References` are both
absent, both optional, and their absence is correct at draft time.

**4. Journey headings: PASS**

Four journeys, each leading with a `###` name heading:

- L94 `### An author edits a skill and gets prose feedback on it`
- L105 `### A drafting skill checks its own artifact before the jury sees it`
- L115 `### An adopter repo inherits the checking without configuring it`
- L125 `### A maintainer changes a rule once`

Each heading is followed by prose, and each names all three required elements.
Spot-checking the contract's user/trigger/outcome-shape requirement: journey 1
names a maintainer opening `skills/execute/SKILL.md`, the edit as trigger, and
an explicit outcome shape; journey 2 names `/design` at its validate phase, the
artifact landing on disk as trigger, and an outcome shape; journey 3 names the
adopter repos calling `validate-docs.yml`, a PR touching a doc as trigger, and
an outcome shape; journey 4 names a maintainer deciding `tier` should stop
being flagged, the edit as trigger, and an outcome shape. Three of the four
use the literal phrases "The trigger is" and "The outcome shape is," which
makes the mechanical check unambiguous.

Entry points are distinct, not one journey re-told. Journeys 1 and 4 both have
"a maintainer" as the user, which is the only place worth a second look, but
they exercise different surfaces: journey 1 is the *unchecked-file* surface
(prose feedback arriving on a SKILL.md that validate has never inspected),
journey 4 is the *rule-source* surface (a single edit propagating to four
enforcing copies). Different entry points, different outcome shapes. Distinct.

**5. Public-visibility: PASS**

Scanned the whole document for `private/` path segments, private repo names,
private filenames, internal codenames, private issue numbers, and internal
tooling references. Clean on every axis. Specifically searched for and found
zero hits on: `private/`, `tsukumogami`, `dot-niwa-overlay`, `coding-tools`,
`vision#`, and `/tsukumogami:`-style internal slash commands.

Every path in the document is a public in-repo path, as expected:
`skills/writing-style/SKILL.md`, `crates/shirabe-validate/src/checks.rs:2551`,
`skills/execute/SKILL.md`, `validate-docs.yml`. Every repo named (shirabe,
koto, niwa, tsuku) is public per the workspace repository table. The only
skill named is `/design`, a public shirabe skill. No issue numbers appear at
all, so the "private issue numbers only" qualifier never comes into play.

This mattered to check carefully because the upstream exploration had private
repo read access. Nothing from that side surfaced.

*One observation, not a defect.* Lines 40-43 describe "a five-word quick
reference in the workspace CLAUDE.md" and "A fifth pointer, from CLAUDE.md to
`.claude/helpers/writing-style.md`, resolves to nothing." I traced both: the
CLAUDE.md carrying that quick reference is the workspace-root one, which sits
*above* `public/` and is therefore not itself a public-repo file. No rule is
broken by this. The BRIEF never names that file's repo or its path, `CLAUDE.md`
and `.claude/helpers/` are ordinary Claude Code conventions that appear in
public repos including shirabe's own, and a path that resolves to nothing
cannot disclose a private filename. So it passes the cleanliness rule as
written. The residual is legibility rather than leakage: an external
contributor reading the public shirabe repo cannot resolve "the workspace
CLAUDE.md" or verify the dangling pointer for themselves. If the author wants
to close that gap, adding four words of orientation ("the workspace-level
CLAUDE.md above the repo") would do it. Optional; I am not making it a
required change.

**6. Writing style: PASS**

Real counts against `skills/writing-style/SKILL.md`.

*Em dashes: 0. Rate 0.00 per 1,000 words.* Confirmed the reduction from 20 to
0 landed completely. I searched for every dash character that could stand in
for one, not just U+2014: em dash U+2014 = 0, horizontal bar U+2015 = 0, minus
U+2212 = 0, spaced `--` = 0 (the only two `--` in the file are the frontmatter
fences at lines 1 and 20). One en dash U+2013 appears, at line 61 in `Tier
1-4`, which is correct typography for a numeric range and not a substituted em
dash.

I read every re-punctuated sentence for naturalness. The substitutions are
overwhelmingly colons and semicolons doing work an em dash was doing, and they
read naturally, not stilted: the appositive stat at lines 65-67 ("Em dashes
run 3,195 in `docs/` and 1,222 in `skills/`: 7.84 per thousand words, with 72%
of files above 3 per thousand and the worst at 28.5") and the enumerated copy
list at lines 38-43 are both better with the colon than they would have been
with a dash. Two spots read slightly tighter than ideal, neither rising to a
finding:

- L26-28, "Whether the answer is an external linter, a widened native check,
  or a mix is a DESIGN decision." The subject is a long `Whether` clause with
  an internal comma series, so a reader hits "or a mix is" and briefly
  re-parses. Mild garden-path. Recasting as "...or a mix, is a DESIGN
  decision" or "That choice is a DESIGN decision" would settle it.
- L111-112, "the phase gets accurate findings, right line and prose only, and
  that those findings name..." The bare appositive "right line and prose only"
  sits between commas next to an `and`, so it can momentarily read as the
  second item of a three-item list. Parentheses would disambiguate.

Both are optional polish. Neither garden-paths badly enough to obscure meaning
and neither reads stilted.

*Banned words, genuine uses: 0.* Total occurrences of banned-list words: 10,
across `tier` (5 lines), `journey` (3 lines), `journeys` (1), `leverage` (1).
I checked each against use-versus-mention:

| Line | Word | Use or mention |
|---|---|---|
| 60 | `tier` | mention: backticked, "`tier` at 147 hits is the Tier 1-4 vocabulary" |
| 61 | `tier` | mention: "Tier 1-4 decision-complexity vocabulary" is the referent under discussion |
| 63 | `leverage` | mention: quoted, "A drafting model reliably avoids \"leverage.\"" |
| 61 | `journey` | mention: backticked, "at 112 hits is a required BRIEF section heading" |
| 89 | `tier`, `journey` | mention: backticked pair, "Domain vocabulary that happens to appear on a banned list" |
| 92 | `Journeys` | contract-mandated section heading `## User Journeys` |
| 127 | `tier` | mention: backticked, "A maintainer decides `tier` should stop being flagged" |
| 147 | `tier`, `journey` | mention: backticked pair, in-scope item on suppressing domain vocabulary |

Every one is the BRIEF quoting the word while explaining that flagging it is a
false positive. That is the legitimate explanatory role and I am not flagging
any of it. The single unbackticked instance, "Tier 1-4" at line 61, is still a
mention: it names the decision-complexity vocabulary that the sentence is
arguing about. Line 92 is the required section name the format contract
mandates; the author has no latitude there. Genuine violations: zero.

*Title Case headings: 0 authored.* Ten headings total. Six `##` headings
(Status, Problem Statement, User Outcome, User Journeys, Scope Boundary, Open
Questions) are Title Case, but every one is a canonical section name fixed by
the format contract and matched by FC04/FC15; changing their case would break
validation. All four `###` journey headings, which are the author's own, are
sentence case: "An author edits a skill and gets prose feedback on it," "A
drafting skill checks its own artifact before the jury sees it," "An adopter
repo inherits the checking without configuring it," "A maintainer changes a
rule once." Zero Title Case headings attributable to author choice.

*"serves as" / "stands as" / stacked qualifiers / hollow gerunds: 0.* Searched
`serves as`, `stands as`, `boasts`, `highlight*`, `underscor*`, `emphasiz*`,
`showcas*`, and "it's not just X, it's Y": no hits. Searched stacked-qualifier
and hedge patterns (`could potentially`, `may possibly`, `might potentially`,
`potentially`, `arguably`, `somewhat`, `fairly`, `quite`, `very`, `really`):
no genuine hits. The five apparent matches were the substring `very` inside
`every` and are false positives.

Also clean on the adjacent rules: adverb openers (Additionally, Notably,
Ultimately, Seamlessly, Significantly, Furthermore, Moreover) = 0 at sentence
or line start; filler phrases (`worth noting`, `important to note`, `at its
core`, `in conclusion`, `in summary`, `delve`, `studies show`, `experts
argue`, `valuable insights`) = 0; over-formality substitutions (`in order to`,
`due to the fact`, `at this point in time`, `prior to`, `subsequent to`, `with
respect to`, `has the ability to`) = 0.

*Bold runs: 2 in the body. Rate 1.48 per 1,000 body words.* Both are
`**In scope:**` and `**Out of scope:**` at lines 137 and 152, which are the
Scope Boundary section's required IN/OUT list labels. No decorative bolding
anywhere else. Well under any overuse threshold.

*Burstiness: strong.* 54 prose sentences, lengths ranging 5 to 51 words, mean
20.6. The distribution has real variation, not mild variation: 5-word and
8-word sentences sit directly beside 45- and 51-word ones. "The trigger is the
edit" against the 51-word sentence that follows it is exactly the target shape
the style guide describes.

*One noted deviation, not a FAIL.* Contractions: 0 genuine ones. The document
uses "does not," "cannot," and "it is" throughout, 22 lines' worth, where the
style guide's formatting-tell table lists "No contractions" as a tell and the
workspace CLAUDE.md says "Use contractions." I am recording this as an
observation rather than a failure for two reasons: it is not among the six
sub-criteria this review was asked to count, and the uniformly formal register
is defensible in a spec-altitude artifact whose sibling briefs read the same
way. If the author wants to close it, contracting even a handful of the
"cannot" instances in the Problem Statement would relieve the formality
without touching the argument.

Every enumerated sub-criterion is clean, so this criterion is a PASS.

**7. No wip/ references: PASS**

Grepped the entire document, frontmatter and body, prose and inline code, for
`wip/`. Zero occurrences. No `wip/...` path appears in the `upstream:` field
(the field is absent entirely), in any prose reference, in the Open Questions
items, or anywhere else. `Downstream Artifacts` and `References` are both
absent, which removes the two sections where the contract specifically warns
about `wip/` paths ("Each entry is a durable repo-relative path (not
`wip/...`)").

Every path the document does cite is durable: `docs/`, `skills/`, `crates/`,
and a workflow filename. The committed artifact carries no pointer that
workflow cleanup could dangle.

## Validator output

Command:

```
cd /home/dgazineu/dev/niwaw/tsuku/tsuku+vale_or_not-33480214/public/shirabe/.claude/worktrees/vale-adoption
./target/release/shirabe validate --format human -- docs/briefs/BRIEF-vale-adoption.md
```

Verbatim:

```
docs/briefs/BRIEF-vale-adoption.md:40 notice [FC10] writing-style banned word "tier" -- see skills/writing-style/SKILL.md for canonical alternatives
docs/briefs/BRIEF-vale-adoption.md:41 notice [FC10] writing-style banned word "tier" -- see skills/writing-style/SKILL.md for canonical alternatives
docs/briefs/BRIEF-vale-adoption.md:43 notice [FC10] writing-style banned word "leverage" -- see skills/writing-style/SKILL.md for canonical alternatives
docs/briefs/BRIEF-vale-adoption.md:69 notice [FC10] writing-style banned word "tier" -- see skills/writing-style/SKILL.md for canonical alternatives
docs/briefs/BRIEF-vale-adoption.md:107 notice [FC10] writing-style banned word "tier" -- see skills/writing-style/SKILL.md for canonical alternatives
docs/briefs/BRIEF-vale-adoption.md:127 notice [FC10] writing-style banned word "tier" -- see skills/writing-style/SKILL.md for canonical alternatives

0 error(s), 6 notice(s) -- clean

Advisory: Draft posture: no draft-tolerable findings to flag.
```

Exit code: 0.

### Reading of the six notices

Confirmed rather than treated as defects, and I verified both halves of the
claim rather than accepting them.

*The offset is exactly +20 and reproduces on all six.* The frontmatter
occupies lines 1-20 inclusive, so FC10 is reporting body-relative line numbers
while labeling them as file line numbers. Mapping each notice to the real line:

| Reported | Actual | Content at the actual line |
|---|---|---|
| 40 | 60 | "domain vocabulary: `tier` at 147 hits is the" |
| 41 | 61 | "Tier 1-4 decision-complexity vocabulary, and `journey`..." |
| 43 | 63 | "\"leverage.\" The rules it obeys are the mechanizable ones." |
| 69 | 89 | "banned list (`tier`, `journey`) does not generate noise..." |
| 107 | 127 | "A maintainer decides `tier` should stop being flagged..." |
| 127 | 147 | "- Suppressing the workspace's domain vocabulary (`tier`, `journey`)..." |

Every one resolves to a real occurrence at actual = reported + 20. This is the
same FC10 frontmatter-offset bug the BRIEF documents at lines 109-110 and
names as out of scope at lines 169-171, so the artifact is describing a defect
it then correctly declines to fix. Worth one caution for whoever reads the raw
output next: reported `127` and actual `127` are both real `tier` lines by
coincidence, which makes that row the easiest to misread.

*All six are mentions, not uses.* Cross-checking against my own count in
criterion 6: the file contains exactly 5 lines with `tier` and 1 with
`leverage`, and FC10 reported exactly 5 plus 1. The coverage is complete, and
every flagged instance is the BRIEF quoting a banned word inside backticks or
quotation marks while arguing that flagging it is a false positive. There is
no genuine style violation among them.

Notices are non-blocking and the run exits 0 with the summary line reading
`0 error(s), 6 notice(s) -- clean`. The advisory confirms no draft-tolerable
findings. Nothing here blocks the Draft -> Accepted transition, and nothing
here is a required change.

## Required changes

None. All seven criteria PASS.

The three items recorded above are optional polish, offered for the author's
judgment and not gating: the workspace-CLAUDE.md orientation note (criterion
5), the two tight re-punctuated sentences at lines 26-28 and 111-112
(criterion 6), and the absence of contractions (criterion 6).

The remaining gate before Draft -> Accepted is the contract's own precondition,
not a format defect: the three Open Questions at lines 178-188 must be empty or
removed at transition time, with each resolving into the downstream PRD's
Decisions and Trade-offs section.
