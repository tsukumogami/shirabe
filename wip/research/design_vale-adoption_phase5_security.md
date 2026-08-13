# Phase 5 Security Review

Target: `docs/designs/DESIGN-vale-adoption.md`
Upstream: `docs/prds/PRD-vale-adoption.md`
Binary used for every empirical claim: `target/release/shirabe` (pre-change tree)

## Verdict

findings requiring design changes

## Findings

### F1. The `None` arm makes two of shirabe's own files a hard CI failure (High)

**Surface.** `FormatSpec` becomes optional in `validate_file`; prose checks run on
the `None` arm so instruction files get checked.

**What the code does today.** `crates/shirabe/src/main.rs:604-607` gates on format
detection *before* reading the file:

```rust
let spec = match detect_format(basename(path)) {
    Some(s) => s,
    None => continue,
};

let doc = match parse_doc(path) { ... }
```

`detect_format` (`crates/shirabe-validate/src/formats.rs:248`) matches on filename
prefix only, so `SKILL.md`, `CLAUDE.md`, `README.md` and every source file return
`None` and are never opened. Reaching the `None` arm requires deleting that
`continue`, which means `parse_doc` now runs on every path the caller passed.
`parse_doc` returns `ParseError::Yaml` on frontmatter saphyr rejects, and
`main.rs:610-622` maps that to `ValidateOutcome::ToolError` — exit 1.

**Concrete failure.** I scanned every non-fixture file in the repo for a leading
`---` whose frontmatter a YAML parser rejects. Exactly two hit, and both are
skill instruction files:

```
files starting with '---': 162
files whose frontmatter a YAML parser rejects: 2
   skills/review-plan/SKILL.md   | mapping values are not allowed here
   skills/writing-style/SKILL.md | mapping values are not allowed here
```

Verified against the real binary by copying each to an artifact-prefixed name so
the current gate lets it through:

```
$ shirabe validate --format human -- /tmp/DESIGN-ws.md /tmp/DESIGN-rp.md
DESIGN-ws.md:1 error could not read file: yaml error: mapping values are not
  allowed in this context at byte 125 line 2 column 106
DESIGN-rp.md:1 error could not read file: yaml error: mapping values are not
  allowed in this context at byte 148 line 3 column 44
2 error(s), 0 notice(s) -- tool-error
EXIT=1
```

The cause is an unquoted `:` inside the `description:` scalar (`skills/writing-style/SKILL.md:3`
contains `whenever: (1) the user asks...`). This is valid Claude Code skill
frontmatter and there is no reason for a skill author to change it.

`.github/workflows/validate-docs.yml:88-99` computes `$FILES` from
`git diff --name-only --diff-filter=ACMR` with no extension filter and passes it
positionally, so any PR that touches `skills/writing-style/SKILL.md` sends it to
`validate`. Phase 6 of the design's own Implementation Approach ("Reduce SKILL.md
to guidance plus a pointer") edits exactly that file. The PR that implements this
design fails its own CI with a tool error, and the failure is not fixable by
rewording — it is a parse refusal.

Note the sharpest irony: Decision 1 rejects Vale partly because "two of them carry
frontmatter its YAML parser rejects" and calls shipping a surface that reports
success for files it could not read "precisely what R12a exists to end." The
chosen design inherits the same two files and the same parser class, and converts
them from a silent skip into a hard stop.

**Covered by the existing Security Considerations?** No. The section discusses
rule-source parsing and vocabulary input; it does not consider what reaching the
`None` arm does to the file set the parser sees.

**Required mitigation.** The design must state the `None`-arm admission rule
explicitly: which paths reach `parse_doc`, and what a parse failure on a
non-artifact file means. A parse failure on a file that carries no schema and was
never claimed by a format must not be a tool error — the prose family should fall
back to raw-line scanning (the body the scoper wants is already recoverable via
`String::from_utf8_lossy`; see `frontmatter.rs:294`). Add a pinned test over both
real SKILL.md files.

### F2. The rule file's runtime location is unspecified, and the "not adopter-controlled" claim rests on it (High)

**Surface.** `skills/writing-style/rules.yaml`, "parsed with `saphyr` at
enforcement time."

**What the design asserts.** Security Considerations: "The rule file is shirabe's
own, arriving at the same commit as the binary, so it is not an adopter-controlled
input."

**What the design never says.** How the binary finds the file at runtime.
`.github/workflows/validate-docs.yml:38-77` checks the caller repo out at the
workspace root, checks shirabe out into `.shirabe-src`, builds, and installs the
binary to `/usr/local/bin/shirabe`. The validate step then runs with CWD = the
*caller's* repo root. Every resolution strategy has a failure mode the design does
not address:

- **CWD-relative.** `skills/writing-style/rules.yaml` does not exist in an adopter
  checkout. Either the run reports success having loaded no rules — a fourth silent
  success, the failure mode the Decision Drivers call worse than the gap being
  closed — or every adopter PR exits 1. And if an adopter repo *does* carry that
  path, the rules become adopter-controlled, flatly contradicting the security
  claim. (koto and tsuku already carry `plugins/*/skills/` trees; the collision
  path is not exotic, only currently unoccupied.)
- **Binary-relative.** `/usr/local/bin/../skills/` does not exist either.
- **`include_str!`.** Forbidden by R1 (rules read at enforcement time, not baked
  into the binary) — the stated reason the design exists.
- **A flag or env var.** An adopter workflow edit, forbidden by R18.

The crate has no precedent to borrow: `grep -rn "include_str!\|CARGO_MANIFEST_DIR"`
over `crates/` finds `env!("CARGO_MANIFEST_DIR")` only in `tests/`, and
`include_str!("checks.rs")` only in a self-referential test at `checks.rs:5195`.

**Covered?** The section asserts the conclusion without the mechanism.

**Required mitigation.** Name the resolution algorithm in Solution Architecture,
and state what happens when the file is absent or malformed. The load result must
be a first-class outcome: a missing or unparseable rule source is a tool error
(exit 1) naming the resolved path, never a clean run over zero rules. If the
resolved path can ever fall inside a repository under check, the "not
adopter-controlled" sentence has to be deleted and replaced by whatever the real
trust boundary is.

### F3. The ancestor walk crosses the repository root; R10 is not satisfied structurally (High)

**Surface.** `resolve_claude_md_header(path, key)`, generalized from
`resolve_doc_visibility`.

**What the code actually does** (`crates/shirabe-validate/src/visibility.rs:70-101`):

```rust
let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
let mut dir = canonical.parent();
while let Some(d) = dir {
    for name in ["CLAUDE.local.md", "CLAUDE.md"] {
        if let Ok(contents) = std::fs::read_to_string(d.join(name)) { ... }
    }
    dir = d.parent();
}
```

Canonicalization happens *before* the walk and applies to the doc path only. There
is no `.git` boundary, no repo-root stop, and no canonicalization of the CLAUDE.md
files the walk finds. The walk runs to `/`.

**Attack 1: an ancestor above the repo root supplies the value.** Proven with the
shipped binary using the existing visibility header (the same walk):

```
childrepo/CLAUDE.md      -> "# childrepo\n\nno visibility header here"
workspace/CLAUDE.md      -> "## Repo Visibility: Private"
$ shirabe validate --check R9 -- workspace/childrepo/docs/COMP-x.md
All checks passed.   exit=0
```

The private-only gate passed on a repo that declared nothing, because a directory
above its root declared for it. The decision-3 report claims first-declaration-wins
"stops an adopter's effective vocabulary from depending on directories above their
repo root that they may not control" (`wip/design_vale-adoption_decision_3_report.md:290`).
It does not. First-hit-wins only stops *merging*; a repo that declares nothing
still inherits from above.

This is live in this very workspace. Walking up from a shirabe doc:

```
/home/dgazineu/dev/niwaw/tsuku/tsuku+vale_or_not-33480214/CLAUDE.md   <- exists
/home/dgazineu/dev/niwaw/tsuku/CLAUDE.md                              <- exists
```

Both sit above `public/` and above every private sibling. The workspace CLAUDE.md
states that a private overlay carries its own CLAUDE.md fragments. A
`## Prose Vocabulary:` in either file suppresses findings in the public shirabe
repo, which is R10's second sentence ("A term suppressed in one repository SHALL
NOT be suppressed in another") violated by the mechanism the design chose to
satisfy it structurally.

**Attack 2: a symlinked CLAUDE.md reads outside the repo.** `read_to_string`
follows symlinks and the target is never canonicalized or bounds-checked. Proven,
discriminating baseline included:

```
public/repo/docs/COMP-x.md, no CLAUDE.md -> path inference says public
  => [R9] Comp docs are private-only; visibility=public   exit=2

ln -s <outside>/SECRET-CLAUDE.md public/repo/CLAUDE.md   (Private header)
  => All checks passed.                                   exit=0
```

A single symlink committed to a repository redirects header resolution to
arbitrary content anywhere the process can read. For visibility this is a gate
bypass; for vocabulary it is a suppression bypass.

**Attack 3 (negative result, worth recording).** Walk cost is not a problem. A
400-level-deep tree resolved in `wall=0.03s rss=4352KB`. `..` components are
resolved by `canonicalize` before the walk begins, so `docs/../docs/X.md` walks the
same ancestors as `docs/X.md`. Filesystem root terminates the loop via
`Path::parent() == None`. These three the design's Security Considerations gets
right.

**Covered?** Partly, and the covered part is stated too strongly. "The ancestor
walk canonicalizes before resolving and stops at the filesystem root" is accurate
but describes protection that does not exist — stopping at `/` is the *problem*,
not the mitigation. The symlink case and the above-the-repo-root case are absent.

**Required mitigation.** Three changes:

1. Bound the walk. Stop at the first directory containing `.git` (or at the
   filesystem root, whichever comes first) so "repo-local" in R10 means the repo.
   Applying this to `resolve_doc_visibility` too is a behavior change and needs to
   be a recorded decision, not a side effect.
2. Reject a `CLAUDE.md` whose canonicalized path escapes the walk root. `read_link`
   / canonicalize the joined path and compare against the bound from (1).
3. State the day-zero consequence in the design: because there is no
   `--vocabulary` flag (unlike `--visibility`, which the reusable workflow always
   passes and which therefore masks this walk in CI), vocabulary has no override
   and always resolves through the walk. CI happens to be safe because a GitHub
   runner's checkout has no CLAUDE.md-bearing ancestors; local development and the
   pre-commit hook are not.

### F4. The finding vector is unbounded, and this design multiplies the rule count (Medium-High)

**Surface.** Word and phrase rules over prose spans; `findings: Vec<ValidationError>`
in `main.rs:598`, accumulated across all files before rendering.

**Measured, current binary, seven rules:**

```
$ ls -la DESIGN-bigline.md          # 10,500,045 bytes, one line
$ /usr/bin/time -v shirabe validate --check FC10 -- DESIGN-bigline.md
  Maximum resident set size (kbytes): 875220     # 875 MB
  Elapsed (wall clock) time: 0:02.43
$ shirabe validate --check FC10 --format json -- DESIGN-bigline.md | jq '.findings|length'
1500000
```

87x memory amplification over input size, from a 10 MB file, with today's
seven-word list. The design takes that list to roughly 47 terms ("the seven words
move into the file first, the other 40 arrive later"), so the same input produces
several times the findings. A 100 MB input reaches the 7 GB ceiling of a standard
GitHub runner. Nothing caps the vector, and `--check` filtering happens *after*
`validate_file` returns the full result, so it does not help.

The per-finding cost is a `ValidationError` with two owned `String`s, one of them
a ~120-byte formatted message repeated per match. The message is constant per rule
and could be interned, but the structural fix is a cap.

**Covered?** No. The section treats denial of service only as "compiling adopter
input as a regex," which the design correctly forbids. The larger denial-of-service
surface is the output side, not the input side, and it exists today.

**Required mitigation.** Cap findings per rule per file (say 50) with a single
"and N more" finding, following the bounded-behavior precedent FC09 already
carries (`checks.rs:5696`, "bounded-over-malformed-input"). State the cap in
Solution Architecture so it is a contract, not an implementation detail.

### F5. Every changed file, not every Markdown file, reaches the parser (Medium)

**Surface.** Same `None`-arm admission gap as F1, different consequence.

`.github/workflows/validate-docs.yml:88-91` filters only fixture directories:

```
FILES=$(git diff --name-only --diff-filter=ACMR ...base...head \
  | grep -vE '(^|/)(evals|tests)/fixtures/' || true)
```

The pre-commit hook is stricter — `main.rs:1225-1229` narrows to `*.md` before
invoking — so the two consumers diverge exactly where it matters. Today the
divergence is harmless because `detect_format` drops everything unrecognized. Once
the `None` arm exists, a PR touching `Cargo.lock`, a `.png`, or `checks.rs` sends
that file to `parse_doc`.

Behavior on a binary input, current binary: `scan_body` calls
`String::from_utf8_lossy` (`frontmatter.rs:294`), so it does not error — it
produces mojibake body lines. I confirmed a PNG-headed file today yields only the
SCHEMA notice at exit 0, which is precisely the arm the design says prose checks
will run above. So under the change it gets prose-checked. Two consequences:
`from_utf8_lossy` expands each invalid byte to a 3-byte replacement character, so
a binary blob costs up to 3x its size in `Vec<String>` *before* F4's amplification;
and `checks.rs` (which literally contains the word list at line 2551) would emit
FC10 notices against its own rule source.

**Covered?** No.

**Required mitigation.** The `None` arm needs an explicit admission predicate.
Extension-based (`*.md` only) is the minimum, and it should live in the CLI rather
than in the workflow so all three consumers inherit it. State it in the design.

### F6. CRLF survives into the body, breaking fence and paragraph detection (Medium)

**Surface.** The ~90-line prose scoper, and the frequency rule's denominator.

`split_lines` (`frontmatter.rs:312-319`) strips only a trailing `\n` and splits on
`'\n'`. The doc comment claims Go `bufio.Scanner` semantics including `\r\n`, but
the implementation does not strip `\r`. Every body line of a CRLF document ends in
a carriage return. Confirmed on a CRLF fixture with an unterminated fence and 5,000
nested blockquote markers:

```
DESIGN-crlf.md:3 notice [FC10] ... "tier"
DESIGN-crlf.md:3 notice [FC10] ... "robust"     <- inside an unterminated ``` fence
DESIGN-crlf.md:4 notice [FC10] ... "leverage"   <- after 5000 '>' markers
exit=2 (from unrelated FC01/FC04)
```

No panic and no hang — the deep blockquote and the unterminated fence are fine
today because FC10 attempts no scoping at all. They will not be fine in a scoper.
Two specific breakages to design against:

- A fence line is `"```\r"`, not `"```"`. A scoper that compares the opening
  fence's info string against the closing one, or that treats anything after the
  backticks as a language tag, sees `\r` as a language tag and never closes the
  fence. The whole rest of the document becomes code and gets excluded — a silent
  under-report, the failure class the Decision Drivers name as the worst outcome.
- A blank line is `"\r"`, not `""`. `line.is_empty()` finds zero paragraph
  boundaries, so a per-paragraph frequency rule's denominator collapses to 1. R7
  requires threshold, denominator, and reporting unit as recorded fields; under
  CRLF the denominator silently becomes the document. That changes whether the rule
  fires, not just how it reports.

**Covered?** No. The section does not discuss input encoding at all.

**Required mitigation.** Normalize line endings once, at the scoper's entry, and
say so in Solution Architecture. Add CRLF fixtures to the corpus comparison — the
"483 of 489" Vale agreement was measured on shirabe's own LF corpus and says
nothing about CRLF.

### F7. Notice registration is fail-open toward error, and adopters are pinned at `@main` (Medium)

**Surface.** Phase 5's frequency rule; `is_intrinsic_notice` in
`crates/shirabe-validate/src/validate.rs:83-98`.

A new check code needs two independent registrations: `is_known_check_code`
(`validate.rs:150`), or `--check <newcode>` is a tool error; and
`is_intrinsic_notice`, or the code ships error-level. The default of omission is
error. `FC16` is the in-tree precedent for a code *deliberately* absent
(`validate.rs:80-82`), so absence reads as intentional to a reviewer and an
accidental omission is invisible in diff review.

The blast radius is stated by the design itself: all three adopters call the
reusable workflow pinned at `@main` and pass no inputs, so whatever merges reaches
them on their next docs PR. R11's own measurements say error level at 3 em dashes
per thousand words fails 92 of shirabe's 124 docs, 47% of koto's corpus, 49% of
niwa's, 20% of tsuku's. A one-line registration omission is a three-repository
outage with no staging step between merge and effect.

**Covered?** No — this is the design's own "silent success is the failure mode"
driver pointed at its own registration surface. Decision 4 counts seventeen
registration touchpoints as an argument against Option A while adding two more of
the same kind.

**Required mitigation.** A test that asserts every code the prose family can emit
is in both sets and resolves to `Severity::Notice` under both postures. Name it in
the design as a merge precondition for Phase 5, alongside the R12 promotion issue
the design already requires.

### F8. Prose checks above the schema gate also land above the R9 private-only short-circuit (Low-Medium)

**Surface.** "Prose checks run on both arms, above the schema gate."

In `validate_file` (`validate.rs:183-196`) the schema gate is step 1 and the R9
private-only gate is step 1a, below it. Placing prose checks above the schema gate
places them above R9 as well. R9's short-circuit is documented as deliberate:

```rust
// 1a. Visibility gate (R9): private-only formats short-circuit before FC
// checks when visibility is not "private", so the failure is the single
// authoritative reason rather than buried among structural errors.
```

Verified today: a public-visibility COMP with a missing required section returns
exactly one finding, R9 (`validate.rs:664-686`). After the change it returns prose
notices plus R9. No document content leaks — FC10's message interpolates the rule
term, not the matched text — but the "single authoritative reason" property the
code comment asserts is gone, and any future prose finding that quotes the
offending line would emit content from a document the validator has just concluded
should not be in this repository at all.

**Covered?** No.

**Required mitigation.** State the ordering explicitly: prose checks run above the
*schema* gate and below the *R9* gate. Add the assertion to the existing
`validate_file_comp_public_yields_only_r9` test, and add a rule that no prose
finding message may interpolate document text.

### F9. Unicode normalization: declared terms and banned terms are both ASCII-literal (Low)

Matching is ASCII-literal against a `to_lowercase()` line. Measured, current binary:

```
plain tier here          -> FC10 fires
Cyrillic homoglyph: tеir -> no finding
Cyrillic homoglyph2: тier-> no finding
Turkish dotted: TİER     -> no finding
fullwidth: ｔier          -> no finding
zero-width: ti<U+200B>er -> no finding
ligature: robust         -> FC10 fires
```

`'İ'.to_lowercase()` yields `i` plus a combining dot, so `TİER` lowercases to
something that is not `tier`.

This is evasion of an advisory style rule, not of a security control, and the right
response is to say so rather than to normalize. It matters only if anyone later
treats the prose family as a control (a secret scanner, a visibility guard). The
symmetric direction is benign: a Cyrillic term of art in a declaration suppresses
nothing because nothing matched it in the first place.

**Required mitigation.** One sentence in Security Considerations: the prose rules
are advisory and are not a control surface; homoglyph and normalization variants
are out of scope by design; do not build a gate on top of them without revisiting
this. If NFKC normalization is wanted, it needs a decision because it changes the
"483 of 489" agreement number.

### F10. Directory rejection is narrower than described, with one regression path (Low)

The design says directory arguments become a tool error "rather than walked" and
that this "turns today's false green into a visible failure." Both halves need
qualification. Measured:

```
$ shirabe validate -- docs/designs
DIR_EXIT=0                                 # silent skip, the false green

$ shirabe validate -- <a directory named DESIGN-dir.md>
error could not read file: read ...: Is a directory (os error 21)
DIRNAMED_EXIT=1                            # already a tool error today
```

So only directories whose basename fails `detect_format` change behavior; the
artifact-prefixed case is already exit 1. Worth stating so the tests pin the right
case.

The one real regression: `git diff --name-only` emits a **git submodule** as a
path that is a directory in the worktree. Neither `validate-docs.yml` nor the
pre-commit hook filters those (the hook's `*.md` case would drop it; the workflow
would not). A PR bumping a submodule pointer goes from exit 0 to exit 1. Neither
`docs/guides/multi-consumer-cli-contract.md:95-97` nor any consumer distinguishes
exit 1 from exit 2 in a way this breaks — CI reads zero vs non-zero, the hook is
fail-closed, and only the skills branch on the full `0/1/2/3` contract, where a
tool error is the more conservative reading. So the exit-code change itself is
safe; the input class is the risk.

I checked the other directory-taking surface: `validate --lifecycle .` takes its
path through a separate argument (`main.rs:552-572`, `.github/workflows/lifecycle.yml:135`)
and returns before the positional-file loop, so directory rejection must not be
applied to it. Grepping `skills/` and `scripts/` found no consumer passing a
directory positionally.

**Required mitigation.** Say that submodule paths are the concrete directory case
in a real diff, and decide whether they are a tool error or a skip with a notice.
Pin both directory cases in tests.

### F11. The workflow passes paths without an end-of-options separator (Low, pre-existing)

`main.rs:1197-1208` documents the security model for the pre-commit hook at length
— NUL-delimited collection, `--` before the paths — "so a file named like a flag is
treated as a path." The reusable workflow does neither:

```yaml
shirabe validate \
  --visibility=${{ github.repository_visibility }} \
  ${CUSTOM_STATUSES:+--custom-statuses="$CUSTOM_STATUSES"} \
  $FILES
```

`$FILES` is unquoted and unseparated, so a committed path beginning with `-` is
parsed as a flag and a path containing whitespace is word-split. A file named
`--allow-untracked-acs` silently changes what the run checks.

Not introduced by this design, but the design rewrites this gate, which makes it
the natural place to fix. One line: `-- $FILES` becomes `--` plus a NUL-safe
array, mirroring the hook.

## What the design's existing section gets right

Three things, and they are the right three to have thought about.

Refusing to compile adopter-supplied strings into a regex is correct and is the
finding a shallower review would have produced. `regex` is a direct dependency and
already imported in `checks.rs`, so the temptation is real and the design names it
and declines.

The path-traversal reasoning is right about the parts it covers: `canonicalize`
does run before the walk (`visibility.rs:76`), `..` is therefore resolved before
any ancestor is touched, and the loop does terminate at the filesystem root. I
confirmed a 400-level tree resolves in 0.03s at 4 MB RSS, so walk depth is not a
denial-of-service surface.

Choosing Option A over Option B for Decision 3 because a header naming a path is a
traversal surface is exactly the right instinct, correctly applied, and the section
says so.

Recording the rejected option's supply-chain cost — a 40 MB third-party binary
plus a network-fetching `vale sync` on every adopter runner — without relitigating
Decision 1 is the correct treatment.

## What it missed

The section reviews the two inputs the design *adds* and stops there. Every finding
above comes from somewhere else:

**The file set, not the file contents.** The security question is not what a
CLAUDE.md contains, it is which files reach the parser at all. The `None` arm
changes that set from "files whose name matches an artifact prefix" to "everything
the caller passed," and the caller is a `git diff` with no extension filter. That
one change produces F1 (two real files break CI, one of them the file this design
edits), F5 (binaries and source files get parsed) and half of F10.

**The claim about the rule file is an assumption, not a property.** "Not an
adopter-controlled input" is true only if the binary resolves `rules.yaml` to a
path inside its own source tree, and the design never says how it does that from
`/usr/local/bin/shirabe` with CWD set to someone else's repository. F2.

**Path traversal was analyzed in the wrong direction.** The section asks whether
the *header value* can name a path — correctly, no. It does not ask what the *walk
itself* reaches. The walk crosses the repository root and follows symlinks, both
demonstrated against the shipped binary. R10's "a term suppressed in one repository
SHALL NOT be suppressed in another" is presented in the design as satisfied
structurally by per-file resolution; per-file resolution is necessary but not
sufficient, and the missing half is a repo-root bound. F3.

**Denial of service was analyzed on the input side only.** Catastrophic
backtracking is the textbook answer and the design gets it right. The measured
problem is on the output side: 1.5 million findings and 875 MB from a 10 MB file,
with a rule list this design multiplies by about seven. F4.

**Nothing in the section is about the scoper**, which the design elsewhere names as
"the most likely place for a future correctness bug." The crate has an established
convention for this and the design does not invoke it: `table.rs:5` declares its
parser "total over arbitrary line input: it never panics on ragged" input;
`mermaid.rs:9` says "never panics";
`checks.rs:5658` pins `check_fc08_extract_legend_total_over_arbitrary_input`, which
enumerates malformed shapes (empty, delimiter-only, multi-byte UTF-8, emoji) and
asserts only that the extractor returns. The convention is a named
`*_total_over_arbitrary_input` test with pinned pathological fixtures. The scoper
needs one and the design does not ask for it. My CRLF probe found the concrete
input class that convention would have caught (F6).

**The two-consumer divergence in path filtering.** The hook narrows to `*.md` and
uses `--`; the workflow does neither. The design changes the gate both consumers
feed and does not reconcile them. F5, F11.

## Required design changes

Add to `## Solution Architecture`:

> **Rule-source resolution.** The validator locates `rules.yaml` at
> `<resolution rule>`. A missing or unparseable rule source is a tool error
> (exit 1) naming the resolved path; a run never proceeds over an empty rule set.
> The resolved path is guaranteed to lie inside the shirabe source tree that
> produced the binary and can never resolve inside a repository under check.

> **`None`-arm admission.** The `None` arm admits a path only when its extension is
> `.md`. A frontmatter parse failure on a `None`-arm file is not a tool error: the
> prose family falls back to raw-line scanning over the whole file. `skills/writing-style/SKILL.md`
> and `skills/review-plan/SKILL.md` are pinned fixtures for this, and both parse-fail
> under `saphyr` today.

> **Check ordering.** Prose checks run above the schema gate and below the R9
> private-only gate. A prose finding message never interpolates document text.

> **Line-ending normalization.** The scoper normalizes CRLF to LF once at entry.
> `split_lines` retains `\r` on every line of a CRLF document, which otherwise
> breaks fence close-matching and paragraph-boundary detection, and silently
> collapses a per-paragraph frequency denominator to the document.

> **Bounded findings.** Each rule emits at most 50 findings per file, plus one
> summarizing finding when truncated. Unbounded emission is measurable today: a
> 10 MB document produces 1,500,000 FC10 findings at 875 MB resident.

Add to `## Security Considerations`, replacing the "Path traversal through the
header walk" paragraph:

> **The header walk's reach.** `resolve_claude_md_header` canonicalizes the doc
> path before walking, so `..` is resolved before any ancestor is read, and the
> walk terminates at the filesystem root. Neither property bounds it to the
> repository. Two consequences are addressed rather than accepted: the walk stops
> at the first directory containing `.git`, so a `## Prose Vocabulary:` declared
> above a repository root cannot suppress findings inside it (R10); and a
> `CLAUDE.md` whose canonicalized path escapes that bound is ignored, so a
> committed symlink cannot redirect resolution outside the repository. Both are
> demonstrated bypasses of the shipped `resolve_doc_visibility` behavior, which
> this change also corrects. Because there is no `--vocabulary` flag to mask
> per-file resolution the way `--visibility` masks it in CI, the walk is always
> live for vocabulary.

> **The prose rules are advisory, not a control.** Matching is ASCII-literal;
> homoglyph, fullwidth, zero-width and Turkish-dotted-I variants do not match and
> are out of scope. No gate may be built on the prose family without revisiting
> this.

Add to `## Implementation Approach`:

- Phase 3 gains the `None`-arm admission predicate, the two SKILL.md fixtures, and
  the submodule-directory decision.
- Phase 5 gains a merge precondition: a test asserting every prose code appears in
  both `is_known_check_code` and `is_intrinsic_notice` and resolves to
  `Severity::Notice` under both postures. Omission from `is_intrinsic_notice` ships
  the code at error level to three adopters pinned at `@main` on their next docs PR.
- A phase (or Phase 2) gains the scoper's
  `*_total_over_arbitrary_input` test, following `check_fc08_extract_legend_total_over_arbitrary_input`:
  unterminated fence, nested fences, fence opened in frontmatter, CRLF, a single
  10 MB line, 5,000-deep blockquote, ragged table, non-UTF8 bytes.

Add to `## Consequences` (Negative):

> The reusable workflow passes changed paths unquoted and without a `--`
> separator, unlike the pre-commit hook, whose security model is documented at
> `main.rs:1197-1208`. This design rewrites the gate both consumers feed and
> reconciles them.
