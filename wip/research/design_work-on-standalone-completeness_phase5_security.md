# Security Review: DESIGN-work-on-standalone-completeness

## Verdict

CONCERNS (findings that must be addressed).

## Findings

### 1. Template interpolation reaching a shell

`{{KEY}}` substitution in koto is a literal, sequential `str::replace` into
the field text (`koto/src/engine/substitute.rs:358-421`,
`koto/src/cli/vars.rs:22-35`), and a gate's resolved `command:` string is
handed to `Command::new("sh").arg("-c").arg(command)` verbatim
(`koto/src/action.rs:163-165`). For a `ShellWord`-form field (which is what
`substitute_gate_fields` uses for `command`, `koto/src/cli/mod.rs:3149`), a
non-empty value is emitted **unescaped** — "quoting a value that may contain
spaces stays the template author's responsibility"
(`koto/src/engine/substitute.rs:317-319`). Taken alone, this would make
`{{ISSUE_NUMBER}}` in a gate `command:` a real injection point.

But every value that can reach a `{{KEY}}` substitution — whether set via
`koto init --var` or captured from a state's stdout — passes through
`validate_value` against an allowlist regex first
(`koto/src/engine/substitute.rs:502-514`, called at `cli/mod.rs:881` for
`--var` and inside `Variables::from_events` for captures,
`koto/src/engine/substitute.rs:266-274`). The allowlist rejects `;`, `` ` ``,
`$(`, `${`, `|`, `&`, `>`, `*`, newlines, and both quote characters
(`koto/src/engine/substitute.rs:565-580`). `ISSUE_NUMBER` is declared exactly
like any other template variable in `work-on.md:16-18`
(`required: false`, no additional pattern), so it goes through this same
gate. This means the design's proposed anchor gate is **not exposed to shell
injection through `{{ISSUE_NUMBER}}`** — that surface is closed structurally
by koto itself, independent of anything the template author writes, and
independent of whether the anchor search is "anchored" or not. There is
also an existing precedent for `{{ISSUE_NUMBER}}` reaching a gate command
unanchored today: `staleness_check`'s `command: "check-staleness.sh --issue
{{ISSUE_NUMBER}} | jq -e ..."` (`work-on.md:325`) has shipped with the same
substitution shape.

What "anchor the pattern" actually buys, given the above, is not injection
safety but **match correctness**: an unanchored search over `docs/plans/`
risks a substring collision (issue `4` matching inside `42`, or inside an
unrelated dependency-column reference), which would hand `run-cascade.sh` a
plausible but wrong PLAN path — a false positive the design's own Decision 2
section names as the failure direction it does *not* want to accept (it
explicitly prefers false-negative "no anchor" over this). This is a real and
correctly-identified risk, but it is a correctness/wrong-document risk, not
a shell-injection risk, and `check-template-interpolation.sh` does not check
for it — that script only flags bare `$VAR`/`${VAR}` shell-style references,
not whether a `{{KEY}}` reference is embedded in an anchored vs. unanchored
pattern (`scripts/check-template-interpolation.sh:15-23`). There is no
mechanical check that will catch an unanchored pattern; it depends on
implementation-time care when the actual gate command is written (the design
is at the architecture level and does not commit to exact command text).

### 2. Path handling in the relocation

`run-cascade.sh` derives `REPO_ROOT` via `git rev-parse --show-toplevel`
(`run-cascade.sh:750`), never from its own `$0`/`BASH_SOURCE` location, so
the relocation changes nothing about the script's internal path logic.
`assert-child-template.sh` resolves `${CLAUDE_PLUGIN_ROOT}` with a
same-shell fallback to its own directory (`assert-child-template.sh:22`) and
fails closed (exit 1) before any child is spawned
(`skills/execute/SKILL.md:163-174`, "Step 1"). That is a real, load-bearing,
"loud and early" guard for the *existing* cross-skill dependency
(`/execute` → `work-on.md`).

The design does not commit to an equivalent guard for the *new* cross-skill
dependency this design creates (`/execute` → `skills/work-on/scripts/run-
cascade.sh`, previously a same-skill path). The Components table and
Implementation Approach only list "invocation path updated to the relocated
script" for `execute.md` — no update to `assert-child-template.sh` (or a new
assertion) to also verify the relocated script resolves. Today,
`run-cascade.sh` is invoked from a plain agent-executed directive inside
`plan_completion` (`execute.md:709`, not a koto gate), so a missing or
misresolved `${CLAUDE_PLUGIN_ROOT}` produces a bare "command not found" deep
inside the cascade state — after the pre-cascade probe has already run —
rather than at Step 1 before anything is touched. This is exactly the
failure shape the codebase already treats as a hazard elsewhere
(`skills/execute/SKILL.md:83-84`: "a missing script or an unexpanded
`${CLAUDE_PLUGIN_ROOT}` exits 127, and an unguarded 127 ... kills a run
mid-cascade"). It is not an injection or privilege-escalation risk — no
attacker-controlled input assembles the path — but it is a regression in
failure posture relative to the pattern the design's own Security
Considerations section names as precedent, and it is worth closing before
this ships, since the whole point of Decision 1 is to make this the third
instance of a shape the repo already has tooling for.

### 3. The cascade script's injection surface

No `eval`, and no document-content or filename value is concatenated into a
shell command unquoted. The two `awk` rewrites (`run-cascade.sh:526-573`)
pass values through `ENVIRON` rather than `-v`, which the script's own
comments flag as a deliberate choice ("use ENVIRON not -v") — this avoids
the classic `awk -v` backslash-reprocessing pitfall, and the value never
becomes part of the awk *program* text either way. `grep -n -F "$plan_slug"`
(`run-cascade.sh:503`) uses `-F` (fixed string), so a slug containing regex
metacharacters can't widen the match. The `jq -r` derived `target`/`new_path`
values from `finalize-chain`'s report are always double-quoted at their `git
add` call sites (`run-cascade.sh:895-919`) — no unquoted expansion. The
finalization commit message is a fixed literal string, `"chore(cascade):
post-implementation artifact transitions"` (`run-cascade.sh:1039`), never
built from document content, so there's no commit-message injection surface
either. Giving the script a second caller (`/work-on`) does not change any
of this: the script's own trust boundary is unchanged — it still requires a
tracked, non-symlink, in-repo path (`validate_upstream_path`,
`run-cascade.sh:97-130`), regardless of who supplies it. The six known no-op
defects (out of scope here) are pre-existing correctness bugs, not
injection points — none of them involve unsanitized data reaching a shell.

### 4. Reading a commit as evidence

The precedent already in the test suite is `git show --name-status --format=
HEAD` (`run-cascade_test.sh:2102`), a read-only porcelain command. Git's own
output quoting (`core.quotepath`) escapes control characters and wraps
unusual filenames in quotes, so a crafted filename can't inject a literal
newline into the path listing and spoof an extra entry. Filenames under
`docs/` are produced by this repo's own document tooling (kebab-case slugs),
not by external/attacker input, and reaching the point where a crafted
filename, branch name, or commit message could matter at all requires
commit access to the repo already — at which point an attacker has strictly
more direct ways to cause damage than tampering with evidence-reading. This
matches the design's own conclusion, and I agree with it: no meaningful
exposure here.

## On the design's own Security Considerations section

Partially agree, with two things it gets wrong or omits.

It correctly scopes the surface to injection and path handling rather than
auth/data handling, correctly identifies that the anchor gate's value is the
one to worry about, and its choice to read evidence from git rather than
from the cascade script's own report is a good call for exactly the reason
given — a value the script controls should not become a security-relevant
input.

What it misses: it attributes `{{ISSUE_NUMBER}}`'s safety to template-author
discipline ("anchor the pattern... is the same discipline `/execute` applies
to `execution_mode`") without mentioning that koto's own variable pipeline
already rejects every shell metacharacter before a value can reach
`{{ISSUE_NUMBER}}` at all (Finding 1). That's the actually load-bearing
defense, and it's structural, not a matter of author care. The
`execution_mode` analogy is also weaker than it sounds: `execution_mode` is
read by the agent from document frontmatter and re-validated by *prose
instruction* the agent is trusted to follow (`SKILL.md:52-55`) — a
discipline that can be skipped by a careless run. `{{ISSUE_NUMBER}}`'s
protection is enforced by the runtime regardless of what any session does.
Conflating the two makes the section understate how safe the interpolation
already is, while simultaneously not naming the one thing "anchor the
pattern" is actually defending against (false-positive PLAN selection, not
injection).

It also asserts a guard-shape precedent ("the existing guard shape ...
`assert-child-template.sh` ... is the precedent for the relocated script")
that the design does not actually commit to implementing anywhere in
Solution Architecture or Implementation Approach (Finding 2). As written,
the section reads as if the guard already extends to the relocated path; it
doesn't yet.

## Recommended changes

1. Add a fail-closed existence assertion for the relocated
   `run-cascade.sh` at its new cross-skill path, run before `plan_completion`
   does anything (extend `assert-child-template.sh` to check both paths, or
   add a sibling check run at the same Step-1 point), so a broken
   `${CLAUDE_PLUGIN_ROOT}` resolution fails before any cascade mutation
   rather than mid-cascade. This is a direct consequence of Decision 1
   (making `/execute` → `run-cascade.sh` a third instance of the cross-skill
   pattern) and should get the same guard the other two instances have.

2. Revise the Security Considerations paragraph on interpolation to name the
   actual mechanism: koto's `validate_value` allowlist closes the shell-
   injection surface for any declared/captured variable, including
   `ISSUE_NUMBER`, before substitution ever happens. Reframe "anchor the
   pattern" explicitly as a false-positive/wrong-document-selection
   safeguard rather than an injection safeguard, and note that no mechanical
   check enforces it (`check-template-interpolation.sh` does not), so the
   actual gate command's anchoring needs to be checked in review when it's
   written.
