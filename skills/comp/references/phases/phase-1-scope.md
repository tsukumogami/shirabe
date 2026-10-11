# Phase 1: Scope

Conversationally scope the competitive analysis before any research.
The goal is a sharp competitive question and a bounded market slice.

## 1.1 Establish the Competitive Question

Work with the user to state, in one or two sentences, the decision this
analysis is meant to inform. A COMP exists to answer a question — "should
we build X the way competitor A does, or the way B does?", "is there an
unserved segment we could own?" — not to catalog the market for its own
sake. Record the question; it becomes the frontmatter `problem` field
and the thing the Implications section must resolve.

## 1.2 Bound the Market Slice

Define the slice under survey: which segment, which class of tools or
products, and — just as important — what is explicitly out of scope. A
COMP that tries to survey "everything" produces a shallow matrix.
Record the boundary; it becomes the frontmatter `scope` field and the
Market Overview's framing.

## 1.3 Distinguish Market-Level vs Tool-Level

Decide whether the survey compares products/tools (tool-level) or
segments/approaches (market-level). This choice drives what the rows of
the Comparative Matrix are. Note it for Phase 2.

## 1.4 Upstream Injection

If Phase 0 recorded an upstream path (from `--upstream`), read it now and let it sharpen the competitive question and
the slice. Do not copy upstream content into the COMP; use it to frame.

## Output

Write the scoping notes to key `work/scope.md` in `comp-<topic>`: the
competitive question, the market slice and its boundary, the market-vs-tool
decision, and any upstream framing. Assemble the text in a scratch
directory, put it, and remove the directory:

```bash
dir=$("${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" scratch)
# write the notes to "$dir/scope.md", then:
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" put comp-<topic> work/scope.md "$dir/scope.md"
rm -rf "$dir"
```

Re-running the `put` replaces the key, so a revision during the
conversation is one more `put`. The key feeds Phase 2; read it back with
`koto context get comp-<topic> work/scope.md`.
