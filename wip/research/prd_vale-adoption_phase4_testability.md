# Phase 4 Verdict: Testability

VERDICT: FAIL

Reviewed against the tree at
`/home/dgazineu/dev/niwaw/tsuku/tsuku+vale_or_not-33480214/public/shirabe/.claude/worktrees/vale-adoption`,
binary `./target/release/shirabe` (reports `shirabe 0.0.0`). Every claim below
that says "verified" was produced by a command reproduced in-line.

The PRD's requirements are good. Its Acceptance Criteria section is the weak
part: of thirteen criteria, two already pass against the unimplemented tree,
one is unachievable by any correct implementation, two cannot be executed at
all as written, and the two requirements the PRD calls its heart (R1, R2) have
no criterion that would survive contact with a regression.

---

## Per-criterion

### 1. Every acceptance criterion is mechanically checkable — FAIL

Nine of thirteen are mechanically checkable. Four are not, and the four are not
peripheral.

**AC1 (single authoritative location)** is not mechanically checkable as
written. There is no defined test for "exactly one authoritative
representation." The obvious grep does not work — a search for one of the
banned words across the tree returns nineteen files, most of which merely
discuss the word:

```
$ grep -rln "robust" --include=*.rs --include=*.md --include=*.json . \
    | grep -v '^./target' | grep -v '^./docs'
skills/brief/references/phases/phase-4-validate.md
skills/writing-style/SKILL.md
skills/writing-style/evals/evals.json
wip/research/explore_vale-adoption_r1_lead-rule-translation.md
...
crates/shirabe-validate/src/checks.rs
```

Separating "a copy of the rulebook" from "prose that names a banned word"
requires a human read. AC1 is an assertion about repository state with no
stated procedure. See item 7.

**AC2 (rule honored by validate and by a drafting skill)** — the validator half
is mechanical (append a sentinel token to the rule source, run `shirabe
validate` on a fixture containing it, assert one finding). The drafting-skill
half is not. A drafting skill is an LLM reading a prose instruction file; the
only harness is `scripts/run-evals.sh`, which grades assertions with `claude
-p` and is nondeterministic by construction. "Honored by a drafting skill" has
no deterministic pass condition and cannot gate CI.

**AC6 (frequency rule)** — see item 3. The doc-recording half is greppable; the
behavioral half has no defined pass condition.

**AC11 (filed issue)** — see item 5. "The check's documentation" names no path,
so a checker cannot locate the reference it is supposed to find.

Two further criteria are checkable but under-specified:

**AC3** does not name the files. Verified that shirabe's own instruction files
would not satisfy it — under the current seven-word list all four are clean, and
under the full 47-word list from `skills/writing-style/SKILL.md` only README.md
produces a single hit:

```
$ grep -c -iE "\b(tier|tiered|robust|leverage|comprehensive|holistic|facilitate)\b" \
    CLAUDE.md AGENTS.md README.md skills/execute/SKILL.md
AGENTS.md:0
CLAUDE.md:0
README.md:0
skills/execute/SKILL.md:0

$ grep -c -oiE "\b(crucial|pivotal|paramount|utilize|delve|foster|navigate|showcase|
    grapple|transcend|elucidate|underscore|highlight|enhance|garner|innovative|
    transformative|profound|vibrant|seamless|meticulous|invaluable|nuanced|
    groundbreaking|intricate|journey|narrative|tapestry|testament|resilience|
    landscape|interplay|realm)\b" CLAUDE.md AGENTS.md README.md skills/execute/SKILL.md
CLAUDE.md:0
AGENTS.md:0
README.md:1
skills/execute/SKILL.md:0
```

Frequency rules do not rescue it either. Em dash density:

```
CLAUDE.md                        em=7     words=1636   per_1k=4.28
AGENTS.md                        em=0     words=423    per_1k=0.00
README.md                        em=0     words=2263   per_1k=0.00
skills/execute/SKILL.md          em=93    words=6027   per_1k=15.43
skills/writing-style/SKILL.md    em=13    words=576    per_1k=22.57
```

AGENTS.md and README.md are clean on both word rules and em dash density. An
implementer who reads AC3 literally and runs it against the repo's real files
will conclude the feature does not work. AC3 must be fixture-based, or restated
as a gate assertion rather than a findings assertion.

**AC13** names `cmd/shirabe`, which does not exist. This is a Rust workspace;
the CLI is `crates/shirabe/src/main.rs`. Verified: `ls cmd` → no such
directory. AC13 also says "agree with the registry" without naming the
registry; the authoritative list is the `is_valid_check_code` match in
`crates/shirabe-validate/src/validate.rs:163-169`.

### 2. The criteria currently FAIL — FAIL

Two criteria already pass against the unimplemented tree, and a third passes in
part.

**AC12 passes today, completely.** All twenty-two codes accepted by the
validator exit 0:

```
SCHEMA exit=0   FC01..FC16 exit=0   FC-CONVENTIONS exit=0   R6..R9 exit=0
```

(unknown codes correctly reject: `--check FC99` → `unknown --check code "FC99";
valid codes: SCHEMA, FC01-FC16, FC-CONVENTIONS, R6-R9`, exit 1.) AC12 is
satisfied before any work is done and will remain satisfied unless a retirement
happens — which R14 says may never happen ("Check-code retirement, **if any**").
It tests nothing.

**AC8 passes vacuously today.** "A term declared in shirabe's repository
produces no suppression in a different repository checked in the same run" — no
declaration mechanism exists, so nothing is suppressed anywhere, so the
criterion holds. The multi-repo invocation itself works (verified: one
`shirabe validate --check FC10` call spanning a shirabe doc and a koto doc
returned findings for both), so the plumbing is fine; the criterion's logic is
one-sided. It states only the negative and omits the positive that gives the
negative meaning.

**AC4 passes in part.** The frontmatter clause is already satisfied — FC10 reads
`doc.body`, so a banned word in frontmatter is never reported. Verified on a
purpose-built probe: `leverage` on frontmatter line 5 produced no finding, while
all eight body occurrences did, including three inside a fenced block, one in an
inline code span, and two inside a URL. The fence/span/URL clauses fail as
expected, so AC4 as a whole fails — but a third of it is already true.

The remaining ten fail correctly. AC3 verified failing:

```
$ ./target/release/shirabe validate --format human CLAUDE.md
All checks passed.
Advisory: Draft posture: no draft-tolerable findings to flag.
exit=0
```

Same for README.md, AGENTS.md, and `skills/execute/SKILL.md`.

AC5 verified failing:

```
$ ./target/release/shirabe validate --format json --check FC10 <probe>
... "line": 8 ...   (actual file line: 16; offset == 8 == frontmatter length)
```

Note a factual problem this exposed. R5 says the offset "makes its CI
annotations point at the wrong lines." It does not — the annotation formatter
emits no `line=` attribute at all:

```
::notice file=<path>::[FC10] writing-style banned word "robust" -- ...
```

Only the `--format json` envelope carries a line, and that is where the offset
shows. AC5 must name the output mode or it is ambiguous which surface is being
asserted.

### 3. Threshold and unit gaps — FAIL

AC6 reads: "An em dash density rule reports against a stated threshold, with
denominator, reporting unit, threshold value, and line-number convention
recorded in the multi-consumer contract doc."

The criterion splits into two halves with different testability.

The **recording half** is mechanically checkable now and stays checkable
regardless of what the DESIGN decides: grep
`docs/guides/multi-consumer-cli-contract.md` for four named fields. Currently
zero em dash mentions in that file (`grep -c "em dash\|em-dash"` → 0), so it
fails correctly.

The **behavioral half** is not testable as written, and its untestability is not
caused by the values being undetermined. "Reports against a stated threshold"
has no pass condition. It does not say a document above the threshold yields a
finding, does not say a document below it yields none, and — the real gap — does
not say the behavior must be consistent with the value the doc records. An
implementation that documents 3.0 per thousand and fires at 8.0 satisfies AC6
literally.

Undetermined values are not the obstacle. A criterion can be parameterized on a
value it does not fix: read the threshold from the recorded contract, synthesize
a fixture just above and just below it, assert one finding and zero findings.
That is fully mechanical today. AC6 simply is not phrased that way.

So: **testable in principle despite the open values; untestable as written.**
The DESIGN does not need to land first. Replacement text is in Required
changes.

One further gap under R7 that no criterion touches: R7 requires "the line a
document-level finding carries" be defined, and AC6 asks it be recorded — but
nothing asserts the emitted finding actually carries that line. Given the R5
offset defect is live in the same code path, this is worth a criterion of its
own.

### 4. Cross-repo criteria — FAIL

All four repos are reachable from this working tree:

```
$ ls -d .../public/koto .../public/niwa .../public/tsuku
```
all present, each with a `docs/` tree.

AC10 is executable. It is also **unachievable by any correct implementation of
this PRD**, and it fails today for reasons the feature cannot fix. Whole-corpus
run, all `docs/**/*.md` excluding fixtures:

```
shirabe: files=147 exit=2 "errors": 5  "notices": 139
koto:    files=69  exit=2 "errors": 6  "notices": 46
niwa:    files=122 exit=2 "errors": 10 "notices": 76
tsuku:   files=194 exit=2 "errors": 5  "notices": 282
```

Every single error in all four repos is a pre-existing dangling-upstream R6:

```
===== shirabe =====
   3 [R6] upstream "docs/designs/DESIGN-roadmap-plan-standardization.md" does not exist on disk
   2 [R6] upstream "docs/plans/PLAN-roadmap-plan-standardization.md" does not exist on disk
===== koto =====
   1 [R6] upstream "docs/prds/PRD-session-legibility.md" does not exist on disk
   ... (6 total)
===== niwa =====
   ... (10 total, all R6 dangling upstream)
===== tsuku =====
   ... (5 total, all R6 dangling upstream)
```

The PRD's own Known Limitations names this for shirabe ("five dangling
`upstream:` links ... produce R6 errors"). What it does not notice is that the
same condition holds in all three adopters, and that AC10 as written therefore
can never be marked done. Ship the feature perfectly and AC10 still reports exit
2 in four of four repos.

A second problem: AC10 does not correspond to any real invocation. The reusable
workflow validates only the changed-file set —
`.github/workflows/validate-docs.yml` computes `FILES` from `git diff
--name-only` and passes them positionally, with the comment "The CLI never
discovers files itself." Nothing in CI ever runs a whole-corpus pass. "The full
check over shirabe, koto, niwa, and tsuku" is a manual procedure that has to be
written down, because there is no existing command it names.

Executed as: build the binary, then for each repo `find <repo>/docs -name
'*.md' -not -path '*/fixtures/*'` and pass the list to `shirabe validate`.
That is the procedure I used above and it is reproducible.

### 5. The R12 "filed issue" criterion — FAIL

Split the question.

**Is issue existence CI-checkable?** Yes. `gh` is installed and authenticated
against the right remote (`origin git@github.com:tsukumogami/shirabe.git`):

```
$ gh issue list --repo tsukumogami/shirabe --limit 3
268  OPEN  fix(docs): PRD-koto-adoption is an orphan, ...
265  OPEN  FC16 is shape-gated, ...
259  OPEN  docs(readme): structure, vocabulary and entry points ...
```

`gh issue view <n> --json state,body` gives existence, open/closed, and body
text. Existence, state, and "the body contains a numeric token" are all
mechanical. What is not mechanical is whether that number is genuinely a
promotion precondition rather than an issue number, a date, or a corpus
statistic. That residue is human — and it is fine that it is human, because the
failure mode R12 exists to prevent is *no artifact at all*, and existence is the
half a machine can check.

**Does it matter?** Yes, but not for the reason the criterion implies. The
criterion is unexecutable for a mundane reason: it says "referenced from the
check's documentation" and never names a path or a reference format. A checker
cannot find what it is meant to verify. Compare AC6, which does name
`docs/guides/multi-consumer-cli-contract.md`. Until AC11 names the file and the
token shape, no procedure exists — not a human one either, since two reviewers
would look in different places.

Second gap: "for every rule shipped below error level" needs an enumeration
source. Today that set is the `is_intrinsic_notice` match in
`crates/shirabe-validate/src/validate.rs:83-98` — currently `SCHEMA`, `FC07`
through `FC15`, and `FC-CONVENTIONS`. Note the existing doc comment there is the
exact anti-pattern R12 is written against: "notice-level additions pending their
respective corpus-cleanup PRs." If AC11 is read as covering every code in that
match, it demands nine issues be filed for pre-existing codes this feature did
not introduce — almost certainly not the intent, and the criterion should scope
itself to rules this feature ships.

Third: a CI check calling `gh` needs network and a token. On a public repo
`GITHUB_TOKEN` suffices, but this would be shirabe's first validator-adjacent
check with a network dependency, and it cannot run in the offline
`shirabe validate` path. That is a DESIGN concern, not a blocker on the
criterion.

### 6. Missing negative tests — FAIL

Taking the four the brief names, in order.

**R4 (prose scoping) — negative present and correct.** AC4 states both
directions in one sentence: fence/span/URL/frontmatter produce no finding, "the
same word in prose produces one." This is the best-written criterion in the set
and the others should copy its shape. Verified currently failing on the positive
side of the negative (fences do fire today).

**R9 (extends not replaces) — negative present.** AC9 covers exactly the case:
a declaring repo receives a rule added after its declaration, with no edit. That
is the right test. It is not executable today because the declaration mechanism
does not exist, so the setup step cannot be performed — this is "blocked on
implementation," not "badly written."

**R10 (repo-local) — negative present, positive missing.** AC8 has only the
negative, which is why it passes vacuously (item 2). Needs its positive half.

**R11 (non-breaking) — negative missing, and this is the significant gap.** Exit
0 across four repos is not sufficient; it is also not achievable (item 4). What
R11 actually claims is a *differential* property: whatever passed before still
passes. Nothing in the criteria expresses a before/after comparison. The correct
test is a baseline diff — capture the error-severity finding set per repo at the
parent commit, capture it again after, assert set equality. That test would pass
today (trivially, empty diff), which is a feature: it is a regression guard, and
regression guards are supposed to be green until something regresses. This one
must be distinguished from AC12, which is green because it asserts nothing.

Additional missing negatives beyond the four named:

- **R1/R2**: no criterion fails when a second copy is introduced. See item 7.
- **R3**: no criterion that widening the format gate leaves artifact-file
  behavior unchanged. Loosening `detect_format`
  (`crates/shirabe-validate/src/formats.rs:248`) is exactly the kind of change
  that silently alters which checks run on PRD/DESIGN/PLAN files.
- **R8 (term-scoped, not rule-scoped)**: AC7's "still receives findings for
  every other rule" is the right idea but stops short. Missing: declaring `tier`
  must not suppress `tiered`, and must not suppress a *different* word rule
  firing on the same line. Morphological scope is where a term-suppression
  implementation actually goes wrong.
- **R13 (no silent registration)**: no criterion at all beyond AC13's static
  range comparison. The requirement is about a class of future mistake — a new
  code missing from one of six lists that fail silently. AC13 checks two prose
  copies at one instant; nothing prevents the next code from repeating the
  failure. This wants a test asserting the registration lists are mutually
  consistent, not a one-time text comparison.
- **R14 (retirement is non-breaking)**: AC12 checks a retired code is still
  *accepted*. Missing: a retired code must also produce *no findings* — accepted
  and silent, not accepted and still firing.
- **R5**: AC5 correctly specifies "on a file with frontmatter," which is the
  case that fails. Good. Worth adding the zero-frontmatter case so a fix that
  hardcodes an offset instead of tracking real positions gets caught.

### 7. Verifiability of the single-source requirement — FAIL

Direct answer to the question posed: **no, the criteria as written would not
fail if a future PR hardcoded a word list somewhere.**

AC1 asserts a state at one instant ("exist in exactly one authoritative
location; the FC10 constant and the BRIEF jury's inline word list are replaced
by references to it"). It names the two known copies and says they are gone.
Once they are gone it is satisfied forever. Nothing in it is a standing check,
and nothing generalizes to a third copy nobody has thought of. The PRD's
Problem Statement makes exactly this point about the FC10 design — "The design
that specified FC10 required the validator read the list from the SKILL.md at
validate time so updates would propagate; the shipped code hardcodes it" — and
the code comment at `crates/shirabe-validate/src/checks.rs:2542-2550` documents
the rationalization verbatim ("this constant is the authoritative compile-time
copy"). The PRD diagnoses the failure and then writes an acceptance criterion
that would not have caught it.

AC2 is closer to a regression guard but is weaker than it looks. "A rule added
to that source is honored by `shirabe validate` and by a drafting skill without
a second edit" catches a *stale* second copy, since a copy that does not receive
the new rule diverges. It does not catch a *synchronized* second copy — the
condition that existed the day FC10 shipped, when the constant matched the
SKILL.md exactly and drifted only later. And it catches nothing at all on the
skills side, where the second copy lives in prose read by a model
(`skills/brief/references/phases/phase-4-validate.md:245` currently restates
five words inline). No code path reads that file; no test can observe whether it
agrees with anything.

What would work, in increasing strength:

1. A parse-and-compare test: the validator's effective rule set at runtime must
   be set-equal to the rule set parsed from the source file. Catches drift,
   catches a hardcoded list that diverges, does not catch a synchronized
   duplicate.
2. A structural CI check over `skills/**` and `crates/**` for word-list-shaped
   content — an array or table of three or more entries drawn from the rule
   source — with the rule source itself allowlisted. Catches the prose copy,
   which is the one that no runtime test can reach. Needs a suppression path for
   `skills/writing-style/evals/evals.json`, which legitimately contains the
   words as test data.
3. A sentinel: insert a token that appears in the rule source and nowhere else,
   and assert every enforcing surface reports it. Cheap, and it makes surface
   *coverage* testable rather than surface *uniqueness*.

None of these is in the criteria. R1 and R2 are, by the PRD's own framing, the
heart of the feature, and they are the least defended.

---

## Acceptance criterion execution table

| # | criterion (abbreviated) | procedure | executable now? | currently passes? |
|---|---|---|---|---|
| 1 | Rules in exactly one location; FC10 constant + jury list replaced by references | No defined procedure. Nearest mechanical approximation `grep -rln '<word>' --include=*.rs --include=*.md .` returns 19 files, most false positives. Requires human adjudication of "authoritative" | No | No (2 copies present: `checks.rs:2551`, `skills/brief/references/phases/phase-4-validate.md:245`) |
| 2 | Rule added to source honored by validate and by a drafting skill | Validator half: append sentinel to source, `shirabe validate <fixture>`, assert 1 finding. Skill half: `scripts/run-evals.sh writing-style` — LLM-graded, nondeterministic | Half | No |
| 3 | Prose findings for SKILL.md, CLAUDE.md, AGENTS.md, README.md | `shirabe validate --format human <each>` | Yes | No — all four return `All checks passed.` exit 0. But unsatisfiable with real repo files even after implementation (0 word hits, 0 em dashes in AGENTS.md/README.md) |
| 4 | Banned word in fence/span/URL/frontmatter → none; in prose → one | Purpose-built probe doc, `shirabe validate --format json --check FC10 <probe>`, count by line | Yes | Partly — frontmatter clause already passes (body-only scan); fence/span/URL clauses fail (8 findings incl. 3 in fence, 1 in span, 2 in URL) |
| 5 | Line number equals author-visible line, on a file with frontmatter | `shirabe validate --format json --check FC10 <probe>`, compare `line` to `grep -n` | Yes (JSON only; annotation mode emits no `line=`) | No — reported 8, actual 16, offset == frontmatter length |
| 6 | Em dash density rule with denominator/unit/threshold/line convention in contract doc | Recording half: grep `docs/guides/multi-consumer-cli-contract.md` for 4 fields. Behavioral half: undefined pass condition | Half | No (`grep -c 'em dash\|em-dash'` → 0; no frequency check exists in `checks.rs`) |
| 7 | Repo declaring `tier` gets no `tier` findings, still gets other rules | Declare `tier`, run over shirabe `docs/`, assert 0 `tier` and >0 others. Baseline today: 76 `tier`, 3 `tiered`, 6 `robust`, 3 each `leverage`/`holistic`/`facilitate`/`comprehensive` | No (no declaration mechanism) | No |
| 8 | Term declared in shirabe → no suppression in a different repo, same run | Single `shirabe validate` invocation spanning both repos' files. Multi-repo invocation verified working. Blocked: koto's schema-passing docs contain zero banned words, so a fixture must be added to the other repo | No (setup impossible) | **Yes, vacuously** — nothing is suppressed anywhere |
| 9 | Rule added after declaration reaches declaring repo with no edit | Declare, snapshot findings, append rule to source, re-run, assert new code appears | No (no declaration mechanism) | No |
| 10 | Full check over 4 repos → exit 0 in all four | `find <repo>/docs -name '*.md' -not -path '*/fixtures/*'` piped to `shirabe validate` | Yes | No — exit 2 in all four. **Unachievable**: 5/6/10/5 pre-existing R6 dangling-upstream errors, none prose-related |
| 11 | Filed issue, referenced from check docs, numeric promotion condition, every below-error rule | `gh` available and authed. But "the check's documentation" names no path and no reference format; "every rule below error level" names no enumeration source (would be `is_intrinsic_notice`, `validate.rs:83-98`) | No | No |
| 12 | `--check <code>` succeeds for every code in the contract doc, incl. retired no-ops | Loop all 22 codes through `shirabe validate --check <c> <doc>`, assert exit 0 | Yes | **Yes** — all 22 exit 0. Asserts nothing; no code has been retired and R14 says retirement may never happen |
| 13 | Check-code ranges in `cmd/shirabe` help and contract doc agree with registry | `shirabe validate --help` and `grep FC0 docs/guides/multi-consumer-cli-contract.md` vs `is_valid_check_code` | Yes, after fixing the path | No — help says `FC01`-`FC13`, contract doc line 89 says `FC01`-`FC13`, registry is `FC01`-`FC16`. Note `cmd/shirabe` does not exist; correct path is `crates/shirabe/src/main.rs` |

Summary: 6 of 13 executable and correctly failing. 2 executable and already
passing (AC8 vacuously, AC12 outright). 1 executable but unachievable (AC10). 2
partly executable (AC2, AC6). 2 not executable (AC1, AC11). 3 blocked purely on
implementation, which is expected and fine (AC7, AC9, and the setup half of
AC8).

---

## Missing negative tests

1. **R11 has no differential criterion.** Exit 0 across four repos is neither
   sufficient nor achievable. Nothing asserts that a build passing before the
   change still passes after it.
2. **R10's positive half is absent.** AC8 states only that suppression does not
   leak, never that it takes effect in the declaring repo — which is why it
   passes vacuously.
3. **R1/R2 have no regression guard.** No criterion fails when a second copy is
   introduced, and none can observe a copy living in skill prose.
4. **R8's morphological negative is absent.** Declaring `tier` must not suppress
   `tiered`, and must not suppress a different rule firing on the same line.
5. **R3's non-interference negative is absent.** Widening the format gate must
   not change which checks run on artifact-prefixed files.
6. **R14's silence negative is absent.** AC12 checks a retired code is accepted;
   nothing checks it produces no findings.
7. **R13 has no forward-looking check.** AC13 compares two prose copies at one
   instant; nothing prevents the next added code from missing a list again.
8. **R5's zero-frontmatter case is absent.** A fix that hardcodes an offset
   rather than tracking true positions would pass AC5 as written.
9. **R7's emitted-line convention is unasserted.** AC6 requires the convention be
   *recorded*; nothing requires the finding actually carry it.

---

## Required changes

**AC1 — replace.** Split state from guard.

> - [ ] The writing-style rules exist in exactly one file; `FC10_BANNED_WORDS`
>       in `crates/shirabe-validate/src/checks.rs` and the inline word list in
>       `skills/brief/references/phases/phase-4-validate.md` are replaced by
>       references to that file's path.
> - [ ] A CI check fails when a word-list-shaped literal (three or more entries
>       drawn from the rule source) appears anywhere under `crates/**` or
>       `skills/**` outside the rule source itself and
>       `skills/writing-style/evals/evals.json`.

**AC2 — replace, and drop the undecidable half.**

> - [ ] Appending a sentinel term to the rule source causes `shirabe validate`
>       to report it on a fixture containing that term, with no other file
>       edited.
> - [ ] The rule set the validator applies at runtime is set-equal to the rule
>       set parsed from the source file; a test asserts the equality and names
>       the count.

The drafting-skill half belongs in `skills/writing-style/evals/evals.json`, not
in a merge-gating criterion.

**AC3 — replace with fixture-based text.** Real repo files cannot satisfy it.

> - [ ] For each of a fixture SKILL.md, CLAUDE.md, AGENTS.md, and README.md
>       containing a known rule violation, `shirabe validate` reports at least
>       one prose finding naming the violation. Verified failing today: all four
>       return `All checks passed.` at exit 0.
> - [ ] Running the same invocation over an artifact-prefixed file produces the
>       same finding set it produced before instruction-file coverage was added.

**AC5 — name the output mode.**

> - [ ] Under `--format json`, a finding's `line` equals the line the author
>       sees, verified on a fixture with frontmatter and on one without. (Today:
>       reported 8 against actual 16 on a 7-line-frontmatter fixture. Note
>       `--format annotation` emits no `line=` attribute at all; if CI
>       annotations are meant to carry a line, that is a separate criterion.)

**AC6 — replace with parameterized text.** Testable now, without waiting on the
DESIGN.

> - [ ] `docs/guides/multi-consumer-cli-contract.md` records, for the em dash
>       density rule, all four of: denominator, reporting unit, threshold value,
>       and the line number a document-level finding carries.
> - [ ] A fixture whose density exceeds the recorded threshold produces exactly
>       one finding per recorded reporting unit; a fixture below it produces
>       none. The test reads the threshold from the recorded value rather than
>       hardcoding it.
> - [ ] The finding emitted for a document-level rule carries the line number the
>       contract doc records as its convention.

This closes item 3: the criterion binds behavior to the recorded value without
fixing the value, so the DESIGN can still choose it.

**AC7 — add the morphological negative.**

> - [ ] A repository declaring `tier` receives no `tier` findings, still receives
>       findings for every other rule, and still receives `tiered` findings.
>       Baseline before declaration on shirabe's `docs/`: 76 `tier`, 3 `tiered`,
>       6 `robust`, 3 each of `leverage`, `holistic`, `facilitate`,
>       `comprehensive`.

**AC8 — add the positive half.** As written it passes vacuously.

> - [ ] In a single `shirabe validate` invocation spanning files from shirabe and
>       from another repository, a term declared in shirabe suppresses that
>       term's findings in shirabe's files and does not suppress them in the
>       other repository's files. Requires a fixture in the second repository:
>       koto's schema-passing docs currently produce zero word findings.

**AC10 — replace.** Unachievable as written; all four repos exit 2 today on
pre-existing R6 errors this feature cannot fix.

> - [ ] For each of shirabe, koto, niwa, and tsuku, the set of error-severity
>       findings produced by `shirabe validate` over `docs/**/*.md` is identical
>       before and after this change. Recorded baseline: shirabe 5, koto 6, niwa
>       10, tsuku 5, all `[R6] upstream ... does not exist on disk`.
> - [ ] No finding introduced by this change is emitted at error severity on the
>       release that introduces it.

This is what R11 actually claims, it is achievable, and it is a real regression
guard rather than a restatement of a pre-existing corpus condition.

**AC11 — name the path, the format, and the enumeration source.**

> - [ ] `docs/guides/multi-consumer-cli-contract.md` contains, for each rule this
>       change ships below error level, a `tsukumogami/shirabe#<n>` reference.
>       Each referenced issue is open and its body states a numeric promotion
>       condition. Scoped to rules introduced by this change; the nine
>       pre-existing notice-level codes in `is_intrinsic_notice`
>       (`crates/shirabe-validate/src/validate.rs:83-98`) are out of scope.

Existence and open-state are `gh`-checkable and should gate; whether the number
is a sound precondition stays with review, which is acceptable — the failure
mode R12 targets is the absent artifact, and absence is machine-detectable.

**AC12 — make it assert something, or drop it.** It passes today against
nothing.

> - [ ] `--check <code>` exits 0 for every code in `is_valid_check_code`, and
>       every code named in `docs/guides/multi-consumer-cli-contract.md` appears
>       in `is_valid_check_code`. A code retired as a no-op is accepted and
>       produces zero findings.

**AC13 — fix the path and name the registry.**

> - [ ] The check-code ranges in `crates/shirabe/src/main.rs` help text and in
>       `docs/guides/multi-consumer-cli-contract.md` agree with the
>       `is_valid_check_code` match in
>       `crates/shirabe-validate/src/validate.rs`. Today both say `FC01`-`FC13`
>       against a registry of `FC01`-`FC16`. (`cmd/shirabe` does not exist; this
>       is a Rust workspace.)

**Add — R3 non-interference, R13 forward guard, R14 silence.** Covered inline
above under AC3, AC12, and AC13 respectively; R13 additionally wants:

> - [ ] A test asserts every code in `is_valid_check_code` also appears in each
>       of the registration lists that gate it, so a newly added code cannot be
>       missing from one of them silently.

---

## Note on scope

Two observations outside my remit that the clarity and completeness reviewers
may want. First, R5's premise is inaccurate: annotation output carries no line
number, so the frontmatter offset does not misdirect CI annotations — it
misdirects the JSON envelope. Second, the schema gate is a larger hole than the
Out of Scope section suggests: several shirabe design docs I probed
(`DESIGN-decision-framework.md`, `DESIGN-complexity-routing-expansion.md`) have
no `schema:` field and run zero checks, so any criterion phrased over "shirabe's
docs" silently excludes them.
