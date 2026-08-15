//! Markdown-aware prose scoping, over a real CommonMark parse.
//!
//! A prose rule that matches raw body lines fires inside fenced code, URLs,
//! and table rows. The superseded writing-style check did exactly that, and
//! not because its scoping was attempted and failed: it iterated raw lines
//! and attempted no scoping at all. This module is the scoping.
//!
//! ## Why a parser and not line heuristics
//!
//! An earlier revision hand-rolled fence and frontmatter detection in about
//! 90 lines. It was wrong in two ways that both instantiate the defect
//! class this capability exists to end, and a review found both:
//!
//! - A fenced block whose first content line is itself a fence marker
//!   inverted: the scoper treated the inner marker as the close, so code
//!   became prose (a false positive inside a fence) and the real prose after
//!   the block became code (a false negative). CommonMark 4.5 forbids an
//!   info string on a closing fence, which is what distinguishes them.
//! - A document opening with a `---` thematic break had everything up to
//!   the next `---` consumed as frontmatter and never checked, while the
//!   file reported success.
//!
//! Hand-rolling this means re-deriving CommonMark one bug report at a time.
//! `pulldown-cmark` is a pull parser with no default features, which adds
//! two crates and no workflow step, because cargo already fetches the
//! dependency tree during the build CI already runs.
//!
//! ## What counts as prose
//!
//! Excluded: fenced and indented code blocks, inline code spans, HTML
//! blocks and inline HTML, link and image destinations, and table cells.
//! Included: headings, paragraph text, list item text, blockquote text, and
//! link *labels* — the words a reader reads.
//!
//! Headings are prose by decision, not by omission, and the decision moves
//! the corpus figure, so a frequency rule whose denominator nobody wrote
//! down is not reproducible.
//!
//! ## Two selections over one parse
//!
//! This module projects one CommonMark parse two ways, by opposite criteria.
//!
//! [`prose_spans`] answers "which words does a reader read". It excludes
//! inline code spans, link destinations, HTML, and table cells, because a
//! writing-style rule must not fire on a path or a URL.
//!
//! [`reference_spans`] answers "where in this file does a path count". It
//! takes the inline code spans and link destinations the first one excludes,
//! because there the paths *are* the subject. Both exclude fenced and
//! indented code, where a path is a worked example by construction. The
//! overlap is plain text, which both take.
//!
//! The second selection lives here, over the same parse, for the reason the
//! first one does: fence handling is the part that goes wrong, and it has
//! already been paid for once.

use pulldown_cmark::{Event, Options, Parser, Tag, TagEnd};

/// A run of prose text with the file line it starts on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProseSpan {
    /// 1-indexed file line.
    pub line: usize,
    /// Prose text originating on that line.
    pub text: String,
}

/// Prose spans for a document body.
///
/// `body` is the post-frontmatter lines; `body_start_line` is the 1-indexed
/// file line `body[0]` sits on, so spans carry file lines rather than
/// body-relative ones.
pub fn prose_spans(body: &[String], body_start_line: usize) -> Vec<ProseSpan> {
    // Normalize line endings once. A retained carriage return breaks fence
    // close-matching and paragraph boundaries.
    let source: String = body
        .iter()
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .collect::<Vec<_>>()
        .join("\n");

    if source.trim().is_empty() {
        return Vec::new();
    }

    // Tables are parsed so their cells can be excluded. Without the
    // extension a table is a paragraph of pipes and its cells read as prose.
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);

    let parser = Parser::new_ext(&source, options);

    // Byte offset of the start of each line, for offset-to-line mapping.
    let mut line_starts = vec![0usize];
    for (i, b) in source.bytes().enumerate() {
        if b == b'\n' {
            line_starts.push(i + 1);
        }
    }
    let line_of = |offset: usize| -> usize {
        let idx = match line_starts.binary_search(&offset) {
            Ok(i) => i,
            Err(i) => i.saturating_sub(1),
        };
        body_start_line + idx
    };

    let mut spans: Vec<ProseSpan> = Vec::new();
    let mut suppress_depth = 0usize;
    // Destination of the link currently being walked, if any. An autolink
    // `<https://x>` has a label equal to its destination, so its text is a
    // URL rather than words a reader reads; a real label is prose.
    let mut link_dest: Vec<String> = Vec::new();

    for (event, range) in parser.into_offset_iter() {
        match event {
            // Regions whose text is not prose. Depth-counted because they
            // nest: a code block inside a list inside a table cell.
            Event::Start(Tag::CodeBlock(_)) | Event::Start(Tag::Table(_)) => {
                suppress_depth += 1;
            }
            Event::End(TagEnd::CodeBlock) | Event::End(TagEnd::Table) => {
                suppress_depth = suppress_depth.saturating_sub(1);
            }

            Event::Start(Tag::Link { dest_url, .. }) => link_dest.push(dest_url.to_string()),
            Event::End(TagEnd::Link) => {
                link_dest.pop();
            }

            Event::Text(t) if suppress_depth == 0 => {
                let is_autolink_text = link_dest.last().is_some_and(|d| d == t.as_ref());
                let text = if is_autolink_text {
                    String::new()
                } else {
                    strip_url_tokens(&t)
                };
                if !text.trim().is_empty() {
                    spans.push(ProseSpan {
                        line: line_of(range.start),
                        text,
                    });
                }
            }

            // Inline code, raw HTML, and math carry no prose. Link and
            // image destinations never surface as Text events at all, so
            // URLs are excluded by construction rather than by a regex that
            // has to guess where one ends.
            Event::Code(_) | Event::Html(_) | Event::InlineHtml(_) => {}

            _ => {}
        }
    }

    spans
}

/// Drop whitespace-delimited tokens that are bare URLs.
///
/// CommonMark does not autolink a bare `https://…` in a paragraph, so the
/// parser hands it back as ordinary text. A URL is not words a reader
/// reads: it inflates the frequency denominator and its path segments can
/// contain banned words. This is token-shape matching, not markup parsing,
/// which is why it is a small function here rather than a parser concern.
fn strip_url_tokens(text: &str) -> String {
    if !text.contains("://") {
        return text.to_string();
    }
    text.split_whitespace()
        .filter(|tok| {
            let t = tok.trim_start_matches(['(', '[', '<']);
            !(t.starts_with("https://") || t.starts_with("http://"))
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// A path-shaped candidate, the file line it sits on, and its byte range
/// within that line.
///
/// The range is what makes one extractor serve both consumers. A check only
/// needs a line to report, so an extractor built for the check alone would
/// hand back `(line, text)` and leave the repoint to re-find the occurrence
/// with a second matcher -- one that can disagree with the first about which
/// occurrence it found on a line naming two paths. Carrying the range means
/// the substitution edits exactly what the extractor matched.
///
/// The range is line-relative rather than document-relative because that is
/// the coordinate a rewriter can act on: it survives the carriage-return
/// normalization the parse needs (a `\r` sits after every token on its line)
/// and it needs no offset table to apply.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RefSpan {
    /// 1-indexed file line.
    pub line: usize,
    /// Byte offsets of the span within its line, as a half-open range.
    pub range: std::ops::Range<usize>,
    /// The path exactly as written.
    pub text: String,
}

/// Path-shaped spans for a document body: every markdown path token outside
/// a fenced or indented code block.
///
/// `body` and `body_start_line` mean what they do for [`prose_spans`], so
/// spans carry file lines. A token is a run of path bytes ending in `.md`
/// and containing a `/`; a bare basename is excluded because no relocation
/// can invalidate one.
///
/// This is a *where*, not a *what*: deciding which of these paths is a
/// defect (artifact prefix, cross-repo form, URL, resolution) belongs to the
/// caller. Both callers -- the `FC20` check and `transition`'s repoint --
/// agree on where a path counts and disagree on what to do about it.
pub fn reference_spans(body: &[String], body_start_line: usize) -> Vec<RefSpan> {
    // Same normalization as `prose_spans`: a retained carriage return breaks
    // fence close-matching. Stripping it is safe for line-relative ranges,
    // because a `\r` only ever sits at end of line, after any token on it.
    let source: String = body
        .iter()
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .collect::<Vec<_>>()
        .join("\n");

    if source.trim().is_empty() {
        return Vec::new();
    }

    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    let parser = Parser::new_ext(&source, options);

    // The parse decides exactly one thing here: where the code blocks are.
    // A `Start` event's offset range covers the whole element, so one range
    // per block is the entire exclusion set -- fenced and indented alike,
    // including the fence whose first content line is itself a fence marker.
    let mut code_ranges: Vec<std::ops::Range<usize>> = Vec::new();
    for (event, range) in parser.into_offset_iter() {
        if let Event::Start(Tag::CodeBlock(_)) = event {
            code_ranges.push(range);
        }
    }

    let mut line_starts = vec![0usize];
    for (i, b) in source.bytes().enumerate() {
        if b == b'\n' {
            line_starts.push(i + 1);
        }
    }
    let line_index_of = |offset: usize| -> usize {
        match line_starts.binary_search(&offset) {
            Ok(i) => i,
            Err(i) => i.saturating_sub(1),
        }
    };

    let bytes = source.as_bytes();
    let mut spans: Vec<RefSpan> = Vec::new();
    let mut start = 0usize;

    // Maximal runs of path bytes, rather than a search for `.md` with a
    // walk-back. The run is what decides where a token ends: `x.md.bak` is
    // not a markdown path and `x.md.` at the end of a sentence is, and only
    // the whole run tells those apart.
    while start < bytes.len() {
        if !is_path_byte(bytes[start]) {
            start += 1;
            continue;
        }
        let mut end = start;
        while end < bytes.len() && is_path_byte(bytes[end]) {
            end += 1;
        }
        let run_end = end;

        // Trailing separators belong to the sentence, not the path.
        while end > start && matches!(bytes[end - 1], b'.' | b'/' | b':' | b'-') {
            end -= 1;
        }

        let text = &source[start..end];
        let is_reference = text.ends_with(MARKDOWN_SUFFIX)
            && text.contains('/')
            && !code_ranges.iter().any(|r| r.start <= start && end <= r.end);
        if is_reference {
            let idx = line_index_of(start);
            let line_start = line_starts[idx];
            spans.push(RefSpan {
                line: body_start_line + idx,
                range: (start - line_start)..(end - line_start),
                text: text.to_string(),
            });
        }

        start = run_end;
    }

    spans
}

/// The suffix every reference this module reports ends in.
const MARKDOWN_SUFFIX: &str = ".md";

/// Bytes that continue a path token.
///
/// `:` is included so a cross-repo `owner/repo:docs/…` reference and a URL
/// come back as one token each rather than as their tails. Both are dropped
/// downstream, and dropping a whole token is a decision a caller can make;
/// dropping the front of one silently is not.
///
/// Non-ASCII bytes are excluded, which is also what keeps every run boundary
/// on a character boundary: a multi-byte character ends a run rather than
/// being walked into.
fn is_path_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || matches!(b, b'.' | b'/' | b'-' | b'_' | b':')
}

/// Word count over prose spans. The denominator a frequency rule divides by.
pub fn prose_word_count(spans: &[ProseSpan]) -> usize {
    spans
        .iter()
        .map(|s| s.text.split_whitespace().count())
        .sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(s: &str) -> Vec<String> {
        s.lines().map(|l| l.to_string()).collect()
    }

    fn joined(spans: &[ProseSpan]) -> String {
        spans
            .iter()
            .map(|s| s.text.as_str())
            .collect::<Vec<_>>()
            .join(" ")
    }

    fn lines_containing(spans: &[ProseSpan], needle: &str) -> Vec<usize> {
        spans
            .iter()
            .filter(|s| s.text.contains(needle))
            .map(|s| s.line)
            .collect()
    }

    #[test]
    fn fenced_code_is_not_prose() {
        let body = lines("before tier\n```\ntier inside\n```\nafter tier");
        let spans = prose_spans(&body, 1);
        assert_eq!(lines_containing(&spans, "tier inside"), Vec::<usize>::new());
        assert_eq!(lines_containing(&spans, "before tier"), vec![1]);
        assert_eq!(lines_containing(&spans, "after tier"), vec![5]);
    }

    /// Regression: a fenced block whose first content line is a fence marker.
    ///
    /// CommonMark 4.5 forbids an info string on a closing fence, so the
    /// inner ```yaml is content, not a close. The hand-rolled scoper treated
    /// it as a close and inverted the block: code became prose and the real
    /// prose after it became code.
    #[test]
    fn inner_fence_marker_does_not_close_the_block() {
        let body = lines(
            "# Doc\n\nExample:\n\n```\n```yaml\nrobust: tier\n```\n\nReal prose about facilitate.",
        );
        let spans = prose_spans(&body, 1);
        let text = joined(&spans);

        assert!(
            !text.contains("robust"),
            "line 7 is inside the code block; got: {text}"
        );
        assert!(
            text.contains("facilitate"),
            "line 10 is real prose and must be checked; got: {text}"
        );
        assert_eq!(lines_containing(&spans, "facilitate"), vec![10]);
    }

    /// Regression: a leading `---` thematic break is not frontmatter.
    ///
    /// The hand-rolled path consumed everything up to the next `---`, so a
    /// paragraph between two thematic breaks was never checked while the
    /// file reported success.
    #[test]
    fn leading_thematic_break_does_not_swallow_content() {
        let body = lines(concat!(
            "---\n\n",
            "This paragraph contains tier and robust words.\n\n",
            "---\n\n",
            "And this one contains facilitate.",
        ));
        let spans = prose_spans(&body, 1);
        let text = joined(&spans);

        assert!(
            text.contains("robust"),
            "content after a thematic break must be checked; got: {text}"
        );
        assert!(text.contains("facilitate"), "got: {text}");
        assert_eq!(lines_containing(&spans, "tier and robust"), vec![3]);
    }

    #[test]
    fn tilde_fence_and_longer_close_marker() {
        let body = lines("~~~\ntier\n~~~~\nafter tier");
        let spans = prose_spans(&body, 1);
        assert!(!joined(&spans).contains("tier\n"));
        assert_eq!(lines_containing(&spans, "after tier"), vec![4]);
    }

    #[test]
    fn unterminated_fence_does_not_panic() {
        let body = lines("intro tier\n```\ntier forever\nstill inside");
        let spans = prose_spans(&body, 1);
        assert_eq!(lines_containing(&spans, "intro tier"), vec![1]);
    }

    #[test]
    fn inline_code_is_not_prose_but_surrounding_text_is() {
        let body = lines("use `tier` here but robust stays");
        let spans = prose_spans(&body, 1);
        let text = joined(&spans);
        assert!(!text.contains("tier"), "got: {text}");
        assert!(text.contains("robust"), "got: {text}");
    }

    #[test]
    fn urls_are_not_prose() {
        let body = lines("see <https://example.com/tier-guide> for robust detail");
        let spans = prose_spans(&body, 1);
        let text = joined(&spans);
        assert!(!text.contains("tier"), "got: {text}");
        assert!(text.contains("robust"), "got: {text}");
    }

    #[test]
    fn link_destination_is_not_prose_but_label_is() {
        let body = lines("[robust label](https://example.com/tier)");
        let spans = prose_spans(&body, 1);
        let text = joined(&spans);
        assert!(text.contains("robust"), "label is prose; got: {text}");
        assert!(
            !text.contains("tier"),
            "destination is not prose; got: {text}"
        );
    }

    #[test]
    fn table_cells_are_not_prose() {
        let body = lines("| tier | robust |\n|---|---|\n| a | b |\n\nafter tier");
        let spans = prose_spans(&body, 1);
        let text = joined(&spans);
        assert!(
            !text.contains("robust"),
            "table cells are data; got: {text}"
        );
        assert_eq!(lines_containing(&spans, "after tier"), vec![5]);
    }

    #[test]
    fn headings_are_prose() {
        let body = lines("## A tier heading\n\nbody");
        let spans = prose_spans(&body, 1);
        assert!(
            joined(&spans).contains("tier"),
            "headings are prose by decision; the frequency denominator depends on it"
        );
    }

    #[test]
    fn html_comments_are_not_prose() {
        let body = lines("text robust\n\n<!-- tier hidden -->\n");
        let spans = prose_spans(&body, 1);
        let text = joined(&spans);
        assert!(!text.contains("tier"), "got: {text}");
        assert!(text.contains("robust"), "got: {text}");
    }

    #[test]
    fn indented_code_is_not_prose() {
        let body = lines("paragraph robust\n\n    tier indented\n\nafter");
        let spans = prose_spans(&body, 1);
        assert!(!joined(&spans).contains("tier"));
    }

    #[test]
    fn spans_carry_file_lines_not_body_relative_ones() {
        let body = lines("first\n\nsecond");
        let spans = prose_spans(&body, 25);
        assert_eq!(spans[0].line, 25);
    }

    #[test]
    fn crlf_does_not_break_fence_matching() {
        let body: Vec<String> = vec![
            "```\r".into(),
            "tier\r".into(),
            "```\r".into(),
            "\r".into(),
            "after tier\r".into(),
        ];
        let spans = prose_spans(&body, 1);
        assert!(
            joined(&spans).contains("after tier"),
            "a CRLF document must close its fence"
        );
    }

    #[test]
    fn word_count_excludes_non_prose() {
        let body = lines("one two three\n\n```\nfour five six seven\n```\n\n| a | b |\n|---|---|");
        let spans = prose_spans(&body, 1);
        assert_eq!(prose_word_count(&spans), 3);
    }

    // ---- reference_spans ------------------------------------------------

    fn ref_texts(spans: &[RefSpan]) -> Vec<&str> {
        spans.iter().map(|s| s.text.as_str()).collect()
    }

    #[test]
    fn a_path_in_an_inline_code_span_is_a_reference() {
        let body = lines("See `docs/designs/DESIGN-a.md` for the rest.");
        let spans = reference_spans(&body, 1);
        assert_eq!(ref_texts(&spans), vec!["docs/designs/DESIGN-a.md"]);
        assert_eq!(spans[0].line, 1);
    }

    #[test]
    fn a_link_destination_is_a_reference() {
        let body = lines("[the design](docs/designs/DESIGN-a.md) says so.");
        let spans = reference_spans(&body, 1);
        assert_eq!(ref_texts(&spans), vec!["docs/designs/DESIGN-a.md"]);
    }

    #[test]
    fn a_path_in_plain_text_is_a_reference() {
        let body = lines("The file docs/prds/PRD-a.md carries the requirements.");
        let spans = reference_spans(&body, 1);
        assert_eq!(ref_texts(&spans), vec!["docs/prds/PRD-a.md"]);
    }

    #[test]
    fn a_path_in_a_fenced_code_block_is_not_a_reference() {
        let body = lines(
            "intro\n\n```\ndocs/designs/DESIGN-fenced.md\n```\n\ndocs/designs/DESIGN-after.md",
        );
        let spans = reference_spans(&body, 1);
        assert_eq!(ref_texts(&spans), vec!["docs/designs/DESIGN-after.md"]);
    }

    /// The regression `prose_spans` carries, asserted for the second
    /// selection: CommonMark 4.5 forbids an info string on a closing fence,
    /// so the inner ```yaml is content and the block runs to the third
    /// marker. A hand-rolled scoper inverts this and leaks the block.
    #[test]
    fn an_inner_fence_marker_does_not_open_a_reference_window() {
        let body = lines(
            "```\n```yaml\nupstream: docs/designs/DESIGN-inside.md\n```\n\nSee `docs/designs/DESIGN-outside.md`.",
        );
        let spans = reference_spans(&body, 1);
        assert_eq!(ref_texts(&spans), vec!["docs/designs/DESIGN-outside.md"]);
    }

    #[test]
    fn a_path_in_an_indented_code_block_is_not_a_reference() {
        let body = lines("paragraph\n\n    docs/designs/DESIGN-indented.md\n\nafter");
        let spans = reference_spans(&body, 1);
        assert!(spans.is_empty(), "got: {:?}", ref_texts(&spans));
    }

    #[test]
    fn reference_lines_are_file_lines_on_a_document_with_frontmatter() {
        // A 12-line frontmatter puts `body[0]` on file line 13.
        let body = lines("# Doc\n\nSee `docs/plans/PLAN-a.md`.");
        let spans = reference_spans(&body, 13);
        assert_eq!(spans.len(), 1);
        assert_eq!(spans[0].line, 15);
    }

    #[test]
    fn byte_ranges_are_correct_on_a_line_naming_two_paths() {
        let line = "Both `docs/prds/PRD-a.md` and `docs/designs/DESIGN-b.md` moved.";
        let body = lines(line);
        let spans = reference_spans(&body, 1);
        assert_eq!(spans.len(), 2, "got: {:?}", ref_texts(&spans));
        for span in &spans {
            assert_eq!(
                &line[span.range.clone()],
                span.text,
                "range {:?} must slice back to the span text",
                span.range
            );
        }
        // The ranges are distinct and ordered, which is what a right-to-left
        // rewrite depends on.
        assert!(spans[0].range.end <= spans[1].range.start);
    }

    #[test]
    fn a_bare_basename_is_not_a_reference() {
        let body = lines("See DESIGN-a.md and `PRD-b.md`.");
        let spans = reference_spans(&body, 1);
        assert!(spans.is_empty(), "got: {:?}", ref_texts(&spans));
    }

    #[test]
    fn the_md_suffix_has_to_end_the_token() {
        let body = lines("docs/x/thing.mdx and docs/y/thing.md5 are not markdown");
        let spans = reference_spans(&body, 1);
        assert!(spans.is_empty(), "got: {:?}", ref_texts(&spans));
    }

    #[test]
    fn trailing_punctuation_is_not_part_of_the_path() {
        let body = lines("(docs/designs/DESIGN-a.md), docs/prds/PRD-b.md.");
        let spans = reference_spans(&body, 1);
        assert_eq!(
            ref_texts(&spans),
            vec!["docs/designs/DESIGN-a.md", "docs/prds/PRD-b.md"]
        );
    }

    #[test]
    fn a_cross_repo_reference_comes_back_whole() {
        // The caller drops it; the extractor must not hand back its tail,
        // which would read as a local path nobody wrote.
        let body = lines("See `owner/repo:docs/designs/DESIGN-a.md`.");
        let spans = reference_spans(&body, 1);
        assert_eq!(
            ref_texts(&spans),
            vec!["owner/repo:docs/designs/DESIGN-a.md"]
        );
    }

    #[test]
    fn a_url_comes_back_whole() {
        let body = lines("See https://example.com/docs/designs/DESIGN-a.md for detail.");
        let spans = reference_spans(&body, 1);
        assert_eq!(
            ref_texts(&spans),
            vec!["https://example.com/docs/designs/DESIGN-a.md"]
        );
    }

    #[test]
    fn a_relative_reference_keeps_its_written_form() {
        let body = lines("See `../prds/PRD-a.md` and `./PLAN-b.md`.");
        let spans = reference_spans(&body, 1);
        assert_eq!(ref_texts(&spans), vec!["../prds/PRD-a.md", "./PLAN-b.md"]);
    }

    #[test]
    fn table_cells_carry_references() {
        // The mirror of `table_cells_are_not_prose`: a table cell is data
        // for a writing-style rule and a reference for this one.
        let body = lines("| doc | path |\n|---|---|\n| A | `docs/designs/DESIGN-a.md` |");
        let spans = reference_spans(&body, 1);
        assert_eq!(ref_texts(&spans), vec!["docs/designs/DESIGN-a.md"]);
        assert_eq!(spans[0].line, 3);
    }

    #[test]
    fn crlf_ranges_are_relative_to_the_original_line() {
        let line = "See `docs/designs/DESIGN-a.md` here.";
        let body: Vec<String> = vec![format!("{line}\r")];
        let spans = reference_spans(&body, 1);
        assert_eq!(spans.len(), 1);
        assert_eq!(&line[spans[0].range.clone()], spans[0].text);
    }

    #[test]
    fn non_ascii_before_a_path_does_not_split_a_character() {
        let line = "Se \u{00e9}docs/designs/DESIGN-a.md hier";
        let body = lines(line);
        let spans = reference_spans(&body, 1);
        assert_eq!(ref_texts(&spans), vec!["docs/designs/DESIGN-a.md"]);
        assert_eq!(&line[spans[0].range.clone()], spans[0].text);
    }

    #[test]
    fn reference_spans_total_over_arbitrary_input() {
        let probes: Vec<Vec<String>> = vec![
            vec![],
            vec![String::new()],
            vec![".md".to_string()],
            vec!["/.md".to_string()],
            vec!["`".repeat(1000)],
            vec!["a/".repeat(10_000) + ".md"],
            vec!["\u{fffd}/x.md".to_string()],
            vec!["```".into(), "a/b.md".into()],
            vec!["    a/b.md".to_string()],
            vec!["|a/b.md|".to_string()],
        ];
        for p in probes {
            let spans = reference_spans(&p, 1);
            for span in &spans {
                let line = &p[span.line - 1];
                let line = line.strip_suffix('\r').unwrap_or(line);
                assert_eq!(&line[span.range.clone()], span.text);
            }
        }
    }

    #[test]
    fn total_over_arbitrary_input() {
        let probes: Vec<Vec<String>> = vec![
            vec![],
            vec![String::new()],
            vec!["`".repeat(1000)],
            vec!["~".repeat(5)],
            vec!["    ".to_string()],
            vec!["|".to_string()],
            vec!["<!--".to_string()],
            vec!["[a](".to_string()],
            vec!["https://".to_string()],
            vec!["x".repeat(1_000_000)],
            vec!["\u{fffd}\u{0}\u{1}".to_string()],
            vec!["```".into(), "\r".into(), "\t".into()],
            vec!["---".into(), "a: b".into(), "---".into()],
        ];
        for p in probes {
            let spans = prose_spans(&p, 1);
            let _ = prose_word_count(&spans);
        }
    }
}
