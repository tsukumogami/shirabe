//! Markdown-aware prose scoping.
//!
//! A prose rule that matches raw body lines fires inside fenced code, URLs,
//! and table rows. The shipped writing-style check does exactly that, and
//! not because its scoping was attempted and failed: it iterates raw lines
//! and attempts no scoping at all. This module is the scoping.
//!
//! ## What counts as prose
//!
//! Excluded: fenced code blocks, indented code blocks, inline code spans,
//! URLs (bare and inside link targets), table rows, and HTML comments.
//! Included: headings, list item text, blockquote text, paragraph text,
//! and link *labels* (the words a reader reads).
//!
//! Headings are prose by decision, not by omission. The design records it
//! because it moves the corpus figure: 3,114 em dashes counting headings
//! against 2,785 counting body paragraphs alone, and a frequency rule whose
//! denominator nobody wrote down is not reproducible.
//!
//! ## Totality
//!
//! Every function here is total over arbitrary input. Unterminated fences,
//! a fence opened inside frontmatter, a single ten-megabyte line, CRLF, and
//! non-UTF8 bytes all produce output rather than a panic. The convention
//! follows `check_fc08_extract_legend_total_over_arbitrary_input`.

/// A run of prose text with the file line it starts on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProseSpan {
    /// 1-indexed file line.
    pub line: usize,
    /// The prose text of that line, with non-prose regions blanked out.
    ///
    /// Blanked rather than removed so a column offset within the line stays
    /// meaningful and the caller can still reason about position.
    pub text: String,
}

/// Prose spans for a document body.
///
/// `body` is the post-frontmatter lines; `body_start_line` is the 1-indexed
/// file line `body[0]` sits on, so returned spans carry file lines rather
/// than body-relative ones.
pub fn prose_spans(body: &[String], body_start_line: usize) -> Vec<ProseSpan> {
    let mut out = Vec::with_capacity(body.len());
    let mut in_fence = false;
    let mut fence_marker: Option<String> = None;

    for (idx, raw) in body.iter().enumerate() {
        // Normalize line endings once, at entry. `split_lines` retains the
        // carriage return on every line of a CRLF document, which breaks
        // fence close-matching (the marker never compares equal) and
        // silently collapses a per-paragraph denominator to the document.
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        let file_line = body_start_line.saturating_add(idx);

        if let Some(marker) = fence_delimiter(line) {
            match (&fence_marker, in_fence) {
                // Closing marker must be at least as long as the opener and
                // use the same character, per CommonMark.
                (Some(open), true) if closes_fence(open, &marker) => {
                    in_fence = false;
                    fence_marker = None;
                }
                (_, false) => {
                    in_fence = true;
                    fence_marker = Some(marker);
                }
                _ => {}
            }
            // The delimiter line itself is never prose.
            out.push(ProseSpan {
                line: file_line,
                text: String::new(),
            });
            continue;
        }

        if in_fence || is_indented_code(line) || is_table_row(line) {
            out.push(ProseSpan {
                line: file_line,
                text: String::new(),
            });
            continue;
        }

        out.push(ProseSpan {
            line: file_line,
            text: blank_inline_non_prose(line),
        });
    }

    out
}

/// Word count over prose spans. The denominator a frequency rule divides by.
pub fn prose_word_count(spans: &[ProseSpan]) -> usize {
    spans
        .iter()
        .map(|s| s.text.split_whitespace().count())
        .sum()
}

/// The fence marker a line opens or closes with, if it is a fence line.
fn fence_delimiter(line: &str) -> Option<String> {
    let trimmed = line.trim_start();
    // More than three leading spaces makes it indented code, not a fence.
    if line.len() - trimmed.len() > 3 {
        return None;
    }
    let first = trimmed.chars().next()?;
    if first != '`' && first != '~' {
        return None;
    }
    let run: String = trimmed.chars().take_while(|c| *c == first).collect();
    if run.chars().count() < 3 {
        return None;
    }
    // A backtick fence's info string may not contain a backtick.
    if first == '`' && trimmed[run.len()..].contains('`') {
        return None;
    }
    Some(run)
}

/// Whether `marker` closes a fence opened by `open`.
fn closes_fence(open: &str, marker: &str) -> bool {
    open.chars().next() == marker.chars().next() && marker.len() >= open.len()
}

fn is_indented_code(line: &str) -> bool {
    // Four spaces or a tab, and not blank.
    if line.trim().is_empty() {
        return false;
    }
    line.starts_with("    ") || line.starts_with('\t')
}

fn is_table_row(line: &str) -> bool {
    let t = line.trim();
    // A row starts with a pipe and contains another one. Delimiter rows
    // (`|---|`) satisfy this too, which is intended: both are table
    // structure, and a banned word in a table cell is data, not prose.
    t.starts_with('|') && t[1..].contains('|')
}

/// Blank the non-prose regions inside a single line.
///
/// Replaced with spaces rather than removed so that column positions stay
/// aligned with the source line.
fn blank_inline_non_prose(line: &str) -> String {
    let mut out: Vec<char> = line.chars().collect();
    blank_code_spans(&mut out);
    blank_html_comments(&mut out);
    blank_link_targets(&mut out);
    blank_bare_urls(&mut out);
    out.into_iter().collect()
}

fn blank_range(buf: &mut [char], start: usize, end: usize) {
    let hi = end.min(buf.len());
    for c in buf.iter_mut().take(hi).skip(start) {
        *c = ' ';
    }
}

/// Blank backtick code spans, honoring multi-backtick delimiters.
fn blank_code_spans(buf: &mut Vec<char>) {
    let n = buf.len();
    let mut i = 0;
    while i < n {
        if buf[i] != '`' {
            i += 1;
            continue;
        }
        let open_start = i;
        let mut run = 0;
        while i < n && buf[i] == '`' {
            run += 1;
            i += 1;
        }
        // Find a closing run of exactly the same length.
        let mut j = i;
        let mut closed = None;
        while j < n {
            if buf[j] == '`' {
                let cstart = j;
                let mut crun = 0;
                while j < n && buf[j] == '`' {
                    crun += 1;
                    j += 1;
                }
                if crun == run {
                    closed = Some((cstart, j));
                    break;
                }
            } else {
                j += 1;
            }
        }
        match closed {
            Some((_, cend)) => {
                blank_range(buf, open_start, cend);
                i = cend;
            }
            // Unclosed span: leave the rest as prose rather than swallowing
            // the line. An unmatched backtick is far more likely a typo
            // than an intent to suppress checking.
            None => break,
        }
    }
}

fn blank_html_comments(buf: &mut Vec<char>) {
    let s: String = buf.iter().collect();
    let mut from = 0;
    while let Some(rel) = s[from..].find("<!--") {
        let start = from + rel;
        let end = match s[start..].find("-->") {
            Some(e) => start + e + 3,
            None => s.len(),
        };
        let cs = s[..start].chars().count();
        let ce = s[..end.min(s.len())].chars().count();
        blank_range(buf, cs, ce);
        if end <= from {
            break;
        }
        from = end;
        if from >= s.len() {
            break;
        }
    }
}

/// Blank the target of `[label](target)` and leave the label as prose.
fn blank_link_targets(buf: &mut Vec<char>) {
    let n = buf.len();
    let mut i = 0;
    while i < n {
        if buf[i] == ']' && i + 1 < n && buf[i + 1] == '(' {
            let start = i + 1;
            let mut depth = 0;
            let mut j = start;
            while j < n {
                if buf[j] == '(' {
                    depth += 1;
                } else if buf[j] == ')' {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                j += 1;
            }
            let end = (j + 1).min(n);
            blank_range(buf, start, end);
            i = end;
            continue;
        }
        i += 1;
    }
}

fn blank_bare_urls(buf: &mut Vec<char>) {
    let s: String = buf.iter().collect();
    for scheme in ["https://", "http://"] {
        let mut from = 0;
        while let Some(rel) = s[from..].find(scheme) {
            let start = from + rel;
            let rest = &s[start..];
            let len = rest
                .find(|c: char| c.is_whitespace() || c == ')' || c == '>')
                .unwrap_or(rest.len());
            let cs = s[..start].chars().count();
            let ce = s[..start + len].chars().count();
            blank_range(buf, cs, ce);
            from = start + len;
            if from >= s.len() {
                break;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(s: &str) -> Vec<String> {
        s.lines().map(|l| l.to_string()).collect()
    }

    fn text_at(spans: &[ProseSpan], file_line: usize) -> String {
        spans
            .iter()
            .find(|s| s.line == file_line)
            .map(|s| s.text.clone())
            .unwrap_or_default()
    }

    #[test]
    fn fenced_code_is_not_prose() {
        let body = lines("before tier\n```\ntier inside\n```\nafter tier");
        let spans = prose_spans(&body, 1);
        assert!(text_at(&spans, 1).contains("tier"));
        assert_eq!(text_at(&spans, 3).trim(), "");
        assert!(text_at(&spans, 5).contains("tier"));
    }

    #[test]
    fn tilde_fence_and_longer_close_marker() {
        let body = lines("~~~\ntier\n~~~~\nafter tier");
        let spans = prose_spans(&body, 1);
        assert_eq!(text_at(&spans, 2).trim(), "");
        assert!(text_at(&spans, 4).contains("tier"));
    }

    #[test]
    fn unterminated_fence_swallows_the_rest_without_panicking() {
        let body = lines("intro tier\n```\ntier forever\nstill inside");
        let spans = prose_spans(&body, 1);
        assert!(text_at(&spans, 1).contains("tier"));
        assert_eq!(text_at(&spans, 3).trim(), "");
        assert_eq!(text_at(&spans, 4).trim(), "");
    }

    #[test]
    fn inline_code_is_not_prose_but_surrounding_text_is() {
        let body = lines("use `tier` here but robust stays");
        let spans = prose_spans(&body, 1);
        let t = text_at(&spans, 1);
        assert!(!t.contains("tier"), "got: {t}");
        assert!(t.contains("robust"), "got: {t}");
    }

    #[test]
    fn urls_are_not_prose() {
        let body = lines("see https://example.com/tier-guide for robust detail");
        let spans = prose_spans(&body, 1);
        let t = text_at(&spans, 1);
        assert!(!t.contains("tier"), "got: {t}");
        assert!(t.contains("robust"), "got: {t}");
    }

    #[test]
    fn link_target_is_not_prose_but_label_is() {
        let body = lines("[robust label](https://example.com/tier)");
        let spans = prose_spans(&body, 1);
        let t = text_at(&spans, 1);
        assert!(t.contains("robust"), "label is prose; got: {t}");
        assert!(!t.contains("tier"), "target is not prose; got: {t}");
    }

    #[test]
    fn table_rows_are_not_prose() {
        let body = lines("| tier | robust |\n|---|---|\n| a | b |\nafter tier");
        let spans = prose_spans(&body, 1);
        assert_eq!(text_at(&spans, 1).trim(), "");
        assert_eq!(text_at(&spans, 2).trim(), "");
        assert!(text_at(&spans, 4).contains("tier"));
    }

    #[test]
    fn headings_are_prose() {
        let body = lines("## A tier heading\n\nbody");
        let spans = prose_spans(&body, 1);
        assert!(
            text_at(&spans, 1).contains("tier"),
            "headings are prose by decision; the frequency denominator depends on it"
        );
    }

    #[test]
    fn html_comments_are_not_prose() {
        let body = lines("text <!-- tier hidden --> robust");
        let spans = prose_spans(&body, 1);
        let t = text_at(&spans, 1);
        assert!(!t.contains("tier"), "got: {t}");
        assert!(t.contains("robust"), "got: {t}");
    }

    #[test]
    fn spans_carry_file_lines_not_body_relative_ones() {
        let body = lines("first\nsecond");
        let spans = prose_spans(&body, 25);
        assert_eq!(spans[0].line, 25);
        assert_eq!(spans[1].line, 26);
    }

    #[test]
    fn crlf_does_not_break_fence_matching() {
        let body: Vec<String> = vec![
            "```\r".into(),
            "tier\r".into(),
            "```\r".into(),
            "after tier\r".into(),
        ];
        let spans = prose_spans(&body, 1);
        assert_eq!(text_at(&spans, 2).trim(), "");
        assert!(
            text_at(&spans, 4).contains("tier"),
            "a CRLF document must close its fence"
        );
    }

    #[test]
    fn word_count_excludes_non_prose() {
        let body = lines("one two three\n```\nfour five six seven\n```\n| a | b |");
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
        ];
        for p in probes {
            let spans = prose_spans(&p, 1);
            let _ = prose_word_count(&spans);
        }
    }
}
