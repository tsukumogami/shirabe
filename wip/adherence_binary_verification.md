# Binary Verification Notes

Claims checked directly against the installed Claude Code binary at
`/home/dgazineu/.local/share/claude/versions/2.1.233` rather than against
documentation, because two of them are load-bearing for the decision and one
research pass had already returned field names that do not exist.

## Skill-registered hooks: CONFIRMED

Alternative 6 rests entirely on skill frontmatter being able to register hooks
that persist for the rest of the session. Extracted from the binary:

```
Registered ${i} hooks from skill '${n}'
Removing one-shot hook for event ${s} in skill '${n}'
```

with the surrounding registration call passing a per-hook `matcher`.

The second string is the proof of the persistence semantics. A *one-shot*
removal path only makes sense if the default is persistent -- if skill hooks
expired with the turn there would be nothing to distinguish and nothing to
remove. So: a skill registers hooks when it is invoked, those hooks stay armed
for the remainder of the session, and `once` is the opt-out.

This moves the mechanism from doc-only to confirmed.

## `SubagentStart`: present

25 occurrences in the binary. The `additionalContext` field on this specific
event remains doc-only -- the extraction around it timed out in research and I
did not re-run it. It matters because it is the only surface that reaches
`spawn_and_await` children, so it should be tested empirically before anything
depends on it (emit a distinctive token from a `SubagentStart` hook, then ask a
subagent to echo it).

## `updatedPrompt` / `expandedPrompt`: DO NOT EXIST

A documentation-summarization pass asserted both confidently. Neither string
appears anywhere in the binary. `updatedInput` appears 82 times and
`additionalContext` 44 times. Recorded here because it is the clearest available
warning that this design must be built against the binary rather than against a
summarized doc page.

## The session-id join: CONFIRMED wired

`crates/shirabe/src/pr_body_hook.rs` shows the PreToolUse hook input carrying
`session_id` alongside `tool_name` and `tool_input` (its own test fixture), and
the deny response already implemented as
`hookSpecificOutput.permissionDecision: "deny"` with
`permissionDecisionReason`. Koto's workflow record
(`~/.claude/projects/<encoded-cwd>/<session-id>/workflows/koto-<uuid>.json`) is
keyed by that same session id.

So the chain from "an edit is about to happen" to "this session has no koto
workflow record over the execute template" contains no inferred link.
