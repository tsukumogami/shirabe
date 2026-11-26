# Topic Derivation

A skill invoked as `/<skill> <topic>` needs a topic slug: the short
kebab-case name its session, branch and documents are keyed on. The
slug is the agent's job, not the author's. An author who writes
`/deliver the cache changes we just discussed` has described the work,
and the run goes ahead on a slug the agent picked from that. Stopping to
ask for a literal slug when the work is plain from the prompt or the
conversation is the failure this rule exists to prevent.

This file states the rule once. Every skill that takes a topic points
here from its Input Modes section; the skill's own modes (a document
path, an issue number, a lifecycle verb) are classified first, and this
rule decides only how a topic is obtained when the input is a topic.

## The Rule

Set the flags aside first, exactly as the skill already does. What is
left is the positional input.

1. **A slug given as-is.** When the positional input is one token that
   matches the skill's slug pattern (lowercase letters, digits and
   hyphens, not starting or ending with `-`), it is the slug. When it
   is several words and the first is a hyphenated token matching the
   pattern (`plugin-cache make the cache faster`), that first token is
   the slug and the rest is the author's description. Use a given slug
   exactly as typed: no rewording, no shortening.
2. **Derived from the prompt.** Otherwise the positional input is the
   author's description of the work. Pick a slug that names the work:
   two to five lowercase words joined by `-`, at most 60 characters,
   matching the skill's slug pattern. Name the thing being built or
   decided (`plugin-cache-invalidation`), not the request around it
   (`the-changes-we-discussed`). When the description points back at
   the conversation ("the work we discussed", "what we just agreed"),
   take the slug from what the conversation settled.
3. **Derived from the conversation.** When the positional input is
   empty but the conversation already describes the work this skill is
   being asked to do, derive the slug from the conversation the same
   way.
4. **Ask only when nothing describes the work.** Empty arguments and
   nothing in the conversation to go on is the one case where the
   skill asks the author what the work is. Ask for the work, not for a
   slug, then derive the slug from the answer.

Before settling on a derived slug, prefer one already in use for this
work, so a re-invocation picks a run up instead of starting a second
one beside it: the slug in the current `docs/<slug>` branch name, a
document or session for the same work, or a slug named earlier in the
conversation.

## Name the Slug

The first line of the skill's output names the slug and where it came
from, so the author can correct it before anything is written under it:

```
Topic: plugin-cache-invalidation (derived from the prompt; re-invoke with a slug to use another)
```

For a slug given as-is, `Topic: <slug>` is enough.

## Free Text Is Description, Not Tokens

Words describing the work inform the slug and the run's context: the
phases that read the author's intent (scoping, the problem statement,
the first draft) read that description. They are never passed to a
script as stray positional tokens. Where a skill writes an args file,
the positional token it writes is the slug alone, followed by the
flags as typed. A script that refuses two leftover words or a
malformed topic still refuses them; the agent just doesn't hand it any.

## What Does Not Change

- **Validation.** Every slug, given or derived, still goes through the
  skill's own check (the session script, koto's topic variable, the
  Phase 0 regex test) exactly as before. Derivation produces a slug
  that passes it; it doesn't loosen it.
- **Paths.** A token that is a file path is not a description. A skill
  with a path mode classifies it there; a skill without one refuses it
  as it always has. A path is never mined for a slug unless the skill's
  own path mode says to.
- **Callers.** A parent skill, a coordinator or a `--koto-leg` caller
  passes a slug it already chose. That slug is used as given; nothing
  here re-derives it.
- **Flag values.** The `--upstream` value is never an input to the
  slug.
