---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-chain-cardinality.md
problem: |
  Document lineage is one-to-many in the formats and in practice, but four
  places in the tooling assume one-to-one: YAML sequences never survive
  frontmatter parsing, the chain-targeted check evaluates whichever chain sorts
  first by filename, a document under two chains receives contradictory status
  requirements with no diagnostic, and the finalization walk retires shared
  parents while other consumers still depend on them.
decision: |
  Parse sequences into real entries and route every reader through one
  normalization helper. Replace the two chain-evaluation loops with a
  member-keyed obligation map consumed by a single emitter, making finding
  identity a map key rather than message text. Add a conflict finding that
  supersedes the contradictory pair, computed from effective postures and
  guarded by a root-versus-member fix applied first. Give the finalization walk
  a referrer map and a worklist, and make a block a reported skip. Give both
  parents and both head children an --upstream flag, recorded in parent state
  and surfaced by a non-blocking notice before the chain head is authored.
rationale: |
  Each half is chosen to make a guarantee structural rather than coincidental.
  One parser plus one normalization helper makes reader agreement impossible to
  drift from; a map key makes duplicate findings unconstructible rather than
  deduplicated after the fact; a referrer map read once makes the blocking
  decision a property of the walk rather than of an external gate; and a flag
  decoupled from the topic slug removes a dependence on two slugs coinciding
  that the reuse case is defined by breaking.
---

# DESIGN: Chain Cardinality

## Status

Proposed

Five decisions were researched independently and cross-validated. Two sequencing edges
and one inverted repair were found at cross-validation and are recorded in Implementation
Approach; they are the parts most likely to be got wrong by reading one decision alone.

## Context and Problem Statement

`PRD-chain-cardinality` establishes that document lineage is one-to-many in the format
references and in practice, while the tooling assumes one-to-one in four places. This
design settles how each is repaired without changing what any document in the corpus
validates to.

Three properties of the existing code shape every decision below.

**The `upstream:` field has three readers that do not agree.** The resolution check and
the finalization walk each treat the whole value as one path; the chain walk splits on
newlines and strips list prefixes. The chain walk's list handling has never been
reachable, because the frontmatter parser collapses every YAML sequence to the empty
string before any reader sees it — block, flow, and single-entry alike. A `|` block
scalar survives as joined text and is the only multi-valued shape that half-works today.

**Posture belongs to a chain, and a chain is identified by its root.** A shared member is
cloned into every chain reaching it, and each imposes an independent requirement on one
mutable status field. Nothing groups by member, so a document under two chains receives
two instructions; and the post-hoc deduplication cannot collapse them because the message
interpolates the posture name, which makes message equality a false proxy for finding
identity.

**The finalization walk is a single-path traversal with no index.** It reads one upstream
per node and transitions every ancestor it reaches. It has no way to know whether anything
outside its branch still points at what it is retiring — which is how five documents in
this repository came to carry dangling references from one commit.

## Decision Drivers

- **No corpus document may change its validation result**, and the existing suite must
  pass with no test modified. This is the binding constraint on every option below and it
  eliminated otherwise-attractive choices in two decisions.
- **Guarantees should be structural, not coincidental.** Several defects here exist
  because a property held by accident until something shifted: reader agreement held while
  no document used a sequence, deduplication held while no message carried a posture name,
  and the parent hand-off holds while two slugs coincide.
- **A repair must not tell an author to fix something that is correct.** A diagnostic that
  fires on documented, intended lineage is worse than silence, because it trains readers to
  ignore it.
- **The mutation path deserves more caution than the check path**, because its failure mode
  is irreversible and its damage is discovered late.
- **Prose contracts are the implementation for the parent half.** The skills are documents;
  changing them means changing contract text, state schemas, and prompt wording, and their
  evals assert on literal strings.

## Considered Options

Each decision was researched independently against the running binary, and every claim
below was measured rather than reasoned about. The evidence is summarized here because the
research files that produced it are working artifacts and do not survive the merge.

### Decision 1 — Sequence representation and resolution reporting

**Chosen: parse sequences into real entries, with one shared normalization helper.** The
parser returns entries; every reader asks for them through the same helper, which owns
trimming, the placeholder rule, cross-repo handling, and self-reference suppression.

*Rejected — newline-joined text.* It would activate the chain walk's existing splitting for
free and cost almost nothing. It fails because a scalar reader then silently receives a
joined multi-path string, which is the exact failure the requirement on reader agreement
exists to prevent, and because splitting scalars would make every `problem: |` prose block
parse as a many-entry list.

*Rejected — a parallel accessor for declared multi-valued fields.* Keeps the scalar path
intact but leaves two ways to read one field, which is the condition that produced three
disagreeing readers in the first place.

Two consequences are accepted deliberately: a `upstream: |` two-line value stops
half-working, and sequence fixtures must stay out of the cross-implementation parity
corpus, because the frozen baseline collapses sequences and such a fixture could only be
made to pass by editing the gate.

### Decision 2 — Chain evaluation and finding identity

**Chosen: a member-keyed obligation map, built once, consumed by a single emitter.** A
document's obligations are the union over every chain containing it. The mode selects only
which documents are reported on, not what is said about them. Finding identity is the map
key — code, path, required set — so a duplicate cannot be constructed rather than being
removed afterwards.

*Rejected — keep both loops, drop the posture name, deduplicate textually.* Fifteen lines
against roughly a hundred and twenty, and it satisfies most requirements the day it lands.
It fails because identity becomes message equality, which is precisely the arrangement that
already failed here; the next person to add a hint or a line number to a message silently
reopens the defect with no test able to name what broke.

*Rejected — chain-targeted calls whole-tree and filters.* Strongest possible form of
mode agreement, but filtering by path drops corpus-integrity findings the mode reports
today, which is a regression on the one mode the cascade runs.

*Rejected — reachability instead of per-root walks.* Produces the same map by a different
traversal, rejected on regression risk rather than merit: the existing walk carries three
observable behaviors that are easy to lose in a rewrite.

### Decision 3 — Conflict detection and supersession

**Chosen: a distinct check code emitted from the obligation map, superseding the
status-lifecycle findings of the conflicting chains, with the root-versus-member fix
applied first.**

Conflict is disjointness of required sets, not inequality — treating "the chains want
different things" as conflict would fire on every shared DESIGN, which is the case the
intersection requirement exists to protect. The sets are computed from *effective*
postures, after the ready-mode re-target, because a conflict computed from raw postures
reports a ready-mode conflict that ready mode does not have.

Supersession is safe by construction rather than by care: if no status satisfies every
chain, the document's status satisfies at most one, so at least one superseded finding
always fired. The replacement is always one-for-N with N at least one, never one-for-zero.

*Rejected — detect but do not supersede.* The honest option, and it was given a full
hearing: it satisfies the severity requirement vacuously, has provably zero regression
exposure, and is the smallest change. It loses on three counts. The accepted requirements
say otherwise in SHALL language, so choosing it is a PRD amendment and would have to be
proposed as one. The contradictory pair is the harm rather than noise — an author who acts
on one message makes the other fire, which is the user story verbatim. And co-location does
not save it, because findings sort by file, code, and message, so the two instructions and
their explanation are separated in the rendered output and become independent annotations.

*Rejected — reuse the existing lifecycle code with a merged message.* Severity would be
pinned by identity and every existing consumer would keep working, but the code family
exists to name kinds, a lineage conflict is not a state-versus-posture mismatch, and a
merged code cannot be split later.

### Decision 4 — Consumer-aware, multi-branch finalization

**Chosen: build the referrer map once per walk from the validator's existing index through
a narrow graph-level API; the walker makes a per-node decision; a block is a reported skip,
not a walk-aborting failure.**

The walk becomes a worklist over every upstream with a visited set, so a shared ancestor
reached through two branches is visited once — otherwise it would be transitioned twice and
the exit code would depend on traversal order. Branches are ordered by written order, not
path order, because ordering by path would reintroduce the filename dependence forbidden
elsewhere.

The carve-out is *documents this walk retires*, not *documents it visits*. That distinction
earns a property for free: a blocked node stays non-terminal, so it remains a blocking
referrer for its own ancestors and the block propagates upward with no additional rule.

*Rejected — an index owned by the finalization module.* Rejected on reader agreement rather
than cost: it would duplicate the upstream parse at the exact moment that parse is being
unified, in a change whose stated problem is that three readers disagree.

*Rejected — a report-only walk plus an external gate.* Given a serious hearing, since a
refusal before any mutation has a smaller blast radius. Rejected on four counts: the
per-node verdict an acceptance criterion requires cannot come from an all-or-nothing gate;
a cross-process gate widens the window between check and mutation; a gate outside the
binary leaves the documented public subcommand willing to perform the unsafe transition;
and it saves no orchestration. Its reporting half is adopted.

### Decision 5 — The parent upstream contract

**Chosen: `--upstream <path>`, the same token on both parents and on both head children,
parsed before the positional slug, recorded in parent state under a conditional field, and
announced by a non-blocking notice inside the chain proposal.**

The flag never enters the positional slot, so the parents' rejection of artifact paths
there is untouched. Inbound validation enforces the basename, deliberately unlike the
outbound contract that does not — outbound, the parent is handing over an artifact whose
type it knows; inbound, it is routing on a string the author typed, and a wrong type
silently mis-frames the chain head.

A notice is not a prompt: no options, no default, no control-flow change. It rides inside
the chain-proposal output that already fires on every run, names no candidate so it needs
no directory scan, and blocks nothing so it has no non-interactive default to get wrong.

*Rejected — an upstream-path positional input mode.* Reopens the path-rejection rule and
still needs the topic slug from somewhere, making it two inputs in one input's costume.

*Rejected — a discovery scan that asks which upstream to attach to.* Adds a blocking prompt
to every run, and attaching a bet to the wrong upstream silently is worse than a visible
duplicate.

## Decision Outcome

The five decisions compose into one change with a clear spine: **make each guarantee a
property of structure rather than of circumstance.**

One parser produces entries; one helper normalizes them; three readers consume that helper.
Reader agreement stops being a thing to verify and becomes a thing that cannot vary.

One obligation map replaces two evaluation loops. Deduplication stops being a post-hoc
pass over message strings and becomes the impossibility of constructing a duplicate key.
Mode agreement stops being a coincidence of two loops staying in sync and becomes identity
of the code that produces both.

One referrer map, read once per walk, replaces the absence of any consumer knowledge.
Safe retirement stops being an external gate's responsibility and becomes a property of
the walk that performs the mutation.

One flag, decoupled from the topic slug, replaces a hand-off that works only while two
slugs coincide — a coincidence the reuse case is defined by breaking.

The conflict diagnostic sits on top of the obligation map and reports the one case the
model cannot represent: a document whose consumers demand states that no single status
satisfies. It supersedes rather than accompanies, because the pair it replaces is itself
the harm.

## Solution Architecture

**Parsing layer.** The frontmatter parser gains an entries representation for sequence
values, preserving written order, covering block and flow syntax and the single-entry case.
Scalars yield exactly one entry containing their whole text; scalars are never split. A
shared normalization helper owns trimming, the placeholder rule, cross-repo references, and
self-reference suppression, and is the only path by which any reader obtains entries. The
string surgery currently inside the chain walk is deleted, since the parser now returns what
it was reconstructing.

**Evaluation layer.** `discover_chains` is unchanged — it is reused precisely to preserve
three observable behaviors that a rewrite would risk. From its output an obligation map is
built once: document path, to required status set, to the postures and chain roots imposing
it. The ready-mode re-target is applied once, before the map is built, so every consumer
sees effective postures. Emission becomes a single function over a scope set of document
paths; whole-tree passes every indexed document, chain-targeted passes the members of every
chain containing the target. Corpus-integrity findings remain whole-corpus in both modes,
which is what both modes already do.

The chain-targeted scope is a shallow closure, not a transitive one: the members of chains
containing the target, not then the chains containing those members. A transitive closure
would make the targeted mode indistinguishable from whole-tree in a connected corpus,
defeating the mode's purpose.

**Conflict layer.** Before conflict detection, the root-versus-member fault is repaired at
source: a ROADMAP that is not the root of the chain being evaluated is required present,
because only its own chain can require its absence. The requirements table cannot currently
tell whether a posture came from a document's own chain or from a chain it merely sits
above, and that conflation produces a live false positive — one feature finishing beneath a
live ROADMAP makes the validator demand the ROADMAP be deleted.

With that repaired, conflict detection is disjointness across the required sets a document
carries. The finding names each conflicting chain and the full set each requires. The
status-lifecycle findings from those chains are withheld in its favour; findings of every
other kind on that document are unaffected.

**Mutation layer.** The finalization walk builds a referrer map once per invocation through
a narrow API over the validator's index, and reads upstreams through the shared helper
rather than its own scalar read. Traversal becomes a worklist with a visited set. Before
transitioning any ancestor, the walk consults the referrer map: a non-terminal document
outside the set this walk retires blocks the transition, which is reported as a skip
carrying the blocking documents and their statuses. The walk continues; the exit code is
unaffected.

**Parent layer.** Both parents accept `--upstream <path>` parsed at setup before slug
validation, canonicalized and bounds-checked, with basename enforcement against the chain
head's type. The value is recorded in the parent's state under a conditional field, absent
when no upstream was supplied, and re-validated on resume with a defined outcome when it no
longer resolves. Both head children gain the same flag, so the parent passes slug and
upstream separately and the child's own slug derivation stops being driven by the upstream's
name. The pre-authoring notice fires from the chain proposal when the head child will author
a new head-altitude artifact and no upstream was supplied.

## Implementation Approach

**Two sequencing edges are load-bearing and were found only at cross-validation.**

The parsing change must land before the finalization change. The finalization walk is being
routed through the shared upstream reader; landing it first would wire it to string surgery
that the parsing change deletes, and the two would have to be reconciled twice.

The evaluation restructure must land before the conflict diagnostic. The conflict check is a
consumer of the obligation map and the root-versus-member repair is a branch inside its
builder; neither exists until the map does.

**One repair runs opposite to the obvious direction.** The requirements table has one cell
that disagrees with its neighbours, and the instinct is to normalize it to match. That is
backwards: the odd cell is the one encoding correct member semantics, and normalizing it
would spread a live false positive rather than remove it. The repair generalizes the odd
cell's semantics to the others, conditioned on position. Anyone reading the evaluation
decision without the conflict decision will get this wrong, which is why it is stated here
rather than left in a research artifact.

**Phasing.** Parsing and normalization first, since three consumers depend on it. Evaluation
restructure second, as the largest single change and the one the conflict work needs.
Conflict diagnostic third, with the root-versus-member repair as its first commit rather
than a follow-up. Finalization fourth. The parent and child contract changes are independent
of all four and can proceed in parallel, with one constraint carried from the requirements:
the conflict diagnostic must be in place before the upstream-recording work ships, because
recording consumed upstreams makes concurrent chains under one parent more common, and that
is the shape the diagnostic exists to catch. That constraint belongs in the plan's
dependency graph, not in a requirement — it constrains the work rather than the software.

**Testing.** Sequence coverage stays out of the cross-implementation parity corpus. The
parity baseline needs re-establishing rather than assuming, because the parsing change is
what makes a sequence-valued fixture possible in the first place. Corpus invariance is
verified against every repository the change is tested against, before and after, in both
modes.

## Security Considerations

The parent flag is the first author-supplied value either parent accepts that is not derived
from a validated topic slug, and the parents' security contract requires that an addition of
author-input handling re-state the interpolation contract explicitly rather than silently
broaden the surface. The flag's value is canonicalized and rejected if it resolves outside
the repository working tree, which closes the symlink and traversal surface that would
otherwise let arbitrary filesystem content be read into a document destined for a public
commit. It is never interpolated into an emitted shell command without that validation, and
it does not enter the positional slot whose regex is the parents' existing guard.

The write-target set stays closed and enumerable. The supplied upstream is a read target
only — it is recorded and handed to a child, never written to — so no new path can become a
write destination through this change.

The finalization change reduces a security-adjacent risk rather than adding one: it prevents
a mutation that strands references, which is a correctness and auditability failure rather
than an access-control one.

The validator changes introduce no new input surface. The parser accepts YAML it already
parsed and previously discarded; making a discarded value visible does not widen what the
tool reads.

One residual is named rather than hidden: when a corpus cannot be indexed, the referrer map
cannot be built and the retirement guard cannot run. Failing closed would break existing
tests that the requirements forbid changing, so the walk fails visibly open — it proceeds
and records on each transition node that the guard did not run. This is the design's only
deliberate safety compromise, and the plan carries a test asserting the note appears.

## Consequences

**Positive.** Three guarantees become structural: reader agreement is enforced by there
being one reader, duplicate findings become unconstructible rather than removed afterwards,
and both validator modes agree because one function produces both. A live false positive is
removed — the validator stops demanding a live ROADMAP be deleted when one feature beneath
it finishes. The finalization walk stops producing the class of damage that left five
dangling references in this repository. Two head children lose a defect unique to them:
they are the only document-emitting children that conflate where an upstream is with what
the produced document is called.

**Negative.** The evaluation restructure is the largest change and touches the module every
lifecycle finding flows through, so its regression surface is the whole corpus rather than
one check. A `upstream: |` block-scalar value stops half-working, which is a behavior
removal even though no document uses it. The conflict diagnostic reports rather than
resolves — an author with genuinely conflicting consumers is told to fix the lineage, not
given a status that satisfies everyone. The parent half now changes four skills rather than
two, because the hand-off cannot work without the children accepting the flag.

**Mitigations.** Corpus invariance is verified before and after against every repository in
the test set, in both modes, which is what catches an evaluation regression. The two
sequencing edges are encoded in the plan's dependency graph rather than left to memory. The
root-versus-member repair ships as the conflict work's first commit, so the false positive
cannot be spread by a partial landing. The un-indexable-corpus compromise is recorded on the
node and asserted by a test rather than left for someone to discover.
