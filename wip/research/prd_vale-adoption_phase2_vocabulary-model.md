# Lead: vocabulary configuration model

## Findings

### 1. Per-repo config precedent: nine headers, one reader, no shared machinery

shirabe has one documented resolution stack and nine convention headers riding
on it. The canonical enumeration is `references/fixes/claude-md-conventions.md`,
which lists the headers and states the independence rule (lines 79-83):

> Each header is independent. A repo may declare any subset; absent
> headers fall through to their defaults (Public visibility, Tactical
> planning, etc.). FC-CONVENTIONS only fires for the Release Notes
> Convention header today; the other headers have their own validators
> or are defaulted silently.

The headers, with what reads each one:

| Header | Read by | Default | Precedence stated where |
|---|---|---|---|
| `## Repo Visibility: Public\|Private` | Rust **and** every skill | `private` | `crates/shirabe-validate/src/visibility.rs:70-101` |
| `## Planning Context: Strategic\|Tactical` | skills only | Tactical | `references/fixes/claude-md-conventions.md:56-58` |
| `## Execution Mode: auto\|interactive` | skills only | `interactive` | `skills/roadmap/SKILL.md:140-141` and six sibling SKILL.md files |
| `## Roadmap Issues: optional\|required` | skills only | `optional` | `skills/roadmap/SKILL.md:146-164` |
| `## Default Scope: <scope>` | skills only | unstated | `references/fixes/claude-md-conventions.md:59-60` |
| `## PR Grouping Policy: <policy>` | skills only | `coarsest-legal` | `CLAUDE.md` (shirabe root), `skills/scope/SKILL.md:133-135` |
| `## Reviewability Ceiling: <value>` | skills only | `default` | `CLAUDE.md` (shirabe root) |
| `## Release Notes Convention: <path>` | validator (presence only) | none | `crates/shirabe-validate/src/checks.rs:3167-3208` |
| `## Artifact Lifecycle: per-skill` | skills only | n/a (pointer) | `CLAUDE.md` (shirabe root) |

**The mechanism is ad hoc per header, not uniform.** Exactly one header has a
compiled implementation, and it is the visibility header. `visibility.rs:70-101`
is the whole of shirabe's real per-repo config machinery:

```rust
// 1. Walk up from the doc's directory; the first CLAUDE.local.md / CLAUDE.md
//    that carries a `## Repo Visibility:` header wins. A CLAUDE.md without
//    the header does not stop the walk (a nested workspace layout keeps the
//    per-repo header below workspace-level CLAUDE.md files that lack it).
let mut dir = canonical.parent();
while let Some(d) = dir {
    for name in ["CLAUDE.local.md", "CLAUDE.md"] {
```

Four properties that matter here are already solved in that function and
nowhere else: the ancestor walk from the file under check, `CLAUDE.local.md`
winning over `CLAUDE.md` in each directory, a header-less `CLAUDE.md` not
halting the walk, and a fail-safe default. Its module docstring
(`visibility.rs:3-17`) names the reason it exists at all:

> Mirrors the idiom every shirabe skill uses to decide whether a doc's
> owning repo is Public or Private [...] so the CLI's auto-detection and the
> skills' hand-detection resolve visibility the same way and cannot drift.

Every other header is resolved by prose instruction inside a skill: grep the
header, take the value after the colon. `skills/roadmap/SKILL.md:146-153` is
representative and explicit that no code is involved:

> read CLAUDE.md's `## Roadmap Issues:` header the same way `## Execution
> Mode:` is read -- grep the header, take the value after the colon. Resolve
> to `required` only when the value is exactly `required` [...] The validator
> never reads this header; it's a skill-only preference.

Two consequences. First, a skill-only header is invisible to `shirabe validate`
and to CI. Second, the one header the validator does touch, Release Notes
Convention, is unreachable in practice: `check_claude_md_conventions` gates on
`basename != "CLAUDE.md"` (`checks.rs:3170`), but `detect_format`
prefix-matches eight artifact types and returns `None` for `CLAUDE.md`
(`crates/shirabe-validate/src/formats.rs:248-260`), and `main.rs:604-607` does
`None => continue`. Confirmed live in this worktree:

```
$ ./target/release/shirabe validate --format human CLAUDE.md
All checks passed.
```

So the honest statement of precedent: **shirabe has one working per-repo config
reader, it reads one scalar header, and it is the visibility header.** The
`flag > CLAUDE.md-header > default` stack is a documented convention that eight
of nine headers implement by asking a model to grep.

### 2. List-shaped config: exactly one instance, and it is not a header

**No CLAUDE.md header carries a list.** Every one of the nine is a single
scalar or a single path. There is no config file of any kind: grepping
`crates/` for `.shirabe`, `shirabe.toml`, `shirabe.yml`, `shirabe.yaml`
returns nothing. shirabe reads no per-repo config file today.

The one list-shaped per-adopter input is `--custom-statuses`, a YAML map passed
as a CLI string (`crates/shirabe/src/main.rs:230-232`) with a 64 KiB cap
(`main.rs:1379-1381`), surfaced to adopters as the sole input of the reusable
workflow (`.github/workflows/validate-docs.yml:19-23`):

```yaml
      custom-statuses:
        description: 'YAML map of schema version to custom status values (optional)'
```

Its semantics are the direct answer to this lead's question, and they are
**replace**. From `crates/shirabe-validate/src/doc.rs:12-15`:

> Format schema version -> replacement status enum. When present for
> a schema version, the custom list replaces (does not extend) the
> format's canonical valid statuses.

Implemented at `checks.rs:93-96` and locked by a test named for the behavior:

```rust
let valid_statuses: &[String] = match cfg.custom_statuses.get(&spec.schema_version) {
    Some(custom) => custom,
    None => &spec.valid_statuses,
};
```

```rust
fn check_fc02_custom_statuses_replace_canonical() {   // checks.rs:3489
```

Replace is defensible there for a reason that does not carry over. A status
enum is a small closed set describing one repo's own lifecycle, and shirabe
does not ship a stream of new statuses that an adopter would want to inherit.
The writing-style rules are the opposite: open-ended and explicitly meant to
keep arriving (`docs/briefs/BRIEF-vale-adoption.md:98-99`, "Every repo that
adopts shirabe gets the changed rule on its next run").

Also note where that one list lives. It reaches CI only. It never reaches the
drafting agent, a local `shirabe validate` run, or the pre-commit hook
scaffolded by `shirabe install-hooks`, and adopting it costs every adopter an
edit to their own workflow file.

**A vocabulary declaration therefore introduces a new config shape on two
axes at once: list-valued rather than scalar, and durable-in-repo rather than
passed per-invocation.** Nothing in shirabe does both today.

### 3. Extend vs replace, costed

First, a distinction the framing hides. "Adopter vocabulary extends or replaces
shirabe's rules" is two questions stacked, and they take opposite answers:

- **The rule set layer.** Does the adopter inherit shirabe's rules and their
  future edits, or supply their own?
- **The vocabulary layer.** Does an adopter's term list build on shirabe's
  own (`tier`, `journey`), or stand alone?

The BRIEF answers the second one already, at lines 109-110: "shirabe needs this
for `tier` and `journey`; every adopter has its own list, and the capability is
the same one." That makes shirabe a consumer of the feature rather than a
privileged case, which means shirabe's own terms are shirabe's repo-local
declaration and must **not** ship as a global exemption. If they did, every
adopter would silently stop getting `tier` flagged while the rulebook still
bans it. So the vocabulary list is per-repo and standalone, while the rule set
is inherited. Conflating the layers is the trap.

With that split, the models cost out as follows.

**Extend (adopter adds suppressions; shirabe's rules otherwise apply).**

Gains: the adopter's declaration is short. shirabe's own would be two entries.
Rule fixes and new rules arrive on the next run with no adopter action, which
is the User Outcome at BRIEF lines 95-99 and the survives-upgrade property at
line 169. shirabe stays the single source, which is the whole point of the
feature. The declaration is also cheap to review: a reader of an adopter's repo
sees two words, not a rulebook.

Losses: the adopter can suppress *terms* and nothing else. A rule they reject
on principle rather than on vocabulary has no lever. The concrete case is
already in scope for this feature: the frequency rules (BRIEF lines 181-183).
An adopter whose house style uses em dashes deliberately cannot express that as
a word list. They can only turn the whole thing off.

The "off" question deserves care, because today it has a bad answer. Adopters
consume checking through `validate-docs.yml`, which exposes one input,
`custom-statuses`. It does not expose `--check`. So an adopter's current rule
control is: call the workflow and get every check, or stop calling it. Extend
does not take anything away, but it also does not fix the coarseness.

What happens when shirabe adds a banned word colliding with an adopter's
domain: under extend the repair is one line, but the adopter learns about it
reactively, from noise in their own PRs after an upgrade. shirabe already has
the staging mechanism for exactly this, and it is not a config knob. It is the
severity seam at `crates/shirabe-validate/src/validate.rs:69-98`:

> **Promotion seam.** FC07-FC15 and FC-CONVENTIONS ship notice-level for
> v1; remove the corresponding arm from this match to promote the check
> from notice to error in a single-line diff.

A new rule ships as a notice, adopters see it without being blocked, they
declare their terms, and only then does it get promoted. That pattern is
established and it is the answer to the collision-on-upgrade cost.

Can an adopter ever remove a shirabe rule they disagree with? Under pure
extend, no. That is the model's real limitation, and it is why pure extend is
not sufficient on its own.

**Replace (adopter supplies its own rule set wholesale).**

What breaks is the feature's reason for existing. The BRIEF diagnoses the
current state at lines 48-50:

> Adopters compound the problem rather than causing it: a repo
> that uses shirabe has no way to read the rulebook mechanically, so any
> local restatement becomes a fourth copy that shirabe cannot keep in sync.

And names the failure again from the adopter's side at lines 165-167: "their
only options are to disable the check or to fork the rulebook, and the second
creates a copy shirabe cannot keep in sync." Replace makes that fork the
supported path. shirabe still gets to evolve the rulebook, but a replacing
adopter inherits nothing: no new rules, no fixes, no corrections to a rule that
was wrong. So yes, replace is fork-the-rulebook with extra steps, and the extra
step is that shirabe now owns and versions the fork's file format, which means
it can never restructure the rules without an adopter migration.

Replace has one honest advantage: it is the only model under which an adopter
with a genuinely different house style is well served, and it needs no new
concept beyond the one `custom_statuses` already established.

**Third model: inherit the rules, declare vocabulary, override named rules.**

The evidence supports this, and most of it is already built.

shirabe already has rule identity. Every check has a stable code, and the codes
are a validated closed set at `validate.rs:150-176`:

```rust
pub fn is_known_check_code(code: &str) -> bool {
    matches!(code, "SCHEMA" | "FC01" | ... | "FC16" | "FC-CONVENTIONS" | "R6" | ... | "R9")
```

with typo rejection wired as a tool error rather than a silent pass
(`main.rs:526-534`):

> // Reject an unknown --check code up front: a typo like `FC1` must be a
> // tool error, not a silent clean pass.

shirabe already has per-rule severity as a first-class property, resolved at a
single point (`validate.rs:127-135`), plus a context axis in `ReviewPosture`
that flips draft-tolerable codes between notice and error. And it already has
per-check selection, contracted publicly in
`docs/guides/multi-consumer-cli-contract.md` under "Per-check selection":

> - Selection drives both what is reported and the outcome, so selecting
>   only a check that passes is a clean run even if an unselected check would
>   have failed.

What is missing is any *per-repo, durable* input into rule identity or
severity. `--check` is a per-invocation whitelist, not a preference. The one
existing per-rule suppression is bespoke: `Config.allow_untracked_acs`
(`doc.rs:19-24`) is a dedicated boolean plus a dedicated CLI flag plus a
dedicated env var, for one check:

> When `true`, the chain-aware L06 outline-AC completeness check
> is suppressed (returns no findings). Default `false`. [...]
> L01-L05 are unaffected -- only L06 honors this setting.

That is precedent for the *need* and an anti-pattern for the *shape*. Repeating
it once per rule is how you end up with forty flags.

The third model costs: one new config surface instead of zero, and a decision
about whether adopter-side rule disabling is in scope at all (see Open
questions). Its gain is that the two knobs cover the two distinct adopter
complaints. "This word is my domain vocabulary" is a vocabulary problem.
"This rule is wrong for my house style" is a rule problem. Vocabulary
suppression cannot solve the second, and rule disabling is far too blunt for
the first, since disabling the word rules to save `tier` also loses the other
45 words.

### 4. What the validator already does about per-check control

Summarized above under the third model; the load-bearing facts, with paths:

- **Check selection**: `--check <code>`, repeatable and comma-splittable
  (`main.rs:213-219`), filtering at `main.rs:642-644`, contracted in
  `docs/guides/multi-consumer-cli-contract.md`. Per-invocation only. Not
  exposed through `validate-docs.yml`, so adopters do not have it.
- **Code registry**: `is_known_check_code` (`validate.rs:150-176`), unknown
  code is exit 1.
- **Severity classification**: `is_intrinsic_notice` (`validate.rs:83-98`) is
  the documented single-line promotion seam; `posture_class`
  (`validate.rs:110-115`) adds the draft/ready axis; `effective_severity`
  (`validate.rs:127-135`) is the single resolution point that both the JSON
  envelope and the exit-code roll-up read, "so they can never disagree."
- **One per-rule suppression, hardcoded**: `allow_untracked_acs` for L06.

This is strong precedent for the shape of a rule-control feature: stable codes,
validated inputs, one resolution point, and severity as an axis distinct from
enablement. It is **not** precedent for per-repo persistence, because none of
it is per-repo. The reusable surface to borrow for that is the visibility
ancestor walk, not the `--check` flag.

One live check worth recording, since it grounds the collision the PRD is
about. Run in this worktree against the BRIEF that describes the problem:

```
$ ./target/release/shirabe validate --format human docs/briefs/BRIEF-vale-adoption.md
docs/briefs/BRIEF-vale-adoption.md:55 notice [FC10] writing-style banned word "tier" ...
[5 findings, all "tier"]
0 error(s), 5 notice(s) -- clean
```

FC10's list is seven words (`checks.rs:2551-2559`), of which the collision word
is the first entry. `journey` is not on FC10's list at all, only on the
47-word SKILL.md table, which no mechanical check reads. Note also that the
reported lines are body-relative, not file-absolute (file line 74 reported as
55), which is the frontmatter-offset defect the BRIEF puts out of scope as a
defect but in scope as a property.

### 5. Precedent outside shirabe

Four shapes exist in comparable tools, named here without recommending any.

- **Vale** separates the two layers cleanly. Rule sets are additive:
  `BasedOnStyles` is a list, and across layered config files "multi-valued
  settings (like `BasedOnStyles`) are merged together, while single-valued
  settings (like `MinAlertLevel`) are overridden." Per-rule control is a
  key-value override in the same section, `Style.Rule = NO` to disable or
  `Style.Rule = suggestion|warning|error` to change severity. Vocabulary is a
  third, separate mechanism: a `Vocab` directory holding `accept.txt` and
  `reject.txt`, where accepted entries are "added to every exception list in
  all styles listed in `BasedOnStyles`", so they suppress across rules rather
  than per rule, and are simultaneously enforced for casing via a generated
  `Vale.Terms` rule. `reject.txt` is the inverse: entries feed a generated
  `Vale.Avoid` existence rule. So Vale is extend-at-the-rule-set-layer,
  standalone-at-the-vocabulary-layer, with selective disable and severity
  override on top. That is the same split this lead arrives at from shirabe's
  own evidence.
  (https://docs.vale.sh/keys/vocabularies.md, https://docs.vale.sh/topics/.vale.ini)
- **cspell**: `words` extends the project dictionary, `ignoreWords` suppresses
  without adding, `flagWords` is the reject direction, and `import`/`extends`
  layers a shared config that local settings add to. Extend by default,
  with an explicit suppress-only channel distinct from the add channel.
- **eslint**: shared config is spread or extended, then `rules` entries
  override individual rules by name to `"off"`, `"warn"`, or `"error"`. Same
  severity-and-enablement axis as Vale, addressed by stable rule id.
- **markdownlint**: `"default": true` then per-rule `false` in config, plus
  inline `<!-- markdownlint-disable MD013 -->` for a local escape, plus MD044
  (proper-names) whose config value is itself a list of terms, which is a
  vocabulary declaration attached to one rule rather than global.

The shapes worth naming for the PRD: rule-set inheritance that merges rather
than replaces; per-rule enable/disable by stable id; per-rule severity
override; a global suppress list separate from both; a reject list as the
inverse of the suppress list; and a file-local inline escape.

## Implications for requirements

Stated mechanism-neutrally. Each is grounded in a finding above.

1. **An adopter's vocabulary declaration must not detach them from shirabe's
   rules.** A repo that declares terms of art must still receive later rule
   additions, corrections, and removals without editing anything. Replace
   semantics at the rule-set layer institutionalize the copy problem the BRIEF
   exists to solve (BRIEF lines 48-50, 165-167), and shirabe's one existing
   replace-shaped config (`custom_statuses`) is replace for a reason that does
   not transfer.

2. **A repo's declared vocabulary applies to that repo only.** shirabe's
   `tier` and `journey` must be declared the same way an adopter declares
   theirs, and must not leak to adopters as a built-in exemption. The BRIEF
   already commits to this at lines 109-110; the PRD should state it as a
   requirement because it is the difference between the feature working and
   quietly disabling a rule everywhere.

3. **The declaration must be resolvable from the file being checked, in the
   repo, with no CI wiring.** It has to reach the drafting agent, a local
   `shirabe validate`, the pre-commit hook, and CI. A workflow input reaches
   only the last of those and costs every adopter a workflow edit
   (`validate-docs.yml:19-23`). The resolution behavior to match is the one
   `resolve_doc_visibility` already implements: walk up from the file, first
   declaration wins, a declaration-less file does not stop the walk, and there
   is a documented default when nothing is found.

4. **The declaration must hold a list that outgrows one line.** shirabe's is
   two terms; an adopter's may be dozens. Every existing per-repo declaration
   in shirabe is a single scalar, so this is a new shape and the PRD should say
   so rather than assume the header convention absorbs it. Whether the list
   sits inline or behind a path is a DESIGN choice; note that
   `## Release Notes Convention: <path>` already establishes a path-valued
   declaration, so both fit the convention.

5. **Suppression must be term-scoped, not rule-scoped.** Suppressing `tier`
   must not disable the word rules, or the adopter loses the other 45 terms to
   save one. This is what separates the vocabulary knob from anything built on
   `--check`.

6. **A new rule that collides with an adopter's vocabulary must not arrive
   blocking.** shirabe already has the mechanism and it is not a config knob:
   new checks ship notice-level and get promoted in a one-line diff after the
   corpus is clean (`validate.rs:69-98`). The PRD should require that staging
   discipline for rule additions, because it is what makes inherit-by-default
   tolerable for adopters.

7. **The PRD should state whether an adopter can reject a rule, and today's
   answer is honest either way.** Vocabulary suppression cannot express "this
   rule is wrong for us", and the frequency rules are the case where an adopter
   will want to. Today the only adopter-facing lever is to stop calling the
   reusable workflow. The PRD should either put per-rule adopter control in
   scope or record that it stays out and that the coarse lever remains the
   answer. Silence here reads as a promise the vocabulary knob cannot keep.

8. **If per-rule control is in scope, it should reuse the existing seams rather
   than invent a surface.** Rule identity, a validated code registry, a single
   severity resolution point, and a context axis all exist
   (`validate.rs:110-176`). The shape to avoid is another
   `allow_untracked_acs`: a bespoke flag per rule (`doc.rs:19-24`).

9. **Whatever the declaration's shape, the value must be read by the same
   resolution for agents and for the validator.** The single-source outcome
   (BRIEF lines 95-99) fails if the vocabulary is honored at validate time but
   invisible while drafting, or vice versa. `visibility.rs:3-17` states this
   requirement for the visibility header in its own words and is the only place
   in the repo where a header is resolved identically by both consumers.

## Open questions

1. **Does the vocabulary knob get a reject direction?** Vale and cspell both
   pair the suppress list with an add-banned-terms list. The BRIEF asks only
   for suppression (line 184-187). Adding the inverse is nearly free once a
   config surface exists and adopters will ask for it, but it is scope growth
   and it changes the feature from "stop firing on my words" to "shirabe's
   rules plus mine", which is a different product claim. A human should decide.

2. **Is adopter-side rule control in scope?** The BRIEF puts "Whether findings
   block or report, and at which severity" in scope (line 190), but that reads
   as shirabe's decision about its own rules, not an adopter-facing knob. Given
   that the frequency rules are the ones an adopter is most likely to reject on
   principle, and that their only current recourse is to stop calling the
   workflow, this needs an explicit yes or no rather than an inference.

3. **What does an adopter get on day zero with no declaration?** The BRIEF
   measures raw word-rule precision at 1.7%, rising to about 16% once domain
   terms are excluded (lines 68-70), which means vocabulary suppression is
   doing most of the precision work. An adopter who never writes a declaration
   gets the unsuppressed rate under every model considered here. Whether that
   is acceptable, and whether the word rules should therefore default to
   report-only until a repo has declared its terms, is a product call.

4. **Does shirabe's own declaration ship in shirabe's repo or in the rule
   source?** Recommendation 2 above says repo-local, following the BRIEF. It is
   worth a human confirming, because the alternative (shipping `tier` and
   `journey` as built-in exemptions) is simpler and is what someone will
   propose in review.

5. **Is `--custom-statuses`'s replace semantics something to align with or to
   diverge from deliberately?** This lead concludes diverge, for the reasons in
   Finding 3. If the PRD diverges, it should say so, because a reader who knows
   the codebase will notice that shirabe's only precedent for adopter-supplied
   lists points the other way.

## Summary

shirabe's per-repo config precedent is thinner than the `flag >
CLAUDE.md-header > default` convention makes it look: nine convention headers,
all scalar, of which exactly one (Repo Visibility) has a compiled reader
(`visibility.rs:70-101`) and eight are resolved by asking a skill to grep. There
is no config file, no list-valued header, and one list-shaped adopter input
overall, `--custom-statuses`, which is documented and tested as **replace, not
extend** (`doc.rs:12-15`, `checks.rs:3489`) and reaches CI only. Extend is the
right answer at the rule-set layer because replace is the copy-that-drifts
problem the BRIEF exists to end, while the vocabulary list itself must be
standalone per repo so shirabe's `tier` and `journey` never become a global
exemption; the evidence in `validate.rs:110-176` (stable codes, validated
registry, single severity resolution point, draft/ready axis) says a later
per-rule enable/severity control should reuse those seams rather than invent a
surface, and the one bespoke per-rule suppression already in the tree
(`allow_untracked_acs`) is the shape not to repeat.
