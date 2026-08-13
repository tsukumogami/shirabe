# Lead: Who uses Vale, and is there evidence it improves LLM-authored prose?

Round 1 research. All claims below are sourced; where I'm inferring rather than
reporting, I say so inline.

## Findings

### 1. Who uses Vale, and what for

Vale's adopter page lists named organizations with links to the repos where the
`.vale.ini` lives, so this is verifiable rather than marketing:
Auth0 (`auth0/docs-v2`), CircleCI (`circleci/circleci-docs`), Consensys,
Determinate Systems (`DeterminateSystems/zero-to-nix`), Discord
(`discord/discord-api-docs`), Docker (`docker/docs`), Expo (`expo/expo`),
GitHub (`github/codeql`), GitLab, Graphile (`graphile/crystal`), InSpec, Kong,
LangChain (`langchain-ai/docs`), Medusa, Mintlify, n8n (`n8n-io/n8n-docs`),
Novu, NVIDIA, PowerShell Docs (`MicrosoftDocs/PowerShell-Docs`), Progress Chef,
Spotify (`spotify/backstage`), Stoplight, Stream, Temporal
(`temporalio/documentation`) — https://vale.sh/adopters

The homepage adds AWS, Microsoft, Grafana Labs, Red Hat, Datadog and claims 90
adopters total; the repo (now `vale-cli/vale`, moved from `errata-ai/vale`) is
MIT, ~5.8k stars — https://vale.sh/

Elsewhere: Homebrew, Linode, CockroachDB, Buildkite, Meilisearch, Contentsquare,
Spectro Cloud, ING, Umbraco, Elastic (`elastic/vale-rules`), the Rubin
Observatory science platform, PostHog, Jenkins Templating Engine.

**What they use it for.** Consistently three things: terminology and product-name
consistency, house style guide enforcement, and letting non-writer contributors
self-correct before a writer reviews them. The strongest concrete claim I found
is Datadog's:

> "Vale has helped us cut down on editing time, reduced the mental toll on
> writers, and even enabled contributors to amend their own contributions before
> we get to reviewing their pull request."

with the scale that motivates it — over 20,000 PRs merged annually, an on-call
writer reviewing "over 40 pull requests per day."
https://www.datadoghq.com/blog/engineering/how-we-use-vale-to-improve-our-documentation-editing-process/

GitLab's is a performance/scale story: 82 rules across all 2,827 documentation
pages in under twenty seconds, run as a required CI check, with rules split into
`gitlab_base` (any GitLab docs) and `gitlab_docs` (published site only).
https://docs.gitlab.com/development/documentation/testing/vale/

Contentsquare's framing is "using Vale to help engineers become better writers"
— the linter as a teaching device for people who don't write for a living.
https://engineering.contentsquare.com/2023/using-vale-to-help-engineers-become-better-writers/

**The shape of every one of these deployments is the same**: many
human contributors of uneven writing skill, high PR volume, and a small docs
team that can't review everything. Vale buys consistency at a scale where human
review doesn't scale. Nobody in this list is using Vale to raise the ceiling on
good prose; they're all using it to raise the floor across contributors. That
distinction matters a lot for this exploration and I'll come back to it.

### 2. The noise and maintenance burden — honest criticisms

The best-sourced criticism is in the LWN write-up and its comment thread
(https://lwn.net/Articles/964075/). The article itself concedes:

> "having a pull request fail due to the use of a passive voice ... can be a
> frustrating experience for new contributors"

and a commenter makes the deeper objection:

> natural language tools may be "needlessly prescriptive and ... mechanical" —
> "breaking rules is, like, totes legit"

That's the core asymmetry with code linting. A compiler error is ground truth. A
Vale alert is a heuristic that a skilled writer is entitled to overrule, and
often should.

Structural pain points I found documented:

- **Exception handling was a known architectural gap.** Vale issue #213, "A new
  (better) way to handle exceptions": no way to specify exceptions independent
  of a style, so using Microsoft or Google as a base meant either forking the
  third-party style or disabling and re-implementing its rules.
  https://github.com/vale-cli/vale/issues/213
- **Rules fire in the wrong places.** Datadog: "Vale rules were alerting on
  content in image shortcodes, which we expected the linter to ignore," plus
  "consuming the Vale styles from a separate repo in our GitHub Action turned
  out to be a bit challenging and resulted in some hackery!"
- **Base styles are software-industry-shaped.** LWN commenter: base styles are
  "Microsoft", "Google" and "Red Hat", but not "Chicago" or "Oxford."
- **Context dependence is intrinsic, not a config bug.** The proselint paper
  (Suchow et al., SciPy 2016) names it directly: "in most cases *extendable* is
  preferable to *extensible*, but in software development the opposite is true,"
  and identifies low false discovery rate as the property that decides whether a
  prose linter is useful at all. https://suchow.io/proselint-paper/

The community's standard mitigations are well documented and consistent:
start with `MinAlertLevel = warning` and only promote to error once noise is
gone; maintain a custom vocabulary / `accept.txt`; demote noisy rules to
suggestion or disable them with a comment explaining why; add rules
incrementally rather than translating the whole style guide at once. Multiple
sources independently converge on "be mindful of the effort to create and
enforce a Vale rule, and the noise it creates."

**Negative evidence I looked for and did not find.** I ran several searches
specifically targeting teams that adopted Vale and then dropped it ("we stopped
using", "abandoned", "removed vale", "too noisy") and found none. I want to be
explicit that this is weak evidence of absence: teams blog about adopting tools
and rarely blog about quietly deleting them. Treat "no documented abandonment"
as unproven, not as proven durability.

### 3. Vale style packages that target AI writing tells

These exist. Four of them, all young, all essentially single-maintainer:

| Package | Rules | Stars | Commits | Notes |
|---|---|---|---|---|
| [`tbhb/vale-ai-tells`](https://github.com/tbhb/vale-ai-tells) | 78 rule files | 62 | 221 (v1.29.0) | Most mature. Includes 15 rules for AI-generated *commit messages*. |
| [`ammil-industries/vale-signs-of-ai-writing`](https://github.com/ammil-industries/vale-signs-of-ai-writing) | not stated | 25 | 53 | Derived from Wikipedia's "Signs of AI writing". Three confidence tiers. |
| [`JMill/deslop`](https://github.com/JMill/deslop) | 34 rule files | 0 | 16 | 16 generic slop rules + 18 "thoughtful essayist" voice rules. |
| [`Syntaf/vale-llm-slop`](https://github.com/Syntaf/vale-llm-slop) | 28 rules | 5 | 6 | Explicitly for agent loops. Ships dirty/clean fixtures. |

Quality notes on the two worth taking seriously:

**vale-ai-tells** is unusually honest about its own limits. It states it cannot
detect sentence-length or paragraph-length uniformity, dead metaphor repetition,
elegant variation (synonym cycling), invented concept labels, perplexity, or
model-specific stylometric signatures — i.e. it cannot detect most of the
*structural* tells. It ships extensive per-domain disable guidance (disable
`GrowthMetaphors` for agricultural writing, `FigurativeFalls` and `ShipOveruse`
for maritime, `ResonateOveruse` for physics) which is itself a measure of the
false-positive surface. The rules were AI-generated and then human-validated
against test documents.

**vale-signs-of-ai-writing** grades by confidence: error = "definite AI
artifacts — chatbot phrases, technical glitches, placeholders, tracking URLs";
warning = "likely AI patterns — hedging clusters, knowledge cutoff references";
suggestion = "suspicious but common in human writing — vocabulary, transitions,
passive voice." The author's own caveats are the useful part:

> "Vale configuration isn't as expressive or flexible as required for some
> advanced AI detection constructions."

> "It's unclear whether the use of AI and machine learning models will ever be
> satisfactory for detecting the use of AI in writing."

and the repo warns the ruleset should be "one signal among many, not the sole
basis." Also worth noting how it was built: the author fed the Wikipedia page to
Claude, asked for rule recommendations, and had Claude open PRs for manual
review. https://ammil.industries/signs-of-ai-writing-a-vale-ruleset/

**Only `vale-llm-slop` ships a false-positive measurement**: "28 rules, 82 alerts
on the dirty fixtures, 0 on the clean ones." That's the only quantified
precision claim in the entire category, and it's self-reported on the author's
own fixtures with 5 stars behind it.

Read together: the category is real, it's about a year old, and there's no
shared benchmark, no independent evaluation, and no package with meaningful
adoption. Adopting one means adopting a single person's judgment about AI tells,
not an industry-validated ruleset.

### 4. The most important negative finding: corpus-level vs per-text

`stuffbucket/vale` (a separate ASD-STE100 linter, name collision with the main
Vale — 2 stars, 38 commits) carries a `research/ai-slop` directory that is the
best-reasoned thing I found on this entire question. It reviews 16 arXiv papers
(2016–2025) and reaches one governing conclusion:

> "Every discriminative finding in the literature is **corpus-level, not
> per-text**." Text-by-text detection is "perhaps impossible."

Consequences it draws, which apply directly to the proposed use:

- Since linters operate line by line, **every rule must function as a style
  suggestion, never as a claim that an LLM authored a passage**.
- It explicitly rejects building connective-overuse rules — the evidence doesn't
  support the marker.
- Most damning for a technical-writing context: **"several markers invert for
  well-formed Simplified Technical English."** Some of the things that look like
  AI slop are exactly what disciplined technical writing looks like.

https://github.com/stuffbucket/vale/tree/main/research/ai-slop

The Wikipedia page that three of the four Vale AI styles descend from carries
the same warning, and it's aimed squarely at mechanical remediation:

> "The patterns listed here are also only potential signs of a problem, not the
> problem itself... Please do not merely treat these signs as the problems to be
> fixed; that could just make detection harder."

> "Do not rely too much on your own judgment. Humans are notoriously bad at
> distinguishing human and LLM-generated text."

https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing

I'll state the inference plainly because it's the crux of the exploration: if an
agent revises until Vale reports zero alerts, it has optimized for the surface
markers and not the underlying flatness. That's Goodhart's law, and the source
document for these rulesets warns about it by name.

### 5. Prose linters inside agent loops — the pattern exists, unmeasured

This is where the brief said evidence would be most valuable, so here's
everything I found, ranked by how close it is to the proposed use.

**Closest analogue — `stuffbucket/vale`.** Ships a Claude Code plugin whose
PostToolUse hook "lints every text file the agent writes or edits (`--slop
--audit`) and feeds any findings back as context." Exposes `lint_text`,
`fix_text`, `update_vocabulary` over stdio MCP, plus an `eval` command that
measures "slop density" across models. This is exactly the proposed architecture,
implemented, at 2 stars. No published results from the eval.

**Second closest — `skill-tools/skill-tools-plugin`.** A PostToolUse hook that
runs a linter on every `SKILL.md` edit and feeds results "back to Claude as
context so it can self-correct quality issues in the same turn." Not Vale and
not prose style, but structurally identical to candidate use #1 (a tool for
authoring skills) and evidence the pattern is being built in this exact niche.
https://github.com/skill-tools/skill-tools-plugin

**`ChrisChinchilla/Vale-MCP`** (25 stars, 37 commits) exposes `vale_status`,
`vale_sync`, `check_file`, and — directly relevant — `check_text`, documented as
evaluating "AI-generated text before writing to files or artifacts." Results
come back markdown-formatted with severity grouping plus structured metadata for
programmatic parsing. https://github.com/ChrisChinchilla/Vale-MCP

Chinchilla's stated motivation is worth quoting because it cuts *against* a
pure-Vale approach: Vale "uses regular expression to check text and while this is
effective, it means Vale has no context of what you're actually writing." He
built the MCP server to merge "Vale's highly configurable rules with the power of
LLMs" — i.e. the person who built the Vale-for-agents integration thinks the
answer is a hybrid, not a linter alone.

**Code-only, no data.** Factory.ai's "Using Linters to Direct Agents" is the most
prominent write-up of linters-as-agent-guidance. It is exclusively about code,
provides no benchmarks or measurements, and — importantly — frames the two
approaches as complementary rather than competing:

> "Use both, but treat them differently: AGENTS.md = the 'why' and the
> examples... Linting = the 'how' and the guarantee."

https://factory.ai/news/using-linters-to-direct-agents

Same story for the git-hooks-for-agents genre: `jonesrussell`'s post argues
"a pre-commit hook catches it before the commit exists. The agent gets the
failure, adjusts, and tries again," but covers code only and offers "logical
reasoning rather than research citations."
https://jonesrussell.github.io/blog/git-hooks-ai-agents/

**Bottom line for this sub-question: I found no published measurement, anywhere,
of a prose linter in an agent revision loop improving prose quality.** The
pattern is implemented in at least three places and measured in zero.

### 6. Does the code analogy transfer, and what does the research say

Research on LLM self-correction is generally favorable to external feedback but
with a specific and load-bearing condition. Self-Refine (Madaan et al.) shows
~20% average improvement from pure self-critique with no external tool. CRITIC
adds external tools for critique and refinement. The survey-level finding is the
one that matters here: **self-correction works well primarily on tasks that admit
reliable external feedback** — an interpreter error, a failing test, a type
error.

That's exactly where the code analogy breaks. A test either passes or it
doesn't. A Vale alert saying "you used 'comprehensive'" is a heuristic proxy for
a quality judgment, and it's wrong some non-trivial fraction of the time. The
transfer isn't automatic; it depends on the rule's precision. My inference, not a
sourced claim: the transfer holds well for the mechanically-decidable rules
(banned word appeared; "in order to" appeared) and holds poorly for everything
requiring judgment.

**The one head-to-head measurement I found** is LintMe (arXiv 2603.00331,
"Linting Style and Substance in READMEs"). Across five major READMEs (Vega-Lite,
TensorFlow, MDAST, Pandas, Docker):

- LintMe: **25.4** issues flagged on average
- Free-prompt LLM: **9.6**
- LLM given the rules explicitly: **7.25**

Read this carefully. It measures *recall of rule violations*, and a linter
trivially wins at finding matches for its own rules — this is not a measurement
of resulting writing quality. But two secondary findings are genuinely useful.
First, the LLM missed whole rule categories outright (hate speech detection,
objectivity checks, availability verification) even when handed the rules. That
is real evidence for the "the model doesn't reliably apply rules it's been
given" hypothesis. Second, the authors' qualitative conclusion: LLM approaches
"lacked the structured feedback mechanisms (blamability, adjustability,
fixability) that make linters effective" — a linter tells you *which line* and
*which rule*, and an LLM reviewer often doesn't.

Third and most interesting: LintMe itself is a hybrid. It uses programmatic
checks for structure and `evaluateUsingLLM` operators for semantic rules like
jargon and tone, because the authors couldn't express those mechanically. The
paper's own design is an argument against picking one side.

### 7. Alternatives, compared honestly

| Option | What it's good at | Where it fails for this job |
|---|---|---|
| **Vale** | Fast (Go), markup-aware across 12 formats, tree-sitter comment extraction for 19 languages, fully custom rules, offline, mature ecosystem | Regex-based; no semantic understanding; custom rules are RE2 regex you maintain and test yourself |
| **textlint** | Pluggable, most formats, can wrap other linters | Slower; JS toolchain; smaller docs-team ecosystem |
| **proselint** | Deep on clarity, curated from great editors | Fixed rule set, not customizable — you can't encode shirabe's list |
| **alex** | Inclusive/insensitive language | Single narrow purpose, take-it-as-is heuristics |
| **write-good** | Simple readability heuristics | Take-it-as-is, no custom rules |
| **LanguageTool / ltex-ls** | Real grammar, 25+ languages | Slow (seconds per document), GB of RAM, ~16GB n-gram download |
| **Harper (Automattic)** | Sub-millisecond, Rust, fully offline, privacy-first | English-only, spelling and core grammar — *not* a configurable style-rule engine, so it can't encode a house style |
| **LLM judge / jury** | Semantics, context, tone, the structural tells no regex reaches; can *rewrite*, not just flag | Non-deterministic; verbosity, position, and self-enhancement biases documented in the LLM-as-judge literature; costs tokens |

Two things to note. Vale can consume proselint, write-good, and alex as style
packages, so those aren't really competitors — they're Vale plugins. And the
LLM-as-judge literature flags **self-enhancement bias** specifically: judges
favor output from their own model family. shirabe's jury reviews prose written
by the same model family that's judging it. That's a genuine argument for
holding a deterministic check alongside the jury rather than instead of it —
which is the one clean pro-Vale argument in this whole report.

Braintrust's and LangChain's practitioner guidance both land in the same place:
rule-based checks for things that are enumerable and verifiable, LLM judges for
nuance, hybrid stack overall.

### 8. What the agent ecosystem actually adopted

This is the loudest signal in the data and it isn't in Vale's favor:

- `hardikpandya/stop-slop` — a **skill file**, pure prompt, no linter:
  **15.6k stars, 1.1k forks**. https://github.com/hardikpandya/stop-slop
- `jalaalrd/anti-ai-slop-writing` — skill file, works across Claude Code, Codex,
  Cursor, Gemini CLI
- `stephenturner/skill-deslop` — skill file for scientific writing
- Best Vale AI-tells package: **62 stars**

A roughly 250x adoption gap between the prompt-based approach and the
deterministic approach, for the same job. That doesn't make prompts *better* —
skills are trivially easier to install, which explains a lot of it, and
`stop-slop` "makes no explicit effectiveness comparisons against linters" and
"doesn't validate outcomes empirically." But the agent ecosystem, given both
options, has overwhelmingly chosen the one shirabe already has.

Notably, `stop-slop` does something shirabe's current skill doesn't: it ships a
**self-scoring rubric** (rate 1–10 across five dimensions; below 35/50 means
revise). That's a cheap middle path worth flagging — structure without a linter.

### 9. How much of shirabe's writing-style skill could Vale actually check

I read the local SKILL.md (`skills/writing-style/SKILL.md`, 73 lines) against
Vale's rule types. Rough split, my analysis:

**Mechanically checkable** (Vale `existence` / `substitution` / `occurrence`):
the ~50-word avoid list; most banned phrases; all over-formality substitutions;
em-dash overuse; Title Case headings (Vale scopes to headings); "serves
as/stands as/boasts"; "It's not just X, it's Y"; stacked qualifiers; hollow
gerunds.

**Not checkable**: synonym cycling; "from X to Y" on no real scale; forced rule
of three; low information density; empty conclusions; "this/that" without
antecedent; vague attribution; uniform paragraph length; boldface overuse in
context.

**Actively not checkable, and this is the important part**: the entire "What
human writing has" section — burstiness, specifics over abstractions, taking a
position. A linter can only subtract. It cannot make prose have a point of view.
The positive half of shirabe's style guidance is exactly the half a linter can't
touch, and arguably the half that matters.

## Implications

**The transfer is not automatic, and the reason is sharper than "agent-authored
vs human-authored."** Every documented Vale deployment solves the same problem:
many contributors of uneven skill, more PRs than reviewers, consistency needed
across people. Vale raises a floor. This workspace has one author (the model),
already given the style rules in-context, already reviewed by juries. There's no
floor to raise and no inconsistency across contributors to flatten. Vale's
proven value proposition doesn't obviously exist here.

**The one genuinely strong pro-Vale argument is determinism against a biased
judge.** shirabe's jury is the same model family reviewing its own prose, and
self-enhancement bias in LLM judges is well documented. A deterministic check
catches the mechanical half regardless of what the jury feels like that day, at
near-zero cost, offline, in milliseconds. That argument stands on its own and
doesn't depend on any of the AI-slop rulesets being good.

**But scope it to what a regex can actually decide.** The banned-word list and
the over-formality substitutions are perfect linter material — enumerable,
context-light, currently enforced by nothing. The structural and cognitive tells
are not, and the "what human writing has" half is not. Roughly half the skill
translates; the more valuable half doesn't.

**Do not adopt an off-the-shelf AI-slop style package.** All four are under a
year old, single-maintainer, sub-100 stars, with one self-reported precision
number between them. Worse, they're aimed at a different goal — detecting
whether text is AI-authored — and the underlying research says that goal is
corpus-level and doesn't work per-text. shirabe already has its own curated
rules, which are better targeted than any of these. If Vale is adopted, the
right move is a hand-written style translating shirabe's existing list, using
these packages as reference for regex construction only.

**Expect the noise-management costs everyone else reports.** Start at warning
level, keep a vocabulary file, demote rules that fire on legitimate technical
prose, and accept that a fraction of alerts will be wrong. In an agent loop with
no human in the middle, a wrong alert is worse than in a human workflow: the
agent will dutifully "fix" it, degrading the prose to satisfy the rule.

**Goodhart is the real risk and it's named in the source material.** Wikipedia's
own guidance — the origin of these rulesets — warns against treating the signs
as the problems to be fixed. An agent iterating to zero alerts optimizes the
surface and leaves the flatness. This argues for Vale as a *reporting* step whose
output the agent weighs, not a *gate* the agent must drive to zero.

## Surprises

1. **The corpus-level finding.** The strongest single piece of evidence against
   naive adoption came from a 2-star repo's research directory, not from any
   paper or vendor. "Every discriminative finding in the literature is
   corpus-level, not per-text" reframes the whole question — these rules can be
   style nudges but cannot be verdicts. And "several markers invert for
   well-formed Simplified Technical English" means some AI-slop rules would
   penalize good technical writing.

2. **The 250x adoption gap.** A prompt-based skill file has 15.6k stars; the best
   Vale AI-tells package has 62. Given both options for the same job, the agent
   ecosystem overwhelmingly picked the approach shirabe already uses.

3. **The Vale-MCP author's own position.** The person who built the Vale
   integration for AI assistants says Vale's regex approach "has no context of
   what you're actually writing" and built the server to combine Vale *with* an
   LLM. The hybrid framing keeps recurring independently — Factory.ai
   ("AGENTS.md = the why, linting = the how"), LintMe (programmatic + LLM
   operators), the LLM-judge practitioner guidance. Nobody credible argues for
   linter-instead-of-judge.

4. **Zero published measurements.** For the closest analogue to the proposed use
   — prose linter in an agent revision loop — the pattern is implemented in at
   least three places and measured in none. Even the repo that ships a
   slop-density `eval` command hasn't published results. Any claim that this
   improves output would be the workspace's own, unsupported by prior art.

5. **I could not find a single documented Vale abandonment.** After several
   targeted searches. Genuinely weak evidence given publication bias, but worth
   recording.

6. **`vale-ai-tells` was itself AI-generated**, as was `vale-signs-of-ai-writing`
   (Claude read the Wikipedia page and opened the PRs). The AI-slop rulesets on
   offer are LLM-authored rules for catching LLM-authored prose, human-validated
   to varying and mostly undocumented degrees.

## Open Questions

- **What's the actual false-positive rate on this workspace's own corpus?** This
  is cheap to answer and would settle most of the argument: run Vale with a
  hand-written shirabe style over existing docs/ artifacts in koto, niwa, tsuku,
  and shirabe, and count how many alerts a human would accept. No amount of
  further web research substitutes for this.
- **Gate or report?** If Vale runs inside a shirabe drafting phase, does a
  nonzero alert count block, or does the agent get the report and decide? The
  Goodhart evidence argues for report; the "nothing checks the output today"
  problem argues for gate. This is a design decision, not a research question.
- **Does the model actually violate its own style rules often enough to justify
  tooling?** Nobody has measured this. Baseline first: how many shirabe
  writing-style violations survive into merged artifacts today?
- **Skill authoring vs document drafting — same answer?** These are different
  problems. Skill files are short, high-leverage, written rarely, and reviewed
  by a human. Design docs are long, written constantly, and reviewed by a jury.
  The cost/benefit differs and the exploration should not assume one verdict
  covers both.
- **Would a self-scoring rubric get most of the benefit for none of the cost?**
  `stop-slop`'s 1–10-across-five-dimensions scoring is a middle path between
  "unchecked model judgment" and "deterministic linter" that nobody in this
  workspace has tried.
- **Who maintains the Vale style?** Every adopter reports ongoing rule tuning as
  a real cost. In a workspace where the maintainer is one person, that cost lands
  entirely on them, and I found no evidence about maintenance burden at
  single-maintainer scale.

## Summary

Vale is genuinely well adopted — GitLab, Datadog, Docker, Spotify, NVIDIA and
~85 others with verifiable `.vale.ini` files — but every documented deployment
solves the same problem this workspace doesn't have: raising a consistency floor
across many human contributors that a small docs team can't review, whereas here
one model authors everything, already has the rules in context, and is already
jury-reviewed. There is no published measurement anywhere of a prose linter
improving prose in an agent revision loop, the four existing AI-slop Vale
packages are all under a year old with sub-100 stars and one self-reported
precision number between them, and the best research on the topic concludes that
AI-writing markers are corpus-level rather than per-text, meaning they can be
style nudges but never verdicts — while a prompt-based skill file doing the same
job has 15.6k stars against the best Vale package's 62. The strongest real
argument for adoption isn't accuracy but determinism: shirabe's jury is the same
model family judging its own prose, self-enhancement bias in LLM judges is well
documented, and roughly half of shirabe's writing-style rules (the banned-word
list and over-formality substitutions) are exactly the enumerable kind a linter
decides perfectly at zero cost — so the open question that would settle this
isn't more research but an experiment: hand-write a shirabe Vale style, run it
over the workspace's existing docs, and count how many alerts a human actually
agrees with.
