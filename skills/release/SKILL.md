---
name: release
description: >-
  Cut a release properly: work out the version from what actually landed,
  derive the change set from the commit range, check for blockers, write notes
  someone would want to read, and drive the release out. Use it whenever a
  version is about to move — "cut a release", "ship 0.19", "tag a new
  version", "publish the new version", "bump the version", "write the
  changelog", "what's changed since the last release?", "is this ready to
  release?". Do NOT do any of it by hand instead: hand-tagging, editing a
  version string directly, writing notes off `git log`, or calling `gh release
  create` yourself skips the blocker check and gets the contents wrong,
  because a search for merged pull requests returns work the release does not
  contain and only the commit range is correct. This is releasing a version,
  not merging a change — shipping one piece of work is `/work-on`.
argument-hint: '[version] [--dry-run]'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh release 2>&1 || true`

@.claude/shirabe-extensions/release.md
@.claude/shirabe-extensions/release.local.md

# Release

Cut a release. Handles version selection, precondition checks, blocker
identification, release notes, draft creation, workflow dispatch, monitoring,
and the host installs the repository declares for after a release.

## Invocation

```
/release [version] [--dry-run]
```

- **`/release`** -- analyzes commits and recommends a version
- **`/release 0.3.0`** -- uses the specified version (`v0.3.0` also accepted);
  anything other than `X.Y.Z` or `X.Y.Z-<pre>` stops the run before it starts
- **`/release --dry-run`** -- previews without side effects

## The release grant

A session niwa dispatched with the `cut-release` authority releases the way a
session holding `merge-pr` merges: the grant is the approval, and nobody is
asked to approve the cut. `release-grant.sh` reads it, once per question
below, through one bounded `niwa authority check`; it prints `go=grant
dispatch=<id>` for a holder and `go=person reason=<why>` for anyone else:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-grant.sh"
```

For a holder the grant answers the version-and-notes go (Phase 3 step 6),
whatever kind of cut it is: a first release, a recommended major bump with no
version given, and a range holding a commit pushed straight to the branch
included. It answers running a check or an asset from the untracked
`release.local.md` (Phase 2 step 7, Phase 4), and the tracked installs after
the release is published (Phase 7). Any other session, a session niwa didn't
dispatch included, is asked each of these, as it always was.

These still go to a person whatever the grant, because each is a finding
about what the release contains or runs, not an approval of the cut, the way
failing required checks still block a `merge-pr` holder:

- **An `UNRESOLVED` line from the security check** (Phase 2 step 6): a `(#N)`
  in the range that isn't a pull request here, so nobody can say what change
  it carries or whether it needs a security treatment.
- **A declared check that exits 5 with a `confirm:` line** (Phase 2 step 7):
  the check found something in this release only a person can accept, such as
  a drop in an eval pass rate.
- **How a `security`-labelled pull request is described** (Phase 2 step 6):
  whether naming the fix arms an attacker before users upgrade is a judgment
  about the change itself.
- **An `## After release` command from `release.local.md`** (Phase 7): an
  untracked command run on the host after the cut, outside anything a
  reviewer saw, is asked about one at a time.

Every Phase 2 check stops a holder's run exactly as it stops anyone's. The
grant's answer is advisory: the workspace gate still decides the draft and
the dispatch for this session on its own.

## Phases

### Phase 1: Version Analysis and Release Contents

**Check a given version first.** When the invocation names a version, check
it before anything else runs, and before Phase 2's declared checks put it on
a command line. Pass it as one single-quoted argument, exactly as typed:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" version '<as typed>'
```

It drops one leading `v` and prints the bare version, which is the version
from here on. A value that isn't `X.Y.Z` or `X.Y.Z-<pre>` (letters, digits and
dots) prints `refused=bad_version` and exits 2 with a message naming it: stop
the run there, repeat that message, and run nothing else. A value holding a
single quote can't be quoted this way and can't pass the check either, so
stop on it the same way without running the command. The check is the same
for every session, whatever its grant. Nothing is open yet, so there is no
session to close.

Establish what the release contains, once, and keep it in the release's koto
session, `release-<topic>`. Phase 2's security check and Phase 3's notes are
both consumers of the pull request set derived here; neither re-derives it.
Later phases run as separate shell invocations, so a shell variable set here
is gone by Phase 2 and an empty list there would pass the security check by
finding nothing. The session keys are the release's membership, and `/release`
writes no file to the `wip/` staging folder.

```bash
topic=$("${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" topic) || exit
echo "Release session: release-$topic"
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open release "$topic" || exit
"${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" membership "$topic" || exit
echo "In the release, not in a pull request:"
"${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" read "$topic" unattributed
```

`<topic>` below is what `release-state.sh topic` prints: the repository's
owner and name from `gh repo view`, joined and lowercased (`tsukumogami-shirabe`
for this repository). A later phase recomputes it with the same command.

- **`open`** attaches to a live `release-<topic>`, replaces a finished one, or
  creates it. A non-zero exit stops the run with the script's message: 127 or 69
  means koto is missing or too old, 6 means HEAD is detached, and the skill
  never falls back to files.
- **`refused=branch_mismatch`** (exit 5) means a `release-<topic>` is still live
  from an interrupted run on another branch. Every run closes its session, so a
  live one is a run that never finished. Stop and tell the author to close it
  and run `/release` again:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close release-<topic> abandoned
  ```

- **`membership`** computes the range (`<last v* tag>..HEAD`, or `HEAD` when no
  tag exists), the pull requests in it and the commits that name none, and
  writes them as `work/range`, `work/prs` and `work/unattributed`, replacing
  whatever an earlier run left. It also removes a `work/notes.md` an earlier
  run left, so a crashed run's notes can't be published. A release with no
  `(#N)` subjects gets an empty `work/prs`, which reads back as an empty list.
- **`read <topic> <range|prs|unattributed|notes|head>`** prints one key. A key
  that is absent exits 1 saying Phase 1 did not run; stop there. `work/head`
  is the commit the release is cut from; Phase 7 reads the committed
  extension there.

The membership step's rules, for the record:

- The range's guard is load-bearing: `..HEAD` is a range git ACCEPTS, and it
  resolves to zero commits, so without the guard a first release derives an
  empty set silently rather than failing.
- The pull requests are the numbers in `(#N)` suffixes, GitHub's squash-merge
  title, sorted and unique. `grep` exiting 1 on no match is a legal outcome, not
  a failure.
- The unattributed commits are the release chore commits and anything pushed
  straight to the base branch.

`work/prs` is the release's membership, computed here and nowhere else; Phase
2 and Phase 3 read it. **Do not re-derive it from a `gh pr list --search
"merged:>..."` query**, for two reasons that compound. GitHub reads a bare
`merged:>YYYY-MM-DD` as "after the *end* of that day", so a date-shaped bound
silently drops every pull request merged on the previous tag's own calendar
day. And `merged:>` has no upper bound at all, so it also credits anything
merged *after* the release point -- against `v0.16.0` with a release point of
`v0.17.0` it returns 18 pull requests where the range holds 13. The commit
range has both bounds and no date semantics to get wrong.

The parse assumes GitHub wrote the `(#N)` suffix. That holds while the
repository squash-merges (`allow_merge_commit` and `allow_rebase_merge` both
false, with `squash_merge_commit_title: PR_TITLE`) -- a live repository setting,
not something this file can enforce, and one an adopting repository may not
share. The pattern is anchored to the end of the subject, so a pull request
whose own title ends in a parenthesized number is not misread.

The unattributed list printed above is what makes that assumption checkable
rather than assumed. A handful of entries is normal: every release carries the
version-bump chore commit. A list that is suddenly most of the range means the
suffix is no longer being written -- the merge strategy changed, or work is
landing by direct push -- and the pull request set is incomplete. Stop and
reconcile by hand before releasing when that happens (close the session
`abandoned` first); it is the one signal that the derivation has gone quiet
rather than empty. Printing it here, before the notes are drafted, is also what
makes it useful rather than a footnote.

If no tag exists, this is the first release: there is nothing to bump from,
so the recommended version is `0.1.0` unless the invocation gave one. Phase 3
settles it as it settles any version.

Count commits by prefix over the range in `work/range`
(`release-state.sh read <topic> range`):

| Prefix | Bump signal |
|--------|------------|
| `feat!:`, `fix!:`, `BREAKING CHANGE` | major |
| `feat:` | minor |
| `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`, `test:` | patch |

Version input is normalized by the check above: both `0.3.0` and `v0.3.0` are
accepted.

### Phase 2: Precondition Checks

All must pass before proceeding:

1. **Clean working tree**: `git status --porcelain` is empty
2. **CI green on HEAD**: Check CI status using this fallback chain:
   - First try commit status: `gh api repos/{owner}/{repo}/commits/{sha}/status`
   - If state is `pending` with 0 check runs (common for squash-merge commits where
     CI ran on the PR branch, not the merge result), fall back to checking the latest
     workflow runs on the branch: `gh run list --branch main --limit 3 --json conclusion`
   - If the latest completed run has `conclusion: success`, treat as green
   - Only fail if there's an actual failure, not just missing status data
3. **No existing tag**: `git tag -l v<version>` returns empty
4. **No existing draft**: `gh release view v<version>` returns 404
5. **No release blockers**: Query `gh issue list --label blocks-release --state open`.
   If any exist, list them and stop. Also check `gh issue list --label priority:critical --state open`.
6. **Security-labeled PRs**: read the labels of every pull request Phase 1
   derived and keep the ones carrying `security`:

   ```bash
   topic=$("${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" topic) || exit
   prs=$("${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" read "$topic" prs) || exit
   printf '%s\n' "$prs" | while read -r pr; do
     [ -n "$pr" ] || continue
     gh pr view "$pr" --json number,title,labels \
       --jq 'select([.labels[].name] | index("security")) | "\(.number) \(.title)"' \
       || echo "UNRESOLVED #$pr: in the release range but not a pull request in this repo"
   done
   ```

   The `read` runs first, outside the loop, so an absent key stops the run
   ("Phase 1 did not run") instead of passing the check on an empty list.

   The set is the one Phase 1 derived and Phase 3 writes the notes from, so a
   pull request cannot reach the notes without also reaching this check. That is
   the point: this check fails permissively -- a pull request it does not see is
   published with a standard description and nobody is prompted -- so it must not
   be reading a different, narrower set than the notes are.

   The `|| echo` is not decoration. A `(#N)` suffix can name something that is
   not a pull request in this repository: a revert, a hand-written subject, or a
   commit cherry-picked from elsewhere. `gh pr view` exits non-zero on those, and
   without the branch the number would be skipped in silence -- which is the
   failure mode this whole check exists to close. Treat any `UNRESOLVED` line as
   something to look at by hand before releasing, not as a pass.

   If found, flag them and use AskUserQuestion to decide how each is handled in the
   release notes, following the pattern in
   `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`. Read the PR before
   asking, and recommend one of the three treatments rather than listing them:

   - **Standard description (Recommended)** when the PR is a hardening change with
     no exploitable window in a released version
   - **Redacted** when the PR fixes a live vulnerability and the detail would arm an
     attacker before users upgrade
   - **Excluded** when naming the change at all would point at an unfixed surface

   Ground the recommendation in what the PR actually did -- cite the change and
   whether an affected version already shipped. Name the tiebreaker every time,
   not only when the call is close: **default to the more conservative
   treatment**. State it even when the call reads as clear-cut, and say that it
   did. A reader cannot tell from a recommendation alone whether it was near the
   line, so the rule that produced it is part of the recommendation; and the one
   case where the tiebreaker matters most is the one where the recommending
   agent was most confident it did not.

7. **Repository-declared checks**: run what the repository lists under
   `## Release checks` in its release extension, imported above from
   `.claude/shirabe-extensions/release.md` (tracked) and
   `.claude/shirabe-extensions/release.local.md` (untracked, this host only).
   Each bullet under that heading is one check: the command in its backticks,
   which starts with a repository path. No extension file, or no
   `## Release checks` heading in either, means there are no declared checks:
   print nothing for this step and go on. Declared checks run in `--dry-run`
   too, because dry-run runs this phase; a check that must not write anything
   reads `RELEASE_DRY_RUN`.

   Run these after checks 1-6, which are cheap reasons to stop first. A
   declared check can be the slowest thing a release does.

   a. **Show the code the checks will run.** From the repository root:

      ```bash
      git diff --stat "$RANGE" -- scripts/ skills/ .claude/shirabe-extensions/
      ```

      `RANGE` is the release range Phase 1 recorded; read it back, since this
      is a new shell: `RANGE=$("${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh"
      read <topic> range) || exit`. When it reads `HEAD` (a first release, no
      tag) print `git diff --stat "$(git hash-object -t tree /dev/null)" HEAD --
      scripts/ skills/ .claude/shirabe-extensions/` instead.

   b. **For each check, in order** (`release.md`'s first, then
      `release.local.md`'s), print the command and the file it came from. A
      check from `release.local.md` is labelled local: that file is untracked
      and nobody reviewed it, so ask with AskUserQuestion before running it,
      and skip it on a no. A session holding the release grant isn't asked:
      before the first local check, run `release-grant.sh` once (see **The
      release grant**), and on `go=grant` run each local check unasked,
      printing `local check: run on the grant of dispatch <id>` before it.

   c. **Run it from the repository root** (`git rev-parse --show-toplevel`),
      exactly as written, with these variables set for the command:

      | Variable | Value |
      |----------|-------|
      | `RELEASE_VERSION` | the version Phase 1 recommends, or the one given, as bare `X.Y.Z` (strip a leading `v`). Phase 3 may still change it; the `## Release assets` step in Phase 4 gets the confirmed one |
      | `RELEASE_LAST_TAG` | the last release tag: `RANGE` above without its `..HEAD`, empty when `RANGE` is `HEAD` (a first release) |
      | `RELEASE_DRY_RUN` | `1` under `--dry-run`, `0` otherwise |
      | `RELEASE_CONFIRMED_DROPS` | the empty string, so a value inherited from the environment can't pre-confirm anything |

      For example, with the check `scripts/example-check.sh --flag`:

      ```bash
      RELEASE_VERSION=0.3.0 RELEASE_LAST_TAG=v0.2.0 RELEASE_DRY_RUN=0 RELEASE_CONFIRMED_DROPS= scripts/example-check.sh --flag
      ```

      A check can run for a long time. Give it the longest timeout the
      session allows, or run it in the background and wait for it to exit;
      never treat a timeout as a pass.

   d. **Act on the exit code.**
      - **0**: the check passed. Go to the next one.
      - **5**: the check needs a person to confirm something before the
        release goes on. Its last output line reads `confirm: <NAME>=<value>`.
        Show the check's output and ask with AskUserQuestion whether to
        proceed, naming what the check reported. On a yes, run the same
        command again with `<NAME>=<value>` set in place of the empty value
        (do not ask again about a local check already approved). That run's
        exit 0 continues; any other exit, 5 included, stops the release as
        below, so a confirmation is asked for once per check. On a no, or when
        the question can't be put to a person, stop the release.
      - **Anything else**: stop the release. Name the check (its command and
        file) and repeat the last lines of its output.

      A check that exits 5 without a `confirm:` last line is treated as any
      other non-zero exit, and so is a `confirm:` line whose `<NAME>` is not an
      upper-case variable name (`[A-Z_][A-Z0-9_]*`) or whose `<value>` holds
      anything beyond letters, digits, `.`, `_`, `-` and `,`: the value goes
      onto a command line, so it is never passed through when it could be
      read as shell.

Report the specific failure and stop on any check, closing the session first:
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close release-<topic> abandoned`.
Name the check that stopped the run (clean tree, CI, tag, draft, blockers, or
the declared check's command and file). These checks stop every run the same
way, a session holding the release grant included.

### Phase 3: Release Notes and Version Confirmation

Generate notes, present them, and confirm the version: with the user, or,
for a session holding the release grant on an ordinary cut, from the grant
(step 6).

1. Gather commits over the range Phase 1 stored:

   ```bash
   topic=$("${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" topic) || exit
   range=$("${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" read "$topic" range) || exit
   git log --oneline "$range"
   ```

   Each subject carries the conventional-commit type, the description, and the
   `(#N)` suffix, so this one read has everything the notes are written from.
2. Cross-check against `work/prs` from Phase 1 (`release-state.sh read <topic>
   prs`) -- the release's membership. Every number in it must appear in a
   subject step 1 gathered, and no other pull request may be credited. It is a
   check, not a second gather: the key was derived from this same range, so a
   disagreement means one of the two reads went wrong and the notes should not
   be written until you know which.
3. Group by type (features, fixes, other)
4. Draft user-facing notes:
   - Focus on user impact
   - One sentence per change
   - Highlight breaking changes prominently
   - Handle security-labeled PRs per user's Phase 2 decision

5. **Print the notes in chat** so the user can read them,
   followed by the output of `release-state.sh read <topic> unattributed`
   under a short heading such as "In the release, not in a pull request".
   Phase 1 already printed this list; repeating
   it here puts it in front of the author at the moment they are deciding
   whether the notes are complete.

6. **Decide where the go comes from.** A session holding the release grant
   takes the go from it; everyone else is asked as below. Add `--unresolved`
   when Phase 2's security check printed any `UNRESOLVED` line:

   ```bash
   topic=$("${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" topic) || exit
   "${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" go "$topic" [--unresolved]
   ```

   Any output other than the two lines below, or a non-zero exit, is a
   `go=person`: ask.

   It prints one line. `go=person reason=<why>` means a person gives the go:
   an `UNRESOLVED` security line (`unresolved`), or a session the grant
   doesn't cover (the reason says which). Go on with the question below.

   `go=grant dispatch=<id>` means the go comes from the grant. Ask nothing:
   the version is the one given, or else the recommended one (a major bump
   and a first release's `0.1.0` included), and the notes are the ones
   printed in step 5. Print the version, then this line with the dispatch id
   it printed, and go on to Phase 4:

   ```
   release go: from the grant of dispatch <id>
   ```

   Otherwise, **use AskUserQuestion** to present the recommended version with
   alternatives. Include the commit analysis from Phase 1:

   > Based on 3 feat, 8 fix, and 1 breaking change since v0.2.0:
   >
   > 1. **v0.3.0 (minor) -- Recommended** because new features were added
   > 2. **v1.0.0 (major)** -- if the breaking change warrants a major bump
   > 3. **v0.2.1 (patch)** -- if the features are minor enough to treat as a patch
   > 4. **Custom version** -- enter a specific version

   If the user picks a different version than the one used to draft the
   notes, update the notes title to reflect the chosen version. A version
   chosen here, a custom one above all, goes through the same check as a
   given one before it is used anywhere (`release-state.sh version '<chosen>'`);
   a version that fails it stops the run as in step 7.

7. Allow the user to request edits to the notes before proceeding. Only
   move to Phase 4 after the user confirms both version and notes. If the
   author declines the version or the notes, or the question can't be put to
   a person, stop: close the session `abandoned`
   (`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close release-<topic>
   abandoned`) and report that the run stopped at the go, and why.

### Phase 4: Draft Release

Phase 3 produces the notes in chat. Store the confirmed notes in the session,
then hand `gh release create` a copy of them in a scratch directory that is
removed when the command returns. Write the notes to `$dir/notes.md` with the
Write tool, then:

```bash
dir=$("${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch) || exit
# write the confirmed notes to "$dir/notes.md", then:
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" put release-<topic> work/notes.md "$dir/notes.md"
rm -rf "$dir"
```

Then create the draft:

```bash
notes_dir=$("${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch) || exit
notes_file=$("${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" get release-<topic> work/notes.md "$notes_dir") || { rm -rf "$notes_dir"; exit 1; }
rc=0
gh release create "v<version>" \
  --draft \
  --title "v<version>" \
  --notes-file "$notes_file" || rc=$?
rm -rf "$notes_dir"
exit "$rc"
```

The draft survives workflow failures and is editable in the GitHub
UI.

**Release assets.** Once the draft exists, and only when this isn't a dry
run, run each bullet under `## Release assets` in the release extension
(`release.md`, then `release.local.md`; a local one is asked about, or run on
the grant, as in Phase 2 step 7). No heading means nothing to attach. Print each command and its file,
then run it from the repository root with `RELEASE_VERSION` set to the
version confirmed in Phase 3 (bare `X.Y.Z`), `RELEASE_LAST_TAG` set as in
Phase 2 (read the range back with `release-state.sh read <topic> range`, as
Phase 2 step 7a does, since this is a new shell),
`RELEASE_DRY_RUN=0`, and `RELEASE_CONFIRMED_DROPS` set to the empty
string, as in Phase 2.

- Exit 0 with a last output line `asset: <path>` names a file to attach. The
  path must name an existing regular file and hold no quotes, `$`, backticks
  or line breaks; anything else is reported as a failed asset, not uploaded.

  ```bash
  gh release upload "v<version>" "<path>" --clobber
  ```

- Exit 0 without an `asset:` line means there is nothing to attach.
- A non-zero exit, or a failed upload, does not stop the release: the draft
  already exists. Report it with the command to retry (the item's command, or
  the `gh release upload` line above), and quote the extension's note on what
  that item's failure costs, if it gives one.

The session stays open through Phases 5 to 7 and is closed once, at the end
of the run (Phase 7), so a step refused on the way closes it `abandoned`
instead.

If draft creation fails, stop. When the workspace gate denied the command,
or asked and the answer was no or nobody could answer, report the step (the
draft) and the gate's reason as it gave it; otherwise check `gh auth status`.
Either way close the session `abandoned`; the stored notes stay readable
(`release-state.sh read <topic> notes`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close release-<topic> abandoned
```

Never reach a refused step another way: no other command, API call or
workaround creates the draft.

### Phase 5: Workflow Dispatch

Detect the release workflow by scanning `.github/workflows/*.yml` for files
referencing `tsukumogami/shirabe/.github/workflows/release.yml` in `uses:` lines.

If found, dispatch with three inputs (version, tag, ref):

```bash
gh workflow run <workflow-file> \
  -f version=<version> \
  -f tag=v<version> \
  -f ref=main
```

Once the dispatch succeeds, record it, so Phase 7 knows this run dispatched
this version and nothing else can start its installs:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" mark <topic> dispatched <version>
```

If the dispatch is refused (the workspace gate denies it, or asks and the
answer is no or nobody can answer) or fails, stop: report the step (the
dispatch) and the gate's reason or the error, and close the session
`abandoned`. Never reach a refused dispatch another way, such as the REST
form (`gh api .../actions/workflows/<file>/dispatches`) or a tag push: the
draft stands, and a person can dispatch it later.

**Skill-only mode**: If no release workflow found, print:

```
No release workflow detected. To complete the release:

  git tag -a v<version> -m "Release v<version>" && git push origin v<version>

Draft release with notes: <url>
```

### Phase 6: Monitoring

1. Record dispatch timestamp
2. Poll `gh run list --workflow=<name> --limit=5 --json databaseId,createdAt,status,conclusion`
   every 10 seconds
3. Use timestamp correlation to match the dispatched run (created within
   30 seconds of dispatch time)
4. Up to 5 minutes:
   - **Success**: Print the release URL, and whether `gh release view
     v<version> --json isDraft` already reports it published, as a line of
     the report. In some repositories later workflows publish the release;
     Phase 7 owns that wait.
   - **Failure**: Print details. Suggest `gh run view <id> --log-failed`.
   - **Timeout**: Print run URL: "Workflow still running -- monitor at <url>"
5. Record how the monitoring ended, `success`, `failure` or `timeout`:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-state.sh" mark <topic> concluded <success|failure|timeout>
   ```

A failed or still-running workflow is reported above, not retried. Go on to
Phase 7 either way; it runs no install unless the run concluded `success`.
In skill-only mode, once the instructions are printed, close the session
`done` as Phase 7's last step says and stop.

### Phase 7: After Release

The installs the repository declares for its host once a release is out:
reinstalling the released tool, checking it reports the new version,
re-applying a workspace. Each is a bullet under `## After release` in the
release extension, the command in the bullet's first backtick span, as for
`## Release checks`. `after-release.sh` reads them, waits for this run's
release to be published, and runs them; the skill asks its questions between
its two halves.

1. **Plan.** The wait can take up to 30 minutes, longer than a foreground
   shell call is allowed, so start it in the background and wait for it to
   exit:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/after-release.sh" plan <topic>
   ```

   - **No output, exit 0**: the repository declares no installs. Say nothing
     about installs and go on to the close.
   - **Exit 2** (`refused=not-dispatched` or `refused=workflow-<conclusion>`):
     this run didn't dispatch the release, or its workflow didn't succeed.
     Nothing runs; report each `not-run` line.
   - **Exit 3** (`published=no reason=wait-ran-out` or `view-failed`): the
     release wasn't seen published. Say the release isn't published yet (or
     that `gh release view` failed), report each `not-run` line, and say the
     installs can be run by hand once it is.
   - **Exit 0 with `published=v<version>`**: the second line is the grant read
     again (a session that held it at the go may not hold it now), and each
     `install tracked <n> <command>` or `install local <n> <command>` line is
     one install.

   The tracked commands are read from `release.md` as committed at the
   commit Phase 1 recorded, so an edit to the working copy during the run
   can't add one.

2. **Ask what the grant doesn't answer.** On `go=grant`, ask nothing about
   the tracked commands. Otherwise put one AskUserQuestion that lists every
   tracked command; a yes runs them all, and a no, or no person to answer,
   runs none. Ask about each local command on its own, for every session,
   holder or not, naming the command; a no skips it.

3. **Run.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/after-release.sh" run <topic> [--tracked-approved] [--local-approved <n>]...
   ```

   Pass `--tracked-approved` for a person's yes to the tracked list, and
   `--local-approved <n>` for each local command answered yes. Each command
   runs from the repository root with `RELEASE_VERSION` (bare `X.Y.Z`),
   `RELEASE_WORKSPACE_ROOT` (the nearest directory above the repository
   holding `.niwa/workspace.toml`, or empty) and `RELEASE_DRY_RUN=0` set.
   Run it in the background too; a reinstall or a workspace apply can be
   slow.

4. **Report.** Print each `result` line: `passed`, `failed`, `not-run` or
   `declined`. The first command that fails stops the list, so a failed
   reinstall or version check never reaches a workspace apply; repeat the
   failed command's last output lines, which `run` prints after it. The
   release stays published whatever an install does. Keep the output in this
   run's report; never copy it into an issue or a pull request.

The run ends here, and so does its state. Close the session `done`, whatever
the monitoring and the installs found; its keys stay readable:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close release-<topic> done
```

## Dry-Run Mode

When `--dry-run` is passed:

- Phases 1-3 run normally (version analysis and release contents, checks,
  notes + confirmation). Phase 1's derivation reads git and nothing else, so it
  runs on this path unchanged, and so do the version check and Phase 3's go
  (a holder's dry run asks no go either).
- The repository's declared checks (Phase 2 step 7) run, with
  `RELEASE_DRY_RUN=1`, and stop the dry run the same way they would stop a
  release.
- Phase 4-7 are skipped (no draft, no dispatch), so no `## Release assets`
  command runs, nothing is attached, and no `## After release` command
  runs. The session is closed `done` at the
  end of the dry run: `"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close
  release-<topic> done`.
- Print what would happen: which files change, what tag, what dev version

## Error Recovery

| Phase | Failure | Recovery |
|-------|---------|---------|
| 1 | `version` prints `refused=bad_version` | The version given isn't `X.Y.Z` or `X.Y.Z-<pre>`. Nothing ran and no session is open; run `/release` again with a version that is |
| 1 | `open` prints `refused=branch_mismatch` | A `release-<topic>` is live from an interrupted run on another branch. Run `skill-session.sh close release-<topic> abandoned`, then `/release` again |
| 1 | `work/prs` is empty but the range has commits | Read `work/unattributed` (`release-state.sh read <topic> unattributed`): if every commit is listed there, the repository is not writing `(#N)` suffixes (the merge strategy changed) and the derivation's assumption no longer holds |
| 1 | `work/range` holds `HEAD` on a repo that has tags | `git describe` found no `v*` tag from this commit -- check you are on the release branch and that tags are fetched (`git fetch --tags`) |
| 2, 3 | `read` exits 1 saying Phase 1 did not run | The key is absent: Phase 1's `membership` step did not complete in this session. Run Phase 1 again |
| 2 | `UNRESOLVED #N` from the security check | The `(#N)` names something that is not a pull request here (a revert, a hand-written subject, a cherry-pick). Check it by hand before releasing |
| 2 | Dirty tree | `git stash` or commit |
| 2 | CI failing | Fix and push |
| 2 | Tag exists | `git push --delete origin v<version>` |
| 2 | Draft exists | `gh release delete v<version> --yes` |
| 2 | Blockers open | Resolve the listed issues first |
| 2 | A declared release check exits non-zero (other than 5) | The step repeated the last lines of the check's output; fix what they report, and run the release again; the check is named with the file that declared it |
| 2 | A declared check exits 5 and the answer is no, or nobody can answer | The release stopped on purpose. Look into what the check reported; run the release again, interactively, to confirm it |
| 4 | A `## Release assets` command fails or its upload fails | The draft stands. Re-run the command from the repository root with the same `RELEASE_*` values, then `gh release upload v<version> <path> --clobber` |
| 3 | `go` prints `go=person` for a session dispatched to release | The reason says why: `unresolved` is a finding the grant never answers (see **The release grant**); the others (`not-held`, `decider-person`, `no-niwa`, ...) mean niwa didn't confirm the grant. The go is asked as usual |
| 3 | The go is declined, or nobody can answer it | The run stopped and closed its session `abandoned`. Run `/release` again when a person can give the go |
| 4 | The workspace gate refuses `gh release create` | The run stopped, closed its session `abandoned`, and printed the gate's reason. Ask whoever dispatched the session for the grant, or cut the release from a session that holds it; don't create the draft another way |
| 4 | Draft creation fails | Check `gh auth status`; the notes are still in `work/notes.md`. Close the session `abandoned` and run again |
| 5 | The workspace gate refuses the workflow dispatch | The run stopped, closed its session `abandoned`, and printed the gate's reason. The draft stands; a person dispatches the workflow, never through the REST endpoint as a way around the gate |
| 5 | Dispatch fails | Check workflow exists and permissions |
| 6 | Workflow fails | `gh run view <id> --log-failed` |
| 6 | Timeout | Check URL printed at timeout |
| 7 | `plan` prints `published=no reason=wait-ran-out` | The release is still a draft after 30 minutes; a later workflow may still publish it. Once it is published, run each command it named from the repository root with `RELEASE_VERSION` set |
| 7 | `plan` prints `refused=...` | This run didn't dispatch the release, or its workflow didn't succeed, so no install is this run's to make |
| 7 | `run` prints `result failed` | The release stands. Fix what the command's last lines report, then run it and the `not-run` ones after it by hand, in order |
