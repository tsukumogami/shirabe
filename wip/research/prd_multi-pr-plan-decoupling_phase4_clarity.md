# Verdict: FAIL

## 1. Ambiguity

**R4 vs R6 — the sharpest finding.** R4 requires the work-tracking preference to
be resolved "independently of the delivery-shape preference and independently
of the resolved `execution_mode`." R6 requires its default, when unstated, to
be "the behavior the repository exhibits today." But today's behavior *is* a
function of `execution_mode` — the Problem Statement says so directly: "filing
GitHub issues and a milestone when the value is `multi-pr` and filing nothing
when it is `single-pr`." So R6's default target (issues iff multi-pr) is
exactly the correlation R4 forbids the resolved preference from having. Two
competent engineers diverge here: one implements R6 literally, as a default
that still keys off `execution_mode` (satisfying R6's letter, violating R4's
independence and quietly preserving the fusion this PRD exists to break); the
other implements R6 as a fixed, execution-mode-blind default value chosen so
that it happens to reproduce today's outcome only in the two cases the
Acceptance Criteria test, and diverges from "today" in any case the ACs don't
cover. Neither reading is ruled out by the requirement text, and the PRD's own
Acceptance Criteria never test "no tracking preference stated" as its own
scenario — only "no delivery preference stated" (AC 4) — so nothing forces the
ambiguity to surface before merge.

**R8's "branches" don't match the rule they cite.** R8 requires naming "which
of the governing rule's branches produced the shape — a forcing constraint, an
incremental-value judgment, or the repository's stated delivery preference."
But the Problem Statement describes the governing principle as permitting
splitting "for a hard constraint or for genuine incremental value and for
nothing else" — two branches, not three. The delivery-shape preference (R1/R2)
is a separate mechanism from the governing rule; R12 even says the
value-confirmation guard "continue[s] to run unchanged" against whatever unit
the preference makes the default, which reads as the preference *feeding* the
value-judgment branch rather than being a third independent branch of "the
governing rule" itself. R8 asks an implementer to name one of three
coordinate branches, but the document that defines the rule only has two.
Whether "the repository's stated preference" is a bypass of the value-judgment
branch or a determinant of it changes what the R8 record is allowed to say,
and R8 doesn't resolve it. (The Acceptance Criteria partially patch this — the
third AC bullet forbids "a fabricated incremental-value claim" when the
preference is the real reason — but a patch in the AC is not a definition in
the requirement.)

**R5 quietly narrows the BRIEF's three-way choice to two, unexplained.** The
upstream BRIEF's Scope In lists the tracking preference as "GitHub issues,
issues with a milestone, or neither" — three options. R5 only requires
distinguishing "filing GitHub issues from filing none" — two. The Acceptance
Criteria bundle milestone with issues without comment ("results in no GitHub
issues and no milestone"), which suggests the milestone-or-not axis was
dropped rather than deferred, but nothing in the PRD says so. Decisions and
Trade-offs closes every other BRIEF Open Question explicitly; this one isn't
named as a decision, so a reader can't tell whether it's an intentional
simplification or an oversight.

**R1's "flag" is not specific to this feature.** R1 resolves the delivery-shape
preference on "`flag > CLAUDE.md-header > default`" — an established
repo-wide precedence stack (confirmed elsewhere in the codebase) — but never
names what the flag actually is for this preference specifically, or whether
one is even in scope (R1 doesn't require a flag to exist, only that if a flag
mechanism exists it takes precedence). Minor by itself, but combined with R4's
"independently... resolved" language, an implementer can't tell from the PRD
alone whether a per-invocation override is being requested here or just
inherited boilerplate from the precedence idiom.

## 2. Undefined terms

- **"delivery shape"** — never defined in this PRD. It doesn't appear at all
  in the Problem Statement (which uses `execution_mode`, `single-pr`,
  `multi-pr`, `coordinated` instead); it's introduced cold in the first Goals
  bullet ("does not re-argue delivery shape") as though already established.
  It is glossed once, informally, in the upstream BRIEF's Problem Statement
  ("can this change land in a single pull request, or does something force it
  apart"), but per the PRD-format rule that a PRD "states its own problem in
  full" and stands alone, this term needed its own anchor here and doesn't
  have one.
- **"reviewable increment(s)"** — used in R2, the third User Story, and AC 3,
  never defined anywhere in the repo (checked; it only appears in this PRD).
  It's plain-English-inferable, but R2 uses it to define an enum value SHALL
  requirement, which is exactly the place a PRD should pin down what counts.
- **"remote GitHub artifacts"** (R13) — undefined at the point of use. R13
  reads as though it could mean any GitHub-side object the transition
  creates, including a pull request itself (every plan creates one). It's
  only clarified nine lines later, in Acceptance Criteria, as meaning
  specifically "will create GitHub issues." A requirement shouldn't need its
  own AC to disambiguate its central noun phrase.
- **"posture"** and **"draft-tolerable"** (R10) — genuinely defined
  elsewhere in the repo (`docs/guides/lifecycle-posture.md`), so these are
  fine as terms of art, but the PRD doesn't cite where they're defined, which
  matters more here than usual because...
- **"the governing workflow principle"** / **"the cross-repository grouping
  rule"** (Problem Statement, R11) — never named as a file. The BRIEF's
  References section names them explicitly
  (`references/workflow-principles.md`, `references/coordination-strategy.md`);
  this PRD, which is supposed to stand alone per the format guide, doesn't.
  The Acceptance Criteria later use closer-to-literal names ("the
  workflow-principles document," "the cross-repository coordination
  contract"), which likely resolve to the same two files, but a reader of R11
  alone has to guess.

## 3. Internal consistency

- R4/R6/R17, detailed above under Ambiguity, is the load-bearing consistency
  problem: R4 demands independence from `execution_mode`, R6 demands the
  unstated default reproduce behavior that is currently *defined by*
  `execution_mode`, and R17 restates the same promise at the "neither
  preference stated" level without resolving which of R4 or R6 gives ground.
- R2's delivery-shape default ("prefer the fewest pull requests") carries no
  explicit backward-compatibility claim of its own — unlike R6's explicit
  "defaults to today's behavior" for tracking — and instead relies entirely
  on R17 to guarantee it matches current output. That's a real requirement
  (R17), so this isn't a contradiction, but it means R2 and R6 are specified
  at different levels (declarative value vs. behavioral equivalence) for
  what should be a structurally parallel pair of requirements, which is worth
  flattening for a reader comparing them side by side.
- R8/R9/R18 are otherwise consistent: R9 is a clean negation-exemption of R8,
  and R18's free-text choice doesn't conflict with either. The only issue in
  this trio is the branch-naming ambiguity in R8 covered above.

## 4. Writing style

No banned-vocabulary hits (tier/tiered, robust, leverage,
comprehensive/holistic, facilitate — zero occurrences). No stacked qualifiers,
no "it's worth noting," no "in order to" / "due to the fact that" family, no
"serves as / stands as / boasts," no hollow gerunds. Contractions are used
correctly where they occur. Em dash count is 16 across ~2,700 words, which is
in the same range as this repo's other PRDs and the upstream BRIEF — not a
threshold breach, and dashes are doing real subordinate-clause work rather
than replacing punctuation lazily. No AI tells found. This criterion passes
outright; nothing to fix here.

## 5. Reader test

No. The Problem Statement leans on four things a cold reader — someone who
has not read the exploration or the BRIEF — cannot resolve from the document
itself: "the governing principle" (unnamed file, see Undefined Terms), "the
cross-repository contract one altitude up" (unnamed file, and "altitude" is
unglossed shirabe jargon for document hierarchy), "the planning skill's own
surfaced rule" (which skill, which rule — not named), and "the wip-hygiene
rule" (defined in the workspace CLAUDE.md, not in this document, and not
cited). A reader can follow the shape of the complaint — one field is
answering three questions — but cannot verify any of the specific claims
("the repository already contradicts itself... in two files") without
already knowing shirabe's document map. Given the PRD-format rule that the
Problem Statement section specifically carries the obligation to stand alone,
this is a real gap, not a nice-to-have.

## Required Changes

1. Resolve the R4/R6/R17 tension: either narrow R4's independence claim to
   exclude the unstated-default case, or rewrite R6 so its default is stated
   as a fixed value (not "today's behavior") and let R17 alone carry the
   backward-compatibility promise for the fully-unstated case. Add an
   Acceptance Criterion that tests "tracking preference unstated, delivery
   preference stated to something non-default" so the resolved behavior is
   pinned down, not just asserted.
2. Fix R8: either state explicitly that "the repository's stated delivery
   preference" is a third, independent branch of the same governing rule
   described in the Problem Statement (and update that Problem Statement /
   R11 language to say the rule now has three branches), or reword R8 so the
   preference is described as feeding the incremental-value branch rather
   than standing beside it.
3. Add a definition (or a citation to the BRIEF's phrasing, brought inline)
   for "delivery shape" before its first use in Goals, and define "reviewable
   increment(s)" where R2 introduces it.
4. Reword R13 to say directly what it means ("creates GitHub issues") instead
   of the ambiguous "remote GitHub artifacts," or define the term at first
   use.
5. Either restore the BRIEF's three-way tracking distinction (issues /
   issues+milestone / neither) in R5 and the Acceptance Criteria, or add a
   line to Decisions and Trade-offs explaining why it collapsed to two.
6. Name the actual files behind "the governing workflow principle" and "the
   cross-repository grouping rule/contract" at first use in the Problem
   Statement, and gloss "wip-hygiene rule" and "altitude" or cut them from
   the Problem Statement in favor of plainer phrasing, so the section stands
   alone per the PRD-format rule.
