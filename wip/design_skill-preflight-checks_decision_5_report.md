# Decision 5 research report — stderr-discard enumeration (5a) and the R22 discriminator (5b)

Prepared for `/design` Phase 2 on `DESIGN-skill-preflight-checks`.
All counts below were produced by running the scans against the tree at
`61b7621`; the probe harnesses are at `wip/scan_probe.sh`,
`wip/unread_probe.sh`, and `wip/r26_probe.sh`.

---

## Decision 5a — the stderr-discard enumeration

### What the data actually says

Raw `grep -rn '2>/dev/null' skills/` returns **109** hits. Filtering to
non-test files and requiring a declared tool (`shirabe`, `koto`, `gh`,
`jq`, `git`, `python3` — the R3 tool set) in the *command text* yields
**27**, reproducing the prior reviewer's number exactly.

Three findings from reproducing it changed the shape of the recommendation:

**1. The naive filter over-counts by one, and the reason matters.** Matching
the declared-tool pattern against the whole `grep` output line — path
included — returns 28. The extra hit is
`skills/work-on/koto-templates/work-on.md:441`, a `go test ./... 2>/dev/null`
whose only tie to a declared tool is the string `koto` in the directory name
`koto-templates/`. The scan must strip `path:lineno:` before testing for a
declared tool. Since the PRD explicitly requires the scan to cover
`koto-templates/`, this false-positive class is guaranteed to recur.

**2. The acceptance criteria's shape list has a hole.** The AC names
`2>/dev/null`, `&>/dev/null`, and `2>&1 >/dev/null`. It omits
`>/dev/null 2>&1`, which discards stderr just as completely. That shape
matches **52** times raw and **6** more in-scope sites beyond the 27:

```
skills/plan/scripts/build-dependency-graph.sh:55   jq -e 'type == "array"' >/dev/null 2>&1
skills/plan/scripts/create-issues-batch.sh:412     gh issue edit ... >/dev/null 2>&1
skills/plan/scripts/render-template.sh:55          jq -e '.' >/dev/null 2>&1
skills/plan/scripts/render-template.sh:60          jq -e '.complexity' >/dev/null 2>&1
skills/plan/scripts/render-template.sh:64          jq -e '.goal' >/dev/null 2>&1
skills/execute/scripts/run-cascade.sh:639          command -v shirabe >/dev/null 2>&1
```

R21's own text is the authority here, not the AC's list: it forbids
"redirection to `/dev/null` in any spelling." The design should widen the
scan to four shapes and note the AC as under-specified relative to its
requirement.

**3. `command -v <tool>` discards nothing and should be carved out.**
Measured directly: `command -v <missing-binary>` writes **zero bytes** to
stdout and stderr combined and exits 1. There is no diagnostic to discard,
and the declared tool is never executed — `command -v` is a shell builtin
answering a question *about* the tool. Every such site already tests the
exit status (all sit inside `if !`). Seven of the 27 are this shape. Folding
them into the enumeration would add seven entries whose "exit status the
fallback is entered on" is a property of the shell, not of the declared
tool, and would dilute a list whose value is that a reader can scan it for
genuine risk.

Net: **27 in-scope under the PRD's literal shape list**; widening to four
shapes adds 6 (33); carving out `command -v` removes 8 of those 33, leaving
**25 sites requiring adjudication** — of which 2 are R26 remediations and 23
become enumeration entries (22 records, since two are byte-identical lines in
one file).

### The fourth arm — capture into an unread variable

The unread-variable probe over non-test `*.sh` and `*.md` under `skills/`
found exactly one hit:
`skills/execute/koto-templates/execute.md:498`, `CASCADE_STATUS=$(echo
"$RESULT" | jq -r '.cascade_status')`, which is never referenced again in
shell. It is not a defect: the surrounding prose instructs the agent to
"Submit `cascade_status` from the JSON output." The consumer is an agent
reading prose, not the shell.

This is a hard limit on mechanizing the fourth arm inside `.md` templates.

**Recommendation:** run the unread-variable arm against `*.sh` only, where
"assigned and never referenced" is a sound proxy, and document that in
`.md` templates the scan relies on the redirect-shape arms alone. Attempting
it in templates produces a false positive on the first file it touches.

### Options considered — enumeration format and location

| Option | Verdict |
|---|---|
| **A. Inline marker comment at the call site** (`# r21b-exempt: exit 3`) | **Rejected on requirement grounds.** R21b exists so that adding an exemption is "a reviewed edit rather than a judgment made silently at the call site." An inline-only marker *is* the silent call-site judgment the requirement was written against. |
| **B. Markdown table in `references/`** | **Rejected on mechanics.** The join key must include the command text, and several in-scope commands contain `\|` (`jq -r '.findings \| length'`, `gh ... --jq '.[] \| select(...)'`). A markdown table would need pipe-escaping in exactly the field the scan parses. |
| **C. TOML / JSON / YAML data file** | **Rejected on convention.** The repo has no committed data files of any of these types under `references/` or `scripts/`; every normative artifact is markdown. It would also need a parser dependency (`jq`, already declared) for a file a human must review. |
| **D. Markdown policy doc whose canonical records live in a fenced TSV block** | **Recommended.** |

### Recommendation (5a)

**Format and location.** A single committed policy document at
`references/tool-diagnostic-discards.md`, following the precedent of
`references/wip-hygiene.md` and `references/worktree-discipline.md` —
normative policy prose that is not loaded by any skill but is reviewed as
part of a PR. The prose half states the rule, the `command -v` carve-out,
and how to add an entry. The machine-readable half is a single fenced block
of tab-separated records:

```
path <TAB> match <TAB> occurrences <TAB> exit_status <TAB> rationale
```

Tab separation sidesteps the pipe collision entirely, and one record per
line keeps the diff of "someone added an exemption" to a single added line
that a reviewer cannot miss.

**The join key is `path` + `match`, never `path:lineno`.** Line numbers drift
whenever anything above a site is edited; keying on them would make every
unrelated edit break the build. `match` is the source line trimmed of leading
and trailing whitespace, so reindentation is tolerated but *editing the
command* breaks the join — which is the correct behavior, because changing
what the command does should force the exemption back through review.
`occurrences` carries the count of byte-identical matches in that file (only
`run-cascade.sh` needs it, at 2), so introducing a third copy fails until the
count is deliberately bumped.

**The scan.** `scripts/check-tool-diagnostic-discards.sh`, with a
`_test.sh` sibling per the precedent of
`scripts/check-template-interpolation_test.sh` and
`scripts/validate-template-mermaid_test.sh`. Its algorithm:

1. Walk non-test files under `skills/` (`*.sh` and `*.md`, including
   `koto-templates/`). Exclusions: `*_test.sh`, `/evals/`, `/fixtures/`.
2. Match four redirect shapes: `2>/dev/null`, `&>/dev/null`,
   `2>&1 >/dev/null`, `>/dev/null 2>&1`.
3. Strip `path:lineno:` from each hit, then require a declared tool as a
   word in the remaining **command text**. The tool list is read from the
   declarations themselves, not hardcoded, so a newly declared tool widens
   the scan automatically.
4. Drop hits whose only tool reference is `command -v <tool>`.
5. For `*.sh` only, additionally flag `VAR=$(<tool> ...)` where `VAR` is
   never referenced again.
6. Join surviving hits against the enumeration on `path` + trimmed `match`,
   comparing occurrence counts. Report both directions: an unenumerated
   site fails, and a stale enumeration entry matching nothing also fails, so
   the list cannot rot into a permanent allowlist.
7. Make no judgment about whether a discard is reasonable — per the AC.

**Where it runs.** `.github/workflows/check-tool-diagnostic-discards.yml`, a
thin wrapper on the `check-no-duplicate-rule-list.yml` pattern: `ubuntu-latest`,
`actions/checkout@v4`, one `run:` step, `pull_request` path-filtered on
`skills/**`, `references/tool-diagnostic-discards.md`, and the script itself.
No matrix — the scan is pure text and has no platform-dependent behavior,
unlike `check-execute-scripts.yml` which runs real bash under test.

### The R26 remediation — and a defect found while checking it

The PRD contrasts two shapes. The first,
`skills/execute/koto-templates/execute.md:339`:

```bash
git checkout impl/$PLAN_SLUG 2>/dev/null || git checkout -b impl/$PLAN_SLUG
```

is a probe whose failure is handled by doing the equivalent work. It is the
canonical R21b entry: enumerate it, exit status 1 (git's "pathspec did not
match"), done.

The second, at lines 390 and 409:

```bash
SETTLED_BRANCH=$(koto context get {{SESSION_NAME}} settled_branch 2>/dev/null || echo "impl/$PLAN_SLUG")
```

masks failure by fabricating a value. Probing the live binary turned up
something worse than the PRD describes:

- **`koto context get` writes its error JSON to stdout, not stderr.** The
  `2>/dev/null` is therefore *inert* — it suppresses a stream koto does not
  use for errors.
- Because command substitution captures stdout and `||` still fires on the
  non-zero exit, the variable receives **both** the error JSON and the
  fallback string. Measured (`wip/r26_probe.sh`):

  ```
  RAW CAPTURE >>>{"command":"context get","error":"failed to read context key
  'settled_branch' for session 'no-such-session-xyz': ..."}
  impl/demo<<<
  ```

- Only the downstream character-class guard
  (`case ... *[!A-Za-z0-9._/-]*`) rescues this, because the JSON contains
  braces, quotes, and spaces. The correct value emerges **by accident**. A
  koto error whose text happened to be sanitizer-clean would flow onward as
  a real branch name.

`koto context get` distinguishes the cases cleanly: **3** = key or session
absent, **2** = clap usage error, **127** = binary absent. The remediation
should branch on the exit status rather than collapsing all three:

```bash
ERRF=$(mktemp)
SETTLED_BRANCH=$(koto context get {{SESSION_NAME}} settled_branch 2>"$ERRF")
rc=$?
case $rc in
  0) : ;;                                   # got a value
  3) SETTLED_BRANCH="impl/$PLAN_SLUG" ;;    # key absent: expected, handled
  *) cat "$ERRF" >&2
     printf 'koto context get failed (exit %s); cannot resolve settled branch\n' "$rc" >&2
     rm -f "$ERRF"; exit "$rc" ;;
esac
rm -f "$ERRF"
```

Exit 3 remains an R21b enumeration entry (expected, handled, named status).
Exits 2 and 127 — stale binary, renamed subcommand, koto absent — now
surface instead of fabricating a branch. That is precisely the `#279`
failure mode R26 exists to close. The `case` sanitizer stays as
defence-in-depth but is no longer load-bearing.

### Consequences (5a)

- Two files ship in the same change as the scan: the enumeration seeded with
  23 entries (22 records) and the check script plus its test.
- The `command -v` carve-out and the four-shape widening both need stating in
  the design as deliberate departures from the AC's literal wording; the AC
  should be read as under-specified against R21 rather than as a ceiling.
- Keying on `path` + `match` means a reviewer sees a failing check whenever
  an exempted command's text changes. That is the intended cost.
- The unread-variable arm is `*.sh`-only. This is a stated coverage gap, not
  an oversight — the one template hit is a genuine false positive.
- Tool names come from the declarations, so the scan's scope grows with them
  and cannot silently fall behind.

---

## Decision 5b — the R22 discriminator

### Verified behavior

Measured against `shirabe v0.16.0`:

| Invocation | Exit | `shirabe-validate/v1` envelope? |
|---|---|---|
| `shirabe validate --not-a-real-flag <doc>` | **2** | **No** — clap usage text on stderr |
| `shirabe validate --format json <clean doc>` | 0 | Yes |
| `shirabe validate --format json <violating doc>` | 2 | Yes |
| `shirabe validate --format json --lifecycle docs <doc>` (mutually exclusive) | 1 | **No** — bare stderr line |

The collision is confirmed. Both consumers branch on exit 2 and then attempt
to read `findings` from an envelope that was never emitted.

### The bug is narrower than it looks

`crates/shirabe/src/main.rs` already defines the right vocabulary.
`ValidateOutcome::ToolError` maps to exit **1**, documented at the
`run_validate` docstring as covering "bad invocation, unreadable or
unparseable file," and it already fires — the mutually-exclusive-flag path at
`main.rs:484-487` returns exit 1 today.

The defect is only that **clap intercepts an unrecognized flag and exits 2
before `run_validate` is ever entered**. `main()` calls `Cli::parse()`, which
terminates the process on a parse error using clap's default code of 2. So
this is not a missing discriminator; it is one existing contract that a
framework default bypasses.

### Is changing clap's exit code safe?

Yes, on all three axes:

- **The frozen surface is untouched.** `main.rs:171` freezes the bytes of
  *annotation-format output* for CI parity. A clap usage error emits no
  annotation bytes at all — it is a usage message on stderr. Changing its
  exit code does not touch the frozen format.
- **No test asserts exit 2.** Three tests exercise clap usage errors
  (`coordination_body.rs:107`, `merge_gate.rs:41`, `cli.rs:50`) and all assert
  `.failure()` — any non-zero — not `.code(2)`. Only three stale code
  *comments* mention exit 2. Zero assertions break.
- **Precedent exists.** `cli.rs:50` documents that this codebase already
  overrides clap's default exit behavior when the contract demands it (bare
  invocation prints help and exits 0 instead of clap's usage error). And
  sibling tests in the same files already assert `.code(1)` for other
  bad-invocation cases, so exit 1 for usage errors is the *consistent*
  choice, not a new one.
- **No CI depends on it.** Grepping `scripts/` and `.github/workflows/` found
  no consumer branching on validate's exit 2 specifically; CI treats
  non-zero as failure.

### Options considered

| Option | Verdict |
|---|---|
| **A. Add a new sentinel exit code (e.g. 4) for CLI-surface errors** | Rejected. Invents a fifth value in a vocabulary deliberately shared with `transition` and `finalize-chain`, and every existing consumer would still misroute until updated. |
| **B. Add an explicit marker string to the usage-error output** | Rejected. Requires consumers to string-match framework-generated text, which is exactly the brittleness R22 is trying to end. |
| **C. Change clap's usage-error exit code to 1** | Necessary, insufficient alone — see below. |
| **D. Have consumers test for the envelope's presence first** | Necessary, and load-bearing. |
| **C + D together** | **Recommended.** |

### Why C alone cannot work

R22 exists because of the **stale binary** case. A stale binary is by
definition one that predates the fix. Shipping C alone changes nothing for
the user actually experiencing the problem: their old binary still exits 2 on
an unrecognized flag, and their consumer still routes it to the violation
branch. The producer-side fix only helps once the binary is new — at which
point the flag is recognized and the error does not arise.

The consumer-side check is what makes a *stale* binary diagnosable, and it
works against every shirabe version ever shipped, because envelope-absence on
a `--format json` run is not a new signal — it is already true of every
release.

### Recommendation (5b)

**Adopt C and D together, with D as the normative discriminator.**

The discriminator is: **on a `--format json` run, absence of a parseable
`shirabe-validate/v1` envelope on stdout means the validator never reached a
verdict — regardless of exit code.** The verified matrix above shows this
holds cleanly: the envelope is emitted whenever `run_validate` gets far
enough to have an opinion, and never when the process failed before that.

Producer change (C): replace `Cli::parse()` in `main()` with
`Cli::try_parse()`, printing the error and mapping `DisplayHelp` /
`DisplayVersion` kinds to exit 0 and every other kind to exit 1
(`ValidateOutcome::ToolError`). Update the three stale comments. This aligns
clap with the contract the codebase already documents.

**What `skills/scope/SKILL.md` must change.** The Validator Pass-Through
section (lines 617-642) currently reads "parses the `shirabe-validate/v1`
JSON envelope and branches on the multi-level exit code," which leaves the
ordering of those two operations unstated — and Phase 2 resolves it by
branching on the code first. It must state an explicit precedence: **test for
the envelope before reading the exit code.** If stdout does not parse as a
`shirabe-validate/v1` envelope, route to the tool-error outcome and surface
the captured stderr verbatim, whatever the exit code was. Only when the
envelope parses do the 0/2/1 branches apply. The section should also name the
stale-binary case explicitly, since that is the failure it now catches.

**What `/charter`'s finalization phase must change.**
`skills/charter/references/phases/phase-finalization.md` (step 4, lines
169-198) has the same latent ordering bug, but is closer to correct already:
its exit-1 bullet lists "an envelope that does not parse" as a tool-error
cause. The fix is to **promote that condition out of the exit-1 bullet and
into a precedence rule ahead of the branch list** — currently it can only be
reached after the exit code has already selected a branch, so an exit-2
no-envelope run enters the violations branch and never consults it. Step 4
should read: parse stdout first; on a parse failure, halt as a tool failure
with `exit:` UNSET and surface stderr; otherwise branch on 0/2/1 as written.
The existing exit-1 prose then stays accurate for the cases that do emit one.

Both consumers must also **capture stderr rather than discarding it** — R21
binds them, and the stderr text is the entire diagnostic payload in the
no-envelope case.

### Consequences (5b)

- Consumers become correct against **every** shirabe version, including ones
  already installed, which is what R22's motivating scenario requires.
- The producer change costs one function swap plus three comment updates, and
  breaks zero assertions.
- No new exit code and no new marker: the 0/1/2/3 vocabulary shared with
  `transition` and `finalize-chain` is preserved, and
  `docs/guides/multi-consumer-cli-contract.md` needs only a sentence stating
  the envelope-presence precedence.
- The AC ("distinguishable by a named discriminator... asserted for both
  inputs against both consumers") is satisfiable as written: the named
  discriminator is envelope presence, and the two inputs are an unrecognized
  flag and a violating document.
- Any future `validate` failure path that exits before emitting an envelope
  is automatically routed correctly, rather than needing its own exit code.

---

## Appendix A — the 27 in-scope sites (PRD's three shapes, non-test, declared tool in command)

Reproduced by `bash wip/scan_probe.sh skills prd3`. `CARVE` marks the
`command -v` sites the recommendation excludes; `R26` marks the two
remediations; the rest are enumeration seed entries.

| # | Site | Command | Class |
|---|---|---|---|
| 1 | `skills/work-on/references/scripts/extract-context.sh:129` | `command -v gh &>/dev/null` | CARVE |
| 2 | `skills/work-on/references/scripts/extract-context.sh:133` | `command -v jq &>/dev/null` | CARVE |
| 3 | `skills/work-on/references/scripts/extract-context.sh:137` | `gh auth status &>/dev/null` | enumerate |
| 4 | `skills/work-on/references/scripts/extract-context.sh:320` | `gh issue view ... --jq '.body' 2>/dev/null) \|\| {` | enumerate |
| 5 | `skills/work-on/references/scripts/extract-context.sh:408` | `command -v koto &>/dev/null` | CARVE |
| 6 | `skills/plan/scripts/build-dependency-graph.sh:40` | `command -v jq &>/dev/null` | CARVE |
| 7 | `skills/plan/scripts/plan-to-tasks.sh:1146` | `command -v jq &>/dev/null` | CARVE |
| 8 | `skills/plan/scripts/create-issues-batch.sh:140` | `command -v jq &>/dev/null` | CARVE |
| 9 | `skills/plan/scripts/create-issues-batch.sh:273` | `gh repo view --json nameWithOwner ... 2>/dev/null)` | enumerate |
| 10 | `skills/plan/scripts/create-issues-batch.sh:284` | `... 2>/dev/null \| jq -r ... 2>/dev/null \|\| true)` | enumerate |
| 11 | `skills/plan/scripts/create-issues-batch.sh:438` | `gh issue view ... --jq '.body' 2>/dev/null \|\| true)` | enumerate |
| 12 | `skills/plan/scripts/render-template.sh:41` | `command -v jq &>/dev/null` | CARVE |
| 13 | `skills/plan/scripts/validate-plan.sh:198` | `git -C ... rev-parse --show-toplevel 2>/dev/null) \|\| {` | enumerate |
| 14 | `skills/plan/scripts/validate-plan.sh:252` | `git -C ... ls-files --error-unmatch ... &>/dev/null` | enumerate |
| 15 | `skills/release/SKILL.md:33` | `git describe --tags --abbrev=0 ... 2>/dev/null \|\| echo ""` | enumerate |
| 16 | `skills/execute/scripts/run-cascade.sh:162` | `gh issue view ... --jq '.state' 2>/dev/null) \|\| {` | enumerate |
| 17 | `skills/execute/scripts/run-cascade.sh:193` | `jq -r '.findings \| length' ... 2>/dev/null) \|\| finding_count=""` | enumerate |
| 18 | `skills/execute/scripts/run-cascade.sh:243` | `jq -r '.findings \| length' ... 2>/dev/null) \|\| finding_count=""` | enumerate |
| 19 | `skills/execute/scripts/run-cascade.sh:628` | `git rev-parse --show-toplevel 2>/dev/null) \|\| {` | enumerate |
| 20 | `skills/execute/scripts/run-cascade.sh:781` | `git add "$new_path" 2>/dev/null \|\| git add "$target" 2>/dev/null \|\| true` | enumerate |
| 21 | `skills/execute/scripts/run-cascade.sh:788` | `git add "$target" 2>/dev/null \|\| true` | enumerate (occurrences=2) |
| 22 | `skills/execute/scripts/run-cascade.sh:794` | `git add "$target" 2>/dev/null \|\| true` | same record as #21 |
| 23 | `skills/execute/scripts/run-cascade.sh:838` | `jq -r '.error // empty' ... 2>/dev/null) \|\| errmsg=""` | enumerate |
| 24 | `skills/execute/koto-templates/execute.md:339` | `git checkout impl/$PLAN_SLUG 2>/dev/null \|\| git checkout -b ...` | enumerate (exit 1) |
| 25 | `skills/execute/koto-templates/execute.md:340` | `git push -u origin impl/$PLAN_SLUG 2>/dev/null \|\| true` | enumerate |
| 26 | `skills/execute/koto-templates/execute.md:390` | `koto context get ... 2>/dev/null \|\| echo "impl/$PLAN_SLUG"` | **R26 remediate** |
| 27 | `skills/execute/koto-templates/execute.md:409` | `koto context get ... 2>/dev/null \|\| echo "impl/$PLAN_SLUG"` | **R26 remediate** |

## Appendix B — the 6 additional sites in the AC-omitted shape (`>/dev/null 2>&1`)

Reproduced by `bash wip/scan_probe.sh skills omitted`.

| # | Site | Command | Class |
|---|---|---|---|
| 28 | `skills/plan/scripts/build-dependency-graph.sh:55` | `jq -e 'type == "array"' >/dev/null 2>&1` | enumerate |
| 29 | `skills/plan/scripts/create-issues-batch.sh:412` | `gh issue edit ... --body "$body" >/dev/null 2>&1` | enumerate |
| 30 | `skills/plan/scripts/render-template.sh:55` | `jq -e '.' >/dev/null 2>&1` | enumerate |
| 31 | `skills/plan/scripts/render-template.sh:60` | `jq -e '.complexity' >/dev/null 2>&1` | enumerate |
| 32 | `skills/plan/scripts/render-template.sh:64` | `jq -e '.goal' >/dev/null 2>&1` | enumerate |
| 33 | `skills/execute/scripts/run-cascade.sh:639` | `command -v shirabe >/dev/null 2>&1` | CARVE |

## Appendix C — excluded false positives

| Site | Why excluded |
|---|---|
| `skills/work-on/koto-templates/work-on.md:441` | `go test ./... 2>/dev/null` — `go` is not a declared tool. Matches only because `koto` appears in the *directory name*. Requires stripping `path:lineno:` before the tool test. |
| `skills/execute/koto-templates/execute.md:498` | `CASCADE_STATUS=$(... jq ...)` assigned and never referenced in shell, but read by the agent per adjacent prose. Basis for restricting the unread-variable arm to `*.sh`. |
| All 11 `2>&1 >/dev/null` hits | Every one is in `create-issues-batch_test.sh` or `plan-to-tasks_test.sh` — test files, excluded by rule. |
