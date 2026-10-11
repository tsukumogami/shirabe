# Phase 5: File an Issue

The work is small enough to act on directly: one person can implement it without
a written contract, and the exploration made no architectural, dependency, or
structural decision that a future contributor would need explained. No document
is produced here.

**Before finalizing this arm:** check key `work/decisions.md`
(`koto context exists explore-<topic> work/decisions.md`, then `koto context get`
if it exists). If it exists and carries entries, the exploration decided
something that needs a durable home, and this is the wrong arm. The session's
keys never reach the repository, so a decision recorded only there is lost when
the branch closes. Return to Phase 4 and re-score: a chain entry point carries
those decisions into a document, and filing an issue does not.

If the decisions key is absent or empty, the arm is right.

**What the arm passes:** the issue. Summarize what the exploration established
so the issue body carries it, then name the next command.

Tell the author:

> Your exploration covered [what was investigated]. Here's what it established:
>
> [3-5 bullets, grounded in specific findings]
>
> That's one bounded piece of work with no open decisions in front of it. File
> it as an issue with your repo's issue tooling (`gh issue create`), then run
> `/work-on <issue-number>` to implement it.
>
> Your exploration research stays readable in the finished session
> `explore-<topic>` (`koto context get explore-<topic> <key>`) if the issue body
> should quote it.

`/work-on` is the skill that accepts an issue number. Do not name `/execute`
here: it takes a PLAN path and has no issue mode.

## Close the Session

The arm is done. Close the session; its keys stay readable:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close explore-<topic> done
```

## Artifact State

After this step:
- Session `explore-<topic>` closed; its keys stay readable
- No new artifacts
