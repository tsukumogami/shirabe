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
