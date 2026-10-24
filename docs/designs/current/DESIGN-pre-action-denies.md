---
schema: design/v1
status: Current
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
upstream: docs/prds/PRD-pre-action-denies.md
user_visible_surface: true
decision_provenance: inline-resolved
---

# DESIGN: Pre-action denies from shirabe

## Status

Current

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

The PRD this design answers, `docs/prds/PRD-pre-action-denies.md`,
sets the behaviour in R1 to R17 and its example table: which commands
are guarded, which rules are checked on each, the reason's shape, the
twelve fail-closed cases, the off switches, the canary exception, the
legacy entry point and the registry link. Each decision below states
the requirement it answers where it answers it.

The technical problem is four problems that touch each other: where
each piece of logic runs so that a missing binary still fails closed;
how the binary reads registry text it never read before; how a push's
outgoing commits are found from local state alone; and how two entry
points that run in parallel, without shared state, agree on which one
reports.

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

- The shirabe binary is on `PATH` or at `$HOME/.shirabe/bin/shirabe`, where
  `install.sh` installs it, on any host that runs shirabe's skills.
- An older binary rejects an unknown subcommand with a non-zero exit
  (clap exits 2), which the wrapper can observe.

#### Chosen: A thin bash wrapper in front of a new binary subcommand

`hooks/hooks.json` runs `bash "${CLAUDE_PLUGIN_ROOT}/hooks/pre-action-deny.sh"`
with `timeout: 30`. Naming `bash` and quoting the path means a lost
executable bit or a space in the plugin's path can't make the hook fail
to start, which Claude Code would treat as a pass. The script reads stdin once into a variable,
returns at once with no decision when `SHIRABE_PRE_ACTION_HOOK` is
`off`, finds the binary (each absolute directory on `PATH`, skipping
relative entries so a repository can't plant one, then
`$HOME/.shirabe/bin/shirabe`), and pipes the input with `printf '%s'` into
`shirabe pre-action-hook --plugin-root "$CLAUDE_PLUGIN_ROOT"`. A pipe,
not a here-string: bash 3.2 to 5.0 back a here-string with a temporary
file, which would write to disk and fail when `TMPDIR` isn't writable.
When the binary exits 0 and prints nothing, or exactly one line that
starts `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",`,
the script passes it through; any other output, `allow` and `ask`
included, is treated as a binary that can't run, so a broken or hostile
binary can't approve a command. Otherwise (no binary, a non-zero exit,
other output) it applies the coarse "named in the text" test to the raw
input and either prints a fixed deny naming the binary, built with
`printf` from constant text and the rule ids on its own `RULE_IDS` line,
or prints nothing. The script never interpolates the input into its
output.

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

#### Chosen: Parse the push argv, then two bounded plumbing calls

The classifier yields the push's words after `push`. The push check
parses them against the option list R4 names (anything else fails
closed), takes the remote from the first positional word or
`--repo=<r>`, and the sources from the remaining words, from `--all`,
`--branches`, `--tags` or `--mirror`, or from the current branch. It
resolves the remote when none is given from `branch.<b>.pushRemote`,
`remote.pushDefault`, `branch.<b>.remote`, then `origin`, through `git
config --get`. A push word holding an expansion, a glob character or a
brace list fails closed, since the shell would rewrite it before git
saw it. A source word starting with `-` fails closed; each
other source is resolved with `git rev-parse --verify --quiet
--end-of-options <src>^{commit}`, and only a 40- or 64-character
hexadecimal answer is accepted. The commits come from two plumbing
calls:

```text
git rev-list --no-merges --max-count=1001 <object ids...> --not --remotes=<remote>
git cat-file --batch          # stdin: those ids, one per line
```

with `--remotes` alone when the remote has no tracking refs (`git
for-each-ref --count=1 refs/remotes/<remote>/` prints nothing) or isn't
a configured remote. The ids on `rev-list`'s command line are the
hexadecimal ids `rev-parse` returned, never the words the agent typed,
so nothing there can be read as an option. A remote word outside
`^[A-Za-z0-9._-]+$` never reaches `--remotes=`, where it would be a glob:
it is read as a URL or a path and checked against every remote with
`--remotes` alone, and it fails closed only when `remote.<word>.url` is
configured, a named remote whose name the check can't pass on. 1,001 ids
means the bound is passed. `cat-file
--batch` returns each raw commit object with its length in a header, so
no byte in a message can break the framing, and the check splits the
message from the headers at the first blank line and caps the total at
16 MiB.

Every git call runs from a fixed environment rather than the hook's: it
keeps only `PATH` (its absolute entries, so a repository can't plant a
`git`), `HOME`, `XDG_CONFIG_HOME` and `GIT_CONFIG_GLOBAL` (which find the
user's global git configuration, where a `safe.directory` entry may
live), `LANG` and `LC_*`, and sets
`GIT_CONFIG_NOSYSTEM=1`, `GIT_NO_LAZY_FETCH=1`,
`GIT_NO_REPLACE_OBJECTS=1`, `GIT_OPTIONAL_LOCKS=0`,
`GIT_TERMINAL_PROMPT=0` and `GIT_PAGER=cat`. Its arguments start `-C
<dir> --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null -c
log.showSignature=false -c core.pager=cat`. Those, and reading commits
with `rev-list` and `cat-file` rather than formatting them with `log`,
close the paths by which a repository's own configuration runs a
program during a read: the filesystem monitor, hooks, signature
verification through `gpg.program`, pagers, external diff and text
conversion, and the lazy fetch a partial clone makes for a missing
object. Only built-in
subcommands run, which an alias can't shadow. `safe.directory` is left
alone: a repository git refuses to read is the "work tree" case. Stdin
is closed, and each child has a deadline: the check spawns it and polls
`try_wait`, killing it when the 20-second budget
(`SHIRABE_PRE_ACTION_GIT_TIMEOUT` overrides it, for tests) runs out.

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
- **One `git log --format=...` call.** One process instead of two, but
  `log` reads formatting configuration (signature display, pagers) and
  a delimiter byte in a message can break its records. Rejected for
  `rev-list` and `cat-file --batch`, which read neither.

### Decision 4: How the two entry points agree on who reports

Resolved inline.

On a niwa host both the plugin hook and the settings-wired `shirabe
pr-body-hook` run on every Bash call, in parallel, as separate
processes. R12 requires one report per broken rule.

Key assumptions:

- niwa wires the legacy hook as a PreToolUse command in a settings file
  Claude Code reads: `$HOME/.claude/settings.json`, or `.claude/settings.json`
  or `.claude/settings.local.json` under the project directory.
- `CLAUDE_PROJECT_DIR` is set in a hook's environment when Claude Code
  knows the project directory.

#### Chosen: The plugin hook reads the settings and yields the PR-body rules

On a guarded `gh pr` command, the plugin hook reads
`$HOME/.claude/settings.json` and, when `CLAUDE_PROJECT_DIR` is set, the
project's `.claude/settings.json` and `.claude/settings.local.json`,
parses each with `serde_json`, and looks for a `hooks.PreToolUse` entry
whose `matcher` is absent, empty, `*` or `Bash` and that holds a
`"type": "command"` hook whose command, run through the same tokenizer,
has a segment that is `shirabe pr-body-hook`, alone or followed by
`2>/dev/null`, which is how niwa's line reads. A redirection of standard
output (`>/dev/null`, `2>&1` into it) would throw the deny away, so such
a line isn't wiring. A file that sets `disableAllHooks` counts as not
wiring it. The wired command runs `shirabe` from `PATH` and exits 0
when `command -v shirabe` fails, so the plugin hook also requires that
`shirabe` resolve through an absolute `PATH` entry; a binary found only
at `$HOME/.shirabe/bin` means the wired command would do nothing. When all
of that holds, the plugin hook skips the PR-body rules and their
fail-closed cases for that call; the legacy entry point, now the same
evaluator, reports them in the same shape. What it can't cover is that
entry point crashing: niwa's `|| exit 0` turns a crash into a pass, a
residual risk the binary's own always-exit-0 design keeps small. A file
it can't read or parse counts as no wiring, so a doubt about a file gives
a duplicate report rather than a missing one; a wiring line Claude Code
didn't load (a settings file it ignores) is the case this can't see. A
push is always the plugin hook's.

The probe is strict on purpose. A line that only mentions the command
(`echo shirabe pr-body-hook`), sits under a matcher that never fires on
Bash, or lives in a directory the agent `cd`s into isn't wiring, so the
only way to make the plugin hook yield is to wire the legacy entry point
for real, and that entry point then checks the same rules. There is no
fallback to the input's `cwd`: a directory the agent chose is not where
Claude Code reads settings.

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
extends to `hooks/`, leaving out the hooks' `*_test.sh` suites, whose
own `RULE_IDS=$(...)` line reads the script's rather than declaring
one. A Rust test reads the script's RULE_IDS line and
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

### Decision 6: What the hook does with what it can't see through

Resolved inline.

The hook sees one command string at one moment. Three things defeat a
check made from that string alone: a guarded action behind a wrapper
(`sudo git push`, `bash -c "gh pr create ..."`, `$GIT push`); an earlier
part of the same command that changes what the check reads (`git commit
... && git push` makes a commit the check can't see yet; `printf ... >
b.md && gh pr create -F b.md` writes the body after the hook read it);
and an input that makes the check itself hang (a `--body-file` naming a
FIFO, a device or a huge file), which Claude Code then treats as a
timed-out hook and lets through.

Key assumptions:

- The wrapper list (`env`, `command`, `builtin`, `exec`, `eval`, `bash`,
  `sh`, `zsh`, `dash`, `xargs`, `sudo`, `time`, `nohup`, `timeout`, a
  `$` head) covers how agents usually prefix a command.
- Splitting `git commit ... && git push` into two calls costs an agent
  one more tool call, which the deny reason tells it to make.

#### Chosen: Fail closed on wrappers and same-command changes, and bound every read

The tokenizer reads the shell's structure closely enough not to lose a
guarded command in it: a backslash-newline outside quotes joins two
lines, and the classifier skips leading reserved words (`if`, `then`,
`elif`, `else`, `do`, `while`, `until`, `!`, `{`, `}`) before it takes a
segment's head, so `if true; then git push; fi` is guarded. A command
substitution (`$(...)` or backquotes outside single quotes) is
classified as a command of its own, its here-document lines treated as
data; a guarded segment inside one is a wrapped guarded command. So is a
segment whose head is on the wrapper list (which includes launchers
such as `nice`, `ssh`, `docker` and `mise`, and the interpreters
`python`, `python3`, `perl`, `ruby` and `node`) and whose own text
passes the coarse "named in the text" test, and a segment whose head
starts with `$` and that has a later word `push` or `pr` followed by
`create`, `new` or `edit` (`$G push` names no `git` for the coarse test to
find). All are fail-closed cases, with the one `env` exception that
follows.

`env` is the one wrapper read by the command it runs. Agents prefix
commands with `env -u GH_TOKEN` routinely, and the coarse test over the
whole segment reads quoted arguments as words: a `gh pr merge` whose
`--body` says "new", or a `gh issue create` whose title mentions `gh pr
create`, would read as a wrapped create. So the classifier skips the env
options it reads (`env_command` lists them: `-i`, `-u NAME`, `--` and a
few that take no value) and every operand holding a `=`, since env takes
any of those as an assignment (`a-b=1` and `'X Y=1'` included, not only
shell names). When the command left is `gh`, it is classified as a
segment of its own, and the skipped words get the text test, since gh
can run what an assignment carries (`GH_BROWSER`, `GH_EDITOR`). A guarded
command in either makes the `env` segment a wrapped guarded command, and
anything else is no guarded action; a merge body comes after `gh`, so the
text test never reads it, and gh is no wrapper, so nothing joins the two
halves. Any other command gets the text test over the whole segment. It
may be a launcher the wrapper list lacks (`stdbuf`, `arch`, `ksh -c`),
which only the text test reads past. (`GH` is `gh`: heads compare in any
case.) It may be `git`, which the classifier reads by its
subcommand's name, so `git -c 'alias.p=!git push' p` names no push. Or it
may be a listed wrapper, a nested `env` included, which can join env's
words with its own: in `env 'BASH_FUNC_f%%=() { gh "$@"; }' bash -c 'f pr
create'` env's words hold only `gh` and bash's only `pr create`, and
bash imports the function and runs the create. So does an option the
hook doesn't read (`-S` splits a string into a command, `-C` changes
directory) and a word the shell expands before the command. The other
wrappers keep the text test: each
takes a shell string (`bash -c`, `eval`, `ssh`) or an option grammar of
its own (`sudo -u`, `timeout 5`, `xargs`) that can carry a guarded command
where a word-by-word reading would miss it.

Before a guarded segment the classifier looks at every earlier segment
of the same command. Before a `gh pr` segment, one that names the body
file, compared after resolving both relative paths against the tracked
directory, or that carries a word ending in the file's name, as a word
or after `>` or `>>`, is a fail-closed case. Before a push it is an
allowlist, not a denylist: an earlier `git` segment is acceptable only
with `status`, `log`, `diff`, `show`, `add`, `rev-parse`, `describe`,
`ls-files`, `grep`, `blame` or `fetch` (none of which changes what the
push would send, except `fetch`, which can only shrink it), so `git
checkout other && git push` or `git commit ... && git push` fail closed,
and so does any earlier segment with a wrapper head or a `gh pr
checkout`. The segments inside a command substitution, at any depth and
in an unquoted here-document too, count as earlier when the
substitution starts before the guarded segment ends, since the shell
runs it first: `echo $(git commit ...) && git push` fails closed the
same way.

Every read is bounded. A `--body-file` must not be a symlink (`lstat`),
is opened with `O_NONBLOCK | O_NOFOLLOW` so a FIFO or a symlink swapped
in after the check can't block or redirect it, is checked again with
`fstat` on the open descriptor (a regular file of at most 1 MiB), and is
read up to that size. The hook input is read whole, since Claude Code
already holds it in memory, but only an input of at most 4 MiB is
tokenized; a longer one is denied when the coarse test over all of it
names a guarded action and gets no decision otherwise. The whole evaluation
runs on a worker thread; the main thread waits 25 seconds and, when the
worker hasn't answered, applies the coarse test to the input's
`tool_input.command` (to the raw input only when it doesn't parse or
holds no command, so text in another field such as `description` can't
deny an unguarded command), prints the fail-closed deny when it names a guarded action (or nothing
when it doesn't) and exits, so a hang anywhere becomes a deny inside
Claude Code's 30-second timeout, not a pass.

#### Alternatives Considered

- **Let wrapped commands through, as the PRD's first draft did.** No
  false denies, but `sudo git push` and `bash -c "gh pr create ..."`
  would skip the check entirely. Rejected: the coarse test already tells
  the hook a guarded action is in there, so saying nothing is a choice
  to fail open.
- **Simulate the earlier segments.** Work out what `git commit -m ...`
  would add and check it. It means re-implementing git's commit and
  every shell redirection, and still misses a commit made by a hook or
  a script. Rejected.
- **Rely on Claude Code's timeout.** Simpler, but a timed-out hook lets
  the call run. Rejected: a FIFO would be a one-line bypass.

### Decision 7: Whether the hook guards merging

Resolved inline.

Merging is the third irreversible action shirabe's rules guard: a squash
merge writes the pull request's Part 1 onto the default branch for good.
The PRD leaves `gh pr merge` out (its Out of Scope and Decisions and
Trade-offs), because no active rule guarding `merge` can be decided from
the command and the local repository. This decision records why that
holds at the design level and what guards the merge instead.

Key assumptions:

- The repositories shirabe runs in protect their default branch with
  required status checks, and the PR-body check (`pr-body.yml`, the
  reusable workflow `validate-pr-body.yml` calls) is among them where the
  two-part convention applies.
- `/execute` and `/work-on` merge only through their own merge gates.

#### Chosen: No merge deny; the merge stays behind server-side and workflow gates

The hook doesn't recognize `gh pr merge` or the API merge forms. What a
squash merge writes is the pull request's title and body as GitHub holds
them, plus any `--subject`, `--body` or `--body-file` the command gives;
the first half is GitHub's state, which the hook never reads (R14), and
the rules that judge it already run where that state lives:

- **The PR-body CI check** runs PB1 to PB4 on the pull request GitHub
  has, and as a required status check it keeps a non-conforming pull
  request from merging. Every PR-body rule the hook denies before
  creation is checked again here before merge, and PB4, the one rule the
  canary may leave to the gate, is backstopped by exactly this check
  (its registry `backstop`).
- **Branch protection** refuses the merge while any required check
  fails, whoever runs `gh pr merge` and however.
- **`/execute`'s merge gates** (`merge_readiness`, `merge_attempt`,
  `merge_confirm`) and the review pause decide whether a run may merge
  at all, and merge only through `merge-exec.sh`.
- **`/work-on`'s PR-body gate** reads the pull request after creation and
  holds the run until it conforms.

#### Alternatives Considered

- **Deny `gh pr merge` when its own `--subject`, `--body` or
  `--body-file` carries an AI-attribution line.** That part is local and
  decidable, and it would close the one way a merge can add a trailer
  the PR-body check never saw. Rejected for this feature: no registry
  rule guards `merge` with that text, no workflow shirabe ships passes a
  merge body, and adding it means a new rule entry and a new guarded
  command for a case no skill produces. It is listed as a residual risk
  and is the natural first step if merge coverage is wanted later.
- **Re-check the pull request's live body at merge time with `gh pr
  view`.** Catches the same things the required CI check does, a moment
  earlier, at the cost of a network call on every merge and a new
  fail-closed case whenever GitHub is slow or unreachable. Rejected: it
  duplicates a check that already blocks the merge.
- **Recognize API merges (`gh api .../merge`, GitHub MCP tools).** These
  aren't Bash commands the hook can classify reliably, and an MCP tool
  isn't a Bash call at all. Rejected; branch protection covers them.

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
checked against its outgoing commits, found with two bounded plumbing calls
run with the repository's programs switched off (Decision 3). A command
the hook can't see through, because a wrapper hides the action or an
earlier part of the command changes what would be checked, is a
fail-closed case, and every read is bounded so nothing can turn a hang
into a pass (Decision 6). Every deny is rendered from the registry the
plugin ships, and every rule that can produce one is linked in the
registry and checked against the script and the code (Decision 5).

The pieces trade a small amount of duplication for the fail-closed
guarantee: the script's coarse test is a second, cruder classifier, kept
deliberately cruder and used only when the precise one can't run.

## Solution Architecture

### Overview

```text
Claude Code (PreToolUse, matcher Bash, timeout 30)
  -> hooks/pre-action-deny.sh            bash 3.2, no jq
       SHIRABE_PRE_ACTION_HOOK=off ? -> no decision
       find shirabe (PATH, $HOME/.shirabe/bin/shirabe)
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
  command hook: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/pre-action-deny.sh"`,
  `timeout: 30`. No `onFailure`.
- **`hooks/pre-action-deny.sh`.** Reads stdin into a variable (`cat`),
  checks the off switch, finds the binary on the absolute `PATH`
  entries or at `$HOME/.shirabe/bin/shirabe`, pipes the saved input into
  `shirabe pre-action-hook --plugin-root <root> --rules "<its RULE_IDS
  line>"`, and checks its exit status and that its output is empty or
  one line starting with the exact deny prefix and ending with `"}}`.
  The binary is started as a background job beside a 26-second watchdog,
  both under `set -m` so each runs in its own process group, and the
  watchdog kills the binary's whole group, so a binary that hangs before
  its own deadline starts still ends inside Claude Code's 30 seconds and
  no child it started can hold the output pipe open past that; a killed
  binary is one that can't run. The
  `--rules` value is the version handshake: a binary that doesn't check
  every rule listed there exits non-zero, so a binary older than the
  plugin fails closed even when it knows the subcommand. On anything
  else it runs the coarse test, under `LC_ALL=C`: the raw input with its
  JSON escapes `\n`, `\r`, `\t`, `\"` and `\\` turned back into
  characters by `sed` (a newline in the command reaches the script as
  the two characters `\n`, which would otherwise glue `git` to the word
  before it), a backslash-newline removed, as the shell joins the two
  lines, and every `"` and `'` dropped by `tr`, since quote removal
  doesn't split a word (`g"i"t` is `git`); then lowercased and split one
  word per line by `tr` on every character outside `[a-z0-9_-]`, and
  read by `awk` for `gh`, a later `pr` and a later `create`, `new` or `edit`,
  or `git` and a later `push`. Under `PR_BODY_HOOK_DISABLE` (any
  non-empty value but `0` or `false`) it looks for `git` and a later
  `push` only, since the PR-body rules are off (PRD R9). That is the
  binary's own reading and takes time linear in the input; a single
  `grep -E` with `.*` between the words is quadratic on a few megabytes
  of `gh` and `pr`, and `hooks/testdata/coarse-cases.tsv` holds the two
  readings to the same answers. On a match it prints a constant
  deny built with `printf`, naming the binary as missing or older than
  the plugin, the install command, the ids from its `RULE_IDS` line, and
  asking the agent to ask the user; else nothing. It always exits 0.
  Declares `RULE_IDS="..."` (Decision 5).
- **`crates/shirabe/src/pre_action/mod.rs`.** `run_plugin(root, rules)` and
  `run_legacy()` entry points; `evaluate(input, ctx) -> Option<String>`
  (the deny reason) with `ctx` carrying the rule set, the registry
  source, the canary probe, the settings probe, the environment and the
  git runner, so tests inject each. The entry points read stdin whole,
  tokenize it only up to 4 MiB, and run `evaluate` on a worker thread
  with the 25-second overall deadline (Decision 6). A panic on the
  worker is caught at the join and becomes the fail-closed deny when
  the coarse test names a guarded action, printed with exit 0, so a
  crash in either entry point is never the silent pass niwa's `|| exit
  0` would make it. `run_plugin` compares `--rules` with its own table
  and exits 3 when the script lists a rule the binary doesn't check.
  `RuleSet::PrBodyOnly`, the legacy entry point's set, keeps every
  fail-closed case attached to a `gh pr` segment, plus the
  segment-less cases (malformed input, an unterminated quote, an
  oversize input) when the raw text names `gh` ... `pr`; the plugin hook,
  when it yields, keeps the push cases and the segment-less ones when
  the raw text names `git` ... `push`. The input's `transcript_path` and
  `session_id` are ignored, and nothing is logged.
- **`tokenize.rs`.** The quote-aware tokenizer from `pr_body_hook.rs`,
  extended: segments end at unquoted `;`, `&`, `|`, newline, `(` and `)`;
  a backslash-newline outside quotes is removed; an unquoted `<` or `>`
  starts a redirection word, as in the shell (`push>/dev/null` is two
  words); each segment keeps its words and its byte span in the raw
  command, and its subshell groups (parentheses, a pipeline element
  beside `|`, an and-or list `&` ends); command substitutions are
  recorded with their spans for the classifier to recurse into, their
  here-documents as data, except the `$(...)` and backquotes in an
  unquoted-delimiter here-document's lines, which the shell runs; `$'`
  starts an opaque word the body reader refuses. Substitutions nest at
  most 64 deep, each level a recursion; deeper input is refused like an
  unterminated quote, so no command can overflow the stack and abort
  the process.
- **`classify.rs`.** Walks segments, tracks the directory (R4's `cd`,
  `pushd`, `popd` rules, with a stack the tokenizer's parenthesis depth
  drives so a `cd` inside `( )` ends when the group closes), skips
  `NAME=value`, redirection and reserved words before the head, drops
  redirection words (and a bare operator's target) after it, and
  returns each
  guarded segment as `Gh(GhSegment { action, words, dir, index })` or
  `Push(PushSegment { words, dir, index })`, with `-C` paths already
  applied to a push's `dir`, or a fail-closed case for an
  unlisted global option, a wrapped guarded command, or an earlier
  segment that changes what the guarded one checks (Decision 6). Heads
  compare by their last path component, in any case (Unicode case
  folded, as the filesystem folds it), as a case-insensitive filesystem
  runs `ENV` as env and `ſudo` as sudo; the builtins `cd`,
  `pushd` and `popd` match only as written.
- **`body.rs`.** Reads `--title`/`-t` and `--body`/`-b`/`--body=`,
  `--body-file`/`-F`/`--body-file=`, and a short flag's attached value
  (`-tVALUE`, `-b=VALUE`, `-FPATH`) the way gh's flag parser reads it;
  detects the here-document form, given as a word of its own or after
  `--body=` or `-b`, in
  the segment's raw span (`$(cat <<` followed by an optional `-`, a
  delimiter quoted with `'` or `"` or bare, a newline, lines, a line equal
  to the delimiter, `)`), returns its lines byte for byte, and refuses an
  unquoted-delimiter body holding `$` or a backquote; refuses every form
  R7 case 4 lists with the form's name. A body file is read only after
  `lstat` shows a regular file, through an `O_NONBLOCK` open, and up to
  1 MiB; its lines reach the validator and never the reason.
- **`push.rs`.** R4's argv parse, remote resolution, source resolution
  and the bounded `rev-list` and `cat-file` calls, through a `GitRunner` trait whose real
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
shirabe pre-action-hook --plugin-root <dir> --rules "<ids>"   stdin: PreToolUse JSON
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
pub enum RuleSet { All, PrBodyOnly, PushOnly }
pub enum RegistrySource { PluginRoot(PathBuf), Embedded }
pub struct Ctx<'a> {
    pub rules: RuleSet,
    pub registry: RegistrySource,
    pub canary_opted_in: &'a dyn Fn() -> bool,
    pub legacy_wired: &'a dyn Fn() -> bool,
    pub git: &'a dyn GitRunner,
    pub git_budget: Duration,
}
pub fn evaluate(input: &str, ctx: &Ctx) -> Option<String>; // the reason
pub const RULES: &[&str] = &[ /* equals the script's RULE_IDS line */ ];

// shirabe::pre_action::classify
pub struct PushSegment { pub words: Vec<Word>, pub dir: PathBuf, pub index: usize }

// shirabe::pre_action::reason
pub fn render(actions: &[Action], broken: &[Broken], fails: &[FailClosed]) -> String;
```

`PushOnly` is the plugin hook's set when it leaves the PR-body rules to
another entry point (`PR_BODY_HOOK_DISABLE`, or a host whose settings
wire `shirabe pr-body-hook`). `legacy_wired` takes no argument: the
probe reads only the environment. `PushSegment.words` keeps each word's
quoting so the push check can refuse one the shell would rewrite, and
`render` takes every guarded action in the command so one header names
them all.

Reason text, per broken rule and per fail-closed case:

```text
shirabe denied this `gh pr create` before it ran.

pr-body/one-separator: The pull request body needs exactly one --- separator and a non-empty Part 1: the PR body has no `---` separator. ...
  full text: /…/references/pr-body-conformance.md lines 52-58

shirabe could not check this `git push` (directory: `cd "$DIR"` isn't a literal path), so it is denied.
It is guarded by: commit/no-ai-trailer.
Fix: run the push from the repository's directory, or with `git -C <path>`.
If you believe this deny is wrong, ask the user.
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

### Phase 2: The PR-body evaluator and the legacy entry point

Move the tokenizer into `pre_action`, extend it, and add the classifier,
body reader, registry reader and reason renderer, each with unit tests,
and point `pr-body-hook` at `run_legacy`. This is the phase that flips
the legacy entry point's five fail-open cases to deny, the change niwa
hosts see, so it lands with its own tests.

Deliverables:

- `crates/shirabe/src/pre_action/{mod,tokenize,classify,body,registry,reason}.rs`
- `crates/shirabe/src/pr_body_hook.rs`

### Phase 3: The plugin subcommand and the settings probe

Add `settings.rs`, the `pre-action-hook` subcommand with `--plugin-root`
and `--rules`, the deadline thread and the panic catch.

Deliverables:

- `crates/shirabe/src/pre_action/settings.rs`, `crates/shirabe/src/main.rs`

### Phase 4: The push check

Add `push.rs` and the `GitRunner`, last because it is the largest and
the most self-contained piece.

Deliverables:

- `crates/shirabe/src/pre_action/push.rs`

### Phase 5: The plugin hook and its suite

Add `hooks/hooks.json`, `hooks/pre-action-deny.sh`,
`hooks/pre-action-deny_test.sh` and `hooks/testdata/coarse-cases.tsv`,
a table of command strings with the coarse test's expected answer that
both the shell suite and a Rust test run, so the two classifiers can't
drift apart unnoticed; and the CI step.

Deliverables:

- `hooks/hooks.json`, `hooks/pre-action-deny.sh`, `hooks/pre-action-deny_test.sh`,
  `hooks/testdata/coarse-cases.tsv`
- `.github/workflows/build-and-test.yml`

### Phase 6: Registry links and the checker

This lands in the same pull request as Phase 5: the script's `RULE_IDS`
line and the registry's `deny` fields are checked against each other, so
neither ships without the other.

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

The hook is a guardrail against an agent's mistakes, not a boundary
against an agent determined to get past it. It runs before every Bash
call with the user's privileges and outside Claude Code's permission
prompts, so the things it must never do matter more than the things it
catches.

**Untrusted input.** The command, the title and body, body files, commit
messages, the repository's configuration and refs, and the project's
settings files are all things the agent can shape. The command is
tokenized and never evaluated; nothing the agent wrote reaches a shell,
and output is built with `serde_json`. The wrapper never interpolates
the input, passes through only a deny decision with the exact
PreToolUse prefix (so a broken or hostile binary on `PATH` can't print
`allow` and approve a command), feeds the binary through a pipe rather
than a here-string so it writes no temporary file, and skips relative
`PATH` entries so a repository can't plant a `shirabe`. Reads are
bounded: 4 MiB of input, a 1 MiB regular body file opened without
blocking, at most 1,001 commits and 16 MiB of commit objects, 20
seconds of git and 25 seconds overall, so no input turns a check into a
timeout that Claude Code would let through.

**Running git in a directory the agent chose.** A repository the agent
just created is fully agent-shaped, including `.git/config`. The push
check therefore runs only built-in plumbing (`rev-parse`, `config`,
`for-each-ref`, `rev-list`, `cat-file`), from a fixed
environment that keeps only `PATH`'s absolute entries, `HOME`,
`XDG_CONFIG_HOME`, `GIT_CONFIG_GLOBAL`, `LANG` and `LC_*` from the
hook's, with the configuration paths that run programs switched
off: the filesystem monitor, hooks, signature verification (which would
run `gpg.program`), pagers, external diff and text conversion, and
lazy fetches from a partial clone's promisor (which would make a
network call through the remote's helpers; `GIT_NO_LAZY_FETCH` needs
git 2.44 or later, so on an older git a repository with
`extensions.partialClone` set is a fail-closed case rather than a
risk). Replace objects are ignored, so a `refs/replace/` entry can't swap
a commit's message. A source word starting with `-` is refused,
`rev-parse` gets the rest after `--end-of-options`, `rev-list` gets only
the hexadecimal ids that came back, and the remote name must be a plain
word. A leading `GIT_...=value` assignment on a guarded push is a
fail-closed case, since it could point git elsewhere. `safe.directory`
is never overridden.

**What reaches the model.** A deny reason carries registry text, the
validator's fixed messages with line numbers, commit hashes and
subjects from the repository (labelled `subject:`, control characters removed, cut to 72 characters,
at most 10 of them, since they are text from a repository the agent may
not trust), and the absolute path of the plugin's reference file (which
shows the user's home directory name). It never quotes a body file's
lines, so `--body-file` can't be used to read the content of a file the
agent's permissions deny it; what leaks is only which PR-body rule the
file breaks and on which line. Settings files are read only for
the wiring test and nothing from them is echoed. The hook ignores the
input's transcript path and logs nothing.

**Turning the hook off.** `SHIRABE_PRE_ACTION_HOOK=off` comes from the
hook's environment, which a command can't set but a write to the
project's settings `env` can. The reason never names the switch; it
tells the agent to ask the user. Whoever can write the settings controls
the hook, which is true of every Claude Code hook. The double-wiring
probe can't be satisfied by a mention: only a Bash-matched hook that
really runs `shirabe pr-body-hook`, in the user's or the project's
settings, counts, and that entry point then checks the same rules.

**Residual risk.** An agent that can write the user's home, `PATH`, the
binary or the repository's refs can defeat the check: a forged
remote-tracking ref hides outgoing commits, a replaced binary allows
everything, and the canary opt-in file is in the user's home. A guarded
action inside a script file, `gh api`, an MCP tool, a shell function or
alias, `git -c alias.x=push x`, or an interpreter or exec wrapper the
wrapper list doesn't name isn't seen. When the plugin hook yields the
PR-body rules to a niwa-wired `shirabe pr-body-hook`, a crash of that
entry point passes, because niwa's line ends `|| exit 0`. Commit
subjects from whatever repository a `git -C` path names reach the model
in a deny reason. Fail-closed cases can be triggered by a repository
the user cloned (an unknown option, a refused `safe.directory`, more
than 1,000 outgoing commits); each stops only the guarded command, and
the user can turn the hook off. Required CI checks and the gates remain
the backstop for all of it.

**Supply chain.** The plugin's files come from the plugin marketplace
and run before every Bash call, which is the trust any plugin hook
asks for. The binary comes from `install.sh`, which checks it against
the release's `checksums.txt` by SHA-256 before installing; both come
from the same GitHub release, so that check gives integrity in transit,
not authenticity; signed provenance for the binary would add that and
is left for later. The binary and the plugin are versioned together. A
binary older than the plugin either lacks the subcommand or fails the
`--rules` handshake (it doesn't check a rule the script lists), and
either way every guarded command fails closed with a reason naming the
binary; the registry reader ignores fields it doesn't know so a newer
registry doesn't break an older reader. No new dependency is added.

**Launch and crash.** A hook that fails to start, crashes or times out
is a pass in Claude Code. The command runs the script through `bash`
with a quoted path, so the executable bit and spaces in the path don't
matter, and CI checks the script's mode anyway; the script's watchdog
and the binary's own deadline end every run inside the declared
timeout; and a panic in either entry point is caught and turned into
the fail-closed deny. A host with no `bash` at all is the one launch
failure left, and Claude Code itself needs a shell to run the Bash
tool.

**What the hook still can't see.** An earlier `export GIT_DIR=...`, or a
command that makes commits without being `git` (`npm version`, a
release script), before a push in the same command; and `gh pr merge
--body`, which can write an AI-attribution line into the squash commit
(merge is out of scope). These are listed with the other residual risks
in the PRD's Known Limitations.

## Consequences

### Positive

- Every plugin user gets the denies with no settings change, and every
  deny names a registered rule in its own words.
- A broken install is visible: a missing, old, hung or crashing binary
  makes a guarded command fail with the cause instead of passing
  unchecked.
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

- The missing-binary deny names the install command and tells the agent to ask the user.
- The unguarded path runs no git and reads no file.
- The coarse test is used only when the binary can't run, and its tests
  pin which commands it denies.
- If the settings shape changes, the failure mode is a duplicate report,
  not a missing one; a follow-up for niwa to stop injecting is proposed.
- Release notes say the plugin's hook needs the binary from the same
  release.
