---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-pre-action-denies.md
decision_provenance: inline-resolved
problem: |
  shirabe's rules that guard an irreversible action (opening or editing a
  pull request, pushing) are checked after the action. The one pre-action
  deny, `shirabe pr-body-hook`, is wired only by niwa, lets a command through
  whenever it can't decide, and reports the validator's message instead of
  the registered rule. The plugin declares no hooks, and nothing reads the
  registry at hook time, so a plugin-only user gets no deny at all.
decision: |
  The plugin ships `hooks/hooks.json`, a Bash-matched PreToolUse hook that
  runs `hooks/pre-action-deny.sh`. That script owns the off switch, finds
  the shirabe binary and runs `shirabe pre-action-hook --plugin-root`, and
  when the binary can't run it denies only commands its coarse text test
  says name a guarded action. The binary does the real work in a new
  `pre_action` module: one tokenizer for both entry points, PR-body checks
  mapped to registry ids through each entry's aliases, a local-git push
  check for `commit/no-ai-trailer`, deny reasons built from the registry
  the plugin ships, and a fail-closed deny for every case it can't decide.
  `shirabe pr-body-hook` becomes the same evaluator restricted to the
  PR-body rules, reading a registry built into the binary, and the plugin
  hook yields those rules to it when the host's settings wire it. Each
  guarded rule gains a `deny` registry field that check-rule-registry.sh
  cross-checks against the script's RULE_IDS line.
rationale: |
  A shell wrapper is the only piece that still runs when the binary is
  missing, so fail-closed on a missing binary has to live there, and only
  there; everything that needs a tokenizer, the validator or JSON stays in
  Rust, where the PR-body engine already is. Reading the registry at run
  time from the plugin root makes the deny carry the text of the plugin the
  agent is using, while the legacy entry point, which has no plugin root,
  falls back to the copy compiled into the same release. Yielding from the
  plugin side is the one direction that can be decided: the plugin hook can
  read the settings that wire the other entry point, and the other entry
  point can't see plugin hooks at all.
---

# DESIGN: Pre-action denies from shirabe

## Status

Proposed

## Context and Problem Statement

Claude Code runs every PreToolUse hook whose matcher fits the tool call,
in parallel, before the call runs. A hook blocks the call only by
printing a `deny` decision on exit 0 or by exiting 2; any other non-zero
exit, a crash or a timeout lets the call run. A plugin's hooks come from
`hooks/hooks.json` at the plugin root, with `${CLAUDE_PLUGIN_ROOT}`
expanded in the command and exported to the hook process. shirabe's
plugin declares none.

The one deny shirabe has is `shirabe pr-body-hook`
(`crates/shirabe/src/pr_body_hook.rs`). niwa injects it into a host's
settings as `command -v shirabe >/dev/null 2>&1 || exit 0; shirabe
pr-body-hook 2>/dev/null || exit 0`. It tokenizes the command without
evaluating it, pulls `--title`, `--body` and `--body-file` out of a `gh
pr create|edit`, runs `shirabe_validate::check_pr_body` (PB1 to PB4), and
denies with the validator's messages. Every case it can't decide allows:
an unreadable body file, `--fill`, a command substitution, a missing
binary. Nothing maps its findings to registry ids; the only mapping lives
in `skills/work-on/scripts/check-pr-output.sh` as message-substring
matches. Nothing in Rust reads `references/rule-registry.json`: the
summary, the line range and the `rule_ref` are computed by
`scripts/rule-registry.sh`, which needs bash and `jq`.

Nothing checks a push. The commit rules exist only in
`skills/work-on/scripts/check-branch-output.sh --commits`, over
`<base>..HEAD` at finalization, and the AI-attribution predicate they use
is a shell port of PB3's private Rust function `is_attribution_line`.

The PRD this design answers sets the behaviour. The plugin itself must
declare a Bash PreToolUse hook with a 30-second timeout (R1). It checks
only guarded commands (R2): a segment whose head, after `NAME=value`
words, is `gh` with `pr create|edit` as its first non-option words, or
`git` with `push`. On those it denies a broken PR-body rule, PB1 to PB4
or the `pr-body/conformance` catch-all (R3), and, on a push, a non-merge
outgoing commit carrying an AI-attribution line (R4), where the outgoing
commits are those reachable from what the push sends and not from the
target remote's tracking refs, in the directory the command runs in.
Each deny lists one block per broken rule, `<id>: <summary>: <detail>`
then `full text: <absolute path> lines <a>-<b>`, with the summary read at
run time from the registry the plugin ships (R5). It reads a body given
inline, from an existing file, or from a `$(cat <<'EOF' ... EOF)`
here-document (R6). It fails closed, with a reason naming the case and
the off switch `SHIRABE_PRE_ACTION_HOOK=off`, in nine named cases from a
missing binary to an unknown option (R7). It never blocks an unguarded
command while the binary runs, and with the binary missing blocks only
commands whose raw text names a guarded action (R8). `SHIRABE_PRE_ACTION_HOOK=off`
silences both entry points, and `PR_BODY_HOOK_DISABLE` keeps silencing
the PR-body part (R9). The offload canary's PB4 exception holds on both
entry points, read from the same opt-in file as today (R10). `shirabe
pr-body-hook` keeps working as niwa wires it (R11), and where both are
wired each broken rule is reported once, with the plugin hook leaving the
PR-body rules to the settings-wired one (R12). Every rule the hook denies
carries a `deny` registry field, cross-checked against the hook's
`RULE_IDS` line, with no `withhold` value changed (R13). Unguarded calls
start no `git` or `gh`; guarded ones run local git plumbing only (R14).
Untrusted text is never evaluated and comes back JSON-escaped, and the
hook writes no file (R15). The script holds to the bash 3.2 floor without
`jq` (R16), and the tests run through the declared command in CI (R17).

The technical problem is therefore four problems that touch each other:
where each piece of logic runs so that a missing binary still fails
closed; how the binary reads registry text it never read before; how a
push's outgoing commits are found from local state alone; and how two
entry points that run in parallel, without shared state, agree on which
one reports.

## Decision Drivers

- **A missing binary must still deny guarded commands** (R7 case 1, R8),
  so some logic must run with no shirabe binary at all, under bash 3.2
  and without `jq` (R16).
- **One tokenizer, one validator.** The PR-body engine is Rust today and
  is the implementation of record for PB1 to PB4; a second
  implementation of either would drift.
- **Registry text, not restated text** (R5): the reason's summary and
  line range come from `references/rule-registry.json` and the file its
  anchors name, in the plugin copy the agent is using.
- **Parallel hooks share nothing.** The two entry points run as separate
  processes at the same moment; any dedupe must be decidable by one side
  from what it can read.
- **Unguarded calls stay cheap and silent** (R8, R14): every Bash call
  pays for the hook, so the common path starts no `git` or `gh`.
- **Local and bounded** (R4, R7 case 8, R14): no network, at most 1,000
  commits walked, 20 seconds for the push check, inside a 30-second hook
  timeout.
- **Existing hosts keep working** (R11): niwa's inline wiring and its
  `|| exit 0` stay as they are; the repository can't change niwa here.
- **The registry stays the one place a rule is defined** (R13), and
  `scripts/check-rule-registry.sh` stays the one checker of it.

## Considered Options

### Decision 1: Where the hook's logic runs

Resolved inline.

The PRD needs a deny when the binary is missing, which no compiled code
can produce, and a precise tokenizer and the PR-body validator, which
exist only in Rust. The question is how to split the work between a
command the plugin declares and the binary.

Key assumptions:

- The shirabe binary is on `PATH` or at `~/.shirabe/bin/shirabe`, where
  `install.sh` installs it, on any host that runs shirabe's skills.
- An older binary rejects an unknown subcommand with a non-zero exit
  (clap exits 2), which the wrapper can observe.

#### Chosen: A thin bash wrapper in front of a new binary subcommand

`hooks/hooks.json` runs `"${CLAUDE_PLUGIN_ROOT}/hooks/pre-action-deny.sh"`
with `timeout: 30`. The script reads stdin once, returns at once with no
decision when `SHIRABE_PRE_ACTION_HOOK` is `off`, finds the binary, and
runs `shirabe pre-action-hook --plugin-root "$CLAUDE_PLUGIN_ROOT"` with
the input on stdin. When the binary exits 0 and prints nothing or one
line that opens `{"hookSpecificOutput":`, the script passes that through.
Otherwise (no binary, a non-zero exit, other output) it applies the
coarse "named in the text" test to the raw input and either prints a
fixed deny naming the binary, built with `printf` from constant text and
the rule ids on its own `RULE_IDS` line, or prints nothing. The script
never interpolates the input into its output.

#### Alternatives Considered

- **`hooks.json` runs the binary directly.** Simplest, but a missing
  binary makes the hook command fail with 127, which Claude Code treats
  as a non-blocking error: the guarded command runs. Rejected because it
  can't meet R7 case 1.
- **`hooks.json` with `onFailure: "block"`.** Makes any hook failure
  block, including on `ls` when the binary is missing. Rejected under
  R8: it blocks commands the hook doesn't guard.
- **All logic in shell with `jq`.** Would need a second tokenizer and a
  second PR-body validator in bash, and `jq` on every host. Rejected
  under the one-validator driver and R16.

### Decision 2: How the binary evaluates commands and reads the registry

Resolved inline.

Both entry points must tokenize the same way, map validator findings to
registry ids, read the registry, and build the same reason shape. The
question is the module layout, how findings become ids, and where the
registry comes from.

Key assumptions:

- Registry entries for PB1 to PB4 keep `aliases` `PB1` to `PB4`, which
  the checker keeps unique.
- The binary and the plugin come from the same release tag, so a copy of
  the registry compiled into the binary matches the plugin's files of
  that release.

#### Chosen: A shared `pre_action` module, alias-keyed findings, the plugin's registry with a compiled-in fallback

A new module, `crates/shirabe/src/pre_action/`, holds the tokenizer
(moved out of `pr_body_hook.rs` and extended to split on newline and
parentheses and to keep raw segment text for here-documents), the
command classifier, the body reader, the PR-body check, the push check,
the registry reader and the reason renderer. `shirabe pre-action-hook
--plugin-root <dir>` runs it with every rule; `shirabe pr-body-hook`
becomes a thin call into it with the PR-body rules only and the
compiled-in registry.

`shirabe_validate::PrBodyFinding` gains a `code: &'static str` field
(`"PB1"` to `"PB4"`, or `""` for a finding outside them), set where each
finding is built. The evaluator maps a code to the active registry entry
whose `aliases` contains it, and an empty code to `pr-body/conformance`,
so the registry, not a message match, decides the id.
`is_attribution_line` becomes public so the push check uses PB3's own
predicate.

The registry reader parses `<plugin-root>/references/rule-registry.json`
with `serde_json`, finds an active entry by id, and resolves its `text`
anchors the way `rule-registry.sh range` does: the first anchor on
exactly one line, the last anchor on the first line at or after it. It
refuses a `text.path` that isn't a relative path under the plugin root
or is a symlink, as `safe_path` does. The legacy entry point uses the
same reader over two `include_str!` copies, the registry and
`references/pr-body-conformance.md`, and names the file by its
repository-relative path.

#### Alternatives Considered

- **Shell out to `scripts/rule-registry.sh`.** Reuses the one existing
  reader, but needs bash and `jq` at hook time and one process per rule.
  Rejected: `jq` isn't guaranteed (R16 already rules it out for the
  script) and it would add a failure mode to every guarded call.
- **Map findings by message text, as `check-pr-output.sh` does.** No
  change to `shirabe-validate`, but a reworded message silently changes
  the id. Rejected in favour of a code set where the finding is built.
- **Compiled-in registry for both entry points.** No plugin-root
  dependency, but the deny would carry the binary's text even when the
  plugin is newer, and an unreadable registry could never be reported.
  Rejected under R5; kept only as the legacy entry point's source.

### Decision 3: How a push's outgoing commits are found

Resolved inline.

R4 fixes the semantics: the non-merge commits reachable from what the
push sends and not from the target remote's tracking refs, in the
directory the command runs in, bounded at 1,000 commits and 20 seconds,
with local git only.

Key assumptions:

- `git` is on `PATH` wherever a `git push` can run.
- Remote-tracking refs are reasonably current; a stale ref can only make
  the check look at more commits, never fewer.

#### Chosen: Parse the push argv, then one bounded `git log`

The classifier yields the push's words after `push`. The push check
parses them against the option list R4 names (anything else fails
closed), takes the remote from the first positional word or
`--repo=<r>`, and the sources from the remaining words, from `--all`,
`--branches`, `--tags` or `--mirror`, or from the current branch. It
resolves the remote when none is given from `branch.<b>.pushRemote`,
`remote.pushDefault`, `branch.<b>.remote`, then `origin`, through `git
config --get`. Each source is resolved with `git rev-parse --verify
--quiet <src>^{commit}`. The commits come from one call:

```text
git log --no-merges --max-count=1001 --format=%H%x1f%s%x1f%B%x1e \
    <source commits...> --not --remotes=<remote>
```

with `--remotes` alone when the remote has no tracking refs (`git
for-each-ref --count=1 refs/remotes/<remote>/` prints nothing) or isn't
a configured remote. 1,001 records means the bound is passed. Every git
call runs with `GIT_DIR`, `GIT_WORK_TREE` and the other location
variables cleared, `GIT_CONFIG_NOSYSTEM=1`, `-c core.fsmonitor=false -c
core.hooksPath=/dev/null`, `-C <dir>`, stdin closed, and a deadline: the
check spawns each child and polls `try_wait`, killing it when the
20-second budget (`SHIRABE_PRE_ACTION_GIT_TIMEOUT` overrides it, for
tests) runs out.

The directory starts at the input's `cwd`. The classifier walks the
segments in order; a segment whose head is `cd` or `pushd` with one
literal word moves it, and `cd` with no word, `-`, a word holding `$`,
a backquote or a leading `~`, or `popd` makes it unknown. A guarded
segment then applies its own `-C` words. `git rev-parse
--show-toplevel` failing there is the "not a work tree" case.

#### Alternatives Considered

- **`<default branch>..HEAD`, as the finalization gate does.** Matches
  existing code, but checks commits the remote already has on a long
  branch and misses a push of another branch. Rejected under R4.
- **Ask the remote (`git push --dry-run --porcelain`, `ls-remote`).**
  Exact, but it's a network call, may prompt for credentials, and can
  run the remote's helpers. Rejected under R14.
- **`git rev-list` then one `git log -1` per commit.** What the shell
  check does; a process per commit. Rejected for cost on a long push.

### Decision 4: How the two entry points agree on who reports

Resolved inline.

On a niwa host both the plugin hook and the settings-wired `shirabe
pr-body-hook` run on every Bash call, in parallel, as separate
processes. R12 requires one report per broken rule.

Key assumptions:

- niwa wires the legacy hook as a PreToolUse command in a settings file
  Claude Code reads: `~/.claude/settings.json`, or `.claude/settings.json`
  or `.claude/settings.local.json` under the project directory.
- `CLAUDE_PROJECT_DIR` is set in a hook's environment when Claude Code
  knows the project directory.

#### Chosen: The plugin hook reads the settings and yields the PR-body rules

On a guarded `gh pr` command, the plugin hook reads those three files
(under `$CLAUDE_PROJECT_DIR`, else under the input's `cwd`), parses each
with `serde_json`, and looks for a `hooks.PreToolUse[].hooks[].command`
string containing `shirabe pr-body-hook`. When it finds one it skips the
PR-body rules and their fail-closed cases for that call; the legacy entry
point, now the same evaluator, reports them in the same shape. A file it
can't read or parse counts as no wiring, so the worst failure is a
duplicate report, never a missing one. A push is always the plugin
hook's.

#### Alternatives Considered

- **The legacy entry point yields when the plugin's hook is active.**
  It can't tell: plugin hooks aren't in the settings files, and the
  places Claude Code records installed plugins aren't a documented
  interface. Rejected.
- **A SessionStart marker written by the plugin, read by the legacy
  entry point.** Deterministic, but it writes a file per session (R15
  says the hook writes nothing), and a marker outlives a plugin disabled
  mid-session, silencing the only remaining check. Rejected.
- **Stop niwa injecting the hook.** The real fix in the long run, but it
  is a change to another repository and leaves every host on an older
  niwa reporting twice. Rejected for this feature; a follow-up for niwa
  to stop injecting once its hosts run a plugin that ships the hook is
  proposed in the pull request.
- **Accept two reports.** No mechanism at all, and both entry points
  would say the same thing. Rejected under R12.

### Decision 5: How the registry links a rule to the hook

Resolved inline.

R13 asks for a registry field per guarded rule naming the hook and the
actions it denies before, checked both ways against what the hook
actually denies.

Key assumptions:

- `scripts/check-rule-registry.sh` tolerates an unknown optional field
  today (it checks required fields, not an allow-list), so adding one
  breaks no existing entry.
- The checker already parses `RULE_IDS="..."` lines under `skills/` and
  `scripts/`.

#### Chosen: An optional `deny` field and a RULE_IDS line in the hook script

Each guarded rule gets `"deny": {"hook": "hooks/pre-action-deny.sh",
"before": ["pr-create"]}` (`["push"]` for `commit/no-ai-trailer`). The
script carries `RULE_IDS="pr-body/conventional-title
pr-body/one-separator pr-body/no-ai-trailer pr-body/no-heading-in-part1
pr-body/conformance commit/no-ai-trailer"`. The checker gains a check:
`deny` is an object whose `hook` is a safe relative path to an existing
file and whose `before` is a non-empty list of protected actions; every
id on a hook script's RULE_IDS line has a `deny` naming that script; and
every `deny` names a script whose line lists the id. Its RULE_IDS scan
extends to `hooks/`. A Rust test reads the script's RULE_IDS line and
asserts it equals the evaluator's rule table, so the code, the script
and the registry can't drift apart. `references/rule-registry.md`
documents the field.

#### Alternatives Considered

- **Make `check` a list.** Says "this rule has two checks" literally,
  but every reader of `check` changes, and the schema with them.
  Rejected as a larger change for the same information.
- **Have the binary print its table (`--list-rules`) for the checker.**
  Exact, but the registry check would need a built binary, and it runs
  in a workflow that builds none. Rejected.

## Decision Outcome

The five decisions make one pipeline. Claude Code runs the plugin's
script on every Bash call (Decision 1). The script handles the two
things only it can, the off switch and a binary that can't run, and
otherwise hands the input to `shirabe pre-action-hook`. The binary
classifies the command with the tokenizer both entry points now share
(Decision 2); an unguarded command ends there with nothing printed and
no process started. A guarded `gh pr` command is checked by the
existing validator, its findings turned into registry ids through their
PB codes, unless the host's settings wire the legacy hook, in which case
the plugin side leaves it to that hook (Decision 4). A guarded push is
checked against its outgoing commits, found with one bounded `git log`
(Decision 3). Every deny is rendered from the registry the plugin ships,
and every rule that can produce one is linked in the registry and
checked against the script and the code (Decision 5).

The pieces trade a small amount of duplication for the fail-closed
guarantee: the script's coarse test is a second, cruder classifier, kept
deliberately cruder and used only when the precise one can't run.

## Solution Architecture

### Overview

```text
Claude Code (PreToolUse, matcher Bash, timeout 30)
  -> hooks/pre-action-deny.sh            bash 3.2, no jq
       SHIRABE_PRE_ACTION_HOOK=off ? -> no decision
       find shirabe (PATH, ~/.shirabe/bin/shirabe)
       run: shirabe pre-action-hook --plugin-root "$CLAUDE_PLUGIN_ROOT"
         ok (exit 0, empty or one deny line) -> print it
         else -> coarse test on raw input
                   names a guarded action -> fixed "binary" deny
                   otherwise              -> no decision
  -> shirabe pre-action-hook (crates/shirabe/src/pre_action/)
       parse input -> classify segments -> for each guarded segment:
         gh pr create|edit -> body reader -> check_pr_body / check_pr_title
         git push          -> push argv -> outgoing commits -> trailer test
       -> findings and fail-closed cases -> reason from registry -> deny

niwa host, in parallel:
  command -v shirabe ... ; shirabe pr-body-hook ... || exit 0
  -> same evaluator, PR-body rules only, compiled-in registry
```

### Components

- **`hooks/hooks.json`.** One `PreToolUse` entry, matcher `Bash`, one
  command hook: `"${CLAUDE_PLUGIN_ROOT}/hooks/pre-action-deny.sh"`,
  `timeout: 30`. No `onFailure`.
- **`hooks/pre-action-deny.sh`.** Reads stdin into a variable (`cat`),
  checks the off switch, finds the binary, runs it with a here-string
  feeding the saved input, and checks its exit status and that its output
  is empty or one line starting `{"hookSpecificOutput":`. On anything
  else it runs the coarse test: the raw input, lowercased, matched with
  `grep -E` for `(^|[^a-z0-9_-])gh([^a-z0-9_-].*)?[^a-z0-9_-]pr[^a-z0-9_-](.*[^a-z0-9_-])?(create|edit)([^a-z0-9_-]|$)`
  and the `git` ... `push` equivalent. On a match it prints a constant
  deny built with `printf`, naming the binary, the install command, the
  ids from its `RULE_IDS` line and `SHIRABE_PRE_ACTION_HOOK=off`; else
  nothing. It always exits 0. Declares `RULE_IDS="..."` (Decision 5).
- **`crates/shirabe/src/pre_action/mod.rs`.** `run_plugin(root)` and
  `run_legacy()` entry points; `evaluate(input, ctx) -> Option<Decision>`
  with `ctx` carrying the rule set, the registry source, the canary probe,
  the settings probe, the environment and the git runner, so tests
  inject each.
- **`tokenize.rs`.** The quote-aware tokenizer from `pr_body_hook.rs`,
  extended: segments end at unquoted `;`, `&`, `|`, newline, `(` and `)`;
  each segment keeps its words and its byte span in the raw command;
  `$'` starts an opaque word the body reader refuses.
- **`classify.rs`.** Walks segments, tracks the directory (R4's `cd`,
  `pushd`, `popd` rules), skips `NAME=value` words, and returns each
  guarded segment as `Gh { words_after_action, action, dir }` or `Git {
  words_after_push, dir, git_c_dirs }`, or a fail-closed case for an
  unlisted global option.
- **`body.rs`.** Reads `--title`/`-t` and `--body`/`-b`/`--body=`,
  `--body-file`/`-F`/`--body-file=`; detects the here-document form in
  the segment's raw span (`$(cat <<` followed by an optional `-`, a
  delimiter quoted with `'` or `"` or bare, a newline, lines, a line equal
  to the delimiter, `)`), returns its lines byte for byte, and refuses an
  unquoted-delimiter body holding `$` or a backquote; refuses every form
  R7 case 4 lists with the form's name.
- **`push.rs`.** R4's argv parse, remote resolution, source resolution
  and the bounded `git log`, through a `GitRunner` trait whose real
  implementation spawns `git` with the sanitized environment and the
  deadline.
- **`registry.rs`.** `Registry::from_plugin_root(dir)` and
  `Registry::embedded()`; `entry(id)`, `by_alias(code)`,
  `range(entry) -> (path, first, last)`. Errors carry the id and what
  failed, for R7 case 6.
- **`reason.rs`.** Renders R5's blocks in registry order and R7's
  fail-closed text; returns a `String` that `emit_deny` places in a
  `serde_json` value.
- **`settings.rs`.** R12's probe: the three settings files, parsed, the
  command strings scanned for `shirabe pr-body-hook`.
- **`crates/shirabe/src/pr_body_hook.rs`.** Shrinks to `run()`, which
  checks `SHIRABE_PRE_ACTION_HOOK` and `PR_BODY_HOOK_DISABLE` and calls
  `pre_action::run_legacy()`; its tests move to the module with their
  decisions kept, except the five fail-open ones the PRD lists, which
  flip to deny.
- **`crates/shirabe-validate/src/pr_body.rs`.** `PrBodyFinding.code`;
  `pub fn is_attribution_line`.
- **`references/rule-registry.json`.** `deny` on the six rules.
- **`scripts/check-rule-registry.sh`** and its test suite: the new
  check, the `hooks/` scan.
- **`hooks/pre-action-deny_test.sh`.** The end-to-end suite: reads the
  command from `hooks/hooks.json` with `sed`, runs it with
  `CLAUDE_PLUGIN_ROOT` at the repository, a scratch `HOME`, `TMPDIR`
  and git repositories, stub `git`, `gh` and `shirabe` binaries where a
  case needs them, and `PATH` without `jq`.
- **`.github/workflows/build-and-test.yml`.** A step after the release
  build that runs the hook suite with `target/release` first on `PATH`.
  `check-rule-registry.yml` adds `hooks/**` and `crates/**` to its paths.

### Key Interfaces

```text
shirabe pre-action-hook --plugin-root <dir>    stdin: PreToolUse JSON
shirabe pr-body-hook                           stdin: PreToolUse JSON
  stdout: nothing, or one line
    {"hookSpecificOutput":{"hookEventName":"PreToolUse",
     "permissionDecision":"deny","permissionDecisionReason":"<reason>"}}
  exit: 0 always
```

```rust
// shirabe-validate
pub struct PrBodyFinding { pub line: usize, pub code: &'static str, pub message: String }
pub fn is_attribution_line(line: &str) -> bool;

// shirabe::pre_action
pub enum RuleSet { All, PrBodyOnly }
pub enum RegistrySource { PluginRoot(PathBuf), Embedded }
pub struct Ctx<'a> {
    pub rules: RuleSet,
    pub registry: RegistrySource,
    pub canary_opted_in: &'a dyn Fn() -> bool,
    pub legacy_wired: &'a dyn Fn(&Path) -> bool,
    pub git: &'a dyn GitRunner,
    pub git_budget: Duration,
}
pub fn evaluate(input: &str, ctx: &Ctx) -> Option<String>; // the reason
const RULES: &[&str] = &[ /* equals the script's RULE_IDS line */ ];
```

Reason text, per broken rule and per fail-closed case:

```text
shirabe denied this `gh pr create` before it ran.

pr-body/one-separator: The pull request body needs exactly one --- separator and a non-empty Part 1: the PR body has no `---` separator. ...
  full text: /…/references/pr-body-conformance.md lines 52-58

shirabe could not check this `git push` (directory: `cd "$DIR"` isn't a literal path), so it is denied.
It is guarded by: commit/no-ai-trailer.
Fix: run the push from the repository's directory, or with `git -C <path>`.
To turn the check off: set SHIRABE_PRE_ACTION_HOOK=off in the host's settings env.
```

The registry field:

```json
"deny": {"hook": "hooks/pre-action-deny.sh", "before": ["pr-create"]}
```

### Data Flow

A hook call reads one JSON document on stdin and writes at most one JSON
line on stdout. The plugin's binary reads, beyond stdin: the registry and
the files its anchors name under the plugin root; on a guarded `gh pr`
command, a `--body-file` and, for R12, three settings files; on a
guarded push, the repository through `git` plumbing; for R10, the
canary opt-in file. It writes nothing. The legacy entry point reads the
same except the plugin root and the settings files. No state outlives a
call.

## Implementation Approach

### Phase 1: Validator codes and the shared predicate

Add `code` to `PrBodyFinding` and set it where each finding is built;
make `is_attribution_line` public. Existing tests pass unchanged, plus
one asserting each code.

Deliverables:

- `crates/shirabe-validate/src/pr_body.rs`

### Phase 2: The evaluator and the two entry points

Move the tokenizer into `pre_action`, extend it, and add the classifier,
body reader, registry reader, reason renderer, settings probe and push
check, each with unit tests. Add the `pre-action-hook` subcommand and
point `pr-body-hook` at `run_legacy`.

Deliverables:

- `crates/shirabe/src/pre_action/{mod,tokenize,classify,body,push,registry,reason,settings}.rs`
- `crates/shirabe/src/pr_body_hook.rs`, `crates/shirabe/src/main.rs`

### Phase 3: The plugin hook and its suite

Add `hooks/hooks.json`, `hooks/pre-action-deny.sh` and
`hooks/pre-action-deny_test.sh`, and the CI step.

Deliverables:

- `hooks/hooks.json`, `hooks/pre-action-deny.sh`, `hooks/pre-action-deny_test.sh`
- `.github/workflows/build-and-test.yml`

### Phase 4: Registry links and the checker

Add `deny` to the six entries, the checker's new check and `hooks/`
scan with fixtures in its suite, the Rust test tying `RULES` to the
script's line, and the docs: `references/rule-registry.md`, a section in
`docs/guides/offload-live-canary.md` saying the PB4 exception now holds
in the plugin hook too, and the plugin README's mention of the hook and
its off switch.

Deliverables:

- `references/rule-registry.json`, `references/rule-registry.md`
- `scripts/check-rule-registry.sh`, `scripts/check-rule-registry_test.sh`,
  `.github/workflows/check-rule-registry.yml`
- `docs/guides/offload-live-canary.md`, `README.md`

## Security Considerations

To be completed in the security review.

## Consequences

### Positive

- Every plugin user gets the denies with no settings change, and every
  deny names a registered rule in its own words.
- A broken install is visible: a guarded command fails with the cause
  instead of passing unchecked.
- The PR-body finding-to-rule mapping is set where findings are built,
  not inferred from message text.
- A push can no longer carry an AI-attribution trailer to a remote
  unnoticed.

### Negative

- A plugin user without the binary can't open a pull request or push
  through the agent until they install it or turn the hook off.
- Every Bash call starts the shirabe binary once (about a millisecond of
  process start); a guarded push adds a few git calls.
- Two classifiers exist: the precise one and the script's coarse test.
- Dedupe depends on niwa keeping `shirabe pr-body-hook` in a command
  string in one of three settings files.
- A host whose binary is older than its plugin is denied on every
  guarded command until the binary is upgraded.

### Mitigations

- The missing-binary deny names the install command and the off switch.
- The unguarded path runs no git and reads no file.
- The coarse test is used only when the binary can't run, and its tests
  pin which commands it denies.
- If the settings shape changes, the failure mode is a duplicate report,
  not a missing one; a follow-up for niwa to stop injecting is proposed.
- Release notes say the plugin's hook needs the binary from the same
  release.
