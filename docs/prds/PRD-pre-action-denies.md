---
schema: prd/v1
status: Done
problem: |
  shirabe's rules that guard an irreversible action are checked after it:
  the /work-on gate reads the pull request GitHub already has, CI reads
  what was pushed. The one deny that runs beforehand, `shirabe
  pr-body-hook`, reaches only hosts a workspace manager wired it into,
  lets the action through whenever it can't decide, and speaks in the
  validator's words rather than the rule's.
goals: |
  Installing the shirabe plugin is enough for an agent to be stopped
  before it opens or edits a pull request whose title or body breaks a
  PR-body rule, or pushes a commit carrying an AI-attribution line. The
  stop names the registered rule and where to read it. A check that
  can't run stops only the guarded action, and nothing else is touched.
absorbed:
  - docs/briefs/BRIEF-pre-action-denies.md
---

## Status

Done

Absorbed [BRIEF-pre-action-denies](docs/briefs/BRIEF-pre-action-denies.md); carried in Absorbed Brief.

## Absorbed Brief

The brief framed why this feature exists. shirabe wants to stop
preloading every rule into an agent's context and hand a rule over at
the moment it applies, and for a rule whose harm can't be undone that is
safe only when something still blocks the action itself, beforehand.
This feature builds that block and withholds no rule. The gap it named
is this document's Problem Statement: rules guarding pull-request
creation and pushing are checked only after the action, and the one deny
that runs first reaches only hosts niwa wired, lets the action through
when it can't decide, and doesn't speak in the rule's words.

The outcome it asked for, an agent on any Claude Code host stopped
before an irreversible action and told the rule and where to read it,
with a check that can't run stopping only the guarded action, is this
document's Goals. Its five journeys (a plugin-only user opening a pull
request, an agent pushing a commit with an AI-attribution trailer, a
maintainer upgrading a host that already wires the hook, a user whose
binary is missing, a maintainer running the offload canary) are the
first four User Stories and the last. Its scope boundary is the
Requirements and Out of Scope: the plugin's own hook, PR-body rules on
pull-request commands and the commit-trailer rule on push, registry
text in the reason, fail-closed checks, compatibility with the existing
entry point and the canary, and the registry link are in; withholding
any rule, rules that need GitHub's state, merge, linter check states,
validate-and-return on koto gates, niwa's own wiring and other hosts
are out.

## Problem Statement

shirabe states rules whose breach can't be taken back. A pull request
opened with a malformed body is public the moment `gh pr create`
returns; a commit carrying a `Co-Authored-By:` line naming an AI model
is in the remote's history the moment `git push` returns, and stays
fetchable from GitHub after a force-push. The rule registry
(`references/rule-registry.json`) marks each such rule with what it
guards (`pr-create`, `push`, `merge`).

Almost every one of those rules is checked after the action. The
/work-on PR-body gate reads the pull request GitHub already has. The
commit checks run at finalization, usually after the branch was pushed.
CI runs on what was pushed. These checks keep a bad change from
merging, but the irreversible part has already happened when they
speak.

`shirabe pr-body-hook` is the exception: a Claude Code PreToolUse
adapter that denies a `gh pr create` or `gh pr edit` whose title or body
breaks PB1 to PB4 (`references/pr-body-conformance.md`) before it runs.
Three things limit it. The shirabe plugin declares no hooks, so it runs
only where niwa, the workspace manager, injects it into a host's
settings; a user who installs the plugin alone gets no deny. When it
can't decide (an unreadable `--body-file`, a command it can't tokenize,
a missing binary) it allows, which was the right trade for early
feedback and is the wrong one for the check that still blocks the
action. And its deny reason is the validator's own message, not the
rule's registered summary, so the agent isn't told the rule and a
reader can't join the event to the registry.

Nothing at all stops a push.

## Goals

An agent running under the shirabe plugin, on any Claude Code host
(plugin-only, workspace-managed or otherwise), is stopped before it
takes an irreversible action that would break a rule guarding it. The
stop carries the rule's id, its registered summary and where its full
text is, so the agent learns the rule at the moment it needs it.

When the check can't run, the guarded action is stopped and the reason
says what failed and how to recover. With the shirabe binary installed,
every command the hook doesn't guard runs as if the hook weren't there.

A maintainer whose host already wires the pr-body hook gets one deny
per broken rule after upgrading, and a maintainer running the live
offload canary sees it behave as before.

## User Stories

- As a developer who installed only the shirabe plugin, I want my
  agent's `gh pr create` with a body that has no `---` separator denied
  before it runs, with the PB2 rule's summary and a pointer to its text,
  so that the agent fixes the body and the pull request opens correct.
- As a developer whose agent is finishing a change, I want a `git push`
  that would send a commit carrying an AI-attribution trailer denied,
  naming the commit and the rule, so that the trailer never reaches the
  remote.
- As a workspace maintainer whose niwa host already injects `shirabe
  pr-body-hook`, I want upgrading to a plugin that ships its own hook to
  leave me with one deny per broken rule, so that the agent isn't told
  the same thing twice and I don't have to change niwa first.
- As a user whose shirabe binary is missing or too old, I want my
  agent's ordinary commands to run untouched and its `gh pr create` to
  be denied with a reason saying the check couldn't run and how to fix
  it, so that a broken install fails visibly instead of silently.
- As a developer whose agent tried `gh pr create --fill`, I want the
  deny to say that the hook can't read a body it doesn't see and to name
  the forms it can read, so that the agent re-issues the command with
  `--body` or `--body-file` instead of guessing.
- As an operator who needs the hook out of the way (a broken install I
  can't fix right now, or a false deny), I want one setting that turns
  every deny off without uninstalling the plugin, so that work can go on
  while I fix the cause.
- As a maintainer who opted a host into the live offload canary, I want
  a `gh pr create` whose only problem is a heading in Part 1 (PB4) to go
  through as it does today, while every other PR-body rule is still
  denied, so that the canary keeps measuring what it measures.

## Requirements

### Definitions

These terms mean the same thing everywhere below.

- **Hook call**: one PreToolUse event for Claude Code's Bash tool. The
  whole Bash command is the unit the hook denies or leaves alone; it
  never runs part of a command.
- **No decision**: the hook prints nothing and exits 0, so Claude Code
  goes on as if the hook weren't installed. The hook never prints an
  `allow` decision.
- **Deny**: the hook prints a PreToolUse `deny` decision whose reason
  Claude Code shows the agent.
- **Segment**: a piece of the command text between unquoted `;`, `&`,
  `|`, newline, `(` or `)` characters. Text inside single or double
  quotes is never split.
- **Head**: a segment's first word after any leading `NAME=value` words
  and shell reserved words (`if`, `then`, `elif`, `else`, `do`, `while`,
  `until`, `!`, `{`, `}`), compared by its last path component, so
  `/usr/bin/git` is `git` and `if true; then git push; fi` holds a
  guarded segment. The comparison ignores case, since a
  case-insensitive filesystem (macOS's default) runs `GH` as gh and
  `ENV` as env. The shell finds a builtin by its exact name, so `EVAL`
  isn't the builtin, but reading a wrapper as one only denies more;
  only `cd`, `pushd` and `popd` match as written, since reading `CD`
  as `cd` would check a later push in a directory it never moved to. A
  backslash followed by a newline outside quotes joins the two lines,
  as the shell does.
- **Word**: a piece of a segment between unquoted blanks, after quote
  removal. Single quotes keep their text literally; inside double quotes
  a backslash escapes only `"`, `\`, `$` and backquote; outside quotes a
  backslash escapes the next character; adjacent quoted and unquoted
  pieces join into one word. `$'...'` quoting is left as written, so a
  body in that form is one R6 can't read.
- **Guarded command**: a segment whose head is `gh`, whose first word
  after `gh` that doesn't start with `-` is `pr`, and whose next word is
  `create`, `new` or `edit` (`new` is gh's built-in alias for `create`
  and is read as `create` everywhere below), where `-R <value>` and `--repo <value>` count as one
  option with its value; or a segment whose head is `git` and whose first
  word after `git` that doesn't start with `-` is `push`, where `-C
  <path>` and `-c <name=value>` count as one option with its value. A
  command is guarded when any of its segments is. Of the options before
  the subcommand, only `-R`, `--repo`, `--repo=<v>` (gh) and `-C`, `-c`,
  `--no-pager`, `-P` (git) are understood; a guarded segment carrying
  any other, or a guarded `git` segment with a leading `GIT_...=value`
  assignment (which can point git at another repository), fails closed
  under R7 case 9. Leading redirection words (`>out`, `2>&1`) are
  skipped like assignments, and a redirection word later in the segment
  (with the target after a bare `>`, `>>`, `2>`, `<` or `&>`) is no
  argument: `git push origin topic 2>&1` pushes `topic`.
- **Named in the text**: the coarse test the plugin's script applies
  when the binary can't run. The raw hook input, with its JSON escapes
  `\n`, `\r`, `\t`, `\"` and `\\` turned back into the characters they
  stand for and a backslash-newline removed, contains, as separate
  words and ignoring quotes, `gh` followed later by `pr` followed later
  by `create`, `new` or `edit`, or `git` followed later by `push`. It is a
  superset of guarded: everything guarded is named in the text, and
  some unguarded commands are too (`echo "git push"`). The same test,
  applied to one segment's text, decides a wrapped guarded command,
  with the one `env` exception below.
- **Wrapped guarded command** (for an `env` head, read with the `env`
  exception below): a segment whose head is `env`, `command`,
  `builtin`, `exec`, `eval`, `bash`, `sh`, `zsh`, `dash`, `xargs`,
  `sudo`, `time`, `nohup`, `timeout`, `nice`, `ssh`, `docker`,
  `podman`, `mise`, `nix`, `python`, `python3`, `perl`, `ruby` or
  `node`, and whose text names a guarded action; a segment whose head
  starts with `$` or a backquote and that has a later word `push`, or
  `pr` followed by
  `create`, `new` or `edit`; or a command substitution (`$(...)` or backquotes, outside
  single quotes) anywhere in the command whose own text, split into
  segments the same way, holds a guarded or wrapped guarded segment. A
  here-document's lines are data, not commands, so `git commit -m
  "$(cat <<'EOF' ... git push ... EOF)"` holds none; with an unquoted
  delimiter the shell still runs a `$(...)` or backquotes in them, and
  those count as command substitutions.
- **The `env` exception**: when an `env` segment runs `gh`, the text
  test over the whole segment doesn't decide it. Past env's own options
  (the classifier's `env_command` lists the ones it reads) and every
  operand holding a `=`, which env takes as an assignment whether or not
  it is a shell name, the `gh` command is classified as a segment of its
  own, and the text test runs over env's own option and assignment words,
  since gh can run what an assignment carries (`GH_BROWSER=...`,
  `GH_EDITOR=...`). The `env` segment is a wrapped guarded command when
  either finds a guarded action. So `env -u GH_TOKEN gh pr merge --body
  "..."` is a merge whatever its body says, and `env -u GH_TOKEN gh pr
  create ...` is still a wrapped guarded command. Any other command
  leaves the segment to the text test: an unlisted launcher, `git`
  (whose aliases can hide a push from the subcommand reading), and any
  listed wrapper, a nested `env`
  included, since a wrapper can join env's words with its own (`env
  'BASH_FUNC_f%%=() { gh "$@"; }' bash -c 'f pr create'`). So do an
  option the hook doesn't read and a word the shell expands before the
  command.

### Functional

- **R1. The plugin declares the hook.** The shirabe plugin's own files
  declare a Claude Code PreToolUse hook on the Bash tool, with a declared
  timeout of 30 seconds, whose command runs the script through `bash`
  with its path quoted, so neither a lost executable bit nor a space in
  the plugin's path makes the hook fail to start (a hook that fails to
  start lets every command through). A host that installs and enables
  the plugin, and changes no setting, runs it.
- **R2. Only guarded commands are checked.** On a command that isn't
  guarded, and holds no wrapped guarded command, the hook gives no
  decision. A wrapped guarded command (`sudo git push`, `bash -c "gh pr
  create ..."`, `$GIT push`) can't be checked and fails closed under R7.
  A guarded action inside a script file the agent runs isn't seen.
- **R3. PR-body rules on pull-request commands.** On a guarded `gh pr
  create` or `gh pr edit` the hook denies when the submitted title or
  body breaks `pr-body/conventional-title` (PB1),
  `pr-body/one-separator` (PB2), `pr-body/no-ai-trailer` (PB3) or
  `pr-body/no-heading-in-part1` (PB4), decided by the same validator
  `shirabe validate --pr-body` runs; a finding that validator raises
  under none of those four is reported as `pr-body/conformance`. What is
  checked follows what is submitted: a title and a body, both; a body
  alone (an edit), PB2 to PB4; a title alone (an edit), PB1; neither (an
  edit such as `--add-label`), no decision. A `gh pr create` that
  submits no title, or no body, is denied under R7. Several findings
  under one rule make one block, their details joined by `; `.
- **R4. The commit-trailer rule on push.** On a guarded `git push` the
  hook denies when any non-merge commit the push would send carries an
  AI-attribution line as `commit/no-ai-trailer` defines it: a message
  line that, after leading blanks, starts with `Co-Authored-By:` in any
  case and names Claude or Anthropic, or a line containing `Generated
  with Claude Code`. That is PB3's predicate, applied to commit messages.
  - *What it pushes.* With no refspec, the current branch; a detached
    HEAD with no refspec fails closed under R7, and so does a push with
    no refspec when `push.default` is `matching` or the remote has a
    `remote.<name>.push` refspec configured, since it may send more than
    the current branch. With refspecs, each
    refspec's source: the part before `:`, with a leading `+` removed;
    an empty source is a deletion and sends nothing, except that `:` or
    `+:` (an empty source and destination) pushes the matching branches
    and is checked as `--all`. `--all` and
    `--branches` push every local branch, `--tags` every tag, `--mirror`
    every branch and tag, an annotated tag counting as the commit it
    points at; `--delete`/`-d` makes every refspec a deletion. A source
    that doesn't resolve to a commit fails closed.
  - *Where it pushes.* The first positional word after the options, or
    `--repo=<remote>`; with neither, the current branch's `pushRemote`,
    then `remote.pushDefault`, then the branch's `remote`, then `origin`.
  - *What it would send.* The non-merge commits reachable from what it
    pushes and not from any remote-tracking ref of that remote. When
    that remote is a URL or path rather than a configured remote, or has
    no remote-tracking refs, the commits not reachable from any
    remote-tracking ref of any remote. A push that sends no commits gives
    no decision. When more than 1,000 commits would be checked, the hook
    fails closed under R7 rather than walk them.
  - *Which repository.* The hook input's `cwd`, moved by each earlier
    segment of the same command whose head is `cd` or `pushd` and whose
    one argument is a literal path (no `$`, backquote or leading `~`),
    applied in order and relative to the directory before it, then by
    `git -C <path>`. A `cd` inside parentheses lasts until the group
    closes, as in a subshell, so `(cd sub && x); git push` pushes from
    the outer directory. A pipeline element (`cd sub | x`) and a list
    run with `&` are subshells too, so a `cd` in one moves nothing
    after it. A `cd` or `pushd` with no argument, `-`, or a
    non-literal argument, or a `popd`, makes the directory unknown for
    every later segment; a guarded push in an unknown directory, or in a
    directory that isn't inside a git work tree, fails closed.
  - *Options.* `--force`, `-f`, `--force-with-lease[=...]`,
    `--force-if-includes`, `--set-upstream`/`-u`, `--dry-run`/`-n`,
    `--no-verify`, `--verify`, `--atomic`, `--porcelain`, `--quiet`/`-q`,
    `--verbose`/`-v`, `--progress`, `--no-progress`, `--follow-tags`,
    `--no-follow-tags`, `--thin`, `--no-thin`, `--signed[=...]`,
    `--no-signed`, `--push-option`/`-o <value>` and
    `--recurse-submodules=<value>` are understood and don't change which
    commits are checked. Any other option fails closed. A force push is
    checked like any other push.
- **R5. Deny reason from the registry.** A deny for broken rules lists
  one block per broken rule, in the order the rules appear in
  `references/rule-registry.json`:

  ```text
  <rule id>: <summary>: <detail>
    full text: <absolute path of the rule's file> lines <first>-<last>
  ```

  `<summary>` is the entry's `summary`, read at run time from the
  registry the plugin ships, and `<first>-<last>` is the range its
  `text` anchors resolve to in that copy. `<detail>` says where the
  breach is: the validator's message for a PR-body rule; for the
  commit rule, each offending commit as its 12-character abbreviated
  hash and `subject: ` followed by its subject with control characters
  removed and cut to 72 characters, at most 10, then `and <n> more`.
- **R6. Read the body the way agents write it.** The hook reads the
  title from `--title`/`-t` and the body from `--body`/`-b` (as `--body
  <v>`, `--body=<v>` or `-b <v>`) and `--body-file`/`-F` (as `-F <p>` or
  `--body-file=<p>`); a short flag's value may also be attached, as gh
  reads it (`-t<v>`, `-t=<v>`, `-b<v>`, `-b=<v>`, `-F<p>`, `-F=<p>`).
  A relative path is resolved against the
  directory R4 determines for that segment and the file read when the
  hook runs. A body of the form `$(cat <<'EOF' ... EOF)`, or with the
  delimiter double-quoted, is read as the here-document's lines exactly
  as written in the command. With an unquoted delimiter it is read only
  when those lines hold no `$` and no backquote. Every other body form
  is one the hook can't read.
- **R7. Fail closed on guarded actions.** On a guarded command the hook
  denies when it can't decide. Each of these is a case:
  1. the shirabe binary isn't found (the hook looks on `PATH`, then at
     `$HOME/.shirabe/bin/shirabe`, where `install.sh` puts it), or doesn't
     know the hook: it exits non-zero, crashes, runs past 26 seconds,
     prints anything other than nothing or one deny decision, or
     doesn't check every rule on the script's `RULE_IDS` line (a binary
     older than the plugin);
  2. the hook input isn't valid JSON, or has no `tool_input.command`
     string, while its raw text names a guarded action (otherwise no
     decision);
  3. the command has an unterminated quote, or nests command
     substitutions more than 64 deep, while its text names a guarded
     action;
  4. a pull-request command's body is in a form R6 can't read: stdin
     (`-F -`), `--fill`, `--fill-first`, `--fill-verbose`, `--web`,
     `--editor`, `--template`, a command or variable expansion, `$'...'`,
     a `--body-file` that doesn't exist, isn't a regular file (a FIFO,
     a device, a directory), is larger than 1 MiB or can't be read, a
     word combining short flags (`-dt`), or, on `gh pr create`, no body
     at all;
  5. a `gh pr create` with no title;
  6. the registry can't be read, or lacks an active entry for a rule
     the hook guards, or that entry's text anchors don't resolve;
  7. any push case R4 says fails closed;
  8. a `git` command the push check runs fails, or the push check runs
     past 20 seconds, or the whole evaluation runs past 25 seconds or
     crashes, or the repository is a partial clone and git is older
     than 2.44 (which can't be stopped from fetching);
  9. a guarded segment carries a global option the Definitions don't
     list; since such an option may take any number of words as its
     value, a `push` anywhere after one on a `git` segment, or a `pr`
     and a later action word anywhere after one on a `gh` segment, is
     this case;
  10. a wrapped guarded command;
  11. an earlier segment of the same command could change what the
      guarded segment checks: it names the `--body-file` path as a word
      or after `>` or `>>`; or, before a push, it runs `git` with any
      subcommand other than `status`, `log`, `diff`, `show`, `add`,
      `rev-parse`, `describe`, `ls-files`, `grep`, `blame` or `fetch`,
      runs `gh pr checkout` (or `gh pr co`), or its head is one a
      wrapped guarded command can have. A segment inside a command
      substitution, at any depth, that starts before the guarded segment
      ends counts as earlier, since the shell runs it first;
  12. the hook input is larger than 4 MiB while its raw text names a
      guarded action.

  The reason of a fail-closed deny names the action, the case that
  failed, the rules the action is guarded by and how to fix it, and
  ends by telling the agent to ask the user if it believes the deny is
  wrong. It doesn't name the off switch: the switch is for the person
  running the host and is documented in the plugin's README, and a
  reason that names it invites the agent to turn the check off. The
  case is named by these words: 1 `binary`; 2 `hook input`; 3 `quote` or `nested`;
  4 the body form (`--fill`, `stdin`, the path, `regular file`, `1 MiB`,
  the combined flag, `no body`); 5 `title`; 6 the rule id; 7 `HEAD`,
  the unresolved source, `1000 commits`, `directory`, `work tree`, the
  option, or the setting (`push.default`, `remote.<name>.push`); 8
  `git` or `25 seconds`; 9 the option; 10 `wrapped`; 11 `same command`;
  12 `4 MiB`. For a body it can't read the reason also names the forms
  R6 reads.
- **R8. Never block what it doesn't guard.** With the binary present,
  the hook gives no decision on a command that isn't guarded, whatever
  else fails, the registry included. With the binary missing or unable
  to run, it denies exactly the commands whose text names a guarded
  action, and the reason says the binary is the cause; this may deny an
  unguarded command such as `echo "git push"`, and gives no decision on
  every other.
- **R9. Off switches.** `SHIRABE_PRE_ACTION_HOOK=off` in the hook's
  environment (a host sets it in its settings' `env`) makes both entry
  points give no decision on every call, fail-closed and missing-binary
  cases included; any other value (`OFF`, `off `, `0`), or none, leaves
  them on.
  `PR_BODY_HOOK_DISABLE` keeps its meaning today (any non-empty value
  other than `0` or `false`) and turns off the PR-body rules and the
  fail-closed cases of pull-request commands, on both entry points,
  leaving the push check on.
- **R10. The canary's PB4 exception.** The opt-in file is
  `$XDG_CONFIG_HOME/shirabe/offload-canary` when `XDG_CONFIG_HOME` is
  set and non-empty, else `$HOME/.config/shirabe/offload-canary`. A host
  is opted in when that path is a regular file, not a symlink, whose
  first line is exactly the two bytes `on`. On an opted-in host PB4 is
  not denied, on `gh pr create` and `gh pr edit` alike, and PB1 to PB3
  are. A missing, unreadable or symlinked file, or any other first line
  (`On`, `on ` or `on\r`), reads as not opted in.
- **R11. Today's entry point keeps working.** `shirabe pr-body-hook`,
  invoked with no arguments as niwa wires it today, denies PB1 to PB4
  under R3, R5, R6, R7 and R10 for pull-request commands. Its registry
  is the copy built into the binary, and its pointer names the file by
  its repository-relative path.
- **R12. One deny where both are wired.** The host wires the legacy
  entry point when `$HOME/.claude/settings.json`, or `.claude/settings.json`
  or `.claude/settings.local.json` under `$CLAUDE_PROJECT_DIR`, has a
  `hooks.PreToolUse` entry whose `matcher` is absent, empty, `*` or
  `Bash` and that holds a `command` hook one of whose segments is the
  words `shirabe pr-body-hook`, alone or followed by `2>/dev/null` (a
  redirection of standard output would throw the deny away), in a file
  that doesn't set
  `disableAllHooks`, and `shirabe` resolves on the hook's `PATH` (the
  wired command needs it there). When it does, the plugin's hook leaves
  the PR-body rules and their fail-closed cases to that entry point and
  checks only the push rule. With `CLAUDE_PROJECT_DIR` unset only the user file is
  read, and a file that can't be read or parsed counts as not wiring
  it, so a doubt about the file gives a duplicate report rather than a
  missing one. Either way each broken rule appears in one deny reason,
  not two.
- **R13. The registry names the hook.** Every rule the hook denies
  carries a `deny` field, `{"hook": "hooks/pre-action-deny.sh",
  "before": [<protected actions>]}`, naming the plugin's hook script
  and the actions it denies before (`pr-create` for the PR-body rules,
  `push` for the commit rule). The hook script declares the rules it
  denies on a `RULE_IDS="..."` line. `scripts/check-rule-registry.sh`
  fails when a `deny` field is malformed or names a file that doesn't
  exist, when a rule on that line lacks the field, or when a rule with
  the field isn't on that line. No rule's `withhold` differs from the
  registry on the base branch.

### Non-functional

- **R14. Cost.** On a command that isn't guarded the hook starts no
  `git` or `gh` process. On a guarded command it starts no `gh` process
  and makes no network call: the push check runs local `git` plumbing
  only (`rev-parse`, `rev-list`, `cat-file`, `config`, `symbolic-ref`,
  `for-each-ref`), never `fetch`, `ls-remote` or `remote show`.
- **R15. Safety of untrusted text.** The command, title, body and commit
  messages are attacker-controlled. The hook never shell-evaluates the
  command, never interpolates them into a shell command, builds its
  output with a JSON encoder, and writes no file. A deny reason never
  quotes a line of a body file; it names lines by number. Git runs with
  repository-controlled programs switched off (signature verification,
  pagers, external diff and text conversion, hooks, the filesystem
  monitor, lazy fetches and replace objects).
- **R16. Portability.** The plugin's script passes
  `scripts/check-bash-floor.sh` (the bash 3.2 floor) and needs no `jq`.
- **R17. Tested.** Tests feed the hook PreToolUse JSON through the
  command `hooks/hooks.json` declares and cover every row of the
  example table below, every fail-closed case in R7, the canary cases,
  the off switches and the double-wiring cases. They run in CI on every
  pull request that touches `hooks/`, `crates/`,
  `references/rule-registry.json`, `references/pr-body-conformance.md`
  or `scripts/check-rule-registry*`.

### Example commands

Run with the binary present, in a repository whose `origin` tracking
refs are current, on a host that isn't opted into the canary and has no
`pr-body-hook` wiring. `<good>` is the body `Adds x.`, a blank line,
`---`, a blank line and `Context.`; `<bad>` is `Adds x.` alone, which has
no `---` separator. "The trailer commit" is an unpushed non-merge commit
whose message ends `Co-Authored-By: Claude <noreply@anthropic.com>`.

| Command | Outcome |
|---|---|
| `ls`, `git status`, `git commit -m x`, `gh pr view 3`, `echo "gh pr create"`, `gh issue create --title pr --body edit`, `git log --grep push` | no decision |
| `sudo git push`, `env X=1 git push`, `bash -c "git push"`, `eval "git push"`, `$GIT push` | deny, fail-closed (`wrapped`) |
| `/usr/bin/git push` with the trailer commit | deny, `commit/no-ai-trailer` |
| `git commit -m x && git push`, `git checkout other && git push` | deny, fail-closed (`same command`) |
| `git status && git push` with the trailer commit | deny, `commit/no-ai-trailer` |
| `if true; then git push; fi` with the trailer commit | deny, `commit/no-ai-trailer` |
| `echo $(git push)`, ``echo `gh pr create` `` | deny, fail-closed (`wrapped`) |
| `printf 'x' > b.md && gh pr create --title "feat: x" -F b.md` | deny, fail-closed (`same command`) |
| `gh pr create --title "feat: x" -F fifo` where `fifo` is a named pipe | deny, fail-closed (`regular file`) |
| `gh pr create --title "feat: x"` (no body) | deny, fail-closed (`no body`) |
| `gh pr create --body <good>` (no title) | deny, fail-closed (`title`) |
| `gh pr create --title "feat: x" --body <good>` | no decision |
| `gh pr create --title "feat: x" --body <bad>` | deny, `pr-body/one-separator` |
| `GH_TOKEN=t gh -R o/r pr create --title "feat: x" --body <bad>` | deny, `pr-body/one-separator` |
| `git add . && gh pr create --title "Add x" --body <bad>` | deny, `pr-body/conventional-title` then `pr-body/one-separator` |
| `gh pr create --title "feat: x" --body "$(cat <<'EOF' ... EOF)"` with bad lines | deny, `pr-body/one-separator` |
| `gh pr create --title "feat: x" --body "$BODY"` | deny, fail-closed (body form) |
| `gh pr create --fill` | deny, fail-closed (body form) |
| `gh pr new --title "feat: x" --body <bad>` | deny, `pr-body/one-separator` |
| `gh pr edit 12 --title "bad title"` | deny, `pr-body/conventional-title` only |
| `gh pr edit 12 --body <bad>` | deny, `pr-body/one-separator`, no title check |
| `gh pr edit 12 --add-label x` | no decision |
| `git push` with an unpushed commit carrying `Co-Authored-By: Claude` | deny, `commit/no-ai-trailer`, naming that commit |
| `git push` with only clean unpushed commits | no decision |
| `git push origin --delete topic`, `git push origin :topic` | no decision |
| `git push --force origin +topic`, `git -c k=v push`, `cd sub && git push`, `git -C sub push` with the trailer commit | deny, `commit/no-ai-trailer` |
| `cd "$DIR" && git push` | deny, fail-closed (directory) |
| `git push --some-new-option` | deny, fail-closed (option) |

## Acceptance Criteria

- [ ] A test reads `hooks/hooks.json` and checks that it declares a
      PreToolUse hook with matcher `Bash`, a `timeout` of 30, and a
      command that runs `bash` on the quoted path
      `${CLAUDE_PLUGIN_ROOT}/hooks/pre-action-deny.sh`, which exists
      with mode 100755 in git; the hook suite passes run from a copy of
      the plugin whose path holds a space (R1).
- [ ] A binary stub that knows the subcommand but checks fewer rules
      than the script's `RULE_IDS` line lists, one that panics, and one
      that sleeps 40 seconds each make a guarded command a deny naming
      the binary, the last within 28 seconds (R7).
- [ ] Every row of the example table gives the outcome it lists, in a
      test (R2, R3, R4, R6, R7).
- [ ] Each of these pushes has a test with the outcome given: with the
      trailer commit on the pushed side, `git push` (no refspec),
      `git push origin HEAD:refs/heads/other`, `git push --all`, `git
      push --tags` (the commit tagged by an annotated tag), `git push
      --mirror` and `git push --repo=fork` are denied; with it only on a
      branch not pushed, `git push origin main` gives no decision; a
      push whose only trailer commit is a merge commit gives no
      decision; the remote chosen is `pushRemote`, then
      `remote.pushDefault`, then the branch's `remote`, then `origin`,
      one test per step; a push to a URL, and to a remote with no
      tracking refs, checks the commits not on any remote's tracking
      refs (R4).
- [ ] Fail-closed pushes: a detached HEAD with no refspec, a source
      that doesn't resolve, 1,001 commits to check (1,000 gives a
      decision on the commits), `cd` with no argument, `cd -`, `pushd
      "$X"`, `popd`, and a `cwd` outside any work tree each deny with
      the case's word from R7 (R4, R7).
- [ ] Each option R4 lists, added to the trailer push, still denies it,
      and to a clean push still gives no decision (R4).
- [ ] With `SHIRABE_PRE_ACTION_GIT_TIMEOUT=1` and a stub `git` that
      sleeps 5 seconds, a guarded push is denied naming `git` within 3
      seconds; the variable exists for tests and the default bound is
      20 seconds (R7).
- [ ] A deny for one broken rule has exactly one block whose first line
      is `<id>: <summary from the registry>: <detail>` and whose second
      line names the absolute path of the rule's file and its line
      range; a command breaking two rules gets two blocks in registry
      order (R5).
- [ ] With a fixture registry whose summary for `pr-body/one-separator`
      is changed, the deny carries the changed summary (R5).
- [ ] A push with 12 offending commits names 10 of them by abbreviated
      hash and subject and ends `and 2 more` (R5).
- [ ] A body given as `--body=<v>`, as `-b <v>`, in an existing file via
      `-F <p>` and via `--body-file=<p>` (relative to `cd sub`), and in a
      here-document with delimiter `'EOF'`, `"EOF"` and unquoted `EOF`
      is checked; an unquoted here-document whose lines hold `$HOME` or
      a backquote is a fail-closed deny (R6, R7).
- [ ] Each fail-closed case in R7 has a test whose deny reason contains
      the case's word R7 names and the words `ask the user`, and doesn't
      contain `SHIRABE_PRE_ACTION_HOOK`; case 6 has one test each for an
      unreadable registry, a missing entry and an anchor that doesn't
      resolve, on a guarded command (R7).
- [ ] Malformed hook input whose raw text doesn't name a guarded action
      gives no decision; malformed input naming `git push` is denied
      (R7).
- [ ] With the binary removed from PATH and from `$HOME/.shirabe/bin`, `ls`,
      `git status`, `git commit -m x` and `gh pr view 3` give no
      decision, and `gh pr create --title t --body b` and `echo "git
      push"` are denied with a reason naming the binary (R8).
- [ ] With a binary stub that exits 2 for the hook's subcommand, a
      guarded command is denied naming the binary and an unguarded one
      gives no decision; so is `cd repo` then a newline then `git push`,
      whose newline reaches the script as the JSON escape `\n` (R7, R8).
- [ ] With the binary present and the registry file unreadable, the
      unguarded commands of the example table give no decision (R8).
- [ ] With `SHIRABE_PRE_ACTION_HOOK=off`, the bad-body create (on both
      entry points), the trailer push and the missing-binary create all
      give no decision; with it unset, `on`, `OFF`, `off ` or `0` they
      are denied (R9).
- [ ] With `PR_BODY_HOOK_DISABLE=1`, the bad-body create gives no
      decision on both entry points and the trailer push is still
      denied; with it empty, `0` or `false` the create is denied (R9).
- [ ] On a host whose opt-in file's first line is `on` (alone, or
      followed by more lines), a create and an edit breaking only PB4
      give no decision on both entry points and one breaking PB2 is
      denied; with `XDG_CONFIG_HOME` unset or empty the file under
      `$HOME/.config` is read; a symlink, `On`, `on `, `on\r` and an
      unreadable file each leave PB4 denied (R10).
- [ ] `shirabe pr-body-hook`, given the inputs of the unit tests in
      `crates/shirabe/src/pr_body_hook.rs` at the base branch, makes the
      same decision on every one except the five that test a fail-open
      case on a guarded command (`fill_and_web_are_allowed`,
      `command_substitution_body_is_allowed`,
      `unreadable_body_file_is_allowed`, `body_file_dash_stdin_is_allowed`
      and `unterminated_quote_segment_is_allowed`), which now deny; its deny for a bad
      body has the R5 shape with the repository-relative path (R11).
- [ ] With niwa's wiring line in each of `$HOME/.claude/settings.json`, the
      project's `.claude/settings.json` and its
      `.claude/settings.local.json` (one test each), the plugin's hook
      gives no decision on the bad-body create and on the `--fill`
      create, and still denies the trailer push; without the wiring it
      denies both creates. Each of these counts as not wired, so the
      plugin's hook still denies the bad-body create: a settings file
      that doesn't parse; one whose command is `echo shirabe
      pr-body-hook`; one whose matcher is `Edit`; one that sets
      `disableAllHooks`; the wiring in a `.claude/settings.json` under
      `cwd` with `CLAUDE_PROJECT_DIR` unset; the wiring when `shirabe`
      is only at `$HOME/.shirabe/bin` and not on `PATH`. Run on the same input, the
      two entry points report the broken rule once between them (R12).
- [ ] Every rule on the hook script's `RULE_IDS` line carries the `deny`
      field and the shipped registry passes
      `scripts/check-rule-registry.sh`; a fixture missing one field, one
      with an extra linked rule, and one whose `deny.hook` names a
      missing file each fail it (R13).
- [ ] `git diff <base> -- references/rule-registry.json` shows no change
      to any `withhold` value (R13).
- [ ] With stub `git` and `gh` on PATH that record their arguments, the
      unguarded commands start neither, and a guarded push runs no
      `fetch`, `ls-remote` or `remote` subcommand and no `gh` (R14).
- [ ] A title, body and commit subject holding `"`, `\`, a newline and
      an ANSI escape sequence come back JSON-escaped in the reason; a
      body holding `$(touch marker)` leaves no `marker` file; a run in an
      empty `HOME` and `TMPDIR` leaves both empty (R15).
- [ ] `scripts/check-bash-floor.sh` passes on the hook script, and its
      tests pass with `jq` removed from PATH (R16).
- [ ] The CI workflow that runs the hook's tests lists the paths in R17
      among its triggers, and those tests run the command `hooks/hooks.json`
      declares, read from that file (R17).

## Out of Scope

- Withholding any rule from an agent's default context. This feature
  builds the deny a withheld rule would need; no rule becomes eligible.
- Rules whose check needs GitHub's state or a run's koto record: panel
  findings, verification verdicts, a pull request's live body.
- A deny on `gh pr merge`. No active rule guarding `merge` can be
  decided from the command and the local repository; merges stay behind
  required CI checks and the review pause.
- `commit/conventional-subject` and `branch/current-with-main` on push
  (see Decisions and Trade-offs).
- Pull requests and pushes made other than by a Bash command the agent
  types: `gh api`, GitHub MCP tools, other Claude Code tools, and
  scripts the agent runs.
- Linter check states and validate-and-return on koto gates.
- Changes to niwa's hook wiring.
- Hosts other than Claude Code.

## Decisions and Trade-offs

- **Only the commit-trailer rule is denied on push.** The registry says
  `commit/conventional-subject` guards push too, and the hook could check
  it. It doesn't, because the harm differs: an AI-attribution trailer is
  public and stays fetchable once pushed, while a feature branch's commit
  subjects are replaced by the squash-merge title, so denying every
  non-conventional work-in-progress push, in every repository the plugin
  is enabled in, costs more than it saves. The finalization gate keeps
  checking subjects. `branch/current-with-main` is /execute's sync rule;
  feature branches are routinely pushed before they merge the default
  branch in, so it isn't a general push guard either.
- **No merge deny.** Considered checking the PR body again at `gh pr
  merge`; rejected because that reads GitHub's state, which R14 rules
  out, and required CI already blocks the merge.
- **A missing binary denies guarded commands.** Today's wiring allows
  when the binary is missing. The feature exists to be the check that
  still blocks the action, and a check that silently disappears isn't
  one. The cost is that a plugin-only install without the binary can't
  open a pull request through the agent until the binary is installed
  or the hook is turned off, and the reason says both.
- **The coarse test may over-deny, only when the binary can't run.**
  Without the binary nothing can tokenize the command, and the choice is
  between denying a few unguarded commands that mention a guarded
  action and letting guarded ones through. The first is visible and
  names its cause.
- **The registry is read at run time from the plugin's own copy.** The
  deny then carries the text of the plugin version the agent's skills
  came from, and an unreadable registry is a fail-closed case rather
  than a stale copy compiled into the binary. The legacy entry point has
  no plugin root to read from, so it uses the copy built into the
  binary (R11).
- **The plugin's hook yields the PR-body rules to a wired `shirabe
  pr-body-hook`, not the reverse.** The plugin's hook can read the
  settings that wire the other entry point; the other entry point can't
  tell whether a plugin hook is running. Both entry points run the same
  checks with the same reason shape, so yielding loses nothing.
- **The reason doesn't name the off switch.** An earlier draft printed
  `SHIRABE_PRE_ACTION_HOOK=off` in every fail-closed reason. The design's
  security review pointed out that this tells the agent how to turn the
  check off, and an agent that can write the project's settings can do
  it. The reason now tells the agent to ask the user, and the switch is
  documented where the person running the host reads it.
- **Wrapped commands and same-command writes fail closed.** An earlier
  draft let `sudo git push` and `bash -c "git push"` through unchecked,
  and checked a push or a body file as they stood before the command
  ran. `git commit ... && git push` is the commonest way an agent pushes,
  and checking the state before the commit misses the very commit being
  pushed, so these are cases the hook can't decide and it says so. The
  cost is that an agent has to split such a command in two.
- **A push's unknown commits are bounded.** Pushing to a remote with no
  tracking refs could otherwise walk a repository's whole history; past
  1,000 commits the hook fails closed and says so, and the off switch
  covers a deliberate mirror push.

## Known Limitations

- With the binary missing, the coarse test may deny an unguarded command
  that mentions a guarded action (R8). The reason says the binary is
  missing, which is the thing to fix.
- Wherever the text test decides (a wrapper other than `env`, or an
  `env` the exception doesn't cover), it reads quoted arguments as
  words, so an unguarded command whose argument mentions a guarded
  action is denied as wrapped (`sudo gh issue create --title "... gh pr
  create"`, `nohup gh pr merge --body "a new path"`, `env -u X koto ...
  "gh pr edit"`). Run it without the wrapper, or as `env ... gh`. env's
  own assignment words get the text test even before `gh`, so
  `env NOTE='gh pr create' gh pr merge 1` is denied too.
- A guarded command behind a launcher that isn't on the wrapper list
  (`stdbuf`, `arch`, `ksh -c`) gets no decision when no `env` precedes
  it (#1021).
- A guarded action run inside a script file isn't seen (R2) and runs
  unchecked. So does a pull request opened through `gh api` or an MCP
  tool, and a wrapped command whose text hides the guarded action (a
  shell function, an alias, `git -c alias.x=push x`). CI and the gates
  remain the backstop for all of them.
- With the binary present, the hook doesn't see a guarded action in a
  shell fed a script on stdin (`bash <<'EOF'`, `echo "git push" | sh`,
  `ssh host <<'EOF'`), in a shell function defined earlier in the
  command, or behind a `cd` in a brace group that's part of a pipeline
  (the group runs in a subshell, which the hook doesn't track). An
  arithmetic `((... << ...))` is read as a here-document, and a `case`
  pattern's `)` inside a double-quoted `$(...)` closes the substitution
  early, so what follows it is misread. The coarse
  test treats a backslash inside a word as a separator, so `g\it push`
  isn't named in the text.
- The hook guards against an agent's mistakes, not against an agent set
  on getting past it. An agent that can write the user's settings,
  `PATH`, the binary or the repository's refs can defeat it: a forged
  remote-tracking ref hides outgoing commits, a planted settings line
  that really wires `shirabe pr-body-hook` moves the PR-body rules to
  that entry point (which still checks them), and the canary opt-in
  file lives in the user's home, where the agent can write.
- A compound command with a guarded part is denied as a whole: `git add
  . && git push` doesn't run the `git add` either.
- An earlier `export GIT_DIR=...`, or a command that makes commits
  without being `git` (`npm version`, a release script), before a push
  in the same command changes what the push sends without the hook
  seeing it. So does a `gh pr merge --body` that writes an
  AI-attribution line into the squash commit; merge is out of scope.
- A wiring line in a settings file Claude Code doesn't load (an
  untrusted workspace, a layer the probe doesn't read) can make the
  plugin's hook yield to an entry point that never runs.
- Whether Claude Code loads `hooks/hooks.json` from an installed plugin
  is Claude Code's behaviour; the tests check the declaration, not a
  live host.
- The push check trusts the local remote-tracking refs. If they're
  stale, the hook may check a commit the remote already has and deny a
  push that sends nothing new; `git fetch` and a retry clear it.
- When the binary is older than the plugin, the plugin's hook denies
  every guarded command as "doesn't know the hook", and a wired `shirabe
  pr-body-hook` from that older binary may deny the same command again,
  in its old wording. Upgrading the binary fixes both.
- A Claude Code timeout on the hook lets the call run, which is Claude
  Code's behaviour for a timed-out hook. The hook's own 20-second bound
  on the push check (R7 case 8) keeps it inside the timeout it declares.
